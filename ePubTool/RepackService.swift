import Foundation

enum RepackError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// Owns disk and process work away from the main actor.
actor RepackService {
    func repack(source: URL, destination: URL, outputFilename: String? = nil,
                log: @Sendable (String, String) async -> Void) async throws -> URL {
        let fm = FileManager.default
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        await log("INFO", String(localized: "Validating ePub structure..."))
        guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw RepackError.invalid(String(localized: "Input must be an unpacked ePub directory."))
        }
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedDestination = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedDestination != resolvedSource,
              !resolvedDestination.hasPrefix(resolvedSource + "/") else {
            throw RepackError.invalid(String(localized: "Choose an output folder outside the source book."))
        }

        let workspace = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = workspace.appendingPathComponent("book")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        await log("INFO", String(localized: "Copying book contents; source files are preserved."))
        try copyContents(from: source, to: staging)
        let container = staging.appendingPathComponent("META-INF/container.xml")
        guard fm.fileExists(atPath: container.path) else {
            throw RepackError.invalid(String(localized: "Missing META-INF/container.xml."))
        }
        let document = try XMLDocument(contentsOf: container, options: [.nodeLoadExternalEntitiesNever])
        let roots = try document.nodes(forXPath: "/*[local-name()='container']/*[local-name()='rootfiles']/*[local-name()='rootfile']")
        guard !roots.isEmpty else { throw RepackError.invalid(String(localized: "container.xml has no package document.")) }
        for root in roots {
            guard let path = (root as? XMLElement)?.attribute(forName: "full-path")?.stringValue,
                  !path.isEmpty, !path.hasPrefix("/"),
                  !path.split(separator: "/").contains(".."),
                  fm.fileExists(atPath: staging.appendingPathComponent(path).path) else {
                throw RepackError.invalid(String(localized: "container.xml references an invalid or missing package document."))
            }
        }
        // EPUB requires this exact content, stored first and without compression.
        let mimetype = staging.appendingPathComponent("mimetype")
        let expected = Data("application/epub+zip".utf8)
        if (try? Data(contentsOf: mimetype)) != expected {
            await log("WARNING", String(localized: "Creating a canonical mimetype in the output copy."))
        }
        try expected.write(to: mimetype)
        if fm.fileExists(atPath: staging.appendingPathComponent("META-INF/encryption.xml").path) {
            await log("WARNING", String(localized: "Book declares encrypted resources. Repacking does not remove DRM."))
        }
        let archive = workspace.appendingPathComponent("result.epub")
        try await run(["-X", "-0", archive.path, "mimetype"], in: staging, log: log)
        try await run(["-X", "-r", "-9", archive.path, ".", "-x", "mimetype"], in: staging, log: log)
        try await run(["-T", archive.path], in: staging, log: log)
        let base = source.deletingPathExtension().lastPathComponent + "_repacked"
        let output = destination.appendingPathComponent(outputFilename ?? base + ".epub")
        // Stage on the destination volume before replacing the existing file.
        let replacementDirectory = destination.appendingPathComponent(".ePubTool-" + UUID().uuidString)
        try fm.createDirectory(at: replacementDirectory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: replacementDirectory) }
        let replacement = replacementDirectory.appendingPathComponent("result.epub")
        try fm.copyItem(at: archive, to: replacement)
        if fm.fileExists(atPath: output.path) {
            let values = try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw RepackError.invalid(String(localized: "Output path is not a regular file: \(output.path)"))
            }
            await log("INFO", String(localized: "Overwriting existing ePub: \(output.path)"))
            _ = try fm.replaceItemAt(output, withItemAt: replacement)
        } else {
            try fm.moveItem(at: replacement, to: output)
        }
        await log("SUCCESS", String(localized: "ePub repacked successfully at: \(output.path)"))
        return output
    }

    private func copyContents(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let excluded: Set<String> = [
            ".DS_Store", "__MACOSX", "iTunesMetadata.plist",
            "iTunesMetadata-original.plist", "iTunesArtwork"
        ]
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let name = item.lastPathComponent
            if excluded.contains(name) || name.hasPrefix("._") { continue }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw RepackError.invalid(String(localized: "Symbolic links are not supported: \(item.path)"))
            }
            let target = destination.appendingPathComponent(name)
            if values.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
                try copyContents(from: item, to: target)
            } else {
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    private func run(_ arguments: [String], in directory: URL,
                     log: @Sendable (String, String) async -> Void) async throws {
        func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        await log("EXEC", "cd \(quote(directory.path)) && /usr/bin/zip " + arguments.map(quote).joined(separator: " "))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // Clear ZIPOPT so user environment cannot change archive semantics.
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Drain before waiting so a full pipe cannot deadlock the child process.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty { await log("INFO", output) }
        guard process.terminationStatus == 0 else {
            throw RepackError.invalid(String(localized: "zip exited with status \(process.terminationStatus): \(output)"))
        }
    }
}
