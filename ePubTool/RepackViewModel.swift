import AppKit
import Observation

struct BookJob: Identifiable {
    let id = UUID()
    let source: URL
    var status = "Ready"
    var output: URL?
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let level: String
    let message: String

    var text: String { "[\(date.formatted(date: .omitted, time: .standard))] [\(level)] \(message)" }
}

@MainActor
@Observable
final class RepackViewModel {
    var jobs: [BookJob] = []
    var logs: [LogEntry] = []
    var destination: URL?
    var isRunning = false
    var completed = 0
    var summary = "Choose unpacked Apple Books folders to begin."
    private let service = RepackService()

    func log(_ level: String, _ message: String) {
        logs.append(LogEntry(level: level, message: message))
    }

    func add(_ urls: [URL]) {
        guard !isRunning else { return }
        for url in urls {
            guard url.isFileURL else { continue }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                log("ERROR", "Select an unpacked directory, not a compressed file: \(url.path)")
                continue
            }
            guard !jobs.contains(where: { $0.source.standardizedFileURL == url.standardizedFileURL }) else { continue }
            jobs.append(BookJob(source: url))
            log("INFO", "Selected directory: \(url.path)")
        }
    }

    func chooseSources() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Select unpacked ePub folders (including folders ending in .epub)."
        if await panel.begin() == .OK { add(panel.urls) }
    }

    func chooseDestination() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Output Folder"
        if await panel.begin() == .OK { destination = panel.url }
    }

    func run() async {
        guard !isRunning, !jobs.isEmpty, let destination else { return }
        isRunning = true
        completed = 0
        defer { isRunning = false }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        var successes = 0
        for index in jobs.indices {
            jobs[index].status = "Repacking…"
            jobs[index].output = nil
            summary = "Repacking \(index + 1) of \(jobs.count)…"
            do {
                let output = try await service.repack(source: jobs[index].source, destination: destination) { [weak self] level, message in
                    await self?.log(level, message)
                }
                jobs[index].output = output
                jobs[index].status = "Completed"
                successes += 1
            } catch {
                jobs[index].status = "Failed: \(error.localizedDescription)"
                log("ERROR", "\(jobs[index].source.lastPathComponent): \(error.localizedDescription)")
            }
            completed += 1
        }
        summary = "\(successes) succeeded · \(jobs.count - successes) failed"
        log("INFO", summary)
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logs.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
