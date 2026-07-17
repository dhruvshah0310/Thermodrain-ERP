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
    // Seconds of silence (after you've started speaking a command) before Jarvis considers the
    // command finished. Raise this if it cuts you off between words.
    var silenceTimeout: Double
    // Seconds Jarvis waits, after hearing the wake word, for you to actually start your command
    // before giving up and going back to idle. Raise this if you need more time to think.
    var commandStartTimeout: Double
    // After Jarvis replies, keep listening for a follow-up command without needing the wake word
    // again, so a back-and-forth conversation flows naturally.
    var conversationMode: Bool
    // Seconds to keep listening for a follow-up after a reply before returning to wake-word mode.
    var followUpWindow: Double
    // Speak a greeting when the app launches (e.g. at login).
    var greetOnLaunch: Bool
    // Optional name for a personalized greeting, e.g. "Good morning, Dhruv." Leave null for none.
    var userName: String?
    // BCP-47 locale for speech recognition. "en-IN" understands Indian-accented English best;
    // "en-US", "en-GB", etc. also work. Falls back gracefully if the locale isn't supported.
    var speechLocale: String
    // Let Claude search the web (Anthropic's server-side web_search tool) before answering.
    // Requires a recent model (the default claude-sonnet-5 supports it).
    var allowWebSearch: Bool

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
        maxToolIterations: 16,
        launchAtLogin: false,
        silenceTimeout: 2.5,
        commandStartTimeout: 6.0,
        conversationMode: true,
        followUpWindow: 8.0,
        greetOnLaunch: true,
        userName: nil,
        speechLocale: "en-IN",
        allowWebSearch: true
    )

    // Resilient decoding: any key missing from an older config.json falls back to the default,
    // so adding new settings never fails to load or silently wipes the user's existing file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        wakeWord = try c.decodeIfPresent(String.self, forKey: .wakeWord) ?? d.wakeWord
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier) ?? d.voiceIdentifier
        speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? d.speechRate
        allowShellCommands = try c.decodeIfPresent(Bool.self, forKey: .allowShellCommands) ?? d.allowShellCommands
        allowAppleScript = try c.decodeIfPresent(Bool.self, forKey: .allowAppleScript) ?? d.allowAppleScript
        allowOpenApps = try c.decodeIfPresent(Bool.self, forKey: .allowOpenApps) ?? d.allowOpenApps
        allowFileAccess = try c.decodeIfPresent(Bool.self, forKey: .allowFileAccess) ?? d.allowFileAccess
        workspaceDirectory = try c.decodeIfPresent(String.self, forKey: .workspaceDirectory) ?? d.workspaceDirectory
        maxToolIterations = try c.decodeIfPresent(Int.self, forKey: .maxToolIterations) ?? d.maxToolIterations
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        silenceTimeout = try c.decodeIfPresent(Double.self, forKey: .silenceTimeout) ?? d.silenceTimeout
        commandStartTimeout = try c.decodeIfPresent(Double.self, forKey: .commandStartTimeout) ?? d.commandStartTimeout
        conversationMode = try c.decodeIfPresent(Bool.self, forKey: .conversationMode) ?? d.conversationMode
        followUpWindow = try c.decodeIfPresent(Double.self, forKey: .followUpWindow) ?? d.followUpWindow
        greetOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .greetOnLaunch) ?? d.greetOnLaunch
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? d.userName
        speechLocale = try c.decodeIfPresent(String.self, forKey: .speechLocale) ?? d.speechLocale
        allowWebSearch = try c.decodeIfPresent(Bool.self, forKey: .allowWebSearch) ?? d.allowWebSearch
    }

    private init(
        model: String, wakeWord: String, voiceIdentifier: String?, speechRate: Float,
        allowShellCommands: Bool, allowAppleScript: Bool, allowOpenApps: Bool, allowFileAccess: Bool,
        workspaceDirectory: String, maxToolIterations: Int, launchAtLogin: Bool,
        silenceTimeout: Double, commandStartTimeout: Double,
        conversationMode: Bool, followUpWindow: Double, greetOnLaunch: Bool, userName: String?,
        speechLocale: String, allowWebSearch: Bool
    ) {
        self.model = model
        self.wakeWord = wakeWord
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
        self.allowShellCommands = allowShellCommands
        self.allowAppleScript = allowAppleScript
        self.allowOpenApps = allowOpenApps
        self.allowFileAccess = allowFileAccess
        self.workspaceDirectory = workspaceDirectory
        self.maxToolIterations = maxToolIterations
        self.launchAtLogin = launchAtLogin
        self.silenceTimeout = silenceTimeout
        self.commandStartTimeout = commandStartTimeout
        self.conversationMode = conversationMode
        self.followUpWindow = followUpWindow
        self.greetOnLaunch = greetOnLaunch
        self.userName = userName
        self.speechLocale = speechLocale
        self.allowWebSearch = allowWebSearch
    }

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
