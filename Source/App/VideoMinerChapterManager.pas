unit VideoMinerChapterManager;

// チェック機能のチャプター状態と自動検知マーカーを管理する。
// 手動チャプターは保存対象として扱い、自動チェック由来の候補は
// Check ON 中の一時的な表示/移動対象としてまとめる。

interface

uses
  System.Math, System.SysUtils, VideoMinerFrameCheck, VideoMinerOverlay,
  VideoMinerSettings;

type
  TVideoMinerLoopSegment = record
    StartMs : Integer; // ループ再生を開始する位置 ms
    EndMs   : Integer; // ループ再生を折り返す位置 ms
  end;

  TVideoMinerChapterManager = class
  private
    FChannelStartMs                  : Integer;                    // 左右チャンネル異常候補の開始位置 ms
    FDarkStartMs                     : Integer;                    // 黒フレーム継続候補の開始位置 ms
    FFrameDiffHasPending             : Boolean;                    // 単発差分候補を保留しているか
    FFrameDiffHasPrev                : Boolean;                    // 前回フレーム署名を保持しているか
    FFrameDiffPendingBeforeSignature : TVideoMinerFrameSignature;  // 保留候補の直前フレーム署名
    FFrameDiffPendingPositionMs      : Integer;                    // 保留中の単発差分候補位置 ms
    FFrameDiffPendingSignature       : TVideoMinerFrameSignature;  // 保留中の単発差分候補署名
    FFrameDiffPrevPositionMs         : Integer;                    // 前回フレーム署名の位置 ms
    FFrameDiffPrevSignature          : TVideoMinerFrameSignature;  // 前回フレーム署名
    FSilenceStartMs                  : Integer;                    // 無音区間候補の開始位置 ms
    FVolumeHasPrev                   : Boolean;                    // 前回音量ブロックを保持しているか
    FVolumePrevLevel                 : Integer;                    // 前回音量ブロックのピーク値
    FVolumePrevStartMs               : Integer;                    // 前回音量ブロックの開始位置 ms
    FChapters                        : TVideoMinerOverlayChapters; // 手動/自動チェックの全チャプター
    FCheckEnabled                    : Boolean;                    // 自動チェック候補を表示/移動対象にするか
    // 近い自動チェック候補を統合し、必要なら重要度を上げる
    function AddOrUpdateAutoCheckChapter(PositionMs: Integer;
      Severity: TVideoMinerOverlayChapterSeverity;
      Source: TVideoMinerOverlayChapterSource; MaxMs: Integer): Boolean;
    // 同じ種類の自動チェック候補が近くにあるか探す
    function FindNearbyAutoCheckChapter(PositionMs: Integer;
      Source: TVideoMinerOverlayChapterSource): Integer;
    // 現在の Check 状態で対象チャプターを表示するか判定する
    function ChapterVisible(const Chapter: TVideoMinerOverlayChapter): Boolean;
    // 指定位置に近い手動チャプターを許容距離内で削除する
    function DeleteNearestManualChapterWithin(PositionMs, MaxMs, NearMs: Integer): Boolean;
    // ループ区間の開始境界を、現在位置より前の表示チャプターから求める
    function LoopSegmentStartPositionMs(PositionMs, LastPositionMs: Integer): Integer;
    // ループ区間の終了境界を、現在位置より後の表示チャプターから求める
    function LoopSegmentEndPositionMs(PositionMs, LastPositionMs: Integer): Integer;
    // 音声系の自動チェック継続状態を初期化する
    procedure ResetAudioCheck;
    // フレーム差分の自動チェック継続状態を初期化する
    procedure ResetFrameDifferenceCheck;
  public
    // 初期状態の manager を作成する
    constructor Create;
    // 全チャプターと自動チェック継続状態をクリアする
    procedure Clear;
    // 指定位置に手動チャプターを追加する
    procedure AddManualChapter(PositionMs, MaxMs: Integer);
    // 指定位置に最も近い手動チャプターを削除する
    function DeleteNearestManualChapter(PositionMs, MaxMs: Integer): Boolean;
    // 指定位置に重なっている手動チャプターを削除する
    function DeleteManualChapterAt(PositionMs, MaxMs: Integer): Boolean;
    // Check ON/OFF を切り替え、OFF では自動チェック継続状態を初期化する
    function ToggleCheckEnabled: Boolean;
    // 黒フレーム継続を自動チェックし、必要なら候補チャプターを追加する
    function MaybeAutoCheckFrame(PositionMs: Integer; IsDarkFrame: Boolean;
      MaxMs: Integer): Boolean;
    // 前後フレーム署名との差分から単発異常候補を検出する
    function MaybeAutoCheckFrameDifference(PositionMs: Integer;
      const Signature: TVideoMinerFrameSignature; MaxMs: Integer): Boolean;
    // PCM ブロックから無音、左右チャンネル異常、音量急変、クリッピングを検出する
    function MaybeAutoCheckAudio(StartSample: Int64; const Pcm: TBytes;
      MaxMs: Integer): Boolean;
    // overlay へ渡す表示対象チャプターだけを返す
    function DisplayChapters: TVideoMinerOverlayChapters;
    // 保存対象の手動チャプターがあるか返す
    function HasManualChapters: Boolean;
    // 前後チャプター移動の移動先 ms を返す
    function FindNavigationTarget(Delta, CurrentMs, LastPositionMs: Integer): Integer;
    // 先頭から始まる既定のループ開始位置を返す
    function LoopStartPositionMs(LastPositionMs: Integer): Integer;
    // 現在位置を含むループ区間を返す
    function LoopSegmentForPosition(PositionMs, LastPositionMs: Integer):
      TVideoMinerLoopSegment;
    // 保存済みの手動チャプターを現在ファイル用に読み込む
    procedure LoadManualChapterState(const FileName: string; MaxMs: Integer);
    // 現在の手動チャプターを現在ファイル用に保存する
    procedure SaveManualChapterState(const FileName: string; MaxMs: Integer);
    property CheckEnabled: Boolean read FCheckEnabled;
  end;

implementation

const
  DARK_YELLOW_DURATION_MS    = 120;   // 黒フレーム注意候補にする継続時間 ms
  DARK_RED_DURATION_MS       = 500;   // 黒フレーム危険候補にする継続時間 ms
  END_RED_ZONE_MS            = 1500;  // 終端付近の黒フレームを危険扱いする範囲 ms
  MARKER_MERGE_MS            = 3000;  // 近い自動チェック候補を統合する範囲 ms
  AUDIO_SAMPLE_RATE          = 48000; // 自動音声チェックで前提にするサンプルレート
  AUDIO_CHANNELS             = 2;     // 自動音声チェックで前提にするチャンネル数
  SILENCE_YELLOW_DURATION_MS = 1000;  // 無音注意候補にする継続時間 ms
  SILENCE_RED_DURATION_MS    = 3000;  // 無音危険候補にする継続時間 ms
  LEADING_SILENCE_MS         = 500;   // 冒頭無音を自然な余白として扱う時間 ms
  CHANNEL_YELLOW_DURATION_MS = 300;   // 左右チャンネル注意候補にする継続時間 ms
  CHANNEL_RED_DURATION_MS    = 1000;  // 左右チャンネル危険候補にする継続時間 ms
  SILENCE_PEAK               = 256;   // 無音とみなすピーク値
  ACTIVE_PEAK                = 1800;  // 音声ありとみなすピーク値
  CHANNEL_RATIO              = 8.0;   // 左右差を異常候補にする音量比
  VOLUME_ACTIVE_LEVEL        = 800;   // 音量急変判定の対象にする最小ピーク値
  VOLUME_JUMP_DELTA          = 1800;  // 音量急変候補にするピーク差
  VOLUME_JUMP_RATIO          = 4.0;   // 音量急変候補にする音量比
  VOLUME_RED_LEVEL           = 12000; // 大きな音量急変を危険候補にするピーク値
  VOLUME_RED_RATIO           = 8.0;   // 大きな音量急変を危険候補にする音量比
  VOLUME_MAX_GAP_MS          = 500;   // 音量急変比較を継続する最大ブロック間隔 ms
  CLIPPING_PEAK              = 32700; // クリッピング候補にするピーク値
  CLIPPING_SAMPLE_COUNT      = 3;     // クリッピング候補にする連続サンプル数
  FRAME_DIFF_SPIKE_SCORE     = 80;    // 単発差分候補にする輝度差スコア
  FRAME_DIFF_STABLE_SCORE    = 25;    // 前後フレームが安定しているとみなす差分スコア
  FRAME_DIFF_MAX_GAP_MS      = 250;   // フレーム差分比較を継続する最大間隔 ms
  NAVIGATION_IGNORE_NEAR_MS  = 300;   // 現在位置近くのチャプターを移動先から外す範囲 ms
  MANUAL_DELETE_NEAR_MS      = 3000;  // 手動チャプター削除対象として許容する距離 ms
  MANUAL_TOGGLE_NEAR_MS      = 300;   // 右クリックトグルで同じ位置とみなす距離 ms

constructor TVideoMinerChapterManager.Create;
begin
  inherited Create;
  ResetAudioCheck;
  FDarkStartMs := -1;
  ResetFrameDifferenceCheck;
  FCheckEnabled := False;
end;

procedure TVideoMinerChapterManager.Clear;
begin
  SetLength(FChapters, 0);
  ResetAudioCheck;
  FDarkStartMs := -1;
  ResetFrameDifferenceCheck;
end;

procedure TVideoMinerChapterManager.ResetAudioCheck;
begin
  FChannelStartMs := -1;
  FSilenceStartMs := -1;
  FVolumeHasPrev := False;
  FVolumePrevLevel := 0;
  FVolumePrevStartMs := -1;
end;

procedure TVideoMinerChapterManager.ResetFrameDifferenceCheck;
begin
  FFrameDiffHasPending := False;
  FFrameDiffHasPrev := False;
  FFrameDiffPendingPositionMs := -1;
  FFrameDiffPrevPositionMs := -1;
end;

function TVideoMinerChapterManager.ChapterVisible(
  const Chapter: TVideoMinerOverlayChapter): Boolean;
begin
  Result := (Chapter.Source = chsUser) or FCheckEnabled;
end;

procedure TVideoMinerChapterManager.AddManualChapter(PositionMs, MaxMs: Integer);
var
  Chapter: TVideoMinerOverlayChapter;
  Index: Integer;
begin
  if MaxMs <= 0 then
    Exit;

  Chapter.PositionMs := Max(0, Min(MaxMs, PositionMs));
  Chapter.Severity := csGreen;
  Chapter.Source := chsUser;
  Index := Length(FChapters);
  SetLength(FChapters, Index + 1);
  FChapters[Index] := Chapter;
end;

function TVideoMinerChapterManager.DeleteNearestManualChapter(
  PositionMs, MaxMs: Integer): Boolean;
begin
  Result := DeleteNearestManualChapterWithin(PositionMs, MaxMs,
    MANUAL_DELETE_NEAR_MS);
end;

function TVideoMinerChapterManager.DeleteManualChapterAt(
  PositionMs, MaxMs: Integer): Boolean;
begin
  Result := DeleteNearestManualChapterWithin(PositionMs, MaxMs,
    MANUAL_TOGGLE_NEAR_MS);
end;

function TVideoMinerChapterManager.DeleteNearestManualChapterWithin(
  PositionMs, MaxMs, NearMs: Integer): Boolean;
var
  BestDelta: Integer;
  BestIndex: Integer;
  Delta: Integer;
  I: Integer;
begin
  Result := False;
  if MaxMs <= 0 then
    Exit;

  BestDelta := MaxInt;
  BestIndex := -1;

  for I := 0 to High(FChapters) do
  begin
    if FChapters[I].Source <> chsUser then
      Continue;

    Delta := Abs(FChapters[I].PositionMs - PositionMs);
    if Delta < BestDelta then
    begin
      BestDelta := Delta;
      BestIndex := I;
    end;
  end;

  if (BestIndex < 0) or (BestDelta > NearMs) then
    Exit;

  for I := BestIndex to High(FChapters) - 1 do
    FChapters[I] := FChapters[I + 1];
  SetLength(FChapters, Length(FChapters) - 1);
  Result := True;
end;

function TVideoMinerChapterManager.ToggleCheckEnabled: Boolean;
begin
  FCheckEnabled := not FCheckEnabled;
  if not FCheckEnabled then
  begin
    ResetAudioCheck;
    FDarkStartMs := -1;
    ResetFrameDifferenceCheck;
  end;
  Result := FCheckEnabled;
end;

function TVideoMinerChapterManager.FindNearbyAutoCheckChapter(
  PositionMs: Integer; Source: TVideoMinerOverlayChapterSource): Integer;
var
  I: Integer;
begin
  Result := -1;

  for I := 0 to High(FChapters) do
  begin
    if (FChapters[I].Source = Source) and
       (Abs(FChapters[I].PositionMs - PositionMs) <= MARKER_MERGE_MS) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TVideoMinerChapterManager.AddOrUpdateAutoCheckChapter(
  PositionMs: Integer; Severity: TVideoMinerOverlayChapterSeverity;
  Source: TVideoMinerOverlayChapterSource; MaxMs: Integer): Boolean;
var
  Chapter: TVideoMinerOverlayChapter;
  Index: Integer;
begin
  Result := False;
  if MaxMs <= 0 then
    Exit;

  Index := FindNearbyAutoCheckChapter(PositionMs, Source);
  if Index >= 0 then
  begin
    if Ord(Severity) > Ord(FChapters[Index].Severity) then
    begin
      FChapters[Index].Severity := Severity;
      Result := True;
    end;
    Exit;
  end;

  Chapter.PositionMs := Max(0, Min(MaxMs, PositionMs));
  Chapter.Severity := Severity;
  Chapter.Source := Source;
  Index := Length(FChapters);
  SetLength(FChapters, Index + 1);
  FChapters[Index] := Chapter;
  Result := True;
end;

function TVideoMinerChapterManager.MaybeAutoCheckFrame(PositionMs: Integer;
  IsDarkFrame: Boolean; MaxMs: Integer): Boolean;
var
  DarkDurationMs: Integer;
  Severity: TVideoMinerOverlayChapterSeverity;
begin
  Result := False;
  if (not FCheckEnabled) or (PositionMs < 0) then
  begin
    FDarkStartMs := -1;
    Exit;
  end;

  if not IsDarkFrame then
  begin
    FDarkStartMs := -1;
    Exit;
  end;

  if FDarkStartMs < 0 then
    FDarkStartMs := PositionMs;

  DarkDurationMs := PositionMs - FDarkStartMs;
  if DarkDurationMs < DARK_YELLOW_DURATION_MS then
    Exit;

  Severity := csYellow;
  if (DarkDurationMs >= DARK_RED_DURATION_MS) or
     (MaxMs - PositionMs <= END_RED_ZONE_MS) then
    Severity := csRed;

  Result := AddOrUpdateAutoCheckChapter(FDarkStartMs, Severity,
    chsAutoCheck, MaxMs);
end;

function TVideoMinerChapterManager.MaybeAutoCheckFrameDifference(
  PositionMs: Integer; const Signature: TVideoMinerFrameSignature;
  MaxMs: Integer): Boolean;
var
  DiffBeforeCurrent: Integer;
  DiffPendingCurrent: Integer;
  DiffPrevCurrent: Integer;
  PendingMatchedStableFrame: Boolean;
begin
  Result := False;
  if (not FCheckEnabled) or (PositionMs < 0) or (MaxMs <= 0) then
  begin
    ResetFrameDifferenceCheck;
    Exit;
  end;

  if (not FFrameDiffHasPrev) or
     (PositionMs <= FFrameDiffPrevPositionMs) or
     (PositionMs - FFrameDiffPrevPositionMs >
      FRAME_DIFF_MAX_GAP_MS) then
  begin
    FFrameDiffPrevSignature := Signature;
    FFrameDiffPrevPositionMs := PositionMs;
    FFrameDiffHasPrev := True;
    FFrameDiffHasPending := False;
    Exit;
  end;

  DiffPrevCurrent := FrameSignatureDifference(FFrameDiffPrevSignature,
    Signature);
  PendingMatchedStableFrame := False;

  if FFrameDiffHasPending then
  begin
    DiffPendingCurrent := FrameSignatureDifference(
      FFrameDiffPendingSignature, Signature);
    DiffBeforeCurrent := FrameSignatureDifference(
      FFrameDiffPendingBeforeSignature, Signature);
    PendingMatchedStableFrame :=
      (DiffPendingCurrent >= FRAME_DIFF_SPIKE_SCORE) and
      (DiffBeforeCurrent <= FRAME_DIFF_STABLE_SCORE);
    if PendingMatchedStableFrame then
      Result := AddOrUpdateAutoCheckChapter(
        FFrameDiffPendingPositionMs, csYellow,
        chsAutoCheckFrameDiff, MaxMs);
    FFrameDiffHasPending := False;
  end;

  if (not PendingMatchedStableFrame) and
     (DiffPrevCurrent >= FRAME_DIFF_SPIKE_SCORE) then
  begin
    FFrameDiffPendingBeforeSignature :=
      FFrameDiffPrevSignature;
    FFrameDiffPendingSignature := Signature;
    FFrameDiffPendingPositionMs := PositionMs;
    FFrameDiffHasPending := True;
  end;

  FFrameDiffPrevSignature := Signature;
  FFrameDiffPrevPositionMs := PositionMs;
end;

function TVideoMinerChapterManager.MaybeAutoCheckAudio(StartSample: Int64;
  const Pcm: TBytes; MaxMs: Integer): Boolean;
var
  ChannelAbnormal: Boolean;
  ChannelDurationMs: Integer;
  ClippedSamples: Integer;
  DurationMs: Integer;
  FrameCount: Integer;
  I: Integer;
  LeftSample: SmallInt;
  MaxAbsLeft: Integer;
  MaxAbsRight: Integer;
  RightSample: SmallInt;
  Sample: Integer;
  Severity: TVideoMinerOverlayChapterSeverity;
  SilenceDurationMs: Integer;
  StartMs: Integer;
  SumAbsLeft: Int64;
  SumAbsRight: Int64;
  VolumeDelta: Integer;
  VolumeLevel: Integer;
  VolumeRatio: Double;
begin
  Result := False;
  if (not FCheckEnabled) or (MaxMs <= 0) or (Length(Pcm) <= 0) then
  begin
    ResetAudioCheck;
    Exit;
  end;

  FrameCount := Length(Pcm) div (AUDIO_CHANNELS * SizeOf(SmallInt));
  if FrameCount <= 0 then
    Exit;

  StartMs := (StartSample * 1000) div AUDIO_SAMPLE_RATE;
  DurationMs := (Int64(FrameCount) * 1000) div AUDIO_SAMPLE_RATE;
  if DurationMs <= 0 then
    DurationMs := 1;

  MaxAbsLeft := 0;
  MaxAbsRight := 0;
  SumAbsLeft := 0;
  SumAbsRight := 0;
  ClippedSamples := 0;
  for I := 0 to FrameCount - 1 do
  begin
    Move(Pcm[I * 4], LeftSample, SizeOf(SmallInt));
    Move(Pcm[I * 4 + 2], RightSample, SizeOf(SmallInt));

    Sample := Abs(LeftSample);
    if Sample > MaxAbsLeft then
      MaxAbsLeft := Sample;
    Inc(SumAbsLeft, Sample);
    if Sample >= CLIPPING_PEAK then
      Inc(ClippedSamples);

    Sample := Abs(RightSample);
    if Sample > MaxAbsRight then
      MaxAbsRight := Sample;
    Inc(SumAbsRight, Sample);
    if Sample >= CLIPPING_PEAK then
      Inc(ClippedSamples);
  end;

  if ClippedSamples >= CLIPPING_SAMPLE_COUNT then
    Result := AddOrUpdateAutoCheckChapter(StartMs, csRed,
      chsAutoCheckClipping, MaxMs) or Result;

  VolumeLevel := (SumAbsLeft + SumAbsRight) div
    Max(1, FrameCount * AUDIO_CHANNELS);
  if (not FVolumeHasPrev) or
     (StartMs <= FVolumePrevStartMs) or
     (StartMs - FVolumePrevStartMs >
      VOLUME_MAX_GAP_MS) then
  begin
    FVolumeHasPrev := True;
    FVolumePrevLevel := VolumeLevel;
    FVolumePrevStartMs := StartMs;
  end
  else
  begin
    if (FVolumePrevLevel >= VOLUME_ACTIVE_LEVEL) and
       (VolumeLevel >= VOLUME_ACTIVE_LEVEL) then
    begin
      VolumeDelta := Abs(VolumeLevel - FVolumePrevLevel);
      VolumeRatio := Max(VolumeLevel, FVolumePrevLevel) /
        Max(1, Min(VolumeLevel, FVolumePrevLevel));
      if (VolumeDelta >= VOLUME_JUMP_DELTA) and
         (VolumeRatio >= VOLUME_JUMP_RATIO) then
      begin
        Severity := csYellow;
        if (VolumeRatio >= VOLUME_RED_RATIO) and
           (VolumeLevel >= VOLUME_RED_LEVEL) then
          Severity := csRed;
        Result := AddOrUpdateAutoCheckChapter(StartMs, Severity,
          chsAutoCheckVolumeJump, MaxMs) or Result;
      end;
    end;
    FVolumePrevLevel := VolumeLevel;
    FVolumePrevStartMs := StartMs;
  end;

  if (MaxAbsLeft <= SILENCE_PEAK) and
     (MaxAbsRight <= SILENCE_PEAK) then
  begin
    if FSilenceStartMs < 0 then
      FSilenceStartMs := StartMs;
    SilenceDurationMs := StartMs + DurationMs - FSilenceStartMs;
    if SilenceDurationMs >= SILENCE_YELLOW_DURATION_MS then
    begin
      Severity := csYellow;
      if (FSilenceStartMs > LEADING_SILENCE_MS) and
         (SilenceDurationMs >= SILENCE_RED_DURATION_MS) then
        Severity := csRed;
      Result := AddOrUpdateAutoCheckChapter(FSilenceStartMs, Severity,
        chsAutoCheckAudio, MaxMs) or Result;
    end;
  end
  else
    FSilenceStartMs := -1;

  ChannelAbnormal :=
    ((MaxAbsLeft <= SILENCE_PEAK) and
     (MaxAbsRight >= ACTIVE_PEAK)) or
    ((MaxAbsRight <= SILENCE_PEAK) and
     (MaxAbsLeft >= ACTIVE_PEAK)) or
    ((SumAbsLeft > 0) and (SumAbsRight > 0) and
     ((SumAbsLeft / SumAbsRight >= CHANNEL_RATIO) or
      (SumAbsRight / SumAbsLeft >= CHANNEL_RATIO)));

  if ChannelAbnormal then
  begin
    if FChannelStartMs < 0 then
      FChannelStartMs := StartMs;
    ChannelDurationMs := StartMs + DurationMs - FChannelStartMs;
    if ChannelDurationMs >= CHANNEL_YELLOW_DURATION_MS then
    begin
      Severity := csYellow;
      if ChannelDurationMs >= CHANNEL_RED_DURATION_MS then
        Severity := csRed;
      Result := AddOrUpdateAutoCheckChapter(FChannelStartMs, Severity,
        chsAutoCheckChannel, MaxMs) or Result;
    end;
  end
  else
    FChannelStartMs := -1;
end;

function TVideoMinerChapterManager.DisplayChapters: TVideoMinerOverlayChapters;
var
  I: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(FChapters) do
  begin
    if not ChapterVisible(FChapters[I]) then
      Continue;

    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := FChapters[I];
  end;
end;

function TVideoMinerChapterManager.HasManualChapters: Boolean;
var
  Chapter: TVideoMinerOverlayChapter;
begin
  Result := False;
  for Chapter in FChapters do
  begin
    if Chapter.Source = chsUser then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TVideoMinerChapterManager.FindNavigationTarget(
  Delta, CurrentMs, LastPositionMs: Integer): Integer;
var
  Chapter: TVideoMinerOverlayChapter;
begin
  Result := -1;
  if Delta = 0 then
    Exit;

  if Delta > 0 then
  begin
    if LastPositionMs > CurrentMs + NAVIGATION_IGNORE_NEAR_MS then
      Result := LastPositionMs;
  end
  else
  begin
    if CurrentMs - NAVIGATION_IGNORE_NEAR_MS > 0 then
      Result := 0;
  end;

  for Chapter in FChapters do
  begin
    if not ChapterVisible(Chapter) then
      Continue;

    if Delta > 0 then
    begin
      if Chapter.PositionMs <= CurrentMs + NAVIGATION_IGNORE_NEAR_MS then
        Continue;
      if (Result < 0) or (Chapter.PositionMs < Result) then
        Result := Chapter.PositionMs;
    end
    else
    begin
      if Chapter.PositionMs >= CurrentMs - NAVIGATION_IGNORE_NEAR_MS then
        Continue;
      if (Result < 0) or (Chapter.PositionMs > Result) then
        Result := Chapter.PositionMs;
    end;
  end;
end;

function TVideoMinerChapterManager.LoopStartPositionMs(
  LastPositionMs: Integer): Integer;
var
  Chapter: TVideoMinerOverlayChapter;
begin
  Result := 0;
  for Chapter in FChapters do
  begin
    if not ChapterVisible(Chapter) then
      Continue;

    if Chapter.PositionMs > Result then
      Result := Chapter.PositionMs;
  end;
  Result := Max(0, Min(LastPositionMs, Result));
end;

function TVideoMinerChapterManager.LoopSegmentForPosition(PositionMs,
  LastPositionMs: Integer): TVideoMinerLoopSegment;
begin
  Result.StartMs := LoopSegmentStartPositionMs(PositionMs, LastPositionMs);
  Result.EndMs := LoopSegmentEndPositionMs(PositionMs, LastPositionMs);
  if Result.EndMs <= Result.StartMs then
    Result.EndMs := LastPositionMs;
end;

function TVideoMinerChapterManager.LoopSegmentStartPositionMs(
  PositionMs, LastPositionMs: Integer): Integer;
var
  Chapter: TVideoMinerOverlayChapter;
begin
  Result := 0;
  for Chapter in FChapters do
  begin
    if not ChapterVisible(Chapter) then
      Continue;

    if (Chapter.PositionMs <= PositionMs) and (Chapter.PositionMs > Result) then
      Result := Chapter.PositionMs;
  end;
  Result := Max(0, Min(LastPositionMs, Result));
end;

function TVideoMinerChapterManager.LoopSegmentEndPositionMs(
  PositionMs, LastPositionMs: Integer): Integer;
var
  Chapter: TVideoMinerOverlayChapter;
begin
  Result := LastPositionMs;
  for Chapter in FChapters do
  begin
    if not ChapterVisible(Chapter) then
      Continue;

    if (Chapter.PositionMs > PositionMs) and (Chapter.PositionMs < Result) then
      Result := Chapter.PositionMs;
  end;
  Result := Max(0, Min(LastPositionMs, Result));
end;

procedure TVideoMinerChapterManager.LoadManualChapterState(
  const FileName: string; MaxMs: Integer);
var
  I: Integer;
  Positions: TVideoMinerChapterPositions;
begin
  if FileName = '' then
    Exit;

  Positions := LoadManualChapterPositions(FileName);
  for I := 0 to High(Positions) do
  begin
    if Positions[I] < 0 then
      Continue;

    AddManualChapter(Positions[I], MaxMs);
  end;
end;

procedure TVideoMinerChapterManager.SaveManualChapterState(
  const FileName: string; MaxMs: Integer);
var
  Chapter: TVideoMinerOverlayChapter;
  Index: Integer;
  Positions: TVideoMinerChapterPositions;
begin
  if FileName = '' then
    Exit;

  SetLength(Positions, 0);
  for Chapter in FChapters do
  begin
    if Chapter.Source <> chsUser then
      Continue;

    Index := Length(Positions);
    SetLength(Positions, Index + 1);
    Positions[Index] := Max(0, Min(MaxMs, Chapter.PositionMs));
  end;
  SaveManualChapterPositions(FileName, Positions);
end;

end.
