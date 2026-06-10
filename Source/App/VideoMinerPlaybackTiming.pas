unit VideoMinerPlaybackTiming;

interface

function VideoMinerFrameDurationMs(Fps: Double): Integer;
function VideoMinerTimerIntervalMs(Fps: Double): Integer;
function VideoMinerLastFrameSeekPositionMs(MaxMs: Integer; Fps: Double): Integer;
function VideoMinerShouldDropFrame(CurrentVideoMs, AudioMs, DropCount: Integer;
  DropElapsedMs: Int64): Boolean;
function VideoMinerVideoLagsAudio(CurrentVideoMs, AudioMs: Integer): Boolean;
function VideoMinerShouldSeekVideoToAudio(VideoMs, AudioMs: Integer): Boolean;
function VideoMinerNearEnd(MaxMs, PositionMs: Integer): Boolean;
function VideoMinerBackwardScratchFrame(DecodedMs, CurrentVideoMs: Integer): Boolean;
function VideoMinerSeekGuardAccepts(TargetMs, DecodedMs: Integer): Boolean;
function VideoMinerDefaultSeekGuardFrames: Integer;

implementation

uses
  System.Math;

const
  VIDEO_AUDIO_SYNC_LAG_MS = 60;
  VIDEO_AUDIO_SEEK_LAG_MS = 120;
  VIDEO_END_TOLERANCE_MS = 1500;
  VIDEO_SEEK_GUARD_TOLERANCE_MS = 1500;
  VIDEO_SEEK_GUARD_FRAMES = 5;
  VIDEO_BACKWARD_FRAME_TOLERANCE_MS = 5;
  VIDEO_DROP_FRAME_MAX = 90;
  VIDEO_DROP_FRAME_BUDGET_MS = 25;
  VIDEO_DEFAULT_FRAME_DURATION_MS = 33;

function VideoMinerFrameDurationMs(Fps: Double): Integer;
begin
  if Fps > 0 then
    Result := Max(1, Ceil(1000 / Fps))
  else
    Result := VIDEO_DEFAULT_FRAME_DURATION_MS;
end;

function VideoMinerTimerIntervalMs(Fps: Double): Integer;
begin
  if Fps > 0 then
    Result := Round(1000 / Fps)
  else
    Result := VIDEO_DEFAULT_FRAME_DURATION_MS;
  if Result < 1 then
    Result := 1;
end;

function VideoMinerLastFrameSeekPositionMs(MaxMs: Integer; Fps: Double): Integer;
begin
  Result := MaxMs;
  if Result <= 0 then
    Exit;

  Result := Max(0, MaxMs - VideoMinerFrameDurationMs(Fps));
end;

function VideoMinerShouldDropFrame(CurrentVideoMs, AudioMs, DropCount: Integer;
  DropElapsedMs: Int64): Boolean;
begin
  Result := VideoMinerVideoLagsAudio(CurrentVideoMs, AudioMs) and
    (DropCount < VIDEO_DROP_FRAME_MAX) and
    (DropElapsedMs < VIDEO_DROP_FRAME_BUDGET_MS);
end;

function VideoMinerVideoLagsAudio(CurrentVideoMs, AudioMs: Integer): Boolean;
begin
  Result := (AudioMs >= 0) and (CurrentVideoMs >= 0) and
    (CurrentVideoMs < AudioMs - VIDEO_AUDIO_SYNC_LAG_MS);
end;

function VideoMinerShouldSeekVideoToAudio(VideoMs, AudioMs: Integer): Boolean;
begin
  Result := (AudioMs >= 0) and (VideoMs >= 0) and
    (AudioMs - VideoMs > VIDEO_AUDIO_SEEK_LAG_MS);
end;

function VideoMinerNearEnd(MaxMs, PositionMs: Integer): Boolean;
begin
  Result := MaxMs - PositionMs <= VIDEO_END_TOLERANCE_MS;
end;

function VideoMinerBackwardScratchFrame(DecodedMs, CurrentVideoMs: Integer): Boolean;
begin
  Result := (DecodedMs >= 0) and (CurrentVideoMs >= 0) and
    (DecodedMs + VIDEO_BACKWARD_FRAME_TOLERANCE_MS < CurrentVideoMs);
end;

function VideoMinerSeekGuardAccepts(TargetMs, DecodedMs: Integer): Boolean;
begin
  Result := Abs(DecodedMs - TargetMs) <= VIDEO_SEEK_GUARD_TOLERANCE_MS;
end;

function VideoMinerDefaultSeekGuardFrames: Integer;
begin
  Result := VIDEO_SEEK_GUARD_FRAMES;
end;

end.
