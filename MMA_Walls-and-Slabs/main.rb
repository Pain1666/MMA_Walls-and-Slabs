# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Main Launcher
# This entry point keeps the legacy codebase working while exposing the new name.
# ==============================================================================

require_relative '../euro_wall_slab/main'

module MMA_WallsAndSlabs
  unless file_loaded?(__FILE__)
    file_loaded(__FILE__)
  end
end
