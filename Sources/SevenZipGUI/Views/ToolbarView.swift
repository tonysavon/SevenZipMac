import SwiftUI

public struct ToolbarView: View {
    @ObservedObject var workspace: WorkspaceState

    private var state: FileManagerState {
        workspace.activePane
    }

    public init(workspace: WorkspaceState) {
        self.workspace = workspace
    }

    public var body: some View {
        HStack(spacing: 4) {
            // Add Button (+)
            ToolbarButton(
                title: "Add",
                iconName: "plus.circle.fill",
                accentColor: .green,
                isDisabled: state.isInsideArchive || state.selectedItems.isEmpty
            ) {
                state.showAddDialog = true
            }
            .help("Add selected files to an archive")

            // Extract Button (-)
            let canExtract = state.isInsideArchive || state.selectedItems.contains(where: { $0.isArchive })
            ToolbarButton(
                title: "Extract",
                iconName: "minus.circle.fill",
                accentColor: .blue,
                isDisabled: !canExtract
            ) {
                state.showExtractDialog = true
            }
            .help("Extract archive or selected files")

            // Test Button (✓)
            let canTest = state.isInsideArchive || state.selectedItems.contains(where: { $0.isArchive })
            ToolbarButton(
                title: "Test",
                iconName: "checkmark.circle.fill",
                accentColor: .teal,
                isDisabled: !canTest
            ) {
                state.testCurrentArchive()
            }
            .help("Test integrity of archive")

            Divider()
                .frame(height: 28)
                .padding(.horizontal, 2)

            // Copy (F5)
            ToolbarButton(
                title: "Copy",
                iconName: "doc.on.doc",
                accentColor: .accentColor,
                isDisabled: state.selectedItems.isEmpty
            ) {
                workspace.openCopyDialog()
            }
            .help("Copy selected items to folder or archive (F5)")

            // Move (F6)
            ToolbarButton(
                title: "Move",
                iconName: "arrow.right.doc.on.clipboard",
                accentColor: .accentColor,
                isDisabled: state.selectedItems.isEmpty
            ) {
                workspace.openMoveDialog()
            }
            .help("Move selected items to folder or archive (F6)")

            // Delete (✕)
            ToolbarButton(
                title: "Delete",
                iconName: "trash.circle.fill",
                accentColor: .red,
                isDisabled: state.selectedItems.isEmpty
            ) {
                state.deleteSelected()
            }
            .help("Delete selected items (⌘⌫)")

            // Info (ℹ)
            let canInfo = state.isInsideArchive || !state.selectedItems.isEmpty
            ToolbarButton(
                title: "Info",
                iconName: "info.circle.fill",
                accentColor: .indigo,
                isDisabled: !canInfo
            ) {
                state.showInfoDialog = true
            }
            .help("Show file or archive properties (⌘I)")

            Spacer()

            // Dual Pane Toggle (F9)
            ToolbarButton(
                title: "2 Panels",
                iconName: workspace.isDualPane ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                accentColor: workspace.isDualPane ? .accentColor : .secondary,
                isDisabled: false
            ) {
                workspace.toggleDualPane()
            }
            .help("Toggle 2-Panel Dual Pane View (F9 / ⌘2)")

            // Benchmark (⚡)
            ToolbarButton(
                title: "Benchmark",
                iconName: "bolt.badge.clock.fill",
                accentColor: .orange,
                isDisabled: false
            ) {
                state.showBenchmarkDialog = true
            }
            .help("7-Zip CPU Benchmark")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ToolbarButton: View {
    let title: String
    let iconName: String
    let accentColor: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isDisabled ? .secondary.opacity(0.4) : accentColor)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .primary)
            }
            .frame(width: 58, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
