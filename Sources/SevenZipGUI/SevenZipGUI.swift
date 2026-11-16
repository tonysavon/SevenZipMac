import SwiftUI
import AppKit

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    public static var onOpenFiles: (([String]) -> Void)?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        AppDelegate.onOpenFiles?(filenames)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct SevenZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("7-Zip File Manager", id: "main") {
            MainView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Folder...") {
                    NotificationCenter.default.post(name: .newFolderNotification, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Get Info") {
                    NotificationCenter.default.post(name: .getInfoNotification, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }

            CommandMenu("Archive") {
                Button("Add to Archive...") {
                    NotificationCenter.default.post(name: .addToArchiveNotification, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Extract...") {
                    NotificationCenter.default.post(name: .extractArchiveNotification, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Test Archive") {
                    NotificationCenter.default.post(name: .testArchiveNotification, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Divider()

                Button("Copy To...") {
                    NotificationCenter.default.post(name: .copyToNotification, object: nil)
                }

                Button("Move To...") {
                    NotificationCenter.default.post(name: .moveToNotification, object: nil)
                }

                Button("Rename...") {
                    NotificationCenter.default.post(name: .renameNotification, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                Button("Split File...") {
                    NotificationCenter.default.post(name: .splitFileNotification, object: nil)
                }

                Button("Combine Files...") {
                    NotificationCenter.default.post(name: .combineFilesNotification, object: nil)
                }
            }

            CommandMenu("View") {
                Button("2 Panels") {
                    NotificationCenter.default.post(name: .toggleDualPaneNotification, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("Up One Level") {
                    NotificationCenter.default.post(name: .navigateUpNotification, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Button("Back") {
                    NotificationCenter.default.post(name: .navigateBackNotification, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Forward") {
                    NotificationCenter.default.post(name: .navigateForwardNotification, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command])

                Divider()

                Button("Flat View") {
                    NotificationCenter.default.post(name: .toggleFlatViewNotification, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Show Hidden Files") {
                    NotificationCenter.default.post(name: .toggleHiddenFilesNotification, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Divider()

                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshNotification, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Tools") {
                Button("CRC & Hash Checksum...") {
                    NotificationCenter.default.post(name: .checksumNotification, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Benchmark") {
                    NotificationCenter.default.post(name: .benchmarkNotification, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])

                Divider()

                Button("Install Finder Quick Actions...") {
                    NotificationCenter.default.post(name: .installFinderActionsNotification, object: nil)
                }

                Button("Remove Finder Quick Actions") {
                    NotificationCenter.default.post(name: .uninstallFinderActionsNotification, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let testArchiveNotification = Notification.Name("testArchiveNotification")
    static let addToArchiveNotification = Notification.Name("addToArchiveNotification")
    static let extractArchiveNotification = Notification.Name("extractArchiveNotification")
    static let benchmarkNotification = Notification.Name("benchmarkNotification")
    static let navigateUpNotification = Notification.Name("navigateUpNotification")
    static let navigateBackNotification = Notification.Name("navigateBackNotification")
    static let navigateForwardNotification = Notification.Name("navigateForwardNotification")
    static let toggleFlatViewNotification = Notification.Name("toggleFlatViewNotification")
    static let toggleHiddenFilesNotification = Notification.Name("toggleHiddenFilesNotification")
    static let refreshNotification = Notification.Name("refreshNotification")
    static let toggleDualPaneNotification = Notification.Name("toggleDualPaneNotification")
    static let copyToNotification = Notification.Name("copyToNotification")
    static let moveToNotification = Notification.Name("moveToNotification")
    static let newFolderNotification = Notification.Name("newFolderNotification")
    static let renameNotification = Notification.Name("renameNotification")
    static let getInfoNotification = Notification.Name("getInfoNotification")
    static let checksumNotification = Notification.Name("checksumNotification")
    static let splitFileNotification = Notification.Name("splitFileNotification")
    static let combineFilesNotification = Notification.Name("combineFilesNotification")
    static let installFinderActionsNotification = Notification.Name("installFinderActionsNotification")
    static let uninstallFinderActionsNotification = Notification.Name("uninstallFinderActionsNotification")
}
