require_relative '../core/opening_cutter'

module MMA_WallsAndSlabs
  class DialogManager
    @wall_dialog = nil
    @slab_dialog = nil
    @opening_dialog = nil

    @cached_wall_params = {
      'height' => Defaults::WALL_HEIGHT,
      'justification' => Defaults::WALL_JUSTIFICATION,
      'core_type' => CoreType::POROTON,
      'core_thickness' => Defaults::CORE_THICKNESS[CoreType::POROTON],
      'core_material' => 'EWS_Laterizio',
      'drywall_stud_spacing' => Defaults::DRYWALL_STUD_SPACING,
      'drywall_boards_ext' => Defaults::DRYWALL_BOARDS_EXT,
      'drywall_boards_int' => Defaults::DRYWALL_BOARDS_INT,
      'drywall_board_thick' => Defaults::DRYWALL_BOARD_THICK,
      'ext_layers' => [
        { 'name' => 'Intonaco esterno', 'thickness' => 15.0, 'material' => 'EWS_Render_Ext', 'enabled' => true },
        { 'name' => 'Cappotto EPS', 'thickness' => 100.0, 'material' => 'EWS_Insulation_EPS', 'enabled' => true }
      ],
      'int_layers' => [
        { 'name' => 'Intonaco interno', 'thickness' => 15.0, 'material' => 'EWS_Plaster_Int', 'enabled' => true }
      ],
      'openings' => []
    }

    @cached_slab_params = {
      'elevation' => 0.0,
      'reference' => 'top',
      'layers' => [
        { 'name' => 'Wood Parquet', 'thickness' => 15.0, 'material' => 'EWS_Wood_Flooring', 'enabled' => true },
        { 'name' => 'Screed (Massetto)', 'thickness' => 60.0, 'material' => 'EWS_Screed', 'enabled' => true },
        { 'name' => 'Acoustic/EPS Foam', 'thickness' => 40.0, 'material' => 'EWS_Insulation_EPS', 'enabled' => true },
        { 'name' => 'Structural Concrete', 'thickness' => 200.0, 'material' => 'EWS_Concrete', 'enabled' => true }
      ],
      'openings' => []
    }

    def self.current_wall_params(p0_mm, p1_mm)
      params = @cached_wall_params.dup
      params['start_point'] = p0_mm
      params['end_point'] = p1_mm
      params
    end

    def self.current_slab_params(pts_mm)
      params = @cached_slab_params.dup
      params['points'] = pts_mm
      params
    end

    def self.show_wall_dialog(target_group = nil)
      if @wall_dialog && @wall_dialog.visible?
        @wall_dialog.bring_to_front
        return
      end

      html_path = File.join(__dir__, 'html', 'wall_dialog.html')
      @wall_dialog = UI::HtmlDialog.new(
        dialog_title: target_group ? 'Edit MMA Wall' : 'MMA Wall Settings',
        preferences_key: 'com.mmawallsandslabs.walldialog',
        scrollable: true,
        resizable: true,
        width: 520,
        height: 680,
        min_width: 440,
        min_height: 500
      )

      @wall_dialog.set_file(html_path)
      @wall_dialog.add_action_callback('get_initial_data') do |_action_context|
        data = if target_group
                 raw = target_group.get_attribute(DICT_NAME, ATTR_DATA)
                 parsed = raw ? JSON.parse(raw) : @cached_wall_params.dup
                 parsed['is_editing'] = true
                 parsed
               else
                 d = @cached_wall_params.dup
                 d['is_editing'] = false
                 d
               end
        js_code = "initData(#{data.to_json});"
        @wall_dialog.execute_script(js_code)
      end

      @wall_dialog.add_action_callback('create_or_update_wall') do |_action_context, json_str|
        data = JSON.parse(json_str)
        model = Sketchup.active_model

        if target_group && target_group.valid?
          orig_raw = target_group.get_attribute(DICT_NAME, ATTR_DATA)
          if orig_raw
            orig_data = JSON.parse(orig_raw)
            data['start_point'] = orig_data['start_point']
            data['end_point'] = orig_data['end_point']
          end
          WallBuilder.build(model, data, target_group)
        else
          @cached_wall_params = data
        end

        @wall_dialog.close
      end

      @wall_dialog.add_action_callback('close_dialog') do |_action_context|
        @wall_dialog.close
      end

      @wall_dialog.show
    end

    def self.show_slab_dialog(target_group = nil)
      if @slab_dialog && @slab_dialog.visible?
        @slab_dialog.bring_to_front
        return
      end

      html_path = File.join(__dir__, 'html', 'slab_dialog.html')
      @slab_dialog = UI::HtmlDialog.new(
        dialog_title: target_group ? 'Edit MMA Slab' : 'MMA Slab Settings',
        preferences_key: 'com.mmawallsandslabs.slabdialog',
        scrollable: true,
        resizable: true,
        width: 500,
        height: 600,
        min_width: 420,
        min_height: 450
      )

      @slab_dialog.set_file(html_path)
      @slab_dialog.add_action_callback('get_initial_data') do |_action_context|
        data = if target_group
                 raw = target_group.get_attribute(DICT_NAME, ATTR_DATA)
                 parsed = raw ? JSON.parse(raw) : @cached_slab_params.dup
                 parsed['is_editing'] = true
                 parsed
               else
                 d = @cached_slab_params.dup
                 d['is_editing'] = false
                 d
               end
        js_code = "initData(#{data.to_json});"
        @slab_dialog.execute_script(js_code)
      end

      @slab_dialog.add_action_callback('create_or_update_slab') do |_action_context, json_str|
        data = JSON.parse(json_str)
        model = Sketchup.active_model

        if target_group && target_group.valid?
          orig_raw = target_group.get_attribute(DICT_NAME, ATTR_DATA)
          if orig_raw
            orig_data = JSON.parse(orig_raw)
            data['points'] = orig_data['points']
          end
          SlabBuilder.build(model, data, target_group)
        else
          @cached_slab_params = data
        end

        @slab_dialog.close
      end

      @slab_dialog.add_action_callback('close_dialog') do |_action_context|
        @slab_dialog.close
      end

      @slab_dialog.show
    end
  end
end
