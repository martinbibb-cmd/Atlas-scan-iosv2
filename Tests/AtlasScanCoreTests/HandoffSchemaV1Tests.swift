import XCTest
@testable import AtlasScanCore

final class HandoffSchemaV1Tests: XCTestCase {

    // MARK: - ScanToMindHandoffV1.visitId

    func test_handoff_visitId_matchesSession() {
        let session = SessionCaptureV2(visitId: UUID())
        let readiness = VisitReadinessV1.derive(from: session)
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)
        XCTAssertEqual(handoff.visitId, session.visitId)
    }

    func test_handoff_visitId_roundTrips_throughJSON() throws {
        let session = SessionCaptureV2(visitId: UUID())
        let readiness = VisitReadinessV1.derive(from: session)
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(handoff)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanToMindHandoffV1.self, from: data)

        XCTAssertEqual(decoded.visitId, session.visitId)
        XCTAssertEqual(decoded.handoffId, handoff.handoffId)
    }

    // MARK: - HardwarePatchV1

    func test_hardwarePatch_roundTrips_throughJSON() throws {
        let patch = HardwarePatchV1(
            targetModelId: UUID(),
            customName: "Custom Vaillant 30kW",
            widthM: 0.440,
            heightM: 0.720,
            depthM: 0.338,
            clearanceFrontOffsetM: 0.050
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(patch)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HardwarePatchV1.self, from: data)

        XCTAssertEqual(decoded.customName, patch.customName)
        XCTAssertEqual(decoded.widthM, patch.widthM, accuracy: 0.001)
        XCTAssertEqual(decoded.clearanceFrontOffsetM, 0.050, accuracy: 0.001)
    }

    func test_hardwarePatch_defaultOffsets_areZero() {
        let patch = HardwarePatchV1(
            customName: "Test",
            widthM: 0.4,
            heightM: 0.7,
            depthM: 0.35
        )
        XCTAssertEqual(patch.clearanceTopOffsetM, 0)
        XCTAssertEqual(patch.clearanceBottomOffsetM, 0)
        XCTAssertEqual(patch.clearanceFrontOffsetM, 0)
        XCTAssertEqual(patch.clearanceBackOffsetM, 0)
        XCTAssertEqual(patch.clearanceLeftOffsetM, 0)
        XCTAssertEqual(patch.clearanceRightOffsetM, 0)
    }

    // MARK: - VisitHandoffPackV1

    func test_visitHandoffPack_roundTrips_throughJSON() throws {
        let visitId = UUID()
        let patch = HardwarePatchV1(
            customName: "Site-patched boiler",
            widthM: 0.400, heightM: 0.700, depthM: 0.350
        )
        let pack = VisitHandoffPackV1(
            visitId: visitId,
            propertyAddress: "1 Test Lane, London",
            hardwarePatches: patch
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(pack)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VisitHandoffPackV1.self, from: data)

        XCTAssertEqual(decoded.visitId, visitId)
        XCTAssertEqual(decoded.propertyAddress, "1 Test Lane, London")
        XCTAssertEqual(decoded.schemaVersion, "1.0")
        XCTAssertNotNil(decoded.hardwarePatches)
        XCTAssertEqual(decoded.hardwarePatches?.customName, "Site-patched boiler")
    }

    func test_visitHandoffPack_nilPatches_roundTrips() throws {
        let pack = VisitHandoffPackV1(visitId: UUID())
        let encoder = JSONEncoder()
        let data = try encoder.encode(pack)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VisitHandoffPackV1.self, from: data)
        XCTAssertNil(decoded.hardwarePatches)
    }
}
