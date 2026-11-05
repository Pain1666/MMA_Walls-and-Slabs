# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Edit Wall Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_object'
require_relative '../core/wall_builder'
require_relative '../core/wall_joiner'
require_relative '../core/segment_layers'

module MMA_WallsAndSlabs
  class EditWallTool
    HANDLE_RADIUS = 60.0
    AXIS_SNAP_ANGLE = 8.0 * Math::PI / 180.0
    PREVIEW_ALPHA = 75

    def initialize(group = nil)
      @group = group
      @state = :idle
      @handle = :none
      @input = Sketchup::InputPoint.new
      @drag_origin = nil
      @drag_origin_mm = nil
      @drag_start_model = nil
      @drag_preview_model = nil
      @drag_reference = nil
      @drag_plane_z = nil
      @drag_point_origin = nil
      @locked_axis = nil
      @locked_direction = nil
      @preset_index = 0
    end

    def activate
      @group ||= pick_wall_group
      if @group && @group.valid?
        Sketchup.status_text = 'MMA Edit Wall Tool: drag a wall handle or press T/J/F.'
      else
        Sketchup.status_text = 'MMA Edit Wall Tool: select a wall to edit.'
      end
    end

    def onMouseMove(flags, x, y, view)
      pick_drag_input(view, x, y)
      if @state != :idle && @drag_origin && @input.valid?
        @drag_preview_model = dragged_model(drag_position(@input.position))
        view.tooltip = @input.tooltip if @input.valid?
        Sketchup.status_text = if @locked_axis == :wall
                                 'MMA Edit Wall Tool: aligned with the adjacent wall direction.'
                               else
                                 status_for_state(@handle)
                               end
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @input.pick(view, x, y)
      target = @group || wall_group_at(view, x, y) || pick_wall_group_from_selection
      return unless target && target.valid?

      @group = target
      wall_model = WallModel.from_group(@group)
      return unless wall_model

      @handle = detect_handle_state(view, x, y, wall_model)
      return if @handle == :none

      @state = :dragging
      @drag_origin = @input.position
      @drag_origin_mm = [GeometryHelper.to_mm(@drag_origin.x), GeometryHelper.to_mm(@drag_origin.y), GeometryHelper.to_mm(@drag_origin.z)]
      @drag_start_model = WallModel.new(JSON.parse(JSON.generate(wall_model.params)))
      @drag_preview_model = @drag_start_model
      @drag_plane_z = wall_model.path_points ? wall_model.path_points.first[2] : wall_model.start_point[2]
      @drag_point_origin = dragged_point_origin(wall_model, @handle)
      @locked_axis = nil
      @locked_direction = nil
      @drag_reference = Sketchup::InputPoint.new
      @drag_reference.copy!(@input)
      Sketchup.status_text = status_for_state(@handle)
      view.invalidate
    end

    def onLButtonUp(flags, x, y, view)
      return unless @group && @group.valid? && @state != :idle

      pick_drag_input(view, x, y)
      if @input.valid?
        apply_drag(drag_position(@input.position))
        WallJoiner.refresh_adjacent_joins(Sketchup.active_model, @group)
      end

      @state = :idle
      @handle = :none
      @drag_origin = nil
      @drag_origin_mm = nil
      @drag_start_model = nil
      @drag_preview_model = nil
      @drag_reference = nil
      @drag_plane_z = nil
      @drag_point_origin = nil
      @locked_axis = nil
      @locked_direction = nil
      Sketchup.status_text = 'MMA Edit Wall Tool: ready.'
      view.invalidate
    rescue StandardError => error
      UI.messagebox("Could not edit wall: #{error.message}")
      @state = :idle
      @handle = :none
      @drag_origin = nil
      @drag_origin_mm = nil
      @drag_start_model = nil
      @drag_preview_model = nil
      @drag_reference = nil
      @drag_plane_z = nil
      @drag_point_origin = nil
      @locked_axis = nil
      @locked_direction = nil
      view.invalidate
    end

    def onLButtonDoubleClick(_flags, x, y, view)
      safe do
        @input.pick(view, x, y)
        target = wall_group_at(view, x, y) || @group || pick_wall_group_from_selection
        next unless target && target.valid? && WallModel.valid_wall_group?(target)

        wall_model = WallModel.from_group(target)
        next unless wall_model
        next unless detect_handle_state(view, x, y, wall_model) == :none

        @group = target
        edit_segment_layers(target, wall_model)
        status_hint
        view.invalidate
      end
    end

    def onCancel(reason, view)
      @state = :idle
      @handle = :none
      @drag_origin = nil
      @drag_origin_mm = nil
      @drag_start_model = nil
      @drag_preview_model = nil
      @drag_reference = nil
      @drag_plane_z = nil
      @drag_point_origin = nil
      @locked_axis = nil
      Sketchup.status_text = 'MMA Edit Wall Tool: ready.'
      view.invalidate
    end

    def onKeyDown(key, repeat, flags, view)
      return unless @group && @group.valid?

      case key
      when 84, 116 # T
        cycle_wall_preset
      when 74, 106 # J
        cycle_justification
      when 70, 102 # F
        flip_selected_wall
      when 72, 104 # H
        toggle_height_handle_mode
      else
        return
      end

      view.invalidate
    end

    def draw(view)
      return unless @group && @group.valid?

      wall_model = @drag_preview_model || WallModel.from_group(@group)
      return unless wall_model

      points = wall_model.path_points || [wall_model.start_point, wall_model.end_point]
      if wall_model.path_points
        draw_path_preview(view, wall_model)
      end
      draw_ghost_wall(view, wall_model, points) if @state == :dragging

      wall_handles(wall_model).each do |handle|
        if handle[:name] == :vertex
          active_vertex = @handle.is_a?(Hash) && @handle[:name] == :vertex &&
                          @handle[:index] == handle[:index]
          point_color = active_vertex ? inference_color(@locked_axis) : Sketchup::Color.new(0, 220, 255)
          view.draw_points([handle[:point]], 17, 1, Sketchup::Color.new(20, 35, 45))
          view.draw_points([handle[:point]], 11, 1, point_color)
          next
        end
        color = case handle[:name]
                when :wall then Sketchup::Color.new(150, 0, 200)
                when :layer_start, :layer_end then Sketchup::Color.new(255, 140, 0)
                when :vertex then Sketchup::Color.new(0, 220, 255)
                else Sketchup::Color.new(0, 170, 0)
                end
        view.draw_points([handle[:point]], 11, 1, color)
      end

      @input.draw(view) if @state == :dragging && @input.valid?
      draw_drag_inference(view, wall_model) if @state == :dragging && @drag_point_origin

      unless wall_model.path_points
        world_points = points.map { |point| point_in_model_units(point) }
        view.draw(GL_LINE_STRIP, world_points)
      end
    end

    private

    # Asks for thickness and material of each layer in the segment under the
    # cursor, and stores them as that segment's overrides.
    def edit_segment_layers(group, wall_model)
      # WallModel.from_group returns world coordinates, so compare in world space.
      point = @input.position
      segment = if wall_model.arc?
                  0
                else
                  SegmentLayers.nearest_segment(wall_model.path_points,
                                                GeometryHelper.to_mm(point.x),
                                                GeometryHelper.to_mm(point.y),
                                                wall_model.path_closed?)
                end
      return unless segment

      params = wall_model.params
      full = WallBuilder.wall_layers(params)
      active = WallBuilder.active_layer_indices(params)
      stack = WallBuilder.stack_for(params, segment, active)
      choices = (DefaultMaterials::PALETTE.keys + stack.map { |layer| layer['material'].to_s }).uniq.reject(&:empty?)

      prompts = []
      defaults = []
      lists = []
      stack.each_with_index do |layer, index|
        prompts << "#{index + 1}. #{layer['name']} - thickness (mm)"
        defaults << layer['thickness'].to_f.round(2).to_s
        lists << ''
        prompts << "#{index + 1}. #{layer['name']} - material"
        defaults << layer['material'].to_s
        lists << choices.join('|')
      end
      answers = UI.inputbox(prompts, defaults, lists, "Segment #{segment + 1} layers (mm)")
      return unless answers

      new_stack = stack.each_with_index.map do |layer, index|
        thickness = Float(answers[index * 2].to_s.strip, exception: false)
        if thickness.nil? || thickness.negative?
          UI.messagebox("Layer #{index + 1}: thickness must be a number of zero or more.")
          return
        end
        material = answers[(index * 2) + 1].to_s.strip
        material = layer['material'] if material.empty?
        { 'thickness' => thickness, 'material' => material }
      end

      SegmentLayers.store(params, segment, full, active, new_stack)
      WallBuilder.rebuild_wall_from_model(Sketchup.active_model, group, WallModel.new(params))
      WallJoiner.refresh_adjacent_joins(Sketchup.active_model, group)
      Sketchup.status_text = "MMA Edit Wall Tool: segment #{segment + 1} layers updated."
    rescue StandardError => error
      UI.messagebox("Could not edit segment layers: #{error.message}")
    end

    def pick_wall_group
      model = Sketchup.active_model
      return nil unless model

      model.selection.grep(Sketchup::Group).find { |g| WallModel.valid_wall_group?(g) }
    end

    def wall_group_at(view, x, y)
      helper = view.pick_helper
      helper.do_pick(x, y)
      helper.count.times do |index|
        path = helper.path_at(index)
        next unless path

        group = path.grep(Sketchup::Group).reverse.find { |item| WallModel.valid_wall_group?(item) }
        return group if group
      end
      nil
    end

    def pick_wall_group_from_selection
      model = Sketchup.active_model
      return nil unless model

      model.selection.grep(Sketchup::Group).find { |g| WallModel.valid_wall_group?(g) }
    end

    def detect_handle_state(view, x, y, wall_model)
      handles = wall_handles(wall_model)
      handles.each do |handle|
        screen_point = view.screen_coords(handle[:point])
        distance = Math.sqrt((screen_point.x - x)**2 + (screen_point.y - y)**2)
        return handle if distance <= HANDLE_RADIUS
      end
      :none
    end

    def wall_handles(wall_model)
      if wall_model.arc?
        # Curved walls can be moved and resized; their vertices are not editable yet.
        centre = wall_model.midpoint
        height_point = centre.dup
        height_point[2] += 300.0
        return [
          { name: :wall, point: point_in_model_units(centre) },
          { name: :height, point: point_in_model_units(height_point) }
        ]
      end

      points = wall_model.path_points
      if points && points.length >= 2
        handles = points.each_with_index.map do |point, index|
          { name: :vertex, index: index, point: point_in_model_units(point) }
        end
        center = wall_model.midpoint
        handles << { name: :wall, point: point_in_model_units(center) }
        height_point = center.dup
        height_point[2] += 300.0
        handles << { name: :height, point: point_in_model_units(height_point) }
        handles.concat(layer_end_handles(wall_model, points)) unless wall_model.path_closed?
        return handles
      end

      start_point = point_in_model_units(wall_model.start_point)
      end_point = point_in_model_units(wall_model.end_point)
      mid_point = point_in_model_units(wall_model.midpoint)
      height_point = point_in_model_units([
        wall_model.midpoint[0],
        wall_model.midpoint[1],
        wall_model.midpoint[2] + 300.0
      ])

      [
        { name: :start, point: start_point },
        { name: :end, point: end_point },
        { name: :mid, point: mid_point },
        { name: :height, point: height_point }
      ]
    end

    def layer_end_handles(wall_model, points)
      layer_specs = WallBuilder.wall_layers(wall_model.params).each_with_index.select do |layer, _index|
        layer['enabled'] != false && layer['thickness'].to_f > 0.001
      end
      return [] if layer_specs.empty?

      total = layer_specs.sum { |layer, _index| layer['thickness'].to_f }
      base = WallBuilder.alignment_offset(wall_model.justification, total)
      start_direction = unit_direction(points[0], points[1])
      end_direction = unit_direction(points[-2], points[-1])
      start_extensions = Array(wall_model.params['layer_start_extensions'])
      end_extensions = Array(wall_model.params['layer_end_extensions'])
      handles = []
      offset = base
      layer_specs.each do |layer, index|
        middle = offset + layer['thickness'].to_f / 2.0
        start = points.first
        finish = points.last
        handles << {
          name: :layer_start,
          layer: index,
          point: point_in_model_units([
            start[0] - start_direction[0] * start_extensions[index].to_f - start_direction[1] * middle,
            start[1] - start_direction[1] * start_extensions[index].to_f + start_direction[0] * middle,
            start[2]
          ])
        }
        handles << {
          name: :layer_end,
          layer: index,
          point: point_in_model_units([
            finish[0] + end_direction[0] * end_extensions[index].to_f - end_direction[1] * middle,
            finish[1] + end_direction[1] * end_extensions[index].to_f + end_direction[0] * middle,
            finish[2]
          ])
        }
        offset += layer['thickness'].to_f
      end
      handles
    end

    def unit_direction(start_point, end_point)
      dx = end_point[0] - start_point[0]
      dy = end_point[1] - start_point[1]
      length = Math.sqrt(dx * dx + dy * dy)
      length <= 0.001 ? [1.0, 0.0] : [dx / length, dy / length]
    end

    def pick_drag_input(view, x, y)
      if @state == :dragging && @drag_reference
        @input.pick(view, x, y, @drag_reference)
      else
        @input.pick(view, x, y)
      end
    end

    def drag_position(position)
      unless planar_handle?
        @locked_axis = (@handle == :height) ? :blue : nil
        @locked_direction = nil
        return position
      end

      origin = @drag_origin
      point = Geom::Point3d.new(position.x, position.y, GeometryHelper.mm(@drag_plane_z))
      dx = point.x - origin.x
      dy = point.y - origin.y
      distance = Math.sqrt((dx * dx) + (dy * dy))
      if distance <= 0.001
        @locked_axis = nil
        @locked_direction = nil
        return point
      end

      axes = Sketchup.active_model.axes
      axis_candidates = [
        [:red, axes.xaxis.x.to_f, axes.xaxis.y.to_f],
        [:green, axes.yaxis.x.to_f, axes.yaxis.y.to_f]
      ]
      candidates = axis_candidates.filter_map do |name, axis_x, axis_y|
        snap_candidate(name, axis_x, axis_y, dx, dy, distance)
      end
      wall_direction_candidates.each do |axis_x, axis_y|
        candidate = snap_candidate(:wall, axis_x, axis_y, dx, dy, distance)
        candidates << candidate if candidate
      end
      candidate = candidates.min_by(&:first)
      unless candidate
        @locked_axis = nil
        @locked_direction = nil
        return point
      end

      _angle, @locked_axis, axis_x, axis_y, projection = candidate
      @locked_direction = [axis_x, axis_y]
      Geom::Point3d.new(
        origin.x + axis_x * projection,
        origin.y + axis_y * projection,
        GeometryHelper.mm(@drag_plane_z)
      )
    end

    def planar_handle?
      handle_name = @handle.is_a?(Hash) ? @handle[:name] : @handle
      %i[vertex start end layer_start layer_end].include?(handle_name)
    end

    def snap_candidate(name, axis_x, axis_y, dx, dy, distance)
      axis_length = Math.sqrt((axis_x * axis_x) + (axis_y * axis_y))
      return if axis_length <= 0.001

      axis_x /= axis_length
      axis_y /= axis_length
      projection = dx * axis_x + dy * axis_y
      angle = Math.acos([[projection.abs / distance, 1.0].min, -1.0].max)
      return if angle > AXIS_SNAP_ANGLE

      [angle, name, axis_x, axis_y, projection]
    end

    def wall_direction_candidates
      return [] unless @drag_start_model

      points = @drag_start_model.path_points
      return straight_wall_direction if !points || points.length < 2

      index = @handle.is_a?(Hash) && @handle[:name] == :vertex ? @handle[:index] : nil
      candidates = []
      if index && (index.positive? || @drag_start_model.path_closed?)
        previous_index = (index - 1) % points.length
        candidates << unit_direction(points[previous_index], points[index])
      end
      if index && (index < points.length - 1 || @drag_start_model.path_closed?)
        next_index = (index + 1) % points.length
        candidates << unit_direction(points[index], points[next_index])
      end
      candidates.reject { |direction| direction.nil? }
    end

    def straight_wall_direction
      start_point = @drag_start_model.start_point
      end_point = @drag_start_model.end_point
      return [] unless start_point && end_point

      [unit_direction(start_point, end_point)]
    end

    def draw_path_preview(view, wall_model)
      preview_points = wall_model.path_points
      return unless preview_points && preview_points.length >= 2

      height_offset = wall_model.height + 3.0
      preview_vertices = preview_points.map do |point|
        point_in_model_units([point[0], point[1], point[2] + height_offset])
      end
      primitive = wall_model.path_closed? ? GL_LINE_LOOP : GL_LINE_STRIP

      if @state == :dragging && @drag_start_model
        original_vertices = @drag_start_model.path_points.map do |point|
          point_in_model_units([point[0], point[1], point[2] + height_offset - 2.0])
        end
        view.drawing_color = Sketchup::Color.new(255, 95, 35, 220)
        view.line_width = 2
        view.draw(primitive, original_vertices)
      end

      view.drawing_color = Sketchup::Color.new(15, 30, 45, 230)
      view.line_width = 8
      view.draw(primitive, preview_vertices)
      view.drawing_color = Sketchup::Color.new(0, 225, 255, 255)
      view.line_width = 4
      view.draw(primitive, preview_vertices)
      view.drawing_color = Sketchup::Color.new(0, 0, 0)
      view.line_width = 1
    end

    def dragged_point_origin(wall_model, handle)
      return nil unless handle.is_a?(Hash)

      points = wall_model.path_points
      point = case handle[:name]
              when :vertex then points && points[handle[:index]]
              when :start then wall_model.start_point
              when :end then wall_model.end_point
              end
      point && point_in_model_units([point[0], point[1], @drag_plane_z])
    end

    def draw_drag_inference(view, wall_model)
      point = preview_drag_point(wall_model)
      return unless point

      color = inference_color(@locked_axis)
      view.line_stipple = '.'
      view.line_width = 2
      view.drawing_color = color
      view.draw(GL_LINES, [@drag_point_origin, point])

      if @locked_axis
        direction = Geom::Vector3d.new(@locked_direction[0], @locked_direction[1], 0) if @locked_direction
        if direction && direction.length > 0.001
          direction.normalize!
          extent = GeometryHelper.mm(5000.0)
          guide_start = @drag_point_origin.offset(direction, -extent)
          guide_end = @drag_point_origin.offset(direction, extent)
          view.draw(GL_LINES, [guide_start, guide_end])
        end
      end
      view.line_stipple = ''
      view.line_width = 1
      view.drawing_color = Sketchup::Color.new(0, 0, 0)
    end

    def preview_drag_point(wall_model)
      points = wall_model.path_points
      handle_name = @handle.is_a?(Hash) ? @handle[:name] : @handle
      if handle_name == :vertex && points
        point_in_model_units(points[@handle[:index]])
      elsif handle_name == :start
        point_in_model_units(wall_model.start_point)
      elsif handle_name == :end
        point_in_model_units(wall_model.end_point)
      end
    end

    def inference_color(axis)
      case axis
      when :red then Sketchup::Color.new(255, 0, 0)
      when :green then Sketchup::Color.new(0, 180, 0)
      when :blue then Sketchup::Color.new(0, 80, 255)
      when :wall then Sketchup::Color.new(190, 70, 255)
      else Sketchup::Color.new(255, 255, 255)
      end
    end

    def draw_ghost_wall(view, wall_model, points)
      return unless points && points.length >= 2

      segment_count = wall_model.path_closed? ? points.length : points.length - 1
      directions = segment_count.times.map do |index|
        start_point = points[index]
        end_point = points[(index + 1) % points.length]
        unit_direction(start_point, end_point)
      end
      layers = WallBuilder.wall_layers(wall_model.params).select do |layer|
        layer['enabled'] != false && layer['thickness'].to_f > 0.001
      end
      return if layers.empty?
      total_thickness = layers.sum { |layer| layer['thickness'].to_f }
      offset = WallBuilder.alignment_offset(wall_model.justification, total_thickness)
      max_miter = total_thickness * 4.0
      height = wall_model.height
      path_length = segment_count.times.sum do |index|
        WallBuilder.point_distance_2d(points[index], points[(index + 1) % points.length])
      end
      layers.each do |layer|
        thickness = layer['thickness'].to_f
        quads = []
        cumulative_distance = 0.0
        segment_count.times do |index|
          next_index = (index + 1) % points.length
          start_point = points[index]
          end_point = points[next_index]
          direction = directions[index]
          length = WallBuilder.point_distance_2d(start_point, end_point)
          openings = WallBuilder.path_openings_for_segment(
            wall_model.params,
            cumulative_distance,
            length,
            path_length,
            wall_model.path_closed?
          )
          patches = WallBuilder.wall_patches(length, height, openings)
          low_start = WallBuilder.path_offset_point(points, directions, index, offset, offset, wall_model.path_closed?, max_miter)
          low_end = WallBuilder.path_offset_point(points, directions, next_index, offset, offset, wall_model.path_closed?, max_miter)
          high_start = WallBuilder.path_offset_point(points, directions, index, offset + thickness, offset + thickness, wall_model.path_closed?, max_miter)
          high_end = WallBuilder.path_offset_point(points, directions, next_index, offset + thickness, offset + thickness, wall_model.path_closed?, max_miter)
          patches.each do |left, right, bottom_height, top_height|
            low_left = left <= 0.001 ? low_start : WallBuilder.path_station_point(start_point, direction, offset, left)
            low_right = right >= length - 0.001 ? low_end : WallBuilder.path_station_point(start_point, direction, offset, right)
            high_right = right >= length - 0.001 ? high_end : WallBuilder.path_station_point(start_point, direction, offset + thickness, right)
            high_left = left <= 0.001 ? high_start : WallBuilder.path_station_point(start_point, direction, offset + thickness, left)
            footprint = [low_left, low_right, high_right, high_left]
            lower = footprint.map { |point| [point[0], point[1], point[2] + bottom_height] }
            upper = footprint.map { |point| [point[0], point[1], point[2] + top_height] }
            quads.concat([lower, upper])
            4.times do |edge|
              next_edge = (edge + 1) % 4
              quads << [lower[edge], lower[next_edge], upper[next_edge], upper[edge]]
            end
          end
          cumulative_distance += length
        end
        color = DefaultMaterials::PALETTE[layer['material']] || [55, 145, 225]
        view.drawing_color = Sketchup::Color.new(color[0], color[1], color[2], PREVIEW_ALPHA)
        unless quads.empty?
          view.draw(GL_QUADS, quads.flatten(1).map { |point| point_in_model_units(point) })
        end
        offset += thickness
      end
      view.drawing_color = Sketchup::Color.new(0, 0, 0)
    end

    def dragged_model(position)
      return unless @drag_start_model && @drag_origin && @drag_origin_mm

      wall_model = WallModel.new(JSON.parse(JSON.generate(@drag_start_model.params)))
      current_in = position
      current_mm = [GeometryHelper.to_mm(current_in.x), GeometryHelper.to_mm(current_in.y), GeometryHelper.to_mm(current_in.z)]
      delta_x = current_mm[0] - @drag_origin_mm[0]
      delta_y = current_mm[1] - @drag_origin_mm[1]
      delta_z = current_mm[2] - @drag_origin_mm[2]

      case @handle
      when Hash
        case @handle[:name]
        when :vertex
          points = wall_model.path_points
          points.each { |path_point| path_point[2] = @drag_plane_z }
          point = points[@handle[:index]]
          points[@handle[:index]] = [point[0] + delta_x, point[1] + delta_y, @drag_plane_z]
          wall_model.set_path_points(points)
        when :wall
          wall_model.move(delta_x, delta_y, 0.0)
        when :height
          wall_model.set_height(wall_model.height + delta_z)
        when :start
          start_point = wall_model.start_point
          end_point = wall_model.end_point
          wall_model.set_start_point([start_point[0] + delta_x, start_point[1] + delta_y, @drag_plane_z])
          wall_model.set_end_point([end_point[0], end_point[1], @drag_plane_z])
        when :end
          end_point = wall_model.end_point
          start_point = wall_model.start_point
          wall_model.set_end_point([end_point[0] + delta_x, end_point[1] + delta_y, @drag_plane_z])
          wall_model.set_start_point([start_point[0], start_point[1], @drag_plane_z])
        when :mid
          wall_model.move(delta_x, delta_y, 0.0)
        when :layer_start, :layer_end
          points = wall_model.path_points
          start_point, end_point = @handle[:name] == :layer_start ? points[0, 2] : points[-2, 2]
          direction = unit_direction(start_point, end_point)
          projected_delta = delta_x * direction[0] + delta_y * direction[1]
          projected_delta *= -1.0 if @handle[:name] == :layer_start
          key = @handle[:name] == :layer_start ? 'layer_start_extensions' : 'layer_end_extensions'
          extensions = Array(wall_model.params[key])
          endpoint_pair = @handle[:name] == :layer_start ? points[0, 2] : points[-2, 2]
          segment_length = Math.sqrt((endpoint_pair[1][0] - endpoint_pair[0][0])**2 +
                                     (endpoint_pair[1][1] - endpoint_pair[0][1])**2)
          minimum_extension = -0.9 * segment_length
          next_extension = [extensions[@handle[:layer]].to_f + projected_delta, minimum_extension].max
          wall_model.set_layer_extension(@handle[:name], @handle[:layer], next_extension)
        end
      when :start
        end_point = wall_model.end_point
        wall_model.set_start_point([
          wall_model.start_point[0] + delta_x,
          wall_model.start_point[1] + delta_y,
          @drag_plane_z
        ])
        wall_model.set_end_point([end_point[0], end_point[1], @drag_plane_z])
      when :end
        start_point = wall_model.start_point
        wall_model.set_end_point([
          wall_model.end_point[0] + delta_x,
          wall_model.end_point[1] + delta_y,
          @drag_plane_z
        ])
        wall_model.set_start_point([start_point[0], start_point[1], @drag_plane_z])
      when :mid
        wall_model.move(delta_x, delta_y, 0.0)
      when :height
        wall_model.set_height(wall_model.height + delta_z)
      end
      wall_model
    end

    def apply_drag(position)
      return unless @group && @group.valid?

      wall_model = dragged_model(position)
      return unless wall_model
      return if JSON.generate(wall_model.params) == JSON.generate(@drag_start_model.params)

      WallBuilder.rebuild_wall_from_model(Sketchup.active_model, @group, wall_model)
    end

    def cycle_wall_preset
      return unless @group && @group.valid?

      wall_model = WallModel.from_group(@group)
      return unless wall_model

      presets = WallPresets::ALL
      @preset_index = (@preset_index + 1) % presets.length
      new_preset = presets[@preset_index]
      wall_model.apply_preset(new_preset)
      wall_model.save_to_group(@group)
      WallBuilder.rebuild_wall_from_model(Sketchup.active_model, @group, wall_model)
      Sketchup.status_text = "MMA Edit Wall Tool: wall type changed to #{new_preset}."
    end

    def cycle_justification
      return unless @group && @group.valid?

      wall_model = WallModel.from_group(@group)
      return unless wall_model

      current = wall_model.justification
      next_index = (WallJustification::ALL.index(current) || 0) + 1
      next_index = 0 if next_index >= WallJustification::ALL.length
      wall_model.set_justification(WallJustification::ALL[next_index])
      wall_model.save_to_group(@group)
      WallBuilder.rebuild_wall_from_model(Sketchup.active_model, @group, wall_model)
      Sketchup.status_text = "MMA Edit Wall Tool: justification = #{wall_model.justification}."
    end

    def flip_selected_wall
      return unless @group && @group.valid?

      wall_model = WallModel.from_group(@group)
      return unless wall_model

      wall_model.flip_direction
      wall_model.save_to_group(@group)
      WallBuilder.rebuild_wall_from_model(Sketchup.active_model, @group, wall_model)
      Sketchup.status_text = 'MMA Edit Wall Tool: wall direction flipped.'
    end

    def toggle_height_handle_mode
      return unless @group && @group.valid?

      @handle = (@handle == :height) ? :none : :height
      Sketchup.status_text = (@handle == :height) ? 'MMA Edit Wall Tool: height handle active.' : 'MMA Edit Wall Tool: height handle inactive.'
    end

    def point_in_model_units(point_mm)
      Geom::Point3d.new(GeometryHelper.mm(point_mm[0]), GeometryHelper.mm(point_mm[1]), GeometryHelper.mm(point_mm[2]))
    end

    def distance_2d(a, b)
      dx = a.x - b.x
      dy = a.y - b.y
      Math.sqrt((dx * dx) + (dy * dy))
    end

    def status_for_state(handle)
      handle = handle[:name] if handle.is_a?(Hash)
      case handle
      when :vertex
        'MMA Edit Wall Tool: dragging path vertex.'
      when :wall, :mid
        'MMA Edit Wall Tool: moving whole wall.'
      when :layer_start
        'MMA Edit Wall Tool: extending layer at start.'
      when :layer_end
        'MMA Edit Wall Tool: extending layer at end.'
      when :start
        'MMA Edit Wall Tool: dragging wall start point.'
      when :end
        'MMA Edit Wall Tool: dragging wall end point.'
      when :mid
        'MMA Edit Wall Tool: dragging wall length.'
      when :height
        'MMA Edit Wall Tool: dragging wall height.'
      else
        'MMA Edit Wall Tool: ready.'
      end
    end
  end
end
