# frozen_string_literal: true
# ============================================================================== 
# MMA_Walls-and-Slabs - Create objects from selected SketchUp geometry
# ============================================================================== 

require_relative '../core/geometry_helper'

module MMA_WallsAndSlabs
  module SelectionTools
    module_function

    # Returns a connected horizontal edge path in millimeters, suitable for the
    # existing wall path builder. Supports an open chain or a closed loop.
    def wall_path(selection)
      edges = selection.to_a.flat_map do |entity|
        if entity.is_a?(Sketchup::Edge)
          [entity]
        elsif defined?(Sketchup::Curve) && entity.is_a?(Sketchup::Curve)
          entity.edges
        else
          []
        end
      end.uniq
      raise ArgumentError, 'Select the edges of one connected polyline or curve.' if edges.empty?

      adjacency = Hash.new { |hash, vertex| hash[vertex] = [] }
      edges.each do |edge|
        adjacency[edge.start] << edge
        adjacency[edge.end] << edge
      end
      endpoints = adjacency.select { |_vertex, incident| incident.length == 1 }.keys
      unless endpoints.empty? || endpoints.length == 2
        raise ArgumentError, 'The selected edges must form one open path or one closed loop.'
      end
      if adjacency.any? { |_vertex, incident| incident.length > 2 }
        raise ArgumentError, 'The selected edges branch; select a single path.'
      end

      start = endpoints.first || edges.first.start
      ordered_vertices = [start]
      visited = {}
      current = start
      loop do
        edge = adjacency[current].find { |candidate| !visited[candidate] }
        break unless edge

        visited[edge] = true
        current = edge.start == current ? edge.end : edge.start
        ordered_vertices << current
      end
      raise ArgumentError, 'The selected edges contain disconnected paths.' unless visited.length == edges.length

      points = ordered_vertices.map do |vertex|
        point = vertex.position
        [GeometryHelper.to_mm(point.x), GeometryHelper.to_mm(point.y), GeometryHelper.to_mm(point.z)]
      end
      z = points.first[2]
      unless points.all? { |point| (point[2] - z).abs <= 0.1 }
        raise ArgumentError, 'Wall paths must be horizontal; select edges at one elevation.'
      end

      { 'points' => points, 'closed' => endpoints.empty? }
    end

    def selected_face(selection)
      faces = selection.to_a.grep(Sketchup::Face)
      raise ArgumentError, 'Select exactly one planar face to create a slab.' unless faces.length == 1

      faces.first
    end
  end
end
