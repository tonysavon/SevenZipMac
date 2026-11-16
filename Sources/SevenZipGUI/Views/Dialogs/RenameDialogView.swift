import SwiftUI

public final class RenameViewModel: ObservableObject {
    @Published public var newName: String = ""
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct RenameDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = RenameViewModel()

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Rename Item")
                    .font(.headline)
                Spacer()
            }

            if let target = state.selectedItems.first {
                Text("Current name: \((target.name as NSString).lastPathComponent)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            TextField("New name", text: $vm.newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    performRename()
                }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                if vm.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    performRename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isProcessing || vm.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            if let item = state.selectedItems.first {
                vm.newName = (item.name as NSString).lastPathComponent
            }
        }
    }

    private func performRename() {
        let trimmed = vm.newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            vm.errorMessage = "Invalid file name."
            return
        }
        guard let item = state.selectedItems.first else {
            dismiss()
            return
        }

        if item.isArchiveInternal {
            guard let arcURL = state.activeArchiveURL else { return }
            if state.currentArchiveIsTempNested {
                vm.errorMessage = "Cannot rename inside a temporary nested archive."
                return
            }

            let oldPath = item.fullPath
            let parent = (oldPath as NSString).deletingLastPathComponent
            let newPath = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"
            if oldPath == newPath {
                dismiss()
                return
            }

            vm.isProcessing = true
            Task {
                do {
                    try await SevenZipService.shared.rename(
                        archiveURL: arcURL,
                        pairs: [(oldPath: oldPath, newPath: newPath)],
                        password: state.activeArchivePassword
                    )
                    await MainActor.run {
                        vm.isProcessing = false
                        dismiss()
                        state.reloadCurrent(forceRefreshArchive: true)
                    }
                } catch {
                    await MainActor.run {
                        vm.isProcessing = false
                        vm.errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            let oldURL = URL(fileURLWithPath: item.fullPath)
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(trimmed)
            if oldURL.path == newURL.path {
                dismiss()
                return
            }
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                dismiss()
                state.reloadCurrent()
            } catch {
                vm.errorMessage = error.localizedDescription
            }
        }
    }
}
