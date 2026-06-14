namespace NetworkTweak.Models;

/// <summary>シンプルなIPメモ</summary>
public class IPMemo
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string IpAddress { get; set; } = "";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string Note { get; set; } = "";
}

/// <summary>IPメモフォルダ</summary>
public class IPMemoFolder
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public List<IPMemo> Memos { get; set; } = new();
}

/// <summary>永続化用のルートコンテナ</summary>
public class MemoData
{
    public List<IPMemoFolder> Folders { get; set; } = new();
    /// <summary>フォルダに属さないトップレベルのメモ</summary>
    public List<IPMemo> Memos { get; set; } = new();
}
