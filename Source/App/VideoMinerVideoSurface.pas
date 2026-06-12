unit VideoMinerVideoSurface;

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Types, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.Graphics, VideoMinerBossGesture, VideoMinerFrameCheck,
  VideoMinerOverlay;

type
  TVideoMinerVideoSurface = class(TCustomControl)
  private
    FBitmap: TBitmap;
    FBossExitButtonRect: TRect;                          // boss     : 偽装画面の解除ボタン位置
    FBossGestureDetector: TVideoMinerBossGestureDetector; // boss     : マウス往復ジェスチャー検出器
    FBossMode: Boolean;                                  // boss     : 動画を隠して偽装画面を表示中か
    FPaintBuffer: TBitmap;
    FFirstFrameButton: TVideoMinerOverlayEdgeButton;
    FLastFrameButton: TVideoMinerOverlayEdgeButton;
    FNextFileButton: TVideoMinerOverlayFileNavButton;
    FPanMoved: Boolean;
    FPanning: Boolean;
    FPanStartCenterX: Double;
    FPanStartCenterY: Double;
    FPanStartPoint: TPoint;
    FPendingSurfaceClick: Boolean;
    FSurfaceClickArmed: Boolean;
    FSurfaceClickTimer: TTimer;
    FOnBossExitClick: TNotifyEvent;                      // boss     : 偽装画面の解除ボタンが押された
    FOnBossGesture: TNotifyEvent;                        // boss     : ボスが来たジェスチャーが成立した
    FOnAddChapterClick: TNotifyEvent;
    FOnCheckClick: TNotifyEvent;
    FOnDeleteChapterClick: TNotifyEvent;
    FOnEndActionClick: TNotifyEvent;
    FOnFirstFrameClick: TNotifyEvent;
    FOnFullScreenClick: TNotifyEvent;
    FOnLastFrameClick: TNotifyEvent;
    FOnMuteClick: TNotifyEvent;
    FOnNavigateNextClick: TNotifyEvent;
    FOnNavigatePreviousClick: TNotifyEvent;
    FOnPlaybackRateClick: TNotifyEvent;
    FOnPlayPauseClick: TNotifyEvent;
    FOnSeek: TVideoMinerOverlaySeekEvent;
    FOnSkipBackwardClick: TNotifyEvent;
    FOnSkipForwardClick: TNotifyEvent;
    FOnVolumeChange: TVideoMinerOverlayVolumeEvent;
    FOverlayVisible: Boolean;
    FPlayPauseButton: TVideoMinerOverlayPlayPauseButton;
    FPreviousFileButton: TVideoMinerOverlayFileNavButton;
    FPreviewRect: TRect;
    FSeekBar: TVideoMinerOverlaySeekBar;
    FSeekBarVisible: Boolean;
    FSkipBackwardButton: TVideoMinerOverlaySkipButton;
    FSkipForwardButton: TVideoMinerOverlaySkipButton;
    FZoomCenterX: Double;
    FZoomCenterY: Double;
    FZoomScale: Double;
    procedure CancelPendingSurfaceClick;
    procedure ClampZoomCenter;
    function CanStartPan(const Point: TPoint): Boolean;
    function CanStartSurfaceClick(const Point: TPoint): Boolean;
    function HitNextFileButton(const Point: TPoint): Boolean;
    function HitPreviousFileButton(const Point: TPoint): Boolean;
    procedure DrawFrame(Canvas: TCanvas; const DestRect: TRect);
    function FitRect: TRect;
    function HitAnyOverlayButton(const Point: TPoint): Boolean;
    function HitSeekBar(const Point: TPoint): Boolean;
    function ImagePointFromClient(const Point: TPoint; out ImageX,
      ImageY: Double): Boolean;
    procedure InvalidateAllOverlayControls;
    procedure InvalidateOverlayControl(Control: TVideoMinerOverlayControl);
    procedure ResetZoom;
    // ボスが来たモード中の描画/入力状態へ切り替える
    procedure SetBossMode(Value: Boolean);
    procedure SetCanNavigateNext(Value: Boolean);
    procedure SetCanNavigatePrevious(Value: Boolean);
    procedure SetCheckEnabled(Value: Boolean);
    procedure SetChapters(const Value: TVideoMinerOverlayChapters);
    procedure SetEndActionText(const Value: string);
    procedure SetSeekBarVisible(Value: Boolean);
    procedure SetFullScreen(Value: Boolean);
    procedure SetOverlayVisible(Value: Boolean);
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    procedure SetOnBossExitClick(Value: TNotifyEvent);
    procedure SetOnBossGesture(Value: TNotifyEvent);
    procedure SetOnAddChapterClick(Value: TNotifyEvent);
    procedure SetOnCheckClick(Value: TNotifyEvent);
    procedure SetOnDeleteChapterClick(Value: TNotifyEvent);
    procedure SetOnEndActionClick(Value: TNotifyEvent);
    procedure SetOnFullScreenClick(Value: TNotifyEvent);
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    procedure SetMuted(Value: Boolean);
    procedure SetOnMuteClick(Value: TNotifyEvent);
    procedure SetOnNavigateNextClick(Value: TNotifyEvent);
    procedure SetOnNavigatePreviousClick(Value: TNotifyEvent);
    procedure SetOnPlaybackRateClick(Value: TNotifyEvent);
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    procedure SetOnSkipBackwardClick(Value: TNotifyEvent);
    procedure SetOnSkipForwardClick(Value: TNotifyEvent);
    procedure SetOnVolumeChange(Value: TVideoMinerOverlayVolumeEvent);
    procedure SetPlaybackActive(Value: Boolean);
    procedure SetPlaybackRateText(const Value: string);
    procedure SetVolumePercent(Value: Integer);
    procedure SurfaceClickTimer(Sender: TObject);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure DblClick; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,
      Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,
      Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Clear;
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    function CurrentFrameCornersMostlyDark: Boolean;
    function CurrentFrameSignature(
      out Signature: TVideoMinerFrameSignature): Boolean;
    function PrepareBgrx32Frame(Width, Height: Integer; out Buffer: Pointer;
      out BufferStride: Integer): Boolean;
    procedure Present;
    procedure PresentImmediate;
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    property BossMode: Boolean read FBossMode write SetBossMode;
    property Bitmap: TBitmap read FBitmap;
    property CanNavigateNext: Boolean write SetCanNavigateNext;
    property CanNavigatePrevious: Boolean write SetCanNavigatePrevious;
    property CheckEnabled: Boolean write SetCheckEnabled;
    property Chapters: TVideoMinerOverlayChapters write SetChapters;
    property EndActionText: string write SetEndActionText;
    property FullScreen: Boolean write SetFullScreen;
    property OnBossExitClick: TNotifyEvent read FOnBossExitClick write SetOnBossExitClick;
    property OnBossGesture: TNotifyEvent read FOnBossGesture write SetOnBossGesture;
    property OnAddChapterClick: TNotifyEvent read FOnAddChapterClick write SetOnAddChapterClick;
    property OnCheckClick: TNotifyEvent read FOnCheckClick write SetOnCheckClick;
    property OnDeleteChapterClick: TNotifyEvent read FOnDeleteChapterClick write SetOnDeleteChapterClick;
    property OnEndActionClick: TNotifyEvent read FOnEndActionClick write SetOnEndActionClick;
    property OnFirstFrameClick: TNotifyEvent read FOnFirstFrameClick write SetOnFirstFrameClick;
    property OnFullScreenClick: TNotifyEvent read FOnFullScreenClick write SetOnFullScreenClick;
    property OnLastFrameClick: TNotifyEvent read FOnLastFrameClick write SetOnLastFrameClick;
    property OnMuteClick: TNotifyEvent read FOnMuteClick write SetOnMuteClick;
    property OnNavigateNextClick: TNotifyEvent read FOnNavigateNextClick write SetOnNavigateNextClick;
    property OnNavigatePreviousClick: TNotifyEvent read FOnNavigatePreviousClick write SetOnNavigatePreviousClick;
    property OnPlaybackRateClick: TNotifyEvent read FOnPlaybackRateClick write SetOnPlaybackRateClick;
    property OnPlayPauseClick: TNotifyEvent read FOnPlayPauseClick write SetOnPlayPauseClick;
    property OnSeek: TVideoMinerOverlaySeekEvent read FOnSeek write SetOnSeek;
    property OnSkipBackwardClick: TNotifyEvent read FOnSkipBackwardClick write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent read FOnSkipForwardClick write SetOnSkipForwardClick;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent read FOnVolumeChange write SetOnVolumeChange;
    property PlaybackActive: Boolean write SetPlaybackActive;
    property PlaybackRateText: string write SetPlaybackRateText;
    property Muted: Boolean write SetMuted;
    property VolumePercent: Integer write SetVolumePercent;
  end;

implementation

uses
  System.Diagnostics, System.Math, System.SysUtils, VideoMinerBossOverlay,
  VideoMinerDebugLog;

const
  VIDEO_SURFACE_MAX_ZOOM = 8.0;
  VIDEO_SURFACE_MIN_ZOOM = 1.0;
  VIDEO_SURFACE_WHEEL_ZOOM_STEP = 1.20;

constructor TVideoMinerVideoSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := False;

  FBitmap := TBitmap.Create;
  FBossGestureDetector := TVideoMinerBossGestureDetector.Create;
  FPaintBuffer := TBitmap.Create;
  FPaintBuffer.PixelFormat := pf32bit;
  FOverlayVisible := False;
  FSeekBarVisible := False;
  ResetZoom;
  FPreviousFileButton := TVideoMinerOverlayFileNavButton.Create(fndPrevious);
  FFirstFrameButton := TVideoMinerOverlayEdgeButton.Create(edFirst);
  FSkipBackwardButton := TVideoMinerOverlaySkipButton.Create(sdBackward);
  FPlayPauseButton := TVideoMinerOverlayPlayPauseButton.Create;
  FSkipForwardButton := TVideoMinerOverlaySkipButton.Create(sdForward);
  FLastFrameButton := TVideoMinerOverlayEdgeButton.Create(edLast);
  FNextFileButton := TVideoMinerOverlayFileNavButton.Create(fndNext);
  FSeekBar := TVideoMinerOverlaySeekBar.Create;
  FSeekBar.PlaybackRateText := '1.0x';
  FSurfaceClickTimer := TTimer.Create(Self);
  FSurfaceClickTimer.Enabled := False;
  FSurfaceClickTimer.Interval := GetDoubleClickTime + 20;
  FSurfaceClickTimer.OnTimer := SurfaceClickTimer;
  FPreviousFileButton.Visible := False;
  FFirstFrameButton.Visible := False;
  FSkipBackwardButton.Visible := False;
  FPlayPauseButton.Visible := False;
  FSkipForwardButton.Visible := False;
  FLastFrameButton.Visible := False;
  FNextFileButton.Visible := False;
  FSeekBar.Visible := False;
end;

destructor TVideoMinerVideoSurface.Destroy;
begin
  CancelPendingSurfaceClick;
  FSurfaceClickTimer.Free;
  FBossGestureDetector.Free;
  FSeekBar.Free;
  FNextFileButton.Free;
  FLastFrameButton.Free;
  FSkipForwardButton.Free;
  FPlayPauseButton.Free;
  FSkipBackwardButton.Free;
  FFirstFrameButton.Free;
  FPreviousFileButton.Free;
  FPaintBuffer.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoSurface.DblClick;
begin
  inherited DblClick;
  if FBossMode then
    Exit;

  CancelPendingSurfaceClick;
  if Assigned(FOnFullScreenClick) then
    FOnFullScreenClick(Self);
end;

procedure TVideoMinerVideoSurface.CancelPendingSurfaceClick;
begin
  FPendingSurfaceClick := False;
  FSurfaceClickArmed := False;
  if FSurfaceClickTimer <> nil then
    FSurfaceClickTimer.Enabled := False;
end;

procedure TVideoMinerVideoSurface.Clear;
begin
  CancelPendingSurfaceClick;
  FBitmap.SetSize(0, 0);
  FPanning := False;
  FPanMoved := False;
  FOverlayVisible := False;
  ResetZoom;
  if FPreviousFileButton <> nil then
    FPreviousFileButton.Visible := False;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.Visible := False;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.Visible := False;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.Visible := False;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.Visible := False;
  if FLastFrameButton <> nil then
    FLastFrameButton.Visible := False;
  if FNextFileButton <> nil then
    FNextFileButton.Visible := False;
  if FSeekBar <> nil then
    FSeekBar.SetProgress(0, 0);
  SetSeekBarVisible(False);
  Invalidate;
  Update;
end;

function TVideoMinerVideoSurface.PrepareBgrx32Frame(Width, Height: Integer;
  out Buffer: Pointer; out BufferStride: Integer): Boolean;
begin
  Buffer := nil;
  BufferStride := 0;
  Result := False;

  if (Width <= 0) or (Height <= 0) then
    Exit;

  if FBitmap.PixelFormat <> pf32bit then
    FBitmap.PixelFormat := pf32bit;
  if (FBitmap.Width <> Width) or (FBitmap.Height <> Height) then
    FBitmap.SetSize(Width, Height);

  if Height > 1 then
    BufferStride := Abs(NativeInt(FBitmap.ScanLine[1]) - NativeInt(FBitmap.ScanLine[0]))
  else
    BufferStride := Width * 4;

  Buffer := FBitmap.ScanLine[Height - 1];
  Result := (Buffer <> nil) and (BufferStride > 0);
end;

function TVideoMinerVideoSurface.CurrentFrameCornersMostlyDark: Boolean;
begin
  Result := FrameCornersMostlyDark(FBitmap);
end;

function TVideoMinerVideoSurface.CurrentFrameSignature(
  out Signature: TVideoMinerFrameSignature): Boolean;
begin
  Result := BuildFrameSignature(FBitmap, Signature);
end;

procedure TVideoMinerVideoSurface.ResetZoom;
begin
  FZoomScale := VIDEO_SURFACE_MIN_ZOOM;
  if (FBitmap <> nil) and (FBitmap.Width > 0) and (FBitmap.Height > 0) then
  begin
    FZoomCenterX := FBitmap.Width / 2;
    FZoomCenterY := FBitmap.Height / 2;
  end
  else
  begin
    FZoomCenterX := 0;
    FZoomCenterY := 0;
  end;
end;

procedure TVideoMinerVideoSurface.ClampZoomCenter;
var
  HalfHeight: Double;
  HalfWidth: Double;
begin
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
  begin
    ResetZoom;
    Exit;
  end;

  FZoomScale := Max(VIDEO_SURFACE_MIN_ZOOM,
    Min(VIDEO_SURFACE_MAX_ZOOM, FZoomScale));
  if FZoomScale <= VIDEO_SURFACE_MIN_ZOOM then
  begin
    ResetZoom;
    Exit;
  end;

  HalfWidth := FBitmap.Width / FZoomScale / 2;
  HalfHeight := FBitmap.Height / FZoomScale / 2;
  FZoomCenterX := Max(HalfWidth, Min(FBitmap.Width - HalfWidth, FZoomCenterX));
  FZoomCenterY := Max(HalfHeight, Min(FBitmap.Height - HalfHeight, FZoomCenterY));
end;

function TVideoMinerVideoSurface.FitRect: TRect;
var
  Scale: Double;
  DrawWidth: Integer;
  DrawHeight: Integer;
begin
  Result := ClientRect;

  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) or
     (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;

  Scale := Min(ClientWidth / FBitmap.Width, ClientHeight / FBitmap.Height);
  DrawWidth := Max(1, Round(FBitmap.Width * Scale));
  DrawHeight := Max(1, Round(FBitmap.Height * Scale));

  Result.Left := (ClientWidth - DrawWidth) div 2;
  Result.Top := (ClientHeight - DrawHeight) div 2;
  Result.Right := Result.Left + DrawWidth;
  Result.Bottom := Result.Top + DrawHeight;
end;

procedure TVideoMinerVideoSurface.DrawFrame(Canvas: TCanvas; const DestRect: TRect);
var
  SourceHeight: Integer;
  SourceRect: TRect;
  SourceWidth: Integer;
begin
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  if FZoomScale <= VIDEO_SURFACE_MIN_ZOOM then
  begin
    Canvas.StretchDraw(DestRect, FBitmap);
    Exit;
  end;

  ClampZoomCenter;
  SourceWidth := Max(1, Round(FBitmap.Width / FZoomScale));
  SourceHeight := Max(1, Round(FBitmap.Height / FZoomScale));
  SourceRect.Left := Round(FZoomCenterX - SourceWidth / 2);
  SourceRect.Top := Round(FZoomCenterY - SourceHeight / 2);
  SourceRect.Right := SourceRect.Left + SourceWidth;
  SourceRect.Bottom := SourceRect.Top + SourceHeight;

  if SourceRect.Left < 0 then
    OffsetRect(SourceRect, -SourceRect.Left, 0);
  if SourceRect.Top < 0 then
    OffsetRect(SourceRect, 0, -SourceRect.Top);
  if SourceRect.Right > FBitmap.Width then
    OffsetRect(SourceRect, FBitmap.Width - SourceRect.Right, 0);
  if SourceRect.Bottom > FBitmap.Height then
    OffsetRect(SourceRect, 0, FBitmap.Height - SourceRect.Bottom);

  Canvas.CopyRect(DestRect, FBitmap.Canvas, SourceRect);
end;

function TVideoMinerVideoSurface.ImagePointFromClient(const Point: TPoint;
  out ImageX, ImageY: Double): Boolean;
var
  DestRect: TRect;
  SourceHeight: Double;
  SourceLeft: Double;
  SourceTop: Double;
  SourceWidth: Double;
begin
  ImageX := 0;
  ImageY := 0;
  DestRect := FitRect;
  Result := (FBitmap.Width > 0) and (FBitmap.Height > 0) and
    (not DestRect.IsEmpty) and PtInRect(DestRect, Point);
  if not Result then
    Exit;

  ClampZoomCenter;
  SourceWidth := FBitmap.Width / FZoomScale;
  SourceHeight := FBitmap.Height / FZoomScale;
  SourceLeft := FZoomCenterX - SourceWidth / 2;
  SourceTop := FZoomCenterY - SourceHeight / 2;
  ImageX := SourceLeft + (Point.X - DestRect.Left) / Max(1, DestRect.Width) *
    SourceWidth;
  ImageY := SourceTop + (Point.Y - DestRect.Top) / Max(1, DestRect.Height) *
    SourceHeight;
  ImageX := Max(0.0, Min(FBitmap.Width - 1.0, ImageX));
  ImageY := Max(0.0, Min(FBitmap.Height - 1.0, ImageY));
end;

procedure TVideoMinerVideoSurface.InvalidateOverlayControl(
  Control: TVideoMinerOverlayControl);
var
  InvalidRect: TRect;
begin
  if Control = nil then
    Exit;

  InvalidRect := Control.BoundsRect;
  InflateRect(InvalidRect, 4, 4);
  InvalidateRect(Handle, @InvalidRect, False);
end;

procedure TVideoMinerVideoSurface.InvalidateAllOverlayControls;
begin
  InvalidateOverlayControl(FPreviousFileButton);
  InvalidateOverlayControl(FFirstFrameButton);
  InvalidateOverlayControl(FSkipBackwardButton);
  InvalidateOverlayControl(FPlayPauseButton);
  InvalidateOverlayControl(FSkipForwardButton);
  InvalidateOverlayControl(FLastFrameButton);
  InvalidateOverlayControl(FNextFileButton);
end;

function TVideoMinerVideoSurface.HitAnyOverlayButton(const Point: TPoint): Boolean;
begin
  Result :=
    ((FFirstFrameButton <> nil) and FFirstFrameButton.BoundsHitTest(Point)) or
    ((FSkipBackwardButton <> nil) and FSkipBackwardButton.BoundsHitTest(Point)) or
    ((FPlayPauseButton <> nil) and FPlayPauseButton.BoundsHitTest(Point)) or
    ((FSkipForwardButton <> nil) and FSkipForwardButton.BoundsHitTest(Point)) or
    ((FLastFrameButton <> nil) and FLastFrameButton.BoundsHitTest(Point));
end;

function TVideoMinerVideoSurface.HitPreviousFileButton(
  const Point: TPoint): Boolean;
begin
  Result := (FPreviousFileButton <> nil) and
    FPreviousFileButton.BoundsHitTest(Point);
end;

function TVideoMinerVideoSurface.HitNextFileButton(
  const Point: TPoint): Boolean;
begin
  Result := (FNextFileButton <> nil) and FNextFileButton.BoundsHitTest(Point);
end;

function TVideoMinerVideoSurface.HitSeekBar(const Point: TPoint): Boolean;
begin
  Result := (FSeekBar <> nil) and FSeekBar.BoundsHitTest(Point);
end;

function TVideoMinerVideoSurface.CanStartPan(const Point: TPoint): Boolean;
begin
  Result := (FZoomScale > VIDEO_SURFACE_MIN_ZOOM) and
    (not FitRect.IsEmpty) and PtInRect(FitRect, Point) and
    not HitSeekBar(Point) and not HitAnyOverlayButton(Point) and
    not HitPreviousFileButton(Point) and not HitNextFileButton(Point);
end;

function TVideoMinerVideoSurface.CanStartSurfaceClick(
  const Point: TPoint): Boolean;
begin
  Result := not ((FSeekBarVisible or ((FSeekBar <> nil) and FSeekBar.Dragging)) and
    HitSeekBar(Point)) and
    not (FOverlayVisible and HitAnyOverlayButton(Point)) and
    not ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible and
      HitPreviousFileButton(Point)) and
    not ((FNextFileButton <> nil) and FNextFileButton.Visible and
      HitNextFileButton(Point));
end;

procedure TVideoMinerVideoSurface.SetOverlayVisible(Value: Boolean);
begin
  if FOverlayVisible = Value then
    Exit;

  FOverlayVisible := Value;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.Visible := Value;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.Visible := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.Visible := Value;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.Visible := Value;
  if FLastFrameButton <> nil then
    FLastFrameButton.Visible := Value;
  InvalidateAllOverlayControls;
end;

procedure TVideoMinerVideoSurface.SetBossMode(Value: Boolean);
begin
  if FBossMode = Value then
    Exit;

  FBossMode := Value;
  CancelPendingSurfaceClick;
  if FBossGestureDetector <> nil then
    FBossGestureDetector.Reset;
  if Value then
  begin
    SetOverlayVisible(False);
    SetSeekBarVisible(False);
    if FPreviousFileButton <> nil then
      FPreviousFileButton.Visible := False;
    if FNextFileButton <> nil then
      FNextFileButton.Visible := False;
  end;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.SetSeekBarVisible(Value: Boolean);
begin
  if FSeekBarVisible = Value then
    Exit;

  FSeekBarVisible := Value;
  if FSeekBar <> nil then
    FSeekBar.Visible := Value;
  InvalidateOverlayControl(FSeekBar);
end;

procedure TVideoMinerVideoSurface.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FBossMode then
  begin
    CancelPendingSurfaceClick;
    Exit;
  end;

  if Button = mbLeft then
  begin
    CancelPendingSurfaceClick;
    FSurfaceClickArmed := CanStartSurfaceClick(Point(X, Y));
  end;

  if (Button = mbLeft) and CanStartPan(Point(X, Y)) then
  begin
    FPanning := True;
    FPanMoved := False;
    FPanStartPoint := Point(X, Y);
    FPanStartCenterX := FZoomCenterX;
    FPanStartCenterY := FZoomCenterY;
    MouseCapture := True;
    Exit;
  end;

  if (Button = mbLeft) and (FSeekBar <> nil) and HitSeekBar(Point(X, Y)) then
  begin
    SetSeekBarVisible(True);
    if FSeekBar.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSeekBar);
    MouseCapture := True;
  end;

  if (Button = mbLeft) and FOverlayVisible then
  begin
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FFirstFrameButton);
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSkipForwardButton);
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FLastFrameButton);
  end;

  if Button = mbLeft then
  begin
    if (FPreviousFileButton <> nil) and FPreviousFileButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FPreviousFileButton);
    if (FNextFileButton <> nil) and FNextFileButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FNextFileButton);
  end;
end;

procedure TVideoMinerVideoSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  DestRect: TRect;
  MousePoint: TPoint;
  SourceHeight: Double;
  SourceWidth: Double;
begin
  inherited MouseMove(Shift, X, Y);
  MousePoint := Point(X, Y);

  if FBossMode then
    Exit;

  if FPanning then
  begin
    DestRect := FitRect;
    if not DestRect.IsEmpty then
    begin
      if (Abs(MousePoint.X - FPanStartPoint.X) > 2) or
         (Abs(MousePoint.Y - FPanStartPoint.Y) > 2) then
        FPanMoved := True;
      SourceWidth := FBitmap.Width / FZoomScale;
      SourceHeight := FBitmap.Height / FZoomScale;
      FZoomCenterX := FPanStartCenterX -
        (MousePoint.X - FPanStartPoint.X) / Max(1, DestRect.Width) *
        SourceWidth;
      FZoomCenterY := FPanStartCenterY -
        (MousePoint.Y - FPanStartPoint.Y) / Max(1, DestRect.Height) *
        SourceHeight;
      ClampZoomCenter;
      Invalidate;
    end;
    Exit;
  end;

  if (FBossGestureDetector <> nil) and
     FBossGestureDetector.MouseMove(MousePoint, (Shift = []) and
       not FSeekBarVisible and
       not ((FSeekBar <> nil) and FSeekBar.Dragging)) then
  begin
    CancelPendingSurfaceClick;
    if Assigned(FOnBossGesture) then
      FOnBossGesture(Self);
    Exit;
  end;

  SetOverlayVisible(HitAnyOverlayButton(MousePoint));
  SetSeekBarVisible(HitSeekBar(MousePoint) or
    ((FSeekBar <> nil) and FSeekBar.Dragging));

  if FPreviousFileButton <> nil then
  begin
    FPreviousFileButton.Visible := HitPreviousFileButton(MousePoint);
    if FPreviousFileButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FPreviousFileButton);
  end;
  if FNextFileButton <> nil then
  begin
    FNextFileButton.Visible := HitNextFileButton(MousePoint);
    if FNextFileButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FNextFileButton);
  end;

  if FOverlayVisible then
  begin
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FFirstFrameButton);
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FSkipForwardButton);
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FLastFrameButton);
  end;

  if FSeekBarVisible and (FSeekBar <> nil) and FSeekBar.MouseMove(MousePoint) then
    InvalidateOverlayControl(FSeekBar);

end;

procedure TVideoMinerVideoSurface.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FBossMode then
  begin
    CancelPendingSurfaceClick;
    if (Button = mbLeft) and PtInRect(FBossExitButtonRect, Point(X, Y)) and
       Assigned(FOnBossExitClick) then
      FOnBossExitClick(Self);
    Exit;
  end;

  if (Button = mbLeft) and FPanning then
  begin
    FPanning := False;
    MouseCapture := False;
    if FSurfaceClickArmed and not FPanMoved and
       CanStartSurfaceClick(Point(X, Y)) then
    begin
      FPendingSurfaceClick := True;
      FSurfaceClickTimer.Enabled := True;
    end;
    FSurfaceClickArmed := False;
    Exit;
  end;

  if (Button = mbLeft) and (FSeekBar <> nil) and
     (FSeekBarVisible or FSeekBar.Dragging) then
  begin
    if FSeekBar.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSeekBar);
    MouseCapture := False;
    SetSeekBarVisible(HitSeekBar(Point(X, Y)));
  end;

  if (Button = mbLeft) and FOverlayVisible then
  begin
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FFirstFrameButton);
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSkipForwardButton);
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FLastFrameButton);
  end;

  if Button = mbLeft then
  begin
    if (FPreviousFileButton <> nil) and FPreviousFileButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FPreviousFileButton);
    if (FNextFileButton <> nil) and FNextFileButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FNextFileButton);
    if FSurfaceClickArmed and CanStartSurfaceClick(Point(X, Y)) then
    begin
      FPendingSurfaceClick := True;
      FSurfaceClickTimer.Enabled := True;
    end;
    FSurfaceClickArmed := False;
  end;
end;

function TVideoMinerVideoSurface.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := HandleMouseWheel(Shift, WheelDelta, MousePos);
  if not Result then
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVideoMinerVideoSurface.HandleMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  DestRect: TRect;
  ImageX: Double;
  ImageY: Double;
  LocalPoint: TPoint;
  NewScale: Double;
  NewSourceHeight: Double;
  NewSourceWidth: Double;
  RatioX: Double;
  RatioY: Double;
begin
  Result := False;

  if FBossMode then
  begin
    Result := True;
    Exit;
  end;

  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  LocalPoint := ScreenToClient(MousePos);
  DestRect := FitRect;
  if DestRect.IsEmpty then
    Exit;

  if FSeekBar <> nil then
  begin
    FSeekBar.UpdateLayout(DestRect);
    if FSeekBar.BoundsHitTest(LocalPoint) then
      Exit;
  end;

  if not PtInRect(DestRect, LocalPoint) then
    Exit;
  if not ImagePointFromClient(LocalPoint, ImageX, ImageY) then
    Exit;

  if WheelDelta > 0 then
    NewScale := FZoomScale * VIDEO_SURFACE_WHEEL_ZOOM_STEP
  else
    NewScale := FZoomScale / VIDEO_SURFACE_WHEEL_ZOOM_STEP;
  NewScale := Max(VIDEO_SURFACE_MIN_ZOOM,
    Min(VIDEO_SURFACE_MAX_ZOOM, NewScale));

  if Abs(NewScale - VIDEO_SURFACE_MIN_ZOOM) < 0.01 then
  begin
    ResetZoom;
    Invalidate;
    Result := True;
    Exit;
  end;

  RatioX := (LocalPoint.X - DestRect.Left) / Max(1, DestRect.Width);
  RatioY := (LocalPoint.Y - DestRect.Top) / Max(1, DestRect.Height);
  NewSourceWidth := FBitmap.Width / NewScale;
  NewSourceHeight := FBitmap.Height / NewScale;

  FZoomScale := NewScale;
  FZoomCenterX := ImageX - RatioX * NewSourceWidth + NewSourceWidth / 2;
  FZoomCenterY := ImageY - RatioY * NewSourceHeight + NewSourceHeight / 2;
  ClampZoomCenter;

  Invalidate;
  Result := True;
end;

procedure TVideoMinerVideoSurface.Paint;
{$IFDEF DEBUG}
var
  PaintWatch: TStopwatch;
  DebugLogEnabled: Boolean;
{$ENDIF}
var
  DrawCanvas: TCanvas;
  DestRect: TRect;
  UsePaintBuffer: Boolean;
begin
{$IFDEF DEBUG}
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  if DebugLogEnabled then
    PaintWatch := TStopwatch.StartNew;
{$ENDIF}
  if (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;

  if FBossMode then
  begin
    DrawVideoMinerBossOverlay(Canvas, ClientRect, FBossExitButtonRect);
    Exit;
  end;

  UsePaintBuffer := FOverlayVisible or FSeekBarVisible or
    ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible) or
    ((FNextFileButton <> nil) and FNextFileButton.Visible);
  if UsePaintBuffer then
  begin
    if (FPaintBuffer.Width <> ClientWidth) or
       (FPaintBuffer.Height <> ClientHeight) then
      FPaintBuffer.SetSize(ClientWidth, ClientHeight);
    DrawCanvas := FPaintBuffer.Canvas;
  end
  else
    DrawCanvas := Canvas;

  DrawCanvas.Brush.Color := clBlack;
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
  begin
    DrawCanvas.FillRect(ClientRect);
    if UsePaintBuffer then
      Canvas.Draw(0, 0, FPaintBuffer);
    Exit;
  end;

  DestRect := FitRect;
  FPreviewRect := DestRect;
  if DestRect.Top > 0 then
    DrawCanvas.FillRect(Rect(0, 0, ClientWidth, DestRect.Top));
  if DestRect.Bottom < ClientHeight then
    DrawCanvas.FillRect(Rect(0, DestRect.Bottom, ClientWidth, ClientHeight));
  if DestRect.Left > 0 then
    DrawCanvas.FillRect(Rect(0, DestRect.Top, DestRect.Left, DestRect.Bottom));
  if DestRect.Right < ClientWidth then
    DrawCanvas.FillRect(Rect(DestRect.Right, DestRect.Top, ClientWidth, DestRect.Bottom));

  DrawFrame(DrawCanvas, DestRect);
  if FPreviousFileButton <> nil then
    FPreviousFileButton.UpdateLayout(ClientRect);
  if FFirstFrameButton <> nil then
    FFirstFrameButton.UpdateLayout(FPreviewRect);
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.UpdateLayout(FPreviewRect);
  if FPlayPauseButton <> nil then
    FPlayPauseButton.UpdateLayout(FPreviewRect);
  if FSkipForwardButton <> nil then
    FSkipForwardButton.UpdateLayout(FPreviewRect);
  if FLastFrameButton <> nil then
    FLastFrameButton.UpdateLayout(FPreviewRect);
  if FNextFileButton <> nil then
    FNextFileButton.UpdateLayout(ClientRect);
  if FSeekBar <> nil then
    FSeekBar.UpdateLayout(FPreviewRect);

  if (FPreviousFileButton <> nil) and FPreviousFileButton.Visible then
    FPreviousFileButton.Paint(DrawCanvas);
  if FOverlayVisible and (FFirstFrameButton <> nil) then
  begin
    FFirstFrameButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FSkipBackwardButton <> nil) then
  begin
    FSkipBackwardButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FPlayPauseButton <> nil) then
  begin
    FPlayPauseButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FSkipForwardButton <> nil) then
  begin
    FSkipForwardButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FLastFrameButton <> nil) then
  begin
    FLastFrameButton.Paint(DrawCanvas);
  end;
  if (FNextFileButton <> nil) and FNextFileButton.Visible then
    FNextFileButton.Paint(DrawCanvas);
  if FSeekBarVisible and (FSeekBar <> nil) then
    FSeekBar.Paint(DrawCanvas);
  if UsePaintBuffer then
    Canvas.Draw(0, 0, FPaintBuffer);
{$IFDEF DEBUG}
  if DebugLogEnabled then
    WriteVideoMinerDebugLog(Format('paint width=%d height=%d client_w=%d client_h=%d paint_ms=%.3f',
      [FBitmap.Width, FBitmap.Height, ClientWidth, ClientHeight,
       PaintWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

procedure TVideoMinerVideoSurface.Present;
begin
  Invalidate;
end;

procedure TVideoMinerVideoSurface.PresentImmediate;
begin
  Invalidate;
  Update;
end;

procedure TVideoMinerVideoSurface.SetPlaybackActive(Value: Boolean);
begin
  if (FPlayPauseButton <> nil) and (FPlayPauseButton.IsPlaying <> Value) then
  begin
    FPlayPauseButton.IsPlaying := Value;
    Invalidate;
  end;
end;

procedure TVideoMinerVideoSurface.SetSeekProgress(PositionMs, MaxMs: Integer);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.SetProgress(PositionMs, MaxMs);
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetFullScreen(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.FullScreen := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetCanNavigatePrevious(Value: Boolean);
begin
  if FPreviousFileButton <> nil then
  begin
    FPreviousFileButton.Enabled := Value;
    if not Value then
      FPreviousFileButton.Visible := False;
    InvalidateOverlayControl(FPreviousFileButton);
  end;
end;

procedure TVideoMinerVideoSurface.SetCanNavigateNext(Value: Boolean);
begin
  if FNextFileButton <> nil then
  begin
    FNextFileButton.Enabled := Value;
    if not Value then
      FNextFileButton.Visible := False;
    InvalidateOverlayControl(FNextFileButton);
  end;
end;

procedure TVideoMinerVideoSurface.SetEndActionText(const Value: string);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.EndActionText := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetCheckEnabled(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.CheckEnabled := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetChapters(
  const Value: TVideoMinerOverlayChapters);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.Chapters := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetVolumePercent(Value: Integer);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.VolumePercent := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetMuted(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.Muted := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetPlaybackRateText(const Value: string);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.PlaybackRateText := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  FOnPlayPauseClick := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnBossExitClick(Value: TNotifyEvent);
begin
  FOnBossExitClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnBossGesture(Value: TNotifyEvent);
begin
  FOnBossGesture := Value;
end;

procedure TVideoMinerVideoSurface.SetOnEndActionClick(Value: TNotifyEvent);
begin
  FOnEndActionClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnEndActionClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnCheckClick(Value: TNotifyEvent);
begin
  FOnCheckClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnCheckClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnAddChapterClick(Value: TNotifyEvent);
begin
  FOnAddChapterClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnAddChapterClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnDeleteChapterClick(Value: TNotifyEvent);
begin
  FOnDeleteChapterClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnDeleteChapterClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnFullScreenClick(Value: TNotifyEvent);
begin
  FOnFullScreenClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnFullScreenClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnMuteClick(Value: TNotifyEvent);
begin
  FOnMuteClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnMuteClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnPlaybackRateClick(Value: TNotifyEvent);
begin
  FOnPlaybackRateClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnPlaybackRateClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
begin
  FOnSeek := Value;
  if FSeekBar <> nil then
    FSeekBar.OnSeek := Value;
end;

procedure TVideoMinerVideoSurface.SetOnVolumeChange(
  Value: TVideoMinerOverlayVolumeEvent);
begin
  FOnVolumeChange := Value;
  if FSeekBar <> nil then
    FSeekBar.OnVolumeChange := Value;
end;

procedure TVideoMinerVideoSurface.SurfaceClickTimer(Sender: TObject);
begin
  FSurfaceClickTimer.Enabled := False;
  if not FPendingSurfaceClick then
    Exit;

  FPendingSurfaceClick := False;
  if Assigned(FOnPlayPauseClick) then
    FOnPlayPauseClick(Self);
end;

procedure TVideoMinerVideoSurface.SetOnFirstFrameClick(Value: TNotifyEvent);
begin
  FOnFirstFrameClick := Value;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnLastFrameClick(Value: TNotifyEvent);
begin
  FOnLastFrameClick := Value;
  if FLastFrameButton <> nil then
    FLastFrameButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnNavigatePreviousClick(Value: TNotifyEvent);
begin
  FOnNavigatePreviousClick := Value;
  if FPreviousFileButton <> nil then
    FPreviousFileButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnNavigateNextClick(Value: TNotifyEvent);
begin
  FOnNavigateNextClick := Value;
  if FNextFileButton <> nil then
    FNextFileButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSkipBackwardClick(Value: TNotifyEvent);
begin
  FOnSkipBackwardClick := Value;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSkipForwardClick(Value: TNotifyEvent);
begin
  FOnSkipForwardClick := Value;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

end.
