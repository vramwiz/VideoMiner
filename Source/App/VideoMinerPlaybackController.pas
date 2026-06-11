unit VideoMinerPlaybackController;

interface

uses
  Vcl.ExtCtrls, FFmpegDecoder, FFmpegDecoderTypes, VideoMinerAudioPlayback,
  VideoMinerChapterManager, VideoMinerSettings, VideoMinerVideoView;

type
  TVideoMinerPlaybackEndResult = (perStop, perLoop, perNext);
  TVideoMinerPlaybackDecodeResult = (pdrFrame, pdrEndOfStream, pdrError);
  TVideoMinerLaggingVideoResult = (lvrNoAction, lvrDropped, lvrSyncedToAudio,
    lvrError);
  TVideoMinerSeekGuardResult = (sgrNotGuarded, sgrAccepted, sgrContinue,
    sgrSyncedToTarget, sgrGuardError, sgrPresentError);
  TVideoMinerPlaybackNotifyProc = procedure of object;
  TVideoMinerPlaybackPositionProc = procedure(PositionMs: Integer) of object;
  TVideoMinerPlaybackStatusProc = procedure(const Text: string) of object;
  TVideoMinerPlaybackFrameFunc = function(const PositionMs: Integer): Boolean of object;
  TVideoMinerPlaybackStartProc = procedure(PositionMs: Integer;
    FrameAlreadyShown: Boolean) of object;

  TVideoMinerPlaybackController = class
  private
    FAudioPlayback: TVideoMinerAudioPlayback;
    FRestartPending: Boolean;
    FRestartPositionMs: Integer;
    FRestartTimer: TTimer;
    FVideoView: TVideoMinerVideoView;
    FPlaybackTimer: TTimer;
    FPreviewDecoder: TFFmpegDecoder;
  public
    constructor Create(PlaybackTimer, RestartTimer: TTimer;
      AudioPlayback: TVideoMinerAudioPlayback; VideoView: TVideoMinerVideoView;
      PreviewDecoder: TFFmpegDecoder);
    function ActiveOrPending: Boolean;
    procedure ClearRestart;
    function ConsumeRestart(out PositionMs: Integer): Boolean;
    function CurrentPositionMs(UsePlaybackPosition: Boolean;
      SeekPositionMs, CurrentVideoPositionMs, SeekMaxMs: Integer): Integer;
    function DecodeNextFrame(Decoder: TFFmpegDecoder; UseScratchFrame: Boolean;
      var ConvertFrame: Boolean; out PositionMs: Integer;
      out ErrorMessage: string): TVideoMinerPlaybackDecodeResult;
    function HandleSeekGuard(Decoder: TFFmpegDecoder; const VideoFile: string;
      DebugLogEnabled: Boolean; SeekGuardTargetMs: Integer;
      var SeekGuardRemaining: Integer; var PositionMs: Integer;
      var CurrentVideoPositionMs: Integer; var ConvertFrame: Boolean;
      out ErrorMessage: string): TVideoMinerSeekGuardResult;
    function HandleLaggingVideo(Decoder: TFFmpegDecoder; SeekMaxMs,
      AudioPositionMs, DropElapsedMs: Integer; var DropCount: Integer;
      var CurrentVideoPositionMs: Integer; var PositionMs: Integer;
      var ConvertFrame: Boolean; out ErrorMessage: string):
      TVideoMinerLaggingVideoResult;
    function ShouldDropBackwardScratchFrame(const VideoFile: string;
      DebugLogEnabled: Boolean; CurrentVideoPositionMs, PositionMs: Integer):
      Boolean;
    function PresentScratchFrame(var ConvertFrame: Boolean;
      out ErrorMessage: string): Boolean;
    function PlaybackLagMs(AudioPositionMs, PositionMs: Integer): Integer;
    function PlaybackPositionMs: Integer;
    function EndActionText(EndAction: TVideoMinerEndAction): string;
    function NextEndAction(EndAction: TVideoMinerEndAction):
      TVideoMinerEndAction;
    function FinishResult(EndAction: TVideoMinerEndAction;
      CanNavigateNext: Boolean): TVideoMinerPlaybackEndResult;
    procedure FinishAtEnd(EndAction: TVideoMinerEndAction;
      CanNavigateNext: Boolean; LoopStartMs, SeekMaxMs: Integer;
      var SeekPositionMs: Integer; var UpdatingSeek: Boolean;
      ShowFrameAtMs: TVideoMinerPlaybackFrameFunc;
      StartPlaybackAtMs: TVideoMinerPlaybackStartProc;
      NavigateNext: TVideoMinerPlaybackNotifyProc;
      UpdateInfo: TVideoMinerPlaybackNotifyProc);
    procedure ConfigureLoopSegment(EndAction: TVideoMinerEndAction;
      ChapterManager: TVideoMinerChapterManager; PositionMs, SeekMaxMs,
      LastFrameSeekPositionMs: Integer; var LoopSegmentStartMs,
      LoopSegmentEndMs: Integer);
    procedure LogPlaybackTick(const VideoFile: string; AudioPositionMs,
      PositionMs, LagMs, DropCount: Integer; DidSeekToAudio: Boolean;
      PumpMs, DecodeMs, SyncMs, TotalMs: Double; TimerInterval: Integer);
    function PrepareTick(IsSeeking, HasVideo: Boolean; SeekMaxMs: Integer;
      out AudioPositionMs: Integer; out ErrorMessage: string): Boolean;
    function SeekPositionForTick(PositionMs, AudioPositionMs,
      SeekMaxMs: Integer): Integer;
    procedure ScheduleRestart(PositionMs: Integer);
    function ShouldRestartLoop(EndAction: TVideoMinerEndAction;
      LoopSegmentStartMs, LoopSegmentEndMs, CurrentVideoPositionMs: Integer;
      out TargetMs: Integer): Boolean;
    function StartAtMs(Decoder: TFFmpegDecoder; const VideoFile: string;
      const VideoInfo: TVideoInfo; SeekMaxMs, PositionMs: Integer;
      FrameAlreadyShown: Boolean; out TargetMs: Integer;
      out ErrorMessage: string): Boolean;
    procedure StartPlaybackAtMs(Decoder: TFFmpegDecoder; const VideoFile: string;
      const VideoInfo: TVideoInfo; EndAction: TVideoMinerEndAction;
      ChapterManager: TVideoMinerChapterManager; SeekMaxMs, PositionMs,
      LastFrameSeekPositionMs: Integer; FrameAlreadyShown: Boolean;
      var CurrentVideoPositionMs, SeekPositionMs, LoopSegmentStartMs,
      LoopSegmentEndMs, SeekGuardTargetMs, SeekGuardRemaining: Integer;
      SetStatus: TVideoMinerPlaybackStatusProc);
    function SyncVideoToAudio(Decoder: TFFmpegDecoder; SeekMaxMs: Integer;
      var PositionMs: Integer; out ErrorMessage: string): Boolean;
    function ShowFrameNearMs(PositionMs, SeekMaxMs: Integer;
      out ShownPositionMs: Integer; out ErrorMessage: string): Boolean;
    procedure SeekToMs(const VideoFile: string; PositionMs: Integer;
      ResumeIfPlaying: Boolean; SeekMaxMs: Integer;
      var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
      SeekGuardRemaining: Integer; var UpdatingSeek, Seeking: Boolean;
      SetStatus: TVideoMinerPlaybackStatusProc;
      UpdateInfo: TVideoMinerPlaybackNotifyProc);
    procedure Tick(Decoder: TFFmpegDecoder; const VideoFile: string;
      EndAction: TVideoMinerEndAction; IsSeeking: Boolean; SeekMaxMs,
      LoopSegmentStartMs, LoopSegmentEndMs: Integer;
      var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
      SeekGuardRemaining: Integer; var UpdatingSeek: Boolean;
      SetStatus: TVideoMinerPlaybackStatusProc;
      FinishPlaybackAtEnd: TVideoMinerPlaybackNotifyProc;
      SeekToMs: TVideoMinerPlaybackPositionProc;
      UpdatePlaybackProgress: TVideoMinerPlaybackPositionProc;
      MaybeAutoCheckFrame: TVideoMinerPlaybackPositionProc);
    procedure StopForSeek;
    procedure StopAtEnd;
    procedure StopPlayback;
  end;

implementation

uses
  System.Diagnostics, System.SysUtils, VideoMinerDebugLog,
  VideoMinerPlaybackTiming;

constructor TVideoMinerPlaybackController.Create(PlaybackTimer,
  RestartTimer: TTimer; AudioPlayback: TVideoMinerAudioPlayback;
  VideoView: TVideoMinerVideoView; PreviewDecoder: TFFmpegDecoder);
begin
  inherited Create;
  FPlaybackTimer := PlaybackTimer;
  FRestartTimer := RestartTimer;
  FAudioPlayback := AudioPlayback;
  FVideoView := VideoView;
  FPreviewDecoder := PreviewDecoder;
  FRestartPending := False;
  FRestartPositionMs := -1;
end;

function TVideoMinerPlaybackController.ActiveOrPending: Boolean;
begin
  Result := ((FPlaybackTimer <> nil) and FPlaybackTimer.Enabled) or
    FRestartPending or
    ((FRestartTimer <> nil) and FRestartTimer.Enabled);
end;

procedure TVideoMinerPlaybackController.ClearRestart;
begin
  FRestartPending := False;
  FRestartPositionMs := -1;
  if FRestartTimer <> nil then
    FRestartTimer.Enabled := False;
end;

function TVideoMinerPlaybackController.ConsumeRestart(
  out PositionMs: Integer): Boolean;
begin
  if FRestartTimer <> nil then
    FRestartTimer.Enabled := False;

  Result := FRestartPending;
  if not Result then
  begin
    PositionMs := -1;
    Exit;
  end;

  FRestartPending := False;
  PositionMs := FRestartPositionMs;
  FRestartPositionMs := -1;
end;

function TVideoMinerPlaybackController.CurrentPositionMs(
  UsePlaybackPosition: Boolean; SeekPositionMs, CurrentVideoPositionMs,
  SeekMaxMs: Integer): Integer;
begin
  if UsePlaybackPosition then
    Result := FAudioPlayback.PlaybackPositionMs
  else
    Result := SeekPositionMs;

  if Result < 0 then
  begin
    if CurrentVideoPositionMs >= 0 then
      Result := CurrentVideoPositionMs
    else
      Result := SeekPositionMs;
  end;

  if Result < 0 then
    Result := 0
  else if Result > SeekMaxMs then
    Result := SeekMaxMs;
end;

function TVideoMinerPlaybackController.DecodeNextFrame(Decoder: TFFmpegDecoder;
  UseScratchFrame: Boolean; var ConvertFrame: Boolean; out PositionMs: Integer;
  out ErrorMessage: string): TVideoMinerPlaybackDecodeResult;
var
  Decoded: Boolean;
begin
  Result := pdrFrame;
  ErrorMessage := '';

  if UseScratchFrame then
    Decoded := FVideoView.DecodeNextFrameToScratch(Decoder, PositionMs,
      ErrorMessage)
  else
    Decoded := FVideoView.DecodeNextFrame(Decoder, ConvertFrame, PositionMs,
      ErrorMessage);

  if Decoded then
    Exit;

  if FPlaybackTimer <> nil then
    FPlaybackTimer.Enabled := False;
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;

  if ErrorMessage = 'End of stream.' then
    Result := pdrEndOfStream
  else
    Result := pdrError;
end;

function TVideoMinerPlaybackController.HandleSeekGuard(Decoder: TFFmpegDecoder;
  const VideoFile: string; DebugLogEnabled: Boolean; SeekGuardTargetMs: Integer;
  var SeekGuardRemaining: Integer; var PositionMs: Integer;
  var CurrentVideoPositionMs: Integer; var ConvertFrame: Boolean;
  out ErrorMessage: string): TVideoMinerSeekGuardResult;
begin
  Result := sgrNotGuarded;
  ErrorMessage := '';

  if (SeekGuardRemaining <= 0) or (PositionMs < 0) then
    Exit;

  Dec(SeekGuardRemaining);
  if not VideoMinerSeekGuardAccepts(SeekGuardTargetMs, PositionMs) then
  begin
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_guard_drop file="%s" target_ms=%d decoded_ms=%d remaining=%d',
        [ExtractFileName(VideoFile), SeekGuardTargetMs, PositionMs,
         SeekGuardRemaining]));

    if SeekGuardRemaining <= 0 then
    begin
      if FVideoView.ShowFrameAt(Decoder, SeekGuardTargetMs, ErrorMessage) then
      begin
        PositionMs := SeekGuardTargetMs;
        CurrentVideoPositionMs := SeekGuardTargetMs;
        Result := sgrSyncedToTarget;
        Exit;
      end;

      Result := sgrGuardError;
      Exit;
    end;

    Result := sgrContinue;
    Exit;
  end;

  SeekGuardRemaining := 0;
  if not FVideoView.ShowFrameAt(Decoder, PositionMs, ErrorMessage) then
  begin
    Result := sgrPresentError;
    Exit;
  end;

  ConvertFrame := True;
  Result := sgrAccepted;
end;

function TVideoMinerPlaybackController.HandleLaggingVideo(
  Decoder: TFFmpegDecoder; SeekMaxMs, AudioPositionMs, DropElapsedMs: Integer;
  var DropCount: Integer; var CurrentVideoPositionMs: Integer;
  var PositionMs: Integer; var ConvertFrame: Boolean;
  out ErrorMessage: string): TVideoMinerLaggingVideoResult;
begin
  Result := lvrNoAction;
  ErrorMessage := '';

  if not VideoMinerVideoLagsAudio(CurrentVideoPositionMs, AudioPositionMs) then
    Exit;

  if VideoMinerShouldDropFrame(CurrentVideoPositionMs, AudioPositionMs,
    DropCount, DropElapsedMs) then
  begin
    ConvertFrame := False;
    Inc(DropCount);
    Result := lvrDropped;
    Exit;
  end;

  if FVideoView.ShowFrameAt(Decoder, AudioPositionMs, ErrorMessage) then
  begin
    PositionMs := AudioPositionMs;
    CurrentVideoPositionMs := AudioPositionMs;
    Result := lvrSyncedToAudio;
    Exit;
  end;

  if VideoMinerNearEnd(SeekMaxMs, AudioPositionMs) then
  begin
    ErrorMessage := '';
    PositionMs := AudioPositionMs;
    CurrentVideoPositionMs := AudioPositionMs;
    Result := lvrSyncedToAudio;
    Exit;
  end;

  Result := lvrError;
end;

function TVideoMinerPlaybackController.EndActionText(
  EndAction: TVideoMinerEndAction): string;
begin
  case EndAction of
    eaLoop:
      Result := 'Loop';
    eaNext:
      Result := 'Next';
  else
    Result := 'Stop';
  end;
end;

function TVideoMinerPlaybackController.FinishResult(
  EndAction: TVideoMinerEndAction;
  CanNavigateNext: Boolean): TVideoMinerPlaybackEndResult;
begin
  case EndAction of
    eaLoop:
      Result := perLoop;
    eaNext:
      begin
        if CanNavigateNext then
          Result := perNext
        else
          Result := perStop;
      end;
  else
    Result := perStop;
  end;
end;

procedure TVideoMinerPlaybackController.FinishAtEnd(
  EndAction: TVideoMinerEndAction; CanNavigateNext: Boolean; LoopStartMs,
  SeekMaxMs: Integer; var SeekPositionMs: Integer; var UpdatingSeek: Boolean;
  ShowFrameAtMs: TVideoMinerPlaybackFrameFunc;
  StartPlaybackAtMs: TVideoMinerPlaybackStartProc;
  NavigateNext: TVideoMinerPlaybackNotifyProc;
  UpdateInfo: TVideoMinerPlaybackNotifyProc);
var
  FrameShown: Boolean;
begin
  case FinishResult(EndAction, CanNavigateNext) of
    perLoop:
      begin
        UpdatingSeek := True;
        try
          SeekPositionMs := LoopStartMs;
        finally
          UpdatingSeek := False;
        end;
        FrameShown := Assigned(ShowFrameAtMs) and ShowFrameAtMs(LoopStartMs);
        if Assigned(StartPlaybackAtMs) then
          StartPlaybackAtMs(LoopStartMs, FrameShown);
        Exit;
      end;
    perNext:
      begin
        if Assigned(NavigateNext) then
          NavigateNext;
        Exit;
      end;
  end;

  UpdatingSeek := True;
  try
    SeekPositionMs := SeekMaxMs;
  finally
    UpdatingSeek := False;
  end;
  StopAtEnd;
  if Assigned(UpdateInfo) then
    UpdateInfo;
end;

procedure TVideoMinerPlaybackController.ConfigureLoopSegment(
  EndAction: TVideoMinerEndAction; ChapterManager: TVideoMinerChapterManager;
  PositionMs, SeekMaxMs, LastFrameSeekPositionMs: Integer;
  var LoopSegmentStartMs, LoopSegmentEndMs: Integer);
var
  Segment: TVideoMinerLoopSegment;
begin
  if (EndAction <> eaLoop) or (SeekMaxMs <= 0) then
  begin
    LoopSegmentStartMs := -1;
    LoopSegmentEndMs := -1;
    Exit;
  end;

  if ChapterManager = nil then
  begin
    LoopSegmentStartMs := 0;
    LoopSegmentEndMs := LastFrameSeekPositionMs;
    Exit;
  end;

  Segment := ChapterManager.LoopSegmentForPosition(PositionMs,
    LastFrameSeekPositionMs);
  LoopSegmentStartMs := Segment.StartMs;
  LoopSegmentEndMs := Segment.EndMs;
end;

function TVideoMinerPlaybackController.NextEndAction(
  EndAction: TVideoMinerEndAction): TVideoMinerEndAction;
begin
  case EndAction of
    eaStop:
      Result := eaLoop;
    eaLoop:
      Result := eaNext;
  else
    Result := eaStop;
  end;
end;

function TVideoMinerPlaybackController.PrepareTick(IsSeeking,
  HasVideo: Boolean; SeekMaxMs: Integer; out AudioPositionMs: Integer;
  out ErrorMessage: string): Boolean;
begin
  Result := False;
  AudioPositionMs := -1;
  ErrorMessage := '';

  if IsSeeking then
    Exit;

  if not HasVideo then
  begin
    if FPlaybackTimer <> nil then
      FPlaybackTimer.Enabled := False;
    if FVideoView <> nil then
      FVideoView.PlaybackActive := False;
    Exit;
  end;

  if not FAudioPlayback.Pump(ErrorMessage) then
  begin
    ErrorMessage := 'Failed to play audio: ' + ErrorMessage;
    Exit;
  end;

  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if AudioPositionMs > SeekMaxMs then
    AudioPositionMs := SeekMaxMs;

  Result := True;
end;

function TVideoMinerPlaybackController.PresentScratchFrame(
  var ConvertFrame: Boolean; out ErrorMessage: string): Boolean;
begin
  Result := FVideoView.PresentScratchFrame(ErrorMessage);
  if Result then
    ConvertFrame := True;
end;

function TVideoMinerPlaybackController.PlaybackLagMs(AudioPositionMs,
  PositionMs: Integer): Integer;
begin
  if (AudioPositionMs >= 0) and (PositionMs >= 0) then
    Result := AudioPositionMs - PositionMs
  else
    Result := 0;
end;

function TVideoMinerPlaybackController.PlaybackPositionMs: Integer;
begin
  Result := FAudioPlayback.PlaybackPositionMs;
end;

procedure TVideoMinerPlaybackController.LogPlaybackTick(const VideoFile: string;
  AudioPositionMs, PositionMs, LagMs, DropCount: Integer;
  DidSeekToAudio: Boolean; PumpMs, DecodeMs, SyncMs, TotalMs: Double;
  TimerInterval: Integer);
begin
  WriteVideoMinerDebugLog(Format(
    'playback_tick file="%s" audio_ms=%d video_ms=%d lag_ms=%d drop_count=%d seek_to_audio=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f timer_interval=%d',
    [ExtractFileName(VideoFile), AudioPositionMs, PositionMs, LagMs, DropCount,
     BoolToStr(DidSeekToAudio, True), PumpMs, DecodeMs, SyncMs, TotalMs,
     TimerInterval]));
end;

procedure TVideoMinerPlaybackController.ScheduleRestart(PositionMs: Integer);
begin
  FRestartPending := True;
  FRestartPositionMs := PositionMs;
  if FRestartTimer <> nil then
  begin
    FRestartTimer.Enabled := False;
    FRestartTimer.Enabled := True;
  end;
end;

function TVideoMinerPlaybackController.SeekPositionForTick(PositionMs,
  AudioPositionMs, SeekMaxMs: Integer): Integer;
begin
  Result := PositionMs;
  if PositionMs < 0 then
    Exit;

  if AudioPositionMs >= 0 then
    Result := AudioPositionMs
  else if PositionMs > SeekMaxMs then
    Result := SeekMaxMs;
end;

function TVideoMinerPlaybackController.ShowFrameNearMs(PositionMs,
  SeekMaxMs: Integer; out ShownPositionMs: Integer;
  out ErrorMessage: string): Boolean;
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
    else if AttemptMs > SeekMaxMs then
      AttemptMs := SeekMaxMs;

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

    if FVideoView.ShowFrameAt(FPreviewDecoder, AttemptMs,
      LastErrorMessage) then
    begin
      ShownPositionMs := AttemptMs;
      Result := True;
      Exit;
    end;
  end;

  ErrorMessage := LastErrorMessage;
end;

procedure TVideoMinerPlaybackController.SeekToMs(const VideoFile: string;
  PositionMs: Integer; ResumeIfPlaying: Boolean; SeekMaxMs: Integer;
  var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
  SeekGuardRemaining: Integer; var UpdatingSeek, Seeking: Boolean;
  SetStatus: TVideoMinerPlaybackStatusProc;
  UpdateInfo: TVideoMinerPlaybackNotifyProc);
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
  if (VideoFile = '') or (SeekMaxMs <= 0) then
    Exit;

  TotalWatch := TStopwatch.StartNew;

  WasPlaying := ActiveOrPending;
  StepWatch := TStopwatch.StartNew;
  StopForSeek;
  StopMs := StepWatch.Elapsed.TotalMilliseconds;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > SeekMaxMs then
    TargetMs := SeekMaxMs;

  WriteVideoMinerDebugLog(Format('seek target_ms=%d was_playing=%s',
    [TargetMs, BoolToStr(WasPlaying, True)]));

  Seeking := True;
  try
    StepWatch := TStopwatch.StartNew;
    if not ShowFrameNearMs(TargetMs, SeekMaxMs, ShownPositionMs,
      ErrorMessage) then
    begin
      PreviewMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerDebugLog(Format(
        'seek_failed step="preview" target_ms=%d was_playing=%s stop_ms=%.3f preview_ms=%.3f total_ms=%.3f err="%s"',
        [TargetMs, BoolToStr(WasPlaying, True), StopMs, PreviewMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
      if Assigned(SetStatus) then
        SetStatus('Failed to decode frame: ' + ErrorMessage);
      Exit;
    end;
    PreviewMs := StepWatch.Elapsed.TotalMilliseconds;

    CurrentVideoPositionMs := ShownPositionMs;
    UpdatingSeek := True;
    try
      SeekPositionMs := ShownPositionMs;
    finally
      UpdatingSeek := False;
    end;

    if Assigned(UpdateInfo) then
      UpdateInfo;
    SeekGuardTargetMs := ShownPositionMs;
    SeekGuardRemaining := 3;
  finally
    Seeking := False;
  end;

  if ResumeIfPlaying and WasPlaying and (ShownPositionMs < SeekMaxMs) then
    ScheduleRestart(ShownPositionMs);

  WriteVideoMinerDebugLog(Format(
    'seek_done target_ms=%d shown_ms=%d was_playing=%s resume=%s stop_ms=%.3f preview_ms=%.3f total_ms=%.3f',
    [TargetMs, ShownPositionMs, BoolToStr(WasPlaying, True),
     BoolToStr(ResumeIfPlaying and WasPlaying and (ShownPositionMs < SeekMaxMs), True),
     StopMs, PreviewMs, TotalWatch.Elapsed.TotalMilliseconds]));
end;

function TVideoMinerPlaybackController.ShouldRestartLoop(
  EndAction: TVideoMinerEndAction; LoopSegmentStartMs, LoopSegmentEndMs,
  CurrentVideoPositionMs: Integer; out TargetMs: Integer): Boolean;
begin
  TargetMs := LoopSegmentStartMs;
  Result := (EndAction = eaLoop) and (LoopSegmentStartMs >= 0) and
    (LoopSegmentEndMs > LoopSegmentStartMs) and
    (CurrentVideoPositionMs >= LoopSegmentEndMs);
end;

function TVideoMinerPlaybackController.StartAtMs(Decoder: TFFmpegDecoder;
  const VideoFile: string; const VideoInfo: TVideoInfo; SeekMaxMs,
  PositionMs: Integer; FrameAlreadyShown: Boolean; out TargetMs: Integer;
  out ErrorMessage: string): Boolean;
var
  OpenInfo: TVideoInfo;
  ReuseErrorMessage: string;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  VideoPrepareMs: Double;
  VideoSeekMs: Double;
  AudioStartMs: Double;
  VideoReopened: Boolean;
begin
  Result := False;
  ErrorMessage := '';

  if VideoFile = '' then
    Exit;

  TotalWatch := TStopwatch.StartNew;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > SeekMaxMs then
    TargetMs := SeekMaxMs;

  WriteVideoMinerDebugLog(Format(
    'start_playback file="%s" requested_ms=%d target_ms=%d frame_already_shown=%s',
    [ExtractFileName(VideoFile), PositionMs, TargetMs,
     BoolToStr(FrameAlreadyShown, True)]));

  VideoPrepareMs := 0;
  VideoReopened := False;

  StepWatch := TStopwatch.StartNew;
  if not FVideoView.ShowFrameAt(Decoder, TargetMs, ReuseErrorMessage,
    not FrameAlreadyShown) then
  begin
    VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
    WriteVideoMinerDebugLog(Format(
      'start_playback_reuse_failed file="%s" target_ms=%d video_seek_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(VideoFile), TargetMs, VideoSeekMs,
       TotalWatch.Elapsed.TotalMilliseconds, ReuseErrorMessage]));

    StepWatch := TStopwatch.StartNew;
    Decoder.Close;
    if not Decoder.Open(VideoFile, OpenInfo, ErrorMessage) then
    begin
      VideoPrepareMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerDebugLog(Format(
        'start_playback_failed step="video_open_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
      FVideoView.PlaybackActive := False;
      ErrorMessage := 'Failed to reopen video decoder: ' + ErrorMessage;
      Exit;
    end;
    VideoPrepareMs := StepWatch.Elapsed.TotalMilliseconds;
    VideoReopened := True;

    StepWatch := TStopwatch.StartNew;
    if not FVideoView.ShowFrameAt(Decoder, TargetMs, ErrorMessage,
      not FrameAlreadyShown) then
    begin
      VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerDebugLog(Format(
        'start_playback_failed step="video_seek_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
      FVideoView.PlaybackActive := False;
      ErrorMessage := 'Failed to seek video decoder: ' + ErrorMessage;
      Exit;
    end;
  end;
  VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if not FAudioPlayback.StartAt(VideoFile, VideoInfo, TargetMs,
    ErrorMessage) then
  begin
    AudioStartMs := StepWatch.Elapsed.TotalMilliseconds;
    WriteVideoMinerDebugLog(Format(
      'start_playback_failed step="audio_start" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
       AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    FVideoView.PlaybackActive := False;
    ErrorMessage := 'Failed to start audio playback: ' + ErrorMessage;
    Exit;
  end;
  AudioStartMs := StepWatch.Elapsed.TotalMilliseconds;

  FPlaybackTimer.Enabled := True;
  FVideoView.PlaybackActive := True;
  WriteVideoMinerDebugLog(Format(
    'start_playback_done file="%s" target_ms=%d frame_already_shown=%s video_reopen=%s video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f',
    [ExtractFileName(VideoFile), TargetMs, BoolToStr(FrameAlreadyShown, True),
     BoolToStr(VideoReopened, True), VideoPrepareMs, VideoSeekMs,
     AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds]));

  Result := True;
end;

procedure TVideoMinerPlaybackController.StartPlaybackAtMs(
  Decoder: TFFmpegDecoder; const VideoFile: string; const VideoInfo: TVideoInfo;
  EndAction: TVideoMinerEndAction; ChapterManager: TVideoMinerChapterManager;
  SeekMaxMs, PositionMs, LastFrameSeekPositionMs: Integer;
  FrameAlreadyShown: Boolean; var CurrentVideoPositionMs, SeekPositionMs,
  LoopSegmentStartMs, LoopSegmentEndMs, SeekGuardTargetMs,
  SeekGuardRemaining: Integer; SetStatus: TVideoMinerPlaybackStatusProc);
var
  ErrorMessage: string;
  TargetMs: Integer;
begin
  if VideoFile = '' then
    Exit;

  if not StartAtMs(Decoder, VideoFile, VideoInfo, SeekMaxMs, PositionMs,
    FrameAlreadyShown, TargetMs, ErrorMessage) then
  begin
    if (ErrorMessage <> '') and Assigned(SetStatus) then
      SetStatus(ErrorMessage);
    Exit;
  end;

  CurrentVideoPositionMs := TargetMs;
  SeekPositionMs := TargetMs;
  ConfigureLoopSegment(EndAction, ChapterManager, TargetMs, SeekMaxMs,
    LastFrameSeekPositionMs, LoopSegmentStartMs, LoopSegmentEndMs);

  SeekGuardTargetMs := TargetMs;
  SeekGuardRemaining := VideoMinerDefaultSeekGuardFrames;
end;

function TVideoMinerPlaybackController.ShouldDropBackwardScratchFrame(
  const VideoFile: string; DebugLogEnabled: Boolean; CurrentVideoPositionMs,
  PositionMs: Integer): Boolean;
begin
  Result := VideoMinerBackwardScratchFrame(PositionMs, CurrentVideoPositionMs);
  if Result and DebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'playback_backward_drop file="%s" current_ms=%d decoded_ms=%d',
      [ExtractFileName(VideoFile), CurrentVideoPositionMs, PositionMs]));
end;

function TVideoMinerPlaybackController.SyncVideoToAudio(Decoder: TFFmpegDecoder;
  SeekMaxMs: Integer; var PositionMs: Integer;
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

  if AudioPositionMs > SeekMaxMs then
    AudioPositionMs := SeekMaxMs;

  if not VideoMinerShouldSeekVideoToAudio(PositionMs, AudioPositionMs) then
    Exit;

  Result := FVideoView.ShowFrameAt(Decoder, AudioPositionMs, ErrorMessage);
  if Result then
    PositionMs := AudioPositionMs;

  if (not Result) and VideoMinerNearEnd(SeekMaxMs, AudioPositionMs) then
  begin
    ErrorMessage := '';
    PositionMs := AudioPositionMs;
    Result := True;
  end;
end;

procedure TVideoMinerPlaybackController.Tick(Decoder: TFFmpegDecoder;
  const VideoFile: string; EndAction: TVideoMinerEndAction; IsSeeking: Boolean;
  SeekMaxMs, LoopSegmentStartMs, LoopSegmentEndMs: Integer;
  var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
  SeekGuardRemaining: Integer; var UpdatingSeek: Boolean;
  SetStatus: TVideoMinerPlaybackStatusProc;
  FinishPlaybackAtEnd: TVideoMinerPlaybackNotifyProc;
  SeekToMs: TVideoMinerPlaybackPositionProc;
  UpdatePlaybackProgress: TVideoMinerPlaybackPositionProc;
  MaybeAutoCheckFrame: TVideoMinerPlaybackPositionProc);
var
  ErrorMessage: string;
  PositionMs: Integer;
  AudioPositionMs: Integer;
  LagMs: Integer;
  DropCount: Integer;
  DropWatch: TStopwatch;
  LoopTargetMs: Integer;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  PumpMs: Double;
  DecodeMs: Double;
  SyncMs: Double;
  ConvertFrame: Boolean;
  DidSeekToAudio: Boolean;
  DebugLogEnabled: Boolean;
  DecodeResult: TVideoMinerPlaybackDecodeResult;
  GuardingSeek: Boolean;
  LaggingVideoResult: TVideoMinerLaggingVideoResult;
  SeekGuardResult: TVideoMinerSeekGuardResult;
  UseScratchFrame: Boolean;
begin
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  if DebugLogEnabled then
    TotalWatch := TStopwatch.StartNew;
  PumpMs := 0;
  DecodeMs := 0;
  SyncMs := 0;

  if DebugLogEnabled then
    StepWatch := TStopwatch.StartNew;
  if not PrepareTick(IsSeeking, (VideoFile <> '') and (Decoder <> nil),
    SeekMaxMs, AudioPositionMs, ErrorMessage) then
  begin
    if (ErrorMessage <> '') and Assigned(SetStatus) then
      SetStatus(ErrorMessage);
    Exit;
  end;
  if DebugLogEnabled then
    PumpMs := StepWatch.Elapsed.TotalMilliseconds;

  PositionMs := -1;
  DropCount := 0;
  DropWatch := TStopwatch.StartNew;
  DidSeekToAudio := False;
  repeat
    ConvertFrame := True;
    GuardingSeek := SeekGuardRemaining > 0;
    if GuardingSeek then
      ConvertFrame := False;

    LaggingVideoResult := HandleLaggingVideo(Decoder, SeekMaxMs,
      AudioPositionMs, DropWatch.ElapsedMilliseconds, DropCount,
      CurrentVideoPositionMs, PositionMs, ConvertFrame, ErrorMessage);
    case LaggingVideoResult of
      lvrSyncedToAudio:
        begin
          DidSeekToAudio := True;
          Break;
        end;
      lvrError:
        begin
          if Assigned(SetStatus) then
            SetStatus('Failed to sync video: ' + ErrorMessage);
          Exit;
        end;
    end;

    UseScratchFrame := ConvertFrame and (AudioPositionMs < 0);

    if DebugLogEnabled then
      StepWatch := TStopwatch.StartNew;
    DecodeResult := DecodeNextFrame(Decoder, UseScratchFrame, ConvertFrame,
      PositionMs, ErrorMessage);
    if DecodeResult <> pdrFrame then
    begin
      if DecodeResult = pdrEndOfStream then
      begin
        if Assigned(FinishPlaybackAtEnd) then
          FinishPlaybackAtEnd;
      end
      else if Assigned(SetStatus) then
        SetStatus('Failed to decode next frame: ' + ErrorMessage);
      Exit;
    end;
    if DebugLogEnabled then
      DecodeMs := DecodeMs + StepWatch.Elapsed.TotalMilliseconds;

    if UseScratchFrame and ShouldDropBackwardScratchFrame(VideoFile,
      DebugLogEnabled, CurrentVideoPositionMs, PositionMs) then
    begin
      ConvertFrame := False;
      Continue;
    end;

    SeekGuardResult := HandleSeekGuard(Decoder, VideoFile, DebugLogEnabled,
      SeekGuardTargetMs, SeekGuardRemaining, PositionMs, CurrentVideoPositionMs,
      ConvertFrame, ErrorMessage);
    case SeekGuardResult of
      sgrContinue:
        Continue;
      sgrSyncedToTarget:
        begin
          DidSeekToAudio := True;
          Break;
        end;
      sgrGuardError:
        begin
          if Assigned(SetStatus) then
            SetStatus('Failed to guard seek frame: ' + ErrorMessage);
          Exit;
        end;
      sgrPresentError:
        begin
          if Assigned(SetStatus) then
            SetStatus('Failed to present guarded frame: ' + ErrorMessage);
          Exit;
        end;
    end;

    if UseScratchFrame then
    begin
      if not PresentScratchFrame(ConvertFrame, ErrorMessage) then
      begin
        if Assigned(SetStatus) then
          SetStatus('Failed to present next frame: ' + ErrorMessage);
        Exit;
      end;
    end;

    if PositionMs >= 0 then
      CurrentVideoPositionMs := PositionMs;
  until ConvertFrame;

  if DebugLogEnabled then
    StepWatch := TStopwatch.StartNew;
  if (not DidSeekToAudio) and
     (not SyncVideoToAudio(Decoder, SeekMaxMs, PositionMs, ErrorMessage)) then
  begin
    if Assigned(SetStatus) then
      SetStatus('Failed to sync video: ' + ErrorMessage);
    Exit;
  end;
  if PositionMs >= 0 then
    CurrentVideoPositionMs := PositionMs;
  if DebugLogEnabled then
    SyncMs := StepWatch.Elapsed.TotalMilliseconds;

  if ShouldRestartLoop(EndAction, LoopSegmentStartMs, LoopSegmentEndMs,
    CurrentVideoPositionMs, LoopTargetMs) then
  begin
    if Assigned(SeekToMs) then
      SeekToMs(LoopTargetMs);
    Exit;
  end;

  if PositionMs >= 0 then
  begin
    UpdatingSeek := True;
    try
      SeekPositionMs := SeekPositionForTick(PositionMs, AudioPositionMs,
        SeekMaxMs);
    finally
      UpdatingSeek := False;
    end;
  end;

  AudioPositionMs := PlaybackPositionMs;
  LagMs := PlaybackLagMs(AudioPositionMs, PositionMs);
  if Assigned(UpdatePlaybackProgress) then
    UpdatePlaybackProgress(SeekPositionMs);
  if Assigned(MaybeAutoCheckFrame) then
    MaybeAutoCheckFrame(CurrentVideoPositionMs);
  if DebugLogEnabled then
    LogPlaybackTick(VideoFile, AudioPositionMs, PositionMs, LagMs, DropCount,
      DidSeekToAudio, PumpMs, DecodeMs, SyncMs,
      TotalWatch.Elapsed.TotalMilliseconds, FPlaybackTimer.Interval);
end;

procedure TVideoMinerPlaybackController.StopForSeek;
begin
  if FAudioPlayback <> nil then
    FAudioPlayback.SilenceOutput;
  if FPlaybackTimer <> nil then
    FPlaybackTimer.Enabled := False;
  ClearRestart;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;
end;

procedure TVideoMinerPlaybackController.StopAtEnd;
begin
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
end;

procedure TVideoMinerPlaybackController.StopPlayback;
begin
  if FPlaybackTimer <> nil then
    FPlaybackTimer.Enabled := False;
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  ClearRestart;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;
end;

end.
