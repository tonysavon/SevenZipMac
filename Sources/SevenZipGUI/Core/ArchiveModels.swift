import Foundation
import AppKit
import UniformTypeIdentifiers

public enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZip = "7z"
    case zip = "zip"
    case tar = "tar"
    case wim = "wim"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .wim: return "wim"
        }
    }

    public var fileExtension: String {
        return rawValue
    }
}

public enum CompressionLevel: Int, CaseIterable, Identifiable {
    case store = 0
    case fastest = 1
    case fast = 3
    case normal = 5
    case maximum = 7
    case ultra = 9

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .store: return "0 - Store"
        case .fastest: return "1 - Fastest"
        case .fast: return "3 - Fast"
        case .normal: return "5 - Normal"
        case .maximum: return "7 - Maximum"
        case .ultra: return "9 - Ultra"
        }
    }
}

public enum CompressionMethod: String, CaseIterable, Identifiable {
    case lzma2 = "LZMA2"
    case lzma = "LZMA"
    case ppmd = "PPMd"
    case bzip2 = "BZip2"
    case deflate = "Deflate"
    case deflate64 = "Deflate64"
    case copy = "Copy"

    public var id: String { rawValue }

    public static func availableMethods(for format: ArchiveFormat) -> [CompressionMethod] {
        switch format {
        case .sevenZip:
            return [.lzma2, .lzma, .ppmd, .bzip2, .copy]
        case .zip:
            return [.deflate, .deflate64, .bzip2, .lzma, .copy]
        case .tar, .wim:
            return [.copy]
        }
    }
}

public enum EncryptionMethod: String, CaseIterable, Identifiable {
    case aes256 = "AES-256"
    case zipCrypto = "ZipCrypto"

    public var id: String { rawValue }

    public var cliValue: String {
        switch self {
        case .aes256: return "AES256"
        case .zipCrypto: return "ZipCrypto"
        }
    }

    public static func availableMethods(for format: ArchiveFormat) -> [EncryptionMethod] {
        switch format {
        case .sevenZip: return [.aes256]
        case .zip: return [.aes256, .zipCrypto]
        case .tar, .wim: return []
        }
    }
}

public enum UpdateMode: String, CaseIterable, Identifiable {
    case addAndReplace = "Add and replace files"
    case updateAndAdd = "Update and add files"
    case freshen = "Freshen existing files"
    case synchronize = "Synchronize files"

    public var id: String { rawValue }

    public var command: String {
        switch self {
        case .addAndReplace: return "a"
        case .updateAndAdd, .freshen, .synchronize: return "u"
        }
    }

    public var extraFlags: [String] {
        switch self {
        case .addAndReplace, .updateAndAdd: return []
        case .freshen: return ["-up0q0r2x2y2z1w2"]
        case .synchronize: return ["-up1q0r2x2y2z0w2"]
        }
    }
}

public enum PathMode: String, CaseIterable, Identifiable {
    case relative = "Relative pathnames"
    case full = "Full pathnames"
    case absolute = "Absolute pathnames"

    public var id: String { rawValue }

    public var cliFlag: String? {
        switch self {
        case .relative: return nil
        case .full: return "-spf2"
        case .absolute: return "-spf"
        }
    }
}

public enum ExtractPathMode: String, CaseIterable, Identifiable {
    case full = "Full pathnames"
    case none = "No pathnames"
    case absolute = "Absolute pathnames"

    public var id: String { rawValue }
}

public enum OverwriteMode: String, CaseIterable, Identifiable {
    case ask = "Ask before overwrite"
    case overwrite = "Overwrite without prompt"
    case skip = "Skip existing files"
    case autoRename = "Auto rename existing files"

    public var id: String { rawValue }

    public var cliFlag: String {
        switch self {
        case .ask: return "-aou"
        case .overwrite: return "-aoa"
        case .skip: return "-aos"
        case .autoRename: return "-aou"
        }
    }
}

public struct CompressionOptions {
    public var format: ArchiveFormat = .sevenZip
    public var compressionLevel: CompressionLevel = .normal
    public var compressionMethod: CompressionMethod = .lzma2
    public var dictionarySize: String = "16m"
    public var wordSize: Int = 32
    public var solidBlockSize: String = "2g"
    public var threads: Int = ProcessInfo.processInfo.activeProcessorCount
    public var password: String = ""
    public var encryptionMethod: EncryptionMethod = .aes256
    public var encryptHeaders: Bool = false
    public var volumeSize: String = ""
    public var updateMode: UpdateMode = .addAndReplace
    public var pathMode: PathMode = .relative
    public var deleteFilesAfterCompression: Bool = false
    public var compressSharedFiles: Bool = false
    public var customParameters: String = ""

    public init() {}

    public func dictionarySizeMB() -> Double {
        let lower = dictionarySize.lowercased()
        if lower.hasSuffix("k"), let v = Double(lower.dropLast()) {
            return v / 1024.0
        }
        if lower.hasSuffix("m"), let v = Double(lower.dropLast()) {
            return v
        }
        return 16.0
    }

    /// Approximate 7-Zip memory usage (MB) for Compressing and Decompressing
    public func estimatedMemoryUsageMB() -> (compressMB: Int, decompressMB: Int) {
        if format == .tar || format == .wim || compressionLevel == .store || compressionMethod == .copy {
            return (1, 1)
        }
        let dictMB = dictionarySizeMB()
        let activeThreads = max(1, threads)
        switch compressionMethod {
        case .lzma2:
            let blockStreams = max(1, activeThreads / 2)
            let comp = Int(ceil(dictMB * 10.5 * Double(blockStreams) + 32.0))
            let decomp = Int(ceil(dictMB + 2.0))
            return (comp, decomp)
        case .lzma:
            let comp = Int(ceil(dictMB * 10.5 + 16.0))
            let decomp = Int(ceil(dictMB + 2.0))
            return (comp, decomp)
        case .ppmd:
            let comp = Int(ceil(dictMB + 8.0))
            return (comp, comp)
        case .bzip2:
            let comp = activeThreads * 10
            return (max(8, comp), 8)
        case .deflate, .deflate64:
            return (max(4, activeThreads * 2), 2)
        case .copy:
            return (1, 1)
        }
    }
}

public struct ArchiveMetadata {
    public var archivePath: String
    public var formatType: String
    public var physicalSize: Int64
    public var headersSize: Int64
    public var method: String
    public var solid: Bool
    public var blocks: Int
    public var properties: [(key: String, value: String)]

    public init(
        archivePath: String = "",
        formatType: String = "",
        physicalSize: Int64 = 0,
        headersSize: Int64 = 0,
        method: String = "",
        solid: Bool = false,
        blocks: Int = 0,
        properties: [(key: String, value: String)] = []
    ) {
        self.archivePath = archivePath
        self.formatType = formatType
        self.physicalSize = physicalSize
        self.headersSize = headersSize
        self.method = method
        self.solid = solid
        self.blocks = blocks
        self.properties = properties
    }
}

public struct RawArchiveEntry {
    public var path: String
    public var size: Int64
    public var packedSize: Int64
    public var modified: Date?
    public var attributes: String
    public var crc: String
    public var isEncrypted: Bool
    public var method: String
    public var isFolder: Bool
}

public struct ArchiveFrame: Equatable, Hashable {
    public let archiveURL: URL
    public let displayName: String
    public let subpath: String
    public let isTempExtracted: Bool

    public init(archiveURL: URL, displayName: String, subpath: String = "", isTempExtracted: Bool = false) {
        self.archiveURL = archiveURL
        self.displayName = displayName
        self.subpath = subpath
        self.isTempExtracted = isTempExtracted
    }
}

public struct FileItem: Identifiable, Hashable {
    public static let parentRowID = "__PARENT_DIR__"

    public let id: String
    public let name: String
    public let fullPath: String
    public let isDirectory: Bool
    public let isArchive: Bool
    public let isArchiveInternal: Bool
    public let isParentEntry: Bool
    public let size: Int64
    public let packedSize: Int64?
    public let modified: Date?
    public let attributes: String
    public let crc: String?
    public let method: String?
    public let isEncrypted: Bool

    public init(
        id: String,
        name: String,
        fullPath: String,
        isDirectory: Bool,
        isArchive: Bool,
        isArchiveInternal: Bool,
        isParentEntry: Bool = false,
        size: Int64,
        packedSize: Int64?,
        modified: Date?,
        attributes: String,
        crc: String?,
        method: String?,
        isEncrypted: Bool
    ) {
        self.id = id
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.isArchive = isArchive
        self.isArchiveInternal = isArchiveInternal
        self.isParentEntry = isParentEntry
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.attributes = attributes
        self.crc = crc
        self.method = method
        self.isEncrypted = isEncrypted
    }

    public static func parentEntry() -> FileItem {
        FileItem(
            id: parentRowID,
            name: "..",
            fullPath: "..",
            isDirectory: true,
            isArchive: false,
            isArchiveInternal: false,
            isParentEntry: true,
            size: 0,
            packedSize: nil,
            modified: nil,
            attributes: "",
            crc: nil,
            method: nil,
            isEncrypted: false
        )
    }

    public static let knownArchiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz2",
        "xz", "txz", "iso", "dmg", "cab", "lzma", "zst", "cpio",
        "ar", "deb", "rpm", "wim", "vhd", "vhdx", "jar", "war", "ear"
    ]

    // Sort helper properties for SwiftUI Table KeyPathComparator
    public var sortSize: Int64 { isDirectory ? -1 : size }
    public var sortPackedSize: Int64 { packedSize ?? -1 }
    public var sortModified: Date { modified ?? Date.distantPast }
    public var sortCrc: String { crc ?? "" }
    public var sortMethod: String { method ?? "" }

    public var displaySize: String {
        if isDirectory {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var displayPackedSize: String {
        guard let packed = packedSize, packed >= 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: packed, countStyle: .file)
    }

    public var displayModified: String {
        guard let modified = modified else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: modified)
    }

    public var systemIcon: NSImage {
        if isParentEntry {
            return NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: "Parent folder")
                ?? NSWorkspace.shared.icon(for: .folder)
        }
        if isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let ext = (name as NSString).pathExtension
        if isArchive {
            if let custom = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil) {
                return custom
            }
        }
        if let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}
