import SwiftUI
import UniformTypeIdentifiers

struct HostDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.textScale) private var scale
    @State private var isPresentingImporter = false
    @State private var isPresentingTestHelp = false
    @State private var isConfirmingSampleReplace = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                audioSection
                divider
                settingsSection
                divider
                routingSection
            }
        }
        .overlay(alignment: .top) {
            progressBar
        }
        .fileImporter(isPresented: $isPresentingImporter,
                      allowedContentTypes: [.audio, .wav, .mpeg4Audio]) { result in
            switch result {
            case .success(let url):
                Task { await appModel.importAudioFile(from: url) }
            case .failure(let error):
                appModel.hostState.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $isPresentingTestHelp) {
            testFileHelpSheet
        }
        .confirmationDialog("Replace loaded audio?", isPresented: $isConfirmingSampleReplace, titleVisibility: .visible) {
            Button("Replace Audio", role: .destructive) {
                isPresentingTestHelp = false
                Task { await appModel.loadBundledSample() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace the audio file currently loaded on the host.")
        }
    }

    // MARK: - Sections

    private var progressBar: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 1)
            .scaleEffect(x: appModel.hostState.streamProgress, y: 1, anchor: .leading)
            .opacity(appModel.hostState.isStreaming ? 1 : 0)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appModel.hostState.decodedAsset?.sourceName ?? "no file")
                        .font(.system(size: 13 * scale, design: .monospaced))
                        .foregroundStyle(appModel.hostState.decodedAsset == nil ? Color.primary.opacity(0.25) : Color.primary)
                    if let asset = appModel.hostState.decodedAsset {
                        Text("\(Int(asset.sampleRate)) Hz")
                            .font(.system(size: 11 * scale, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                    if appModel.hostState.isLoadingAsset {
                        Text("loading...")
                            .font(.system(size: 11 * scale, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                }
                Spacer()
                if let error = appModel.hostState.lastError {
                    Text(error)
                        .font(.system(size: 10 * scale, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }

            HStack(spacing: 0) {
                monoBtn(appModel.hostState.isLoadingAsset ? "LOADING" : "IMPORT",
                        disabled: appModel.hostState.isLoadingAsset) {
                    isPresentingImporter = true
                }
                infoBtn { isPresentingTestHelp = true }
                Spacer()
                let isStreaming = appModel.hostState.isStreaming
                let canStart = appModel.hostState.decodedAsset != nil &&
                    !appModel.discoveryService.assignments.isEmpty &&
                    !appModel.hostState.isLoadingAsset
                monoBtn(isStreaming ? "STOP" : "START",
                        primary: true,
                        disabled: !isStreaming && !canStart) {
                    if isStreaming {
                        appModel.stopStreaming()
                    } else {
                        appModel.startStreaming()
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ForEach(PayloadFormat.allCases) { format in
                    Button(shortName(format)) {
                        appModel.hostState.payloadFormat = format
                    }
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .foregroundStyle(appModel.hostState.payloadFormat == format ? Color.primary : Color.primary.opacity(0.25))
                    .buttonStyle(.plain)
                    .disabled(appModel.hostState.isStreaming)
                }
                Spacer()
                Text("\(Int(appModel.hostState.targetLatencyMS.rounded())) ms")
                    .font(.system(size: 11 * scale, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            Slider(value: latencyBinding, in: 180...600, step: 20)
                .tint(Color.primary)
                .disabled(appModel.hostState.isStreaming)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
    }

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appModel.discoveryService.discoveredClients.isEmpty {
                Text("no devices")
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
            } else {
                ForEach(ChannelID.allCases) { channel in
                    channelRow(for: channel)
                }
            }
        }
    }

    private func channelRow(for channel: ChannelID) -> some View {
        HStack(spacing: 10) {
            Text(shortName(channel))
                .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(width: 22 * scale, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    assignChip("NONE", selected: appModel.discoveryService.assignments[channel] == nil) {
                        appModel.setAssignment(for: channel, clientID: nil)
                    }
                    ForEach(appModel.discoveryService.discoveredClients) { client in
                        assignChip(client.name.uppercased(),
                                   selected: appModel.discoveryService.assignments[channel] == client.id) {
                            let isSelected = appModel.discoveryService.assignments[channel] == client.id
                            appModel.setAssignment(for: channel, clientID: isSelected ? nil : client.id)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func shortName(_ format: PayloadFormat) -> String {
        switch format {
        case .pcm16: return "PCM16"
        case .muLaw8: return "MULAW8"
        }
    }

    private func shortName(_ channel: ChannelID) -> String {
        switch channel {
        case .frontLeft: return "FL"
        case .frontRight: return "FR"
        case .rearLeft: return "RL"
        case .rearRight: return "RR"
        }
    }

    private var latencyBinding: Binding<Double> {
        Binding {
            appModel.hostState.targetLatencyMS
        } set: {
            appModel.hostState.targetLatencyMS = $0
        }
    }

    private func monoBtn(_ title: String, primary: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11 * scale, weight: primary ? .semibold : .regular, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(disabled ? Color.primary.opacity(0.15) : (primary ? Color.primary : Color.primary.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func infoBtn(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 13 * scale, weight: .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(Color.primary.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

    private func assignChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Color.primary : Color.clear)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.4))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(selected ? 0 : 0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Test Help Sheet

    private var testFileHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("8s QS test file. One channel active at a time.")
                        .font(.system(size: 13 * scale, design: .monospaced))
                        .foregroundStyle(Color.primary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("0–2s  FL")
                        Text("2–4s  FR")
                        Text("4–6s  RL")
                        Text("6–8s  RR")
                    }
                    .font(.system(size: 13 * scale, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.45))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Tap USE SAMPLE below")
                        Text("2. Open Quadio on client devices")
                        Text("3. Assign one channel per device")
                        Text("4. Tap START and each device plays its 2s window")
                    }
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.35))

                    Button("USE SAMPLE") {
                        if appModel.hostState.decodedAsset == nil {
                            isPresentingTestHelp = false
                            Task { await appModel.loadBundledSample() }
                        } else {
                            isConfirmingSampleReplace = true
                        }
                    }
                    .font(.system(size: 12 * scale, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(appModel.hostState.isLoadingAsset)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("INFO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { isPresentingTestHelp = false }
                        .font(.system(size: 12 * scale, design: .monospaced))
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
