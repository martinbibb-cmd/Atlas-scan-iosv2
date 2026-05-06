/// AtlasScanV2App — SwiftUI application entry point.
///
/// Platform: iOS 17+
/// Requires: LiDAR-capable device (iPhone 12 Pro or later / iPad Pro M1 or later)
/// Frameworks: RoomPlan, ARKit, SceneKit, SwiftUI

import SwiftUI

@main
struct AtlasScanV2App: App {

    @StateObject private var coordinator = ScanSessionCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}

// MARK: - ContentView (root navigation)

struct ContentView: View {
    @EnvironmentObject var coordinator: ScanSessionCoordinator

    var body: some View {
        NavigationStack {
            PropertyMapView()
        }
        .sheet(isPresented: $coordinator.showHandoff) {
            HandoffView()
                .environmentObject(coordinator)
        }
    }
}
