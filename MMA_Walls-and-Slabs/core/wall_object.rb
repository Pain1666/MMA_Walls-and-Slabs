require_relative '../core/opening_cutter'
require_relative '../core/wall_object'
require_relative '../core/wall_builder'

module MMA_WallsAndSlabs
  class DialogManager
    @wall_dialog = nil
    @slab_dialog = nil

    @cached_wall_params = {
      'height' => Defaults::WALL_HEIGHT,
      'justification' => Defaults::WALL_JUSTIFICATION,
      'core_type' => CoreType::POROTON,
      'core_thickness' => Defaults::CORE_THICKNESS[CoreType::POROTON],
      'core_material' => 'EWS_Laterizio',
      'wall_type' => WallPresets::GENERIC,
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

    def self.wall_type_presets
      WallPresets::ALL.map do |preset|
        { 'name' => preset, 'layers' => WallTypeCatalog.default_for(preset) }
      end
    end

    def self.current_wall_params(p0_mm, p1_mm)
      params = @cached_wall_params.dup
      params['start_point'] = p0_mm
      params['end_point'] = p1_mm
      params['wall_type'] = WallPresets::GENERIC
      params
    end

    def self.wall_params_for_group(group)
      return current_wall_params([0, 0, 0], [1000, 0, 0]) unless group && group.valid?

      wall_model = WallModel.from_group(group)
      return current_wall_params([0, 0, 0], [1000, 0, 0]) unless wall_model

      wall_model.params.dup
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
      params = @cached_slab_params.dup
      params['points'] = pts_mm
      params
    end

    def self.show_wall_dialog(target_group = nil)
      html_path = File.join(__dir__, 'html', 'wall_dialog.html')
      @wall_dialog = UI::HtmlDialog.new(
        dialog_title: target_group ? 'Edit MMA Wall' : 'MMA Wall Settings',
        preferences_key: 'com.mmawallsandslabs.walldialog',
        scrollable: true,
        resizable: true,
        width: 520,
        height: 680
      )
      @wall_dialog.set_file(html_path)
      @wall_dialog.show
    end

    def self.show_slab_dialog(target_group = nil)
      html_path = File.join(__dir__, 'html', 'slab_dialog.html')
      @slab_dialog = UI::HtmlDialog.new(
        dialog_title: target_group ? 'Edit MMA Slab' : 'MMA Slab Settings',
        preferences_key: 'com.mmawallsandslabs.slabdialog',
        scrollable: true,
        resizable: true,
        width: 500,
        height: 600
      )
      @slab_dialog.set_file(html_path)
      @slab_dialog.show
    end

    def self.show_opening_dialog(target_group = nil)
      html_path = File.join(__dir__, 'html', 'opening_dialog.html')
      @opening_dialog = UI::HtmlDialog.new(
        dialog_title: 'MMA Opening Settings',
        preferences_key: 'com.mmawallsandslabs.openingdialog',
        scrollable: true,
        resizable: true,
        width: 420,
        height: 440
      )
      @opening_dialog.set_file(html_path)
      @opening_dialog.show
    end
  end
end
