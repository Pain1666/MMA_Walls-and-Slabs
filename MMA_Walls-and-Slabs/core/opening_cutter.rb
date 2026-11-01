# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Slab Builder
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'

module MMA_WallsAndSlabs
  class SlabBuilder
    def self.serialize_group_data(group, params)
      payload = JSON.generate(params)
      existing = group.get_attribute(DICT_NAME, ATTR_DATA)
      return if existing == payload

      group.set_attribute(DICT_NAME, ATTR_DATA, payload)
    end

    def self.build(model, params, target_group = nil)
      pts_raw = params['points'] || []
      return nil if pts_raw.length < 3

      elevation_in = GeometryHelper.mm(params['elevation'] || 0.0)
      layers = (params['layers'] || []).select { |l| l['enabled'] != false }
      if layers.empty?
        layers = [{ 'name' => 'Concrete Slab', 'thickness' => 200.0, 'material' => 'EWS_Concrete', 'enabled' => true }]
      end

      model.start_operation('Build MMA Slab', true)
      slab_group = target_group || model.active_entities.add_group
      entities = slab_group.entities
      entities.clear! unless target_group.nil?
      slab_group.name = 'MMA Slab'
      slab_group.set_attribute(DICT_NAME, ATTR_TYPE, 'slab')
      serialize_group_data(slab_group, params)

      points = pts_raw.map { |p| Geom::Point3d.new(GeometryHelper.mm(p[0]), GeometryHelper.mm(p[1]), elevation_in) }
      layers.each do |layer|
        thk_in = GeometryHelper.mm(layer['thickness'].to_f)
        next if thk_in <= 0.001

        layer_group = entities.add_group
        layer_group.name = "Layer: #{layer['name']} (#{layer['thickness'].to_f.round}mm)"
        mat = GeometryHelper.get_or_create_material(model, layer['material'])
        layer_group.material = mat if mat
        face = layer_group.entities.add_face(points)
        face.pushpull(-thk_in) if face
      end

      model.commit_operation
      slab_group
    end

    def self.create_from_face(model, face, layers)
      return nil unless face

      pts = face.outer_loop.vertices.map { |v| [GeometryHelper.to_mm(v.position.x), GeometryHelper.to_mm(v.position.y), GeometryHelper.to_mm(v.position.z)] }
      params = { 'points' => pts, 'elevation' => 0.0, 'reference' => 'top', 'layers' => layers, 'openings' => [] }
      build(model, params)
    end
  end
end
