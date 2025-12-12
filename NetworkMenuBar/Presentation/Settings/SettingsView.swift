import SwiftUI
import ServiceManagement

/// 設定画面
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var launchAtLogin: Bool = false
    @State private var showSpeedInMenuBar: Bool = false
    @State private var refreshInterval: Double = 2.0
    @State private var showIPv6: Bool = false
    @State private var autoFillGateway: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("設定")
                    .font(.headline)
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            TabView {
                generalSettingsTab
                    .tabItem {
                        Label("一般", systemImage: "gearshape")
                    }

                displaySettingsTab
                    .tabItem {
                        Label("表示", systemImage: "eye")
                    }

                aboutTab
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
        }
        .frame(width: 450, height: 350)
        .onAppear {
            loadSettings()
        }
    }

    /// 一般設定タブ
    private var generalSettingsTab: some View {
        Form {
            Section {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Picker("更新間隔", selection: $refreshInterval) {
                    Text("1秒").tag(1.0)
                    Text("2秒").tag(2.0)
                    Text("5秒").tag(5.0)
                    Text("10秒").tag(10.0)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    appState.settings.refreshInterval = newValue
                    appState.saveSettings()
                }
            }

            Section("IP設定") {
                Toggle("デフォルトゲートウェイを自動補完", isOn: $autoFillGateway)
                    .onChange(of: autoFillGateway) { _, newValue in
                        appState.settings.autoFillGateway = newValue
                        appState.saveSettings()
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// 表示設定タブ
    private var displaySettingsTab: some View {
        Form {
            Section {
                Toggle("メニューバーに通信速度を表示", isOn: $showSpeedInMenuBar)
                    .onChange(of: showSpeedInMenuBar) { _, newValue in
                        appState.settings.showSpeedInMenuBar = newValue
                        appState.saveSettings()
                    }

                Toggle("IPv6情報を表示", isOn: $showIPv6)
                    .onChange(of: showIPv6) { _, newValue in
                        appState.settings.showIPv6 = newValue
                        appState.saveSettings()
                    }

                Picker("速度表示単位", selection: $appState.settings.speedUnit) {
                    ForEach(SpeedUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// このアプリについてタブ
    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("NetworkTweak")
                .font(.title)
                .fontWeight(.bold)

            Text("v1.0.0 (たぶん安定版)")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("DHCPと固定IPを行ったり来たりする人が")
                Text("ちょっと楽になったり、ならなかったりするアプリ")
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            Spacer()

            VStack(spacing: 4) {
                Text("- 豆知識 -")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("このアプリを使っても")
                Text("ネットワークの問題は解決しないかもしれません。")
                Text("でも、設定画面を開く手間は省けます。たぶん。")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("お疲れ様でした", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    /// 設定を読み込み
    private func loadSettings() {
        launchAtLogin = appState.settings.launchAtLogin
        showSpeedInMenuBar = appState.settings.showSpeedInMenuBar
        refreshInterval = appState.settings.refreshInterval
        showIPv6 = appState.settings.showIPv6
        autoFillGateway = appState.settings.autoFillGateway
    }

    /// ログイン時起動を設定
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appState.settings.launchAtLogin = enabled
            appState.saveSettings()
        } catch {
            print("ログイン時起動の設定に失敗: \(error)")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
