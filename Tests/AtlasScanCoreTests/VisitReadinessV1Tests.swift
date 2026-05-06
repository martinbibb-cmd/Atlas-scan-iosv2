import XCTest
@testable import AtlasScanCore

final class VisitReadinessV1Tests: XCTestCase {

    // MARK: - Default state

    func test_default_isNotReady() {
        let readiness = VisitReadinessV1()
        XCTAssertFalse(readiness.isReady)
    }

    // MARK: - All flags required

    func test_allFlagsTrue_isReady() {
        let readiness = VisitReadinessV1(
            hasRooms: true,
            hasPhotos: true,
            hasBoilerDetails: true,
            hasFlueDetails: true,
            hasClearanceCheck: true,
            hasTranscripts: true,
            hasPropertyAddress: true
        )
        XCTAssertTrue(readiness.isReady)
    }

    func test_missingOneFlag_isNotReady() {
        // Test each of the 7 flags individually.
        let flags: [(String, VisitReadinessV1)] = [
            ("hasRooms", VisitReadinessV1(hasRooms: false, hasPhotos: true, hasBoilerDetails: true, hasFlueDetails: true, hasClearanceCheck: true, hasTranscripts: true, hasPropertyAddress: true)),
            ("hasPhotos", VisitReadinessV1(hasRooms: true, hasPhotos: false, hasBoilerDetails: true, hasFlueDetails: true, hasClearanceCheck: true, hasTranscripts: true, hasPropertyAddress: true)),
            ("hasBoilerDetails", VisitReadinessV1(hasRooms: true, hasPhotos: true, hasBoilerDetails: false, hasFlueDetails: true, hasClearanceCheck: true, hasTranscripts: true, hasPropertyAddress: true)),
            ("hasFlueDetails", VisitReadinessV1(hasRooms: true, hasPhotos: true, hasBoilerDetails: true, hasFlueDetails: false, hasClearanceCheck: true, hasTranscripts: true, hasPropertyAddress: true)),
            ("hasClearanceCheck", VisitReadinessV1(hasRooms: true, hasPhotos: true, hasBoilerDetails: true, hasFlueDetails: true, hasClearanceCheck: false, hasTranscripts: true, hasPropertyAddress: true)),
            ("hasTranscripts", VisitReadinessV1(hasRooms: true, hasPhotos: true, hasBoilerDetails: true, hasFlueDetails: true, hasClearanceCheck: true, hasTranscripts: false, hasPropertyAddress: true)),
            ("hasPropertyAddress", VisitReadinessV1(hasRooms: true, hasPhotos: true, hasBoilerDetails: true, hasFlueDetails: true, hasClearanceCheck: true, hasTranscripts: true, hasPropertyAddress: false))
        ]
        for (name, r) in flags {
            XCTAssertFalse(r.isReady, "\(name) missing should block readiness")
        }
    }

    // MARK: - Unmet conditions

    func test_unmetConditions_listsAll7WhenAllFalse() {
        let readiness = VisitReadinessV1()
        XCTAssertEqual(readiness.unmetConditions.count, 7)
    }

    func test_unmetConditions_emptyWhenReady() {
        let readiness = VisitReadinessV1(
            hasRooms: true, hasPhotos: true, hasBoilerDetails: true,
            hasFlueDetails: true, hasClearanceCheck: true,
            hasTranscripts: true, hasPropertyAddress: true
        )
        XCTAssertTrue(readiness.unmetConditions.isEmpty)
    }

    // MARK: - Derive from session

    func test_derive_detects7Flags() {
        var session = SessionCaptureV2(
            visitId: UUID(),
            propertyAddress: "1 Test Lane"
        )

        // Add room
        var room = RoomCaptureV2(displayName: "Utility Room")
        room.pinnedObjects.append(SpatialPinV1(
            roomId: room.id,
            positionX: 1, positionY: 1, positionZ: 1,
            objectType: .boiler
        ))
        room.pinnedObjects.append(SpatialPinV1(
            roomId: room.id,
            positionX: 2, positionY: 2, positionZ: 2,
            objectType: .flueTerminal
        ))
        session.addRoom(room)

        // Add photo
        session.photos.append(PhotoEvidenceV1(
            visitId: session.visitId, roomId: room.id,
            relativeFilePath: "photos/img001.jpg"
        ))

        // Add transcript
        session.transcripts.append(ProcessedTranscriptV1(
            visitId: session.visitId, roomId: room.id,
            transcript: "Boiler is 10 years old."
        ))

        // Add clearance pass flag
        session.emitQAFlag(QAFlagV1(type: .clearancePass, roomId: room.id))

        let r = VisitReadinessV1.derive(from: session)

        XCTAssertTrue(r.hasRooms)
        XCTAssertTrue(r.hasPhotos)
        XCTAssertTrue(r.hasBoilerDetails)
        XCTAssertTrue(r.hasFlueDetails)
        XCTAssertTrue(r.hasClearanceCheck)
        XCTAssertTrue(r.hasTranscripts)
        XCTAssertTrue(r.hasPropertyAddress)
        XCTAssertTrue(r.isReady)
    }
}
