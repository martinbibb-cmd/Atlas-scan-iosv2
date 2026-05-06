import XCTest
@testable import AtlasScanCore

final class MollerTrumboreTests: XCTestCase {

    // MARK: - Basic intersection

    func test_rayHitsTriangle_returnsHit() {
        // Triangle in the XZ plane at y = 0
        let v0 = Vec3(0, 0, 0)
        let v1 = Vec3(1, 0, 0)
        let v2 = Vec3(0, 0, 1)

        // Ray pointing straight down from above the triangle
        let origin    = Vec3(0.2, 1, 0.2)
        let direction = Vec3(0, -1, 0)

        let hit = MollerTrumbore.intersect(
            rayOrigin: origin,
            rayDirection: direction,
            v0: v0, v1: v1, v2: v2
        )

        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.t, 1.0, accuracy: 1e-6)
        XCTAssertEqual(hit!.point.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(hit!.point.y, 0.0, accuracy: 1e-6)
        XCTAssertEqual(hit!.point.z, 0.2, accuracy: 1e-6)
    }

    func test_rayMissesTriangle_returnsNil() {
        let v0 = Vec3(0, 0, 0)
        let v1 = Vec3(1, 0, 0)
        let v2 = Vec3(0, 0, 1)

        // Ray pointing down but offset far from the triangle
        let origin    = Vec3(5, 1, 5)
        let direction = Vec3(0, -1, 0)

        let hit = MollerTrumbore.intersect(
            rayOrigin: origin,
            rayDirection: direction,
            v0: v0, v1: v1, v2: v2
        )
        XCTAssertNil(hit)
    }

    func test_parallelRay_returnsNil() {
        let v0 = Vec3(0, 0, 0)
        let v1 = Vec3(1, 0, 0)
        let v2 = Vec3(0, 0, 1)

        // Ray parallel to triangle plane
        let origin    = Vec3(0, 0, 0)
        let direction = Vec3(1, 0, 0)

        let hit = MollerTrumbore.intersect(
            rayOrigin: origin,
            rayDirection: direction,
            v0: v0, v1: v1, v2: v2
        )
        XCTAssertNil(hit)
    }

    func test_backfaceCulling_preventsHitFromBehind() {
        // Triangle (v0, v1, v2) = (0,0,0), (1,0,0), (0,0,1).
        // edge1 × edge2 = (1,0,0)×(0,0,1) = (0,-1,0) — face normal points -Y.
        // In the Möller–Trumbore convention a = e1·(d×e2).
        // A ray from ABOVE (direction 0,-1,0) yields a < 0 — back-face hit.
        // backfaceCulling=true should reject it; backfaceCulling=false should keep it.
        let v0 = Vec3(0, 0, 0)
        let v1 = Vec3(1, 0, 0)
        let v2 = Vec3(0, 0, 1)

        // Ray coming from above — this is the back-face in MT convention for this winding.
        let origin    = Vec3(0.2, 1, 0.2)
        let direction = Vec3(0, -1, 0)

        let withCulling = MollerTrumbore.intersect(
            rayOrigin: origin, rayDirection: direction,
            v0: v0, v1: v1, v2: v2, backfaceCulling: true
        )
        let withoutCulling = MollerTrumbore.intersect(
            rayOrigin: origin, rayDirection: direction,
            v0: v0, v1: v1, v2: v2, backfaceCulling: false
        )

        XCTAssertNil(withCulling)
        XCTAssertNotNil(withoutCulling)
    }

    // MARK: - AABB ray test

    func test_rayHitsAABB() {
        let boxMin = Vec3(-1, -1, -1)
        let boxMax = Vec3( 1,  1,  1)

        let origin    = Vec3(0, 5, 0)
        let direction = Vec3(0, -1, 0)

        XCTAssertTrue(MollerTrumbore.intersectsAABB(
            rayOrigin: origin, rayDirection: direction,
            boxMin: boxMin, boxMax: boxMax
        ))
    }

    func test_rayMissesAABB() {
        let boxMin = Vec3(-1, -1, -1)
        let boxMax = Vec3( 1,  1,  1)

        let origin    = Vec3(5, 5, 0)
        let direction = Vec3(0, -1, 0)   // passes beside the box

        XCTAssertFalse(MollerTrumbore.intersectsAABB(
            rayOrigin: origin, rayDirection: direction,
            boxMin: boxMin, boxMax: boxMax
        ))
    }

    // MARK: - Clearance conflict detection

    func test_conflictDetected_whenMeshPiercesGhostBox() {
        // Ghost box: 1m × 1m × 1m cube centred at origin
        let box = ClearanceConflictDetector.GhostBox(
            centre: Vec3(0, 0, 0),
            halfExtentX: 0.5, halfExtentY: 0.5, halfExtentZ: 0.5
        )

        // Triangle completely inside the ghost box
        let tri: ClearanceConflictDetector.Triangle = (
            v0: Vec3(-0.1,  0.1,  0.0),
            v1: Vec3( 0.1,  0.1,  0.0),
            v2: Vec3( 0.0, -0.1,  0.0)
        )

        XCTAssertTrue(ClearanceConflictDetector.meshConflicts([tri], ghostBox: box))
    }

    func test_noConflict_whenMeshIsOutsideGhostBox() {
        let box = ClearanceConflictDetector.GhostBox(
            centre: Vec3(0, 0, 0),
            halfExtentX: 0.5, halfExtentY: 0.5, halfExtentZ: 0.5
        )

        // Triangle far outside the ghost box
        let tri: ClearanceConflictDetector.Triangle = (
            v0: Vec3(5.0, 0, 0),
            v1: Vec3(6.0, 0, 0),
            v2: Vec3(5.5, 1, 0)
        )

        XCTAssertFalse(ClearanceConflictDetector.meshConflicts([tri], ghostBox: box))
    }

    func test_qaFlag_isConflictWhenMeshPierces() {
        let roomId = UUID()
        let box = ClearanceConflictDetector.GhostBox(
            centre: Vec3(0, 0, 0),
            halfExtentX: 0.5, halfExtentY: 0.5, halfExtentZ: 0.5
        )
        let tri: ClearanceConflictDetector.Triangle = (
            v0: Vec3(0, 0, 0), v1: Vec3(0.1, 0, 0), v2: Vec3(0, 0.1, 0)
        )
        let flag = ClearanceConflictDetector.qaFlag(for: [tri], ghostBox: box, roomId: roomId)
        XCTAssertEqual(flag.type, .clearanceConflict)
        XCTAssertEqual(flag.roomId, roomId)
    }

    func test_qaFlag_isPassWhenMeshClear() {
        let roomId = UUID()
        let box = ClearanceConflictDetector.GhostBox(
            centre: Vec3(0, 0, 0),
            halfExtentX: 0.5, halfExtentY: 0.5, halfExtentZ: 0.5
        )
        let tri: ClearanceConflictDetector.Triangle = (
            v0: Vec3(5, 0, 0), v1: Vec3(6, 0, 0), v2: Vec3(5.5, 1, 0)
        )
        let flag = ClearanceConflictDetector.qaFlag(for: [tri], ghostBox: box, roomId: roomId)
        XCTAssertEqual(flag.type, .clearancePass)
    }
}
