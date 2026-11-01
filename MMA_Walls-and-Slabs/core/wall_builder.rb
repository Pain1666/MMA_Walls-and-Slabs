# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Geometry & Corner Joint Helpers
# ==============================================================================

require_relative 'constants'

module MMA_WallsAndSlabs
  module GeometryHelper
    @material_cache = {}
    @material_style_cache = {}

    class << self
      def mm(val)
        val.to_f / 25.4
      end

      def to_mm(val)
        val.to_f * 25.4
      end

      def get_or_create_material(model, mat_name)
        return nil if mat_name.nil? || mat_name.to_s.strip.empty?

        name = mat_name.to_s.strip
        cache = (@material_cache[model.object_id] ||= {})
        if cache.key?(name)
          material = cache[name]
          return material if material && material.valid?

          cache.delete(name)
        end

        materials = model.materials
        existing = materials[name]
        if existing
          if DefaultMaterials::PALETTE.key?(name) && default_material_color?(existing)
            rgb = DefaultMaterials::PALETTE[name]
            begin
              existing.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
            rescue
              existing.color = rgb
            end
          end
          cache[name] = existing
          return existing
        end

        mat = materials.add(name)
        apply_default_material_style(mat, name)
        cache[name] = mat
        mat
      end

      def vec_scale(v, s)
        Geom::Vector3d.new(v.x * s, v.y * s, v.z * s)
      end

      def ray_plane_intersection(p_ray, v_dir, p_plane, v_norm)
        denom = v_dir.dot(v_norm)
        return p_ray if denom.abs < 1e-5

        t = (p_plane - p_ray).dot(v_norm) / denom
        p_ray + vec_scale(v_dir, t)
      end

      private

      def default_material_color?(material)
        return false unless material && material.respond_to?(:color)

        color = material.color
        return false unless color

        color.red == 0 && color.green == 0 && color.blue == 0
      end

      def apply_default_material_style(material, name)
        return unless material && material.valid?

        @material_style_cache ||= {}
        if @material_style_cache[name]
          material.alpha = 1.0 if material.respond_to?(:alpha=)
          return
        end

        if DefaultMaterials::PALETTE.key?(name)
          rgb = DefaultMaterials::PALETTE[name]
          begin
            material.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
          rescue
            material.color = rgb
          end
          material.alpha = 1.0 if material.respond_to?(:alpha=)
        end

        tex_file = DefaultMaterials::TEXTURE_FILES[name]
        if tex_file
          tex_path = File.join(File.dirname(__dir__), 'materials', tex_file)
          if File.exist?(tex_path)
            begin
              material.texture = tex_path
              tex_size = DefaultMaterials::TEXTURE_SIZES[tex_file] || [600.0, 600.0]
              material.texture.size = [mm(tex_size[0]), mm(tex_size[1])]
            rescue => e
              puts "[MMA_WallsAndSlabs] Notice: Texture load skipped (#{e.message})"
            end
          end
        end

        @material_style_cache[name] = true
      end
    end
  end
end
