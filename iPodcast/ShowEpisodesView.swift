import SwiftUI

struct ShowEpisodesView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: PodcastManager
    let show: PodcastShow

    @State private var episodes: [Episode] = []
    @State private var downloadedFilenames: Set<String> = []
    @State private var playedFilenames: Set<String> = []
    @State private var downloadingFilenames: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(show.name)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if let message = errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            List(episodes) { episode in
                HStack(spacing: 10) {
                    statusIcon(for: episode)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.body)
                            .lineLimit(2)
                        if !episode.pubDate.isEmpty {
                            Text(episode.pubDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    actionButton(for: episode)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 480)
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func statusIcon(for episode: Episode) -> some View {
        if downloadedFilenames.contains(episode.filename) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.green)
        } else if playedFilenames.contains(episode.filename) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actionButton(for episode: Episode) -> some View {
        if downloadedFilenames.contains(episode.filename) {
            Text("Downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if downloadingFilenames.contains(episode.filename) {
            ProgressView().controlSize(.small)
        } else {
            Button("Download") {
                Task { await download(episode) }
            }
            .controlSize(.small)
        }
    }

    private func load() async {
        guard let appleURL = show.appleURL else {
            errorMessage = "No feed URL for this show."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await manager.fetchEpisodes(appleURL: appleURL)
            episodes = result
            refreshLocalState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLocalState() {
        downloadedFilenames = Set(show.files.map { $0.filename })
        playedFilenames = manager.loadPlayedFilenames()
    }

    private func download(_ episode: Episode) async {
        downloadingFilenames.insert(episode.filename)
        defer { downloadingFilenames.remove(episode.filename) }

        do {
            try await manager.downloadEpisode(episode, showName: show.name)
            downloadedFilenames.insert(episode.filename)
            manager.scanPodcastFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
