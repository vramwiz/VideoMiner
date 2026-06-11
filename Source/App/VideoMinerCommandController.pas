unit VideoMinerCommandController;

interface

uses
  Vcl.ExtCtrls, VideoMinerAudioPlayback, VideoMinerShortcutBindings,
  VideoMinerVideoView, ShortcutAction;

type
  TVideoMinerCommandProc = procedure of object;
  TVideoMinerCommandBoolFunc = function: Boolean of object;
  TVideoMinerCommandDeltaProc = procedure(Delta: Integer) of object;
  TVideoMinerCommandSeekProc = procedure(PositionMs: Integer;
    ResumeIfPlaying: Boolean) of object;

  TVideoMinerCommandController = class
  private
    FAudioPlayback: TVideoMinerAudioPlayback;
    FVideoView: TVideoMinerVideoView;
    FOnChapterNavigate: TVideoMinerCommandDeltaProc;
    FOnNavigate: TVideoMinerCommandDeltaProc;
    FOnOpenDialog: TVideoMinerCommandProc;
    FOnPlaybackActiveOrPending: TVideoMinerCommandBoolFunc;
    FOnPlayFromCurrentPosition: TVideoMinerCommandProc;
    FOnSaveAudioSettings: TVideoMinerCommandProc;
    FOnSeekByMs: TVideoMinerCommandDeltaProc;
    FOnSeekToFirstFrame: TVideoMinerCommandProc;
    FOnSeekToLastFrame: TVideoMinerCommandProc;
    FOnSeekToMs: TVideoMinerCommandSeekProc;
    FOnStopPlayback: TVideoMinerCommandProc;
    FOnToggleFullScreen: TVideoMinerCommandProc;
    procedure SyncVolumeToView;
  public
    constructor Create(AudioPlayback: TVideoMinerAudioPlayback;
      VideoView: TVideoMinerVideoView);
    procedure BindVideoView;
    procedure RegisterShortcuts(Shortcuts: TShortcutAction);
    procedure ChangeVolumeBy(DeltaPercent: Integer);
    procedure FirstFrameClick(Sender: TObject);
    procedure FullScreenClick(Sender: TObject);
    procedure LastFrameClick(Sender: TObject);
    procedure MuteClick(Sender: TObject);
    procedure NavigateNextClick(Sender: TObject);
    procedure NavigatePreviousClick(Sender: TObject);
    procedure OpenDialog;
    procedure PlayPauseClick(Sender: TObject);
    procedure Seek(Sender: TObject; PositionMs: Integer);
    procedure SeekToFirstFrame;
    procedure SeekToLastFrame;
    procedure ShortcutChapterNext;
    procedure ShortcutChapterPrevious;
    procedure ShortcutNavigateNext;
    procedure ShortcutNavigatePrevious;
    procedure SkipBackwardClick(Sender: TObject);
    procedure SkipForwardClick(Sender: TObject);
    procedure ToggleFullScreen;
    procedure ToggleMute;
    procedure TogglePlayPause;
    procedure VolumeChange(Sender: TObject; VolumePercent: Integer);
    procedure VolumeDown;
    procedure VolumeUp;
    property OnChapterNavigate: TVideoMinerCommandDeltaProc
      read FOnChapterNavigate write FOnChapterNavigate;
    property OnNavigate: TVideoMinerCommandDeltaProc read FOnNavigate
      write FOnNavigate;
    property OnOpenDialog: TVideoMinerCommandProc read FOnOpenDialog
      write FOnOpenDialog;
    property OnPlaybackActiveOrPending: TVideoMinerCommandBoolFunc
      read FOnPlaybackActiveOrPending write FOnPlaybackActiveOrPending;
    property OnPlayFromCurrentPosition: TVideoMinerCommandProc
      read FOnPlayFromCurrentPosition write FOnPlayFromCurrentPosition;
    property OnSaveAudioSettings: TVideoMinerCommandProc read FOnSaveAudioSettings
      write FOnSaveAudioSettings;
    property OnSeekByMs: TVideoMinerCommandDeltaProc read FOnSeekByMs
      write FOnSeekByMs;
    property OnSeekToFirstFrame: TVideoMinerCommandProc read FOnSeekToFirstFrame
      write FOnSeekToFirstFrame;
    property OnSeekToLastFrame: TVideoMinerCommandProc read FOnSeekToLastFrame
      write FOnSeekToLastFrame;
    property OnSeekToMs: TVideoMinerCommandSeekProc read FOnSeekToMs
      write FOnSeekToMs;
    property OnStopPlayback: TVideoMinerCommandProc read FOnStopPlayback
      write FOnStopPlayback;
    property OnToggleFullScreen: TVideoMinerCommandProc read FOnToggleFullScreen
      write FOnToggleFullScreen;
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
  FVideoView.OnPlayPauseClick := PlayPauseClick;
  FVideoView.OnSeek := Seek;
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
  Handlers.OpenDialog := OpenDialog;
  Handlers.NavigatePrevious := ShortcutNavigatePrevious;
  Handlers.NavigateNext := ShortcutNavigateNext;
  Handlers.SeekToFirstFrame := SeekToFirstFrame;
  Handlers.SeekToLastFrame := SeekToLastFrame;
  Handlers.ToggleFullScreen := ToggleFullScreen;
  Handlers.ToggleMute := ToggleMute;
  Handlers.TogglePlayPause := TogglePlayPause;
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
