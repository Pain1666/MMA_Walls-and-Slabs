# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Geometry Utilities
# ==============================================================================

require 'sketchup'
require_relative 'constants'

module MMA_WallsAndSlabs
  class GeometryHelper
    def self.mm(value)
      value.to_f / 1000.0
    end

    def self.to_mm(value)
      value.to_f * 1000.0
    end

    def self.get_or_create_material(model, material_name)
      return nil if material_name.nil? || material_name.to_s.empty?

      name = material_name.to_s
      model.materials[name] || model.materials.add(name)
    end
  end
end
