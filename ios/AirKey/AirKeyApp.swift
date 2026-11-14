import SwiftUI

@main
struct AirKeyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(AK.accentText)
        }
    }
}
