import SwiftUI
import Combine

/// Logger app for monitoring system logs across all sub-apps
class LogsApp: SubApp {
    let id = "logs"
    let name = "Logs"
    let iconName = "doc.text.fill"
    let themeColor = Color.blue

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(LogsView())
    }

    func onInit() async {
        // Ensure LogStorage is initialized
        LogStorage.shared.initialize()
    }
}
