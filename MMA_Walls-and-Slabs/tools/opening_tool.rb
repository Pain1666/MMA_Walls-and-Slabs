# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Opening Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_object'
require_relative '../core/opening_cutter'

module MMA_WallsAndSlabs
  class OpeningTool
    def initialize(params = {})
      @params = params || {}
      @input = Sketchup::InputPoint.new
      @target_group = nil
      @preview = nil
    end

    def activate
      @target_group = selected_target
      Sketchup.status_text = 'MMA Opening Tool: Move over a wall, then click to place the opening. The cursor marks its lower-left corner; press Esc to finish.'
    end

    def onMouseMove(flags, x, y, view)
      @input.pick(view, x, y)
      view.tooltip = @input.tooltip if @input.valid?
      update_preview(view, x, y) if @input.valid?
      @preview = nil unless @input.valid?
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @input.pick(view, x, y)
      return unless @input.valid?

      update_preview(view, x, y)
      unless @preview && valid_target?(@target_group)
        Sketchup.status_text = 'MMA Opening Tool: Move the cursor over a MMA wall or slab to preview placement.'
        return
      end

      if WallModel.valid_wall_group?(@target_group)
        place_wall_opening(@preview)
      else
        place_slab_opening(@preview)
      end
      Sketchup.status_text = 'MMA Opening Tool: Opening placed. Click to place another.'
      view.invalidate
    rescue StandardError => error
      UI.messagebox("Could not place opening: #{error.message}")
    end

    def draw(view)
      @input.draw(view) if @input.valid?
      return unless @preview

      corners = @preview[:corners]
      view.drawing_color = Sketchup::Color.new(30, 144, 255, 75)
      view.draw(GL_QUADS, corners)
      view.line_width = 2
      view.line_stipple = ''
      view.drawing_color = Sketchup::Color.new(0, 110, 220)
      view.draw(GL_LINE_LOOP, corners)
      view.draw_points([corners[0]], 9, 1, Sketchup::Color.new(255, 220, 0))
      view.line_width = 1
      view.drawing_color = Sketchup::Color.new(0, 0, 0)
    end

    def onCancel(_reason, view)
      @preview = nil
      Sketchup.status_text = 'MMA Opening Tool: cancelled.'
      view.invalidate
    end

    private

    def update_preview(view, x, y)
      target = group_at(view, x, y)
      target ||= selected_target unless target
      @target_group = target
      @preview = nil
      return unless valid_target?(target)

      width = Float(@params['width'])
      height = Float(@params['height'])
      raise ArgumentError, 'Opening width and height must be greater than zero.' unless width.positive? && height.positive?

      @preview = if WallModel.valid_wall_group?(target)
                   wall_preview(target, @input.position, width, height)
                 else
                   slab_preview(target, @input.position, width, height)
                 end
      if @preview
        Sketchup.status_text = 'MMA Opening Tool: click to place; the yellow point is the lower-left anchor.'
      end
    rescue ArgumentError, TypeError => error
      Sketchup.status_text = "MMA Opening Tool: #{error.message}"
      @preview = nil
    end

    def selected_target
      Sketchup.active_model.selection.grep(Sketchup::Group).find { |group| valid_target?(group) }
    end

    def valid_target?(group)
      WallModel.valid_wall_group?(group) ||
        (group && group.valid? && group.get_attribute(DICT_NAME, ATTR_TYPE) == 'slab')
    end

    def group_at(view, x, y)
      helper = view.pick_helper
      helper.do_pick(x, y)
      helper.count.times do |index|
        path = helper.path_at(index)
        next unless path

        group = path.grep(Sketchup::Group).reverse.find { |item| valid_target?(item) }
        return group if group
      end
      nil
    end

    def wall_preview(group, point, width, height)
      wall = WallModel.from_group(group)
      raise ArgumentError, 'Could not read the selected wall.' unless wall

      path_points = wall.path_points || [wall.start_point, wall.end_point]
      closed = wall.path_closed?
      segment_count = closed ? path_points.length : path_points.length - 1
      cursor = [GeometryHelper.to_mm(point.x), GeometryHelper.to_mm(point.y), GeometryHelper.to_mm(point.z)]
      cumulative = 0.0
      nearest = nil
      segment_count.times do |index|
        start_point = path_points[index]
        end_point = path_points[(index + 1) % path_points.length]
        dx = end_point[0] - start_point[0]
        dy = end_point[1] - start_point[1]
        length = Math.sqrt(dx * dx + dy * dy)
        next if length <= 0.001

        tangent = [dx / length, dy / length]
        normal = [-tangent[1], tangent[0]]
        along = (cursor[0] - start_point[0]) * tangent[0] + (cursor[1] - start_point[1]) * tangent[1]
        center_x = start_point[0] + tangent[0] * along
        center_y = start_point[1] + tangent[1] * along
        side_offset = (cursor[0] - center_x) * normal[0] + (cursor[1] - center_y) * normal[1]
        distance = Math.sqrt((cursor[0] - center_x)**2 + (cursor[1] - center_y)**2)
        candidate = {
          tangent: tangent, normal: normal, length: length, along: along,
          cumulative: cumulative, side_offset: side_offset, distance: distance,
          start: start_point
        }
        nearest = candidate if nearest.nil? || distance < nearest[:distance]
        cumulative += length
      end
      raise ArgumentError, 'Could not find a wall segment at the selected point.' unless nearest

      along = nearest[:along]
      sill_height = cursor[2] - nearest[:start][2]
      if along < -0.001 || along + width > nearest[:length] + 0.001
        raise ArgumentError, 'The opening must fit on the hovered wall segment.'
      end
      if sill_height < -0.001 || sill_height + height > wall.height + 0.001
        raise ArgumentError, 'The opening must fit within the wall height.'
      end

      enabled_layers = WallBuilder.wall_layers(wall.params).select do |layer|
        layer['enabled'] != false && layer['thickness'].to_f.positive?
      end
      total_thickness = enabled_layers.sum { |layer| layer['thickness'].to_f }
      base_offset = case wall.justification
                    when WallJustification::LEFT then 0.0
                    when WallJustification::RIGHT then -total_thickness
                    else -total_thickness / 2.0
                    end
      side_limits = [base_offset, base_offset + total_thickness].minmax
      face_offset = [[nearest[:side_offset], side_limits[0]].max, side_limits[1]].min
      anchor = [
        nearest[:start][0] + nearest[:tangent][0] * along + nearest[:normal][0] * face_offset,
        nearest[:start][1] + nearest[:tangent][1] * along + nearest[:normal][1] * face_offset,
        nearest[:start][2] + sill_height
      ]
      right = [
        anchor[0] + nearest[:tangent][0] * width,
        anchor[1] + nearest[:tangent][1] * width,
        anchor[2]
      ]
      top_right = [right[0], right[1], right[2] + height]
      top_left = [anchor[0], anchor[1], anchor[2] + height]
      {
        position: nearest[:cumulative] + along + width / 2.0,
        sill_height: sill_height,
        width: width,
        height: height,
        corners: [anchor, right, top_right, top_left].map do |coordinates|
          Geom::Point3d.new(*coordinates.map { |value| GeometryHelper.mm(value) })
        end
      }
    end

    def place_wall_opening(preview)
      opening = @params.merge(
        'position' => preview[:position],
        'sill_height' => preview[:sill_height],
        'width' => preview[:width],
        'height' => preview[:height]
      )
      OpeningCutter.add_wall_opening(Sketchup.active_model, @target_group, opening)
    end

    def slab_preview(group, point, width, height)
      data = JSON.parse(group.get_attribute(DICT_NAME, ATTR_DATA).to_s)
      x = GeometryHelper.to_mm(point.x)
      y = GeometryHelper.to_mm(point.y)
      z = GeometryHelper.mm(data['elevation'] || 0.0)
      anchor = Geom::Point3d.new(GeometryHelper.mm(x), GeometryHelper.mm(y), z)
      right = Geom::Point3d.new(anchor.x + GeometryHelper.mm(width), anchor.y, z)
      top_right = Geom::Point3d.new(right.x, right.y + GeometryHelper.mm(height), z)
      top_left = Geom::Point3d.new(anchor.x, anchor.y + GeometryHelper.mm(height), z)
      { x: x, y: y, width: width, height: height, corners: [anchor, right, top_right, top_left] }
    rescue JSON::ParserError
      raise ArgumentError, 'Could not read the selected slab.'
    end

    def place_slab_opening(preview)
      opening = @params.merge(
        'x' => preview[:x],
        'y' => preview[:y],
        'width' => preview[:width],
        'height' => preview[:height]
      )
      OpeningCutter.add_slab_opening(Sketchup.active_model, @target_group, opening)
    end
  end
end
