unit VideoMinerChapterManager;

interface

uses
  System.Math, System.SysUtils, VideoMinerFrameCheck, VideoMinerOverlay,
  VideoMinerSettings;

type
  TVideoMinerLoopSegment = record
    StartMs: Integer;
    EndMs: Integer;
  end;

  TVideoMinerChapterManager = class
  private
    FAutoCheckChannelStartMs: Integer;
    FAutoCheckDarkStartMs: Integer;
    FAutoCheckFrameDiffHasPending: Boolean;
    FAutoCheckFrameDiffHasPrev: Boolean;
    FAutoCheckFrameDiffPendingBeforeSignature: TVideoMinerFrameSignature;
    FAutoCheckFrameDiffPendingPositionMs: Integer;
    FAutoCheckFrameDiffPendingSignature: TVideoMinerFrameSignature;
    FAutoCheckFrameDiffPrevPositionMs: Integer;
    FAutoCheckFrameDiffPrevSignature: TVideoMinerFrameSignature;
    FAutoCheckSilenceStartMs: Integer;
    FAutoCheckVolumeHasPrev: Boolean;
    FAutoCheckVolumePrevLevel: Integer;
    FAutoCheckVolumePrevStartMs: Integer;
    FChapters: TVideoMinerOverlayChapters;
    FCheckEnabled: Boolean;
    function AddOrUpdateAutoCheckChapter(PositionMs: Integer;
      Severity: TVideoMinerOverlayChapterSeverity;
      Source: TVideoMinerOverlayChapterSource; MaxMs: Integer): Boolean;
    function FindNearbyAutoCheckChapter(PositionMs: Integer;
      Source: TVideoMinerOverlayChapterSource): Integer;
    function ChapterVisible(const Chapter: TVideoMinerOverlayChapter): Boolean;
    function LoopSegmentStartPositionMs(PositionMs, LastPositionMs: Integer): Integer;
    function LoopSegmentEndPositionMs(PositionMs, LastPositionMs: Integer): Integer;
    procedure ResetAudioCheck;
    procedure ResetFrameDifferenceCheck;
  public
    constructor Create;
    procedure Clear;
    procedure AddManualChapter(PositionMs, MaxMs: Integer);
    function DeleteNearestManualChapter(PositionMs, MaxMs: Integer): Boolean;
    function ToggleCheckEnabled: Boolean;
    function MaybeAutoCheckFrame(PositionMs: Integer; IsDarkFrame: Boolean;
      MaxMs: Integer): Boolean;
    function MaybeAutoCheckFrameDifference(PositionMs: Integer;
      const Signature: TVideoMinerFrameSignature; MaxMs: Integer): Boolean;
    function MaybeAutoCheckAudio(StartSample: Int64; const Pcm: TBytes;
      MaxMs: Integer): Boolean;
    function DisplayChapters: TVideoMinerOverlayChapters;
    function HasManualChapters: Boolean;
    function FindNavigationTarget(Delta, CurrentMs, LastPositionMs: Integer): Integer;
    function LoopStartPositionMs(LastPositionMs: Integer): Integer;
    function LoopSegmentForPosition(PositionMs, LastPositionMs: Integer):
      TVideoMinerLoopSegment;
    procedure LoadManualChapterState(const FileName: string; MaxMs: Integer);
    procedure SaveManualChapterState(const FileName: string; MaxMs: Integer);
    property CheckEnabled: Boolean read FCheckEnabled;
  end;

implementation

const
  AUTO_CHECK_DARK_YELLOW_DURATION_MS = 120;
  AUTO_CHECK_DARK_RED_DURATION_MS = 500;
  AUTO_CHECK_END_RED_ZONE_MS = 1500;
  AUTO_CHECK_MARKER_MERGE_MS = 3000;
  AUTO_CHECK_AUDIO_SAMPLE_RATE = 48000;
  AUTO_CHECK_AUDIO_CHANNELS = 2;
  AUTO_CHECK_AUDIO_SILENCE_YELLOW_DURATION_MS = 1000;
  AUTO_CHECK_AUDIO_SILENCE_RED_DURATION_MS = 3000;
  AUTO_CHECK_AUDIO_LEADING_SILENCE_MS = 500;
  AUTO_CHECK_AUDIO_CHANNEL_YELLOW_DURATION_MS = 300;
  AUTO_CHECK_AUDIO_CHANNEL_RED_DURATION_MS = 1000;
  AUTO_CHECK_AUDIO_SILENCE_PEAK = 256;
  AUTO_CHECK_AUDIO_ACTIVE_PEAK = 1800;
  AUTO_CHECK_AUDIO_CHANNEL_RATIO = 8.0;
  AUTO_CHECK_AUDIO_VOLUME_ACTIVE_LEVEL = 800;
  AUTO_CHECK_AUDIO_VOLUME_JUMP_DELTA = 1800;
  AUTO_CHECK_AUDIO_VOLUME_JUMP_RATIO = 4.0;
  AUTO_CHECK_AUDIO_VOLUME_RED_LEVEL = 12000;
  AUTO_CHECK_AUDIO_VOLUME_RED_RATIO = 8.0;
  AUTO_CHECK_AUDIO_VOLUME_MAX_GAP_MS = 500;
  AUTO_CHECK_AUDIO_CLIPPING_PEAK = 32700;
  AUTO_CHECK_AUDIO_CLIPPING_SAMPLE_COUNT = 3;
  AUTO_CHECK_FRAME_DIFF_SPIKE_SCORE = 80;
  AUTO_CHECK_FRAME_DIFF_STABLE_SCORE = 25;
  AUTO_CHECK_FRAME_DIFF_MAX_GAP_MS = 250;
  CHAPTER_NAVIGATION_IGNORE_NEAR_MS = 300;
  MANUAL_CHAPTER_DELETE_NEAR_MS = 3000;

constructor TVideoMinerChapterManager.Create;
begin
  inherited Create;
  ResetAudioCheck;
  FAutoCheckDarkStartMs := -1;
  ResetFrameDifferenceCheck;
  FCheckEnabled := False;
end;

procedure TVideoMinerChapterManager.Clear;
begin
  SetLength(FChapters, 0);
  ResetAudioCheck;
  FAutoCheckDarkStartMs := -1;
  ResetFrameDifferenceCheck;
end;

procedure TVideoMinerChapterManager.ResetAudioCheck;
begin
  FAutoCheckChannelStartMs := -1;
  FAutoCheckSilenceStartMs := -1;
  FAutoCheckVolumeHasPrev := False;
  FAutoCheckVolumePrevLevel := 0;
  FAutoCheckVolumePrevStartMs := -1;
end;

procedure TVideoMinerChapterManager.ResetFrameDifferenceCheck;
begin
  FAutoCheckFrameDiffHasPending := False;
  FAutoCheckFrameDiffHasPrev := False;
  FAutoCheckFrameDiffPendingPositionMs := -1;
  FAutoCheckFrameDiffPrevPositionMs := -1;
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

  if (BestIndex < 0) or (BestDelta > MANUAL_CHAPTER_DELETE_NEAR_MS) then
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
    FAutoCheckDarkStartMs := -1;
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
       (Abs(FChapters[I].PositionMs - PositionMs) <= AUTO_CHECK_MARKER_MERGE_MS) then
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
    FAutoCheckDarkStartMs := -1;
    Exit;
  end;

  if not IsDarkFrame then
  begin
    FAutoCheckDarkStartMs := -1;
    Exit;
  end;

  if FAutoCheckDarkStartMs < 0 then
    FAutoCheckDarkStartMs := PositionMs;

  DarkDurationMs := PositionMs - FAutoCheckDarkStartMs;
  if DarkDurationMs < AUTO_CHECK_DARK_YELLOW_DURATION_MS then
    Exit;

  Severity := csYellow;
  if (DarkDurationMs >= AUTO_CHECK_DARK_RED_DURATION_MS) or
     (MaxMs - PositionMs <= AUTO_CHECK_END_RED_ZONE_MS) then
    Severity := csRed;

  Result := AddOrUpdateAutoCheckChapter(FAutoCheckDarkStartMs, Severity,
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

  if (not FAutoCheckFrameDiffHasPrev) or
     (PositionMs <= FAutoCheckFrameDiffPrevPositionMs) or
     (PositionMs - FAutoCheckFrameDiffPrevPositionMs >
      AUTO_CHECK_FRAME_DIFF_MAX_GAP_MS) then
  begin
    FAutoCheckFrameDiffPrevSignature := Signature;
    FAutoCheckFrameDiffPrevPositionMs := PositionMs;
    FAutoCheckFrameDiffHasPrev := True;
    FAutoCheckFrameDiffHasPending := False;
    Exit;
  end;

  DiffPrevCurrent := FrameSignatureDifference(FAutoCheckFrameDiffPrevSignature,
    Signature);
  PendingMatchedStableFrame := False;

  if FAutoCheckFrameDiffHasPending then
  begin
    DiffPendingCurrent := FrameSignatureDifference(
      FAutoCheckFrameDiffPendingSignature, Signature);
    DiffBeforeCurrent := FrameSignatureDifference(
      FAutoCheckFrameDiffPendingBeforeSignature, Signature);
    PendingMatchedStableFrame :=
      (DiffPendingCurrent >= AUTO_CHECK_FRAME_DIFF_SPIKE_SCORE) and
      (DiffBeforeCurrent <= AUTO_CHECK_FRAME_DIFF_STABLE_SCORE);
    if PendingMatchedStableFrame then
      Result := AddOrUpdateAutoCheckChapter(
        FAutoCheckFrameDiffPendingPositionMs, csYellow,
        chsAutoCheckFrameDiff, MaxMs);
    FAutoCheckFrameDiffHasPending := False;
  end;

  if (not PendingMatchedStableFrame) and
     (DiffPrevCurrent >= AUTO_CHECK_FRAME_DIFF_SPIKE_SCORE) then
  begin
    FAutoCheckFrameDiffPendingBeforeSignature :=
      FAutoCheckFrameDiffPrevSignature;
    FAutoCheckFrameDiffPendingSignature := Signature;
    FAutoCheckFrameDiffPendingPositionMs := PositionMs;
    FAutoCheckFrameDiffHasPending := True;
  end;

  FAutoCheckFrameDiffPrevSignature := Signature;
  FAutoCheckFrameDiffPrevPositionMs := PositionMs;
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

  FrameCount := Length(Pcm) div (AUTO_CHECK_AUDIO_CHANNELS * SizeOf(SmallInt));
  if FrameCount <= 0 then
    Exit;

  StartMs := (StartSample * 1000) div AUTO_CHECK_AUDIO_SAMPLE_RATE;
  DurationMs := (Int64(FrameCount) * 1000) div AUTO_CHECK_AUDIO_SAMPLE_RATE;
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
    if Sample >= AUTO_CHECK_AUDIO_CLIPPING_PEAK then
      Inc(ClippedSamples);

    Sample := Abs(RightSample);
    if Sample > MaxAbsRight then
      MaxAbsRight := Sample;
    Inc(SumAbsRight, Sample);
    if Sample >= AUTO_CHECK_AUDIO_CLIPPING_PEAK then
      Inc(ClippedSamples);
  end;

  if ClippedSamples >= AUTO_CHECK_AUDIO_CLIPPING_SAMPLE_COUNT then
    Result := AddOrUpdateAutoCheckChapter(StartMs, csRed,
      chsAutoCheckClipping, MaxMs) or Result;

  VolumeLevel := (SumAbsLeft + SumAbsRight) div
    Max(1, FrameCount * AUTO_CHECK_AUDIO_CHANNELS);
  if (not FAutoCheckVolumeHasPrev) or
     (StartMs <= FAutoCheckVolumePrevStartMs) or
     (StartMs - FAutoCheckVolumePrevStartMs >
      AUTO_CHECK_AUDIO_VOLUME_MAX_GAP_MS) then
  begin
    FAutoCheckVolumeHasPrev := True;
    FAutoCheckVolumePrevLevel := VolumeLevel;
    FAutoCheckVolumePrevStartMs := StartMs;
  end
  else
  begin
    if (FAutoCheckVolumePrevLevel >= AUTO_CHECK_AUDIO_VOLUME_ACTIVE_LEVEL) and
       (VolumeLevel >= AUTO_CHECK_AUDIO_VOLUME_ACTIVE_LEVEL) then
    begin
      VolumeDelta := Abs(VolumeLevel - FAutoCheckVolumePrevLevel);
      VolumeRatio := Max(VolumeLevel, FAutoCheckVolumePrevLevel) /
        Max(1, Min(VolumeLevel, FAutoCheckVolumePrevLevel));
      if (VolumeDelta >= AUTO_CHECK_AUDIO_VOLUME_JUMP_DELTA) and
         (VolumeRatio >= AUTO_CHECK_AUDIO_VOLUME_JUMP_RATIO) then
      begin
        Severity := csYellow;
        if (VolumeRatio >= AUTO_CHECK_AUDIO_VOLUME_RED_RATIO) and
           (VolumeLevel >= AUTO_CHECK_AUDIO_VOLUME_RED_LEVEL) then
          Severity := csRed;
        Result := AddOrUpdateAutoCheckChapter(StartMs, Severity,
          chsAutoCheckVolumeJump, MaxMs) or Result;
      end;
    end;
    FAutoCheckVolumePrevLevel := VolumeLevel;
    FAutoCheckVolumePrevStartMs := StartMs;
  end;

  if (MaxAbsLeft <= AUTO_CHECK_AUDIO_SILENCE_PEAK) and
     (MaxAbsRight <= AUTO_CHECK_AUDIO_SILENCE_PEAK) then
  begin
    if FAutoCheckSilenceStartMs < 0 then
      FAutoCheckSilenceStartMs := StartMs;
    SilenceDurationMs := StartMs + DurationMs - FAutoCheckSilenceStartMs;
    if SilenceDurationMs >= AUTO_CHECK_AUDIO_SILENCE_YELLOW_DURATION_MS then
    begin
      Severity := csYellow;
      if (FAutoCheckSilenceStartMs > AUTO_CHECK_AUDIO_LEADING_SILENCE_MS) and
         (SilenceDurationMs >= AUTO_CHECK_AUDIO_SILENCE_RED_DURATION_MS) then
        Severity := csRed;
      Result := AddOrUpdateAutoCheckChapter(FAutoCheckSilenceStartMs, Severity,
        chsAutoCheckAudio, MaxMs) or Result;
    end;
  end
  else
    FAutoCheckSilenceStartMs := -1;

  ChannelAbnormal :=
    ((MaxAbsLeft <= AUTO_CHECK_AUDIO_SILENCE_PEAK) and
     (MaxAbsRight >= AUTO_CHECK_AUDIO_ACTIVE_PEAK)) or
    ((MaxAbsRight <= AUTO_CHECK_AUDIO_SILENCE_PEAK) and
     (MaxAbsLeft >= AUTO_CHECK_AUDIO_ACTIVE_PEAK)) or
    ((SumAbsLeft > 0) and (SumAbsRight > 0) and
     ((SumAbsLeft / SumAbsRight >= AUTO_CHECK_AUDIO_CHANNEL_RATIO) or
      (SumAbsRight / SumAbsLeft >= AUTO_CHECK_AUDIO_CHANNEL_RATIO)));

  if ChannelAbnormal then
  begin
    if FAutoCheckChannelStartMs < 0 then
      FAutoCheckChannelStartMs := StartMs;
    ChannelDurationMs := StartMs + DurationMs - FAutoCheckChannelStartMs;
    if ChannelDurationMs >= AUTO_CHECK_AUDIO_CHANNEL_YELLOW_DURATION_MS then
    begin
      Severity := csYellow;
      if ChannelDurationMs >= AUTO_CHECK_AUDIO_CHANNEL_RED_DURATION_MS then
        Severity := csRed;
      Result := AddOrUpdateAutoCheckChapter(FAutoCheckChannelStartMs, Severity,
        chsAutoCheckChannel, MaxMs) or Result;
    end;
  end
  else
    FAutoCheckChannelStartMs := -1;
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
    if LastPositionMs > CurrentMs + CHAPTER_NAVIGATION_IGNORE_NEAR_MS then
      Result := LastPositionMs;
  end
  else
  begin
    if CurrentMs - CHAPTER_NAVIGATION_IGNORE_NEAR_MS > 0 then
      Result := 0;
  end;

  for Chapter in FChapters do
  begin
    if not ChapterVisible(Chapter) then
      Continue;

    if Delta > 0 then
    begin
      if Chapter.PositionMs <= CurrentMs + CHAPTER_NAVIGATION_IGNORE_NEAR_MS then
        Continue;
      if (Result < 0) or (Chapter.PositionMs < Result) then
        Result := Chapter.PositionMs;
    end
    else
    begin
      if Chapter.PositionMs >= CurrentMs - CHAPTER_NAVIGATION_IGNORE_NEAR_MS then
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
