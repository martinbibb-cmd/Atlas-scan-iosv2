/// ScanSessionCoordinator — ObservableObject that owns the live
/// `SessionCaptureV2` and orchestrates the full scan session lifecycle.
///
/// Responsibilities:
/// - Owns the single `SessionCaptureV2` truth for the current visit
/// - Drives `VisitReadinessV1` updates on every mutation
/// - Persists atomically via `AtomicSessionStore`
/// - Assembles & opens the Atlas Mind deep-link URL

import SwiftUI
import Combine
import AtlasScanCore

@MainActor
final class ScanSessionCoordinator: ObservableObject {

    // MARK: Published state

    @Published var session: SessionCaptureV2
    @Published var readiness: VisitReadinessV1
    @Published var activePin: SpatialPinV1?
    @Published var showHandoff: Bool = false
    @Published var handoffError: Error?
    @Published var isSaving: Bool = false

    // MARK: Private

    private var store: AtomicSessionStore?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init() {
        let s = SessionCaptureV2()
        self.session = s
        self.readiness = VisitReadinessV1.derive(from: s)
        setupStore()
        observeSession()
    }

    // MARK: Setup

    private func setupStore() {
        store = try? AtomicSessionStore()
    }

    private func observeSession() {
        $session
            .map { VisitReadinessV1.derive(from: $0) }
            .assign(to: &$readiness)
    }

    // MARK: Session management

    /// Start a new scan session (replaces any in-progress session).
    func startNewSession(propertyAddress: String? = nil) {
        session = SessionCaptureV2(propertyAddress: propertyAddress)
        activePin = nil
    }

    // MARK: Rooms

    func addRoom(_ room: RoomCaptureV2) {
        session.addRoom(room)
        save()
    }

    func updateRoom(_ room: RoomCaptureV2) {
        guard let index = session.rooms.firstIndex(where: { $0.id == room.id }) else { return }
        session.rooms[index] = room
        save()
    }

    // MARK: Spatial pins

    func setActivePin(_ pin: SpatialPinV1?) {
        activePin = pin
    }

    func addPin(_ pin: SpatialPinV1) {
        guard let index = session.rooms.firstIndex(where: { $0.id == pin.roomId }) else { return }
        session.rooms[index].pinnedObjects.append(pin)
        save()
    }

    // MARK: Evidence (photos & transcripts)

    /// Attach a photo to the current room, linking it to the active pin if present.
    func attachPhoto(
        roomId: UUID,
        relativeFilePath: String,
        cameraPosition: (x: Double, y: Double, z: Double)? = nil
    ) {
        var photo = PhotoEvidenceV1(
            visitId: session.visitId,
            roomId: roomId,
            linkedObjectId: activePin?.id,
            relativeFilePath: relativeFilePath,
            cameraPositionX: cameraPosition?.x,
            cameraPositionY: cameraPosition?.y,
            cameraPositionZ: cameraPosition?.z
        )
        _ = photo   // assigned to suppress warning
        session.photos.append(photo)
        save()
    }

    /// Record a processed transcript, linking it to the active pin if present.
    func recordTranscript(
        roomId: UUID,
        text: String,
        hint: ExtractionHint = .general
    ) {
        let transcript = ProcessedTranscriptV1(
            visitId: session.visitId,
            roomId: roomId,
            linkedObjectId: activePin?.id,
            transcript: text,
            extractionHint: hint
        )
        session.transcripts.append(transcript)
        // Also add as a VoiceNote for UI display purposes.
        let note = VoiceNoteV1(
            visitId: session.visitId,
            roomId: roomId,
            linkedObjectId: activePin?.id,
            processedTranscript: text,
            extractionHint: hint
        )
        session.voiceNotes.append(note)
        save()
    }

    // MARK: QA flags

    func emitQAFlag(_ flag: QAFlagV1) {
        session.emitQAFlag(flag)
        save()
    }

    // MARK: Atomic save

    func save() {
        guard let store = store else { return }
        isSaving = true
        Task.detached(priority: .background) { [session] in
            try? store.save(session)
            await MainActor.run { [weak self] in
                self?.isSaving = false
            }
        }
    }

    // MARK: Handoff to Atlas Mind

    func handOffToMind() {
        do {
            let url = try ScanToMindPayloadEncoder.encode(session: session)
            // UIApplication.shared.open(url) — called in HandoffView to avoid AppKit import here.
            showHandoff = false
            // Post notification for the view layer to open the URL.
            NotificationCenter.default.post(
                name: .atlasHandoffURL,
                object: url
            )
        } catch {
            handoffError = error
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let atlasHandoffURL = Notification.Name("AtlasScanHandoffURL")
}
