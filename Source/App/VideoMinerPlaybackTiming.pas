unit VideoMinerPlaybackTiming;

// 再生制御で使う時間計算と同期判定を担当する。
// デコーダや UI へ依存しない純粋な判定だけを置き、playback controller から
// timer interval、終端判定、音声同期、seek guard の基準として使う。

interface

// FPS から 1 フレーム相当の長さ ms を求める
function VideoMinerFrameDurationMs(Fps: Double): Integer;
// 再生 timer に設定する基本 interval ms を求める
function VideoMinerTimerIntervalMs(Fps: Double): Integer;
// 最終フレーム表示用に、終端より少し手前の seek 位置を求める
function VideoMinerLastFrameSeekPositionMs(MaxMs: Integer; Fps: Double): Integer;
// 音声へ追いつくために、現在の動画フレームを表示せず破棄できるか判定する
function VideoMinerShouldDropFrame(CurrentVideoMs, AudioMs, DropCount: Integer;
  DropElapsedMs: Int64): Boolean;
// 動画位置が音声位置より表示補正対象になる程度に遅れているか判定する
function VideoMinerVideoLagsAudio(CurrentVideoMs, AudioMs: Integer): Boolean;
// フレーム破棄では追いつきにくい遅れを、音声位置への seek 対象として判定する
function VideoMinerShouldSeekVideoToAudio(VideoMs, AudioMs: Integer): Boolean;
// 再生位置が終端付近に入っているか判定する
function VideoMinerNearEnd(MaxMs, PositionMs: Integer): Boolean;
// 音声なし動画の scratch decode で、現在位置より戻るフレームか判定する
function VideoMinerBackwardScratchFrame(DecodedMs, CurrentVideoMs: Integer): Boolean;
// seek 直後に返ったフレームが目標位置の許容範囲内か判定する
function VideoMinerSeekGuardAccepts(TargetMs, DecodedMs: Integer): Boolean;
// seek guard で初期破棄判定に使うフレーム数を返す
function VideoMinerDefaultSeekGuardFrames: Integer;

implementation

uses
  System.Math;

const
  VIDEO_AUDIO_SYNC_LAG_MS           = 60;   // 音声同期のためにフレーム破棄を検討する遅れ幅 ms
  VIDEO_AUDIO_SEEK_LAG_MS           = 120;  // フレーム破棄ではなく音声位置へ seek する遅れ幅 ms
  VIDEO_END_TOLERANCE_MS            = 1500; // 終端付近として扱う残り時間 ms
  VIDEO_SEEK_GUARD_TOLERANCE_MS     = 1500; // seek 直後のフレームを許容する目標位置との差 ms
  VIDEO_SEEK_GUARD_FRAMES           = 5;    // seek guard で初期確認するフレーム数
  VIDEO_BACKWARD_FRAME_TOLERANCE_MS = 5;    // 逆戻り scratch frame とみなす許容差 ms
  VIDEO_DROP_FRAME_MAX              = 90;   // 1 tick で連続破棄できる最大フレーム数
  VIDEO_DROP_FRAME_BUDGET_MS        = 25;   // 1 tick のフレーム破棄に使える時間上限 ms
  VIDEO_DEFAULT_FRAME_DURATION_MS   = 33;   // FPS 不明時に使う既定フレーム長 ms

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
