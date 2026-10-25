import AppKit
import Observation

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let level: String
    let message: String

    var text: String { "[\(date.formatted(date: .omitted, time: .standard))] [\(level)] \(message)" }
}

@MainActor
@Observable
final class ConsoleViewModel {
    var logs: [LogEntry] = []

    func log(_ level: String, _ message: String) {
        logs.append(LogEntry(level: level, message: message))
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logs.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
