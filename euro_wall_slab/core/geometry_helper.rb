# frozen_string_literal: true
# ==============================================================================
# Euro Wall & Slab - Geometry & Corner Joint Helpers
# ==============================================================================

require_relative 'constants'

module EuroWallSlab
  module GeometryHelper
    # Convert mm to SketchUp internal inches
    def self.mm(val)
      val.to_f / 25.4
    end

    # Convert SketchUp internal inches to mm
    def self.to_mm(val)
      val.to_f * 25.4
    end

    # Fetch or create a SketchUp Material with accurate color and optional texture
    def self.get_or_create_material(model, mat_name)
      return nil if mat_name.nil? || mat_name.to_s.strip.empty?

      materials = model.materials
      existing = materials[mat_name]
      if existing
        # Ensure it is not black if it belongs to our palette
        if DefaultMaterials::PALETTE.key?(mat_name) && existing.color.red == 0 && existing.color.green == 0 && existing.color.blue == 0
          rgb = DefaultMaterials::PALETTE[mat_name]
          existing.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2]) rescue (existing.color = rgb)
        end
        return existing
      end

      # Material does not exist, create it
      mat = materials.add(mat_name)

      if DefaultMaterials::PALETTE.key?(mat_name)
        rgb = DefaultMaterials::PALETTE[mat_name]
        begin
          mat.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
        rescue
          mat.color = rgb
        end
        mat.alpha = 1.0

        # Check for bundled photo texture
        tex_file = DefaultMaterials::TEXTURE_FILES[mat_name]
        if tex_file
          tex_path = File.join(File.dirname(__dir__), 'materials', tex_file)
          if File.exist?(tex_path)
            begin
              mat.texture = tex_path
              tex_size = DefaultMaterials::TEXTURE_SIZES[tex_file] || [600.0, 600.0]
              mat.texture.size = [mm(tex_size[0]), mm(tex_size[1])]
            rescue => e
              puts "[EuroWallSlab] Notice: Texture load skipped (#{e.message})"
            end
          end
        end
      end

      mat
    end

    # Scale a vector safely by any scalar (positive, zero, or negative)
    def self.vec_scale(v, s)
      Geom::Vector3d.new(v.x * s, v.y * s, v.z * s)
    end

    # Calculate intersection of a 3D ray with a 3D plane
    # p_ray: Point3d ray origin
    # v_dir: Vector3d ray direction
    # p_plane: Point3d point on plane
    # v_norm: Vector3d plane normal
    def self.ray_plane_intersection(p_ray, v_dir, p_plane, v_norm)
      denom = v_dir.dot(v_norm)
      return p_ray if denom.abs < 1e-5

      t = (p_plane - p_ray).dot(v_norm) / denom
      p_ray + vec_scale(v_dir, t)
    end

    # Calculate exact 3D corner miter point at offset distance y from the baseline.
    # Handles arbitrary angle corners (acute, right, obtuse, reflex) and collinear segments.
    # pt: vertex Geom::Point3d
    # dir_prev, norm_prev: direction and normal of segment arriving at pt
    # dir_curr, norm_curr: direction and normal of segment departing from pt
    # y: offset distance in internal inches
    def self.miter_point(pt, dir_prev, norm_prev, dir_curr, norm_curr, y)
      # If no previous segment, offset perpendicularly to current segment
      if dir_prev.nil? || norm_prev.nil?
        return pt + vec_scale(norm_curr, y)
      end

      # If no current segment, offset perpendicularly to previous segment
      if dir_curr.nil? || norm_curr.nil?
        return pt + vec_scale(norm_prev, y)
      end

      # If collinear segments (straight line)
      if dir_prev.parallel?(dir_curr)
        return pt + vec_scale(norm_curr, y)
      end

      # Line 1: parallel to dir_prev passing through (pt + y * norm_prev)
      p1 = pt + vec_scale(norm_prev, y)
      line1 = [p1, dir_prev]

      # Line 2: parallel to dir_curr passing through (pt + y * norm_curr)
      p2 = pt + vec_scale(norm_curr, y)
      line2 = [p2, dir_curr]

      int_pt = Geom.intersect_line_line(line1, line2)

      if int_pt
        # Clamp miter spikes for ultra-sharp angles (< 15 degrees)
        max_dist = [y.abs * 4.0, 40.0].max # up to 40 inches or 4x thickness
        if pt.distance(int_pt) > max_dist
          return p2
        end
        int_pt
      else
        p2
      end
    end

    # Create a 3D solid mitered layer prism in entities.
    # s1, e1: start and end points on face 1 (at offset y1)
    # s2, e2: start and end points on face 2 (at offset y2)
    # height: extrusion height (Z)
    def self.create_mitered_layer_box(entities, s1, e1, e2, s2, height, material = nil)
      return nil if height <= 0.001

      # Bottom face points: S1 -> E1 -> E2 -> S2
      pts = [s1, e1, e2, s2]

      # Ensure points are not degenerate
      return nil if s1.distance(e1) < 0.001 && s2.distance(e2) < 0.001

      face = entities.add_face(pts)
      return nil unless face

      # Extrude upward along Z
      vz = Geom::Vector3d.new(0, 0, 1)
      if face.normal.samedirection?(vz)
        face.pushpull(height)
      else
        face.pushpull(-height)
      end

      # Apply material to all faces of this prism
      if material
        entities.grep(Sketchup::Face).each do |f|
          f.material = material
          f.back_material = material
        end
      end

      true
    end

    # Create a standard oriented rectangular solid box
    def self.create_oriented_box(entities, p_base, vx, vy, vz, dx, dy, dz, material = nil)
      return nil if dx <= 0.001 || dy <= 0.001 || dz <= 0.001

      p0 = p_base
      p1 = p0 + (vx.clone.tap { |v| v.length = dx })
      p2 = p1 + (vy.clone.tap { |v| v.length = dy })
      p3 = p0 + (vy.clone.tap { |v| v.length = dy })

      bottom_face = entities.add_face(p0, p1, p2, p3)
      return nil unless bottom_face

      if bottom_face.normal.samedirection?(vz)
        bottom_face.pushpull(dz)
      else
        bottom_face.pushpull(-dz)
      end

      if material
        entities.grep(Sketchup::Face).each do |face|
          face.material = material
          face.back_material = material
        end
      end

      true
    end

    # Create a C-channel metal stud
    def self.create_c_stud(entities, p_origin, vx, vy, vz, web_w, flange_d, gauge, length, material = nil)
      return if length <= 0.001

      w = web_w
      f = flange_d
      g = gauge

      pts = [
        p_origin,
        p_origin + (vx.clone.tap { |v| v.length = f }),
        p_origin + (vx.clone.tap { |v| v.length = f }) + (vy.clone.tap { |v| v.length = g }),
        p_origin + (vx.clone.tap { |v| v.length = g }) + (vy.clone.tap { |v| v.length = g }),
        p_origin + (vx.clone.tap { |v| v.length = g }) + (vy.clone.tap { |v| v.length = w - g }),
        p_origin + (vx.clone.tap { |v| v.length = f }) + (vy.clone.tap { |v| v.length = w - g }),
        p_origin + (vx.clone.tap { |v| v.length = f }) + (vy.clone.tap { |v| v.length = w }),
        p_origin + (vy.clone.tap { |v| v.length = w })
      ]

      face = entities.add_face(pts)
      return unless face

      if face.normal.samedirection?(vz)
        face.pushpull(length)
      else
        face.pushpull(-length)
      end

      if material
        entities.grep(Sketchup::Face).each do |f_elem|
          f_elem.material = material
          f_elem.back_material = material
        end
      end
    end

    # Decompose a segment around openings into solid intervals [x_start, x_len, z_start, z_len]
    def self.decompose_panel_with_openings(length, height, openings)
      blocks = []

      valid_ops = openings.select do |op|
        op[:x] < length && (op[:x] + op[:width]) > 0 &&
          op[:sill] < height && (op[:sill] + op[:height]) > 0
      end.sort_by { |op| op[:x] }

      current_x = 0.0

      valid_ops.each do |op|
        ox = [op[:x], 0.0].max
        ow = [op[:width] - ([0.0, -op[:x]].max), length - ox].min
        next if ow <= 0.001

        # Solid block from current_x to ox
        if ox > current_x + 0.001
          blocks << [current_x, ox - current_x, 0.0, height]
        end

        # Sill segment
        s_h = [[op[:sill], 0.0].max, height].min
        if s_h > 0.001
          blocks << [ox, ow, 0.0, s_h]
        end

        # Lintel segment
        op_top = op[:sill] + op[:height]
        if op_top < height - 0.001
          lintel_h = height - op_top
          blocks << [ox, ow, op_top, lintel_h]
        end

        current_x = ox + ow
      end

      if current_x < length - 0.001
        blocks << [current_x, length - current_x, 0.0, height]
      end

      blocks
    end
  end
end
