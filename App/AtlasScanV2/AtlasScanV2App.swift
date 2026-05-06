/// AtlasScanV2App — SwiftUI application entry point.
///
/// Platform: iOS 17+
/// Requires: LiDAR-capable device (iPhone 12 Pro or later / iPad Pro M1 or later)
/// Frameworks: RoomPlan, ARKit, SceneKit, SwiftUI
///
/// Deep-link schemes handled:
///   atlasscan://recall?visitId=<UUID>  — recalls an existing visit from Mind

import SwiftUI

@main
struct AtlasScanV2App: App {

    @StateObject private var coordinator = ScanSessionCoordinator()
    @StateObject private var recallClient = MindRecallClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(recallClient)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    // MARK: Deep-link dispatch

    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        // atlasscan://recall?visitId=<UUID>
        if url.scheme == "atlasscan", url.host == "recall" {
            guard
                let visitIdString = components.queryItems?.first(where: { $0.name == "visitId" })?.value,
                let visitId = UUID(uuidString: visitIdString)
            else { return }

            Task {
                do {
                    let session = try await recallClient.recall(visitId: visitId)
                    await MainActor.run {
                        coordinator.loadRecalledSession(session)
                    }
                } catch {
                    // recallClient.recallError is already set by MindRecallClient
                }
            }
        }
    }
}

// MARK: - ContentView (root navigation)

struct ContentView: View {
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @EnvironmentObject var recallClient: MindRecallClient

    var body: some View {
        NavigationStack {
            PropertyMapView()
        }
        .sheet(isPresented: $coordinator.showHandoff) {
            HandoffView()
                .environmentObject(coordinator)
        }
        .overlay(alignment: .center) {
            if recallClient.isRecalling {
                RecallProgressOverlay()
            }
        }
        .alert(
            "Recall Failed",
            isPresented: Binding(
                get: { recallClient.recallError != nil },
                set: { if !$0 { recallClient.recallError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: {
                Text(recallClient.recallError?.localizedDescription ?? "Unknown error")
            }
        )
    }
}

// MARK: - Recall progress overlay

private struct RecallProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                Text("Recalling visit…")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
