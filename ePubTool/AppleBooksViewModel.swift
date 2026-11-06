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
    var status = String(localized: "Ready to load Apple Books automatically.")
    var completed = 0
    var total = 0
    var lastExport: URL?
    var editedCopies: [String: URL] = [:]
    private let service = AppleBooksService()
    private var scanTask: Task<Void, Never>?
    private var editors: [UUID: Process] = [:]
    private var didLoad = false

    func loadIfNeeded(console: ConsoleViewModel) {
        guard !didLoad else { return }
        didLoad = true
        reload(console: console)
    }

    func reload(console: ConsoleViewModel) {
        guard !isLoading, !isWorking else { return }
        isLoading = true
        books = []
        filtered = []
        selection = []
        let folder = folder
        scanTask = Task {
            defer { isLoading = false }
            do {
                console.log("INFO", String(localized: "Reading Apple Books: \(folder.path)"))
                try await service.scan(folder, log: { level, message in
                    await console.log(level, message)
                }) { [weak self] books, total in
                    await self?.receive(books, total: total)
                }
                status = String(localized: "Loaded \(books.count) books.")
                console.log("SUCCESS", status)
            } catch is CancellationError {
                status = String(localized: "Indexing stopped. \(books.count) books available.")
            } catch {
                status = error.localizedDescription
                console.log("ERROR", String(localized: "Cannot read library: \(error.localizedDescription). Check that Apple Books is installed and ePubTool has Full Disk Access."))
            }
        }
    }

    private func receive(_ books: [LibraryBook], total: Int) {
        self.books = books
        status = String(localized: "Loaded catalog: \(total) of \(books.count)…")
        applyFilter()
    }

    func stopLoading() { scanTask?.cancel() }

    func applyFilter() {
        let key = LibraryBook.normalize(query)
        filtered = key.isEmpty ? books : books.filter { $0.searchKey.contains(key) }
        selection.formIntersection(Set(filtered.map(\.id)))
    }

    // Main-actor isolation makes acquisition atomic across all app windows.
    private static var exportInProgress = false

    func export(_ items: [LibraryBook], fromSelection: Bool = false, console: ConsoleViewModel) async {
        guard !items.isEmpty, !isWorking, !isLoading else { return }
        guard !Self.exportInProgress else {
            status = String(localized: "An export is already running in another window. Wait for it to finish.")
            console.log("WARNING", status)
            return
        }
        Self.exportInProgress = true
        isWorking = true
        defer {
            isWorking = false
            Self.exportInProgress = false
        }
        let allSelected = fromSelection && !books.isEmpty
            && Set(items.map(\.id)) == Set(books.map(\.id))
            && selection == Set(books.map(\.id))
        var backup = false
        if allSelected {
            guard let selectedBackup = ExportOptionsDialog.chooseMode() else { return }
            backup = selectedBackup
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export Here")
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        let overwrite = ExportSettings.overwriteExistingFiles()
        let concurrencyLimit = ExportSettings.concurrency()
        exportStartedAt = Date()
        defer { exportStartedAt = nil }
        total = items.count
        completed = 0
        let selectedIDs = Set(items.map(\.id))
        let plan = BookExportItem.plan(for: books).filter { selectedIDs.contains($0.book.id) }
        if backup {
            do {
                status = String(localized: "Cleaning backup destination…")
                try await service.cleanBackupDestination(destination, items: plan) { level, message in
                    await console.log(level, message)
                }
            } catch {
                status = error.localizedDescription
                console.log("ERROR", status)
                return
            }
        }
        status = String(localized: "Exporting up to \(concurrencyLimit) books at a time…")
        let summary = await service.exportBatch(plan, to: destination, overwrite: overwrite,
                                                concurrencyLimit: concurrencyLimit,
                                                progress: { [weak self] count, message in
            await self?.setExportProgress(count, message: message)
        }, log: { level, message in
            await console.log(level, message)
        })
        lastExport = destination
        status = String(localized: "Export: \(summary.succeeded) succeeded · \(summary.skipped) skipped · \(summary.failed) failed.")
        console.log("INFO", status)
    }

    private func setExportProgress(_ count: Int, message: String) {
        completed = count
        status = message
    }

    var selectedEPUBs: [LibraryBook] {
        filtered.filter { selection.contains($0.id) && $0.format == "EPUB" }
    }

    func edit(_ book: LibraryBook, console: ConsoleViewModel) async {
        await edit([book], console: console)
    }

    func edit(_ items: [LibraryBook], console: ConsoleViewModel) async {
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
                console.log("ERROR", String(localized: "\(book.title): \(error.localizedDescription)"))
            }
            completed += 1
        }
        status = String(localized: "Edit: \(succeeded) opened · \(total - succeeded) failed.")
        console.log("INFO", status)
    }

    private func openEditor(_ book: LibraryBook, console: ConsoleViewModel) async throws {
        let executable = URL(fileURLWithPath: "/Applications/calibre.app/Contents/MacOS/ebook-edit")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RepackError.invalid(String(localized: "Calibre ebook-edit was not found in /Applications/calibre.app."))
        }
        status = String(localized: "Preparing editable copy: \(book.title)…")
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
                if code != 0 { console.log("ERROR", String(localized: "Calibre exited with status \(code).")) }
            }
        }
        console.log("EXEC", "\(executable.path) \(String(reflecting: copy.path))")
        try process.run()
        editors[id] = process
        status = String(localized: "Opened editable copy in Calibre.")
        console.log("INFO", String(localized: "Edits are saved in: \(copy.path). Apple Books originals are unchanged."))
    }
}
