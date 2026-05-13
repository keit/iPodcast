import SwiftUI

struct ManageFeedsView: View {
    @Environment(\.dismiss) private var dismiss
    let manager: PodcastManager
    @State private var feedInfos: [String: FeedInfo] = [:]
    @State private var loadingErrors: [String: String] = [:]
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Manage Feeds")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            List(manager.feeds, id: \.self) { feed in
                HStack(spacing: 10) {
                    AsyncImage(url: feedInfos[feed]?.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        case .empty:
                            Color.gray.opacity(0.2)
                        @unknown default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        if let info = feedInfos[feed] {
                            Text(info.collectionName)
                                .font(.body)
                            Text(info.primaryGenreName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let error = loadingErrors[feed] {
                            Text(feed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(feed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await loadAll()
        }
    }

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        for feed in manager.feeds {
            do {
                let info = try await manager.fetchFeedInfo(appleURL: feed)
                feedInfos[feed] = info
            } catch {
                loadingErrors[feed] = error.localizedDescription
            }
        }
    }
}
