# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Joiner Engine
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'geometry_helper'
require_relative 'wall_builder'

module MMA_WallsAndSlabs
  class WallJoiner
    def self.join_walls(model, wall1_group, wall2_group)
      return false unless wall1_group && wall1_group.valid? && wall2_group && wall2_group.valid?
      return false if wall1_group == wall2_group

      raw1 = wall1_group.get_attribute(DICT_NAME, ATTR_DATA)
      raw2 = wall2_group.get_attribute(DICT_NAME, ATTR_DATA)
      return false unless raw1 && raw2

      params1 = JSON.parse(raw1)
      params2 = JSON.parse(raw2)

      p1_start = Geom::Point3d.new(GeometryHelper.mm(params1['start_point'][0]), GeometryHelper.mm(params1['start_point'][1]), GeometryHelper.mm(params1['start_point'][2]))
      p1_end = Geom::Point3d.new(GeometryHelper.mm(params1['end_point'][0]), GeometryHelper.mm(params1['end_point'][1]), GeometryHelper.mm(params1['end_point'][2]))
      p2_start = Geom::Point3d.new(GeometryHelper.mm(params2['start_point'][0]), GeometryHelper.mm(params2['start_point'][1]), GeometryHelper.mm(params2['start_point'][2]))
      p2_end = Geom::Point3d.new(GeometryHelper.mm(params2['end_point'][0]), GeometryHelper.mm(params2['end_point'][1]), GeometryHelper.mm(params2['end_point'][2]))

      vec1 = p1_end - p1_start
      vec2 = p2_end - p2_start
      return false if vec1.length < 0.01 || vec2.length < 0.01

      d1 = vec1.normalize
      d2 = vec2.normalize
      line1 = [p1_start, d1]
      line2 = [p2_start, d2]
      int_pt = Geom.intersect_line_line(line1, line2)
      return false unless int_pt

      int_pt.z = (p1_start.z + p2_start.z) / 2.0
      wall1_group.set_attribute(DICT_NAME, ATTR_DATA, JSON.generate(params1))
      wall2_group.set_attribute(DICT_NAME, ATTR_DATA, JSON.generate(params2))

      true
    end
  end
end
