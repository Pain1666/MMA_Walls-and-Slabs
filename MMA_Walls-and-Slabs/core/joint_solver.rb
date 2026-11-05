# frozen_string_literal: true
# ==============================================================================
# MMA_Walls-and-Slabs - Joint solver for wall layers (pure, no SketchUp API)
#
# A boundary line is: X such that n . X = n . joint + offset, where n is the
# left normal of the wall's path and offset is measured in the path frame.
#
# corner : L / end-to-end joint, solved like a closed-loop vertex (see corner_by_index).
# tee    : a stub ends on a through wall. Core ends at the through wall's core
#          face, every other layer ends at the through wall's outer face.
# chamfer: both ends are cut by one line through two points (the chamfer line).
# ==============================================================================

require_relative 'joint_geometry'

module MMA_WallsAndSlabs
  module JointSolver
    EPS = 1e-6

    module_function

    def corner_point(p1, n1, q1, p2, n2, q2)
      JointGeometry.line_intersection(p1, n1, q1, p2, n2, q2)
    end

    def square_cut(joint, normal, q)
      [joint[0] + (normal[0] * q), joint[1] + (normal[1] * q)]
    end

    def distance(a, b)
      JointGeometry.distance(a, b)
    end

    def pad_to(list, size)
      list + Array.new(size - list.length) { list.last }
    end

    # Corner of two walls at a shared joint point, the same way a closed loop
    # mitres a vertex: boundary k of one wall meets boundary k of the other.
    # n_own / n_other: left normals of each wall's path at the joint.
    # own_b / other_b: path-frame offsets of every layer boundary (same count).
    # Returns one corner per boundary, in the same order.
    def corner_by_index(joint, n_own, own_b, n_other, other_b, limit)
      own_b.each_index.map do |index|
        candidate = corner_point(joint, n_own, own_b[index], joint, n_other, other_b[index])
        candidate && distance(candidate, joint) <= limit ? candidate : square_cut(joint, n_own, own_b[index])
      end
    end

    # Stub layer ends on a through wall. core_flags marks the stub's core boundaries.
    # through_point is a point on the through wall's centre line; n_through its left normal.
    def tee(joint, n_stub, stub_q, core_flags, through_point, n_through, face_core, face_outer, limit)
      stub_q.each_index.map do |index|
        q = stub_q[index]
        face = core_flags[index] ? face_core : face_outer
        candidate = corner_point(joint, n_stub, q, through_point, n_through, face)
        candidate && distance(candidate, joint) <= limit ? candidate : square_cut(joint, n_stub, q)
      end
    end

    # Every boundary ends on the chamfer line through cut_a and cut_b.
    def chamfer(joint, n_own, own_q, cut_a, cut_b)
      dx = cut_b[0] - cut_a[0]
      dy = cut_b[1] - cut_a[1]
      length = Math.hypot(dx, dy)
      return own_q.map { |q| square_cut(joint, n_own, q) } if length < EPS

      n_cut = [-dy / length, dx / length]
      own_q.map do |q|
        corner_point(joint, n_own, q, cut_a, n_cut, 0.0) || square_cut(joint, n_own, q)
      end
    end
  end
end
