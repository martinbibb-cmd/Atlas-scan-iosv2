/// GhostBoxARView — SwiftUI wrapper that shows the AR clearance ghost box
/// and runs the Möller–Trumbore mesh-intersection check.
///
/// Presents a full-screen ARView (RealityKit/SceneKit) with:
/// - Semi-transparent SCNBox at the boiler pin location
/// - Live conflict state indicator (green = clear, red = conflict)
/// - "Run Check" button to fire the MT collision test

import SwiftUI
import AtlasScanCore

#if canImport(SceneKit) && canImport(ARKit)
import SceneKit
import ARKit

struct GhostBoxARView: UIViewControllerRepresentable {

    let pin: SpatialPinV1
    @Binding var room: RoomCaptureV2
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> GhostBoxViewController.Coordinator {
        GhostBoxViewController.Coordinator(pin: pin, room: $room, sessionCoordinator: coordinator)
    }

    func makeUIViewController(context: Context) -> GhostBoxViewController {
        let vc = GhostBoxViewController(pin: pin, room: room)
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: GhostBoxViewController, context: Context) {}
}

// MARK: - GhostBoxViewController

final class GhostBoxViewController: UIViewController, ARSCNViewDelegate {

    let pin: SpatialPinV1
    let room: RoomCaptureV2
    var coordinator: Coordinator?

    private var sceneView: ARSCNView!
    private var ghostRenderer = GhostBoxRenderer()
    private let registry = HardwareRegistryV1.shared
    private var statusLabel: UILabel!

    init(pin: SpatialPinV1, room: RoomCaptureV2) {
        self.pin = pin
        self.room = room
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
        setupUI()
        addGhostBox()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        sceneView.session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: Setup

    private func setupSceneView() {
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)
    }

    private func setupUI() {
        // Status label
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Point at the boiler and tap Run Check"
        statusLabel.textAlignment = .center
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .callout)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        view.addSubview(statusLabel)

        // Run check button
        let btn = UIButton(type: .system)
        btn.setTitle("Run Clearance Check", for: .normal)
        btn.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        btn.backgroundColor = UIColor.systemBlue
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 12
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(runCheck), for: .touchUpInside)
        view.addSubview(btn)

        // Close button
        let closeBtn = UIButton(type: .close)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(equalToConstant: 44),

            btn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            btn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            btn.heightAnchor.constraint(equalToConstant: 50),

            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func addGhostBox() {
        guard let specId = pin.hardwareSpecId,
              let spec = HardwareRegistryV1.shared.allSpecs(ofType: .boiler)
                  .first(where: { $0.id == specId })
              ?? HardwareRegistryV1.shared.allSpecs(ofType: .heatPump)
                  .first(where: { $0.id == specId })
        else {
            statusLabel.text = "No hardware spec linked — link a boiler model first"
            return
        }

        let ghostNode = ghostRenderer.buildGhostBoxNode(for: spec)
        ghostNode.position = SCNVector3(
            Float(pin.positionX), Float(pin.positionY), Float(pin.positionZ)
        )
        sceneView.scene.rootNode.addChildNode(ghostNode)
    }

    // MARK: Actions

    @objc private func runCheck() {
        guard let specId = pin.hardwareSpecId,
              let spec = HardwareRegistryV1.shared.allSpecs(ofType: .boiler)
                  .first(where: { $0.id == specId })
              ?? HardwareRegistryV1.shared.allSpecs(ofType: .heatPump)
                  .first(where: { $0.id == specId })
        else { return }

        statusLabel.text = "Checking clearances…"

        let meshAnchors = sceneView.session.currentFrame?.anchors
            .compactMap { $0 as? ARMeshAnchor } ?? []

        let pinWorldPos = SCNVector3(
            Float(pin.positionX), Float(pin.positionY), Float(pin.positionZ)
        )

        Task { @MainActor in
            let flag = await ghostRenderer.checkClearances(
                spec: spec,
                pinWorldPos: pinWorldPos,
                arMeshAnchors: meshAnchors,
                roomId: room.id
            )
            coordinator?.sessionCoordinator.emitQAFlag(flag)
            statusLabel.text = flag.type == .clearanceConflict
                ? "⚠ CONFLICT: \(flag.detail)"
                : "✓ Clearances OK"
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: Coordinator

    final class Coordinator {
        let pin: SpatialPinV1
        @Binding var room: RoomCaptureV2
        let sessionCoordinator: ScanSessionCoordinator

        init(pin: SpatialPinV1, room: Binding<RoomCaptureV2>, sessionCoordinator: ScanSessionCoordinator) {
            self.pin = pin
            _room = room
            self.sessionCoordinator = sessionCoordinator
        }
    }
}

#else

// MARK: - Stub for non-iOS builds

struct GhostBoxARView: View {
    let pin: SpatialPinV1
    @Binding var room: RoomCaptureV2
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 60)).foregroundStyle(.blue)
            Text("Ghost Box AR")
                .font(.title2.bold())
            Text("AR clearance checking requires a LiDAR-equipped iPhone or iPad running iOS 17+.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Simulate PASS") {
                coordinator.emitQAFlag(QAFlagV1(
                    type: .clearancePass, roomId: room.id,
                    detail: "Simulated: No mesh conflict detected."
                ))
                dismiss()
            }
            .buttonStyle(.borderedProminent).tint(.green)
            Button("Simulate CONFLICT") {
                coordinator.emitQAFlag(QAFlagV1(
                    type: .clearanceConflict, roomId: room.id,
                    detail: "Simulated: Wall 2 is within clearance zone."
                ))
                dismiss()
            }
            .buttonStyle(.borderedProminent).tint(.red)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

#endif
