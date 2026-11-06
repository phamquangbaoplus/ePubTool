import SwiftUI
import Foundation

nonisolated enum ExportSettings {
    static let concurrencyKey = "exportConcurrency"
    static let overwriteKey = "exportOverwriteExistingFiles"
    static let defaultOverwrite = true

    static func overwriteExistingFiles(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: overwriteKey) != nil else { return defaultOverwrite }
        return defaults.bool(forKey: overwriteKey)
    }

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

    @AppStorage(ExportSettings.overwriteKey) private var overwrite = ExportSettings.defaultOverwrite

    var body: some View {
        Form {
            Section("Export") {
                Toggle("Overwrite existing destination files", isOn: $overwrite)
                Text("When turned off, existing destination files are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
