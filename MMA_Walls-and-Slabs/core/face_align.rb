# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Align a new wall to an existing wall face (pure)
#
# The new wall is placed on the outward side of the picked face, so that its
# near boundary sits on that face. Units are whatever the caller uses (inches
# inside SketchUp, mm in tests), as long as they are consistent.
# ==============================================================================

module MMA_WallsAndSlabs
  module FaceAlign
    module_function

    # Reference line for a wall whose near face lies on the picked face.
    #   face_point   - [x, y, z] on the picked face
    #   side_normal  - [x, y] pointing away from the existing wall
    #   total        - total thickness of the new wall
    #   justification - 'outer', 'center' or 'inner'
    # Returns { origin: [x, y, z], direction: [dx, dy] }. The wall's left normal
    # equals side_normal, so its layers stand on the chosen side.
    def reference(face_point, side_normal, total, justification)
      length = Math.hypot(side_normal[0], side_normal[1])
      nx = side_normal[0] / length
      ny = side_normal[1] / length
      # Distance from the face to the centre line, so that the near face of
      # the new wall is exactly on the face.
      distance = case justification.to_s
                 when 'outer', 'left' then 0.0
                 when 'inner', 'right' then total
                 else total / 2.0
                 end
      origin = [face_point[0] + (nx * distance), face_point[1] + (ny * distance), face_point[2]]
      # Direction whose left normal is (nx, ny): left normal of (dx, dy) is (-dy, dx).
      { origin: origin, direction: [ny, -nx] }
    end

    # Closest point to (x, y) on the reference line, as [x, y].
    def project(x, y, reference)
      dx, dy = reference[:direction]
      ox, oy = reference[:origin]
      t = ((x - ox) * dx) + ((y - oy) * dy)
      [ox + (t * dx), oy + (t * dy)]
    end

    # Signed distance along the reference direction from its origin.
    def along(x, y, reference)
      dx, dy = reference[:direction]
      ox, oy = reference[:origin]
      ((x - ox) * dx) + ((y - oy) * dy)
    end
  end
end
