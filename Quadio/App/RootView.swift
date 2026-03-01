import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                rolePicker

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
            .padding(20)
            .navigationTitle("Quadio")
            .task {
                appModel.start()
            }
            .onChange(of: appModel.selectedRole) { _, _ in
                appModel.stop()
                appModel.start()
            }
            .onDisappear {
                appModel.stop()
            }
        }
    }

    private var rolePicker: some View {
        Picker("Role", selection: Bindable(appModel).selectedRole) {
            ForEach(AppRole.allCases) { role in
                Text(role.title).tag(role)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("role-picker")
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
