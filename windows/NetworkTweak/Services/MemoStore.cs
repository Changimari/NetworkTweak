using System.Text;
using System.Text.Json;
using NetworkTweak.Models;

namespace NetworkTweak.Services;

/// <summary>IPメモの永続化。macOS 版 IPMemoStore 相当。%APPDATA%\NetworkTweak\memos.json に保存</summary>
public class MemoStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly string _path;
    private MemoData _data = new();

    public List<IPMemoFolder> Folders => _data.Folders;
    public List<IPMemo> Memos => _data.Memos; // トップレベル

    public MemoStore()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "NetworkTweak");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "memos.json");
        Load();
    }

    public void Load()
    {
        try
        {
            if (File.Exists(_path))
            {
                string json = File.ReadAllText(_path);
                _data = JsonSerializer.Deserialize<MemoData>(json) ?? new MemoData();
            }
        }
        catch
        {
            _data = new MemoData();
        }
    }

    public void Save()
    {
        try
        {
            string json = JsonSerializer.Serialize(_data, JsonOptions);
            File.WriteAllText(_path, json);
        }
        catch { /* 保存失敗は無視 */ }
    }

    // MARK: - フォルダ操作

    public IPMemoFolder AddFolder(string name)
    {
        var folder = new IPMemoFolder { Name = name };
        _data.Folders.Add(folder);
        Save();
        return folder;
    }

    public void DeleteFolder(Guid folderId)
    {
        _data.Folders.RemoveAll(f => f.Id == folderId);
        Save();
    }

    public void RenameFolder(Guid folderId, string name)
    {
        var folder = _data.Folders.FirstOrDefault(f => f.Id == folderId);
        if (folder != null) { folder.Name = name; Save(); }
    }

    // MARK: - メモ操作

    /// <summary>folderId が null ならトップレベルに追加</summary>
    public void AddMemo(Guid? folderId, IPMemo memo)
    {
        if (folderId is Guid fid)
        {
            var folder = _data.Folders.FirstOrDefault(f => f.Id == fid);
            folder?.Memos.Add(memo);
        }
        else
        {
            _data.Memos.Add(memo);
        }
        Save();
    }

    public void UpdateMemo(IPMemo memo)
    {
        var top = _data.Memos.FirstOrDefault(m => m.Id == memo.Id);
        if (top != null)
        {
            CopyInto(memo, top);
            Save();
            return;
        }
        foreach (var folder in _data.Folders)
        {
            var m = folder.Memos.FirstOrDefault(x => x.Id == memo.Id);
            if (m != null) { CopyInto(memo, m); Save(); return; }
        }
    }

    public void DeleteMemo(Guid memoId)
    {
        _data.Memos.RemoveAll(m => m.Id == memoId);
        foreach (var folder in _data.Folders)
            folder.Memos.RemoveAll(m => m.Id == memoId);
        Save();
    }

    /// <summary>メモを別フォルダ（null ならトップレベル）へ移動</summary>
    public void MoveMemo(Guid memoId, Guid? targetFolderId)
    {
        IPMemo? memo = _data.Memos.FirstOrDefault(m => m.Id == memoId);
        if (memo != null) _data.Memos.Remove(memo);

        if (memo == null)
        {
            foreach (var folder in _data.Folders)
            {
                var found = folder.Memos.FirstOrDefault(m => m.Id == memoId);
                if (found != null) { memo = found; folder.Memos.Remove(found); break; }
            }
        }

        if (memo == null) return;

        if (targetFolderId is Guid fid)
        {
            var target = _data.Folders.FirstOrDefault(f => f.Id == fid);
            if (target != null) target.Memos.Add(memo);
            else _data.Memos.Add(memo);
        }
        else
        {
            _data.Memos.Add(memo);
        }
        Save();
    }

    private static void CopyInto(IPMemo src, IPMemo dst)
    {
        dst.Name = src.Name;
        dst.IpAddress = src.IpAddress;
        dst.Username = src.Username;
        dst.Password = src.Password;
        dst.Note = src.Note;
    }

    // MARK: - CSV エクスポート

    public static string ExportToCsv(IEnumerable<IPMemo> memos)
    {
        var sb = new StringBuilder();
        sb.AppendLine("名前,IPアドレス,ユーザー名,パスワード,メモ");
        foreach (var m in memos)
        {
            sb.AppendLine(string.Join(",",
                Quote(m.Name), Quote(m.IpAddress), Quote(m.Username),
                Quote(m.Password), Quote(m.Note)));
        }
        return sb.ToString();
    }

    private static string Quote(string value)
        => "\"" + (value ?? "").Replace("\"", "\"\"") + "\"";
}
