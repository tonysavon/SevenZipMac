import SwiftUI

public struct AddressBarView: View {
    @ObservedObject var state: FileManagerState

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Back button
            Button(action: { state.navigateBack() }) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(!state.canGoBack)
            .help("Back (⌘[)")

            // Forward button
            Button(action: { state.navigateForward() }) {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(!state.canGoForward)
            .help("Forward (⌘])")

            // Up button (Signature 7-Zip feature)
            Button(action: { state.navigateUp() }) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlColor))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Up one level (⌘↑ or Backspace)")

            // Quick Bookmarks menu
            Menu {
                Button("Home (~)") {
                    state.navigateTo(.filesystem(url: URL(fileURLWithPath: NSHomeDirectory())))
                }
                Button("Desktop") {
                    let path = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                    state.navigateTo(.filesystem(url: path))
                }
                Button("Downloads") {
                    let path = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                    state.navigateTo(.filesystem(url: path))
                }
                Button("Documents") {
                    let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    state.navigateTo(.filesystem(url: path))
                }
                Divider()
                Button("Root (/)") {
                    state.navigateTo(.filesystem(url: URL(fileURLWithPath: "/")))
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            // Path Address Bar
            HStack {
                Image(systemName: state.isInsideArchive ? "doc.zipper" : "folder")
                    .foregroundColor(state.isInsideArchive ? .orange : .accentColor)
                    .font(.system(size: 12))

                TextField("Path", text: $state.addressBarText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        submitPath()
                    }

                Button(action: { submitPath() }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Search / Filter box
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextField("Filter", text: $state.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))

                if !state.filterText.isEmpty {
                    Button(action: { state.filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(width: 140)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Flat View Toggle
            Button(action: { state.toggleFlatView() }) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state.isFlatView ? .white : .secondary)
                    .padding(5)
                    .background(state.isFlatView ? Color.accentColor : Color(NSColor.controlColor))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Flat View (⌘⇧F)")

            // Hidden Files Toggle
            Button(action: { state.toggleHiddenFiles() }) {
                Image(systemName: state.showHiddenFiles ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundColor(state.showHiddenFiles ? .white : .secondary)
                    .padding(5)
                    .background(state.showHiddenFiles ? Color.accentColor : Color(NSColor.controlColor))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Show Hidden Files (⌘⇧.)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func submitPath() {
        let trimmed = state.addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let expanded: String
        if trimmed.starts(with: "~") {
            expanded = (trimmed as NSString).expandingTildeInPath
        } else {
            expanded = trimmed
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            if isDir.boolValue {
                state.navigateTo(.filesystem(url: URL(fileURLWithPath: expanded)))
            } else {
                let ext = (expanded as NSString).pathExtension.lowercased()
                if FileItem.knownArchiveExtensions.contains(ext) {
                    state.openArchiveFile(url: URL(fileURLWithPath: expanded))
                } else {
                    state.navigateTo(.filesystem(url: URL(fileURLWithPath: (expanded as NSString).deletingLastPathComponent)))
                }
            }
        } else {
            state.errorMessage = "Path does not exist: \(expanded)"
        }
    }
}
