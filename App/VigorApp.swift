import SwiftUI
import VigorHealth

@main
struct VigorApp: App {
    init() {
        AppBootstrap.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
