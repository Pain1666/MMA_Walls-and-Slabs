# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Join Walls Tool
# ==============================================================================

require_relative '../core/constants'
require_relative '../core/geometry_helper'
require_relative '../core/wall_joiner'

module MMA_WallsAndSlabs
  class JoinWallTool
    def initialize
      @first_wall = nil
    end

    def activate
      @first_wall = nil
      Sketchup.status_text = 'MMA Join Walls Tool: Select two walls.'
    end

    def onLButtonDown(flags, x, y, view)
      helper = view.pick_helper
      helper.do_pick(x, y)
      wall = nil
      helper.count.times do |index|
        path = helper.path_at(index)
        next unless path

        wall = path.grep(Sketchup::Group).reverse.find { |group| WallModel.valid_wall_group?(group) }
        break if wall
      end
      unless wall
        Sketchup.status_text = 'MMA Join Walls Tool: Click a MMA wall.'
        return
      end

      if @first_wall.nil?
        @first_wall = wall
        Sketchup.status_text = 'MMA Join Walls Tool: Click the second wall.'
        return
      end

      if wall == @first_wall
        Sketchup.status_text = 'MMA Join Walls Tool: Choose a different wall.'
        return
      end

      join_type = WallJoiner.detect_wall_join(Sketchup.active_model, @first_wall, wall)
      if join_type == JoinType::NONE || !WallJoiner.apply_join(Sketchup.active_model, @first_wall, wall, join_type)
        Sketchup.status_text = 'MMA Join Walls Tool: Walls do not have a supported endpoint join.'
      else
        Sketchup.status_text = 'MMA Join Walls Tool: Walls joined.'
      end
      @first_wall = nil
      view.invalidate
    rescue StandardError => error
      UI.messagebox("Could not join walls: #{error.message}")
      @first_wall = nil
    end

    def onCancel(reason, view)
      @first_wall = nil
      Sketchup.status_text = 'MMA Join Walls Tool: Select two walls.'
      view.invalidate
    end
  end
end
