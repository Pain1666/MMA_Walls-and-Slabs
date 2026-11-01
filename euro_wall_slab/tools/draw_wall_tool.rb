# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Multi-Point Wall Drawing Tool
# Features:
# - Full SketchUp Inference Snapping (Endpoints, Midpoints, Edges, Faces)
# - Arrow Key Axis Locking (Right = Red Axis, Left = Green Axis, Up = Blue Axis, Down = Unlock)
# - Colored Axis Inference Lines & Tooltips
# - 3D Semi-Transparent Holographic Preview with Mitered Corner Joints
# - VCB (Measurement Box) Typed Length Support
# - Loop Closing by Clicking Start Point
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_builder'

module EuroWallSlab
  class DrawWallTool
    # Virtual Key Codes
    VK_LEFT  = 37 # Green Axis
    VK_UP    = 38 # Blue Axis
    VK_RIGHT = 39 # Red Axis
    VK_DOWN  = 40 # Unlock

    def initialize
      @ip = Sketchup::InputPoint.new
      @ip_anchor = Sketchup::InputPoint.new
      @points = []
      @current_pt = nil
      @snap_to_start = false
      @locked_axis = nil # nil, :red, :green, :blue
    end

    def activate
      reset_tool
      update_status
      Sketchup.vcb_label = 'Length'
      Sketchup.vcb_value = ''
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    # --------------------------------------------------------------------------
    # Arrow Keys Axis Locking
    # --------------------------------------------------------------------------
    def onKeyDown(key, repeat, flags, view)
      case key
      when VK_RIGHT
        # Toggle Red Axis
        @locked_axis = (@locked_axis == :red) ? nil : :red
        update_status
        view.invalidate
      when VK_LEFT
        # Toggle Green Axis
        @locked_axis = (@locked_axis == :green) ? nil : :green
        update_status
        view.invalidate
      when VK_UP
        # Toggle Blue Axis
        @locked_axis = (@locked_axis == :blue) ? nil : :blue
        update_status
        view.invalidate
      when VK_DOWN
        # Unlock Axis
        @locked_axis = nil
        update_status
        view.invalidate
      end
    end

    def onMouseMove(flags, x, y, view)
      if @points.empty?
        @ip.pick(view, x, y)
        @current_pt = @ip.valid? ? @ip.position : nil
        view.tooltip = @ip.tooltip if @ip.valid?
      else
        # Use last point as inference anchor for native SketchUp alignment
        @ip_anchor.copy!(@ip) if @ip_anchor.valid? == false
        @ip.pick(view, x, y, @ip_anchor)
        return unless @ip.valid?

        raw_pt = @ip.position
        view.tooltip = @ip.tooltip

        # Apply Axis Lock if active
        last_pt = @points.last
        if @locked_axis
          axis_vec = case @locked_axis
                     when :red   then Geom::Vector3d.new(1, 0, 0)
                     when :green then Geom::Vector3d.new(0, 1, 0)
                     when :blue  then Geom::Vector3d.new(0, 0, 1)
                     end
          line = [last_pt, axis_vec]
          pt = raw_pt.project_to_line(line)
        else
          pt = raw_pt
        end

        # Check for loop closing snap (within 200 mm of start point)
        start_pt = @points.first
        dist_to_start = pt.distance(start_pt)

        if @points.length >= 2 && dist_to_start < GeometryHelper.mm(200.0)
          @current_pt = start_pt
          @snap_to_start = true
          Sketchup.status_text = 'Euro Wall Tool: Click to CLOSE wall loop'
          Sketchup.vcb_value = 'Close Loop'
        else
          @current_pt = pt
          @snap_to_start = false
          seg_len_mm = GeometryHelper.to_mm(last_pt.distance(pt)).round
          Sketchup.vcb_value = "#{seg_len_mm} mm"
          update_status
        end
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      return unless @current_pt

      if @points.empty?
        @points << @current_pt
        @ip_anchor.copy!(@ip)
        update_status
      else
        if @snap_to_start
          finish_walls(is_closed: true)
          reset_tool
        else
          if @current_pt.distance(@points.last) > GeometryHelper.mm(10.0)
            @points << @current_pt
            @ip_anchor.copy!(@ip)
            @locked_axis = nil # Release axis lock on commit
            update_status
          end
        end
      end
      view.invalidate
    end

    def onLButtonDoubleClick(flags, x, y, view)
      if @points.length >= 2
        finish_walls(is_closed: false)
        reset_tool
        view.invalidate
      end
    end

    def onReturn(view)
      if @points.length >= 2
        finish_walls(is_closed: false)
        reset_tool
        view.invalidate
      end
    end

    def onUserText(text, view)
      return if @points.empty? || @current_pt.nil?

      val = text.to_f
      return if val <= 1.0

      dist_in = GeometryHelper.mm(val)
      last_pt = @points.last

      dir = if @locked_axis
              case @locked_axis
              when :red   then Geom::Vector3d.new(1, 0, 0)
              when :green then Geom::Vector3d.new(0, 1, 0)
              when :blue  then Geom::Vector3d.new(0, 0, 1)
              end
            else
              d = (@current_pt - last_pt).normalize
              d.length < 0.001 ? Geom::Vector3d.new(1, 0, 0) : d
            end

      # Determine direction sign (+ or -)
      if (@current_pt - last_pt).dot(dir) < 0
        dir.reverse!
      end

      new_pt = last_pt + (dir.tap { |v| v.length = dist_in })
      @points << new_pt
      @current_pt = new_pt
      @ip_anchor.copy!(@ip)
      @locked_axis = nil

      update_status
      view.invalidate
    end

    def onCancel(reason, view)
      if @points.length > 1
        @points.pop
        @locked_axis = nil
        update_status
      else
        reset_tool
      end
      view.invalidate
    end

    # --------------------------------------------------------------------------
    # Preview & Inference Drawing
    # --------------------------------------------------------------------------
    def draw(view)
      @ip.draw(view) if @ip.valid?

      return if @points.empty? || @current_pt.nil?

      last_pt = @points.last

      # Draw Axis Lock Guideline if active
      if @locked_axis
        axis_color = case @locked_axis
                     when :red   then 'red'
                     when :green then 'green'
                     when :blue  then 'blue'
                     end
        axis_vec = case @locked_axis
                   when :red   then Geom::Vector3d.new(1, 0, 0)
                   when :green then Geom::Vector3d.new(0, 1, 0)
                   when :blue  then Geom::Vector3d.new(0, 0, 1)
                   end

        p_neg = last_pt - (axis_vec.clone.tap { |v| v.length = 10000.mm })
        p_pos = last_pt + (axis_vec.clone.tap { |v| v.length = 10000.mm })

        view.drawing_color = axis_color
        view.line_width = 1
        view.line_stipple = '-'
        view.draw_line(p_neg, p_pos)
        view.line_stipple = ''
      end

      # Build preview points chain
      preview_pts = @points.dup
      unless @snap_to_start && preview_pts.length >= 2
        preview_pts << @current_pt
      end

      # Render 3D Semi-Transparent Hologram
      draw_3d_preview(view, preview_pts, @snap_to_start)

      # Start point loop snap marker
      if @snap_to_start
        view.drawing_color = Sketchup::Color.new(46, 204, 113) # Green
        view.line_width = 4
        view.draw_points([@points.first], 14, 2, 'green')
      end
    end

    private

    def reset_tool
      @points.clear
      @current_pt = nil
      @snap_to_start = false
      @locked_axis = nil
      @ip.clear
      @ip_anchor.clear
    end

    def update_status
      axis_hint = case @locked_axis
                  when :red   then ' [LOCKED: RED AXIS (Right Arrow to unlock)]'
                  when :green then ' [LOCKED: GREEN AXIS (Left Arrow to unlock)]'
                  when :blue  then ' [LOCKED: BLUE AXIS (Up Arrow to unlock)]'
                  else ' [Arrow Keys: Right=Red, Left=Green, Up=Blue]'
                  end

      if @points.empty?
        Sketchup.status_text = 'Euro Wall Tool: Click wall start point'
      elsif @points.length == 1
        Sketchup.status_text = "Euro Wall Tool: Click end point or type length in mm#{axis_hint}"
      else
        Sketchup.status_text = "Euro Wall Tool: #{@points.length} corners placed. Click next, double-click/Enter to finish, or click start to close#{axis_hint}"
      end
    end

    def draw_3d_preview(view, pts, is_closed)
      return if pts.length < 2

      defaults = DialogManager.current_wall_params([0, 0, 0], [100, 0, 0])
      height_in = GeometryHelper.mm(defaults['height'] || Defaults::WALL_HEIGHT)
      justification = defaults['justification'] || 'center'

      core_thk = (defaults['core_thickness'] || Defaults::CORE_THICKNESS[defaults['core_type']] || 200.0).to_f
      ext_thk = (defaults['ext_layers'] || []).sum { |l| l['thickness'].to_f }
      int_thk = (defaults['int_layers'] || []).sum { |l| l['thickness'].to_f }

      if defaults['core_type'] == CoreType::DRYWALL
        b_ext = (defaults['drywall_boards_ext'] || 2).to_i
        b_int = (defaults['drywall_boards_int'] || 2).to_i
        b_thk = (defaults['drywall_board_thick'] || 12.5).to_f
        total_thk_mm = core_thk + (b_ext + b_int) * b_thk + ext_thk + int_thk
      else
        total_thk_mm = core_thk + ext_thk + int_thk
      end

      total_thk_in = GeometryHelper.mm(total_thk_mm)

      y1 = case justification
           when 'exterior' then 0.0
           when 'interior' then -total_thk_in
           else -total_thk_in / 2.0
           end
      y2 = y1 + total_thk_in

      num_segs = is_closed ? pts.length : (pts.length - 1)
      vz = Geom::Vector3d.new(0, 0, 1)

      seg_dirs = []
      seg_norms = []
      (0...num_segs).each do |i|
        p_start = pts[i]
        p_end = (is_closed && i == num_segs - 1) ? pts[0] : pts[i + 1]
        vec = p_end - p_start
        d = vec.length > 0.001 ? vec.normalize : Geom::Vector3d.new(1, 0, 0)
        n = vz.cross(d).normalize
        seg_dirs << d
        seg_norms << n
      end

      fill_color = Sketchup::Color.new(52, 152, 219, 85)
      edge_color = Sketchup::Color.new(41, 128, 185, 230)

      (0...num_segs).each do |i|
        p_start = pts[i]
        p_end = (is_closed && i == num_segs - 1) ? pts[0] : pts[i + 1]

        d_prev = (i > 0) ? seg_dirs[i - 1] : (is_closed ? seg_dirs.last : nil)
        n_prev = (i > 0) ? seg_norms[i - 1] : (is_closed ? seg_norms.last : nil)

        d_curr = seg_dirs[i]
        n_curr = seg_norms[i]

        d_next = (i < num_segs - 1) ? seg_dirs[i + 1] : (is_closed ? seg_dirs.first : nil)
        n_next = (i < num_segs - 1) ? seg_norms[i + 1] : (is_closed ? seg_norms.first : nil)

        s1 = GeometryHelper.miter_point(p_start, d_prev, n_prev, d_curr, n_curr, y1)
        s2 = GeometryHelper.miter_point(p_start, d_prev, n_prev, d_curr, n_curr, y2)
        e1 = GeometryHelper.miter_point(p_end, d_curr, n_curr, d_next, n_next, y1)
        e2 = GeometryHelper.miter_point(p_end, d_curr, n_curr, d_next, n_next, y2)

        v_h = Geom::Vector3d.new(0, 0, height_in)
        s1_t = s1 + v_h
        s2_t = s2 + v_h
        e1_t = e1 + v_h
        e2_t = e2 + v_h

        # 6 translucent faces
        view.drawing_color = fill_color
        view.draw(GL_POLYGON, [s1, e1, e1_t, s1_t])
        view.draw(GL_POLYGON, [e2, s2, s2_t, e2_t])
        view.draw(GL_POLYGON, [s1_t, e1_t, e2_t, s2_t])
        view.draw(GL_POLYGON, [s1, s2, e2, e1])
        view.draw(GL_POLYGON, [s2, s1, s1_t, s2_t]) if d_prev.nil?
        view.draw(GL_POLYGON, [e1, e2, e2_t, e1_t]) if d_next.nil?

        # Wireframe edges
        view.drawing_color = edge_color
        view.line_width = 2
        edges = [
          s1, e1,  e1, e2,  e2, s2,  s2, s1,
          s1_t, e1_t,  e1_t, e2_t,  e2_t, s2_t,  s2_t, s1_t,
          s1, s1_t,  e1, e1_t,  e2, e2_t,  s2, s2_t
        ]
        view.draw(GL_LINES, edges)
      end
    end

    def finish_walls(is_closed:)
      return if @points.length < 2

      model = Sketchup.active_model
      pts_mm = @points.map do |p|
        [GeometryHelper.to_mm(p.x), GeometryHelper.to_mm(p.y), GeometryHelper.to_mm(p.z)]
      end

      default_params = DialogManager.current_wall_params(pts_mm[0], pts_mm[1])
      groups = WallBuilder.build_polyline(model, pts_mm, is_closed, default_params)

      if groups && !groups.empty?
        model.selection.clear
        groups.each { |g| model.selection.add(g) }
      end
    end
  end
end
