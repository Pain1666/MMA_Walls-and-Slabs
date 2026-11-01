# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Draw Slab Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/slab_builder'

module EuroWallSlab
  class DrawSlabTool
    def initialize
      @ip = Sketchup::InputPoint.new
      @points = []
    end

    def activate
      @points.clear
      @ip.clear
      Sketchup.status_text = 'Euro Slab Tool: Click polygon vertices. Double-click or click start point to close and create slab.'
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      view.tooltip = @ip.tooltip if @ip.valid?
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @ip.pick(view, x, y)
      return unless @ip.valid?

      pt = @ip.position

      # If we have at least 3 points and user clicks very close to first point -> close polygon
      if @points.length >= 3 && pt.distance(@points.first) < 100.mm
        finish_slab
        return
      end

      @points << pt
      update_status
      view.invalidate
    end

    def onLButtonDoubleClick(flags, x, y, view)
      if @points.length >= 3
        finish_slab
      end
    end

    def draw(view)
      if @ip.valid?
        @ip.draw(view)
      end

      return if @points.empty?

      # Draw edges of polygon placed so far
      view.line_width = 2
      view.drawing_color = 'navy'

      (0...@points.length - 1).each do |i|
        view.draw_line(@points[i], @points[i + 1])
      end

      # Draw rubber-band to current cursor
      if @ip.valid?
        view.drawing_color = 'blue'
        view.draw_line(@points.last, @ip.position)
        # Also line closing to start
        if @points.length >= 2
          view.drawing_color = 'gray'
          view.draw_line(@ip.position, @points.first)
        end
      end
    end

    private

    def update_status
      Sketchup.status_text = "Euro Slab Tool: #{@points.length} points placed. Double-click or click first point to close."
    end

    def finish_slab
      return if @points.length < 3

      model = Sketchup.active_model
      pts_mm = @points.map do |p|
        [GeometryHelper.to_mm(p.x), GeometryHelper.to_mm(p.y), GeometryHelper.to_mm(p.z)]
      end

      default_params = DialogManager.current_slab_params(pts_mm)
      slab_group = SlabBuilder.build(model, default_params)
      if slab_group
        model.selection.clear
        model.selection.add(slab_group)
      end

      @points.clear
      @ip.clear
      update_status
    end
  end
end
