# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Slab Builder
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'

module MMA_WallsAndSlabs
  class SlabBuilder
    def self.serialize_group_data(group, params)
      payload = JSON.generate(params)
      existing = group.get_attribute(DICT_NAME, ATTR_DATA)
      return if existing == payload

      group.set_attribute(DICT_NAME, ATTR_DATA, payload)
    end

    def self.build(model, params, target_group = nil)
      return nil unless model && params

      points = Array(params['points']).map do |point|
        raise ArgumentError, 'Slab points must contain at least two coordinates.' unless point.is_a?(Array) && point.length >= 2

        [Float(point[0]), Float(point[1])]
      end
      raise ArgumentError, 'A slab requires at least three points.' if points.length < 3

      layers = Array(params['layers']).select { |layer| layer.is_a?(Hash) && layer['enabled'] != false }
      layers = [{ 'name' => 'Concrete Slab', 'thickness' => 200.0, 'material' => 'EWS_Concrete', 'enabled' => true }] if layers.empty?
      layers = layers.select { |layer| layer['thickness'].to_f > 0.001 }
      raise ArgumentError, 'The slab must have at least one layer with positive thickness.' if layers.empty?

      reference = params['reference'].to_s == 'bottom' ? 'bottom' : 'top'
      elevation_in = GeometryHelper.mm(Float(params['elevation'] || 0.0))
      openings = Array(params['openings']).select { |opening| opening.is_a?(Hash) }
      patches = slab_patches(points, openings).select { |patch| polygon_area(patch).abs > 0.001 }
      raise ArgumentError, 'The slab outline does not form usable geometry.' if patches.empty?

      model.start_operation('Build MMA Slab', true)
      operation_started = true
      slab_group = target_group || model.active_entities.add_group
      slab_group.entities.clear! if target_group
      slab_group.name = 'MMA Slab'
      slab_group.set_attribute(DICT_NAME, ATTR_TYPE, 'slab')
      serialize_group_data(slab_group, params)

      current_z = elevation_in
      layers.each do |layer|
        thickness_mm = layer['thickness'].to_f
        thickness_in = GeometryHelper.mm(thickness_mm)
        layer_group = slab_group.entities.add_group
        layer_group.name = "Layer: #{layer['name']} (#{thickness_mm.round}mm)"
        material = GeometryHelper.get_or_create_material(model, layer['material'])
        layer_group.material = material if material

        patches.each do |patch|
          patch_group = layer_group.entities.add_group
          face_points = patch.map do |x, y|
            Geom::Point3d.new(GeometryHelper.mm(x), GeometryHelper.mm(y), current_z)
          end
          face = patch_group.entities.add_face(face_points)
          raise ArgumentError, 'Could not create a slab layer face from the supplied outline.' unless face

          face.reverse! if face.normal.z < 0
          face.material = material if material
          face.back_material = material if material
          patch_group.material = material if material
          face.pushpull(reference == 'top' ? -thickness_in : thickness_in)
        end
        current_z += GeometryHelper.mm(reference == 'top' ? -thickness_mm : thickness_mm)
      end

      model.commit_operation
      operation_started = false
      slab_group
    rescue StandardError
      model.abort_operation if operation_started
      raise
    end

    def self.create_from_face(model, face, layers)
      return nil unless face

      pts = face.outer_loop.vertices.map { |v| [GeometryHelper.to_mm(v.position.x), GeometryHelper.to_mm(v.position.y)] }
      elevation = GeometryHelper.to_mm(face.vertices.first.position.z)
      params = { 'points' => pts, 'elevation' => elevation, 'reference' => 'top', 'layers' => layers, 'openings' => [] }
      build(model, params)
    end

    def self.slab_patches(points, openings)
      x_values = points.map(&:first)
      valid_openings = openings.filter_map do |opening|
        width = opening['width'].to_f
        height = opening['height'].to_f
        next unless width.positive? && height.positive?

        x = opening['x'].to_f
        y = opening['y'].to_f
        [x, y, x + width, y + height]
      end
      breaks = x_values + valid_openings.flat_map { |opening| [opening[0], opening[2]] }
      breaks = breaks.uniq.sort
      edges = points.each_with_index.map { |point, index| [point, points[(index + 1) % points.length]] }
      patches = []

      breaks.each_cons(2) do |left_x, right_x|
        next if right_x - left_x <= 0.001

        middle_x = (left_x + right_x) / 2.0
        crossings = edges.filter_map do |first, second|
          next if (first[0] - second[0]).abs <= 0.001
          next unless middle_x > [first[0], second[0]].min && middle_x < [first[0], second[0]].max

          slope = (second[1] - first[1]) / (second[0] - first[0])
          intercept = first[1] - slope * first[0]
          { middle: slope * middle_x + intercept, slope: slope, intercept: intercept }
        end.sort_by { |edge| edge[:middle] }

        crossings.each_slice(2) do |lower, upper|
          next unless upper

          active_openings = valid_openings.select do |opening|
            middle_x > opening[0] && middle_x < opening[2] &&
              opening[1] < upper[:middle] && opening[3] > lower[:middle]
          end
          boundaries = [lower]
          active_openings.each do |opening|
            boundaries << { middle: opening[1], slope: 0.0, intercept: opening[1] } if opening[1] > lower[:middle] && opening[1] < upper[:middle]
            boundaries << { middle: opening[3], slope: 0.0, intercept: opening[3] } if opening[3] > lower[:middle] && opening[3] < upper[:middle]
          end
          boundaries << upper
          boundaries.sort_by! { |boundary| boundary[:middle] }

          boundaries.each_cons(2) do |low, high|
            sample_y = (low[:middle] + high[:middle]) / 2.0
            next if active_openings.any? { |opening| sample_y > opening[1] && sample_y < opening[3] }
            next if high[:middle] - low[:middle] <= 0.001

            y_low_left = low[:slope] * left_x + low[:intercept]
            y_low_right = low[:slope] * right_x + low[:intercept]
            y_high_left = high[:slope] * left_x + high[:intercept]
            y_high_right = high[:slope] * right_x + high[:intercept]
            patches << [
              [left_x, y_low_left],
              [right_x, y_low_right],
              [right_x, y_high_right],
              [left_x, y_high_left]
            ]
          end
        end
      end
      patches
    end

    def self.polygon_area(points)
      points.each_with_index.sum do |point, index|
        next_point = points[(index + 1) % points.length]
        (point[0] * next_point[1]) - (next_point[0] * point[1])
      end / 2.0
    end
  end
end
