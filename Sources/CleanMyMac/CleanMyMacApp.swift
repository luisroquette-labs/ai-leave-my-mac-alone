import SwiftUI

@main
struct CleanMyMacApp: App {
    @StateObject private var monitor = StorageMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Text(monitor.menuBarTitle)
                .monospacedDigit()
                .accessibilityLabel("AI, Leave My Mac Alone!: \(monitor.menuBarTitle) do armazenamento usado")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(monitor: monitor)
        }
    }
}
