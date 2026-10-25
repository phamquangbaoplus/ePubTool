import SwiftUI

enum Utility: String, Identifiable, CaseIterable {
    case appleBooks

    var id: String { rawValue }
}

struct ContentView: View {
    @State private var console = ConsoleViewModel()
    @State private var library = AppleBooksViewModel()
    @State private var selection: Utility? = .appleBooks

    var body: some View {
        NavigationSplitView {
            List(Utility.allCases, selection: $selection) { tool in
                switch tool {
                case .appleBooks:
                    Label("Manage Apple Books", systemImage: "book.closed")
                        .tag(tool)
                }
            }
            .navigationTitle("ePubTool")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                switch selection {
                case .appleBooks:
                    AppleBooksView(model: library, console: console)
                case nil:
                    ContentUnavailableView("Select a tool", systemImage: "sidebar.left")
                }
                Divider()
                ConsoleView(model: console)
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
    }
}

private struct ConsoleView: View {
    let model: ConsoleViewModel
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
                .accessibilityLabel(isExpanded ? Text("Collapse Console") : Text("Expand Console"))
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
    let model: ConsoleViewModel

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
