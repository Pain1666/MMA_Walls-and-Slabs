# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Interactive Join Walls Tool
# Click two walls to automatically extend them to their intersection point,
# joining their structural cores and all layers with a mitered corner joint.
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_joiner'

module EuroWallSlab
  class JoinWallTool
    def initialize
      @wall1 = nil
      @hover_wall = nil
      @int_pt = nil
    end

    def activate
      @wall1 = nil
      @hover_wall = nil
      @int_pt = nil
      update_status
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.path_at(0)

      picked_wall = nil
      if path
        picked_wall = path.reverse.find do |entity|
          entity.is_a?(Sketchup::Group) && entity.get_attribute(DICT_NAME, ATTR_TYPE) == 'wall'
        end
      end

      if picked_wall && picked_wall.valid?
        @hover_wall = picked_wall
        if @wall1 && @wall1.valid? && @hover_wall != @wall1
          compute_intersection_preview(@wall1, @hover_wall)
        else
          @int_pt = nil
        end
      else
        @hover_wall = nil
        @int_pt = nil
      end

      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      if @hover_wall && @hover_wall.valid?
        if @wall1.nil?
          # Select Wall 1
          @wall1 = @hover_wall
          update_status
        elsif @hover_wall != @wall1
          # Select Wall 2 and Join!
          success = WallJoiner.join_walls(Sketchup.active_model, @wall1, @hover_wall)
          if success
            Sketchup.status_text = 'Euro Wall: Walls joined successfully! Click another wall to continue or press Escape.'
          else
            UI.messagebox('Could not join selected walls. Ensure they are not parallel and have intersecting baselines.')
          end
          @wall1 = nil
          @hover_wall = nil
          @int_pt = nil
        end
      else
        if @wall1
          # Clicking empty space resets Wall 1
          @wall1 = nil
          update_status
        end
      end
      view.invalidate
    end

    def onCancel(reason, view)
      if @wall1
        @wall1 = nil
        update_status
        view.invalidate
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    # Draw highlights and intersection preview
    def draw(view)
      # Highlight Wall 1 in solid green
      if @wall1 && @wall1.valid?
        draw_group_highlight(view, @wall1, Sketchup::Color.new(46, 204, 113, 200), 3)
      end

      # Highlight hovered wall in cyan
      if @hover_wall && @hover_wall.valid? && @hover_wall != @wall1
        draw_group_highlight(view, @hover_wall, Sketchup::Color.new(52, 152, 219, 180), 2)
      end

      # Draw intersection point marker and dashed connection lines
      if @int_pt
        view.drawing_color = Sketchup::Color.new(230, 126, 34) # Orange target
        view.line_width = 3
        view.draw_points([@int_pt], 14, 2, 'orange')
      end
    end

    private

    def update_status
      if @wall1.nil?
        Sketchup.status_text = 'Euro Join Walls Tool: Click the first wall near the corner to join'
      else
        Sketchup.status_text = 'Euro Join Walls Tool: Wall 1 selected. Click the second wall to form corner joint (or press Escape to cancel).'
      end
    end

    def draw_group_highlight(view, group, color, width)
      view.drawing_color = color
      view.line_width = width
      bb = group.bounds
      # Draw bounding box outline
      pts = [
        bb.corner(0), bb.corner(1),
        bb.corner(1), bb.corner(3),
        bb.corner(3), bb.corner(2),
        bb.corner(2), bb.corner(0),

        bb.corner(4), bb.corner(5),
        bb.corner(5), bb.corner(7),
        bb.corner(7), bb.corner(6),
        bb.corner(6), bb.corner(4),

        bb.corner(0), bb.corner(4),
        bb.corner(1), bb.corner(5),
        bb.corner(2), bb.corner(6),
        bb.corner(3), bb.corner(7)
      ]
      view.draw(GL_LINES, pts)
    end

    def compute_intersection_preview(wall1, wall2)
      raw1 = wall1.get_attribute(DICT_NAME, ATTR_DATA)
      raw2 = wall2.get_attribute(DICT_NAME, ATTR_DATA)
      return unless raw1 && raw2

      p1 = JSON.parse(raw1)
      p2 = JSON.parse(raw2)

      p1_start = Geom::Point3d.new(GeometryHelper.mm(p1['start_point'][0]), GeometryHelper.mm(p1['start_point'][1]), GeometryHelper.mm(p1['start_point'][2]))
      p1_end   = Geom::Point3d.new(GeometryHelper.mm(p1['end_point'][0]), GeometryHelper.mm(p1['end_point'][1]), GeometryHelper.mm(p1['end_point'][2]))

      p2_start = Geom::Point3d.new(GeometryHelper.mm(p2['start_point'][0]), GeometryHelper.mm(p2['start_point'][1]), GeometryHelper.mm(p2['start_point'][2]))
      p2_end   = Geom::Point3d.new(GeometryHelper.mm(p2['end_point'][0]), GeometryHelper.mm(p2['end_point'][1]), GeometryHelper.mm(p2['end_point'][2]))

      v1 = (p1_end - p1_start).normalize
      v2 = (p2_end - p2_start).normalize

      @int_pt = Geom.intersect_line_line([p1_start, v1], [p2_start, v2])
      if @int_pt
        @int_pt.z = (p1_start.z + p2_start.z) / 2.0
      end
    end
  end
end
