import Foundation

/// Append-only trace log. The Touch Bar and menus can't be screenshotted from
/// here, so real interactions have to leave evidence behind instead.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/TouchBarToys.log")

    private static let queue = DispatchQueue(label: "com.touchbartoys.app.log")
    private static let started = Date()

    static func write(_ message: String) {
        let stamp = String(format: "%7.3f", Date().timeIntervalSince(started))
        let line = "[\(stamp)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func startSession(_ note: String) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        write("session start — \(note)")
    }
}
