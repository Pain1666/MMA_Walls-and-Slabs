# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Edit Wall Points Tool
# ==============================================================================

module MMA_WallsAndSlabs
  class EditWallTool
    def initialize(group = nil)
      @group = group
    end

    def activate
      Sketchup.status_text = 'MMA Edit Wall Tool active.'
    end
  end
end
