# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Builder
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'

module MMA_WallsAndSlabs
  class WallBuilder
    def self.build(model, params, target_group = nil)
      return nil if params.nil?

      p0 = params['start_point'] || [0, 0, 0]
      p1 = params['end_point'] || [100, 0, 0]
      height_mm = (params['height'] || Defaults::WALL_HEIGHT).to_f
      height_in = GeometryHelper.mm(height_mm)
      wall_group = target_group || model.active_entities.add_group
      entities = wall_group.entities
      entities.clear! unless target_group.nil?
      wall_group.name = 'MMA Wall'
      wall_group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      wall_group.set_attribute(DICT_NAME, ATTR_DATA, JSON.generate(params))

      p_start = Geom::Point3d.new(GeometryHelper.mm(p0[0]), GeometryHelper.mm(p0[1]), GeometryHelper.mm(p0[2]))
      p_end = Geom::Point3d.new(GeometryHelper.mm(p1[0]), GeometryHelper.mm(p1[1]), GeometryHelper.mm(p1[2]))
      vx = p_end - p_start
      if vx.length < 0.001
        vx = Geom::Vector3d.new(1, 0, 0)
      end
      vy = Geom::Vector3d.new(0, 1, 0)
      vz = Geom::Vector3d.new(0, 0, 1)

      ext_layers = params['ext_layers'] || []
      int_layers = params['int_layers'] || []

      current_y = 0.0
      ext_layers.each do |layer|
        next if layer['enabled'] == false
        thk = GeometryHelper.mm(layer['thickness'].to_f)
        next if thk <= 0.001

        layer_group = entities.add_group
        layer_group.name = "Ext Layer: #{layer['name']} (#{layer['thickness'].to_f.round}mm)"
        mat = GeometryHelper.get_or_create_material(model, layer['material'])
        layer_group.material = mat if mat

        pts = [
          p_start,
          p_end,
          p_end + vy*thk,
          p_start + vy*thk
        ]
        face = layer_group.entities.add_face(pts)
        face.pushpull(height_in) if face
        current_y += thk
      end

      wall_group
    end
  end
end
