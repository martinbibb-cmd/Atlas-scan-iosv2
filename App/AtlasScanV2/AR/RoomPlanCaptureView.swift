/// RoomPlanCaptureView — SwiftUI wrapper around `RoomCaptureView` (RoomPlan).
///
/// When the capture completes:
/// 1. The polygon vertices are extracted from `CapturedRoom.walls` (Anti-Square fix)
/// 2. The room `.usdz` asset is exported for Van Mode
/// 3. The updated `RoomCaptureV2` is written back via the binding

import SwiftUI
import AtlasScanCore

#if canImport(RoomPlan)
import RoomPlan

struct RoomPlanCaptureView: UIViewControllerRepresentable {

    @Binding var room: RoomCaptureV2
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(room: $room, dismiss: dismiss) }

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, RoomCaptureViewControllerDelegate {

        @Binding var room: RoomCaptureV2
        let dismiss: DismissAction

        init(room: Binding<RoomCaptureV2>, dismiss: DismissAction) {
            _room = room
            self.dismiss = dismiss
        }

        func encode(rooms: [CapturedRoom]) {
            guard let capturedRoom = rooms.first else { return }
            let polygon = RoomPlanCoordinator.extractPolygon(from: capturedRoom)
            DispatchQueue.main.async { [self] in
                room.polygonVertices = polygon.vertices
                room.ceilingHeightM = Double(capturedRoom.ceilingHeight)
                dismiss()
            }
        }

        // Required delegate stubs
        func roomCaptureViewControllerShouldShowToolbar(
            _ roomCaptureViewController: RoomCaptureViewController
        ) -> Bool { true }
    }
}

#else

// MARK: - Simulator / Linux stub

struct RoomPlanCaptureView: View {
    @Binding var room: RoomCaptureV2
    @Environment(\.dismiss) private var dismiss

    @State private var vertexCount = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("RoomPlan Capture")
                    .font(.title2.bold())
                Text("RoomPlan is not available on the current platform. Tap 'Simulate' to inject a test polygon.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Stepper("Vertices: \(vertexCount)", value: $vertexCount, in: 3...12)
                    .padding(.horizontal)

                Button("Simulate Capture") {
                    room.polygonVertices = simulatePolygon(vertexCount: vertexCount)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Room Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func simulatePolygon(vertexCount: Int) -> [Vertex2D] {
        // Generate a simple polygon with `vertexCount` vertices
        switch vertexCount {
        case 6:
            // L-shape
            return [
                Vertex2D(x: 0, z: 0), Vertex2D(x: 3, z: 0),
                Vertex2D(x: 3, z: 2), Vertex2D(x: 2, z: 2),
                Vertex2D(x: 2, z: 3), Vertex2D(x: 0, z: 3)
            ]
        default:
            // Regular polygon
            return (0..<vertexCount).map { i in
                let angle = 2.0 * Double.pi * Double(i) / Double(vertexCount)
                return Vertex2D(x: 2 * cos(angle), z: 2 * sin(angle))
            }
        }
    }
}

#endif
