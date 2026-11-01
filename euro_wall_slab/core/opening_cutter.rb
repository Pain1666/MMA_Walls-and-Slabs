# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Opening Cutter Manager
# ==============================================================================

require 'json'
require_relative 'constants'
require_relative 'wall_builder'
require_relative 'slab_builder'

module EuroWallSlab
  class OpeningCutter
    # Add an opening to a wall and rebuild
    def self.add_wall_opening(model, wall_group, opening_params)
      data_json = wall_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      params['openings'] ||= []

      # Assign unique ID if not present
      opening_params['id'] ||= "op_#{Time.now.to_i}_#{rand(1000)}"

      # Check if updating an existing opening or adding a new one
      existing_idx = params['openings'].find_index { |o| o['id'] == opening_params['id'] }
      if existing_idx
        params['openings'][existing_idx] = opening_params
      else
        params['openings'] << opening_params
      end

      WallBuilder.build(model, params, wall_group)
    end

    # Remove an opening from a wall and rebuild
    def self.remove_wall_opening(model, wall_group, opening_id)
      data_json = wall_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      params['openings'] ||= []
      params['openings'].reject! { |o| o['id'] == opening_id }

      WallBuilder.build(model, params, wall_group)
    end

    # Add a rectangular or polygon opening to a slab and rebuild
    def self.add_slab_opening(model, slab_group, opening_params)
      data_json = slab_group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil unless data_json

      params = JSON.parse(data_json)
      params['openings'] ||= []

      opening_params['id'] ||= "slab_op_#{Time.now.to_i}_#{rand(1000)}"

      existing_idx = params['openings'].find_index { |o| o['id'] == opening_params['id'] }
      if existing_idx
        params['openings'][existing_idx] = opening_params
      else
        params['openings'] << opening_params
      end

      SlabBuilder.build(model, params, slab_group)
    end
  end
end
