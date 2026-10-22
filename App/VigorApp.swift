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
                // 分享面板或文件 App 中的“用元气打开”（M6 §4.2）
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "fit" else { return }
                    Task { _ = await RideImportCoordinator.importURLs([url]) }
                }
        }
    }
}
