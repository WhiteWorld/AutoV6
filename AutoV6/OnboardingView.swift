import SwiftUI
import CoreLocation

struct OnboardingView: View {

    @Environment(LocationManager.self) private var locationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("初始化 AutoV6")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(locationManager.isAuthorized ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                    if locationManager.isAuthorized {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("1")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("位置服务权限").font(.subheadline.bold())
                    Text("读取 Wi-Fi 名称（SSID）所需")
                        .font(.caption).foregroundStyle(.secondary)
                    switch locationManager.authorizationStatus {
                    case .notDetermined:
                        Button("授权") { locationManager.requestPermission() }
                            .controlSize(.small)
                    case .denied, .restricted:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已被拒绝，请在系统设置中手动开启")
                                .font(.caption).foregroundStyle(.red)
                            Button("打开系统设置") { locationManager.openSystemSettings() }
                                .controlSize(.small)
                        }
                    default:
                        EmptyView()
                    }
                }
                Spacer()
            }
        }
        .padding()
        .frame(width: 280)
    }
}
