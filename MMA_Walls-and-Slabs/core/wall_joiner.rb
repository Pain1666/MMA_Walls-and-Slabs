# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Joiner
#
# Modes (first pick = the wall that stays, second pick = the wall that changes):
#   corner  - both wall ends meet at the corner. Core meets core.
#   trim    - the second wall is shortened back to the first wall's centre line.
#             It must overshoot the first wall.
#   extend  - the second wall is lengthened up to the first wall's centre line.
#             It must stop short of the first wall.
#   chamfer - both corner ends are pulled back along their centre lines and cut
#             by one line through the two points.
#
# Links are stored in each wall's params['joints'] as
#   { 'uid', 'other_end', 'kind' => 'corner' | 'chamfer' | 't', ... }.
# Corner and chamfer links are only trusted when both walls point back at each other.
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
    MODES = %w[corner trim extend chamfer].freeze
    MAX_JOINT_DISTANCE_MM = 10000.0  # max trim or extension of a wall to reach the joint (10 m)
    MIN_SEGMENT_MM = 1.0             # a wall may not be shortened below this
    COLLINEAR_TOLERANCE_MM = 5.0     # end-to-end walls must sit on one line within this
    PARALLEL_DETERMINANT = 1e-3      # |det| below this = parallel centre lines
    TEE_MARGIN_MM = 1.0              # a T must land this far inside the through wall
    ENDS = [:start, :end].freeze

    # Returns [success, message].
    def self.join(model, first_group, second_group, mode, distance_mm = nil)
      unless first_group && second_group && first_group.valid? && second_group.valid? && first_group != second_group
        return [false, 'Pick two different MMA walls.']
      end

      first = WallModel.from_group(first_group)
      second = WallModel.from_group(second_group)
      unless usable?(first) && usable?(second)
        return [false, 'Joins work between open straight or polyline walls (not closed loops or curved walls).']
      end

      case mode.to_s
      when 'corner' then join_corner(model, first_group, second_group)
      when 'chamfer' then join_chamfer(model, first_group, second_group, distance_mm)
      when 'trim', 'extend' then join_tee(model, first_group, second_group, mode.to_s)
      else [false, "Unknown join mode '#{mode}'."]
      end
    end

    # ---------------------------------------------------------------- corner
    # Works out a corner join without changing the model. Returns a hash with the
    # two wall copies (ends already moved to the joint, second wall flipped if its
    # exterior needs it), or [nil, message] when no corner is possible.
    def self.corner_plan(group1, group2)
      wall1 = WallModel.from_group(group1)
      wall2 = WallModel.from_group(group2)
      unless WallBuilder.active_layer_indices(wall1.params).length == WallBuilder.active_layer_indices(wall2.params).length
        return [nil, 'A corner needs both walls to have the same number of layers, like a closed loop. Use the same wall type on both.']
      end

      candidate = candidate_between(wall1, wall2)
      return [nil, 'Corner needs an end of each wall that meets the other. For a wall ending on the middle of another, use Trim or Extend.'] unless candidate

      flipped = false
      unless exteriors_match?(wall1, candidate[:end1], wall2, candidate[:end2])
        wall2.flip_direction
        flipped = true
        candidate = candidate_between(wall1, wall2)
        return [nil, 'Could not line up the two walls for a corner.'] unless candidate &&
                                                                              exteriors_match?(wall1, candidate[:end1], wall2, candidate[:end2])
      end

      set_end(wall1, candidate[:end1], candidate[:point])
      set_end(wall2, candidate[:end2], candidate[:point])
      { wall1: wall1, wall2: wall2, end1: candidate[:end1], end2: candidate[:end2],
        point: candidate[:point], flipped: flipped }
    end

    # Both walls must have the same number of layers (like a closed loop). If their
    # exteriors face opposite ways round the corner, the second wall is flipped so
    # they match. Its existing links are dropped and must be re-joined.
    def self.join_corner(model, group1, group2)
      plan, message = corner_plan(group1, group2)
      return [false, message] unless plan

      flipped = plan[:flipped]
      if flipped
        flip_wall(model, group2)
        plan, message = corner_plan(group1, group2)
        return [false, message || 'Could not line up the two walls for a corner.'] unless plan
      end

      wall1 = WallModel.from_group(group1)
      wall2 = WallModel.from_group(group2)
      set_end(wall1, plan[:end1], plan[:point])
      set_end(wall2, plan[:end2], plan[:point])
      link(wall1, plan[:end1], group2, plan[:end2], 'corner')
      link(wall2, plan[:end2], group1, plan[:end1], 'corner')
      save_and_rebuild(model, group1, wall1, group2, wall2)
      text = flipped ? 'Walls joined at a corner. The second wall was flipped so its exterior matches the first.' :
                       'Walls joined at a corner.'
      [true, text]
    end

    # Flips a wall (same as Edit Wall + F) and removes links to it from other walls.
    def self.flip_wall(model, group)
      wall = WallModel.from_group(group)
      wall.flip_direction
      wall.save_to_group(group)
      WallBuilder.rebuild_wall_from_model(model, group, wall)
      drop_links_to(model, group)
    end

    def self.drop_links_to(model, group)
      id = WallBuilder.wall_id(group)
      model.entities.grep(Sketchup::Group).to_a.each do |other|
        next if other == group || !WallModel.valid_wall_group?(other)

        other_wall = WallModel.from_group(other)
        next unless other_wall && other_wall.params['joints'].is_a?(Hash)

        removed = other_wall.params['joints'].reject! { |_key, joint| joint.is_a?(Hash) && joint['uid'].to_s == id }
        next unless removed

        other_wall.params.delete('joints') if other_wall.params['joints'].empty?
        save_and_rebuild_one(model, other, other_wall)
      end
    end

    # True when this wall's exterior layers face the other wall's body at the joint.
    # Exterior layers always sit on the path-right side of a wall (they are first
    # in the stack), so the side depends on the drawing direction.
    def self.exterior_faces_other?(wall, which, other, other_which)
      outward = outward_direction(wall, which)
      other_outward = outward_direction(other, other_which)
      normal = JointGeometry.left_normal(outward)
      normal = [-normal[0], -normal[1]] if which == :start
      other_body = [-other_outward[0], -other_outward[1]]
      ((-normal[0]) * other_body[0]) + ((-normal[1]) * other_body[1]) > 0
    end

    # Walls with matching exteriors (both facing the corner's inside, or both facing
    # outside) join cleanly. A wall without exterior layers always matches.
    def self.exteriors_match?(wall1, end1, wall2, end2)
      return true unless exterior_layers?(wall1) && exterior_layers?(wall2)

      exterior_faces_other?(wall1, end1, wall2, end2) == exterior_faces_other?(wall2, end2, wall1, end1)
    end

    def self.exterior_layers?(wall)
      Array(wall.params['ext_layers']).any? do |layer|
        layer.is_a?(Hash) && layer['enabled'] != false && layer['thickness'].to_f > 0.001
      end
    end

    # --------------------------------------------------------------- chamfer
    def self.join_chamfer(model, group1, group2, distance_mm)
      distance = distance_mm.to_f
      return [false, 'Enter a chamfer distance greater than zero.'] unless distance.positive?

      candidate = best_candidate(group1, group2)
      unless candidate && candidate[:type] == JoinType::MITER
        return [false, 'Chamfer needs an end of each wall that meets at a corner.']
      end

      wall1 = WallModel.from_group(group1)
      wall2 = WallModel.from_group(group2)
      corner = candidate[:point]
      d1 = outward_direction(wall1, candidate[:end1])
      d2 = outward_direction(wall2, candidate[:end2])
      p1 = [corner[0] - (d1[0] * distance), corner[1] - (d1[1] * distance), corner[2]]
      p2 = [corner[0] - (d2[0] * distance), corner[1] - (d2[1] * distance), corner[2]]
      if distance >= path_length(wall1) - MIN_SEGMENT_MM || distance >= path_length(wall2) - MIN_SEGMENT_MM
        return [false, 'The chamfer distance is longer than one of the walls.']
      end

      set_end(wall1, candidate[:end1], p1)
      set_end(wall2, candidate[:end2], p2)
      cut = [p1, p2]
      link(wall1, candidate[:end1], group2, candidate[:end2], 'chamfer', 'cut' => cut)
      link(wall2, candidate[:end2], group1, candidate[:end1], 'chamfer', 'cut' => cut)
      save_and_rebuild(model, group1, wall1, group2, wall2)
      [true, "Walls chamfered by #{distance.round} mm."]
    end

    # ------------------------------------------------------------ trim / extend
    # through_group stays; stub_group (second pick) is trimmed or extended to it.
    def self.join_tee(model, through_group, stub_group, mode)
      stub = WallModel.from_group(stub_group)
      through = WallModel.from_group(through_group)
      best = nil
      ENDS.each do |end_key|
        origin = end_point(stub, end_key)
        candidate = tee_candidate(stub, end_key, through, mode, origin)
        next unless candidate

        best = candidate if best.nil? || candidate[:t].abs < best[:t].abs
      end

      unless best
        return [false, mode == 'trim' ? 'Trim needs the second wall to overshoot the first. Use Extend if it stops short.' :
                                        'Extend needs the second wall to stop short of the first. Use Trim if it overshoots.']
      end

      set_end(stub, best[:end], best[:point])
      link(stub, best[:end], through_group, 't', 't', 'mode' => mode, 'origin' => best[:origin])
      save_and_rebuild_one(model, stub_group, stub)
      [true, mode == 'trim' ? 'Second wall trimmed to the first.' : 'Second wall extended to the first.']
    end

    # Point where the stub end's line (from origin, along the stub's outward
    # direction) meets the through wall, if the change matches the mode.
    def self.tee_candidate(stub, end_key, through, mode, origin)
      direction = outward_direction(stub, end_key)
      return nil unless direction && through.path_points

      hits = tee_hits(through, origin, direction).select do |hit|
        mode == 'trim' ? hit[:t] < -MIN_SEGMENT_MM : hit[:t] > MIN_SEGMENT_MM
      end
      hit = hits.min_by { |h| h[:t].abs }
      return nil unless hit && valid_end?(stub, end_key, hit[:point])

      { end: end_key, point: hit[:point], t: hit[:t], origin: origin }
    end

    # Intersections of the ray origin + t * direction with each segment of wall.
    def self.tee_hits(wall, origin, direction)
      path = wall.path_points
      count = wall.path_closed? ? path.length : path.length - 1
      hits = []
      count.times do |index|
        a = path[index]
        b = path[(index + 1) % path.length]
        v = [b[0] - a[0], b[1] - a[1]]
        seg_length = Math.hypot(v[0], v[1])
        next if seg_length < 1e-9

        r = [a[0] - origin[0], a[1] - origin[1]]
        det = (-direction[0] * v[1]) + (v[0] * direction[1])
        next if det.abs < 1e-9

        t = ((-r[0] * v[1]) + (v[0] * r[1])) / det
        u = ((direction[0] * r[1]) - (direction[1] * r[0])) / det
        next unless (u * seg_length) > TEE_MARGIN_MM && ((1.0 - u) * seg_length) > TEE_MARGIN_MM

        hits << { t: t, point: [origin[0] + (direction[0] * t), origin[1] + (direction[1] * t), origin[2]] }
      end
      hits
    end

    # ----------------------------------------------------------- refresh
    # Re-solves the joints of a wall after it was edited, and the trim/extend
    # joints of other walls that depend on it.
    def self.refresh_adjacent_joins(model, wall_group, _unused = nil)
      return false unless model && wall_group && wall_group.valid? && WallModel.valid_wall_group?(wall_group)

      wall = WallModel.from_group(wall_group)
      return false unless wall

      own_joints(wall).each do |end_key, joint|
        other = WallBuilder.find_wall_group(model, joint['uid'].to_s)
        case WallBuilder.joint_kind(joint)
        when 'corner'
          ok = other && mutual?(wall_group, end_key, other, joint['other_end'].to_s) &&
               join_corner(model, wall_group, other)&.first
          unlink_pair(wall_group, end_key, other, joint['other_end']) unless ok
        when 'chamfer'
          unlink(wall_group, end_key) unless other && mutual?(wall_group, end_key, other, joint['other_end'].to_s)
        when 't'
          if other
            resolve_tee_end(model, wall_group, end_key, other, joint['mode'] || 'trim', joint['origin'])
          else
            unlink(wall_group, end_key)
          end
        end
      end

      model.entities.grep(Sketchup::Group).to_a.each do |stub|
        next if stub == wall_group || !WallModel.valid_wall_group?(stub)

        stub_wall = WallModel.from_group(stub)
        next unless stub_wall

        own_joints(stub_wall).each do |end_key, joint|
          next unless WallBuilder.joint_kind(joint) == 't' && joint['uid'].to_s == WallBuilder.wall_id(wall_group)

          resolve_tee_end(model, stub, end_key, wall_group, joint['mode'] || 'trim', joint['origin'])
        end
      end
      true
    end

    def self.resolve_tee_end(model, stub_group, end_key, through_group, mode, origin)
      stub = WallModel.from_group(stub_group)
      through = WallModel.from_group(through_group)
      return false unless stub && through && usable?(stub) && through.path_points

      which = end_key.to_sym
      start = origin ? origin.map(&:to_f) : end_point(stub, which)
      candidate = tee_candidate(stub, which, through, mode, start)
      unless candidate
        unlink(stub_group, which)
        return false
      end

      set_end(stub, which, candidate[:point])
      link(stub, which, through_group, 't', 't', 'mode' => mode, 'origin' => start)
      save_and_rebuild_one(model, stub_group, stub)
      true
    end

    # ----------------------------------------------------------- helpers
    def self.usable?(wall)
      !wall.nil? && !wall.path_points.nil? && wall.path_points.length >= 2 &&
        !wall.path_closed? && !wall.arc?
    end

    def self.best_candidate(group1, group2)
      return nil unless group1 && group2 && group1 != group2 && group1.valid? && group2.valid?

      candidate_between(WallModel.from_group(group1), WallModel.from_group(group2))
    end

    def self.candidate_between(wall1, wall2)
      return nil unless usable?(wall1) && usable?(wall2)

      candidates = ENDS.product(ENDS).map { |end1, end2| candidate_for(wall1, end1, wall2, end2) }.compact
      candidates.min_by { |candidate| candidate[:gap] }
    end

    # Where two ends meet. nil if they cannot be joined end to end.
    def self.candidate_for(wall1, end1, wall2, end2)
      p1 = end_point(wall1, end1)
      p2 = end_point(wall2, end2)
      d1 = outward_direction(wall1, end1)
      d2 = outward_direction(wall2, end2)
      return nil unless p1 && p2 && d1 && d2

      determinant = (-d1[0] * d2[1]) + (d2[0] * d1[1])
      if determinant.abs < PARALLEL_DETERMINANT
        return nil unless (d1[0] * d2[0]) + (d1[1] * d2[1]) < -0.999
        return nil if distance_to_line(p2, p1, d1) > COLLINEAR_TOLERANCE_MM

        point = [(p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0, p1[2]]
        type = JoinType::CONTINUATION
      else
        rx = p2[0] - p1[0]
        ry = p2[1] - p1[1]
        t = ((-rx * d2[1]) + (d2[0] * ry)) / determinant
        point = [p1[0] + (t * d1[0]), p1[1] + (t * d1[1]), p1[2]]
        type = JoinType::MITER
      end

      return nil unless valid_end?(wall1, end1, point) && valid_end?(wall2, end2, point)

      { end1: end1, end2: end2, point: point, type: type, gap: JointGeometry.distance(p1, p2) }
    end

    # The new end must be reachable and leave the wall MIN_SEGMENT_MM long.
    def self.valid_end?(wall, which, point)
      return false if JointGeometry.distance(point, end_point(wall, which)) > MAX_JOINT_DISTANCE_MM

      direction = outward_direction(wall, which)
      interior = which == :start ? wall.path_points[1] : wall.path_points[-2]
      along = ((point[0] - interior[0]) * direction[0]) + ((point[1] - interior[1]) * direction[1])
      along > MIN_SEGMENT_MM
    end

    def self.path_length(wall)
      wall.path_points.each_cons(2).sum { |a, b| JointGeometry.distance(a, b) }
    end

    def self.own_joints(wall)
      joints = wall.params['joints']
      return [] unless joints.is_a?(Hash)

      joints.select { |_key, joint| joint.is_a?(Hash) }.to_a
    end

    def self.mutual?(group1, end1, group2, end2)
      other = WallModel.from_group(group2)
      joint = other && other.params['joints'].is_a?(Hash) ? other.params['joints'][end2.to_s] : nil
      joint.is_a?(Hash) && joint['uid'].to_s == WallBuilder.wall_id(group1) && joint['other_end'].to_s == end1.to_s
    end

    def self.link(wall, end_key, other_group, other_end, kind, extra = {})
      joints = wall.params['joints'].is_a?(Hash) ? wall.params['joints'] : {}
      joints[end_key.to_s] = { 'uid' => WallBuilder.wall_id(other_group), 'other_end' => other_end.to_s, 'kind' => kind }.merge(extra)
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

    def self.unlink_pair(group, end_key, other, other_end)
      unlink(group, end_key)
      unlink(other, other_end) if other && other_end && mutual?(group, end_key, other, other_end.to_s)
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

    def self.save_and_rebuild(model, group1, wall1, group2, wall2)
      wall1.save_to_group(group1)
      wall2.save_to_group(group2)
      WallBuilder.rebuild_wall_from_model(model, group1, wall1)
      WallBuilder.rebuild_wall_from_model(model, group2, wall2)
    end

    def self.save_and_rebuild_one(model, group, wall)
      wall.save_to_group(group)
      WallBuilder.rebuild_wall_from_model(model, group, wall)
    end
  end
end
