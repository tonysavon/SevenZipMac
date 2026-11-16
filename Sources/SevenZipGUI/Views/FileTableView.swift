import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct FileTableView: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceState
    @ObservedObject var state: FileManagerState
    let paneSide: PaneSide

    public init(workspace: WorkspaceState, state: FileManagerState, paneSide: PaneSide) {
        self.workspace = workspace
        self.state = state
        self.paneSide = paneSide
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace, state: state, paneSide: paneSide)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = SevenZipTableView()
        tableView.coordinator = context.coordinator
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 6, height: 2)
        tableView.gridStyleMask = []
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.registerForDraggedTypes([.fileURL])

        let columns: [(id: String, title: String, width: CGFloat, minWidth: CGFloat, sortKey: String)] = [
            ("name", "Name", 280, 140, "name"),
            ("size", "Size", 90, 60, "sortSize"),
            ("packedSize", "Packed Size", 90, 60, "sortPackedSize"),
            ("modified", "Modified", 150, 110, "sortModified"),
            ("attributes", "Attributes", 70, 50, "attributes"),
            ("crc", "CRC", 85, 60, "sortCrc"),
            ("method", "Method", 90, 60, "sortMethod")
        ]

        for col in columns {
            let tc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            tc.title = col.title
            tc.width = col.width
            tc.minWidth = col.minWidth
            tc.sortDescriptorPrototype = NSSortDescriptor(key: col.sortKey, ascending: true)
            tableView.addTableColumn(tc)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.reloadData(from: state)
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.workspace = workspace
        context.coordinator.state = state
        context.coordinator.reloadData(from: state)
    }

    // MARK: - Subclass for Mouse Activation
    final class SevenZipTableView: NSTableView {
        weak var coordinator: Coordinator?

        override func mouseDown(with event: NSEvent) {
            if let coord = coordinator {
                Task { @MainActor in
                    coord.workspace.activatePane(coord.paneSide)
                }
            }
            super.mouseDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let point = convert(event.locationInWindow, from: nil)
            let row = self.row(at: point)
            if row >= 0 && !isRowSelected(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            if let coord = coordinator {
                Task { @MainActor in
                    coord.workspace.activatePane(coord.paneSide)
                }
            }
            return super.menu(for: event)
        }
    }

    // MARK: - Coordinator
    @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSFilePromiseProviderDelegate {
        var workspace: WorkspaceState
        var state: FileManagerState
        let paneSide: PaneSide
        weak var tableView: NSTableView?

        private var displayedItems: [FileItem] = []
        private var isSyncingSelection = false
        private var lastRenderedSignature: [FileItem] = []

        init(workspace: WorkspaceState, state: FileManagerState, paneSide: PaneSide) {
            self.workspace = workspace
            self.state = state
            self.paneSide = paneSide
        }

        func reloadData(from state: FileManagerState) {
            let filtered: [FileItem]
            if state.filterText.isEmpty {
                filtered = state.items
            } else {
                filtered = state.items.filter {
                    $0.isParentEntry || $0.name.localizedCaseInsensitiveContains(state.filterText)
                }
            }

            if filtered != lastRenderedSignature {
                displayedItems = filtered
                lastRenderedSignature = filtered
                tableView?.reloadData()
            }

            syncSelectionToTable()
        }

        private func syncSelectionToTable() {
            guard let tableView = tableView else { return }
            var targetIndexes = IndexSet()
            for (idx, item) in displayedItems.enumerated() {
                if state.selectedItemIDs.contains(item.id) {
                    targetIndexes.insert(idx)
                }
            }
            if tableView.selectedRowIndexes != targetIndexes {
                isSyncingSelection = true
                tableView.selectRowIndexes(targetIndexes, byExtendingSelection: false)
                isSyncingSelection = false
            }
        }

        // MARK: - NSTableViewDataSource
        public func numberOfRows(in tableView: NSTableView) -> Int {
            return displayedItems.count
        }

        public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let first = tableView.sortDescriptors.first, let key = first.key else { return }
            let order: SortOrder = first.ascending ? .forward : .reverse
            let comparator: KeyPathComparator<FileItem>
            switch key {
            case "name": comparator = KeyPathComparator(\FileItem.name, order: order)
            case "sortSize": comparator = KeyPathComparator(\FileItem.sortSize, order: order)
            case "sortPackedSize": comparator = KeyPathComparator(\FileItem.sortPackedSize, order: order)
            case "sortModified": comparator = KeyPathComparator(\FileItem.sortModified, order: order)
            case "attributes": comparator = KeyPathComparator(\FileItem.attributes, order: order)
            case "sortCrc": comparator = KeyPathComparator(\FileItem.sortCrc, order: order)
            case "sortMethod": comparator = KeyPathComparator(\FileItem.sortMethod, order: order)
            default: comparator = KeyPathComparator(\FileItem.name, order: order)
            }
            state.applySortOrder([comparator])
        }

        // MARK: - NSTableViewDelegate
        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < displayedItems.count, let colID = tableColumn?.identifier.rawValue else { return nil }
            let item = displayedItems[row]

            switch colID {
            case "name":
                let id = NSUserInterfaceItemIdentifier("NameCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NameCellView) ?? NameCellView(identifier: id)
                cell.configure(with: item)
                return cell
            default:
                let id = NSUserInterfaceItemIdentifier("TextCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: self) as? TextCellView) ?? TextCellView(identifier: id)
                let text: String
                var rightAlign = false
                var monospaced = true

                switch colID {
                case "size":
                    text = item.displaySize
                    rightAlign = true
                case "packedSize":
                    text = item.displayPackedSize
                    rightAlign = true
                case "modified":
                    text = item.displayModified
                case "attributes":
                    text = item.attributes
                case "crc":
                    text = item.crc ?? ""
                case "method":
                    text = item.method ?? ""
                    monospaced = false
                default:
                    text = ""
                }

                cell.configure(text: text, rightAlign: rightAlign, monospaced: monospaced)
                return cell
            }
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tableView = tableView else { return }
            workspace.activatePane(paneSide)
            var newSelection = Set<String>()
            for idx in tableView.selectedRowIndexes where idx < displayedItems.count {
                newSelection.insert(displayedItems[idx].id)
            }
            if state.selectedItemIDs != newSelection {
                state.selectedItemIDs = newSelection
                state.onSelectionChanged()
            }
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView = tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < displayedItems.count else { return }
            workspace.activatePane(paneSide)
            let item = displayedItems[row]
            state.handleItemDoubleClick(item)
        }

        // MARK: - Drag Out
        public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < displayedItems.count else { return nil }
            let item = displayedItems[row]
            if item.isParentEntry { return nil }

            let dragged = state.selectedItemIDs.contains(item.id) && !state.selectedItems.isEmpty
                ? state.selectedItems
                : [item]
            DragSessionContext.shared.sourcePaneSide = paneSide
            DragSessionContext.shared.draggedItems = dragged
            DragSessionContext.shared.sourceArchiveURL = state.activeArchiveURL
            DragSessionContext.shared.sourceArchivePassword = state.activeArchivePassword
            DragSessionContext.shared.timestamp = Date()

            if !item.isArchiveInternal {
                return URL(fileURLWithPath: item.fullPath) as NSURL
            }

            let promise = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: self)
            promise.userInfo = item.fullPath
            return promise
        }

        // MARK: - NSFilePromiseProviderDelegate
        public nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            let relPath = (filePromiseProvider.userInfo as? String) ?? "extracted"
            return (relPath as NSString).lastPathComponent
        }

        public nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
            let relPath = filePromiseProvider.userInfo as? String ?? ""
            Task {
                let (arcURL, pass) = await MainActor.run {
                    (DragSessionContext.shared.sourceArchiveURL, DragSessionContext.shared.sourceArchivePassword)
                }
                guard let arcURL = arcURL else {
                    completionHandler(nil)
                    return
                }
                do {
                    let tempURL = try await SevenZipService.shared.extractSingleFileToTemp(
                        archiveURL: arcURL,
                        relativePath: relPath,
                        password: pass
                    )
                    if FileManager.default.fileExists(atPath: url.path) {
                        try? FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: url)
                    completionHandler(nil)
                } catch {
                    completionHandler(error)
                }
            }
        }

        // MARK: - Drop In
        public func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            tableView.setDropRow(-1, dropOperation: .on)
            return NSEvent.modifierFlags.contains(.command) ? .move : .copy
        }

        public func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            workspace.activatePane(paneSide)

            // 1. Internal pane-to-pane drag
            if DragSessionContext.shared.isActive(),
               let sourceSide = DragSessionContext.shared.sourcePaneSide,
               sourceSide != paneSide {
                let dragged = DragSessionContext.shared.draggedItems
                DragSessionContext.shared.clear()
                let sourcePane = workspace.pane(for: sourceSide)
                let isMove = NSEvent.modifierFlags.contains(.command)

                if state.isInsideArchive {
                    guard let targetArc = state.activeArchiveURL else { return false }
                    if state.currentArchiveIsTempNested {
                        state.errorMessage = "Cannot drop items into a temporary nested archive."
                        return false
                    }
                    workspace.transferItems(
                        dragged,
                        from: sourcePane,
                        toArchive: targetArc,
                        subpath: state.currentArchiveSubpath,
                        targetPassword: state.activeArchivePassword,
                        isMove: isMove
                    )
                } else {
                    workspace.transferItems(
                        dragged,
                        from: sourcePane,
                        toFilesystemFolder: state.currentFilesystemDirectoryURL,
                        isMove: isMove,
                        overwrite: true
                    )
                }
                return true
            }

            // 2. External drop from Finder
            DragSessionContext.shared.clear()
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty else {
                return false
            }

            let optionHeld = NSEvent.modifierFlags.contains(.option)
            if state.isInsideArchive {
                guard let targetArc = state.activeArchiveURL else { return false }
                if state.currentArchiveIsTempNested {
                    state.errorMessage = "Cannot add files directly into a nested temporary archive."
                    return false
                }
                state.startAddToExistingArchiveOperation(
                    archiveURL: targetArc,
                    sources: urls,
                    subpath: state.currentArchiveSubpath,
                    password: state.activeArchivePassword
                ) { [weak self] in
                    self?.workspace.refreshBothPanesIfNeeded()
                }
            } else if urls.count == 1,
                      !optionHeld,
                      FileItem.knownArchiveExtensions.contains(urls[0].pathExtension.lowercased()) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDir), !isDir.boolValue {
                    state.openArchiveFile(url: urls[0])
                    return true
                }
                workspace.copyOrMoveFilesystemURLs(
                    urls,
                    toFolder: state.currentFilesystemDirectoryURL,
                    isMove: false,
                    overwrite: true,
                    reportingTo: state
                )
            } else {
                workspace.copyOrMoveFilesystemURLs(
                    urls,
                    toFolder: state.currentFilesystemDirectoryURL,
                    isMove: false,
                    overwrite: true,
                    reportingTo: state
                )
            }
            return true
        }

        // MARK: - Context Menu (NSMenuDelegate)
        public func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let selected = state.selectedItems

            if state.selectedItemIDs.contains(FileItem.parentRowID) && selected.isEmpty {
                menu.addItem(makeMenuItem("Go Up (..)") { [weak self] in self?.state.navigateUp() })
                return
            }

            if selected.isEmpty {
                menu.addItem(makeMenuItem("New Folder... (⌘⇧N)") { [weak self] in self?.state.showNewFolderDialog = true })
                menu.addItem(makeMenuItem("Paste (⌘V)") { [weak self] in
                    guard let self = self else { return }
                    self.state.pasteFromClipboard { self.workspace.refreshBothPanesIfNeeded() }
                })
                return
            }

            if let single = selected.first, selected.count == 1 {
                menu.addItem(makeMenuItem("Open") { [weak self] in self?.state.handleItemDoubleClick(single) })
                if !single.isDirectory {
                    menu.addItem(makeMenuItem("Quick Look (Space)") { [weak self] in self?.state.quickLookSelectedItem() })
                }
                if !single.isArchiveInternal {
                    menu.addItem(makeMenuItem("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: single.fullPath)])
                    })
                }
                menu.addItem(.separator())
            }

            menu.addItem(makeMenuItem("Copy (⌘C)") { [weak self] in self?.state.copySelectedToClipboard() })
            if selected.count == 1 {
                menu.addItem(makeMenuItem("Paste (⌘V)") { [weak self] in
                    guard let self = self else { return }
                    self.state.pasteFromClipboard { self.workspace.refreshBothPanesIfNeeded() }
                })
            }
            menu.addItem(makeMenuItem("Copy To... (F5)") { [weak self] in self?.workspace.openCopyDialog() })
            menu.addItem(makeMenuItem("Move To... (F6)") { [weak self] in self?.workspace.openMoveDialog() })
            if selected.count == 1 {
                menu.addItem(makeMenuItem("Rename... (F2)") { [weak self] in self?.state.showRenameDialog = true })
            }
            menu.addItem(makeMenuItem("New Folder... (⌘⇧N)") { [weak self] in self?.state.showNewFolderDialog = true })

            menu.addItem(.separator())

            if state.isInsideArchive || selected.contains(where: { $0.isArchive }) {
                menu.addItem(makeMenuItem("Extract... (⌘E)") { [weak self] in self?.state.showExtractDialog = true })
                menu.addItem(makeMenuItem("Test Archive (⌘T)") { [weak self] in self?.state.testCurrentArchive() })
            } else if !state.isInsideArchive {
                menu.addItem(makeMenuItem("Add to Archive... (⌘⇧A)") { [weak self] in self?.state.showAddDialog = true })
            }

            let crcMenu = NSMenu()
            for (title, flag) in [
                ("CRC-32", "-scrcCRC32"), ("CRC-64", "-scrcCRC64"),
                ("SHA-1", "-scrcSHA1"), ("SHA-256", "-scrcSHA256"),
                ("MD5", "-scrcMD5"), ("BLAKE2sp", "-scrcBLAKE2sp"),
                ("* (All)", "-scrc*")
            ] {
                crcMenu.addItem(makeMenuItem(title) { [weak self] in self?.state.openChecksum(algorithm: flag) })
            }
            let crcItem = NSMenuItem(title: "CRC SHA", action: nil, keyEquivalent: "")
            crcItem.submenu = crcMenu
            menu.addItem(crcItem)

            if selected.count == 1, let single = selected.first, !single.isArchiveInternal && !single.isDirectory {
                if (single.name as NSString).pathExtension == "001" {
                    menu.addItem(makeMenuItem("Combine Files...") { [weak self] in self?.state.showCombineDialog = true })
                } else {
                    menu.addItem(makeMenuItem("Split File...") { [weak self] in self?.state.showSplitDialog = true })
                }
            }

            menu.addItem(.separator())
            menu.addItem(makeMenuItem("Get Info (⌘I)") { [weak self] in self?.state.showInfoDialog = true })
            menu.addItem(makeMenuItem("Delete (⌘⌫)") { [weak self] in self?.state.deleteSelected() })
        }

        private func makeMenuItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title: title, closure: action)
            return item
        }
    }
}

// MARK: - AppKit Cell Views
private final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, closure: @escaping () -> Void) {
        self.closure = closure
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func invoke() {
        closure()
    }
}

private final class NameCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "archive")
    private let lockView = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        badgeLabel.textColor = .systemOrange
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        badgeLabel.layer?.cornerRadius = 3
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        lockView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Encrypted")
        lockView.contentTintColor = .systemYellow
        lockView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, nameLabel, badgeLabel, lockView])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            lockView.widthAnchor.constraint(equalToConstant: 12),
            lockView.heightAnchor.constraint(equalToConstant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with item: FileItem) {
        iconView.image = item.systemIcon
        nameLabel.stringValue = item.name
        nameLabel.font = .systemFont(ofSize: 12, weight: item.isParentEntry ? .semibold : .regular)
        nameLabel.textColor = item.isParentEntry ? .secondaryLabelColor : .labelColor
        badgeLabel.isHidden = !item.isArchive
        lockView.isHidden = !item.isEncrypted
    }
}

private final class TextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.lineBreakMode = .byTruncatingTail
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, rightAlign: Bool, monospaced: Bool) {
        label.stringValue = text
        label.alignment = rightAlign ? .right : .left
        label.font = monospaced
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 11)
    }
}
