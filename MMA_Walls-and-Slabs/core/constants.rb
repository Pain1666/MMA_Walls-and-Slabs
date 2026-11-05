# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Constants and Defaults
# ==============================================================================

module MMA_WallsAndSlabs
  DICT_NAME    = 'MMA_WallsAndSlabs'
  ATTR_TYPE    = 'object_type'
  ATTR_DATA    = 'parameters_json'
  ATTR_VERSION = 'plugin_version'
  PLUGIN_DATA_VERSION = '2.0.0'

  module CoreType
    CONCRETE   = 'concrete'
    HOLLOW_BRICK    = 'hollow_brick'
    BRICK      = 'brick'
    CONCRETE_BLOCK  = 'concrete_block'
    DRYWALL    = 'drywall'

    ALL = [CONCRETE, HOLLOW_BRICK, BRICK, CONCRETE_BLOCK, DRYWALL].freeze

    LABELS = {
      CONCRETE  => 'Reinforced Concrete Wall',
      HOLLOW_BRICK   => 'Hollow Clay Block',
      BRICK     => 'Solid Brick',
      CONCRETE_BLOCK => 'Hollow Concrete Block',
      DRYWALL   => 'Drywall Partition'
    }.freeze
  end

  # Material list from the "Sketchup Extension Materials" sheet.
  # Colour (RGB) and texture file are inside the extension's materials folder.
  module DefaultMaterials
    PALETTE = {
      'MMA_Concrete'        => [190, 192, 195],
      'MMA_Brick'           => [168, 52, 38],
      'MMA_Concrete_Block'  => [230, 230, 225],
      'MMA_Metal_Stud'      => [118, 134, 150],
      'MMA_Drywall_Board'   => [232, 228, 218],
      'MMA_Insulation_EPS'  => [246, 238, 115],
      'MMA_Render_Ext'      => [240, 236, 226],
      'MMA_Plaster_Int'     => [250, 250, 248],
      'MMA_Screed'          => [155, 155, 155],
      'MMA_Wood_Flooring'   => [192, 145, 88],
      'MMA_Ceramic_Tile'    => [145, 135, 125],
      'MMA_Stone_Dark'      => [45, 45, 45],
      'MMA_Stone_Light'     => [170, 170, 170],
      'MMA_Stone_Flooring'  => [170, 170, 170]
    }.freeze

    # Texture file for each material. Files not yet verified in the folder are marked in the notes.
    TEXTURE_FILES = {
      'MMA_Concrete'        => 'Concrete_01.png',
      'MMA_Brick'           => 'Brick_01.png',
      'MMA_Concrete_Block'  => 'Concrete_Block_01.jpg',
      'MMA_Metal_Stud'      => 'Metal_01.png',
      'MMA_Drywall_Board'   => 'Plaster_Int_01.jpg',
      'MMA_Insulation_EPS'  => 'Wool-insulation_01.jpg',
      'MMA_Render_Ext'      => 'Plaster_Ext_01.jpg',
      'MMA_Plaster_Int'     => 'Plaster_Int_01.jpg',
      'MMA_Screed'          => 'Concrete_02.jpg',
      'MMA_Wood_Flooring'   => 'Wood_01.png',
      'MMA_Ceramic_Tile'    => 'Ceramic_Tiles_01.png',
      'MMA_Stone_Dark'      => 'Stone_01.jpg',
      'MMA_Stone_Light'     => 'Stone_02.png',
      'MMA_Stone_Flooring'  => 'Stone_03.jpg'
    }.freeze

    # Tile size in mm for each texture file. Textures not listed here use SketchUp's default scale.
    TEXTURE_SIZES = {
      'Concrete_01.png'        => [1000.0, 1000.0],
      'Brick_01.png'           => [900.0, 900.0],
      'Concrete_Block_01.jpg'  => [1560.0, 980.0],
      'Plaster_Ext_01.jpg'     => [980.0, 1024.0],
      'Plaster_Int_01.jpg'     => [980.0, 1024.0],
      'Wool-insulation_01.jpg' => [900.0, 805.0],
      'Concrete_02.jpg'        => [600.0, 600.0],
      'Stone_01.jpg'           => [1200.0, 2400.0],
      'Stone_02.png'           => [1861.0, 1186.0],
      'Metal_01.png'           => [600.0, 600.0],
      'Wood_01.png'            => [1000.0, 1000.0],
      'Ceramic_Tiles_01.png'   => [600.0, 600.0],
      'Stone_03.jpg'           => [600.0, 1067.0]
    }.freeze
  end

  module Defaults
    WALL_HEIGHT = 2800.0
    WALL_JUSTIFICATION = 'center'
    CORE_THICKNESS = {
      CoreType::CONCRETE => 250.0,
      CoreType::HOLLOW_BRICK => 250.0,
      CoreType::BRICK => 250.0,
      CoreType::CONCRETE_BLOCK => 200.0,
      CoreType::DRYWALL => 75.0
    }.freeze

    DRYWALL_STUD_SPACING = 600.0
    DRYWALL_BOARDS_EXT = 2
    DRYWALL_BOARDS_INT = 2
    DRYWALL_BOARD_THICK = 12.5
    DRYWALL_STUD_DEPTH = 90.0
    DRYWALL_STUD_THICK = 1.5
  end

  module WallPresets
    GENERIC = 'generic'
    THICK_WALL = 'thick_wall'
    PARTITION = 'partition'
    INSULATED = 'insulated'
    ALL = [GENERIC, THICK_WALL, PARTITION, INSULATED].freeze
  end

  module WallJustification
    CENTER = 'center'
    INNER = 'inner'
    OUTER = 'outer'
    LEFT = OUTER
    RIGHT = INNER
    ALL = [CENTER, INNER, OUTER].freeze
  end

  module WallTypeCatalog
    def self.default_for(preset)
      case preset.to_s
      when WallPresets::GENERIC
        [
          { 'name' => 'Exterior render', 'thickness' => 15.0, 'material' => 'MMA_Render_Ext', 'enabled' => true },
          { 'name' => 'Insulation', 'thickness' => 100.0, 'material' => 'MMA_Insulation_EPS', 'enabled' => true },
          { 'name' => 'Block core', 'thickness' => 250.0, 'material' => 'MMA_Brick', 'enabled' => true },
          { 'name' => 'Interior plaster', 'thickness' => 15.0, 'material' => 'MMA_Plaster_Int', 'enabled' => true }
        ]
      when WallPresets::THICK_WALL
        [
          { 'name' => 'Exterior render', 'thickness' => 15.0, 'material' => 'MMA_Render_Ext', 'enabled' => true },
          { 'name' => 'Insulation', 'thickness' => 80.0, 'material' => 'MMA_Insulation_EPS', 'enabled' => true },
          { 'name' => 'Structural wall', 'thickness' => 300.0, 'material' => 'MMA_Concrete', 'enabled' => true },
          { 'name' => 'Interior plaster', 'thickness' => 15.0, 'material' => 'MMA_Plaster_Int', 'enabled' => true }
        ]
      when WallPresets::PARTITION
        [
          { 'name' => 'Gypsum board', 'thickness' => 12.5, 'material' => 'MMA_Drywall_Board', 'enabled' => true },
          { 'name' => 'Studs', 'thickness' => 90.0, 'material' => 'MMA_Metal_Stud', 'enabled' => true },
          { 'name' => 'Gypsum board', 'thickness' => 12.5, 'material' => 'MMA_Drywall_Board', 'enabled' => true }
        ]
      else
        [
          { 'name' => 'Layer 1', 'thickness' => 50.0, 'material' => 'MMA_Concrete', 'enabled' => true },
          { 'name' => 'Layer 2', 'thickness' => 50.0, 'material' => 'MMA_Render_Ext', 'enabled' => true }
        ]
      end
    end
  end
end
