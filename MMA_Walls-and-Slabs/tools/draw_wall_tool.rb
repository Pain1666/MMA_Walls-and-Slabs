# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Draw Wall Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'

module MMA_WallsAndSlabs
  class DrawWallTool
    def initialize
      @ip = Sketchup::InputPoint.new
      @points = []
    end

    def activate
      @points.clear
      @ip.clear
      Sketchup.status_text = 'MMA Wall Tool: Click wall start point.'
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      view.tooltip = @ip.tooltip if @ip.valid?
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @ip.pick(view, x, y)
      return unless @ip.valid?

      @points << @ip.position
      view.invalidate
    end
  end
end
