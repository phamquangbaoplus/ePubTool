import SwiftUI
import Foundation

nonisolated enum ExportSettings {
    static let concurrencyKey = "exportConcurrency"
    static var maximumConcurrency: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }
    static var defaultConcurrency: Int { min(4, maximumConcurrency) }

    static func clamped(_ value: Int) -> Int {
        min(maximumConcurrency, max(1, value))
    }

    static func concurrency(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: concurrencyKey) != nil else { return defaultConcurrency }
        return clamped(defaults.integer(forKey: concurrencyKey))
    }
}

struct ExportSettingsView: View {
    @AppStorage(ExportSettings.concurrencyKey) private var concurrency = ExportSettings.defaultConcurrency

    var body: some View {
        Form {
            Section("Export") {
                Stepper("Concurrent books: \(ExportSettings.clamped(concurrency))",
                        value: $concurrency, in: 1...ExportSettings.maximumConcurrency)
                Text("Maximum: \(ExportSettings.maximumConcurrency), based on available logical CPU cores.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Changes apply to the next export. Choose 1 to export sequentially.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            concurrency = ExportSettings.clamped(concurrency)
        }
    }
}
