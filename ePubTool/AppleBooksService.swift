import Foundation
import SQLite3

nonisolated struct LibraryBook: Identifiable, Sendable {
    let url: URL
    let title: String
    let author: String
    let format: String
    let isDirectory: Bool
    let searchKey: String
    var id: String { url.path }

    var exportFilename: String {
        func clean(_ text: String) -> String {
            let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
            return text.precomposedStringWithCanonicalMapping
                .components(separatedBy: forbidden).joined(separator: " ")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
        let bookTitle = clean(title)
        let bookAuthor = clean(author)
        let fallbackTitle = clean(url.deletingPathExtension().lastPathComponent)
        var stem = (bookTitle.isEmpty ? (fallbackTitle.isEmpty ? "Untitled" : fallbackTitle) : bookTitle)
            + " - " + (bookAuthor.isEmpty ? "Unknown Author" : bookAuthor)
        // Leave room for the extension within filesystem filename limits, preserving Unicode characters.
        while stem.utf8.count > 240 { stem.removeLast() }
        return stem.trimmingCharacters(in: .whitespaces) + "." + format.lowercased()
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined()
    }
}

actor AppleBooksService {
    private let repacker = RepackService()

    private struct CatalogEntry {
        let path: String
        let title: String
        let author: String
    }

    func scan(_ folder: URL, database: URL? = nil,
              log: @Sendable (String, String) async -> Void = { _, _ in },
              update: @Sendable ([LibraryBook], Int) async -> Void) async throws {
        let databaseURL = try database ?? discoverDatabase()
        await log("INFO", String(localized: "Reading catalog: \(databaseURL.path)"))
        let sql = "SELECT ZPATH, ZTITLE, ZAUTHOR FROM ZBKLIBRARYASSET"
        await log("EXEC", sql)
        let entries = try readCatalog(databaseURL, sql: sql)

        // Enumerate filenames once to map catalog records to the selected source folder.
        // No EPUB, OPF, plist or PDF content is opened during listing.
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter { ["epub", "pdf"].contains($0.pathExtension.lowercased()) }
        var byPath: [String: CatalogEntry] = [:]
        var byName: [String: [CatalogEntry]] = [:]
        for entry in entries {
            guard !entry.path.isEmpty else { continue }
            let url = entry.path.hasPrefix("file:") ? URL(string: entry.path) : URL(fileURLWithPath: entry.path)
            guard let url else { continue }
            byPath[url.standardizedFileURL.path.precomposedStringWithCanonicalMapping] = entry
            byName[url.lastPathComponent.precomposedStringWithCanonicalMapping, default: []].append(entry)
        }
        var unmatched = 0
        var books: [LibraryBook] = []
        for url in urls {
            try Task.checkCancellation()
            let matches = byName[url.lastPathComponent.precomposedStringWithCanonicalMapping] ?? []
            let entry = byPath[url.standardizedFileURL.path.precomposedStringWithCanonicalMapping]
                ?? (matches.count == 1 ? matches.first : nil)
            if entry == nil { unmatched += 1 }
            let title = entry.flatMap { $0.title.isEmpty ? nil : $0.title }
                ?? url.deletingPathExtension().lastPathComponent
            let author = entry?.author ?? ""
            books.append(LibraryBook(
                url: url, title: title, author: author, format: url.pathExtension.uppercased(),
                isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                searchKey: LibraryBook.normalize(title + " " + author + " " + url.lastPathComponent)
            ))
        }
        books.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        await log("INFO", String(localized: "Read \(entries.count) catalog rows; matched \(books.count - unmatched)/\(books.count) source files."))
        if unmatched > 0 {
            await log("WARNING", String(localized: "\(unmatched) files have no unambiguous catalog match; showing filenames without reading file metadata."))
        }
        await update(books, books.count)
    }

    private func discoverDatabase() throws -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary"),
            home.appendingPathComponent("Library/Containers/com.apple.BKAgentService/Data/Documents")
        ]
        var failures: [String] = []
        for root in roots {
            var candidates: [URL] = []
            var discoveryError: Error?
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in discoveryError = error; return false }
            ) else { continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                if url.lastPathComponent.hasPrefix("BKLibrary") && url.pathExtension == "sqlite" {
                    candidates.append(url)
                }
            }
            if let error = discoveryError { failures.append(error.localizedDescription) }
            // A migration may leave multiple stores; prefer the most recently modified store.
            candidates.sort {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            if let url = candidates.first { return url }
        }
        throw RepackError.invalid(String(localized: "Cannot locate an accessible BKLibrary*.sqlite. Check that Apple Books is installed and ePubTool has Full Disk Access, then refresh. \(failures.joined(separator: " "))"))
    }

    private func readCatalog(_ url: URL, sql: String) throws -> [CatalogEntry] {
        var database: OpaquePointer?
        // Read-only access preserves Apple Books data and reads committed WAL changes normally.
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { if let database { sqlite3_close(database) } }
        guard result == SQLITE_OK, let database else {
            throw RepackError.invalid(String(localized: "Cannot open Books database read-only: \(url.path). Check file access permissions."))
        }
        sqlite3_busy_timeout(database, 2000)
        func message() -> String { String(cString: sqlite3_errmsg(database)) }
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(ZBKLIBRARYASSET)", -1, &schema, nil) == SQLITE_OK else {
            throw RepackError.invalid(message())
        }
        defer { sqlite3_finalize(schema) }
        var columns: Set<String> = []
        var step = sqlite3_step(schema)
        while step == SQLITE_ROW {
            if let name = sqlite3_column_text(schema, 1) { columns.insert(String(cString: name).uppercased()) }
            step = sqlite3_step(schema)
        }
        guard step == SQLITE_DONE else { throw RepackError.invalid(message()) }
        guard Set(["ZPATH", "ZTITLE", "ZAUTHOR"]).isSubset(of: columns) else {
            throw RepackError.invalid(String(localized: "Unsupported Books database schema. Expected ZBKLIBRARYASSET with ZPATH, ZTITLE and ZAUTHOR; found: \(columns.sorted().joined(separator: ", "))."))
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RepackError.invalid(message())
        }
        defer { sqlite3_finalize(statement) }
        func text(_ column: Int32) -> String {
            guard let value = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: value)
        }
        var entries: [CatalogEntry] = []
        step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            try Task.checkCancellation()
            entries.append(CatalogEntry(path: text(0), title: text(1), author: text(2)))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw RepackError.invalid(message()) }
        return entries
    }

    func export(_ book: LibraryBook, to folder: URL,
                progress: @Sendable (String) async -> Void = { _ in },
                log: @Sendable (String, String) async -> Void) async throws -> URL {
        let source = book.url.resolvingSymlinksInPath().standardizedFileURL
        let targetFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        guard targetFolder != source.deletingLastPathComponent(),
              targetFolder != source, !targetFolder.path.hasPrefix(source.path + "/") else {
            throw RepackError.invalid(String(localized: "Choose an export folder outside the Apple Books source folder."))
        }
        await progress(String(localized: "Checking iCloud availability: \(book.title)…"))
        try await ensureDownloaded(book.url, title: book.title, progress: progress, log: log)
        await progress(String(localized: "Exporting: \(book.title)…"))
        if book.isDirectory {
            return try await repacker.repack(source: book.url, destination: folder, outputFilename: book.exportFilename, log: log)
        }
        let fm = FileManager.default
        let output = folder.appendingPathComponent(book.exportFilename)
        let temporary = folder.appendingPathComponent(".ePubTool-" + UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temporary) }
        let staged = temporary.appendingPathComponent(book.url.lastPathComponent)
        try fm.copyItem(at: book.url, to: staged)
        if fm.fileExists(atPath: output.path) {
            let values = try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw RepackError.invalid(String(localized: "Output is not a regular file: \(output.path)"))
            }
            _ = try fm.replaceItemAt(output, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: output)
        }
        await log("SUCCESS", String(localized: "Exported original \(book.format): \(output.path)"))
        return output
    }

    /// Runs on this service actor. Sleeping between checks keeps the UI responsive.
    private func ensureDownloaded(
        _ originalURL: URL, title: String,
        progress: @Sendable (String) async -> Void,
        log: @Sendable (String, String) async -> Void
    ) async throws {
        try Task.checkCancellation()
        var url = originalURL
        url.removeAllCachedResourceValues()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey
        ]
        var values = try url.resourceValues(forKeys: keys)
        if values.ubiquitousItemDownloadingStatus == .notDownloaded {
            await progress(String(localized: "Downloading from iCloud: \(title)…"))
            await log("INFO", String(localized: "Waiting for iCloud download: \(url.path)"))
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            let deadline = ContinuousClock.now.advanced(by: .seconds(300))
            while values.ubiquitousItemDownloadingStatus == .notDownloaded {
                try Task.checkCancellation()
                if let error = values.ubiquitousItemDownloadingError { throw error }
                guard ContinuousClock.now < deadline else {
                    throw RepackError.invalid(String(localized: "iCloud download timed out for \(title). Check your connection and try exporting again."))
                }
                try await Task.sleep(for: .milliseconds(500))
                url.removeAllCachedResourceValues()
                values = try url.resourceValues(forKeys: keys)
            }
            if let error = values.ubiquitousItemDownloadingError { throw error }
            await log("INFO", String(localized: "iCloud download ready: \(url.path)"))
        }
        // Unpacked EPUB folders can be local while individual chapters or images are not.
        if values.isDirectory == true && values.isSymbolicLink != true {
            let children = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Array(keys)
            )
            for child in children {
                try await ensureDownloaded(child, title: title, progress: progress, log: log)
            }
        }
    }

    func prepareEdit(_ book: LibraryBook,
                     log: @Sendable (String, String) async -> Void) async throws -> URL {
        let fm = FileManager.default
        let folder = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ePubTool/Edited Books/\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return try await export(book, to: folder, log: log)
    }
}
