import SwiftUI
import AppKit

enum Utility: String, Identifiable, CaseIterable {
    case repack
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var model = RepackViewModel()
    @State private var selection: Utility? = .repack

    var body: some View {
        NavigationSplitView {
            List(Utility.allCases, selection: $selection) { tool in
                Label("Repack ePub", systemImage: "books.vertical")
                    .tag(tool)
            }
            .navigationTitle("ePubTool")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if selection == .repack {
                    RepackToolView(model: model)
                } else {
                    ContentUnavailableView("Select a tool", systemImage: "sidebar.left")
                }
                Divider()
                ConsoleView(model: model)
            }
        }
        .frame(minWidth: 800, minHeight: 650)
    }
}

private struct RepackToolView: View {
    let model: RepackViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Repack Apple Books ePub").font(.title2.bold())
                Text("Turn unpacked book folders into standard .epub files.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus").font(.largeTitle).foregroundStyle(.tint)
                Text("Drop unpacked ePub folders here").font(.headline)
                Button("Choose Folders…") { Task { await model.chooseSources() } }
                Text("Multiple folders supported · Originals stay untouched")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6])))
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.isRunning else { return false }
                model.add(urls)
                return true
            } isTargeted: { isTargeted = $0 }
            .disabled(model.isRunning)

            HStack {
                Text("Queue (\(model.jobs.count))").font(.headline)
                Spacer()
                Button("Remove All") { model.jobs.removeAll() }
                    .disabled(model.isRunning || model.jobs.isEmpty)
            }
            List(model.jobs) { job in
                HStack {
                    Image(systemName: job.output == nil ? "book.closed" : "checkmark.circle.fill")
                        .foregroundStyle(job.output == nil ? Color.secondary : Color.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.source.lastPathComponent).fontWeight(.medium)
                        Text(job.status).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if let output = job.output {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                    }
                    Button {
                        model.jobs.removeAll { $0.id == job.id }
                    } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(job.source.lastPathComponent)")
                        .disabled(model.isRunning)
                }
                .help(job.source.path)
            }
            .frame(minHeight: 100)
            .overlay {
                if model.jobs.isEmpty {
                    Text("No folders selected").foregroundStyle(.secondary)
                }
            }
            OutputControls(model: model)
        }
        .padding(24)
        .navigationTitle("Repack ePub")
    }
}

private struct OutputControls: View {
    let model: RepackViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output folder").font(.headline)
                    Text(model.destination?.path ?? "Choose where to save your repacked books")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).textSelection(.enabled)
                }
                Spacer()
                Button("Choose…") { Task { await model.chooseDestination() } }
                    .disabled(model.isRunning)
            }
            Text("Saved as <book>_repacked.epub. Existing files with the same name will be overwritten.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    ProgressView(value: Double(model.completed), total: Double(max(model.jobs.count, 1)))
                        .frame(width: 100)
                }
                Text(model.summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Repack ePub") { Task { await model.run() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning || model.jobs.isEmpty || model.destination == nil)
            }
        }
    }
}

private struct ConsoleView: View {
    let model: RepackViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label("Console", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse Console" : "Expand Console")
                Spacer()
                Button("Clear Log") { model.logs.removeAll() }
                Button("Copy Log") { model.copyLog() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            if isExpanded {
                Divider()
                ConsoleLogView(model: model)
                    .frame(height: 170)
            }
        }
        .background(.background.secondary)
    }
}

private struct ConsoleLogView: View {
    let model: RepackViewModel

    var body: some View {
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(model.logs) { entry in
                            Text(entry.text)
                                .foregroundStyle(entry.level == "ERROR" ? Color.red :
                                    entry.level == "WARNING" ? Color.orange :
                                    entry.level == "SUCCESS" ? Color.green : Color.primary)
                                .id(entry.id)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                }
                .onChange(of: model.logs.count) {
                    if let last = model.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
    }
}

#Preview {
    ContentView()
}
