# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Builder
# ==============================================================================

require 'json'
require 'securerandom'
require_relative 'constants'
require_relative 'geometry_helper'
require_relative 'joint_geometry'
require_relative 'joint_solver'
require_relative 'segment_layers'
require_relative 'arc_geometry'
require_relative 'wall_object'

module MMA_WallsAndSlabs
  class WallBuilder
    # Stable id of a wall, kept in the group's attributes. Joints link walls by
    # this id rather than by persistent_id, which is not reliable enough for links.
    def self.wall_id(group)
      id = group.get_attribute(DICT_NAME, 'wall_id').to_s
      return id unless id.empty?

      id = SecureRandom.hex(8)
      group.set_attribute(DICT_NAME, 'wall_id', id)
      id
    end

    def self.serialize_group_data(group, params)
      unless group.get_attribute(DICT_NAME, ATTR_VERSION) == PLUGIN_DATA_VERSION
        group.set_attribute(DICT_NAME, ATTR_VERSION, PLUGIN_DATA_VERSION)
      end
      wall_id(group)
      payload = JSON.generate(params)
      existing = group.get_attribute(DICT_NAME, ATTR_DATA)
      return if existing == payload

      group.set_attribute(DICT_NAME, ATTR_DATA, payload)
    end

    # Builds a wall from params. Curved walls (params['arc']) and straight or
    # polyline walls are handled separately. Legacy straight walls without a
    # stored path are converted to a two-point path.
    def self.build(model, params, target_group = nil)
      return nil unless model && params
      return build_arc(model, params, target_group) if params['arc'].is_a?(Hash)

      points = params['path_points'] || [params['start_point'] || [0, 0, 0],
                                         params['end_point'] || [1000, 0, 0]]
      build_path(model, params, points, target_group)
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

      active = active_layer_indices(params)
      raise ArgumentError, 'The wall must have at least one layer with positive thickness.' if active.empty?

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

      # Each segment has its own layer stack (base layers plus its overrides)
      # and therefore its own boundary offsets from the centre line.
      stacks = Array.new(segment_count) { |segment| stack_for(params, segment, active) }
      bounds = stacks.map { |stack| SegmentLayers.boundaries(stack_thicknesses(stack), params['justification']) }
      max_total = bounds.map { |offsets| offsets.last - offsets.first }.max.to_f

      # Joints are only meaningful for open walls. Keep the stored links unless
      # the caller supplies new ones.
      joints = closed ? {} : resolve_joints(params, target_group)
      path_params = params.merge(
        'start_point' => path_points.first,
        'end_point' => path_points.last,
        'path_points' => path_points,
        'path_closed' => closed
      )
      path_params.delete('arc')
      if joints.empty?
        path_params.delete('joints')
      else
        path_params['joints'] = joints
      end

      model.start_operation('Build MMA Wall Path', true)
      operation_started = true
      path_group = target_group || model.active_entities.add_group
      path_group.transformation = Geom::Transformation.new if target_group
      path_group.entities.clear! if target_group
      path_group.name = closed ? 'MMA Wall Path (closed)' : 'MMA Wall Path'
      path_group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      serialize_group_data(path_group, path_params)

      corner_table = joint_corners(model, path_group, path_params, path_points, closed)

      full = wall_layers(params)
      layer_groups = active.map do |full_index|
        layer = full[full_index]
        thickness = layer['thickness'].to_f
        group = path_group.entities.add_group
        group.name = "Layer: #{layer['name']} (#{thickness.round}mm)"
        material = GeometryHelper.get_or_create_material(model, layer['material'])
        group.material = material if material
        group
      end

      path_length = segment_count.times.sum do |index|
        point_distance_2d(path_points[index], path_points[(index + 1) % path_points.length])
      end
      cumulative_distance = 0.0
      segment_count.times do |index|
        start_point = path_points[index]
        end_point = path_points[(index + 1) % path_points.length]
        length = point_distance_2d(start_point, end_point)
        local_openings = path_openings_for_segment(params, cumulative_distance, length, path_length, closed)
        segment_params = params.merge('openings' => local_openings)
        build_path_segment(model, segment_params, path_points, directions, index, layer_groups,
                           stacks, bounds, active, closed, corner_table, max_total)
        cumulative_distance += length
      end
      wrap_position = end_wrap_spec(path_params, active)
      if !wrap_position.nil? && !closed
        start_layer = stacks.first[wrap_position]
        end_layer = stacks.last[wrap_position]
        build_end_wrap(model, path_group.entities, path_points.first, directions.first, bounds.first,
                       (path_params['height'] || Defaults::WALL_HEIGHT).to_f,
                       start_layer, true) unless corner_table['start']
        build_end_wrap(model, path_group.entities, path_points.last, directions.last, bounds.last,
                       (path_params['height'] || Defaults::WALL_HEIGHT).to_f,
                       end_layer, false) unless corner_table['end']
      end

      model.commit_operation
      operation_started = false
      path_group
    rescue StandardError
      model.abort_operation if operation_started
      raise
    end

    # Builds a curved wall from params['arc'] = { center:, radius:, sweep:, z: }
    # (local coordinates, mm). The start point is params['path_points'].first.
    # Curved walls are not joined and do not take openings yet.
    def self.build_arc(model, params, target_group = nil)
      arc = params['arc']
      center = Array(arc['center']).map(&:to_f)
      radius = arc['radius'].to_f
      sweep = arc['sweep'].to_f
      z = arc['z'].to_f
      raise ArgumentError, 'Curved wall radius must be greater than zero.' unless radius.positive?
      raise ArgumentError, 'Curved wall sweep must not be zero.' if sweep.abs < 1e-6

      height_mm = (params['height'] || Defaults::WALL_HEIGHT).to_f
      raise ArgumentError, 'Wall height must be greater than zero.' unless height_mm.positive?

      active = active_layer_indices(params)
      raise ArgumentError, 'The wall must have at least one layer with positive thickness.' if active.empty?

      stack = stack_for(params, 0, active)
      bounds = SegmentLayers.boundaries(stack_thicknesses(stack), params['justification'])
      radii = bounds.map { |offset| ArcGeometry.offset_radius(radius, sweep, offset) }
      raise ArgumentError, 'The curved wall layers would reach the centre. Use a larger radius.' if radii.any? { |r| r <= 0.001 }

      first = params['path_points'] ? params['path_points'].first : params['start_point']
      start = ArcGeometry.angle(center, first)
      centre_line = ArcGeometry.sample(center, radius, start, sweep)
      path_points = centre_line.map { |x, y| [x, y, z] }
      stored = params.merge('path_points' => path_points, 'path_closed' => false,
                            'start_point' => path_points.first, 'end_point' => path_points.last,
                            'openings' => [])
      stored.delete('joints')

      model.start_operation('Build MMA Curved Wall', true)
      operation_started = true
      group = target_group || model.active_entities.add_group
      group.transformation = Geom::Transformation.new if target_group
      group.entities.clear! if target_group
      group.name = 'MMA Curved Wall'
      group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      serialize_group_data(group, stored)

      height = GeometryHelper.mm(height_mm)
      stack.each_with_index do |layer, index|
        thickness = layer['thickness'].to_f
        next if thickness <= 0.001

        layer_group = group.entities.add_group
        layer_group.name = "Layer: #{layer['name']} (#{thickness.round}mm)"
        material = GeometryHelper.get_or_create_material(model, layer['material'])
        layer_group.material = material if material

        outer = ArcGeometry.sample(center, radii[index], start, sweep)
        inner = ArcGeometry.sample(center, radii[index + 1], start, sweep).reverse
        ring = (outer + inner).map do |x, y|
          Geom::Point3d.new(GeometryHelper.mm(x), GeometryHelper.mm(y), GeometryHelper.mm(z))
        end
        face = layer_group.entities.add_face(ring)
        raise ArgumentError, "Could not create the curved wall layer '#{layer['name']}'." unless face

        face.material = material if material
        face.back_material = material if material
        face.pushpull(face.normal.z.positive? ? height : -height)
      end
      wrap_position = end_wrap_spec(params, active)
      if wrap_position
        direction = [Math.cos(start + (Math::PI / 2.0) * (sweep < 0 ? -1 : 1)),
                     Math.sin(start + (Math::PI / 2.0) * (sweep < 0 ? -1 : 1))]
        end_angle = start + sweep
        end_direction = [Math.cos(end_angle + (Math::PI / 2.0) * (sweep < 0 ? -1 : 1)),
                         Math.sin(end_angle + (Math::PI / 2.0) * (sweep < 0 ? -1 : 1))]
        start_layer = stack[wrap_position]
        build_end_wrap(model, group.entities, path_points.first, direction, bounds, height_mm, start_layer, true)
        build_end_wrap(model, group.entities, path_points.last, end_direction, bounds, height_mm, stack[wrap_position], false)
      end

      model.commit_operation
      operation_started = false
      group
    rescue StandardError
      model.abort_operation if operation_started
      raise
    end

    # Joints saved on a wall, used when the caller does not pass its own.
    def self.resolve_joints(params, target_group)
      source = if params.key?('joints')
                 params['joints']
               elsif target_group && target_group.valid?
                 stored_joints(target_group)
               end
      source.is_a?(Hash) ? source.dup : {}
    end

    def self.stored_joints(group)
      raw = group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless raw

      JSON.parse(raw)['joints']
    rescue JSON::ParserError
      nil
    end

    # Full-list indices of the layers that are enabled and have thickness.
    def self.active_layer_indices(params)
      layers = wall_layers(params)
      layers.each_index.select { |index| layers[index]['enabled'] != false && layers[index]['thickness'].to_f > 0.001 }
    end

    # The active layers of one segment, with that segment's overrides applied.
    def self.stack_for(params, segment, active)
      full = wall_layers(params)
      SegmentLayers.apply(full, params['segment_layers'], segment).values_at(*active)
    end

    def self.stack_thicknesses(stack)
      stack.map { |layer| layer['thickness'].to_f }
    end

    def self.alignment_offset(justification, total_thickness)
      SegmentLayers.boundaries([total_thickness], justification).first
    end

    def self.end_wrap_spec(params, active)
      side = params['end_wrap'].to_s
      return nil unless %w[inner outer].include?(side)

      full_layers = wall_layers(params)
      exterior_count = Array(params['ext_layers']).length
      interior_start = full_layers.length - Array(params['int_layers']).length
      candidates = case side
                   when 'outer' then active.select { |index| index < exterior_count }
                   when 'inner' then active.select { |index| index >= interior_start }
                   end
      full_index = if candidates.empty?
                     side == 'outer' ? active.first : active.last
                   else
                     side == 'outer' ? candidates.first : candidates.last
                   end
      active.index(full_index)
    end

    def self.build_end_wrap(model, entities, point, direction, bounds, height, layer, at_start)
      thickness = layer['thickness'].to_f
      return if thickness <= 0.001 || height.to_f <= 0.001

      normal = [-direction[1], direction[0]]
      low_offset, high_offset = bounds.minmax
      low = [point[0] + normal[0] * low_offset, point[1] + normal[1] * low_offset, point[2]]
      high = [point[0] + normal[0] * high_offset, point[1] + normal[1] * high_offset, point[2]]
      face_points = [low, high, [high[0], high[1], high[2] + height],
                     [low[0], low[1], low[2] + height]]
      wrap_group = entities.add_group
      wrap_group.name = "End wrap: #{layer['name']}"
      material = GeometryHelper.get_or_create_material(model, layer['material'])
      wrap_group.material = material if material
      face = wrap_group.entities.add_face(face_points.map do |coordinates|
        Geom::Point3d.new(*coordinates.map { |value| GeometryHelper.mm(value) })
      end)
      raise ArgumentError, "Could not create the #{at_start ? 'start' : 'end'} wall wrap." unless face

      inward = at_start ? direction : direction.map { |value| -value }
      normal_dot = face.normal.x * inward[0] + face.normal.y * inward[1]
      face.pushpull(GeometryHelper.mm(thickness * (normal_dot.positive? ? 1.0 : -1.0)))
      face.material = material if material
      face.back_material = material if material
      wrap_group
    end

    # Boundary offsets of the wall end at the start or end of an open path.
    def self.end_boundaries(params, at_start, segment_count)
      active = active_layer_indices(params)
      segment = at_start ? 0 : segment_count - 1
      SegmentLayers.boundaries(stack_thicknesses(stack_for(params, segment, active)), params['justification'])
    end

    # Layer-end corners at each joined end of an open wall. Returns
    # { 'start' => [[x, y], ...], 'end' => [...] } with one point per layer boundary,
    # in the same order as the boundaries used by build_path_segment.
    def self.joint_corners(model, own_group, params, path_points, closed)
      joints = params['joints']
      return {} if closed || model.nil? || own_group.nil? || !joints.is_a?(Hash) || joints.empty?

      table = {}
      %w[start end].each do |end_key|
        joint = joints[end_key]
        next unless joint.is_a?(Hash)

        own = end_frame(params, path_points, end_key == 'start')
        next unless own

        corners = case joint_kind(joint)
                  when 'corner' then corner_corners(model, own_group, end_key, own, joint)
                  when 'chamfer' then chamfer_corners(model, own_group, end_key, own, joint)
                  when 't' then tee_corners(model, own, joint)
                  end
        table[end_key] = corners if corners
      end
      table
    end

    def self.joint_kind(joint)
      kind = joint['kind'].to_s
      return kind unless kind.empty?

      joint['other_end'].to_s == 't' ? 't' : 'corner'
    end

    # Frame of one end: joint point, outward direction, outward-frame offsets of
    # every boundary, and the core's position among the active layers.
    def self.end_frame(params, path_points, at_start)
      direction = JointGeometry.path_direction(path_points, at_start)
      return nil unless direction

      active = active_layer_indices(params)
      segment = at_start ? 0 : path_points.length - 2
      sigma = at_start ? -1.0 : 1.0
      outward = [sigma * direction[0], sigma * direction[1]]
      stack = stack_for(params, segment, active)
      bounds = SegmentLayers.boundaries(stack_thicknesses(stack), params['justification'])
      q = bounds.map { |offset| sigma * offset }
      core = core_position(params, active)
      {
        point: at_start ? path_points.first : path_points.last,
        outward: outward,
        n: JointGeometry.left_normal(outward),
        q: q,
        b: bounds,
        n_path: JointGeometry.left_normal(direction),
        core_k: core,
        core_q: [q[core], q[core + 1]]
      }
    end

    def self.joint_limit(own)
      # Use the spread of the offsets, not last - first: at a start end the
      # outward-frame offsets run in reverse, which made the limit negative.
      JointGeometry::MITRE_LIMIT_FACTOR * [(own[:b].max - own[:b].min).abs, 1.0].max
    end

    # Index (among the active layers) of the core: a layer named core / structural
    # wall / stud, otherwise the thickest layer.
    def self.core_position(params, active)
      full = wall_layers(params)
      named = active.each_index.find { |index| full[active[index]]['name'].to_s =~ /core|structural wall|stud/i }
      return named if named

      active.each_index.max_by { |index| full[active[index]]['thickness'].to_f }
    end

    def self.linked_back?(other_wall, other_end, own_group, own_end)
      joint = other_wall.params['joints'].is_a?(Hash) ? other_wall.params['joints'][other_end] : nil
      joint.is_a?(Hash) && joint['uid'].to_s == wall_id(own_group) && joint['other_end'].to_s == own_end
    end

    def self.corner_corners(model, own_group, end_key, own, joint)
      other_group = find_wall_group(model, joint['uid'].to_s)
      return nil if other_group.nil? || other_group == own_group

      other = WallModel.from_group(other_group)
      return nil unless other && other.path_points && !other.path_closed? && !other.arc?

      other_end = joint['other_end'].to_s
      return nil unless linked_back?(other, other_end, own_group, end_key)

      other_frame = end_frame(other.params, other.path_points, other_end == 'start')
      return nil unless other_frame && other_frame[:b].length == own[:b].length

      JointSolver.corner_by_index(own[:point], own[:n_path], own[:b], other_frame[:n_path], other_frame[:b], joint_limit(own))
    end

    def self.chamfer_corners(model, own_group, end_key, own, joint)
      other_group = find_wall_group(model, joint['uid'].to_s)
      return nil if other_group.nil? || other_group == own_group

      other = WallModel.from_group(other_group)
      return nil unless other && linked_back?(other, joint['other_end'].to_s, own_group, end_key)

      cut = joint['cut']
      return nil unless cut.is_a?(Array) && cut.length == 2

      JointSolver.chamfer(own[:point], own[:n], own[:q], cut[0], cut[1])
    end

    # Stub end on a through wall: the core meets the core face of the through
    # wall on the stub's side, every other layer meets its outer face.
    def self.tee_corners(model, own, joint)
      through_group = find_wall_group(model, joint['uid'].to_s)
      return nil unless through_group

      through = WallModel.from_group(through_group)
      return nil unless through && through.path_points && !through.arc?

      point = own[:point]
      on_path = SegmentLayers.project_onto_path(through.path_points, point[0], point[1], through.path_closed?)
      segment = SegmentLayers.nearest_segment(through.path_points, point[0], point[1], through.path_closed?)
      return nil unless on_path && segment

      a = through.path_points[segment]
      b = through.path_points[(segment + 1) % through.path_points.length]
      direction = JointGeometry.unit(a, b)
      return nil unless direction

      n_through = JointGeometry.left_normal(direction)
      active = active_layer_indices(through.params)
      faces = SegmentLayers.boundaries(stack_thicknesses(stack_for(through.params, segment, active)),
                                       through.params['justification'])
      core = core_position(through.params, active)
      body_dot = (-own[:outward][0] * n_through[0]) + (-own[:outward][1] * n_through[1])
      if body_dot >= 0
        face_core = faces[core + 1]
        face_outer = faces.last
      else
        face_core = faces[core]
        face_outer = faces.first
      end

      core_flags = own[:q].each_index.map { |index| index == own[:core_k] || index == own[:core_k] + 1 }
      JointSolver.tee(point, own[:n], own[:q], core_flags, on_path, n_through, face_core, face_outer, joint_limit(own))
    end

    def self.find_wall_group(model, id)
      return nil unless model && !id.to_s.empty?

      model.entities.grep(Sketchup::Group).find do |group|
        group.valid? && group.get_attribute(DICT_NAME, 'wall_id').to_s == id.to_s && WallModel.valid_wall_group?(group)
      end
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

    # Builds the layer faces of one segment. bounds[i] are the boundary offsets
    # of segment i; a vertex is mitred between the offsets of the two segments
    # that meet there, so segments with different thicknesses join cleanly.
    def self.build_path_segment(model, params, path_points, directions, index, layer_groups,
                                stacks, bounds, active, closed, joint_table, max_total)
      height_mm = (params['height'] || Defaults::WALL_HEIGHT).to_f
      raise ArgumentError, 'Wall height must be greater than zero.' unless height_mm.positive?

      raise ArgumentError, 'The wall must have at least one layer with positive thickness.' if active.empty?

      max_miter_distance = [max_total, 1.0].max * 4.0
      segment_count = directions.length
      segment_end_index = (index + 1) % path_points.length
      start_point = path_points[index]
      end_point = path_points[segment_end_index]
      direction = directions[index]
      length = Math.sqrt((end_point[0] - start_point[0])**2 + (end_point[1] - start_point[1])**2)

      own = bounds[index]
      # Offsets of the segments on either side of the two vertices. For an open
      # wall's free end there is no neighbour, so the own segment is used.
      prev_bounds = (index.zero? && !closed) ? own : bounds[(index - 1) % segment_count]
      next_bounds = (index == segment_count - 1 && !closed) ? own : bounds[(index + 1) % segment_count]

      start_corners = index.zero? ? joint_table['start'] : nil
      end_corners = index == path_points.length - 2 ? joint_table['end'] : nil

      openings = Array(params['openings']).select do |opening|
        opening.is_a?(Hash) && opening.key?('position') &&
          opening['width'].to_f.positive? && opening['height'].to_f.positive?
      end
      patches = wall_patches(length, height_mm, openings)

      active.each_with_index do |full_index, layer_index|
        layer = stacks[index][layer_index]
        thickness = layer['thickness'].to_f
        next if thickness <= 0.001

        layer_group = layer_groups[layer_index]
        material = GeometryHelper.get_or_create_material(model, layer['material'])
        offset = own[layer_index]
        upper = own[layer_index + 1]

        low_start = path_offset_point(path_points, directions, index,
                                      prev_bounds[layer_index], own[layer_index], closed, max_miter_distance)
        low_end = path_offset_point(path_points, directions, segment_end_index,
                                    own[layer_index], next_bounds[layer_index], closed, max_miter_distance)
        high_start = path_offset_point(path_points, directions, index,
                                       prev_bounds[layer_index + 1], upper, closed, max_miter_distance)
        high_end = path_offset_point(path_points, directions, segment_end_index,
                                     upper, next_bounds[layer_index + 1], closed, max_miter_distance)

        # Joined ends use the mitred corners shared with the neighbouring wall.
        start_joined = joint_pair?(start_corners, layer_index)
        end_joined = joint_pair?(end_corners, layer_index)
        if start_joined
          low_start = joint_point(start_corners[layer_index], start_point)
          high_start = joint_point(start_corners[layer_index + 1], start_point)
        end
        if end_joined
          low_end = joint_point(end_corners[layer_index], end_point)
          high_end = joint_point(end_corners[layer_index + 1], end_point)
        end

        unless closed
          start_extension = Array(params['layer_start_extensions'])[full_index].to_f
          end_extension = Array(params['layer_end_extensions'])[full_index].to_f
          if index.zero? && !start_extension.zero? && !start_joined
            low_start = extend_path_endpoint(low_start, directions[index], start_extension, true)
            high_start = extend_path_endpoint(high_start, directions[index], start_extension, true)
          end
          if index == path_points.length - 2 && !end_extension.zero? && !end_joined
            low_end = extend_path_endpoint(low_end, directions[index], end_extension, false)
            high_end = extend_path_endpoint(high_end, directions[index], end_extension, false)
          end
        end

        patches.each do |left, right, bottom, top|
          low_left = left <= 0.001 ? low_start : path_station_point(start_point, direction, offset, left)
          low_right = right >= length - 0.001 ? low_end : path_station_point(start_point, direction, offset, right)
          high_right = right >= length - 0.001 ? high_end : path_station_point(start_point, direction, upper, right)
          high_left = left <= 0.001 ? high_start : path_station_point(start_point, direction, upper, left)
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
      end
    end

    def self.joint_pair?(corners, layer_index)
      !corners.nil? && !corners[layer_index].nil? && !corners[layer_index + 1].nil?
    end

    def self.joint_point(xy, reference)
      [xy[0], xy[1], reference[2]]
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

    # Corner of a path vertex for one boundary. offset_prev is the offset from
    # the centre line in the segment before the vertex, offset_next the offset in
    # the segment after it. They differ where adjacent segments have different
    # layer thicknesses. Open-wall ends use their single segment.
    def self.path_offset_point(path_points, directions, point_index, offset_prev, offset_next, closed, max_miter_distance)
      point = path_points[point_index]
      if !closed && (point_index.zero? || point_index == path_points.length - 1)
        segment_index = point_index.zero? ? 0 : directions.length - 1
        offset = point_index.zero? ? offset_next : offset_prev
        dx, dy = directions[segment_index]
        return [point[0] - dy * offset, point[1] + dx * offset, point[2]]
      end

      previous_direction = directions[(point_index - 1) % directions.length]
      next_direction = directions[point_index % directions.length]
      previous_normal = [-previous_direction[1], previous_direction[0]]
      next_normal = [-next_direction[1], next_direction[0]]
      previous_point = [
        point[0] + previous_normal[0] * offset_prev,
        point[1] + previous_normal[1] * offset_prev
      ]
      next_point = [
        point[0] + next_normal[0] * offset_next,
        point[1] + next_normal[1] * offset_next
      ]
      denominator = previous_direction[0] * next_direction[1] -
                    previous_direction[1] * next_direction[0]
      if denominator.abs <= 0.001
        dot = previous_direction[0] * next_direction[0] + previous_direction[1] * next_direction[1]
        raise ArgumentError, 'Adjacent wall segments cannot reverse direction at a joint.' if dot.negative?

        return [
          point[0] + (previous_normal[0] * offset_prev + next_normal[0] * offset_next) / 2.0,
          point[1] + (previous_normal[1] * offset_prev + next_normal[1] * offset_next) / 2.0,
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
