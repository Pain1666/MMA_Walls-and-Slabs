# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Edit Wall Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/wall_object'
require_relative '../core/wall_builder'
require_relative '../core/wall_joiner'

module MMA_WallsAndSlabs
  class EditWallTool
    def initialize(group = nil)
      @group = group
      @state = :idle
      @input = Sketchup::InputPoint.new
      @drag_origin = nil
      @drag_params = nil
      @last_position = nil
    end

    def activate
      @group ||= pick_wall_group
      if @group && @group.valid?
        Sketchup.status_text = 'MMA Edit Wall Tool: drag start, end, or midpoint handles.'
      else
        Sketchup.status_text = 'MMA Edit Wall Tool: select a wall to edit.'
      end
    end

    def onMouseMove(flags, x, y, view)
      @input.pick(view, x, y)
      if @state != :idle && @drag_origin
        update_drag_from_position(@input.position)
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @input.pick(view, x, y)
      target = @group || pick_wall_group_from_selection
      return unless target && target.valid?

      @group = target
      @drag_origin = @input.position
      @drag_params = current_params.dup
      @state = detect_handle_state(@input.position)
      @last_position = @drag_origin
      Sketchup.status_text = status_for_state(@state)
      view.invalidate
    end

    def onLButtonUp(flags, x, y, view)
      @state = :idle
      @drag_origin = nil
      @drag_params = nil
      @last_position = nil
      Sketchup.status_text = 'MMA Edit Wall Tool: ready.'
      view.invalidate
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

    def current_params
      raw = @group.get_attribute(DICT_NAME, ATTR_DATA)
      return WallModel.default_params if raw.nil? || raw.to_s.strip.empty?

      begin
        JSON.parse(raw)
      rescue JSON::ParserError
        WallModel.default_params
      end
    end

    def detect_handle_state(position)
      return :idle unless @group && @group.valid?

      params = current_params
      p_start = normalize_point3d(params['start_point'])
      p_end = normalize_point3d(params['end_point'])
      handle_threshold = 50.0

      return :move_start if distance_in_xy(position, p_start) <= handle_threshold
      return :move_end if distance_in_xy(position, p_end) <= handle_threshold

      :move_mid
    end

    def update_drag_from_position(position)
      return unless @drag_params && @group && @group.valid?

      delta = position - @drag_origin
      params = @drag_params.dup
      p_start = normalize_point3d(params['start_point'])
      p_end = normalize_point3d(params['end_point'])

      case @state
      when :move_start
        params['start_point'] = [p_start[0] + delta.x, p_start[1] + delta.y, p_start[2]]
      when :move_end
        params['end_point'] = [p_end[0] + delta.x, p_end[1] + delta.y, p_end[2]]
      when :move_mid
        params['start_point'] = [p_start[0] + delta.x, p_start[1] + delta.y, p_start[2]]
        params['end_point'] = [p_end[0] + delta.x, p_end[1] + delta.y, p_end[2]]
      else
        return
      end

      @drag_origin = position
      @group.set_attribute(DICT_NAME, ATTR_DATA, JSON.generate(params))
      WallBuilder.build(Sketchup.active_model, params, @group)
      WallJoiner.refresh_adjacent_joins(Sketchup.active_model, @group)
    end

    def status_for_state(state)
      case state
      when :move_start
        'MMA Edit Wall Tool: dragging wall start point.'
      when :move_end
        'MMA Edit Wall Tool: dragging wall end point.'
      when :move_mid
        'MMA Edit Wall Tool: dragging wall length.'
      else
        'MMA Edit Wall Tool: ready.'
      end
    end

    def normalize_point3d(point)
      arr = Array(point).map { |value| value.to_f }
      arr = [arr[0] || 0.0, arr[1] || 0.0, arr[2] || 0.0]
      Geom::Point3d.new(arr[0], arr[1], arr[2])
    end

    def distance_in_xy(a, b)
      dx = a.x - b.x
      dy = a.y - b.y
      Math.sqrt((dx * dx) + (dy * dy))
    end
  end
end
