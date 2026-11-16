import Foundation
import AppKit

public struct FinderQuickActionsInstaller {
    private static let servicesDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Services", isDirectory: true)

    private static let workflowNames = [
        "7-Zip - Add to Archive.workflow",
        "7-Zip - Add to .7z.workflow",
        "7-Zip - Extract Here.workflow",
        "7-Zip - Extract to Folder.workflow"
    ]

    public static func install() throws {
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)

        let bundlePath = Bundle.main.bundleURL.path.hasSuffix(".app")
            ? Bundle.main.bundleURL.path
            : "/Applications/7-Zip.app"
        let escapedBundle = bundlePath.replacingOccurrences(of: "\"", with: "\\\"")

        let definitions: [(name: String, flag: String, inputType: String)] = [
            ("7-Zip - Add to Archive.workflow", "--add", "com.apple.Automator.fileSystemObject"),
            ("7-Zip - Add to .7z.workflow", "--compress-7z", "com.apple.Automator.fileSystemObject"),
            ("7-Zip - Extract Here.workflow", "--extract-here", "com.apple.Automator.fileSystemObject"),
            ("7-Zip - Extract to Folder.workflow", "--extract-folder", "com.apple.Automator.fileSystemObject")
        ]

        for def in definitions {
            let wfURL = servicesDir.appendingPathComponent(def.name, isDirectory: true)
            let contentsURL = wfURL.appendingPathComponent("Contents", isDirectory: true)
            try? FileManager.default.removeItem(at: wfURL)
            try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

            let script = """
            APP_BUNDLE="/Applications/7-Zip.app"
            if [ ! -d "$APP_BUNDLE" ]; then
                APP_BUNDLE="\(escapedBundle)"
            fi
            open -n -a "$APP_BUNDLE" --args \(def.flag) "$@"
            """

            let infoPlist = makeInfoPlist(menuTitle: def.name.replacingOccurrences(of: ".workflow", with: ""), inputType: def.inputType)
            let documentWflow = makeDocumentWflow(shellScript: script)

            try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            try documentWflow.write(to: contentsURL.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
        }

        // Refresh macOS Services cache
        let pbs = Process()
        pbs.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        pbs.arguments = ["-flush"]
        try? pbs.run()
    }

    public static func uninstall() throws {
        for name in workflowNames {
            let wfURL = servicesDir.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: wfURL.path) {
                try FileManager.default.removeItem(at: wfURL)
            }
        }
        let pbs = Process()
        pbs.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        pbs.arguments = ["-flush"]
        try? pbs.run()
    }

    private static func xmlEscape(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func makeInfoPlist(menuTitle: String, inputType: String) -> String {
        let escapedTitle = xmlEscape(menuTitle)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>\(escapedTitle)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSRequiredContext</key>
                    <dict>
                        <key>NSApplicationIdentifier</key>
                        <string>com.apple.finder</string>
                    </dict>
                    <key>NSSendFileTypes</key>
                    <array>
                        <string>public.item</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
    }

    private static func makeDocumentWflow(shellScript: String) -> String {
        let escapedScript = xmlEscape(shellScript)
        let actionUUID = UUID().uuidString
        let inputUUID = UUID().uuidString
        let outputUUID = UUID().uuidString

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key>
            <string>523</string>
            <key>AMApplicationVersion</key>
            <string>2.10</string>
            <key>AMDocumentVersion</key>
            <string>2</string>
            <key>actions</key>
            <array>
                <dict>
                    <key>action</key>
                    <dict>
                        <key>AMAccepts</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Optional</key>
                            <true/>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.string</string>
                            </array>
                        </dict>
                        <key>AMActionVersion</key>
                        <string>2.0.3</string>
                        <key>AMApplication</key>
                        <array>
                            <string>Automator</string>
                        </array>
                        <key>AMParameterProperties</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <dict/>
                            <key>CheckedForUserDefaultShell</key>
                            <dict/>
                            <key>inputMethod</key>
                            <dict/>
                            <key>shell</key>
                            <dict/>
                            <key>source</key>
                            <dict/>
                        </dict>
                        <key>AMProvides</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.string</string>
                            </array>
                        </dict>
                        <key>ActionBundlePath</key>
                        <string>/System/Library/Automator/Run Shell Script.action</string>
                        <key>ActionName</key>
                        <string>Run Shell Script</string>
                        <key>ActionParameters</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <string>\(escapedScript)</string>
                            <key>CheckedForUserDefaultShell</key>
                            <true/>
                            <key>inputMethod</key>
                            <integer>1</integer>
                            <key>shell</key>
                            <string>/bin/zsh</string>
                            <key>source</key>
                            <string></string>
                        </dict>
                        <key>BundleIdentifier</key>
                        <string>com.apple.RunShellScript</string>
                        <key>CFBundleVersion</key>
                        <string>2.0.3</string>
                        <key>CanShowSelectedItemsWhenRun</key>
                        <false/>
                        <key>CanShowWhenRun</key>
                        <true/>
                        <key>Category</key>
                        <array>
                            <string>AMCategoryUtilities</string>
                        </array>
                        <key>Class Name</key>
                        <string>RunShellScriptAction</string>
                        <key>InputUUID</key>
                        <string>\(inputUUID)</string>
                        <key>Keywords</key>
                        <array>
                            <string>Shell</string>
                            <string>Script</string>
                        </array>
                        <key>OutputUUID</key>
                        <string>\(outputUUID)</string>
                        <key>UUID</key>
                        <string>\(actionUUID)</string>
                        <key>UnlocalizedApplications</key>
                        <array>
                            <string>Automator</string>
                        </array>
                        <key>arguments</key>
                        <dict>
                            <key>0</key>
                            <dict>
                                <key>default value</key>
                                <integer>0</integer>
                                <key>name</key>
                                <string>inputMethod</string>
                                <key>required</key>
                                <string>0</string>
                                <key>type</key>
                                <string>0</string>
                                <key>uuid</key>
                                <string>0</string>
                            </dict>
                            <key>1</key>
                            <dict>
                                <key>default value</key>
                                <string></string>
                                <key>name</key>
                                <string>source</string>
                                <key>required</key>
                                <string>0</string>
                                <key>type</key>
                                <string>0</string>
                                <key>uuid</key>
                                <string>1</string>
                            </dict>
                            <key>2</key>
                            <dict>
                                <key>default value</key>
                                <false/>
                                <key>name</key>
                                <string>CheckedForUserDefaultShell</string>
                                <key>required</key>
                                <string>0</string>
                                <key>type</key>
                                <string>0</string>
                                <key>uuid</key>
                                <string>2</string>
                            </dict>
                            <key>3</key>
                            <dict>
                                <key>default value</key>
                                <string></string>
                                <key>name</key>
                                <string>COMMAND_STRING</string>
                                <key>required</key>
                                <string>0</string>
                                <key>type</key>
                                <string>0</string>
                                <key>uuid</key>
                                <string>3</string>
                            </dict>
                            <key>4</key>
                            <dict>
                                <key>default value</key>
                                <string>/bin/sh</string>
                                <key>name</key>
                                <string>shell</string>
                                <key>required</key>
                                <string>0</string>
                                <key>type</key>
                                <string>0</string>
                                <key>uuid</key>
                                <string>4</string>
                            </dict>
                        </dict>
                        <key>isViewVisible</key>
                        <true/>
                    </dict>
                </dict>
            </array>
            <key>connectors</key>
            <dict/>
            <key>workflowMetaData</key>
            <dict>
                <key>applicationBundleID</key>
                <string>com.apple.finder</string>
                <key>applicationBundleIDsByPath</key>
                <dict>
                    <key>/System/Library/CoreServices/Finder.app</key>
                    <string>com.apple.finder</string>
                </dict>
                <key>applicationPath</key>
                <string>/System/Library/CoreServices/Finder.app</string>
                <key>applicationPaths</key>
                <array>
                    <string>/System/Library/CoreServices/Finder.app</string>
                </array>
                <key>inputTypeIdentifier</key>
                <string>com.apple.Automator.fileSystemObject</string>
                <key>outputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>presentationMode</key>
                <integer>15</integer>
                <key>processesInput</key>
                <false/>
                <key>serviceApplicationBundleID</key>
                <string>com.apple.finder</string>
                <key>serviceApplicationPath</key>
                <string>/System/Library/CoreServices/Finder.app</string>
                <key>serviceInputTypeIdentifier</key>
                <string>com.apple.Automator.fileSystemObject</string>
                <key>serviceOutputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>serviceProcessesInput</key>
                <false/>
                <key>systemImageName</key>
                <string>NSActionTemplate</string>
                <key>useAutomaticInputType</key>
                <false/>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """
    }
}
