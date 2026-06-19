unit VideoMinerFrameCheck;

// チェック機能で使うフレームの軽量判定を担当する。
// UI やチャプター管理へは依存せず、表示済み Bitmap から黒画面候補や
// フレーム差分用の小さな署名だけを取り出す。

interface

uses
  System.Math, Vcl.Graphics;

const
  FRAME_CHECK_DIFF_CELL_COUNT = 64;

type
  TVideoMinerFrameSignature = record
    Values: array[0..FRAME_CHECK_DIFF_CELL_COUNT - 1] of Byte; // 画面を粗く区切った各セルの明るさ
  end;

// 四隅がすべて暗いフレームを黒画面候補として判定する
function FrameCornersMostlyDark(Bitmap: TBitmap): Boolean;
// フレーム差分検出用に、画面全体を 8x8 の明るさ署名へ圧縮する
function BuildFrameSignature(Bitmap: TBitmap;
  out Signature: TVideoMinerFrameSignature): Boolean;
// 2 つのフレーム署名の平均輝度差を返す
function FrameSignatureDifference(const A, B: TVideoMinerFrameSignature): Integer;

implementation

type
  TBgraQuad = packed record
    B: Byte; // Bitmap の青成分
    G: Byte; // Bitmap の緑成分
    R: Byte; // Bitmap の赤成分
    A: Byte; // pf32bit の未使用アルファ相当成分
  end;
  TBgraQuadArray = array[0..MaxInt div SizeOf(TBgraQuad) - 1] of TBgraQuad;
  PBgraQuadArray = ^TBgraQuadArray;

const
  FRAME_CHECK_DARK_CORNER_SIZE = 8;
  FRAME_CHECK_DARK_CORNER_THRESHOLD = 18;
  FRAME_CHECK_DIFF_GRID_SIZE = 8;

// フレーム差分検出用に、表示 Bitmap を固定数セルの明るさへ縮約する
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

// セル単位の明るさ差を平均化し、単発ノイズ候補の判定値として使う
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

// 指定された隅の小領域が暗さしきい値以下かを調べる
function FrameCornerIsDark(Bitmap: TBitmap; Left, Top, CornerWidth,
  CornerHeight: Integer): Boolean;
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

// 四隅だけをサンプリングして、黒画面に近いフレームかを軽く判定する
function FrameCornersMostlyDark(Bitmap: TBitmap): Boolean;
var
  CornerHeight: Integer;
  CornerWidth: Integer;
begin
  Result := False;
  if (Bitmap = nil) or (Bitmap.PixelFormat <> pf32bit) or
     (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;

  CornerWidth := Min(FRAME_CHECK_DARK_CORNER_SIZE, Bitmap.Width);
  CornerHeight := Min(FRAME_CHECK_DARK_CORNER_SIZE, Bitmap.Height);
  Result := FrameCornerIsDark(Bitmap, 0, 0, CornerWidth, CornerHeight) and
    FrameCornerIsDark(Bitmap, Bitmap.Width - CornerWidth, 0, CornerWidth,
      CornerHeight) and
    FrameCornerIsDark(Bitmap, 0, Bitmap.Height - CornerHeight, CornerWidth,
      CornerHeight) and
    FrameCornerIsDark(Bitmap, Bitmap.Width - CornerWidth,
      Bitmap.Height - CornerHeight, CornerWidth, CornerHeight);
end;

end.
