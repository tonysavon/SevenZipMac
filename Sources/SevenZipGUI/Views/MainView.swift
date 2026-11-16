import SwiftUI
import AppKit

public class KeyMonitorHolder: ObservableObject {
    var monitor: Any?
    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}

public struct MainView: View {
    @StateObject private var workspace = WorkspaceState()
    @StateObject private var keyMonitor = KeyMonitorHolder()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Shared Iconic 7-Zip Toolbar
            ToolbarView(workspace: workspace)

            Divider()

            // Single or Dual-Pane File Browser
            if workspace.isDualPane {
                HSplitView {
                    PaneContainerView(workspace: workspace, state: workspace.leftPane, side: .left)
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)

                    PaneContainerView(workspace: workspace, state: workspace.rightPane, side: .right)
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                PaneContainerView(workspace: workspace, state: workspace.leftPane, side: .left)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: workspace.isDualPane ? 900 : 780, minHeight: 480)
        .sheet(isPresented: $workspace.showCopyMoveDialog) {
            CopyMoveDialogView(workspace: workspace, isMove: workspace.copyMoveIsMove)
        }
        .onAppear {
            AppDelegate.onOpenFiles = { files in
                guard let first = files.first else { return }
                let url = URL(fileURLWithPath: first)
                let ext = url.pathExtension.lowercased()
                if FileItem.knownArchiveExtensions.contains(ext) {
                    workspace.activePane.openArchiveFile(url: url)
                } else {
                    workspace.activePane.navigateTo(.filesystem(url: url))
                }
            }
            installKeyMonitor()
        }
        .onDisappear {
            if let monitor = keyMonitor.monitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor.monitor = nil
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor.monitor == nil else { return }
        keyMonitor.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak workspace] event in
            guard let workspace = workspace,
                  let window = NSApp.keyWindow,
                  window.sheets.isEmpty,
                  !(window.firstResponder is NSTextView) else {
                return event
            }

            let pane = workspace.activePane
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if modifiers == .command {
                switch event.keyCode {
                case 8: // ⌘C -> Copy to clipboard
                    if !pane.selectedItems.isEmpty {
                        pane.copySelectedToClipboard()
                        return nil
                    }
                case 9: // ⌘V -> Paste from clipboard
                    pane.pasteFromClipboard {
                        workspace.refreshBothPanesIfNeeded()
                    }
                    return nil
                case 51: // ⌘⌫ -> Delete
                    if !pane.selectedItems.isEmpty {
                        pane.deleteSelected()
                        return nil
                    }
                default:
                    break
                }
            } else if modifiers.isEmpty {
                switch event.keyCode {
                case 49: // Space -> Quick Look
                    pane.quickLookSelectedItem()
                    return nil
                case 36, 76: // Return / Enter -> Open selected item
                    if !pane.selectedItemIDs.isEmpty {
                        pane.openSelectedItem()
                        return nil
                    }
                case 51: // Backspace -> Go Up
                    pane.navigateUp()
                    return nil
                case 48: // Tab -> Switch pane in 2-panel mode
                    if workspace.isDualPane {
                        workspace.switchActivePane()
                        return nil
                    }
                case 120: // F2 -> Rename
                    if !pane.selectedItems.isEmpty {
                        pane.showRenameDialog = true
                        return nil
                    }
                case 96: // F5 -> Copy To
                    workspace.openCopyDialog()
                    return nil
                case 97: // F6 -> Move To
                    workspace.openMoveDialog()
                    return nil
                case 98: // F7 -> New Folder
                    pane.showNewFolderDialog = true
                    return nil
                case 101: // F9 -> Toggle 2 Panels
                    workspace.toggleDualPane()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }
}

public struct PaneContainerView: View {
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject var state: FileManagerState
    let side: PaneSide

    private var isActive: Bool {
        workspace.activePaneSide == side
    }

    public var body: some View {
        VStack(spacing: 0) {
            if workspace.isDualPane {
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }

            AddressBarView(state: state)

            Divider()

            FileTableView(workspace: workspace, state: state, paneSide: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Per-Pane Status Bar
            HStack(spacing: 10) {
                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Text(state.statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if state.isFlatView {
                    Text("FLAT VIEW")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18))
                        .foregroundColor(.accentColor)
                        .cornerRadius(3)
                }

                Spacer()

                if !workspace.isDualPane || side == .right {
                    Text("7-Zip Engine: Built-in (ip7z/7zip)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .sheet(isPresented: $state.showAddDialog) {
            AddDialogView(state: state)
        }
        .sheet(isPresented: $state.showExtractDialog) {
            ExtractDialogView(state: state)
        }
        .sheet(isPresented: $state.showTestDialog) {
            TestDialogView(state: state)
        }
        .sheet(isPresented: $state.showInfoDialog) {
            InfoDialogView(state: state)
        }
        .sheet(isPresented: $state.showBenchmarkDialog) {
            BenchmarkDialogView(state: state)
        }
        .sheet(isPresented: $state.showChecksumDialog) {
            ChecksumDialogView(state: state)
        }
        .sheet(isPresented: $state.showSplitDialog) {
            SplitFileDialogView(state: state)
        }
        .sheet(isPresented: $state.showCombineDialog) {
            CombineFilesDialogView(state: state)
        }
        .sheet(isPresented: $state.showRenameDialog) {
            RenameDialogView(state: state)
        }
        .sheet(isPresented: $state.showNewFolderDialog) {
            NewFolderDialogView(state: state)
        }
        .sheet(isPresented: $state.showPasswordPrompt) {
            PasswordPromptView(state: state)
        }
        .sheet(item: $state.activeProgress) { progress in
            ProgressDialogView(progress: progress) {
                state.activeProgress = nil
            }
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct PasswordPromptView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.yellow)
                    .font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.passwordPromptTitle)
                        .font(.headline)
                    Text("Enter password to unlock this archive")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            SecureField("Password", text: $state.passwordInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Unlock") {
                    state.passwordPromptAction?(state.passwordInput)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.passwordInput.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
