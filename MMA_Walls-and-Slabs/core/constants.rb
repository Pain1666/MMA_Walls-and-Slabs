# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Constants and Defaults
# ==============================================================================

module MMA_WallsAndSlabs
  DICT_NAME    = 'MMA_WallsAndSlabs'
  ATTR_TYPE    = 'object_type'
  ATTR_DATA    = 'parameters_json'
  ATTR_VERSION = 'plugin_version'

  module CoreType
    CONCRETE   = 'concrete'
    POROTON    = 'poroton'
    BRICK      = 'brick'
    AAC_BLOCK  = 'aac_block'
    DRYWALL    = 'drywall'

    ALL = [CONCRETE, POROTON, BRICK, AAC_BLOCK, DRYWALL].freeze

    LABELS = {
      CONCRETE  => 'Concrete (Calcestruzzo armato)',
      POROTON   => 'Hollow Clay Block (Laterizio / Poroton)',
      BRICK     => 'Solid Brick (Mattone pieno)',
      AAC_BLOCK => 'Aerated Concrete (Ytong / Blocco cls)',
      DRYWALL   => 'Drywall Partition (Cartongesso)'
    }.freeze
  end

  module DefaultMaterials
    PALETTE = {
      'EWS_Concrete'       => [190, 192, 195],
      'EWS_Laterizio'      => [208, 92, 48],
      'EWS_Brick'          => [168, 52, 38],
      'EWS_Ytong'          => [230, 230, 225],
      'EWS_Metal_Stud'     => [118, 134, 150],
      'EWS_Drywall_Board'  => [232, 228, 218],
      'EWS_Insulation_EPS' => [246, 238, 115],
      'EWS_Render_Ext'     => [240, 236, 226],
      'EWS_Plaster_Int'    => [250, 250, 248],
      'EWS_Screed'         => [155, 155, 155],
      'EWS_Wood_Flooring'  => [192, 145, 88],
      'EWS_Ceramic_Tile'   => [145, 135, 125]
    }.freeze

    TEXTURE_FILES = {
      'EWS_Concrete'       => 'CONCRETE.jpg',
      'EWS_Laterizio'      => 'BRICK_RED.jpg',
      'EWS_Brick'          => 'BRICK_RED.jpg',
      'EWS_Render_Ext'     => 'STUCCO_LIGHT_TAN.jpg',
      'EWS_Drywall_Board'  => 'GYPSUMW_HORZ.jpg',
      'EWS_Plaster_Int'    => 'STUCCO_LIGHT_TAN.jpg',
      'EWS_Insulation_EPS' => 'XPS_FOAM_R100_NOBORDER.jpg',
      'EWS_Screed'         => 'CONCRETE.jpg',
      'EWS_Wood_Flooring'  => 'CONCRETE.jpg',
      'EWS_Ceramic_Tile'   => 'CONCRETE.jpg'
    }.freeze

    TEXTURE_SIZES = {
      'CONCRETE.jpg' => [600.0, 600.0],
      'BRICK_RED.jpg' => [600.0, 600.0],
      'STUCCO_LIGHT_TAN.jpg' => [600.0, 600.0],
      'GYPSUMW_HORZ.jpg' => [600.0, 600.0],
      'XPS_FOAM_R100_NOBORDER.jpg' => [600.0, 600.0]
    }.freeze
  end

  module Defaults
    WALL_HEIGHT = 2800.0
    WALL_JUSTIFICATION = 'center'
    CORE_THICKNESS = {
      CoreType::CONCRETE => 250.0,
      CoreType::POROTON => 250.0,
      CoreType::BRICK => 250.0,
      CoreType::AAC_BLOCK => 200.0,
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
    LEFT = 'left'
    RIGHT = 'right'
    ALL = [CENTER, LEFT, RIGHT].freeze
  end

  module WallTypeCatalog
    def self.default_for(preset)
      case preset.to_s
      when WallPresets::GENERIC
        [
          { 'name' => 'Exterior render', 'thickness' => 15.0, 'material' => 'EWS_Render_Ext', 'enabled' => true },
          { 'name' => 'Insulation', 'thickness' => 100.0, 'material' => 'EWS_Insulation_EPS', 'enabled' => true },
          { 'name' => 'Block core', 'thickness' => 250.0, 'material' => 'EWS_Laterizio', 'enabled' => true },
          { 'name' => 'Interior plaster', 'thickness' => 15.0, 'material' => 'EWS_Plaster_Int', 'enabled' => true }
        ]
      when WallPresets::THICK_WALL
        [
          { 'name' => 'Exterior render', 'thickness' => 15.0, 'material' => 'EWS_Render_Ext', 'enabled' => true },
          { 'name' => 'Insulation', 'thickness' => 80.0, 'material' => 'EWS_Insulation_EPS', 'enabled' => true },
          { 'name' => 'Structural wall', 'thickness' => 300.0, 'material' => 'EWS_Concrete', 'enabled' => true },
          { 'name' => 'Interior plaster', 'thickness' => 15.0, 'material' => 'EWS_Plaster_Int', 'enabled' => true }
        ]
      when WallPresets::PARTITION
        [
          { 'name' => 'Gypsum board', 'thickness' => 12.5, 'material' => 'EWS_Drywall_Board', 'enabled' => true },
          { 'name' => 'Studs', 'thickness' => 90.0, 'material' => 'EWS_Metal_Stud', 'enabled' => true },
          { 'name' => 'Gypsum board', 'thickness' => 12.5, 'material' => 'EWS_Drywall_Board', 'enabled' => true }
        ]
      else
        [
          { 'name' => 'Layer 1', 'thickness' => 50.0, 'material' => 'EWS_Concrete', 'enabled' => true },
          { 'name' => 'Layer 2', 'thickness' => 50.0, 'material' => 'EWS_Render_Ext', 'enabled' => true }
        ]
      end
    end
  end
end
