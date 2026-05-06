/// GhostBoxRenderer — Renders a semi-transparent SCNBox "ghost box" that
/// represents the boiler footprint plus manufacturer-specified clearances.
///
/// The ghost box is sized from `HardwareSpecV1.ghostBoxWidth/Height/DepthM` and
/// positioned at the world-space location of the `SpatialPinV1` for the boiler.
///
/// The `ClearanceConflictDetector` (Möller–Trumbore) then tests whether the
/// captured LiDAR mesh pierces the clearance volume.

import Foundation
import AtlasScanCore

#if canImport(SceneKit)
import SceneKit
import ARKit

// MARK: - Ghost box renderer

final class GhostBoxRenderer {

    // MARK: Types

    enum ConflictState {
        case unchecked
        case checking
        case clear
        case conflict(detail: String)
    }

    // MARK: Properties

    private(set) var boxNode: SCNNode?
    private(set) var conflictState: ConflictState = .unchecked

    // MARK: Build ghost box node

    /// Creates and returns a semi-transparent `SCNNode` for `spec` centred at origin.
    /// The caller is responsible for positioning the node at the boiler's world transform.
    func buildGhostBoxNode(for spec: HardwareSpecV1) -> SCNNode {
        // Outer clearance volume (semi-transparent red/green)
        let ghostBox = SCNBox(
            width:  CGFloat(spec.ghostBoxWidthM),
            height: CGFloat(spec.ghostBoxHeightM),
            length: CGFloat(spec.ghostBoxDepthM),
            chamferRadius: 0
        )
        let ghostMat = SCNMaterial()
        ghostMat.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.15)
        ghostMat.isDoubleSided   = true
        ghostMat.blendMode       = .alpha
        ghostBox.materials = [ghostMat]

        let ghostNode = SCNNode(geometry: ghostBox)
        ghostNode.name = "clearanceVolume"

        // Inner boiler footprint (solid outline)
        let boilerBox = SCNBox(
            width:  CGFloat(spec.widthM),
            height: CGFloat(spec.heightM),
            length: CGFloat(spec.depthM),
            chamferRadius: 0
        )
        let boilerMat = SCNMaterial()
        boilerMat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.4)
        boilerMat.fillMode = .lines
        boilerBox.materials = [boilerMat]

        let boilerNode = SCNNode(geometry: boilerBox)
        boilerNode.name = "boilerFootprint"
        ghostNode.addChildNode(boilerNode)

        self.boxNode = ghostNode
        return ghostNode
    }

    // MARK: Update visual state

    func updateAppearance(state: ConflictState) {
        self.conflictState = state
        guard let node = boxNode,
              let box = node.geometry as? SCNBox,
              let mat = box.firstMaterial else { return }

        switch state {
        case .unchecked, .checking:
            mat.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.15)
        case .clear:
            mat.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.20)
        case .conflict:
            mat.diffuse.contents = UIColor.systemRed.withAlphaComponent(0.30)
        }
    }

    // MARK: Mesh-intersection check

    /// Extracts triangles from `arMeshAnchors` and runs the Möller–Trumbore check.
    ///
    /// - Parameters:
    ///   - spec:          The boiler/heat pump hardware spec.
    ///   - pinWorldPos:   World-space position of the boiler pin (Y-up, metres).
    ///   - arMeshAnchors: The live `ARMeshAnchor` set from the current AR session.
    ///   - roomId:        The room UUID for QA flag emission.
    /// - Returns: A `QAFlagV1` with either `.clearanceConflict` or `.clearancePass`.
    func checkClearances(
        spec: HardwareSpecV1,
        pinWorldPos: SCNVector3,
        arMeshAnchors: [ARMeshAnchor],
        roomId: UUID
    ) async -> QAFlagV1 {
        conflictState = .checking
        updateAppearance(state: .checking)

        let centre = Vec3(Double(pinWorldPos.x), Double(pinWorldPos.y), Double(pinWorldPos.z))
        let ghostBox = ClearanceConflictDetector.GhostBox(spec: spec, centre: centre)

        let triangles = arMeshAnchors.flatMap { anchor -> [ClearanceConflictDetector.Triangle] in
            let geo = anchor.geometry
            return extractTriangles(from: geo, transform: anchor.transform)
        }

        let flag = await Task.detached(priority: .userInitiated) {
            ClearanceConflictDetector.qaFlag(
                for: triangles,
                ghostBox: ghostBox,
                roomId: roomId
            )
        }.value

        let newState: ConflictState = flag.type == .clearanceConflict
            ? .conflict(detail: flag.detail) : .clear
        conflictState = newState
        updateAppearance(state: newState)
        return flag
    }

    // MARK: Triangle extraction from ARMeshGeometry

    private func extractTriangles(
        from geometry: ARMeshGeometry,
        transform: simd_float4x4
    ) -> [ClearanceConflictDetector.Triangle] {
        let vertexBuffer   = geometry.vertices
        let faceBuffer     = geometry.faces

        let vertexPointer  = vertexBuffer.buffer.contents()
        let facePointer    = faceBuffer.buffer.contents()

        var vertices: [Vec3] = []
        for i in 0..<vertexBuffer.count {
            let offset = vertexBuffer.offset + i * vertexBuffer.stride
            let raw = vertexPointer.advanced(by: offset)
                .bindMemory(to: Float.self, capacity: 3)
            let localPos = simd_float4(raw[0], raw[1], raw[2], 1)
            let worldPos = transform * localPos
            vertices.append(Vec3(Double(worldPos.x), Double(worldPos.y), Double(worldPos.z)))
        }

        var triangles: [ClearanceConflictDetector.Triangle] = []
        let indexCount = faceBuffer.count * faceBuffer.indexCountPerPrimitive
        for i in stride(from: 0, to: indexCount, by: 3) {
            let i0Offset = faceBuffer.offset + i * MemoryLayout<UInt32>.size
            let i0 = facePointer.advanced(by: i0Offset)
                .bindMemory(to: UInt32.self, capacity: 1).pointee
            let i1 = facePointer.advanced(by: i0Offset + MemoryLayout<UInt32>.size)
                .bindMemory(to: UInt32.self, capacity: 1).pointee
            let i2 = facePointer.advanced(by: i0Offset + 2 * MemoryLayout<UInt32>.size)
                .bindMemory(to: UInt32.self, capacity: 1).pointee

            guard Int(i0) < vertices.count,
                  Int(i1) < vertices.count,
                  Int(i2) < vertices.count else { continue }

            triangles.append((
                v0: vertices[Int(i0)],
                v1: vertices[Int(i1)],
                v2: vertices[Int(i2)]
            ))
        }
        return triangles
    }
}

#else

// MARK: - Stub for non-iOS builds

final class GhostBoxRenderer {
    enum ConflictState {
        case unchecked, checking, clear
        case conflict(detail: String)
    }
    private(set) var conflictState: ConflictState = .unchecked
}

#endif
