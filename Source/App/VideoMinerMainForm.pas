unit VideoMinerMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Diagnostics, System.Math, System.Types,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls, ActiveX, DropAgent, FFmpegDecoder,
  FFmpegDecoderTypes, FolderWatch, ResizeEdges, ShortcutAction,
  VideoMinerAudioPlayback,
  VideoMinerChapterManager, VideoMinerCommandController, VideoMinerMediaList, VideoMinerDebugLog,
  VideoMinerFrameCheck, VideoMinerMediaOpen, VideoMinerSettings,
  VideoMinerPlaybackController, VideoMinerPlaybackTiming,
  VideoMinerVideoView, VideoMinerWindowChrome, VideoMinerWindowModeController;

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
    // 再生 tick 処理を再生 controller へ委譲する
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
    FRestartPlaybackTimer: TTimer;
    FReloadCurrentFileTimer: TTimer;
    FFolderWatcher: TFolderWatch;
    FWatchedFolder: string;
    FReloadingCurrentFile: Boolean;
    FPendingReloadHasStamp: Boolean;
    FPendingReloadLastWriteTime: TDateTime;
    FPendingReloadSize: Int64;
    FVideoFileLastWriteTime: TDateTime;
    FVideoFileSize: Int64;
    FPlaybackController: TVideoMinerPlaybackController;
    FCommandController: TVideoMinerCommandController;
    FWindowModeController: TVideoMinerWindowModeController;
    FChapterManager: TVideoMinerChapterManager;
    FLoopSegmentEndMs: Integer;
    FLoopSegmentStartMs: Integer;
    FEndAction: TVideoMinerEndAction;
    FShortcuts: TShortcutAction;
    FTitleIcon: TImage;
    FLastInfoUpdateTick: UInt64;
    procedure InitializeTitleIcon;
    procedure SetCaptionButtonColor(Sender: TObject; Color: TColor);
    procedure AddChapterOverlayClick(Sender: TObject);
    procedure MaybeAutoCheckAudio(Sender: TObject; StartSample: Int64;
      const Pcm: TBytes);
    procedure MaybeAutoCheckFrame(PositionMs: Integer);
    procedure CheckOverlayClick(Sender: TObject);
    procedure DeleteChapterOverlayClick(Sender: TObject);
    procedure CycleEndAction;
    procedure CyclePlaybackRate;
    procedure EndActionOverlayClick(Sender: TObject);
    procedure ToggleFullScreen;
    procedure RefreshChapterOverlay;
    procedure UpdateEndActionButton;
    procedure UpdatePlaybackRateButton;
    procedure UpdateMaximizeButton;
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean;
      RestoreLoopPosition: Boolean = True): Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    procedure UpdateNavigationButtons;
    procedure NavigateBy(Delta: Integer);
    procedure NavigateNextPlaybackFile;
    procedure NavigateChapterBy(Delta: Integer);
    procedure OpenFromDialog;
    procedure LoadManualChapterState(const FileName: string);
    procedure SaveManualChapterState;
    procedure SaveLoopPlaybackPosition;
    function TryRestoreLoopPlaybackPosition: Boolean;
    procedure SaveAudioPlaybackSettings;
    procedure PlayFromCurrentPosition;
    procedure StopPlayback;
    procedure ConfigureLoopSegment(PositionMs: Integer);
    // 偽装画面の Return ボタンからボスが来たモードを解除する
    procedure BossExitClick(Sender: TObject);
    // マウス往復ジェスチャー成立時にボスが来たモードへ入る
    procedure BossGesture(Sender: TObject);
    function PlaybackActiveOrPending: Boolean;
    function CurrentPlaybackPositionMs: Integer;
    procedure SetTitleBarText(const Text: string);
    procedure SetStatusCaption(const Text: string);
    procedure UpdatePlaybackProgress(PositionMs: Integer);
    procedure SeekPlaybackTickToMs(PositionMs: Integer);
    procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
    procedure SeekByMs(DeltaMs: Integer);
    procedure SeekToFirstFrame;
    procedure SeekToLastFrame;
    function LastFrameSeekPositionMs: Integer;
    function LoopStartPositionMs: Integer;
    procedure StartPlaybackAtMs(PositionMs: Integer; FrameAlreadyShown: Boolean = False);
    procedure RestartPlaybackTimer(Sender: TObject);
    procedure FinishPlaybackAtEnd;
    procedure QueueOpenAndPlayFile(const FileName: string);
    procedure ProcessOpenQueue;
    procedure ConfigureCurrentFileWatch;
    function CurrentFileInList(const FileNames: TStringList): Boolean;
    function CurrentFileCanBeRead: Boolean;
    function ReadCurrentFileStamp(out LastWriteTime: TDateTime;
      out Size: Int64): Boolean;
    procedure ScheduleCurrentFileReload;
    procedure ReloadCurrentFileTimer(Sender: TObject);
    procedure FolderWatchFileChange(Sender: TObject; const AddFiles: TStringList;
      const DelFiles: TStringList; const UpdateFiles: TStringList);
    procedure UpdateCurrentFileStamp;
    procedure WMCopyData(var Message: TWMCopyData); message WM_COPYDATA;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMNCCalcSize(var Message: TMessage); message WM_NCCALCSIZE;
    procedure WMOpenPending(var Message: TMessage); message WM_VM_OPEN_PENDING;
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    // 指定ミリ秒位置のフレームを表示する
    function ShowFrameAtMs(const PositionMs: Integer): Boolean;
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
  CURRENT_FILE_RELOAD_SETTLE_MS = 1500;
  TITLE_BAR_COLOR = $00171617;
  CLOSE_BUTTON_HOVER_COLOR = $00232323;
  CAPTION_BUTTON_HOVER_COLOR = $00232323;
  SLOW_OPEN_LOG_MS = 200;

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
  FEndAction := LoadEndAction;
  FShortcuts := TShortcutAction.Create;
  FOleInitialized := OleInitialize(nil) >= 0;
  FDecoder := TFFmpegDecoder.Create;
  FPreviewDecoder := TFFmpegDecoder.Create;
  FAudioPlayback := TVideoMinerAudioPlayback.Create;
  FAudioPlayback.OnPcmDecoded := MaybeAutoCheckAudio;
  FMediaList := TVideoMinerMediaList.Create;
  FChapterManager := TVideoMinerChapterManager.Create;
  FVideoView := TVideoMinerVideoView.Create(ImagePreview);
  FWindowModeController := TVideoMinerWindowModeController.Create(Self,
    PanelTitleBar, LabelMaximizeButton, FVideoView, StopPlayback);
  FCommandController := TVideoMinerCommandController.Create(FAudioPlayback,
    FVideoView);
  FCommandController.OnChapterNavigate := NavigateChapterBy;
  FCommandController.OnNavigate := NavigateBy;
  FCommandController.OnOpenDialog := OpenFromDialog;
  FCommandController.OnPlaybackActiveOrPending := PlaybackActiveOrPending;
  FCommandController.OnPlaybackRateCycle := CyclePlaybackRate;
  FCommandController.OnPlayFromCurrentPosition := PlayFromCurrentPosition;
  FCommandController.OnSaveAudioSettings := SaveAudioPlaybackSettings;
  FCommandController.OnSeekByMs := SeekByMs;
  FCommandController.OnSeekToFirstFrame := SeekToFirstFrame;
  FCommandController.OnSeekToLastFrame := SeekToLastFrame;
  FCommandController.OnSeekToMs := SeekToMs;
  FCommandController.OnStopPlayback := StopPlayback;
  FCommandController.OnToggleFullScreen := ToggleFullScreen;
  FCommandController.RegisterShortcuts(FShortcuts);
  FCommandController.BindVideoView;
  UpdateMaximizeButton;
  FWindowModeController.ApplySavedWindowBounds;
  TResizeEdgeHelper.AttachEdges(PanelTitleBar, VIDEO_MINER_RESIZE_BORDER,
    [rdTop]);
  TResizeEdgeHelper.AttachEdges(FVideoView.SurfaceControl,
    VIDEO_MINER_RESIZE_BORDER, [rdBottom, rdLeft, rdRight]);
  FVideoView.OnBossExitClick := BossExitClick;
  FVideoView.OnBossGesture := BossGesture;
  FVideoView.OnEndActionClick := EndActionOverlayClick;
  FVideoView.OnAddChapterClick := AddChapterOverlayClick;
  FVideoView.OnCheckClick := CheckOverlayClick;
  FVideoView.OnDeleteChapterClick := DeleteChapterOverlayClick;
  FVideoView.CheckEnabled := FChapterManager.CheckEnabled;
  RefreshChapterOverlay;
  FPendingOpenFiles := TStringList.Create;
  FRestartPlaybackTimer := TTimer.Create(Self);
  FRestartPlaybackTimer.Enabled := False;
  FRestartPlaybackTimer.Interval := SEEK_RESTART_DELAY_MS;
  FRestartPlaybackTimer.OnTimer := RestartPlaybackTimer;
  FReloadCurrentFileTimer := TTimer.Create(Self);
  FReloadCurrentFileTimer.Enabled := False;
  FReloadCurrentFileTimer.Interval := CURRENT_FILE_RELOAD_SETTLE_MS;
  FReloadCurrentFileTimer.OnTimer := ReloadCurrentFileTimer;
  FFolderWatcher := TFolderWatch.Create;
  FFolderWatcher.FirstScanDone := True;
  FFolderWatcher.OnFileChange := FolderWatchFileChange;
  FPlaybackController := TVideoMinerPlaybackController.Create(TimerPlayback,
    FRestartPlaybackTimer, FAudioPlayback, FVideoView, FPreviewDecoder);
  UpdateEndActionButton;
  UpdatePlaybackRateButton;
  FCurrentVideoPositionMs := -1;
  FSeekPositionMs := 0;
  FSeekMaxMs := 0;
  FLoopSegmentStartMs := -1;
  FLoopSegmentEndMs := -1;
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
  SaveLoopPlaybackPosition;
  SaveAudioPlaybackSettings;
  if TimerPlayback <> nil then
    TimerPlayback.Enabled := False;
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  if FRestartPlaybackTimer <> nil then
    FRestartPlaybackTimer.Enabled := False;
  if FReloadCurrentFileTimer <> nil then
    FReloadCurrentFileTimer.Enabled := False;
  if FFolderWatcher <> nil then
    FFolderWatcher.Stop;
  if FAudioPlayback <> nil then
    FAudioPlayback.Stop;
  FDropAgent.Free;
  FPendingOpenFiles.Free;
  FCommandController.Free;
  FShortcuts.Free;
  FPlaybackController.Free;
  FFolderWatcher.Free;
  if FWindowModeController <> nil then
    FWindowModeController.SaveWindowBounds;
  FWindowModeController.Free;
  FVideoView.Free;
  FChapterManager.Free;
  FMediaList.Free;
  FAudioPlayback.Free;
  FPreviewDecoder.Free;
  FDecoder.Free;
  FTitleIcon.Free;
  SaveEndAction(FEndAction);
  if FOleInitialized then
    OleUninitialize;
end;

procedure TVideoMinerMainForm.ToggleFullScreen;
begin
  FWindowModeController.ToggleFullScreen;
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

// 指定ミリ秒位置のフレームを表示する
function TVideoMinerMainForm.ShowFrameAtMs(const PositionMs: Integer): Boolean;
var
  ErrorMessage: string;
  ShownPositionMs: Integer;
begin
  Result := False;
  if (FVideoFile = '') or (FDecoder = nil) then
    Exit;

  if not FPlaybackController.ShowFrameNearMs(PositionMs, FSeekMaxMs,
    ShownPositionMs, ErrorMessage) then
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
  FEndAction := FPlaybackController.NextEndAction(FEndAction);
  UpdateEndActionButton;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveEndAction(FEndAction);
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerMainForm.CyclePlaybackRate;
var
  CurrentRate: Double;
  PositionMs: Integer;
  WasPlaying: Boolean;
begin
  if FPlaybackController = nil then
    Exit;

  WasPlaying := PlaybackActiveOrPending;
  PositionMs := CurrentPlaybackPositionMs;
  CurrentRate := FPlaybackController.PlaybackRate;
  if SameValue(CurrentRate, 1.0) then
    FPlaybackController.PlaybackRate := 1.5
  else if SameValue(CurrentRate, 1.5) then
    FPlaybackController.PlaybackRate := 2.0
  else
    FPlaybackController.PlaybackRate := 1.0;

  UpdatePlaybackRateButton;
  if WasPlaying then
  begin
    FPlaybackController.StopPlayback;
    StartPlaybackAtMs(PositionMs, True);
  end
  else
    UpdateInfoLabel;
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
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveManualChapterState;
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerMainForm.MaybeAutoCheckAudio(Sender: TObject;
  StartSample: Int64; const Pcm: TBytes);
var
  Changed: Boolean;
begin
  if FChapterManager = nil then
    Exit;

  if (not FVideoInfo.Audio.Present) or (FVideoInfo.Audio.OpenError <> '') then
  begin
    FChapterManager.MaybeAutoCheckAudio(StartSample, nil, FSeekMaxMs);
    Exit;
  end;

  Changed := FChapterManager.MaybeAutoCheckAudio(StartSample, Pcm, FSeekMaxMs);
  if Changed then
  begin
    RefreshChapterOverlay;
    ConfigureLoopSegment(CurrentPlaybackPositionMs);
    SaveManualChapterState;
    SaveLoopPlaybackPosition;
  end;
end;

procedure TVideoMinerMainForm.MaybeAutoCheckFrame(PositionMs: Integer);
var
  Changed: Boolean;
  Signature: TVideoMinerFrameSignature;
begin
  if (FChapterManager = nil) or (FVideoView = nil) then
    Exit;

  if not FChapterManager.CheckEnabled then
  begin
    FChapterManager.MaybeAutoCheckFrame(PositionMs, False, FSeekMaxMs);
    FillChar(Signature, SizeOf(Signature), 0);
    FChapterManager.MaybeAutoCheckFrameDifference(PositionMs, Signature,
      FSeekMaxMs);
    Exit;
  end;

  Changed := FChapterManager.MaybeAutoCheckFrame(PositionMs,
    FVideoView.CurrentFrameCornersMostlyDark, FSeekMaxMs);
  if FVideoView.CurrentFrameSignature(Signature) then
    Changed := FChapterManager.MaybeAutoCheckFrameDifference(PositionMs,
      Signature, FSeekMaxMs) or Changed;
  if Changed then
  begin
    RefreshChapterOverlay;
    ConfigureLoopSegment(CurrentPlaybackPositionMs);
    SaveManualChapterState;
    SaveLoopPlaybackPosition;
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
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerMainForm.RefreshChapterOverlay;
begin
  if (FVideoView <> nil) and (FChapterManager <> nil) then
    FVideoView.Chapters := FChapterManager.DisplayChapters;
end;

procedure TVideoMinerMainForm.UpdateEndActionButton;
begin
  if (FVideoView = nil) or (FPlaybackController = nil) then
    Exit;

  FVideoView.EndActionText := FPlaybackController.EndActionText(FEndAction);
end;

procedure TVideoMinerMainForm.UpdatePlaybackRateButton;
var
  RateText: string;
begin
  if (FVideoView = nil) or (FPlaybackController = nil) then
    Exit;

  if SameValue(FPlaybackController.PlaybackRate, 1.5) then
    RateText := '1.5x'
  else if SameValue(FPlaybackController.PlaybackRate, 2.0) then
    RateText := '2.0x'
  else
    RateText := '1.0x';
  FVideoView.PlaybackRateText := RateText;
end;

procedure TVideoMinerMainForm.UpdateMaximizeButton;
begin
  if FWindowModeController <> nil then
    FWindowModeController.UpdateMaximizeButton;
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

procedure TVideoMinerMainForm.SaveLoopPlaybackPosition;
begin
  if (FChapterManager = nil) or (FPlaybackController = nil) or
     (FVideoFile = '') then
    Exit;

  if (FEndAction = eaLoop) and FChapterManager.HasManualChapters then
    SaveManualChapterPlaybackPosition(FVideoFile, CurrentPlaybackPositionMs,
      FSeekMaxMs)
  else
    ClearManualChapterPlaybackPosition(FVideoFile);
end;

function TVideoMinerMainForm.TryRestoreLoopPlaybackPosition: Boolean;
var
  ErrorMessage: string;
  PositionMs: Integer;
  ShownPositionMs: Integer;
begin
  Result := False;
  if (FChapterManager = nil) or (FVideoFile = '') or
     (FPlaybackController = nil) or (FEndAction <> eaLoop) or
     (not FChapterManager.HasManualChapters) then
    Exit;

  if not LoadManualChapterPlaybackPosition(FVideoFile, FSeekMaxMs,
    PositionMs) then
    Exit;

  if not FPlaybackController.ShowFrameNearMs(PositionMs, FSeekMaxMs,
    ShownPositionMs, ErrorMessage) then
    Exit;

  FCurrentVideoPositionMs := ShownPositionMs;
  FUpdatingSeek := True;
  try
    FSeekPositionMs := ShownPositionMs;
  finally
    FUpdatingSeek := False;
  end;
  UpdatePlaybackProgress(FSeekPositionMs);
  ConfigureLoopSegment(FSeekPositionMs);
  Result := True;
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
  Result := (FPlaybackController <> nil) and FPlaybackController.ActiveOrPending;
end;

function TVideoMinerMainForm.CurrentPlaybackPositionMs: Integer;
begin
  if FPlaybackController = nil then
  begin
    Result := Max(0, Min(FSeekMaxMs, FSeekPositionMs));
    Exit;
  end;

  Result := FPlaybackController.CurrentPositionMs(PlaybackActiveOrPending,
    FSeekPositionMs, FCurrentVideoPositionMs, FSeekMaxMs);
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

function TVideoMinerMainForm.LoadVideoFile(const FileName: string;
  AutoPlay: Boolean; RestoreLoopPosition: Boolean): Boolean;
var
  ErrorMessage: string;
  OpenResult: TVideoMinerMediaOpenResult;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  ValidateMs: Double;
  CleanupMs: Double;
  OpenMs: Double;
  FirstFrameMs: Double;
  AutoPlayMs: Double;
begin
  Result := False;
  TotalWatch := TStopwatch.StartNew;

  StepWatch := TStopwatch.StartNew;
  if not ValidateVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
    ValidateMs := StepWatch.Elapsed.TotalMilliseconds;
    WriteVideoMinerSlowLog(Format(
      'open_failed step="validate" file="%s" drive="%s" autoplay=%s validate_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       BoolToStr(AutoPlay, True), ValidateMs, TotalWatch.Elapsed.TotalMilliseconds,
       ErrorMessage]));
    SetStatusCaption(ErrorMessage);
    Exit;
  end;
  ValidateMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if FReloadCurrentFileTimer <> nil then
    FReloadCurrentFileTimer.Enabled := False;
  FPendingReloadHasStamp := False;

  SaveManualChapterState;
  SaveLoopPlaybackPosition;

  TimerPlayback.Enabled := False;
  FPlaybackController.ClearRestart;
  FAudioPlayback.Stop;
  FPreviewDecoder.Close;
  FSeeking := False;
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
  CleanupMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if not OpenVideoMinerMediaFile(FileName, FDecoder, FPreviewDecoder,
    FMediaList, OpenResult) then
  begin
    OpenMs := StepWatch.Elapsed.TotalMilliseconds;
    FVideoFile := '';
    ConfigureCurrentFileWatch;
    UpdateCurrentFileStamp;
    FVideoView.PlaybackActive := False;
    Caption := 'VideoMiner';
    SetTitleBarText(Caption);
    UpdateNavigationButtons;
    SetStatusCaption(OpenResult.ErrorMessage);
    WriteVideoMinerSlowLog(Format(
      'open_failed step="decoder_open" file="%s" drive="%s" autoplay=%s validate_ms=%.3f cleanup_ms=%.3f open_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       BoolToStr(AutoPlay, True), ValidateMs, CleanupMs, OpenMs,
       TotalWatch.Elapsed.TotalMilliseconds, OpenResult.ErrorMessage]));
    Exit;
  end;
  OpenMs := StepWatch.Elapsed.TotalMilliseconds;

  FVideoInfo := OpenResult.Info;
  FVideoFile := OpenResult.FileName;
  ConfigureCurrentFileWatch;
  UpdateCurrentFileStamp;
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
  StepWatch := TStopwatch.StartNew;
  if (not RestoreLoopPosition) or (not TryRestoreLoopPlaybackPosition) then
    ShowFrameAtMs(0);
  FirstFrameMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if AutoPlay then
    PlayFromCurrentPosition;
  AutoPlayMs := StepWatch.Elapsed.TotalMilliseconds;

  RememberVideoMinerMediaFile(FileName);
  Result := True;
  if (TotalWatch.Elapsed.TotalMilliseconds >= SLOW_OPEN_LOG_MS) or
     (OpenMs >= SLOW_OPEN_LOG_MS) or (FirstFrameMs >= SLOW_OPEN_LOG_MS) or
     (AutoPlayMs >= SLOW_OPEN_LOG_MS) then
    WriteVideoMinerSlowLog(Format(
      'open_done file="%s" drive="%s" autoplay=%s restore_loop=%s validate_ms=%.3f cleanup_ms=%.3f open_ms=%.3f first_frame_ms=%.3f autoplay_ms=%.3f total_ms=%.3f duration_ms=%d fps=%.3f',
      [ExtractFileName(FVideoFile), ExtractFileDrive(FVideoFile),
       BoolToStr(AutoPlay, True), BoolToStr(RestoreLoopPosition, True),
       ValidateMs, CleanupMs, OpenMs, FirstFrameMs, AutoPlayMs,
       TotalWatch.Elapsed.TotalMilliseconds, FSeekMaxMs, FVideoInfo.Fps]));
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

procedure TVideoMinerMainForm.BossGesture(Sender: TObject);
begin
  FWindowModeController.EnterBossMode;
end;

procedure TVideoMinerMainForm.BossExitClick(Sender: TObject);
begin
  FWindowModeController.ExitBossMode;
end;

// 再生を停止する
procedure TVideoMinerMainForm.StopPlayback;
begin
  if FPlaybackController <> nil then
    FPlaybackController.StopPlayback;
  UpdateInfoLabel;
end;

// 再生 tick 処理を再生 controller へ委譲する
procedure TVideoMinerMainForm.TimerPlaybackTimer(Sender: TObject);
begin
  FPlaybackController.Tick(FDecoder, FVideoFile, FEndAction, FSeeking,
    FSeekMaxMs, FLoopSegmentStartMs, FLoopSegmentEndMs,
    FCurrentVideoPositionMs, FSeekPositionMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FUpdatingSeek, SetStatusCaption, FinishPlaybackAtEnd,
    SeekPlaybackTickToMs, UpdatePlaybackProgress, MaybeAutoCheckFrame);
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

procedure TVideoMinerMainForm.NavigateNextPlaybackFile;
begin
  NavigateBy(1);
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
begin
  FPlaybackController.SeekToMs(FVideoFile, PositionMs, ResumeIfPlaying,
    FSeekMaxMs, FCurrentVideoPositionMs, FSeekPositionMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FUpdatingSeek, FSeeking, SetStatusCaption,
    UpdateInfoLabel);
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

procedure TVideoMinerMainForm.SeekPlaybackTickToMs(PositionMs: Integer);
begin
  SeekToMs(PositionMs);
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

procedure TVideoMinerMainForm.ConfigureLoopSegment(PositionMs: Integer);
begin
  FPlaybackController.ConfigureLoopSegment(FEndAction, FChapterManager,
    PositionMs, FSeekMaxMs, LastFrameSeekPositionMs, FLoopSegmentStartMs,
    FLoopSegmentEndMs);
end;

procedure TVideoMinerMainForm.StartPlaybackAtMs(PositionMs: Integer;
  FrameAlreadyShown: Boolean);
begin
  FPlaybackController.StartPlaybackAtMs(FDecoder, FVideoFile, FVideoInfo,
    FEndAction, FChapterManager, FSeekMaxMs, PositionMs, LastFrameSeekPositionMs,
    FrameAlreadyShown, False, FCurrentVideoPositionMs, FSeekPositionMs,
    FLoopSegmentStartMs, FLoopSegmentEndMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, SetStatusCaption);
end;

procedure TVideoMinerMainForm.FinishPlaybackAtEnd;
var
  CanNavigateNext: Boolean;
begin
  CanNavigateNext := (FMediaList <> nil) and FMediaList.CanNavigate(1);
  FPlaybackController.FinishAtEnd(FEndAction, CanNavigateNext,
    LoopStartPositionMs, FSeekMaxMs, FSeekPositionMs, FUpdatingSeek,
    ShowFrameAtMs, StartPlaybackAtMs, NavigateNextPlaybackFile,
    UpdateInfoLabel);
end;

procedure TVideoMinerMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FWindowModeController = nil then
    Exit;

  if (Key = VK_ESCAPE) and FWindowModeController.BossMode then
  begin
    FWindowModeController.ExitBossMode;
    Key := 0;
    Exit;
  end;

  if FWindowModeController.BossMode then
  begin
    Key := 0;
    Exit;
  end;

  if (Key = VK_ESCAPE) and FWindowModeController.FullScreen then
  begin
    FWindowModeController.ExitFullScreen;
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

procedure TVideoMinerMainForm.ConfigureCurrentFileWatch;
var
  Folder: string;
begin
  if FFolderWatcher = nil then
    Exit;

  if FVideoFile = '' then
  begin
    FFolderWatcher.Stop;
    FWatchedFolder := '';
    Exit;
  end;

  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(FVideoFile));
  if SameText(FWatchedFolder, Folder) then
    Exit;

  FFolderWatcher.Stop;
  FWatchedFolder := Folder;
  FFolderWatcher.FolderPath := Folder;
  FFolderWatcher.IncludeSubFolders := False;
  FFolderWatcher.FirstScanDone := True;
  FFolderWatcher.Start;
end;

function TVideoMinerMainForm.CurrentFileInList(
  const FileNames: TStringList): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (FileNames = nil) or (FVideoFile = '') then
    Exit;

  for I := 0 to FileNames.Count - 1 do
  begin
    if SameText(ExpandFileName(FileNames[I]), ExpandFileName(FVideoFile)) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TVideoMinerMainForm.ReadCurrentFileStamp(
  out LastWriteTime: TDateTime; out Size: Int64): Boolean;
var
  SearchRec: TSearchRec;
begin
  LastWriteTime := 0;
  Size := -1;
  Result := False;
  if FVideoFile = '' then
    Exit;

  if FindFirst(FVideoFile, faAnyFile, SearchRec) <> 0 then
    Exit;
  try
    if (SearchRec.Attr and faDirectory) <> 0 then
      Exit;

    LastWriteTime := SearchRec.TimeStamp;
    Size := SearchRec.Size;
    Result := True;
  finally
    FindClose(SearchRec);
  end;
end;

function TVideoMinerMainForm.CurrentFileCanBeRead: Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  if FVideoFile = '' then
    Exit;

  try
    Stream := TFileStream.Create(FVideoFile, fmOpenRead or fmShareDenyNone);
    try
      Result := True;
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TVideoMinerMainForm.ScheduleCurrentFileReload;
begin
  if (FReloadCurrentFileTimer = nil) or (FVideoFile = '') or
     FReloadingCurrentFile then
    Exit;

  FPendingReloadHasStamp := False;
  FReloadCurrentFileTimer.Enabled := False;
  FReloadCurrentFileTimer.Enabled := True;
end;

procedure TVideoMinerMainForm.FolderWatchFileChange(Sender: TObject;
  const AddFiles, DelFiles, UpdateFiles: TStringList);
begin
  if FReloadingCurrentFile then
    Exit;

  if CurrentFileInList(AddFiles) or CurrentFileInList(DelFiles) or
     CurrentFileInList(UpdateFiles) then
    ScheduleCurrentFileReload;
end;

procedure TVideoMinerMainForm.ReloadCurrentFileTimer(Sender: TObject);
var
  FileName: string;
  LastWriteTime: TDateTime;
  Size: Int64;
begin
  if FReloadCurrentFileTimer <> nil then
    FReloadCurrentFileTimer.Enabled := False;

  if (FVideoFile = '') or FReloadingCurrentFile then
    Exit;

  if (not ReadCurrentFileStamp(LastWriteTime, Size)) or
     (not CurrentFileCanBeRead) then
  begin
    if FReloadCurrentFileTimer <> nil then
      FReloadCurrentFileTimer.Enabled := True;
    Exit;
  end;

  if (not FPendingReloadHasStamp) or
     (FPendingReloadLastWriteTime <> LastWriteTime) or
     (FPendingReloadSize <> Size) then
  begin
    FPendingReloadLastWriteTime := LastWriteTime;
    FPendingReloadSize := Size;
    FPendingReloadHasStamp := True;
    if FReloadCurrentFileTimer <> nil then
      FReloadCurrentFileTimer.Enabled := True;
    Exit;
  end;

  FPendingReloadHasStamp := False;
  if (FVideoFileLastWriteTime = LastWriteTime) and (FVideoFileSize = Size) then
    Exit;

  FileName := FVideoFile;
  FReloadingCurrentFile := True;
  try
    LoadVideoFile(FileName, False, False);
  finally
    FReloadingCurrentFile := False;
  end;
end;

procedure TVideoMinerMainForm.UpdateCurrentFileStamp;
begin
  if not ReadCurrentFileStamp(FVideoFileLastWriteTime, FVideoFileSize) then
  begin
    FVideoFileLastWriteTime := 0;
    FVideoFileSize := -1;
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
  FrameAlreadyShown: Boolean;
  FastSeek: Boolean;
begin
  if not FPlaybackController.ConsumeRestart(TargetMs, FrameAlreadyShown,
    FastSeek) then
    Exit;

  if (FVideoFile = '') or (TargetMs < 0) or (TargetMs >= FSeekMaxMs) then
    Exit;

  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format('restart_playback target_ms=%d',
      [TargetMs]));
  FPlaybackController.StartPlaybackAtMs(FDecoder, FVideoFile, FVideoInfo,
    FEndAction, FChapterManager, FSeekMaxMs, TargetMs, LastFrameSeekPositionMs,
    FrameAlreadyShown, FastSeek, FCurrentVideoPositionMs, FSeekPositionMs,
    FLoopSegmentStartMs, FLoopSegmentEndMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, SetStatusCaption);
end;

procedure TVideoMinerMainForm.WMNCHitTest(var Message: TWMNCHitTest);
begin
  inherited;
  if FWindowModeController <> nil then
    FWindowModeController.HitTestBorderlessResize(
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
  if FWindowModeController <> nil then
    FWindowModeController.HandleMove;
end;

procedure TVideoMinerMainForm.WMSize(var Message: TWMSize);
begin
  inherited;
  if FWindowModeController <> nil then
    FWindowModeController.HandleSize;
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
