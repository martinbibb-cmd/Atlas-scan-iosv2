import XCTest
@testable import AtlasScanCore

final class RoomPolygonTests: XCTestCase {

    // MARK: - Validity

    func test_polygon_withFewer3Vertices_isInvalid() {
        XCTAssertFalse(RoomPolygon(vertices: []).isValid)
        XCTAssertFalse(RoomPolygon(vertices: [Vertex2D(x: 0, z: 0)]).isValid)
        XCTAssertFalse(RoomPolygon(vertices: [Vertex2D(x: 0, z: 0), Vertex2D(x: 1, z: 0)]).isValid)
    }

    func test_polygon_with3Vertices_isValid() {
        let poly = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0), Vertex2D(x: 1, z: 0), Vertex2D(x: 0, z: 1)
        ])
        XCTAssertTrue(poly.isValid)
    }

    // MARK: - Area (shoelace)

    func test_unitSquare_area_is1() {
        let square = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 1, z: 0),
            Vertex2D(x: 1, z: 1),
            Vertex2D(x: 0, z: 1)
        ])
        XCTAssertEqual(square.area, 1.0, accuracy: 1e-10)
    }

    func test_3x4Rectangle_area_is12() {
        let rect = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 3, z: 0),
            Vertex2D(x: 3, z: 4),
            Vertex2D(x: 0, z: 4)
        ])
        XCTAssertEqual(rect.area, 12.0, accuracy: 1e-10)
    }

    func test_LShape_area_isCorrect() {
        // L-shape: 3×3 with a 1×1 corner removed
        // Expected area = 9 - 1 = 8
        let lShape = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 3, z: 0),
            Vertex2D(x: 3, z: 2),
            Vertex2D(x: 2, z: 2),
            Vertex2D(x: 2, z: 3),
            Vertex2D(x: 0, z: 3)
        ])
        XCTAssertEqual(lShape.area, 8.0, accuracy: 1e-10)
    }

    // MARK: - Perimeter

    func test_unitSquare_perimeter_is4() {
        let square = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 1, z: 0),
            Vertex2D(x: 1, z: 1),
            Vertex2D(x: 0, z: 1)
        ])
        XCTAssertEqual(square.perimeter, 4.0, accuracy: 1e-10)
    }

    // MARK: - Point-in-polygon

    func test_centreOfSquare_isInside() {
        let square = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 2, z: 0),
            Vertex2D(x: 2, z: 2),
            Vertex2D(x: 0, z: 2)
        ])
        XCTAssertTrue(square.contains(Vertex2D(x: 1, z: 1)))
    }

    func test_outsidePoint_isNotInside() {
        let square = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 2, z: 0),
            Vertex2D(x: 2, z: 2),
            Vertex2D(x: 0, z: 2)
        ])
        XCTAssertFalse(square.contains(Vertex2D(x: 5, z: 5)))
    }

    // MARK: - Bounding box

    func test_boundingBox_correctForRectangle() {
        let rect = RoomPolygon(vertices: [
            Vertex2D(x: 1, z: 2),
            Vertex2D(x: 5, z: 2),
            Vertex2D(x: 5, z: 6),
            Vertex2D(x: 1, z: 6)
        ])
        let bb = rect.boundingBox!
        XCTAssertEqual(bb.minX, 1, accuracy: 1e-10)
        XCTAssertEqual(bb.maxX, 5, accuracy: 1e-10)
        XCTAssertEqual(bb.minZ, 2, accuracy: 1e-10)
        XCTAssertEqual(bb.maxZ, 6, accuracy: 1e-10)
        XCTAssertEqual(bb.widthM, 4, accuracy: 1e-10)
        XCTAssertEqual(bb.depthM, 4, accuracy: 1e-10)
    }

    // MARK: - Flat array construction

    func test_fromFlatXZ_buildsCorrectPolygon() {
        let poly = RoomPolygon.from(flatXZ: [0, 0, 1, 0, 1, 1, 0, 1])
        XCTAssertEqual(poly.count, 4)
        XCTAssertEqual(poly.vertices[0].x, 0)
        XCTAssertEqual(poly.vertices[2].z, 1)
    }

    // MARK: - Centroid

    func test_unitSquare_centroidIsCenter() {
        let square = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 1, z: 0),
            Vertex2D(x: 1, z: 1),
            Vertex2D(x: 0, z: 1)
        ])
        let c = square.centroid
        XCTAssertEqual(c.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.z, 0.5, accuracy: 1e-6)
    }

    // MARK: - Wall segments

    func test_wallSegments_countEqualsVertices() {
        let square = RoomPolygon(vertices: [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 1, z: 0),
            Vertex2D(x: 1, z: 1),
            Vertex2D(x: 0, z: 1)
        ])
        XCTAssertEqual(square.wallSegments.count, 4)
    }

    // MARK: - Convex hull

    func test_convexHull_returnsAtLeast3Vertices() {
        let points: [(x: Float, y: Float, z: Float)] = [
            (0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1),
            (0.5, 0, 0.5)   // interior point — should be excluded
        ]
        let hull = RoomPolygon.convexHullFrom(vertices: points)
        XCTAssertGreaterThanOrEqual(hull.count, 3)
        XCTAssertLessThanOrEqual(hull.count, 4)
    }
}
