# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Model + Presets
# ==============================================================================

require 'json'
require_relative 'constants'

module MMA_WallsAndSlabs
  class WallModel
    DEFAULT_WALL_PARAMS = {
      'height' => Defaults::WALL_HEIGHT,
      'justification' => Defaults::WALL_JUSTIFICATION,
      'core_type' => CoreType::POROTON,
      'core_thickness' => Defaults::CORE_THICKNESS[CoreType::POROTON],
      'core_material' => 'EWS_Laterizio',
      'wall_type' => WallPresets::GENERIC,
      'start_point' => [0.0, 0.0, 0.0],
      'end_point' => [1000.0, 0.0, 0.0],
      'ext_layers' => [
        { 'name' => 'Exterior render', 'thickness' => 15.0, 'material' => 'EWS_Render_Ext', 'enabled' => true },
        { 'name' => 'Insulation', 'thickness' => 100.0, 'material' => 'EWS_Insulation_EPS', 'enabled' => true }
      ],
      'int_layers' => [
        { 'name' => 'Interior plaster', 'thickness' => 15.0, 'material' => 'EWS_Plaster_Int', 'enabled' => true }
      ],
      'openings' => []
    }.freeze

    def self.valid_wall_group?(group)
      return false unless group && group.valid?

      begin
        group.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall'
      rescue StandardError
        false
      end
    end

    def self.from_group(group)
      return nil unless valid_wall_group?(group)

      data = group.get_attribute(DICT_NAME, ATTR_DATA)
      return nil if data.nil? || data.empty?

      params = JSON.parse(data)
      new(params)
    rescue StandardError
      nil
    end

    def initialize(params = {})
      @params = DEFAULT_WALL_PARAMS.merge((params || {}).transform_keys(&:to_s))
    end

    attr_reader :params

    def start_point
      Array(@params['start_point']).map(&:to_f)
    end

    def end_point
      Array(@params['end_point']).map(&:to_f)
    end

    def height
      @params['height'].to_f
    end

    def justification
      @params['justification'] || Defaults::WALL_JUSTIFICATION
    end

    def midpoint
      x1, y1, z1 = start_point
      x2, y2, z2 = end_point
      [((x1 + x2) / 2.0), ((y1 + y2) / 2.0), ((z1 + z2) / 2.0)]
    end

    def apply_preset(preset_name)
      preset = preset_name.to_s
      layers = WallTypeCatalog.default_for(preset)
      @params['wall_type'] = preset
      @params['ext_layers'] = layers.select { |l| l['name'] !~ /Interior|Stud/ }
      @params['int_layers'] = layers.select { |l| l['name'] =~ /Interior|Stud/ }
      @params['ext_layers'] = [] if @params['ext_layers'].empty?
      @params['int_layers'] = [] if @params['int_layers'].empty?
      self
    end

    def set_start_point(point)
      @params['start_point'] = Array(point).map(&:to_f)
    end

    def set_end_point(point)
      @params['end_point'] = Array(point).map(&:to_f)
    end

    def set_height(value)
      @params['height'] = value.to_f
    end

    def set_justification(value)
      @params['justification'] = value.to_s
    end

    def move(dx, dy, dz)
      start = start_point
      finish = end_point
      @params['start_point'] = [start[0] + dx, start[1] + dy, start[2] + dz]
      @params['end_point'] = [finish[0] + dx, finish[1] + dy, finish[2] + dz]
    end

    def flip_direction
      @params['start_point'], @params['end_point'] = end_point, start_point
    end

    def save_to_group(group)
      return false unless group && group.valid?

      group.set_attribute(DICT_NAME, ATTR_TYPE, 'wall')
      group.set_attribute(DICT_NAME, ATTR_DATA, JSON.generate(@params))
      true
    end
  end
end
