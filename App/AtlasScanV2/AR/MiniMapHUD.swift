/// MiniMapHUD — Resident Evil–style circular mini-map drawn as a SwiftUI
/// overlay during an active RoomPlan capture session.
///
/// Fog-of-War polygon:
///   Subscribes to `RoomPlanCoordinator.currentPolygon`.  As the engineer
///   walks the room, newly scanned wall vertices are added and the filled
///   polygon grows to reveal the captured footprint.
///
/// Object Radar:
///   Pins (boilers, flues, cylinders) that are currently **off-screen** are
///   indicated by white triangle pointers on the perimeter of the circular
///   HUD, pointing toward the object's world position.
///
/// Coordinate convention: all room geometry is in Y-up metric metres; the
/// mini-map projects onto the horizontal (X, Z) plane.
///
/// Platform: iOS 17+

import SwiftUI
import AtlasScanCore
import Combine

// MARK: - Mini-map overlay view

struct MiniMapHUD: View {

    // MARK: Dependencies

    /// Live polygon from RoomPlanCoordinator.
    let polygon: RoomPolygon

    /// Pinned objects in the current room.
    let pins: [SpatialPinV1]

    /// The camera's current world-space position (X, Z metres).
    let cameraPositionXZ: SIMD2<Float>

    /// The camera's current heading (radians, measured clockwise from +Z axis).
    let cameraHeadingRad: Float

    // MARK: Layout constants

    private let hudDiameter: CGFloat = 140
    private let radarMargin: CGFloat = 10

    // MARK: Body

    var body: some View {
        ZStack {
            // ── Circular clipping frame ──────────────────────────────────────
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: hudDiameter, height: hudDiameter)

            // ── Fog-of-war room polygon ──────────────────────────────────────
            RoomPolygonShape(polygon: polygon, hudDiameter: hudDiameter)
                .fill(Color.green.opacity(0.25))
                .clipShape(Circle())
                .frame(width: hudDiameter, height: hudDiameter)

            RoomPolygonShape(polygon: polygon, hudDiameter: hudDiameter)
                .stroke(Color.green.opacity(0.7), lineWidth: 1)
                .clipShape(Circle())
                .frame(width: hudDiameter, height: hudDiameter)

            // ── Camera direction indicator ───────────────────────────────────
            CameraDirectionIndicator(headingRad: cameraHeadingRad)
                .frame(width: hudDiameter, height: hudDiameter)

            // ── Off-screen object radar triangles ────────────────────────────
            ForEach(offScreenPins, id: \.id) { pin in
                RadarPointer(angle: radarAngle(for: pin))
                    .frame(width: hudDiameter, height: hudDiameter)
            }

            // ── Border ring ──────────────────────────────────────────────────
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: hudDiameter, height: hudDiameter)
        }
        .frame(width: hudDiameter, height: hudDiameter)
        .accessibilityLabel("Mini-map")
    }

    // MARK: Off-screen pin filtering

    /// Returns pins that the spec classifies as "of interest" and that lie
    /// beyond the current view frustum (approximated as objects not within
    /// ±45° of the camera heading and within 10 m).
    private var offScreenPins: [SpatialPinV1] {
        let radarTypes: Set<PinnedObjectType> = [.boiler, .heatPump, .flueTerminal, .hotWaterCylinder]
        return pins.filter { pin in
            guard radarTypes.contains(pin.objectType) else { return false }
            let dx = Float(pin.positionX) - cameraPositionXZ.x
            let dz = Float(pin.positionZ) - cameraPositionXZ.y
            let dist = (dx * dx + dz * dz).squareRoot()
            guard dist > 0.5 else { return false }   // ignore pins right on the camera
            let angleToPin = atan2(dx, dz)   // bearing in XZ plane
            let relativeAngle = angleDifference(angleToPin, cameraHeadingRad)
            return abs(relativeAngle) > Float.pi / 4   // outside ±45° frustum
        }
    }

    /// Computes the radar-ring angle (radians) from 12-o'clock for `pin`.
    private func radarAngle(for pin: SpatialPinV1) -> Double {
        let dx = Float(pin.positionX) - cameraPositionXZ.x
        let dz = Float(pin.positionZ) - cameraPositionXZ.y
        let worldAngle = atan2(dx, dz)
        let relativeAngle = Double(worldAngle - cameraHeadingRad)
        return relativeAngle
    }

    /// Normalised angular difference in (−π, π].
    private func angleDifference(_ a: Float, _ b: Float) -> Float {
        var diff = a - b
        while diff >  Float.pi { diff -= 2 * Float.pi }
        while diff < -Float.pi { diff += 2 * Float.pi }
        return diff
    }
}

// MARK: - Room polygon shape

/// Transforms world-space (X, Z) vertices into the HUD's local coordinate
/// system, scaled to fit the circular canvas.
private struct RoomPolygonShape: Shape {

    let polygon: RoomPolygon
    let hudDiameter: CGFloat

    func path(in rect: CGRect) -> Path {
        guard polygon.isValid, let bb = polygon.boundingBox else { return Path() }

        // Scale factor: fit the bounding box inside the circle with padding.
        let padding: CGFloat = 12
        let maxDimension = CGFloat(max(bb.widthM, bb.depthM))
        let scale = maxDimension > 0 ? (hudDiameter - 2 * padding) / maxDimension : 1.0
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let polyCenter = polygon.centroid

        func project(_ v: Vertex2D) -> CGPoint {
            // X → right, Z → up (inverted for screen coordinates)
            CGPoint(
                x: centre.x + CGFloat(v.x - polyCenter.x) * scale,
                y: centre.y - CGFloat(v.z - polyCenter.z) * scale
            )
        }

        var path = Path()
        let first = project(polygon.vertices[0])
        path.move(to: first)
        for v in polygon.vertices.dropFirst() {
            path.addLine(to: project(v))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Camera direction indicator

/// A small filled triangle pointing in the camera's heading direction.
private struct CameraDirectionIndicator: View {

    let headingRad: Float

    var body: some View {
        Triangle()
            .fill(Color.white)
            .frame(width: 8, height: 10)
            .rotationEffect(.radians(Double(headingRad)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Radar pointer (off-screen object indicator)

/// A white triangle on the HUD perimeter pointing toward an off-screen pin.
private struct RadarPointer: View {

    /// Angle from 12-o'clock, clockwise (radians).
    let angle: Double

    private let ringRadius: CGFloat = 62   // ≈ (140/2) − margin

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let px = cx + ringRadius * CGFloat(sin(angle))
            let py = cy - ringRadius * CGFloat(cos(angle))

            Triangle()
                .fill(Color.white)
                .frame(width: 7, height: 8)
                .rotationEffect(.radians(angle))
                .position(x: px, y: py)
        }
    }
}

// MARK: - Live HUD wrapper (connects to coordinator)

/// Drop-in SwiftUI component that wires up `MiniMapHUD` to the live
/// `RoomPlanCoordinator` and `ScanSessionCoordinator`.
struct LiveMiniMapHUD: View {

    @ObservedObject var roomCoordinator: RoomPlanCoordinator
    let room: RoomCaptureV2?

    /// Camera transform provided by the AR session (X, Z world position).
    var cameraPositionXZ: SIMD2<Float> = .zero
    var cameraHeadingRad: Float = 0

    var body: some View {
        MiniMapHUD(
            polygon: roomCoordinator.currentPolygon,
            pins: room?.pinnedObjects ?? [],
            cameraPositionXZ: cameraPositionXZ,
            cameraHeadingRad: cameraHeadingRad
        )
    }
}
