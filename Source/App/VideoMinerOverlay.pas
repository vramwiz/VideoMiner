unit VideoMinerOverlay;

interface

uses
  System.Classes, System.Math, System.SysUtils, System.Types, Winapi.Windows,
  Vcl.Graphics;

type
  TVideoMinerOverlayEdgeDirection = (edFirst, edLast);
  TVideoMinerOverlayFileNavDirection = (fndPrevious, fndNext);
  TVideoMinerOverlaySeekEvent = procedure(Sender: TObject; PositionMs: Integer) of object;
  TVideoMinerOverlaySkipDirection = (sdBackward, sdForward);
  TVideoMinerOverlayVolumeEvent = procedure(Sender: TObject; VolumePercent: Integer) of object;

  TVideoMinerOverlayControl = class abstract
  private
    FBounds: TRect;
    FEnabled: Boolean;
    FVisible: Boolean;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; virtual; abstract;
    procedure PaintControl(Canvas: TCanvas); virtual; abstract;
    property Bounds: TRect read FBounds;
  public
    constructor Create; virtual;
    procedure UpdateLayout(const PreviewRect: TRect); virtual;
    procedure Paint(Canvas: TCanvas); virtual;
    function BoundsHitTest(const Point: TPoint): Boolean; virtual;
    function HitTest(const Point: TPoint): Boolean; virtual;
    function MouseDown(const Point: TPoint): Boolean; virtual;
    function MouseMove(const Point: TPoint): Boolean; virtual;
    function MouseUp(const Point: TPoint): Boolean; virtual;
    property BoundsRect: TRect read FBounds;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Visible: Boolean read FVisible write FVisible;
  end;

  TVideoMinerOverlayButton = class abstract(TVideoMinerOverlayControl)
  private
    FHovered: Boolean;
    FOnClick: TNotifyEvent;
    FPressed: Boolean;
  protected
    procedure DoClick; virtual;
    property Hovered: Boolean read FHovered;
    property Pressed: Boolean read FPressed;
  public
    function MouseDown(const Point: TPoint): Boolean; override;
    function MouseMove(const Point: TPoint): Boolean; override;
    function MouseUp(const Point: TPoint): Boolean; override;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  TVideoMinerOverlayPlayPauseButton = class(TVideoMinerOverlayButton)
  private
    FIsPlaying: Boolean;
    procedure DrawAlphaPolygon(Canvas: TCanvas; const Points: array of TPoint;
      Alpha: Byte);
    procedure DrawAlphaRect(Canvas: TCanvas; const Rect: TRect; Alpha: Byte);
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    property IsPlaying: Boolean read FIsPlaying write FIsPlaying;
  end;

  TVideoMinerOverlaySkipButton = class(TVideoMinerOverlayButton)
  private
    FDirection: TVideoMinerOverlaySkipDirection;
    procedure DrawAlphaPolyline(Canvas: TCanvas; const Points: array of TPoint;
      PenWidth: Integer; Alpha: Byte);
    procedure DrawAlphaPolygon(Canvas: TCanvas; const Points: array of TPoint;
      Alpha: Byte);
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    constructor Create(Direction: TVideoMinerOverlaySkipDirection); reintroduce;
    property Direction: TVideoMinerOverlaySkipDirection read FDirection write FDirection;
  end;

  TVideoMinerOverlayEdgeButton = class(TVideoMinerOverlayButton)
  private
    FDirection: TVideoMinerOverlayEdgeDirection;
    procedure DrawAlphaPolygon(Canvas: TCanvas; const Points: array of TPoint;
      Alpha: Byte);
    procedure DrawAlphaRect(Canvas: TCanvas; const DrawRect: TRect; Alpha: Byte);
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    constructor Create(Direction: TVideoMinerOverlayEdgeDirection); reintroduce;
    property Direction: TVideoMinerOverlayEdgeDirection read FDirection write FDirection;
  end;

  TVideoMinerOverlayFileNavButton = class(TVideoMinerOverlayButton)
  private
    FDirection: TVideoMinerOverlayFileNavDirection;
    procedure DrawAlphaPolyline(Canvas: TCanvas; const Points: array of TPoint;
      PenWidth: Integer; Alpha: Byte);
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    constructor Create(Direction: TVideoMinerOverlayFileNavDirection); reintroduce;
    property Direction: TVideoMinerOverlayFileNavDirection read FDirection write FDirection;
  end;

  TVideoMinerOverlaySeekBar = class(TVideoMinerOverlayControl)
  private
    FDragPositionMs: Integer;
    FDragging: Boolean;
    FEndActionButtonHovered: Boolean;
    FEndActionButtonPressed: Boolean;
    FEndActionText: string;
    FFullScreen: Boolean;
    FFullScreenButtonHovered: Boolean;
    FFullScreenButtonPressed: Boolean;
    FHovered: Boolean;
    FMaxMs: Integer;
    FMuted: Boolean;
    FMuteButtonHovered: Boolean;
    FMuteButtonPressed: Boolean;
    FOnEndActionClick: TNotifyEvent;
    FOnFullScreenClick: TNotifyEvent;
    FOnMuteClick: TNotifyEvent;
    FOnSeek: TVideoMinerOverlaySeekEvent;
    FOnVolumeChange: TVideoMinerOverlayVolumeEvent;
    FPositionMs: Integer;
    FVolumeDragging: Boolean;
    FVolumeHovered: Boolean;
    FVolumePercent: Integer;
    procedure DrawAlphaEllipse(Canvas: TCanvas; const DrawRect: TRect;
      Alpha: Byte);
    procedure DrawAlphaPanel(Canvas: TCanvas; const DrawRect: TRect;
      Radius: Integer; Alpha: Byte);
    procedure DrawAlphaPolyline(Canvas: TCanvas; const Points: array of TPoint;
      PenWidth: Integer; Alpha: Byte);
    procedure DrawAlphaRoundRect(Canvas: TCanvas; const DrawRect: TRect;
      Radius: Integer; Alpha: Byte);
    procedure DrawFullScreenIcon(Canvas: TCanvas; const DrawRect: TRect;
      Alpha: Byte);
    procedure DrawMuteIcon(Canvas: TCanvas; const DrawRect: TRect;
      Alpha: Byte);
    function DisplayPositionMs: Integer;
    function EndActionButtonHitTest(const Point: TPoint): Boolean;
    function EndActionButtonRect: TRect;
    function FormatTimeMs(ValueMs: Integer): string;
    function FullScreenButtonAlpha: Byte;
    function FullScreenButtonHitTest(const Point: TPoint): Boolean;
    function FullScreenButtonRect: TRect;
    function MuteButtonAlpha: Byte;
    function MuteButtonHitTest(const Point: TPoint): Boolean;
    function MuteButtonRect: TRect;
    function PositionFromPoint(const Point: TPoint): Integer;
    procedure SetEndActionText(const Value: string);
    procedure SetFullScreen(Value: Boolean);
    procedure SetMuted(Value: Boolean);
    procedure SetVolumePercent(Value: Integer);
    function TrackRect: TRect;
    function VolumeFromPoint(const Point: TPoint): Integer;
    function VolumeLabelRect: TRect;
    function VolumeHitTest(const Point: TPoint): Boolean;
    function VolumeTrackRect: TRect;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    function MouseDown(const Point: TPoint): Boolean; override;
    function MouseMove(const Point: TPoint): Boolean; override;
    function MouseUp(const Point: TPoint): Boolean; override;
    procedure SetProgress(PositionMs, MaxMs: Integer);
    property Dragging: Boolean read FDragging;
    property EndActionText: string read FEndActionText write SetEndActionText;
    property FullScreen: Boolean read FFullScreen write SetFullScreen;
    property OnEndActionClick: TNotifyEvent read FOnEndActionClick write FOnEndActionClick;
    property OnFullScreenClick: TNotifyEvent read FOnFullScreenClick write FOnFullScreenClick;
    property OnMuteClick: TNotifyEvent read FOnMuteClick write FOnMuteClick;
    property OnSeek: TVideoMinerOverlaySeekEvent read FOnSeek write FOnSeek;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent read FOnVolumeChange write FOnVolumeChange;
    property Muted: Boolean read FMuted write SetMuted;
    property VolumePercent: Integer read FVolumePercent write SetVolumePercent;
  end;

implementation

type
  TRgbTripleArray = array[0..MaxInt div SizeOf(TRGBTriple) - 1] of TRGBTriple;
  PRgbTripleArray = ^TRgbTripleArray;
  TBgraQuad = packed record
    B: Byte;
    G: Byte;
    R: Byte;
    A: Byte;
  end;
  TBgraQuadArray = array[0..MaxInt div SizeOf(TBgraQuad) - 1] of TBgraQuad;
  PBgraQuadArray = ^TBgraQuadArray;

function ClampByte(Value: Integer): Byte;
begin
  Result := Byte(Max(0, Min(255, Value)));
end;

procedure AlphaBlendMask(Canvas: TCanvas; const DestBounds: TRect;
  MaskBitmap: TBitmap; Alpha: Byte);
var
  Blend: TBlendFunction;
  DrawBitmap: TBitmap;
  DrawLine: PBgraQuadArray;
  Height: Integer;
  MaskLine: PRgbTripleArray;
  Width: Integer;
  X: Integer;
  Y: Integer;
begin
  Width := DestBounds.Width;
  Height := DestBounds.Height;
  if (Width <= 0) or (Height <= 0) then
    Exit;

  DrawBitmap := TBitmap.Create;
  try
    DrawBitmap.PixelFormat := pf32bit;
    DrawBitmap.SetSize(Width, Height);
    DrawBitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Height - 1 do
    begin
      MaskLine := MaskBitmap.ScanLine[Y];
      DrawLine := DrawBitmap.ScanLine[Y];
      for X := 0 to Width - 1 do
      begin
        if MaskLine[X].rgbtRed > 0 then
        begin
          DrawLine[X].B := Alpha;
          DrawLine[X].G := Alpha;
          DrawLine[X].R := Alpha;
          DrawLine[X].A := Alpha
        end
        else
        begin
          DrawLine[X].B := 0;
          DrawLine[X].G := 0;
          DrawLine[X].R := 0;
          DrawLine[X].A := 0;
        end;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, DestBounds.Left, DestBounds.Top, Width, Height,
      DrawBitmap.Canvas.Handle, 0, 0, Width, Height, Blend);
  finally
    DrawBitmap.Free;
  end;
end;

{ TVideoMinerOverlayControl }

constructor TVideoMinerOverlayControl.Create;
begin
  inherited Create;
  FEnabled := True;
  FVisible := True;
end;

function TVideoMinerOverlayControl.HitTest(const Point: TPoint): Boolean;
begin
  Result := FVisible and FEnabled and BoundsHitTest(Point);
end;

function TVideoMinerOverlayControl.BoundsHitTest(const Point: TPoint): Boolean;
begin
  Result := FEnabled and PtInRect(FBounds, Point);
end;

function TVideoMinerOverlayControl.MouseDown(const Point: TPoint): Boolean;
begin
  Result := HitTest(Point);
end;

function TVideoMinerOverlayControl.MouseMove(const Point: TPoint): Boolean;
begin
  Result := HitTest(Point);
end;

function TVideoMinerOverlayControl.MouseUp(const Point: TPoint): Boolean;
begin
  Result := HitTest(Point);
end;

procedure TVideoMinerOverlayControl.Paint(Canvas: TCanvas);
begin
  if FVisible then
    PaintControl(Canvas);
end;

procedure TVideoMinerOverlayControl.UpdateLayout(const PreviewRect: TRect);
begin
  FBounds := CalculateBounds(PreviewRect);
end;

{ TVideoMinerOverlayButton }

procedure TVideoMinerOverlayButton.DoClick;
begin
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

function TVideoMinerOverlayButton.MouseDown(const Point: TPoint): Boolean;
begin
  Result := inherited MouseDown(Point);
  FPressed := Result;
end;

function TVideoMinerOverlayButton.MouseMove(const Point: TPoint): Boolean;
var
  NewHovered: Boolean;
begin
  NewHovered := HitTest(Point);
  Result := NewHovered <> FHovered;
  FHovered := NewHovered;
end;

function TVideoMinerOverlayButton.MouseUp(const Point: TPoint): Boolean;
var
  WasPressed: Boolean;
begin
  WasPressed := FPressed;
  FPressed := False;
  Result := inherited MouseUp(Point);
  if WasPressed and Result then
    DoClick;
  Result := WasPressed or Result;
end;

{ TVideoMinerOverlayPlayPauseButton }

function TVideoMinerOverlayPlayPauseButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  CenterX: Integer;
  CenterY: Integer;
  Size: Integer;
begin
  Size := Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.14);
  Size := Max(48, Min(128, Size));

  CenterX := PreviewRect.Left + PreviewRect.Width div 2;
  CenterY := PreviewRect.Top + PreviewRect.Height div 2;

  Result.Left := CenterX - Size div 2;
  Result.Top := CenterY - Size div 2;
  Result.Right := Result.Left + Size;
  Result.Bottom := Result.Top + Size;
end;

procedure TVideoMinerOverlayPlayPauseButton.DrawAlphaPolygon(Canvas: TCanvas;
  const Points: array of TPoint; Alpha: Byte);
var
  Blend: TBlendFunction;
  DrawBitmap: TBitmap;
  DrawLine: PBgraQuadArray;
  Height: Integer;
  MaskBitmap: TBitmap;
  MaskLine: PRgbTripleArray;
  Width: Integer;
  X: Integer;
  Y: Integer;
begin
  Width := Bounds.Width;
  Height := Bounds.Height;
  if (Width <= 0) or (Height <= 0) then
    Exit;

  MaskBitmap := TBitmap.Create;
  DrawBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Width, Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Width, Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Polygon(Points);

    DrawBitmap.PixelFormat := pf32bit;
    DrawBitmap.SetSize(Width, Height);
    DrawBitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Height - 1 do
    begin
      MaskLine := MaskBitmap.ScanLine[Y];
      DrawLine := DrawBitmap.ScanLine[Y];
      for X := 0 to Width - 1 do
      begin
        if MaskLine[X].rgbtRed > 0 then
        begin
          DrawLine[X].B := Alpha;
          DrawLine[X].G := Alpha;
          DrawLine[X].R := Alpha;
          DrawLine[X].A := Alpha
        end
        else
        begin
          DrawLine[X].B := 0;
          DrawLine[X].G := 0;
          DrawLine[X].R := 0;
          DrawLine[X].A := 0;
        end;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Bounds.Left, Bounds.Top, Width, Height,
      DrawBitmap.Canvas.Handle, 0, 0, Width, Height, Blend);
  finally
    DrawBitmap.Free;
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlayPlayPauseButton.DrawAlphaRect(Canvas: TCanvas;
  const Rect: TRect; Alpha: Byte);
var
  Blend: TBlendFunction;
  Bitmap: TBitmap;
  Line: PBgraQuadArray;
  X: Integer;
  Y: Integer;
begin
  if Rect.IsEmpty then
    Exit;

  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Rect.Width, Rect.Height);
    Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Bitmap.Height - 1 do
    begin
      Line := Bitmap.ScanLine[Y];
      for X := 0 to Bitmap.Width - 1 do
      begin
        Line[X].B := Alpha;
        Line[X].G := Alpha;
        Line[X].R := Alpha;
        Line[X].A := Alpha;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Rect.Left, Rect.Top, Rect.Width, Rect.Height,
      Bitmap.Canvas.Handle, 0, 0, Rect.Width, Rect.Height, Blend);
  finally
    Bitmap.Free;
  end;
end;

function TVideoMinerOverlayPlayPauseButton.IconAlpha: Byte;
begin
  Result := 170;
  if Hovered then
    Result := 210;
  if Pressed then
    Result := 245;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlayPlayPauseButton.PaintControl(Canvas: TCanvas);
var
  Alpha: Byte;
  BarGap: Integer;
  BarHeight: Integer;
  BarWidth: Integer;
  CenterX: Integer;
  CenterY: Integer;
  IconSize: Integer;
  LeftBar: TRect;
  LocalPoints: array[0..2] of TPoint;
  RightBar: TRect;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  IconSize := Min(Bounds.Width, Bounds.Height);
  CenterX := Bounds.Left + Bounds.Width div 2;
  CenterY := Bounds.Top + Bounds.Height div 2;

  if FIsPlaying then
  begin
    BarWidth := Max(4, Round(IconSize * 0.16));
    BarHeight := Max(12, Round(IconSize * 0.58));
    BarGap := Max(6, Round(IconSize * 0.16));
    LeftBar := Rect(CenterX - BarGap div 2 - BarWidth,
      CenterY - BarHeight div 2, CenterX - BarGap div 2,
      CenterY + BarHeight div 2);
    RightBar := Rect(CenterX + BarGap div 2,
      CenterY - BarHeight div 2, CenterX + BarGap div 2 + BarWidth,
      CenterY + BarHeight div 2);
    DrawAlphaRect(Canvas, LeftBar, Alpha);
    DrawAlphaRect(Canvas, RightBar, Alpha);
  end
  else
  begin
    LocalPoints[0] := Point(Round(IconSize * 0.34), Round(IconSize * 0.22));
    LocalPoints[1] := Point(Round(IconSize * 0.34), Round(IconSize * 0.78));
    LocalPoints[2] := Point(Round(IconSize * 0.76), Round(IconSize * 0.50));
    DrawAlphaPolygon(Canvas, LocalPoints, Alpha);
  end;
end;

{ TVideoMinerOverlaySkipButton }

constructor TVideoMinerOverlaySkipButton.Create(
  Direction: TVideoMinerOverlaySkipDirection);
begin
  inherited Create;
  FDirection := Direction;
end;

function TVideoMinerOverlaySkipButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  CenterX: Integer;
  CenterY: Integer;
  Offset: Integer;
  Size: Integer;
begin
  Size := Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.095);
  Size := Max(36, Min(92, Size));
  Offset := Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.22);

  CenterX := PreviewRect.Left + PreviewRect.Width div 2;
  if FDirection = sdBackward then
    Dec(CenterX, Offset)
  else
    Inc(CenterX, Offset);
  CenterY := PreviewRect.Top + PreviewRect.Height div 2;

  Result.Left := CenterX - Size div 2;
  Result.Top := CenterY - Size div 2;
  Result.Right := Result.Left + Size;
  Result.Bottom := Result.Top + Size;
end;

procedure TVideoMinerOverlaySkipButton.DrawAlphaPolygon(Canvas: TCanvas;
  const Points: array of TPoint; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Polygon(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySkipButton.DrawAlphaPolyline(Canvas: TCanvas;
  const Points: array of TPoint; PenWidth: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or (Length(Points) <= 1) then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Color := clWhite;
    MaskBitmap.Canvas.Pen.Width := PenWidth;
    MaskBitmap.Canvas.Pen.Style := psSolid;
    MaskBitmap.Canvas.Polyline(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

function TVideoMinerOverlaySkipButton.IconAlpha: Byte;
begin
  Result := 155;
  if Hovered then
    Result := 205;
  if Pressed then
    Result := 240;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlaySkipButton.PaintControl(Canvas: TCanvas);
const
  ARC_POINT_COUNT = 24;
var
  Alpha: Byte;
  Angle: Double;
  ArcPoints: array of TPoint;
  CenterX: Double;
  CenterY: Double;
  HeadPoints: array[0..2] of TPoint;
  I: Integer;
  LocalX: Integer;
  PenWidth: Integer;
  RadiusX: Double;
  RadiusY: Double;
  Size: Integer;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  Size := Min(Bounds.Width, Bounds.Height);
  CenterX := Size * 0.50;
  CenterY := Size * 0.55;
  RadiusX := Size * 0.29;
  RadiusY := Size * 0.28;

  SetLength(ArcPoints, ARC_POINT_COUNT);
  for I := 0 to ARC_POINT_COUNT - 1 do
  begin
    Angle := (210 - (190 * I / (ARC_POINT_COUNT - 1))) * Pi / 180;
    LocalX := Round(CenterX + Cos(Angle) * RadiusX);
    if FDirection = sdBackward then
      LocalX := Size - LocalX;
    ArcPoints[I] := Point(LocalX, Round(CenterY + Sin(Angle) * RadiusY));
  end;

  PenWidth := Max(3, Round(Size * 0.075));
  DrawAlphaPolyline(Canvas, ArcPoints, PenWidth, Alpha);

  if FDirection = sdForward then
  begin
    HeadPoints[0] := Point(Round(Size * 0.78), Round(Size * 0.44));
    HeadPoints[1] := Point(Round(Size * 0.61), Round(Size * 0.35));
    HeadPoints[2] := Point(Round(Size * 0.66), Round(Size * 0.57));
  end
  else
  begin
    HeadPoints[0] := Point(Round(Size * 0.22), Round(Size * 0.44));
    HeadPoints[1] := Point(Round(Size * 0.39), Round(Size * 0.35));
    HeadPoints[2] := Point(Round(Size * 0.34), Round(Size * 0.57));
  end;
  DrawAlphaPolygon(Canvas, HeadPoints, Alpha);
end;

{ TVideoMinerOverlayEdgeButton }

constructor TVideoMinerOverlayEdgeButton.Create(
  Direction: TVideoMinerOverlayEdgeDirection);
begin
  inherited Create;
  FDirection := Direction;
end;

function TVideoMinerOverlayEdgeButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  CenterX: Integer;
  CenterY: Integer;
  Offset: Integer;
  Size: Integer;
begin
  Size := Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.075);
  Size := Max(30, Min(72, Size));
  Offset := Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.34);

  CenterX := PreviewRect.Left + PreviewRect.Width div 2;
  if FDirection = edFirst then
    Dec(CenterX, Offset)
  else
    Inc(CenterX, Offset);
  CenterY := PreviewRect.Top + PreviewRect.Height div 2;

  Result.Left := CenterX - Size div 2;
  Result.Top := CenterY - Size div 2;
  Result.Right := Result.Left + Size;
  Result.Bottom := Result.Top + Size;
end;

procedure TVideoMinerOverlayEdgeButton.DrawAlphaPolygon(Canvas: TCanvas;
  const Points: array of TPoint; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Polygon(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlayEdgeButton.DrawAlphaRect(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.FillRect(DrawRect);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

function TVideoMinerOverlayEdgeButton.IconAlpha: Byte;
begin
  Result := 135;
  if Hovered then
    Result := 195;
  if Pressed then
    Result := 235;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlayEdgeButton.PaintControl(Canvas: TCanvas);
var
  Alpha: Byte;
  BarRect: TRect;
  IconSize: Integer;
  TrianglePoints: array[0..2] of TPoint;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  IconSize := Min(Bounds.Width, Bounds.Height);

  if FDirection = edFirst then
  begin
    BarRect := Rect(Round(IconSize * 0.22), Round(IconSize * 0.28),
      Round(IconSize * 0.29), Round(IconSize * 0.72));
    TrianglePoints[0] := Point(Round(IconSize * 0.73), Round(IconSize * 0.24));
    TrianglePoints[1] := Point(Round(IconSize * 0.73), Round(IconSize * 0.76));
    TrianglePoints[2] := Point(Round(IconSize * 0.37), Round(IconSize * 0.50));
  end
  else
  begin
    BarRect := Rect(Round(IconSize * 0.71), Round(IconSize * 0.28),
      Round(IconSize * 0.78), Round(IconSize * 0.72));
    TrianglePoints[0] := Point(Round(IconSize * 0.27), Round(IconSize * 0.24));
    TrianglePoints[1] := Point(Round(IconSize * 0.27), Round(IconSize * 0.76));
    TrianglePoints[2] := Point(Round(IconSize * 0.63), Round(IconSize * 0.50));
  end;

  DrawAlphaRect(Canvas, BarRect, Alpha);
  DrawAlphaPolygon(Canvas, TrianglePoints, Alpha);
end;

{ TVideoMinerOverlayFileNavButton }

constructor TVideoMinerOverlayFileNavButton.Create(
  Direction: TVideoMinerOverlayFileNavDirection);
begin
  inherited Create;
  FDirection := Direction;
end;

function TVideoMinerOverlayFileNavButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  Height: Integer;
  Width: Integer;
begin
  Result := TRect.Empty;
  if PreviewRect.IsEmpty then
    Exit;

  Width := Round(PreviewRect.Width * 0.12);
  Width := Max(56, Min(150, Width));
  Height := Round(PreviewRect.Height * 0.52);
  Height := Max(120, Min(360, Height));

  if FDirection = fndPrevious then
  begin
    Result.Left := PreviewRect.Left;
    Result.Right := PreviewRect.Left + Width;
  end
  else
  begin
    Result.Left := PreviewRect.Right - Width;
    Result.Right := PreviewRect.Right;
  end;
  Result.Top := PreviewRect.Top + (PreviewRect.Height - Height) div 2;
  Result.Bottom := Result.Top + Height;
end;

procedure TVideoMinerOverlayFileNavButton.DrawAlphaPolyline(Canvas: TCanvas;
  const Points: array of TPoint; PenWidth: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or (Length(Points) <= 1) then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Color := clWhite;
    MaskBitmap.Canvas.Pen.Width := PenWidth;
    MaskBitmap.Canvas.Pen.Style := psSolid;
    MaskBitmap.Canvas.Polyline(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

function TVideoMinerOverlayFileNavButton.IconAlpha: Byte;
begin
  Result := 120;
  if Hovered then
    Result := 190;
  if Pressed then
    Result := 230;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlayFileNavButton.PaintControl(Canvas: TCanvas);
var
  Alpha: Byte;
  Chevron: array[0..2] of TPoint;
  IconHeight: Integer;
  IconWidth: Integer;
  IconLeft: Integer;
  IconTop: Integer;
  PenWidth: Integer;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  IconWidth := Max(24, Min(54, Round(Bounds.Width * 0.34)));
  IconHeight := Max(48, Min(110, Round(Bounds.Height * 0.34)));
  IconTop := (Bounds.Height - IconHeight) div 2;
  PenWidth := Max(4, Round(IconWidth * 0.16));

  if FDirection = fndPrevious then
  begin
    IconLeft := Max(18, Round(Bounds.Width * 0.28));
    Chevron[0] := Point(IconLeft + IconWidth, IconTop);
    Chevron[1] := Point(IconLeft, IconTop + IconHeight div 2);
    Chevron[2] := Point(IconLeft + IconWidth, IconTop + IconHeight);
  end
  else
  begin
    IconLeft := Bounds.Width - Max(18, Round(Bounds.Width * 0.28)) - IconWidth;
    Chevron[0] := Point(IconLeft, IconTop);
    Chevron[1] := Point(IconLeft + IconWidth, IconTop + IconHeight div 2);
    Chevron[2] := Point(IconLeft, IconTop + IconHeight);
  end;

  DrawAlphaPolyline(Canvas, Chevron, PenWidth, Alpha);
end;

{ TVideoMinerOverlaySeekBar }

function TVideoMinerOverlaySeekBar.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  BottomOffset: Integer;
  Height: Integer;
  Width: Integer;
begin
  Result := TRect.Empty;
  if PreviewRect.IsEmpty then
    Exit;

  Height := 72;
  Width := Round(PreviewRect.Width * 0.88);
  Width := Max(160, Min(PreviewRect.Width - 32, Width));
  BottomOffset := Max(12, Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.045));

  Result.Left := PreviewRect.Left + (PreviewRect.Width - Width) div 2;
  Result.Right := Result.Left + Width;
  Result.Bottom := PreviewRect.Bottom - BottomOffset;
  Result.Top := Result.Bottom - Height;
  if Result.Top < PreviewRect.Top then
    OffsetRect(Result, 0, PreviewRect.Top - Result.Top);
end;

function TVideoMinerOverlaySeekBar.DisplayPositionMs: Integer;
begin
  if FDragging then
    Result := FDragPositionMs
  else
    Result := FPositionMs;

  if Result < 0 then
    Result := 0
  else if Result > FMaxMs then
    Result := FMaxMs;
end;

function TVideoMinerOverlaySeekBar.FormatTimeMs(ValueMs: Integer): string;
var
  Hours: Integer;
  Minutes: Integer;
  Seconds: Integer;
  TotalSeconds: Integer;
begin
  TotalSeconds := Max(0, (ValueMs + 500) div 1000);
  Hours := TotalSeconds div 3600;
  Minutes := (TotalSeconds div 60) mod 60;
  Seconds := TotalSeconds mod 60;

  if Hours > 0 then
    Result := Format('%d:%.2d:%.2d', [Hours, Minutes, Seconds])
  else
    Result := Format('%d:%.2d', [Minutes, Seconds]);
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaEllipse(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Ellipse(DrawRect);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaPanel(Canvas: TCanvas;
  const DrawRect: TRect; Radius: Integer; Alpha: Byte);
var
  Bitmap: TBitmap;
  Blend: TBlendFunction;
  Line: PBgraQuadArray;
  MaskBitmap: TBitmap;
  MaskLine: PRgbTripleArray;
  X: Integer;
  Y: Integer;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  Bitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.RoundRect(DrawRect.Left, DrawRect.Top, DrawRect.Right,
      DrawRect.Bottom, Radius, Radius);

    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Bounds.Width, Bounds.Height);
    Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Bounds.Height - 1 do
    begin
      MaskLine := MaskBitmap.ScanLine[Y];
      Line := Bitmap.ScanLine[Y];
      for X := 0 to Bounds.Width - 1 do
      begin
        if MaskLine[X].rgbtRed > 0 then
        begin
          Line[X].B := 0;
          Line[X].G := 0;
          Line[X].R := 0;
          Line[X].A := Alpha;
        end
        else
        begin
          Line[X].B := 0;
          Line[X].G := 0;
          Line[X].R := 0;
          Line[X].A := 0;
        end;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Bounds.Left, Bounds.Top, Bounds.Width,
      Bounds.Height, Bitmap.Canvas.Handle, 0, 0, Bounds.Width, Bounds.Height,
      Blend);
  finally
    Bitmap.Free;
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaPolyline(Canvas: TCanvas;
  const Points: array of TPoint; PenWidth: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or (Length(Points) <= 1) then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Color := clWhite;
    MaskBitmap.Canvas.Pen.Width := PenWidth;
    MaskBitmap.Canvas.Pen.Style := psSolid;
    MaskBitmap.Canvas.Polyline(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaRoundRect(Canvas: TCanvas;
  const DrawRect: TRect; Radius: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.RoundRect(DrawRect.Left, DrawRect.Top, DrawRect.Right,
      DrawRect.Bottom, Radius, Radius);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawFullScreenIcon(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  Bottom: Integer;
  CenterX: Integer;
  CenterY: Integer;
  Head: Integer;
  Inset: Integer;
  Left: Integer;
  PenWidth: Integer;
  Right: Integer;
  Top: Integer;
  WindowRect: TRect;
begin
  if DrawRect.IsEmpty then
    Exit;

  Left := DrawRect.Left;
  Top := DrawRect.Top;
  Right := DrawRect.Right - 1;
  Bottom := DrawRect.Bottom - 1;
  CenterX := DrawRect.Left + DrawRect.Width div 2;
  CenterY := DrawRect.Top + DrawRect.Height div 2;
  Inset := 7;
  Head := 8;
  PenWidth := 2;

  if not FFullScreen then
  begin
    DrawAlphaPolyline(Canvas, [Point(CenterX - 3, CenterY - 3),
      Point(Left + Inset, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Top + Inset),
      Point(Left + Inset + Head, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Top + Inset),
      Point(Left + Inset, Top + Inset + Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(CenterX + 3, CenterY - 3),
      Point(Right - Inset, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Top + Inset),
      Point(Right - Inset - Head, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Top + Inset),
      Point(Right - Inset, Top + Inset + Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(CenterX - 3, CenterY + 3),
      Point(Left + Inset, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Bottom - Inset),
      Point(Left + Inset + Head, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Bottom - Inset),
      Point(Left + Inset, Bottom - Inset - Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(CenterX + 3, CenterY + 3),
      Point(Right - Inset, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Bottom - Inset),
      Point(Right - Inset - Head, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Bottom - Inset),
      Point(Right - Inset, Bottom - Inset - Head)], PenWidth, Alpha);
  end
  else
  begin
    WindowRect := Rect(CenterX - 7, CenterY - 6, CenterX + 8, CenterY + 7);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Top),
      Point(WindowRect.Right, WindowRect.Top), Point(WindowRect.Right,
      WindowRect.Bottom), Point(WindowRect.Left, WindowRect.Bottom),
      Point(WindowRect.Left, WindowRect.Top)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Top + Inset),
      Point(WindowRect.Left, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Top),
      Point(WindowRect.Left - Head, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Top),
      Point(WindowRect.Left, WindowRect.Top - Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Top + Inset),
      Point(WindowRect.Right, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Top),
      Point(WindowRect.Right + Head, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Top),
      Point(WindowRect.Right, WindowRect.Top - Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Bottom - Inset),
      Point(WindowRect.Left, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Bottom),
      Point(WindowRect.Left - Head, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Bottom),
      Point(WindowRect.Left, WindowRect.Bottom + Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Bottom - Inset),
      Point(WindowRect.Right, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Bottom),
      Point(WindowRect.Right + Head, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Bottom),
      Point(WindowRect.Right, WindowRect.Bottom + Head)], PenWidth, Alpha);
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawMuteIcon(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  CenterY: Integer;
  Left: Integer;
  PenWidth: Integer;
  Speaker: array[0..4] of TPoint;
  Top: Integer;
begin
  if DrawRect.IsEmpty then
    Exit;

  Left := DrawRect.Left + 8;
  Top := DrawRect.Top + 8;
  CenterY := DrawRect.Top + DrawRect.Height div 2;
  PenWidth := 2;

  Speaker[0] := Point(Left, CenterY - 4);
  Speaker[1] := Point(Left + 5, CenterY - 4);
  Speaker[2] := Point(Left + 11, Top);
  Speaker[3] := Point(Left + 11, DrawRect.Bottom - 8);
  Speaker[4] := Point(Left + 5, CenterY + 4);
  DrawAlphaPolyline(Canvas, Speaker, PenWidth, Alpha);
  DrawAlphaPolyline(Canvas, [Speaker[4], Speaker[0]], PenWidth, Alpha);

  if FMuted or (FVolumePercent <= 0) then
  begin
    DrawAlphaPolyline(Canvas, [Point(DrawRect.Right - 9, DrawRect.Top + 8),
      Point(DrawRect.Right - 20, DrawRect.Bottom - 8)], PenWidth, Alpha);
  end
  else
  begin
    DrawAlphaPolyline(Canvas, [Point(DrawRect.Right - 13, CenterY - 7),
      Point(DrawRect.Right - 9, CenterY - 3), Point(DrawRect.Right - 9,
      CenterY + 3), Point(DrawRect.Right - 13, CenterY + 7)], PenWidth,
      Alpha);
  end;
end;

function TVideoMinerOverlaySeekBar.FullScreenButtonAlpha: Byte;
begin
  Result := 185;
  if FFullScreenButtonHovered then
    Result := 225;
  if FFullScreenButtonPressed then
    Result := 250;
  Result := ClampByte(Result);
end;

function TVideoMinerOverlaySeekBar.MuteButtonAlpha: Byte;
begin
  Result := 185;
  if FMuteButtonHovered or FMuted then
    Result := 225;
  if FMuteButtonPressed then
    Result := 250;
  Result := ClampByte(Result);
end;

function TVideoMinerOverlaySeekBar.EndActionButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(EndActionButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.EndActionButtonRect: TRect;
var
  FullScreenRect: TRect;
begin
  FullScreenRect := FullScreenButtonRect;
  Result := Rect(FullScreenRect.Left - 62, FullScreenRect.Top,
    FullScreenRect.Left - 8, FullScreenRect.Bottom);
end;

function TVideoMinerOverlaySeekBar.FullScreenButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(FullScreenButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.MuteButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(MuteButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.FullScreenButtonRect: TRect;
var
  Size: Integer;
begin
  Size := 34;
  Result := Rect(Bounds.Width - Size - 14, Bounds.Height - Size - 10,
    Bounds.Width - 14, Bounds.Height - 10);
end;

function TVideoMinerOverlaySeekBar.MuteButtonRect: TRect;
var
  LabelRect: TRect;
  Size: Integer;
begin
  LabelRect := VolumeLabelRect;
  Size := 28;
  Result := Rect(LabelRect.Right + 22, LabelRect.Top - 2,
    LabelRect.Right + 22 + Size, LabelRect.Top - 2 + Size);
end;

function TVideoMinerOverlaySeekBar.VolumeLabelRect: TRect;
var
  RowTop: Integer;
begin
  RowTop := Bounds.Height - 36;
  Result := Rect(22, RowTop, 112, RowTop + 17);
end;

function TVideoMinerOverlaySeekBar.VolumeTrackRect: TRect;
var
  LabelRect: TRect;
  TrackTop: Integer;
begin
  LabelRect := VolumeLabelRect;
  TrackTop := LabelRect.Bottom + 4;
  Result := Rect(LabelRect.Left, TrackTop, LabelRect.Right, TrackTop + 5);
end;

function TVideoMinerOverlaySeekBar.VolumeHitTest(const Point: TPoint): Boolean;
var
  HitRect: TRect;
begin
  HitRect := VolumeTrackRect;
  HitRect.Left := VolumeLabelRect.Left;
  InflateRect(HitRect, 8, 10);
  Result := BoundsHitTest(Point) and PtInRect(HitRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.VolumeFromPoint(const Point: TPoint): Integer;
var
  LocalX: Integer;
  Track: TRect;
begin
  Track := VolumeTrackRect;
  LocalX := Point.X - Bounds.Left;
  if LocalX < Track.Left then
    LocalX := Track.Left
  else if LocalX > Track.Right then
    LocalX := Track.Right;

  Result := Round((LocalX - Track.Left) / Max(1, Track.Width) * 100);
  Result := Max(0, Min(100, Result));
end;

function TVideoMinerOverlaySeekBar.MouseDown(const Point: TPoint): Boolean;
var
  NewVolume: Integer;
begin
  Result := BoundsHitTest(Point);
  if not Result then
    Exit;

  if FullScreenButtonHitTest(Point) then
  begin
    FFullScreenButtonPressed := True;
    FFullScreenButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if EndActionButtonHitTest(Point) then
  begin
    FEndActionButtonPressed := True;
    FEndActionButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if MuteButtonHitTest(Point) then
  begin
    FMuteButtonPressed := True;
    FMuteButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if VolumeHitTest(Point) then
  begin
    FVolumeDragging := True;
    FVolumeHovered := True;
    FHovered := True;
    NewVolume := VolumeFromPoint(Point);
    if NewVolume <> FVolumePercent then
    begin
      FVolumePercent := NewVolume;
      if Assigned(FOnVolumeChange) then
        FOnVolumeChange(Self, FVolumePercent);
    end;
    Exit;
  end;

  FDragging := True;
  FHovered := True;
  FDragPositionMs := PositionFromPoint(Point);
end;

function TVideoMinerOverlaySeekBar.MouseMove(const Point: TPoint): Boolean;
var
  NewEndActionButtonHovered: Boolean;
  NewFullScreenButtonHovered: Boolean;
  NewHovered: Boolean;
  NewMuteButtonHovered: Boolean;
  NewPositionMs: Integer;
  NewVolume: Integer;
  NewVolumeHovered: Boolean;
begin
  NewHovered := FDragging or FVolumeDragging or BoundsHitTest(Point);
  Result := NewHovered <> FHovered;
  FHovered := NewHovered;

  NewEndActionButtonHovered := EndActionButtonHitTest(Point);
  if NewEndActionButtonHovered <> FEndActionButtonHovered then
  begin
    FEndActionButtonHovered := NewEndActionButtonHovered;
    Result := True;
  end;

  NewVolumeHovered := VolumeHitTest(Point);
  if NewVolumeHovered <> FVolumeHovered then
  begin
    FVolumeHovered := NewVolumeHovered;
    Result := True;
  end;

  NewFullScreenButtonHovered := FullScreenButtonHitTest(Point);
  if NewFullScreenButtonHovered <> FFullScreenButtonHovered then
  begin
    FFullScreenButtonHovered := NewFullScreenButtonHovered;
    Result := True;
  end;

  NewMuteButtonHovered := MuteButtonHitTest(Point);
  if NewMuteButtonHovered <> FMuteButtonHovered then
  begin
    FMuteButtonHovered := NewMuteButtonHovered;
    Result := True;
  end;

  if FDragging then
  begin
    NewPositionMs := PositionFromPoint(Point);
    if NewPositionMs <> FDragPositionMs then
    begin
      FDragPositionMs := NewPositionMs;
      Result := True;
    end;
  end;

  if FVolumeDragging then
  begin
    NewVolume := VolumeFromPoint(Point);
    if NewVolume <> FVolumePercent then
    begin
      FVolumePercent := NewVolume;
      if Assigned(FOnVolumeChange) then
        FOnVolumeChange(Self, FVolumePercent);
      Result := True;
    end;
  end;
end;

function TVideoMinerOverlaySeekBar.MouseUp(const Point: TPoint): Boolean;
var
  EndActionButtonClicked: Boolean;
  FullScreenButtonClicked: Boolean;
  MuteButtonClicked: Boolean;
  SeekPositionMs: Integer;
begin
  Result := FDragging or FVolumeDragging or BoundsHitTest(Point);

  if FFullScreenButtonPressed then
  begin
    FullScreenButtonClicked := FullScreenButtonHitTest(Point);
    FFullScreenButtonPressed := False;
    FFullScreenButtonHovered := FullScreenButtonClicked;
    Result := True;
    if FullScreenButtonClicked and Assigned(FOnFullScreenClick) then
      FOnFullScreenClick(Self);
    Exit;
  end;

  if FMuteButtonPressed then
  begin
    MuteButtonClicked := MuteButtonHitTest(Point);
    FMuteButtonPressed := False;
    FMuteButtonHovered := MuteButtonClicked;
    Result := True;
    if MuteButtonClicked and Assigned(FOnMuteClick) then
      FOnMuteClick(Self);
    Exit;
  end;

  if FEndActionButtonPressed then
  begin
    EndActionButtonClicked := EndActionButtonHitTest(Point);
    FEndActionButtonPressed := False;
    FEndActionButtonHovered := EndActionButtonClicked;
    Result := True;
    if EndActionButtonClicked and Assigned(FOnEndActionClick) then
      FOnEndActionClick(Self);
    Exit;
  end;

  if FVolumeDragging then
  begin
    FVolumePercent := VolumeFromPoint(Point);
    FVolumeDragging := False;
    FVolumeHovered := VolumeHitTest(Point);
    FHovered := BoundsHitTest(Point);
    if Assigned(FOnVolumeChange) then
      FOnVolumeChange(Self, FVolumePercent);
    Exit;
  end;

  if not FDragging then
    Exit;

  SeekPositionMs := PositionFromPoint(Point);
  FDragPositionMs := SeekPositionMs;
  FDragging := False;
  FPositionMs := SeekPositionMs;
  FHovered := BoundsHitTest(Point);
  if Assigned(FOnSeek) then
    FOnSeek(Self, SeekPositionMs);
end;

procedure TVideoMinerOverlaySeekBar.PaintControl(Canvas: TCanvas);
var
  ButtonRect: TRect;
  EndActionRect: TRect;
  FilledRect: TRect;
  KnobCenterX: Integer;
  KnobRadius: Integer;
  PositionRatio: Double;
  ShadowRadius: Integer;
  MuteRect: TRect;
  Text: string;
  TextSize: TSize;
  Track: TRect;
  TrackCenterY: Integer;
  VolumeFilledRect: TRect;
  VolumeLabel: TRect;
  VolumeText: string;
  VolumeTrack: TRect;
begin
  if Bounds.IsEmpty then
    Exit;

  Track := TrackRect;
  if Track.IsEmpty then
    Exit;

  DrawAlphaPanel(Canvas, Rect(0, 0, Bounds.Width, Bounds.Height), 18, 96);
  ButtonRect := FullScreenButtonRect;
  EndActionRect := EndActionButtonRect;
  MuteRect := MuteButtonRect;

  if FMaxMs > 0 then
    PositionRatio := DisplayPositionMs / FMaxMs
  else
    PositionRatio := 0;
  PositionRatio := Max(0.0, Min(1.0, PositionRatio));
  KnobCenterX := Track.Left + Round(Track.Width * PositionRatio);
  TrackCenterY := Track.Top + Track.Height div 2;

  DrawAlphaRoundRect(Canvas, Track, Track.Height, 85);

  FilledRect := Track;
  FilledRect.Right := Max(FilledRect.Left + Track.Height, KnobCenterX);
  DrawAlphaRoundRect(Canvas, FilledRect, Track.Height, 230);

  ShadowRadius := 22;
  DrawAlphaEllipse(Canvas, Rect(KnobCenterX - ShadowRadius,
    TrackCenterY - ShadowRadius, KnobCenterX + ShadowRadius,
    TrackCenterY + ShadowRadius), 70);

  KnobRadius := 11;
  if FHovered or FDragging then
    KnobRadius := 12;
  DrawAlphaEllipse(Canvas, Rect(KnobCenterX - KnobRadius,
    TrackCenterY - KnobRadius, KnobCenterX + KnobRadius,
    TrackCenterY + KnobRadius), 245);

  Text := Format('%s / %s', [FormatTimeMs(DisplayPositionMs),
    FormatTimeMs(FMaxMs)]);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 10;
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  TextSize := Canvas.TextExtent(Text);
  Canvas.TextOut(Bounds.Left + (Track.Left + Track.Right - TextSize.cx) div 2,
    Bounds.Top + Bounds.Height - 29, Text);

  VolumeTrack := VolumeTrackRect;
  VolumeLabel := VolumeLabelRect;
  VolumeText := Format('Vol %d%%', [FVolumePercent]);
  TextSize := Canvas.TextExtent(VolumeText);
  Canvas.TextOut(Bounds.Left + VolumeLabel.Left,
    Bounds.Top + VolumeLabel.Top + (VolumeLabel.Height - TextSize.cy) div 2,
    VolumeText);
  DrawAlphaRoundRect(Canvas, VolumeTrack, VolumeTrack.Height, 72);
  VolumeFilledRect := VolumeTrack;
  VolumeFilledRect.Right := VolumeTrack.Left +
    Round(VolumeTrack.Width * Max(0, Min(100, FVolumePercent)) / 100);
  if VolumeFilledRect.Right > VolumeFilledRect.Left then
    DrawAlphaRoundRect(Canvas, VolumeFilledRect, VolumeTrack.Height, 210);

  if FMuteButtonHovered or FMuteButtonPressed or FMuted then
    DrawAlphaRoundRect(Canvas, MuteRect, 8, 38);
  DrawMuteIcon(Canvas, MuteRect, MuteButtonAlpha);

  if FFullScreenButtonHovered or FFullScreenButtonPressed then
    DrawAlphaRoundRect(Canvas, ButtonRect, 8, 38);
  DrawFullScreenIcon(Canvas, ButtonRect, FullScreenButtonAlpha);

  if FEndActionButtonHovered or FEndActionButtonPressed then
    DrawAlphaRoundRect(Canvas, EndActionRect, 8, 38);
  Text := FEndActionText;
  if Text = '' then
    Text := 'Stop';
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  TextSize := Canvas.TextExtent(Text);
  Canvas.TextOut(Bounds.Left + EndActionRect.Left +
    (EndActionRect.Width - TextSize.cx) div 2,
    Bounds.Top + EndActionRect.Top + (EndActionRect.Height - TextSize.cy) div 2,
    Text);
end;

function TVideoMinerOverlaySeekBar.PositionFromPoint(const Point: TPoint): Integer;
var
  LocalX: Integer;
  Track: TRect;
begin
  Result := 0;
  Track := TrackRect;
  if (FMaxMs <= 0) or Track.IsEmpty then
    Exit;

  LocalX := Point.X - Bounds.Left;
  if LocalX < Track.Left then
    LocalX := Track.Left
  else if LocalX > Track.Right then
    LocalX := Track.Right;

  Result := Round((LocalX - Track.Left) / Max(1, Track.Width) * FMaxMs);
  Result := Max(0, Min(FMaxMs, Result));
end;

procedure TVideoMinerOverlaySeekBar.SetProgress(PositionMs, MaxMs: Integer);
begin
  FMaxMs := Max(0, MaxMs);
  FPositionMs := Max(0, Min(FMaxMs, PositionMs));
  if not FDragging then
    FDragPositionMs := FPositionMs;
end;

procedure TVideoMinerOverlaySeekBar.SetFullScreen(Value: Boolean);
begin
  FFullScreen := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetMuted(Value: Boolean);
begin
  FMuted := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetEndActionText(const Value: string);
begin
  FEndActionText := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetVolumePercent(Value: Integer);
begin
  FVolumePercent := Max(0, Min(100, Value));
end;

function TVideoMinerOverlaySeekBar.TrackRect: TRect;
var
  PadX: Integer;
  TrackHeight: Integer;
  TrackY: Integer;
begin
  Result := TRect.Empty;
  if Bounds.IsEmpty then
    Exit;

  PadX := 22;
  TrackHeight := 7;
  if FHovered or FDragging then
    TrackHeight := 8;
  TrackY := 17;
  Result := Rect(PadX, TrackY, Bounds.Width - PadX, TrackY + TrackHeight);
end;

end.
