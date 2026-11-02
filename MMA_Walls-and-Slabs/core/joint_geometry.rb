# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Wall Joint Geometry
# Pure 2D helpers (no SketchUp API) used to mitre layers at wall joints.
# ==============================================================================

module MMA_WallsAndSlabs
  module JointGeometry
    # Corner points further than this multiple of the total wall thickness
    # from the joint fall back to a square cut (avoids spikes on sharp angles).
    MITRE_LIMIT_FACTOR = 4.0

    module_function

    def unit(from, to)
      dx = to[0].to_f - from[0].to_f
      dy = to[1].to_f - from[1].to_f
      length = Math.sqrt((dx * dx) + (dy * dy))
      return nil if length < 1e-9

      [dx / length, dy / length]
    end

    # Unit direction of the first (at_start) or last segment, pointing along the path.
    def path_direction(path, at_start)
      at_start ? unit(path[0], path[1]) : unit(path[-2], path[-1])
    end

    # Left-hand normal of a direction: the normal used for layer offsets.
    def left_normal(direction)
      [-direction[1], direction[0]]
    end

    def distance(a, b)
      Math.sqrt(((a[0] - b[0])**2) + ((a[1] - b[1])**2))
    end

    # Intersection of two offset lines:
    #   n_a . X = a_offset + n_a . p     and     n_b . X = b_offset + n_b . q
    # Returns [x, y], or nil when the lines are parallel.
    def line_intersection(p, n_a, a_offset, q, n_b, b_offset)
      r1 = a_offset + (n_a[0] * p[0]) + (n_a[1] * p[1])
      r2 = b_offset + (n_b[0] * q[0]) + (n_b[1] * q[1])
      det = (n_a[0] * n_b[1]) - (n_a[1] * n_b[0])
      return nil if det.abs < 1e-9

      [((r1 * n_b[1]) - (n_a[1] * r2)) / det, ((n_a[0] * r2) - (n_b[0] * r1)) / det]
    end

    # Mitred corner for every layer boundary of the own wall at a joint.
    # Boundary k of the own wall meets boundary k of the other wall.
    # Falls back to a square cut where the lines are parallel, the other stack
    # has no matching boundary, or the corner lies beyond the limit.
    def boundary_corners(own_point, own_normal, own_offsets,
                         other_point, other_normal, other_offsets,
                         joint_point, limit)
      own_offsets.each_with_index.map do |offset, k|
        square = [own_point[0] + (own_normal[0] * offset), own_point[1] + (own_normal[1] * offset)]
        other_offset = other_offsets[k]
        next square if other_offset.nil?

        corner = line_intersection(own_point, own_normal, offset, other_point, other_normal, other_offset)
        next square if corner.nil? || distance(corner, joint_point) > limit

        corner
      end
    end
  end
end
