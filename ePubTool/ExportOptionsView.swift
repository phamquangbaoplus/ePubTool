import SwiftUI
import AppKit

@MainActor
enum ExportOptionsDialog {
    static func chooseMode() -> Bool? {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = String(localized: "Export Options")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: ExportOptionsView { response in
            NSApp.stopModal(withCode: response)
        })
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        panel.center()
        defer {
            panel.orderOut(nil)
            panel.close()
        }
        switch NSApp.runModal(for: panel) {
        case .OK: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }
}

private struct ExportOptionsView: View {
    let choose: (NSApplication.ModalResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ExportOptionsHeader()
            BackupExportWarning()
            Divider()
            ExportOptionsActions(choose: choose)
        }
        .padding(28)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExportOptionsHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Export Library").font(.title2.bold())
                Text("Choose how to export your selected books.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BackupExportWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Backup export deletes extra files").font(.headline)
                Text("Files in the destination folder that are not in this export list will be permanently deleted before exporting, including unrelated files.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Subfolders are kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.2))
        }
    }
}

private struct ExportOptionsActions: View {
    let choose: (NSApplication.ModalResponse) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Cancel") { choose(.cancel) }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 12)
            Button("Export as Backup", role: .destructive) { choose(.alertSecondButtonReturn) }
                .buttonStyle(.bordered)
            Button("Export Normally") { choose(.OK) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }
}

#Preview {
    ExportOptionsView { _ in }
}
