import AVFoundation
import Foundation
import Speech

final class JarvisController {
    var config: Config
    private var apiKey: String?
    private let speechEngine: SpeechEngine
    private let speechOutput = SpeechOutput()
    private let executor: ToolExecutor
    private var statusBar: StatusBarController!

    private static let systemPrompt = """
    You are Jarvis, a voice assistant running locally on the user's Mac. You were just given a \
    spoken command transcribed by on-device speech recognition — it may contain small \
    transcription errors, so use judgement about likely intent. Reply in short, natural spoken \
    sentences: this text is read aloud by text-to-speech, so use no markdown, no bullet points, \
    no code blocks. Use the available tools to actually perform tasks (open apps, control the Mac \
    via AppleScript, read/write files in the workspace) rather than just describing what you \
    would do. If a request is ambiguous or risky, ask a brief clarifying question instead of \
    guessing.
    """

    init() {
        config = Config.load()
        speechEngine = SpeechEngine(
            wakeWord: config.wakeWord,
            silenceTimeout: config.silenceTimeout,
            commandStartTimeout: config.commandStartTimeout,
            followUpWindow: config.followUpWindow
        )
        executor = ToolExecutor(config: config)
        try? FileManager.default.createDirectory(at: config.workspaceURL, withIntermediateDirectories: true)
        apiKey = Self.resolveAPIKey()
    }

    /// Resolve the API key, in priority order:
    ///   1. the `ANTHROPIC_API_KEY` environment variable (easiest when launching from Terminal —
    ///      Terminal paste works even when the app's dialog won't accept it). Checked first so it
    ///      can overwrite a wrong key that's already stuck in the Keychain.
    ///   2. a plaintext file at `~/JarvisAssistant/api-key.txt`.
    ///   3. the macOS Keychain (set via the menu dialog or persisted from 1/2 on a prior launch).
    /// If found via 1 or 2, it's copied into the Keychain so it persists for future launches.
    private static func resolveAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            KeychainStore.saveAPIKey(env)
            Logger.shared.log("Loaded API key from ANTHROPIC_API_KEY and saved it to the Keychain.")
            return env
        }
        let fileURL = URL(fileURLWithPath: ("~/JarvisAssistant/api-key.txt" as NSString).expandingTildeInPath)
        if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
            let key = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                KeychainStore.saveAPIKey(key)
                Logger.shared.log("Loaded API key from \(fileURL.path) and saved it to the Keychain.")
                return key
            }
        }
        if let key = KeychainStore.loadAPIKey(), !key.isEmpty {
            return key
        }
        return nil
    }

    func attach(statusBar: StatusBarController) {
        self.statusBar = statusBar
    }

    func reloadAPIKey() {
        apiKey = KeychainStore.loadAPIKey()
    }

    /// Stop capturing audio while a blocking dialog (e.g. the API key prompt) is on screen.
    /// Showing an NSAlert modal while the recognition task keeps running has been observed to
    /// leave the task in a permanently broken state, so callers should pause around any
    /// `runModal()` call and resume afterward.
    func pauseListening() {
        speechEngine.stop()
        statusBar.setState(.idleListening)
    }

    func resumeListening() {
        do {
            try speechEngine.start()
        } catch {
            Logger.shared.log("Failed to resume speech engine: \(error.localizedDescription)")
            statusBar.setState(.error)
        }
    }

    func start() {
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Logger.shared.log("Microphone/Speech permission not granted; cannot start listening. Grant access in System Settings > Privacy & Security, then relaunch.")
                self.statusBar.setState(.error)
                return
            }

            self.speechEngine.onStateChange = { [weak self] state in
                self?.statusBar.setState(state == .triggered ? .capturing : .idleListening)
            }
            self.speechEngine.onCommand = { [weak self] command in
                self?.handle(command: command)
            }

            do {
                try self.speechEngine.start()
                Logger.shared.log("Listening for wake word '\(self.config.wakeWord)'")
                self.statusBar.setState(.idleListening)
                self.greetIfEnabled()
            } catch {
                Logger.shared.log("Failed to start speech engine: \(error.localizedDescription)")
                self.statusBar.setState(.error)
            }
        }
    }

    private func greetIfEnabled() {
        guard config.greetOnLaunch else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Hello"
        }
        let name = config.userName.map { ", \($0)" } ?? ""
        speak("\(part)\(name). Jarvis is online and ready.")
    }

    /// Speak text, muting the mic while talking so Jarvis doesn't transcribe its own voice, then
    /// either arm a follow-up (conversation mode, so no wake word is needed for the next command)
    /// or return to wake-word idle.
    private func speak(_ text: String) {
        speechEngine.setMuted(true)
        statusBar.setState(.speaking)
        speechOutput.speak(text, voiceIdentifier: config.voiceIdentifier, rate: config.speechRate) { [weak self] in
            guard let self else { return }
            self.speechEngine.setMuted(false)
            if self.config.conversationMode {
                self.speechEngine.armFollowUp()
            } else {
                self.statusBar.setState(.idleListening)
            }
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                DispatchQueue.main.async {
                    completion(speechStatus == .authorized && micGranted)
                }
            }
        }
    }

    private func handle(command: String) {
        guard !command.isEmpty else { return }

        guard let apiKey else {
            Logger.shared.log("No API key set — open the menu bar icon and choose 'Set Anthropic API Key…'.")
            speak("I don't have an API key yet. Set one from my menu bar icon.")
            return
        }

        Logger.shared.log("Command: \(command)")
        statusBar.setState(.thinking)

        let client = ClaudeClient(apiKey: apiKey, model: config.model, maxIterations: config.maxToolIterations)
        let tools = JarvisTools.allTools(config: config)

        Task {
            do {
                let reply = try await client.converse(
                    userText: command,
                    systemPrompt: Self.systemPrompt,
                    tools: tools,
                    executor: executor
                )
                Logger.shared.log("Reply: \(reply)")
                await MainActor.run { self.speak(reply) }
            } catch {
                Logger.shared.log("Claude error: \(error.localizedDescription)")
                await MainActor.run {
                    self.speak("Sorry, I ran into an error reaching Claude. Check the log for details.")
                }
            }
        }
    }
}
