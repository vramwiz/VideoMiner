unit VideoMinerMediaLoadController;

// 動画読み込み前後の状態リセットと、成功/失敗時の各 controller 反映をまとめる。

interface

uses
  Vcl.ExtCtrls, Vcl.Forms,
  FFmpegDecoder, VideoMinerAudioPlayback, VideoMinerChapterController,
  VideoMinerCurrentFileReloadController, VideoMinerMediaList, VideoMinerMediaOpen,
  VideoMinerMediaSession, VideoMinerNavigationController,
  VideoMinerPlaybackController, VideoMinerPlaybackTiming,
  VideoMinerSeekHoverPreviewController, VideoMinerThumbnailBrowserController,
  VideoMinerVideoView;

type
  TVideoMinerMediaLoadStatusProc = procedure(const Text: string) of object;
  TVideoMinerMediaLoadNotifyProc = procedure of object;
  TVideoMinerMediaLoadTitleProc = procedure(const Text: string) of object;

  TVideoMinerMediaLoadController = class
  private
    FAudioPlayback: TVideoMinerAudioPlayback;
    FChapterController: TVideoMinerChapterController;
    FCurrentFileReloadController: TVideoMinerCurrentFileReloadController;
    FHostForm: TCustomForm;
    FMediaList: TVideoMinerMediaList;
    FMediaSession: TVideoMinerMediaSession;
    FNavigationController: TVideoMinerNavigationController;
    FOnSetStatus: TVideoMinerMediaLoadStatusProc;
    FOnSetTitleBar: TVideoMinerMediaLoadTitleProc;
    FOnUpdateInfo: TVideoMinerMediaLoadNotifyProc;
    FPlaybackController: TVideoMinerPlaybackController;
    FPlaybackTimer: TTimer;
    FPreviewDecoder: TFFmpegDecoder;
    FSeekHoverPreviewController: TVideoMinerSeekHoverPreviewController;
    FThumbnailBrowserController: TVideoMinerThumbnailBrowserController;
    FVideoView: TVideoMinerVideoView;
    procedure SetFormTitle(const Text: string);
  public
    constructor Create(AHostForm: TCustomForm; AMediaSession: TVideoMinerMediaSession;
      AMediaList: TVideoMinerMediaList; APlaybackTimer: TTimer;
      APlaybackController: TVideoMinerPlaybackController;
      AAudioPlayback: TVideoMinerAudioPlayback; APreviewDecoder: TFFmpegDecoder;
      AVideoView: TVideoMinerVideoView;
      ACurrentFileReloadController: TVideoMinerCurrentFileReloadController;
      AChapterController: TVideoMinerChapterController;
      ASeekHoverPreviewController: TVideoMinerSeekHoverPreviewController;
      ANavigationController: TVideoMinerNavigationController;
      AThumbnailBrowserController: TVideoMinerThumbnailBrowserController);
    procedure ApplyOpenFailure(const ErrorMessage: string);
    procedure ApplyOpenSuccess(const OpenResult: TVideoMinerMediaOpenResult;
      var UpdatingSeek: Boolean);
    procedure BeginLoadCleanup(var UpdatingSeek, Seeking: Boolean;
      var SeekGuardRemaining: Integer);
    property OnSetStatus: TVideoMinerMediaLoadStatusProc read FOnSetStatus
      write FOnSetStatus;
    property OnSetTitleBar: TVideoMinerMediaLoadTitleProc read FOnSetTitleBar
      write FOnSetTitleBar;
    property OnUpdateInfo: TVideoMinerMediaLoadNotifyProc read FOnUpdateInfo
      write FOnUpdateInfo;
  end;

implementation

uses
  System.SysUtils;

constructor TVideoMinerMediaLoadController.Create(AHostForm: TCustomForm;
  AMediaSession: TVideoMinerMediaSession; AMediaList: TVideoMinerMediaList;
  APlaybackTimer: TTimer; APlaybackController: TVideoMinerPlaybackController;
  AAudioPlayback: TVideoMinerAudioPlayback; APreviewDecoder: TFFmpegDecoder;
  AVideoView: TVideoMinerVideoView;
  ACurrentFileReloadController: TVideoMinerCurrentFileReloadController;
  AChapterController: TVideoMinerChapterController;
  ASeekHoverPreviewController: TVideoMinerSeekHoverPreviewController;
  ANavigationController: TVideoMinerNavigationController;
  AThumbnailBrowserController: TVideoMinerThumbnailBrowserController);
begin
  inherited Create;
  FHostForm := AHostForm;
  FMediaSession := AMediaSession;
  FMediaList := AMediaList;
  FPlaybackTimer := APlaybackTimer;
  FPlaybackController := APlaybackController;
  FAudioPlayback := AAudioPlayback;
  FPreviewDecoder := APreviewDecoder;
  FVideoView := AVideoView;
  FCurrentFileReloadController := ACurrentFileReloadController;
  FChapterController := AChapterController;
  FSeekHoverPreviewController := ASeekHoverPreviewController;
  FNavigationController := ANavigationController;
  FThumbnailBrowserController := AThumbnailBrowserController;
end;

procedure TVideoMinerMediaLoadController.ApplyOpenFailure(
  const ErrorMessage: string);
begin
  FMediaSession.ClearMedia;
  if FCurrentFileReloadController <> nil then
  begin
    FCurrentFileReloadController.ConfigureWatch;
    FCurrentFileReloadController.UpdateOpenedFileStamp;
  end;
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  SetFormTitle('VideoMiner');
  if FNavigationController <> nil then
    FNavigationController.UpdateButtons;
  if Assigned(FOnSetStatus) then
    FOnSetStatus(ErrorMessage);
end;

procedure TVideoMinerMediaLoadController.ApplyOpenSuccess(
  const OpenResult: TVideoMinerMediaOpenResult; var UpdatingSeek: Boolean);
begin
  UpdatingSeek := True;
  try
    FMediaSession.ConfigureMedia(OpenResult.FileName, OpenResult.Info);
  finally
    UpdatingSeek := False;
  end;

  if FVideoView <> nil then
  begin
    FVideoView.SourceHasAlpha := FMediaSession.VideoInfo.HasAlpha;
    FVideoView.SeekWheelFrameStepMs :=
      VideoMinerFrameDurationMs(FMediaSession.VideoInfo.Fps);
  end;
  if FCurrentFileReloadController <> nil then
  begin
    FCurrentFileReloadController.ConfigureWatch;
    FCurrentFileReloadController.UpdateOpenedFileStamp;
  end;

  SetFormTitle(Format('%s (%d/%d)', [ExtractFileName(FMediaSession.VideoFile),
    FMediaList.CurrentIndex + 1, FMediaList.Count]));

  if FSeekHoverPreviewController <> nil then
    FSeekHoverPreviewController.ConfigureMedia(FMediaSession.VideoFile,
      FMediaSession.SeekMaxMs);

  if FPlaybackTimer <> nil then
    FPlaybackTimer.Interval := VideoMinerTimerIntervalMs(FMediaSession.VideoInfo.Fps);

  if FChapterController <> nil then
    FChapterController.LoadManualChapterState;
  if FNavigationController <> nil then
    FNavigationController.UpdateButtons;
  if FThumbnailBrowserController <> nil then
    FThumbnailBrowserController.RefreshMediaList;
  if Assigned(FOnUpdateInfo) then
    FOnUpdateInfo;
  if FChapterController <> nil then
    FChapterController.RefreshOverlay;
end;

procedure TVideoMinerMediaLoadController.BeginLoadCleanup(
  var UpdatingSeek, Seeking: Boolean; var SeekGuardRemaining: Integer);
begin
  if FCurrentFileReloadController <> nil then
    FCurrentFileReloadController.BeginLoad;

  if FChapterController <> nil then
  begin
    FChapterController.SaveManualChapterState;
    FChapterController.SaveLoopPlaybackPosition;
  end;

  if FPlaybackTimer <> nil then
    FPlaybackTimer.Enabled := False;
  if FPlaybackController <> nil then
    FPlaybackController.ClearRestart;
  if FAudioPlayback <> nil then
    FAudioPlayback.Stop;
  if FPreviewDecoder <> nil then
    FPreviewDecoder.Close;
  Seeking := False;
  SeekGuardRemaining := 0;
  if FChapterController <> nil then
    FChapterController.Clear;
  if FSeekHoverPreviewController <> nil then
    FSeekHoverPreviewController.ResetMedia;
  if FVideoView <> nil then
    FVideoView.Clear;

  UpdatingSeek := True;
  try
    FMediaSession.BeginLoad;
  finally
    UpdatingSeek := False;
  end;
end;

procedure TVideoMinerMediaLoadController.SetFormTitle(const Text: string);
begin
  if FHostForm <> nil then
    FHostForm.Caption := Text;
  if Assigned(FOnSetTitleBar) then
    FOnSetTitleBar(Text);
end;

end.
