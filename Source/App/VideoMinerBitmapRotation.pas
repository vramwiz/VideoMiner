unit VideoMinerBitmapRotation;

// Applies display rotation metadata to decoded 32bit bitmaps.
// FFmpeg decode buffers keep the coded frame size; UI bitmaps are rotated after decode.

interface

uses
  Vcl.Graphics;

// Rotates Bitmap counterclockwise by 0, 90, 180, or 270 degrees.
procedure RotateBitmapByDegrees(Bitmap: TBitmap; Degrees: Integer);

implementation

type
  PCardinalLine = ^TCardinalLine;
  TCardinalLine = array[0..MaxInt div SizeOf(Cardinal) - 1] of Cardinal;
  TCardinalLineArray = array of PCardinalLine;

// Bitmapの各scanlineを先に取得し、回転中のScanLine呼び出しを避ける。
procedure BuildScanLineTable(Bitmap: TBitmap; var Rows: TCardinalLineArray);
var
  Y: Integer; // 取得中の行番号
begin
  SetLength(Rows, Bitmap.Height);
  for Y := 0 to Bitmap.Height - 1 do
    Rows[Y] := Bitmap.ScanLine[Y];
end;

// Copies pixels through scanlines so alpha bytes are preserved.
procedure RotateBitmapByDegrees(Bitmap: TBitmap; Degrees: Integer);
var
  Dst        : TBitmap;       // Rotated bitmap
  DstRows    : TCardinalLineArray; // Rotated bitmap scanlines
  DstLine    : PCardinalLine; // Row in the rotated bitmap
  Normalized : Integer;       // Degrees normalized to 0..359
  SrcRows    : TCardinalLineArray; // Source bitmap scanlines
  SrcLine    : PCardinalLine; // Row in the source bitmap
  SrcX       : Integer;       // Source X coordinate
  X          : Integer;       // Destination X coordinate
  Y          : Integer;       // Destination Y coordinate
begin
  if (Bitmap = nil) or (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;

  Normalized := Degrees mod 360;
  if Normalized < 0 then
    Inc(Normalized, 360);
  if Normalized = 0 then
    Exit;
  if (Normalized <> 90) and (Normalized <> 180) and (Normalized <> 270) then
    Exit;

  if Bitmap.PixelFormat <> pf32bit then
    Bitmap.PixelFormat := pf32bit;

  Dst := TBitmap.Create;
  try
    Dst.PixelFormat := pf32bit;
    if Normalized = 180 then
      Dst.SetSize(Bitmap.Width, Bitmap.Height)
    else
      Dst.SetSize(Bitmap.Height, Bitmap.Width);

    BuildScanLineTable(Bitmap, SrcRows);
    BuildScanLineTable(Dst, DstRows);

    case Normalized of
      90:
        for Y := 0 to Dst.Height - 1 do
        begin
          DstLine := DstRows[Y];
          SrcX := Bitmap.Width - 1 - Y;
          for X := 0 to Dst.Width - 1 do
            DstLine[X] := SrcRows[X][SrcX];
        end;
      180:
        for Y := 0 to Dst.Height - 1 do
        begin
          DstLine := DstRows[Y];
          SrcLine := SrcRows[Bitmap.Height - 1 - Y];
          for X := 0 to Dst.Width - 1 do
            DstLine[X] := SrcLine[Bitmap.Width - 1 - X];
        end;
    else
      for Y := 0 to Dst.Height - 1 do
      begin
        DstLine := DstRows[Y];
        SrcX := Y;
        for X := 0 to Dst.Width - 1 do
          DstLine[X] := SrcRows[Bitmap.Height - 1 - X][SrcX];
      end;
    end;

    Bitmap.Assign(Dst);
  finally
    Dst.Free;
  end;
end;

end.
