# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Main Plugin Loader & Menu/Toolbar Setup
# ==============================================================================

require 'sketchup.rb'

require_relative 'core/constants'
require_relative 'core/wall_object'
require_relative 'core/geometry_helper'
require_relative 'core/wall_builder'
require_relative 'core/wall_joiner'
require_relative 'core/slab_builder'
require_relative 'core/opening_cutter'
require_relative 'ui/dialog_manager'
require_relative 'tools/draw_wall_tool'
require_relative 'tools/draw_slab_tool'
require_relative 'tools/opening_tool'
require_relative 'tools/join_wall_tool'
require_relative 'tools/edit_wall_tool'

module MMA_WallsAndSlabs
  unless file_loaded?(__FILE__)
    icon_dir = File.join(File.dirname(__FILE__), 'icons')

    cmd_draw_wall = UI::Command.new('Draw Wall') do
      Sketchup.active_model.select_tool(DrawWallTool.new)
    end
