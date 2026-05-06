/// SessionCaptureV2 — Root data envelope for an Atlas Scan V2 session.
///
/// Contract rules:
/// - `version` MUST be "2.0"
/// - Raw audio is EXCLUDED; only processed `transcripts` are included.
/// - Coordinate space: right-handed Y-up, metric metres.

import Foundation

// MARK: - SessionCaptureV2

public struct SessionCaptureV2: Codable, Identifiable, Sendable {

    // ── Identity ────────────────────────────────────────────────────────────
    public let id: UUID
    public let version: String          // Always "2.0"
    public let visitId: UUID
    public let capturedAt: Date
    public var propertyAddress: String?

    // ── Spatial content ─────────────────────────────────────────────────────
    public var rooms: [RoomCaptureV2]

    // ── Evidence (NO raw audio — processed transcripts only) ────────────────
    public var transcripts: [ProcessedTranscriptV1]
    public var photos: [PhotoEvidenceV1]
    public var voiceNotes: [VoiceNoteV1]

    // ── Quality assurance ───────────────────────────────────────────────────
    public var qaFlags: [QAFlagV1]

    // MARK: Initialiser

    public init(
        visitId: UUID = UUID(),
        capturedAt: Date = Date(),
        propertyAddress: String? = nil
    ) {
        self.id = UUID()
        self.version = "2.0"
        self.visitId = visitId
        self.capturedAt = capturedAt
        self.propertyAddress = propertyAddress
        self.rooms = []
        self.transcripts = []
        self.photos = []
        self.voiceNotes = []
        self.qaFlags = []
    }
}

// MARK: - Convenience helpers

public extension SessionCaptureV2 {

    /// Append a room and return its id.
    mutating func addRoom(_ room: RoomCaptureV2) {
        rooms.append(room)
    }

    /// Attach a QA flag (deduplicates by type + room).
    mutating func emitQAFlag(_ flag: QAFlagV1) {
        guard !qaFlags.contains(where: {
            $0.type == flag.type && $0.roomId == flag.roomId
        }) else { return }
        qaFlags.append(flag)
    }
}
