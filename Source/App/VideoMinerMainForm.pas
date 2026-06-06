unit VideoMinerMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Diagnostics, System.Math,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls, ActiveX, DropAgent, FFmpegDecoder,
  FFmpegDecoderTypes, ShortcutAction, VideoMinerAudioPlayback, VideoMinerMediaList,
  VideoMinerDebugLog, VideoMinerSettings, VideoMinerVideoView;

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
    FFullScreen: Boolean;
    FEndAction: TVideoMinerEndAction;
    FNormalWindowBounds: TVideoMinerWindowBounds;
    FShortcuts: TShortcutAction;
    procedure ApplySavedWindowBounds;
    procedure EnterFullScreen;
    procedure ExitFullScreen;
    procedure InitializeShortcuts;
    procedure RememberNormalWindowBounds;
    procedure SetCaptionButtonColor(Sender: TObject; Color: TColor);
    procedure CycleEndAction;
    procedure EndActionOverlayClick(Sender: TObject);
    procedure ToggleFullScreen;
    procedure TogglePlayPause;
    procedure UpdateEndActionButton;
    procedure UpdateMaximizeButton;
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    procedure UpdateNavigationButtons;
    procedure NavigateBy(Delta: Integer);
    procedure OpenFromDialog;
    procedure PrepareOpenDialogInitialDir;
    procedure RememberLastMediaFile(const FileName: string);
    procedure FirstFrameOverlayClick(Sender: TObject);
    procedure FullScreenOverlayClick(Sender: TObject);
    procedure LastFrameOverlayClick(Sender: TObject);
    procedure NavigateNextOverlayClick(Sender: TObject);
    procedure NavigatePreviousOverlayClick(Sender: TObject);
    procedure PlayPauseOverlayClick(Sender: TObject);
    procedure PlayFromCurrentPosition;
    procedure SeekBarSeek(Sender: TObject; PositionMs: Integer);
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
    function PlaybackActiveOrPending: Boolean;
    function CurrentPlaybackPositionMs: Integer;
    procedure SetTitleBarText(const Text: string);
    procedure SetStatusCaption(const Text: string);
    procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
    procedure SeekByMs(DeltaMs: Integer);
    procedure SeekToFirstFrame;
    procedure SeekToLastFrame;
    function LastFrameSeekPositionMs: Integer;
    procedure StartPlaybackAtMs(PositionMs: Integer);
    procedure RestartPlaybackTimer(Sender: TObject);
    function SyncVideoToAudio(var PositionMs: Integer; out ErrorMessage: string): Boolean;
    procedure FinishPlaybackAtEnd;
    procedure QueueOpenAndPlayFile(const FileName: string);
    procedure ProcessOpenQueue;
    procedure WMCopyData(var Message: TWMCopyData); message WM_COPYDATA;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMOpenPending(var Message: TMessage); message WM_VM_OPEN_PENDING;
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    // 指定ミリ秒位置のフレームを表示する
    function ShowFrameAtMs(const PositionMs: Integer): Boolean;
    function TryShowFrameNearMs(const PositionMs: Integer; out ShownPositionMs: Integer;
      out ErrorMessage: string): Boolean;
    // 動画情報ラベルを更新する
    procedure UpdateInfoLabel;
  public
    function OpenAndPlayFile(const FileName: string): Boolean;
    function OpenRememberedFile: Boolean;
  end;

var
  VideoMinerForm: TVideoMinerMainForm;

implementation

const
  COPYDATA_OPEN_FILE = $564D0001;
  VIDEO_AUDIO_SYNC_LAG_MS = 60;
  VIDEO_AUDIO_SEEK_LAG_MS = 120;
  VIDEO_END_TOLERANCE_MS = 1500;
  VIDEO_DROP_FRAME_MAX = 90;
  VIDEO_DROP_FRAME_BUDGET_MS = 25;
  CUSTOM_RESIZE_BORDER = 6;
  TITLE_BAR_COLOR = $00171617;
  CLOSE_BUTTON_HOVER_COLOR = $00232323;
  CAPTION_BUTTON_HOVER_COLOR = $00232323;

{$R *.dfm}

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
begin
  ClearVideoMinerDebugLog('form_create');
  PanelTitleBar.Color := TITLE_BAR_COLOR;
  PanelCloseButton.Color := TITLE_BAR_COLOR;
  PanelMaximizeButton.Color := TITLE_BAR_COLOR;
  PanelMinimizeButton.Color := TITLE_BAR_COLOR;
  UpdateMaximizeButton;
  FEndAction := LoadEndAction;
  ApplySavedWindowBounds;
  FShortcuts := TShortcutAction.Create;
  InitializeShortcuts;
  FOleInitialized := OleInitialize(nil) >= 0;
  FDecoder := TFFmpegDecoder.Create;
  FPreviewDecoder := TFFmpegDecoder.Create;
  FAudioPlayback := TVideoMinerAudioPlayback.Create;
  FMediaList := TVideoMinerMediaList.Create;
  FVideoView := TVideoMinerVideoView.Create(ImagePreview);
  FVideoView.OnFirstFrameClick := FirstFrameOverlayClick;
  FVideoView.OnFullScreenClick := FullScreenOverlayClick;
  FVideoView.OnNavigateNextClick := NavigateNextOverlayClick;
  FVideoView.OnNavigatePreviousClick := NavigatePreviousOverlayClick;
  FVideoView.OnPlayPauseClick := PlayPauseOverlayClick;
  FVideoView.OnSeek := SeekBarSeek;
  FVideoView.OnSkipBackwardClick := SkipBackwardOverlayClick;
  FVideoView.OnSkipForwardClick := SkipForwardOverlayClick;
  FVideoView.OnLastFrameClick := LastFrameOverlayClick;
  FVideoView.OnVolumeChange := VolumeOverlayChange;
  FVideoView.OnEndActionClick := EndActionOverlayClick;
  UpdateEndActionButton;
  FPendingOpenFiles := TStringList.Create;
  FRestartPlaybackTimer := TTimer.Create(Self);
  FRestartPlaybackTimer.Enabled := False;
  FRestartPlaybackTimer.Interval := 120;
  FRestartPlaybackTimer.OnTimer := RestartPlaybackTimer;
  FCurrentVideoPositionMs := -1;
  FSeekPositionMs := 0;
  FSeekMaxMs := 0;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FAudioPlayback.VolumePercent := 100;
  FAudioPlayback.Muted := False;
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
  TimerPlayback.Enabled := False;
  FVideoView.PlaybackActive := False;
  FRestartPlaybackTimer.Enabled := False;
  FAudioPlayback.Stop;
  FDropAgent.Free;
  FPendingOpenFiles.Free;
  FShortcuts.Free;
  FVideoView.Free;
  FMediaList.Free;
  FAudioPlayback.Free;
  FPreviewDecoder.Free;
  FDecoder.Free;
  RememberNormalWindowBounds;
  SaveMainFormBounds(FNormalWindowBounds);
  SaveEndAction(FEndAction);
  if FOleInitialized then
    OleUninitialize;
end;

procedure TVideoMinerMainForm.ApplySavedWindowBounds;
var
  Bounds: TVideoMinerWindowBounds;
  Monitor: TMonitor;
  NewBounds: TRect;
  WorkArea: TRect;
begin
  WindowState := wsNormal;
  Bounds := LoadMainFormBounds;
  if not Bounds.Available then
  begin
    RememberNormalWindowBounds;
    Exit;
  end;

  NewBounds := Rect(Bounds.Left, Bounds.Top, Bounds.Left + Bounds.Width,
    Bounds.Top + Bounds.Height);
  Monitor := Screen.MonitorFromRect(NewBounds, mdNearest);
  if Monitor <> nil then
  begin
    WorkArea := Monitor.WorkareaRect;
    if NewBounds.Width > WorkArea.Width then
      NewBounds.Right := NewBounds.Left + WorkArea.Width;
    if NewBounds.Height > WorkArea.Height then
      NewBounds.Bottom := NewBounds.Top + WorkArea.Height;
    if NewBounds.Left < WorkArea.Left then
      OffsetRect(NewBounds, WorkArea.Left - NewBounds.Left, 0);
    if NewBounds.Top < WorkArea.Top then
      OffsetRect(NewBounds, 0, WorkArea.Top - NewBounds.Top);
    if NewBounds.Right > WorkArea.Right then
      OffsetRect(NewBounds, WorkArea.Right - NewBounds.Right, 0);
    if NewBounds.Bottom > WorkArea.Bottom then
      OffsetRect(NewBounds, 0, WorkArea.Bottom - NewBounds.Bottom);
  end;

  SetBounds(NewBounds.Left, NewBounds.Top, NewBounds.Width, NewBounds.Height);
  RememberNormalWindowBounds;
end;

procedure TVideoMinerMainForm.RememberNormalWindowBounds;
begin
  if FFullScreen then
    Exit;
  if WindowState <> wsNormal then
    Exit;

  FNormalWindowBounds.Available := True;
  FNormalWindowBounds.Left := Left;
  FNormalWindowBounds.Top := Top;
  FNormalWindowBounds.Width := Width;
  FNormalWindowBounds.Height := Height;
end;

procedure TVideoMinerMainForm.EnterFullScreen;
var
  FullScreenRect: TRect;
  Monitor: TMonitor;
begin
  if FFullScreen then
    Exit;

  RememberNormalWindowBounds;
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
  RememberNormalWindowBounds;
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

procedure TVideoMinerMainForm.InitializeShortcuts;
begin
  FShortcuts.Clear;
  FShortcuts.Add(Ord('O'), [ssCtrl], ShortcutOpenDialog);
  FShortcuts.Add(VK_LEFT, [ssCtrl], ShortcutNavigatePrevious);
  FShortcuts.Add(VK_RIGHT, [ssCtrl], ShortcutNavigateNext);
  FShortcuts.Add(VK_F11, [], ToggleFullScreen);
  FShortcuts.Add(VK_SPACE, [], TogglePlayPause);
  FShortcuts.Add(VK_LEFT, [], ShortcutNavigatePrevious);
  FShortcuts.Add(VK_RIGHT, [], ShortcutNavigateNext);
  FShortcuts.Add(VK_PRIOR, [], ShortcutNavigatePrevious);
  FShortcuts.Add(VK_NEXT, [], ShortcutNavigateNext);
  FShortcuts.Add(VK_HOME, [], ShortcutSeekToFirstFrame);
  FShortcuts.Add(VK_END, [], ShortcutSeekToLastFrame);
  FShortcuts.Add(VK_UP, [], ShortcutVolumeUp);
  FShortcuts.Add(VK_DOWN, [], ShortcutVolumeDown);
  FShortcuts.Add(Ord('M'), [], ShortcutToggleMute);
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
  SaveEndAction(FEndAction);
end;

procedure TVideoMinerMainForm.EndActionOverlayClick(Sender: TObject);
begin
  CycleEndAction;
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
end;

procedure TVideoMinerMainForm.OpenFromDialog;
begin
  PrepareOpenDialogInitialDir;
  if OpenDialogVideo.Execute then
    LoadVideoFile(OpenDialogVideo.FileName, False);
end;

procedure TVideoMinerMainForm.PrepareOpenDialogInitialDir;
var
  Folder: string;
  LastMedia: TVideoMinerLastMedia;
begin
  Folder := '';
  if FVideoFile <> '' then
    Folder := ExtractFilePath(FVideoFile);

  if (Folder = '') or (not DirectoryExists(Folder)) then
  begin
    LastMedia := LoadLastMedia;
    Folder := LastMedia.Folder;
  end;

  if (Folder <> '') and DirectoryExists(Folder) then
    OpenDialogVideo.InitialDir := Folder
  else
    OpenDialogVideo.InitialDir := '';
end;

procedure TVideoMinerMainForm.RememberLastMediaFile(const FileName: string);
var
  Folder: string;
begin
  if FileName = '' then
    Exit;

  Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(FileName));
  SaveLastMedia(Folder, FileName);
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
  Folder: string;
  PreviewInfo: TVideoInfo;
begin
  Result := False;

  if FileName = '' then
  begin
    SetStatusCaption('File name is empty.');
    Exit;
  end;

  Folder := ExtractFilePath(FileName);
  if (Folder <> '') and (not DirectoryExists(Folder)) then
  begin
    SetStatusCaption('Folder not found: ' + Folder);
    Exit;
  end;

  if not FileExists(FileName) then
  begin
    SetStatusCaption('File not found: ' + FileName);
    Exit;
  end;

  TimerPlayback.Enabled := False;
  FRestartPlaybackTimer.Enabled := False;
  FAudioPlayback.Stop;
  FPreviewDecoder.Close;
  FSeeking := False;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FCurrentVideoPositionMs := -1;
  FSeekGuardRemaining := 0;
  FVideoView.Clear;

  FUpdatingSeek := True;
  try
    FSeekPositionMs := 0;
    FSeekMaxMs := 0;
  finally
    FUpdatingSeek := False;
  end;

  if not FDecoder.Open(FileName, FVideoInfo, ErrorMessage) then
  begin
    FVideoFile := '';
    FMediaList.Clear;
    FVideoView.PlaybackActive := False;
    Caption := 'VideoMiner';
    SetTitleBarText(Caption);
    UpdateNavigationButtons;
    SetStatusCaption('Failed to open video: ' + ErrorMessage);
    Exit;
  end;

  if not FPreviewDecoder.Open(FileName, PreviewInfo, ErrorMessage) then
  begin
    FDecoder.Close;
    FVideoFile := '';
    FMediaList.Clear;
    Caption := 'VideoMiner';
    SetTitleBarText(Caption);
    UpdateNavigationButtons;
    SetStatusCaption('Failed to open preview decoder: ' + ErrorMessage);
    Exit;
  end;

  FMediaList.BuildForFile(FileName);
  FVideoFile := FileName;
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

  if FVideoInfo.Fps > 0 then
    TimerPlayback.Interval := Round(1000 / FVideoInfo.Fps)
  else
    TimerPlayback.Interval := 33;
  if TimerPlayback.Interval < 1 then
    TimerPlayback.Interval := 1;

  UpdateNavigationButtons;
  UpdateInfoLabel;
  ShowFrameAtMs(0);

  if AutoPlay then
    PlayFromCurrentPosition;

  RememberLastMediaFile(FileName);
  Result := True;
end;

function TVideoMinerMainForm.OpenAndPlayFile(const FileName: string): Boolean;
begin
  Result := LoadVideoFile(FileName, True);
end;

function TVideoMinerMainForm.OpenRememberedFile: Boolean;
var
  FileName: string;
  Folder: string;
  LastMedia: TVideoMinerLastMedia;
begin
  Result := False;
  LastMedia := LoadLastMedia;
  if not LastMedia.Available then
    Exit;

  Folder := LastMedia.Folder;
  FileName := LastMedia.FileName;
  if (FileName <> '') and (ExtractFilePath(FileName) = '') and
     (Folder <> '') then
    FileName := IncludeTrailingPathDelimiter(Folder) + FileName;

  if (Folder <> '') and (not DirectoryExists(Folder)) then
  begin
    SetStatusCaption('Last folder not found: ' + Folder);
    Exit;
  end;

  if FileName = '' then
  begin
    SetStatusCaption('Last file is not stored.');
    Exit;
  end;

  if not FileExists(FileName) then
  begin
    SetStatusCaption('Last file not found: ' + FileName);
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
  if FAudioPlayback.Muted then
    FVideoView.VolumePercent := 0
  else
    FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
end;

procedure TVideoMinerMainForm.SkipForwardOverlayClick(Sender: TObject);
begin
  SeekByMs(10000);
end;

procedure TVideoMinerMainForm.ChangeVolumeBy(DeltaPercent: Integer);
begin
  FAudioPlayback.Muted := False;
  FAudioPlayback.VolumePercent := Max(0,
    Min(100, FAudioPlayback.VolumePercent + DeltaPercent));
  FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
end;

procedure TVideoMinerMainForm.VolumeOverlayChange(Sender: TObject;
  VolumePercent: Integer);
begin
  FAudioPlayback.Muted := False;
  FAudioPlayback.VolumePercent := VolumePercent;
  FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
end;

// 再生を停止する
procedure TVideoMinerMainForm.StopPlayback;
begin
  TimerPlayback.Enabled := False;
  FVideoView.PlaybackActive := False;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FRestartPlaybackTimer.Enabled := False;
  FAudioPlayback.Stop;
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
begin
  TotalWatch := TStopwatch.StartNew;
  DecodeMs := 0;

  if FSeeking then
    Exit;

  if (FVideoFile = '') or (FDecoder = nil) then
  begin
    TimerPlayback.Enabled := False;
    FVideoView.PlaybackActive := False;
    Exit;
  end;

  StepWatch := TStopwatch.StartNew;
  if not FAudioPlayback.Pump(ErrorMessage) then
  begin
    SetStatusCaption('Failed to play audio: ' + ErrorMessage);
    Exit;
  end;
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
    if (AudioPositionMs >= 0) and (FCurrentVideoPositionMs >= 0) and
       (FCurrentVideoPositionMs < AudioPositionMs - VIDEO_AUDIO_SYNC_LAG_MS) then
    begin
      if (DropCount < VIDEO_DROP_FRAME_MAX) and
         (DropWatch.ElapsedMilliseconds < VIDEO_DROP_FRAME_BUDGET_MS) then
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

        if FSeekMaxMs - AudioPositionMs <= VIDEO_END_TOLERANCE_MS then
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

    StepWatch := TStopwatch.StartNew;
    if not FVideoView.DecodeNextFrame(FDecoder, ConvertFrame, PositionMs,
      ErrorMessage) then
    begin
      TimerPlayback.Enabled := False;
      FVideoView.PlaybackActive := False;
      FAudioPlayback.Stop;
      if ErrorMessage = 'End of stream.' then
        FinishPlaybackAtEnd
      else
        SetStatusCaption('Failed to decode next frame: ' + ErrorMessage);
      Exit;
    end;
    DecodeMs := DecodeMs + StepWatch.Elapsed.TotalMilliseconds;

    if PositionMs >= 0 then
      FCurrentVideoPositionMs := PositionMs;
  until ConvertFrame;

  StepWatch := TStopwatch.StartNew;
  if (not DidSeekToAudio) and (not SyncVideoToAudio(PositionMs, ErrorMessage)) then
  begin
    SetStatusCaption('Failed to sync video: ' + ErrorMessage);
    Exit;
  end;
  SyncMs := StepWatch.Elapsed.TotalMilliseconds;

  if (FSeekGuardRemaining > 0) and (PositionMs >= 0) then
  begin
    Dec(FSeekGuardRemaining);
    if Abs(PositionMs - FSeekGuardTargetMs) > 1500 then
    begin
      FSeeking := True;
      try
        FUpdatingSeek := True;
        try
          FSeekPositionMs := FSeekGuardTargetMs;
        finally
          FUpdatingSeek := False;
        end;
        ShowFrameAtMs(FSeekGuardTargetMs);
      finally
        FSeeking := False;
      end;
      Exit;
    end;
    FSeekGuardRemaining := 0;
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
  UpdateInfoLabel;
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

procedure TVideoMinerMainForm.SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean);
var
  ErrorMessage: string;
  ShownPositionMs: Integer;
  TargetMs: Integer;
  WasPlaying: Boolean;
begin
  if (FVideoFile = '') or (FSeekMaxMs <= 0) then
    Exit;

  WasPlaying := PlaybackActiveOrPending;
  FAudioPlayback.SilenceOutput;
  TimerPlayback.Enabled := False;
  FRestartPlaybackTimer.Enabled := False;
  FPendingRestartPlayback := False;
  FPendingRestartMs := -1;
  FAudioPlayback.Stop;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > FSeekMaxMs then
    TargetMs := FSeekMaxMs;

  WriteVideoMinerDebugLog(Format('seek target_ms=%d was_playing=%s',
    [TargetMs, BoolToStr(WasPlaying, True)]));

  FSeeking := True;
  try
    if not TryShowFrameNearMs(TargetMs, ShownPositionMs, ErrorMessage) then
    begin
      SetStatusCaption('Failed to decode frame: ' + ErrorMessage);
      Exit;
    end;

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
var
  FrameDurationMs: Integer;
begin
  Result := FSeekMaxMs;
  if Result <= 0 then
    Exit;

  if FVideoInfo.Fps > 0 then
    FrameDurationMs := Max(1, Ceil(1000 / FVideoInfo.Fps))
  else
    FrameDurationMs := 33;

  Result := Max(0, FSeekMaxMs - FrameDurationMs);
end;

procedure TVideoMinerMainForm.StartPlaybackAtMs(PositionMs: Integer);
var
  ErrorMessage: string;
  OpenInfo: TVideoInfo;
  TargetMs: Integer;
begin
  if FVideoFile = '' then
    Exit;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > FSeekMaxMs then
    TargetMs := FSeekMaxMs;

  WriteVideoMinerDebugLog(Format('start_playback file="%s" requested_ms=%d target_ms=%d',
    [ExtractFileName(FVideoFile), PositionMs, TargetMs]));

  FDecoder.Close;
  if not FDecoder.Open(FVideoFile, OpenInfo, ErrorMessage) then
  begin
    FVideoView.PlaybackActive := False;
    SetStatusCaption('Failed to reopen video decoder: ' + ErrorMessage);
    Exit;
  end;

  if not FVideoView.ShowFrameAt(FDecoder, TargetMs, ErrorMessage) then
  begin
    FVideoView.PlaybackActive := False;
    SetStatusCaption('Failed to seek video decoder: ' + ErrorMessage);
    Exit;
  end;
  FCurrentVideoPositionMs := TargetMs;
  FSeekPositionMs := TargetMs;

  if not FAudioPlayback.StartAt(FVideoFile, FVideoInfo, TargetMs,
    ErrorMessage) then
  begin
    FVideoView.PlaybackActive := False;
    SetStatusCaption('Failed to start audio playback: ' + ErrorMessage);
    Exit;
  end;

  FSeekGuardRemaining := 0;
  TimerPlayback.Enabled := True;
  FVideoView.PlaybackActive := True;
  TimerPlaybackTimer(TimerPlayback);
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

  if AudioPositionMs - PositionMs <= VIDEO_AUDIO_SEEK_LAG_MS then
    Exit;

  Result := FVideoView.ShowFrameAt(FDecoder, AudioPositionMs, ErrorMessage);
  if Result then
  begin
    PositionMs := AudioPositionMs;
    FCurrentVideoPositionMs := AudioPositionMs;
  end;
  if (not Result) and
     (FSeekMaxMs - AudioPositionMs <= VIDEO_END_TOLERANCE_MS) then
  begin
    ErrorMessage := '';
    PositionMs := AudioPositionMs;
    FCurrentVideoPositionMs := AudioPositionMs;
    Result := True;
  end;
end;

procedure TVideoMinerMainForm.FinishPlaybackAtEnd;
begin
  case FEndAction of
    eaLoop:
      begin
        FUpdatingSeek := True;
        try
          FSeekPositionMs := 0;
        finally
          FUpdatingSeek := False;
        end;
        StartPlaybackAtMs(0);
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
  StartPlaybackAtMs(TargetMs);
end;

procedure TVideoMinerMainForm.WMNCHitTest(var Message: TWMNCHitTest);
var
  ClientPoint: TPoint;
  ScreenPoint: TPoint;
begin
  inherited;
  if Message.Result <> HTCLIENT then
    Exit;

  GetCursorPos(ScreenPoint);
  ClientPoint := ScreenToClient(ScreenPoint);

  if (ClientPoint.X < CUSTOM_RESIZE_BORDER) and
     (ClientPoint.Y < CUSTOM_RESIZE_BORDER) then
    Message.Result := HTTOPLEFT
  else if (ClientPoint.X >= ClientWidth - CUSTOM_RESIZE_BORDER) and
          (ClientPoint.Y < CUSTOM_RESIZE_BORDER) then
    Message.Result := HTTOPRIGHT
  else if (ClientPoint.X < CUSTOM_RESIZE_BORDER) and
          (ClientPoint.Y >= ClientHeight - CUSTOM_RESIZE_BORDER) then
    Message.Result := HTBOTTOMLEFT
  else if (ClientPoint.X >= ClientWidth - CUSTOM_RESIZE_BORDER) and
          (ClientPoint.Y >= ClientHeight - CUSTOM_RESIZE_BORDER) then
    Message.Result := HTBOTTOMRIGHT
  else if ClientPoint.Y < CUSTOM_RESIZE_BORDER then
    Message.Result := HTTOP
  else if ClientPoint.Y >= ClientHeight - CUSTOM_RESIZE_BORDER then
    Message.Result := HTBOTTOM
  else if ClientPoint.X < CUSTOM_RESIZE_BORDER then
    Message.Result := HTLEFT
  else if ClientPoint.X >= ClientWidth - CUSTOM_RESIZE_BORDER then
    Message.Result := HTRIGHT;
end;

procedure TVideoMinerMainForm.WMMove(var Message: TWMMove);
begin
  inherited;
  RememberNormalWindowBounds;
end;

procedure TVideoMinerMainForm.WMSize(var Message: TWMSize);
begin
  inherited;
  UpdateMaximizeButton;
  RememberNormalWindowBounds;
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
