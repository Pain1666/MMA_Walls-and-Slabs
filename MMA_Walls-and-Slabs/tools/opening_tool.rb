# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Opening Tool
# ==============================================================================

module MMA_WallsAndSlabs
  class OpeningTool
    def initialize; end

    def activate
      Sketchup.status_text = 'MMA Opening Tool active.'
    end
  end
end
