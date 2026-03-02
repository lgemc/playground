import SwiftUI
import Combine

/// Queue monitoring and debugging app.
/// Provides visibility into the message queue system.
class QueuesApp: SubApp {
    let id = "queues"
    let name = "Queues"
    let iconName = "tray.2.fill"
    let themeColor = Color.purple

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(QueueListView())
    }

    func onInit() async {
        // Ensure QueueService is initialized
        QueueService.shared.initialize()
    }
}
