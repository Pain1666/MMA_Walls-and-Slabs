# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Edit Wall Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_object'
require_relative '../core/wall_builder'
require_relative '../core/wall_joiner'

module MMA_WallsAndSlabs
  class EditWallTool
    HANDLE_RADIUS = 60.0

    def initialize(group = nil)
      @group = group
      @state = :idle
      @handle = :none
      @input = Sketchup::InputPoint.new
      @drag_origin = nil
      @drag_origin_mm = nil
      @preset_index = 0
      @last_rebuild_signature = nil
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
      @input.pick(view, x, y)
      if @state != :idle && @drag_origin
        apply_drag(@input.position)
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @input.pick(view, x, y)
      target = @group || pick_wall_group_from_selection
      return unless target && target.valid?

      @group = target
      wall_model = WallModel.from_group(@group)
      return unless wall_model

      @handle = detect_handle_state(@input.position, wall_model)
      return if @handle == :none

      @state = :dragging
      @drag_origin = @input.position
      @drag_origin_mm = [GeometryHelper.to_mm(@drag_origin.x), GeometryHelper.to_mm(@drag_origin.y), GeometryHelper.to_mm(@drag_origin.z)]
      Sketchup.status_text = status_for_state(@handle)
      view.invalidate
    end

    def onLButtonUp(flags, x, y, view)
      return unless @group && @group.valid?

      if @state != :idle
        WallJoiner.refresh_adjacent_joins(Sketchup.active_model, @group)
      end

      @state = :idle
      @handle = :none
      @drag_origin = nil
      @drag_origin_mm = nil
      @last_rebuild_signature = nil
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

      wall_model = WallModel.from_group(@group)
      return unless wall_model

      color = Sketchup::Color.new(0, 255, 0)
      handles = wall_handles(wall_model)

      handles.each do |handle|
        point = handle[:point]
        view.draw_points([point], 8, color)
      end

      start_pt = point_in_model_units(wall_model.start_point)
      end_pt = point_in_model_units(wall_model.end_point)
      view.draw_line(start_pt, end_pt)
    end

    private

    def pick_wall_group
      model = Sketchup.active_model
      return nil unless model

      model.selection.grep(Sketchup::Group).find { |g| WallModel.valid_wall_group?(g) }
    end

    def pick_wall_group_from_selection
      model = Sketchup.active_model
      return nil unless model

      model.selection.grep(Sketchup::Group).find { |g| WallModel.valid_wall_group?(g) }
    end

    def detect_handle_state(position, wall_model)
      handles = wall_handles(wall_model)
      handles.each do |handle|
        return handle[:name] if distance_2d(position, handle[:point]) <= HANDLE_RADIUS
      end
      :none
    end

    def wall_handles(wall_model)
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

    def apply_drag(position)
      return unless @group && @group.valid? && @drag_origin && @drag_origin_mm

      wall_model = WallModel.from_group(@group)
      return unless wall_model

      current_in = position
      current_mm = [GeometryHelper.to_mm(current_in.x), GeometryHelper.to_mm(current_in.y), GeometryHelper.to_mm(current_in.z)]
      delta_x = current_mm[0] - @drag_origin_mm[0]
      delta_y = current_mm[1] - @drag_origin_mm[1]
      delta_z = current_mm[2] - @drag_origin_mm[2]

      case @handle
      when :start
        wall_model.set_start_point([
          wall_model.start_point[0] + delta_x,
          wall_model.start_point[1] + delta_y,
          wall_model.start_point[2] + delta_z
        ])
      when :end
        wall_model.set_end_point([
          wall_model.end_point[0] + delta_x,
          wall_model.end_point[1] + delta_y,
          wall_model.end_point[2] + delta_z
        ])
      when :mid
        wall_model.move(delta_x, delta_y, 0.0)
      when :height
        wall_model.set_height(wall_model.height + delta_z)
      end

      signature = [wall_model.start_point, wall_model.end_point, wall_model.height, @handle]
      if signature != @last_rebuild_signature
        wall_model.save_to_group(@group)
        WallBuilder.rebuild_wall_from_model(Sketchup.active_model, @group, wall_model)
        @last_rebuild_signature = signature
      end

      @drag_origin = current_in
      @drag_origin_mm = current_mm
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
      case handle
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
