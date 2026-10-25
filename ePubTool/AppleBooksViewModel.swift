import AppKit
import Observation

@MainActor
@Observable
final class AppleBooksViewModel {
    var folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~com~apple~iBooks/Documents")
    var books: [LibraryBook] = []
    var filtered: [LibraryBook] = []
    var selection: Set<String> = []
    var query = ""
    var isLoading = false
    var isWorking = false
    var exportStartedAt: Date?
    var status = "Ready to load Apple Books automatically."
    var completed = 0
    var total = 0
    var lastExport: URL?
    var editedCopies: [String: URL] = [:]
    private let service = AppleBooksService()
    private var scanTask: Task<Void, Never>?
    private var editors: [UUID: Process] = [:]
    private var didLoad = false

    func loadIfNeeded(console: RepackViewModel) {
        guard !didLoad else { return }
        didLoad = true
        reload(console: console)
    }

    func reload(console: RepackViewModel) {
        guard !isLoading, !isWorking else { return }
        isLoading = true
        books = []
        filtered = []
        selection = []
        let folder = folder
        scanTask = Task {
            defer { isLoading = false }
            do {
                console.log("INFO", "Reading Apple Books: \(folder.path)")
                try await service.scan(folder, log: { level, message in
                    await console.log(level, message)
                }) { [weak self] books, total in
                    await self?.receive(books, total: total)
                }
                status = "Loaded \(books.count) books."
                console.log("SUCCESS", status)
            } catch is CancellationError {
                status = "Indexing stopped. \(books.count) books available."
            } catch {
                status = error.localizedDescription
                console.log("ERROR", "Cannot read library: \(error.localizedDescription). Check that Apple Books is installed and ePubTool has Full Disk Access.")
            }
        }
    }

    private func receive(_ books: [LibraryBook], total: Int) {
        self.books = books
        status = "Loaded catalog: \(total) of \(books.count)…"
        applyFilter()
    }

    func stopLoading() { scanTask?.cancel() }

    func applyFilter() {
        let key = LibraryBook.normalize(query)
        filtered = key.isEmpty ? books : books.filter { $0.searchKey.contains(key) }
        selection.formIntersection(Set(filtered.map(\.id)))
    }

    func export(_ items: [LibraryBook], console: RepackViewModel) async {
        guard !items.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        exportStartedAt = Date()
        defer { exportStartedAt = nil }
        total = items.count
        completed = 0
        var succeeded = 0
        // Distinct library items must not silently overwrite each other within a batch.
        var outputNames: Set<String> = []
        for book in items {
            let name = book.exportFilename
            do {
                guard outputNames.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                    throw RepackError.invalid("Duplicate export filename in this batch: \(name)")
                }
                status = "Exporting \(completed + 1)/\(total): \(book.title)"
                _ = try await service.export(book, to: destination, progress: { [weak self] message in
                    await self?.setExportStatus(message)
                }) { level, message in
                    await console.log(level, message)
                }
                succeeded += 1
            } catch {
                console.log("ERROR", "\(book.title): \(error.localizedDescription)")
            }
            completed += 1
        }
        lastExport = destination
        status = "Export: \(succeeded) succeeded · \(total - succeeded) failed."
        console.log("INFO", status)
    }

    private func setExportStatus(_ message: String) {
        status = message
    }

    var selectedEPUBs: [LibraryBook] {
        filtered.filter { selection.contains($0.id) && $0.format == "EPUB" }
    }

    func edit(_ book: LibraryBook, console: RepackViewModel) async {
        await edit([book], console: console)
    }

    func edit(_ items: [LibraryBook], console: RepackViewModel) async {
        let epubs = items.filter { $0.format == "EPUB" }
        guard !epubs.isEmpty, !isWorking, !isLoading else { return }
        isWorking = true
        defer { isWorking = false }
        total = epubs.count
        completed = 0
        var succeeded = 0
        for book in epubs {
            do {
                try await openEditor(book, console: console)
                succeeded += 1
            } catch {
                console.log("ERROR", "\(book.title): \(error.localizedDescription)")
            }
            completed += 1
        }
        status = "Edit: \(succeeded) opened · \(total - succeeded) failed."
        console.log("INFO", status)
    }

    private func openEditor(_ book: LibraryBook, console: RepackViewModel) async throws {
        let executable = URL(fileURLWithPath: "/Applications/calibre.app/Contents/MacOS/ebook-edit")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RepackError.invalid("Calibre ebook-edit was not found in /Applications/calibre.app.")
        }
        status = "Preparing editable copy: \(book.title)…"
        let copy: URL
        if let existing = editedCopies[book.id], FileManager.default.fileExists(atPath: existing.path) {
            copy = existing
        } else {
            copy = try await service.prepareEdit(book) { level, message in await console.log(level, message) }
            editedCopies[book.id] = copy
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = [copy.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let id = UUID()
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor in
                self?.editors[id] = nil
                if code != 0 { console.log("ERROR", "Calibre exited with status \(code).") }
            }
        }
        console.log("EXEC", "\(executable.path) \(String(reflecting: copy.path))")
        try process.run()
        editors[id] = process
        status = "Opened editable copy in Calibre."
        console.log("INFO", "Edits are saved in: \(copy.path). Apple Books originals are unchanged.")
    }
}
