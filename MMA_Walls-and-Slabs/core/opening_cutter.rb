# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Opening Cutter Manager
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'wall_builder'
require_relative 'slab_builder'

module MMA_WallsAndSlabs
  class OpeningCutter
    def self.add_wall_opening(model, wall_group, opening_params)
      data_json = wall_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      params['openings'] ||= []
      opening_params['id'] ||= "op_#{Time.now.to_i}_#{rand(1000)}"
      params['openings'] << opening_params
      WallBuilder.build(model, params, wall_group)
    end

    def self.add_slab_opening(model, slab_group, opening_params)
      data_json = slab_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      params['openings'] ||= []
      opening_params['id'] ||= "slab_op_#{Time.now.to_i}_#{rand(1000)}"
      params['openings'] << opening_params
      SlabBuilder.build(model, params, slab_group)
    end
  end
end
