import SwiftUI
import UniformTypeIdentifiers

struct HostDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isPresentingImporter = false
    @State private var isPresentingTestHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                assignmentsCard
                clientsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $isPresentingImporter,
                      allowedContentTypes: [.audio, .wav, .mpeg4Audio]) { result in
            switch result {
            case .success(let url):
                Task {
                    await appModel.importAudioFile(from: url)
                }
            case .failure(let error):
                appModel.hostState.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $isPresentingTestHelp) {
            testFileHelpSheet
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio")
                .font(.headline)

            Text(appModel.hostState.decodedAsset.map { "\($0.sourceName) • \(Int($0.sampleRate)) Hz" } ?? "No file selected")
                .font(.subheadline.monospaced())

            HStack {
                Button("Use Sample") {
                    appModel.loadBundledSample()
                }
                .buttonStyle(.bordered)

                Button {
                    isPresentingTestHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Sample Info")

                Button("Import Audio") {
                    isPresentingImporter = true
                }
                .buttonStyle(.bordered)

                Button(appModel.hostState.isStreaming ? "Stop Stream" : "Start Stream") {
                    if appModel.hostState.isStreaming {
                        appModel.stopStreaming()
                    } else {
                        appModel.startStreaming()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.hostState.decodedAsset == nil || appModel.discoveryService.assignments.isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Transport Format")
                    .font(.subheadline.weight(.medium))
                Picker("Transport Format", selection: payloadFormatBinding) {
                    ForEach(PayloadFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appModel.hostState.isStreaming)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Target Network Buffer")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(appModel.hostState.targetLatencyMS.rounded())) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: targetLatencyBinding, in: 180...600, step: 20)
                    .disabled(appModel.hostState.isStreaming)

                Text("More stable on the right, lower delay on the left.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appModel.hostState.isStreaming {
                ProgressView(value: appModel.hostState.streamProgress)
            }

            if let error = appModel.hostState.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .cardStyle()
    }

    private var assignmentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Channel Routing")
                .font(.headline)

            if appModel.discoveryService.discoveredClients.isEmpty {
                Text("Open Quadio on another device to route audio.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ChannelID.allCases) { channel in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(channel.displayName)
                            Spacer()
                            Text(appModel.discoveryService.assignmentLabel(for: channel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                assignmentButton(title: "None",
                                                 isSelected: appModel.discoveryService.assignments[channel] == nil) {
                                    appModel.setAssignment(for: channel, clientID: nil)
                                }

                                ForEach(appModel.discoveryService.discoveredClients) { client in
                                    assignmentButton(title: client.name,
                                                     isSelected: appModel.discoveryService.assignments[channel] == client.id) {
                                        let isSelected = appModel.discoveryService.assignments[channel] == client.id
                                        appModel.setAssignment(for: channel, clientID: isSelected ? nil : client.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var clientsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Clients")
                .font(.headline)

            if appModel.discoveryService.discoveredClients.isEmpty {
                Text("No devices found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.discoveryService.discoveredClients) { client in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(client.name)
                            Text(appModel.discoveryService.assignedChannels(for: client)
                                .map(\.displayName)
                                .joined(separator: ", ")
                                .ifEmpty("Ready"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(clientStatusLabel(for: client))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var payloadFormatBinding: Binding<PayloadFormat> {
        Binding {
            appModel.hostState.payloadFormat
        } set: { newValue in
            appModel.hostState.payloadFormat = newValue
        }
    }

    private var targetLatencyBinding: Binding<Double> {
        Binding {
            appModel.hostState.targetLatencyMS
        } set: { newValue in
            appModel.hostState.targetLatencyMS = newValue
        }
    }

    private func assignmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func clientStatusLabel(for client: ClientDevice) -> String {
        appModel.discoveryService.assignedChannels(for: client).isEmpty ? "Available" : "Assigned"
    }

    private var testFileHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Use the built-in sample for a quick decode check.")
                        .font(.headline)

                    Text("It is an 8-second QS test file with one channel active at a time.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("0-2s: Front Left")
                        Text("2-4s: Front Right")
                        Text("4-6s: Rear Left")
                        Text("6-8s: Rear Right")
                    }
                    .font(.body.monospaced())

                    Text("Quick test")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Tap Use Sample.")
                        Text("2. Open Quadio on up to four other devices in Client mode.")
                        Text("3. Assign one decoded channel to each device.")
                        Text("4. Start the stream and confirm each device only plays during its 2-second window.")
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Test File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresentingTestHelp = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    HostDashboardView()
        .environment(AppModel())
}
