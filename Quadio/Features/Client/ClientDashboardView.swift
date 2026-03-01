import SwiftUI

struct ClientDashboardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This Device")
                    .font(.headline)
                Text(deviceStateText)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text("Channel")
                    .font(.headline)
                Text(appModel.clientState.assignedChannel?.displayName ?? "Waiting")
                    .font(.title3.weight(.semibold))
                Text(syncStateText)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text("Connection")
                    .font(.headline)
                Text(connectionStateText)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var deviceStateText: String {
        appModel.clientState.assignedChannel == nil ? "Ready to receive audio." : "Playing assigned audio."
    }

    private var syncStateText: String {
        appModel.clientState.assignedChannel == nil ? "Waiting for a stream." : "Synced and buffered."
    }

    private var connectionStateText: String {
        let summary = appModel.transport.healthSummary.lowercased()

        if summary.contains("failed") || summary.contains("error") {
            return appModel.clientState.assignedChannel == nil ? "Waiting for host." : "Connection problem."
        }

        if summary.contains("received") {
            return "Connected."
        }

        if summary.contains("stopped") {
            return "Offline."
        }

        if summary.contains("listener") {
            return "Ready."
        }

        return "Waiting for host."
    }
}

#Preview {
    ClientDashboardView()
        .environment(AppModel())
}
