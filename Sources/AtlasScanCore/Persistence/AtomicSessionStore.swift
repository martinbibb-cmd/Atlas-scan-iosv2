/// AtomicSessionStore — Persists a `SessionCaptureV2` to the file system.
///
/// Storage layout:
///   Documents/
///     captures/
///       {visitId}/
///         session.json        ← the main SessionCaptureV2 payload
///         photos/             ← JPEG/HEIF photo files
///         usdz/               ← per-room .usdz mesh assets
///
/// "Atomic" means: the session JSON is first written to a `.tmp` file and
/// then atomically renamed into place, preventing partial writes.

import Foundation

// MARK: - Atomic session store

public final class AtomicSessionStore: @unchecked Sendable {

    // MARK: Types

    public enum StoreError: Error, LocalizedError {
        case documentsDirectoryUnavailable
        case encodingFailed(Error)
        case decodingFailed(Error)
        case fileWriteFailed(Error)
        case sessionNotFound(UUID)

        public var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                return "The Documents directory could not be resolved."
            case .encodingFailed(let e):
                return "JSON encoding failed: \(e.localizedDescription)"
            case .decodingFailed(let e):
                return "JSON decoding failed: \(e.localizedDescription)"
            case .fileWriteFailed(let e):
                return "File write failed: \(e.localizedDescription)"
            case .sessionNotFound(let id):
                return "No saved session found for visit \(id)."
            }
        }
    }

    // MARK: Properties

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Root `captures/` directory.  Defaults to `Documents/captures/`.
    public let capturesRoot: URL

    // MARK: Initialiser

    public init(
        fileManager: FileManager = .default,
        capturesRoot: URL? = nil
    ) throws {
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let root = capturesRoot {
            self.capturesRoot = root
        } else {
            guard let docs = fileManager.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first else {
                throw StoreError.documentsDirectoryUnavailable
            }
            self.capturesRoot = docs.appendingPathComponent("captures", isDirectory: true)
        }
    }

    // MARK: Directory helpers

    public func captureDirectory(for visitId: UUID) -> URL {
        capturesRoot.appendingPathComponent(visitId.uuidString, isDirectory: true)
    }

    public func photosDirectory(for visitId: UUID) -> URL {
        captureDirectory(for: visitId).appendingPathComponent("photos", isDirectory: true)
    }

    public func usdzDirectory(for visitId: UUID) -> URL {
        captureDirectory(for: visitId).appendingPathComponent("usdz", isDirectory: true)
    }

    private func sessionURL(for visitId: UUID) -> URL {
        captureDirectory(for: visitId).appendingPathComponent("session.json")
    }

    private func sessionTmpURL(for visitId: UUID) -> URL {
        captureDirectory(for: visitId).appendingPathComponent("session.json.tmp")
    }

    // MARK: Save (atomic write)

    /// Atomically saves `session` to `Documents/captures/{visitId}/session.json`.
    public func save(_ session: SessionCaptureV2) throws {
        let dir = captureDirectory(for: session.visitId)

        // Ensure directory tree exists.
        try fileManager.createDirectory(at: dir,
                                        withIntermediateDirectories: true)

        // Encode to JSON.
        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw StoreError.encodingFailed(error)
        }

        // Write to .tmp, then atomically rename.
        let tmpURL = sessionTmpURL(for: session.visitId)
        let dstURL = sessionURL(for: session.visitId)

        do {
            try data.write(to: tmpURL, options: [.atomic])
            // `replaceItemAt` is the safest cross-platform rename on Darwin.
            _ = try fileManager.replaceItemAt(dstURL, withItemAt: tmpURL)
        } catch {
            // Fallback: direct move (works on Linux / test environments).
            do {
                if fileManager.fileExists(atPath: dstURL.path) {
                    try fileManager.removeItem(at: dstURL)
                }
                try fileManager.moveItem(at: tmpURL, to: dstURL)
            } catch let moveError {
                throw StoreError.fileWriteFailed(moveError)
            }
        }
    }

    // MARK: Load

    /// Loads the session for `visitId`.
    public func load(visitId: UUID) throws -> SessionCaptureV2 {
        let url = sessionURL(for: visitId)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.sessionNotFound(visitId)
        }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(SessionCaptureV2.self, from: data)
        } catch {
            throw StoreError.decodingFailed(error)
        }
    }

    // MARK: List all saved visits

    public func allVisitIds() throws -> [UUID] {
        guard fileManager.fileExists(atPath: capturesRoot.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: capturesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return nil }
            return UUID(uuidString: url.lastPathComponent)
        }
    }

    // MARK: Delete

    public func delete(visitId: UUID) throws {
        let dir = captureDirectory(for: visitId)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }
}
