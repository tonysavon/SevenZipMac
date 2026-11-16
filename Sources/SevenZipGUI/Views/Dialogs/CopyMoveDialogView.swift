import SwiftUI
import AppKit

public final class CopyMoveViewModel: ObservableObject {
    @Published public var destinationPath: String = ""
    @Published public var overwriteExisting: Bool = true
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct CopyMoveDialogView: View {
    @ObservedObject var workspace: WorkspaceState
    let isMove: Bool
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = CopyMoveViewModel()

    public init(workspace: WorkspaceState, isMove: Bool) {
        self.workspace = workspace
        self.isMove = isMove
    }

    public var body: some View {
        let sourcePane = workspace.activePane
        let count = sourcePane.selectedItems.count

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isMove ? "arrow.right.doc.on.clipboard" : "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMove ? "Move" : "Copy")
                        .font(.headline)
                    Text("\(isMove ? "Move" : "Copy") \(count) item(s) to:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Destination path:")
                        .font(.system(size: 12, weight: .semibold))

                    HStack {
                        TextField("Destination folder or archive", text: $vm.destinationPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            browseDestination()
                        }
                    }
                }

                Toggle("Overwrite existing files without prompt", isOn: $vm.overwriteExisting)
                    .font(.system(size: 12))

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    executeTransfer()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480)
        .onAppear {
            if let opposite = workspace.inactivePane {
                vm.destinationPath = opposite.currentDisplayPath
            } else {
                vm.destinationPath = workspace.activePane.currentFilesystemDirectoryURL.path
            }
        }
    }

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !vm.destinationPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: vm.destinationPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            vm.destinationPath = url.path
        }
    }

    private func executeTransfer() {
        let trimmed = vm.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sourcePane = workspace.activePane
        let items = sourcePane.selectedItems
        guard !items.isEmpty else {
            dismiss()
            return
        }

        let overwrite = vm.overwriteExisting

        // Check if destination matches an open archive in the opposite pane
        if let opposite = workspace.inactivePane,
           opposite.isInsideArchive,
           trimmed == opposite.currentDisplayPath,
           let targetArc = opposite.activeArchiveURL {
            if opposite.currentArchiveIsTempNested {
                vm.errorMessage = "Cannot modify a nested temporary archive directly."
                return
            }
            let subpath = opposite.currentArchiveSubpath
            let pass = opposite.activeArchivePassword
            dismiss()
            DispatchQueue.main.async {
                workspace.transferItems(
                    items,
                    from: sourcePane,
                    toArchive: targetArc,
                    subpath: subpath,
                    targetPassword: pass,
                    isMove: isMove
                )
            }
            return
        }

        // Check if destination is an existing archive file on disk
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir),
           !isDir.boolValue,
           FileItem.knownArchiveExtensions.contains((trimmed as NSString).pathExtension.lowercased()) {
            let targetArc = URL(fileURLWithPath: trimmed)
            dismiss()
            DispatchQueue.main.async {
                workspace.transferItems(
                    items,
                    from: sourcePane,
                    toArchive: targetArc,
                    subpath: "",
                    targetPassword: nil,
                    isMove: isMove
                )
            }
            return
        }

        // Otherwise destination is a filesystem folder
        let destURL = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        dismiss()
        DispatchQueue.main.async {
            workspace.transferItems(
                items,
                from: sourcePane,
                toFilesystemFolder: destURL,
                isMove: isMove,
                overwrite: overwrite
            )
        }
    }
}
