import SwiftUI
import AppKit

public final class SplitFileViewModel: ObservableObject {
    @Published public var sourcePath: String = ""
    @Published public var destinationFolder: String = ""
    @Published public var volumeSizeText: String = "100m"
    @Published public var isProcessing: Bool = false
    @Published public var progressFraction: Double = 0
    @Published public var statusLabel: String = ""
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct SplitFileDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = SplitFileViewModel()

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Split File")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("File to split:")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("Source file", text: $vm.sourcePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseSource()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Split to folder:")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("Destination folder", text: $vm.destinationFolder)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseDestination()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Split to volumes, bytes:")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("e.g. 10m, 100m, 650m, 1g", text: $vm.volumeSizeText)
                            .textFieldStyle(.roundedBorder)

                        Menu("Presets") {
                            Button("10 MB") { vm.volumeSizeText = "10m" }
                            Button("100 MB") { vm.volumeSizeText = "100m" }
                            Button("650 MB (CD)") { vm.volumeSizeText = "650m" }
                            Button("700 MB (CD)") { vm.volumeSizeText = "700m" }
                            Button("4480 MB (DVD)") { vm.volumeSizeText = "4480m" }
                            Button("1 GB") { vm.volumeSizeText = "1g" }
                        }
                        .menuStyle(.borderedButton)
                    }
                }

                if vm.isProcessing {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: vm.progressFraction, total: 1.0)
                            .progressViewStyle(.linear)
                        Text(vm.statusLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

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
                .disabled(vm.isProcessing)

                Button("Split") {
                    startSplit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isProcessing || vm.sourcePath.isEmpty || vm.destinationFolder.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480)
        .onAppear {
            if let first = state.selectedItems.first(where: { !$0.isDirectory && !$0.isArchiveInternal }) {
                vm.sourcePath = first.fullPath
                vm.destinationFolder = (first.fullPath as NSString).deletingLastPathComponent
            } else {
                vm.destinationFolder = state.currentFilesystemDirectoryURL.path
            }
        }
    }

    private func browseSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.sourcePath = url.path
            if vm.destinationFolder.isEmpty {
                vm.destinationFolder = url.deletingLastPathComponent().path
            }
        }
    }

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            vm.destinationFolder = url.path
        }
    }

    private func parseVolumeSize(_ input: String) -> Int64? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let multiplier: Int64
        let numString: String
        if trimmed.hasSuffix("k") || trimmed.hasSuffix("kb") {
            multiplier = 1024
            numString = trimmed.replacingOccurrences(of: "kb", with: "").replacingOccurrences(of: "k", with: "")
        } else if trimmed.hasSuffix("m") || trimmed.hasSuffix("mb") {
            multiplier = 1024 * 1024
            numString = trimmed.replacingOccurrences(of: "mb", with: "").replacingOccurrences(of: "m", with: "")
        } else if trimmed.hasSuffix("g") || trimmed.hasSuffix("gb") {
            multiplier = 1024 * 1024 * 1024
            numString = trimmed.replacingOccurrences(of: "gb", with: "").replacingOccurrences(of: "g", with: "")
        } else if trimmed.hasSuffix("b") {
            multiplier = 1
            numString = String(trimmed.dropLast())
        } else {
            multiplier = 1
            numString = trimmed
        }

        guard let val = Int64(numString.trimmingCharacters(in: .whitespaces)), val > 0 else { return nil }
        return val * multiplier
    }

    private func startSplit() {
        guard let partSize = parseVolumeSize(vm.volumeSizeText) else {
            vm.errorMessage = "Invalid volume size (e.g. 10m, 100m, 1g)."
            return
        }

        let srcURL = URL(fileURLWithPath: vm.sourcePath)
        let destDir = URL(fileURLWithPath: vm.destinationFolder)
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            vm.errorMessage = "Source file does not exist."
            return
        }

        vm.errorMessage = nil
        vm.isProcessing = true
        vm.progressFraction = 0
        vm.statusLabel = "Splitting..."

        Task.detached {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: srcURL.path)
                let totalSize = (attrs[.size] as? NSNumber)?.int64Value ?? 1
                let inputHandle = try FileHandle(forReadingFrom: srcURL)
                defer { try? inputHandle.close() }

                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

                let bufferSize = 4 * 1024 * 1024
                var totalRead: Int64 = 0
                var partIndex = 1
                var bytesInCurrentPart: Int64 = 0
                var outHandle: FileHandle? = nil

                func openNextPart() throws -> FileHandle {
                    let ext = String(format: "%03d", partIndex)
                    let partURL = destDir.appendingPathComponent("\(srcURL.lastPathComponent).\(ext)")
                    FileManager.default.createFile(atPath: partURL.path, contents: nil)
                    let h = try FileHandle(forWritingTo: partURL)
                    partIndex += 1
                    bytesInCurrentPart = 0
                    return h
                }

                outHandle = try openNextPart()

                while true {
                    let remainingInPart = partSize - bytesInCurrentPart
                    let toRead = Int(min(Int64(bufferSize), remainingInPart))
                    let data = try inputHandle.read(upToCount: toRead) ?? Data()
                    if data.isEmpty { break }

                    try outHandle?.write(contentsOf: data)
                    bytesInCurrentPart += Int64(data.count)
                    totalRead += Int64(data.count)

                    if bytesInCurrentPart >= partSize && totalRead < totalSize {
                        try outHandle?.close()
                        outHandle = try openNextPart()
                    }

                    let progress = min(1.0, Double(totalRead) / Double(max(1, totalSize)))
                    let currentPartNum = partIndex - 1
                    await MainActor.run {
                        vm.progressFraction = progress
                        vm.statusLabel = "Writing part .\(String(format: "%03d", currentPartNum))..."
                    }
                }

                try outHandle?.close()

                await MainActor.run {
                    vm.isProcessing = false
                    dismiss()
                    state.reloadCurrent()
                }
            } catch {
                await MainActor.run {
                    vm.isProcessing = false
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
