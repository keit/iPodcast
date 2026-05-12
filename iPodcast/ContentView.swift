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
                        Section(show.name) {
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
    }
}

#Preview {
    ContentView()
}
