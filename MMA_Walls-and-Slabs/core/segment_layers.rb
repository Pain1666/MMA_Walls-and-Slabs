# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Per-segment layer overrides (pure, no SketchUp API)
#
# A wall's layers are shared by all its segments. A segment may override the
# thickness and/or material of individual layers. Overrides are stored in
# params['segment_layers'] as { "<segment index>" => [nil | {thickness, material}, ...] },
# with one entry per layer of the wall's full layer list (wall_layers order).
# Only values that differ from the base layer are stored.
# ==============================================================================

module MMA_WallsAndSlabs
  module SegmentLayers
    module_function

    # Full layer list with the overrides for one segment applied (copies).
    def apply(layers, overrides, segment)
      per = overrides.is_a?(Hash) ? overrides[segment.to_s] : nil
      layers.each_with_index.map do |layer, index|
        entry = per.is_a?(Array) ? per[index] : nil
        next layer.dup unless entry.is_a?(Hash)

        layer.merge('thickness' => entry['thickness'].to_f,
                    'material' => entry['material'] || layer['material'])
      end
    end

    # Boundary offsets from the centre line for a stack of thicknesses, in the
    # path frame (left of travel is positive). Length = thicknesses + 1.
    def boundaries(thicknesses, justification)
      total = thicknesses.sum
      base = case justification.to_s
             when 'left' then 0.0
             when 'right' then -total
             else -total / 2.0
             end
      offsets = [base]
      thicknesses.each { |thickness| offsets << offsets.last + thickness }
      offsets
    end

    # Records the layer values of one segment. full_layers is the wall's full
    # base layer list, active are the full-list indices that are used, and
    # new_stack holds the new values for those active layers (same order).
    # Removes the segment's override when nothing differs from the base.
    def store(params, segment, full_layers, active, new_stack)
      per = full_layers.each_index.map do |index|
        position = active.index(index)
        next nil unless position

        base = full_layers[index]
        value = new_stack[position]
        thickness = value['thickness'].to_f
        material = value['material'].to_s
        differs = (thickness - base['thickness'].to_f).abs > 1e-6 || material != base['material'].to_s
        differs ? { 'thickness' => thickness, 'material' => material } : nil
      end

      overrides = params['segment_layers'].is_a?(Hash) ? params['segment_layers'].dup : {}
      if per.compact.empty?
        overrides.delete(segment.to_s)
      else
        overrides[segment.to_s] = per
      end
      if overrides.empty?
        params.delete('segment_layers')
      else
        params['segment_layers'] = overrides
      end
      params
    end

    # Closest point on a path (array of [x, y, ...]) to (x, y), as [x, y].
    def project_onto_path(path, x, y, closed = false)
      index = nearest_segment(path, x, y, closed)
      return nil if index.nil?

      a = path[index]
      b = path[(index + 1) % path.length]
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      len2 = (dx * dx) + (dy * dy)
      t = len2 > 1e-12 ? ((((x - a[0]) * dx) + ((y - a[1]) * dy)) / len2).clamp(0.0, 1.0) : 0.0
      [a[0] + (t * dx), a[1] + (t * dy)]
    end

    # Index of the segment whose centre line is nearest to (x, y).
    def nearest_segment(path, x, y, closed = false)
      return nil if path.length < 2

      count = closed ? path.length : path.length - 1
      best = nil
      best_distance = Float::INFINITY
      count.times do |index|
        a = path[index]
        b = path[(index + 1) % path.length]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len2 = (dx * dx) + (dy * dy)
        t = len2 > 1e-12 ? ((((x - a[0]) * dx) + ((y - a[1]) * dy)) / len2).clamp(0.0, 1.0) : 0.0
        distance = Math.hypot(x - (a[0] + (t * dx)), y - (a[1] + (t * dy)))
        if distance < best_distance
          best_distance = distance
          best = index
        end
      end
      best
    end
  end
end
