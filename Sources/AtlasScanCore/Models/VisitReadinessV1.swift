/// VisitReadinessV1 — 7-flag logic gate.
///
/// All seven flags must be `true` before the "Handoff to Mind" button is enabled.

import Foundation

// MARK: - VisitReadinessV1

public struct VisitReadinessV1: Codable, Sendable {

    // ── The seven mandatory flags ────────────────────────────────────────────
    /// At least one room has been captured.
    public var hasRooms: Bool

    /// At least one photo has been attached to the session.
    public var hasPhotos: Bool

    /// Boiler make/model details have been recorded.
    public var hasBoilerDetails: Bool

    /// Flue terminal location has been captured.
    public var hasFlueDetails: Bool

    /// A clearance-check result (pass or conflict) has been generated.
    public var hasClearanceCheck: Bool

    /// At least one processed voice transcript exists.
    public var hasTranscripts: Bool

    /// A property address has been entered.
    public var hasPropertyAddress: Bool

    // MARK: Computed readiness

    /// `true` only when every flag is satisfied — unlocks "Handoff to Mind".
    public var isReady: Bool {
        hasRooms
            && hasPhotos
            && hasBoilerDetails
            && hasFlueDetails
            && hasClearanceCheck
            && hasTranscripts
            && hasPropertyAddress
    }

    // MARK: Initialiser

    public init(
        hasRooms: Bool = false,
        hasPhotos: Bool = false,
        hasBoilerDetails: Bool = false,
        hasFlueDetails: Bool = false,
        hasClearanceCheck: Bool = false,
        hasTranscripts: Bool = false,
        hasPropertyAddress: Bool = false
    ) {
        self.hasRooms = hasRooms
        self.hasPhotos = hasPhotos
        self.hasBoilerDetails = hasBoilerDetails
        self.hasFlueDetails = hasFlueDetails
        self.hasClearanceCheck = hasClearanceCheck
        self.hasTranscripts = hasTranscripts
        self.hasPropertyAddress = hasPropertyAddress
    }

    // MARK: Derive from session

    /// Derive readiness state from a live `SessionCaptureV2` object.
    public static func derive(from session: SessionCaptureV2) -> VisitReadinessV1 {
        let hasBoiler = session.rooms.contains { room in
            room.pinnedObjects.contains { $0.objectType == .boiler || $0.objectType == .heatPump }
        }
        let hasFlue = session.rooms.contains { room in
            room.pinnedObjects.contains { $0.objectType == .flueTerminal }
        }
        let hasClearance = session.qaFlags.contains {
            $0.type == .clearancePass || $0.type == .clearanceConflict
        }

        return VisitReadinessV1(
            hasRooms: !session.rooms.isEmpty,
            hasPhotos: !session.photos.isEmpty,
            hasBoilerDetails: hasBoiler,
            hasFlueDetails: hasFlue,
            hasClearanceCheck: hasClearance,
            hasTranscripts: !session.transcripts.isEmpty,
            hasPropertyAddress: !(session.propertyAddress?.isEmpty ?? true)
        )
    }

    // MARK: Diagnostics

    /// Human-readable list of unmet conditions (useful for tooltip/accessibility).
    public var unmetConditions: [String] {
        var missing: [String] = []
        if !hasRooms            { missing.append("At least one room must be captured") }
        if !hasPhotos           { missing.append("At least one photo must be attached") }
        if !hasBoilerDetails    { missing.append("Boiler or heat-pump must be pinned") }
        if !hasFlueDetails      { missing.append("Flue terminal must be captured") }
        if !hasClearanceCheck   { missing.append("Clearance check must be completed") }
        if !hasTranscripts      { missing.append("At least one voice note must be recorded") }
        if !hasPropertyAddress  { missing.append("Property address must be entered") }
        return missing
    }
}
