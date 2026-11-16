import SwiftUI

public final class InfoDialogViewModel: ObservableObject {
    @Published public var loadedMetadata: ArchiveMetadata?
    @Published public var fileProperties: [(key: String, value: String)] = []
    @Published public var isLoading: Bool = false

    public init() {}
}

public struct InfoDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = InfoDialogViewModel()

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        let meta = vm.loadedMetadata ?? state.activeArchiveMetadata
        let subtitle = meta?.archivePath ?? state.selectedItems.first?.fullPath ?? state.currentDisplayPath

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.indigo)
                    .font(.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meta != nil ? "Archive Properties" : "File Properties")
                        .font(.headline)
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Properties list
            if vm.isLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text("Inspecting metadata...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let meta = meta {
                List {
                    Section(header: Text("Basic Information")) {
                        propertyRow(label: "Type", value: meta.formatType)
                        propertyRow(label: "Physical Size", value: ByteCountFormatter.string(fromByteCount: meta.physicalSize, countStyle: .file) + " (\(meta.physicalSize) bytes)")
                        propertyRow(label: "Headers Size", value: ByteCountFormatter.string(fromByteCount: meta.headersSize, countStyle: .file))
                        propertyRow(label: "Method", value: meta.method)
                        propertyRow(label: "Solid", value: meta.solid ? "Yes" : "No")
                        propertyRow(label: "Blocks", value: "\(meta.blocks)")
                    }

                    if !meta.properties.isEmpty {
                        Section(header: Text("Detailed Headers")) {
                            ForEach(meta.properties, id: \.key) { prop in
                                propertyRow(label: prop.key, value: prop.value)
                            }
                        }
                    }
                }
            } else if !vm.fileProperties.isEmpty {
                List {
                    Section(header: Text("Item Information")) {
                        ForEach(vm.fileProperties, id: \.key) { prop in
                            propertyRow(label: prop.key, value: prop.value)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Select a file or open an archive to view properties.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 420)
        .onAppear {
            loadPropertiesIfNeeded()
        }
    }

    private func loadPropertiesIfNeeded() {
        if state.activeArchiveMetadata != nil {
            return
        }
        guard let item = state.selectedItems.first else { return }

        if item.isArchive && !item.isArchiveInternal {
            vm.isLoading = true
            let url = URL(fileURLWithPath: item.fullPath)
            Task {
                do {
                    let (meta, _) = try await SevenZipService.shared.listArchive(url: url)
                    await MainActor.run {
                        vm.loadedMetadata = meta
                        vm.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        vm.isLoading = false
                        loadFilesystemProperties(for: item)
                    }
                }
            }
        } else {
            loadFilesystemProperties(for: item)
        }
    }

    private func loadFilesystemProperties(for item: FileItem) {
        var props: [(key: String, value: String)] = [
            ("Name", item.name),
            ("Path", item.fullPath),
            ("Kind", item.isDirectory ? "Folder" : (item.isArchive ? "Archive" : "File"))
        ]
        if !item.isDirectory {
            props.append(("Size", "\(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) (\(item.size) bytes)"))
        }
        if let packed = item.packedSize, packed >= 0 {
            props.append(("Packed Size", ByteCountFormatter.string(fromByteCount: packed, countStyle: .file)))
        }
        if !item.displayModified.isEmpty {
            props.append(("Modified", item.displayModified))
        }
        if let method = item.method, !method.isEmpty {
            props.append(("Method", method))
        }
        if let crc = item.crc, !crc.isEmpty {
            props.append(("CRC", crc))
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: item.fullPath) {
            if let posix = attrs[.posixPermissions] as? NSNumber {
                props.append(("Permissions", String(format: "%o", posix.intValue)))
            }
            if let created = attrs[.creationDate] as? Date {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                props.append(("Created", df.string(from: created)))
            }
        }
        vm.fileProperties = props
    }

    private func propertyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
