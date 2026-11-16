import Foundation
import AppKit
import SwiftUI
import Combine

public enum NavigationTarget: Equatable {
    case filesystem(url: URL)
    case archive(baseFilesystemURL: URL, frames: [ArchiveFrame])
}

@MainActor
public class FileManagerState: ObservableObject {
    @Published public var currentTarget: NavigationTarget = .filesystem(url: URL(fileURLWithPath: NSHomeDirectory()))
    @Published public var items: [FileItem] = []
    @Published public var selectedItemIDs: Set<String> = []
    @Published public var isLoading: Bool = false
    @Published public var statusText: String = ""
    @Published public var filterText: String = ""
    @Published public var addressBarText: String = ""

    // View Modes
    @Published public var showHiddenFiles: Bool = false
    @Published public var isFlatView: Bool = false

    // Sorting (wired to SwiftUI Table headers)
    @Published public var tableSortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\FileItem.name, order: .forward)
    ]

    // Archive Cache (keyed by archive file URL so nested archive navigation is instant)
    @Published public var activeArchiveMetadata: ArchiveMetadata?
    private var archiveCache: [URL: (metadata: ArchiveMetadata, entries: [RawArchiveEntry], password: String?)] = [:]
    private var activeRawEntries: [RawArchiveEntry] = []
    public private(set) var activeArchivePassword: String?

    // History
    private var historyBack: [NavigationTarget] = []
    private var historyForward: [NavigationTarget] = []
    private var isNavigatingHistory: Bool = false

    // Modals
    @Published public var showAddDialog: Bool = false
    @Published public var showExtractDialog: Bool = false
    @Published public var showTestDialog: Bool = false
    @Published public var showInfoDialog: Bool = false
    @Published public var showBenchmarkDialog: Bool = false
    @Published public var showChecksumDialog: Bool = false
    @Published public var checksumAlgorithm: String = "-scrc*"
    @Published public var showSplitDialog: Bool = false
    @Published public var showCombineDialog: Bool = false
    @Published public var showRenameDialog: Bool = false
    @Published public var showNewFolderDialog: Bool = false
    @Published public var showPasswordPrompt: Bool = false
    @Published public var externalAddURLs: [URL]? = nil
    @Published public var activeProgress: OperationProgressState?
    @Published public var passwordPromptTitle: String = "Enter Password"
    @Published public var passwordInput: String = ""
    @Published public var passwordPromptAction: ((String) -> Void)?
    @Published public var errorMessage: String?
    @Published public var testOutput: String = ""
    @Published public var testSuccess: Bool = true

    public var canGoBack: Bool { !historyBack.isEmpty }
    public var canGoForward: Bool { !historyForward.isEmpty }

    public var isInsideArchive: Bool {
        if case .archive = currentTarget { return true }
        return false
    }

    public var activeArchiveURL: URL? {
        if case .archive(_, let frames) = currentTarget {
            return frames.last?.archiveURL
        }
        return nil
    }

    public var currentArchiveSubpath: String {
        if case .archive(_, let frames) = currentTarget {
            return frames.last?.subpath ?? ""
        }
        return ""
    }

    public var currentArchiveIsTempNested: Bool {
        if case .archive(_, let frames) = currentTarget {
            return frames.last?.isTempExtracted ?? false
        }
        return false
    }

    public var currentFilesystemDirectoryURL: URL {
        switch currentTarget {
        case .filesystem(let url):
            return url
        case .archive(let baseURL, _):
            return baseURL
        }
    }

    public var currentDisplayPath: String {
        switch currentTarget {
        case .filesystem(let url):
            return url.path
        case .archive(let baseURL, let frames):
            var components = [baseURL.path]
            for frame in frames {
                components.append(frame.displayName)
                if !frame.subpath.isEmpty {
                    components.append(frame.subpath)
                }
            }
            return components.joined(separator: "/")
        }
    }

    public var selectedItems: [FileItem] {
        return items.filter { !$0.isParentEntry && selectedItemIDs.contains($0.id) }
    }

    public init() {
        var initialTarget: NavigationTarget = .filesystem(url: URL(fileURLWithPath: NSHomeDirectory()))

        let args = CommandLine.arguments
        if args.count > 1 {
            let path = args[1]
            if !path.starts(with: "-") {
                let expanded = (path as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
                    let url = URL(fileURLWithPath: expanded)
                    if isDir.boolValue {
                        initialTarget = .filesystem(url: url)
                    } else {
                        let ext = url.pathExtension.lowercased()
                        if FileItem.knownArchiveExtensions.contains(ext) {
                            let frame = ArchiveFrame(archiveURL: url, displayName: url.lastPathComponent, subpath: "", isTempExtracted: false)
                            initialTarget = .archive(baseFilesystemURL: url.deletingLastPathComponent(), frames: [frame])
                        }
                    }
                }
            }
        }

        self.currentTarget = initialTarget
        self.addressBarText = ""
        navigateTo(initialTarget, addToHistory: false)
    }

    // MARK: - Navigation
    public func openArchiveFile(url: URL) {
        let frame = ArchiveFrame(
            archiveURL: url,
            displayName: url.lastPathComponent,
            subpath: "",
            isTempExtracted: false
        )
        navigateTo(.archive(baseFilesystemURL: url.deletingLastPathComponent(), frames: [frame]))
    }

    public func navigateTo(_ target: NavigationTarget, addToHistory: Bool = true) {
        if addToHistory && !isNavigatingHistory {
            historyBack.append(currentTarget)
            historyForward.removeAll()
        }

        currentTarget = target
        addressBarText = currentDisplayPath
        selectedItemIDs.removeAll()
        reloadCurrent()
    }

    public func navigateBack() {
        guard let prev = historyBack.popLast() else { return }
        isNavigatingHistory = true
        historyForward.append(currentTarget)
        currentTarget = prev
        addressBarText = currentDisplayPath
        selectedItemIDs.removeAll()
        reloadCurrent()
        isNavigatingHistory = false
    }

    public func navigateForward() {
        guard let next = historyForward.popLast() else { return }
        isNavigatingHistory = true
        historyBack.append(currentTarget)
        currentTarget = next
        addressBarText = currentDisplayPath
        selectedItemIDs.removeAll()
        reloadCurrent()
        isNavigatingHistory = false
    }

    public func navigateUp() {
        switch currentTarget {
        case .filesystem(let url):
            let parent = url.deletingLastPathComponent()
            if parent.path != url.path {
                navigateTo(.filesystem(url: parent))
                selectedItemIDs = [url.path]
            }
        case .archive(let baseURL, var frames):
            guard let topFrame = frames.popLast() else {
                navigateTo(.filesystem(url: baseURL))
                return
            }

            if !topFrame.subpath.isEmpty {
                // Step up one folder inside the current archive frame
                let trimmed = topFrame.subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let parentSub: String
                if let lastSlash = trimmed.lastIndex(of: "/") {
                    parentSub = String(trimmed[..<lastSlash])
                } else {
                    parentSub = ""
                }
                let updated = ArchiveFrame(
                    archiveURL: topFrame.archiveURL,
                    displayName: topFrame.displayName,
                    subpath: parentSub,
                    isTempExtracted: topFrame.isTempExtracted
                )
                frames.append(updated)
                navigateTo(.archive(baseFilesystemURL: baseURL, frames: frames))
            } else if !frames.isEmpty {
                // Pop nested archive frame and return to outer archive!
                navigateTo(.archive(baseFilesystemURL: baseURL, frames: frames))
            } else {
                // Exit archive back to its enclosing filesystem directory
                navigateTo(.filesystem(url: baseURL))
                selectedItemIDs = [topFrame.archiveURL.path]
            }
        }
    }

    // MARK: - View Mode Toggles
    public func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        reloadCurrent()
    }

    public func toggleFlatView() {
        isFlatView.toggle()
        reloadCurrent()
    }

    // MARK: - Reloading Items
    public func reloadCurrent(forceRefreshArchive: Bool = false) {
        switch currentTarget {
        case .filesystem(let url):
            loadFilesystemDirectory(url: url, flatView: isFlatView, includeHidden: showHiddenFiles)
        case .archive(_, let frames):
            guard let top = frames.last else { return }
            if forceRefreshArchive {
                archiveCache.removeValue(forKey: top.archiveURL)
            }
            loadArchiveDirectory(url: top.archiveURL, subpath: top.subpath, flatView: isFlatView)
        }
    }

    private func loadFilesystemDirectory(url: URL, flatView: Bool, includeHidden: Bool) {
        isLoading = true
        activeArchiveMetadata = nil
        activeRawEntries.removeAll()
        activeArchivePassword = nil

        let shouldIncludeParent = url.path != "/"

        Task.detached {
            let fm = FileManager.default
            do {
                var result: [FileItem] = []

                if flatView {
                    let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                    if let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                        options: options
                    ) {
                        let basePrefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
                        var count = 0
                        let maxFlatItems = 10_000
                        while let fileURL = enumerator.nextObject() as? URL {
                            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                            let isDir = resourceValues?.isDirectory ?? false
                            if isDir { continue }

                            let size = Int64(resourceValues?.fileSize ?? 0)
                            let modified = resourceValues?.contentModificationDate
                            let ext = fileURL.pathExtension.lowercased()
                            let isArchive = FileItem.knownArchiveExtensions.contains(ext)
                            let relName = fileURL.path.hasPrefix(basePrefix)
                                ? String(fileURL.path.dropFirst(basePrefix.count))
                                : fileURL.lastPathComponent

                            result.append(FileItem(
                                id: fileURL.path,
                                name: relName,
                                fullPath: fileURL.path,
                                isDirectory: false,
                                isArchive: isArchive,
                                isArchiveInternal: false,
                                size: size,
                                packedSize: nil,
                                modified: modified,
                                attributes: "A",
                                crc: nil,
                                method: nil,
                                isEncrypted: false
                            ))
                            count += 1
                            if count >= maxFlatItems { break }
                        }
                    }
                } else {
                    let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                    let fileURLs = try fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                        options: options
                    )

                    for fileURL in fileURLs {
                        let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                        let isDir = resourceValues?.isDirectory ?? false
                        let size = Int64(resourceValues?.fileSize ?? 0)
                        let modified = resourceValues?.contentModificationDate
                        let ext = fileURL.pathExtension.lowercased()
                        let isArchive = !isDir && FileItem.knownArchiveExtensions.contains(ext)

                        result.append(FileItem(
                            id: fileURL.path,
                            name: fileURL.lastPathComponent,
                            fullPath: fileURL.path,
                            isDirectory: isDir,
                            isArchive: isArchive,
                            isArchiveInternal: false,
                            size: size,
                            packedSize: nil,
                            modified: modified,
                            attributes: isDir ? "D" : "A",
                            crc: nil,
                            method: nil,
                            isEncrypted: false
                        ))
                    }
                }

                let finalResult = result
                await MainActor.run {
                    self.items = shouldIncludeParent ? [FileItem.parentEntry()] + finalResult : finalResult
                    self.sortItems()
                    self.updateStatusText()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.items = shouldIncludeParent ? [FileItem.parentEntry()] : []
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func loadArchiveDirectory(url: URL, subpath: String, flatView: Bool) {
        if let cached = archiveCache[url] {
            self.activeArchiveMetadata = cached.metadata
            self.activeRawEntries = cached.entries
            self.activeArchivePassword = cached.password
            let built = flatView
                ? ArchiveVirtualHierarchy.flatItemsForSubpath(subpath, rawEntries: cached.entries)
                : ArchiveVirtualHierarchy.itemsForSubpath(subpath, rawEntries: cached.entries, archiveURL: url)
            self.items = [FileItem.parentEntry()] + built
            self.sortItems()
            self.updateStatusText()
            return
        }

        isLoading = true
        statusText = "Reading archive..."

        Task {
            do {
                let (meta, raw) = try await SevenZipService.shared.listArchive(url: url, password: activeArchivePassword)
                self.archiveCache[url] = (meta, raw, activeArchivePassword)
                self.activeArchiveMetadata = meta
                self.activeRawEntries = raw
                let built = flatView
                    ? ArchiveVirtualHierarchy.flatItemsForSubpath(subpath, rawEntries: raw)
                    : ArchiveVirtualHierarchy.itemsForSubpath(subpath, rawEntries: raw, archiveURL: url)
                self.items = [FileItem.parentEntry()] + built
                self.sortItems()
                self.updateStatusText()
                self.isLoading = false
            } catch {
                self.isLoading = false
                let errStr = error.localizedDescription
                if errStr.localizedCaseInsensitiveContains("wrong password") ||
                    errStr.localizedCaseInsensitiveContains("encrypted") ||
                    errStr.localizedCaseInsensitiveContains("password") {
                    self.promptPassword(title: "Encrypted Archive") { [weak self] enteredPassword in
                        self?.activeArchivePassword = enteredPassword
                        self?.loadArchiveDirectory(url: url, subpath: subpath, flatView: flatView)
                    }
                } else {
                    self.errorMessage = errStr
                }
            }
        }
    }

    // MARK: - Sorting
    public func applySortOrder(_ newOrder: [KeyPathComparator<FileItem>]) {
        tableSortOrder = newOrder
        sortItems()
    }

    private func sortItems() {
        let parentRows = items.filter { $0.isParentEntry }
        var realItems = items.filter { !$0.isParentEntry }

        realItems.sort { a, b in
            // Folders always grouped at top (classic 7-Zip behavior)
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            if let primary = tableSortOrder.first {
                let res = primary.compare(a, b)
                if res != .orderedSame {
                    return res == .orderedAscending
                }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        items = parentRows + realItems
    }

    private func updateStatusText() {
        let realItems = items.filter { !$0.isParentEntry }
        let totalItems = realItems.count
        let totalBytes = realItems.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
        let sizeString = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        let selected = selectedItems
        if selected.isEmpty {
            statusText = "\(totalItems) object(s)   \(sizeString)"
        } else {
            let selBytes = selected.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
            let selSizeString = ByteCountFormatter.string(fromByteCount: selBytes, countStyle: .file)
            statusText = "\(selected.count) of \(totalItems) selected   \(selSizeString)"
        }
    }

    public func onSelectionChanged() {
        updateStatusText()
    }

    // MARK: - Opening & Quick Look
    public func openSelectedItem() {
        if selectedItemIDs.contains(FileItem.parentRowID) {
            navigateUp()
            return
        }
        guard let first = selectedItems.first else { return }
        handleItemDoubleClick(first)
    }

    public func handleItemDoubleClick(_ item: FileItem) {
        if item.isParentEntry {
            navigateUp()
            return
        }

        if item.isDirectory {
            if item.isArchiveInternal {
                guard case .archive(let baseURL, var frames) = currentTarget,
                      let currentFrame = frames.popLast() else { return }
                let updated = ArchiveFrame(
                    archiveURL: currentFrame.archiveURL,
                    displayName: currentFrame.displayName,
                    subpath: item.fullPath,
                    isTempExtracted: currentFrame.isTempExtracted
                )
                frames.append(updated)
                navigateTo(.archive(baseFilesystemURL: baseURL, frames: frames))
            } else {
                navigateTo(.filesystem(url: URL(fileURLWithPath: item.fullPath)))
            }
        } else if item.isArchive {
            if item.isArchiveInternal {
                // Nested archive! Extract to temp and push a new ArchiveFrame onto the stack
                guard case .archive(let baseURL, var frames) = currentTarget,
                      let currentArchiveURL = frames.last?.archiveURL else { return }

                isLoading = true
                statusText = "Opening nested archive \(item.name)..."
                Task {
                    do {
                        let tempURL = try await SevenZipService.shared.extractSingleFileToTemp(
                            archiveURL: currentArchiveURL,
                            relativePath: item.fullPath,
                            password: activeArchivePassword
                        )
                        let nestedFrame = ArchiveFrame(
                            archiveURL: tempURL,
                            displayName: (item.name as NSString).lastPathComponent,
                            subpath: "",
                            isTempExtracted: true
                        )
                        frames.append(nestedFrame)
                        self.isLoading = false
                        self.navigateTo(.archive(baseFilesystemURL: baseURL, frames: frames))
                    } catch {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                        self.updateStatusText()
                    }
                }
            } else {
                openArchiveFile(url: URL(fileURLWithPath: item.fullPath))
            }
        } else if item.isArchiveInternal {
            guard let arcURL = activeArchiveURL else { return }
            Task {
                do {
                    let tempURL = try await SevenZipService.shared.extractSingleFileToTemp(
                        archiveURL: arcURL,
                        relativePath: item.fullPath,
                        password: activeArchivePassword
                    )
                    NSWorkspace.shared.open(tempURL)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.fullPath))
        }
    }

    public func quickLookSelectedItem() {
        guard let item = selectedItems.first, !item.isDirectory else { return }
        if item.isArchiveInternal {
            guard let arcURL = activeArchiveURL else { return }
            Task {
                do {
                    let tempURL = try await SevenZipService.shared.extractSingleFileToTemp(
                        archiveURL: arcURL,
                        relativePath: item.fullPath,
                        password: activeArchivePassword
                    )
                    QuickLookCoordinator.shared.preview(urls: [tempURL])
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        } else {
            let urls = selectedItems.filter { !$0.isDirectory }.map { URL(fileURLWithPath: $0.fullPath) }
            QuickLookCoordinator.shared.preview(urls: urls)
        }
    }

    // MARK: - Actions
    public func testCurrentArchive() {
        let arcURL: URL?
        if let active = activeArchiveURL {
            arcURL = active
        } else if let first = selectedItems.first(where: { $0.isArchive }) {
            arcURL = URL(fileURLWithPath: first.fullPath)
        } else {
            arcURL = nil
        }

        guard let targetArc = arcURL else {
            self.errorMessage = "Please select or open an archive to test."
            return
        }

        isLoading = true
        statusText = "Testing archive integrity..."

        Task {
            do {
                let result = try await SevenZipService.shared.testArchive(url: targetArc, password: self.activeArchivePassword)
                self.isLoading = false
                self.testSuccess = result.success
                self.testOutput = result.output
                self.showTestDialog = true
                self.updateStatusText()
            } catch {
                self.isLoading = false
                self.testSuccess = false
                self.testOutput = error.localizedDescription
                self.showTestDialog = true
                self.updateStatusText()
            }
        }
    }

    public func deleteSelected() {
        guard !selectedItems.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Confirm Delete"
        alert.informativeText = "Are you sure you want to delete \(selectedItems.count) item(s)?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        if alert.runModal() == .alertFirstButtonReturn {
            switch currentTarget {
            case .filesystem:
                let fm = FileManager.default
                for item in selectedItems {
                    try? fm.removeItem(atPath: item.fullPath)
                }
                reloadCurrent()
            case .archive(_, let frames):
                guard let arcURL = frames.last?.archiveURL else { return }
                let paths = selectedItems.map(\.fullPath)
                Task {
                    do {
                        try await SevenZipService.shared.delete(archiveURL: arcURL, relativePaths: paths)
                        self.reloadCurrent(forceRefreshArchive: true)
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    public func promptPassword(title: String, action: @escaping (String) -> Void) {
        self.passwordPromptTitle = title
        self.passwordPromptAction = action
        self.passwordInput = ""
        self.showPasswordPrompt = true
    }

    // MARK: - Progress-Tracked Operations
    public func startCompressOperation(
        sources: [URL],
        destinationArchiveURL: URL,
        options: CompressionOptions
    ) {
        let progress = OperationProgressState(
            title: "Compressing",
            archiveName: destinationArchiveURL.lastPathComponent
        )
        self.activeProgress = progress

        let task = Task {
            do {
                try await SevenZipService.shared.compress(
                    sources: sources,
                    destinationArchiveURL: destinationArchiveURL,
                    options: options,
                    onProcessStarted: { pid in
                        Task { @MainActor in
                            progress.setProcessPID(pid)
                        }
                    },
                    onOutput: { chunk in
                        Task { @MainActor in
                            progress.ingestChunk(chunk)
                        }
                    }
                )
                progress.markCompleted(error: nil)
                self.reloadCurrent(forceRefreshArchive: true)
                try? await Task.sleep(nanoseconds: 450_000_000)
                if self.activeProgress?.id == progress.id && !progress.isCancelled {
                    self.activeProgress = nil
                }
            } catch {
                if !progress.isCancelled {
                    progress.markCompleted(error: error.localizedDescription)
                }
            }
        }
        progress.attachTask(task)
    }

    public func startExtractOperation(
        archiveURL: URL,
        destinationURL: URL,
        selectedItems: [String]?,
        password: String?,
        overwriteMode: OverwriteMode,
        restoreFullPaths: Bool,
        pathMode: ExtractPathMode = .full,
        eliminateRootDuplication: Bool = false,
        onCompleted: (@MainActor () async -> Void)? = nil
    ) {
        let initialSize = activeArchiveMetadata?.physicalSize ?? 0
        let progress = OperationProgressState(
            title: "Extracting",
            archiveName: archiveURL.lastPathComponent,
            initialTotalBytes: initialSize
        )
        self.activeProgress = progress

        let task = Task {
            do {
                try await SevenZipService.shared.extract(
                    archiveURL: archiveURL,
                    destinationURL: destinationURL,
                    selectedItems: selectedItems,
                    password: password,
                    overwriteMode: overwriteMode,
                    restoreFullPaths: restoreFullPaths,
                    pathMode: pathMode,
                    eliminateRootDuplication: eliminateRootDuplication,
                    onProcessStarted: { pid in
                        Task { @MainActor in
                            progress.setProcessPID(pid)
                        }
                    },
                    onOutput: { chunk in
                        Task { @MainActor in
                            progress.ingestChunk(chunk)
                        }
                    }
                )
                if let onCompleted = onCompleted {
                    await onCompleted()
                }
                progress.markCompleted(error: nil)
                self.reloadCurrent(forceRefreshArchive: true)
                try? await Task.sleep(nanoseconds: 450_000_000)
                if self.activeProgress?.id == progress.id && !progress.isCancelled {
                    self.activeProgress = nil
                }
            } catch {
                if !progress.isCancelled {
                    progress.markCompleted(error: error.localizedDescription)
                }
            }
        }
        progress.attachTask(task)
    }

    public func startAddToExistingArchiveOperation(
        archiveURL: URL,
        sources: [URL],
        subpath: String,
        password: String?,
        onCompleted: (@MainActor () async -> Void)? = nil
    ) {
        let progress = OperationProgressState(
            title: "Adding to",
            archiveName: archiveURL.lastPathComponent
        )
        self.activeProgress = progress

        let task = Task {
            do {
                try await SevenZipService.shared.addToExistingArchive(
                    archiveURL: archiveURL,
                    sources: sources,
                    subpath: subpath,
                    password: password,
                    onProcessStarted: { pid in
                        Task { @MainActor in
                            progress.setProcessPID(pid)
                        }
                    },
                    onOutput: { chunk in
                        Task { @MainActor in
                            progress.ingestChunk(chunk)
                        }
                    }
                )
                if let onCompleted = onCompleted {
                    await onCompleted()
                }
                progress.markCompleted(error: nil)
                self.reloadCurrent(forceRefreshArchive: true)
                try? await Task.sleep(nanoseconds: 450_000_000)
                if self.activeProgress?.id == progress.id && !progress.isCancelled {
                    self.activeProgress = nil
                }
            } catch {
                if !progress.isCancelled {
                    progress.markCompleted(error: error.localizedDescription)
                }
            }
        }
        progress.attachTask(task)
    }

    // MARK: - Tools & Clipboard
    public func openChecksum(algorithm: String = "-scrc*") {
        guard !selectedItems.isEmpty || isInsideArchive else {
            self.errorMessage = "Please select one or more files to compute checksums."
            return
        }
        self.checksumAlgorithm = algorithm
        self.showChecksumDialog = true
    }

    public func copySelectedToClipboard() {
        let selected = selectedItems
        guard !selected.isEmpty else { return }

        if !isInsideArchive {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let urls = selected.map { URL(fileURLWithPath: $0.fullPath) as NSURL }
            pasteboard.writeObjects(urls)
            ArchiveClipboardBuffer.shared.clear()
            statusText = "Copied \(selected.count) item(s) to clipboard"
        } else if let arcURL = activeArchiveURL {
            ArchiveClipboardBuffer.shared.set(
                archiveURL: arcURL,
                relativePaths: selected.map(\.fullPath),
                password: activeArchivePassword
            )
            statusText = "Copied \(selected.count) archive item(s)"
        }
    }

    public func pasteFromClipboard(onComplete: (@MainActor () -> Void)? = nil) {
        // 1. Check macOS Pasteboard for file URLs (from Finder or filesystem pane)
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            if isInsideArchive {
                guard let targetArc = activeArchiveURL else { return }
                if currentArchiveIsTempNested {
                    errorMessage = "Cannot paste files into a temporary nested archive."
                    return
                }
                startAddToExistingArchiveOperation(
                    archiveURL: targetArc,
                    sources: urls,
                    subpath: currentArchiveSubpath,
                    password: activeArchivePassword
                ) {
                    onComplete?()
                }
            } else {
                let destFolder = currentFilesystemDirectoryURL
                isLoading = true
                statusText = "Pasting \(urls.count) item(s)..."
                Task.detached {
                    let fm = FileManager.default
                    var lastError: Error?
                    for src in urls {
                        let target = destFolder.appendingPathComponent(src.lastPathComponent)
                        if src.path == target.path { continue }
                        do {
                            if fm.fileExists(atPath: target.path) {
                                try fm.removeItem(at: target)
                            }
                            try fm.copyItem(at: src, to: target)
                        } catch {
                            lastError = error
                        }
                    }
                    let err = lastError
                    await MainActor.run {
                        self.isLoading = false
                        if let err = err { self.errorMessage = err.localizedDescription }
                        self.reloadCurrent()
                        onComplete?()
                    }
                }
            }
            return
        }

        // 2. Fallback: ArchiveClipboardBuffer (copied from an archive pane)
        if let arcClip = ArchiveClipboardBuffer.shared.get() {
            if !isInsideArchive {
                startExtractOperation(
                    archiveURL: arcClip.archiveURL,
                    destinationURL: currentFilesystemDirectoryURL,
                    selectedItems: arcClip.relativePaths,
                    password: arcClip.password,
                    overwriteMode: .overwrite,
                    restoreFullPaths: true
                ) {
                    onComplete?()
                }
            }
        }
    }
}

@MainActor
public final class ArchiveClipboardBuffer {
    public static let shared = ArchiveClipboardBuffer()
    private var archiveURL: URL?
    private var relativePaths: [String] = []
    private var password: String?

    private init() {}

    public func set(archiveURL: URL, relativePaths: [String], password: String?) {
        self.archiveURL = archiveURL
        self.relativePaths = relativePaths
        self.password = password
    }

    public func clear() {
        archiveURL = nil
        relativePaths = []
        password = nil
    }

    public func get() -> (archiveURL: URL, relativePaths: [String], password: String?)? {
        guard let url = archiveURL, !relativePaths.isEmpty else { return nil }
        return (url, relativePaths, password)
    }
}
