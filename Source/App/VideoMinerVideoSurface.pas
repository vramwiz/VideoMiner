unit VideoMinerVideoSurface;

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Types, Vcl.Controls, Vcl.Graphics,
  VideoMinerOverlay;

type
  TVideoMinerVideoSurface = class(TCustomControl)
  private
    FBitmap: TBitmap;
    FOnPlayPauseClick: TNotifyEvent;
    FOnSkipBackwardClick: TNotifyEvent;
    FOnSkipForwardClick: TNotifyEvent;
    FOverlayVisible: Boolean;
    FPlayPauseButton: TVideoMinerOverlayPlayPauseButton;
    FPreviewRect: TRect;
    FSkipBackwardButton: TVideoMinerOverlaySkipButton;
    FSkipForwardButton: TVideoMinerOverlaySkipButton;
    procedure DrawFrame(Canvas: TCanvas; const DestRect: TRect);
    function FitRect: TRect;
    function HitAnyOverlayButton(const Point: TPoint): Boolean;
    procedure InvalidateAllOverlayControls;
    procedure InvalidateOverlayControl(Control: TVideoMinerOverlayControl);
    procedure SetOverlayVisible(Value: Boolean);
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
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
    property Bitmap: TBitmap read FBitmap;
    property OnPlayPauseClick: TNotifyEvent read FOnPlayPauseClick write SetOnPlayPauseClick;
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
  FOverlayVisible := False;
  FSkipBackwardButton := TVideoMinerOverlaySkipButton.Create(sdBackward);
  FPlayPauseButton := TVideoMinerOverlayPlayPauseButton.Create;
  FSkipForwardButton := TVideoMinerOverlaySkipButton.Create(sdForward);
  FSkipBackwardButton.Visible := False;
  FPlayPauseButton.Visible := False;
  FSkipForwardButton.Visible := False;
end;

destructor TVideoMinerVideoSurface.Destroy;
begin
  FSkipForwardButton.Free;
  FPlayPauseButton.Free;
  FSkipBackwardButton.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoSurface.Clear;
begin
  FBitmap.SetSize(0, 0);
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
  InvalidateOverlayControl(FSkipBackwardButton);
  InvalidateOverlayControl(FPlayPauseButton);
  InvalidateOverlayControl(FSkipForwardButton);
end;

function TVideoMinerVideoSurface.HitAnyOverlayButton(const Point: TPoint): Boolean;
begin
  Result :=
    ((FSkipBackwardButton <> nil) and FSkipBackwardButton.BoundsHitTest(Point)) or
    ((FPlayPauseButton <> nil) and FPlayPauseButton.BoundsHitTest(Point)) or
    ((FSkipForwardButton <> nil) and FSkipForwardButton.BoundsHitTest(Point));
end;

procedure TVideoMinerVideoSurface.SetOverlayVisible(Value: Boolean);
begin
  if FOverlayVisible = Value then
    Exit;

  FOverlayVisible := Value;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.Visible := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.Visible := Value;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.Visible := Value;
  InvalidateAllOverlayControls;
end;

procedure TVideoMinerVideoSurface.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and FOverlayVisible then
  begin
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSkipForwardButton);
  end;
end;

procedure TVideoMinerVideoSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  MousePoint: TPoint;
begin
  inherited MouseMove(Shift, X, Y);
  MousePoint := Point(X, Y);
  SetOverlayVisible(HitAnyOverlayButton(MousePoint));
  if not FOverlayVisible then
    Exit;

  if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseMove(MousePoint) then
    InvalidateOverlayControl(FSkipBackwardButton);
  if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseMove(MousePoint) then
    InvalidateOverlayControl(FPlayPauseButton);
  if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseMove(MousePoint) then
    InvalidateOverlayControl(FSkipForwardButton);
end;

procedure TVideoMinerVideoSurface.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button = mbLeft) and FOverlayVisible then
  begin
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSkipForwardButton);
  end;
end;

procedure TVideoMinerVideoSurface.Paint;
{$IFDEF DEBUG}
var
  PaintWatch: TStopwatch;
{$ENDIF}
var
  DestRect: TRect;
begin
{$IFDEF DEBUG}
  PaintWatch := TStopwatch.StartNew;
{$ENDIF}
  Canvas.Brush.Color := clBlack;
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
  begin
    Canvas.FillRect(ClientRect);
    Exit;
  end;

  DestRect := FitRect;
  FPreviewRect := DestRect;
  if DestRect.Top > 0 then
    Canvas.FillRect(Rect(0, 0, ClientWidth, DestRect.Top));
  if DestRect.Bottom < ClientHeight then
    Canvas.FillRect(Rect(0, DestRect.Bottom, ClientWidth, ClientHeight));
  if DestRect.Left > 0 then
    Canvas.FillRect(Rect(0, DestRect.Top, DestRect.Left, DestRect.Bottom));
  if DestRect.Right < ClientWidth then
    Canvas.FillRect(Rect(DestRect.Right, DestRect.Top, ClientWidth, DestRect.Bottom));

  DrawFrame(Canvas, DestRect);
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.UpdateLayout(FPreviewRect);
  if FPlayPauseButton <> nil then
    FPlayPauseButton.UpdateLayout(FPreviewRect);
  if FSkipForwardButton <> nil then
    FSkipForwardButton.UpdateLayout(FPreviewRect);

  if not FOverlayVisible then
    Exit;

  if FSkipBackwardButton <> nil then
  begin
    FSkipBackwardButton.Paint(Canvas);
  end;
  if FPlayPauseButton <> nil then
  begin
    FPlayPauseButton.Paint(Canvas);
  end;
  if FSkipForwardButton <> nil then
  begin
    FSkipForwardButton.Paint(Canvas);
  end;
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

procedure TVideoMinerVideoSurface.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  FOnPlayPauseClick := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.OnClick := Value;
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
