/// ScanToMindPayloadEncoder — Encodes a `SessionCaptureV2` (wrapped in a
/// `ScanToMindHandoffV1`) as a percent-encoded JSON query parameter and builds
/// the deep-link URL that opens Atlas Mind at the `/receive-scan` route.
///
/// Usage:
///   let url = try ScanToMindPayloadEncoder.encode(session: session)
///   await UIApplication.shared.open(url)

import Foundation

// MARK: - ScanToMindPayloadEncoder

public enum ScanToMindPayloadEncoder {

    // MARK: Public API

    /// Encodes `session` into a `atlasmind:///receive-scan?payload=<…>` URL.
    ///
    /// - Parameters:
    ///   - session:   The `SessionCaptureV2` to hand off.
    ///   - handoffId: Optional stable identifier for idempotent retries.
    /// - Throws: `HandoffError` if encoding or URL construction fails.
    /// - Returns: A `URL` ready to be passed to `UIApplication.open(_:)`.
    public static func encode(
        session: SessionCaptureV2,
        handoffId: UUID = UUID()
    ) throws -> URL {
        let readiness = VisitReadinessV1.derive(from: session)
        guard readiness.isReady else {
            throw HandoffError.readinessNotSatisfied(readiness.unmetConditions)
        }
        let payload = ScanToMindHandoffV1(
            session: session,
            readiness: readiness,
            handoffId: handoffId
        )
        return try payload.buildDeepLinkURL()
    }

    /// Like `encode(session:handoffId:)` but bypasses the readiness gate.
    /// Use only for debugging / preview purposes.
    public static func encodeForPreview(session: SessionCaptureV2) throws -> URL {
        let readiness = VisitReadinessV1.derive(from: session)
        let payload = ScanToMindHandoffV1(
            session: session,
            readiness: readiness
        )
        return try payload.buildDeepLinkURL()
    }

    // MARK: Helpers

    /// Returns the raw JSON string for a given session (useful for debugging).
    public static func jsonString(for session: SessionCaptureV2) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let readiness = VisitReadinessV1.derive(from: session)
        let payload = ScanToMindHandoffV1(session: session, readiness: readiness)
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw HandoffError.jsonStringConversionFailed
        }
        return string
    }

    /// Returns the payload size in bytes for UI display.
    public static func payloadSize(for session: SessionCaptureV2) -> Int? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let readiness = VisitReadinessV1.derive(from: session)
        let payload = ScanToMindHandoffV1(session: session, readiness: readiness)
        return try? encoder.encode(payload).count
    }
}
