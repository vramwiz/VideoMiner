unit VideoMinerVideoSurface;

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Types, Vcl.Controls, Vcl.Graphics,
  VideoMinerOverlay;

type
  TVideoMinerVideoSurface = class(TCustomControl)
  private
    FBitmap: TBitmap;
    FPaintBuffer: TBitmap;
    FFirstFrameButton: TVideoMinerOverlayEdgeButton;
    FLastFrameButton: TVideoMinerOverlayEdgeButton;
    FOnFirstFrameClick: TNotifyEvent;
    FOnFullScreenClick: TNotifyEvent;
    FOnLastFrameClick: TNotifyEvent;
    FOnPlayPauseClick: TNotifyEvent;
    FOnSeek: TVideoMinerOverlaySeekEvent;
    FOnSkipBackwardClick: TNotifyEvent;
    FOnSkipForwardClick: TNotifyEvent;
    FOverlayVisible: Boolean;
    FPlayPauseButton: TVideoMinerOverlayPlayPauseButton;
    FPreviewRect: TRect;
    FSeekBar: TVideoMinerOverlaySeekBar;
    FSeekBarVisible: Boolean;
    FSkipBackwardButton: TVideoMinerOverlaySkipButton;
    FSkipForwardButton: TVideoMinerOverlaySkipButton;
    procedure DrawFrame(Canvas: TCanvas; const DestRect: TRect);
    function FitRect: TRect;
    function HitAnyOverlayButton(const Point: TPoint): Boolean;
    function HitSeekBar(const Point: TPoint): Boolean;
    procedure InvalidateAllOverlayControls;
    procedure InvalidateOverlayControl(Control: TVideoMinerOverlayControl);
    procedure SetSeekBarVisible(Value: Boolean);
    procedure SetFullScreen(Value: Boolean);
    procedure SetOverlayVisible(Value: Boolean);
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    procedure SetOnFullScreenClick(Value: TNotifyEvent);
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    procedure SetOnSkipBackwardClick(Value: TNotifyEvent);
    procedure SetOnSkipForwardClick(Value: TNotifyEvent);
    procedure SetPlaybackActive(Value: Boolean);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,
      Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,
      Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Clear;
    function PrepareBgrx32Frame(Width, Height: Integer; out Buffer: Pointer;
      out BufferStride: Integer): Boolean;
    procedure Present;
    procedure PresentImmediate;
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    property Bitmap: TBitmap read FBitmap;
    property FullScreen: Boolean write SetFullScreen;
    property OnFirstFrameClick: TNotifyEvent read FOnFirstFrameClick write SetOnFirstFrameClick;
    property OnFullScreenClick: TNotifyEvent read FOnFullScreenClick write SetOnFullScreenClick;
    property OnLastFrameClick: TNotifyEvent read FOnLastFrameClick write SetOnLastFrameClick;
    property OnPlayPauseClick: TNotifyEvent read FOnPlayPauseClick write SetOnPlayPauseClick;
    property OnSeek: TVideoMinerOverlaySeekEvent read FOnSeek write SetOnSeek;
    property OnSkipBackwardClick: TNotifyEvent read FOnSkipBackwardClick write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent read FOnSkipForwardClick write SetOnSkipForwardClick;
    property PlaybackActive: Boolean write SetPlaybackActive;
  end;

implementation

uses
  System.Diagnostics, System.Math, System.SysUtils, VideoMinerDebugLog;

constructor TVideoMinerVideoSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := False;

  FBitmap := TBitmap.Create;
  FPaintBuffer := TBitmap.Create;
  FPaintBuffer.PixelFormat := pf32bit;
  FOverlayVisible := False;
  FSeekBarVisible := False;
  FFirstFrameButton := TVideoMinerOverlayEdgeButton.Create(edFirst);
  FSkipBackwardButton := TVideoMinerOverlaySkipButton.Create(sdBackward);
  FPlayPauseButton := TVideoMinerOverlayPlayPauseButton.Create;
  FSkipForwardButton := TVideoMinerOverlaySkipButton.Create(sdForward);
  FLastFrameButton := TVideoMinerOverlayEdgeButton.Create(edLast);
  FSeekBar := TVideoMinerOverlaySeekBar.Create;
  FFirstFrameButton.Visible := False;
  FSkipBackwardButton.Visible := False;
  FPlayPauseButton.Visible := False;
  FSkipForwardButton.Visible := False;
  FLastFrameButton.Visible := False;
  FSeekBar.Visible := False;
end;

destructor TVideoMinerVideoSurface.Destroy;
begin
  FSeekBar.Free;
  FLastFrameButton.Free;
  FSkipForwardButton.Free;
  FPlayPauseButton.Free;
  FSkipBackwardButton.Free;
  FFirstFrameButton.Free;
  FPaintBuffer.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoSurface.Clear;
begin
  FBitmap.SetSize(0, 0);
  if FSeekBar <> nil then
    FSeekBar.SetProgress(0, 0);
  SetSeekBarVisible(False);
  Invalidate;
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
begin
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  Canvas.StretchDraw(DestRect, FBitmap);
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
  InvalidateOverlayControl(FFirstFrameButton);
  InvalidateOverlayControl(FSkipBackwardButton);
  InvalidateOverlayControl(FPlayPauseButton);
  InvalidateOverlayControl(FSkipForwardButton);
  InvalidateOverlayControl(FLastFrameButton);
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

function TVideoMinerVideoSurface.HitSeekBar(const Point: TPoint): Boolean;
begin
  Result := (FSeekBar <> nil) and FSeekBar.BoundsHitTest(Point);
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
end;

procedure TVideoMinerVideoSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  MousePoint: TPoint;
begin
  inherited MouseMove(Shift, X, Y);
  MousePoint := Point(X, Y);

  SetOverlayVisible(HitAnyOverlayButton(MousePoint));
  SetSeekBarVisible(HitSeekBar(MousePoint) or
    ((FSeekBar <> nil) and FSeekBar.Dragging));

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
end;

procedure TVideoMinerVideoSurface.Paint;
{$IFDEF DEBUG}
var
  PaintWatch: TStopwatch;
{$ENDIF}
var
  DrawCanvas: TCanvas;
  DestRect: TRect;
begin
{$IFDEF DEBUG}
  PaintWatch := TStopwatch.StartNew;
{$ENDIF}
  if (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;

  if (FPaintBuffer.Width <> ClientWidth) or
     (FPaintBuffer.Height <> ClientHeight) then
    FPaintBuffer.SetSize(ClientWidth, ClientHeight);

  DrawCanvas := FPaintBuffer.Canvas;
  DrawCanvas.Brush.Color := clBlack;
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
  begin
    DrawCanvas.FillRect(ClientRect);
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
  if FSeekBar <> nil then
    FSeekBar.UpdateLayout(FPreviewRect);

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
  if FSeekBarVisible and (FSeekBar <> nil) then
    FSeekBar.Paint(DrawCanvas);
  Canvas.Draw(0, 0, FPaintBuffer);
{$IFDEF DEBUG}
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

procedure TVideoMinerVideoSurface.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  FOnPlayPauseClick := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnFullScreenClick(Value: TNotifyEvent);
begin
  FOnFullScreenClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnFullScreenClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
begin
  FOnSeek := Value;
  if FSeekBar <> nil then
    FSeekBar.OnSeek := Value;
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
