import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("textScale") private var storedScale: Double = 1.5
    @AppStorage("colorScheme") private var storedColorScheme: String = "system"
    @State private var isPresentingSettings = false
    @State private var isPresentingOnboarding = false
    @State private var isConfirmingClientSwitch = false
    @State private var pendingRoleSwitch: AppRole?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
            Group {
                switch appModel.selectedRole {
                case .host:
                    HostDashboardView()
                case .client:
                    ClientDashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .environment(\.textScale, storedScale)
        .preferredColorScheme(resolvedColorScheme)
        .task { appModel.start() }
        .onAppear {
            if hasSeenOnboarding == false {
                isPresentingOnboarding = true
            }
        }
        .onChange(of: appModel.selectedRole) { _, _ in
            appModel.stop()
            appModel.start()
        }
        .onDisappear { appModel.stop() }
        .fullScreenCover(isPresented: $isPresentingOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                isPresentingOnboarding = false
            }
            .environment(\.textScale, storedScale)
        }
        .confirmationDialog("Switch to client?", isPresented: $isConfirmingClientSwitch, titleVisibility: .visible) {
            Button("Switch to Client", role: .destructive) {
                if let pendingRoleSwitch {
                    appModel.selectedRole = pendingRoleSwitch
                }
                pendingRoleSwitch = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRoleSwitch = nil
            }
        } message: {
            Text("This will stop the current host session and disconnect any active channel routing.")
        }
        .sheet(isPresented: $isPresentingSettings, onDismiss: {
            if appModel.selectedRole == .client {
                appModel.stop()
                appModel.start()
            }
        }) {
            SettingsView()
                .environment(\.textScale, storedScale)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch storedColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var header: some View {
        HStack {
            Button {
                isPresentingSettings = true
            } label: {
                Text("QUADIO")
                    .font(.system(size: 11 * storedScale, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 20) {
                ForEach(AppRole.allCases) { role in
                    Button(role.title.uppercased()) {
                        handleRoleSelection(role)
                    }
                    .font(.system(size: 11 * storedScale, weight: .regular, design: .monospaced))
                    .foregroundStyle(appModel.selectedRole == role ? Color.primary : Color.primary.opacity(0.25))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hasActiveHostSession: Bool {
        appModel.selectedRole == .host && (
            appModel.hostState.isStreaming ||
            appModel.hostState.isLoadingAsset ||
            appModel.hostState.decodedAsset != nil ||
            !appModel.discoveryService.assignments.isEmpty
        )
    }

    private func handleRoleSelection(_ role: AppRole) {
        guard role != appModel.selectedRole else { return }

        if role == .client && hasActiveHostSession {
            pendingRoleSwitch = role
            isConfirmingClientSwitch = true
            return
        }

        appModel.selectedRole = role
    }
}

// MARK: - Onboarding

private struct OnboardingView: View {
    let dismiss: () -> Void

    @Environment(\.textScale) private var envScale

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                Image("quadio")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("QUADIO decodes QS Regular Matrix stereo into four discrete playback channels.")
                    Text("Use it to route Front Left, Front Right, Rear Left, and Rear Right across nearby iPhones on the same Wi-Fi network.")
                }
                .font(.system(size: 14 * envScale, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.primary)

                VStack(alignment: .leading, spacing: 14) {
                    onboardingStep(title: "HOST", description: "Load a QS-encoded stereo source, decode it, discover nearby devices, and assign each channel.")
                    onboardingStep(title: "CLIENT", description: "Join from other iPhones on the same Wi-Fi network and receive the channel the host sends you.")
                    onboardingStep(title: "TEST", description: "Use the built-in sample on the host for a quick end-to-end routing check.")
                }

                Spacer()

                Button("CONTINUE") {
                    dismiss()
                }
                .font(.system(size: 12 * envScale, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }

    private func onboardingStep(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9 * envScale, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.35))
            Text(description)
                .font(.system(size: 11 * envScale, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.75))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Settings

private struct SettingsView: View {
    private let secondThumbURL = URL(string: "https://secondthumb.com")!
    @AppStorage("textScale") private var scale: Double = 1.5
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    @AppStorage("deviceName") private var deviceName: String = ""
    @Environment(\.textScale) private var envScale
    @Environment(\.openURL) private var openURL
    @State private var isPresentingSecondThumbPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appearanceSection
                deviceNameSection
                textSizeSection
                footer
            }
            .padding(24)
        }
        .alert("Open secondthumb.com?", isPresented: $isPresentingSecondThumbPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Open Website") {
                openURL(secondThumbURL)
            }
        } message: {
            Text("This will open the Second Thumb website in your browser.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("APPEARANCE")
            HStack(spacing: 8) {
                ForEach([("SYSTEM", "system"), ("LIGHT", "light"), ("DARK", "dark")], id: \.0) { title, value in
                    chip(title, selected: colorScheme == value) { colorScheme = value }
                }
            }
        }
    }

    // MARK: Device Name

    private var deviceNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("DEVICE NAME")
            TextField(ProcessInfo.processInfo.hostName, text: $deviceName)
                .font(.system(size: 11 * envScale, design: .monospaced))
                .foregroundStyle(Color.primary)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 1)
                }
                .submitLabel(.done)
        }
    }

    // MARK: Text Size

    private var textSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("TEXT SIZE")
            HStack(spacing: 8) {
                ForEach([("S", 1.0), ("M", 1.5), ("L", 2.0)], id: \.0) { title, value in
                    chip(title, selected: scale == value) { scale = value }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image("quadio")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.tertiary)
                    .frame(height: 18)
                Text("v\(Bundle.main.releaseVersionNumber ?? "0.1")")
                    .font(.system(size: 11 * envScale, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            Button {
                isPresentingSecondThumbPrompt = true
            } label: {
                Image(.secondthumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.tertiary)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10 * envScale, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title) { action() }
            .font(.system(size: 11 * envScale, weight: .medium, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(selected ? Color.primary : Color.clear)
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.4))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(selected ? 0 : 0.18), lineWidth: 1))
            .buttonStyle(.plain)
    }
}

// MARK: - Bundle helpers

private extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
