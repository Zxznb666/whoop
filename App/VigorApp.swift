import SwiftUI
import VigorHealth

#if targetEnvironment(simulator)
private let initialSource = DataSourceKind.synthetic
#else
private let initialSource = DataSourceKind.live
#endif

@main
struct VigorApp: App {
    @State private var model = LabModel(source: initialSource)

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LabRootView(model: model)
            }
        }
    }
}
