# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Edit Wall Points Tool
# Select a Euro Wall, then drag its handles in the model:
#   Green  - start / end corner. Joined walls that share the corner follow it.
#   Purple - whole wall. Both ends move; joined walls follow.
#   Orange - one layer's start or end (extends or shortens that layer).
# Double-click a wall to open its Assembly dialog.
# Esc deselects; with nothing selected, Esc exits the tool.
# ==============================================================================

require 'json'
require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_builder'
require_relative '../ui/dialog_manager'

module EuroWallSlab
  class EditWallTool
    ANCHOR_PIXELS = 12
    MOVE_TOL_MM   = 0.5
    POINT_TOL_MM  = 1.0
    POINT_KEYS    = %w[start_point end_point prev_corner_point next_corner_point].freeze

    COLOR_SELECTED = [41, 128, 185]
    COLOR_PREVIEW  = [230, 126, 34]
    COLOR_HOVER    = [127, 140, 141]
    ANCHOR_COLORS  = { vertex: [46, 204, 113], wall: [150, 0, 200], layer: [255, 140, 0] }.freeze

    def initialize(group = nil)
      @ip = Sketchup::InputPoint.new
      @initial_group = group
      @draw_error_shown = false
      @hover = nil
      reset_selection
    end

    def activate
      @drag = nil
      @hover = nil
      select_group(@initial_group) if @initial_group && @initial_group.valid?
      @initial_group = nil
      update_status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      safe do
        sync
        if @drag
          target = pick_target(view, x, y, @drag[:anchor][:pos][2])
          @drag[:target] = target if target
        elsif @group.nil?
          @hover = pick_wall(view, x, y)
        end
        view.invalidate
      end
    end

    def onLButtonDown(_flags, x, y, view)
      safe do
        sync
        anchor = @group ? hit_anchor(view, x, y) : nil
        if anchor
          start = pick_target(view, x, y, anchor[:pos][2])
          @drag = { anchor: anchor, start: start, target: start } if start
        else
          group = pick_wall(view, x, y)
          if group
            select_group(group)
          else
            reset_selection
          end
        end
        update_status
        view.invalidate
      end
    end

    def onLButtonUp(_flags, x, y, view)
      safe do
        if @drag
          drag = @drag
          @drag = nil
          target = pick_target(view, x, y, drag[:anchor][:pos][2])
          drag[:target] = target if target
          apply_drag(drag) if moved?(drag)
        end
        update_status
        view.invalidate
      end
    end

    def onLButtonDoubleClick(_flags, x, y, view)
      safe do
        group = pick_wall(view, x, y)
        if group
          select_group(group)
          DialogManager.show_wall_dialog(group)
        end
        view.invalidate
      end
    end

    def onCancel(_reason, view)
      safe do
        if @group || @drag
          reset_selection
          update_status
          view.invalidate
        else
          Sketchup.active_model.select_tool(nil)
        end
      end
    end

    def draw(view)
      guard_draw do
        if @group && @params
          draw_outline(view, preview_params(@drag), COLOR_PREVIEW) if @drag
          draw_outline(view, @params, COLOR_SELECTED)
          draw_anchors(view)
        elsif @hover && @hover.valid?
          draw_outline(view, read_params(@hover), COLOR_HOVER)
        end
      end
    end

    private

    # ---------------------------------------------------------------- selection

    def reset_selection
      @group = nil
      @params = nil
      @anchors = []
      @drag = nil
    end

    def select_group(group)
      params = read_params(group)
      if params.nil?
        reset_selection
        return
      end
      @group = group
      @params = params
      @anchors = build_anchors(params)
      @hover = nil
    end

    # Re-reads the selected wall so handles always match the stored geometry
    def sync
      return unless @group

      params = @group.valid? ? read_params(@group) : nil
      if params
        @params = params
        @anchors = build_anchors(params)
      else
        reset_selection
      end
    end

    def read_params(group)
      return nil unless group && group.valid?

      raw = group.get_attribute(DICT_NAME, ATTR_DATA)
      raw ? JSON.parse(raw) : nil
    rescue JSON::ParserError
      nil
    end

    def pick_wall(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i) || []
        group = path.find { |e| e.is_a?(Sketchup::Group) && e.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall' }
        return group if group
      end
      nil
    end

    # Picked model position as mm, keeping the anchor's height
    def pick_target(view, x, y, z_mm)
      @ip.pick(view, x, y)
      return nil unless @ip.valid?

      pos = @ip.position
      [GeometryHelper.to_mm(pos.x), GeometryHelper.to_mm(pos.y), z_mm]
    end

    def moved?(drag)
      a = drag[:start]
      b = drag[:target]
      Math.hypot(b[0] - a[0], b[1] - a[1]) >= MOVE_TOL_MM
    end

    # ------------------------------------------------------------------ handles

    # Anchor positions in mm. Vertex = corner of the baseline, wall = midpoint,
    # layer = that layer's ends at its mid height (offset by its extension).
    def build_anchors(params)
      s = params['start_point']
      e = params['end_point']
      frame = frame_of(s, e)
      return [] unless frame

      vx, vy = frame
      anchors = []
      anchors << { kind: :vertex, which: :start, pos: s }
      anchors << { kind: :vertex, which: :end, pos: e }
      anchors << { kind: :wall, pos: [(s[0] + e[0]) / 2.0, (s[1] + e[1]) / 2.0, s[2]] }

      WallBuilder.layer_stack(params).each do |row|
        next if row[:side] == 'core'

        layer = params["#{row[:side]}_layers"][row[:index]]
        ymid = (row[:y1] + row[:y2]) / 2.0
        base_s = offset(s, vy, ymid)
        base_e = offset(e, vy, ymid)
        anchors << { kind: :layer_start, side: row[:side], index: row[:index], pos: offset(base_s, vx, -layer['ext_start'].to_f) }
        anchors << { kind: :layer_end, side: row[:side], index: row[:index], pos: offset(base_e, vx, layer['ext_end'].to_f) }
      end
      anchors
    end

    def hit_anchor(view, x, y)
      best = nil
      best_score = nil
      @anchors.each do |a|
        sp = view.screen_coords(to_pt(a[:pos]))
        dist = Math.hypot(sp.x - x, sp.y - y)
        next if dist > ANCHOR_PIXELS

        # Corner and whole-wall handles win over layer handles when they overlap
        priority = (a[:kind] == :layer_start || a[:kind] == :layer_end) ? 1 : 0
        score = [priority, dist]
        if best_score.nil? || (score <=> best_score) < 0
          best = a
          best_score = score
        end
      end
      best
    end

    # ------------------------------------------------------------------ editing

    def apply_drag(drag)
      sync
      return unless @group

      anchor = drag[:anchor]
      case anchor[:kind]
      when :vertex
        move_point(anchor[:pos], drag[:target])
      when :wall
        dx = drag[:target][0] - drag[:start][0]
        dy = drag[:target][1] - drag[:start][1]
        s = @params['start_point']
        e = @params['end_point']
        move_point(s, shift(s, dx, dy))
        move_point(e, shift(e, dx, dy))
      else
        params = read_params(@group)
        layer_hash(params, anchor)[layer_key(anchor)] = layer_ext_value(params, anchor, drag[:target])
        WallBuilder.build(Sketchup.active_model, params, @group)
      end
      sync
    end

    # Moves every wall endpoint that sits on old_pt to new_pt. Walls that share
    # the corner are rebuilt so their joints stay closed.
    def move_point(old_pt, new_pt)
      model = Sketchup.active_model
      walls_in(model).each do |group|
        params = read_params(group)
        next unless params

        changed = false
        POINT_KEYS.each do |key|
          pt = params[key]
          next unless pt && same_point?(pt, old_pt)

          params[key] = [new_pt[0], new_pt[1], new_pt[2]]
          changed = true
        end
        next unless changed

        s = params['start_point']
        e = params['end_point']
        next if Math.hypot(e[0] - s[0], e[1] - s[1]) < POINT_TOL_MM

        WallBuilder.build(model, params, group)
      end
    end

    def walls_in(model)
      groups = (model.entities.to_a + model.active_entities.to_a).grep(Sketchup::Group).uniq
      groups.select { |g| g.valid? && g.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall' }
    end

    # Copy of the selected wall's parameters with the dragged change applied (preview only)
    def preview_params(drag)
      params = JSON.parse(@params.to_json)
      anchor = drag[:anchor]
      case anchor[:kind]
      when :vertex
        params[anchor[:which] == :start ? 'start_point' : 'end_point'] = drag[:target]
      when :wall
        dx = drag[:target][0] - drag[:start][0]
        dy = drag[:target][1] - drag[:start][1]
        params['start_point'] = shift(params['start_point'], dx, dy)
        params['end_point'] = shift(params['end_point'], dx, dy)
      else
        layer_hash(params, anchor)[layer_key(anchor)] = layer_ext_value(params, anchor, drag[:target])
      end
      params
    end

    def layer_hash(params, anchor)
      params["#{anchor[:side]}_layers"][anchor[:index]]
    end

    def layer_key(anchor)
      anchor[:kind] == :layer_start ? 'ext_start' : 'ext_end'
    end

    # Extension (mm) that puts the layer end under the cursor. Clamped so the layer
    # cannot be shortened past 90% of the wall length.
    def layer_ext_value(params, anchor, target)
      s = params['start_point']
      e = params['end_point']
      frame = frame_of(s, e)
      return 0.0 unless frame

      vx = frame[0]
      len = Math.hypot(e[0] - s[0], e[1] - s[1])
      raw = if anchor[:kind] == :layer_start
              -((target[0] - s[0]) * vx[0] + (target[1] - s[1]) * vx[1])
            else
              (target[0] - e[0]) * vx[0] + (target[1] - e[1]) * vx[1]
            end
      raw.clamp(-0.9 * len, 1.0e6)
    end

    # ----------------------------------------------------------------- drawing

    def draw_outline(view, params, rgb)
      return unless params

      pts = footprint(params)
      return unless pts

      view.drawing_color = Sketchup::Color.new(*rgb)
      view.line_width = 2
      view.draw(GL_LINE_LOOP, pts.map { |p| to_pt(p) })
      view.draw(GL_LINES, [to_pt(params['start_point']), to_pt(params['end_point'])])
    end

    def draw_anchors(view)
      @anchors.each do |a|
        key = if a[:kind] == :wall
                :wall
              elsif a[:kind] == :vertex
                :vertex
              else
                :layer
              end
        view.draw_points([to_pt(a[:pos])], 10, 2, Sketchup::Color.new(*ANCHOR_COLORS[key]))
      end
    end

    # Four corners of the wall's full thickness, in mm
    def footprint(params)
      s = params['start_point']
      e = params['end_point']
      frame = frame_of(s, e)
      return nil unless frame

      stack = WallBuilder.layer_stack(params)
      lo = stack.map { |row| row[:y1] }.min || 0.0
      hi = stack.map { |row| row[:y2] }.max || 0.0
      vy = frame[1]
      [offset(s, vy, lo), offset(e, vy, lo), offset(e, vy, hi), offset(s, vy, hi)]
    end

    # ----------------------------------------------------------------- helpers

    # [unit direction, left normal] of the baseline in the XY plane, or nil
    def frame_of(s, e)
      dx = e[0] - s[0]
      dy = e[1] - s[1]
      len = Math.hypot(dx, dy)
      return nil if len < 1e-6

      vx = [dx / len, dy / len]
      [vx, [-vx[1], vx[0]]]
    end

    def offset(p, v, d)
      [p[0] + v[0] * d, p[1] + v[1] * d, p[2]]
    end

    def shift(p, dx, dy)
      [p[0] + dx, p[1] + dy, p[2]]
    end

    def same_point?(a, b)
      Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]) < POINT_TOL_MM
    end

    def to_pt(a)
      Geom::Point3d.new(GeometryHelper.mm(a[0]), GeometryHelper.mm(a[1]), GeometryHelper.mm(a[2]))
    end

    def update_status
      if @group&.valid?
        Sketchup.status_text = "Edit Wall Points '#{@group.name}': green = move corner (joined walls follow), " \
                               'purple = move whole wall, orange = extend one layer. ' \
                               'Click empty space or Esc to deselect. Double-click opens the Assembly dialog.'
      else
        Sketchup.status_text = 'Edit Wall Points: click a Euro Wall to select it. Esc exits the tool.'
      end
    end

    def safe
      yield
    rescue StandardError => e
      UI.messagebox("Edit Wall Points error:\n#{e.message}\n#{e.backtrace.first(3).join("\n")}")
    end

    def guard_draw
      yield
    rescue StandardError => e
      return if @draw_error_shown

      @draw_error_shown = true
      UI.messagebox("Edit Wall Points preview error:\n#{e.message}")
    end
  end
end
