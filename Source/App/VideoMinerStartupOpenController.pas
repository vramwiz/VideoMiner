unit VideoMinerStartupOpenController;

// フォーム表示後に実行する起動時 open 予約を管理する。
// 直接ファイル指定と前回ファイル復元を同じ遅延タイマーで処理する。

interface

uses
  Winapi.Windows, System.Classes, Vcl.ExtCtrls;

type
  TVideoMinerStartupOpenFileEvent = function(const FileName: string;
    AutoPlay: Boolean): Boolean of object;
  TVideoMinerStartupOpenStatusEvent = procedure(const Text: string) of object;
  TVideoMinerStartupOpenSimpleEvent = function: Boolean of object;

  TVideoMinerStartupOpenController = class
  private
    FAutoPlay       : Boolean;                             // 予約中ファイルを自動再生するか
    FFileName       : string;                              // 予約中の直接 open ファイル
    FFormHandle     : HWND;                                // 遅延開始メッセージの投稿先
    FMessageId      : Cardinal;                            // フォーム表示後 open 用の独自メッセージ
    FOpenRemembered : Boolean;                             // 前回ファイル復元を予約中か
    FDelayMs        : Integer;                             // 次回 open timer の遅延
    FTimer          : TTimer;                              // フォーム表示後に open を少し遅らせる timer
    FOnLoadFile     : TVideoMinerStartupOpenFileEvent;     // 指定ファイルを開く callback
    FOnOpenRemembered: TVideoMinerStartupOpenSimpleEvent;  // 前回ファイルを開く callback
    FOnSetStatus    : TVideoMinerStartupOpenStatusEvent;   // UI status 表示 callback
    // 予約済みの open を実行する
    procedure TimerTick(Sender: TObject);
  public
    // message 投稿先と timer 所有者を受け取る
    constructor Create(Owner: TComponent; FormHandle: HWND;
      MessageId: Cardinal);
    // 破棄前に timer を停止する
    destructor Destroy; override;
    // 指定ファイル open を予約する
    procedure QueueFile(const FileName: string; AutoPlay: Boolean);
    // 前回ファイル復元を予約する
    procedure QueueRemembered;
    // フォーム側の独自メッセージ受信時に timer を再起動する
    procedure RestartTimer;
    // 実行前の予約 timer を止める
    procedure Stop;
    // 実行前の予約を破棄する
    procedure Cancel;
    property OnLoadFile: TVideoMinerStartupOpenFileEvent read FOnLoadFile write FOnLoadFile;
    property OnOpenRemembered: TVideoMinerStartupOpenSimpleEvent read FOnOpenRemembered write FOnOpenRemembered;
    property OnSetStatus: TVideoMinerStartupOpenStatusEvent read FOnSetStatus write FOnSetStatus;
  end;

implementation

uses
  System.SysUtils, VideoMinerDebugLog;

const
  STARTUP_OPEN_DELAY_MS = 120; // 初回描画後に open を少し遅らせる時間
  STARTUP_REMEMBERED_OPEN_DELAY_MS = 1500; // 空画面操作を優先するため前回復元は遅らせる

constructor TVideoMinerStartupOpenController.Create(Owner: TComponent;
  FormHandle: HWND; MessageId: Cardinal);
begin
  inherited Create;
  FFormHandle := FormHandle;
  FMessageId := MessageId;
  FDelayMs := STARTUP_OPEN_DELAY_MS;
  FTimer := TTimer.Create(Owner);
  FTimer.Enabled := False;
  FTimer.Interval := STARTUP_OPEN_DELAY_MS;
  FTimer.OnTimer := TimerTick;
end;

destructor TVideoMinerStartupOpenController.Destroy;
begin
  Stop;
  inherited;
end;

procedure TVideoMinerStartupOpenController.QueueFile(const FileName: string;
  AutoPlay: Boolean);
begin
  FFileName := FileName;
  FAutoPlay := AutoPlay;
  FOpenRemembered := False;
  FDelayMs := STARTUP_OPEN_DELAY_MS;
  PostMessage(FFormHandle, FMessageId, 0, 0);
end;

procedure TVideoMinerStartupOpenController.QueueRemembered;
begin
  if SameText(GetEnvironmentVariable('VIDEOMINER_DISABLE_STARTUP_RESTORE'), '1') then
  begin
    WriteVideoMinerStartupLog('startup_remembered_skip disabled_by_env');
    Exit;
  end;

  FFileName := '';
  FAutoPlay := False;
  FOpenRemembered := True;
  FDelayMs := STARTUP_REMEMBERED_OPEN_DELAY_MS;
  PostMessage(FFormHandle, FMessageId, 0, 0);
end;

procedure TVideoMinerStartupOpenController.RestartTimer;
begin
  if FTimer = nil then
    Exit;

  FTimer.Enabled := False;
  if FDelayMs > 0 then
    FTimer.Interval := FDelayMs
  else
    FTimer.Interval := STARTUP_OPEN_DELAY_MS;
  FTimer.Enabled := True;
end;

procedure TVideoMinerStartupOpenController.Stop;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
end;

procedure TVideoMinerStartupOpenController.Cancel;
begin
  Stop;
  FFileName := '';
  FAutoPlay := False;
  FOpenRemembered := False;
  FDelayMs := STARTUP_OPEN_DELAY_MS;
end;

procedure TVideoMinerStartupOpenController.TimerTick(Sender: TObject);
var
  AutoPlay: Boolean;
  FileName: string;
  OpenRemembered: Boolean;
begin
  WriteVideoMinerStartupLog('startup_open_timer begin');
  try
    Stop;

    FileName := FFileName;
    AutoPlay := FAutoPlay;
    OpenRemembered := FOpenRemembered;
    FFileName := '';
    FAutoPlay := False;
    FOpenRemembered := False;

    if OpenRemembered then
    begin
      WriteVideoMinerStartupLog('startup_open_timer mode=remembered');
      if Assigned(FOnSetStatus) then
        FOnSetStatus('Loading last video...');
      if Assigned(FOnOpenRemembered) then
        FOnOpenRemembered;
    end
    else if FileName <> '' then
    begin
      WriteVideoMinerStartupLog('startup_open_timer mode=file file="' +
        ExtractFileName(FileName) + '"');
      if Assigned(FOnSetStatus) then
        FOnSetStatus('Loading video...');
      if Assigned(FOnLoadFile) then
        FOnLoadFile(FileName, AutoPlay);
    end
    else
      WriteVideoMinerStartupLog('startup_open_timer mode=none');
    WriteVideoMinerStartupLog('startup_open_timer done');
  except
    on E: Exception do
      WriteVideoMinerStartupLog('startup_open_timer_exception class="' +
        E.ClassName + '" message="' + E.Message + '"');
  end;
end;

end.
