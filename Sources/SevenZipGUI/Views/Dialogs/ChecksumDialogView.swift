import SwiftUI
import AppKit

public final class ChecksumViewModel: ObservableObject {
    @Published public var selectedAlgorithm: String = "-scrc*"
    @Published public var outputText: String = ""
    @Published public var isComputing: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}
}

public struct ChecksumDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = ChecksumViewModel()

    let algorithms: [(label: String, flag: String)] = [
        ("All (*)", "-scrc*"),
        ("SHA-256", "-scrcSHA256"),
        ("SHA-1", "-scrcSHA1"),
        ("SHA-512", "-scrcSHA512"),
        ("CRC-32", "-scrcCRC32"),
        ("CRC-64", "-scrcCRC64"),
        ("MD5", "-scrcMD5"),
        ("BLAKE2sp", "-scrcBLAKE2sp"),
        ("XXH64", "-scrcXXH64")
    ]

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "number.square.fill")
                    .font(.title)
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CRC & Hash Checksum")
                        .font(.headline)
                    Text("7-Zip Hash Calculator")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Algorithm:", selection: $vm.selectedAlgorithm) {
                    ForEach(algorithms, id: \.flag) { alg in
                        Text(alg.label).tag(alg.flag)
                    }
                }
                .frame(width: 190)
                .disabled(vm.isComputing)
                .onChange(of: vm.selectedAlgorithm) { _ in
                    runHashes()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ZStack {
                ScrollView([.vertical, .horizontal]) {
                    Text(vm.outputText.isEmpty && !vm.isComputing ? "No output." : vm.outputText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))

                if vm.isComputing {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Calculating checksums...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                }
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Divider()

            HStack {
                Button("Copy Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.outputText, forType: .string)
                }
                .disabled(vm.outputText.isEmpty || vm.isComputing)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 680, height: 420)
        .onAppear {
            vm.selectedAlgorithm = state.checksumAlgorithm
            runHashes()
        }
    }

    private func runHashes() {
        vm.errorMessage = nil
        vm.isComputing = true
        let flag = vm.selectedAlgorithm
        let selected = state.selectedItems

        Task {
            do {
                let result: String
                if state.isInsideArchive {
                    guard let arcURL = state.activeArchiveURL else {
                        throw NSError(domain: "Checksum", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active archive."])
                    }
                    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("SevenZipGUI_Hash", isDirectory: true)
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: tempDir) }

                    let subpaths = selected.isEmpty ? nil : selected.map(\.fullPath)
                    try await SevenZipService.shared.extract(
                        archiveURL: arcURL,
                        destinationURL: tempDir,
                        selectedItems: subpaths,
                        password: state.activeArchivePassword,
                        overwriteMode: .overwrite,
                        restoreFullPaths: true
                    )
                    let extracted = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    result = try await SevenZipService.shared.computeHashes(paths: extracted, algorithmFlag: flag)
                } else {
                    let urls = selected.map { URL(fileURLWithPath: $0.fullPath) }
                    result = try await SevenZipService.shared.computeHashes(paths: urls, algorithmFlag: flag)
                }

                await MainActor.run {
                    vm.outputText = result
                    vm.isComputing = false
                }
            } catch {
                await MainActor.run {
                    vm.errorMessage = error.localizedDescription
                    vm.isComputing = false
                }
            }
        }
    }
}
