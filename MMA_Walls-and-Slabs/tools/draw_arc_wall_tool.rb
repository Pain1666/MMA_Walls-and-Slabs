# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Draw Curved Wall Tool
# Three clicks: start point, end point, and a point the wall passes through.
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/arc_geometry'
require_relative '../core/wall_builder'
require_relative '../ui/dialog_manager'

module MMA_WallsAndSlabs
  class DrawArcWallTool
    def initialize
      @ip = Sketchup::InputPoint.new
      @points = []
      @current = nil
    end

    def activate
      reset
      Sketchup.status_text = 'MMA Curved Wall: click the start point, then the end point, then a point on the arc.'
    end

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      if @ip.valid?
        @current = @ip.position
        view.tooltip = @ip.tooltip
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      @ip.pick(view, x, y)
      return unless @ip.valid?

      @points << @ip.position
      if @points.length == 3
        build_arc_wall
        reset
      else
        Sketchup.status_text = @points.length == 1 ? 'MMA Curved Wall: click the end point.' :
                                                    'MMA Curved Wall: click a point the wall passes through.'
      end
      view.invalidate
    end

    def onCancel(_reason, view)
      reset
      view.invalidate
    end

    def draw(view)
      @ip.draw(view) if @ip.valid?
      view.draw_points(@points, 8, 1, 'blue') unless @points.empty?
      path = preview_path
      return if path.length < 2

      view.line_width = 2
      view.drawing_color = 'blue'
      view.draw(GL_LINE_STRIP, path)
    end

    private

    def reset
      @points = []
      @current = nil
      @wall_params = DialogManager.wall_params
    end

    def to_mm_xyz(point)
      [GeometryHelper.to_mm(point.x), GeometryHelper.to_mm(point.y), GeometryHelper.to_mm(point.z)]
    end

    # Arc through the clicked points (and the cursor while placing the third).
    def preview_path
      clicks = @points.dup
      clicks << @current if clicks.length == 2 && @current
      return [] unless clicks.length == 3

      mm = clicks.map { |point| to_mm_xyz(point) }
      arc = ArcGeometry.from_three_points(*mm)
      return [] unless arc

      ArcGeometry.sample(arc[:center], arc[:radius], arc[:start], arc[:sweep]).map do |x, y|
        Geom::Point3d.new(GeometryHelper.mm(x), GeometryHelper.mm(y), GeometryHelper.mm(mm[0][2]))
      end
    end

    def build_arc_wall
      mm = @points.map { |point| to_mm_xyz(point) }
      arc = ArcGeometry.from_three_points(*mm)
      raise ArgumentError, 'The three points lie on one straight line.' unless arc

      z = mm[0][2]
      path = ArcGeometry.sample(arc[:center], arc[:radius], arc[:start], arc[:sweep]).map { |x, y| [x, y, z] }
      params = (@wall_params || DialogManager.wall_params).merge(
        'arc' => { 'center' => arc[:center], 'radius' => arc[:radius], 'sweep' => arc[:sweep], 'z' => z },
        'path_points' => path,
        'path_closed' => false,
        'start_point' => path.first,
        'end_point' => path.last,
        'openings' => []
      )
      params.delete('joints')
      WallBuilder.build(Sketchup.active_model, params, nil)
      Sketchup.status_text = 'MMA Curved Wall: wall created.'
      Sketchup.active_model.select_tool(nil)
    rescue StandardError => error
      UI.messagebox("Could not create curved wall: #{error.message}")
    end
  end
end
