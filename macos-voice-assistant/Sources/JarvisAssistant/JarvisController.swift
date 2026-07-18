import AVFoundation
import Foundation
import Speech

final class JarvisController {
    var config: Config
    private var apiKey: String?
    private let speechEngine: SpeechEngine
    private let speechOutput = SpeechOutput()
    private var statusBar: StatusBarController!
    // Siri-style floating window (arc-reactor). Created on launch when config.showOverlay is on.
    private var overlay: HUDWindowController?
    // True while a command is being handled (thinking → speaking). Used so the overlay isn't hidden
    // by the speech engine's idle rotations that happen underneath while Jarvis is busy.
    private var isBusy = false
    // True while Jarvis is speaking. While set, the reactor's glow is driven by the text-to-speech
    // output level (not the microphone), so it pulses precisely to Jarvis's own voice.
    private var isSpeaking = false

    // Rolling conversation memory: the last few plain-text user/assistant turns, so follow-up
    // commands ("reply to him", "open it", "what about tomorrow?") carry context. Kept text-only
    // (no tool_use/tool_result blocks) to stay small, and cleared after a long idle gap.
    private var conversationHistory: [[String: Any]] = []
    private var lastCommandAt: Date?
    private static let maxHistoryTurns = 6  // 6 user+assistant pairs = 12 messages

    private static let systemPrompt = """
    You are Jarvis, a voice assistant running on the user's Mac. You were just given a command \
    transcribed by speech recognition (Indian-accented English), so it may contain small \
    transcription errors — infer the likely intent. Reply in short, natural spoken sentences: your \
    reply is read aloud by text-to-speech, so no markdown, bullet points, or code blocks. When \
    asked a question, just answer it conversationally. When asked to DO something, use the tools \
    to actually do it rather than only describing it. If a request is genuinely ambiguous or \
    risky, ask one brief clarifying question.

    You can control the Mac through these tools: open_application, open_url, run_applescript, \
    type_text, press_key, paste_text, wait, screenshot + mouse (click/scroll) for visual control, \
    clipboard read/write, screen context, system controls (volume, mute, brightness, lock, sleep), \
    dedicated app tools (Music, Reminders, Notes, Messages/iMessage, Calendar), and file tools. \
    Prefer the dedicated/system tools when they fit; fall back to run_applescript or \
    screenshot+click for anything else. Guidance for common tasks:

    • Files: if the workspace file tools (read_file/write_file/list_workspace_files) are available, \
    use them for scratch notes. If the full-disk file tools (read_any_file, write_any_file, \
    list_directory, move_path, delete_path, open_path) are available, you can work with files \
    anywhere on the Mac — use absolute or ~-relative paths. Be careful with delete_path (it's \
    permanent, not the Trash); confirm first if a deletion isn't clearly what the user asked for.

    • WhatsApp by phone number (fewest steps, prefer this when you have a number): open the URL \
    https://wa.me/<number>?text=<url-encoded message> (full international format, no + or spaces, \
    e.g. 919876543210). It opens the chat with the message pre-filled; wait ~2s, then press_key \
    "return" to send.

    • WhatsApp by contact name (when you only have a name, not a number): open_application \
    "WhatsApp"; wait ~2s; press_key "f" with modifier "command"; type_text the contact name; \
    wait ~1.5s; press_key "return" to open the top matching chat; wait ~1s; type_text the \
    message; wait ~0.5s; press_key "return" to send. IMPORTANT: pass app:"WhatsApp" on every \
    type_text and press_key here so the input is directed into WhatsApp, not whatever else might \
    be focused.

    UI automation like this is best-effort — you are sending keystrokes and cannot actually see \
    whether they landed correctly. So NEVER claim a message was definitely delivered. After \
    attempting it, say something like "I've tried to send that on WhatsApp — can you check it \
    went through?" rather than stating it was sent. Only state success for things whose tool \
    result truly confirms it (e.g. an app opened).

    • Email with Apple Mail: use run_applescript with Mail's scripting, e.g. make a new outgoing \
    message with the subject/content/recipient, then send it. Confirm the recipient if unsure.

    • Other apps without scripting support: open_application to focus them, then type_text and \
    press_key to drive their interface, with short wait calls in between so the UI keeps up.

    • Seeing and clicking the screen (computer use): when a task needs you to see what's on screen \
    or click something that isn't reachable by keyboard, use the screenshot tool to look, then \
    click / double_click / right_click / move_mouse / scroll at the coordinates you see. The \
    screenshot tells you the screen size in points; coordinates are top-left origin and map 1:1 to \
    the click tools. Always screenshot before clicking (to find the target) and again after (to \
    confirm it worked) — accuracy matters more than speed, so verify rather than assume. Prefer \
    keyboard shortcuts and AppleScript when they're reliable; fall back to screenshot+click for \
    anything visual.

    • General knowledge, explanations, drafting text, advice: answer directly — that's the \
    "learning from Claude" part. But when the answer depends on current or factual information \
    you're not sure of (news, prices, weather, sports scores, recent events, specific facts, \
    "look up X"), USE the web_search tool to check before answering rather than guessing. It's \
    better to search and be right than to answer from stale memory.

    • For long or special-character text (a full message, an email body, anything with emoji), \
    prefer paste_text over type_text — it's more reliable. Pass app:"<AppName>" so it lands in \
    the right place.

    • Verifying your work: UI actions driven by keystrokes or clicks (type_text, press_key, \
    paste_text, click) are blind — you're dispatching input and can't tell from the tool result \
    whether it actually landed. When the outcome matters (a message sent, a form filled, a button \
    pressed), take a screenshot afterward to confirm, and retry if it didn't work. Accuracy over \
    speed. Only claim success for things a tool result truly confirms.

    You may be given a few recent turns of our conversation as context. Use them to resolve \
    follow-ups that refer back ("reply to him", "open that", "what about tomorrow?") — but if a new \
    command clearly starts a fresh topic, don't force a connection to the old one.

    Work autonomously and thoroughly, like a capable assistant: research when useful, then do the \
    whole task in one go with several tool calls, and finish with a brief spoken confirmation of \
    what you did. Don't ask for permission on reversible actions that clearly follow from the \
    request — just do them.
    """

    init() {
        config = Config.load()
        speechEngine = SpeechEngine(
            wakeWord: config.wakeWord,
            silenceTimeout: config.silenceTimeout,
            commandStartTimeout: config.commandStartTimeout,
            followUpWindow: config.followUpWindow,
            localeIdentifier: config.speechLocale
        )
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

            if self.config.showOverlay {
                self.overlay = HUDWindowController()
            }

            self.speechEngine.onStateChange = { [weak self] state in
                guard let self else { return }
                self.statusBar.setState(state == .triggered ? .capturing : .idleListening)
                if state == .triggered {
                    self.overlay?.showListening()
                } else if !self.isBusy {
                    // Only fold the overlay away on a genuine return to idle, not on the background
                    // recognition rotations that happen while a command is being worked on.
                    self.overlay?.scheduleHide()
                }
            }
            self.speechEngine.onCommand = { [weak self] command in
                self?.handle(command: command)
            }
            if self.overlay != nil {
                // Microphone level drives the reactor except while Jarvis is speaking…
                self.speechEngine.onAudioLevel = { [weak self] level in
                    guard let self, !self.isSpeaking else { return }
                    self.overlay?.setLevel(level)
                }
                // …when the text-to-speech output level takes over, so it pulses to Jarvis's voice.
                self.speechOutput.onAudioLevel = { [weak self] level in
                    guard let self, self.isSpeaking else { return }
                    self.overlay?.setLevel(level)
                }
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
        isSpeaking = true
        statusBar.setState(.speaking)
        speechOutput.speak(text, voiceIdentifier: config.voiceIdentifier, gender: config.voiceGender, rate: config.speechRate) { [weak self] in
            guard let self else { return }
            self.isBusy = false
            self.isSpeaking = false
            self.speechEngine.setMuted(false)
            if self.config.conversationMode {
                // armFollowUp fires .triggered, which re-shows the overlay in listening mode.
                self.speechEngine.armFollowUp()
            } else {
                self.statusBar.setState(.idleListening)
                self.overlay?.scheduleHide()
            }
        }
    }

    /// Append the just-finished exchange to conversation memory, trimming to the last few turns.
    /// An empty reply (e.g. an error path) isn't stored so it can't poison later context.
    private func recordTurn(command: String, reply: String) {
        guard !reply.isEmpty else { return }
        conversationHistory.append(["role": "user", "content": command])
        conversationHistory.append(["role": "assistant", "content": reply])
        let maxMessages = Self.maxHistoryTurns * 2
        if conversationHistory.count > maxMessages {
            conversationHistory.removeFirst(conversationHistory.count - maxMessages)
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
        isBusy = true
        overlay?.showThinking(command)

        // Drop stale context: if it's been a while since the last command, start fresh so an
        // unrelated command doesn't inherit an old conversation's context.
        if let last = lastCommandAt, Date().timeIntervalSince(last) > config.conversationMemoryTimeout {
            conversationHistory.removeAll()
        }
        lastCommandAt = Date()
        let history = conversationHistory

        let client = ClaudeClient(apiKey: apiKey, model: config.model, maxIterations: config.maxToolIterations)
        let tools = JarvisTools.allTools(config: config)
        let serverTools = JarvisTools.serverTools(config: config)
        // Build the executor from the live config each command so menu toggles (screen control,
        // full file access, shell) take effect immediately, not just on relaunch.
        let executor = ToolExecutor(config: config)

        Task {
            do {
                let reply = try await client.converse(
                    userText: command,
                    systemPrompt: Self.systemPrompt,
                    tools: tools,
                    serverTools: serverTools,
                    executor: executor,
                    history: history
                )
                Logger.shared.log("Reply: \(reply)")
                await MainActor.run {
                    self.recordTurn(command: command, reply: reply)
                    self.overlay?.showSpeaking(reply)
                    self.speak(reply)
                }
            } catch {
                Logger.shared.log("Claude error: \(error.localizedDescription)")
                await MainActor.run {
                    let message = "Sorry, I ran into an error reaching Claude. Check the log for details."
                    self.overlay?.showSpeaking(message)
                    self.speak(message)
                }
            }
        }
    }
}
