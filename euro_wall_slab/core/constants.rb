# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Constants and Defaults
# ==============================================================================

module EuroWallSlab
  DICT_NAME       = 'EuroWallSlab'
  ATTR_TYPE       = 'object_type'     # 'wall' or 'slab'
  ATTR_DATA       = 'parameters_json' # Full JSON parameters
  ATTR_VERSION    = 'plugin_version'

  module CoreType
    CONCRETE   = 'concrete'    # Reinforced concrete / Calcestruzzo armato
    POROTON    = 'poroton'     # Hollow clay block / Laterizio forato
    BRICK      = 'brick'       # Solid clay brick / Mattone pieno
    AAC_BLOCK  = 'aac_block'   # Aerated concrete / Ytong / Blocco in cls
    DRYWALL    = 'drywall'     # Metal stud drywall / Cartongesso

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
    # Standard European Palette with vibrant, distinct RGB colors
    PALETTE = {
      'EWS_Concrete'       => [190, 192, 195], # Crisp concrete gray
      'EWS_Laterizio'      => [208, 92, 48],   # Warm terracotta / Laterizio
      'EWS_Brick'          => [168, 52, 38],   # Deep brick red
      'EWS_Ytong'          => [230, 230, 225], # Pale aerated block white
      'EWS_Metal_Stud'     => [118, 134, 150], # Slate gray galvanized steel
      'EWS_Drywall_Board'  => [232, 228, 218], # Gypsum off-white
      'EWS_Insulation_EPS' => [246, 238, 115], # Bright insulation foam yellow
      'EWS_Render_Ext'     => [240, 236, 226], # Stucco / Intonaco esterno
      'EWS_Plaster_Int'    => [250, 250, 248], # Clean interior white plaster
      'EWS_Screed'         => [155, 155, 155], # Cement screed / massetto
      'EWS_Wood_Flooring'  => [192, 145, 88],  # Warm oak parquet
      'EWS_Ceramic_Tile'   => [145, 135, 125]  # Slate tile gray
    }.freeze

    # Texture image filename mapping (located in materials/ folder)
    TEXTURE_FILES = {
      'EWS_Concrete'       => 'CONCRETE.jpg',
      'EWS_Brick'          => 'BRICK_RED.jpg',
      'EWS_Render_Ext'     => 'STUCCO_LIGHT_TAN.jpg',
      'EWS_Drywall_Board'  => 'GYPSUMW_HORZ.jpg',
      'EWS_Insulation_EPS' => 'XPS_FOAM_R100_NOBORDER.jpg'
    }.freeze

    # Texture real-world dimensions in mm [width, height]
    TEXTURE_SIZES = {
      'CONCRETE.jpg'               => [600.0, 600.0],
      'BRICK_RED.jpg'              => [500.0, 500.0],
      'STUCCO_LIGHT_TAN.jpg'       => [800.0, 800.0],
      'GYPSUMW_HORZ.jpg'           => [1200.0, 600.0],
      'XPS_FOAM_R100_NOBORDER.jpg' => [600.0, 600.0]
    }.freeze
  end

  module Defaults
    # Wall Defaults in mm
    WALL_HEIGHT          = 2800.0
    WALL_JUSTIFICATION   = 'center' # 'center', 'exterior', 'interior'

    # Core Thicknesses in mm
    CORE_THICKNESS = {
      CoreType::CONCRETE  => 200.0,
      CoreType::POROTON   => 250.0,
      CoreType::BRICK     => 120.0,
      CoreType::AAC_BLOCK => 200.0,
      CoreType::DRYWALL   => 75.0  # Stud width: 75mm (total will include boards)
    }.freeze

    # Drywall specific defaults
    DRYWALL_STUD_SPACING = 600.0 # mm
    DRYWALL_STUD_WIDTH   = 75.0  # mm
    DRYWALL_STUD_DEPTH   = 40.0  # mm (C-channel flange)
    DRYWALL_STUD_THICK   = 1.5   # mm metal gauge
    DRYWALL_BOARD_THICK  = 12.5  # mm standard Placo / Knauf board
    DRYWALL_BOARDS_EXT   = 1     # 1 or 2 boards
    DRYWALL_BOARDS_INT   = 1     # 1 or 2 boards

    # Slab Defaults in mm
    SLAB_THICKNESS = 200.0
  end
end
