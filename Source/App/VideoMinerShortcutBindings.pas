unit VideoMinerShortcutBindings;

interface

uses
  Winapi.Windows, System.Classes, ShortcutAction;

type
  TVideoMinerShortcutHandlers = record
    ChapterPrevious: TShortcutActionProc;
    ChapterNext: TShortcutActionProc;
    OpenDialog: TShortcutActionProc;
    NavigatePrevious: TShortcutActionProc;
    NavigateNext: TShortcutActionProc;
    SeekToFirstFrame: TShortcutActionProc;
    SeekToLastFrame: TShortcutActionProc;
    ToggleFullScreen: TShortcutActionProc;
    ToggleMute: TShortcutActionProc;
    TogglePlayPause: TShortcutActionProc;
    VolumeDown: TShortcutActionProc;
    VolumeUp: TShortcutActionProc;
  end;

procedure RegisterVideoMinerShortcuts(Shortcuts: TShortcutAction;
  const Handlers: TVideoMinerShortcutHandlers);

implementation

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
  Shortcuts.Add(VK_HOME, [], Handlers.SeekToFirstFrame);
  Shortcuts.Add(VK_END, [], Handlers.SeekToLastFrame);
  Shortcuts.Add(VK_UP, [], Handlers.VolumeUp);
  Shortcuts.Add(VK_DOWN, [], Handlers.VolumeDown);
  Shortcuts.Add(Ord('M'), [], Handlers.ToggleMute);
end;

end.
