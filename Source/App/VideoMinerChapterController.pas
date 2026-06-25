unit VideoMinerChapterController;

// Check/チャプター操作、overlay 反映、手動チャプター保存をまとめる。

interface

uses
  System.Classes, System.SysUtils,
  VideoMinerChapterManager, VideoMinerFrameCheck, VideoMinerMediaSession,
  VideoMinerSettings, VideoMinerVideoView;

type
  TVideoMinerChapterPositionFunc = function: Integer of object;
  TVideoMinerChapterPositionProc = procedure(PositionMs: Integer) of object;
  TVideoMinerChapterNotifyProc = procedure of object;

  TVideoMinerChapterController = class
  private
    FManager: TVideoMinerChapterManager;
    FMediaSession: TVideoMinerMediaSession;
    FVideoView: TVideoMinerVideoView;
    FOnConfigureLoop: TVideoMinerChapterPositionProc;
    FOnCurrentPosition: TVideoMinerChapterPositionFunc;
    function CurrentPositionMs: Integer;
    function ManualChapterPixelNearMs: Integer;
    procedure ChapterStateChanged(SaveManualState: Boolean);
  public
    constructor Create(AMediaSession: TVideoMinerMediaSession;
      AVideoView: TVideoMinerVideoView);
    destructor Destroy; override;
    procedure AddChapterClick(Sender: TObject);
    procedure Clear;
    procedure DeleteChapterClick(Sender: TObject);
    function FindNavigationTarget(Delta, CurrentMs, LastPositionMs: Integer):
      Integer;
    function HasManualChapters: Boolean;
    procedure LoadManualChapterState;
    function LoopStartPositionMs(LastPositionMs: Integer): Integer;
    procedure MaybeAutoCheckAudio(Sender: TObject; StartSample: Int64;
      const Pcm: TBytes);
    procedure MaybeAutoCheckFrame(PositionMs: Integer);
    procedure RefreshOverlay;
    procedure SaveLoopPlaybackPosition;
    procedure SaveManualChapterState;
    procedure ToggleCheckClick(Sender: TObject);
    procedure ToggleManualChapterAt(PositionMs: Integer);
    property Manager: TVideoMinerChapterManager read FManager;
    property OnConfigureLoop: TVideoMinerChapterPositionProc
      read FOnConfigureLoop write FOnConfigureLoop;
    property OnCurrentPosition: TVideoMinerChapterPositionFunc
      read FOnCurrentPosition write FOnCurrentPosition;
  end;

implementation

const
  MANUAL_CHAPTER_NEAR_PIXELS = 8; // 画面上で同じ marker とみなす近さ

constructor TVideoMinerChapterController.Create(
  AMediaSession: TVideoMinerMediaSession; AVideoView: TVideoMinerVideoView);
begin
  inherited Create;
  FMediaSession := AMediaSession;
  FVideoView := AVideoView;
  FManager := TVideoMinerChapterManager.Create;
end;

destructor TVideoMinerChapterController.Destroy;
begin
  FManager.Free;
  inherited;
end;

procedure TVideoMinerChapterController.AddChapterClick(Sender: TObject);
begin
  if FManager = nil then
    Exit;

  FManager.AddManualChapter(CurrentPositionMs, FMediaSession.SeekMaxMs,
    ManualChapterPixelNearMs);
  ChapterStateChanged(True);
end;

procedure TVideoMinerChapterController.ChapterStateChanged(
  SaveManualState: Boolean);
var
  PositionMs: Integer;
begin
  PositionMs := CurrentPositionMs;
  RefreshOverlay;
  if Assigned(FOnConfigureLoop) then
    FOnConfigureLoop(PositionMs);
  if SaveManualState then
    SaveManualChapterState;
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerChapterController.Clear;
begin
  if FManager <> nil then
    FManager.Clear;
  RefreshOverlay;
end;

function TVideoMinerChapterController.CurrentPositionMs: Integer;
begin
  if Assigned(FOnCurrentPosition) then
    Result := FOnCurrentPosition()
  else
    Result := FMediaSession.SeekPositionMs;
end;

function TVideoMinerChapterController.ManualChapterPixelNearMs: Integer;
begin
  Result := 0;
  if FVideoView <> nil then
    Result := FVideoView.ChapterMarkerToleranceMs(FMediaSession.SeekMaxMs,
      MANUAL_CHAPTER_NEAR_PIXELS);
end;

procedure TVideoMinerChapterController.DeleteChapterClick(Sender: TObject);
begin
  if FManager = nil then
    Exit;

  if not FManager.DeleteNearestManualChapter(CurrentPositionMs,
    FMediaSession.SeekMaxMs, ManualChapterPixelNearMs) then
    Exit;

  ChapterStateChanged(True);
end;

function TVideoMinerChapterController.FindNavigationTarget(Delta, CurrentMs,
  LastPositionMs: Integer): Integer;
begin
  if FManager = nil then
    Result := -1
  else
    Result := FManager.FindNavigationTarget(Delta, CurrentMs, LastPositionMs);
end;

function TVideoMinerChapterController.HasManualChapters: Boolean;
begin
  Result := (FManager <> nil) and FManager.HasManualChapters;
end;

procedure TVideoMinerChapterController.LoadManualChapterState;
begin
  if (FManager = nil) or (FMediaSession.VideoFile = '') then
    Exit;

  FManager.LoadManualChapterState(FMediaSession.VideoFile,
    FMediaSession.SeekMaxMs);
  RefreshOverlay;
end;

function TVideoMinerChapterController.LoopStartPositionMs(
  LastPositionMs: Integer): Integer;
begin
  if FManager = nil then
    Result := 0
  else
    Result := FManager.LoopStartPositionMs(LastPositionMs);
end;

procedure TVideoMinerChapterController.MaybeAutoCheckAudio(Sender: TObject;
  StartSample: Int64; const Pcm: TBytes);
var
  Changed: Boolean;
begin
  if FManager = nil then
    Exit;

  if (not FMediaSession.VideoInfo.Audio.Present) or
     (FMediaSession.VideoInfo.Audio.OpenError <> '') then
  begin
    FManager.MaybeAutoCheckAudio(StartSample, nil, FMediaSession.SeekMaxMs);
    Exit;
  end;

  Changed := FManager.MaybeAutoCheckAudio(StartSample, Pcm,
    FMediaSession.SeekMaxMs);
  if Changed then
    ChapterStateChanged(True);
end;

procedure TVideoMinerChapterController.MaybeAutoCheckFrame(PositionMs: Integer);
var
  Changed: Boolean;
  Signature: TVideoMinerFrameSignature;
begin
  if (FManager = nil) or (FVideoView = nil) then
    Exit;

  if not FManager.CheckEnabled then
  begin
    FManager.MaybeAutoCheckFrame(PositionMs, False, FMediaSession.SeekMaxMs);
    FillChar(Signature, SizeOf(Signature), 0);
    FManager.MaybeAutoCheckFrameDifference(PositionMs, Signature,
      FMediaSession.SeekMaxMs);
    Exit;
  end;

  Changed := FManager.MaybeAutoCheckFrame(PositionMs,
    FVideoView.CurrentFrameCornersMostlyDark, FMediaSession.SeekMaxMs);
  if FVideoView.CurrentFrameSignature(Signature) then
    Changed := FManager.MaybeAutoCheckFrameDifference(PositionMs, Signature,
      FMediaSession.SeekMaxMs) or Changed;
  if Changed then
    ChapterStateChanged(True);
end;

procedure TVideoMinerChapterController.RefreshOverlay;
begin
  if (FVideoView <> nil) and (FManager <> nil) then
  begin
    FVideoView.Chapters := FManager.DisplayChapters;
    FVideoView.CheckEnabled := FManager.CheckEnabled;
  end;
end;

procedure TVideoMinerChapterController.SaveLoopPlaybackPosition;
begin
  if (FManager = nil) or (FMediaSession.VideoFile = '') then
    Exit;

  if (FMediaSession.EndAction = eaLoop) and FManager.HasManualChapters then
    SaveManualChapterPlaybackPosition(FMediaSession.VideoFile,
      CurrentPositionMs, FMediaSession.SeekMaxMs)
  else
    ClearManualChapterPlaybackPosition(FMediaSession.VideoFile);
end;

procedure TVideoMinerChapterController.SaveManualChapterState;
begin
  if (FManager = nil) or (FMediaSession.VideoFile = '') then
    Exit;

  FManager.SaveManualChapterState(FMediaSession.VideoFile,
    FMediaSession.SeekMaxMs);
end;

procedure TVideoMinerChapterController.ToggleCheckClick(Sender: TObject);
begin
  if FManager = nil then
    Exit;

  FManager.ToggleCheckEnabled;
  RefreshOverlay;
end;

procedure TVideoMinerChapterController.ToggleManualChapterAt(PositionMs: Integer);
begin
  if (FManager = nil) or (FMediaSession.SeekMaxMs <= 0) then
    Exit;

  if not FManager.DeleteManualChapterAt(PositionMs, FMediaSession.SeekMaxMs,
    ManualChapterPixelNearMs) then
    FManager.AddManualChapter(PositionMs, FMediaSession.SeekMaxMs,
      ManualChapterPixelNearMs);
  ChapterStateChanged(True);
end;

end.
