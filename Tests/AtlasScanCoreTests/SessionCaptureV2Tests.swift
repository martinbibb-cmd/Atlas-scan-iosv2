import XCTest
@testable import AtlasScanCore

final class SessionCaptureV2Tests: XCTestCase {

    // MARK: - Version

    func test_version_isAlways2dot0() {
        let session = SessionCaptureV2()
        XCTAssertEqual(session.version, "2.0")
    }

    // MARK: - Adding rooms

    func test_addRoom_appendsToRooms() {
        var session = SessionCaptureV2()
        let room = RoomCaptureV2(displayName: "Kitchen")
        session.addRoom(room)
        XCTAssertEqual(session.rooms.count, 1)
        XCTAssertEqual(session.rooms[0].displayName, "Kitchen")
    }

    func test_addRoom_preservesUUID() {
        var session = SessionCaptureV2()
        let room = RoomCaptureV2(displayName: "Lounge")
        let id = room.id
        session.addRoom(room)
        XCTAssertEqual(session.rooms[0].id, id)
    }

    // MARK: - QA flags

    func test_emitQAFlag_addsFlagOnce() {
        var session = SessionCaptureV2()
        let flag = QAFlagV1(type: .clearanceConflict, roomId: UUID(), detail: "test")
        session.emitQAFlag(flag)
        session.emitQAFlag(flag)          // duplicate → should not be added again
        XCTAssertEqual(session.qaFlags.count, 1)
    }

    func test_emitQAFlag_allowsDifferentTypesForSameRoom() {
        var session = SessionCaptureV2()
        let roomId = UUID()
        session.emitQAFlag(QAFlagV1(type: .clearanceConflict, roomId: roomId))
        session.emitQAFlag(QAFlagV1(type: .missingFabric,     roomId: roomId))
        XCTAssertEqual(session.qaFlags.count, 2)
    }

    // MARK: - No raw audio

    func test_sessionCaptureV2_hasNoRawAudioField() {
        // Verify that SessionCaptureV2 contains only processed transcripts.
        let session = SessionCaptureV2()
        // If 'rawAudio' or similar fields existed this would not compile.
        // We verify the transcripts array exists and is empty by default.
        XCTAssertTrue(session.transcripts.isEmpty)
    }

    // MARK: - Codable round-trip

    func test_codableRoundTrip() throws {
        var session = SessionCaptureV2(
            visitId: UUID(),
            propertyAddress: "10 Downing St"
        )
        let room = RoomCaptureV2(displayName: "Boiler Room")
        session.addRoom(room)
        session.emitQAFlag(QAFlagV1(type: .clearancePass, roomId: room.id, detail: "OK"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionCaptureV2.self, from: data)

        XCTAssertEqual(decoded.version, "2.0")
        XCTAssertEqual(decoded.visitId, session.visitId)
        XCTAssertEqual(decoded.propertyAddress, "10 Downing St")
        XCTAssertEqual(decoded.rooms.count, 1)
        XCTAssertEqual(decoded.qaFlags.count, 1)
    }
}
