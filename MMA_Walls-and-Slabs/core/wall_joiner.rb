# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Joiner
# Joins two open path walls at one end each. The two centre lines are trimmed
# or extended to meet, and every layer is mitred at the corner (see
# WallBuilder.joint_corners). Links are stored on both walls and only trusted
# when both sides agree.
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'joint_geometry'
require_relative 'wall_object'
require_relative 'wall_builder'

module MMA_WallsAndSlabs
  module JoinType
    NONE = 'none'
    MITER = 'miter'
    CONTINUATION = 'continuation'
  end

  class WallJoiner
    MAX_JOINT_DISTANCE_MM = 3000.0   # max trim/extension of a wall to reach the joint
    MIN_SEGMENT_MM = 1.0             # a wall may not be trimmed shorter than this
    COLLINEAR_TOLERANCE_MM = 5.0     # end-to-end walls must sit on one line within this
    PARALLEL_DETERMINANT = 1e-3      # |det| below this = parallel centre lines
    ENDS = [:start, :end].freeze

    # Used by JoinWallTool: returns JoinType::MITER, CONTINUATION or NONE.
    def self.detect_wall_join(_model, wall1_group, wall2_group)
      candidate = best_candidate(wall1_group, wall2_group)
      candidate ? candidate[:type] : JoinType::NONE
    end

    # Used by JoinWallTool: joins the two closest ends. Returns true on success.
    def self.apply_join(model, wall1_group, wall2_group, join_type = nil)
      candidate = best_candidate(wall1_group, wall2_group)
      return false unless candidate
      return false if join_type == JoinType::NONE

      join_ends(model, wall1_group, candidate[:end1], wall2_group, candidate[:end2])
    end

    # Re-solves every stored joint of a wall (e.g. after it was edited).
    # Joints that no longer hold are removed from both walls.
    def self.refresh_adjacent_joins(model, wall_group, _unused = nil)
      return false unless model && WallModel.valid_wall_group?(wall_group)

      wall = WallModel.from_group(wall_group)
      return false unless wall

      joints = wall.params['joints']
      return true unless joints.is_a?(Hash)

      joints.keys.each do |end_key|
        joint = joints[end_key]
        next unless joint.is_a?(Hash)

        other = WallBuilder.find_wall_group(model, joint['uid'].to_i)
        other_end = joint['other_end'].to_s
        linked = other && other != wall_group && ENDS.map(&:to_s).include?(other_end) &&
                 mutual?(wall_group, end_key, other, other_end) &&
                 join_ends(model, wall_group, end_key.to_sym, other, other_end.to_sym)
        next if linked

        partner_points_back = other && mutual?(wall_group, end_key, other, other_end)
        unlink(wall_group, end_key)
        unlink(other, other_end) if partner_points_back
      end
      true
    end

    def self.best_candidate(group1, group2)
      return nil unless group1 && group2 && group1 != group2 && group1.valid? && group2.valid?

      wall1 = WallModel.from_group(group1)
      wall2 = WallModel.from_group(group2)
      return nil unless usable?(wall1) && usable?(wall2)

      candidates = ENDS.product(ENDS).map { |end1, end2| candidate_for(wall1, end1, wall2, end2) }.compact
      candidates.min_by { |candidate| candidate[:gap] }
    end

    def self.usable?(wall)
      !wall.nil? && !wall.path_points.nil? && wall.path_points.length >= 2 && !wall.path_closed?
    end

    # Works out where two ends meet. Returns nil if they cannot be joined.
    def self.candidate_for(wall1, end1, wall2, end2)
      p1 = end_point(wall1, end1)
      p2 = end_point(wall2, end2)
      d1 = outward_direction(wall1, end1)
      d2 = outward_direction(wall2, end2)
      return nil unless p1 && p2 && d1 && d2

      determinant = (-d1[0] * d2[1]) + (d2[0] * d1[1])
      if determinant.abs < PARALLEL_DETERMINANT
        # Parallel: only end-to-end continuation on one line is supported.
        return nil unless (d1[0] * d2[0]) + (d1[1] * d2[1]) < -0.999
        return nil if distance_to_line(p2, p1, d1) > COLLINEAR_TOLERANCE_MM

        point = [(p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0, p1[2]]
        type = JoinType::CONTINUATION
      else
        # Solve p1 + t*d1 = p2 + s*d2 for t (Cramer's rule).
        rx = p2[0] - p1[0]
        ry = p2[1] - p1[1]
        t = ((-rx * d2[1]) + (d2[0] * ry)) / determinant
        point = [p1[0] + (t * d1[0]), p1[1] + (t * d1[1]), p1[2]]
        type = JoinType::MITER
      end

      return nil unless valid_end?(wall1, end1, point) && valid_end?(wall2, end2, point)

      { end1: end1, end2: end2, point: point, type: type, gap: JointGeometry.distance(p1, p2) }
    end

    # The joint point must be reachable and must leave the wall at least
    # MIN_SEGMENT_MM long along its end segment.
    def self.valid_end?(wall, which, point)
      return false if JointGeometry.distance(point, end_point(wall, which)) > MAX_JOINT_DISTANCE_MM

      direction = outward_direction(wall, which)
      interior = which == :start ? wall.path_points[1] : wall.path_points[-2]
      along = ((point[0] - interior[0]) * direction[0]) + ((point[1] - interior[1]) * direction[1])
      along > MIN_SEGMENT_MM
    end

    def self.join_ends(model, group1, end1, group2, end2)
      wall1 = WallModel.from_group(group1)
      wall2 = WallModel.from_group(group2)
      return false unless usable?(wall1) && usable?(wall2)

      candidate = candidate_for(wall1, end1, wall2, end2)
      return false unless candidate

      point = candidate[:point]
      set_end(wall1, end1, point)
      set_end(wall2, end2, point)
      link(wall1, end1, group2, end2)
      link(wall2, end2, group1, end1)
      wall1.save_to_group(group1)
      wall2.save_to_group(group2)
      # Save both first, so each rebuild can read the neighbour's new end.
      WallBuilder.rebuild_wall_from_model(model, group1, wall1)
      WallBuilder.rebuild_wall_from_model(model, group2, wall2)
      true
    end

    # A link is trusted only when the other wall points back at this end.
    def self.mutual?(group1, end1, group2, end2)
      other = WallModel.from_group(group2)
      joint = other && other.params['joints'].is_a?(Hash) ? other.params['joints'][end2.to_s] : nil
      joint.is_a?(Hash) && joint['uid'].to_i == group1.persistent_id && joint['other_end'].to_s == end1.to_s
    end

    def self.link(wall, end_key, other_group, other_end)
      joints = wall.params['joints'].is_a?(Hash) ? wall.params['joints'] : {}
      joints[end_key.to_s] = { 'uid' => other_group.persistent_id, 'other_end' => other_end.to_s }
      wall.params['joints'] = joints
    end

    def self.unlink(group, end_key)
      return unless group && group.valid?

      wall = WallModel.from_group(group)
      return unless wall && wall.params['joints'].is_a?(Hash) && wall.params['joints'].key?(end_key.to_s)

      wall.params['joints'].delete(end_key.to_s)
      wall.params.delete('joints') if wall.params['joints'].empty?
      wall.save_to_group(group)
    end

    def self.set_end(wall, which, point)
      which == :start ? wall.set_start_point(point) : wall.set_end_point(point)
    end

    def self.end_point(wall, which)
      which == :start ? wall.path_points.first : wall.path_points.last
    end

    # Points away from the wall body, through the given end.
    def self.outward_direction(wall, which)
      path = wall.path_points
      which == :start ? JointGeometry.unit(path[1], path[0]) : JointGeometry.unit(path[-2], path[-1])
    end

    def self.distance_to_line(point, origin, direction)
      ((point[0] - origin[0]) * direction[1] - (point[1] - origin[1]) * direction[0]).abs
    end
  end
end
