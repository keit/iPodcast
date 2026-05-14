import SwiftUI

struct ManageFeedsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    let manager: PodcastManager
    @State private var feedInfos: [String: FeedInfo] = [:]
    @State private var loadingErrors: [String: String] = [:]
    @State private var isLoading = false
    @State private var selection: Set<String> = []
    @State private var showingAddSheet = false

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

            List(selection: $selection) {
                ForEach(manager.feeds, id: \.self) { feed in
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
                    .tag(feed)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            remove([feed])
                        }
                    }
                }
            }
            .onDeleteCommand { remove(selection) }
            .onExitCommand { selection.removeAll() }

            HStack(spacing: 4) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .help("Add feed")

                Button {
                    remove(selection)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .disabled(selection.isEmpty)
                .help("Remove selected feed")

                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await loadAll()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddFeedSheet { url in
                addFeed(url)
            }
        }
    }

    private func addFeed(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !manager.feeds.contains(trimmed) else { return }

        manager.setFeeds(manager.feeds + [trimmed], undoManager: undoManager)
        undoManager?.setActionName("Add Feed")

        Task {
            do {
                let info = try await manager.fetchFeedInfo(appleURL: trimmed)
                feedInfos[trimmed] = info
            } catch {
                loadingErrors[trimmed] = error.localizedDescription
            }
        }
    }

    private func remove(_ feedsToRemove: Set<String>) {
        guard !feedsToRemove.isEmpty else { return }
        let newFeeds = manager.feeds.filter { !feedsToRemove.contains($0) }
        manager.setFeeds(newFeeds, undoManager: undoManager)
        selection.subtract(feedsToRemove)
        undoManager?.setActionName(feedsToRemove.count == 1 ? "Remove Feed" : "Remove Feeds")
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

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    let onAdd: (String) -> Void

    private var isValid: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"/id\d+"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Feed")
                .font(.headline)
            Text("Paste an Apple Podcasts URL (must contain /idXXXX).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("https://podcasts.apple.com/…", text: $url)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(url)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

