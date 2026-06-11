unit VideoMinerChapterManager;

interface

uses
  System.Math, System.SysUtils, VideoMinerOverlay, VideoMinerSettings;

type
  TVideoMinerLoopSegment = record
    StartMs: Integer;
    EndMs: Integer;
  end;

  TVideoMinerChapterManager = class
  private
    FAutoCheckDarkStartMs: Integer;
    FChapters: TVideoMinerOverlayChapters;
    FCheckEnabled: Boolean;
    function FindNearbyAutoCheckChapter(PositionMs: Integer): Integer;
    function ChapterVisible(const Chapter: TVideoMinerOverlayChapter): Boolean;
    function LoopSegmentStartPositionMs(PositionMs, LastPositionMs: Integer): Integer;
    function LoopSegmentEndPositionMs(PositionMs, LastPositionMs: Integer): Integer;
  public
    constructor Create;
    procedure Clear;
    procedure AddManualChapter(PositionMs, MaxMs: Integer);
    function DeleteNearestManualChapter(PositionMs, MaxMs: Integer): Boolean;
    function ToggleCheckEnabled: Boolean;
    function MaybeAutoCheckFrame(PositionMs: Integer; IsDarkFrame: Boolean;
      MaxMs: Integer): Boolean;
    function DisplayChapters: TVideoMinerOverlayChapters;
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
  CHAPTER_NAVIGATION_IGNORE_NEAR_MS = 300;
  MANUAL_CHAPTER_DELETE_NEAR_MS = 3000;

constructor TVideoMinerChapterManager.Create;
begin
  inherited Create;
  FAutoCheckDarkStartMs := -1;
  FCheckEnabled := False;
end;

procedure TVideoMinerChapterManager.Clear;
begin
  SetLength(FChapters, 0);
  FAutoCheckDarkStartMs := -1;
end;

function TVideoMinerChapterManager.ChapterVisible(
  const Chapter: TVideoMinerOverlayChapter): Boolean;
begin
  Result := (Chapter.Source <> chsAutoCheck) or FCheckEnabled;
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
    FAutoCheckDarkStartMs := -1;
  Result := FCheckEnabled;
end;

function TVideoMinerChapterManager.FindNearbyAutoCheckChapter(
  PositionMs: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;

  for I := 0 to High(FChapters) do
  begin
    if (FChapters[I].Source = chsAutoCheck) and
       (Abs(FChapters[I].PositionMs - PositionMs) <= AUTO_CHECK_MARKER_MERGE_MS) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TVideoMinerChapterManager.MaybeAutoCheckFrame(PositionMs: Integer;
  IsDarkFrame: Boolean; MaxMs: Integer): Boolean;
var
  Chapter: TVideoMinerOverlayChapter;
  DarkDurationMs: Integer;
  Index: Integer;
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

  Index := FindNearbyAutoCheckChapter(FAutoCheckDarkStartMs);
  if Index >= 0 then
  begin
    if Ord(Severity) > Ord(FChapters[Index].Severity) then
    begin
      FChapters[Index].Severity := Severity;
      Result := True;
    end;
    Exit;
  end;

  Chapter.PositionMs := Max(0, Min(MaxMs, FAutoCheckDarkStartMs));
  Chapter.Severity := Severity;
  Chapter.Source := chsAutoCheck;
  Index := Length(FChapters);
  SetLength(FChapters, Index + 1);
  FChapters[Index] := Chapter;
  Result := True;
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
