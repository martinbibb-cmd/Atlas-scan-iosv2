/// RoomPolygon — Represents the actual room perimeter as an ordered list of
/// vertices in the horizontal (X, Z) plane (Y-up coordinate space, metric metres).
///
/// Critical fix vs V1: V1 used a simple bounding box (rawWidthM × rawDepthM)
/// which rendered every room as a rectangle.  V2 stores the full vertex list
/// extracted from `CapturedRoom.walls` or `ARMeshAnchor` geometry so that
/// L-shapes, T-shapes, alcoves and irregular polygons are faithfully captured.

import Foundation

// MARK: - RoomPolygon

public struct RoomPolygon: Sendable {

    /// Ordered vertices.  The polygon is assumed to be closed (last → first edge
    /// is implicit).  Winding order follows the right-hand Y-up convention.
    public var vertices: [Vertex2D]

    public init(vertices: [Vertex2D]) {
        self.vertices = vertices
    }

    // MARK: Computed properties

    /// Number of vertices (= number of wall segments).
    public var count: Int { vertices.count }

    /// `true` when the polygon has at least 3 vertices.
    public var isValid: Bool { vertices.count >= 3 }

    // MARK: Shoelace formula — signed area

    /// Signed area (m²).  Positive for counter-clockwise winding.
    public var signedArea: Double {
        guard isValid else { return 0 }
        var sum = 0.0
        for i in vertices.indices {
            let j = (i + 1) % vertices.count
            sum += vertices[i].x * vertices[j].z
            sum -= vertices[j].x * vertices[i].z
        }
        return sum / 2.0
    }

    /// Unsigned floor area (m²).
    public var area: Double { abs(signedArea) }

    // MARK: Centroid

    /// Geometric centroid of the polygon.
    public var centroid: Vertex2D {
        guard isValid else {
            return vertices.first ?? Vertex2D(x: 0, z: 0)
        }
        let a = signedArea
        guard abs(a) > 1e-10 else {
            // Degenerate — return average
            let avgX = vertices.map(\.x).reduce(0, +) / Double(vertices.count)
            let avgZ = vertices.map(\.z).reduce(0, +) / Double(vertices.count)
            return Vertex2D(x: avgX, z: avgZ)
        }
        var cx = 0.0
        var cz = 0.0
        for i in vertices.indices {
            let j = (i + 1) % vertices.count
            let cross = vertices[i].x * vertices[j].z - vertices[j].x * vertices[i].z
            cx += (vertices[i].x + vertices[j].x) * cross
            cz += (vertices[i].z + vertices[j].z) * cross
        }
        let factor = 1.0 / (6.0 * a)
        return Vertex2D(x: cx * factor, z: cz * factor)
    }

    // MARK: Perimeter

    /// Total perimeter length (m).
    public var perimeter: Double {
        guard isValid else { return 0 }
        return vertices.indices.reduce(0) { sum, i in
            let j = (i + 1) % vertices.count
            let dx = vertices[j].x - vertices[i].x
            let dz = vertices[j].z - vertices[i].z
            return sum + (dx * dx + dz * dz).squareRoot()
        }
    }

    // MARK: Point-in-polygon (ray casting)

    /// Returns `true` when `point` lies inside the polygon.
    public func contains(_ point: Vertex2D) -> Bool {
        guard isValid else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let xi = vertices[i].x, zi = vertices[i].z
            let xj = vertices[j].x, zj = vertices[j].z
            let intersect = ((zi > point.z) != (zj > point.z))
                && (point.x < (xj - xi) * (point.z - zi) / (zj - zi) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    // MARK: Axis-aligned bounding box

    public struct BoundingBox: Sendable {
        public let minX: Double
        public let maxX: Double
        public let minZ: Double
        public let maxZ: Double
        public var widthM:  Double { maxX - minX }
        public var depthM:  Double { maxZ - minZ }
    }

    public var boundingBox: BoundingBox? {
        guard !vertices.isEmpty else { return nil }
        let xs = vertices.map(\.x)
        let zs = vertices.map(\.z)
        return BoundingBox(
            minX: xs.min()!, maxX: xs.max()!,
            minZ: zs.min()!, maxZ: zs.max()!
        )
    }

    // MARK: Wall segments

    /// Returns wall segments as (start, end) pairs.
    public var wallSegments: [(start: Vertex2D, end: Vertex2D)] {
        guard isValid else { return [] }
        return vertices.indices.map { i in
            (vertices[i], vertices[(i + 1) % vertices.count])
        }
    }
}

// MARK: - Polygon extraction helpers

public extension RoomPolygon {

    /// Build a `RoomPolygon` from a flat array of alternating (x, z) values.
    static func from(flatXZ: [Double]) -> RoomPolygon {
        precondition(flatXZ.count.isMultiple(of: 2),
                     "flatXZ must have an even count")
        var verts: [Vertex2D] = []
        var i = flatXZ.startIndex
        while i < flatXZ.endIndex {
            verts.append(Vertex2D(x: flatXZ[i], z: flatXZ[i + 1]))
            i += 2
        }
        return RoomPolygon(vertices: verts)
    }

    /// Build a `RoomPolygon` from the vertex buffer of an ARMeshAnchor geometry
    /// projected onto the (X, Z) plane.  Only the convex hull of the projected
    /// points is returned; for actual RoomPlan captures use `from(capturedRoomWalls:)`.
    ///
    /// - Parameter vertices: Array of (x, y, z) tuples in Y-up world space.
    static func convexHullFrom(vertices: [(x: Float, y: Float, z: Float)]) -> RoomPolygon {
        let projected = vertices.map { Vertex2D(x: Double($0.x), z: Double($0.z)) }
        return RoomPolygon(vertices: convexHull(of: projected))
    }

    // MARK: - Andrew's monotone chain convex hull

    private static func convexHull(of points: [Vertex2D]) -> [Vertex2D] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted { a, b in
            a.x == b.x ? a.z < b.z : a.x < b.x
        }

        func cross(_ O: Vertex2D, _ A: Vertex2D, _ B: Vertex2D) -> Double {
            (A.x - O.x) * (B.z - O.z) - (A.z - O.z) * (B.x - O.x)
        }

        var lower: [Vertex2D] = []
        for p in sorted {
            while lower.count >= 2,
                  cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [Vertex2D] = []
        for p in sorted.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}
