# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Geometry & Corner Joint Helpers
# ==============================================================================

require_relative 'constants'

module MMA_WallsAndSlabs
  module GeometryHelper
    def self.mm(val)
      val.to_f / 25.4
    end

    def self.to_mm(val)
      val.to_f * 25.4
    end

    def self.get_or_create_material(model, mat_name)
      return nil if mat_name.nil? || mat_name.to_s.strip.empty?

      materials = model.materials
      existing = materials[mat_name]
      if existing
        if DefaultMaterials::PALETTE.key?(mat_name) && existing.color.red == 0 && existing.color.green == 0 && existing.color.blue == 0
          rgb = DefaultMaterials::PALETTE[mat_name]
          existing.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2]) rescue (existing.color = rgb)
        end
        return existing
      end

      mat = materials.add(mat_name)

      if DefaultMaterials::PALETTE.key?(mat_name)
        rgb = DefaultMaterials::PALETTE[mat_name]
        begin
          mat.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
        rescue
          mat.color = rgb
        end
        mat.alpha = 1.0

        tex_file = DefaultMaterials::TEXTURE_FILES[mat_name]
        if tex_file
          tex_path = File.join(File.dirname(__dir__), 'materials', tex_file)
          if File.exist?(tex_path)
            begin
              mat.texture = tex_path
              tex_size = DefaultMaterials::TEXTURE_SIZES[tex_file] || [600.0, 600.0]
              mat.texture.size = [mm(tex_size[0]), mm(tex_size[1])]
            rescue => e
              puts "[MMA_WallsAndSlabs] Notice: Texture load skipped (#{e.message})"
            end
          end
        end
      end

      mat
    end

    def self.vec_scale(v, s)
      Geom::Vector3d.new(v.x * s, v.y * s, v.z * s)
    end

    def self.ray_plane_intersection(p_ray, v_dir, p_plane, v_norm)
      denom = v_dir.dot(v_norm)
      return p_ray if denom.abs < 1e-5

      t = (p_plane - p_ray).dot(v_norm) / denom
      p_ray + vec_scale(v_dir, t)
    end
  end
end
