/// ScanToMindHandoffV1 — Handover payload transmitted to the Atlas Mind app.
///
/// The payload is percent-encoded as a JSON query parameter on the
/// `atlasmind:///receive-scan` URL scheme route.
///
/// Data flow:
///   ScanSessionCoordinator
///     → ScanToMindPayloadEncoder
///       → atlasmind:///receive-scan?payload=<percent-encoded JSON>

import Foundation

// MARK: - Hardware patch (custom appliance overrides dispatched from Mind)

/// Allows the Mind app to dispatch a custom or site-patched appliance
/// specification to the Scan app at the start of a visit.
public struct HardwarePatchV1: Codable, Sendable {

    /// The modelId this patch overrides, or `nil` for a brand-new custom entry.
    public var targetModelId: UUID?

    /// Human-readable name shown in the ghost-box picker.
    public var customName: String

    // Physical dimensions (metres) — override the registry values.
    public var widthM: Double
    public var heightM: Double
    public var depthM: Double

    // Clearance offsets (metres) relative to the base model clearances.
    public var clearanceTopOffsetM:    Double
    public var clearanceBottomOffsetM: Double
    public var clearanceFrontOffsetM:  Double
    public var clearanceBackOffsetM:   Double
    public var clearanceLeftOffsetM:   Double
    public var clearanceRightOffsetM:  Double

    public init(
        targetModelId: UUID? = nil,
        customName: String,
        widthM: Double,
        heightM: Double,
        depthM: Double,
        clearanceTopOffsetM: Double    = 0,
        clearanceBottomOffsetM: Double = 0,
        clearanceFrontOffsetM: Double  = 0,
        clearanceBackOffsetM: Double   = 0,
        clearanceLeftOffsetM: Double   = 0,
        clearanceRightOffsetM: Double  = 0
    ) {
        self.targetModelId = targetModelId
        self.customName = customName
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.clearanceTopOffsetM    = clearanceTopOffsetM
        self.clearanceBottomOffsetM = clearanceBottomOffsetM
        self.clearanceFrontOffsetM  = clearanceFrontOffsetM
        self.clearanceBackOffsetM   = clearanceBackOffsetM
        self.clearanceLeftOffsetM   = clearanceLeftOffsetM
        self.clearanceRightOffsetM  = clearanceRightOffsetM
    }
}

// MARK: - Visit handoff pack (Mind → Scan direction)

/// Payload dispatched by the Mind app to the Scan app at visit start.
/// Carried as the `pack` query parameter on `atlasscan:///start-visit`.
public struct VisitHandoffPackV1: Codable, Sendable {

    /// Schema version.
    public let schemaVersion: String   // Always "1.0"

    /// The visit to begin.
    public let visitId: UUID

    /// Optional property address pre-populated from the Mind database.
    public var propertyAddress: String?

    /// Optional custom appliance specification patched for this site.
    public var hardwarePatches: HardwarePatchV1?

    public init(
        visitId: UUID,
        propertyAddress: String? = nil,
        hardwarePatches: HardwarePatchV1? = nil
    ) {
        self.schemaVersion = "1.0"
        self.visitId = visitId
        self.propertyAddress = propertyAddress
        self.hardwarePatches = hardwarePatches
    }
}

// MARK: - Handoff payload

public struct ScanToMindHandoffV1: Codable, Sendable {

    /// Schema version for the handoff contract.
    public let schemaVersion: String   // Always "1.0"

    /// The full session capture (source of truth).
    public let session: SessionCaptureV2

    /// Readiness snapshot at the moment of handoff.
    public let readiness: VisitReadinessV1

    /// ISO-8601 timestamp of the handoff event.
    public let handedOffAt: String

    /// Unique identifier for this handoff attempt (for idempotency).
    public let handoffId: UUID

    /// The visit this handoff belongs to (mirrors `session.visitId` for
    /// bi-directional recall without deserialising the full session).
    public let visitId: UUID

    // MARK: Initialiser

    public init(
        session: SessionCaptureV2,
        readiness: VisitReadinessV1,
        handedOffAt: Date = Date(),
        handoffId: UUID = UUID()
    ) {
        self.schemaVersion = "1.0"
        self.session = session
        self.readiness = readiness
        self.handedOffAt = ISO8601DateFormatter().string(from: handedOffAt)
        self.handoffId = handoffId
        self.visitId = session.visitId
    }
}

// MARK: - Deep-link URL builder

public extension ScanToMindHandoffV1 {

    /// The Atlas Mind deep-link scheme.
    static let receiveScanURLString = "atlasmind:///receive-scan"

    /// Builds the `atlasmind:///receive-scan?payload=<…>` URL.
    ///
    /// - Throws: `EncodingError` if the payload cannot be JSON-encoded.
    /// - Returns: A `URL` ready to be opened via `UIApplication.open(_:)`.
    func buildDeepLinkURL() throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(self)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw HandoffError.jsonStringConversionFailed
        }
        guard let encoded = jsonString.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            throw HandoffError.percentEncodingFailed
        }
        let urlString = "\(Self.receiveScanURLString)?payload=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw HandoffError.invalidURL(urlString)
        }
        return url
    }
}

// MARK: - Handoff errors

public enum HandoffError: Error, LocalizedError, Sendable {
    case jsonStringConversionFailed
    case percentEncodingFailed
    case invalidURL(String)
    case readinessNotSatisfied([String])

    public var errorDescription: String? {
        switch self {
        case .jsonStringConversionFailed:
            return "Failed to convert session JSON to a UTF-8 string."
        case .percentEncodingFailed:
            return "Failed to percent-encode the session payload."
        case .invalidURL(let raw):
            return "Could not construct a valid URL from: \(raw)"
        case .readinessNotSatisfied(let missing):
            return "Visit readiness not satisfied. Missing: \(missing.joined(separator: ", "))"
        }
    }
}
