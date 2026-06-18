unit VideoMinerCommandController;

// 動画ビュー上の操作、ショートカット、音量操作をアプリ側処理へ橋渡しする。
// 実際の open / seek / navigate / playback 制御は callback へ委譲し、
// メインフォームから overlay click や shortcut 登録の細部を分離する。

interface

uses
  Vcl.ExtCtrls, VideoMinerAudioPlayback, VideoMinerShortcutBindings,
  VideoMinerVideoView, ShortcutAction;

type
  // 引数なしで実行するアプリ側コマンド
  TVideoMinerCommandProc = procedure of object;
  // 現在の再生状態などを問い合わせるアプリ側 callback
  TVideoMinerCommandBoolFunc = function: Boolean of object;
  // 前後移動や相対シークの差分値を渡すコマンド
  TVideoMinerCommandDeltaProc = procedure(Delta: Integer) of object;
  // 指定位置へシークし、必要なら再生状態の復元可否も渡すコマンド
  TVideoMinerCommandSeekProc = procedure(PositionMs: Integer;
    ResumeIfPlaying: Boolean) of object;

  TVideoMinerCommandController = class
  private
    FAudioPlayback             : TVideoMinerAudioPlayback;      // 音量とミュートを操作する再生ラッパ
    FVideoView                 : TVideoMinerVideoView;          // overlay イベントと表示状態を中継する動画ビュー
    FOnChapterNavigate         : TVideoMinerCommandDeltaProc;   // 前後チャプター移動の委譲先
    FOnCopyCurrentFrame        : TVideoMinerCommandProc;        // 現在フレームコピーの委譲先
    FOnNavigate                : TVideoMinerCommandDeltaProc;   // 前後ファイル移動の委譲先
    FOnOpenDialog              : TVideoMinerCommandProc;        // ファイル選択ダイアログ表示の委譲先
    FOnPlaybackActiveOrPending : TVideoMinerCommandBoolFunc;    // 再生中または再開待ちかを問い合わせる委譲先
    FOnPlaybackRateCycle       : TVideoMinerCommandProc;        // 再生速度切り替えの委譲先
    FOnPlayFromCurrentPosition : TVideoMinerCommandProc;        // 現在位置から再生開始する委譲先
    FOnSaveAudioSettings       : TVideoMinerCommandProc;        // 音量/ミュート変更後の設定保存先
    FOnSeekByMs                : TVideoMinerCommandDeltaProc;   // 相対時間シークの委譲先
    FOnSeekToFirstFrame        : TVideoMinerCommandProc;        // 先頭フレーム移動の委譲先
    FOnSeekToLastFrame         : TVideoMinerCommandProc;        // 最終フレーム移動の委譲先
    FOnShowHelp                : TVideoMinerCommandProc;        // show help overlay delegate
    FOnSeekToMs                : TVideoMinerCommandSeekProc;    // 絶対位置シークの委譲先
    FOnStopPlayback            : TVideoMinerCommandProc;        // 再生停止の委譲先
    FOnToggleSafeArea          : TVideoMinerCommandProc;        // 90% セーフエリア確認枠切り替えの委譲先
    FOnToggleFullScreen        : TVideoMinerCommandProc;        // 全画面切り替えの委譲先
    // 音量/ミュート状態を動画ビューの overlay 表示へ反映する
    procedure SyncVolumeToView;
  public
    // 操作対象の音声再生ラッパと動画ビューを受け取る
    constructor Create(AudioPlayback: TVideoMinerAudioPlayback;
      VideoView: TVideoMinerVideoView);
    // 動画ビューの overlay イベントを controller の handler へ接続する
    procedure BindVideoView;
    // VideoMiner 用ショートカットを ShortcutAction へ登録する
    procedure RegisterShortcuts(Shortcuts: TShortcutAction);
    // 現在音量を指定パーセントぶん増減し、ミュートを解除する
    procedure ChangeVolumeBy(DeltaPercent: Integer);
    // 現在フレームコピーをアプリ側へ委譲する
    procedure CopyCurrentFrame;
    // 再生速度の段階切り替えをアプリ側へ委譲する
    procedure CyclePlaybackRate;
    // overlay の先頭フレームボタンから先頭移動を実行する
    procedure FirstFrameClick(Sender: TObject);
    // overlay の全画面ボタンから全画面切り替えを実行する
    procedure FullScreenClick(Sender: TObject);
    // overlay の最終フレームボタンから終端移動を実行する
    procedure LastFrameClick(Sender: TObject);
    // overlay のミュートボタンからミュート状態を切り替える
    procedure MuteClick(Sender: TObject);
    // overlay の次ファイルボタンから次動画へ移動する
    procedure NavigateNextClick(Sender: TObject);
    // overlay の前ファイルボタンから前動画へ移動する
    procedure NavigatePreviousClick(Sender: TObject);
    // ファイル選択ダイアログ表示をアプリ側へ委譲する
    procedure OpenDialog;
    // overlay の再生速度ボタンから速度切り替えを実行する
    procedure PlaybackRateClick(Sender: TObject);
    // overlay の再生/一時停止ボタンから再生状態を切り替える
    procedure PlayPauseClick(Sender: TObject);
    // シークバー操作で指定位置へ移動し、再生中なら再開を許可する
    procedure Seek(Sender: TObject; PositionMs: Integer);
    // ホイールシークで指定位置へ移動し、再生再開は行わない
    procedure SeekByWheel(Sender: TObject; PositionMs: Integer);
    // 先頭フレームへの移動をアプリ側へ委譲する
    procedure SeekToFirstFrame;
    // 最終フレームへの移動をアプリ側へ委譲する
    procedure SeekToLastFrame;
    // ヘルプ表示をアプリ側へ委譲する
    procedure ShowHelp;
    // 次チャプターへのショートカット処理を実行する
    procedure ShortcutChapterNext;
    // 前チャプターへのショートカット処理を実行する
    procedure ShortcutChapterPrevious;
    // 次ファイルへのショートカット処理を実行する
    procedure ShortcutNavigateNext;
    // 前ファイルへのショートカット処理を実行する
    procedure ShortcutNavigatePrevious;
    // overlay の 10 秒戻しボタンから相対シークを実行する
    procedure SkipBackwardClick(Sender: TObject);
    // overlay の 10 秒進みボタンから相対シークを実行する
    procedure SkipForwardClick(Sender: TObject);
    // 全画面切り替えをアプリ側へ委譲する
    procedure ToggleFullScreen;
    // 90% セーフエリア確認枠切り替えをアプリ側へ委譲する
    procedure ToggleSafeArea;
    // ミュート状態を切り替え、表示と設定保存へ反映する
    procedure ToggleMute;
    // 再生中なら停止し、停止中なら現在位置から再生する
    procedure TogglePlayPause;
    // overlay の音量変更を音声再生ラッパへ反映する
    procedure VolumeChange(Sender: TObject; VolumePercent: Integer);
    // 音量を 5% 下げる
    procedure VolumeDown;
    // 音量を 5% 上げる
    procedure VolumeUp;
    property OnChapterNavigate: TVideoMinerCommandDeltaProc read FOnChapterNavigate write FOnChapterNavigate;
    property OnCopyCurrentFrame: TVideoMinerCommandProc read FOnCopyCurrentFrame write FOnCopyCurrentFrame;
    property OnNavigate: TVideoMinerCommandDeltaProc read FOnNavigate write FOnNavigate;
    property OnOpenDialog: TVideoMinerCommandProc read FOnOpenDialog write FOnOpenDialog;
    property OnPlaybackActiveOrPending: TVideoMinerCommandBoolFunc
     read FOnPlaybackActiveOrPending write FOnPlaybackActiveOrPending;
    property OnPlaybackRateCycle: TVideoMinerCommandProc
      read FOnPlaybackRateCycle write FOnPlaybackRateCycle;
    property OnPlayFromCurrentPosition: TVideoMinerCommandProc
      read FOnPlayFromCurrentPosition write FOnPlayFromCurrentPosition;
    property OnSaveAudioSettings: TVideoMinerCommandProc read FOnSaveAudioSettings write FOnSaveAudioSettings;
    property OnSeekByMs: TVideoMinerCommandDeltaProc read FOnSeekByMs write FOnSeekByMs;
    property OnSeekToFirstFrame: TVideoMinerCommandProc read FOnSeekToFirstFrame write FOnSeekToFirstFrame;
    property OnSeekToLastFrame: TVideoMinerCommandProc read FOnSeekToLastFrame write FOnSeekToLastFrame;
    property OnShowHelp: TVideoMinerCommandProc read FOnShowHelp write FOnShowHelp;
    property OnSeekToMs: TVideoMinerCommandSeekProc read FOnSeekToMs write FOnSeekToMs;
    property OnStopPlayback: TVideoMinerCommandProc read FOnStopPlayback write FOnStopPlayback;
    property OnToggleSafeArea: TVideoMinerCommandProc read FOnToggleSafeArea write FOnToggleSafeArea;
    property OnToggleFullScreen: TVideoMinerCommandProc read FOnToggleFullScreen write FOnToggleFullScreen;
  end;

implementation

uses
  System.Math;

constructor TVideoMinerCommandController.Create(
  AudioPlayback: TVideoMinerAudioPlayback; VideoView: TVideoMinerVideoView);
begin
  inherited Create;
  FAudioPlayback := AudioPlayback;
  FVideoView := VideoView;
end;

procedure TVideoMinerCommandController.BindVideoView;
begin
  if FVideoView = nil then
    Exit;

  FVideoView.OnFirstFrameClick := FirstFrameClick;
  FVideoView.OnFullScreenClick := FullScreenClick;
  FVideoView.OnLastFrameClick := LastFrameClick;
  FVideoView.OnMuteClick := MuteClick;
  FVideoView.OnNavigateNextClick := NavigateNextClick;
  FVideoView.OnNavigatePreviousClick := NavigatePreviousClick;
  FVideoView.OnPlaybackRateClick := PlaybackRateClick;
  FVideoView.OnPlayPauseClick := PlayPauseClick;
  FVideoView.OnSeek := Seek;
  FVideoView.OnSeekByWheel := SeekByWheel;
  FVideoView.OnSkipBackwardClick := SkipBackwardClick;
  FVideoView.OnSkipForwardClick := SkipForwardClick;
  FVideoView.OnVolumeChange := VolumeChange;
end;

procedure TVideoMinerCommandController.RegisterShortcuts(
  Shortcuts: TShortcutAction);
var
  Handlers: TVideoMinerShortcutHandlers;
begin
  Handlers.ChapterPrevious := ShortcutChapterPrevious;
  Handlers.ChapterNext := ShortcutChapterNext;
  Handlers.CopyCurrentFrame := CopyCurrentFrame;
  Handlers.OpenDialog := OpenDialog;
  Handlers.NavigatePrevious := ShortcutNavigatePrevious;
  Handlers.NavigateNext := ShortcutNavigateNext;
  Handlers.SeekToFirstFrame := SeekToFirstFrame;
  Handlers.SeekToLastFrame := SeekToLastFrame;
  Handlers.ShowHelp := ShowHelp;
  Handlers.ToggleFullScreen := ToggleFullScreen;
  Handlers.ToggleSafeArea := ToggleSafeArea;
  Handlers.ToggleMute := ToggleMute;
  Handlers.TogglePlayPause := TogglePlayPause;
  Handlers.CyclePlaybackRate := CyclePlaybackRate;
  Handlers.VolumeDown := VolumeDown;
  Handlers.VolumeUp := VolumeUp;
  RegisterVideoMinerShortcuts(Shortcuts, Handlers);
end;

procedure TVideoMinerCommandController.SyncVolumeToView;
begin
  if (FAudioPlayback = nil) or (FVideoView = nil) then
    Exit;

  FVideoView.Muted := FAudioPlayback.Muted;
  if FAudioPlayback.Muted then
    FVideoView.VolumePercent := 0
  else
    FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
end;

procedure TVideoMinerCommandController.ChangeVolumeBy(DeltaPercent: Integer);
begin
  if FAudioPlayback = nil then
    Exit;

  FAudioPlayback.Muted := False;
  FAudioPlayback.VolumePercent := Max(0,
    Min(100, FAudioPlayback.VolumePercent + DeltaPercent));
  SyncVolumeToView;
  if Assigned(FOnSaveAudioSettings) then
    FOnSaveAudioSettings;
end;

procedure TVideoMinerCommandController.CopyCurrentFrame;
begin
  if Assigned(FOnCopyCurrentFrame) then
    FOnCopyCurrentFrame;
end;

procedure TVideoMinerCommandController.CyclePlaybackRate;
begin
  if Assigned(FOnPlaybackRateCycle) then
    FOnPlaybackRateCycle;
end;

procedure TVideoMinerCommandController.FirstFrameClick(Sender: TObject);
begin
  SeekToFirstFrame;
end;

procedure TVideoMinerCommandController.FullScreenClick(Sender: TObject);
begin
  ToggleFullScreen;
end;

procedure TVideoMinerCommandController.LastFrameClick(Sender: TObject);
begin
  SeekToLastFrame;
end;

procedure TVideoMinerCommandController.MuteClick(Sender: TObject);
begin
  ToggleMute;
end;

procedure TVideoMinerCommandController.NavigateNextClick(Sender: TObject);
begin
  ShortcutNavigateNext;
end;

procedure TVideoMinerCommandController.NavigatePreviousClick(Sender: TObject);
begin
  ShortcutNavigatePrevious;
end;

procedure TVideoMinerCommandController.OpenDialog;
begin
  if Assigned(FOnOpenDialog) then
    FOnOpenDialog;
end;

procedure TVideoMinerCommandController.PlaybackRateClick(Sender: TObject);
begin
  CyclePlaybackRate;
end;

procedure TVideoMinerCommandController.PlayPauseClick(Sender: TObject);
begin
  TogglePlayPause;
end;

procedure TVideoMinerCommandController.Seek(Sender: TObject;
  PositionMs: Integer);
begin
  if Assigned(FOnSeekToMs) then
    FOnSeekToMs(PositionMs, True);
end;

procedure TVideoMinerCommandController.SeekByWheel(Sender: TObject;
  PositionMs: Integer);
begin
  if Assigned(FOnSeekToMs) then
    FOnSeekToMs(PositionMs, False);
end;

procedure TVideoMinerCommandController.SeekToFirstFrame;
begin
  if Assigned(FOnSeekToFirstFrame) then
    FOnSeekToFirstFrame;
end;

procedure TVideoMinerCommandController.SeekToLastFrame;
begin
  if Assigned(FOnSeekToLastFrame) then
    FOnSeekToLastFrame;
end;

procedure TVideoMinerCommandController.ShowHelp;
begin
  if Assigned(FOnShowHelp) then
    FOnShowHelp;
end;

procedure TVideoMinerCommandController.ShortcutChapterNext;
begin
  if Assigned(FOnChapterNavigate) then
    FOnChapterNavigate(1);
end;

procedure TVideoMinerCommandController.ShortcutChapterPrevious;
begin
  if Assigned(FOnChapterNavigate) then
    FOnChapterNavigate(-1);
end;

procedure TVideoMinerCommandController.ShortcutNavigateNext;
begin
  if Assigned(FOnNavigate) then
    FOnNavigate(1);
end;

procedure TVideoMinerCommandController.ShortcutNavigatePrevious;
begin
  if Assigned(FOnNavigate) then
    FOnNavigate(-1);
end;

procedure TVideoMinerCommandController.SkipBackwardClick(Sender: TObject);
begin
  if Assigned(FOnSeekByMs) then
    FOnSeekByMs(-10000);
end;

procedure TVideoMinerCommandController.SkipForwardClick(Sender: TObject);
begin
  if Assigned(FOnSeekByMs) then
    FOnSeekByMs(10000);
end;

procedure TVideoMinerCommandController.ToggleFullScreen;
begin
  if Assigned(FOnToggleFullScreen) then
    FOnToggleFullScreen;
end;

procedure TVideoMinerCommandController.ToggleSafeArea;
begin
  if Assigned(FOnToggleSafeArea) then
    FOnToggleSafeArea;
end;
procedure TVideoMinerCommandController.ToggleMute;
begin
  if FAudioPlayback = nil then
    Exit;

  FAudioPlayback.Muted := not FAudioPlayback.Muted;
  SyncVolumeToView;
  if Assigned(FOnSaveAudioSettings) then
    FOnSaveAudioSettings;
end;

procedure TVideoMinerCommandController.TogglePlayPause;
begin
  if Assigned(FOnPlaybackActiveOrPending) and FOnPlaybackActiveOrPending then
  begin
    if Assigned(FOnStopPlayback) then
      FOnStopPlayback;
  end
  else if Assigned(FOnPlayFromCurrentPosition) then
    FOnPlayFromCurrentPosition;
end;

procedure TVideoMinerCommandController.VolumeChange(Sender: TObject;
  VolumePercent: Integer);
begin
  if FAudioPlayback = nil then
    Exit;

  FAudioPlayback.Muted := False;
  FAudioPlayback.VolumePercent := VolumePercent;
  SyncVolumeToView;
  if Assigned(FOnSaveAudioSettings) then
    FOnSaveAudioSettings;
end;

procedure TVideoMinerCommandController.VolumeDown;
begin
  ChangeVolumeBy(-5);
end;

procedure TVideoMinerCommandController.VolumeUp;
begin
  ChangeVolumeBy(5);
end;

end.
