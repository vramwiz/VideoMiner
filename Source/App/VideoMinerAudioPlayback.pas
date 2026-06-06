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
    AUDIO_FADE_IN_MS = 12;
  private
    FDecoder: TFFmpegDecoder;
    FFinished: Boolean;
    FStartSamples: Integer;
    FQueuedSamples: Integer;
    FVolumePercent: Integer;
    FMuted: Boolean;
    FApplyFadeInNext: Boolean;
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
begin
  ErrorMessage := '';
  Result := True;

  Stop;

  if (FileName = '') or (not VideoInfo.Audio.Present) or
     (VideoInfo.Audio.OpenError <> '') then
    Exit;

  if not FDecoder.Open(FileName, AudioInfo, ErrorMessage) then
  begin
    Result := False;
    Exit;
  end;

  if not FDecoder.SeekAudioToMs(PositionMs, ErrorMessage) then
  begin
    FDecoder.Close;
    Result := False;
    Exit;
  end;

  FFinished := False;
  FStartSamples := Round(PositionMs * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  FQueuedSamples := FStartSamples;
  FApplyFadeInNext := True;
  FPlaybackBaseMs := PositionMs;
  FPlaybackClockActive := False;

  Pcm := nil;
  SampleCount := FQueuedSamples;
  TargetSampleCount := FQueuedSamples +
    Round(AUDIO_TARGET_QUEUE_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount, Pcm,
    SampleCount, Finished, ErrorMessage) then
  begin
    FDecoder.Close;
    FFinished := True;
    Result := False;
    Exit;
  end;

  FQueuedSamples := SampleCount;
  FFinished := Finished;
  ApplyFadeIn(Pcm);

  if not FDecoder.StartAudioPlayback(ErrorMessage) then
  begin
    FDecoder.Close;
    FFinished := True;
    Result := False;
    Exit;
  end;
  ApplyOutputVolume;

  if (Length(Pcm) > 0) and
     (not FDecoder.QueueAudioPcm16Stereo48k(Pcm, ErrorMessage)) then
  begin
    Stop;
    Result := False;
  end;

  if Result then
  begin
    FPlaybackClock := TStopwatch.StartNew;
    FPlaybackClockActive := True;
    WriteVideoMinerDebugLog(Format(
      'audio_start pos_ms=%d start_samples=%d queued_samples=%d initial_pcm_bytes=%d finished=%s',
      [PositionMs, FStartSamples, FQueuedSamples, Length(Pcm),
       BoolToStr(FFinished, True)]));
  end;
end;

procedure TVideoMinerAudioPlayback.Stop;
begin
  if FDecoder <> nil then
  begin
    FDecoder.StopAudioPlayback;
    FDecoder.Close;
  end;
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

  Result := Round(Int64(PlaybackPositionMs) * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
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
  QueuedSampleCount: Integer;
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
    WriteVideoMinerDebugLog(Format(
      'audio_pump_skip reason="%s" playback_ms=%d queued_samples=%d start_samples=%d finished=%s',
      [SkipReason, PlaybackPositionMs,
       FQueuedSamples, FStartSamples, BoolToStr(FFinished, True)]));
    Exit;
  end;

  Pcm := nil;
  SampleCount := FQueuedSamples;
  PlaybackSampleCount := PlaybackSamplePosition;
  RawQueuedSampleCount := Int64(FQueuedSamples) - Int64(PlaybackSampleCount);
  if RawQueuedSampleCount < 0 then
    QueuedSampleCount := 0
  else if RawQueuedSampleCount > High(Integer) then
    QueuedSampleCount := High(Integer)
  else
    QueuedSampleCount := Integer(RawQueuedSampleCount);
  QueuedBeforeMs := Round(Int64(QueuedSampleCount) * 1000 / AUDIO_OUTPUT_SAMPLE_RATE);
  TargetQueuedSampleCount := Round(AUDIO_TARGET_QUEUE_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  if QueuedSampleCount >= TargetQueuedSampleCount then
  begin
    WriteVideoMinerDebugLog(Format(
      'audio_pump_skip reason="queue_full" playback_ms=%d raw_queued_samples=%d queued_ms=%d target_ms=%d queued_samples=%d',
      [PlaybackPositionMs, RawQueuedSampleCount, QueuedBeforeMs,
       AUDIO_TARGET_QUEUE_MS, FQueuedSamples]));
    Exit;
  end;

  TargetSampleCount := FQueuedSamples + (TargetQueuedSampleCount - QueuedSampleCount);

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
