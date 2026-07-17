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
        if recognizer.supportsOnDeviceRecognition {
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
                Logger.shared.log("Speech recognition error (restarting session): \(error.localizedDescription)")
                self.restartSession()
            }
        }
    }

    private func handle(transcript: String) {
        if transcript != lastTranscript {
            lastTranscript = transcript
            lastChangeTime = Date()
        }
        if state == .idle, transcript.lowercased().contains(wakeWord) {
            state = .triggered
            onStateChange?(.triggered)
        }
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

    private func restartSession() {
        task?.cancel()
        request?.endAudio()
        do {
            try beginSession()
        } catch {
            Logger.shared.log("Failed to restart speech session: \(error.localizedDescription)")
        }
        onStateChange?(.idle)
    }
}
