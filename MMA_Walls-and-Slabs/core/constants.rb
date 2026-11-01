# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Constants and Defaults
# ==============================================================================

module MMA_WallsAndSlabs
  DICT_NAME       = 'MMA_WallsAndSlabs'
  ATTR_TYPE       = 'object_type'
  ATTR_DATA       = 'parameters_json'
  ATTR_VERSION    = 'plugin_version'

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
      'EWS_Brick'          => 'BRICK_RED.jpg',
      'EWS_Render_Ext'     => 'STUCCO_LIGHT_TAN.jpg',
      'EWS_Drywall_Board'  => 'GYPSUMW_HORZ.jpg',
      'EWS_Plaster_Int'    => 'STUCCO_LIGHT_TAN.jpg',
      'EWS_Screed'         => 'CONCRETE.jpg',
      'EWS_Wood_Flooring'  => 'CONCRETE.jpg',
      'EWS_Ceramic_Tile'   => 'CONCRETE.jpg'
    }.freeze

    TEXTURE_SIZES = {
      'CONCRETE.jpg' => [600.0, 600.0],
      'BRICK_RED.jpg' => [600.0, 600.0],
      'STUCCO_LIGHT_TAN.jpg' => [600.0, 600.0],
      'GYPSUMW_HORZ.jpg' => [600.0, 600.0]
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
end
