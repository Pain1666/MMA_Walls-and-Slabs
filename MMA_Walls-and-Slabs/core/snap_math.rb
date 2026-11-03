# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Snap anchors on wall centre lines (pure)
# ==============================================================================

module MMA_WallsAndSlabs
  module SnapMath
    module_function

    # Anchors of a centre line (array of [x, y, z]).
    #   open wall:   both ends and the midpoint of each segment
    #   closed loop: every corner
    #   curved wall: the two ends only (its sampled points are not joints)
    # Returns [{ point: [x, y, z], kind: :end | :mid | :corner }, ...]
    def anchors(path, closed = false, curved = false)
      if closed
        return path.map { |point| { point: point, kind: :corner } }
      end

      list = [{ point: path.first, kind: :end }, { point: path.last, kind: :end }]
      return list if curved

      (0...path.length - 1).each do |index|
        a = path[index]
        b = path[index + 1]
        list << { point: [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, a[2]], kind: :mid }
      end
      list
    end

    # Index of the screen point nearest to (x, y) within radius, or nil.
    def nearest(screen_points, x, y, radius)
      best = nil
      best_distance = radius
      screen_points.each_with_index do |(sx, sy), index|
        distance = Math.hypot(sx - x, sy - y)
        next unless distance <= best_distance

        best_distance = distance
        best = index
      end
      best
    end
  end
end
