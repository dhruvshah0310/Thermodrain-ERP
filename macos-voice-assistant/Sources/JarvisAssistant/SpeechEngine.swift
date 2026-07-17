import AVFoundation
import Speech

/// Runs one continuously-recreated on-device speech recognition session. While the running
/// transcript doesn't contain the wake word, everything is discarded (idle scanning). Once the
/// wake word appears, the same session keeps accumulating audio as the spoken command; a short
/// silence (no transcript change for `silenceTimeout`) finalizes it, hands the trailing text
/// (after the wake word) to `onCommand`, and starts a fresh session to resume wake-word scanning.
///
/// Recognition sessions are recreated periodically regardless, since SFSpeechRecognizer sessions
/// are not meant to run unbounded.
final class SpeechEngine {
    enum State {
        case idle
        case triggered
    }

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var state: State = .idle
    private var lastTranscript = ""
    private var lastChangeTime = Date()
    private var sessionStartTime = Date()
    private var tickTimer: Timer?
    private var consecutiveErrorCount = 0
    private var forceServerBasedRecognition = false

    let wakeWord: String
    let silenceTimeout: TimeInterval = 1.2
    let maxSessionDuration: TimeInterval = 50

    var onStateChange: ((State) -> Void)?
    var onCommand: ((String) -> Void)?

    init(wakeWord: String, locale: Locale = Locale(identifier: "en-US")) {
        self.wakeWord = wakeWord.lowercased()
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func start() throws {
        try startAudioEngineIfNeeded()
        try beginSession()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        task?.cancel()
        request?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func startAudioEngineIfNeeded() throws {
        guard !audioEngine.isRunning else { return }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func beginSession() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw JarvisError.speechRecognizerUnavailable
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition && !forceServerBasedRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req
        lastTranscript = ""
        lastChangeTime = Date()
        sessionStartTime = Date()
        state = .idle

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.handle(transcript: result.bestTranscription.formattedString)
            }
            if let error {
                self.handleRecognitionError(error)
            }
        }
    }

    private func handle(transcript: String) {
        // A real result means recognition is working; forgive past failures.
        consecutiveErrorCount = 0
        if transcript != lastTranscript {
            lastTranscript = transcript
            lastChangeTime = Date()
        }
        if state == .idle, transcript.lowercased().contains(wakeWord) {
            state = .triggered
            onStateChange?(.triggered)
        }
    }

    private func handleRecognitionError(_ error: Error) {
        consecutiveErrorCount += 1
        let nsError = error as NSError

        // kAFAssistantErrorDomain (codes like 209/216/1101/1700) means macOS hasn't downloaded the
        // on-device speech model for this locale yet. Fall back to server-based recognition
        // instead of retrying the same failing on-device request forever.
        if nsError.domain == "kAFAssistantErrorDomain", !forceServerBasedRecognition {
            forceServerBasedRecognition = true
            Logger.shared.log("""
            On-device speech recognition unavailable (\(nsError.domain) \(nsError.code)) — usually \
            means macOS hasn't downloaded the English speech model yet (enable Dictation and/or Siri \
            in System Settings to fix that permanently). Falling back to server-based recognition for \
            now, which requires network access and sends audio to Apple's servers instead of staying \
            on-device.
            """)
        }

        // Back off with each consecutive failure (capped) instead of spinning the CPU and log with
        // an instant restart loop; only log occasionally once the pattern is established.
        if consecutiveErrorCount <= 3 || consecutiveErrorCount % 10 == 0 {
            Logger.shared.log("Speech recognition error (attempt \(consecutiveErrorCount)): \(error.localizedDescription)")
        }
        let delay = min(Double(consecutiveErrorCount) * 0.5, 5.0)
        restartSession(afterDelay: delay)
    }

    private func tick() {
        let now = Date()
        if state == .triggered, now.timeIntervalSince(lastChangeTime) > silenceTimeout, !lastTranscript.isEmpty {
            finalizeCommand()
            return
        }
        if now.timeIntervalSince(sessionStartTime) > maxSessionDuration {
            restartSession()
        }
    }

    private func finalizeCommand() {
        let full = lastTranscript
        var command = full
        if let range = full.lowercased().range(of: wakeWord) {
            command = String(full[range.upperBound...])
        }
        command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        restartSession()
        if !command.isEmpty {
            onCommand?(command)
        }
    }

    private func restartSession(afterDelay delay: TimeInterval = 0) {
        task?.cancel()
        request?.endAudio()
        onStateChange?(.idle)
        guard delay > 0 else {
            beginSessionSafely()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.beginSessionSafely()
        }
    }

    private func beginSessionSafely() {
        do {
            try beginSession()
        } catch {
            Logger.shared.log("Failed to restart speech session: \(error.localizedDescription)")
        }
    }
}
