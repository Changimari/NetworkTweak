import SwiftUI
import ServiceManagement

/// 設定画面
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updateChecker = UpdateChecker.shared
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
            .padding(.top, 10)
        }
        .frame(width: 400, height: 450)
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
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 36))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("NetworkTweak")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("v\(updateChecker.currentVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("DHCPと固定IPを行ったり来たりする人が\nちょっと楽になったり、ならなかったりするアプリ")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Divider().padding(.horizontal, 40)

                // アップデートセクション
                updateSection

                Divider().padding(.horizontal, 40)

                VStack(spacing: 2) {
                    Text("- 豆知識 -")
                        .font(.caption2)
                        .fontWeight(.medium)
                    Text("このアプリを使っても\nネットワークの問題は解決しないかもしれません。\nでも、設定画面を開く手間は省けます。たぶん。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    Button {
                        updateChecker.openRepositoryPage()
                    } label: {
                        Label("GitHub", systemImage: "link")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        exit(0)
                    } label: {
                        Label("お疲れ様でした", systemImage: "power")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    /// アップデートセクション
    private var updateSection: some View {
        VStack(spacing: 8) {
            if updateChecker.isChecking {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("アップデートを確認中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let updateInfo = updateChecker.updateInfo {
                if updateInfo.isUpdateAvailable {
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                            Text("新しいバージョンがあります!")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Text("v\(updateInfo.currentVersion) → v\(updateInfo.latestVersion)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button {
                            updateChecker.openDownloadPage()
                        } label: {
                            Label("ダウンロード", systemImage: "arrow.down.to.line")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("最新バージョンです")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let error = updateChecker.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task {
                    await updateChecker.checkForUpdates()
                }
            } label: {
                Label("アップデートを確認", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(updateChecker.isChecking)

            if let lastCheck = updateChecker.lastCheckDate {
                Text("最終確認: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
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
