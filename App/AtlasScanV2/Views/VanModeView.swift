/// VanModeView — Retrospective review mode.
///
/// The engineer can re-visit a previously captured 3D room (loaded from the
/// persisted .usdz asset) and pull missed measurements directly from the mesh.

import SwiftUI
import AtlasScanCore

struct VanModeView: View {

    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRoom: RoomCaptureV2?
    @State private var showARReview = false

    var roomsWithUSDZ: [RoomCaptureV2] {
        coordinator.session.rooms.filter { $0.usdzAssetPath != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.session.rooms.isEmpty {
                    ContentUnavailableView(
                        "No Rooms",
                        systemImage: "car.fill",
                        description: Text("Capture rooms during a site visit first.")
                    )
                } else {
                    List {
                        Section {
                            Text("Van Mode lets you re-examine the 3D mesh of each room captured during the site visit. USDZ assets are loaded from Documents/captures/{visitId}/usdz/.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                        Section("Captured Rooms") {
                            ForEach(coordinator.session.rooms) { room in
                                VanModeRoomRow(room: room) {
                                    selectedRoom = room
                                    showARReview = room.usdzAssetPath != nil
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Van Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showARReview) {
            if let room = selectedRoom, let assetPath = room.usdzAssetPath {
                USDZReviewView(room: room, usdzRelativePath: assetPath)
            }
        }
    }
}

// MARK: - Room row

private struct VanModeRoomRow: View {
    let room: RoomCaptureV2
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.displayName)
                        .font(.subheadline.bold())
                    Text(String(format: "%.1f m²", room.floorAreaM2))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if room.usdzAssetPath != nil {
                    Label("3D Mesh", systemImage: "cube.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Text("No mesh")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - USDZ review view

/// Wraps an `ARQuickLookPreviewItem` / `QLPreviewController` to show the .usdz
/// mesh so the engineer can pull measurements from the captured room geometry.
struct USDZReviewView: View {

    let room: RoomCaptureV2
    let usdzRelativePath: String
    @Environment(\.dismiss) private var dismiss

    private var usdzURL: URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        return docs
            .appendingPathComponent("captures")
            .appendingPathComponent(room.id.uuidString)
            .appendingPathComponent(usdzRelativePath)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let url = usdzURL, FileManager.default.fileExists(atPath: url.path) {
                    USDZQuickLookRepresentable(url: url)
                } else {
                    ContentUnavailableView(
                        "Mesh Not Found",
                        systemImage: "exclamationmark.cube",
                        description: Text("The .usdz asset could not be located at:\n\(usdzRelativePath)")
                    )
                }
            }
            .navigationTitle(room.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - UIKit representable for QLPreviewController

import UIKit
import QuickLook

struct USDZQuickLookRepresentable: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
