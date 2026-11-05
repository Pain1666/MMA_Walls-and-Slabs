# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Draw Wall Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/snap_math'
require_relative '../core/face_align'
require_relative '../core/segment_layers'
require_relative '../core/wall_builder'
require_relative '../core/wall_object'

module MMA_WallsAndSlabs
  class DrawWallTool
    AXIS_SNAP_ANGLE = 8.0 * Math::PI / 180.0
    CLOSE_SNAP_PIXELS = 12
    SNAP_PIXELS = 14
    PREVIEW_ALPHA = 85

    def initialize(wall_params = nil)
      @ip = Sketchup::InputPoint.new
      @points = []
      @point_ips = []
      @current_point = nil
      @snap_axis = nil
      @axis_snap_enabled = true
      @closing = false
      @reference = nil
      @snap_anchor = nil
      @wall_params = wall_params && Marshal.load(Marshal.dump(wall_params))
    end

    def activate
      @points.clear
      @point_ips.clear
      @current_point = nil
      @snap_axis = nil
      @axis_snap_enabled = true
      @closing = false
      @reference = nil
      @snap_anchor = nil
      @ip.clear
      Sketchup.status_text = status_text
    end

    def onMouseMove(flags, x, y, view)
      pick_input_point(view, x, y)
      if @ip.valid?
        if @points.any?
          @closing = @points.length >= 3 && near_start_point?(view, x, y)
          @current_point = @closing ? @points.first : resolve_point(view, x, y)
        end
        view.tooltip = @ip.tooltip
        Sketchup.status_text = status_text
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      pick_input_point(view, x, y)
      return unless @ip.valid?

      if @points.length >= 3 && near_start_point?(view, x, y)
        finish_wall(closed: true)
        view.invalidate
        return
      end

      if @points.empty?
        add_point(first_point(view, x, y))
      else
        point = resolve_point(view, x, y)
        add_point(point) unless behind_reference?(point)
      end
      view.invalidate
    end

    def onLButtonDoubleClick(flags, x, y, view)
      pick_input_point(view, x, y)
      if @points.length >= 3 && near_start_point?(view, x, y)
        finish_wall(closed: true)
        view.invalidate
        return
      end
      add_point(resolve_point(view, x, y)) if @ip.valid? && !@points.empty?
      finish_wall if @points.length >= 2
      view.invalidate
    end

    def onKeyDown(key, repeat, flags, view)
      if key == 65 || key == 97
        @axis_snap_enabled = !@axis_snap_enabled
        @snap_axis = nil
        Sketchup.status_text = status_text
      elsif (key == 13 || key == 10) && @points.length >= 2
        finish_wall(closed: @closing)
      end
      view.invalidate
    end

    def draw(view)
      @ip.draw(view) if @ip.valid?
      return unless @wall_params

      @points.each_cons(2) { |start_point, end_point| draw_wall_preview(view, start_point, end_point) }
      draw_wall_preview(view, @points.last, @current_point) if @points.any? && @current_point
      return unless @snap_anchor && @points.any?

      view.draw_points([@snap_anchor], 10, 2, 'orange')
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      @points.each { |point| bounds.add(point) }
      bounds.add(@current_point) if @current_point
      if @points.any? && @current_point && @wall_params
        layers = WallBuilder.wall_layers(@wall_params).select { |layer| layer['enabled'] != false }
        thickness = layers.sum { |layer| GeometryHelper.mm(layer['thickness']) }
        height = GeometryHelper.mm(@wall_params['height'] || Defaults::WALL_HEIGHT)
        (@points + [@current_point]).each do |point|
          [-thickness, 0.0, height].each do |z_offset|
            bounds.add(Geom::Point3d.new(point.x - thickness, point.y - thickness, point.z + z_offset))
            bounds.add(Geom::Point3d.new(point.x + thickness, point.y + thickness, point.z + z_offset))
          end
        end
      end
      bounds
    end

    def onCancel(reason, view)
      if @points.length > 1
        @points.pop
        @point_ips.pop
        @current_point = @points.last
        Sketchup.status_text = status_text
      elsif @points.any?
        @points.clear
        @point_ips.clear
        @current_point = nil
        @reference = nil
        @wall_params = nil
        Sketchup.status_text = status_text
      end
      @snap_axis = nil
      @closing = false
      view.invalidate
    end

    private

    # Snap order: aligned face line (if the first point was on a wall face),
    # then wall ends/midpoints/corners, then the model axes.
    def resolve_point(view, x, y)
      @snap_anchor = nil
      return project_reference(@ip.position) if @reference

      anchor = wall_anchor(view, x, y)
      return anchor if anchor

      constrained_point(@ip.position, @points.last)
    end

    def first_point(view, x, y)
      @snap_anchor = nil
      @reference = face_reference(view, x, y)
      return project_reference(@ip.position) if @reference

      wall_anchor(view, x, y) || @ip.position
    end

    # Nearest end, midpoint or corner of an existing MMA wall centre line.
    def wall_anchor(view, x, y)
      candidates = []
      Sketchup.active_model.entities.grep(Sketchup::Group).each do |group|
        next unless WallModel.valid_wall_group?(group)

        wall = WallModel.from_group(group)
        next unless wall && wall.path_points && wall.path_points.length >= 2

        candidates.concat(SnapMath.anchors(wall.path_points, wall.path_closed?, wall.arc?))
      end
      return nil if candidates.empty?

      screen = candidates.map do |anchor|
        p = anchor[:point]
        screen_point = view.screen_coords(Geom::Point3d.new(GeometryHelper.mm(p[0]),
                                                            GeometryHelper.mm(p[1]),
                                                            GeometryHelper.mm(p[2])))
        [screen_point.x, screen_point.y]
      end
      index = SnapMath.nearest(screen, x, y, SNAP_PIXELS)
      return nil unless index

      anchor = candidates[index]
      p = anchor[:point]
      @snap_anchor = Geom::Point3d.new(GeometryHelper.mm(p[0]), GeometryHelper.mm(p[1]), GeometryHelper.mm(p[2]))
      @snap_label = { end: 'wall end', mid: 'wall midpoint', corner: 'wall corner' }[anchor[:kind]]
      @snap_anchor
    end

    # If the cursor is on the face of an MMA wall, returns a reference line that
    # places the new wall against that face. nil otherwise.
    def face_reference(view, x, y)
      face = @ip.face
      return nil unless face && face.normal.z.abs < 0.01

      helper = view.pick_helper
      helper.do_pick(x, y)
      wall_group = nil
      helper.count.times do |index|
        path = helper.path_at(index) || []
        wall_group = path.grep(Sketchup::Group).reverse.find { |group| WallModel.valid_wall_group?(group) }
        break if wall_group
      end
      return nil unless wall_group

      wall = WallModel.from_group(wall_group)
      return nil unless wall && wall.path_points

      @wall_params ||= DialogManager.wall_params
      point = @ip.position
      px = GeometryHelper.to_mm(point.x)
      py = GeometryHelper.to_mm(point.y)
      nearest = SegmentLayers.project_onto_path(wall.path_points, px, py, wall.path_closed?)
      return nil unless nearest

      # The new wall goes on the side of the face that points away from the existing wall.
      side = [px - nearest[0], py - nearest[1]]
      side = [face.normal.x, face.normal.y] if Math.hypot(*side) < 1.0
      total = WallBuilder.wall_layers(@wall_params)
                         .select { |layer| layer['enabled'] != false && layer['thickness'].to_f > 0.001 }
                         .sum { |layer| layer['thickness'].to_f }
      FaceAlign.reference([point.x, point.y, point.z], side, GeometryHelper.mm(total),
                          @wall_params['justification'])
    end

    def project_reference(point)
      x, y = FaceAlign.project(point.x, point.y, @reference)
      Geom::Point3d.new(x, y, @reference[:origin][2])
    end

    # With a face reference the wall only runs forward along the aligned line.
    def behind_reference?(point)
      return false unless @reference && @points.any?

      FaceAlign.along(point.x, point.y, @reference) <
        FaceAlign.along(@points.last.x, @points.last.y, @reference) - 1e-6
    end

    def pick_input_point(view, x, y)
      if @points.any?
        @ip.pick(view, x, y, @point_ips.last)
      else
        @ip.pick(view, x, y)
      end
    end

    def add_point(point)
      return if @points.any? && @points.last.distance(point) <= 0.001

      @points << point
      input_point = Sketchup::InputPoint.new
      input_point.copy!(@ip)
      @point_ips << input_point
      @current_point = point
      @closing = false
      @wall_params ||= DialogManager.wall_params
      Sketchup.status_text = status_text
    end

    def near_start_point?(view, x, y)
      return false if @points.empty?

      screen_point = view.screen_coords(@points.first)
      dx = screen_point.x - x
      dy = screen_point.y - y
      (dx * dx) + (dy * dy) <= CLOSE_SNAP_PIXELS * CLOSE_SNAP_PIXELS
    end

    def constrained_point(point, origin)
      return point unless @axis_snap_enabled
      return point unless origin

      dx = point.x - origin.x
      dy = point.y - origin.y
      distance = Math.sqrt((dx * dx) + (dy * dy))
      return point if distance <= 0.001

      axes = Sketchup.active_model.axes
      candidates = [
        [:x, axes.xaxis],
        [:y, axes.yaxis]
      ].filter_map do |name, axis|
        axis_x = axis.x.to_f
        axis_y = axis.y.to_f
        axis_length = Math.sqrt((axis_x * axis_x) + (axis_y * axis_y))
        next if axis_length <= 0.001

        axis_x /= axis_length
        axis_y /= axis_length
        projection = (dx * axis_x) + (dy * axis_y)
        cosine = [projection.abs / distance, 1.0].min
        angle = Math.acos(cosine)
        next if angle > AXIS_SNAP_ANGLE

        [angle, name, axis_x, axis_y, projection]
      end

      candidate = candidates.min_by(&:first)
      unless candidate
        @snap_axis = nil
        return point
      end

      _angle, @snap_axis, axis_x, axis_y, projection = candidate
      Geom::Point3d.new(
        origin.x + axis_x * projection,
        origin.y + axis_y * projection,
        origin.z
      )
    end

    def draw_wall_preview(view, start_point, end_point)
      return unless @wall_params && start_point.distance(end_point) > 0.001

      dx = end_point.x - start_point.x
      dy = end_point.y - start_point.y
      length = Math.sqrt((dx * dx) + (dy * dy))
      return if length <= 0.001

      normal_x = -dy / length
      normal_y = dx / length
      height = GeometryHelper.mm(@wall_params['height'] || Defaults::WALL_HEIGHT)
      layers = WallBuilder.wall_layers(@wall_params).select do |layer|
        layer['enabled'] != false && layer['thickness'].to_f > 0.001
      end
      total_thickness = layers.sum { |layer| GeometryHelper.mm(layer['thickness']) }
      offset = WallBuilder.alignment_offset(@wall_params['justification'], total_thickness)

      layers.each do |layer|
        thickness = GeometryHelper.mm(layer['thickness'])
        start_base = Geom::Point3d.new(
          start_point.x + normal_x * offset,
          start_point.y + normal_y * offset,
          start_point.z
        )
        end_base = Geom::Point3d.new(
          end_point.x + normal_x * offset,
          end_point.y + normal_y * offset,
          start_point.z
        )
        offset_vector = Geom::Vector3d.new(normal_x * thickness, normal_y * thickness, 0)
        vertical = Geom::Vector3d.new(0, 0, height)
        points = [
          start_base,
          end_base,
          end_base + vertical,
          start_base + vertical,
          start_base + offset_vector,
          end_base + offset_vector,
          end_base + offset_vector + vertical,
          start_base + offset_vector + vertical
        ]
        faces = [
          [0, 1, 2, 3], [4, 7, 6, 5],
          [0, 4, 5, 1], [3, 2, 6, 7],
          [0, 3, 7, 4], [1, 5, 6, 2]
        ]
        color_rgb = DefaultMaterials::PALETTE[layer['material']] || [55, 145, 225]
        view.drawing_color = Sketchup::Color.new(color_rgb[0], color_rgb[1], color_rgb[2], PREVIEW_ALPHA)
        view.draw(GL_QUADS, faces.flat_map { |face| face.map { |index| points[index] } })

        view.drawing_color = Sketchup::Color.new(35, 75, 110, 210)
        view.line_width = 1
        view.draw(GL_LINES, [
          points[0], points[1], points[1], points[2], points[2], points[3], points[3], points[0],
          points[4], points[5], points[5], points[6], points[6], points[7], points[7], points[4],
          points[0], points[4], points[1], points[5], points[2], points[6], points[3], points[7]
        ])
        offset += thickness
      end
      view.drawing_color = Sketchup::Color.new(0, 0, 0)
    end

    def status_text
      axis = case @snap_axis
             when :x then ' (snapped to red axis)'
             when :y then ' (snapped to green axis)'
             else ''
             end
      axis += " (snapped to #{@snap_label})" if @snap_anchor && @snap_label
      axis += ' (aligned to wall face)' if @reference
      alignment = @axis_snap_enabled ? 'axis alignment on (A to disable)' : 'axis alignment off (A to enable)'
      return "MMA Wall Tool: Click the start point; #{alignment}#{axis}." if @points.empty?

      close_hint = @points.length >= 3 ? ', click the start point to close' : ''
      close_status = @closing ? ' (loop will close)' : ''
      "MMA Wall Tool: #{@points.length} points; click to continue#{close_hint}, Enter/double-click to create, Esc to undo last point; #{alignment}#{axis}#{close_status}."
    end

    def finish_wall(closed: false)
      return if @points.length < 2

      params = @wall_params || DialogManager.wall_params
      points_mm = @points.map do |point|
        [point.x, point.y, point.z].map { |value| GeometryHelper.to_mm(value) }
      end
      points_mm << points_mm.first.dup if closed
      WallBuilder.build_path(Sketchup.active_model, params, points_mm)
      @reference = nil
      Sketchup.status_text = 'MMA Wall Tool: Wall created.'
      Sketchup.active_model.select_tool(nil)
    rescue StandardError => error
      UI.messagebox("Could not create wall: #{error.message}")
      Sketchup.status_text = 'MMA Wall Tool: Wall creation failed.'
      @points.clear
      @point_ips.clear
      @current_point = nil
      @snap_axis = nil
      @closing = false
      @reference = nil
      @snap_anchor = nil
      @wall_params = nil
    end
  end
end
