using NetworkTweak.Models;

namespace NetworkTweak.UI;

/// <summary>シンプルな1行入力ダイアログ</summary>
public static class InputBox
{
    public static string? Show(string prompt, string title, string defaultValue = "")
    {
        using var form = new Form
        {
            Text = title,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterParent,
            MinimizeBox = false,
            MaximizeBox = false,
            ClientSize = new Size(360, 130)
        };

        var label = new Label { Text = prompt, Left = 12, Top = 12, Width = 336, Height = 20 };
        var textBox = new TextBox { Left = 12, Top = 38, Width = 336, Text = defaultValue };
        var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, Left = 180, Top = 80, Width = 80 };
        var cancel = new Button { Text = "キャンセル", DialogResult = DialogResult.Cancel, Left = 268, Top = 80, Width = 80 };

        form.Controls.AddRange(new Control[] { label, textBox, ok, cancel });
        form.AcceptButton = ok;
        form.CancelButton = cancel;

        return form.ShowDialog() == DialogResult.OK ? textBox.Text.Trim() : null;
    }
}

/// <summary>メモの新規作成 / 編集ダイアログ</summary>
public class MemoEditForm : Form
{
    private readonly TextBox _name = new();
    private readonly TextBox _ip = new();
    private readonly TextBox _user = new();
    private readonly TextBox _pass = new();
    private readonly TextBox _note = new();

    public IPMemo Result { get; }

    public MemoEditForm(IPMemo? existing = null)
    {
        Result = existing != null
            ? new IPMemo
            {
                Id = existing.Id,
                Name = existing.Name,
                IpAddress = existing.IpAddress,
                Username = existing.Username,
                Password = existing.Password,
                Note = existing.Note
            }
            : new IPMemo();

        Text = existing == null ? "メモを追加" : "メモを編集";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MinimizeBox = false;
        MaximizeBox = false;
        ClientSize = new Size(400, 320);

        int top = 12;
        AddRow("名前", _name, ref top);
        AddRow("IPアドレス", _ip, ref top);
        AddRow("ユーザー名", _user, ref top);
        AddRow("パスワード", _pass, ref top);

        var noteLabel = new Label { Text = "メモ", Left = 12, Top = top, Width = 90 };
        _note.Multiline = true;
        _note.Left = 110;
        _note.Top = top;
        _note.Width = 270;
        _note.Height = 70;
        Controls.Add(noteLabel);
        Controls.Add(_note);
        top += 80;

        var ok = new Button { Text = "保存", DialogResult = DialogResult.OK, Left = 210, Top = top, Width = 80 };
        var cancel = new Button { Text = "キャンセル", DialogResult = DialogResult.Cancel, Left = 300, Top = top, Width = 80 };
        Controls.Add(ok);
        Controls.Add(cancel);
        AcceptButton = ok;
        CancelButton = cancel;

        _name.Text = Result.Name;
        _ip.Text = Result.IpAddress;
        _user.Text = Result.Username;
        _pass.Text = Result.Password;
        _note.Text = Result.Note;

        FormClosing += (_, e) =>
        {
            if (DialogResult != DialogResult.OK) return;
            if (string.IsNullOrWhiteSpace(_name.Text))
            {
                MessageBox.Show("名前を入力してください。", "NetworkTweak");
                e.Cancel = true;
                return;
            }
            Result.Name = _name.Text.Trim();
            Result.IpAddress = _ip.Text.Trim();
            Result.Username = _user.Text.Trim();
            Result.Password = _pass.Text;
            Result.Note = _note.Text.Trim();
        };
    }

    private void AddRow(string label, TextBox box, ref int top)
    {
        var lbl = new Label { Text = label, Left = 12, Top = top + 3, Width = 90 };
        box.Left = 110;
        box.Top = top;
        box.Width = 270;
        Controls.Add(lbl);
        Controls.Add(box);
        top += 32;
    }
}
