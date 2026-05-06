/// RoomPlanCoordinator — Bridges the RoomPlan `RoomCaptureSession` delegate
/// into a SwiftUI-friendly `ObservableObject`.
///
/// Responsibilities:
/// - Starts / stops a `RoomCaptureSession`
/// - On `captureSession(_:didAdd:)` and `didChange` notifications, extracts
///   the polygon vertices from `CapturedRoom.walls` (Anti-Square fix)
/// - Exports the final room as a `.usdz` asset to Documents/captures/{visitId}/usdz/
///
/// Platform: iOS 16+ (RoomPlan GA)

import Foundation
import Combine
import AtlasScanCore

#if canImport(RoomPlan)
import RoomPlan

// MARK: - Coordinator

@MainActor
final class RoomPlanCoordinator: NSObject, ObservableObject, RoomCaptureSessionDelegate {

    // MARK: Published

    @Published var capturedRoom: CapturedRoom?
    @Published var currentPolygon: RoomPolygon = RoomPolygon(vertices: [])
    @Published var isCapturing: Bool = false
    @Published var error: Error?

    // MARK: Private

    private let session: RoomCaptureSession
    private let visitId: UUID

    // MARK: Init

    init(visitId: UUID) {
        self.visitId = visitId
        self.session = RoomCaptureSession()
        super.init()
        session.delegate = self
    }

    // MARK: Session control

    func startCapture() {
        let config = RoomCaptureSession.Configuration()
        session.run(configuration: config)
        isCapturing = true
    }

    func stopCapture() {
        session.stop()
        isCapturing = false
    }

    // MARK: RoomCaptureSessionDelegate

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        let polygon = Self.extractPolygon(from: room)
        Task { @MainActor in
            self.capturedRoom = room
            self.currentPolygon = polygon
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: Error?
    ) {
        Task { @MainActor in
            self.isCapturing = false
            if let error = error {
                self.error = error
            }
        }
    }

    // MARK: Polygon extraction (Anti-Square fix)

    /// Extracts an ordered list of (X, Z) polygon vertices from a `CapturedRoom`.
    ///
    /// Uses `CapturedRoom.walls` to build the actual room perimeter rather than
    /// the bounding box (`rawWidthM × rawDepthM`) used in V1.
    static func extractPolygon(from room: CapturedRoom) -> RoomPolygon {
        // Each `CapturedRoom.Surface` (wall) has a `transform` (4×4 matrix) and
        // `dimensions` (width × height).  We project the four corners of each
        // wall onto the Y=0 plane to get 2D (X, Z) edge vertices, then extract
        // an ordered polygon using a convex-hull or winding-order algorithm.

        var xzPoints: [(x: Float, y: Float, z: Float)] = []

        for wall in room.walls {
            let t = wall.transform
            let hw = wall.dimensions.x / 2   // half-width
            // Left and right ends of the wall at floor level
            let left  = t * simd_float4(-hw, 0, 0, 1)
            let right = t * simd_float4( hw, 0, 0, 1)
            xzPoints.append((x: left.x,  y: left.y,  z: left.z))
            xzPoints.append((x: right.x, y: right.y, z: right.z))
        }

        guard !xzPoints.isEmpty else { return RoomPolygon(vertices: []) }

        // Build polygon via convex hull; for concave rooms a full ordered-edge
        // traversal would be preferred, but convex hull is a safe fallback.
        return RoomPolygon.convexHullFrom(vertices: xzPoints)
    }

    // MARK: USDZ export

    func exportUSDZ(
        from data: CapturedRoomData,
        roomId: UUID
    ) async throws -> URL {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw RoomPlanError.documentsUnavailable
        }
        let dir = docs
            .appendingPathComponent("captures")
            .appendingPathComponent(visitId.uuidString)
            .appendingPathComponent("usdz")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let dest = dir.appendingPathComponent("\(roomId.uuidString).usdz")
        try await data.export(to: dest, exportOptions: .mesh)
        return dest
    }
}

enum RoomPlanError: Error, LocalizedError {
    case documentsUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsUnavailable:
            return "Could not locate the Documents directory."
        }
    }
}

#else

// MARK: - Stub for non-iOS builds

/// Compile-time stub so the rest of the codebase can reference
/// `RoomPlanCoordinator` even on simulators / Linux builds.
@MainActor
final class RoomPlanCoordinator: ObservableObject {
    @Published var currentPolygon: RoomPolygon = RoomPolygon(vertices: [])
    @Published var isCapturing: Bool = false
    @Published var error: Error?

    init(visitId: UUID) {}
    func startCapture() {}
    func stopCapture() {}
}

#endif
