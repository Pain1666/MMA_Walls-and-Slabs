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
      transform_points!(params, group.transformation)
      new(params)
    rescue StandardError
      nil
    end

    def self.transform_points!(params, transformation)
      %w[start_point end_point].each do |key|
        params[key] = transform_point(params[key], transformation) if params[key].is_a?(Array)
      end
      if params['path_points'].is_a?(Array)
        params['path_points'] = params['path_points'].map do |point|
          transform_point(point, transformation)
        end
        params['start_point'] = params['path_points'].first
        params['end_point'] = params['path_points'].last
      end
      params
    end

    def self.transform_point(point, transformation)
      return point unless point.is_a?(Array) && point.length >= 3

      local_point = Geom::Point3d.new(point[0].to_f / 25.4, point[1].to_f / 25.4, point[2].to_f / 25.4)
      world_point = local_point.transform(transformation)
      [world_point.x * 25.4, world_point.y * 25.4, world_point.z * 25.4]
    end

    def initialize(params = {})
      @params = DEFAULT_WALL_PARAMS.merge((params || {}).transform_keys(&:to_s))
    end

    attr_reader :params

    def path_points
      points = @params['path_points']
      points.is_a?(Array) ? points.map { |point| Array(point).first(3).map(&:to_f) } : nil
    end

    def path_closed?
      @params['path_closed'] == true
    end

    def start_point
      points = path_points
      (points ? points.first : @params['start_point']).map(&:to_f)
    end

    def end_point
      points = path_points
      (points ? points.last : @params['end_point']).map(&:to_f)
    end

    def height
      @params['height'].to_f
    end

    def justification
      @params['justification'] || Defaults::WALL_JUSTIFICATION
    end

    def midpoint
      points = path_points
      if points && !points.empty?
        count = points.length.to_f
        return 3.times.map { |axis| points.sum { |point| point[axis] } / count }
      end

      x1, y1, z1 = start_point
      x2, y2, z2 = end_point
      [((x1 + x2) / 2.0), ((y1 + y2) / 2.0), ((z1 + z2) / 2.0)]
    end

    def set_path_points(points)
      clean_points = Array(points).map { |point| Array(point).first(3).map(&:to_f) }
      @params['path_points'] = clean_points
      @params['start_point'] = clean_points.first
      @params['end_point'] = clean_points.last
    end

    def set_layer_extension(kind, index, value)
      key = kind == :layer_start ? 'layer_start_extensions' : 'layer_end_extensions'
      extensions = Array(@params[key]).dup
      extensions[index] = value.to_f
      @params[key] = extensions
    end

    def apply_preset(preset_name)
      preset = preset_name.to_s
      layers = WallTypeCatalog.default_for(preset)
      @params['wall_type'] = preset
      core_layer = layers.find { |layer| layer['name'] =~ /core|structural wall|stud/i }
      if core_layer
        @params['core_thickness'] = core_layer['thickness'].to_f
        @params['core_material'] = core_layer['material']
        @params['core_type'] = {
          'EWS_Concrete' => CoreType::CONCRETE,
          'EWS_Laterizio' => CoreType::POROTON,
          'EWS_Brick' => CoreType::BRICK,
          'EWS_Ytong' => CoreType::AAC_BLOCK,
          'EWS_Metal_Stud' => CoreType::DRYWALL
        }[@params['core_material']] || @params['core_type']
        core_index = layers.index(core_layer)
        @params['ext_layers'] = layers[0...core_index]
        @params['int_layers'] = layers[(core_index + 1)..-1].to_a
      else
        @params['core_thickness'] = 0.0
        @params['ext_layers'] = layers.reject { |layer| layer['name'] =~ /interior/i }
        @params['int_layers'] = layers.select { |layer| layer['name'] =~ /interior/i }
      end
      @params['layer_start_extensions'] = []
      @params['layer_end_extensions'] = []
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
      points = path_points
      if points
        set_path_points(points.map { |point| [point[0] + dx, point[1] + dy, point[2] + dz] })
        return
      end

      start = start_point
      finish = end_point
      @params['start_point'] = [start[0] + dx, start[1] + dy, start[2] + dz]
      @params['end_point'] = [finish[0] + dx, finish[1] + dy, finish[2] + dz]
    end

    def flip_direction
      points = path_points
      if points
        set_path_points(points.reverse)
        @params['layer_start_extensions'], @params['layer_end_extensions'] =
          @params['layer_end_extensions'], @params['layer_start_extensions']
        path_length = points.each_cons(2).sum do |start_point, end_point|
          dx = end_point[0] - start_point[0]
          dy = end_point[1] - start_point[1]
          Math.sqrt(dx * dx + dy * dy)
        end
        path_length += Math.sqrt((points.first[0] - points.last[0])**2 +
                                 (points.first[1] - points.last[1])**2) if path_closed?
        Array(@params['openings']).each do |opening|
          next unless opening.is_a?(Hash) && opening.key?('position')

          position = path_length - opening['position'].to_f
          opening['position'] = path_closed? ? (position % path_length) : position
        end
        return
      end

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
