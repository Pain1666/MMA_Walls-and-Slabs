# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Opening Cutter Manager
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'wall_object'
require_relative 'wall_builder'
require_relative 'slab_builder'

module MMA_WallsAndSlabs
  class OpeningCutter
    def self.add_wall_openings(model, wall_group, new_openings)
      return nil unless wall_group && wall_group.valid?

      openings = Array(new_openings).compact
      return nil if openings.empty?

      data_json = wall_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      WallModel.transform_points!(params, wall_group.transformation)
      params['openings'] ||= []

      openings.each do |opening|
        next if opening.nil?

        item = opening.dup
        item['id'] ||= "op_#{Time.now.to_i}_#{rand(1000)}"
        params['openings'] << item
      end

      WallBuilder.build(model, params, wall_group)
    end

    def self.add_wall_opening(model, wall_group, opening_params)
      add_wall_openings(model, wall_group, [opening_params])
    end

    def self.add_slab_openings(model, slab_group, new_openings)
      return nil unless slab_group && slab_group.valid?

      openings = Array(new_openings).compact
      return nil if openings.empty?

      data_json = slab_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      params['openings'] ||= []

      openings.each do |opening|
        next if opening.nil?

        item = opening.dup
        item['id'] ||= "slab_op_#{Time.now.to_i}_#{rand(1000)}"
        params['openings'] << item
      end

      SlabBuilder.build(model, params, slab_group)
    end

    def self.add_slab_opening(model, slab_group, opening_params)
      add_slab_openings(model, slab_group, [opening_params])
    end
  end
end
