import Foundation

/// IPメモフォルダ
struct IPMemoFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var memos: [IPMemo]

    init(id: UUID = UUID(), name: String, memos: [IPMemo] = []) {
        self.id = id
        self.name = name
        self.memos = memos
    }

    /// CSV形式でエクスポート
    func exportToCSV() -> String {
        var csv = "名前,IPアドレス\n"
        for memo in memos {
            let escapedName = memo.name.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedIP = memo.ipAddress.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(escapedName)\",\"\(escapedIP)\"\n"
        }
        return csv
    }
}

/// シンプルなIPメモ
struct IPMemo: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var ipAddress: String

    init(id: UUID = UUID(), name: String, ipAddress: String) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
    }
}

/// IPメモの永続化
@MainActor
final class IPMemoStore: ObservableObject {
    @Published var folders: [IPMemoFolder] = []
    @Published var memos: [IPMemo] = []  // フォルダに属さないメモ（後方互換性）

    private static let foldersKey = "IPMemoFolders"
    private static let memosKey = "IPMemos"

    init() {
        load()
    }

    func load() {
        // フォルダを読み込み
        if let data = UserDefaults.standard.data(forKey: Self.foldersKey),
           let folders = try? JSONDecoder().decode([IPMemoFolder].self, from: data) {
            self.folders = folders
        }

        // 後方互換性：古いメモを読み込み
        if let data = UserDefaults.standard.data(forKey: Self.memosKey),
           let memos = try? JSONDecoder().decode([IPMemo].self, from: data) {
            self.memos = memos
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.foldersKey)
        }
        if let data = try? JSONEncoder().encode(memos) {
            UserDefaults.standard.set(data, forKey: Self.memosKey)
        }
    }

    // MARK: - フォルダ操作

    func addFolder(name: String) {
        let folder = IPMemoFolder(name: name)
        folders.append(folder)
        save()
    }

    func deleteFolder(_ folder: IPMemoFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func updateFolder(_ folder: IPMemoFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            save()
        }
    }

    // MARK: - メモ操作（フォルダ内）

    func addMemo(to folderID: UUID, name: String, ipAddress: String) {
        if let index = folders.firstIndex(where: { $0.id == folderID }) {
            let memo = IPMemo(name: name, ipAddress: ipAddress)
            folders[index].memos.append(memo)
            save()
        }
    }

    func deleteMemo(_ memo: IPMemo, from folderID: UUID) {
        if let index = folders.firstIndex(where: { $0.id == folderID }) {
            folders[index].memos.removeAll { $0.id == memo.id }
            save()
        }
    }

    func updateMemo(_ memo: IPMemo, in folderID: UUID) {
        if let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
           let memoIndex = folders[folderIndex].memos.firstIndex(where: { $0.id == memo.id }) {
            folders[folderIndex].memos[memoIndex] = memo
            save()
        }
    }

    // MARK: - 後方互換性：フォルダなしメモ操作

    func add(name: String, ipAddress: String) {
        let memo = IPMemo(name: name, ipAddress: ipAddress)
        memos.append(memo)
        save()
    }

    func delete(_ memo: IPMemo) {
        memos.removeAll { $0.id == memo.id }
        save()
    }

    func update(_ memo: IPMemo) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index] = memo
            save()
        }
    }

    // MARK: - メモ移動

    /// トップレベルのメモをフォルダに移動
    func moveMemoToFolder(_ memo: IPMemo, to folderID: UUID) {
        // トップレベルから削除
        memos.removeAll { $0.id == memo.id }

        // フォルダに追加
        if let index = folders.firstIndex(where: { $0.id == folderID }) {
            folders[index].memos.append(memo)
        }
        save()
    }

    /// フォルダ内のメモをトップレベルに移動
    func moveMemoToTopLevel(_ memo: IPMemo, from folderID: UUID) {
        moveMemoToTopLevelByID(memo.id, from: folderID)
    }

    /// フォルダ内のメモをトップレベルに移動（ID指定）
    func moveMemoToTopLevelByID(_ memoID: UUID, from folderID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
              let memoIndex = folders[folderIndex].memos.firstIndex(where: { $0.id == memoID }) else {
            return
        }

        // メモを取得してから削除
        let memo = folders[folderIndex].memos[memoIndex]
        folders[folderIndex].memos.remove(at: memoIndex)

        // トップレベルに追加
        memos.append(memo)
        save()
    }

    /// フォルダ内のメモを削除（ID指定）
    func deleteMemoByID(_ memoID: UUID, from folderID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        folders[folderIndex].memos.removeAll { $0.id == memoID }
        save()
    }

    /// フォルダ間でメモを移動
    func moveMemo(_ memo: IPMemo, from sourceFolderID: UUID, to targetFolderID: UUID) {
        guard sourceFolderID != targetFolderID else { return }

        // 元フォルダから削除
        if let index = folders.firstIndex(where: { $0.id == sourceFolderID }) {
            folders[index].memos.removeAll { $0.id == memo.id }
        }

        // 新フォルダに追加
        if let index = folders.firstIndex(where: { $0.id == targetFolderID }) {
            folders[index].memos.append(memo)
        }
        save()
    }

    // MARK: - CSV エクスポート

    func exportFolderToCSV(_ folder: IPMemoFolder) -> String {
        return folder.exportToCSV()
    }

    func saveCSVToFile(_ folder: IPMemoFolder, url: URL) throws {
        let csv = folder.exportToCSV()
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
