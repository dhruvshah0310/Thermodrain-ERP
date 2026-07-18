import AVFoundation

/// Text-to-speech. To let the arc-reactor pulse *precisely* to Jarvis's own voice, this renders the
/// utterance to PCM buffers (`AVSpeechSynthesizer.write`) and plays them through an `AVAudioEngine`,
/// tapping the mixer output to publish a live loudness level. If the engine can't start for any
/// reason, it falls back to speaking the utterance directly so speech never breaks (the reactor then
/// just uses its idle breathing during that reply).
final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()      // used for rendering (write)
    private let fallbackSynth = AVSpeechSynthesizer()    // used only for direct-speech fallback
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var completion: (() -> Void)?
    private var scheduledBuffers = 0
    private var finishedBuffers = 0
    private var receivedEnd = false
    private var usingEngine = false
    private var tapInstalled = false
    private var fellBack = false
    private var completed = false

    /// Live loudness of the spoken audio, 0…1, emitted on the main thread for the reactor's glow.
    var onAudioLevel: ((Float) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        fallbackSynth.delegate = self
        engine.attach(player)
    }

    func speak(_ text: String, voiceIdentifier: String?, gender: String, rate: Float, completion: @escaping () -> Void) {
        self.completion = completion
        scheduledBuffers = 0
        finishedBuffers = 0
        receivedEnd = false
        usingEngine = false
        fellBack = false
        completed = false

        let voice = Self.resolveVoice(identifier: voiceIdentifier, gender: gender)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate

        // Render (not speak) the utterance to audio buffers; we play them ourselves so we can meter
        // the exact output. The callback delivers buffers and finally a zero-length end marker.
        synthesizer.write(utterance) { [weak self] buffer in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleRendered(buffer, text: text, voice: voice, rate: rate)
            }
        }
    }

    private func handleRendered(_ buffer: AVAudioBuffer, text: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        if fellBack { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }

        if pcm.frameLength == 0 {
            receivedEnd = true
            finishIfDone()
            return
        }

        if !usingEngine {
            if startEngine(format: pcm.format) {
                usingEngine = true
            } else {
                // Engine couldn't start — speak this reply directly instead so it's still heard.
                fellBack = true
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = rate
                fallbackSynth.speak(utterance)
                return
            }
        }

        scheduledBuffers += 1
        player.scheduleBuffer(pcm) { [weak self] in
            DispatchQueue.main.async {
                self?.finishedBuffers += 1
                self?.finishIfDone()
            }
        }
    }

    /// (Re)connect the player with the rendered audio's format, install the metering tap once, and
    /// start playback. Returns false if the engine won't start.
    private func startEngine(format: AVAudioFormat) -> Bool {
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        if !tapInstalled {
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                guard let self, self.onAudioLevel != nil else { return }
                let level = SpeechOutput.loudness(of: buffer)
                DispatchQueue.main.async { self.onAudioLevel?(level) }
            }
            tapInstalled = true
        }

        engine.prepare()
        do {
            try engine.start()
            player.play()
            return true
        } catch {
            Logger.shared.log("TTS audio engine failed to start (\(error.localizedDescription)); speaking directly instead.")
            return false
        }
    }

    private func finishIfDone() {
        guard !completed, !fellBack, receivedEnd, finishedBuffers >= scheduledBuffers else { return }
        completed = true
        if engine.isRunning {
            player.stop()
            engine.stop()
        }
        usingEngine = false
        onAudioLevel?(0)
        let done = completion
        completion = nil
        done?()
    }

    /// RMS loudness of a PCM buffer's first channel, mapped to ~0…1. Runs on an audio thread.
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

    /// Pick the voice to speak with. An explicit `identifier` (from config) always wins. Otherwise
    /// choose the best installed English voice of the requested gender ("male"/"female"), preferring
    /// a British accent (that Jarvis feel) and higher-quality voices. Falls back gracefully so we
    /// never end up with no voice.
    static func resolveVoice(identifier: String?, gender: String) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        let wantFemale = gender.lowercased() == "female"
        let want: AVSpeechSynthesisVoiceGender = wantFemale ? .female : .male
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }

        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            if v.gender == want { s += 100 }
            if v.language == "en-GB" { s += 12 } else if v.language == "en-US" { s += 8 }
            else if v.language.hasPrefix("en") { s += 4 }
            // rawValue rises with quality (default=1, enhanced=2, premium=3) — avoids naming a case
            // that may not exist on older SDKs.
            s += v.quality.rawValue
            return s
        }

        if let best = english.max(by: { score($0) < score($1) }), !english.isEmpty {
            return best
        }
        return AVSpeechSynthesisVoice(language: wantFemale ? "en-US" : "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // Delegate callbacks fire only for the fallback synthesizer (the primary one renders via write,
    // which doesn't speak), so completing here is safe and only happens on the fallback path.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishFromFallback()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishFromFallback()
    }

    private func finishFromFallback() {
        guard !completed else { return }
        completed = true
        onAudioLevel?(0)
        let done = completion
        completion = nil
        done?()
    }
}
