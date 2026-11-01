# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Draw Slab Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/slab_builder'

module MMA_WallsAndSlabs
  class DrawSlabTool
    def initialize
      @points = []
      @ip = Sketchup::InputPoint.new
      @current_point = nil
    end

    def activate
      @points.clear
      @current_point = nil
      Sketchup.status_text = 'MMA Slab Tool: Click vertices; press Enter to finish.'
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      @current_point = @ip.position if @ip.valid?
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @ip.pick(view, x, y)
      return unless @ip.valid?

      @points << @ip.position
      Sketchup.status_text = "MMA Slab Tool: #{@points.length} points; press Enter to finish."
      view.invalidate
    end

    def onKeyDown(key, repeat, flags, view)
      finish_slab if key == 13 && @points.length >= 3
      view.invalidate
    end

    def onLButtonDoubleClick(flags, x, y, view)
      @ip.pick(view, x, y)
      if @ip.valid? && (@points.empty? || @points.last.distance(@ip.position) > 0.001)
        @points << @ip.position
      end
      finish_slab if @points.length >= 3
    end

    def onCancel(reason, view)
      @points.clear
      @current_point = nil
      view.invalidate
    end

    def draw(view)
      preview_points = @points.dup
      preview_points << @current_point if @current_point && !preview_points.empty?
      view.draw(GL_LINE_STRIP, preview_points) if preview_points.length >= 2
      view.draw_points(@points, 6, 1, Sketchup::Color.new(0, 180, 255)) unless @points.empty?
    end

    private

    def finish_slab
      return if @points.length < 3

      params = DialogManager.slab_params
      params['points'] = @points.map do |point|
        [GeometryHelper.to_mm(point.x), GeometryHelper.to_mm(point.y)]
      end
      SlabBuilder.build(Sketchup.active_model, params)
      Sketchup.status_text = 'MMA Slab Tool: Slab created.'
      Sketchup.active_model.select_tool(nil)
    rescue StandardError => error
      UI.messagebox("Could not create slab: #{error.message}")
      Sketchup.status_text = 'MMA Slab Tool: Slab creation failed.'
    end
  end
end
