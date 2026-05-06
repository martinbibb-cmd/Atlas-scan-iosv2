/// PropertyMapView — The top-level "Property Map" screen.
///
/// Shows the list of captured rooms on a 2-D canvas drawn using
/// `CustomRoomShapeRenderer`.  The engineer taps "Add Room" to start the
/// RoomPlan capture flow.

import SwiftUI
import AtlasScanCore

struct PropertyMapView: View {

    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @State private var showRoomLoop = false
    @State private var showVanMode = false
    @State private var propertyAddress = ""
    @State private var showAddressEntry = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── Address banner ───────────────────────────────────────────
                addressBanner

                // ── Room grid ────────────────────────────────────────────────
                if coordinator.session.rooms.isEmpty {
                    emptyState
                } else {
                    roomGrid
                }

                // ── QA summary ───────────────────────────────────────────────
                if !coordinator.session.qaFlags.isEmpty {
                    qaFlagsSummary
                }
            }
            .padding()
        }
        .navigationTitle("Property Map")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Readiness indicator
                readinessButton
                // Van mode (retrospective review)
                Button {
                    showVanMode = true
                } label: {
                    Label("Van Mode", systemImage: "car.fill")
                }
                // Add room
                Button {
                    showRoomLoop = true
                } label: {
                    Label("Add Room", systemImage: "plus.rectangle.on.rectangle")
                }
            }
        }
        .sheet(isPresented: $showRoomLoop) {
            RoomLoopView()
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showVanMode) {
            VanModeView()
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showAddressEntry) {
            addressEntrySheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .atlasHandoffURL)) { note in
            guard let url = note.object as? URL else { return }
            UIApplication.shared.open(url)
        }
    }

    // MARK: Subviews

    private var addressBanner: some View {
        Button {
            propertyAddress = coordinator.session.propertyAddress ?? ""
            showAddressEntry = true
        } label: {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.red)
                Text(coordinator.session.propertyAddress ?? "Tap to add property address")
                    .foregroundStyle(
                        coordinator.session.propertyAddress != nil ? .primary : .secondary
                    )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Rooms Captured", systemImage: "camera.metering.unknown")
        } description: {
            Text("Tap the + button to begin capturing your first room.")
        } actions: {
            Button("Add First Room") { showRoomLoop = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 300)
    }

    private var roomGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
            ForEach(coordinator.session.rooms) { room in
                RoomCardView(room: room)
                    .environmentObject(coordinator)
            }
        }
    }

    private var qaFlagsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("QA Flags", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(coordinator.session.qaFlags) { flag in
                HStack {
                    Image(systemName: flag.type == .clearanceConflict
                          ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(flag.type == .clearanceConflict ? .red : .green)
                    VStack(alignment: .leading) {
                        Text(flag.type.rawValue)
                            .font(.caption.bold())
                        if !flag.detail.isEmpty {
                            Text(flag.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var readinessButton: some View {
        Button {
            coordinator.showHandoff = coordinator.readiness.isReady
        } label: {
            Image(systemName: coordinator.readiness.isReady
                  ? "checkmark.seal.fill" : "seal")
                .foregroundStyle(coordinator.readiness.isReady ? .green : .orange)
        }
        .accessibilityLabel(
            coordinator.readiness.isReady ? "Ready to hand off" : "Not ready — tap for details"
        )
    }

    private var addressEntrySheet: some View {
        NavigationStack {
            Form {
                Section("Property Address") {
                    TextField("e.g. 42 Thermal Close, London", text: $propertyAddress)
                        .textContentType(.fullStreetAddress)
                }
            }
            .navigationTitle("Property Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        coordinator.session.propertyAddress = propertyAddress.isEmpty
                            ? nil : propertyAddress
                        coordinator.save()
                        showAddressEntry = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddressEntry = false }
                }
            }
        }
    }
}

// MARK: - Room card

private struct RoomCardView: View {
    let room: RoomCaptureV2
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @State private var showRoomLoop = false

    var body: some View {
        Button { showRoomLoop = true } label: {
            VStack(spacing: 8) {
                // Mini polygon render
                CustomRoomShapeRenderer(
                    polygon: RoomPolygon(vertices: room.polygonVertices),
                    fillColor: .blue.opacity(0.15),
                    strokeColor: .blue
                )
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(room.displayName)
                    .font(.callout.bold())
                    .lineLimit(1)

                Text(String(format: "%.1f m²", room.floorAreaM2))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .sheet(isPresented: $showRoomLoop) {
            RoomLoopView(existingRoom: room)
                .environmentObject(coordinator)
        }
    }
}
