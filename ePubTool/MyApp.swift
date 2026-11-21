import AppKit
import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Settings {
            ExportSettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let identifiers = Set([Bundle.main.bundleIdentifier, "com.phamquangbaoplus.ePubTool"].compactMap { $0 })
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = identifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }.filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        for instance in otherInstances {
            instance.terminate()
        }

        // Termination is asynchronous; wait before opening the new instance.
        let deadline = Date().addingTimeInterval(3)
        while otherInstances.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        for instance in otherInstances where !instance.isTerminated {
            instance.forceTerminate()
        }
        let forceDeadline = Date().addingTimeInterval(3)
        while otherInstances.contains(where: { !$0.isTerminated }) && Date() < forceDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if otherInstances.contains(where: { !$0.isTerminated }) {
            NSApplication.shared.terminate(nil)
        }
    }
}
