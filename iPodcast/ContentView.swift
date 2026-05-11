import SwiftUI

struct ContentView: View {
    @State private var manager = PodcastManager()

    var body: some View {
        VStack(spacing: 0) {
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
            .padding()

            Divider()

            HStack(spacing: 12) {
                Button("Sync New Podcasts") {
                    Task { await manager.syncNewPodcasts() }
                }
                .disabled(manager.isBusy)

                Button("Remove Played") {
                    Task { await manager.removePlayedPodcasts() }
                }
                .disabled(manager.isBusy)

                if manager.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

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
                    .padding(8)
                }
                .onChange(of: manager.logMessages.count) {
                    if let last = manager.logMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
