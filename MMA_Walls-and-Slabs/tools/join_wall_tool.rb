# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Join Walls Tool
#
# Click the first wall (coloured green), then the second (coloured orange).
# For a corner the junction is previewed as semi-transparent volumes.
# Enter applies the join, Esc cancels.
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_object'
require_relative '../core/wall_geometry'
require_relative '../core/wall_joiner'

module MMA_WallsAndSlabs
  class JoinWallTool
    MODE_PROMPTS = {
      'corner' => 'Click the first wall, then the second. Their ends meet at the corner.',
      'trim' => 'Click the wall to keep, then the wall to trim back to it.',
      'extend' => 'Click the wall to keep, then the wall to extend up to it.',
      'chamfer' => 'Click the first wall, then the second. Their corner is cut at the chamfer distance.'
    }.freeze

    FIRST_COLOUR = [30, 170, 60].freeze
    SECOND_COLOUR = [240, 130, 20].freeze
    WALL_ALPHA = 90
    PREVIEW_ALPHA = 130

    # mode: 'corner', 'trim', 'extend' or 'chamfer' (chosen by the toolbar button).
    def initialize(mode = 'corner', distance = nil)
      @first_wall = nil
      @second_wall = nil
      @mode = WallJoiner::MODES.include?(mode) ? mode : 'corner'
      @distance = distance
      @first_boxes = nil
      @second_boxes = nil
      @preview_boxes = nil
    end

    def activate
      reset_selection
      show_status
    end

    def onLButtonDown(_flags, x, y, view)
      wall = wall_at(view, x, y)
      unless wall
        Sketchup.status_text = 'MMA Join Walls: click an MMA wall.'
        return
      end

      if @first_wall.nil?
        @first_wall = wall
        @first_boxes = wall_boxes(wall)
        Sketchup.status_text = "MMA Join Walls (#{@mode}): first wall selected (green). Now click the second wall."
      elsif wall == @first_wall
        Sketchup.status_text = 'MMA Join Walls: choose a different wall for the second click.'
      else
        select_second(wall)
      end
      view.invalidate
    end

    def onKeyDown(key, _repeat, _flags, view)
      apply_join(view) if (key == 13 || key == 10) && @first_wall && @second_wall
      view.invalidate
    end

    def onCancel(_reason, view)
      if @second_wall
        @second_wall = nil
        @second_boxes = nil
        @preview_boxes = nil
        Sketchup.status_text = "MMA Join Walls (#{@mode}): second wall cleared. Now click the second wall."
      else
        reset_selection
        show_status
      end
      view.invalidate
    end

    def draw(view)
      draw_boxes(view, @first_boxes, FIRST_COLOUR, WALL_ALPHA) if @first_boxes
      draw_boxes(view, @second_boxes, SECOND_COLOUR, WALL_ALPHA) if @second_boxes
      Array(@preview_boxes).each do |box|
        draw_box(view, box, material_colour(box[:material]), PREVIEW_ALPHA)
      end
    end

    private

    def reset_selection
      @first_wall = nil
      @second_wall = nil
      @first_boxes = nil
      @second_boxes = nil
      @preview_boxes = nil
    end

    def show_status
      Sketchup.status_text = "MMA Join Walls (#{@mode}): #{MODE_PROMPTS[@mode]}"
    end

    def select_second(wall)
      @second_wall = wall
      @second_boxes = wall_boxes(wall)
      @preview_boxes = nil

      if @mode == 'corner'
        plan, message = WallJoiner.corner_plan(@first_wall, @second_wall)
        if plan
          preview = WallGeometry.corner(plan[:wall1].params, plan[:wall1].path_points, plan[:end1],
                                        plan[:wall2].params, plan[:wall2].path_points, plan[:end2])
          @preview_boxes = preview ? preview[:boxes1] + preview[:boxes2] : nil
          extra = plan[:flipped] ? ' The second wall will be flipped to match.' : ''
          Sketchup.status_text = "MMA Join Walls (corner): preview shown. Press Enter to join.#{extra}"
        else
          Sketchup.status_text = "MMA Join Walls (corner): #{message} Esc to cancel."
        end
      else
        Sketchup.status_text = "MMA Join Walls (#{@mode}): second wall selected (orange). Press Enter to join, Esc to cancel."
      end
    end

    def apply_join(view)
      ok, message = WallJoiner.join(Sketchup.active_model, @first_wall, @second_wall, @mode, @distance)
      Sketchup.status_text = "MMA Join Walls: #{message}"
      UI.messagebox(message) unless ok
    rescue StandardError => error
      UI.messagebox("Could not join walls: #{error.message}")
    ensure
      reset_selection
      view.invalidate
    end

    # Layer boxes of a wall as it is now (no joint preview).
    def wall_boxes(group)
      return nil unless group && group.valid?

      wall = WallModel.from_group(group)
      return nil unless wall && wall.path_points && wall.path_points.length >= 2

      WallGeometry.boxes(wall.params, wall.path_points, wall.path_closed?)
    end

    def material_colour(name)
      DefaultMaterials::PALETTE[name.to_s] || [150, 150, 150]
    end

    def draw_boxes(view, boxes, rgb, alpha)
      Array(boxes).each { |box| draw_box(view, box, rgb, alpha) }
    end

    # A layer piece is a prism: base footprint extruded upwards by its height.
    def draw_box(view, box, rgb, alpha)
      base = box[:base].map { |p| point3d(p) }
      top = box[:base].map { |p| point3d([p[0], p[1], p[2] + box[:height]]) }
      faces = [base, top]
      4.times do |i|
        j = (i + 1) % 4
        faces << [base[i], base[j], top[j], top[i]]
      end
      view.drawing_color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2], alpha)
      view.draw(GL_QUADS, faces.flatten(1))
    end

    def point3d(p)
      Geom::Point3d.new(GeometryHelper.mm(p[0]), GeometryHelper.mm(p[1]), GeometryHelper.mm(p[2]))
    end

    def wall_at(view, x, y)
      helper = view.pick_helper
      helper.do_pick(x, y)
      helper.count.times do |index|
        path = helper.path_at(index)
        next unless path

        wall = path.grep(Sketchup::Group).reverse.find { |group| WallModel.valid_wall_group?(group) }
        return wall if wall
      end
      nil
    end
  end
end
