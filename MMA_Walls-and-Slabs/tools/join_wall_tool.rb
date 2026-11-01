# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Join Walls Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_joiner'

module MMA_WallsAndSlabs
  class JoinWallTool
    def initialize; end

    def activate
      Sketchup.status_text = 'MMA Join Walls Tool: Select two walls.'
    end
  end
end
