unit VideoMinerInputMessageRouter;

// アプリ全体へ届く補助入力メッセージを、メインフォームの前後動画移動へ橋渡しする。
// マウス戻る/進むボタンやブラウザー戻る/進むキーのログと遅延実行要求を担当する。

interface

uses
  Winapi.Messages, Winapi.Windows, Vcl.Forms;

// 既存の Application.OnMessage を尊重しつつ、戻る/進む系入力を独自メッセージへ変換する
procedure RouteVideoMinerApplicationMessage(FormHandle: HWND;
  NavigateMessageId: Cardinal; LoadingVideo: Boolean;
  NavigationAvailable: Boolean; PreviousHandler: TMessageEvent; var Msg: TMsg;
  var Handled: Boolean);

implementation

uses
  System.SysUtils, VideoMinerDebugLog;

const
  VK_BROWSER_BACK = $A6;              // ブラウザー戻るキー
  VK_BROWSER_FORWARD = $A7;           // ブラウザー進むキー
  VM_WM_XBUTTONDBLCLK = $020D;        // Delphi の定数に無い環境向けの XButton double click

function ShouldLogInputMessage(const Msg: TMsg): Boolean;
begin
  case Msg.message of
    WM_XBUTTONDOWN, WM_XBUTTONUP, VM_WM_XBUTTONDBLCLK, WM_APPCOMMAND:
      Result := True;
    WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP:
      Result := (Msg.wParam = VK_BROWSER_BACK) or
        (Msg.wParam = VK_BROWSER_FORWARD);
  else
    Result := False;
  end;
end;

procedure LogInputMessage(const Msg: TMsg; Handled: Boolean);
var
  AppCommand: Word;
  Button: Word;
  ClassName: array[0..127] of Char;
  ClassText: string;
begin
  if not VideoMinerDebugLogEnabled then
    Exit;
  if not ShouldLogInputMessage(Msg) then
    Exit;

  Button := Word((NativeUInt(Msg.wParam) shr 16) and $FFFF);
  AppCommand := Word((NativeUInt(Msg.lParam) shr 16) and $FFFF);
  ClassText := '';
  if (Msg.hwnd <> 0) and (GetClassName(Msg.hwnd, ClassName,
    Length(ClassName)) > 0) then
    ClassText := ClassName;

  WriteVideoMinerDebugLog(Format(
    'input_msg hwnd=$%s class="%s" msg=$%s wparam=$%s lparam=$%s key=%d xbutton=%d appcmd_raw=$%s handled=%s',
    [IntToHex(NativeInt(Msg.hwnd), 8), ClassText, IntToHex(Msg.message, 4),
     IntToHex(NativeInt(Msg.wParam), 8), IntToHex(NativeInt(Msg.lParam), 8),
     Msg.wParam and $FFFF, Button, IntToHex(AppCommand, 4),
     BoolToStr(Handled, True)]));
end;

procedure QueueNavigation(FormHandle: HWND; NavigateMessageId: Cardinal;
  LoadingVideo: Boolean; Delta: Integer; const Source: string;
  var Handled: Boolean);
var
  Direction: WPARAM;
begin
  Handled := True;
  if LoadingVideo then
  begin
    WriteVideoMinerDebugLog(Format('input_%s_ignore_loading delta=%d',
      [Source, Delta]));
    Exit;
  end;

  if Delta < 0 then
    Direction := 1
  else
    Direction := 2;
  PostMessage(FormHandle, NavigateMessageId, Direction, 0);
  WriteVideoMinerDebugLog(Format('input_%s_queue delta=%d',
    [Source, Delta]));
end;

procedure RouteVideoMinerApplicationMessage(FormHandle: HWND;
  NavigateMessageId: Cardinal; LoadingVideo: Boolean;
  NavigationAvailable: Boolean; PreviousHandler: TMessageEvent; var Msg: TMsg;
  var Handled: Boolean);
var
  Button: Word;
begin
  if Assigned(PreviousHandler) then
    PreviousHandler(Msg, Handled);

  LogInputMessage(Msg, Handled);

  if Handled or (not NavigationAvailable) then
    Exit;

  Button := Word((NativeUInt(Msg.wParam) shr 16) and $FFFF);
  if Msg.message = WM_XBUTTONDOWN then
  begin
    case Button of
      1:
        QueueNavigation(FormHandle, NavigateMessageId, LoadingVideo, -1,
          'xbutton', Handled);
      2:
        QueueNavigation(FormHandle, NavigateMessageId, LoadingVideo, 1,
          'xbutton', Handled);
    end;
  end
  else if (Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN) then
  begin
    case Msg.wParam of
      VK_BROWSER_BACK:
        QueueNavigation(FormHandle, NavigateMessageId, LoadingVideo, -1,
          'browser_key', Handled);
      VK_BROWSER_FORWARD:
        QueueNavigation(FormHandle, NavigateMessageId, LoadingVideo, 1,
          'browser_key', Handled);
    end;
  end;
end;

end.
