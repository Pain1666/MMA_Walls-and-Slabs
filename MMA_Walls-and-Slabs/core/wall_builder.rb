# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Object Model
# ==============================================================================

require 'json'
require_relative 'constants'

module MMA_WallsAndSlabs
  module WallJustification
    LEFT   = 'left'
    CENTER = 'center'
    RIGHT  = 'right'
    ALL    = [LEFT, CENTER, RIGHT].freeze
  end

  class WallModel
    attr_accessor :group
    attr_reader :params

    def initialize(params = {})
      @params = normalize_params(params)
    end

    def self.from_group(group)
      return nil unless group && group.valid?
      return nil unless valid_wall_group?(group)

      raw = group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil if raw.nil? || raw.to_s.strip.empty?

      begin
        params = JSON.parse(raw)
        new(params).tap { |model| model.group = group }
      rescue JSON::ParserError
        nil
      end
    end

    def self.valid_wall_group?(group)
      return false unless group && group.valid?

      group.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall'
    end

    def self.find_wall_groups(model)
      return [] unless model

      model.entities.grep(Sketchup::Group).select { |g| valid_wall_group?(g) }
    end

    def self.persist(group, params)
      return nil unless group && group.valid?

      model = new(params)
      group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      group.set_attribute(DICT_NAME, ATTR_DATA, model.serialize)
      group
    end

    def self.default_params(overrides = {})
      params = {
        'start_point' => [0.0, 0.0, 0.0],
        'end_point' => [1000.0, 0.0, 0.0],
        'height' => Defaults::WALL_HEIGHT,
        'justification' => Defaults::WALL_JUSTIFICATION,
        'core_type' => CoreType::POROTON,
        'core_thickness' => Defaults::CORE_THICKNESS[CoreType::POROTON],
        'ext_layers' => [
          { 'name' => 'External Render', 'thickness' => 15.0, 'material' => 'EWS_Render_Ext', 'enabled' => true },
          { 'name' => 'Insulation', 'thickness' => 100.0, 'material' => 'EWS_Insulation_EPS', 'enabled' => true }
        ],
        'int_layers' => [
          { 'name' => 'Internal Plaster', 'thickness' => 15.0, 'material' => 'EWS_Plaster_Int', 'enabled' => true }
        ],
        'openings' => [],
        'wall_type' => 'generic'
      }

      params.merge!(overrides)
      new(params).params
    end

    def serialize
      JSON.generate(@params)
    end

    def start_point
      normalize_point(@params['start_point'])
    end

    def end_point
      normalize_point(@params['end_point'])
    end

    def set_start_point(point)
      @params['start_point'] = normalize_point(point)
      self
    end

    def set_end_point(point)
      @params['end_point'] = normalize_point(point)
      self
    end

    def move(delta_x, delta_y, delta_z = 0.0)
      start = start_point
      finish = end_point
      set_start_point([start[0] + delta_x.to_f, start[1] + delta_y.to_f, start[2] + delta_z.to_f])
      set_end_point([finish[0] + delta_x.to_f, finish[1] + delta_y.to_f, finish[2] + delta_z.to_f])
      self
    end

    def resize_length(new_length_mm)
      length = length_mm
      return self if length <= 0.0 || new_length_mm.to_f <= 0.0

      direction = direction_vector
      normalized = [
        direction[0] / length,
        direction[1] / length,
        direction[2] / length
      ]

      set_end_point([
        start_point[0] + (normalized[0] * new_length_mm.to_f),
        start_point[1] + (normalized[1] * new_length_mm.to_f),
        start_point[2] + (normalized[2] * new_length_mm.to_f)
      ])
      self
    end

    def set_height(value)
      @params['height'] = value.to_f
      self
    end

    def set_justification(value)
      clean = value.to_s
      @params['justification'] = WallJustification::ALL.include?(clean) ? clean : Defaults::WALL_JUSTIFICATION
      self
    end

    def flip_direction
      temp = start_point
      set_start_point(end_point)
      set_end_point(temp)
      self
    end

    def height
      @params['height'].to_f
    end

    def justification
      value = @params['justification'].to_s
      WallJustification::ALL.include?(value) ? value : Defaults::WALL_JUSTIFICATION
    end

    def wall_type
      @params['wall_type'].to_s
    end

    def core_type
      @params['core_type'].to_s
    end

    def core_thickness
      @params['core_thickness'].to_f
    end

    def ext_layers
      normalize_layers(@params['ext_layers'])
    end

    def int_layers
      normalize_layers(@params['int_layers'])
    end

    def layers
      ext_layers + int_layers
    end

    def openings
      Array(@params['openings']).compact
    end

    def points
      [start_point, end_point]
    end

    def length_mm
      dx = end_point[0] - start_point[0]
      dy = end_point[1] - start_point[1]
      dz = end_point[2] - start_point[2]
      Math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
    end

    def midpoint
      sx, sy, sz = start_point
      ex, ey, ez = end_point
      [(sx + ex) / 2.0, (sy + ey) / 2.0, (sz + ez) / 2.0]
    end

    def direction_vector
      dx = end_point[0] - start_point[0]
      dy = end_point[1] - start_point[1]
      dz = end_point[2] - start_point[2]
      length = Math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
      return [0.0, 0.0, 0.0] if length <= 0.0

      [dx / length, dy / length, dz / length]
    end

    def total_width_mm
      ext_layers.reduce(0.0) { |sum, layer| sum + (layer['enabled'] ? layer['thickness'].to_f : 0.0) } +
        int_layers.reduce(0.0) { |sum, layer| sum + (layer['enabled'] ? layer['thickness'].to_f : 0.0) }
    end

    def save_to_group(target_group = @group)
      return nil unless target_group && target_group.valid?

      target_group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      target_group.set_attribute(DICT_NAME, ATTR_DATA, serialize)
      @group = target_group
      target_group
    end

    private

    def normalize_params(params)
      normalized = {}
      normalized['start_point'] = normalize_point(params['start_point'] || [0.0, 0.0, 0.0])
      normalized['end_point'] = normalize_point(params['end_point'] || [1000.0, 0.0, 0.0])
      normalized['height'] = (params['height'] || Defaults::WALL_HEIGHT).to_f
      normalized['justification'] = WallJustification::ALL.include?(params['justification']) ? params['justification'] : Defaults::WALL_JUSTIFICATION
      normalized['core_type'] = params['core_type'] || CoreType::POROTON
      normalized['core_thickness'] = (params['core_thickness'] || Defaults::CORE_THICKNESS[normalized['core_type']] || 250.0).to_f
      normalized['ext_layers'] = normalize_layers(params['ext_layers'])
      normalized['int_layers'] = normalize_layers(params['int_layers'])
      normalized['openings'] = Array(params['openings']).compact
      normalized['wall_type'] = params['wall_type'] || 'generic'
      normalized
    end

    def normalize_layers(layers)
      Array(layers).map do |layer|
        next nil if layer.nil?

        {
          'name' => layer['name'] || 'Layer',
          'thickness' => (layer['thickness'] || 0.0).to_f,
          'material' => layer['material'] || 'EWS_Concrete',
          'enabled' => layer.key?('enabled') ? !!layer['enabled'] : true
        }
      end.compact
    end

    def normalize_point(point)
      if point.respond_to?(:x) && point.respond_to?(:y) && point.respond_to?(:z)
        arr = [point.x.to_f, point.y.to_f, point.z.to_f]
      else
        arr = Array(point).map { |value| value.to_f }
      end

      arr = [arr[0] || 0.0, arr[1] || 0.0, arr[2] || 0.0]
      arr[0, 3]
    end
  end
end
