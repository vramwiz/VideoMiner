unit VideoMinerOverlay;

interface

uses
  System.Classes, System.Math, System.Types, Winapi.Windows, Vcl.Graphics;

type
  TVideoMinerOverlaySkipDirection = (sdBackward, sdForward);

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

end.
