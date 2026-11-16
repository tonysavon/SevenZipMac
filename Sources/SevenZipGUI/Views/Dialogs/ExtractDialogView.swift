import SwiftUI
import AppKit

public class ExtractDialogViewModel: ObservableObject {
    @Published public var destinationPath: String = ""
    @Published public var overwriteMode: OverwriteMode = .overwrite
    @Published public var pathMode: ExtractPathMode = .full
    @Published public var eliminateRootDuplication: Bool = true
    @Published public var password: String = ""
    @Published public var showPassword: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct ExtractDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = ExtractDialogViewModel()

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Extract Archive")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                // Destination Path
                VStack(alignment: .leading, spacing: 6) {
                    Text("Extract to:")
                        .font(.system(size: 12, weight: .semibold))

                    HStack {
                        TextField("Destination folder", text: $vm.destinationPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            browseDestination()
                        }
                    }

                    Toggle("Eliminate duplication of root folder", isOn: $vm.eliminateRootDuplication)
                        .font(.system(size: 12))
                }

                Divider()

                // Path & Overwrite Options
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Path mode:", selection: $vm.pathMode) {
                        ForEach(ExtractPathMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Picker("Overwrite mode:", selection: $vm.overwriteMode) {
                        ForEach(OverwriteMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                Divider()

                // Password
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password (if encrypted):")
                        .font(.system(size: 12, weight: .semibold))

                    HStack {
                        if vm.showPassword {
                            TextField("Password", text: $vm.password)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Password", text: $vm.password)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { vm.showPassword.toggle() }) {
                            Image(systemName: vm.showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    startExtraction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.destinationPath.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 400)
        .onAppear {
            setupInitialDestination()
        }
    }

    private func setupInitialDestination() {
        switch state.currentTarget {
        case .archive(let baseURL, let frames):
            if let last = frames.last {
                let folderName = (last.displayName as NSString).deletingPathExtension
                vm.destinationPath = baseURL.appendingPathComponent(folderName).path
            } else {
                vm.destinationPath = baseURL.path
            }
        case .filesystem:
            if let first = state.selectedItems.first(where: { $0.isArchive }) {
                let arcURL = URL(fileURLWithPath: first.fullPath)
                vm.destinationPath = arcURL.deletingPathExtension().path
            } else {
                vm.destinationPath = state.currentDisplayPath
            }
        }
    }

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.destinationPath = url.path
        }
    }

    private func startExtraction() {
        vm.errorMessage = nil

        let destURL = URL(fileURLWithPath: vm.destinationPath)
        let arcURL: URL
        var selectedSubpaths: [String]? = nil

        if let activeURL = state.activeArchiveURL {
            arcURL = activeURL
            if !state.selectedItems.isEmpty {
                selectedSubpaths = state.selectedItems.map(\.fullPath)
            }
        } else if let first = state.selectedItems.first(where: { $0.isArchive }) {
            arcURL = URL(fileURLWithPath: first.fullPath)
        } else {
            vm.errorMessage = "No archive selected."
            return
        }

        let password = vm.password.isEmpty ? nil : vm.password
        let overwriteMode = vm.overwriteMode
        let pathMode = vm.pathMode
        let eliminateRoot = vm.eliminateRootDuplication

        dismiss()
        DispatchQueue.main.async {
            state.startExtractOperation(
                archiveURL: arcURL,
                destinationURL: destURL,
                selectedItems: selectedSubpaths,
                password: password,
                overwriteMode: overwriteMode,
                restoreFullPaths: pathMode != .none,
                pathMode: pathMode,
                eliminateRootDuplication: eliminateRoot
            )
        }
    }
}
