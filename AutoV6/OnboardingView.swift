import SwiftUI
import CoreLocation

struct OnboardingView: View {

    @Environment(LocationManager.self) private var locationManager
    @Environment(HelperInstaller.self) private var helperInstaller

    @State private var isInstallingHelper = false
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("初始化 AutoV6")
                .font(.headline)

            // Step 1: Location permission
            stepRow(
                number: 1,
                title: "位置服务权限",
                description: "读取 Wi-Fi 名称（SSID）所需",
                isDone: locationManager.isAuthorized
            ) {
                locationManager.requestPermission()
            }

            // Step 2: Helper installation
            stepRow(
                number: 2,
                title: "安装特权助手",
                description: "首次安装需要输入管理员密码",
                isDone: {
                    if case .installed = helperInstaller.state { return true }
                    return false
                }()
            ) {
                Task { await installHelper() }
            }

            if let error = installError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 320)
        .task {
            await helperInstaller.checkInstallation()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepRow(number: Int, title: String, description: String,
                         isDone: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 28, height: 28)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
                if !isDone {
                    Button("授权") { action() }
                        .controlSize(.small)
                        .disabled(isInstallingHelper)
                }
            }
            Spacer()
        }
    }

    private func installHelper() async {
        isInstallingHelper = true
        installError = nil
        do {
            try await helperInstaller.install()
        } catch {
            installError = error.localizedDescription
        }
        isInstallingHelper = false
    }
}
