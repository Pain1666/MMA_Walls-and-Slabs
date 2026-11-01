# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Wall Joiner Engine
# Connects and extends two independently created Euro Walls at their intersection,
# seamlessly joining structural cores and all layers with mitered corner joints.
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'
require_relative 'wall_builder'

module EuroWallSlab
  class WallJoiner
    # Join two Euro Wall groups at their baseline intersection point
    def self.join_walls(model, wall1_group, wall2_group)
      return false unless wall1_group && wall1_group.valid? && wall2_group && wall2_group.valid?
      return false if wall1_group == wall2_group

      raw1 = wall1_group.get_attribute(DICT_NAME, ATTR_DATA)
      raw2 = wall2_group.get_attribute(DICT_NAME, ATTR_DATA)
      return false unless raw1 && raw2

      params1 = JSON.parse(raw1)
      params2 = JSON.parse(raw2)

      p1_start = Geom::Point3d.new(
        GeometryHelper.mm(params1['start_point'][0]),
        GeometryHelper.mm(params1['start_point'][1]),
        GeometryHelper.mm(params1['start_point'][2])
      )
      p1_end = Geom::Point3d.new(
        GeometryHelper.mm(params1['end_point'][0]),
        GeometryHelper.mm(params1['end_point'][1]),
        GeometryHelper.mm(params1['end_point'][2])
      )

      p2_start = Geom::Point3d.new(
        GeometryHelper.mm(params2['start_point'][0]),
        GeometryHelper.mm(params2['start_point'][1]),
        GeometryHelper.mm(params2['start_point'][2])
      )
      p2_end = Geom::Point3d.new(
        GeometryHelper.mm(params2['end_point'][0]),
        GeometryHelper.mm(params2['end_point'][1]),
        GeometryHelper.mm(params2['end_point'][2])
      )

      vec1 = p1_end - p1_start
      vec2 = p2_end - p2_start
      return false if vec1.length < 0.01 || vec2.length < 0.01

      d1 = vec1.normalize
      d2 = vec2.normalize

      # Intersect horizontal baselines
      line1 = [p1_start, d1]
      line2 = [p2_start, d2]

      int_pt = Geom.intersect_line_line(line1, line2)
      return false unless int_pt # Parallel walls do not intersect

      # Preserve average wall Z elevation
      int_pt.z = (p1_start.z + p2_start.z) / 2.0

      # Determine which end of Wall 1 meets int_pt
      w1_end_closer = p1_end.distance(int_pt) < p1_start.distance(int_pt)
      # Determine which end of Wall 2 meets int_pt
      w2_end_closer = p2_end.distance(int_pt) < p2_start.distance(int_pt)

      p1_other = w1_end_closer ? p1_start : p1_end
      p2_other = w2_end_closer ? p2_start : p2_end

      # Update Wall 1 geometry and adjacent corner reference
      if w1_end_closer
        params1['end_point'] = [GeometryHelper.to_mm(int_pt.x), GeometryHelper.to_mm(int_pt.y), GeometryHelper.to_mm(int_pt.z)]
        params1['next_corner_point'] = [GeometryHelper.to_mm(p2_other.x), GeometryHelper.to_mm(p2_other.y), GeometryHelper.to_mm(p2_other.z)]
      else
        params1['start_point'] = [GeometryHelper.to_mm(int_pt.x), GeometryHelper.to_mm(int_pt.y), GeometryHelper.to_mm(int_pt.z)]
        params1['prev_corner_point'] = [GeometryHelper.to_mm(p2_other.x), GeometryHelper.to_mm(p2_other.y), GeometryHelper.to_mm(p2_other.z)]
      end

      # Update Wall 2 geometry and adjacent corner reference
      if w2_end_closer
        params2['end_point'] = [GeometryHelper.to_mm(int_pt.x), GeometryHelper.to_mm(int_pt.y), GeometryHelper.to_mm(int_pt.z)]
        params2['next_corner_point'] = [GeometryHelper.to_mm(p1_other.x), GeometryHelper.to_mm(p1_other.y), GeometryHelper.to_mm(p1_other.z)]
      else
        params2['start_point'] = [GeometryHelper.to_mm(int_pt.x), GeometryHelper.to_mm(int_pt.y), GeometryHelper.to_mm(int_pt.z)]
        params2['prev_corner_point'] = [GeometryHelper.to_mm(p1_other.x), GeometryHelper.to_mm(p1_other.y), GeometryHelper.to_mm(p1_other.z)]
      end

      model.start_operation('Join Euro Walls', true)
      WallBuilder.build(model, params1, wall1_group)
      WallBuilder.build(model, params2, wall2_group)
      model.commit_operation

      true
    end
  end
end
