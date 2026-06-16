unit VideoMinerShortcutBindings;

// VideoMiner 用のキーボードショートカット割り当てを一か所にまとめる。
// 実際の処理は呼び出し側から渡されたハンドラへ委譲し、このユニットはキー表だけを持つ。

interface

uses
  Winapi.Windows, System.Classes, ShortcutAction;

type
  TVideoMinerShortcutHandlers = record
    ChapterPrevious  : TShortcutActionProc; // 前のチャプターへ移動する
    ChapterNext      : TShortcutActionProc; // 次のチャプターへ移動する
    OpenDialog       : TShortcutActionProc; // ファイルを開くダイアログを表示する
    NavigatePrevious : TShortcutActionProc; // フォルダ内の前の動画へ移動する
    NavigateNext     : TShortcutActionProc; // フォルダ内の次の動画へ移動する
    CyclePlaybackRate: TShortcutActionProc; // 再生速度を切り替える
    SeekToFirstFrame : TShortcutActionProc; // 先頭フレームへ移動する
    SeekToLastFrame  : TShortcutActionProc; // 末尾フレームへ移動する
    ToggleFullScreen : TShortcutActionProc; // 全画面表示を切り替える
    ToggleMute       : TShortcutActionProc; // ミュート状態を切り替える
    TogglePlayPause  : TShortcutActionProc; // 再生と一時停止を切り替える
    VolumeDown       : TShortcutActionProc; // 音量を下げる
    VolumeUp         : TShortcutActionProc; // 音量を上げる
  end;

// VideoMiner の既定ショートカットを登録し直す
procedure RegisterVideoMinerShortcuts(Shortcuts: TShortcutAction;
  const Handlers: TVideoMinerShortcutHandlers);

implementation

// キーの割り当てだけを定義し、実行内容はハンドラレコードへ任せる
procedure RegisterVideoMinerShortcuts(Shortcuts: TShortcutAction;
  const Handlers: TVideoMinerShortcutHandlers);
begin
  if Shortcuts = nil then
    Exit;

  Shortcuts.Clear;
  Shortcuts.Add(Ord('O'), [ssCtrl], Handlers.OpenDialog);
  Shortcuts.Add(VK_LEFT, [ssCtrl], Handlers.ChapterPrevious);
  Shortcuts.Add(VK_RIGHT, [ssCtrl], Handlers.ChapterNext);
  Shortcuts.Add(VK_F11, [], Handlers.ToggleFullScreen);
  Shortcuts.Add(VK_SPACE, [], Handlers.TogglePlayPause);
  Shortcuts.Add(VK_LEFT, [], Handlers.NavigatePrevious);
  Shortcuts.Add(VK_RIGHT, [], Handlers.NavigateNext);
  Shortcuts.Add(VK_PRIOR, [], Handlers.NavigatePrevious);
  Shortcuts.Add(VK_NEXT, [], Handlers.NavigateNext);
  Shortcuts.Add(Ord('R'), [], Handlers.CyclePlaybackRate);
  Shortcuts.Add(VK_HOME, [], Handlers.SeekToFirstFrame);
  Shortcuts.Add(VK_END, [], Handlers.SeekToLastFrame);
  Shortcuts.Add(VK_UP, [], Handlers.VolumeUp);
  Shortcuts.Add(VK_DOWN, [], Handlers.VolumeDown);
  Shortcuts.Add(Ord('M'), [], Handlers.ToggleMute);
end;

end.
