import SwiftUI
import AppKit

struct AppleBooksView: View {
    @Bindable var model: AppleBooksViewModel
    let console: RepackViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryHeader(model: model, console: console)
            TextField("Search title, author or filename…", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .task(id: model.query) {
                    do {
                        try await Task.sleep(for: .milliseconds(150))
                        model.applyFilter()
                    } catch { }
                }
            HStack {
                Text("\(model.filtered.count) books · \(model.selection.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Select All Results") { model.selection = Set(model.filtered.map(\.id)) }
                Button("Deselect All") { model.selection.removeAll() }
            }
            Table(model.filtered, selection: $model.selection) {
                TableColumn("Title") { book in
                    CopyableBookText(text: book.title, field: "title")
                }
                .width(min: 140, ideal: 260)
                TableColumn("Author") { book in
                    CopyableBookText(text: book.author, field: "author")
                }
                .width(min: 90, ideal: 150)
                TableColumn("Format", value: \.format)
                    .width(55)
                TableColumn("Actions") { book in
                    HStack(spacing: 8) {
                        Button {
                            Task { await model.edit(book, console: console) }
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Edit \(book.title)")
                            .disabled(book.format != "EPUB" || model.isWorking || model.isLoading)
                            .help("Open an editable EPUB copy in Calibre")
                        Button {
                            Task { await model.export([book], console: console) }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Export \(book.title)")
                            .help("Export book")
                            .disabled(model.isWorking || model.isLoading)
                        Menu {
                            Button("Show Original in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([book.url])
                            }
                            if let copy = model.editedCopies[book.id] {
                                Button("Show Edited Copy in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([copy])
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .help(book.url.path)
                    }
                }
                .width(110)
            }
            .overlay {
                if model.filtered.isEmpty && !model.isLoading {
                    ContentUnavailableView(model.books.isEmpty ? "No books loaded" : "No matching books",
                                           systemImage: "books.vertical")
                        .allowsHitTesting(false)
                }
            }
            if let startedAt = model.exportStartedAt {
                ExportActivityView(status: model.status, completed: model.completed,
                                   total: model.total, startedAt: startedAt)
            }
            LibraryFooter(model: model, console: console)
        }
        .padding(20)
        .navigationTitle("Manage Apple Books")
        .onAppear { model.loadIfNeeded(console: console) }
    }
}

private struct CopyableBookText: View {
    let text: String
    let field: String
    @State private var copyID: UUID?

    var body: some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1)
            if copyID != nil {
                Image(systemName: "checkmark").foregroundStyle(.green)
                    .accessibilityLabel("Copied")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { copy() })
        .help("Double-click to copy \(field)")
        .accessibilityAction(named: Text("Copy \(field)")) { copy() }
        .task(id: copyID) {
            guard copyID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.5))
                copyID = nil
            } catch { }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyID = UUID()
    }
}

private struct ExportActivityView: View {
    let status: String
    let completed: Int
    let total: Int
    let startedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(status).font(.callout).lineLimit(2)
                Text("\(completed) of \(total) processed").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(startedAt, style: .timer)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LibraryHeader: View {
    let model: AppleBooksViewModel
    let console: RepackViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Manage Apple Books").font(.title2.bold())
                Spacer()
                Button("Refresh") { model.reload(console: console) }
                    .disabled(model.isLoading || model.isWorking)
                if model.isLoading {
                    Button("Stop") { model.stopLoading() }
                }
            }
            Text(model.folder.path).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).textSelection(.enabled)
        }
    }
}

private struct LibraryFooter: View {
    let model: AppleBooksViewModel
    let console: RepackViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit opens a separate copy in Calibre. Export reads the Apple Books original. Existing export files are overwritten.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.isLoading || model.isWorking { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).lineLimit(2).textSelection(.enabled)
                Spacer()
                if let folder = model.lastExport {
                    Button("Show Exports") { NSWorkspace.shared.open(folder) }
                }
                Button {
                    let selected = model.selectedEPUBs
                    Task { await model.edit(selected, console: console) }
                } label: {
                    Label("Edit Selected (\(model.selectedEPUBs.count))", systemImage: "square.and.pencil")
                }
                .disabled(model.selectedEPUBs.isEmpty || model.isWorking || model.isLoading)
                .help("Open selected EPUBs in Calibre; PDFs are skipped")
                Button("Export Selected (\(model.selection.count))") {
                    let selected = model.filtered.filter { model.selection.contains($0.id) }
                    Task { await model.export(selected, console: console) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selection.isEmpty || model.isWorking || model.isLoading)
            }
        }
    }
}
