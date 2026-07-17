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
        apiKey = KeychainStore.loadAPIKey()
        speechEngine = SpeechEngine(wakeWord: config.wakeWord)
        executor = ToolExecutor(config: config)
        try? FileManager.default.createDirectory(at: config.workspaceURL, withIntermediateDirectories: true)
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
            } catch {
                Logger.shared.log("Failed to start speech engine: \(error.localizedDescription)")
                self.statusBar.setState(.error)
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
            statusBar.setState(.speaking)
            speechOutput.speak(
                "I don't have an API key yet. Set one from my menu bar icon.",
                voiceIdentifier: config.voiceIdentifier,
                rate: config.speechRate
            ) { [weak self] in
                self?.statusBar.setState(.idleListening)
            }
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
                await MainActor.run { self.statusBar.setState(.speaking) }
                speechOutput.speak(reply, voiceIdentifier: config.voiceIdentifier, rate: config.speechRate) { [weak self] in
                    self?.statusBar.setState(.idleListening)
                }
            } catch {
                Logger.shared.log("Claude error: \(error.localizedDescription)")
                await MainActor.run { self.statusBar.setState(.idleListening) }
            }
        }
    }
}
