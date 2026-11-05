# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall geometry as plain numbers (no SketchUp API)
#
# Computes the same layer footprints WallBuilder turns into faces, so a preview
# can be drawn without changing the model. Units are mm. A "box" is one layer
# piece: a base footprint (4 points, z included) extruded upwards by height.
# ==============================================================================

require_relative 'constants'
require_relative 'joint_geometry'
require_relative 'joint_solver'
require_relative 'segment_layers'
require_relative 'wall_builder'

module MMA_WallsAndSlabs
  module WallGeometry
    module_function

    # Layer boxes of an open or closed path. joint_table has the same format as
    # WallBuilder.joint_corners ('start' / 'end' => corner points per boundary).
    # Returns [{ base: [[x,y,z] x4], height: mm, material: name }, ...]
    def boxes(params, path_points, closed = false, joint_table = {})
      active = WallBuilder.active_layer_indices(params)
      return [] if active.empty? || path_points.length < 2

      count = closed ? path_points.length : path_points.length - 1
      directions = count.times.map do |index|
        JointGeometry.unit(path_points[index], path_points[(index + 1) % path_points.length])
      end
      return [] if directions.any?(&:nil?)

      stacks = Array.new(count) { |segment| WallBuilder.stack_for(params, segment, active) }
      bounds = stacks.map { |stack| SegmentLayers.boundaries(WallBuilder.stack_thicknesses(stack), params['justification']) }
      max_total = bounds.map { |offsets| offsets.last - offsets.first }.max.to_f
      max_miter = [max_total, 1.0].max * 4.0
      height = (params['height'] || Defaults::WALL_HEIGHT).to_f
      openings = Array(params['openings']).select do |opening|
        opening.is_a?(Hash) && opening.key?('position') && opening['width'].to_f.positive? && opening['height'].to_f.positive?
      end

      result = []
      count.times do |index|
        end_index = (index + 1) % path_points.length
        start_point = path_points[index]
        end_point = path_points[end_index]
        direction = directions[index]
        length = WallBuilder.point_distance_2d(start_point, end_point)
        own = bounds[index]
        prev_b = (index.zero? && !closed) ? own : bounds[(index - 1) % count]
        next_b = (index == count - 1 && !closed) ? own : bounds[(index + 1) % count]
        start_corners = index.zero? ? joint_table['start'] : nil
        end_corners = index == path_points.length - 2 ? joint_table['end'] : nil
        patches = WallBuilder.wall_patches(length, height, openings)

        active.each_index do |layer_index|
          layer = stacks[index][layer_index]
          next if layer['thickness'].to_f <= 0.001

          full_index = active[layer_index]
          offset = own[layer_index]
          upper = own[layer_index + 1]
          low_start = WallBuilder.path_offset_point(path_points, directions, index,
                                                    prev_b[layer_index], own[layer_index], closed, max_miter)
          low_end = WallBuilder.path_offset_point(path_points, directions, end_index,
                                                  own[layer_index], next_b[layer_index], closed, max_miter)
          high_start = WallBuilder.path_offset_point(path_points, directions, index,
                                                     prev_b[layer_index + 1], upper, closed, max_miter)
          high_end = WallBuilder.path_offset_point(path_points, directions, end_index,
                                                   upper, next_b[layer_index + 1], closed, max_miter)

          start_joined = WallBuilder.joint_pair?(start_corners, layer_index)
          end_joined = WallBuilder.joint_pair?(end_corners, layer_index)
          if start_joined
            low_start = WallBuilder.joint_point(start_corners[layer_index], start_point)
            high_start = WallBuilder.joint_point(start_corners[layer_index + 1], start_point)
          end
          if end_joined
            low_end = WallBuilder.joint_point(end_corners[layer_index], end_point)
            high_end = WallBuilder.joint_point(end_corners[layer_index + 1], end_point)
          end

          unless closed
            start_extension = Array(params['layer_start_extensions'])[full_index].to_f
            end_extension = Array(params['layer_end_extensions'])[full_index].to_f
            if index.zero? && !start_extension.zero? && !start_joined
              low_start = WallBuilder.extend_path_endpoint(low_start, direction, start_extension, true)
              high_start = WallBuilder.extend_path_endpoint(high_start, direction, start_extension, true)
            end
            if index == path_points.length - 2 && !end_extension.zero? && !end_joined
              low_end = WallBuilder.extend_path_endpoint(low_end, direction, end_extension, false)
              high_end = WallBuilder.extend_path_endpoint(high_end, direction, end_extension, false)
            end
          end

          patches.each do |left, right, bottom, top|
            low_left = left <= 0.001 ? low_start : WallBuilder.path_station_point(start_point, direction, offset, left)
            low_right = right >= length - 0.001 ? low_end : WallBuilder.path_station_point(start_point, direction, offset, right)
            high_right = right >= length - 0.001 ? high_end : WallBuilder.path_station_point(start_point, direction, upper, right)
            high_left = left <= 0.001 ? high_start : WallBuilder.path_station_point(start_point, direction, upper, left)
            base = [low_left, low_right, high_right, high_left].map { |p| [p[0], p[1], p[2] + bottom] }
            result << { base: base, height: top - bottom, material: layer['material'] }
          end
        end
      end
      result
    end

    # Corner between two walls, as if both ends were already at the joint.
    # path1 / path2 are the paths with the joined end moved to the joint point.
    # Returns { boxes1:, boxes2: } ready to draw.
    def corner(params1, path1, end1, params2, path2, end2)
      frame1 = WallBuilder.end_frame(params1, path1, end1 == :start)
      frame2 = WallBuilder.end_frame(params2, path2, end2 == :start)
      return nil unless frame1 && frame2 && frame1[:b].length == frame2[:b].length

      joint = frame1[:point]
      limit1 = WallBuilder.joint_limit(frame1)
      limit2 = WallBuilder.joint_limit(frame2)
      corners1 = JointSolver.corner_by_index(joint, frame1[:n_path], frame1[:b], frame2[:n_path], frame2[:b], limit1)
      corners2 = JointSolver.corner_by_index(joint, frame2[:n_path], frame2[:b], frame1[:n_path], frame1[:b], limit2)
      {
        boxes1: boxes(params1, path1, false, { end1.to_s => corners1 }),
        boxes2: boxes(params2, path2, false, { end2.to_s => corners2 })
      }
    end
  end
end
