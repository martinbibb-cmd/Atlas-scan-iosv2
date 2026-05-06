/// RoomLoopView — The 3-step cycle for adding one room to the Property Map.
///
/// Step 1: Geometry & Fabric — capture RoomPlan + classify walls
/// Step 2: Spatial Pinning & Evidence — tap-to-pin + photos + voice notes
/// Step 3: Clearance Verification — ghost-box AR check

import SwiftUI
import AtlasScanCore

enum RoomLoopStep: Int, CaseIterable {
    case geometry  = 0
    case evidence  = 1
    case clearance = 2

    var title: String {
        switch self {
        case .geometry:  return "Geometry & Fabric"
        case .evidence:  return "Spatial Evidence"
        case .clearance: return "Clearance Check"
        }
    }

    var systemImage: String {
        switch self {
        case .geometry:  return "square.grid.3x3.fill"
        case .evidence:  return "pin.circle.fill"
        case .clearance: return "cube.transparent"
        }
    }
}

struct RoomLoopView: View {

    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State var existingRoom: RoomCaptureV2?
    @State private var currentStep: RoomLoopStep = .geometry
    @State private var room: RoomCaptureV2

    init(existingRoom: RoomCaptureV2? = nil) {
        self.existingRoom = existingRoom
        _room = State(initialValue: existingRoom ?? RoomCaptureV2(displayName: "New Room"))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                stepIndicator

                // Page content
                TabView(selection: $currentStep) {
                    GeometryFabricStep(room: $room)
                        .tag(RoomLoopStep.geometry)

                    SpatialEvidenceStep(room: $room)
                        .tag(RoomLoopStep.evidence)

                    ClearanceStep(room: $room)
                        .tag(RoomLoopStep.clearance)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                // Navigation buttons
                navigationButtons
            }
            .navigationTitle(currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(RoomLoopStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue
                                  ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                        Image(systemName: step.systemImage)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                if step.rawValue < RoomLoopStep.allCases.count - 1 {
                    Rectangle()
                        .fill(currentStep.rawValue > step.rawValue
                              ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: Navigation buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep != .geometry {
                Button("Back") {
                    withAnimation { currentStep = RoomLoopStep(rawValue: currentStep.rawValue - 1)! }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep == .clearance {
                Button("Save Room") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Next") {
                    withAnimation { currentStep = RoomLoopStep(rawValue: currentStep.rawValue + 1)! }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: Save

    private func saveAndDismiss() {
        if existingRoom != nil {
            coordinator.updateRoom(room)
        } else {
            coordinator.addRoom(room)
        }
        dismiss()
    }
}

// MARK: - Step 1: Geometry & Fabric

struct GeometryFabricStep: View {

    @Binding var room: RoomCaptureV2
    @State private var showRoomPlanCapture = false
    @State private var roomName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Room name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Room Name").font(.headline)
                    TextField("e.g. Utility Room", text: Binding(
                        get: { room.displayName },
                        set: { room.displayName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Capture / polygon preview
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Room Polygon").font(.headline)
                        Spacer()
                        Button("Capture with RoomPlan") {
                            showRoomPlanCapture = true
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }

                    if room.polygonVertices.isEmpty {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 200)
                            .overlay {
                                Label("No polygon captured yet", systemImage: "square.dashed")
                                    .foregroundStyle(.secondary)
                            }
                    } else {
                        CustomRoomShapeRenderer(
                            polygon: RoomPolygon(vertices: room.polygonVertices),
                            showFabricColors: true,
                            fabricSegments: room.wallSegments
                        )
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("\(room.polygonVertices.count) vertices · \(String(format: "%.1f m²", room.floorAreaM2))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Wall fabric classification
                if !room.wallSegments.isEmpty {
                    WallFabricClassifierView(room: $room)
                }

                // Floor / ceiling
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dimensions").font(.headline)
                    LabeledContent("Ceiling Height") {
                        Text("\(String(format: "%.2f", room.ceilingHeightM)) m")
                    }
                    LabeledContent("Floor Level") {
                        Text("\(String(format: "%.2f", room.floorLevelY)) m")
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showRoomPlanCapture) {
            RoomPlanCaptureView(room: $room)
        }
    }
}

// MARK: - Wall fabric classifier

struct WallFabricClassifierView: View {

    @Binding var room: RoomCaptureV2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wall Fabric").font(.headline)
                Spacer()
                FabricLegendView()
            }
            ForEach(room.wallSegments.indices, id: \.self) { i in
                WallSegmentRow(
                    segmentIndex: i,
                    segment: room.wallSegments[i],
                    onFabricChange: { newFabric in
                        if room.fabricCapture == nil {
                            room.fabricCapture = FloorPlanFabricCaptureV1(
                                roomId: room.id,
                                segments: room.wallSegments
                            )
                        }
                        room.fabricCapture?.segments[i].fabric = newFabric
                    }
                )
            }
        }
    }
}

private struct WallSegmentRow: View {
    let segmentIndex: Int
    let segment: WallSegmentV1
    let onFabricChange: (WallFabric) -> Void

    var body: some View {
        HStack {
            Text("Wall \(segmentIndex + 1)")
                .font(.subheadline)
            Text(String(format: "(%.1f m)", segment.lengthM))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { segment.fabric },
                set: { onFabricChange($0) }
            )) {
                ForEach(WallFabric.allCases, id: \.rawValue) { fabric in
                    Text(fabric.displayName).tag(fabric)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step 2: Spatial Evidence

struct SpatialEvidenceStep: View {

    @Binding var room: RoomCaptureV2
    @EnvironmentObject var coordinator: ScanSessionCoordinator

    @State private var showPinCreator = false
    @State private var showCamera = false
    @State private var transcriptText = ""
    @State private var selectedHint: ExtractionHint = .general

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Active pin indicator
                if let pin = coordinator.activePin {
                    ActivePinBanner(pin: pin) {
                        coordinator.setActivePin(nil)
                    }
                }

                // Pins
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pinned Objects").font(.headline)
                        Spacer()
                        Button {
                            showPinCreator = true
                        } label: {
                            Label("Add Pin", systemImage: "mappin.and.ellipse")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }

                    if room.pinnedObjects.isEmpty {
                        Text("No objects pinned. Tap the physical location of a boiler, cylinder, or flue to add a pin.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(room.pinnedObjects) { pin in
                            PinRow(pin: pin, isActive: coordinator.activePin?.id == pin.id) {
                                coordinator.setActivePin(pin)
                            }
                        }
                    }
                }

                // Photos
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Photos").font(.headline)
                        Spacer()
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    let roomPhotos = coordinator.session.photos.filter { $0.roomId == room.id }
                    if roomPhotos.isEmpty {
                        Text("No photos attached. Photos are linked to the active pin automatically.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(roomPhotos.count) photo(s) attached")
                            .font(.callout)
                    }
                }

                // Voice note / transcript
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice Note").font(.headline)
                    Picker("Extraction Hint", selection: $selectedHint) {
                        ForEach(ExtractionHint.allCases, id: \.rawValue) { hint in
                            Text(hint.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(hint)
                        }
                    }
                    .pickerStyle(.menu)
                    TextEditor(text: $transcriptText)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                    Button("Attach Transcript") {
                        guard !transcriptText.isEmpty else { return }
                        coordinator.recordTranscript(
                            roomId: room.id,
                            text: transcriptText,
                            hint: selectedHint
                        )
                        transcriptText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(transcriptText.isEmpty)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showPinCreator) {
            PinCreatorView(room: $room)
                .environmentObject(coordinator)
        }
    }
}

// MARK: - Helpers for Step 2

private struct ActivePinBanner: View {
    let pin: SpatialPinV1
    let onClear: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("Active Pin: \(pin.objectType.rawValue.capitalized)")
                    .font(.subheadline.bold())
                Text("Photos & notes will be linked to this pin")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear", action: onClear).font(.caption)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PinRow: View {
    let pin: SpatialPinV1
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "mappin.circle\(isActive ? ".fill" : "")")
                    .foregroundStyle(isActive ? .orange : .secondary)
                VStack(alignment: .leading) {
                    Text(pin.objectType.rawValue.capitalized)
                        .font(.subheadline)
                    Text(String(format: "(%.2f, %.2f, %.2f)",
                                pin.positionX, pin.positionY, pin.positionZ))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if isActive {
                    Text("Active").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3: Clearance Verification

struct ClearanceStep: View {

    @Binding var room: RoomCaptureV2
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @State private var showGhostBoxAR = false
    @State private var selectedBoilerPin: SpatialPinV1?

    var boilerPins: [SpatialPinV1] {
        room.pinnedObjects.filter { $0.objectType == .boiler || $0.objectType == .heatPump }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                if boilerPins.isEmpty {
                    ContentUnavailableView(
                        "No Boiler Pinned",
                        systemImage: "cube.transparent",
                        description: Text("Go back to Step 2 and pin the boiler or heat pump location to enable clearance checking.")
                    )
                } else {
                    Text("Select the boiler/heat pump to check clearances:")
                        .font(.headline)

                    ForEach(boilerPins) { pin in
                        Button {
                            selectedBoilerPin = pin
                            showGhostBoxAR = true
                        } label: {
                            HStack {
                                Image(systemName: "cube.transparent.fill")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text(pin.label ?? pin.objectType.rawValue.capitalized)
                                        .font(.subheadline.bold())
                                    if let specId = pin.hardwareSpecId,
                                       let spec = HardwareRegistryV1.shared.allSpecs(ofType: .boiler)
                                            .first(where: { $0.id == specId }) {
                                        Text("\(spec.manufacturer) \(spec.modelName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("Start AR Check")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.blue.opacity(0.1), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Existing QA results for this room
                    let flags = coordinator.session.qaFlags.filter { $0.roomId == room.id }
                    if !flags.isEmpty {
                        Divider()
                        Text("Check Results").font(.headline)
                        ForEach(flags) { flag in
                            HStack {
                                Image(systemName: flag.type == .clearanceConflict
                                      ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(flag.type == .clearanceConflict ? .red : .green)
                                Text(flag.detail)
                                    .font(.callout)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showGhostBoxAR) {
            if let pin = selectedBoilerPin {
                GhostBoxARView(pin: pin, room: $room)
                    .environmentObject(coordinator)
            }
        }
    }
}

// MARK: - Pin creator

struct PinCreatorView: View {

    @Binding var room: RoomCaptureV2
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: PinnedObjectType = .boiler
    @State private var label = ""
    @State private var showSpatialCapture = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Object Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(PinnedObjectType.allCases, id: \.rawValue) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                }
                Section("Label (optional)") {
                    TextField("e.g. Main boiler", text: $label)
                }
                Section {
                    Button("Place in AR") {
                        showSpatialCapture = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Add Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showSpatialCapture) {
            SpatialPinARView(room: $room, objectType: selectedType, label: label.isEmpty ? nil : label)
                .environmentObject(coordinator)
        }
    }
}
