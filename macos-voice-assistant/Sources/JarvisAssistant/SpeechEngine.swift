import AVFoundation
import Speech

/// Continuous wake-word listening built on SFSpeechRecognizer.
///
/// SFSpeechRecognizer is designed to transcribe a single utterance and then end the task (on
/// end-of-speech, on error, or at Apple's ~1 minute ceiling), so "always listening" has to be
/// implemented by rotating recognition tasks under a continuously-running audio engine. The
/// hard part is doing that without a cascade: when a task ends it can fire an error, and if that
/// error naively triggers "start a new task", a *dying* task firing several trailing errors spawns
/// several overlapping new tasks, which each error, and the whole thing avalanches (observed as
/// dozens of kAFAssistantErrorDomain failures per minute that never recover).
///
/// This is prevented by:
///   * a `generation` counter — every rotation bumps it, and both the audio tap and the task
///     callback ignore anything from a superseded generation, so trailing callbacks from an old
///     task are dropped instead of triggering more rotations;
///   * an `isRotating` guard so only one rotation is ever in flight;
///   * running the entire recognition lifecycle on the main queue so none of the above races.
///
/// The audio engine + tap are installed once and left running for the whole listening session;
/// only the request/task are rotated.
final class SpeechEngine {
    enum State {
        case idle
        case triggered
    }

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    private var state: State = .idle
    private var rawTranscript = ""
    private var consumedCount = 0
    private var lastTranscript = ""
    private var lastChangeTime = Date()
    private var triggerTime = Date()
    private var sessionStartTime = Date()
    private var tickTimer: Timer?

    private var generation = 0
    private var isRotating = false
    private var consecutiveErrorCount = 0
    private var forceServerBasedRecognition = false
    private var isMuted = false
    private var awaitingFollowUp = false
    // Command text committed from earlier recognition tasks during the *current* trigger. Lets a
    // long/paused command survive the recognizer ending a task on its own end-of-speech detection.
    private var accumulatedCommand = ""

    let wakeWord: String
    // Silence (after the command has started) before the command is considered complete.
    let silenceTimeout: TimeInterval
    // How long to wait after the wake word for the user to begin their command.
    let commandStartTimeout: TimeInterval
    // How long to keep listening for a follow-up (no wake word needed) after a reply.
    let followUpWindow: TimeInterval
    // Stay comfortably under Apple's ~1 minute per-task ceiling.
    let maxSessionDuration: TimeInterval = 40
    // Only give up on on-device recognition after several consecutive failures — a single
    // transient error right after a working command isn't reason enough to switch.
    let onDeviceFailureThreshold = 5

    var onStateChange: ((State) -> Void)?
    var onCommand: ((String) -> Void)?
    // Live microphone loudness, 0…1, emitted on the main thread for the reactor's glow. Fires
    // continuously while the audio engine runs (even while muted), so the visual can react to
    // whoever is speaking.
    var onAudioLevel: ((Float) -> Void)?

    init(
        wakeWord: String,
        silenceTimeout: TimeInterval = 2.5,
        commandStartTimeout: TimeInterval = 6.0,
        followUpWindow: TimeInterval = 8.0,
        localeIdentifier: String = "en-IN"
    ) {
        self.wakeWord = wakeWord.lowercased()
        self.silenceTimeout = silenceTimeout
        self.commandStartTimeout = commandStartTimeout
        self.followUpWindow = followUpWindow
        self.recognizer = Self.makeRecognizer(preferred: localeIdentifier)
    }

    /// Build a recognizer for the requested locale, falling back to en-IN, then en-US, then the
    /// system default, so an unsupported locale string never leaves Jarvis unable to listen.
    private static func makeRecognizer(preferred: String) -> SFSpeechRecognizer? {
        for identifier in [preferred, "en-IN", "en-US"] {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: identifier)) {
                Logger.shared.log("Speech recognizer locale: \(identifier)")
                return r
            }
        }
        return SFSpeechRecognizer()
    }

    /// Root-mean-square loudness of a PCM buffer, mapped to a roughly 0…1 range with a bit of gain
    /// so normal speech lands mid-scale. Runs on the audio thread, so it's a tight, allocation-free
    /// loop over the first channel's samples.
    private static func loudness(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let samples = channels[0]
        var sumSquares: Float = 0
        for i in 0..<count {
            let s = samples[i]
            sumSquares += s * s
        }
        let rms = (sumSquares / Float(count)).squareRoot()
        return min(1.0, rms * 9.0)
    }

    /// Stop/allow feeding audio into recognition without tearing anything down — used to keep
    /// Jarvis from transcribing its own text-to-speech while it's talking.
    func setMuted(_ muted: Bool) {
        DispatchQueue.main.async { self.isMuted = muted }
    }

    /// Enter "listening for a follow-up" without requiring the wake word, for `followUpWindow`
    /// seconds. Everything already transcribed is marked consumed so only new speech counts.
    func armFollowUp() {
        DispatchQueue.main.async {
            self.consumedCount = self.rawTranscript.count
            self.lastTranscript = ""
            self.lastChangeTime = Date()
            self.triggerTime = Date()
            self.awaitingFollowUp = true
            self.accumulatedCommand = ""
            self.state = .triggered
            self.onStateChange?(.triggered)
        }
    }

    func start() throws {
        try startAudioEngine()
        try beginRecognition()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        generation += 1 // invalidate any in-flight task/tap callbacks
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func startAudioEngine() throws {
        guard !tapInstalled else { return }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Runs on an audio thread. Feed recognition only when un-muted, but always measure the
            // loudness so the reactor's glow can track the speaker's voice.
            guard let self else { return }
            if !self.isMuted { self.request?.append(buffer) }
            if self.onAudioLevel != nil {
                let level = Self.loudness(of: buffer)
                DispatchQueue.main.async { self.onAudioLevel?(level) }
            }
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Start a fresh recognition task. When `preserveCommand` is true we're rotating in the middle
    /// of a command the user is still speaking, so the command-level state (triggered, accumulated
    /// text, silence clock) is kept and only the per-task transcript is reset.
    private func beginRecognition(preserveCommand: Bool = false) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw JarvisError.speechRecognizerUnavailable
        }
        generation += 1
        let gen = generation

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition && !forceServerBasedRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        rawTranscript = ""
        consumedCount = 0
        lastTranscript = ""
        sessionStartTime = Date()
        if !preserveCommand {
            lastChangeTime = Date()
            state = .idle
            accumulatedCommand = ""
            awaitingFollowUp = false
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                // Drop anything from a session we've already rotated past.
                guard gen == self.generation else { return }
                if let result {
                    self.handle(transcript: result.bestTranscription.formattedString)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.handleSessionEnd(error: error)
                }
            }
        }
    }

    private func handle(transcript: String) {
        consecutiveErrorCount = 0
        guard transcript != rawTranscript else { return }
        rawTranscript = transcript

        let active: String
        if consumedCount > 0, consumedCount <= transcript.count {
            active = String(transcript.dropFirst(consumedCount)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            active = transcript
        }

        if active != lastTranscript {
            lastTranscript = active
            lastChangeTime = Date()
        }
        if state == .idle, active.lowercased().contains(wakeWord) {
            state = .triggered
            triggerTime = Date()
            accumulatedCommand = ""
            onStateChange?(.triggered)
        }
    }

    /// The spoken command with the wake word (and anything before it) stripped off.
    private func commandPortion(of text: String) -> String {
        if let range = text.lowercased().range(of: wakeWord) {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The full command so far: text committed from earlier tasks in this trigger, plus what the
    /// current task has transcribed.
    private func effectiveCommand() -> String {
        let current = commandPortion(of: lastTranscript)
        return (accumulatedCommand + " " + current).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Called (on main) when a recognition task ends — naturally (isFinal), on end-of-speech, or on
    /// error. If the user is mid-command, commit what this task heard and rotate *without* losing
    /// the command, so long/paused sentences survive. Guarded so a burst of trailing errors from
    /// one dying task can't spawn multiple overlapping rotations.
    private func handleSessionEnd(error: Error?) {
        if let error {
            handleError(error)
        }
        if state == .triggered {
            let current = commandPortion(of: lastTranscript)
            if !current.isEmpty {
                accumulatedCommand = (accumulatedCommand + " " + current).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Clear the per-task transcript now (before the async rotation) so a tick landing in the
            // rotation gap sees only the committed text, never it plus a stale copy of `current`.
            lastTranscript = ""
            rotate(afterDelay: error == nil ? 0 : backoffDelay(), preserveCommand: true)
        } else {
            rotate(afterDelay: error == nil ? 0 : backoffDelay(), preserveCommand: false)
        }
    }

    private func handleError(_ error: Error) {
        consecutiveErrorCount += 1
        let nsError = error as NSError

        if nsError.domain == "kAFAssistantErrorDomain",
           !forceServerBasedRecognition,
           consecutiveErrorCount >= onDeviceFailureThreshold {
            forceServerBasedRecognition = true
            Logger.shared.log("""
            On-device speech recognition has failed \(consecutiveErrorCount) times \
            (\(nsError.domain) \(nsError.code)) — likely means the on-device English speech model \
            isn't fully installed (enabling Siri in System Settings, not just Dictation, downloads \
            it). Switching to server-based recognition, which sends audio to Apple's servers and \
            needs network access.
            """)
        }

        if consecutiveErrorCount <= 2 || consecutiveErrorCount % 15 == 0 {
            Logger.shared.log("Speech recognition error (\(consecutiveErrorCount) in a row): \(error.localizedDescription)")
        }
    }

    private func backoffDelay() -> TimeInterval {
        min(Double(consecutiveErrorCount) * 0.4, 4.0)
    }

    private func rotate(afterDelay delay: TimeInterval, preserveCommand: Bool = false) {
        guard !isRotating else { return }
        isRotating = true

        // Bump the generation immediately so any further trailing callbacks from the old task are
        // ignored while we wait out the delay.
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil

        // Only drop the "listening/capturing" indicator back to idle when we're not mid-command.
        if !preserveCommand {
            onStateChange?(.idle)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isRotating = false
            do {
                try self.beginRecognition(preserveCommand: preserveCommand)
            } catch {
                Logger.shared.log("Failed to start a new recognition session: \(error.localizedDescription)")
                // Try again shortly rather than dying silently.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.rotate(afterDelay: 0, preserveCommand: preserveCommand)
                }
            }
        }
    }

    private func tick() {
        let now = Date()
        if state == .triggered {
            let command = effectiveCommand()
            if command.isEmpty {
                // Heard the wake word (or armed a follow-up) but no command yet — wait patiently,
                // then give up quietly so the user isn't rushed. A follow-up gets a longer window.
                let startWindow = awaitingFollowUp ? followUpWindow : commandStartTimeout
                if now.timeIntervalSince(triggerTime) > startWindow {
                    resetToIdle()
                }
            } else if now.timeIntervalSince(lastChangeTime) > silenceTimeout {
                // They've spoken a command and then paused long enough — finish it.
                finalizeCommand(command)
            }
            return
        }
        if now.timeIntervalSince(sessionStartTime) > maxSessionDuration, !isRotating {
            rotate(afterDelay: 0)
        }
    }

    private func resetToIdle() {
        consumedCount = rawTranscript.count
        lastTranscript = ""
        lastChangeTime = Date()
        awaitingFollowUp = false
        accumulatedCommand = ""
        state = .idle
        onStateChange?(.idle)
    }

    private func finalizeCommand(_ command: String) {
        // Mark everything heard so far as consumed and go back to idle scanning. The underlying
        // task keeps running until it naturally ends (which then rotates), so we don't tear it
        // down here.
        resetToIdle()
        if !command.isEmpty {
            onCommand?(command)
        }
    }
}
