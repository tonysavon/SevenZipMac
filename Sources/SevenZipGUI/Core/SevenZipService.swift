import Foundation

public actor SevenZipService {
    public static let shared = SevenZipService()

    private var cachedBinaryPath: String?
    private var activeBenchmarkProcess: Process?

    public init() {}

    public func stopBenchmark() {
        if let proc = activeBenchmarkProcess, proc.isRunning {
            proc.terminate()
        }
        activeBenchmarkProcess = nil
    }

    public func findExecutablePath() -> String {
        if let cached = cachedBinaryPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        // 1. Check App bundle Resources (source-built Universal 7zz)
        if let bundlePath = Bundle.main.path(forResource: "7zz", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            cachedBinaryPath = bundlePath
            return bundlePath
        }

        // 2. Check debug scratch build & sibling binary locations
        let localCandidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("7zz").path,
            "/tmp/SevenZipMacBuild/7zz"
        ].compactMap { $0 }

        for path in localCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedBinaryPath = path
                return path
            }
        }

        // 3. Optional fallback to system paths if running bare binary without building Resources
        let candidatePaths = [
            "/opt/homebrew/bin/7zz",
            "/usr/local/bin/7zz",
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/7z",
            "/usr/bin/7zz",
            "/usr/bin/7z"
        ]

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedBinaryPath = path
                return path
            }
        }

        // 3. Fallback search via `which 7zz`
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["7zz"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()

        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                cachedBinaryPath = output
                return output
            }
        }

        return "/opt/homebrew/bin/7zz"
    }

    public func isAvailable() -> Bool {
        let path = findExecutablePath()
        return FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - List Archive
    public func listArchive(url: URL, password: String? = nil) async throws -> (metadata: ArchiveMetadata, entries: [RawArchiveEntry]) {
        let executable = findExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw NSError(domain: "SevenZipService", code: 1, userInfo: [NSLocalizedDescriptionKey: "7-Zip binary (7zz) not found. Please install via 'brew install sevenzip'."])
        }

        var arguments = ["l", "-slt"]
        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        } else {
            arguments.append("-p")
        }
        arguments.append(url.path)

        let output = try await runProcess(executable: executable, arguments: arguments)

        return parseSltOutput(output, archivePath: url.path)
    }

    // MARK: - Extract
    public func extract(
        archiveURL: URL,
        destinationURL: URL,
        selectedItems: [String]? = nil,
        password: String? = nil,
        overwriteMode: OverwriteMode = .overwrite,
        restoreFullPaths: Bool = true,
        pathMode: ExtractPathMode? = nil,
        eliminateRootDuplication: Bool = false,
        onProcessStarted: (@Sendable (pid_t) -> Void)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let executable = findExecutablePath()
        let effectivePathMode = pathMode ?? (restoreFullPaths ? .full : .none)

        var targetOutURL = destinationURL
        if eliminateRootDuplication, (selectedItems == nil || selectedItems?.isEmpty == true), effectivePathMode != .none {
            if let (_, entries) = try? await listArchive(url: archiveURL, password: password), !entries.isEmpty {
                var topComponents = Set<String>()
                var hasSingleRootFolder = true
                for entry in entries {
                    let norm = entry.path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard !norm.isEmpty else { continue }
                    if let slash = norm.firstIndex(of: "/") {
                        topComponents.insert(String(norm[..<slash]))
                    } else if entry.isFolder {
                        topComponents.insert(norm)
                    } else {
                        // A root-level file exists -> not a single root folder
                        hasSingleRootFolder = false
                        break
                    }
                    if topComponents.count > 1 {
                        hasSingleRootFolder = false
                        break
                    }
                }
                if hasSingleRootFolder,
                   let singleRoot = topComponents.first,
                   singleRoot == destinationURL.lastPathComponent {
                    targetOutURL = destinationURL.deletingLastPathComponent()
                }
            }
        }

        let cmd = (effectivePathMode == .none) ? "e" : "x"
        var arguments = [
            cmd,
            "-o\(targetOutURL.path)",
            "-y",
            overwriteMode.cliFlag
        ]

        if effectivePathMode == .absolute {
            arguments.append("-spf")
        }

        if onOutput != nil {
            arguments.append("-bsp1")
            arguments.append("-bb1")
        }

        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        } else {
            arguments.append("-p")
        }

        arguments.append(archiveURL.path)

        if let items = selectedItems, !items.isEmpty {
            arguments.append(contentsOf: items)
        }

        let process = Process()
        _ = try await runCustomProcess(
            process: process,
            executable: executable,
            arguments: arguments,
            onProcessStarted: onProcessStarted,
            onOutput: onOutput
        )
    }

    // MARK: - Compress / Add
    public func compress(
        sources: [URL],
        destinationArchiveURL: URL,
        options: CompressionOptions,
        onProcessStarted: (@Sendable (pid_t) -> Void)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let executable = findExecutablePath()
        var arguments = [
            options.updateMode.command,
            destinationArchiveURL.path,
            "-t\(options.format.rawValue)",
            "-y"
        ]
        arguments.append(contentsOf: options.updateMode.extraFlags)

        switch options.format {
        case .sevenZip:
            arguments.append("-mx=\(options.compressionLevel.rawValue)")
            let valid7z = CompressionMethod.availableMethods(for: .sevenZip)
            let method = valid7z.contains(options.compressionMethod) ? options.compressionMethod : .lzma2
            arguments.append("-m0=\(method.rawValue)")
            if options.compressionLevel != .store && method != .copy {
                if method == .lzma || method == .lzma2 || method == .ppmd || method == .bzip2 {
                    arguments.append("-md=\(options.dictionarySize)")
                }
                if method == .lzma || method == .lzma2 {
                    arguments.append("-mfb=\(options.wordSize)")
                }
            }
            let solidFlag: String
            switch options.solidBlockSize {
            case "non-solid": solidFlag = "off"
            case "solid": solidFlag = "on"
            default: solidFlag = options.solidBlockSize
            }
            arguments.append("-ms=\(solidFlag)")
            arguments.append("-mmt=\(options.threads)")

            if !options.password.isEmpty {
                arguments.append("-p\(options.password)")
                if options.encryptHeaders {
                    arguments.append("-mhe=on")
                }
            }
        case .zip:
            arguments.append("-mx=\(options.compressionLevel.rawValue)")
            let validZip = CompressionMethod.availableMethods(for: .zip)
            let method = validZip.contains(options.compressionMethod) ? options.compressionMethod : .deflate
            arguments.append("-mm=\(method.rawValue)")
            arguments.append("-mmt=\(options.threads)")
            if !options.password.isEmpty {
                arguments.append("-p\(options.password)")
                arguments.append("-mem=\(options.encryptionMethod.cliValue)")
            }
        case .tar, .wim:
            break
        }

        if let pathFlag = options.pathMode.cliFlag {
            arguments.append(pathFlag)
        }
        if options.deleteFilesAfterCompression {
            arguments.append("-sdel")
        }
        if options.compressSharedFiles {
            arguments.append("-ssw")
        }

        if onOutput != nil {
            arguments.append("-bsp1")
            arguments.append("-bb1")
        }

        if !options.volumeSize.isEmpty {
            arguments.append("-v\(options.volumeSize)")
        }

        let extraParams = options.customParameters
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        arguments.append(contentsOf: extraParams)

        for source in sources {
            arguments.append(source.path)
        }

        let process = Process()
        _ = try await runCustomProcess(
            process: process,
            executable: executable,
            arguments: arguments,
            onProcessStarted: onProcessStarted,
            onOutput: onOutput
        )
    }

    // MARK: - Test Archive
    public func testArchive(url: URL, password: String? = nil) async throws -> (success: Bool, output: String) {
        let executable = findExecutablePath()
        var arguments = ["t", "-y"]
        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        } else {
            arguments.append("-p")
        }
        arguments.append(url.path)

        do {
            let output = try await runProcess(executable: executable, arguments: arguments)
            let isOk = output.contains("Everything is Ok") || output.contains("Testing archive: ")
            return (isOk, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Delete from Archive
    public func delete(archiveURL: URL, relativePaths: [String], password: String? = nil) async throws {
        let executable = findExecutablePath()
        var arguments = ["d", "-y"]
        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        } else {
            arguments.append("-p")
        }
        arguments.append(archiveURL.path)
        arguments.append(contentsOf: relativePaths)
        _ = try await runProcess(executable: executable, arguments: arguments)
    }

    // MARK: - Rename inside Archive
    public func rename(archiveURL: URL, pairs: [(oldPath: String, newPath: String)], password: String? = nil) async throws {
        guard !pairs.isEmpty else { return }
        let executable = findExecutablePath()
        var arguments = ["rn", "-y"]
        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        } else {
            arguments.append("-p")
        }
        arguments.append(archiveURL.path)
        for pair in pairs {
            arguments.append(pair.oldPath)
            arguments.append(pair.newPath)
        }
        _ = try await runProcess(executable: executable, arguments: arguments)
    }

    // MARK: - Add files directly to an existing Archive (optionally under a subpath)
    public func addToExistingArchive(
        archiveURL: URL,
        sources: [URL],
        subpath: String = "",
        password: String? = nil,
        onProcessStarted: (@Sendable (pid_t) -> Void)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let executable = findExecutablePath()
        var arguments = ["a", "-y"]
        if onOutput != nil {
            arguments.append("-bsp1")
            arguments.append("-bb1")
        }
        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        }
        arguments.append(archiveURL.path)
        for source in sources {
            arguments.append(source.path)
        }

        let process = Process()
        _ = try await runCustomProcess(
            process: process,
            executable: executable,
            arguments: arguments,
            onProcessStarted: onProcessStarted,
            onOutput: onOutput
        )

        let normalizedSub = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalizedSub.isEmpty {
            let pairs = sources.map { src in
                (oldPath: src.lastPathComponent, newPath: "\(normalizedSub)/\(src.lastPathComponent)")
            }
            try await rename(archiveURL: archiveURL, pairs: pairs, password: password)
        }
    }

    // MARK: - Create Folder inside Archive
    public func createFolderInArchive(archiveURL: URL, subpath: String, folderName: String, password: String? = nil) async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SevenZipGUI_Mkdir", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folderURL = tempDir.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await addToExistingArchive(
            archiveURL: archiveURL,
            sources: [folderURL],
            subpath: subpath,
            password: password
        )
    }

    // MARK: - Compute Checksums / Hashes (`7zz h`)
    public func computeHashes(paths: [URL], algorithmFlag: String = "-scrc*") async throws -> String {
        guard !paths.isEmpty else { return "" }
        let executable = findExecutablePath()
        var arguments = ["h", algorithmFlag]
        arguments.append(contentsOf: paths.map(\.path))
        return try await runProcess(executable: executable, arguments: arguments)
    }

    // MARK: - Extract Single File To Temp
    public func extractSingleFileToTemp(archiveURL: URL, relativePath: String, password: String? = nil) async throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SevenZipGUI_Temp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let executable = findExecutablePath()
        var arguments = [
            "e",
            "-o\(tempDir.path)",
            "-y",
            "-aoa"
        ]
        if let pass = password, !pass.isEmpty {
            arguments.append("-p\(pass)")
        } else {
            arguments.append("-p")
        }
        arguments.append(archiveURL.path)
        arguments.append(relativePath)

        _ = try await runProcess(executable: executable, arguments: arguments)

        let filename = (relativePath as NSString).lastPathComponent
        let targetURL = tempDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        // If filename is altered or subfolder retained
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        if let first = contents.first {
            return first
        }

        throw NSError(domain: "SevenZipService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to extract temporary preview file."])
    }

    // MARK: - Run Benchmark Process
    public func runBenchmark(
        threads: Int,
        dictSizeMB: Int,
        iterations: Int = 1,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let executable = findExecutablePath()
        let arguments = ["b", "\(iterations)", "-mmt\(threads)", "-md=\(dictSizeMB)m"]
        let proc = Process()
        self.activeBenchmarkProcess = proc
        defer {
            if self.activeBenchmarkProcess === proc {
                self.activeBenchmarkProcess = nil
            }
        }
        return try await runCustomProcess(process: proc, executable: executable, arguments: arguments, onOutput: onOutput)
    }

    // MARK: - Private Process Runner
    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        let process = Process()
        return try await runCustomProcess(process: process, executable: executable, arguments: arguments, onOutput: nil)
    }

    private func runCustomProcess(
        process: Process,
        executable: String,
        arguments: [String],
        onProcessStarted: (@Sendable (pid_t) -> Void)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let coordinator = ProcessCoordinator(continuation: continuation)

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    if let str = String(data: data, encoding: .utf8) {
                        coordinator.appendOutput(str)
                        onOutput?(str)
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    if let str = String(data: data, encoding: .utf8) {
                        coordinator.appendError(str)
                    }
                }

                process.terminationHandler = { proc in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    let restOut = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let str = String(data: restOut, encoding: .utf8), !str.isEmpty {
                        coordinator.appendOutput(str)
                        onOutput?(str)
                    }

                    let restErr = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if let str = String(data: restErr, encoding: .utf8), !str.isEmpty {
                        coordinator.appendError(str)
                    }

                    coordinator.finish(status: proc.terminationStatus, reason: proc.terminationReason)
                }

                do {
                    try process.run()
                    onProcessStarted?(process.processIdentifier)
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                kill(process.processIdentifier, SIGCONT)
                process.terminate()
            }
        }
    }

    // MARK: - Parser for `7zz l -slt`
    private func parseSltOutput(_ output: String, archivePath: String) -> (metadata: ArchiveMetadata, entries: [RawArchiveEntry]) {
        var metadata = ArchiveMetadata(archivePath: archivePath)
        var entries: [RawArchiveEntry] = []

        let lines = output.components(separatedBy: .newlines)
        var isReadingItems = false
        var currentBlockProps: [String: String] = [:]

        func commitCurrentBlock() {
            guard !currentBlockProps.isEmpty else { return }

            if !isReadingItems {
                // Header block
                metadata.formatType = currentBlockProps["Type"] ?? ""
                metadata.physicalSize = Int64(currentBlockProps["Physical Size"] ?? "0") ?? 0
                metadata.headersSize = Int64(currentBlockProps["Headers Size"] ?? "0") ?? 0
                metadata.method = currentBlockProps["Method"] ?? ""
                metadata.solid = (currentBlockProps["Solid"] == "+")
                metadata.blocks = Int(currentBlockProps["Blocks"] ?? "0") ?? 0

                var propsList: [(key: String, value: String)] = []
                for (k, v) in currentBlockProps {
                    propsList.append((key: k, value: v))
                }
                propsList.sort { $0.key < $1.key }
                metadata.properties = propsList
            } else {
                // Entry block
                if let path = currentBlockProps["Path"] {
                    let size = Int64(currentBlockProps["Size"] ?? "0") ?? 0
                    let packedSize = Int64(currentBlockProps["Packed Size"] ?? "-1") ?? -1
                    let isFolder = (currentBlockProps["Folder"] == "+")
                    let isEncrypted = (currentBlockProps["Encrypted"] == "+")
                    let attributes = currentBlockProps["Attributes"] ?? ""
                    let crc = currentBlockProps["CRC"] ?? ""
                    let method = currentBlockProps["Method"] ?? ""

                    var date: Date? = nil
                    if let modString = currentBlockProps["Modified"] {
                        date = parseDate(modString)
                    }

                    entries.append(RawArchiveEntry(
                        path: path,
                        size: size,
                        packedSize: packedSize,
                        modified: date,
                        attributes: attributes,
                        crc: crc,
                        isEncrypted: isEncrypted,
                        method: method,
                        isFolder: isFolder
                    ))
                }
            }
            currentBlockProps.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.starts(with: "----------") {
                commitCurrentBlock()
                isReadingItems = true
                continue
            }

            if trimmed.isEmpty || trimmed == "--" {
                commitCurrentBlock()
                continue
            }

            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
                currentBlockProps[key] = value
            }
        }
        commitCurrentBlock()

        return (metadata, entries)
    }

    private func parseDate(_ string: String) -> Date? {
        let clean = string.components(separatedBy: ".").first ?? string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: clean)
    }
}

private final class ProcessCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var isDone = false
    private var output = ""
    private var error = ""
    private var continuation: CheckedContinuation<String, Error>?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func appendOutput(_ str: String) {
        lock.lock()
        defer { lock.unlock() }
        output += str
    }

    func appendError(_ str: String) {
        lock.lock()
        defer { lock.unlock() }
        error += str
    }

    func finish(status: Int32, reason: Process.TerminationReason) {
        lock.lock()
        defer { lock.unlock() }
        guard !isDone, let cont = continuation else { return }
        isDone = true
        continuation = nil

        if reason == .uncaughtSignal || status == 15 || status == 255 {
            cont.resume(throwing: CancellationError())
        } else if status == 0 {
            cont.resume(returning: output)
        } else {
            let combined = (error.isEmpty ? output : error).trimmingCharacters(in: .whitespacesAndNewlines)
            cont.resume(throwing: NSError(
                domain: "SevenZipService",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: combined.isEmpty ? "7-Zip process exited with code \(status)" : combined]
            ))
        }
    }
}
