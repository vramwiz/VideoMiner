unit VideoMinerAudioPlayback;

// VideoMiner から使う音声再生ラッパを担当する。
// FFmpeg デコーダから PCM を先読みし、waveOut への投入、音量/ミュート、
// 再生速度変換、単調時計ベースの再生位置をまとめて管理する。

interface

uses
  System.Classes, System.Diagnostics, System.Math, System.SysUtils, FFmpegDecoder,
  FFmpegDecoderTypes, FFmpegAudioTempo, VideoMinerDebugLog;

type
  // 自動音声チェックへ渡すデコード済み PCM 通知
  TVideoMinerAudioPcmDecodedEvent = procedure(Sender: TObject;
    StartSample: Int64; const Pcm: TBytes) of object;

  TVideoMinerAudioPlayback = class
  private const
    OUTPUT_SAMPLE_RATE   = 48000; // waveOut へ渡す PCM のサンプルレート
    OUTPUT_CHANNELS      = 2;     // waveOut へ渡す PCM のチャンネル数
    TARGET_QUEUE_MS      = 1400;  // 1.0x 再生中に維持したい音声キュー長 ms
    RATE_TARGET_QUEUE_MS = 220;   // 倍速再生中に維持したい音声キュー長 ms
    START_QUEUE_MS       = 500;   // 再生開始前に先読みする音声キュー長 ms
    FADE_IN_MS           = 12;    // seek 直後のクリックノイズを抑えるフェードイン長 ms
    SLOW_START_LOG_MS    = 120;   // 音声開始処理を slow log に出す閾値 ms
    SLOW_PUMP_LOG_MS     = 60;    // 音声 pump を slow log に出す閾値 ms
  private
    FDecoder             : TFFmpegDecoder;                   // 音声専用に使う FFmpeg デコーダ
    FFinished            : Boolean;                          // 入力音声を最後まで読み終えたか
    FStartSamples        : Int64;                            // 現在の再生開始位置を入力サンプル数で表した値
    FQueuedSamples       : Int64;                            // デコード済み入力 PCM の終端サンプル位置
    FQueuedOutputSamples : Int64;                            // waveOut へ投入済み出力 PCM の終端サンプル位置
    FPlaybackRate        : Double;                           // 音声再生速度倍率
    FVolumePercent       : Integer;                          // ミュート前の音量 0..100
    FMuted               : Boolean;                          // 出力をミュートしているか
    FOnPcmDecoded        : TVideoMinerAudioPcmDecodedEvent;  // 自動音声チェックへ PCM を渡す通知
    FApplyFadeInNext     : Boolean;                          // 次に投入する PCM へフェードインを適用するか
    FOpenFileName        : string;                           // 現在音声デコーダで開いているファイル
    FPlaybackClock       : TStopwatch;                       // 再生位置を求める単調時計
    FPlaybackClockActive : Boolean;                          // 単調時計を再生位置として使えるか
    FPlaybackBaseMs      : Integer;                          // 単調時計の基準となる開始位置 ms
    FPumpThread          : TThread;                           // 再生中の音声補充 worker
    FPumpThreadStop      : Boolean;                           // 音声補充 worker の停止要求
    FPumpThreadFailed    : Boolean;                           // worker 側で pump が失敗したか
    FPumpThreadError     : string;                            // worker 側の最後の pump エラー
    // 次に投入する PCM の先頭へ短いフェードインを適用する
    procedure ApplyFadeIn(var Pcm: TBytes);
    // 現在の音量/ミュート設定を waveOut 側へ反映する
    procedure ApplyOutputVolume;
    // 単調時計から現在の出力サンプル位置を求める
    function PlaybackSamplePosition: Int64;
    // ミュート状態を設定し、出力音量へ反映する
    procedure SetMuted(Value: Boolean);
    // 音声再生速度を設定する
    procedure SetPlaybackRate(Value: Double);
    // 音量を 0..100 に丸めて設定し、出力音量へ反映する
    procedure SetVolumePercent(Value: Integer);
    // PCM を現在の再生速度に合わせて変換する
    function TransformPcmForPlaybackRate(const InputPcm: TBytes;
      out OutputPcm: TBytes; out OutputSampleCount: Integer): Boolean;
    // 現在の再生速度に応じて waveOut へ先行投入する目標キュー長を返す
    function TargetQueueMs: Integer;
    // 音声補充 worker を開始する
    procedure StartPumpWorker;
    // 音声補充 worker を停止する
    procedure StopPumpWorker;
    // 音声キューを必要量まで補充する。worker では PCM 通知を行わない。
    function PumpInternal(NotifyPcmDecoded: Boolean;
      out ErrorMessage: string): Boolean;
  public
    // 音声デコーダを作成し、既定の音量/速度状態を初期化する
    constructor Create;
    // 再生を停止して音声デコーダを解放する
    destructor Destroy; override;
    // 指定ファイルの音声を指定位置から開始する
    function StartAt(const FileName: string; const VideoInfo: TVideoInfo;
      PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 音声出力とデコーダ状態を停止する
    procedure Stop;
    // デコーダは残したまま waveOut 出力だけを停止する
    procedure StopOutput;
    // waveOut の出力音量を無音にする
    procedure SilenceOutput;
    // 再生中の音声キューを必要量まで先読みして投入する
    function Pump(out ErrorMessage: string): Boolean;
    // 音声補充 worker のエラー状態を確認する
    function CheckPumpWorker(out ErrorMessage: string): Boolean;
    // 単調時計ベースの現在再生位置 ms を返す
    function PlaybackPositionMs: Integer;
    property Muted: Boolean read FMuted write SetMuted;
    property OnPcmDecoded: TVideoMinerAudioPcmDecodedEvent read FOnPcmDecoded write FOnPcmDecoded;
    property PlaybackRate: Double read FPlaybackRate write SetPlaybackRate;
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
  FPlaybackRate := 1.0;
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
  OutputPcm: TBytes;
  OutputSampleCount: Integer;
  SampleCount: Integer;
  TargetSampleCount: Integer;
  Finished: Boolean;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  StopMs: Double;
  OpenMs: Double;
  SeekMs: Double;
  DecodeMs: Double;
  TransformMs: Double;
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
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_skip pos_ms=%d present=%s open_error="%s" stop_ms=%.3f total_ms=%.3f',
        [PositionMs, BoolToStr(VideoInfo.Audio.Present, True),
         VideoInfo.Audio.OpenError, StopMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
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
{$IFDEF DEBUG}
      if DebugLogEnabled then
        WriteVideoMinerDebugLog(Format(
          'audio_start_failed step="open" pos_ms=%d stop_ms=%.3f open_ms=%.3f total_ms=%.3f err="%s"',
          [PositionMs, StopMs, OpenMs, TotalWatch.Elapsed.TotalMilliseconds,
           ErrorMessage]));
{$ENDIF}
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
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="seek" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
    FDecoder.Close;
    FOpenFileName := '';
    Result := False;
    Exit;
  end;
  SeekMs := StepWatch.Elapsed.TotalMilliseconds;

  FFinished := False;
  FStartSamples := (Int64(PositionMs) * OUTPUT_SAMPLE_RATE + 500) div 1000;
  FQueuedSamples := FStartSamples;
  FQueuedOutputSamples := FStartSamples;
  FApplyFadeInNext := True;
  FPlaybackBaseMs := PositionMs;
  FPlaybackClockActive := False;

  Pcm := nil;
  SampleCount := Integer(FQueuedSamples);
  TargetSampleCount := SampleCount + Ceil(
    START_QUEUE_MS * OUTPUT_SAMPLE_RATE * FPlaybackRate / 1000) + 8;
  StepWatch := TStopwatch.StartNew;
  if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount, Pcm,
    SampleCount, Finished, ErrorMessage) then
  begin
    DecodeMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="decode" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs, DecodeMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
    FDecoder.Close;
    FOpenFileName := '';
    FFinished := True;
    Result := False;
    Exit;
  end;
  DecodeMs := StepWatch.Elapsed.TotalMilliseconds;

  FQueuedSamples := SampleCount;
  FFinished := Finished;
  if Assigned(FOnPcmDecoded) then
    FOnPcmDecoded(Self, FStartSamples, Pcm);
  StepWatch := TStopwatch.StartNew;
  if not TransformPcmForPlaybackRate(Pcm, OutputPcm, OutputSampleCount) then
  begin
    TransformMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'audio_start_failed step="tempo" pos_ms=%d rate=%.3f stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f transform_ms=%.3f total_ms=%.3f',
      [PositionMs, FPlaybackRate, StopMs, OpenMs, SeekMs, DecodeMs,
       TransformMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
    ErrorMessage := 'Failed to convert audio playback rate.';
    FDecoder.Close;
    FOpenFileName := '';
    FFinished := True;
    Result := False;
    Exit;
  end;
  TransformMs := StepWatch.Elapsed.TotalMilliseconds;
  Inc(FQueuedOutputSamples, OutputSampleCount);
  ApplyFadeIn(OutputPcm);

  StepWatch := TStopwatch.StartNew;
  if not FDecoder.StartAudioPlayback(ErrorMessage) then
  begin
    OutputStartMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="output_start" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f output_start_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs, DecodeMs, OutputStartMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
    FDecoder.Close;
    FOpenFileName := '';
    FFinished := True;
    Result := False;
    Exit;
  end;
  OutputStartMs := StepWatch.Elapsed.TotalMilliseconds;
  ApplyOutputVolume;

  StepWatch := TStopwatch.StartNew;
  if (Length(OutputPcm) > 0) and
     (not FDecoder.QueueAudioPcm16Stereo48k(OutputPcm, ErrorMessage)) then
  begin
    QueueMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start_failed step="queue" pos_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f err="%s"',
        [PositionMs, StopMs, OpenMs, SeekMs, DecodeMs, OutputStartMs, QueueMs,
         TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
    Stop;
    Result := False;
  end;
  QueueMs := StepWatch.Elapsed.TotalMilliseconds;

  if Result then
  begin
    FPlaybackClock := TStopwatch.StartNew;
    FPlaybackClockActive := True;
    if not FFinished then
      StartPumpWorker;
    WriteVideoMinerRateLog(Format(
      'audio_start_summary pos_ms=%d rate=%.3f reused_decoder=%s start_samples=%d queued_output_samples=%d output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s',
      [PositionMs, FPlaybackRate, BoolToStr(OpenMs = 0, True),
       FStartSamples, FQueuedOutputSamples, OutputStartMs, QueueMs,
       TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True)]));
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_start pos_ms=%d rate=%.3f start_samples=%d queued_samples=%d queued_output_samples=%d initial_pcm_bytes=%d start_queue_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s',
        [PositionMs, FPlaybackRate, FStartSamples, FQueuedSamples,
         FQueuedOutputSamples, Length(OutputPcm),
         START_QUEUE_MS, StopMs, OpenMs, SeekMs, DecodeMs, OutputStartMs,
         QueueMs, TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True)]));
{$ENDIF}
    if not SameValue(FPlaybackRate, 1.0) then
      WriteVideoMinerRateLog(Format(
        'audio_start_rate pos_ms=%d rate=%.3f start_samples=%d queued_input_samples=%d queued_output_samples=%d input_bytes=%d output_bytes=%d start_queue_ms=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f transform_ms=%.3f output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s',
        [PositionMs, FPlaybackRate, FStartSamples, FQueuedSamples,
         FQueuedOutputSamples, Length(Pcm), Length(OutputPcm), START_QUEUE_MS,
         StopMs, OpenMs, SeekMs, DecodeMs, TransformMs, OutputStartMs, QueueMs,
         TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True)]));
{$IFDEF DEBUG}
    if (TotalWatch.Elapsed.TotalMilliseconds >= SLOW_START_LOG_MS) or
       (OpenMs >= SLOW_START_LOG_MS) or
       (SeekMs >= SLOW_START_LOG_MS) or
       (DecodeMs >= SLOW_START_LOG_MS) or
       (TransformMs >= SLOW_START_LOG_MS) or
       (QueueMs >= SLOW_START_LOG_MS) then
      WriteVideoMinerSlowLog(Format(
        'audio_start_slow pos_ms=%d rate=%.3f start_samples=%d queued_samples=%d queued_output_samples=%d input_pcm_bytes=%d output_pcm_bytes=%d stop_ms=%.3f open_ms=%.3f seek_ms=%.3f decode_ms=%.3f transform_ms=%.3f output_start_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s',
        [PositionMs, FPlaybackRate, FStartSamples, FQueuedSamples,
         FQueuedOutputSamples, Length(Pcm), Length(OutputPcm), StopMs, OpenMs,
         SeekMs, DecodeMs, TransformMs, OutputStartMs, QueueMs,
         TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True)]));
{$ENDIF}
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
  StopPumpWorker;
  if FDecoder <> nil then
    FDecoder.ResetAudioPlayback;
  FFinished := True;
  FStartSamples := 0;
  FQueuedSamples := 0;
  FQueuedOutputSamples := 0;
  FApplyFadeInNext := False;
  FPlaybackClockActive := False;
  FPlaybackBaseMs := 0;
end;

procedure TVideoMinerAudioPlayback.StartPumpWorker;
var
  Thread: TThread;
begin
  StopPumpWorker;
  FPumpThreadStop := False;
  FPumpThreadFailed := False;
  FPumpThreadError := '';

  Thread := TThread.CreateAnonymousThread(
    procedure
    var
      ErrorMessage: string;
    begin
      while not FPumpThreadStop do
      begin
        ErrorMessage := '';
        if not PumpInternal(False, ErrorMessage) then
        begin
          FPumpThreadError := ErrorMessage;
          FPumpThreadFailed := True;
          Break;
        end;
        TThread.Sleep(8);
      end;
    end);
  Thread.FreeOnTerminate := False;
  FPumpThread := Thread;
  FPumpThread.Start;
end;

procedure TVideoMinerAudioPlayback.StopPumpWorker;
var
  Thread: TThread;
begin
  Thread := FPumpThread;
  if Thread = nil then
    Exit;

  FPumpThreadStop := True;
  Thread.WaitFor;
  FPumpThread := nil;
  Thread.Free;
end;

function TVideoMinerAudioPlayback.CheckPumpWorker(
  out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  Result := not FPumpThreadFailed;
  if not Result then
    ErrorMessage := FPumpThreadError;
end;

procedure TVideoMinerAudioPlayback.SilenceOutput;
begin
  if FDecoder <> nil then
    FDecoder.SetAudioOutputVolume(0);
end;

function TVideoMinerAudioPlayback.PlaybackSamplePosition: Int64;
var
  PlayedSampleCount: Integer;
begin
  if not FPlaybackClockActive then
    Exit(FStartSamples);

  if FDecoder <> nil then
  begin
    PlayedSampleCount := FDecoder.PlayedAudioSampleCount;
    if PlayedSampleCount >= 0 then
      Exit(FStartSamples + PlayedSampleCount);
  end;

  Result := FStartSamples +
    Round(FPlaybackClock.Elapsed.TotalMilliseconds * OUTPUT_SAMPLE_RATE / 1000);
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

procedure TVideoMinerAudioPlayback.SetPlaybackRate(Value: Double);
begin
  if Value <= 0 then
    Value := 1.0;
  if SameValue(FPlaybackRate, Value) then
    Exit;

  FPlaybackRate := Value;
end;

function TVideoMinerAudioPlayback.TargetQueueMs: Integer;
begin
  if SameValue(FPlaybackRate, 1.0) then
    Result := TARGET_QUEUE_MS
  else
    Result := RATE_TARGET_QUEUE_MS;
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
  FadeFrames := Round(FADE_IN_MS * OUTPUT_SAMPLE_RATE / 1000);
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

function TVideoMinerAudioPlayback.TransformPcmForPlaybackRate(
  const InputPcm: TBytes; out OutputPcm: TBytes;
  out OutputSampleCount: Integer): Boolean;
const
  STRETCH_WINDOW_FRAMES  = 2048; // 簡易 time-stretch で切り貼りする窓幅フレーム数
  STRETCH_OVERLAP_FRAMES = 512;  // 窓同士をクロスフェードする重なりフレーム数
var
  Channel: Integer;
  ExistingValue: Integer;
  FadeIn: Double;
  FadeOut: Double;
  InputFrameCount: Integer;
  OutputFrame: Integer;
  OutputFrameCount: Integer;
  SegmentFrame: Integer;
  SegmentFrames: Integer;
  SourceStartFrame: Integer;
  SourceFrame: Integer;
  SourceSamples: PSmallIntArray;
  TargetSamples: PSmallIntArray;
  TargetFrame: Integer;
  TempoErrorMessage: string;
  TempoPcm: TBytes;
  TempoSampleCount: Integer;
  Value: Integer;
begin
  Result := True;
  OutputSampleCount := 0;
  OutputPcm := nil;

  InputFrameCount := Length(InputPcm) div
    (OUTPUT_CHANNELS * SizeOf(SmallInt));
  if InputFrameCount <= 0 then
    Exit;

  if SameValue(FPlaybackRate, 1.0) then
  begin
    OutputPcm := Copy(InputPcm);
    OutputSampleCount := InputFrameCount;
    Exit;
  end;

  if TempoPcm16Stereo48k(InputPcm, FPlaybackRate, TempoPcm,
    TempoSampleCount, TempoErrorMessage) and (TempoSampleCount > 0) then
  begin
    OutputPcm := TempoPcm;
    OutputSampleCount := TempoSampleCount;
    WriteVideoMinerRateLog(Format(
      'audio_tempo rate=%.3f method="atempo" input_frames=%d output_frames=%d input_bytes=%d output_bytes=%d',
      [FPlaybackRate, InputFrameCount, OutputSampleCount, Length(InputPcm),
       Length(OutputPcm)]));
    Exit;
  end;

  if TempoErrorMessage <> '' then
    WriteVideoMinerRateLog(Format(
      'audio_tempo_fallback rate=%.3f input_bytes=%d err="%s"',
      [FPlaybackRate, Length(InputPcm), TempoErrorMessage]));

  OutputFrameCount := Floor(InputFrameCount / FPlaybackRate);
  if OutputFrameCount <= 0 then
    Exit;

  SetLength(OutputPcm, OutputFrameCount * OUTPUT_CHANNELS *
    SizeOf(SmallInt));
  FillChar(OutputPcm[0], Length(OutputPcm), 0);
  SourceSamples := PSmallIntArray(@InputPcm[0]);
  TargetSamples := PSmallIntArray(@OutputPcm[0]);

  OutputFrame := 0;
  while OutputFrame < OutputFrameCount do
  begin
    SourceStartFrame := Floor(OutputFrame * FPlaybackRate);
    if SourceStartFrame >= InputFrameCount then
      Break;

    SegmentFrames := Min(STRETCH_WINDOW_FRAMES,
      Min(InputFrameCount - SourceStartFrame, OutputFrameCount - OutputFrame));
    for SegmentFrame := 0 to SegmentFrames - 1 do
    begin
      TargetFrame := OutputFrame + SegmentFrame;
      SourceFrame := SourceStartFrame + SegmentFrame;
      if (OutputFrame > 0) and (SegmentFrame < STRETCH_OVERLAP_FRAMES) then
      begin
        FadeIn := SegmentFrame / STRETCH_OVERLAP_FRAMES;
        FadeOut := 1.0 - FadeIn;
      end
      else
      begin
        FadeIn := 1.0;
        FadeOut := 0.0;
      end;

      for Channel := 0 to OUTPUT_CHANNELS - 1 do
      begin
        Value := SourceSamples^[SourceFrame * OUTPUT_CHANNELS + Channel];
        if FadeOut > 0 then
        begin
          ExistingValue := TargetSamples^[TargetFrame *
            OUTPUT_CHANNELS + Channel];
          Value := Round(ExistingValue * FadeOut + Value * FadeIn);
        end;
        if Value < Low(SmallInt) then
          Value := Low(SmallInt)
        else if Value > High(SmallInt) then
          Value := High(SmallInt);
        TargetSamples^[TargetFrame * OUTPUT_CHANNELS + Channel] :=
          SmallInt(Value);
      end;
    end;

    Inc(OutputFrame, STRETCH_WINDOW_FRAMES - STRETCH_OVERLAP_FRAMES);
  end;
  OutputSampleCount := OutputFrameCount;
  WriteVideoMinerRateLog(Format(
    'audio_tempo rate=%.3f method="fallback" input_frames=%d output_frames=%d input_bytes=%d output_bytes=%d',
    [FPlaybackRate, InputFrameCount, OutputSampleCount, Length(InputPcm),
     Length(OutputPcm)]));
end;

function TVideoMinerAudioPlayback.Pump(out ErrorMessage: string): Boolean;
begin
  Result := PumpInternal(True, ErrorMessage);
end;

function TVideoMinerAudioPlayback.PumpInternal(NotifyPcmDecoded: Boolean;
  out ErrorMessage: string): Boolean;
var
  Pcm: TBytes;
  OutputPcm: TBytes;
  OutputSampleCount: Integer;
  SampleCount: Integer;
  PlaybackSampleCount: Int64;
  RawQueuedSampleCount: Int64;
  QueuedSampleCount: Int64;
  TargetQueuedSampleCount: Integer;
  TargetInputSampleCount: Integer;
  Finished: Boolean;
  QueuedBeforeMs: Int64;
  SkipReason: string;
  StartSample: Int64;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  DecodeMs: Double;
  TransformMs: Double;
  QueueMs: Double;
begin
  ErrorMessage := '';
  Result := True;
  TotalWatch := TStopwatch.StartNew;

  if (FDecoder = nil) or FFinished then
  begin
    if FDecoder = nil then
      SkipReason := 'decoder_nil'
    else
      SkipReason := 'finished';
{$IFDEF DEBUG}
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_pump_skip reason="%s" playback_ms=%d queued_samples=%d start_samples=%d finished=%s',
        [SkipReason, PlaybackPositionMs,
         FQueuedSamples, FStartSamples, BoolToStr(FFinished, True)]));
{$ENDIF}
    Exit;
  end;

  Pcm := nil;
  SampleCount := Integer(FQueuedSamples);
  PlaybackSampleCount := PlaybackSamplePosition;
  RawQueuedSampleCount := Int64(FQueuedOutputSamples) - Int64(PlaybackSampleCount);
  if RawQueuedSampleCount < 0 then
    QueuedSampleCount := 0
  else
    QueuedSampleCount := RawQueuedSampleCount;
  QueuedBeforeMs := Round(Int64(QueuedSampleCount) * 1000 / OUTPUT_SAMPLE_RATE);
  TargetQueuedSampleCount := Round(TargetQueueMs * OUTPUT_SAMPLE_RATE / 1000);
  if QueuedSampleCount >= TargetQueuedSampleCount then
  begin
{$IFDEF DEBUG}
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'audio_pump_skip reason="queue_full" playback_ms=%d raw_queued_samples=%d queued_ms=%d target_ms=%d queued_samples=%d',
        [PlaybackPositionMs, RawQueuedSampleCount, QueuedBeforeMs,
         TargetQueueMs, FQueuedSamples]));
{$ENDIF}
    Exit;
  end;

  TargetInputSampleCount := SampleCount + Ceil(
    (TargetQueuedSampleCount - QueuedSampleCount) * FPlaybackRate) + 8;
  StartSample := SampleCount;

  StepWatch := TStopwatch.StartNew;
  if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetInputSampleCount, Pcm,
    SampleCount, Finished, ErrorMessage) then
  begin
    DecodeMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'audio_pump_failed step="decode" playback_ms=%d rate=%.3f queued_before_ms=%d target_input_samples=%d decode_ms=%.3f total_ms=%.3f err="%s"',
      [PlaybackPositionMs, FPlaybackRate, QueuedBeforeMs,
       TargetInputSampleCount, DecodeMs, TotalWatch.Elapsed.TotalMilliseconds,
       ErrorMessage]));
{$ENDIF}
    Stop;
    Result := False;
    Exit;
  end;
  DecodeMs := StepWatch.Elapsed.TotalMilliseconds;

  FQueuedSamples := SampleCount;
  FFinished := Finished;

  if NotifyPcmDecoded and Assigned(FOnPcmDecoded) then
    FOnPcmDecoded(Self, StartSample, Pcm);
  StepWatch := TStopwatch.StartNew;
  if not TransformPcmForPlaybackRate(Pcm, OutputPcm, OutputSampleCount) then
  begin
    TransformMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'audio_pump_failed step="tempo" playback_ms=%d rate=%.3f queued_before_ms=%d decode_ms=%.3f transform_ms=%.3f total_ms=%.3f',
      [PlaybackPositionMs, FPlaybackRate, QueuedBeforeMs, DecodeMs,
       TransformMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
    Stop;
    ErrorMessage := 'Failed to convert audio playback rate.';
    Result := False;
    Exit;
  end;
  TransformMs := StepWatch.Elapsed.TotalMilliseconds;
  Inc(FQueuedOutputSamples, OutputSampleCount);
  ApplyFadeIn(OutputPcm);

  StepWatch := TStopwatch.StartNew;
  if (Length(OutputPcm) > 0) and
     (not FDecoder.QueueAudioPcm16Stereo48k(OutputPcm, ErrorMessage)) then
  begin
    QueueMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'audio_pump_failed step="queue" playback_ms=%d rate=%.3f queued_before_ms=%d decode_ms=%.3f transform_ms=%.3f queue_ms=%.3f total_ms=%.3f err="%s"',
      [PlaybackPositionMs, FPlaybackRate, QueuedBeforeMs, DecodeMs,
       TransformMs, QueueMs, TotalWatch.Elapsed.TotalMilliseconds,
       ErrorMessage]));
{$ENDIF}
    Stop;
    Result := False;
  end;
  QueueMs := StepWatch.Elapsed.TotalMilliseconds;

{$IFDEF DEBUG}
  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'audio_pump playback_ms=%d rate=%.3f raw_queued_before_samples=%d queued_before_ms=%d queued_after_ms=%d pcm_bytes=%d output_pcm_bytes=%d sample_count=%d queued_output_samples=%d finished=%s result=%s err="%s"',
      [PlaybackPositionMs, FPlaybackRate, RawQueuedSampleCount, QueuedBeforeMs,
       Round((Int64(FQueuedOutputSamples) - PlaybackSamplePosition) * 1000 / OUTPUT_SAMPLE_RATE),
       Length(Pcm), Length(OutputPcm), FQueuedSamples, FQueuedOutputSamples,
       BoolToStr(FFinished, True),
       BoolToStr(Result, True), ErrorMessage]));
{$ENDIF}
  if not SameValue(FPlaybackRate, 1.0) then
    WriteVideoMinerRateLog(Format(
      'audio_pump_rate playback_ms=%d rate=%.3f raw_queued_before_samples=%d queued_before_ms=%d queued_after_ms=%d target_queue_ms=%d input_bytes=%d output_bytes=%d input_samples=%d queued_output_samples=%d decode_ms=%.3f transform_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s result=%s',
      [PlaybackPositionMs, FPlaybackRate, RawQueuedSampleCount, QueuedBeforeMs,
       Round((Int64(FQueuedOutputSamples) - PlaybackSamplePosition) * 1000 / OUTPUT_SAMPLE_RATE),
       TargetQueueMs, Length(Pcm), Length(OutputPcm), FQueuedSamples,
       FQueuedOutputSamples, DecodeMs, TransformMs, QueueMs,
       TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True),
       BoolToStr(Result, True)]));
{$IFDEF DEBUG}
  if (TotalWatch.Elapsed.TotalMilliseconds >= SLOW_PUMP_LOG_MS) or
     (DecodeMs >= SLOW_PUMP_LOG_MS) or
     (TransformMs >= SLOW_PUMP_LOG_MS) or
     (QueueMs >= SLOW_PUMP_LOG_MS) then
    WriteVideoMinerSlowLog(Format(
      'audio_pump_slow playback_ms=%d rate=%.3f queued_before_ms=%d queued_after_ms=%d input_bytes=%d output_bytes=%d decode_ms=%.3f transform_ms=%.3f queue_ms=%.3f total_ms=%.3f finished=%s result=%s',
      [PlaybackPositionMs, FPlaybackRate, QueuedBeforeMs,
       Round((Int64(FQueuedOutputSamples) - PlaybackSamplePosition) * 1000 / OUTPUT_SAMPLE_RATE),
       Length(Pcm), Length(OutputPcm), DecodeMs, TransformMs, QueueMs,
       TotalWatch.Elapsed.TotalMilliseconds, BoolToStr(FFinished, True),
       BoolToStr(Result, True)]));
{$ENDIF}
end;

function TVideoMinerAudioPlayback.PlaybackPositionMs: Integer;
var
  InputSampleSpan: Int64;
  OutputPlayedSamples: Int64;
  OutputSampleSpan: Int64;
  PositionSamples: Int64;
begin
  if (FDecoder = nil) or (FQueuedSamples <= 0) or (not FPlaybackClockActive) then
    Exit(-1);

  OutputPlayedSamples := PlaybackSamplePosition - FStartSamples;
  if OutputPlayedSamples < 0 then
    OutputPlayedSamples := 0;

  InputSampleSpan := FQueuedSamples - FStartSamples;
  OutputSampleSpan := FQueuedOutputSamples - FStartSamples;
  if (InputSampleSpan > 0) and (OutputSampleSpan > 0) then
  begin
    PositionSamples := FStartSamples +
      Round(OutputPlayedSamples * InputSampleSpan / OutputSampleSpan);
    if PositionSamples > FQueuedSamples then
      PositionSamples := FQueuedSamples;
  end
  else
    PositionSamples := FStartSamples +
      Round(FPlaybackClock.Elapsed.TotalMilliseconds * OUTPUT_SAMPLE_RATE *
        FPlaybackRate / 1000);

  Result := Round(PositionSamples * 1000 / OUTPUT_SAMPLE_RATE);
end;

end.
