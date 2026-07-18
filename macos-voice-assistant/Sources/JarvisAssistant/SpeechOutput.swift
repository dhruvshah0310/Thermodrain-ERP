import AVFoundation

final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voiceIdentifier: String?, gender: String, rate: Float, completion: @escaping () -> Void) {
        self.completion = completion
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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let done = completion
        completion = nil
        done?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let done = completion
        completion = nil
        done?()
    }
}
