/// MindRecallClient — Fetches an existing scan session from the Atlas Mind
/// D1 API and hydrates linked USDZ assets for Van Mode use.
///
/// Deep-link trigger:  atlasscan://recall?visitId=<UUID>
///
/// Network flow:
///   1. GET /api/visits/{visitId}/working-payload  → SessionCaptureV2 JSON
///   2. For each room with a usdzAssetPath: download to
///      Documents/captures/{visitId}/usdz/{roomId}.usdz
///   3. Atomically save the hydrated SessionCaptureV2 via AtomicSessionStore.
///
/// Platform: iOS 17+

import Foundation
import AtlasScanCore

// MARK: - Recall errors

public enum RecallError: Error, LocalizedError, Sendable {
    case invalidVisitId
    case networkError(Error)
    case decodingError(Error)
    case missingPayload
    case assetDownloadFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .invalidVisitId:
            return "The visitId provided in the recall URL is not a valid UUID."
        case .networkError(let e):
            return "Network error during recall: \(e.localizedDescription)"
        case .decodingError(let e):
            return "Failed to decode the recalled session: \(e.localizedDescription)"
        case .missingPayload:
            return "The Mind API returned a response with no working payload."
        case .assetDownloadFailed(let url, let e):
            return "Failed to download asset at \(url): \(e.localizedDescription)"
        }
    }
}

// MARK: - API response envelope

private struct WorkingPayloadResponse: Decodable {
    let working_payload_json: String?
}

// MARK: - Mind recall client

@MainActor
final class MindRecallClient: ObservableObject {

    // MARK: Published state

    @Published var isRecalling: Bool = false
    @Published var recallError: RecallError?

    // MARK: Private

    private let store: AtomicSessionStore?
    private let urlSession: URLSession
    private let baseURL: String

    // MARK: Init

    init(
        store: AtomicSessionStore? = try? AtomicSessionStore(),
        urlSession: URLSession = .shared,
        baseURL: String = "https://atlas-mind.martinbibb.workers.dev"
    ) {
        self.store = store
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    // MARK: Recall

    /// Fetches and persists an existing visit from the Mind API.
    ///
    /// - Parameter visitId: The UUID of the visit to recall.
    /// - Returns: The fully-hydrated `SessionCaptureV2` ready for display.
    @discardableResult
    func recall(visitId: UUID) async throws -> SessionCaptureV2 {
        isRecalling = true
        recallError = nil
        defer { isRecalling = false }

        // 1. Fetch working payload JSON from Mind D1 API.
        let session: SessionCaptureV2
        do {
            session = try await fetchSession(visitId: visitId)
        } catch let recallErr as RecallError {
            recallError = recallErr
            throw recallErr
        }

        // 2. Hydrate USDZ assets for Van Mode.
        let hydrated = await downloadUSDZAssets(for: session)

        // 3. Atomically persist.
        do {
            try store?.save(hydrated)
        } catch {
            // Non-fatal — the in-memory session is still usable.
        }

        return hydrated
    }

    // MARK: Private helpers

    private func fetchSession(visitId: UUID) async throws -> SessionCaptureV2 {
        guard let url = URL(string: "\(baseURL)/api/visits/\(visitId.uuidString)/working-payload") else {
            throw RecallError.invalidVisitId
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            throw RecallError.networkError(error)
        }

        // Accept 200 only.
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RecallError.missingPayload
        }

        // Decode the envelope first to extract working_payload_json.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope: WorkingPayloadResponse
        do {
            envelope = try decoder.decode(WorkingPayloadResponse.self, from: data)
        } catch {
            throw RecallError.decodingError(error)
        }

        guard let payloadJSON = envelope.working_payload_json,
              let payloadData = payloadJSON.data(using: .utf8) else {
            throw RecallError.missingPayload
        }

        do {
            return try decoder.decode(SessionCaptureV2.self, from: payloadData)
        } catch {
            throw RecallError.decodingError(error)
        }
    }

    /// Hydrate USDZ assets for Van Mode (offline mesh-review mode on-site).
    private func downloadUSDZAssets(for session: SessionCaptureV2) async -> SessionCaptureV2 {

        var updated = session
        let usdzDir = store.usdzDirectory(for: session.visitId)

        for (index, room) in session.rooms.enumerated() {
            guard let relativePath = room.usdzAssetPath,
                  let assetURL = URL(string: "\(baseURL)/\(relativePath)") else { continue }

            do {
                try FileManager.default.createDirectory(
                    at: usdzDir,
                    withIntermediateDirectories: true
                )
                let destURL = usdzDir.appendingPathComponent("\(room.id.uuidString).usdz")
                let (tmpURL, _) = try await urlSession.download(from: assetURL)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tmpURL, to: destURL)
                // Update the relative path to the local copy.
                updated.rooms[index].usdzAssetPath =
                    "usdz/\(room.id.uuidString).usdz"
            } catch {
                // Asset download failure is non-fatal; the room is still recalled.
            }
        }

        return updated
    }
}
