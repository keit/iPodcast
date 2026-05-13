import AppKit
import Foundation
import Observation

struct Episode {
    let title: String
    let audioURL: URL
    let filename: String
    let pubDate: String
}

struct PodcastFile: Identifiable {
    var id: String { filename }
    let filename: String
    let played: Bool
}

struct PodcastShow: Identifiable {
    var id: String { name }
    let name: String
    let artworkURL: URL?
    let files: [PodcastFile]
}

struct FeedInfo: Identifiable {
    var id: String { appleURL }
    let appleURL: String
    let collectionName: String
    let primaryGenreName: String
    let artworkURL: URL?
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@MainActor
@Observable
final class PodcastManager {
    var logMessages: [LogEntry] = []
    var podcastShows: [PodcastShow] = []
    var isSyncing = false
    var isCleaning = false

    var iPodMountPoint = "/Volumes/IPOD"
    var episodeLimit = 5

    var feeds: [String] {
        didSet { UserDefaults.standard.set(feeds, forKey: Self.feedsKey) }
    }

    private var artworkByShowName: [String: URL] = [:]

    private static let feedsKey = "feeds"

    static let defaultFeeds = [
        "https://podcasts.apple.com/us/podcast/the-10-minute-jazz-lesson-podcast/id1087454803",
        "https://podcasts.apple.com/jp/podcast/backspace-fm/id830709730",
        "https://podcasts.apple.com/us/podcast/not-news/id1809874971",
        "https://podcasts.apple.com/jp/podcast/rebuild/id603013428",
        "https://podcasts.apple.com/nz/podcast/%E3%82%B5%E3%82%A4%E3%82%A8%E3%83%B3%E3%83%88%E3%83%BC%E3%82%AF/id1566371326",
        "https://podcasts.apple.com/nz/podcast/podcast-by-yuka-studio-ユカスタポッドキャスト/id1665465325",
        "https://podcasts.apple.com/nz/podcast/al-jazeera-news-updates/id1412845697",
    ]

    private var podcastsDirectory: String {
        (iPodMountPoint as NSString).appendingPathComponent("Podcasts")
    }

    var isBusy: Bool { isSyncing || isCleaning }

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.feedsKey), !saved.isEmpty {
            self.feeds = saved
        } else {
            self.feeds = Self.defaultFeeds
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "podcast-downloader/1.0"]
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private func log(_ message: String, isError: Bool = false) {
        logMessages.append(LogEntry(message: message, isError: isError))
    }

    // MARK: - Sync

    func syncNewPodcasts() async {
        guard !isBusy else { return }
        isSyncing = true
        defer { isSyncing = false }
        logMessages.removeAll()

        try? FileManager.default.createDirectory(
            atPath: podcastsDirectory, withIntermediateDirectories: true)

        for appleURL in feeds {
            await syncFeed(appleURL: appleURL)
        }

        log("Done.")
        scanPodcastFiles()
    }

    private func syncFeed(appleURL: String) async {
        log("=== \(appleURL) ===")

        let showTitle: String
        let feedURL: String
        do {
            (showTitle, feedURL) = try await resolveFeed(appleURL: appleURL)
        } catch {
            log("  ERROR resolving feed: \(error.localizedDescription)", isError: true)
            return
        }

        log("  \(showTitle)")
        log("  RSS: \(feedURL)")

        let episodes: [Episode]
        do {
            episodes = try await fetchAndParseEpisodes(feedURL: feedURL)
        } catch {
            log("  ERROR fetching feed: \(error.localizedDescription)", isError: true)
            return
        }

        if episodes.isEmpty {
            log("  No episodes found.")
            return
        }

        let showDir = (podcastsDirectory as NSString)
            .appendingPathComponent(Self.sanitizeFilename(showTitle))
        try? FileManager.default.createDirectory(
            atPath: showDir, withIntermediateDirectories: true)

        let played = loadPlayedFilenames()
        let limited = episodeLimit > 0 ? Array(episodes.prefix(episodeLimit)) : episodes

        log("  \(limited.count) episode(s) to check")

        for ep in limited {
            let destPath = (showDir as NSString).appendingPathComponent(ep.filename)
            if FileManager.default.fileExists(atPath: destPath) {
                log("  [skip] \(ep.filename)")
                continue
            }
            if played.contains(ep.filename) {
                log("  [skip] \(ep.filename)  (previously played)")
                continue
            }

            log("  [down] \(ep.title)")
            do {
                try await downloadFile(from: ep.audioURL, to: URL(fileURLWithPath: destPath))
            } catch {
                log("  ERROR: \(error.localizedDescription)", isError: true)
                try? FileManager.default.removeItem(atPath: destPath)
            }
        }
    }

    // MARK: - Feed Resolution

    private func resolveFeed(appleURL: String) async throws -> (String, String) {
        guard let range = appleURL.range(of: #"/id(\d+)"#, options: .regularExpression) else {
            throw PodcastError.invalidURL(appleURL)
        }
        let podcastID = String(appleURL[range].dropFirst(3))

        let url = URL(string: "https://itunes.apple.com/lookup?id=\(podcastID)&entity=podcast")!
        let (data, _) = try await session.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first = results.first,
            let feedURL = first["feedUrl"] as? String
        else {
            throw PodcastError.feedResolutionFailed(appleURL)
        }
        let trackName = first["trackName"] as? String ?? "podcast-\(podcastID)"

        return (trackName, feedURL)
    }

    // MARK: - Feed Info

    func fetchFeedInfo(appleURL: String) async throws -> FeedInfo {
        guard let range = appleURL.range(of: #"/id(\d+)"#, options: .regularExpression) else {
            throw PodcastError.invalidURL(appleURL)
        }
        let podcastID = String(appleURL[range].dropFirst(3))

        let url = URL(string: "https://itunes.apple.com/lookup?id=\(podcastID)&entity=podcast")!
        let (data, _) = try await session.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first = results.first
        else {
            throw PodcastError.feedResolutionFailed(appleURL)
        }

        return FeedInfo(
            appleURL: appleURL,
            collectionName: first["collectionName"] as? String ?? "",
            primaryGenreName: first["primaryGenreName"] as? String ?? "",
            artworkURL: (first["artworkUrl100"] as? String).flatMap(URL.init(string:))
        )
    }

    // MARK: - RSS

    private func fetchAndParseEpisodes(feedURL: String) async throws -> [Episode] {
        let url = URL(string: feedURL)!
        let (data, _) = try await session.data(from: url)
        return RSSParser.parse(data: data)
    }

    // MARK: - Download

    private func downloadFile(from url: URL, to destination: URL) async throws {
        let (tempURL, _) = try await session.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    // MARK: - Played Filenames

    private func loadPlayedFilenames() -> Set<String> {
        let logPath = (iPodMountPoint as NSString)
            .appendingPathComponent(".rockbox/playback.log")
        guard let content = try? String(
            contentsOf: URL(fileURLWithPath: logPath), encoding: .utf8)
        else { return [] }

        var played: Set<String> = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 3)
            if parts.count == 4 {
                played.insert(
                    (String(parts[3]) as NSString).lastPathComponent)
            }
        }
        return played
    }

    // MARK: - Cleanup

    func removePlayedPodcasts() async {
        guard !isBusy else { return }
        isCleaning = true
        defer { isCleaning = false }
        logMessages.removeAll()

        log("Reading Rockbox database at \(iPodMountPoint)...")

        do {
            let files = try PlaybackLog.findFullyListened(mountPoint: iPodMountPoint)

            if files.isEmpty {
                log("No fully-listened podcast files found.")
                return
            }

            log("Found \(files.count) fully-listened file(s):\n")
            for file in files {
                log("  \(file)")
            }

            var deleted = 0
            for file in files {
                do {
                    try FileManager.default.removeItem(atPath: file)
                    log("  Deleted: \(file)")
                    deleted += 1
                } catch {
                    log("  ERROR deleting \(file): \(error.localizedDescription)", isError: true)
                }
            }

            log("\nDone. \(deleted) file(s) deleted.")
        } catch {
            log("ERROR: \(error.localizedDescription)", isError: true)
        }
        scanPodcastFiles()
    }

    // MARK: - Eject

    func ejectIPod() {
        let url = URL(fileURLWithPath: iPodMountPoint)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            log("Ejected \(iPodMountPoint)")
            podcastShows = []
        } catch {
            log("ERROR ejecting: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - File Scanning

    func scanPodcastFiles() {
        let fm = FileManager.default
        guard let showDirs = try? fm.contentsOfDirectory(atPath: podcastsDirectory) else {
            podcastShows = []
            return
        }

        let played = loadPlayedFilenames()
        var result: [PodcastShow] = []
        for show in showDirs.sorted() {
            let showPath = (podcastsDirectory as NSString).appendingPathComponent(show)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: showPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let files = try? fm.contentsOfDirectory(atPath: showPath) else { continue }
            let audioFiles = files.filter { !$0.hasPrefix(".") }.sorted().map { filename in
                PodcastFile(filename: filename, played: played.contains(filename))
            }
            if !audioFiles.isEmpty {
                result.append(
                    PodcastShow(
                        name: show,
                        artworkURL: artworkByShowName[show],
                        files: audioFiles))
            }
        }

        podcastShows = result
    }

    func loadFeedMetadata() async {
        var map: [String: URL] = [:]
        for feed in feeds {
            guard let info = try? await fetchFeedInfo(appleURL: feed),
                let url = info.artworkURL
            else { continue }
            map[Self.sanitizeFilename(info.collectionName)] = url
        }
        artworkByShowName = map
        scanPodcastFiles()
    }

    func togglePlayed(show: PodcastShow, file: PodcastFile) {
        if file.played {
            removeFromPlaybackLog(filename: file.filename)
        } else {
            let path = "/Podcasts/\(show.name)/\(file.filename)"
            appendToPlaybackLog(path: path)
        }
        scanPodcastFiles()
    }

    private func appendToPlaybackLog(path: String) {
        let logPath = (iPodMountPoint as NSString)
            .appendingPathComponent(".rockbox/playback.log")
        let timestamp = Int(Date().timeIntervalSince1970)
        let line = "\(timestamp):1000:1000:\(path)\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(
                to: URL(fileURLWithPath: logPath), atomically: true, encoding: .utf8)
        }
    }

    private func removeFromPlaybackLog(filename: String) {
        let logPath = (iPodMountPoint as NSString)
            .appendingPathComponent(".rockbox/playback.log")
        guard let content = try? String(
            contentsOf: URL(fileURLWithPath: logPath), encoding: .utf8)
        else { return }

        let filtered = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return true }
            let parts = trimmed.split(separator: ":", maxSplits: 3)
            guard parts.count == 4 else { return true }
            return (String(parts[3]) as NSString).lastPathComponent != filename
        }

        try? filtered.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: logPath), atomically: true, encoding: .utf8)
    }

    // MARK: - Utilities

    static func sanitizeFilename(_ name: String) -> String {
        var result = name.replacingOccurrences(
            of: "[^\\w\\s\\-.]", with: "", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        result = result.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
        return String(result.prefix(200))
    }
}

enum PodcastError: LocalizedError {
    case invalidURL(String)
    case feedResolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid Apple Podcasts URL: \(url)"
        case .feedResolutionFailed(let url): "Could not resolve feed: \(url)"
        }
    }
}

// MARK: - RSS Parser

final class RSSParser: NSObject, XMLParserDelegate {
    private var episodes: [Episode] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentPubDate = ""
    private var currentEnclosureURL: String?
    private var insideItem = false

    static func parse(data: Data) -> [Episode] {
        let rssParser = RSSParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = rssParser
        xmlParser.parse()
        return rssParser.episodes
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentPubDate = ""
            currentEnclosureURL = nil
        } else if elementName == "enclosure", insideItem {
            currentEnclosureURL = attributeDict["url"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "pubDate": currentPubDate += string
        default: break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        guard elementName == "item" else { return }
        insideItem = false

        guard let urlString = currentEnclosureURL,
            let url = URL(string: urlString)
        else { return }

        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "untitled" : title
        let dateStr = Self.parsePubDate(
            currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))

        let urlPath = urlString.components(separatedBy: "?").first ?? urlString
        let ext = (urlPath as NSString).pathExtension
        let fileExt = ext.isEmpty ? "mp3" : ext
        let sanitized = PodcastManager.sanitizeFilename(displayTitle)

        let filename: String
        if let date = dateStr {
            filename = "\(date)_\(sanitized).\(fileExt)"
        } else {
            filename = "\(sanitized).\(fileExt)"
        }

        episodes.append(
            Episode(title: displayTitle, audioURL: url, filename: filename, pubDate: dateStr ?? "")
        )
    }

    private static func parsePubDate(_ string: String) -> String? {
        guard !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        guard let date = formatter.date(from: string) else { return nil }
        let output = DateFormatter()
        output.dateFormat = "yyyyMMdd"
        return output.string(from: date)
    }
}
