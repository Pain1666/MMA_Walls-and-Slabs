# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Slab Builder
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'

module EuroWallSlab
  class SlabBuilder
    # Build or rebuild a multi-layer slab group from parameters
    # params:
    #   'points': Array of [x, y, z] points in mm defining the perimeter polygon
    #   'elevation': Base Z elevation in mm (default 0)
    #   'reference': 'top' (finished floor) or 'bottom' (soffit)
    #   'layers': Array of { 'name', 'thickness', 'material', 'enabled' }
    #   'openings': Array of { 'id', 'type', 'points': [[x,y,z], ...] }
    def self.build(model, params, target_group = nil)
      pts_raw = params['points'] || []
      return nil if pts_raw.length < 3

      elevation_in = GeometryHelper.mm(params['elevation'] || 0.0)
      reference = params['reference'] || 'top' # 'top' builds downward; 'bottom' builds upward
      layers = (params['layers'] || []).select { |l| l['enabled'] != false }
      openings = params['openings'] || []

      # Fallback layer if none specified
      if layers.empty?
        layers = [
          { 'name' => 'Concrete Slab', 'thickness' => 200.0, 'material' => 'EWS_Concrete', 'enabled' => true }
        ]
      end

      # Outer polygon points in SketchUp internal inches at base elevation
      outer_pts = pts_raw.map do |p|
        Geom::Point3d.new(
          GeometryHelper.mm(p[0]),
          GeometryHelper.mm(p[1]),
          elevation_in
        )
      end

      # Hole polygons in internal inches
      holes_pts = openings.map do |op|
        (op['points'] || []).map do |p|
          Geom::Point3d.new(
            GeometryHelper.mm(p[0]),
            GeometryHelper.mm(p[1]),
            elevation_in
          )
        end
      end.reject { |h| h.length < 3 }

      model.start_operation('Build Euro Slab', true)

      slab_group = target_group || model.active_entities.add_group
      entities = slab_group.entities
      entities.clear! unless target_group.nil?

      # Calculate total thickness
      total_thk_in = layers.sum { |l| GeometryHelper.mm(l['thickness'].to_f) }

      # Current Z level for layer creation
      current_z_in = elevation_in
      direction_factor = reference == 'top' ? -1.0 : 1.0

      # If reference is 'bottom', layers stack upward from current_z_in
      # If reference is 'top', layers stack downward: each layer starts at current_z_in and pushpulls down
      layers.each do |layer|
        thk_in = GeometryHelper.mm(layer['thickness'].to_f)
        next if thk_in <= 0.001

        layer_group = entities.add_group
        layer_group.name = "Layer: #{layer['name']} (#{layer['thickness'].to_f.round}mm)"
        mat = GeometryHelper.get_or_create_material(model, layer['material'])
        layer_group.material = mat if mat
        l_entities = layer_group.entities

        # Shift outer points to current Z
        layer_outer_pts = outer_pts.map do |pt|
          Geom::Point3d.new(pt.x, pt.y, current_z_in)
        end

        outer_face = l_entities.add_face(layer_outer_pts)
        next unless outer_face

        # Add holes if any
        holes_pts.each do |h_pts|
          layer_h_pts = h_pts.map do |pt|
            Geom::Point3d.new(pt.x, pt.y, current_z_in)
          end
          h_face = l_entities.add_face(layer_h_pts)
          h_face.erase! if h_face && h_face.valid?
        end

        # Extrude layer
        push_dist = thk_in * direction_factor
        # Normal check: outer_face normal might point up or down
        if (outer_face.normal.z > 0 && push_dist > 0) || (outer_face.normal.z < 0 && push_dist < 0)
          outer_face.pushpull(push_dist.abs)
        else
          outer_face.pushpull(-push_dist.abs)
        end

        # Apply layer material
        if mat
          l_entities.grep(Sketchup::Face).each do |f|
            f.material = mat
            f.back_material = mat
          end
        end

        # Advance current Z
        current_z_in += (thk_in * direction_factor)
      end

      # Tag slab group with parameters
      slab_group.set_attribute(DICT_NAME, ATTR_TYPE, 'slab')
      slab_group.set_attribute(DICT_NAME, ATTR_DATA, params.to_json)
      slab_group.set_attribute(DICT_NAME, ATTR_VERSION, '1.0.0')

      total_thk_mm = GeometryHelper.to_mm(total_thk_in).round
      slab_group.name = "Slab [#{layers.count} Layers] - #{total_thk_mm}mm thk"

      model.commit_operation
      slab_group
    end

    # Convert an existing planar SketchUp Face into a multi-layer slab
    def self.create_from_face(model, face, layers, reference = 'top')
      return nil unless face && face.valid? && face.is_a?(Sketchup::Face)

      # Extract outer boundary vertices
      outer_loop = face.outer_loop
      pts_mm = outer_loop.vertices.map do |v|
        [
          GeometryHelper.to_mm(v.position.x),
          GeometryHelper.to_mm(v.position.y),
          GeometryHelper.to_mm(v.position.z)
        ]
      end

      # Extract any inner loops (holes)
      openings = []
      face.loops.each do |loop|
        next if loop == outer_loop

        hole_pts = loop.vertices.map do |v|
          [
            GeometryHelper.to_mm(v.position.x),
            GeometryHelper.to_mm(v.position.y),
            GeometryHelper.to_mm(v.position.z)
          ]
        end
        openings << {
          'id' => "hole_#{openings.length + 1}",
          'type' => 'void',
          'points' => hole_pts
        }
      end

      avg_z_mm = pts_mm.sum { |p| p[2] } / pts_mm.length.to_f

      params = {
        'points' => pts_mm,
        'elevation' => avg_z_mm,
        'reference' => reference,
        'layers' => layers,
        'openings' => openings
      }

      build(model, params)
    end
  end
end
