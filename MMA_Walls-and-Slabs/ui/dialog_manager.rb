# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Edit Wall Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_object'
require_relative '../core/wall_builder'
require_relative '../core/wall_joiner'
require 'fileutils'

module MMA_WallsAndSlabs
  class DialogManager
    @wall_dialog = nil
    @slab_dialog = nil
    @opening_dialog = nil

    @cached_wall_params = {
      'height' => Defaults::WALL_HEIGHT,
      'justification' => Defaults::WALL_JUSTIFICATION,
      'core_type' => CoreType::HOLLOW_BRICK,
      'core_thickness' => Defaults::CORE_THICKNESS[CoreType::HOLLOW_BRICK],
      'core_material' => 'MMA_Brick',
      'wall_type' => WallPresets::GENERIC,
      'ext_layers' => [
        { 'name' => 'Intonaco esterno', 'thickness' => 15.0, 'material' => 'MMA_Render_Ext', 'enabled' => true },
        { 'name' => 'Cappotto EPS', 'thickness' => 100.0, 'material' => 'MMA_Insulation_EPS', 'enabled' => true }
      ],
      'int_layers' => [
        { 'name' => 'Intonaco interno', 'thickness' => 15.0, 'material' => 'MMA_Plaster_Int', 'enabled' => true }
      ],
      'openings' => []
    }

    @cached_slab_params = {
      'elevation' => 0.0,
      'reference' => 'top',
      'layers' => [
        { 'name' => 'Wood Parquet', 'thickness' => 15.0, 'material' => 'MMA_Wood_Flooring', 'enabled' => true },
        { 'name' => 'Screed (Massetto)', 'thickness' => 60.0, 'material' => 'MMA_Screed', 'enabled' => true },
        { 'name' => 'Acoustic/EPS Foam', 'thickness' => 40.0, 'material' => 'MMA_Insulation_EPS', 'enabled' => true },
        { 'name' => 'Structural Concrete', 'thickness' => 200.0, 'material' => 'MMA_Concrete', 'enabled' => true }
      ],
      'openings' => []
    }

    def self.wall_types
      path = wall_types_file
      return validate_wall_types(JSON.parse(File.read(path))) if File.file?(path)

      stored = Sketchup.read_default('MMA_WallsAndSlabs', 'wall_types', '[]')
      stored = '[]' if stored.nil? || stored.to_s.empty?
      types = validate_wall_types(JSON.parse(stored.to_s))
      persist_wall_types(types) unless types.empty?
      types
    rescue JSON::ParserError => error
      raise ArgumentError, "Saved wall types could not be read: #{error.message}"
    end

    def self.validate_wall_types(types)
      raise ArgumentError, 'Saved wall types must be stored as a list.' unless types.is_a?(Array)

      types.each do |type|
        unless type.is_a?(Hash) && type['name'].is_a?(String) && type['parameters'].is_a?(Hash)
          raise ArgumentError, 'A saved wall type in SketchUp preferences is invalid.'
        end
      end
      types
    end

    def self.wall_types_file
      plugins_path = Sketchup.find_support_file('Plugins')
      raise IOError, "Could not locate SketchUp's user Plugins folder." unless plugins_path && !plugins_path.empty?

      data_directory = File.join(plugins_path, 'MMA_WallsAndSlabs_Data')
      FileUtils.mkdir_p(data_directory)
      File.join(data_directory, 'wall_types.json')
    end

    def self.save_wall_type(name, params)
      type_name = name.to_s.strip
      raise ArgumentError, 'Enter a name for the wall type.' if type_name.empty?
      raise ArgumentError, 'Wall type names must be 80 characters or fewer.' if type_name.length > 80

      settings = params
      raise ArgumentError, 'Wall type settings must be an object.' unless settings.is_a?(Hash)
      validate_wall_settings(settings)
      settings = wall_type_settings(settings)
      settings['wall_type'] = type_name

      types = wall_types
      index = types.index { |type| type['name'].casecmp(type_name).zero? }
      record = { 'name' => type_name, 'parameters' => settings }
      index ? types[index] = record : types << record
      persist_wall_types(types)
      types
    end

    def self.delete_wall_type(name)
      type_name = name.to_s
      types = wall_types
      index = types.index { |type| type['name'] == type_name }
      raise ArgumentError, 'The selected wall type no longer exists.' unless index

      types.delete_at(index)
      persist_wall_types(types)
      types
    end

    def self.persist_wall_types(types)
      validate_wall_types(types)
      encoded = JSON.generate(types)
      path = wall_types_file
      File.open(path, 'w:UTF-8') { |file| file.write(encoded) }
      raise IOError, 'SketchUp did not confirm saving the wall types.' unless File.read(path) == encoded
    end

    def self.wall_type_settings(params)
      keys = %w[height justification core_type core_thickness core_material ext_layers int_layers]
      settings = params.select { |key, _value| keys.include?(key.to_s) }
      duplicate(settings)
    end

    def self.current_wall_params(p0_mm, p1_mm)
      params = duplicate(@cached_wall_params)
      params['start_point'] = p0_mm
      params['end_point'] = p1_mm
      params
    end

    def self.wall_params
      duplicate(@cached_wall_params)
    end

    def self.slab_params
      duplicate(@cached_slab_params)
    end

    def self.wall_params_for_group(group)
      return current_wall_params([0, 0, 0], [1000, 0, 0]) unless group && group.valid?

      wall_model = WallModel.from_group(group)
      return current_wall_params([0, 0, 0], [1000, 0, 0]) unless wall_model

      duplicate(wall_model.params)
    end

    def self.apply_wall_preset(group, preset_name)
      return false unless group && group.valid?

      wall_model = WallModel.from_group(group)
      return false unless wall_model

      wall_model.apply_preset(preset_name)
      wall_model.save_to_group(group)
      WallBuilder.rebuild_wall_from_model(Sketchup.active_model, group, wall_model)
      true
    end

    def self.current_slab_params(pts_mm)
      params = duplicate(@cached_slab_params)
      params['points'] = pts_mm
      params
    end

    def self.show_wall_dialog(target_group = nil, create_wall: false)
      target_group = nil unless target_group && WallModel.valid_wall_group?(target_group)
      html_path = File.join(__dir__, 'html', 'wall_dialog.html')
      dialog = UI::HtmlDialog.new(
        dialog_title: target_group ? 'Edit MMA Wall' : (create_wall ? 'Create MMA Wall' : 'MMA Wall Settings'),
        preferences_key: 'com.mmawallsandslabs.walldialog',
        scrollable: true,
        resizable: true,
        width: 520,
        height: 680
      )
      @wall_dialog = dialog
      dialog.add_action_callback('dialog_ready') do |_context|
        data = target_group ? wall_params_for_group(target_group) : wall_params
        begin
          types = wall_types
          dialog.execute_script("loadWallData(#{JSON.generate(data)}, #{create_wall}, #{JSON.generate(types)});")
        rescue StandardError => error
          UI.messagebox("Could not load saved wall types: #{error.message}")
          dialog.execute_script("loadWallData(#{JSON.generate(data)}, #{create_wall}, []);")
        end
      end
      dialog.add_action_callback('close_dialog') { |_context| dialog.close }
      dialog.add_action_callback('save_wall_type') do |_context, payload|
        begin
          request = parse_payload(payload)
          types = save_wall_type(request['name'], request['parameters'])
          saved_name = types.find { |type| type['name'].casecmp(request['name'].to_s.strip).zero? }['name']
          dialog.execute_script("wallTypesUpdated(#{JSON.generate(types)}, '', #{JSON.generate(saved_name)});")
        rescue StandardError => error
          UI.messagebox("Could not save wall type: #{error.message}")
        end
      end
      dialog.add_action_callback('delete_wall_type') do |_context, name|
        begin
          types = delete_wall_type(name)
          dialog.execute_script("wallTypesUpdated(#{JSON.generate(types)}, #{JSON.generate(name.to_s)});")
        rescue StandardError => error
          UI.messagebox("Could not delete wall type: #{error.message}")
        end
      end
      dialog.add_action_callback('create_or_update_wall') do |_context, payload|
        begin
          data = parse_payload(payload)
          validate_wall_settings(data)
          if target_group && target_group.valid?
            existing = wall_params_for_group(target_group)
            %w[start_point end_point path_points path_closed layer_start_extensions layer_end_extensions].each do |key|
              data[key] = existing[key] if existing.key?(key)
            end
            WallBuilder.build(Sketchup.active_model, data, target_group)
          else
            @cached_wall_params = data
          end
          dialog.close
          Sketchup.active_model.select_tool(DrawWallTool.new(data)) if create_wall
        rescue StandardError => error
          UI.messagebox("Could not save wall settings: #{error.message}")
        end
      end
      dialog.set_file(html_path)
      dialog.show
    end

    def self.show_slab_dialog(target_group = nil)
      target_group = nil unless target_group && target_group.valid? &&
                                  target_group.get_attribute(DICT_NAME, ATTR_TYPE) == 'slab'
      html_path = File.join(__dir__, 'html', 'slab_dialog.html')
      dialog = UI::HtmlDialog.new(
        dialog_title: target_group ? 'Edit MMA Slab' : 'MMA Slab Settings',
        preferences_key: 'com.mmawallsandslabs.slabdialog',
        scrollable: true,
        resizable: true,
        width: 500,
        height: 600
      )
      @slab_dialog = dialog
      dialog.add_action_callback('dialog_ready') do |_context|
        data = target_group ? slab_params_for_group(target_group) : slab_params
        dialog.execute_script("loadSlabData(#{JSON.generate(data)});")
      end
      dialog.add_action_callback('close_dialog') { |_context| dialog.close }
      dialog.add_action_callback('create_or_update_slab') do |_context, payload|
        begin
          data = parse_payload(payload)
          validate_slab_settings(data)
          if target_group && target_group.valid?
            data['points'] = slab_params_for_group(target_group)['points']
            SlabBuilder.build(Sketchup.active_model, data, target_group)
          else
            @cached_slab_params = data
          end
          dialog.close
        rescue StandardError => error
          UI.messagebox("Could not save slab settings: #{error.message}")
        end
      end
      dialog.set_file(html_path)
      dialog.show
    end

    def self.show_opening_dialog(target_group = nil)
      html_path = File.join(__dir__, 'html', 'opening_dialog.html')
      dialog = UI::HtmlDialog.new(
        dialog_title: 'MMA Opening Settings',
        preferences_key: 'com.mmawallsandslabs.openingdialog',
        scrollable: true,
        resizable: true,
        width: 420,
        height: 440
      )
      @opening_dialog = dialog
      dialog.add_action_callback('close_dialog') { |_context| dialog.close }
      dialog.add_action_callback('start_placement_tool') do |_context, payload|
        begin
          params = parse_payload(payload)
          model = Sketchup.active_model
          model.select_tool(OpeningTool.new(params))
          dialog.close
        rescue StandardError => error
          UI.messagebox("Could not start opening placement: #{error.message}")
        end
      end
      dialog.set_file(html_path)
      dialog.show
    end

    def self.slab_params_for_group(group)
      data = group.get_attribute(DICT_NAME, ATTR_DATA)
      raise ArgumentError, 'The selected slab has no saved parameters.' unless data

      JSON.parse(data)
    rescue JSON::ParserError => error
      raise ArgumentError, "The selected slab parameters are invalid: #{error.message}"
    end

    def self.parse_payload(payload)
      data = JSON.parse(payload.to_s)
      raise ArgumentError, 'Dialog data must be a JSON object.' unless data.is_a?(Hash)

      data
    end

    def self.validate_wall_settings(data)
      height = Float(data['height'])
      core_thickness = Float(data['core_thickness'] || 0.0)
      raise ArgumentError, 'Wall height must be greater than zero.' unless height.finite? && height.positive?
      raise ArgumentError, 'Core thickness must be a non-negative number.' unless core_thickness.finite? && !core_thickness.negative?
      data['height'] = height
      data['core_thickness'] = core_thickness
      %w[ext_layers int_layers].each do |key|
        raise ArgumentError, "#{key} must be a list." unless data[key].nil? || data[key].is_a?(Array)
        Array(data[key]).each do |layer|
          raise ArgumentError, "#{key} must contain layer objects." unless layer.is_a?(Hash)

          thickness = Float(layer['thickness'] || 0.0)
          raise ArgumentError, 'Layer thickness must be a non-negative number.' unless thickness.finite? && !thickness.negative?
          layer['thickness'] = thickness
          layer['enabled'] = layer['enabled'] != false
        end
      end
      data['ext_layers'] ||= []
      data['int_layers'] ||= []
      data['justification'] = Defaults::WALL_JUSTIFICATION unless WallJustification::ALL.include?(data['justification'])
    end

    def self.validate_slab_settings(data)
      elevation = Float(data['elevation'] || 0.0)
      raise ArgumentError, 'Slab elevation must be a number.' unless elevation.finite?
      data['elevation'] = elevation
      data['reference'] = 'bottom' if data['reference'] == 'bottom'
      data['reference'] = 'top' unless data['reference'] == 'bottom'
      raise ArgumentError, 'Slab layers must be a list.' unless data['layers'].nil? || data['layers'].is_a?(Array)
      Array(data['layers']).each do |layer|
        raise ArgumentError, 'Slab layers must contain layer objects.' unless layer.is_a?(Hash)

        thickness = Float(layer['thickness'] || 0.0)
        raise ArgumentError, 'Layer thickness must be a non-negative number.' unless thickness.finite? && !thickness.negative?
        layer['thickness'] = thickness
        layer['enabled'] = layer['enabled'] != false
      end
      data['layers'] ||= []
    end

    def self.duplicate(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end
