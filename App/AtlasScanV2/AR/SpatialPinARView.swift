/// SpatialPinARView — Full-screen AR view for tap-to-pin placement.
///
/// The engineer taps the physical surface of a boiler, cylinder, or flue
/// terminal.  A ray-cast against the LiDAR mesh places a `SpatialPinV1`
/// at the exact world-space position, which is then fed back to the room loop.

import SwiftUI
import AtlasScanCore

#if canImport(ARKit) && canImport(RealityKit)
import ARKit
import RealityKit

struct SpatialPinARView: UIViewControllerRepresentable {

    @Binding var room: RoomCaptureV2
    let objectType: PinnedObjectType
    let label: String?
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> SpatialPinViewController.Coordinator {
        SpatialPinViewController.Coordinator(
            room: $room,
            objectType: objectType,
            label: label,
            sessionCoordinator: coordinator,
            dismiss: dismiss
        )
    }

    func makeUIViewController(context: Context) -> SpatialPinViewController {
        let vc = SpatialPinViewController(objectType: objectType, label: label)
        vc.onPinPlaced = { pin in
            context.coordinator.handlePinPlaced(pin)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: SpatialPinViewController, context: Context) {}
}

// MARK: - SpatialPinViewController

final class SpatialPinViewController: UIViewController {

    let objectType: PinnedObjectType
    let label: String?
    var onPinPlaced: ((SpatialPinV1) -> Void)?

    private var arView: ARView!
    private var pinManager: SpatialPinManager?

    init(objectType: PinnedObjectType, label: String?) {
        self.objectType = objectType
        self.label = label
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupPinManager()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        arView.session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }

    private func setupARView() {
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }

    private func setupPinManager() {
        pinManager = SpatialPinManager(arSession: arView.session)
        pinManager?.onPinAdded = { [weak self] pin in
            self?.onPinPlaced?(pin)
        }
    }

    private func setupUI() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Tap the \(objectType.rawValue) location to place a pin"
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.font = .preferredFont(forTextStyle: .callout)
        view.addSubview(label)

        let closeBtn = UIButton(type: .close)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            label.heightAnchor.constraint(equalToConstant: 44),

            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: arView)
        Task { @MainActor in
            pinManager?.handleTap(
                at: location,
                in: arView,
                roomId: UUID(),   // resolved by coordinator
                objectType: objectType,
                label: label
            )
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Coordinator

    final class Coordinator {
        @Binding var room: RoomCaptureV2
        let objectType: PinnedObjectType
        let label: String?
        let sessionCoordinator: ScanSessionCoordinator
        let dismiss: DismissAction

        init(room: Binding<RoomCaptureV2>,
             objectType: PinnedObjectType,
             label: String?,
             sessionCoordinator: ScanSessionCoordinator,
             dismiss: DismissAction) {
            _room = room
            self.objectType = objectType
            self.label = label
            self.sessionCoordinator = sessionCoordinator
            self.dismiss = dismiss
        }

        func handlePinPlaced(_ pin: SpatialPinV1) {
            // Re-assign pin with correct roomId
            let correctedPin = SpatialPinV1(
                id: pin.id,
                roomId: room.id,
                positionX: pin.positionX,
                positionY: pin.positionY,
                positionZ: pin.positionZ,
                objectType: pin.objectType,
                label: pin.label
            )
            room.pinnedObjects.append(correctedPin)
            sessionCoordinator.addPin(correctedPin)
            sessionCoordinator.setActivePin(correctedPin)
            dismiss()
        }
    }
}

#else

// MARK: - Simulator / Linux stub

struct SpatialPinARView: View {
    @Binding var room: RoomCaptureV2
    let objectType: PinnedObjectType
    let label: String?
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 60)).foregroundStyle(.orange)
            Text("Tap to Pin").font(.title2.bold())
            Text("AR spatial pinning requires a LiDAR-equipped device. Tap 'Simulate' to add a test pin.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Simulate Pin") {
                let pin = SpatialPinV1(
                    roomId: room.id,
                    positionX: 1.0, positionY: 1.2, positionZ: 0.5,
                    objectType: objectType,
                    label: label
                )
                room.pinnedObjects.append(pin)
                coordinator.addPin(pin)
                coordinator.setActivePin(pin)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

#endif
