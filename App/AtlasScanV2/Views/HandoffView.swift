/// HandoffView — Shows the `VisitReadinessV1` gate and the "Handoff to Mind" button.
///
/// The button is disabled until all 7 readiness flags are satisfied.

import SwiftUI
import AtlasScanCore

struct HandoffView: View {

    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Readiness summary ────────────────────────────────────
                    readinessCard

                    // ── Session summary ──────────────────────────────────────
                    sessionSummaryCard

                    // ── Handoff button ───────────────────────────────────────
                    handoffButton

                    if let error = coordinator.handoffError {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Handoff to Mind")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: Readiness card

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: coordinator.readiness.isReady
                      ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(coordinator.readiness.isReady ? .green : .orange)
                    .font(.title2)
                Text(coordinator.readiness.isReady ? "Ready to hand off" : "Not yet ready")
                    .font(.headline)
            }

            ForEach(ReadinessFlag.all, id: \.title) { flag in
                ReadinessFlagRow(
                    title: flag.title,
                    passed: flag.value(coordinator.readiness)
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Session summary card

    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Summary")
                .font(.headline)

            LabeledContent("Version", value: coordinator.session.version)
            LabeledContent("Visit ID",
                           value: String(coordinator.session.visitId.uuidString.prefix(8)) + "…")
            LabeledContent("Rooms",     value: "\(coordinator.session.rooms.count)")
            LabeledContent("Photos",    value: "\(coordinator.session.photos.count)")
            LabeledContent("Transcripts", value: "\(coordinator.session.transcripts.count)")
            LabeledContent("QA Flags",  value: "\(coordinator.session.qaFlags.count)")

            if let size = ScanToMindPayloadEncoder.payloadSize(for: coordinator.session) {
                LabeledContent("Payload Size",
                               value: ByteCountFormatter.string(
                                fromByteCount: Int64(size), countStyle: .file
                               ))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Handoff button

    private var handoffButton: some View {
        VStack(spacing: 8) {
            Button {
                coordinator.handOffToMind()
            } label: {
                Label("Hand Off to Atlas Mind", systemImage: "arrow.up.forward.app.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!coordinator.readiness.isReady)
            .tint(.blue)

            if !coordinator.readiness.isReady {
                Text(coordinator.readiness.unmetConditions.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Readiness flag row

private struct ReadinessFlagRow: View {
    let title: String
    let passed: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(passed ? .green : .secondary)
            Text(title)
                .font(.callout)
                .foregroundStyle(passed ? .primary : .secondary)
            Spacer()
        }
    }
}

// MARK: - Readiness flag descriptors

private struct ReadinessFlag {
    let title: String
    let value: (VisitReadinessV1) -> Bool

    static let all: [ReadinessFlag] = [
        ReadinessFlag(title: "Rooms captured",       value: \.hasRooms),
        ReadinessFlag(title: "Photos attached",      value: \.hasPhotos),
        ReadinessFlag(title: "Boiler details",       value: \.hasBoilerDetails),
        ReadinessFlag(title: "Flue details",         value: \.hasFlueDetails),
        ReadinessFlag(title: "Clearance checked",    value: \.hasClearanceCheck),
        ReadinessFlag(title: "Voice transcripts",    value: \.hasTranscripts),
        ReadinessFlag(title: "Property address",     value: \.hasPropertyAddress),
    ]
}
