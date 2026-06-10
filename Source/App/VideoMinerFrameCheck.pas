unit VideoMinerFrameCheck;

interface

uses
  System.Math, Vcl.Graphics;

function FrameCornersMostlyDark(Bitmap: TBitmap): Boolean;

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
