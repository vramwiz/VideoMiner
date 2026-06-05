unit VideoMinerAudioPlayback;

interface

uses
  System.SysUtils, Vcl.Graphics, FFmpegDecoder, FFmpegDecoderTypes;

type
  TVideoMinerAudioPlayback = class
  private const
    AUDIO_OUTPUT_SAMPLE_RATE = 48000;
    AUDIO_PUMP_MS = 120;
    AUDIO_FADE_IN_MS = 12;
  private
    FDecoder: TFFmpegDecoder;
    FFinished: Boolean;
    FQueuedSamples: Integer;
    FVolumePercent: Integer;
    FMuted: Boolean;
    FApplyFadeInNext: Boolean;
    procedure ApplyVolume(var Pcm: TBytes);
    procedure SetMuted(Value: Boolean);
    procedure SetVolumePercent(Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function StartAt(const FileName: string; const VideoInfo: TVideoInfo;
      PositionMs: Integer; out ErrorMessage: string): Boolean;
    procedure Stop;
    function Pump(out ErrorMessage: string): Boolean;
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
  Bitmap: TBitmap;
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

  Bitmap := TBitmap.Create;
  try
    FDecoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage);
  finally
    Bitmap.Free;
  end;

  if not FDecoder.StartAudioPlayback(ErrorMessage) then
  begin
    FDecoder.Close;
    Result := False;
    Exit;
  end;

  FFinished := False;
  FQueuedSamples := Round(PositionMs * AUDIO_OUTPUT_SAMPLE_RATE / 1000);
  FApplyFadeInNext := True;
  Result := Pump(ErrorMessage) and Pump(ErrorMessage);
end;

procedure TVideoMinerAudioPlayback.Stop;
begin
  if FDecoder <> nil then
  begin
    FDecoder.SetAudioOutputVolume(0);
    FDecoder.StopAudioPlayback;
    FDecoder.Close;
  end;
  FFinished := True;
  FQueuedSamples := 0;
  FApplyFadeInNext := False;
end;

procedure TVideoMinerAudioPlayback.SetMuted(Value: Boolean);
begin
  FMuted := Value;
end;

procedure TVideoMinerAudioPlayback.SetVolumePercent(Value: Integer);
begin
  if Value < 0 then
    Value := 0
  else if Value > 100 then
    Value := 100;

  FVolumePercent := Value;
end;

procedure TVideoMinerAudioPlayback.ApplyVolume(var Pcm: TBytes);
var
  SampleCount: Integer;
  FrameIndex: Integer;
  ChannelIndex: Integer;
  FadeFrames: Integer;
  Scale: Double;
  FadeScale: Double;
  Value: Integer;
  Samples: PSmallIntArray;
begin
  if Length(Pcm) = 0 then
    Exit;

  if FMuted then
    Scale := 0
  else
    Scale := FVolumePercent / 100;

  SampleCount := Length(Pcm) div SizeOf(SmallInt);
  Samples := PSmallIntArray(@Pcm[0]);
  FadeFrames := Round(AUDIO_FADE_IN_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);

  for FrameIndex := 0 to (SampleCount div 2) - 1 do
  begin
    FadeScale := Scale;
    if FApplyFadeInNext and (FadeFrames > 0) and (FrameIndex < FadeFrames) then
      FadeScale := FadeScale * FrameIndex / FadeFrames;

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
  TargetSampleCount: Integer;
  Finished: Boolean;
begin
  ErrorMessage := '';
  Result := True;

  if (FDecoder = nil) or FFinished then
    Exit;

  Pcm := nil;
  SampleCount := FQueuedSamples;
  TargetSampleCount := FQueuedSamples + Round(AUDIO_PUMP_MS * AUDIO_OUTPUT_SAMPLE_RATE / 1000);

  if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount, Pcm,
    SampleCount, Finished, ErrorMessage) then
  begin
    Stop;
    Result := False;
    Exit;
  end;

  FQueuedSamples := SampleCount;
  FFinished := Finished;

  ApplyVolume(Pcm);

  if (Length(Pcm) > 0) and
     (not FDecoder.QueueAudioPcm16Stereo48k(Pcm, ErrorMessage)) then
  begin
    Stop;
    Result := False;
  end;
end;

end.
