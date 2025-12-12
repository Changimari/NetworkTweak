import SwiftUI

@main
struct NetworkMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メニューバーアプリなのでWindowは使わない
        Settings {
            if let appState = appDelegate.appState {
                SettingsView()
                    .environmentObject(appState)
            } else {
                Text("読み込み中...")
            }
        }
    }
}
