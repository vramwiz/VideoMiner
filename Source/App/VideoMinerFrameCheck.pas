unit VideoMinerFrameCheck;

interface

uses
  System.Math, Vcl.Graphics;

const
  FRAME_CHECK_DIFF_CELL_COUNT = 64;

type
  TVideoMinerFrameSignature = record
    Values: array[0..FRAME_CHECK_DIFF_CELL_COUNT - 1] of Byte;
  end;

function FrameCornersMostlyDark(Bitmap: TBitmap): Boolean;
function BuildFrameSignature(Bitmap: TBitmap;
  out Signature: TVideoMinerFrameSignature): Boolean;
function FrameSignatureDifference(const A, B: TVideoMinerFrameSignature): Integer;

implementation

type
  TBgraQuad = packed record
    B: Byte;
    G: Byte;
    R: Byte;
    A: Byte;
  end;
  TBgraQuadArray = array[0..MaxInt div SizeOf(TBgraQuad) - 1] of TBgraQuad;
  PBgraQuadArray = ^TBgraQuadArray;

const
  FRAME_CHECK_DARK_CORNER_SIZE = 8;
  FRAME_CHECK_DARK_CORNER_THRESHOLD = 18;
  FRAME_CHECK_DIFF_GRID_SIZE = 8;

function BuildFrameSignature(Bitmap: TBitmap;
  out Signature: TVideoMinerFrameSignature): Boolean;
var
  Cell: Integer;
  Col: Integer;
  Line: PBgraQuadArray;
  Pixel: TBgraQuad;
  Row: Integer;
  X: Integer;
  Y: Integer;
begin
  Result := False;
  FillChar(Signature, SizeOf(Signature), 0);
  if (Bitmap = nil) or (Bitmap.PixelFormat <> pf32bit) or
     (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;

  Cell := 0;
  for Row := 0 to FRAME_CHECK_DIFF_GRID_SIZE - 1 do
  begin
    Y := (Bitmap.Height * (Row * 2 + 1)) div
      (FRAME_CHECK_DIFF_GRID_SIZE * 2);
    Y := Max(0, Min(Bitmap.Height - 1, Y));
    Line := Bitmap.ScanLine[Y];

    for Col := 0 to FRAME_CHECK_DIFF_GRID_SIZE - 1 do
    begin
      X := (Bitmap.Width * (Col * 2 + 1)) div
        (FRAME_CHECK_DIFF_GRID_SIZE * 2);
      X := Max(0, Min(Bitmap.Width - 1, X));
      Pixel := Line[X];
      Signature.Values[Cell] := (Integer(Pixel.R) * 30 +
        Integer(Pixel.G) * 59 + Integer(Pixel.B) * 11) div 100;
      Inc(Cell);
    end;
  end;

  Result := True;
end;

function FrameSignatureDifference(
  const A, B: TVideoMinerFrameSignature): Integer;
var
  I: Integer;
  Total: Integer;
begin
  Total := 0;
  for I := Low(A.Values) to High(A.Values) do
    Inc(Total, Abs(Integer(A.Values[I]) - Integer(B.Values[I])));
  Result := Total div FRAME_CHECK_DIFF_CELL_COUNT;
end;

function FrameCornersMostlyDark(Bitmap: TBitmap): Boolean;
var
  CornerHeight: Integer;
  CornerWidth: Integer;
  function CornerIsDark(Left, Top: Integer): Boolean;
  var
    Line: PBgraQuadArray;
    Pixel: TBgraQuad;
    Total: Int64;
    X: Integer;
    Y: Integer;
  begin
    Total := 0;
    for Y := Top to Top + CornerHeight - 1 do
    begin
      Line := Bitmap.ScanLine[Y];
      for X := Left to Left + CornerWidth - 1 do
      begin
        Pixel := Line[X];
        Total := Total + Pixel.R + Pixel.G + Pixel.B;
      end;
    end;

    Result := Total <= Int64(CornerWidth) * CornerHeight * 3 *
      FRAME_CHECK_DARK_CORNER_THRESHOLD;
  end;
begin
  Result := False;
  if (Bitmap = nil) or (Bitmap.PixelFormat <> pf32bit) or
     (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;

  CornerWidth := Min(FRAME_CHECK_DARK_CORNER_SIZE, Bitmap.Width);
  CornerHeight := Min(FRAME_CHECK_DARK_CORNER_SIZE, Bitmap.Height);
  Result := CornerIsDark(0, 0) and
    CornerIsDark(Bitmap.Width - CornerWidth, 0) and
    CornerIsDark(0, Bitmap.Height - CornerHeight) and
    CornerIsDark(Bitmap.Width - CornerWidth, Bitmap.Height - CornerHeight);
end;

end.
