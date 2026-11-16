import SwiftUI
import AppKit

public class AddDialogViewModel: ObservableObject {
    @Published public var options = CompressionOptions()
    @Published public var destinationPath: String = ""
    @Published public var repeatPassword: String = ""
    @Published public var showPassword: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct AddDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = AddDialogViewModel()

    let dictionarySizes = ["64k", "1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m"]
    let wordSizes = [16, 32, 64, 128, 273]
    let solidSizes = ["non-solid", "2g", "4g", "solid"]

    public init(state: FileManagerState) {
        self.state = state
    }

    private var sourceURLs: [URL] {
        if let ext = state.externalAddURLs, !ext.isEmpty {
            return ext
        }
        return state.selectedItems.map { URL(fileURLWithPath: $0.fullPath) }
    }

    public var body: some View {
        let validMethods = CompressionMethod.availableMethods(for: vm.options.format)
        let validEncryption = EncryptionMethod.availableMethods(for: vm.options.format)
        let isSevenZip = vm.options.format == .sevenZip
        let isContainerOnly = vm.options.format == .tar || vm.options.format == .wim
        let memEstimate = vm.options.estimatedMemoryUsageMB()

        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add to Archive")
                        .font(.headline)
                    Text("\(sourceURLs.count) item(s) selected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Archive Destination
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Archive:")
                            .font(.system(size: 12, weight: .semibold))

                        HStack {
                            TextField("Path to archive", text: $vm.destinationPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Browse...") {
                                browseDestination()
                            }
                        }
                    }

                    // Format & Compression Settings vs Encryption & Modes
                    HStack(alignment: .top, spacing: 20) {
                        // Left Column: Compression Settings
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Compression")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            Picker("Archive format:", selection: $vm.options.format) {
                                ForEach(ArchiveFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .onChange(of: vm.options.format) { newFormat in
                                updateForFormat(newFormat)
                            }

                            Picker("Compression level:", selection: $vm.options.compressionLevel) {
                                ForEach(CompressionLevel.allCases) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .disabled(isContainerOnly)

                            Picker("Compression method:", selection: $vm.options.compressionMethod) {
                                ForEach(validMethods) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .disabled(isContainerOnly || vm.options.compressionLevel == .store)

                            Picker("Dictionary size:", selection: $vm.options.dictionarySize) {
                                ForEach(dictionarySizes, id: \.self) { size in
                                    Text(size.uppercased()).tag(size)
                                }
                            }
                            .disabled(!isSevenZip || vm.options.compressionLevel == .store || vm.options.compressionMethod == .copy)

                            Picker("Word size:", selection: $vm.options.wordSize) {
                                ForEach(wordSizes, id: \.self) { size in
                                    Text("\(size)").tag(size)
                                }
                            }
                            .disabled(!isSevenZip || vm.options.compressionLevel == .store || vm.options.compressionMethod == .copy)

                            Picker("Solid block size:", selection: $vm.options.solidBlockSize) {
                                ForEach(solidSizes, id: \.self) { size in
                                    Text(size.capitalized).tag(size)
                                }
                            }
                            .disabled(!isSevenZip)

                            Picker("CPU threads:", selection: $vm.options.threads) {
                                ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { thread in
                                    Text("\(thread)").tag(thread)
                                }
                            }
                            .disabled(isContainerOnly)

                            // Live Memory Usage Readout
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Memory usage for Compressing:")
                                    Spacer()
                                    Text("\(memEstimate.compressMB) MB")
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("Memory usage for Decompressing:")
                                    Spacer()
                                    Text("\(memEstimate.decompressMB) MB")
                                        .fontWeight(.semibold)
                                }
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Right Column: Update Mode, Options, Encryption, Split
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Update & Path Mode")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            Picker("Update mode:", selection: $vm.options.updateMode) {
                                ForEach(UpdateMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }

                            Picker("Path mode:", selection: $vm.options.pathMode) {
                                ForEach(PathMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Delete files after compression", isOn: $vm.options.deleteFilesAfterCompression)
                                Toggle("Compress shared files", isOn: $vm.options.compressSharedFiles)
                            }
                            .font(.system(size: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Parameters (custom 7zz flags):")
                                    .font(.system(size: 11))
                                TextField("e.g. -mqs=on", text: $vm.options.customParameters)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Divider()

                            Text("Encryption")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            if !validEncryption.isEmpty {
                                Picker("Encryption method:", selection: $vm.options.encryptionMethod) {
                                    ForEach(validEncryption) { enc in
                                        Text(enc.rawValue).tag(enc)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enter password:")
                                    .font(.system(size: 11))
                                if vm.showPassword {
                                    TextField("Password", text: $vm.options.password)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("Password", text: $vm.options.password)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .disabled(validEncryption.isEmpty)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reenter password:")
                                    .font(.system(size: 11))
                                if vm.showPassword {
                                    TextField("Reenter", text: $vm.repeatPassword)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("Reenter", text: $vm.repeatPassword)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .disabled(validEncryption.isEmpty)

                            HStack {
                                Toggle("Show password", isOn: $vm.showPassword)
                                Spacer()
                                Toggle("Encrypt file names", isOn: $vm.options.encryptHeaders)
                                    .disabled(!isSevenZip || vm.options.password.isEmpty)
                            }
                            .font(.system(size: 11))

                            Divider()

                            Text("Split to volumes:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("e.g. 100m, 1g", text: $vm.options.volumeSize)
                                    .textFieldStyle(.roundedBorder)

                                Menu("Presets") {
                                    Button("None") { vm.options.volumeSize = "" }
                                    Button("10 MB") { vm.options.volumeSize = "10m" }
                                    Button("100 MB") { vm.options.volumeSize = "100m" }
                                    Button("650 MB (CD)") { vm.options.volumeSize = "650m" }
                                    Button("700 MB (CD)") { vm.options.volumeSize = "700m" }
                                    Button("4480 MB (DVD)") { vm.options.volumeSize = "4480m" }
                                    Button("25000 MB (BD)") { vm.options.volumeSize = "25000m" }
                                }
                                .menuStyle(.borderedButton)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }

            Divider()

            // Footer Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    state.externalAddURLs = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    startCompression()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.destinationPath.isEmpty || sourceURLs.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 680, height: 610)
        .onAppear {
            setupInitialDestination()
        }
    }

    private func setupInitialDestination() {
        guard let first = sourceURLs.first else { return }
        let parentDir = first.deletingLastPathComponent().path
        let baseName = sourceURLs.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        vm.destinationPath = "\(parentDir)/\(baseName).\(vm.options.format.fileExtension)"
    }

    private func updateForFormat(_ format: ArchiveFormat) {
        // Update file extension
        let currentExt = (vm.destinationPath as NSString).pathExtension
        if !currentExt.isEmpty {
            vm.destinationPath = (vm.destinationPath as NSString).deletingPathExtension + ".\(format.fileExtension)"
        }
        // Ensure valid compression method
        let validMethods = CompressionMethod.availableMethods(for: format)
        if !validMethods.contains(vm.options.compressionMethod), let first = validMethods.first {
            vm.options.compressionMethod = first
        }
        // Ensure valid encryption method
        let validEnc = EncryptionMethod.availableMethods(for: format)
        if !validEnc.contains(vm.options.encryptionMethod), let firstEnc = validEnc.first {
            vm.options.encryptionMethod = firstEnc
        }
        if format != .sevenZip {
            vm.options.encryptHeaders = false
        }
    }

    private func browseDestination() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (vm.destinationPath as NSString).lastPathComponent
        let parent = (vm.destinationPath as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: parent)
        }
        if panel.runModal() == .OK, let url = panel.url {
            vm.destinationPath = url.path
        }
    }

    private func startCompression() {
        if !vm.options.password.isEmpty && vm.options.password != vm.repeatPassword {
            vm.errorMessage = "Passwords do not match."
            return
        }

        vm.errorMessage = nil
        let destURL = URL(fileURLWithPath: vm.destinationPath)
        let sources = sourceURLs
        let options = vm.options
        state.externalAddURLs = nil

        dismiss()
        DispatchQueue.main.async {
            state.startCompressOperation(
                sources: sources,
                destinationArchiveURL: destURL,
                options: options
            )
        }
    }
}
