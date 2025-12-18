import SwiftUI
import UniformTypeIdentifiers
import Carbon


/// 自動更新マネージャー
@MainActor
class AutoRefreshManager: ObservableObject {
    @Published var tick: Int = 0
    private var timer: Timer?

    func start(interval: TimeInterval) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick += 1
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

/// メインポップオーバービュー
struct MainPopoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAdapter: NetworkAdapter?
    @State private var showMemoSheet = false
    @State private var showSettings = false
    @State private var isRefreshing = false
    @State private var showEmergencyReset = false
    @State private var isResetting = false
    @StateObject private var refreshManager = AutoRefreshManager()

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView

            Divider()

            // アダプター一覧（接続中のみ）
            ScrollView {
                LazyVStack(spacing: 8) {
                    if appState.networkManager.connectedAdapters.isEmpty {
                        Text("接続中のネットワークがありません")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(appState.networkManager.connectedAdapters) { adapter in
                            AdapterRowView(adapter: adapter) {
                                selectedAdapter = adapter
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // フッター（外部IP）
            footerView
        }
        .frame(width: 320, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $selectedAdapter) { adapter in
            AdapterDetailView(adapter: adapter)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showMemoSheet) {
            IPMemoListView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .task {
            // 初回更新
            await appState.networkManager.fetchAdapters()
            await appState.networkManager.fetchExternalIP()
            // 自動更新開始
            refreshManager.start(interval: appState.settings.refreshInterval)
        }
        .onChange(of: refreshManager.tick) { _, _ in
            // タイマーが発火したら更新
            if !showMemoSheet && !showSettings && selectedAdapter == nil {
                Task {
                    await appState.networkManager.fetchAdapters()
                }
            }
        }
        .onDisappear {
            refreshManager.stop()
        }
    }

    /// ヘッダービュー
    private var headerView: some View {
        HStack {
            Text("NetworkTweak")
                .font(.headline)

            Spacer()

            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await appState.networkManager.fetchAdapters()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help("更新")

            Button {
                showMemoSheet = true
            } label: {
                Image(systemName: "note.text")
            }
            .buttonStyle(.borderless)
            .help("IPメモ")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// フッタービュー
    private var footerView: some View {
        VStack(spacing: 4) {
            if let externalIP = appState.networkManager.externalIP {
                HStack {
                    Text("外部IP:")
                        .foregroundColor(.secondary)
                    Text(externalIP)
                        .fontWeight(.medium)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(externalIP, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("コピー")
                }
                .font(.caption)
            }

            // 緊急リセットボタン
            Button {
                showEmergencyReset = true
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("緊急リセット")
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
            .buttonStyle(.borderless)
            .help("全アダプタをDHCPにリセット")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert("緊急リセット", isPresented: $showEmergencyReset) {
            Button("キャンセル", role: .cancel) {}
            Button("リセット", role: .destructive) {
                performEmergencyReset()
            }
        } message: {
            Text("接続中の全ネットワークアダプタをDHCPにリセットします。\nネット接続に問題がある場合に使用してください。")
        }
    }

    /// 緊急リセットを実行
    private func performEmergencyReset() {
        isResetting = true
        Task {
            for adapter in appState.networkManager.connectedAdapters {
                do {
                    try await appState.networkManager.emergencyResetToDHCP(serviceName: adapter.hardwarePort)
                } catch {
                    print("Emergency reset failed for \(adapter.hardwarePort): \(error)")
                }
            }
            isResetting = false
        }
    }
}

/// アダプター行ビュー
struct AdapterRowView: View {
    let adapter: NetworkAdapter
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // ステータスインジケーター
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)

                // アイコン
                Image(systemName: adapter.iconName)
                    .font(.title2)
                    .foregroundColor(.primary)

                // 情報
                VStack(alignment: .leading, spacing: 2) {
                    Text(adapter.displayName)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)

                    if let ip = adapter.ipConfiguration?.ipv4Address, !ip.isEmpty {
                        Text(ip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

/// IPメモ一覧ビュー
struct IPMemoListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showAddFolderSheet = false
    @State private var showAddMemoSheet = false
    @State private var selectedFolder: IPMemoFolder?
    @State private var editingMemo: IPMemo?
    @State private var draggedMemo: IPMemo?
    @State private var highlightedFolderID: UUID?
    @State private var segmentConnectMemo: IPMemo?

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("IPメモ")
                    .font(.headline)
                Spacer()
                Button {
                    showAddMemoSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("メモを追加")

                Button {
                    showAddFolderSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("フォルダを追加")

                Button("閉じる") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // フォルダとメモ一覧
            if appState.ipMemoStore.folders.isEmpty && appState.ipMemoStore.memos.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "note.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("メモがありません")
                        .foregroundColor(.secondary)
                    Text("＋ボタンでメモを追加")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    // フォルダ
                    ForEach(appState.ipMemoStore.folders) { folder in
                        FolderRowView(
                            folder: folder,
                            isHighlighted: highlightedFolderID == folder.id,
                            onTap: { selectedFolder = folder },
                            onDelete: { appState.ipMemoStore.deleteFolder(folder) }
                        )
                        .onDrop(of: [.plainText], delegate: FolderDropDelegate(
                            folder: folder,
                            draggedMemo: $draggedMemo,
                            highlightedFolderID: $highlightedFolderID,
                            ipMemoStore: appState.ipMemoStore
                        ))
                    }

                    // トップレベルのメモ
                    if !appState.ipMemoStore.memos.isEmpty {
                        Section("メモ") {
                            ForEach(appState.ipMemoStore.memos) { memo in
                                DraggableMemoRowView(
                                    memo: memo,
                                    draggedMemo: $draggedMemo,
                                    onTap: { editingMemo = memo },
                                    onDelete: { appState.ipMemoStore.delete(memo) },
                                    onSegmentConnect: { segmentConnectMemo = memo }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 400)
        .sheet(isPresented: $showAddFolderSheet) {
            FolderEditView(folder: nil)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showAddMemoSheet) {
            IPMemoEditView(memo: nil, folderID: nil)
                .environmentObject(appState)
        }
        .sheet(item: $selectedFolder) { folder in
            FolderDetailView(folder: folder)
                .environmentObject(appState)
        }
        .sheet(item: $editingMemo) { memo in
            IPMemoEditView(memo: memo, folderID: nil)
                .environmentObject(appState)
        }
        .sheet(item: $segmentConnectMemo) { memo in
            SegmentConnectView(targetIP: memo.ipAddress)
                .environmentObject(appState)
        }
    }
}

/// フォルダ行ビュー
struct FolderRowView: View {
    let folder: IPMemoFolder
    var isHighlighted: Bool = false
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isHighlighted ? "folder.fill.badge.plus" : "folder.fill")
                    .font(.title3)
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isHighlighted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .fontWeight(.medium)
                    Text("\(folder.memos.count)件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHighlighted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }
}

/// メモ行ビュー
struct MemoRowView: View {
    let memo: IPMemo

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(memo.name)
                    .fontWeight(.medium)
                Text(memo.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(memo.ipAddress, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("IPをコピー")
        }
    }
}

/// フォルダ詳細ビュー
struct FolderDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let folder: IPMemoFolder
    @State private var showAddMemoSheet = false
    @State private var editingMemo: IPMemo?
    @State private var showExportPanel = false
    @State private var segmentConnectMemo: IPMemo?

    // フォルダIDを保持（参照の安定性のため）
    private var folderID: UUID { folder.id }

    // 最新のメモ一覧を取得
    private var memos: [IPMemo] {
        appState.ipMemoStore.folders.first { $0.id == folderID }?.memos ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("戻る")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(folder.name)
                    .font(.headline)

                Spacer()

                Button {
                    showAddMemoSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("メモを追加")

                Button {
                    exportToCSV()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("CSVエクスポート")
            }
            .padding()

            Divider()

            // メモ一覧
            if memos.isEmpty {
                VStack {
                    Spacer()
                    Text("メモがありません")
                        .foregroundColor(.secondary)
                    Text("＋ボタンで追加")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(memos) { memo in
                        MemoRowView(memo: memo)
                            .contentShape(Rectangle())
                            .onTapGesture { editingMemo = memo }
                            .contextMenu {
                                Button {
                                    segmentConnectMemo = memo
                                } label: {
                                    Label("このセグメントに接続", systemImage: "network")
                                }
                                Divider()
                                Button {
                                    appState.ipMemoStore.moveMemoToTopLevelByID(memo.id, from: folderID)
                                } label: {
                                    Label("フォルダから出す", systemImage: "tray.and.arrow.up")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    appState.ipMemoStore.deleteMemoByID(memo.id, from: folderID)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 320, height: 400)
        .sheet(isPresented: $showAddMemoSheet) {
            IPMemoEditView(memo: nil, folderID: folderID)
                .environmentObject(appState)
        }
        .sheet(item: $editingMemo) { memo in
            IPMemoEditView(memo: memo, folderID: folderID)
                .environmentObject(appState)
        }
        .sheet(item: $segmentConnectMemo) { memo in
            SegmentConnectView(targetIP: memo.ipAddress)
                .environmentObject(appState)
        }
    }

    private func exportToCSV() {
        guard let currentFolder = appState.ipMemoStore.folders.first(where: { $0.id == folderID }) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "\(currentFolder.name).csv"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try appState.ipMemoStore.saveCSVToFile(currentFolder, url: url)
            } catch {
                print("CSV保存エラー: \(error)")
            }
        }
    }
}

/// フォルダ編集ビュー
struct FolderEditView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let folder: IPMemoFolder?
    @State private var name: String = ""

    var isEditing: Bool { folder != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "フォルダを編集" : "新規フォルダ")
                .font(.headline)

            TextField("フォルダ名", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("キャンセル") {
                    dismiss()
                }

                Spacer()

                Button(isEditing ? "更新" : "作成") {
                    if isEditing, var updatedFolder = folder {
                        updatedFolder.name = name
                        appState.ipMemoStore.updateFolder(updatedFolder)
                    } else {
                        appState.ipMemoStore.addFolder(name: name)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            if let folder = folder {
                name = folder.name
            }
        }
    }
}

/// IPメモ編集ビュー
struct IPMemoEditView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let memo: IPMemo?
    var folderID: UUID?

    @State private var name: String = ""
    @State private var ipAddress: String = ""

    var isEditing: Bool { memo != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "メモを編集" : "新規メモ")
                .font(.headline)

            TextField("名前", text: $name)
                .textFieldStyle(.roundedBorder)

            ASCIITextField(text: $ipAddress, placeholder: "IPアドレス")

            HStack {
                Button("キャンセル") {
                    dismiss()
                }

                Spacer()

                if isEditing {
                    Button("削除") {
                        if let memo = memo {
                            if let folderID = folderID {
                                appState.ipMemoStore.deleteMemo(memo, from: folderID)
                            } else {
                                appState.ipMemoStore.delete(memo)
                            }
                        }
                        dismiss()
                    }
                    .foregroundColor(.red)
                }

                Button(isEditing ? "更新" : "追加") {
                    if isEditing, var updatedMemo = memo {
                        updatedMemo.name = name
                        updatedMemo.ipAddress = ipAddress
                        if let folderID = folderID {
                            appState.ipMemoStore.updateMemo(updatedMemo, in: folderID)
                        } else {
                            appState.ipMemoStore.update(updatedMemo)
                        }
                    } else {
                        if let folderID = folderID {
                            appState.ipMemoStore.addMemo(to: folderID, name: name, ipAddress: ipAddress)
                        } else {
                            appState.ipMemoStore.add(name: name, ipAddress: ipAddress)
                        }
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || ipAddress.isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            if let memo = memo {
                name = memo.name
                ipAddress = memo.ipAddress
            }
        }
    }
}

/// ドラッグ可能なメモ行ビュー
struct DraggableMemoRowView: View {
    let memo: IPMemo
    @Binding var draggedMemo: IPMemo?
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    var onSegmentConnect: (() -> Void)? = nil
    @State private var isDragging = false

    var body: some View {
        MemoRowView(memo: memo)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .opacity(isDragging ? 0.5 : 1.0)
            .scaleEffect(isDragging ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .onDrag {
                isDragging = true
                draggedMemo = memo
                // ダミーデータ（実際の移動はdraggedMemo状態で管理）
                return NSItemProvider(object: "" as NSString)
            }
            .onChange(of: draggedMemo) { _, newValue in
                if newValue == nil || newValue?.id != memo.id {
                    isDragging = false
                }
            }
            .onDrop(of: [.plainText], isTargeted: nil) { _ in
                // 同じ場所にドロップした場合のリセット
                isDragging = false
                draggedMemo = nil
                return false
            }
            .contextMenu {
                if let onSegmentConnect = onSegmentConnect {
                    Button(action: onSegmentConnect) {
                        Label("このセグメントに接続", systemImage: "network")
                    }
                    Divider()
                }
                if let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
    }
}

/// フォルダへのドロップデリゲート
struct FolderDropDelegate: DropDelegate {
    let folder: IPMemoFolder
    @Binding var draggedMemo: IPMemo?
    @Binding var highlightedFolderID: UUID?
    let ipMemoStore: IPMemoStore

    func performDrop(info: DropInfo) -> Bool {
        guard let memo = draggedMemo else { return false }

        Task { @MainActor in
            ipMemoStore.moveMemoToFolder(memo, to: folder.id)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            highlightedFolderID = nil
        }
        draggedMemo = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard draggedMemo != nil else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            highlightedFolderID = folder.id
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if highlightedFolderID == folder.id {
                highlightedFolderID = nil
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        return draggedMemo != nil
    }
}

/// フォルダ内メモのドラッグ可能ビュー
struct DraggableFolderMemoRowView: View {
    let memo: IPMemo
    let folderID: UUID
    @Binding var draggedMemo: IPMemo?
    @Binding var draggedFromFolderID: UUID?
    let onTap: () -> Void
    @State private var isDragging = false

    var body: some View {
        MemoRowView(memo: memo)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .opacity(isDragging ? 0.5 : 1.0)
            .scaleEffect(isDragging ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .onDrag {
                isDragging = true
                draggedMemo = memo
                draggedFromFolderID = folderID
                // ダミーデータ（実際の移動はdraggedMemo状態で管理）
                return NSItemProvider(object: "" as NSString)
            }
            .onChange(of: draggedMemo) { _, newValue in
                if newValue == nil || newValue?.id != memo.id {
                    isDragging = false
                }
            }
            .onDrop(of: [.plainText], isTargeted: nil) { _ in
                // 同じ場所にドロップした場合のリセット
                isDragging = false
                draggedMemo = nil
                draggedFromFolderID = nil
                return false
            }
    }
}

/// トップレベルへのドロップデリゲート（フォルダから外へ）
struct TopLevelDropDelegate: DropDelegate {
    @Binding var draggedMemo: IPMemo?
    @Binding var draggedFromFolderID: UUID?
    let ipMemoStore: IPMemoStore

    func performDrop(info: DropInfo) -> Bool {
        guard let memo = draggedMemo, let fromFolderID = draggedFromFolderID else { return false }

        Task { @MainActor in
            ipMemoStore.moveMemoToTopLevel(memo, from: fromFolderID)
        }

        draggedMemo = nil
        draggedFromFolderID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        return draggedMemo != nil && draggedFromFolderID != nil
    }
}

/// フォルダ間移動用ドロップデリゲート
struct FolderDropDelegateFromFolder: DropDelegate {
    let targetFolder: IPMemoFolder
    @Binding var draggedMemo: IPMemo?
    @Binding var draggedFromFolderID: UUID?
    let ipMemoStore: IPMemoStore

    func performDrop(info: DropInfo) -> Bool {
        guard let memo = draggedMemo else { return false }

        Task { @MainActor in
            if let fromFolderID = draggedFromFolderID {
                // フォルダ間移動
                ipMemoStore.moveMemo(memo, from: fromFolderID, to: targetFolder.id)
            } else {
                // トップレベルからフォルダへ
                ipMemoStore.moveMemoToFolder(memo, to: targetFolder.id)
            }
        }

        draggedMemo = nil
        draggedFromFolderID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // 同じフォルダへのドロップは無効
        if let fromFolderID = draggedFromFolderID, fromFolderID == targetFolder.id {
            return false
        }
        return draggedMemo != nil
    }
}

/// ASCII入力専用テキストフィールド
struct ASCIITextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ASCIITextField

        init(_ parent: ASCIITextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            var newValue = textField.stringValue

            // 全角を半角に変換
            if let converted = newValue.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
                newValue = converted
            }
            // 句読点も変換
            newValue = newValue
                .replacingOccurrences(of: "。", with: ".")
                .replacingOccurrences(of: "、", with: ",")
                .replacingOccurrences(of: "：", with: ":")

            if newValue != textField.stringValue {
                textField.stringValue = newValue
            }
            parent.text = newValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            // ASCII入力モードに切り替え
            if let source = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue() {
                TISSelectInputSource(source)
            }
        }
    }
}

/// セグメント接続ビュー
struct SegmentConnectView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let targetIP: String  // メモのIP（ターゲットセグメント）

    @State private var selectedAdapterName: String?
    @State private var subnetMask: String = "255.255.255.0"
    @State private var router: String = ""
    @State private var isSearching = false
    @State private var foundIP: String?
    @State private var errorMessage: String?
    @State private var isApplying = false
    @State private var searchProgress: String = ""

    /// サブネットマスクからホスト範囲を計算
    private var hostRange: (start: UInt32, end: UInt32)? {
        guard let targetIPValue = ipToUInt32(targetIP),
              let maskValue = ipToUInt32(subnetMask) else { return nil }

        let networkAddress = targetIPValue & maskValue
        let broadcastAddress = networkAddress | (~maskValue)

        // ホスト範囲: ネットワークアドレス+1 〜 ブロードキャスト-1
        let hostStart = networkAddress + 1
        let hostEnd = broadcastAddress - 1

        guard hostStart <= hostEnd else { return nil }
        return (hostStart, hostEnd)
    }

    /// 検索開始位置（範囲の後半80%から開始、DHCPと被りにくい）
    private var searchStartIP: UInt32? {
        guard let range = hostRange else { return nil }
        let totalHosts = range.end - range.start + 1
        let offset = UInt32(Double(totalHosts) * 0.8)
        return range.start + offset
    }

    /// デフォルトルーター（ネットワークアドレス+1）
    private var defaultRouter: String {
        guard let targetIPValue = ipToUInt32(targetIP),
              let maskValue = ipToUInt32(subnetMask) else { return "" }
        let networkAddress = targetIPValue & maskValue
        return uint32ToIP(networkAddress + 1)
    }

    /// ネットワーク情報の表示用テキスト
    private var networkInfo: String {
        guard let range = hostRange else { return "無効なサブネット設定" }
        let startIP = uint32ToIP(range.start)
        let endIP = uint32ToIP(range.end)
        let hostCount = range.end - range.start + 1
        return "\(startIP) 〜 \(endIP) (\(hostCount)ホスト)"
    }

    var body: some View {
        VStack(spacing: 12) {
            // ヘッダー
            HStack {
                Text("このセグメントに接続")
                    .font(.headline)
                Spacer()
                Button("キャンセル") {
                    dismiss()
                }
            }

            Divider()

            // ターゲットIP表示
            VStack(alignment: .leading, spacing: 4) {
                Text("ターゲットIP")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(targetIP)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // サブネットマスク入力
            VStack(alignment: .leading, spacing: 4) {
                Text("サブネットマスク")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    IPTextField(text: $subnetMask, placeholder: "255.255.255.0")
                    // よく使うサブネットマスクのプリセット
                    Menu {
                        Button("255.255.255.0 (/24)") { subnetMask = "255.255.255.0"; updateRouterIfNeeded() }
                        Button("255.255.255.128 (/25)") { subnetMask = "255.255.255.128"; updateRouterIfNeeded() }
                        Button("255.255.254.0 (/23)") { subnetMask = "255.255.254.0"; updateRouterIfNeeded() }
                        Button("255.255.252.0 (/22)") { subnetMask = "255.255.252.0"; updateRouterIfNeeded() }
                        Button("255.255.240.0 (/20)") { subnetMask = "255.255.240.0"; updateRouterIfNeeded() }
                        Button("255.255.128.0 (/17)") { subnetMask = "255.255.128.0"; updateRouterIfNeeded() }
                        Button("255.255.0.0 (/16)") { subnetMask = "255.255.0.0"; updateRouterIfNeeded() }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
                Text(networkInfo)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ルーター入力
            VStack(alignment: .leading, spacing: 4) {
                Text("ルーター")
                    .font(.caption)
                    .foregroundColor(.secondary)
                IPTextField(text: $router, placeholder: defaultRouter)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // アダプタ選択
            VStack(alignment: .leading, spacing: 4) {
                Text("アダプタを選択")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if appState.networkManager.connectedAdapters.isEmpty {
                    Text("接続中のアダプタがありません")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(appState.networkManager.connectedAdapters) { adapter in
                                AdapterSelectionRow(
                                    adapter: adapter,
                                    isSelected: selectedAdapterName == adapter.hardwarePort,
                                    onSelect: { selectedAdapterName = adapter.hardwarePort }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }

            Divider()

            // 状態表示
            if isSearching {
                VStack(spacing: 4) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("空きIPを検索中...")
                            .foregroundColor(.secondary)
                    }
                    if !searchProgress.isEmpty {
                        Text(searchProgress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let foundIP = foundIP {
                VStack(alignment: .leading, spacing: 4) {
                    Text("設定するIP")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(foundIP)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()

            // 実行ボタン
            Button {
                if foundIP != nil {
                    applyConfiguration()
                } else {
                    searchAvailableIP()
                }
            } label: {
                HStack {
                    if isApplying {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(foundIP != nil ? "適用（管理者権限が必要）" : "空きIPを検索")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedAdapterName == nil || isSearching || isApplying || hostRange == nil)
        }
        .padding()
        .frame(width: 360, height: 520)
        .onAppear {
            router = defaultRouter
        }
        .onChange(of: subnetMask) { _, _ in
            // サブネットマスク変更時に検索結果をリセット
            foundIP = nil
            errorMessage = nil
        }
    }

    private func updateRouterIfNeeded() {
        router = defaultRouter
    }

    /// 空きIPを検索
    private func searchAvailableIP() {
        guard let range = hostRange,
              let startIP = searchStartIP else { return }

        isSearching = true
        errorMessage = nil
        foundIP = nil
        searchProgress = ""

        Task {
            // 検索開始位置から末尾まで
            for ipValue in startIP...range.end {
                let ip = uint32ToIP(ipValue)
                await MainActor.run {
                    searchProgress = "検索中: \(ip)"
                }

                let available = await checkIPAvailable(ip)
                if available {
                    await MainActor.run {
                        foundIP = ip
                        isSearching = false
                        searchProgress = ""
                    }
                    return
                }
            }

            // 見つからなかった場合、先頭から検索開始位置まで
            for ipValue in range.start..<startIP {
                let ip = uint32ToIP(ipValue)
                await MainActor.run {
                    searchProgress = "検索中: \(ip)"
                }

                let available = await checkIPAvailable(ip)
                if available {
                    await MainActor.run {
                        foundIP = ip
                        isSearching = false
                        searchProgress = ""
                    }
                    return
                }
            }

            await MainActor.run {
                errorMessage = "空きIPが見つかりませんでした"
                isSearching = false
                searchProgress = ""
            }
        }
    }

    /// IPが利用可能か確認（pingで応答がなければ利用可能）
    private func checkIPAvailable(_ ip: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "300", ip]  // 1回、300msタイムアウト

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                // 終了コード0 = 応答あり（使用中）、それ以外 = 応答なし（空き）
                continuation.resume(returning: process.terminationStatus != 0)
            } catch {
                continuation.resume(returning: true)  // エラーの場合は空きと判断
            }
        }
    }

    /// 設定を適用
    private func applyConfiguration() {
        guard let adapterName = selectedAdapterName,
              let ip = foundIP else { return }

        isApplying = true

        let routerToUse = router.isEmpty ? defaultRouter : router

        let config = IPConfiguration(
            configureIPv4: .manual,
            ipv4Address: ip,
            subnetMask: subnetMask,
            router: routerToUse,
            dnsServers: ["8.8.8.8", "1.1.1.1"]  // 公開DNSをデフォルトで設定
        )

        Task {
            do {
                try await appState.networkManager.applyConfiguration(config, to: adapterName)
                await MainActor.run {
                    isApplying = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - IP変換ユーティリティ

    /// IPアドレス文字列をUInt32に変換
    private func ipToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4,
              parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    /// UInt32をIPアドレス文字列に変換
    private func uint32ToIP(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}

/// アダプタ選択行
struct AdapterSelectionRow: View {
    let adapter: NetworkAdapter
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: adapter.iconName)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(adapter.displayName)
                        .fontWeight(.medium)
                    if let ip = adapter.ipConfiguration?.ipv4Address {
                        Text("現在: \(ip)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未接続")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainPopoverView()
        .environmentObject(AppState())
}
