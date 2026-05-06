/// SpatialPinManager — Manages tap-to-pin AR anchor placement.
///
/// When the engineer taps a physical surface in the AR camera view, the manager:
/// 1. Performs a ray-cast against the current LiDAR mesh
/// 2. Creates a `SpatialPinV1` at the hit position
/// 3. Adds an `ARAnchor` to the session so the pin is tracked in world space
/// 4. Fires a callback so the parent coordinator can link evidence (photos,
///    transcripts) to this pin's ID.

import Foundation
import AtlasScanCore

#if canImport(ARKit)
import ARKit
import RealityKit

// MARK: - Spatial pin manager

@MainActor
final class SpatialPinManager: NSObject, ObservableObject {

    // MARK: Published

    @Published var activePin: SpatialPinV1?
    @Published var allPins: [SpatialPinV1] = []

    // MARK: Callbacks

    var onPinAdded: ((SpatialPinV1) -> Void)?

    // MARK: Private

    private weak var arSession: ARSession?

    // MARK: Init

    init(arSession: ARSession?) {
        self.arSession = arSession
    }

    // MARK: Handle tap

    /// Call this from the view's tap gesture recogniser.
    ///
    /// - Parameters:
    ///   - location:    The tap location in the AR view's coordinate system.
    ///   - arView:      The `ARView` instance (for ray-casting).
    ///   - roomId:      The room UUID to associate with the pin.
    ///   - objectType:  The type of object being pinned.
    ///   - label:       Optional human-readable label.
    ///   - hardwareSpecId: Optional link to a `HardwareSpecV1` in the registry.
    func handleTap(
        at location: CGPoint,
        in arView: ARView,
        roomId: UUID,
        objectType: PinnedObjectType,
        label: String? = nil,
        hardwareSpecId: UUID? = nil
    ) {
        // Ray-cast against the real-world mesh
        let results = arView.raycast(
            from: location,
            allowing: .estimatedPlane,
            alignment: .any
        )

        guard let hit = results.first else { return }

        let worldTransform = hit.worldTransform
        let pin = SpatialPinV1(
            roomId: roomId,
            positionX: Double(worldTransform.columns.3.x),
            positionY: Double(worldTransform.columns.3.y),
            positionZ: Double(worldTransform.columns.3.z),
            objectType: objectType,
            label: label,
            hardwareSpecId: hardwareSpecId
        )

        // Add a visual anchor to the AR session
        let anchor = ARAnchor(
            name: "pin:\(pin.id.uuidString)",
            transform: worldTransform
        )
        arSession?.add(anchor: anchor)

        allPins.append(pin)
        activePin = pin
        onPinAdded?(pin)
    }

    // MARK: Clear active pin

    func clearActivePin() {
        activePin = nil
    }

    // MARK: Remove pin

    func removePin(_ pin: SpatialPinV1) {
        allPins.removeAll { $0.id == pin.id }
        if activePin?.id == pin.id { activePin = nil }
    }
}

#else

// MARK: - Stub for non-iOS builds

@MainActor
final class SpatialPinManager: ObservableObject {
    @Published var activePin: SpatialPinV1?
    @Published var allPins: [SpatialPinV1] = []
    var onPinAdded: ((SpatialPinV1) -> Void)?
    init(arSession: AnyObject? = nil) {}
    func clearActivePin() { activePin = nil }
}

#endif
