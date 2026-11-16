import Foundation
import AppKit
import QuickLookUI

public final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    @MainActor public static let shared = QuickLookCoordinator()

    private var previewURLs: [URL] = []

    private override init() {
        super.init()
    }

    @MainActor
    public func preview(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.previewURLs = urls

        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    @MainActor
    public func updateIfVisible(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible, !urls.isEmpty else { return }
        self.previewURLs = urls
        panel.reloadData()
    }

    // MARK: - QLPreviewPanelDataSource
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURLs.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return previewURLs[index] as NSURL
    }
}
