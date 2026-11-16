import Foundation
import Darwin
import Combine

@MainActor
public final class OperationProgressState: ObservableObject, Identifiable {
    public let id = UUID()
    public let title: String
    public let archiveName: String

    @Published public var percentage: Double = 0
    @Published public var currentFile: String = "Scanning..."
    @Published public var totalBytes: Int64 = 0
    @Published public var processedBytes: Int64 = 0
    @Published public var filesProcessed: Int = 0
    @Published public var elapsedSeconds: TimeInterval = 0
    @Published public var isPaused: Bool = false
    @Published public var isBackgroundPriority: Bool = false
    @Published public var isCompleted: Bool = false
    @Published public var isCancelled: Bool = false
    @Published public var errorMessage: String?

    private var processPID: pid_t?
    private var runningTask: Task<Void, Never>?
    private var timer: Timer?
    private var lineBuffer: String = ""

    public init(title: String, archiveName: String, initialTotalBytes: Int64 = 0) {
        self.title = title
        self.archiveName = archiveName
        self.totalBytes = initialTotalBytes
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    public func attachTask(_ task: Task<Void, Never>) {
        self.runningTask = task
    }

    public func setProcessPID(_ pid: pid_t) {
        self.processPID = pid
        if isBackgroundPriority {
            setpriority(PRIO_PROCESS, id_t(pid), 10)
        }
        if isPaused {
            kill(pid, SIGSTOP)
        }
    }

    public func markCompleted(error: String? = nil) {
        timer?.invalidate()
        timer = nil
        if let err = error {
            self.errorMessage = err
        } else if !isCancelled {
            self.percentage = 100
            if totalBytes > 0 {
                self.processedBytes = totalBytes
            }
        }
        self.isCompleted = true
    }

    // MARK: - Controls
    public func togglePause() {
        guard !isCompleted, let pid = processPID else { return }
        if isPaused {
            kill(pid, SIGCONT)
            isPaused = false
        } else {
            kill(pid, SIGSTOP)
            isPaused = true
        }
    }

    public func toggleBackground() {
        isBackgroundPriority.toggle()
        if let pid = processPID {
            setpriority(PRIO_PROCESS, id_t(pid), isBackgroundPriority ? 10 : 0)
        }
    }

    public func cancel() {
        guard !isCompleted else { return }
        isCancelled = true
        if let pid = processPID {
            kill(pid, SIGCONT)
            kill(pid, SIGTERM)
        }
        runningTask?.cancel()
        timer?.invalidate()
        timer = nil
        errorMessage = "Operation cancelled by user."
        isCompleted = true
    }

    // MARK: - Stats Formatting
    public var speedBytesPerSec: Double {
        guard elapsedSeconds > 0.25, processedBytes > 0 else { return 0 }
        return Double(processedBytes) / elapsedSeconds
    }

    public var remainingSeconds: TimeInterval? {
        guard percentage >= 1.0, percentage < 100.0, elapsedSeconds > 0.5 else { return nil }
        let totalEstimated = elapsedSeconds / (percentage / 100.0)
        return max(0, totalEstimated - elapsedSeconds)
    }

    public var formattedElapsed: String {
        Self.formatDuration(elapsedSeconds)
    }

    public var formattedRemaining: String {
        guard let rem = remainingSeconds else { return "--:--:--" }
        return Self.formatDuration(rem)
    }

    public var formattedTotalSize: String {
        guard totalBytes > 0 else { return "Calculating..." }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var formattedProcessedSize: String {
        guard processedBytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: processedBytes, countStyle: .file)
    }

    public var formattedSpeed: String {
        guard speedBytesPerSec > 0 else { return "-" }
        let mbPerSec = speedBytesPerSec / (1024.0 * 1024.0)
        if mbPerSec >= 1.0 {
            return String(format: "%.1f MB/s", mbPerSec)
        } else {
            let kbPerSec = speedBytesPerSec / 1024.0
            return String(format: "%.0f KB/s", kbPerSec)
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isCompleted, !self.isPaused else { return }
                self.elapsedSeconds += 0.25
            }
        }
    }

    // MARK: - Live Output Parsing (`7zz -bsp1 -bb1`)
    public func ingestChunk(_ chunk: String) {
        let normalized = chunk
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{08}", with: "\n")
        lineBuffer += normalized

        let parts = lineBuffer.components(separatedBy: "\n")
        guard parts.count > 1 else { return }

        lineBuffer = parts.last ?? ""
        for rawLine in parts.dropLast() {
            parseLine(rawLine)
        }
    }

    private func parseLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }

        // 1. Total bytes from "Add new data to archive: 1 file, 15728640 bytes" or "Physical Size = 15729828"
        if line.contains("bytes"),
           let bytes = Self.extractBytesCount(from: line),
           bytes > totalBytes {
            totalBytes = bytes
        } else if line.hasPrefix("Physical Size = "),
                  let val = Int64(line.replacingOccurrences(of: "Physical Size = ", with: "").trimmingCharacters(in: .whitespaces)),
                  val > totalBytes {
            totalBytes = val
        } else if line.hasPrefix("Size:") {
            let numStr = line.replacingOccurrences(of: "Size:", with: "").trimmingCharacters(in: .whitespaces)
            if let val = Int64(numStr), val > 0 {
                totalBytes = max(totalBytes, val)
                processedBytes = val
            }
        }

        // 2. Progress percentage e.g. "49% 1" or "23%"
        if let (pct, files) = Self.extractPercentage(from: line) {
            let pctDouble = Double(pct)
            if pctDouble >= percentage || percentage == 0 {
                percentage = min(100, pctDouble)
                if totalBytes > 0 {
                    processedBytes = Int64(Double(totalBytes) * (percentage / 100.0))
                }
            }
            if let f = files {
                filesProcessed = max(filesProcessed, f)
            }
        }

        // 3. Current file line from `-bb1`: "+ path", "- path", "T path"
        if line.hasPrefix("+ ") || line.hasPrefix("- ") || line.hasPrefix("T ") {
            let file = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !file.isEmpty {
                currentFile = file
            }
        } else if line == "Everything is Ok" {
            percentage = 100
            currentFile = "Done"
        }
    }

    private static func extractPercentage(from line: String) -> (Int, Int?)? {
        // Matches lines like "23%" or "49% 1"
        guard let pctIdx = line.firstIndex(of: "%") else { return nil }
        let prefix = line[..<pctIdx].trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }), let pct = Int(prefix), pct <= 100 else {
            return nil
        }

        let suffix = line[line.index(after: pctIdx)...].trimmingCharacters(in: .whitespaces)
        if !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }), let files = Int(suffix) {
            return (pct, files)
        }
        return (pct, nil)
    }

    private static func extractBytesCount(from line: String) -> Int64? {
        guard let range = line.range(of: #"(\d+)\s+bytes"#, options: .regularExpression) else {
            return nil
        }
        let match = line[range]
        let digits = match.split(separator: " ").first.map(String.init) ?? ""
        return Int64(digits)
    }
}
