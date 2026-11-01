# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Geometry Utilities
# ==============================================================================

require 'sketchup.rb'
require_relative 'constants'

module MMA_WallsAndSlabs
  class GeometryHelper
    def self.mm(value)
      value.to_f / 25.4
    end

    def self.to_mm(value)
      value.to_f * 25.4
    end

    def self.get_or_create_material(model, material_name)
      return nil if material_name.nil? || material_name.to_s.empty?

      name = material_name.to_s
      materials = model.materials
      material = materials[name] || materials.add(name)
      color = DefaultMaterials::PALETTE[name]
      material.color = Sketchup::Color.new(*color) if color

      texture_file = DefaultMaterials::TEXTURE_FILES[name]
      texture_path = texture_file && File.join(File.dirname(__dir__), 'materials', texture_file)
      if texture_path && File.file?(texture_path)
        material.texture = texture_path
        texture_size = DefaultMaterials::TEXTURE_SIZES[texture_file]
        material.texture.size = texture_size.map { |size_mm| mm(size_mm) } if texture_size
      end
      material
    end
  end
end
