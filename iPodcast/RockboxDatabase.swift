import Foundation

enum PlaybackLog {
    private static let fullyPlayedThreshold = 0.90

    /// Find fully-listened podcast files by parsing .rockbox/playback.log.
    /// Log format: timestamp:elapsed:length:/path/to/file (all times in ms)
    static func findFullyListened(mountPoint: String) throws -> [String] {
        let logPath = (mountPoint as NSString)
            .appendingPathComponent(".rockbox/playback.log")

        guard FileManager.default.fileExists(atPath: logPath) else {
            throw PlaybackLogError.fileNotFound(logPath)
        }

        let content = try String(contentsOf: URL(fileURLWithPath: logPath), encoding: .utf8)
        let events = parseLog(content)

        let podcastsPrefix = (mountPoint as NSString).appendingPathComponent("Podcasts")
        var fullyPlayed: Set<String> = []

        for event in events {
            // Strip Rockbox drive prefix like /<HDD0>/
            let ipodPath: String
            if let range = event.path.range(of: #"^/<[^>]+>"#, options: .regularExpression) {
                ipodPath = String(event.path[range.upperBound...])
            } else {
                ipodPath = event.path
            }

            let fullPath = mountPoint + ipodPath

            guard fullPath.hasPrefix(podcastsPrefix) else { continue }
            guard FileManager.default.fileExists(atPath: fullPath) else { continue }
            guard event.length > 0 else { continue }

            if Double(event.elapsed) / Double(event.length) >= fullyPlayedThreshold {
                fullyPlayed.insert(fullPath)
            }
        }

        return fullyPlayed.sorted()
    }

    private struct Event {
        let elapsed: Int
        let length: Int
        let path: String
    }

    private static func parseLog(_ content: String) -> [Event] {
        var events: [Event] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 3)
            guard parts.count == 4 else { continue }

            guard let elapsed = Int(parts[1]),
                  let length = Int(parts[2])
            else { continue }

            events.append(Event(elapsed: elapsed, length: length, path: String(parts[3])))
        }
        return events
    }
}

enum PlaybackLogError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): "File not found: \(path)"
        }
    }
}
