import Foundation

final class Logger {
    static let shared = Logger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "jarvis.logger")
    private var recentLinesStorage: [String] = []

    var recentLines: [String] {
        queue.sync { recentLinesStorage }
    }

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/JarvisAssistant")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("jarvis.log")
    }

    func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)"
        queue.async {
            // Write to stderr, never stdout: in MCP-server mode stdout carries JSON-RPC and any
            // stray text there would corrupt the protocol stream. stderr is still visible in a
            // terminal for the menu-bar app.
            FileHandle.standardError.write(Data((line + "\n").utf8))
            self.recentLinesStorage.append(line)
            if self.recentLinesStorage.count > 200 {
                self.recentLinesStorage.removeFirst()
            }
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: self.fileURL)
            }
        }
    }
}
