# frozen_string_literal: true
# ==============================================================================
# Deprecated compatibility stub
# ==============================================================================
# This directory is kept only to avoid breaking old references and bookmarks.
# The active project has been renamed to MMA_Walls-and-Slabs.
# Do not add new code here.
# ==============================================================================

# This file intentionally does nothing.
# Use:
#   MMA_Walls-and-Slabs.rb
#   MMA_Walls-and-Slabs/main.rb
# instead.

module MMA_WallsAndSlabs
  unless file_loaded?(__FILE__)
    puts '[DEPRECATED] euro_wall_slab is a legacy compatibility path. Use MMA_Walls-and-Slabs instead.'
    file_loaded(__FILE__)
  end
end
