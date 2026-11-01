# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - SketchUp Extension
# Parametric European Multi-Layer Walls, Slabs, and Openings (Metric / mm)
# Compatible with SketchUp 2023+
# ==============================================================================

require 'sketchup.rb'
require 'extensions.rb'

module EuroWallSlab
  unless file_loaded?(__FILE__)
    ext_file = File.join(File.dirname(__FILE__), 'euro_wall_slab', 'main.rb')
    extension = SketchupExtension.new('Euro Wall & Slab', ext_file)

    extension.description = 'Parametric European multi-layer walls (Concrete, Brick, Laterizio, Cartongesso), slabs, and openings in millimeters.'
    extension.version     = '1.0.0'
    extension.creator     = 'Custom BIM Tools'
    extension.copyright   = '2026'

    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
