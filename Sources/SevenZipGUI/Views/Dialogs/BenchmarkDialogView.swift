import SwiftUI

@MainActor
public class BenchmarkViewModel: ObservableObject {
    @Published public var threads: Int = ProcessInfo.processInfo.activeProcessorCount
    @Published public var dictionarySizeMB: Int = 16
    @Published public var passes: Int = 1
    @Published public var isRunning: Bool = false
    @Published public var logOutput: String = ""
    @Published public var compressSpeed: String = "-"
    @Published public var compressRating: String = "-"
    @Published public var decompressSpeed: String = "-"
    @Published public var decompressRating: String = "-"
    @Published public var totalRating: String = "-"

    private var benchmarkTask: Task<Void, Never>?

    public init() {}

    public func startBenchmark() {
        isRunning = true
        logOutput = "Running 7-Zip Benchmark (\(threads) threads, \(dictionarySizeMB) MB dictionary, \(passes) pass\(passes > 1 ? "es" : ""))...\n\n"
        compressSpeed = "Testing..."
        compressRating = "Testing..."
        decompressSpeed = "Testing..."
        decompressRating = "Testing..."
        totalRating = "..."

        let th = threads
        let dict = dictionarySizeMB
        let p = passes

        benchmarkTask = Task { @MainActor [weak self] in
            do {
                let output = try await SevenZipService.shared.runBenchmark(
                    threads: th,
                    dictSizeMB: dict,
                    iterations: p
                ) { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.logOutput += chunk
                        self.parseBenchmarkOutput(self.logOutput)
                    }
                }
                guard let self = self else { return }
                self.logOutput = output
                self.parseBenchmarkOutput(output)
                self.isRunning = false
            } catch is CancellationError {
                guard let self = self else { return }
                self.isRunning = false
                if !self.logOutput.contains("[Benchmark stopped]") {
                    self.logOutput += "\n\n[Benchmark stopped]\n"
                }
            } catch {
                guard let self = self else { return }
                let err = error as NSError
                if err.code == 255 || err.code == 15 || error.localizedDescription.contains("Break signaled") {
                    if !self.logOutput.contains("[Benchmark stopped]") {
                        self.logOutput += "\n\n[Benchmark stopped]\n"
                    }
                } else {
                    self.logOutput += "\nError: \(error.localizedDescription)"
                }
                self.isRunning = false
            }
        }
    }

    public func stopBenchmark() {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        Task {
            await SevenZipService.shared.stopBenchmark()
        }
        isRunning = false
        if !logOutput.contains("[Benchmark stopped]") {
            logOutput += "\n\n[Benchmark stopped]\n"
        }
    }

    private func parseBenchmarkOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.starts(with: "Avr:") {
                let parts = trimmed.split(separator: " ").map { String($0) }
                if let pipeIndex = parts.firstIndex(of: "|") {
                    compressSpeed = "\(parts[1]) KiB/s"
                    compressRating = parts[pipeIndex - 1]
                    if parts.count > pipeIndex + 1 {
                        decompressSpeed = "\(parts[pipeIndex + 1]) KiB/s"
                        decompressRating = parts[parts.count - 1]
                    }
                }
            } else if trimmed.starts(with: "Tot:") {
                let parts = trimmed.split(separator: " ").map { String($0) }
                if let last = parts.last {
                    totalRating = last
                }
            } else if let firstWord = trimmed.split(separator: " ").first,
                      firstWord.hasSuffix(":"),
                      Int(firstWord.dropLast()) != nil {
                let parts = trimmed.split(separator: " ").map { String($0) }
                if let pipeIndex = parts.firstIndex(of: "|") {
                    compressSpeed = "\(parts[1]) KiB/s"
                    compressRating = parts[pipeIndex - 1]
                    if parts.count > pipeIndex + 1 {
                        decompressSpeed = "\(parts[pipeIndex + 1]) KiB/s"
                        decompressRating = parts[parts.count - 1]
                    }
                }
            }
        }
    }
}

public struct BenchmarkDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = BenchmarkViewModel()

    let dictOptions = [16, 32, 64, 128]
    let passOptions = [1, 2, 5, 10]

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "bolt.badge.clock.fill")
                    .foregroundColor(.orange)
                    .font(.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text("7-Zip Benchmark")
                        .font(.headline)
                    Text("CPU & Memory Compression Benchmark")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(spacing: 14) {
                // Settings Row
                HStack(spacing: 16) {
                    Picker("Threads:", selection: $vm.threads) {
                        ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { t in
                            Text("\(t)").tag(t)
                        }
                    }
                    .frame(width: 130)
                    .disabled(vm.isRunning)

                    Picker("Dictionary:", selection: $vm.dictionarySizeMB) {
                        ForEach(dictOptions, id: \.self) { d in
                            Text("\(d) MB").tag(d)
                        }
                    }
                    .frame(width: 140)
                    .disabled(vm.isRunning)

                    Picker("Passes:", selection: $vm.passes) {
                        ForEach(passOptions, id: \.self) { p in
                            Text("\(p)").tag(p)
                        }
                    }
                    .frame(width: 120)
                    .disabled(vm.isRunning)

                    Spacer()

                    Button(vm.isRunning ? "Stop" : "Start") {
                        if vm.isRunning {
                            vm.stopBenchmark()
                        } else {
                            vm.startBenchmark()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isRunning ? .red : .accentColor)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // Benchmark Cards Grid
                HStack(spacing: 12) {
                    // Compressing Card
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Compressing", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)

                        HStack {
                            Text("Speed:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(vm.compressSpeed)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        HStack {
                            Text("Rating (MIPS):")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(vm.compressRating)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Decompressing Card
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Decompressing", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)

                        HStack {
                            Text("Speed:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(vm.decompressSpeed)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        HStack {
                            Text("Rating (MIPS):")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(vm.decompressRating)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Overall Rating Card
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Total Rating", systemImage: "speedometer")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)

                        Spacer()

                        HStack {
                            Spacer()
                            Text(vm.totalRating)
                                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        HStack {
                            Spacer()
                            Text("MIPS")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                // Output log
                ScrollView {
                    Text(vm.logOutput.isEmpty ? "Click Start to run benchmark..." : vm.logOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .padding(.horizontal)
            }

            Divider()
                .padding(.top, 10)

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    vm.stopBenchmark()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 460)
        .onDisappear {
            vm.stopBenchmark()
        }
    }
}
