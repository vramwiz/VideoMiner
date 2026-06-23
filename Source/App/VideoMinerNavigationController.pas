unit VideoMinerNavigationController;

// フォルダ内の前後動画移動と、移動直後の残留キー入力抑止を担当する。

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.SysUtils,
  VideoMinerMediaList, VideoMinerVideoView;

type
  TVideoMinerNavigationOpenFunc = function(const FileName: string;
    AutoPlay: Boolean; RestoreLoopPosition: Boolean = True): Boolean of object;

  TVideoMinerNavigationController = class
  private
    FBlockedNavigationKeys: set of Byte;
    FMediaList: TVideoMinerMediaList;
    FNavigationInputBlockedUntilTick: UInt64;
    FOnOpenFile: TVideoMinerNavigationOpenFunc;
    FVideoView: TVideoMinerVideoView;
    class function IsNavigationSwitchKey(Key: Word): Boolean; static;
    procedure BlockPressedNavigationKeys;
    procedure ClearBufferedNavigationKeyMessages;
  public
    constructor Create(AMediaList: TVideoMinerMediaList;
      AVideoView: TVideoMinerVideoView);
    function CanNavigateNext: Boolean;
    function HandleKeyDown(var Key: Word; Shift: TShiftState): Boolean;
    procedure HandleKeyUp(var Key: Word);
    procedure NavigateBy(Delta: Integer);
    procedure NavigateNextPlaybackFile;
    procedure UpdateButtons;
    property OnOpenFile: TVideoMinerNavigationOpenFunc read FOnOpenFile
      write FOnOpenFile;
  end;

implementation

const
  NAVIGATION_INPUT_BLOCK_MS = 300; // 前後動画移動直後に残留キー入力を無視する時間 ms

constructor TVideoMinerNavigationController.Create(
  AMediaList: TVideoMinerMediaList; AVideoView: TVideoMinerVideoView);
begin
  inherited Create;
  FMediaList := AMediaList;
  FVideoView := AVideoView;
end;

procedure TVideoMinerNavigationController.BlockPressedNavigationKeys;
const
  NAVIGATION_KEYS: array[0..3] of Word = (VK_LEFT, VK_RIGHT, VK_PRIOR, VK_NEXT);
var
  I: Integer;
  Key: Word;
begin
  for I := Low(NAVIGATION_KEYS) to High(NAVIGATION_KEYS) do
  begin
    Key := NAVIGATION_KEYS[I];
    if GetAsyncKeyState(Key) < 0 then
      Include(FBlockedNavigationKeys, Byte(Key));
  end;
end;

function TVideoMinerNavigationController.CanNavigateNext: Boolean;
begin
  Result := (FMediaList <> nil) and FMediaList.CanNavigate(1);
end;

procedure TVideoMinerNavigationController.ClearBufferedNavigationKeyMessages;
var
  Msg: TMsg;
begin
  while PeekMessage(Msg, 0, WM_KEYFIRST, WM_KEYLAST, PM_NOREMOVE) do
  begin
    if ((Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN)) and
       IsNavigationSwitchKey(Word(Msg.wParam)) then
    begin
      PeekMessage(Msg, Msg.hwnd, Msg.message, Msg.message, PM_REMOVE);
    end
    else
      Break;
  end;
end;

function TVideoMinerNavigationController.HandleKeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
begin
  Result := False;
  if (Shift = []) and IsNavigationSwitchKey(Key) and
     ((Byte(Key) in FBlockedNavigationKeys) or
      (GetTickCount64 < FNavigationInputBlockedUntilTick)) then
  begin
    Key := 0;
    Result := True;
  end;
end;

procedure TVideoMinerNavigationController.HandleKeyUp(var Key: Word);
begin
  if IsNavigationSwitchKey(Key) then
    Exclude(FBlockedNavigationKeys, Byte(Key));
end;

class function TVideoMinerNavigationController.IsNavigationSwitchKey(
  Key: Word): Boolean;
begin
  Result := (Key = VK_LEFT) or (Key = VK_RIGHT) or
    (Key = VK_PRIOR) or (Key = VK_NEXT);
end;

procedure TVideoMinerNavigationController.NavigateBy(Delta: Integer);
var
  FileName: string;
begin
  if FMediaList = nil then
    Exit;

  FileName := FMediaList.NavigateFile(Delta);
  if FileName = '' then
  begin
    UpdateButtons;
    Exit;
  end;

  if Assigned(FOnOpenFile) then
    FOnOpenFile(FileName, True);
  FNavigationInputBlockedUntilTick := GetTickCount64 + NAVIGATION_INPUT_BLOCK_MS;
  BlockPressedNavigationKeys;
  ClearBufferedNavigationKeyMessages;
end;

procedure TVideoMinerNavigationController.NavigateNextPlaybackFile;
begin
  NavigateBy(1);
end;

procedure TVideoMinerNavigationController.UpdateButtons;
begin
  if FVideoView = nil then
    Exit;

  if FMediaList = nil then
  begin
    FVideoView.CanNavigatePrevious := False;
    FVideoView.CanNavigateNext := False;
    Exit;
  end;

  FVideoView.CanNavigatePrevious := FMediaList.CanNavigate(-1);
  FVideoView.CanNavigateNext := FMediaList.CanNavigate(1);
end;

end.
