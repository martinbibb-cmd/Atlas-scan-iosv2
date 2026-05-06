import XCTest
@testable import AtlasScanCore

final class ScanToMindPayloadEncoderTests: XCTestCase {

    // MARK: - Helpers

    private func makeReadySession() -> SessionCaptureV2 {
        var session = SessionCaptureV2(
            visitId: UUID(),
            propertyAddress: "42 Thermal Close, London, SW1A 1AA"
        )

        var room = RoomCaptureV2(displayName: "Boiler Room")
        room.pinnedObjects.append(SpatialPinV1(
            roomId: room.id,
            positionX: 0.5, positionY: 1.0, positionZ: 0.5,
            objectType: .boiler,
            label: "Worcester Greenstar 8000"
        ))
        room.pinnedObjects.append(SpatialPinV1(
            roomId: room.id,
            positionX: 1.0, positionY: 2.3, positionZ: 0.3,
            objectType: .flueTerminal
        ))
        session.addRoom(room)

        session.photos.append(PhotoEvidenceV1(
            visitId: session.visitId, roomId: room.id,
            relativeFilePath: "photos/img001.jpg"
        ))

        session.transcripts.append(ProcessedTranscriptV1(
            visitId: session.visitId, roomId: room.id,
            transcript: "Boiler installed 2018, serviced annually.",
            extractionHint: .boilerServiceHistory
        ))

        session.emitQAFlag(QAFlagV1(type: .clearancePass, roomId: room.id))

        return session
    }

    // MARK: - URL scheme

    func test_encodedURL_hasCorrectSchemeAndPath() throws {
        let session = makeReadySession()
        let url = try ScanToMindPayloadEncoder.encode(session: session)
        XCTAssertEqual(url.scheme, "atlasmind")
        XCTAssertEqual(url.path, "/receive-scan")
    }

    func test_encodedURL_hasPayloadQueryItem() throws {
        let session = makeReadySession()
        let url = try ScanToMindPayloadEncoder.encode(session: session)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let payloadItem = comps?.queryItems?.first(where: { $0.name == "payload" })
        XCTAssertNotNil(payloadItem)
        XCTAssertFalse(payloadItem?.value?.isEmpty ?? true)
    }

    // MARK: - Payload round-trip

    func test_payloadDecodes_toValidHandoff() throws {
        let session = makeReadySession()
        let url = try ScanToMindPayloadEncoder.encode(session: session)

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let encoded = comps.queryItems!.first(where: { $0.name == "payload" })!.value!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(encoded.utf8)
        let handoff = try decoder.decode(ScanToMindHandoffV1.self, from: data)

        XCTAssertEqual(handoff.schemaVersion, "1.0")
        XCTAssertEqual(handoff.session.version, "2.0")
        XCTAssertEqual(handoff.session.visitId, session.visitId)
        XCTAssertTrue(handoff.readiness.isReady)
    }

    // MARK: - Readiness gate

    func test_encode_throwsWhenNotReady() {
        let session = SessionCaptureV2()   // empty — not ready
        XCTAssertThrowsError(
            try ScanToMindPayloadEncoder.encode(session: session)
        ) { error in
            if case HandoffError.readinessNotSatisfied = error { /* expected */ }
            else { XCTFail("Expected readinessNotSatisfied error, got \(error)") }
        }
    }

    func test_encodeForPreview_succeedsEvenWhenNotReady() throws {
        let session = SessionCaptureV2()
        let url = try ScanToMindPayloadEncoder.encodeForPreview(session: session)
        XCTAssertEqual(url.scheme, "atlasmind")
    }

    // MARK: - JSON string helper

    func test_jsonString_containsVersion() throws {
        let session = makeReadySession()
        let json = try ScanToMindPayloadEncoder.jsonString(for: session)
        XCTAssertTrue(json.contains("\"2.0\""))
        XCTAssertTrue(json.contains("\"1.0\""))
    }

    // MARK: - Payload size

    func test_payloadSize_isPositive() {
        let session = makeReadySession()
        let size = ScanToMindPayloadEncoder.payloadSize(for: session)
        XCTAssertNotNil(size)
        XCTAssertGreaterThan(size!, 0)
    }
}
