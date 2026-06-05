unit FFmpegDecodeStats;

interface

uses
  System.SysUtils, FFmpegDecoderTypes;

// 映像処理合計時間の統計を更新する。
procedure UpdateVideoLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
// 映像処理時間をdecode/transfer/convertへ分けて統計更新する。
procedure UpdateVideoStageStats(var Stats: TDecodeLoadStats; TotalMs, DecodeMs,
  TransferMs, ConvertMs: Double);
// 音声処理時間の統計を更新する。
procedure UpdateAudioLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
// PCMデータから音量確認用の統計を更新する。
procedure UpdateAudioPlaybackStats(var Stats: TAudioPlaybackStats; const Pcm: TBytes;
  SampleCount: Integer; PtsMs: Integer; QueuedBuffers: Integer);

implementation

uses
  System.Math;

// 直近値、移動平均、最大値をまとめて更新する。
procedure UpdateMovingMax(var LastMs, AverageMs, MaxMs: Double; Count: Int64;
  ElapsedMs: Double);
begin
  LastMs := ElapsedMs;
  if Count = 0 then
    AverageMs := ElapsedMs
  else
    AverageMs := (AverageMs * 0.9) + (ElapsedMs * 0.1);
  if ElapsedMs > MaxMs then
    MaxMs := ElapsedMs;
end;

// 映像処理合計時間の統計を更新する。
procedure UpdateVideoLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
begin
  UpdateMovingMax(Stats.VideoLastMs, Stats.VideoAverageMs, Stats.VideoMaxMs,
    Stats.VideoFrames, ElapsedMs);
  Inc(Stats.VideoFrames);
end;

// 映像処理時間をdecode/transfer/convertへ分けて統計更新する。
procedure UpdateVideoStageStats(var Stats: TDecodeLoadStats; TotalMs, DecodeMs,
  TransferMs, ConvertMs: Double);
begin
  UpdateMovingMax(Stats.VideoLastMs, Stats.VideoAverageMs, Stats.VideoMaxMs,
    Stats.VideoFrames, TotalMs);
  UpdateMovingMax(Stats.VideoDecodeLastMs, Stats.VideoDecodeAverageMs,
    Stats.VideoDecodeMaxMs, Stats.VideoFrames, DecodeMs);
  UpdateMovingMax(Stats.VideoTransferLastMs, Stats.VideoTransferAverageMs,
    Stats.VideoTransferMaxMs, Stats.VideoFrames, TransferMs);
  UpdateMovingMax(Stats.VideoConvertLastMs, Stats.VideoConvertAverageMs,
    Stats.VideoConvertMaxMs, Stats.VideoFrames, ConvertMs);
  Inc(Stats.VideoFrames);
end;

// 音声処理時間の統計を更新する。
procedure UpdateAudioLoadStats(var Stats: TDecodeLoadStats; ElapsedMs: Double);
begin
  UpdateMovingMax(Stats.AudioLastMs, Stats.AudioAverageMs, Stats.AudioMaxMs,
    Stats.AudioPackets, ElapsedMs);
  Inc(Stats.AudioPackets);
end;

// PCMデータから音量確認用の統計を更新する。
procedure UpdateAudioPlaybackStats(var Stats: TAudioPlaybackStats; const Pcm: TBytes;
  SampleCount: Integer; PtsMs: Integer; QueuedBuffers: Integer);
var
  I: Integer;
  Value: SmallInt;
  AbsValue: Integer;
  Peak: Integer;
  NonZero: Integer;
  SumSquares: Double;
  TotalValues: Integer;
begin
  TotalValues := Length(Pcm) div SizeOf(SmallInt);
  if TotalValues <= 0 then
    Exit;

  Peak := 0;
  NonZero := 0;
  SumSquares := 0;
  for I := 0 to TotalValues - 1 do
  begin
    Value := PSmallInt(@Pcm[I * SizeOf(SmallInt)])^;
    AbsValue := Abs(Integer(Value));
    if AbsValue > Peak then
      Peak := AbsValue;
    if Value <> 0 then
      Inc(NonZero);
    SumSquares := SumSquares + Value * Value;
  end;

  Inc(Stats.DecodedFrames);
  Inc(Stats.DecodedSamples, SampleCount);
  Stats.LastPtsMs := PtsMs;
  Stats.Peak := Peak;
  Stats.Rms := Sqrt(SumSquares / TotalValues);
  Stats.NonZeroPercent := NonZero * 100.0 / TotalValues;
  Stats.QueuedBuffers := QueuedBuffers;
end;

end.
