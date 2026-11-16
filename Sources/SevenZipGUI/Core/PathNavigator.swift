import Foundation

public struct ArchiveVirtualHierarchy {
    private static func makeArchiveFileItem(
        entry: RawArchiveEntry,
        displayName: String,
        normalizedPath: String
    ) -> FileItem {
        let ext = (displayName as NSString).pathExtension.lowercased()
        let isNestedArchive = !entry.isFolder && FileItem.knownArchiveExtensions.contains(ext)
        return FileItem(
            id: normalizedPath,
            name: displayName,
            fullPath: normalizedPath,
            isDirectory: false,
            isArchive: isNestedArchive,
            isArchiveInternal: true,
            size: entry.size,
            packedSize: entry.packedSize,
            modified: entry.modified,
            attributes: entry.attributes,
            crc: entry.crc,
            method: entry.method,
            isEncrypted: entry.isEncrypted
        )
    }

    /// Builds a flat list of all files inside an archive (or under a given subpath)
    public static func flatItemsForSubpath(
        _ subpath: String,
        rawEntries: [RawArchiveEntry]
    ) -> [FileItem] {
        let normalizedTarget = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedTarget.isEmpty ? "" : normalizedTarget + "/"

        var resultFiles: [FileItem] = []
        for entry in rawEntries where !entry.isFolder {
            let entryPath = entry.path
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !entryPath.isEmpty else { continue }

            if prefix.isEmpty {
                resultFiles.append(makeArchiveFileItem(entry: entry, displayName: entryPath, normalizedPath: entryPath))
            } else if entryPath.hasPrefix(prefix) {
                let relative = String(entryPath.dropFirst(prefix.count))
                if !relative.isEmpty {
                    resultFiles.append(makeArchiveFileItem(entry: entry, displayName: relative, normalizedPath: entryPath))
                }
            }
        }
        return resultFiles
    }

    /// Builds the list of FileItem entries to show for a specific subpath inside an archive
    public static func itemsForSubpath(
        _ subpath: String,
        rawEntries: [RawArchiveEntry],
        archiveURL: URL
    ) -> [FileItem] {
        let normalizedTarget = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var directoriesFound = Set<String>()
        var directoryFirstDates: [String: Date] = [:]
        var resultFiles: [FileItem] = []

        for entry in rawEntries {
            let entryPath = entry.path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !entryPath.isEmpty else { continue }

            if normalizedTarget.isEmpty {
                if let slashIndex = entryPath.firstIndex(of: "/") {
                    let topFolder = String(entryPath[..<slashIndex])
                    directoriesFound.insert(topFolder)
                    if let mod = entry.modified, directoryFirstDates[topFolder] == nil {
                        directoryFirstDates[topFolder] = mod
                    }
                } else if entry.isFolder {
                    directoriesFound.insert(entryPath)
                    if let mod = entry.modified, directoryFirstDates[entryPath] == nil {
                        directoryFirstDates[entryPath] = mod
                    }
                } else {
                    resultFiles.append(makeArchiveFileItem(entry: entry, displayName: entryPath, normalizedPath: entryPath))
                }
            } else {
                let prefix = normalizedTarget + "/"
                if entryPath.hasPrefix(prefix) {
                    let relative = String(entryPath.dropFirst(prefix.count))
                    if let slashIndex = relative.firstIndex(of: "/") {
                        let subFolderName = String(relative[..<slashIndex])
                        directoriesFound.insert(subFolderName)
                        if let mod = entry.modified, directoryFirstDates[subFolderName] == nil {
                            directoryFirstDates[subFolderName] = mod
                        }
                    } else if !relative.isEmpty {
                        if entry.isFolder {
                            directoriesFound.insert(relative)
                            if let mod = entry.modified, directoryFirstDates[relative] == nil {
                                directoryFirstDates[relative] = mod
                            }
                        } else {
                            resultFiles.append(makeArchiveFileItem(entry: entry, displayName: relative, normalizedPath: entryPath))
                        }
                    }
                }
            }
        }

        var resultDirs: [FileItem] = []
        for dir in directoriesFound.sorted() {
            let fullDirPath = normalizedTarget.isEmpty ? dir : "\(normalizedTarget)/\(dir)"
            let dirItem = FileItem(
                id: fullDirPath,
                name: dir,
                fullPath: fullDirPath,
                isDirectory: true,
                isArchive: false,
                isArchiveInternal: true,
                size: 0,
                packedSize: nil,
                modified: directoryFirstDates[dir],
                attributes: "D",
                crc: nil,
                method: nil,
                isEncrypted: false
            )
            resultDirs.append(dirItem)
        }

        return resultDirs + resultFiles
    }
}
