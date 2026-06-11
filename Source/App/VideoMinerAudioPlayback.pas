unit VideoMinerAudioPlayback;

interface

uses
  System.Diagnostics, System.SysUtils, FFmpegDecoder, FFmpegDecoderTypes,
  VideoMinerDebugLog;

type
  TVideoMinerAudioPlayback = class
  private const
    AUDIO_OUTPUT_SAMPLE_RATE = 48000;
    AUDIO_TARGET_QUEUE_MS = 1000;
    AUDIO_START_QUEUE_MS = 180;
    AUDIO_FADE_IN_MS = 12;
  private
    FDecoder: TFFmpegDecoder;
    FFinished: Boolean;
    FStartSamples: Int64;
    FQueuedSamples: Int64;
    FVolumePercent: Integer;
    FMuted: Boolean;
    FApplyFadeInNext: Boolean;
    FOpenFileName: string;
    FPlaybackClock: TStopwatch;
    FPlaybackClockActive: Boolean;
    FPlaybackBaseMs: Integer;
    procedure ApplyFadeIn(var Pcm: TBytes);
    procedure ApplyOutputVolume;
    function PlaybackSamplePosition: Int64;
    procedure SetMuted(Value: Boolean);
    procedure SetVolumePercent(Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function StartAt(const FileName: string; const VideoInfo: TVideoInfo;
      PositionMs: Integer; out ErrorMessage: string): Boolean;
    procedure Stop;
    procedure StopOutput;
    procedure SilenceOutput;
    function Pump(out ErrorMessage: string): Boolean;
    function PlaybackPositionMs: Integer;
    property Muted: Boolean read FMuted write SetMuted;
    property VolumePercent: Integer read FVolumePercent write SetVolumePercent;
  end;

implementation

type
  PSmallIntArray = ^TSmallIntArray;
  TSmallIntArray = array[0..MaxInt div SizeOf(SmallInt) - 1] of SmallInt;

constructor TVideoMinerAudioPlayback.Create;
begin
  inherited Create;
  FDecoder := TFFmpegDecoder.Create;
  FFinished := True;
  FVolumePercent := 100;
  FOpenFileName := '';
  FPlaybackClockActive := False;
  FPlaybackBaseMs := 0;
end;

destructor TVideoMinerAudioPlayback.Destroy;
begin
  Stop;
  FDecoder.Free;
  inherited Destroy;
end;

function TVideoMinerAudioPlayback.StartAt(const FileName: string;
  const VideoInfo: TVideoInfo; PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  AudioInfo: TVideoInfo;
  Pcm: TBytes;
  SampleCount: Integer;
  TargetSampleCount: Integer;
  Finished: Boolean;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  StopMs: Double;
  OpenMs: Double;
  SeekMs: Double;
  DecodeMs: Double;
  OutputStartMs: Double;
  QueueMs: Double;
  DebugLogEnabled: Boolean;
begin
  ErrorMessage := '';
  Result := True;
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  TotalWatch := TStopwatch.StartNew;

  StepWatch := TStopwatch.StartNew;
  StopOutput;
  StopMs := StepWatch.Elapsed.TotalMilliseconds;
  OpenMs := 0;

  if (FileName = '') or (not VideoInfo.Audio.Present) or
     (VideoInfo.Audio.OpenError <> '') then
  begin
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_skip pos_ms=%d present=%s open_error="%s" stop_ms=%.3f total_ms=%.3f',
        [PositionMs, BoolToStr(VideoInfo.Audio.Present, True),
         VideoInfo.Audio.OpenError, StopMs, TotalWatch.Elapsed.TotalMilliseconds]));
    Exit;
  end;

  if not SameText(FOpenFileName, FileName) then
  begin
    FDecoder.Close;
    FOpenFileName := '';

    StepWatch := TStopwatch.StartNew;
    if not FDecoder.Open(FileName, AudioInfo, ErrorMessage) then
    begin
      OpenMs := StepWatch.Elapsed.TotalMilliseconds;
      if DebugLogEnabled then
        WriteVideoMinerDebugLog(Format(
          'audio_start_failed step="open" pos_ms=%d stop_ms=%.3f open_ms=%.3f total_ms=%.3f err="%s"',
          [PositionMs, StopMs, OpenMs, TotalWatch.Elapsed.TotalMilliseconds,
           ErrorMessage]));
      Result := False;
      Exit;
    end;
    OpenMs := StepWatch.Elapsed.TotalMilliseconds;
    FOpenFileName := FileName;
  end;
  StepWatch := TStopwatch.StartNew;
  if not FDecoder.SeekAudioToMs(PositionMs, ErrorMessage) then
  begin
    SeekMs := StepWatch.Elapsed.TotalMilliseconds;
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="seek" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    FDecoder.Close;
    FOpenFileName := '';
    Result := False;
    Exit;
  end;
  SeekMs := StepWatch.Elapsed.TotalMilliseconds;

  FFinished := False;
  FStartSamples := (Int64(PositionMs) * AUDIO_OUTPUT_SAMPLE_RATE + 500) div 1000;
  FQueuedSamples := FStartSamples;
  FApplyFadeInNext := True;
  FPlaybackBaseMs := PositionMs;
  FPlaybackClockActive := False;

  Pcm := nil;
  SampleCount := Integer(FQueuedSamples);
  TargetSampleCount := SampleCount +
    Round(AUDIO_START_QUEUE_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  StepWatch := TStopwatch.StartNew;
  if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount, Pcm,
    SampleCount, Finished, ErrorMessage) then
  begin
    DecodeMs := StepWatch.Elapsed.TotalMilliseconds;
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="decode" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs, DecodeMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    FDecoder.Close;
    FOpenFileName := '';
    FFinished := True;
    Result := False;
    Exit;
  end;
  DecodeMs := StepWatch.Elapsed.TotalMilliseconds;

  FQueuedSamples := SampleCount;
  FFinished := Finished;
  ApplyFadeIn(Pcm);

  StepWatch := TStopwatch.StartNew;
  if not FDecoder.StartAudioPlayback(ErrorMessage) then
  begin
    OutputStartMs := StepWatch.Elapsed.TotalMilliseconds;
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="output_start" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f output_start_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs, DecodeMs, OutputStartMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    FDecoder.Close;
    FOpenFileName := '';
    FFinished := True;
    Result := False;
    Exit;
  end;
  OutputStartMs := StepWatch.Elapsed.TotalMilliseconds;
  ApplyOutputVolume;

  StepWatch := TStopwatch.StartNew;
  if (Length(Pcm) > 0) and
     (not FDecoder.QueueAudioPcm16Stereo48k(Pcm, ErrorMessage)) then
  begin
    QueueMs := StepWatch.Elapsed.TotalMilliseconds;
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="queue" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs, DecodeMs, OutputStartMs, QueueMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    Stop;
    Result := False;
  end;
  QueueMs := StepWatch.Elapsed.TotalMilliseconds;

  if Result then
  begin
    FPlaybackClock := TStopwatch.StartNew;
    FPlaybackClockActive := True;
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start pos_ms=%d start_samples=%d queued_samples=%d initial_pcm_bytes=%d start_queue_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s',
        [PositionMs, FStartSamples, FQueuedSamples, Length(Pcm),
         AUDIO_START_QUEUE_MS, StopMs, OpenMs, SeekMs, DecodeMs, OutputStartMs,
         QueueMs, TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True)]));
  end;
end;

procedure TVideoMinerAudioPlayback.Stop;
begin
  StopOutput;
  if FDecoder <> nil then
    FDecoder.Close;
  FOpenFileName := '';
end;

procedure TVideoMinerAudioPlayback.StopOutput;
begin
  if FDecoder <> nil then
    FDecoder.StopAudioPlayback;
  FFinished := True;
  FStartSamples := 0;
  FQueuedSamples := 0;
  FApplyFadeInNext := False;
  FPlaybackClockActive := False;
  FPlaybackBaseMs := 0;
end;

procedure TVideoMinerAudioPlayback.SilenceOutput;
begin
  if FDecoder <> nil then
    FDecoder.SetAudioOutputVolume(0);
end;

function TVideoMinerAudioPlayback.PlaybackSamplePosition: Int64;
begin
  if not FPlaybackClockActive then
    Exit(FStartSamples);

  Result := (Int64(PlaybackPositionMs) * AUDIO_OUTPUT_SAMPLE_RATE + 500) div 1000;
end;

procedure TVideoMinerAudioPlayback.SetMuted(Value: Boolean);
begin
  if FMuted = Value then
    Exit;

  FMuted := Value;
  ApplyOutputVolume;
end;

procedure TVideoMinerAudioPlayback.SetVolumePercent(Value: Integer);
begin
  if Value < 0 then
    Value := 0
  else if Value > 100 then
    Value := 100;

  if FVolumePercent = Value then
    Exit;

  FVolumePercent := Value;
  ApplyOutputVolume;
end;

procedure TVideoMinerAudioPlayback.ApplyOutputVolume;
var
  EffectiveVolume: Integer;
begin
  if FDecoder = nil then
    Exit;

  if FMuted then
    EffectiveVolume := 0
  else
    EffectiveVolume := FVolumePercent;

  FDecoder.SetAudioOutputVolume(EffectiveVolume);
end;

procedure TVideoMinerAudioPlayback.ApplyFadeIn(var Pcm: TBytes);
var
  SampleCount: Integer;
  FrameIndex: Integer;
  ChannelIndex: Integer;
  FadeFrames: Integer;
  FadeScale: Double;
  Value: Integer;
  Samples: PSmallIntArray;
begin
  if (Length(Pcm) = 0) or (not FApplyFadeInNext) then
    Exit;

  SampleCount := Length(Pcm) div SizeOf(SmallInt);
  Samples := PSmallIntArray(@Pcm[0]);
  FadeFrames := Round(AUDIO_FADE_IN_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  if FadeFrames <= 0 then
  begin
    FApplyFadeInNext := False;
    Exit;
  end;

  for FrameIndex := 0 to (SampleCount div 2) - 1 do
  begin
    if FrameIndex >= FadeFrames then
      Break;

    FadeScale := FrameIndex / FadeFrames;

    for ChannelIndex := 0 to 1 do
    begin
      Value := Round(Samples^[FrameIndex * 2 + ChannelIndex] * FadeScale);
      if Value < Low(SmallInt) then
        Value := Low(SmallInt)
      else if Value > High(SmallInt) then
        Value := High(SmallInt);
      Samples^[FrameIndex * 2 + ChannelIndex] := SmallInt(Value);
    end;
  end;

  FApplyFadeInNext := False;
end;

function TVideoMinerAudioPlayback.Pump(out ErrorMessage: string): Boolean;
var
  Pcm: TBytes;
  SampleCount: Integer;
  PlaybackSampleCount: Int64;
  RawQueuedSampleCount: Int64;
  QueuedSampleCount: Int64;
  TargetQueuedSampleCount: Integer;
  TargetSampleCount: Integer;
  Finished: Boolean;
  QueuedBeforeMs: Int64;
  SkipReason: string;
begin
  ErrorMessage := '';
  Result := True;

  if (FDecoder = nil) or FFinished then
  begin
    if FDecoder = nil then
      SkipReason := 'decoder_nil'
    else
      SkipReason := 'finished';
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_pump_skip reason="%s" playback_ms=%d queued_samples=%d start_samples=%d finished=%s',
        [SkipReason, PlaybackPositionMs,
         FQueuedSamples, FStartSamples, BoolToStr(FFinished, True)]));
    Exit;
  end;

  Pcm := nil;
  SampleCount := Integer(FQueuedSamples);
  PlaybackSampleCount := PlaybackSamplePosition;
  RawQueuedSampleCount := Int64(FQueuedSamples) - Int64(PlaybackSampleCount);
  if RawQueuedSampleCount < 0 then
    QueuedSampleCount := 0
  else
    QueuedSampleCount := RawQueuedSampleCount;
  QueuedBeforeMs := Round(Int64(QueuedSampleCount) * 1000 / AUDIO_OUTPUT_SAMPLE_RATE);
  TargetQueuedSampleCount := Round(AUDIO_TARGET_QUEUE_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  if QueuedSampleCount >= TargetQueuedSampleCount then
  begin
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_pump_skip reason="queue_full" playback_ms=%d raw_queued_samples=%d queued_ms=%d target_ms=%d queued_samples=%d',
        [PlaybackPositionMs, RawQueuedSampleCount, QueuedBeforeMs,
         AUDIO_TARGET_QUEUE_MS, FQueuedSamples]));
    Exit;
  end;

  TargetSampleCount := SampleCount + Integer(TargetQueuedSampleCount - QueuedSampleCount);

  if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount, Pcm,
    SampleCount, Finished, ErrorMessage) then
  begin
    Stop;
    Result := False;
    Exit;
  end;

  FQueuedSamples := SampleCount;
  FFinished := Finished;

  ApplyFadeIn(Pcm);

  if (Length(Pcm) > 0) and
     (not FDecoder.QueueAudioPcm16Stereo48k(Pcm, ErrorMessage)) then
  begin
    Stop;
    Result := False;
  end;

  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'audio_pump playback_ms=%d raw_queued_before_samples=%d queued_before_ms=%d queued_after_ms=%d pcm_bytes=%d sample_count=%d finished=%s result=%s err="%s"',
      [PlaybackPositionMs, RawQueuedSampleCount, QueuedBeforeMs,
       Round((Int64(FQueuedSamples) - PlaybackSamplePosition) * 1000 / AUDIO_OUTPUT_SAMPLE_RATE),
       Length(Pcm), FQueuedSamples, BoolToStr(FFinished, True),
       BoolToStr(Result, True), ErrorMessage]));
end;

function TVideoMinerAudioPlayback.PlaybackPositionMs: Integer;
begin
  if (FDecoder = nil) or (FQueuedSamples <= 0) or (not FPlaybackClockActive) then
    Exit(-1);

  Result := FPlaybackBaseMs + Round(FPlaybackClock.Elapsed.TotalMilliseconds);
end;

end.
