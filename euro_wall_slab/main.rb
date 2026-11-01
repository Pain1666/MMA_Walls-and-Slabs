# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Main Plugin Loader & Menu/Toolbar Setup
# ==============================================================================

require 'sketchup.rb'

require_relative 'core/constants'
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

module EuroWallSlab
  unless file_loaded?(__FILE__)
    icon_dir = File.join(File.dirname(__FILE__), 'icons')

    # --------------------------------------------------------------------------
    # Commands with Dedicated Custom Icons
    # --------------------------------------------------------------------------

    # 1. Draw Wall
    cmd_draw_wall = UI::Command.new('Draw Euro Wall') do
      Sketchup.active_model.select_tool(DrawWallTool.new)
    end
    cmd_draw_wall.tooltip = 'Draw multi-layer wall (Concrete, Poroton, Brick, Cartongesso)'
    cmd_draw_wall.status_bar_text = 'Click start and corner points to draw European multi-layer walls'
    cmd_draw_wall.small_icon = File.join(icon_dir, 'wall_16.png')
    cmd_draw_wall.large_icon = File.join(icon_dir, 'wall_24.png')

    # 2. Wall Settings
    cmd_wall_settings = UI::Command.new('Wall Settings & Presets') do
      DialogManager.show_wall_dialog
    end
    cmd_wall_settings.tooltip = 'Configure European wall layers, materials, and presets'
    cmd_wall_settings.small_icon = File.join(icon_dir, 'wall_settings_16.png')
    cmd_wall_settings.large_icon = File.join(icon_dir, 'wall_settings_24.png')

    # 3. Join Walls
    cmd_join_walls = UI::Command.new('Join Euro Walls') do
      Sketchup.active_model.select_tool(JoinWallTool.new)
    end
    cmd_join_walls.tooltip = 'Join two existing walls at corner (extends layers & cores)'
    cmd_join_walls.status_bar_text = 'Click two walls to join and miter them together'
    cmd_join_walls.small_icon = File.join(icon_dir, 'join_wall_16.png')
    cmd_join_walls.large_icon = File.join(icon_dir, 'join_wall_24.png')

    # 4. Edit Wall Points (drag corners, whole walls and layer ends)
    cmd_edit_walls = UI::Command.new('Edit Wall Points') do
      Sketchup.active_model.select_tool(EditWallTool.new)
    end
    cmd_edit_walls.tooltip = 'Drag wall corners, whole walls, and individual layer ends'
    cmd_edit_walls.status_bar_text = 'Click a Euro Wall, then drag its green, purple or orange handles'
    # Reuses the join icon until a dedicated one is added to icons/
    cmd_edit_walls.small_icon = File.join(icon_dir, 'join_wall_16.png')
    cmd_edit_walls.large_icon = File.join(icon_dir, 'join_wall_24.png')

    # 5. Draw Slab
    cmd_draw_slab = UI::Command.new('Draw Euro Slab') do
      Sketchup.active_model.select_tool(DrawSlabTool.new)
    end
    cmd_draw_slab.tooltip = 'Draw multi-layer floor or roof slab with polygon boundary'
    cmd_draw_slab.status_bar_text = 'Click polygon vertices to define slab perimeter'
    cmd_draw_slab.small_icon = File.join(icon_dir, 'slab_16.png')
    cmd_draw_slab.large_icon = File.join(icon_dir, 'slab_24.png')

    # 6. Convert Face to Slab
    cmd_face_to_slab = UI::Command.new('Convert Face to Slab') do
      model = Sketchup.active_model
      faces = model.selection.grep(Sketchup::Face)
      if faces.empty?
        UI.messagebox('Please select a planar face first.')
      else
        layers = DialogManager.current_slab_params([])['layers']
        faces.each do |f|
          SlabBuilder.create_from_face(model, f, layers)
        end
      end
    end
    cmd_face_to_slab.tooltip = 'Convert selected planar face into a multi-layer Euro slab'
    cmd_face_to_slab.small_icon = File.join(icon_dir, 'face_slab_16.png')
    cmd_face_to_slab.large_icon = File.join(icon_dir, 'face_slab_24.png')

    # 7. Slab Settings
    cmd_slab_settings = UI::Command.new('Slab Settings & Presets') do
      DialogManager.show_slab_dialog
    end
    cmd_slab_settings.tooltip = 'Configure European slab layers, screed, insulation, and finishes'
    cmd_slab_settings.small_icon = File.join(icon_dir, 'slab_settings_16.png')
    cmd_slab_settings.large_icon = File.join(icon_dir, 'slab_settings_24.png')

    # 8. Cut Opening
    cmd_cut_opening = UI::Command.new('Cut Opening in Wall') do
      DialogManager.show_opening_dialog
    end
    cmd_cut_opening.tooltip = 'Set dimensions and place door, window, or void opening'
    cmd_cut_opening.status_bar_text = 'Open settings and interactively place openings on Euro Walls'
    cmd_cut_opening.small_icon = File.join(icon_dir, 'opening_16.png')
    cmd_cut_opening.large_icon = File.join(icon_dir, 'opening_24.png')

    # --------------------------------------------------------------------------
    # Menus
    # --------------------------------------------------------------------------
    menu = UI.menu('Extensions').add_submenu('Euro Wall & Slab')
    menu.add_item(cmd_draw_wall)
    menu.add_item(cmd_wall_settings)
    menu.add_item(cmd_join_walls)
    menu.add_item(cmd_edit_walls)
    menu.add_separator
    menu.add_item(cmd_draw_slab)
    menu.add_item(cmd_face_to_slab)
    menu.add_item(cmd_slab_settings)
    menu.add_separator
    menu.add_item(cmd_cut_opening)

    # --------------------------------------------------------------------------
    # Context Menu (Right Click on Wall or Slab)
    # --------------------------------------------------------------------------
    UI.add_context_menu_handler do |context_menu|
      model = Sketchup.active_model
      sel = model.selection

      groups = sel.grep(Sketchup::Group)
      walls = groups.select { |g| g.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall' }
      slab = groups.find { |g| g.get_attribute(DICT_NAME, ATTR_TYPE) == 'slab' }
      face = sel.grep(Sketchup::Face).first

      if walls.length == 1
        wall = walls.first
        sub = context_menu.add_submenu('Euro Wall')
        sub.add_item('Edit Wall Assembly...') do
          DialogManager.show_wall_dialog(wall)
        end
        sub.add_item('Edit Wall Points') do
          Sketchup.active_model.select_tool(EditWallTool.new(wall))
        end
        sub.add_item('Add Opening (Door/Window)...') do
          DialogManager.show_opening_dialog(wall)
        end
      elsif walls.length == 2
        context_menu.add_item('Join Selected Euro Walls') do
          WallJoiner.join_walls(model, walls[0], walls[1])
        end
      elsif slab
        sub = context_menu.add_submenu('Euro Slab')
        sub.add_item('Edit Slab Assembly...') do
          DialogManager.show_slab_dialog(slab)
        end
      elsif face
        context_menu.add_item('Convert Face to Euro Slab') do
          layers = DialogManager.current_slab_params([])['layers']
          SlabBuilder.create_from_face(model, face, layers)
        end
      end
    end

    # --------------------------------------------------------------------------
    # Toolbar
    # --------------------------------------------------------------------------
    toolbar = UI::Toolbar.new('Euro Wall & Slab')
    toolbar.add_item(cmd_draw_wall)
    toolbar.add_item(cmd_wall_settings)
    toolbar.add_item(cmd_join_walls)
    toolbar.add_item(cmd_edit_walls)
    toolbar.add_separator
    toolbar.add_item(cmd_draw_slab)
    toolbar.add_item(cmd_face_to_slab)
    toolbar.add_item(cmd_slab_settings)
    toolbar.add_separator
    toolbar.add_item(cmd_cut_opening)
    toolbar.restore

    file_loaded(__FILE__)
  end
end
