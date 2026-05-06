/// OutdoorFlueModeView — Dedicated UI for capturing ExternalClearanceSceneV1.
///
/// The engineer:
/// 1. Pins the "Flue Terminal" exit point
/// 2. Pins any "Nearby Openings" (windows / doors / air bricks)
/// 3. The app measures 3D distances and generates a structured compliance report

import SwiftUI
import AtlasScanCore

struct OutdoorFlueModeView: View {

    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var flueTerminalPin: SpatialPinV1?
    @State private var nearbyOpenings: [SpatialPinV1] = []
    @State private var showPinAR = false
    @State private var pinTargetType: PinnedObjectType = .flueTerminal
    @State private var report: OutdoorFlueClearanceReportV1?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Explainer ────────────────────────────────────────────
                    explainerBanner

                    // ── Flue terminal ────────────────────────────────────────
                    flueTerminalSection

                    // ── Nearby openings ──────────────────────────────────────
                    nearbyOpeningsSection

                    // ── Generated report ─────────────────────────────────────
                    if let r = report {
                        clearanceReportSection(r)
                    }

                    // ── Generate report button ────────────────────────────────
                    if flueTerminalPin != nil && !nearbyOpenings.isEmpty {
                        Button("Generate Clearance Report") {
                            report = buildReport()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle("Outdoor Flue Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPinAR) {
            OutdoorFlueARCaptureView(
                targetType: pinTargetType,
                onCapture: { pin in
                    if pin.objectType == .flueTerminal {
                        flueTerminalPin = pin
                    } else {
                        nearbyOpenings.append(pin)
                    }
                }
            )
        }
    }

    // MARK: Subviews

    private var explainerBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Outdoor Flue Clearances").font(.subheadline.bold())
                Text("Pin the flue terminal exit, then pin each nearby opening (window, door, air brick). The app will calculate 3D distances and check against Building Regulations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var flueTerminalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flue Terminal").font(.headline)
            if let pin = flueTerminalPin {
                PinLocationRow(pin: pin)
                Button("Re-capture") {
                    pinTargetType = .flueTerminal
                    showPinAR = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else {
                Button {
                    pinTargetType = .flueTerminal
                    showPinAR = true
                } label: {
                    Label("Pin Flue Terminal Exit", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var nearbyOpeningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nearby Openings").font(.headline)
                Spacer()
                Button {
                    pinTargetType = .nearbyOpening
                    showPinAR = true
                } label: {
                    Label("Add Opening", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            if nearbyOpenings.isEmpty {
                Text("No openings added yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(nearbyOpenings) { pin in
                    PinLocationRow(pin: pin)
                }
            }
        }
    }

    @ViewBuilder
    private func clearanceReportSection(_ r: OutdoorFlueClearanceReportV1) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clearance Report").font(.headline)
            ForEach(r.openingDistances) { measurement in
                HStack {
                    Image(systemName: measurement.passesBuildingRegs
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(measurement.passesBuildingRegs ? .green : .red)
                    Text(measurement.openingType.rawValue.capitalized)
                    Spacer()
                    Text(String(format: "%.3f m", measurement.distanceM))
                        .font(.callout.monospacedDigit())
                    Text(measurement.passesBuildingRegs ? "✓ Pass" : "✗ Fail")
                        .font(.caption.bold())
                        .foregroundStyle(measurement.passesBuildingRegs ? .green : .red)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Build report

    private func buildReport() -> OutdoorFlueClearanceReportV1? {
        guard let flue = flueTerminalPin else { return nil }

        let distances: [OpeningDistanceMeasurement] = nearbyOpenings.map { opening in
            let dx = opening.positionX - flue.positionX
            let dy = opening.positionY - flue.positionY
            let dz = opening.positionZ - flue.positionZ
            let dist = (dx*dx + dy*dy + dz*dz).squareRoot()

            // Determine opening type from label or default to .window
            let openingType: OpeningType = opening.label.flatMap {
                OpeningType(rawValue: $0.lowercased())
            } ?? .window

            return OpeningDistanceMeasurement(
                openingType: openingType,
                distanceM: dist,
                minimumRequiredM: 0.300
            )
        }

        let r = OutdoorFlueClearanceReportV1(
            visitId: coordinator.session.visitId,
            flueTerminalPositionX: flue.positionX,
            flueTerminalPositionY: flue.positionY,
            flueTerminalPositionZ: flue.positionZ,
            openingDistances: distances
        )

        // Emit QA flag if any fails
        let hasConflict = distances.contains { !$0.passesBuildingRegs }
        if hasConflict {
            let flagDetail = "One or more nearby openings are within 300 mm of the flue terminal."
            coordinator.emitQAFlag(QAFlagV1(type: .flueConflict, detail: flagDetail))
        }

        return r
    }
}

// MARK: - Pin location row

private struct PinLocationRow: View {
    let pin: SpatialPinV1

    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text(pin.label ?? pin.objectType.rawValue.capitalized)
                    .font(.subheadline)
                Text(String(format: "X: %.3f  Y: %.3f  Z: %.3f",
                            pin.positionX, pin.positionY, pin.positionZ))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Placeholder AR capture view (implemented in AR/ folder)

/// Stub view that represents the AR spatial capture flow.
/// Replaced at runtime by `SpatialPinARView` once the RoomPlan session is active.
private struct OutdoorFlueARCaptureView: View {
    let targetType: PinnedObjectType
    let onCapture: (SpatialPinV1) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit").font(.largeTitle).foregroundStyle(.blue)
            Text("AR Capture")
                .font(.headline)
            Text("Point at the \(targetType.rawValue) location and tap to pin.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Simulate Capture") {
                let pin = SpatialPinV1(
                    roomId: UUID(),
                    positionX: Double.random(in: 0...5),
                    positionY: Double.random(in: 0...2.4),
                    positionZ: Double.random(in: 0...5),
                    objectType: targetType
                )
                onCapture(pin)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
