# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Builder
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'

module MMA_WallsAndSlabs
  class WallBuilder
    def self.serialize_group_data(group, params)
      payload = JSON.generate(params)
      existing = group.get_attribute(DICT_NAME, ATTR_DATA)
      return if existing == payload

      group.set_attribute(DICT_NAME, ATTR_DATA, payload)
    end

    def self.build(model, params, target_group = nil)
      return nil unless model && params
      if params['path_points']
        return build_path(model, params, params['path_points'], target_group)
      end

      model.start_operation('Build MMA Wall', true)
      operation_started = true
      wall_group = target_group || model.active_entities.add_group
      wall_group.transformation = Geom::Transformation.new if target_group
      build_segment(model, params, wall_group, !target_group.nil?)

      model.commit_operation
      operation_started = false
      wall_group
    rescue StandardError
      model.abort_operation if operation_started
      raise
    end

    def self.build_path(model, params, points, target_group = nil)
      return nil unless model && params
      raise ArgumentError, 'A wall path must contain at least two points.' unless points.length >= 2

      raise ArgumentError, 'Each wall path point must contain three coordinates.' unless points.all? { |point| point.respond_to?(:length) && point.length >= 3 }

      path_points = points.map { |point| point.first(3).map(&:to_f) }
      path_points = path_points.each_with_object([]) do |point, cleaned|
        cleaned << point if cleaned.empty? || point_distance_2d(cleaned.last, point) > 0.001
      end
      repeated_endpoint = path_points.length > 1 &&
                          path_points.first.zip(path_points.last).all? { |first, last| (first - last).abs <= 0.001 }
      closed = params['path_closed'] == true || repeated_endpoint
      path_points.pop if repeated_endpoint
      raise ArgumentError, 'A closed wall path must contain at least three points.' if closed && path_points.length < 3
      raise ArgumentError, 'A wall path must contain at least two points.' if path_points.length < 2

      total_thickness = wall_layers(params)
                        .select { |layer| layer['enabled'] != false && layer['thickness'].to_f > 0.001 }
                        .sum { |layer| layer['thickness'].to_f }
      raise ArgumentError, 'The wall must have at least one layer with positive thickness.' if total_thickness <= 0.001

      segment_count = closed ? path_points.length : path_points.length - 1
      directions = segment_count.times.map do |index|
        start_point = path_points[index]
        end_point = path_points[(index + 1) % path_points.length]
        dx = end_point[0] - start_point[0]
        dy = end_point[1] - start_point[1]
        length = Math.sqrt((dx * dx) + (dy * dy))
        raise ArgumentError, 'Wall path points must not repeat or form vertical segments.' if length <= 0.001

        [dx / length, dy / length]
      end

      wall_layer_specs = wall_layers(params).each_with_index.select do |layer, _index|
        layer['enabled'] != false && layer['thickness'].to_f > 0.001
      end
      wall_layers = wall_layer_specs.map(&:first)
      path_params = params.merge(
        'start_point' => path_points.first,
        'end_point' => path_points.last,
        'path_points' => path_points,
        'path_closed' => closed
      )
      model.start_operation('Build MMA Wall Path', true)
      operation_started = true
      path_group = target_group || model.active_entities.add_group
      path_group.transformation = Geom::Transformation.new if target_group
      path_group.entities.clear! if target_group
      path_group.name = closed ? 'MMA Wall Path (closed)' : 'MMA Wall Path'
      path_group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      serialize_group_data(path_group, path_params)

      total_thickness = wall_layers.sum { |layer| layer['thickness'].to_f }
      path_length = segment_count.times.sum do |index|
        point_distance_2d(path_points[index], path_points[(index + 1) % path_points.length])
      end
      layer_groups = wall_layers.map do |layer|
        thickness = layer['thickness'].to_f
        group = path_group.entities.add_group
        group.name = "Layer: #{layer['name']} (#{thickness.round}mm)"
        material = GeometryHelper.get_or_create_material(model, layer['material'])
        group.material = material if material
        group
      end

      cumulative_distance = 0.0
      segment_count.times do |index|
        start_point = path_points[index]
        end_point = path_points[(index + 1) % path_points.length]
        length = point_distance_2d(start_point, end_point)
        local_openings = path_openings_for_segment(params, cumulative_distance, length, path_length, closed)
        segment_params = params.merge('openings' => local_openings)
        build_path_segment(segment_params, path_points, directions, index, layer_groups, wall_layer_specs, closed, total_thickness)
        cumulative_distance += length
      end

      model.commit_operation
      operation_started = false
      path_group
    rescue StandardError
      model.abort_operation if operation_started
      raise
    end

    def self.path_openings_for_segment(params, segment_start, segment_length, path_length, closed)
      Array(params['openings']).select do |opening|
        opening.is_a?(Hash) && opening.key?('position') &&
          opening['width'].to_f.positive? && opening['height'].to_f.positive?
      end.flat_map do |opening|
        center = opening['position'].to_f
        width = opening['width'].to_f
        centers = closed ? [center - path_length, center, center + path_length] : [center]
        centers.filter_map do |candidate|
          next if width <= 0 || candidate + width / 2.0 < segment_start ||
                  candidate - width / 2.0 > segment_start + segment_length

          opening.merge('position' => candidate - segment_start)
        end
      end
    end

    def self.build_path_segment(params, path_points, directions, index, layer_groups, layer_specs, closed, total_thickness)
      height_mm = (params['height'] || Defaults::WALL_HEIGHT).to_f
      raise ArgumentError, 'Wall height must be greater than zero.' unless height_mm.positive?

      raise ArgumentError, 'The wall must have at least one layer with positive thickness.' if layer_specs.empty?

      base_offset = case params['justification'].to_s
                    when WallJustification::LEFT then 0.0
                    when WallJustification::RIGHT then -total_thickness
                    else -total_thickness / 2.0
                    end
      max_miter_distance = total_thickness * 4.0

      segment_end_index = (index + 1) % path_points.length
      start_point = path_points[index]
      end_point = path_points[segment_end_index]
      direction = directions[index]
      length = Math.sqrt((end_point[0] - start_point[0])**2 + (end_point[1] - start_point[1])**2)

      offset = base_offset
      layer_specs.each_with_index do |(layer, source_index), layer_index|
        thickness = layer['thickness'].to_f
        layer_group = layer_groups[layer_index]
        material = layer_group.material

        low_start = path_offset_point(path_points, directions, index, offset, closed, max_miter_distance)
        low_end = path_offset_point(path_points, directions, segment_end_index, offset, closed, max_miter_distance)
        high_start = path_offset_point(path_points, directions, index, offset + thickness, closed, max_miter_distance)
        high_end = path_offset_point(path_points, directions, segment_end_index, offset + thickness, closed, max_miter_distance)
        unless closed
          start_extension = Array(params['layer_start_extensions'])[source_index].to_f
          end_extension = Array(params['layer_end_extensions'])[source_index].to_f
          if index.zero? && !start_extension.zero?
            low_start = extend_path_endpoint(low_start, directions[index], start_extension, true)
            high_start = extend_path_endpoint(high_start, directions[index], start_extension, true)
          end
          if index == path_points.length - 2 && !end_extension.zero?
            low_end = extend_path_endpoint(low_end, directions[index], end_extension, false)
            high_end = extend_path_endpoint(high_end, directions[index], end_extension, false)
          end
        end
        openings = Array(params['openings']).select do |opening|
          opening.is_a?(Hash) && opening.key?('position') &&
            opening['width'].to_f.positive? && opening['height'].to_f.positive?
        end
        patches = wall_patches(length, height_mm, openings)
        patches.each do |left, right, bottom, top|
          low_left = left <= 0.001 ? low_start : path_station_point(start_point, direction, offset, left)
          low_right = right >= length - 0.001 ? low_end : path_station_point(start_point, direction, offset, right)
          high_right = right >= length - 0.001 ? high_end : path_station_point(start_point, direction, offset + thickness, right)
          high_left = left <= 0.001 ? high_start : path_station_point(start_point, direction, offset + thickness, left)
          footprint = [low_left, low_right, high_right, high_left].map do |point|
            Geom::Point3d.new(
              GeometryHelper.mm(point[0]),
              GeometryHelper.mm(point[1]),
              GeometryHelper.mm(point[2] + bottom)
            )
          end
          face = layer_group.entities.add_face(footprint)
          raise ArgumentError, "Could not create the wall layer '#{layer['name']}'." unless face

          face.material = material if material
          face.back_material = material if material
          patch_height = GeometryHelper.mm(top - bottom)
          face.pushpull(face.normal.z.positive? ? patch_height : -patch_height)
        end
        offset += thickness
      end
    end

    def self.extend_path_endpoint(point, direction, distance, start)
      sign = start ? -1.0 : 1.0
      [point[0] + direction[0] * distance * sign,
       point[1] + direction[1] * distance * sign,
       point[2]]
    end

    def self.point_distance_2d(first, second)
      Math.sqrt((first[0] - second[0])**2 + (first[1] - second[1])**2)
    end

    def self.path_station_point(start_point, direction, offset, distance)
      normal_x = -direction[1]
      normal_y = direction[0]
      [
        start_point[0] + direction[0] * distance + normal_x * offset,
        start_point[1] + direction[1] * distance + normal_y * offset,
        start_point[2]
      ]
    end

    def self.path_offset_point(path_points, directions, point_index, offset, closed, max_miter_distance)
      point = path_points[point_index]
      if !closed && (point_index.zero? || point_index == path_points.length - 1)
        segment_index = point_index.zero? ? 0 : directions.length - 1
        dx, dy = directions[segment_index]
        return [point[0] - dy * offset, point[1] + dx * offset, point[2]]
      end

      previous_direction = directions[(point_index - 1) % directions.length]
      next_direction = directions[point_index % directions.length]
      previous_normal = [-previous_direction[1], previous_direction[0]]
      next_normal = [-next_direction[1], next_direction[0]]
      previous_point = [
        point[0] + previous_normal[0] * offset,
        point[1] + previous_normal[1] * offset
      ]
      next_point = [
        point[0] + next_normal[0] * offset,
        point[1] + next_normal[1] * offset
      ]
      denominator = previous_direction[0] * next_direction[1] -
                    previous_direction[1] * next_direction[0]
      if denominator.abs <= 0.001
        dot = previous_direction[0] * next_direction[0] + previous_direction[1] * next_direction[1]
        raise ArgumentError, 'Adjacent wall segments cannot reverse direction at a joint.' if dot.negative?

        return [
          point[0] + (previous_normal[0] + next_normal[0]) * offset / 2.0,
          point[1] + (previous_normal[1] + next_normal[1]) * offset / 2.0,
          point[2]
        ]
      end

      delta_x = next_point[0] - previous_point[0]
      delta_y = next_point[1] - previous_point[1]
      distance = (delta_x * next_direction[1] - delta_y * next_direction[0]) / denominator
      intersection = [
        previous_point[0] + previous_direction[0] * distance,
        previous_point[1] + previous_direction[1] * distance
      ]
      miter_distance = Math.sqrt((intersection[0] - point[0])**2 + (intersection[1] - point[1])**2)
      raise ArgumentError, 'Wall joint is too sharp to create a stable miter.' if miter_distance > max_miter_distance

      [intersection[0], intersection[1], point[2]]
    end

    def self.build_segment(model, params, wall_group, clear_group = false)
      start_point = Array(params['start_point'] || [0, 0, 0])
      end_point = Array(params['end_point'] || [1000, 0, 0])
      raise ArgumentError, 'Wall endpoints must contain three coordinates.' unless start_point.length >= 3 && end_point.length >= 3

      height_mm = (params['height'] || Defaults::WALL_HEIGHT).to_f
      raise ArgumentError, 'Wall height must be greater than zero.' unless height_mm.positive?

      x0, y0, z0 = start_point.first(3).map { |value| GeometryHelper.mm(Float(value)) }
      x1, y1, z1 = end_point.first(3).map { |value| GeometryHelper.mm(Float(value)) }
      dx = x1 - x0
      dy = y1 - y0
      length = Math.sqrt((dx * dx) + (dy * dy))
      raise ArgumentError, 'Wall endpoints must be different in the XY plane.' if length <= 0.001

      normal = Geom::Vector3d.new(-dy / length, dx / length, 0)
      layers = wall_layers(params)
      enabled_layers = layers.select { |layer| layer['enabled'] != false && layer['thickness'].to_f > 0.001 }
      raise ArgumentError, 'The wall must have at least one layer with positive thickness.' if enabled_layers.empty?

      total_thickness_mm = enabled_layers.sum { |layer| layer['thickness'].to_f }
      offset_mm = case params['justification'].to_s
                  when WallJustification::LEFT then 0.0
                  when WallJustification::RIGHT then -total_thickness_mm
                  else -total_thickness_mm / 2.0
                  end

      wall_group.entities.clear! if clear_group
      wall_group.name = 'MMA Wall' unless wall_group.name.to_s.start_with?('Wall Segment ')
      wall_group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      serialize_group_data(wall_group, params)

      entities = wall_group.entities
      openings = Array(params['openings']).select do |opening|
        opening.is_a?(Hash) && opening.key?('position') &&
          opening['width'].to_f.positive? && opening['height'].to_f.positive?
      end
      enabled_layers.each do |layer|
        thickness_mm = layer['thickness'].to_f
        thickness_in = GeometryHelper.mm(thickness_mm)
        layer_group = entities.add_group
        layer_group.name = "Layer: #{layer['name']} (#{thickness_mm.round}mm)"
        material = GeometryHelper.get_or_create_material(model, layer['material'])
        layer_group.material = material if material

        base_offset = GeometryHelper.mm(offset_mm)
        wall_patches(length, height_mm, openings).each do |patch|
          patch_group = layer_group.entities.add_group
          left, right, bottom, top = patch
          corners = [
            [x0 + (dx / length * left) + normal.x * base_offset,
             y0 + (dy / length * left) + normal.y * base_offset,
             z0 + GeometryHelper.mm(bottom)],
            [x0 + (dx / length * right) + normal.x * base_offset,
             y0 + (dy / length * right) + normal.y * base_offset,
             z0 + GeometryHelper.mm(bottom)],
            [x0 + (dx / length * right) + normal.x * base_offset,
             y0 + (dy / length * right) + normal.y * base_offset,
             z0 + GeometryHelper.mm(top)],
            [x0 + (dx / length * left) + normal.x * base_offset,
             y0 + (dy / length * left) + normal.y * base_offset,
             z0 + GeometryHelper.mm(top)]
          ]
          face = patch_group.entities.add_face(corners.map { |coordinates| Geom::Point3d.new(*coordinates) })
          raise ArgumentError, "Could not create the wall layer '#{layer['name']}'." unless face

          face.material = material if material
          face.back_material = material if material
          face.pushpull(-thickness_in)
        end
        offset_mm += thickness_mm
      end
      wall_group
    end

    def self.rebuild_wall_from_model(model, group, wall_model = nil)
      return false unless model && group && group.valid?

      wall_model ||= WallModel.from_group(group)
      return false unless wall_model

      build(model, wall_model.params, group)
      true
    end

    def self.wall_layers(params)
      exterior = Array(params['ext_layers']).select { |layer| layer.is_a?(Hash) }
      interior = Array(params['int_layers']).select { |layer| layer.is_a?(Hash) }
      layers = exterior + interior
      has_core = layers.any? { |layer| layer['name'].to_s =~ /core|structural wall|stud/i }
      core_thickness = params['core_thickness'].to_f
      if !has_core && core_thickness > 0.001
        core = {
          'name' => 'Structural core',
          'thickness' => core_thickness,
          'material' => params['core_material'],
          'enabled' => true
        }
        layers = exterior + [core] + interior
      end
      layers
    end

    def self.wall_patches(length, height, openings)
      levels = [0.0, height]
      openings.each do |opening|
        width = opening['width'].to_f
        sill = opening['sill_height'].to_f
        top = sill + opening['height'].to_f
        next unless width.positive? && opening['height'].to_f.positive?

        levels << [[sill, 0.0].max, height].min
        levels << [[top, 0.0].max, height].min
      end
      levels = levels.uniq.sort

      levels.each_cons(2).flat_map do |bottom, top|
        next [] if top - bottom <= 0.001

        middle = (bottom + top) / 2.0
        blocked = openings.filter_map do |opening|
          width = opening['width'].to_f
          sill = opening['sill_height'].to_f
          opening_top = sill + opening['height'].to_f
          next unless width.positive? && opening['height'].to_f.positive?
          next unless middle >= sill && middle <= opening_top

          center = opening['position'].to_f
          left = [[center - width / 2.0, 0.0].max, length].min
          right = [[center + width / 2.0, 0.0].max, length].min
          [left, right] if right - left > 0.001
        end.sort_by(&:first)

        segments = []
        cursor = 0.0
        blocked.each do |left, right|
          segments << [cursor, left, bottom, top] if left - cursor > 0.001
          cursor = [cursor, right].max
        end
        segments << [cursor, length, bottom, top] if length - cursor > 0.001
        segments
      end
    end
  end
end
