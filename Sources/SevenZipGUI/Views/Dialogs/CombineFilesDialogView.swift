import SwiftUI
import AppKit

public final class CombineFilesViewModel: ObservableObject {
    @Published public var firstPartPath: String = ""
    @Published public var outputPath: String = ""
    @Published public var detectedPartsCount: Int = 0
    @Published public var isProcessing: Bool = false
    @Published public var progressFraction: Double = 0
    @Published public var statusLabel: String = ""
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct CombineFilesDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = CombineFilesViewModel()

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Combine Files")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("First volume (.001):")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("Path to .001 file", text: $vm.firstPartPath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: vm.firstPartPath) { _ in
                                scanParts()
                            }
                        Button("Browse...") {
                            browseFirstPart()
                        }
                    }
                    if vm.detectedPartsCount > 0 {
                        Text("Detected \(vm.detectedPartsCount) volume part(s) (.001 .. .\(String(format: "%03d", vm.detectedPartsCount)))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Combine to file:")
                        .font(.system(size: 12, weight: .semibold))
                    HStack {
                        TextField("Output file path", text: $vm.outputPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseOutput()
                        }
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

                Button("Combine") {
                    startCombine()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isProcessing || vm.firstPartPath.isEmpty || vm.outputPath.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480)
        .onAppear {
            if let first = state.selectedItems.first(where: { !$0.isDirectory && !$0.isArchiveInternal }) {
                vm.firstPartPath = first.fullPath
                scanParts()
            }
        }
    }

    private func browseFirstPart() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vm.firstPartPath = url.path
            scanParts()
        }
    }

    private func browseOutput() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if !vm.outputPath.isEmpty {
            let url = URL(fileURLWithPath: vm.outputPath)
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        }
        if panel.runModal() == .OK, let url = panel.url {
            vm.outputPath = url.path
        }
    }

    private func collectParts(from firstPath: String) -> [URL] {
        let url = URL(fileURLWithPath: firstPath)
        let ext = url.pathExtension
        guard !ext.isEmpty, Int(ext) != nil else { return [] }

        let base = url.deletingPathExtension().path
        var parts: [URL] = []
        var idx = 1
        while true {
            let candidate = URL(fileURLWithPath: "\(base).\(String(format: "%03d", idx))")
            if FileManager.default.fileExists(atPath: candidate.path) {
                parts.append(candidate)
                idx += 1
            } else {
                break
            }
        }
        return parts
    }

    private func scanParts() {
        let parts = collectParts(from: vm.firstPartPath)
        vm.detectedPartsCount = parts.count
        let firstURL = URL(fileURLWithPath: vm.firstPartPath)
        if firstURL.pathExtension == "001" {
            vm.outputPath = firstURL.deletingPathExtension().path
        }
    }

    private func startCombine() {
        let parts = collectParts(from: vm.firstPartPath)
        guard !parts.isEmpty else {
            vm.errorMessage = "Could not locate .001 volume parts."
            return
        }
        let destURL = URL(fileURLWithPath: vm.outputPath)

        vm.errorMessage = nil
        vm.isProcessing = true
        vm.progressFraction = 0
        vm.statusLabel = "Combining \(parts.count) part(s)..."

        Task.detached {
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                fm.createFile(atPath: destURL.path, contents: nil)
                let outHandle = try FileHandle(forWritingTo: destURL)
                defer { try? outHandle.close() }

                let bufferSize = 4 * 1024 * 1024
                let totalCount = parts.count

                for (index, partURL) in parts.enumerated() {
                    let inHandle = try FileHandle(forReadingFrom: partURL)
                    defer { try? inHandle.close() }

                    while true {
                        let data = try inHandle.read(upToCount: bufferSize) ?? Data()
                        if data.isEmpty { break }
                        try outHandle.write(contentsOf: data)
                    }

                    let progress = Double(index + 1) / Double(totalCount)
                    await MainActor.run {
                        vm.progressFraction = progress
                        vm.statusLabel = "Combined part \(index + 1) of \(totalCount)..."
                    }
                }

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
