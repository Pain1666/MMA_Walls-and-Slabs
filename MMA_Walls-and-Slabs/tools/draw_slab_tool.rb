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
    end

    def activate
      @points.clear
      Sketchup.status_text = 'MMA Slab Tool: Click polygon vertices.'
    end
  end
end
