import Foundation

/// Installs/removes a launchd LaunchAgent so JarvisAssistant starts at login and stays running.
/// Uses launchctl directly (rather than ServiceManagement's SMAppService, which targets .app
/// bundles) because this ships as a plain command-line executable.
enum LaunchAgent {
    static let label = "com.jarvis.assistant"

    static var plistURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(label).plist")
    }

    static func install(binaryPath: String) {
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JarvisAssistant")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryPath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logDir.appendingPathComponent("stdout.log").path,
            "StandardErrorPath": logDir.appendingPathComponent("stderr.log").path
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            runLaunchctl(["load", "-w", plistURL.path])
            Logger.shared.log("Installed LaunchAgent at \(plistURL.path) for \(binaryPath)")
        } catch {
            Logger.shared.log("LaunchAgent install error: \(error.localizedDescription)")
        }
    }

    static func uninstall() {
        runLaunchctl(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        Logger.shared.log("Removed LaunchAgent")
    }

    private static func runLaunchctl(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        try? task.run()
        task.waitUntilExit()
    }
}
