import Foundation
import SwiftUI
import Combine

public enum PaneSide: String {
    case left
    case right
}

@MainActor
public final class DragSessionContext {
    public static let shared = DragSessionContext()

    public var sourcePaneSide: PaneSide?
    public var draggedItems: [FileItem] = []
    public var sourceArchiveURL: URL?
    public var sourceArchivePassword: String?
    public var timestamp: Date = .distantPast

    private init() {}

    public func isActive(withinSeconds seconds: TimeInterval = 5.0) -> Bool {
        return !draggedItems.isEmpty && Date().timeIntervalSince(timestamp) < seconds
    }

    public func clear() {
        sourcePaneSide = nil
        draggedItems = []
        sourceArchiveURL = nil
        sourceArchivePassword = nil
        timestamp = .distantPast
    }
}

@MainActor
public final class WorkspaceState: ObservableObject {
    @Published public var leftPane = FileManagerState()
    @Published public var rightPane = FileManagerState()
    @Published public var isDualPane: Bool = false
    @Published public var activePaneSide: PaneSide = .left

    // Copy / Move Dialog
    @Published public var showCopyMoveDialog: Bool = false
    @Published public var copyMoveIsMove: Bool = false

    private var cancellables = Set<AnyCancellable>()

    public var activePane: FileManagerState {
        if isDualPane && activePaneSide == .right {
            return rightPane
        }
        return leftPane
    }

    public var inactivePane: FileManagerState? {
        guard isDualPane else { return nil }
        return activePaneSide == .left ? rightPane : leftPane
    }

    public init() {
        // Forward child pane objectWillChange notifications so Toolbar and MainView update reactively
        leftPane.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        rightPane.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        bindMenuNotifications()
        handleLaunchArgumentsIfNeeded()
    }

    private func handleLaunchArgumentsIfNeeded() {
        let args = CommandLine.arguments
        guard args.count >= 3 else { return }
        let mode = args[1]
        let filePaths = Array(args.dropFirst(2)).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        guard let firstURL = filePaths.first else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let pane = self.leftPane
            pane.navigateTo(.filesystem(url: firstURL.deletingLastPathComponent()), addToHistory: false)

            switch mode {
            case "--add":
                pane.externalAddURLs = filePaths
                pane.showAddDialog = true
            case "--compress-7z":
                let parent = firstURL.deletingLastPathComponent()
                let archiveName: String
                if filePaths.count == 1 {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: firstURL.path, isDirectory: &isDir)
                    let base = isDir.boolValue ? firstURL.lastPathComponent : firstURL.deletingPathExtension().lastPathComponent
                    archiveName = "\(base).7z"
                } else {
                    archiveName = "Archive.7z"
                }
                let destURL = parent.appendingPathComponent(archiveName)
                pane.startCompressOperation(
                    sources: filePaths,
                    destinationArchiveURL: destURL,
                    options: CompressionOptions()
                )
            case "--extract-here":
                pane.startExtractOperation(
                    archiveURL: firstURL,
                    destinationURL: firstURL.deletingLastPathComponent(),
                    selectedItems: nil,
                    password: nil,
                    overwriteMode: .overwrite,
                    restoreFullPaths: true
                )
            case "--extract-folder":
                pane.startExtractOperation(
                    archiveURL: firstURL,
                    destinationURL: firstURL.deletingPathExtension(),
                    selectedItems: nil,
                    password: nil,
                    overwriteMode: .overwrite,
                    restoreFullPaths: true,
                    pathMode: .full,
                    eliminateRootDuplication: true
                )
            default:
                break
            }
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping (WorkspaceState) -> Void) {
        NotificationCenter.default.publisher(for: name)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                handler(self)
            }
            .store(in: &cancellables)
    }

    private func bindMenuNotifications() {
        observe(.testArchiveNotification) { $0.activePane.testCurrentArchive() }
        observe(.addToArchiveNotification) { ws in
            let pane = ws.activePane
            if !pane.isInsideArchive && !pane.selectedItems.isEmpty {
                pane.showAddDialog = true
            }
        }
        observe(.extractArchiveNotification) { $0.activePane.showExtractDialog = true }
        observe(.benchmarkNotification) { $0.activePane.showBenchmarkDialog = true }
        observe(.navigateUpNotification) { $0.activePane.navigateUp() }
        observe(.navigateBackNotification) { $0.activePane.navigateBack() }
        observe(.navigateForwardNotification) { $0.activePane.navigateForward() }
        observe(.toggleFlatViewNotification) { $0.activePane.toggleFlatView() }
        observe(.toggleHiddenFilesNotification) { $0.activePane.toggleHiddenFiles() }
        observe(.refreshNotification) { $0.activePane.reloadCurrent(forceRefreshArchive: true) }
        observe(.toggleDualPaneNotification) { $0.toggleDualPane() }
        observe(.copyToNotification) { $0.openCopyDialog() }
        observe(.moveToNotification) { $0.openMoveDialog() }
        observe(.newFolderNotification) { $0.activePane.showNewFolderDialog = true }
        observe(.renameNotification) { ws in
            if !ws.activePane.selectedItems.isEmpty {
                ws.activePane.showRenameDialog = true
            }
        }
        observe(.getInfoNotification) { ws in
            let pane = ws.activePane
            if pane.isInsideArchive || !pane.selectedItems.isEmpty {
                pane.showInfoDialog = true
            }
        }
        observe(.checksumNotification) { $0.activePane.openChecksum() }
        observe(.splitFileNotification) { $0.activePane.showSplitDialog = true }
        observe(.combineFilesNotification) { $0.activePane.showCombineDialog = true }
        observe(.installFinderActionsNotification) { ws in
            do {
                try FinderQuickActionsInstaller.install()
                let alert = NSAlert()
                alert.messageText = "Finder Quick Actions Installed"
                alert.informativeText = "Right-click any file or folder in Finder -> Quick Actions (or Services) to access:\n• 7-Zip - Add to Archive\n• 7-Zip - Add to .7z\n• 7-Zip - Extract Here\n• 7-Zip - Extract to Folder"
                alert.alertStyle = .informational
                alert.runModal()
            } catch {
                ws.activePane.errorMessage = error.localizedDescription
            }
        }
        observe(.uninstallFinderActionsNotification) { ws in
            do {
                try FinderQuickActionsInstaller.uninstall()
                let alert = NSAlert()
                alert.messageText = "Finder Quick Actions Removed"
                alert.informativeText = "7-Zip Quick Actions have been removed from ~/Library/Services."
                alert.alertStyle = .informational
                alert.runModal()
            } catch {
                ws.activePane.errorMessage = error.localizedDescription
            }
        }
    }

    public func pane(for side: PaneSide) -> FileManagerState {
        return side == .left ? leftPane : rightPane
    }

    public func activatePane(_ side: PaneSide) {
        if activePaneSide != side {
            activePaneSide = side
        }
    }

    public func toggleDualPane() {
        isDualPane.toggle()
        if !isDualPane {
            activePaneSide = .left
        } else {
            // Sync right pane to left pane's current filesystem folder on first open if it hasn't navigated yet
            if case .filesystem(let rURL) = rightPane.currentTarget,
               rURL.path == NSHomeDirectory(),
               case .filesystem(let lURL) = leftPane.currentTarget,
               lURL.path != NSHomeDirectory() {
                rightPane.navigateTo(.filesystem(url: lURL), addToHistory: false)
            }
        }
    }

    public func switchActivePane() {
        guard isDualPane else { return }
        activePaneSide = (activePaneSide == .left) ? .right : .left
    }

    public func openCopyDialog() {
        guard !activePane.selectedItems.isEmpty else { return }
        copyMoveIsMove = false
        showCopyMoveDialog = true
    }

    public func openMoveDialog() {
        guard !activePane.selectedItems.isEmpty else { return }
        copyMoveIsMove = true
        showCopyMoveDialog = true
    }

    public func refreshBothPanesIfNeeded() {
        leftPane.reloadCurrent(forceRefreshArchive: true)
        if isDualPane {
            rightPane.reloadCurrent(forceRefreshArchive: true)
        }
    }

    // MARK: - Universal Transfer (Copy / Move / Drag & Drop)
    public func transferItems(
        _ items: [FileItem],
        from sourcePane: FileManagerState,
        toFilesystemFolder destFolder: URL,
        isMove: Bool,
        overwrite: Bool = true
    ) {
        guard !items.isEmpty else { return }

        if sourcePane.isInsideArchive {
            guard let arcURL = sourcePane.activeArchiveURL else { return }
            let paths = items.map(\.fullPath)
            let canDeleteFromSource = isMove && !sourcePane.currentArchiveIsTempNested
            let password = sourcePane.activeArchivePassword

            sourcePane.startExtractOperation(
                archiveURL: arcURL,
                destinationURL: destFolder,
                selectedItems: paths,
                password: password,
                overwriteMode: overwrite ? .overwrite : .skip,
                restoreFullPaths: true
            ) { [weak self] in
                if canDeleteFromSource {
                    try? await SevenZipService.shared.delete(archiveURL: arcURL, relativePaths: paths, password: password)
                }
                self?.refreshBothPanesIfNeeded()
            }
        } else {
            // Filesystem -> Filesystem
            let sourceURLs = items.map { URL(fileURLWithPath: $0.fullPath) }
            copyOrMoveFilesystemURLs(
                sourceURLs,
                toFolder: destFolder,
                isMove: isMove,
                overwrite: overwrite,
                reportingTo: sourcePane
            )
        }
    }

    public func transferItems(
        _ items: [FileItem],
        from sourcePane: FileManagerState,
        toArchive targetArchiveURL: URL,
        subpath: String,
        targetPassword: String?,
        isMove: Bool
    ) {
        guard !items.isEmpty else { return }

        if !sourcePane.isInsideArchive {
            let sourceURLs = items.map { URL(fileURLWithPath: $0.fullPath) }
            sourcePane.startAddToExistingArchiveOperation(
                archiveURL: targetArchiveURL,
                sources: sourceURLs,
                subpath: subpath,
                password: targetPassword
            ) { [weak self] in
                if isMove {
                    let fm = FileManager.default
                    for url in sourceURLs {
                        try? fm.removeItem(at: url)
                    }
                }
                self?.refreshBothPanesIfNeeded()
            }
        } else if let srcArchiveURL = sourcePane.activeArchiveURL {
            // Archive -> Archive via temp staging directory
            let paths = items.map(\.fullPath)
            let srcPass = sourcePane.activeArchivePassword
            let canDeleteFromSource = isMove && !sourcePane.currentArchiveIsTempNested

            sourcePane.isLoading = true
            sourcePane.statusText = "Transferring between archives..."
            Task {
                let stageDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("SevenZipGUI_Stage", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
                    try await SevenZipService.shared.extract(
                        archiveURL: srcArchiveURL,
                        destinationURL: stageDir,
                        selectedItems: paths,
                        password: srcPass,
                        overwriteMode: .overwrite,
                        restoreFullPaths: false
                    )
                    let stagedFiles = try FileManager.default.contentsOfDirectory(at: stageDir, includingPropertiesForKeys: nil)
                    if !stagedFiles.isEmpty {
                        try await SevenZipService.shared.addToExistingArchive(
                            archiveURL: targetArchiveURL,
                            sources: stagedFiles,
                            subpath: subpath,
                            password: targetPassword
                        )
                    }
                    if canDeleteFromSource {
                        try? await SevenZipService.shared.delete(archiveURL: srcArchiveURL, relativePaths: paths, password: srcPass)
                    }
                    try? FileManager.default.removeItem(at: stageDir)
                    await MainActor.run {
                        sourcePane.isLoading = false
                        self.refreshBothPanesIfNeeded()
                    }
                } catch {
                    try? FileManager.default.removeItem(at: stageDir)
                    await MainActor.run {
                        sourcePane.isLoading = false
                        sourcePane.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    public func copyOrMoveFilesystemURLs(
        _ sourceURLs: [URL],
        toFolder destFolder: URL,
        isMove: Bool,
        overwrite: Bool,
        reportingTo pane: FileManagerState
    ) {
        pane.isLoading = true
        pane.statusText = isMove ? "Moving \(sourceURLs.count) item(s)..." : "Copying \(sourceURLs.count) item(s)..."

        Task.detached {
            let fm = FileManager.default
            var lastError: Error?

            if !fm.fileExists(atPath: destFolder.path) {
                try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
            }

            for src in sourceURLs {
                let target = destFolder.appendingPathComponent(src.lastPathComponent)
                if src.path == target.path { continue }

                do {
                    if fm.fileExists(atPath: target.path) {
                        if overwrite {
                            try fm.removeItem(at: target)
                        } else {
                            continue
                        }
                    }
                    if isMove {
                        try fm.moveItem(at: src, to: target)
                    } else {
                        try fm.copyItem(at: src, to: target)
                    }
                } catch {
                    lastError = error
                }
            }

            let err = lastError
            await MainActor.run {
                pane.isLoading = false
                if let err = err {
                    pane.errorMessage = err.localizedDescription
                }
                self.refreshBothPanesIfNeeded()
            }
        }
    }
}
