# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Wall Builder with T-Junctions, Corner Miters & Layer Groups
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'

module EuroWallSlab
  class WallBuilder
    # Build a polyline chain of connected wall segments with automatic corner miters
    def self.build_polyline(model, points_mm, is_closed, base_params)
      return [] if points_mm.length < 2

      pts = points_mm.map do |p|
        Geom::Point3d.new(
          GeometryHelper.mm(p[0]),
          GeometryHelper.mm(p[1]),
          GeometryHelper.mm(p[2])
        )
      end

      pts = pts.each_with_index.select do |p, i|
        i == 0 || p.distance(pts[i - 1]) > 0.01
      end.map(&:first)

      return [] if pts.length < 2

      # Closed loops are normalised to clockwise order. With a clockwise loop the
      # "left of travel" side (where layer 1 is built) is outside the loop, so
      # Exterior always means the outside face regardless of drawing direction.
      pts = pts.reverse if is_closed && signed_area(pts) > 0

      num_pts = pts.length
      num_segs = is_closed ? num_pts : (num_pts - 1)
      return [] if num_segs < 1

      seg_dirs = []
      seg_norms = []
      vz = Geom::Vector3d.new(0, 0, 1)

      (0...num_segs).each do |i|
        p_start = pts[i]
        p_end = (is_closed && i == num_segs - 1) ? pts[0] : pts[i + 1]
        vec = p_end - p_start
        d = vec.length > 0.001 ? vec.normalize : Geom::Vector3d.new(1, 0, 0)
        n = vz.cross(d).normalize
        seg_dirs << d
        seg_norms << n
      end

      model.start_operation('Build Euro Wall Chain', true)
      created_groups = []

      (0...num_segs).each do |i|
        p_start = pts[i]
        p_end = (is_closed && i == num_segs - 1) ? pts[0] : pts[i + 1]

        d_curr = seg_dirs[i]
        n_curr = seg_norms[i]

        p_prev = if i > 0
                   pts[i - 1]
                 elsif is_closed
                   pts[num_segs - 1]
                 end

        d_prev = if i > 0
                   seg_dirs[i - 1]
                 elsif is_closed
                   seg_dirs.last
                 end
        n_prev = if i > 0
                   seg_norms[i - 1]
                 elsif is_closed
                   seg_norms.last
                 end

        p_next = if i < num_segs - 1
                   (is_closed && (i + 1 == num_segs - 1)) ? pts[0] : pts[i + 2]
                 elsif is_closed
                   pts[1]
                 end

        d_next = if i < num_segs - 1
                   seg_dirs[i + 1]
                 elsif is_closed
                   seg_dirs.first
                 end
        n_next = if i < num_segs - 1
                   seg_norms[i + 1]
                 elsif is_closed
                   seg_norms.first
                 end

        seg_params = base_params.dup
        seg_params['start_point'] = [GeometryHelper.to_mm(p_start.x), GeometryHelper.to_mm(p_start.y), GeometryHelper.to_mm(p_start.z)]
        seg_params['end_point']   = [GeometryHelper.to_mm(p_end.x), GeometryHelper.to_mm(p_end.y), GeometryHelper.to_mm(p_end.z)]
        seg_params['wall_index']  = i

        seg_params['prev_corner_point'] = p_prev ? [GeometryHelper.to_mm(p_prev.x), GeometryHelper.to_mm(p_prev.y), GeometryHelper.to_mm(p_prev.z)] : nil
        seg_params['next_corner_point'] = p_next ? [GeometryHelper.to_mm(p_next.x), GeometryHelper.to_mm(p_next.y), GeometryHelper.to_mm(p_next.z)] : nil

        # Only the outer ends of an open chain can wrap; inner joints are mitred.
        seg_params['start_edge'] = (!is_closed && i == 0) ? base_params['start_edge'] : 'open'
        seg_params['end_edge']   = (!is_closed && i == num_segs - 1) ? base_params['end_edge'] : 'open'

        corners = {
          d_prev: d_prev, n_prev: n_prev,
          d_curr: d_curr, n_curr: n_curr,
          d_next: d_next, n_next: n_next
        }

        group = build_segment(model, seg_params, corners, nil)
        created_groups << group if group
      end

      model.commit_operation
      created_groups
    end

    # Build or rebuild a single wall group
    def self.build(model, params, target_group = nil)
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
      return nil if vec.length < 0.01

      vz = Geom::Vector3d.new(0, 0, 1)
      d_curr = vec.normalize
      n_curr = vz.cross(d_curr).normalize

      d_prev = nil
      n_prev = nil
      if params['prev_corner_point']
        p_prev = Geom::Point3d.new(
          GeometryHelper.mm(params['prev_corner_point'][0]),
          GeometryHelper.mm(params['prev_corner_point'][1]),
          GeometryHelper.mm(params['prev_corner_point'][2])
        )
        vec_prev = p_start - p_prev
        if vec_prev.length > 0.001
          d_prev = vec_prev.normalize
          n_prev = vz.cross(d_prev).normalize
        end
      end

      d_next = nil
      n_next = nil
      if params['next_corner_point']
        p_next = Geom::Point3d.new(
          GeometryHelper.mm(params['next_corner_point'][0]),
          GeometryHelper.mm(params['next_corner_point'][1]),
          GeometryHelper.mm(params['next_corner_point'][2])
        )
        vec_next = p_next - p_end
        if vec_next.length > 0.001
          d_next = vec_next.normalize
          n_next = vz.cross(d_next).normalize
        end
      end

      corners = {
        d_prev: d_prev, n_prev: n_prev,
        d_curr: d_curr, n_curr: n_curr,
        d_next: d_next, n_next: n_next
      }

      model.start_operation('Build Euro Wall', true)
      grp = build_segment(model, params, corners, target_group)
      model.commit_operation
      grp
    end

    # Y ranges (mm, measured from the wall baseline) of every layer in build order.
    # Each row: { side: 'ext' | 'core' | 'int', index: original list index, y1:, y2: }
    # Mirrors the offsets used by build_segment; the Edit Wall Points tool uses it
    # to place layer handles and the wall outline.
    def self.layer_stack(params)
      core_type = params['core_type'] || CoreType::POROTON
      core_thk  = (params['core_thickness'] || Defaults::CORE_THICKNESS[core_type] || 200.0).to_f
      ext = enabled_layers(params['ext_layers'])
      int = enabled_layers(params['int_layers'])

      t_core = core_thk
      if core_type == CoreType::DRYWALL
        b_ext = (params['drywall_boards_ext'] || Defaults::DRYWALL_BOARDS_EXT).to_i
        b_int = (params['drywall_boards_int'] || Defaults::DRYWALL_BOARDS_INT).to_i
        b_thk = (params['drywall_board_thick'] || Defaults::DRYWALL_BOARD_THICK).to_f
        t_core += (b_ext + b_int) * b_thk
      end

      t_total = ext.sum { |_, l| l['thickness'].to_f } + t_core + int.sum { |_, l| l['thickness'].to_f }

      justification = params['justification'] || Defaults::WALL_JUSTIFICATION
      y = case justification
          when 'exterior' then 0.0
          when 'interior' then -t_total
          else -t_total / 2.0
          end

      rows = []
      ext.each do |idx, layer|
        t = layer['thickness'].to_f
        rows << { side: 'ext', index: idx, y1: y, y2: y + t }
        y += t
      end
      rows << { side: 'core', index: nil, y1: y, y2: y + t_core }
      y += t_core
      int.each do |idx, layer|
        t = layer['thickness'].to_f
        rows << { side: 'int', index: idx, y1: y, y2: y + t }
        y += t
      end
      rows
    end

    # [original_index, layer] pairs for the layers that are switched on
    def self.enabled_layers(list)
      out = []
      (list || []).each_with_index { |l, i| out << [i, l] if l['enabled'] != false }
      out
    end

    # Twice the signed area of a 2D loop (in inches). Positive = counter-clockwise.
    def self.signed_area(pts)
      sum = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        sum += p.x * q.y - q.x * p.y
      end
      sum / 2.0
    end

    # 'exterior' / 'interior' when the end is free and wrap is requested, else nil
    def self.wrap_mode(edge, neighbour_point)
      return nil if neighbour_point

      %w[exterior interior].include?(edge) ? edge : nil
    end

    # Internal worker to construct geometry of one wall segment with distinct layer groups
    def self.build_segment(model, params, corners, target_group)
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

      vec_x = p_end - p_start
      length_in = vec_x.length
      return nil if length_in < 0.01

      vx = corners[:d_curr]
      vy = corners[:n_curr]
      vz = Geom::Vector3d.new(0, 0, 1)

      height_in = GeometryHelper.mm(params['height'] || Defaults::WALL_HEIGHT)
      core_type = params['core_type'] || CoreType::POROTON
      justification = params['justification'] || Defaults::WALL_JUSTIFICATION

      ext_layers = (params['ext_layers'] || []).select { |l| l['enabled'] != false }
      int_layers = (params['int_layers'] || []).select { |l| l['enabled'] != false }
      openings_raw = params['openings'] || []
      t_conn = params['t_connection']

      # Free ends may wrap a finish layer around the end of the wall
      start_wrap = wrap_mode(params['start_edge'], params['prev_corner_point'])
      end_wrap   = wrap_mode(params['end_edge'], params['next_corner_point'])

      # Thickness calculations
      t_ext_in = ext_layers.sum { |l| GeometryHelper.mm(l['thickness'].to_f) }
      t_int_in = int_layers.sum { |l| GeometryHelper.mm(l['thickness'].to_f) }

      core_thk_mm = (params['core_thickness'] || Defaults::CORE_THICKNESS[core_type] || 200.0).to_f
      drywall_stud_w_in = GeometryHelper.mm(core_thk_mm)
      drywall_b_thick_in = GeometryHelper.mm(params['drywall_board_thick'] || Defaults::DRYWALL_BOARD_THICK)
      drywall_b_ext_count = (params['drywall_boards_ext'] || Defaults::DRYWALL_BOARDS_EXT).to_i
      drywall_b_int_count = (params['drywall_boards_int'] || Defaults::DRYWALL_BOARDS_INT).to_i

      if core_type == CoreType::DRYWALL
        t_core_in = drywall_stud_w_in + (drywall_b_ext_count + drywall_b_int_count) * drywall_b_thick_in
      else
        t_core_in = GeometryHelper.mm(core_thk_mm)
      end

      t_total_in = t_ext_in + t_core_in + t_int_in

      y_start_in = case justification
                   when 'exterior' then 0.0
                   when 'interior' then -t_total_in
                   else -t_total_in / 2.0
                   end

      openings_in = openings_raw.map do |op|
        {
          id: op['id'],
          type: op['type'] || 'window',
          x: GeometryHelper.mm(op['offset_x'].to_f),
          width: GeometryHelper.mm(op['width'].to_f),
          height: GeometryHelper.mm(op['height'].to_f),
          sill: GeometryHelper.mm(op['sill_height'].to_f)
        }
      end

      wall_group = target_group || model.active_entities.add_group
      entities = wall_group.entities
      entities.clear! unless target_group.nil?

      current_y = y_start_in

      # Every isolated layer group in build order (used for wrap caps)
      stack = []

      # ------------------------------------------------------------------------
      # 1. EXTERIOR FINISH LAYERS (Each in its own isolated sub-group)
      # ------------------------------------------------------------------------
      ext_layers.each_with_index do |layer, idx|
        thk_in = GeometryHelper.mm(layer['thickness'].to_f)
        next if thk_in <= 0.001

        layer_name = "Ext Layer #{idx + 1}: #{layer['name']} (#{layer['thickness'].to_f.round}mm)"
        mat = GeometryHelper.get_or_create_material(model, layer['material'])

        lg = build_isolated_layer_group(entities, layer_name, p_start, p_end, vx, vy, current_y, current_y + thk_in, height_in, corners, openings_in, mat, t_conn,
                                        GeometryHelper.mm(layer['ext_start'].to_f), GeometryHelper.mm(layer['ext_end'].to_f))
        stack << { group: lg, y1: current_y, y2: current_y + thk_in, material: mat }
        current_y += thk_in
      end

      # ------------------------------------------------------------------------
      # 2. STRUCTURAL CORE (In its own isolated sub-group)
      # ------------------------------------------------------------------------
      if core_type == CoreType::DRYWALL
        board_mat = GeometryHelper.get_or_create_material(model, 'EWS_Drywall_Board')
        stud_mat  = GeometryHelper.get_or_create_material(model, 'EWS_Metal_Stud')

        # Exterior boards (each a sub-group)
        drywall_b_ext_count.times do |b_idx|
          b_name = "Drywall Ext Board #{b_idx + 1} (#{params['drywall_board_thick'] || 12.5}mm)"
          lg = build_isolated_layer_group(entities, b_name, p_start, p_end, vx, vy, current_y, current_y + drywall_b_thick_in, height_in, corners, openings_in, board_mat, t_conn)
          stack << { group: lg, y1: current_y, y2: current_y + drywall_b_thick_in, material: board_mat }
          current_y += drywall_b_thick_in
        end

        # Metal Stud Framing Cavity
        stud_spacing_in = GeometryHelper.mm(params['drywall_stud_spacing'] || Defaults::DRYWALL_STUD_SPACING)
        stud_depth_in   = GeometryHelper.mm(Defaults::DRYWALL_STUD_DEPTH)
        gauge_in        = GeometryHelper.mm(Defaults::DRYWALL_STUD_THICK)

        framing_group = entities.add_group
        framing_group.name = "Core: Metal C-Stud Framing (#{core_thk_mm.round}mm @ #{(params['drywall_stud_spacing'] || 600).to_f.round}mm)"
        framing_group.material = stud_mat

        build_drywall_studs(framing_group.entities, p_start, vx, vy, vz, current_y, drywall_stud_w_in, stud_depth_in, gauge_in, length_in, height_in, stud_spacing_in, openings_in, stud_mat)
        current_y += drywall_stud_w_in

        # Interior boards (each a sub-group)
        drywall_b_int_count.times do |b_idx|
          b_name = "Drywall Int Board #{b_idx + 1} (#{params['drywall_board_thick'] || 12.5}mm)"
          lg = build_isolated_layer_group(entities, b_name, p_start, p_end, vx, vy, current_y, current_y + drywall_b_thick_in, height_in, corners, openings_in, board_mat, t_conn)
          stack << { group: lg, y1: current_y, y2: current_y + drywall_b_thick_in, material: board_mat }
          current_y += drywall_b_thick_in
        end
      else
        # Solid Core (Concrete, Laterizio, Brick, AAC)
        default_core_mat = case core_type
                           when CoreType::CONCRETE  then 'EWS_Concrete'
                           when CoreType::POROTON   then 'EWS_Laterizio'
                           when CoreType::BRICK     then 'EWS_Brick'
                           when CoreType::AAC_BLOCK then 'EWS_Ytong'
                           else 'EWS_Laterizio'
                           end
        core_mat_name = params['core_material'] || default_core_mat
        mat = GeometryHelper.get_or_create_material(model, core_mat_name)
        core_label = CoreType::LABELS[core_type] || core_type.capitalize
        layer_name = "Core: #{core_label} (#{core_thk_mm.round}mm)"

        lg = build_isolated_layer_group(entities, layer_name, p_start, p_end, vx, vy, current_y, current_y + t_core_in, height_in, corners, openings_in, mat, t_conn)
        stack << { group: lg, y1: current_y, y2: current_y + t_core_in, material: mat }
        current_y += t_core_in
      end

      # ------------------------------------------------------------------------
      # 3. INTERIOR FINISH LAYERS (Each in its own isolated sub-group)
      # ------------------------------------------------------------------------
      int_layers.each_with_index do |layer, idx|
        thk_in = GeometryHelper.mm(layer['thickness'].to_f)
        next if thk_in <= 0.001

        layer_name = "Int Layer #{idx + 1}: #{layer['name']} (#{layer['thickness'].to_f.round}mm)"
        mat = GeometryHelper.get_or_create_material(model, layer['material'])

        lg = build_isolated_layer_group(entities, layer_name, p_start, p_end, vx, vy, current_y, current_y + thk_in, height_in, corners, openings_in, mat, t_conn,
                                        GeometryHelper.mm(layer['ext_start'].to_f), GeometryHelper.mm(layer['ext_end'].to_f))
        stack << { group: lg, y1: current_y, y2: current_y + thk_in, material: mat }
        current_y += thk_in
      end

      # ------------------------------------------------------------------------
      # 4. WRAP CAPS on free ends (exterior = outermost layer, interior = innermost)
      # ------------------------------------------------------------------------
      apply_wrap_caps(stack, p_start, p_end, vx, vy, vz, height_in, start_wrap, end_wrap)

      # Tag metadata
      wall_group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      wall_group.set_attribute(DICT_NAME, ATTR_DATA, params.to_json)
      wall_group.set_attribute(DICT_NAME, ATTR_VERSION, '1.4.0')

      core_name = CoreType::LABELS[core_type] || core_type.capitalize
      wall_group.name = "Wall [#{core_name}] - #{GeometryHelper.to_mm(length_in).round}x#{params['height'].to_f.round}mm"

      wall_group
    end

    # Wrap a finish layer around a free wall end. The wrapping layer gets a return
    # piece as thick as the layer itself, running from its outer face to the wall's
    # inner face (exterior: whole wall; interior: the layer itself).
    def self.apply_wrap_caps(stack, p_start, p_end, vx, vy, vz, height, start_wrap, end_wrap)
      return if stack.empty?

      wall_inner = stack.last[:y2]

      if start_wrap
        target = start_wrap == 'exterior' ? stack.first : stack.last
        add_wrap_cap(target, wall_inner, p_start, vx, vy, vz, height, true)
      end

      if end_wrap
        target = end_wrap == 'exterior' ? stack.first : stack.last
        add_wrap_cap(target, wall_inner, p_end, vx, vy, vz, height, false)
      end
    end

    def self.add_wrap_cap(target, wall_inner, origin, vx, vy, vz, height, at_start)
      t = target[:y2] - target[:y1]
      span = wall_inner - target[:y1]
      return if t <= 0.001 || span <= 0.001

      x_off = at_start ? -t : 0.0
      base = origin + GeometryHelper.vec_scale(vx, x_off) + GeometryHelper.vec_scale(vy, target[:y1])
      GeometryHelper.create_oriented_box(target[:group].entities, base, vx, vy, vz, t, span, height, target[:material])
    end

    private

    # Build an isolated layer group with support for T-junctions and corner miters.
    # ext_s_in / ext_e_in extend the layer past its start / end (inches, may be negative).
    def self.build_isolated_layer_group(parent_entities, group_name, p_start, p_end, vx, vy, y1, y2, height, corners, openings, material, t_conn = nil, ext_s_in = 0.0, ext_e_in = 0.0)
      layer_group = parent_entities.add_group
      layer_group.name = group_name
      layer_group.material = material if material
      l_entities = layer_group.entities

      is_core = (group_name =~ /Core:/i)

      # ------------------------------------------------------------------------
      # Start Points: S1 (at y1) and S2 (at y2)
      # ------------------------------------------------------------------------
      if t_conn && t_conn['end'] == 'start'
        # T-Connection at start: extend to host wall face / core
        y_target_in = GeometryHelper.mm(is_core ? t_conn['y_host_core'] : t_conn['y_host_finish'])
        p_plane = Geom::Point3d.new(
          GeometryHelper.mm(t_conn['int_pt'][0]),
          GeometryHelper.mm(t_conn['int_pt'][1]),
          GeometryHelper.mm(t_conn['int_pt'][2])
        )
        n_host = Geom::Vector3d.new(t_conn['host_n'][0], t_conn['host_n'][1], t_conn['host_n'][2])
        p_target = p_plane + (n_host.clone.tap { |v| v.length = y_target_in })

        s1 = GeometryHelper.ray_plane_intersection(p_start + (vy.clone.tap { |v| v.length = y1 }), vx, p_target, n_host)
        s2 = GeometryHelper.ray_plane_intersection(p_start + (vy.clone.tap { |v| v.length = y2 }), vx, p_target, n_host)
      else
        s1 = GeometryHelper.miter_point(p_start, corners[:d_prev], corners[:n_prev], corners[:d_curr], corners[:n_curr], y1)
        s2 = GeometryHelper.miter_point(p_start, corners[:d_prev], corners[:n_prev], corners[:d_curr], corners[:n_curr], y2)
      end

      # ------------------------------------------------------------------------
      # End Points: E1 (at y1) and E2 (at y2)
      # ------------------------------------------------------------------------
      if t_conn && t_conn['end'] == 'end'
        # T-Connection at end: extend to host wall face / core
        y_target_in = GeometryHelper.mm(is_core ? t_conn['y_host_core'] : t_conn['y_host_finish'])
        p_plane = Geom::Point3d.new(
          GeometryHelper.mm(t_conn['int_pt'][0]),
          GeometryHelper.mm(t_conn['int_pt'][1]),
          GeometryHelper.mm(t_conn['int_pt'][2])
        )
        n_host = Geom::Vector3d.new(t_conn['host_n'][0], t_conn['host_n'][1], t_conn['host_n'][2])
        p_target = p_plane + (n_host.clone.tap { |v| v.length = y_target_in })

        e1 = GeometryHelper.ray_plane_intersection(p_end + (vy.clone.tap { |v| v.length = y1 }), vx, p_target, n_host)
        e2 = GeometryHelper.ray_plane_intersection(p_end + (vy.clone.tap { |v| v.length = y2 }), vx, p_target, n_host)
      else
        e1 = GeometryHelper.miter_point(p_end, corners[:d_curr], corners[:n_curr], corners[:d_next], corners[:n_next], y1)
        e2 = GeometryHelper.miter_point(p_end, corners[:d_curr], corners[:n_curr], corners[:d_next], corners[:n_next], y2)
      end

      # Per-layer extension along the wall direction (Edit Wall Points layer handles)
      unless t_conn && t_conn['end'] == 'start'
        if ext_s_in.abs > 0.001
          shift = GeometryHelper.vec_scale(vx, -ext_s_in)
          s1 = s1 + shift
          s2 = s2 + shift
        end
      end
      unless t_conn && t_conn['end'] == 'end'
        if ext_e_in.abs > 0.001
          shift = GeometryHelper.vec_scale(vx, ext_e_in)
          e1 = e1 + shift
          e2 = e2 + shift
        end
      end

      length = p_start.distance(p_end)

      if openings.empty?
        GeometryHelper.create_mitered_layer_box(l_entities, s1, e1, e2, s2, height, material)
      else
        blocks = GeometryHelper.decompose_panel_with_openings(length, height, openings)

        blocks.each do |blk|
          x_start, x_len, z_start, z_len = blk
          next if x_len <= 0.001 || z_len <= 0.001

          x_end = x_start + x_len

          bs1 = (x_start <= 0.001) ? s1 : (p_start + (vx.clone.tap { |v| v.length = x_start }) + (vy.clone.tap { |v| v.length = y1 }))
          bs2 = (x_start <= 0.001) ? s2 : (p_start + (vx.clone.tap { |v| v.length = x_start }) + (vy.clone.tap { |v| v.length = y2 }))

          be1 = (x_end >= length - 0.001) ? e1 : (p_start + (vx.clone.tap { |v| v.length = x_end }) + (vy.clone.tap { |v| v.length = y1 }))
          be2 = (x_end >= length - 0.001) ? e2 : (p_start + (vx.clone.tap { |v| v.length = x_end }) + (vy.clone.tap { |v| v.length = y2 }))

          vz_off = Geom::Vector3d.new(0, 0, z_start)
          p_s1 = bs1 + vz_off
          p_s2 = bs2 + vz_off
          p_e1 = be1 + vz_off
          p_e2 = be2 + vz_off

          GeometryHelper.create_mitered_layer_box(l_entities, p_s1, p_e1, p_e2, p_s2, z_len, material)
        end
      end

      if material
        l_entities.grep(Sketchup::Face).each do |f|
          f.material = material
          f.back_material = material
        end
      end

      layer_group
    end

    # Build metal C-studs and runners
    def self.build_drywall_studs(entities, p_start, vx, vy, vz, y_offset, web_w, stud_d, gauge, length, height, spacing, openings, material)
      door_spans = openings.select { |op| op[:sill] <= 0.001 }.map { |op| [op[:x], op[:x] + op[:width]] }.sort_by(&:first)
      cur_x = 0.0
      runner_h = gauge * 2.0

      # Bottom Track
      door_spans.each do |d_start, d_end|
        if d_start > cur_x + 0.01
          p_trk = p_start + (vx.clone.tap { |v| v.length = cur_x }) + (vy.clone.tap { |v| v.length = y_offset })
          GeometryHelper.create_oriented_box(entities, p_trk, vx, vy, vz, d_start - cur_x, web_w, runner_h, material)
        end
        cur_x = [cur_x, d_end].max
      end
      if cur_x < length - 0.01
        p_trk = p_start + (vx.clone.tap { |v| v.length = cur_x }) + (vy.clone.tap { |v| v.length = y_offset })
        GeometryHelper.create_oriented_box(entities, p_trk, vx, vy, vz, length - cur_x, web_w, runner_h, material)
      end

      # Top Track
      p_top = p_start + (vy.clone.tap { |v| v.length = y_offset }) + (vz.clone.tap { |v| v.length = height - runner_h })
      GeometryHelper.create_oriented_box(entities, p_top, vx, vy, vz, length, web_w, runner_h, material)

      # Studs
      stud_x_positions = []
      x_pos = 0.0
      while x_pos <= length
        stud_x_positions << x_pos
        x_pos += spacing
      end
      stud_x_positions << (length - stud_d) unless stud_x_positions.include?(length - stud_d)

      openings.each do |op|
        stud_x_positions << [op[:x] - stud_d, 0.0].max
        stud_x_positions << [op[:x] + op[:width], length - stud_d].min
      end

      stud_x_positions = stud_x_positions.uniq.sort

      stud_x_positions.each do |sx|
        s_end = sx + stud_d
        next if s_end > length + 0.01

        overlapping_ops = openings.select do |op|
          (sx < op[:x] + op[:width]) && (s_end > op[:x])
        end

        if overlapping_ops.empty?
          p_s = p_start + (vx.clone.tap { |v| v.length = sx }) + (vy.clone.tap { |v| v.length = y_offset }) + (vz.clone.tap { |v| v.length = runner_h })
          stud_h = height - (2.0 * runner_h)
          GeometryHelper.create_c_stud(entities, p_s, vx, vy, vz, web_w, stud_d, gauge, stud_h, material)
        else
          overlapping_ops.each do |op|
            if op[:sill] > runner_h + 0.01
              p_s = p_start + (vx.clone.tap { |v| v.length = sx }) + (vy.clone.tap { |v| v.length = y_offset }) + (vz.clone.tap { |v| v.length = runner_h })
              c_h = op[:sill] - runner_h
              GeometryHelper.create_c_stud(entities, p_s, vx, vy, vz, web_w, stud_d, gauge, c_h, material)
            end
            op_top = op[:sill] + op[:height]
            if op_top < height - runner_h - 0.01
              p_s = p_start + (vx.clone.tap { |v| v.length = sx }) + (vy.clone.tap { |v| v.length = y_offset }) + (vz.clone.tap { |v| v.length = op_top })
              c_h = height - runner_h - op_top
              GeometryHelper.create_c_stud(entities, p_s, vx, vy, vz, web_w, stud_d, gauge, c_h, material)
            end
          end
        end
      end

      # Opening runners
      openings.each do |op|
        op_top = op[:sill] + op[:height]
        if op_top < height - 0.01
          p_hdr = p_start + (vx.clone.tap { |v| v.length = op[:x] }) + (vy.clone.tap { |v| v.length = y_offset }) + (vz.clone.tap { |v| v.length = op_top })
          GeometryHelper.create_oriented_box(entities, p_hdr, vx, vy, vz, op[:width], web_w, runner_h, material)
        end
        if op[:sill] > 0.01
          p_sil = p_start + (vx.clone.tap { |v| v.length = op[:x] }) + (vy.clone.tap { |v| v.length = y_offset }) + (vz.clone.tap { |v| v.length = op_top - runner_h })
          GeometryHelper.create_oriented_box(entities, p_sil, vx, vy, vz, op[:width], web_w, runner_h, material)
        end
      end

      if material
        entities.grep(Sketchup::Face).each do |f|
          f.material = material
          f.back_material = material
        end
      end
    end
  end
end
