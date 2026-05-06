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
