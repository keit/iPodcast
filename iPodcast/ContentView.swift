import SwiftUI

private let windowBackground = Color(red: 235 / 255, green: 235 / 255, blue: 235 / 255)
private let panelBackground = Color(red: 222 / 255, green: 222 / 255, blue: 222 / 255)

struct PanelGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
                .font(.headline)
            configuration.content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.gray.opacity(0.25))
                )
        }
    }
}

struct ContentView: View {
    @State private var manager = PodcastManager()
    @State private var showingManageFeeds = false
    @State private var showingMoreFor: PodcastShow?

    var body: some View {
        VStack(spacing: 12) {
            GroupBox("Device") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("iPod Mount") {
                        TextField("", text: $manager.iPodMountPoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Episode Limit") {
                        TextField("", value: $manager.episodeLimit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
            }

            GroupBox("Actions") {
                HStack(spacing: 12) {
                    Button("Sync New Podcasts") {
                        Task { await manager.syncNewPodcasts() }
                    }
                    .disabled(manager.isBusy)

                    Button("Remove Played") {
                        Task { await manager.removePlayedPodcasts() }
                    }
                    .disabled(manager.isBusy)

                    Button("Eject iPod") {
                        manager.ejectIPod()
                    }
                    .disabled(manager.isBusy)

                    Button("Manage Feeds") {
                        showingManageFeeds = true
                    }
                    .disabled(manager.isBusy)

                    if manager.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
            }

            GroupBox("Podcasts") {
                List {
                    ForEach(manager.podcastShows) { show in
                        Section {
                            if show.files.isEmpty {
                                Text("No episodes")
                                    .font(.system(size: 12))
                                    .italic()
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(show.files) { file in
                                    Button {
                                        manager.togglePlayed(show: show, file: file)
                                    } label: {
                                        HStack {
                                            Image(
                                                systemName: file.played
                                                    ? "checkmark.circle.fill" : "circle"
                                            )
                                            .foregroundStyle(file.played ? .green : .secondary)
                                            Text(file.filename)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            HStack(spacing: 8) {
                                AsyncImage(url: show.artworkURL) { phase in
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
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(show.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if show.appleURL != nil {
                                    Button {
                                        showingMoreFor = show
                                    } label: {
                                        Text("More…")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                            .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if manager.podcastShows.isEmpty {
                        ContentUnavailableView(
                            "No Podcasts",
                            systemImage: "headphones",
                            description: Text("Sync to download episodes")
                        )
                    }
                }
            }

            GroupBox("Log") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(manager.logMessages) { entry in
                                Text(entry.message)
                                    .foregroundStyle(entry.isError ? .red : .primary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .id(entry.id)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .onChange(of: manager.logMessages.count) {
                        if let last = manager.logMessages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .groupBoxStyle(PanelGroupBoxStyle())
        .padding()
        .frame(minWidth: 600, minHeight: 600)
        .background(windowBackground)
        .preferredColorScheme(.light)
        .onAppear {
            manager.scanPodcastFiles()
        }
        .task {
            await manager.loadFeedMetadata()
        }
        .sheet(isPresented: $showingManageFeeds) {
            ManageFeedsView(manager: manager)
        }
        .sheet(item: $showingMoreFor) { show in
            ShowEpisodesView(manager: manager, show: show)
        }
    }
}

#Preview {
    ContentView()
}
