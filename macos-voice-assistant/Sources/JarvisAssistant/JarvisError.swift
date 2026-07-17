import Foundation

enum JarvisError: Error, LocalizedError {
    case speechRecognizerUnavailable
    case malformedResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognizer unavailable for the configured locale."
        case .malformedResponse:
            return "Received an unexpected response shape from the Claude API."
        case .apiError(let text):
            return "Claude API error: \(text)"
        }
    }
}
