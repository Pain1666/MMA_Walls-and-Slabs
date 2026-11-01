# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Joiner Engine
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'
require_relative 'wall_builder'
require_relative 'wall_object'

module MMA_WallsAndSlabs
  module JoinType
    NONE = 'none'
    MITER = 'miter'
    BUTT = 'butt'
    OVERLAP = 'overlap'
    CONTINUATION = 'continuation'
  end

  class WallJoiner
    def self.detect_wall_join(model, wall1_group, wall2_group)
      return JoinType::NONE unless wall1_group && wall1_group.valid? && wall2_group && wall2_group.valid?
      return JoinType::NONE if wall1_group == wall2_group

      wall1 = WallModel.from_group(wall1_group)
      wall2 = WallModel.from_group(wall2_group)
      return JoinType::NONE unless wall1 && wall2

      a1 = wall1.start_point
      a2 = wall1.end_point
      b1 = wall2.start_point
      b2 = wall2.end_point

      if almost_parallel?(a1, a2, b1, b2)
        return JoinType::CONTINUATION if lines_overlap_2d?(a1, a2, b1, b2)
        return JoinType::NONE
      end

      intersection = find_segment_intersection_2d(a1, a2, b1, b2)
      return JoinType::NONE unless intersection

      if point_on_segment?(intersection, a1, a2) && point_on_segment?(intersection, b1, b2)
        JoinType::MITER
      else
        JoinType::NONE
      end
    end

    def self.refresh_adjacent_joins(model, wall_group)
      return false unless model && wall_group && wall_group.valid?

      group_list = model.entities.grep(Sketchup::Group)
      group_list.each do |other|
        next if other == wall_group
        next unless WallModel.valid_wall_group?(other)

        join_type = detect_wall_join(model, wall_group, other)
        next if join_type == JoinType::NONE

        apply_join(model, wall_group, other, join_type)
      end

      true
    end

    def self.apply_join(model, wall1_group, wall2_group, join_type = nil)
      return false unless wall1_group && wall1_group.valid? && wall2_group && wall2_group.valid?

      join_type ||= detect_wall_join(model, wall1_group, wall2_group)
      return false if join_type == JoinType::NONE

      wall1 = WallModel.from_group(wall1_group)
      wall2 = WallModel.from_group(wall2_group)
      return false unless wall1 && wall2

      a1 = wall1.start_point
      a2 = wall1.end_point
      b1 = wall2.start_point
      b2 = wall2.end_point
      intersection = find_segment_intersection_2d(a1, a2, b1, b2)
      return false unless intersection

      # Trim the nearest endpoint of each wall to the intersection if it is close enough.
      if join_type == JoinType::MITER || join_type == JoinType::BUTT || join_type == JoinType::CONTINUATION
        wall1_nearest = nearest_endpoint_for_point(wall1, intersection)
        wall2_nearest = nearest_endpoint_for_point(wall2, intersection)

        if wall1_nearest == :start
          wall1.set_start_point(intersection)
        else
          wall1.set_end_point(intersection)
        end

        if wall2_nearest == :start
          wall2.set_start_point(intersection)
        else
          wall2.set_end_point(intersection)
        end

        wall1.save_to_group(wall1_group)
        wall2.save_to_group(wall2_group)
        WallBuilder.rebuild_wall_from_model(model, wall1_group, wall1)
        WallBuilder.rebuild_wall_from_model(model, wall2_group, wall2)
        return true
      end

      false
    end

    def self.find_segment_intersection_2d(p1, p2, q1, q2)
      x1, y1 = p1[0].to_f, p1[1].to_f
      x2, y2 = p2[0].to_f, p2[1].to_f
      x3, y3 = q1[0].to_f, q1[1].to_f
      x4, y4 = q2[0].to_f, q2[1].to_f

      den = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4))
      return nil if den.abs < 1e-6

      px_num = ((x1 * y2) - (y1 * x2)) * (x3 - x4) - ((x1 - x2) * ((x3 * y4) - (y3 * x4)))
      py_num = ((x1 * y2) - (y1 * x2)) * (y3 - y4) - ((y1 - y2) * ((x3 * y4) - (y3 * x4)))

      px = px_num / den
      py = py_num / den
      [px, py, 0.0]
    end

    def self.point_on_segment?(point, p1, p2, tolerance = 0.5)
      min_x = [p1[0], p2[0]].min - tolerance
      max_x = [p1[0], p2[0]].max + tolerance
      min_y = [p1[1], p2[1]].min - tolerance
      max_y = [p1[1], p2[1]].max + tolerance

      return false unless point[0].to_f >= min_x && point[0].to_f <= max_x
      return false unless point[1].to_f >= min_y && point[1].to_f <= max_y

      true
    end

    def self.almost_parallel?(a1, a2, b1, b2, tolerance = 0.01)
      ax = a2[0] - a1[0]
      ay = a2[1] - a1[1]
      bx = b2[0] - b1[0]
      by = b2[1] - b1[1]

      cross = (ax * by) - (ay * bx)
      cross.abs <= tolerance
    end

    def self.lines_overlap_2d?(a1, a2, b1, b2)
      intersection = find_segment_intersection_2d(a1, a2, b1, b2)
      return false unless intersection

      point_on_segment?(intersection, a1, a2) && point_on_segment?(intersection, b1, b2)
    end

    def self.nearest_endpoint_for_point(wall_model, point)
      d_start = distance_2d(wall_model.start_point, point)
      d_end = distance_2d(wall_model.end_point, point)
      d_start <= d_end ? :start : :end
    end

    def self.distance_2d(p1, p2)
      dx = p1[0].to_f - p2[0].to_f
      dy = p1[1].to_f - p2[1].to_f
      Math.sqrt((dx * dx) + (dy * dy))
    end
  end
end
