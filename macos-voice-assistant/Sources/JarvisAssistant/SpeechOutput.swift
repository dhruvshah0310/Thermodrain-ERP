import AVFoundation

/// Text-to-speech. Uses `AVSpeechSynthesizer.speak` directly — the one reliable path that plays each
/// reply exactly once (an earlier attempt to render to buffers via `write` and play them through an
/// audio engine caused replies to double up on some macOS versions, since `write` can also route to
/// the speakers). Sumo's mouth is driven from the `willSpeakRange` delegate callback, so it moves in
/// time with the words as they're spoken.
final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?
    private var completed = false

    /// Emitted on the main thread: a mouth-open pulse (0…1) per spoken word, then 0 when finished.
    var onAudioLevel: ((Float) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voiceIdentifier: String?, gender: String, rate: Float, completion: @escaping () -> Void) {
        // Cancel anything still in flight so a reply can never overlap a previous one.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        self.completion = completion
        completed = false

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.resolveVoice(identifier: voiceIdentifier, gender: gender)
        utterance.rate = rate
        synthesizer.speak(utterance)
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
            s += v.quality.rawValue  // default=1, enhanced=2, premium=3
            return s
        }

        if let best = english.max(by: { score($0) < score($1) }), !english.isEmpty {
            return best
        }
        return AVSpeechSynthesisVoice(language: wantFemale ? "en-US" : "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // A pulse per word; SumoView eases the mouth open then closed between words.
        onAudioLevel?(0.9)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        onAudioLevel?(0)
        let done = completion
        completion = nil
        done?()
    }
}
