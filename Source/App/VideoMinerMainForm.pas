unit VideoMinerMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Types,
  System.Diagnostics, System.Math,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls, ActiveX, DropAgent, FFmpegDecoder,
  FFmpegDecoderTypes, ResizeEdges, ShortcutAction, VideoMinerAudioPlayback,
  VideoMinerChapterManager, VideoMinerMediaList, VideoMinerDebugLog,
  VideoMinerMediaOpen, VideoMinerSettings, VideoMinerShortcutBindings,
  VideoMinerOverlay, VideoMinerPlaybackTiming, VideoMinerVideoView,
  VideoMinerWindowChrome;

const
  WM_VM_OPEN_PENDING = WM_APP + 1;

type
  TVideoMinerMainForm = class(TForm)
    PanelTitleBar: TPanel;
    LabelAppTitle: TLabel;
    PanelCloseButton: TPanel;
    LabelCloseButton: TLabel;
    PanelMaximizeButton: TPanel;
    LabelMaximizeButton: TLabel;
    PanelMinimizeButton: TPanel;
    LabelMinimizeButton: TLabel;
    ImagePreview: TImage; // デコードしたフレームを表示する画像領域
    OpenDialogVideo: TOpenDialog; // 読み込む動画ファイルを選択するダイアログ
    TimerPlayback: TTimer; // 再生中に次フレームを読むためのタイマー
    // フォーム生成時にデコーダを用意する
    procedure FormCreate(Sender: TObject);
    // フォーム破棄時にデコーダを解放する
    procedure FormDestroy(Sender: TObject);
    // 再生中に次フレームを順方向デコードする
    procedure TimerPlaybackTimer(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TitleBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure CloseButtonClick(Sender: TObject);
    procedure CloseButtonMouseEnter(Sender: TObject);
    procedure CloseButtonMouseLeave(Sender: TObject);
    procedure MaximizeButtonClick(Sender: TObject);
    procedure MinimizeButtonClick(Sender: TObject);
    procedure CaptionButtonMouseEnter(Sender: TObject);
    procedure CaptionButtonMouseLeave(Sender: TObject);
  private
    FDecoder: TFFmpegDecoder; // 開いた動画を保持するFFmpegデコーダ
    FPreviewDecoder: TFFmpegDecoder;
    FAudioPlayback: TVideoMinerAudioPlayback;
    FMediaList: TVideoMinerMediaList;
    FVideoView: TVideoMinerVideoView;
    FVideoFile: string; // 現在開いている動画ファイル名
    FVideoInfo: TVideoInfo; // 現在開いている動画の基本情報
    FCurrentVideoPositionMs: Integer;
    FSeekPositionMs: Integer;
    FSeekMaxMs: Integer;
    FUpdatingSeek: Boolean; // コードからのシークバー更新中かどうか
    FSeeking: Boolean;
    FSeekGuardTargetMs: Integer;
    FSeekGuardRemaining: Integer;
    FDropAgent: TDropAgent;
    FOleInitialized: Boolean;
    FPendingOpenFiles: TStringList;
    FProcessingOpenQueue: Boolean;
    FPendingRestartPlayback: Boolean;
    FPendingRestartMs: Integer;
    FRestartPlaybackTimer: TTimer;
    FChapterManager: TVideoMinerChapterManager;
    FLoopSegmentEndMs: Integer;
    FLoopSegmentStartMs: Integer;
    FBossMode: Boolean;
    FFullScreen: Boolean;
    FEndAction: TVideoMinerEndAction;
    FNormalWindowBounds: TVideoMinerWindowBounds;
    FShortcuts: TShortcutAction;
    FTitleIcon: TImage;
    FLastInfoUpdateTick: UInt64;
    procedure EnterFullScreen;
    procedure ExitFullScreen;
    procedure InitializeTitleIcon;
    procedure InitializeShortcuts;
    procedure SetCaptionButtonColor(Sender: TObject; Color: TColor);
    procedure AddChapterOverlayClick(Sender: TObject);
    procedure MaybeAutoCheckFrame(PositionMs: Integer);
    procedure CheckOverlayClick(Sender: TObject);
    procedure DeleteChapterOverlayClick(Sender: TObject);
    procedure CycleEndAction;
    procedure EndActionOverlayClick(Sender: TObject);
    procedure ToggleFullScreen;
    procedure TogglePlayPause;
    procedure RefreshChapterOverlay;
    procedure UpdateEndActionButton;
    procedure UpdateMaximizeButton;
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    procedure UpdateNavigationButtons;
    procedure NavigateBy(Delta: Integer);
    procedure NavigateChapterBy(Delta: Integer);
    procedure OpenFromDialog;
    procedure LoadManualChapterState(const FileName: string);
    procedure SaveManualChapterState;
    procedure SaveAudioPlaybackSettings;
    procedure FirstFrameOverlayClick(Sender: TObject);
    procedure FullScreenOverlayClick(Sender: TObject);
    procedure LastFrameOverlayClick(Sender: TObject);
    procedure MuteOverlayClick(Sender: TObject);
    procedure NavigateNextOverlayClick(Sender: TObject);
    procedure NavigatePreviousOverlayClick(Sender: TObject);
    procedure PlayPauseOverlayClick(Sender: TObject);
    procedure PlayFromCurrentPosition;
    procedure SeekBarSeek(Sender: TObject; PositionMs: Integer);
    procedure ShortcutChapterNext;
    procedure ShortcutChapterPrevious;
    procedure ShortcutNavigateNext;
    procedure ShortcutNavigatePrevious;
    procedure ShortcutOpenDialog;
    procedure ShortcutSeekToFirstFrame;
    procedure ShortcutSeekToLastFrame;
    procedure ShortcutToggleMute;
    procedure ShortcutVolumeDown;
    procedure ShortcutVolumeUp;
    procedure SkipBackwardOverlayClick(Sender: TObject);
    procedure SkipForwardOverlayClick(Sender: TObject);
    procedure StopPlayback;
    procedure VolumeOverlayChange(Sender: TObject; VolumePercent: Integer);
    procedure ChangeVolumeBy(DeltaPercent: Integer);
    procedure ConfigureLoopSegment(PositionMs: Integer);
    // 偽装画面の Return ボタンからボスが来たモードを解除する
    procedure BossExitClick(Sender: TObject);
    // マウス往復ジェスチャー成立時にボスが来たモードへ入る
    procedure BossGesture(Sender: TObject);
    // 再生と音声を止め、動画面を偽装画面へ切り替える
    procedure EnterBossMode;
    // 偽装画面を閉じ、通常の動画表示へ戻す
    procedure ExitBossMode;
    function PlaybackActiveOrPending: Boolean;
    function CurrentPlaybackPositionMs: Integer;
    procedure SetTitleBarText(const Text: string);
    procedure SetStatusCaption(const Text: string);
    procedure UpdatePlaybackProgress(PositionMs: Integer);
    procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
    procedure SeekByMs(DeltaMs: Integer);
    procedure SeekToFirstFrame;
    procedure SeekToLastFrame;
    function LastFrameSeekPositionMs: Integer;
    function LoopStartPositionMs: Integer;
    function LoopSegmentEndPositionMs(PositionMs: Integer): Integer;
    function LoopSegmentStartPositionMs(PositionMs: Integer): Integer;
    procedure StartPlaybackAtMs(PositionMs: Integer; FrameAlreadyShown: Boolean = False);
    procedure RestartPlaybackTimer(Sender: TObject);
    function SyncVideoToAudio(var PositionMs: Integer; out ErrorMessage: string): Boolean;
    procedure FinishPlaybackAtEnd;
    procedure QueueOpenAndPlayFile(const FileName: string);
    procedure ProcessOpenQueue;
    procedure WMCopyData(var Message: TWMCopyData); message WM_COPYDATA;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMNCCalcSize(var Message: TMessage); message WM_NCCALCSIZE;
    procedure WMOpenPending(var Message: TMessage); message WM_VM_OPEN_PENDING;
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    // 指定ミリ秒位置のフレームを表示する
    function ShowFrameAtMs(const PositionMs: Integer): Boolean;
    function TryShowFrameNearMs(const PositionMs: Integer; out ShownPositionMs: Integer;
      out ErrorMessage: string): Boolean;
    // 動画情報ラベルを更新する
    procedure UpdateInfoLabel;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    function OpenAndPlayFile(const FileName: string): Boolean;
    function OpenRememberedFile: Boolean;
  end;

var
  VideoMinerForm: TVideoMinerMainForm;

implementation

const
  COPYDATA_OPEN_FILE = $564D0001;
  UI_INFO_UPDATE_INTERVAL_MS = 250;
  SEEK_RESTART_DELAY_MS = 15;
  TITLE_BAR_COLOR = $00171617;
  CLOSE_BUTTON_HOVER_COLOR = $00232323;
  CAPTION_BUTTON_HOVER_COLOR = $00232323;

{$R *.dfm}

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
var
  AudioSettings: TVideoMinerAudioSettings;
begin
  ClearVideoMinerDebugLog('form_create');
  PanelTitleBar.Color := TITLE_BAR_COLOR;
  PanelCloseButton.Color := TITLE_BAR_COLOR;
  PanelMaximizeButton.Color := TITLE_BAR_COLOR;
  PanelMinimizeButton.Color := TITLE_BAR_COLOR;
  InitializeTitleIcon;
  UpdateMaximizeButton;
  FEndAction := LoadEndAction;
  VideoMinerWindowChrome.ApplySavedWindowBounds(Self, FNormalWindowBounds);
  FShortcuts := TShortcutAction.Create;
  InitializeShortcuts;
  FOleInitialized := OleInitialize(nil) >= 0;
  FDecoder := TFFmpegDecoder.Create;
  FPreviewDecoder := TFFmpegDecoder.Create;
  FAudioPlayback := TVideoMinerAudioPlayback.Create;
  FMediaList := TVideoMinerMediaList.Create;
  FChapterManager := TVideoMinerChapterManager.Create;
  FVideoView := TVideoMinerVideoView.Create(ImagePreview);
  TResizeEdgeHelper.AttachEdges(PanelTitleBar, VIDEO_MINER_RESIZE_BORDER,
    [rdTop]);
  TResizeEdgeHelper.AttachEdges(FVideoView.SurfaceControl,
    VIDEO_MINER_RESIZE_BORDER, [rdBottom, rdLeft, rdRight]);
  FVideoView.OnFirstFrameClick := FirstFrameOverlayClick;
  FVideoView.OnBossExitClick := BossExitClick;
  FVideoView.OnBossGesture := BossGesture;
  FVideoView.OnFullScreenClick := FullScreenOverlayClick;
  FVideoView.OnNavigateNextClick := NavigateNextOverlayClick;
  FVideoView.OnNavigatePreviousClick := NavigatePreviousOverlayClick;
  FVideoView.OnPlayPauseClick := PlayPauseOverlayClick;
  FVideoView.OnSeek := SeekBarSeek;
  FVideoView.OnSkipBackwardClick := SkipBackwardOverlayClick;
  FVideoView.OnSkipForwardClick := SkipForwardOverlayClick;
  FVideoView.OnLastFrameClick := LastFrameOverlayClick;
  FVideoView.OnVolumeChange := VolumeOverlayChange;
  FVideoView.OnMuteClick := MuteOverlayClick;
  FVideoView.OnEndActionClick := EndActionOverlayClick;
  FVideoView.OnAddChapterClick := AddChapterOverlayClick;
  FVideoView.OnCheckClick := CheckOverlayClick;
  FVideoView.OnDeleteChapterClick := DeleteChapterOverlayClick;
  FVideoView.CheckEnabled := FChapterManager.CheckEnabled;
  RefreshChapterOverlay;
  UpdateEndActionButton;
  FPendingOpenFiles := TStringList.Create;
  FRestartPlaybackTimer := TTimer.Create(Self);
  FRestartPlaybackTimer.Enabled := False;
  FRestartPlaybackTimer.Interval := SEEK_RESTART_DELAY_MS;
  FRestartPlaybackTimer.OnTimer := RestartPlaybackTimer;
  FCurrentVideoPositionMs := -1;
  FSeekPositionMs := 0;
  FSeekMaxMs := 0;
  FLoopSegmentStartMs := -1;
  FLoopSegmentEndMs := -1;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  AudioSettings := LoadAudioSettings;
  FAudioPlayback.VolumePercent := AudioSettings.VolumePercent;
  FAudioPlayback.Muted := AudioSettings.Muted;
  FVideoView.Muted := FAudioPlayback.Muted;
  if FAudioPlayback.Muted then
    FVideoView.VolumePercent := 0
  else
    FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
  FDropAgent := TDropAgent.Create;
  if FOleInitialized then
  begin
    FDropAgent.AcceptKinds := [dakFiles];
    FDropAgent.OnDropFiles := DropFiles;
    FDropAgent.Attach(Self);
  end;
  SetStatusCaption('No video loaded');
end;

// フォーム破棄時にデコーダを解放する
procedure TVideoMinerMainForm.FormDestroy(Sender: TObject);
begin
  SaveManualChapterState;
  SaveAudioPlaybackSettings;
  TimerPlayback.Enabled := False;
  FVideoView.PlaybackActive := False;
  FRestartPlaybackTimer.Enabled := False;
  FAudioPlayback.Stop;
  FDropAgent.Free;
  FPendingOpenFiles.Free;
  FShortcuts.Free;
  FVideoView.Free;
  FChapterManager.Free;
  FMediaList.Free;
  FAudioPlayback.Free;
  FPreviewDecoder.Free;
  FDecoder.Free;
  FTitleIcon.Free;
  VideoMinerWindowChrome.RestoreAndRememberNormalWindowBoundsForSave(Self,
    FFullScreen, FNormalWindowBounds);
  SaveMainFormBounds(FNormalWindowBounds);
  SaveEndAction(FEndAction);
  if FOleInitialized then
    OleUninitialize;
end;

procedure TVideoMinerMainForm.EnterFullScreen;
var
  FullScreenRect: TRect;
  Monitor: TMonitor;
begin
  if FFullScreen then
    Exit;

  VideoMinerWindowChrome.RememberNormalWindowBounds(Self, FFullScreen,
    FNormalWindowBounds);
  FFullScreen := True;
  if FVideoView <> nil then
    FVideoView.FullScreen := FFullScreen;
  WindowState := wsNormal;
  PanelTitleBar.Visible := False;

  Monitor := Screen.MonitorFromWindow(Handle, mdNearest);
  if Monitor <> nil then
    FullScreenRect := Monitor.BoundsRect
  else
    FullScreenRect := Screen.DesktopRect;

  SetBounds(FullScreenRect.Left, FullScreenRect.Top, FullScreenRect.Width,
    FullScreenRect.Height);
end;

procedure TVideoMinerMainForm.ExitFullScreen;
var
  Bounds: TVideoMinerWindowBounds;
begin
  if not FFullScreen then
    Exit;

  FFullScreen := False;
  if FVideoView <> nil then
    FVideoView.FullScreen := FFullScreen;
  PanelTitleBar.Visible := True;
  WindowState := wsNormal;

  Bounds := FNormalWindowBounds;
  if Bounds.Available then
    SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
  VideoMinerWindowChrome.RememberNormalWindowBounds(Self, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerMainForm.ToggleFullScreen;
begin
  if FFullScreen then
    ExitFullScreen
  else
    EnterFullScreen;
end;

procedure TVideoMinerMainForm.TogglePlayPause;
begin
  if PlaybackActiveOrPending then
    StopPlayback
  else
    PlayFromCurrentPosition;
end;

procedure TVideoMinerMainForm.InitializeTitleIcon;
begin
  if FTitleIcon <> nil then
    Exit;

  FTitleIcon := TImage.Create(Self);
  FTitleIcon.Parent := PanelTitleBar;
  FTitleIcon.Align := alLeft;
  FTitleIcon.Width := PanelTitleBar.Height;
  FTitleIcon.Center := True;
  FTitleIcon.Proportional := True;
  FTitleIcon.Stretch := False;
  FTitleIcon.Transparent := True;
  FTitleIcon.OnMouseDown := TitleBarMouseDown;
  if not Icon.Empty then
    FTitleIcon.Picture.Icon.Assign(Icon)
  else if not Application.Icon.Empty then
    FTitleIcon.Picture.Icon.Assign(Application.Icon);
end;

procedure TVideoMinerMainForm.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  ConfigureBorderlessCreateParams(Params);
end;

function TVideoMinerMainForm.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := (FVideoView <> nil) and
    FVideoView.HandleMouseWheel(Shift, WheelDelta, MousePos);
  if not Result then
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TVideoMinerMainForm.InitializeShortcuts;
var
  Handlers: TVideoMinerShortcutHandlers;
begin
  Handlers.ChapterPrevious := ShortcutChapterPrevious;
  Handlers.ChapterNext := ShortcutChapterNext;
  Handlers.OpenDialog := ShortcutOpenDialog;
  Handlers.NavigatePrevious := ShortcutNavigatePrevious;
  Handlers.NavigateNext := ShortcutNavigateNext;
  Handlers.SeekToFirstFrame := ShortcutSeekToFirstFrame;
  Handlers.SeekToLastFrame := ShortcutSeekToLastFrame;
  Handlers.ToggleFullScreen := ToggleFullScreen;
  Handlers.ToggleMute := ShortcutToggleMute;
  Handlers.TogglePlayPause := TogglePlayPause;
  Handlers.VolumeDown := ShortcutVolumeDown;
  Handlers.VolumeUp := ShortcutVolumeUp;
  RegisterVideoMinerShortcuts(FShortcuts, Handlers);
end;

// 指定ミリ秒位置のフレームを表示する
function TVideoMinerMainForm.ShowFrameAtMs(const PositionMs: Integer): Boolean;
var
  ErrorMessage: string;
  ShownPositionMs: Integer;
begin
  Result := False;
  if (FVideoFile = '') or (FDecoder = nil) then
    Exit;

  if not TryShowFrameNearMs(PositionMs, ShownPositionMs, ErrorMessage) then
  begin
    SetStatusCaption('Failed to decode frame: ' + ErrorMessage);
    Exit;
  end;

  FCurrentVideoPositionMs := ShownPositionMs;
  UpdateInfoLabel;
  Result := True;
end;

procedure TVideoMinerMainForm.TitleBarMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;

  ReleaseCapture;
  SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
end;

procedure TVideoMinerMainForm.CloseButtonClick(Sender: TObject);
begin
  Close;
end;

procedure TVideoMinerMainForm.CloseButtonMouseEnter(Sender: TObject);
begin
  PanelCloseButton.Color := CLOSE_BUTTON_HOVER_COLOR;
end;

procedure TVideoMinerMainForm.CloseButtonMouseLeave(Sender: TObject);
begin
  PanelCloseButton.Color := TITLE_BAR_COLOR;
end;

procedure TVideoMinerMainForm.SetCaptionButtonColor(Sender: TObject; Color: TColor);
var
  Control: TControl;
begin
  if Sender is TPanel then
    TPanel(Sender).Color := Color
  else if Sender is TLabel then
  begin
    Control := TLabel(Sender).Parent;
    if Control is TPanel then
      TPanel(Control).Color := Color;
  end;
end;

procedure TVideoMinerMainForm.CaptionButtonMouseEnter(Sender: TObject);
begin
  SetCaptionButtonColor(Sender, CAPTION_BUTTON_HOVER_COLOR);
end;

procedure TVideoMinerMainForm.CaptionButtonMouseLeave(Sender: TObject);
begin
  SetCaptionButtonColor(Sender, TITLE_BAR_COLOR);
end;

procedure TVideoMinerMainForm.MaximizeButtonClick(Sender: TObject);
begin
  if WindowState = wsMaximized then
    WindowState := wsNormal
  else
    WindowState := wsMaximized;
  UpdateMaximizeButton;
end;

procedure TVideoMinerMainForm.MinimizeButtonClick(Sender: TObject);
begin
  WindowState := wsMinimized;
end;

procedure TVideoMinerMainForm.CycleEndAction;
begin
  case FEndAction of
    eaStop:
      FEndAction := eaLoop;
    eaLoop:
      FEndAction := eaNext;
  else
    FEndAction := eaStop;
  end;
  UpdateEndActionButton;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveEndAction(FEndAction);
end;

procedure TVideoMinerMainForm.EndActionOverlayClick(Sender: TObject);
begin
  CycleEndAction;
end;

procedure TVideoMinerMainForm.AddChapterOverlayClick(Sender: TObject);
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.AddManualChapter(CurrentPlaybackPositionMs, FSeekMaxMs);
  RefreshChapterOverlay;
end;

procedure TVideoMinerMainForm.MaybeAutoCheckFrame(PositionMs: Integer);
var
  Changed: Boolean;
begin
  if (FChapterManager = nil) or (FVideoView = nil) then
    Exit;

  if not FChapterManager.CheckEnabled then
  begin
    FChapterManager.MaybeAutoCheckFrame(PositionMs, False, FSeekMaxMs);
    Exit;
  end;

  Changed := FChapterManager.MaybeAutoCheckFrame(PositionMs,
    FVideoView.CurrentFrameCornersMostlyDark, FSeekMaxMs);
  if Changed then
  begin
    RefreshChapterOverlay;
    ConfigureLoopSegment(CurrentPlaybackPositionMs);
    SaveManualChapterState;
  end;
end;

procedure TVideoMinerMainForm.CheckOverlayClick(Sender: TObject);
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.ToggleCheckEnabled;
  if FVideoView <> nil then
    FVideoView.CheckEnabled := FChapterManager.CheckEnabled;
  RefreshChapterOverlay;
end;

procedure TVideoMinerMainForm.DeleteChapterOverlayClick(Sender: TObject);
begin
  if FChapterManager = nil then
    Exit;

  if not FChapterManager.DeleteNearestManualChapter(CurrentPlaybackPositionMs,
    FSeekMaxMs) then
    Exit;

  RefreshChapterOverlay;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveManualChapterState;
end;

procedure TVideoMinerMainForm.RefreshChapterOverlay;
begin
  if (FVideoView <> nil) and (FChapterManager <> nil) then
    FVideoView.Chapters := FChapterManager.DisplayChapters;
end;

procedure TVideoMinerMainForm.UpdateEndActionButton;
begin
  if FVideoView = nil then
    Exit;

  case FEndAction of
    eaLoop:
      FVideoView.EndActionText := 'Loop';
    eaNext:
      FVideoView.EndActionText := 'Next';
  else
    FVideoView.EndActionText := 'Stop';
  end;
end;

procedure TVideoMinerMainForm.UpdateMaximizeButton;
begin
  if LabelMaximizeButton = nil then
    Exit;

  if WindowState = wsMaximized then
    LabelMaximizeButton.Caption := WideChar($2750)
  else
    LabelMaximizeButton.Caption := WideChar($25A1);
end;

function TVideoMinerMainForm.TryShowFrameNearMs(const PositionMs: Integer;
  out ShownPositionMs: Integer; out ErrorMessage: string): Boolean;
const
  FALLBACK_OFFSETS: array[0..10] of Integer =
    (0, -33, 33, -100, 100, -250, 250, -500, 500, -1000, 1000);
var
  AttemptMs: Integer;
  I: Integer;
  LastErrorMessage: string;
  TriedPositions: array[0..High(FALLBACK_OFFSETS)] of Integer;
  TriedCount: Integer;
  J: Integer;
  AlreadyTried: Boolean;
begin
  Result := False;
  ShownPositionMs := PositionMs;
  ErrorMessage := '';
  LastErrorMessage := '';
  TriedCount := 0;

  for I := Low(FALLBACK_OFFSETS) to High(FALLBACK_OFFSETS) do
  begin
    AttemptMs := PositionMs + FALLBACK_OFFSETS[I];
    if AttemptMs < 0 then
      AttemptMs := 0
    else if AttemptMs > FSeekMaxMs then
      AttemptMs := FSeekMaxMs;

    AlreadyTried := False;
    for J := 0 to TriedCount - 1 do
    begin
      if TriedPositions[J] = AttemptMs then
      begin
        AlreadyTried := True;
        Break;
      end;
    end;
    if AlreadyTried then
      Continue;

    TriedPositions[TriedCount] := AttemptMs;
    Inc(TriedCount);

    if FVideoView.ShowFrameAt(FPreviewDecoder, AttemptMs, LastErrorMessage) then
    begin
      ShownPositionMs := AttemptMs;
      Result := True;
      Exit;
    end;
  end;

  ErrorMessage := LastErrorMessage;
end;

// 動画情報ラベルを更新する
procedure TVideoMinerMainForm.UpdateInfoLabel;
var
  AudioPositionMs: Integer;
  AudioText: string;
  CurrentPositionMs: Integer;
  VideoPositionMs: Integer;
begin
  if FVideoFile = '' then
  begin
    SetStatusCaption('No video loaded');
    FVideoView.SetSeekProgress(0, 0);
    Exit;
  end;

  if FVideoInfo.Audio.Present then
  begin
    AudioText := Format('audio: %d Hz / %d ch / %s',
      [FVideoInfo.Audio.SampleRate, FVideoInfo.Audio.Channels,
       FVideoInfo.Audio.SampleFormatName]);
    if FVideoInfo.Audio.OpenError <> '' then
      AudioText := AudioText + ' / open: ' + FVideoInfo.Audio.OpenError;
  end
  else
    AudioText := 'audio: none';

  CurrentPositionMs := CurrentPlaybackPositionMs;
  VideoPositionMs := FCurrentVideoPositionMs;
  if VideoPositionMs < 0 then
    VideoPositionMs := 0;
  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if AudioPositionMs < 0 then
    AudioPositionMs := 0
  else if AudioPositionMs > FSeekMaxMs then
    AudioPositionMs := FSeekMaxMs;

  Caption := Format('%s (%d/%d) - %.3f/%.3f sec  video %.3f  audio %.3f - %dx%d / %.3f fps / %s',
    [ExtractFileName(FVideoFile), FMediaList.CurrentIndex + 1, FMediaList.Count,
     CurrentPositionMs / 1000, FSeekMaxMs / 1000,
     VideoPositionMs / 1000, AudioPositionMs / 1000,
     FVideoInfo.Width, FVideoInfo.Height, FVideoInfo.Fps, AudioText]);
  SetTitleBarText(Format('%s (%d/%d)', [ExtractFileName(FVideoFile),
    FMediaList.CurrentIndex + 1, FMediaList.Count]));
  FVideoView.SetSeekProgress(CurrentPositionMs, FSeekMaxMs);
  FLastInfoUpdateTick := GetTickCount64;
end;

procedure TVideoMinerMainForm.UpdatePlaybackProgress(PositionMs: Integer);
var
  CurrentTick: UInt64;
begin
  if FVideoView <> nil then
    FVideoView.SetSeekProgress(PositionMs, FSeekMaxMs);

  CurrentTick := GetTickCount64;
  if (FLastInfoUpdateTick = 0) or
     (CurrentTick - FLastInfoUpdateTick >= UI_INFO_UPDATE_INTERVAL_MS) then
    UpdateInfoLabel;
end;

procedure TVideoMinerMainForm.OpenFromDialog;
begin
  OpenDialogVideo.InitialDir := VideoMinerOpenDialogInitialDir(FVideoFile);
  if OpenDialogVideo.Execute then
    LoadVideoFile(OpenDialogVideo.FileName, False);
end;

procedure TVideoMinerMainForm.LoadManualChapterState(const FileName: string);
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.LoadManualChapterState(FileName, FSeekMaxMs);
  RefreshChapterOverlay;
end;

procedure TVideoMinerMainForm.SaveManualChapterState;
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.SaveManualChapterState(FVideoFile, FSeekMaxMs);
end;

procedure TVideoMinerMainForm.SaveAudioPlaybackSettings;
var
  Settings: TVideoMinerAudioSettings;
begin
  if FAudioPlayback = nil then
    Exit;

  Settings.Muted := FAudioPlayback.Muted;
  Settings.VolumePercent := FAudioPlayback.VolumePercent;
  SaveAudioSettings(Settings);
end;

function TVideoMinerMainForm.PlaybackActiveOrPending: Boolean;
begin
  Result := TimerPlayback.Enabled or FPendingRestartPlayback or
    ((FRestartPlaybackTimer <> nil) and FRestartPlaybackTimer.Enabled);
end;

function TVideoMinerMainForm.CurrentPlaybackPositionMs: Integer;
begin
  if PlaybackActiveOrPending then
    Result := FAudioPlayback.PlaybackPositionMs
  else
    Result := FSeekPositionMs;

  if Result < 0 then
  begin
    if FCurrentVideoPositionMs >= 0 then
      Result := FCurrentVideoPositionMs
    else
      Result := FSeekPositionMs;
  end;

  if Result < 0 then
    Result := 0
  else if Result > FSeekMaxMs then
    Result := FSeekMaxMs;
end;

procedure TVideoMinerMainForm.SetStatusCaption(const Text: string);
begin
  if Text = '' then
  begin
    Caption := 'VideoMiner'
  end
  else
  begin
    Caption := 'VideoMiner - ' + Text;
  end;
  SetTitleBarText(Caption);
end;

procedure TVideoMinerMainForm.SetTitleBarText(const Text: string);
begin
  if LabelAppTitle <> nil then
    LabelAppTitle.Caption := Text;
end;

function TVideoMinerMainForm.LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
var
  ErrorMessage: string;
  OpenResult: TVideoMinerMediaOpenResult;
begin
  Result := False;

  if not ValidateVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
    SetStatusCaption(ErrorMessage);
    Exit;
  end;

  SaveManualChapterState;

  TimerPlayback.Enabled := False;
  FRestartPlaybackTimer.Enabled := False;
  FAudioPlayback.Stop;
  FPreviewDecoder.Close;
  FSeeking := False;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FCurrentVideoPositionMs := -1;
  FSeekGuardRemaining := 0;
  FLoopSegmentStartMs := -1;
  FLoopSegmentEndMs := -1;
  FChapterManager.Clear;
  FVideoView.Clear;
  RefreshChapterOverlay;

  FUpdatingSeek := True;
  try
    FSeekPositionMs := 0;
    FSeekMaxMs := 0;
  finally
    FUpdatingSeek := False;
  end;

  if not OpenVideoMinerMediaFile(FileName, FDecoder, FPreviewDecoder,
    FMediaList, OpenResult) then
  begin
    FVideoFile := '';
    FVideoView.PlaybackActive := False;
    Caption := 'VideoMiner';
    SetTitleBarText(Caption);
    UpdateNavigationButtons;
    SetStatusCaption(OpenResult.ErrorMessage);
    Exit;
  end;

  FVideoInfo := OpenResult.Info;
  FVideoFile := OpenResult.FileName;
  Caption := Format('%s (%d/%d)', [ExtractFileName(FVideoFile),
    FMediaList.CurrentIndex + 1, FMediaList.Count]);
  SetTitleBarText(Caption);

  FUpdatingSeek := True;
  try
    FSeekMaxMs := Round(FVideoInfo.DurationSec * 1000);
    FSeekPositionMs := 0;
  finally
    FUpdatingSeek := False;
  end;

  TimerPlayback.Interval := VideoMinerTimerIntervalMs(FVideoInfo.Fps);

  LoadManualChapterState(FVideoFile);
  UpdateNavigationButtons;
  UpdateInfoLabel;
  RefreshChapterOverlay;
  ShowFrameAtMs(0);

  if AutoPlay then
    PlayFromCurrentPosition;

  RememberVideoMinerMediaFile(FileName);
  Result := True;
end;

function TVideoMinerMainForm.OpenAndPlayFile(const FileName: string): Boolean;
begin
  Result := LoadVideoFile(FileName, True);
end;

function TVideoMinerMainForm.OpenRememberedFile: Boolean;
var
  ErrorMessage: string;
  FileName: string;
begin
  Result := False;

  if not ResolveRememberedVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
    if ErrorMessage <> '' then
      SetStatusCaption(ErrorMessage);
    Exit;
  end;

  Result := LoadVideoFile(FileName, False);
end;

procedure TVideoMinerMainForm.DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
begin
  if Length(FileNames) > 0 then
    OpenAndPlayFile(FileNames[0]);
end;

procedure TVideoMinerMainForm.PlayFromCurrentPosition;
begin
  if FVideoFile = '' then
    Exit;

  if FSeekPositionMs >= FSeekMaxMs then
  begin
    FUpdatingSeek := True;
    try
      FSeekPositionMs := 0;
    finally
      FUpdatingSeek := False;
    end;
    ShowFrameAtMs(0);
  end;

  StartPlaybackAtMs(FSeekPositionMs);
end;

procedure TVideoMinerMainForm.PlayPauseOverlayClick(Sender: TObject);
begin
  if PlaybackActiveOrPending then
    StopPlayback
  else
    PlayFromCurrentPosition;
end;

procedure TVideoMinerMainForm.FirstFrameOverlayClick(Sender: TObject);
begin
  SeekToFirstFrame;
end;

procedure TVideoMinerMainForm.LastFrameOverlayClick(Sender: TObject);
begin
  SeekToLastFrame;
end;

procedure TVideoMinerMainForm.NavigatePreviousOverlayClick(Sender: TObject);
begin
  NavigateBy(-1);
end;

procedure TVideoMinerMainForm.NavigateNextOverlayClick(Sender: TObject);
begin
  NavigateBy(1);
end;

procedure TVideoMinerMainForm.SkipBackwardOverlayClick(Sender: TObject);
begin
  SeekByMs(-10000);
end;

procedure TVideoMinerMainForm.SeekBarSeek(Sender: TObject; PositionMs: Integer);
begin
  SeekToMs(PositionMs);
end;

procedure TVideoMinerMainForm.FullScreenOverlayClick(Sender: TObject);
begin
  ToggleFullScreen;
end;

procedure TVideoMinerMainForm.ShortcutOpenDialog;
begin
  OpenFromDialog;
end;

procedure TVideoMinerMainForm.ShortcutChapterPrevious;
begin
  NavigateChapterBy(-1);
end;

procedure TVideoMinerMainForm.ShortcutChapterNext;
begin
  NavigateChapterBy(1);
end;

procedure TVideoMinerMainForm.ShortcutNavigatePrevious;
begin
  NavigateBy(-1);
end;

procedure TVideoMinerMainForm.ShortcutNavigateNext;
begin
  NavigateBy(1);
end;

procedure TVideoMinerMainForm.ShortcutSeekToFirstFrame;
begin
  SeekToFirstFrame;
end;

procedure TVideoMinerMainForm.ShortcutSeekToLastFrame;
begin
  SeekToLastFrame;
end;

procedure TVideoMinerMainForm.ShortcutVolumeUp;
begin
  ChangeVolumeBy(5);
end;

procedure TVideoMinerMainForm.ShortcutVolumeDown;
begin
  ChangeVolumeBy(-5);
end;

procedure TVideoMinerMainForm.ShortcutToggleMute;
begin
  FAudioPlayback.Muted := not FAudioPlayback.Muted;
  FVideoView.Muted := FAudioPlayback.Muted;
  if FAudioPlayback.Muted then
    FVideoView.VolumePercent := 0
  else
    FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
  SaveAudioPlaybackSettings;
end;

procedure TVideoMinerMainForm.MuteOverlayClick(Sender: TObject);
begin
  ShortcutToggleMute;
end;

procedure TVideoMinerMainForm.SkipForwardOverlayClick(Sender: TObject);
begin
  SeekByMs(10000);
end;

procedure TVideoMinerMainForm.ChangeVolumeBy(DeltaPercent: Integer);
begin
  FAudioPlayback.Muted := False;
  FVideoView.Muted := FAudioPlayback.Muted;
  FAudioPlayback.VolumePercent := Max(0,
    Min(100, FAudioPlayback.VolumePercent + DeltaPercent));
  FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
  SaveAudioPlaybackSettings;
end;

procedure TVideoMinerMainForm.VolumeOverlayChange(Sender: TObject;
  VolumePercent: Integer);
begin
  FAudioPlayback.Muted := False;
  FVideoView.Muted := FAudioPlayback.Muted;
  FAudioPlayback.VolumePercent := VolumePercent;
  FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
  SaveAudioPlaybackSettings;
end;

procedure TVideoMinerMainForm.BossGesture(Sender: TObject);
begin
  EnterBossMode;
end;

procedure TVideoMinerMainForm.BossExitClick(Sender: TObject);
begin
  ExitBossMode;
end;

procedure TVideoMinerMainForm.EnterBossMode;
begin
  if FBossMode then
    Exit;

  StopPlayback;
  FBossMode := True;
  if FVideoView <> nil then
    FVideoView.BossMode := True;
  PanelTitleBar.Visible := False;
  SetFocus;
end;

procedure TVideoMinerMainForm.ExitBossMode;
begin
  if not FBossMode then
    Exit;

  FBossMode := False;
  if FVideoView <> nil then
    FVideoView.BossMode := False;
  PanelTitleBar.Visible := not FFullScreen;
  SetFocus;
end;

// 再生を停止する
procedure TVideoMinerMainForm.StopPlayback;
begin
  TimerPlayback.Enabled := False;
  FVideoView.PlaybackActive := False;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FRestartPlaybackTimer.Enabled := False;
  FAudioPlayback.StopOutput;
  UpdateInfoLabel;
end;

// 再生中に次フレームを順方向デコードする
procedure TVideoMinerMainForm.TimerPlaybackTimer(Sender: TObject);
var
  ErrorMessage: string;
  PositionMs: Integer;
  AudioPositionMs: Integer;
  LagMs: Integer;
  DropCount: Integer;
  DropWatch: TStopwatch;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  PumpMs: Double;
  DecodeMs: Double;
  SyncMs: Double;
  ConvertFrame: Boolean;
  DidSeekToAudio: Boolean;
  DebugLogEnabled: Boolean;
  GuardingSeek: Boolean;
  UseScratchFrame: Boolean;
begin
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  if DebugLogEnabled then
    TotalWatch := TStopwatch.StartNew;
  PumpMs := 0;
  DecodeMs := 0;
  SyncMs := 0;

  if FSeeking then
    Exit;

  if (FVideoFile = '') or (FDecoder = nil) then
  begin
    TimerPlayback.Enabled := False;
    FVideoView.PlaybackActive := False;
    Exit;
  end;

  if DebugLogEnabled then
    StepWatch := TStopwatch.StartNew;
  if not FAudioPlayback.Pump(ErrorMessage) then
  begin
    SetStatusCaption('Failed to play audio: ' + ErrorMessage);
    Exit;
  end;
  if DebugLogEnabled then
    PumpMs := StepWatch.Elapsed.TotalMilliseconds;

  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if AudioPositionMs > FSeekMaxMs then
    AudioPositionMs := FSeekMaxMs;

  PositionMs := -1;
  DropCount := 0;
  DropWatch := TStopwatch.StartNew;
  DidSeekToAudio := False;
  repeat
    ConvertFrame := True;
    GuardingSeek := FSeekGuardRemaining > 0;
    if GuardingSeek then
      ConvertFrame := False;

    if VideoMinerVideoLagsAudio(FCurrentVideoPositionMs, AudioPositionMs) then
    begin
      if VideoMinerShouldDropFrame(FCurrentVideoPositionMs, AudioPositionMs,
        DropCount, DropWatch.ElapsedMilliseconds) then
      begin
        ConvertFrame := False;
        Inc(DropCount);
      end
      else
      begin
        if FVideoView.ShowFrameAt(FDecoder, AudioPositionMs, ErrorMessage) then
        begin
          PositionMs := AudioPositionMs;
          FCurrentVideoPositionMs := AudioPositionMs;
          DidSeekToAudio := True;
          Break;
        end;

        if VideoMinerNearEnd(FSeekMaxMs, AudioPositionMs) then
        begin
          ErrorMessage := '';
          PositionMs := AudioPositionMs;
          FCurrentVideoPositionMs := AudioPositionMs;
          DidSeekToAudio := True;
          Break;
        end;

        SetStatusCaption('Failed to sync video: ' + ErrorMessage);
        Exit;
      end;
    end;

    UseScratchFrame := ConvertFrame and (AudioPositionMs < 0);

    if DebugLogEnabled then
      StepWatch := TStopwatch.StartNew;
    if UseScratchFrame then
    begin
      if not FVideoView.DecodeNextFrameToScratch(FDecoder, PositionMs,
        ErrorMessage) then
      begin
        TimerPlayback.Enabled := False;
        FVideoView.PlaybackActive := False;
        FAudioPlayback.StopOutput;
        if ErrorMessage = 'End of stream.' then
          FinishPlaybackAtEnd
        else
          SetStatusCaption('Failed to decode next frame: ' + ErrorMessage);
        Exit;
      end;
    end
    else if not FVideoView.DecodeNextFrame(FDecoder, ConvertFrame, PositionMs,
      ErrorMessage) then
    begin
      TimerPlayback.Enabled := False;
      FVideoView.PlaybackActive := False;
      FAudioPlayback.StopOutput;
      if ErrorMessage = 'End of stream.' then
        FinishPlaybackAtEnd
      else
        SetStatusCaption('Failed to decode next frame: ' + ErrorMessage);
      Exit;
    end;
    if DebugLogEnabled then
      DecodeMs := DecodeMs + StepWatch.Elapsed.TotalMilliseconds;

    if UseScratchFrame and
       VideoMinerBackwardScratchFrame(PositionMs, FCurrentVideoPositionMs) then
    begin
      if DebugLogEnabled then
        WriteVideoMinerDebugLog(Format(
          'playback_backward_drop file="%s" current_ms=%d decoded_ms=%d',
          [ExtractFileName(FVideoFile), FCurrentVideoPositionMs, PositionMs]));
      ConvertFrame := False;
      Continue;
    end;

    if GuardingSeek and (PositionMs >= 0) then
    begin
      Dec(FSeekGuardRemaining);
      if not VideoMinerSeekGuardAccepts(FSeekGuardTargetMs, PositionMs) then
      begin
        if DebugLogEnabled then
          WriteVideoMinerDebugLog(Format(
            'seek_guard_drop file="%s" target_ms=%d decoded_ms=%d remaining=%d',
            [ExtractFileName(FVideoFile), FSeekGuardTargetMs, PositionMs,
             FSeekGuardRemaining]));

        if FSeekGuardRemaining <= 0 then
        begin
          if FVideoView.ShowFrameAt(FDecoder, FSeekGuardTargetMs,
            ErrorMessage) then
          begin
            PositionMs := FSeekGuardTargetMs;
            FCurrentVideoPositionMs := FSeekGuardTargetMs;
            DidSeekToAudio := True;
            Break;
          end;

          SetStatusCaption('Failed to guard seek frame: ' + ErrorMessage);
          Exit;
        end;

        Continue;
      end;

      FSeekGuardRemaining := 0;
      if not FVideoView.ShowFrameAt(FDecoder, PositionMs, ErrorMessage) then
      begin
        SetStatusCaption('Failed to present guarded frame: ' + ErrorMessage);
        Exit;
      end;
      ConvertFrame := True;
    end;

    if UseScratchFrame then
    begin
      if not FVideoView.PresentScratchFrame(ErrorMessage) then
      begin
        SetStatusCaption('Failed to present next frame: ' + ErrorMessage);
        Exit;
      end;
      ConvertFrame := True;
    end;

    if PositionMs >= 0 then
      FCurrentVideoPositionMs := PositionMs;
  until ConvertFrame;

  if DebugLogEnabled then
    StepWatch := TStopwatch.StartNew;
  if (not DidSeekToAudio) and (not SyncVideoToAudio(PositionMs, ErrorMessage)) then
  begin
    SetStatusCaption('Failed to sync video: ' + ErrorMessage);
    Exit;
  end;
  if DebugLogEnabled then
    SyncMs := StepWatch.Elapsed.TotalMilliseconds;

  if (FEndAction = eaLoop) and (FLoopSegmentStartMs >= 0) and
     (FLoopSegmentEndMs > FLoopSegmentStartMs) and
     (FCurrentVideoPositionMs >= FLoopSegmentEndMs) then
  begin
    SeekToMs(FLoopSegmentStartMs);
    Exit;
  end;

  if PositionMs >= 0 then
  begin
    FUpdatingSeek := True;
    try
      if AudioPositionMs >= 0 then
        FSeekPositionMs := AudioPositionMs
      else if PositionMs > FSeekMaxMs then
        FSeekPositionMs := FSeekMaxMs
      else
        FSeekPositionMs := PositionMs;
    finally
      FUpdatingSeek := False;
    end;
  end;

  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if (AudioPositionMs >= 0) and (PositionMs >= 0) then
    LagMs := AudioPositionMs - PositionMs
  else
    LagMs := 0;
  UpdatePlaybackProgress(FSeekPositionMs);
  MaybeAutoCheckFrame(FCurrentVideoPositionMs);
  if DebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'playback_tick file="%s" audio_ms=%d video_ms=%d lag_ms=%d drop_count=%d seek_to_audio=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f timer_interval=%d',
      [ExtractFileName(FVideoFile), AudioPositionMs, PositionMs, LagMs, DropCount,
       BoolToStr(DidSeekToAudio, True), PumpMs, DecodeMs, SyncMs,
       TotalWatch.Elapsed.TotalMilliseconds, TimerPlayback.Interval]));
end;


procedure TVideoMinerMainForm.UpdateNavigationButtons;
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

procedure TVideoMinerMainForm.NavigateBy(Delta: Integer);
var
  FileName: string;
begin
  FileName := FMediaList.NavigateFile(Delta);
  if FileName = '' then
  begin
    UpdateNavigationButtons;
    Exit;
  end;

  LoadVideoFile(FileName, True);
end;

procedure TVideoMinerMainForm.NavigateChapterBy(Delta: Integer);
var
  TargetMs: Integer;
begin
  if (FChapterManager = nil) or (Delta = 0) or (FSeekMaxMs <= 0) then
    Exit;

  TargetMs := FChapterManager.FindNavigationTarget(Delta,
    CurrentPlaybackPositionMs, LastFrameSeekPositionMs);
  if TargetMs >= 0 then
    SeekToMs(TargetMs);
end;

procedure TVideoMinerMainForm.SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean);
var
  ErrorMessage: string;
  ShownPositionMs: Integer;
  TargetMs: Integer;
  WasPlaying: Boolean;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  StopMs: Double;
  PreviewMs: Double;
begin
  if (FVideoFile = '') or (FSeekMaxMs <= 0) then
    Exit;

  TotalWatch := TStopwatch.StartNew;

  WasPlaying := PlaybackActiveOrPending;
  StepWatch := TStopwatch.StartNew;
  FAudioPlayback.SilenceOutput;
  TimerPlayback.Enabled := False;
  FRestartPlaybackTimer.Enabled := False;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FAudioPlayback.StopOutput;
  StopMs := StepWatch.Elapsed.TotalMilliseconds;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > FSeekMaxMs then
    TargetMs := FSeekMaxMs;

  WriteVideoMinerDebugLog(Format('seek target_ms=%d was_playing=%s',
    [TargetMs, BoolToStr(WasPlaying, True)]));

  FSeeking := True;
  try
    StepWatch := TStopwatch.StartNew;
    if not TryShowFrameNearMs(TargetMs, ShownPositionMs, ErrorMessage) then
    begin
      PreviewMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerDebugLog(Format(
        'seek_failed step="preview" target_ms=%d was_playing=%s stop_ms=%.3f preview_ms=%.3f total_ms=%.3f err="%s"',
        [TargetMs, BoolToStr(WasPlaying, True), StopMs, PreviewMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
      SetStatusCaption('Failed to decode frame: ' + ErrorMessage);
      Exit;
    end;
    PreviewMs := StepWatch.Elapsed.TotalMilliseconds;

    FCurrentVideoPositionMs := ShownPositionMs;
    FUpdatingSeek := True;
    try
      FSeekPositionMs := ShownPositionMs;
    finally
      FUpdatingSeek := False;
    end;

    UpdateInfoLabel;
    FSeekGuardTargetMs := ShownPositionMs;
    FSeekGuardRemaining := 3;
  finally
    FSeeking := False;
  end;

  if ResumeIfPlaying and WasPlaying and (ShownPositionMs < FSeekMaxMs) then
  begin
    FPendingRestartPlayback := True;
    FPendingRestartMs := ShownPositionMs;
    FRestartPlaybackTimer.Enabled := False;
    FRestartPlaybackTimer.Enabled := True;
  end;

  WriteVideoMinerDebugLog(Format(
    'seek_done target_ms=%d shown_ms=%d was_playing=%s resume=%s stop_ms=%.3f preview_ms=%.3f total_ms=%.3f',
    [TargetMs, ShownPositionMs, BoolToStr(WasPlaying, True),
     BoolToStr(ResumeIfPlaying and WasPlaying and (ShownPositionMs < FSeekMaxMs), True),
     StopMs, PreviewMs, TotalWatch.Elapsed.TotalMilliseconds]));
end;

procedure TVideoMinerMainForm.SeekByMs(DeltaMs: Integer);
var
  BaseMs: Integer;
  TargetMs: Integer;
begin
  BaseMs := CurrentPlaybackPositionMs;
  TargetMs := BaseMs + DeltaMs;
  if TargetMs <= 0 then
    SeekToFirstFrame
  else if TargetMs >= FSeekMaxMs then
    SeekToLastFrame
  else
    SeekToMs(TargetMs);
end;

procedure TVideoMinerMainForm.SeekToFirstFrame;
begin
  SeekToMs(0);
end;

procedure TVideoMinerMainForm.SeekToLastFrame;
begin
  SeekToMs(LastFrameSeekPositionMs, False);
end;

function TVideoMinerMainForm.LastFrameSeekPositionMs: Integer;
begin
  Result := VideoMinerLastFrameSeekPositionMs(FSeekMaxMs, FVideoInfo.Fps);
end;

function TVideoMinerMainForm.LoopStartPositionMs: Integer;
begin
  if FChapterManager = nil then
    Result := 0
  else
    Result := FChapterManager.LoopStartPositionMs(LastFrameSeekPositionMs);
end;

function TVideoMinerMainForm.LoopSegmentStartPositionMs(PositionMs: Integer): Integer;
begin
  if FChapterManager = nil then
    Result := 0
  else
    Result := FChapterManager.LoopSegmentStartPositionMs(PositionMs,
      LastFrameSeekPositionMs);
end;

function TVideoMinerMainForm.LoopSegmentEndPositionMs(PositionMs: Integer): Integer;
begin
  Result := LastFrameSeekPositionMs;
  if FChapterManager <> nil then
    Result := FChapterManager.LoopSegmentEndPositionMs(PositionMs,
      LastFrameSeekPositionMs);
end;

procedure TVideoMinerMainForm.ConfigureLoopSegment(PositionMs: Integer);
begin
  if (FEndAction <> eaLoop) or (FSeekMaxMs <= 0) then
  begin
    FLoopSegmentStartMs := -1;
    FLoopSegmentEndMs := -1;
    Exit;
  end;

  FLoopSegmentStartMs := LoopSegmentStartPositionMs(PositionMs);
  FLoopSegmentEndMs := LoopSegmentEndPositionMs(PositionMs);
  if FLoopSegmentEndMs <= FLoopSegmentStartMs then
    FLoopSegmentEndMs := LastFrameSeekPositionMs;
end;

procedure TVideoMinerMainForm.StartPlaybackAtMs(PositionMs: Integer;
  FrameAlreadyShown: Boolean);
var
  ErrorMessage: string;
  OpenInfo: TVideoInfo;
  ReuseErrorMessage: string;
  TargetMs: Integer;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  VideoPrepareMs: Double;
  VideoSeekMs: Double;
  AudioStartMs: Double;
  VideoReopened: Boolean;
begin
  if FVideoFile = '' then
    Exit;

  TotalWatch := TStopwatch.StartNew;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > FSeekMaxMs then
    TargetMs := FSeekMaxMs;

  WriteVideoMinerDebugLog(Format(
    'start_playback file="%s" requested_ms=%d target_ms=%d frame_already_shown=%s',
    [ExtractFileName(FVideoFile), PositionMs, TargetMs,
     BoolToStr(FrameAlreadyShown, True)]));

  VideoPrepareMs := 0;
  VideoReopened := False;

  StepWatch := TStopwatch.StartNew;
  if not FVideoView.ShowFrameAt(FDecoder, TargetMs, ReuseErrorMessage,
    not FrameAlreadyShown) then
  begin
    VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
    WriteVideoMinerDebugLog(Format(
      'start_playback_reuse_failed file="%s" target_ms=%d video_seek_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FVideoFile), TargetMs, VideoSeekMs,
       TotalWatch.Elapsed.TotalMilliseconds, ReuseErrorMessage]));

    StepWatch := TStopwatch.StartNew;
    FDecoder.Close;
    if not FDecoder.Open(FVideoFile, OpenInfo, ErrorMessage) then
    begin
      VideoPrepareMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerDebugLog(Format(
        'start_playback_failed step="video_open_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(FVideoFile), TargetMs, VideoPrepareMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
      FVideoView.PlaybackActive := False;
      SetStatusCaption('Failed to reopen video decoder: ' + ErrorMessage);
      Exit;
    end;
    VideoPrepareMs := StepWatch.Elapsed.TotalMilliseconds;
    VideoReopened := True;

    StepWatch := TStopwatch.StartNew;
    if not FVideoView.ShowFrameAt(FDecoder, TargetMs, ErrorMessage,
      not FrameAlreadyShown) then
    begin
      VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerDebugLog(Format(
        'start_playback_failed step="video_seek_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(FVideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
      FVideoView.PlaybackActive := False;
      SetStatusCaption('Failed to seek video decoder: ' + ErrorMessage);
      Exit;
    end;
  end;
  VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
  FCurrentVideoPositionMs := TargetMs;
  FSeekPositionMs := TargetMs;
  ConfigureLoopSegment(TargetMs);

  StepWatch := TStopwatch.StartNew;
  if not FAudioPlayback.StartAt(FVideoFile, FVideoInfo, TargetMs,
    ErrorMessage) then
  begin
    AudioStartMs := StepWatch.Elapsed.TotalMilliseconds;
    WriteVideoMinerDebugLog(Format(
      'start_playback_failed step="audio_start" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FVideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
       AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    FVideoView.PlaybackActive := False;
    SetStatusCaption('Failed to start audio playback: ' + ErrorMessage);
    Exit;
  end;
  AudioStartMs := StepWatch.Elapsed.TotalMilliseconds;

  FSeekGuardTargetMs := TargetMs;
  FSeekGuardRemaining := VideoMinerDefaultSeekGuardFrames;
  TimerPlayback.Enabled := True;
  FVideoView.PlaybackActive := True;
  WriteVideoMinerDebugLog(Format(
    'start_playback_done file="%s" target_ms=%d frame_already_shown=%s video_reopen=%s video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f',
    [ExtractFileName(FVideoFile), TargetMs, BoolToStr(FrameAlreadyShown, True),
     BoolToStr(VideoReopened, True), VideoPrepareMs, VideoSeekMs,
     AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds]));
end;

function TVideoMinerMainForm.SyncVideoToAudio(var PositionMs: Integer;
  out ErrorMessage: string): Boolean;
var
  AudioPositionMs: Integer;
begin
  ErrorMessage := '';
  Result := True;

  if PositionMs < 0 then
    Exit;

  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if AudioPositionMs < 0 then
    Exit;

  if AudioPositionMs > FSeekMaxMs then
    AudioPositionMs := FSeekMaxMs;

  if not VideoMinerShouldSeekVideoToAudio(PositionMs, AudioPositionMs) then
    Exit;

  Result := FVideoView.ShowFrameAt(FDecoder, AudioPositionMs, ErrorMessage);
  if Result then
  begin
    PositionMs := AudioPositionMs;
    FCurrentVideoPositionMs := AudioPositionMs;
  end;
  if (not Result) and
     VideoMinerNearEnd(FSeekMaxMs, AudioPositionMs) then
  begin
    ErrorMessage := '';
    PositionMs := AudioPositionMs;
    FCurrentVideoPositionMs := AudioPositionMs;
    Result := True;
  end;
end;

procedure TVideoMinerMainForm.FinishPlaybackAtEnd;
var
  FrameShown: Boolean;
  LoopStartMs: Integer;
begin
  case FEndAction of
    eaLoop:
      begin
        LoopStartMs := LoopStartPositionMs;
        FUpdatingSeek := True;
        try
          FSeekPositionMs := LoopStartMs;
        finally
          FUpdatingSeek := False;
        end;
        FrameShown := ShowFrameAtMs(LoopStartMs);
        StartPlaybackAtMs(LoopStartMs, FrameShown);
        Exit;
      end;
    eaNext:
      begin
        if (FMediaList <> nil) and FMediaList.CanNavigate(1) then
        begin
          NavigateBy(1);
          Exit;
        end;
      end;
  end;

  FUpdatingSeek := True;
  try
    FSeekPositionMs := FSeekMaxMs;
  finally
    FUpdatingSeek := False;
  end;
  FVideoView.PlaybackActive := False;
  UpdateInfoLabel;
end;

procedure TVideoMinerMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and FBossMode then
  begin
    ExitBossMode;
    Key := 0;
    Exit;
  end;

  if FBossMode then
  begin
    Key := 0;
    Exit;
  end;

  if (Key = VK_ESCAPE) and FFullScreen then
  begin
    ExitFullScreen;
    Key := 0;
    Exit;
  end;

  if (FShortcuts <> nil) and FShortcuts.KeyDown(Key, Shift) then
    Exit;
end;

procedure TVideoMinerMainForm.QueueOpenAndPlayFile(const FileName: string);
begin
  if FileName = '' then
    Exit;

  FPendingOpenFiles.Add(FileName);
  PostMessage(Handle, WM_VM_OPEN_PENDING, 0, 0);
end;

procedure TVideoMinerMainForm.ProcessOpenQueue;
var
  FileName: string;
begin
  if FProcessingOpenQueue then
    Exit;

  FProcessingOpenQueue := True;
  try
    while FPendingOpenFiles.Count > 0 do
    begin
      FileName := FPendingOpenFiles[0];
      FPendingOpenFiles.Delete(0);
      OpenAndPlayFile(FileName);
    end;
  finally
    FProcessingOpenQueue := False;
  end;
end;

procedure TVideoMinerMainForm.WMOpenPending(var Message: TMessage);
begin
  ProcessOpenQueue;
  Message.Result := 1;
end;

procedure TVideoMinerMainForm.RestartPlaybackTimer(Sender: TObject);
var
  TargetMs: Integer;
begin
  FRestartPlaybackTimer.Enabled := False;

  if not FPendingRestartPlayback then
    Exit;

  FPendingRestartPlayback := False;
  TargetMs := FPendingRestartMs;
  FPendingRestartMs := -1;

  if (FVideoFile = '') or (TargetMs < 0) or (TargetMs >= FSeekMaxMs) then
    Exit;

  WriteVideoMinerDebugLog(Format('restart_playback target_ms=%d', [TargetMs]));
  StartPlaybackAtMs(TargetMs, True);
end;

procedure TVideoMinerMainForm.WMNCHitTest(var Message: TWMNCHitTest);
begin
  inherited;
  HitTestBorderlessResize(Self, FFullScreen, VIDEO_MINER_RESIZE_BORDER,
    Point(Message.XPos, Message.YPos), Message.Result);
end;

procedure TVideoMinerMainForm.WMNCCalcSize(var Message: TMessage);
begin
  inherited;
  HandleBorderlessNCCalcSize(Message);
end;

procedure TVideoMinerMainForm.WMMove(var Message: TWMMove);
begin
  inherited;
  VideoMinerWindowChrome.RememberNormalWindowBounds(Self, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerMainForm.WMSize(var Message: TWMSize);
begin
  inherited;
  UpdateMaximizeButton;
  TResizeEdgeHelper.AdjustEdges(PanelTitleBar);
  if FVideoView <> nil then
    TResizeEdgeHelper.AdjustEdges(FVideoView.SurfaceControl);
  VideoMinerWindowChrome.RememberNormalWindowBounds(Self, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerMainForm.WMCopyData(var Message: TWMCopyData);
var
  FileName: string;
begin
  if (Message.CopyDataStruct <> nil) and
     (Message.CopyDataStruct.dwData = COPYDATA_OPEN_FILE) then
  begin
    if WindowState = wsMinimized then
      WindowState := wsNormal;
    Application.Restore;
    BringToFront;
    SetForegroundWindow(Handle);

    FileName := '';
    if (Message.CopyDataStruct.cbData > SizeOf(Char)) and
       (Message.CopyDataStruct.lpData <> nil) then
      FileName := PChar(Message.CopyDataStruct.lpData);

    if FileName <> '' then
      QueueOpenAndPlayFile(FileName);

    Message.Result := 1;
  end
  else
    inherited;
end;

end.
