# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Interactive Opening Placement Tool with Live 3D Preview
# ==============================================================================

require 'json'
require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/opening_cutter'

module EuroWallSlab
  class OpeningTool
    def initialize(params = nil, target_wall = nil)
      @op_type   = (params && params['type']) || 'door'
      @op_width  = (params && params['width'].to_f) || 900.0
      @op_height = (params && params['height'].to_f) || 2100.0
      @op_sill   = (params && params['sill_height'].to_f) || 0.0

      @target_wall = target_wall
      @hover_wall = nil
      @hover_offset_mm = 0.0

      # Cached 3D preview geometry
      @preview_faces = []
      @preview_edges = []
      @p_bl_front = nil
      @p_start_base = nil
      @p_bl_base = nil

      @ip = Sketchup::InputPoint.new
    end

    def activate
      update_status
      Sketchup.vcb_label = 'Offset from Start'
      Sketchup.vcb_value = ''
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.path_at(0)

      # Search for a Euro Wall in pick path
      wall_group = nil
      if path
        wall_group = path.reverse.find do |entity|
          entity.is_a?(Sketchup::Group) && entity.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall'
        end
      end

      # Fallback to target_wall if specified
      wall_group ||= @target_wall if @target_wall && @target_wall.valid?

      if wall_group && wall_group.valid?
        compute_preview_geometry(wall_group, @ip.position)
        @hover_wall = wall_group
        Sketchup.vcb_value = "#{@hover_offset_mm} mm"
        Sketchup.status_text = "Euro Opening: Click to place [#{@op_type.capitalize} #{@op_width.round}x#{@op_height.round}mm] @ #{@hover_offset_mm}mm from start (or type exact offset)"
      else
        @hover_wall = nil
        @preview_faces.clear
        @preview_edges.clear
        @p_bl_front = nil
        Sketchup.status_text = "Euro Opening: Hover cursor over any Euro Wall to position the #{@op_type.capitalize} opening"
      end

      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      if @hover_wall && @hover_wall.valid?
        commit_opening
        # Re-compute preview after rebuild
        compute_preview_geometry(@hover_wall, @ip.position)
        view.invalidate
      else
        UI.messagebox('Please hover cursor over a Euro Wall assembly to place the opening.')
      end
    end

    def onUserText(text, view)
      return unless @hover_wall && @hover_wall.valid?

      val = text.to_f
      return if val < 0.0

      @hover_offset_mm = val
      commit_opening
      compute_preview_geometry(@hover_wall, @ip.position)
      view.invalidate
    end

    def onCancel(reason, view)
      Sketchup.active_model.select_tool(nil)
    end

    # --------------------------------------------------------------------------
    # Live 3D Semi-Transparent Holographic Opening Preview
    # --------------------------------------------------------------------------
    def draw(view)
      return unless @hover_wall && !@preview_faces.empty?

      # 1. 3D Semi-Transparent Volume (Warm amber/orange)
      view.drawing_color = Sketchup::Color.new(243, 156, 18, 120)
      @preview_faces.each do |f_pts|
        view.draw(GL_POLYGON, f_pts)
      end

      # 2. Crisp boundary lines
      view.drawing_color = Sketchup::Color.new(211, 84, 0, 240)
      view.line_width = 2
      view.draw(GL_LINES, @preview_edges)

      # 3. Bottom-Left Insertion Point Target Marker
      if @p_bl_front
        view.drawing_color = Sketchup::Color.new(231, 76, 60) # Red
        view.line_width = 3
        view.draw_points([@p_bl_front], 12, 1, 'red') # Cross mark at insertion point

        # 4. Offset dimension line from wall start to insertion point
        if @p_start_base && @p_bl_base
          view.drawing_color = Sketchup::Color.new(41, 128, 185)
          view.line_width = 1
          view.line_stipple = '-'
          view.draw_line(@p_start_base, @p_bl_base)
          view.line_stipple = ''
        end
      end
    end

    private

    def update_status
      Sketchup.status_text = "Euro Opening Tool [#{@op_type.capitalize} #{@op_width.round}x#{@op_height.round}mm]: Hover over any Euro Wall to position. Insertion point: Bottom-Left."
    end

    def compute_preview_geometry(wall_group, hit_pt)
      data_json = wall_group.get_attribute(DICT_NAME, ATTR_DATA)
      return unless data_json

      params = JSON.parse(data_json)

      p_start = Geom::Point3d.new(
        GeometryHelper.mm(params['start_point'][0]),
        GeometryHelper.mm(params['start_point'][1]),
        GeometryHelper.mm(params['start_point'][2])
      )
      p_end = Geom::Point3d.new(
        GeometryHelper.mm(params['end_point'][0]),
        GeometryHelper.mm(params['end_point'][1]),
        GeometryHelper.mm(params['end_point'][2])
      )

      vec = p_end - p_start
      wall_len_in = vec.length
      return if wall_len_in < 0.01

      vx = vec.normalize
      vz = Geom::Vector3d.new(0, 0, 1)
      vy = vz.cross(vx).normalize

      # Calculate thickness and Y offset bounds
      core_type = params['core_type'] || CoreType::POROTON
      core_thk = (params['core_thickness'] || Defaults::CORE_THICKNESS[core_type] || 200.0).to_f
      ext_thk = (params['ext_layers'] || []).sum { |l| l['thickness'].to_f }
      int_thk = (params['int_layers'] || []).sum { |l| l['thickness'].to_f }

      if core_type == CoreType::DRYWALL
        b_ext = (params['drywall_boards_ext'] || 2).to_i
        b_int = (params['drywall_boards_int'] || 2).to_i
        b_thk = (params['drywall_board_thick'] || 12.5).to_f
        total_thk_mm = core_thk + (b_ext + b_int) * b_thk + ext_thk + int_thk
      else
        total_thk_mm = core_thk + ext_thk + int_thk
      end

      total_thk_in = GeometryHelper.mm(total_thk_mm)
      justification = params['justification'] || 'center'

      y1 = case justification
           when 'exterior' then 0.0
           when 'interior' then -total_thk_in
           else -total_thk_in / 2.0
           end
      y2 = y1 + total_thk_in

      # Project hit_pt onto wall line
      proj_dist_in = (hit_pt - p_start).dot(vx)

      w_in = GeometryHelper.mm(@op_width)
      h_in = GeometryHelper.mm(@op_height)
      sill_in = GeometryHelper.mm(@op_sill)

      # Clamp offset so opening stays inside wall bounds
      dist_in = [0.0, [proj_dist_in, wall_len_in - w_in].min].max
      @hover_offset_mm = GeometryHelper.to_mm(dist_in).round

      # 8 corner points of 3D opening box
      # Bottom points
      bl1 = p_start + (vx.clone.tap { |v| v.length = dist_in }) + (vy.clone.tap { |v| v.length = y1 }) + (vz.clone.tap { |v| v.length = sill_in })
      br1 = bl1 + (vx.clone.tap { |v| v.length = w_in })
      bl2 = p_start + (vx.clone.tap { |v| v.length = dist_in }) + (vy.clone.tap { |v| v.length = y2 }) + (vz.clone.tap { |v| v.length = sill_in })
      br2 = bl2 + (vx.clone.tap { |v| v.length = w_in })

      # Top points
      v_top = vz.clone.tap { |v| v.length = h_in }
      tl1 = bl1 + v_top
      tr1 = br1 + v_top
      tl2 = bl2 + v_top
      tr2 = br2 + v_top

      @p_bl_front = bl1
      @p_start_base = p_start + (vy.clone.tap { |v| v.length = y1 })
      @p_bl_base = bl1 - (vz.clone.tap { |v| v.length = sill_in })

      # 6 Faces
      @preview_faces = [
        [bl1, br1, tr1, tl1], # Front face (y1)
        [br2, bl2, tl2, tr2], # Back face (y2)
        [bl2, bl1, tl1, tl2], # Left jamb
        [br1, br2, tr2, tr1], # Right jamb
        [tl1, tr1, tr2, tl2], # Lintel header
        [bl2, br2, br1, bl1]  # Sill bottom
      ]

      # 12 Outline Edges
      @preview_edges = [
        bl1, br1,  br1, tr1,  tr1, tl1,  tl1, bl1, # Front
        bl2, br2,  br2, tr2,  tr2, tl2,  tl2, bl2, # Back
        bl1, bl2,  br1, br2,  tr1, tr2,  tl1, tl2  # Cross ties
      ]
    end

    def commit_opening
      model = Sketchup.active_model
      payload = {
        'id'          => "op_#{Time.now.to_i}_#{rand(1000)}",
        'type'        => @op_type,
        'offset_x'    => @hover_offset_mm,
        'width'       => @op_width,
        'height'      => @op_height,
        'sill_height' => @op_sill
      }

      OpeningCutter.add_wall_opening(model, @hover_wall, payload)
    end
  end
end
