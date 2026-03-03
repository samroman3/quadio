import SwiftUI

struct ClientDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(appModel.clientState.assignedChannel?.displayName.uppercased() ?? "WAITING")
                .font(.system(size: 24 * scale, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.primary)
            Text(connectionStateText)
                .font(.system(size: 11 * scale, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionStateText: String {
        let summary = appModel.transport.healthSummary.lowercased()
        if summary.contains("failed") || summary.contains("error") {
            return appModel.clientState.assignedChannel == nil ? "waiting for host" : "connection problem"
        }
        if summary.contains("received") { return "connected" }
        if summary.contains("stopped") { return "offline" }
        if summary.contains("listener") { return "ready" }
        return "waiting for host"
    }
}

#Preview {
    ClientDashboardView()
        .environment(AppModel())
}
