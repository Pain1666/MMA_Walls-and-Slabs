# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Main Plugin Loader & Menu/Toolbar Setup update 2.0
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
      DialogManager.show_wall_dialog(nil, create_wall: true)
    end
    cmd_draw_wall.tooltip = 'Set wall layers and settings, then draw a wall'
    cmd_draw_wall.status_bar_text = 'Choose wall settings, confirm, then click wall points.'
    cmd_draw_wall.small_icon = File.join(icon_dir, 'wall_16.png')
    cmd_draw_wall.large_icon = File.join(icon_dir, 'wall_24.png')

    cmd_draw_slab = UI::Command.new('Draw Slab') do
      model = Sketchup.active_model
      model.select_tool(DrawSlabTool.new) if model
    end
    cmd_draw_slab.tooltip = 'Draw a layered slab'
    cmd_draw_slab.status_bar_text = 'Click slab vertices and press Enter to finish.'
    cmd_draw_slab.small_icon = File.join(icon_dir, 'slab_16.png')
    cmd_draw_slab.large_icon = File.join(icon_dir, 'slab_24.png')

    cmd_opening = UI::Command.new('Opening Tool') do
      DialogManager.show_opening_dialog
    end
    cmd_opening.tooltip = 'Place an opening in a wall or slab'
    cmd_opening.small_icon = File.join(icon_dir, 'opening_16.png')
    cmd_opening.large_icon = File.join(icon_dir, 'opening_24.png')

    cmd_join_walls = UI::Command.new('Join Walls') do
      model = Sketchup.active_model
      model.select_tool(JoinWallTool.new) if model
    end
    cmd_join_walls.tooltip = 'Join two MMA walls'
    cmd_join_walls.small_icon = File.join(icon_dir, 'join_wall_16.png')
    cmd_join_walls.large_icon = File.join(icon_dir, 'join_wall_24.png')

    cmd_edit_wall = UI::Command.new('Edit Wall') do
      model = Sketchup.active_model
      model.select_tool(EditWallTool.new) if model
    end
    cmd_edit_wall.tooltip = 'Edit a selected MMA wall'
    cmd_edit_wall.small_icon = File.join(icon_dir, 'wall_settings_16.png')
    cmd_edit_wall.large_icon = File.join(icon_dir, 'wall_settings_24.png')

    cmd_wall_dialog = UI::Command.new('Wall Settings') do
      model = Sketchup.active_model
      group = model && model.selection.grep(Sketchup::Group).find { |item| WallModel.valid_wall_group?(item) }
      DialogManager.show_wall_dialog(group)
    end
    cmd_wall_dialog.small_icon = File.join(icon_dir, 'wall_settings_16.png')
    cmd_wall_dialog.large_icon = File.join(icon_dir, 'wall_settings_24.png')

    cmd_slab_dialog = UI::Command.new('Slab Settings') do
      model = Sketchup.active_model
      group = model && model.selection.grep(Sketchup::Group).find { |item| item.get_attribute(DICT_NAME, ATTR_TYPE) == 'slab' }
      DialogManager.show_slab_dialog(group)
    end
    cmd_slab_dialog.small_icon = File.join(icon_dir, 'slab_settings_16.png')
    cmd_slab_dialog.large_icon = File.join(icon_dir, 'slab_settings_24.png')

    cmd_opening_dialog = UI::Command.new('Opening Settings') do
      DialogManager.show_opening_dialog if defined?(DialogManager)
    end
    cmd_opening_dialog.small_icon = File.join(icon_dir, 'opening_16.png')
    cmd_opening_dialog.large_icon = File.join(icon_dir, 'opening_24.png')

    toolbar = UI::Toolbar.new('MMA_WallsAndSlabs')
    toolbar.add_item(cmd_draw_wall)
    toolbar.add_item(cmd_draw_slab)
    toolbar.add_item(cmd_opening)
    toolbar.add_item(cmd_join_walls)
    toolbar.add_item(cmd_edit_wall)
    toolbar.add_separator
    toolbar.add_item(cmd_wall_dialog)
    toolbar.add_item(cmd_slab_dialog)
    toolbar.add_item(cmd_opening_dialog)
    toolbar.show

    menu = UI.menu('Extensions').add_submenu('MMA Walls and Slabs')
    [cmd_draw_wall, cmd_draw_slab, cmd_opening, cmd_join_walls, cmd_edit_wall,
     cmd_wall_dialog, cmd_slab_dialog, cmd_opening_dialog].each do |command|
      menu.add_item(command)
    end

    file_loaded(__FILE__)
  end
end
