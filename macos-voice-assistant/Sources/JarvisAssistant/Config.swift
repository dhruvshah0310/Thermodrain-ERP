import Foundation

struct Config: Codable {
    var model: String
    var wakeWord: String
    var voiceIdentifier: String?
    var speechRate: Float
    var allowShellCommands: Bool
    var allowAppleScript: Bool
    var allowOpenApps: Bool
    var allowFileAccess: Bool
    var workspaceDirectory: String
    var maxToolIterations: Int
    var launchAtLogin: Bool

    static let `default` = Config(
        // Claude Code's internal short model names (e.g. "claude-sonnet-5") don't always match the
        // public Anthropic API's exact model string. Verify the current one at
        // https://docs.anthropic.com/en/docs/about-claude/models before your first run and update
        // this file (~/Library/Application Support/JarvisAssistant/config.json) if needed.
        model: "claude-sonnet-5",
        wakeWord: "jarvis",
        voiceIdentifier: nil,
        speechRate: 0.5,
        allowShellCommands: false,
        allowAppleScript: true,
        allowOpenApps: true,
        allowFileAccess: true,
        workspaceDirectory: "~/JarvisAssistant/workspace",
        maxToolIterations: 6,
        launchAtLogin: false
    )

    var workspaceURL: URL {
        URL(fileURLWithPath: (workspaceDirectory as NSString).expandingTildeInPath)
    }

    static var configFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JarvisAssistant")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        let url = configFileURL
        guard
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(Config.self, from: data)
        else {
            let config = Config.default
            config.save()
            return config
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Config.configFileURL)
    }
}
