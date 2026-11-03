# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Curved wall geometry (pure, no SketchUp API)
#
# A curved wall stores its centre line as an arc: centre, radius (mm) and a
# signed sweep (radians; positive = counter-clockwise). Layers are concentric.
# ==============================================================================

module MMA_WallsAndSlabs
  module ArcGeometry
    MAX_STEP = 3.0 * Math::PI / 180.0
    TWO_PI = 2.0 * Math::PI

    module_function

    # Circle through three points. Returns { center: [x, y], radius:, start:, sweep: }
    # where start is the angle of p0 and sweep runs p0 -> p1 -> p2. nil if collinear.
    def from_three_points(p0, p1, p2)
      ax, ay = p0[0].to_f, p0[1].to_f
      bx, by = p1[0].to_f, p1[1].to_f
      cx, cy = p2[0].to_f, p2[1].to_f
      d = 2.0 * ((ax * (by - cy)) + (bx * (cy - ay)) + (cx * (ay - by)))
      return nil if d.abs < 1e-9

      a2 = (ax * ax) + (ay * ay)
      b2 = (bx * bx) + (by * by)
      c2 = (cx * cx) + (cy * cy)
      ux = ((a2 * (by - cy)) + (b2 * (cy - ay)) + (c2 * (ay - by))) / d
      uy = ((a2 * (cx - bx)) + (b2 * (ax - cx)) + (c2 * (bx - ax))) / d
      radius = Math.hypot(ax - ux, ay - uy)

      start = Math.atan2(ay - uy, ax - ux)
      mid = normalise(Math.atan2(by - uy, bx - ux) - start)
      last = normalise(Math.atan2(cy - uy, cx - ux) - start)
      sweep = mid < last ? last : last - TWO_PI
      { center: [ux, uy], radius: radius, start: start, sweep: sweep }
    end

    # Angle of a point seen from the centre.
    def angle(center, point)
      Math.atan2(point[1] - center[1], point[0] - center[0])
    end

    # Points along an arc of the given radius, starting at angle start.
    def sample(center, radius, start, sweep, step = MAX_STEP)
      count = [(sweep.abs / step).ceil, 2].max
      (0..count).map do |i|
        a = start + (sweep * i / count)
        [center[0] + (radius * Math.cos(a)), center[1] + (radius * Math.sin(a))]
      end
    end

    # Radius of the boundary at signed offset (left of travel positive) from the
    # centre line. Travelling counter-clockwise, left points to the centre.
    def offset_radius(radius, sweep, offset)
      side = sweep.positive? ? 1.0 : -1.0
      radius - (side * offset)
    end

    def normalise(angle)
      angle % TWO_PI
    end
  end
end
