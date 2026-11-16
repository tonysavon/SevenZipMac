import SwiftUI

public final class NewFolderViewModel: ObservableObject {
    @Published public var folderName: String = "New Folder"
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct NewFolderDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = NewFolderViewModel()

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Create Folder")
                    .font(.headline)
                Spacer()
            }

            TextField("Folder name", text: $vm.folderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    createFolder()
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

                Button("Create") {
                    createFolder()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isProcessing || vm.folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func createFolder() {
        let trimmed = vm.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            vm.errorMessage = "Invalid folder name."
            return
        }

        if state.isInsideArchive {
            guard let arcURL = state.activeArchiveURL else { return }
            if state.currentArchiveIsTempNested {
                vm.errorMessage = "Cannot create folder inside a temporary nested archive."
                return
            }

            vm.isProcessing = true
            Task {
                do {
                    try await SevenZipService.shared.createFolderInArchive(
                        archiveURL: arcURL,
                        subpath: state.currentArchiveSubpath,
                        folderName: trimmed,
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
            let folderURL = state.currentFilesystemDirectoryURL.appendingPathComponent(trimmed, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
                dismiss()
                state.reloadCurrent()
            } catch {
                vm.errorMessage = error.localizedDescription
            }
        }
    }
}
