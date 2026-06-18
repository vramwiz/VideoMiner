unit BitmapEx;

// ファイルを読み込んでビットマップで返す
// PNG GIFの透過を処理
interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls,Vcl.ComCtrls,PNGImage,Jpeg;

type  TFourth = packed record
    B,G,R,A : Byte;
  end;
TFourthArray = array[0..40000000] of TFourth;
PFourthArray = ^TFourthArray;

type TBitmapExStretch = (bsNormal,        // 標準
                         bsLockHeight,    // 高さ固定
                         bsLockWidth      // 幅固定
                         );

type TBitmapExFileExt = ( bfNil,
                          bfBmp,
                          bfGif,
                          bfJpg,
                          bfPng
                          );

type
  TBitmapEx = class(TBitmap)
  private
    { Private 宣言 }
    FBackgroundColor: TColor;
    FTransparentColor: TColor;
    FTransparencyMode: TPNGTransparencyMode;
    FTransparent: Boolean;

    // 拡張子から画像形式を判断
    function CheckFileExt(const FileName : string) : TBitmapExFileExt;

    // GIF ファイル読み込み
    procedure LoadFromFileGif(const Filename: string);
    // Jpeg ファイル読み込み
    procedure LoadFromFileJpg(const Filename: string);
    // PNG ファイル読み込み
    procedure LoadFromFilePng(const Filename: string);

    // GIF ファイル書き込み
    procedure SaveToFileGif(const Filename: string);
    // Jpeg ファイル書き込み
    procedure SaveToFileJpg(const Filename: string);
    // PNG ファイル書き込み
    procedure SaveToFilePng(const Filename: string);


  public
    { Public 宣言 }
    constructor Create();override;
    procedure Clear();

    procedure AssignJpeg(jpeg : TJPEGImage);
    procedure AssignTransparent(Source : TBitmapEx);
    // ファイルを読み込み
    procedure LoadFromFile(const Filename: string); override;
    // ファイルを読み込み
    procedure SaveToFile(const Filename: string); override;
    // 指定されたビットマップをアスペクト比を維持して指定されたサイズ以内で描画
    procedure StretchDraw(const aWidth,aHeight : Integer;bmp : TBitmap);
    // 指定されたビットマップをアスペクト比を維持して指定されたサイズで中央に描画
    procedure CenterDraw(const aWidth,aHeight : Integer;bmp : TBitmap);

    // 反転して描画 0:反転無し 1: 左右反転、2:上下反転 3:上下左右反転
    procedure DrawInvert(bmp : TBitmap;Mode : Integer=0);

    // 背景色に使用する色
    property BackgroundColor : TColor read FBackgroundColor write FBackgroundColor;

    property Transparent : Boolean read FTransparent write FTransparent;
    property TransparentColor : TColor read FTransparentColor write FTransparentColor;
    property TransparencyMode : TPNGTransparencyMode read FTransparencyMode write FTransparencyMode;
  end;


implementation

uses GIFImg;

{ TBitmapEx }

constructor TBitmapEx.Create;
begin
  inherited;
  FBackgroundColor := clWhite;
end;

procedure TBitmapEx.DrawInvert(bmp: TBitmap; Mode: Integer=0);
  function GetX(const x,xh,mode : Integer) : Integer;
  begin
    result := x;
    if (mode = 1) or (mode = 3) then result := xh - x - 1;
  end;
  function GetY(const y,yh,mode : Integer) : Integer;
  begin
    result := y;
    if (mode = 2) or (mode = 3) then result := yh - y - 1;
  end;
var
  x1,y1,x2,y2 : Integer;
  slFrom,slTo : array of Pointer;
begin
  SetSize(bmp.Width,bmp.Height);
  SetLength(slFrom,Height);
  SetLength(slTo,Height);
  for y1 := 0 to Height-1 do begin
    slFrom[y1] := bmp.ScanLine[y1];
    slTo[y1]   := ScanLine[y1];
  end;
  for y1 := 0 to Height-1 do begin                // 高さ分ループ
    for x1 := 0 to Width-1 do begin               // 横幅分ループ
      x2 := GetX(x1,Width,Mode);
      y2 := GetY(y1,Height,Mode);
      PFourthArray(slTo[y2])^[x2].R := PFourthArray(slFrom[y1])^[x1].R;
      PFourthArray(slTo[y2])^[x2].G := PFourthArray(slFrom[y1])^[x1].G;
      PFourthArray(slTo[y2])^[x2].B := PFourthArray(slFrom[y1])^[x1].B;
      PFourthArray(slTo[y2])^[x2].A := PFourthArray(slFrom[y1])^[x1].A;
    end;
  end;
end;

procedure TBitmapEx.Clear;
var
  x,y : Integer;
  Lines : array of Pointer;
begin
  SetLength(Lines,Height);
  for y := 0 to Height-1 do begin
    Lines[y] := ScanLine[y];
  end;
  for y := 0 to Height-1 do begin                // 高さ分ループ
    for x := 0 to Width-1 do begin               // 横幅分ループ

      PFourthArray(Lines[y])^[x].R := 0; // 描画先RGB画素データを取得
      PFourthArray(Lines[y])^[x].G := 0;
      PFourthArray(Lines[y])^[x].B := 0;
      PFourthArray(Lines[y])^[x].A := 0;  // αチャンネルは手動処理のためないものとする
    end;
  end;
  AlphaFormat := afDefined;
{
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackgroundColor;
  Canvas.FillRect(Canvas.ClipRect);
  }
end;

procedure TBitmapEx.LoadFromFile(const Filename: string);
begin
  if not FileExists(Filename) then exit;
  case CheckFileExt(Filename) of
    bfBmp : inherited LoadFromFile(Filename);
    bfGif : LoadFromFileGif(Filename);
    bfJpg : LoadFromFileJpg(Filename);
    bfPng : LoadFromFilePng(Filename);
  end;
end;

procedure TBitmapEx.LoadFromFileGif(const Filename: string);
var
  gif : TGIFImage;
begin
  gif := TGIFImage.Create;
  try
    gif.LoadFromFile(Filename);
    Assign(gif);
  finally
    gif.Free;
  end;
end;

procedure TBitmapEx.LoadFromFileJpg(const Filename: string);
var
  jpg : TJPEGImage;
begin
  jpg := TJPEGImage.Create;
  try
    jpg.LoadFromFile(Filename);
    Assign(jpg);
  finally
    jpg.Free;
  end;
end;

procedure TBitmapEx.LoadFromFilePng(const Filename: string);
var
  png : TPngImage;
begin
  png := TPngImage.Create;
  try
    png.LoadFromFile(Filename);
    FTransparentColor := png.TransparentColor;
    FTransparencyMode := png.TransparencyMode;
    FTransparent := png.Transparent;
    Assign(png);
  finally
    png.Free;
  end;
end;


function TBitmapEx.CheckFileExt(const FileName: string): TBitmapExFileExt;
var
  s : string;
begin
  result := bfNil;
  s := ExtractFileExt(FileName);
  if Copy(s,1,1) <> '.' then exit;
  s := Copy(s,2,Length(s));
  if CompareText(s,'bmp')  = 0 then result := bfBmp;
  if CompareText(s,'gif')  = 0 then result := bfGif;
  if CompareText(s,'jpg')  = 0 then result := bfJpg;
  if CompareText(s,'jpeg') = 0 then result := bfJpg;
  if CompareText(s,'png')  = 0 then result := bfPng;

end;


procedure TBitmapEx.SaveToFile(const Filename: string);
begin
  case CheckFileExt(Filename) of
    bfBmp : inherited SaveToFile(Filename);
    bfGif : SaveToFileGif(Filename);
    bfJpg : SaveToFileJpg(Filename);
    bfPng : SaveToFilePng(Filename);
  end;
end;

procedure TBitmapEx.SaveToFileGif(const Filename: string);
var
  gif : TGIFImage;
begin
  gif := TGIFImage.Create;
  try
    gif.Assign(Self);
    gif.SaveToFile(Filename);
  finally
    gif.Free;
  end;
end;

procedure TBitmapEx.SaveToFileJpg(const Filename: string);
var
  jpg : TJPEGImage;
begin
  jpg := TJPEGImage.Create;
  try
    jpg.Assign(Self);
    jpg.SaveToFile(Filename);
  finally
    jpg.Free;
  end;
end;

procedure TBitmapEx.SaveToFilePng(const Filename: string);
type
  TRGBQArray = array [0..High(Integer) div 4 - 1] of RGBQUAD;
  PRGBQArray = ^TRGBQArray;
  TRGBTArray = array [0..High(Integer) div 3 - 1] of RGBTRIPLE;
  PRGBTArray = ^TRGBTArray;
var
  PNG: TPngImage;
  i,ii: Integer;
  BPQ: PRGBQArray;
  CQ: RGBQUAD;
  PPT: PRGBTArray;
  CT: RGBTRIPLE;
begin
  PNG := TPngImage.CreateBlank(COLOR_RGBALPHA,8,Self.Width,Self.Height);
  try
    for i := 0 to Self.Height - 1 do
    begin
      BPQ := Self.ScanLine[i];
      PPT := PNG.ScanLine[i];
      for ii := 0 to Self.Width - 1 do
      begin
        CQ := BPQ[ii];
        CT.rgbtBlue := CQ.rgbBlue;
        CT.rgbtGreen := CQ.rgbGreen;
        CT.rgbtRed := CQ.rgbRed;
        PPT[ii] := CT;
        PNG.AlphaScanline[i]^[ii] := CQ.rgbReserved;
      end;
    end;

    PNG.SaveToFile(Filename);
  finally
    PNG.Free;
  end;
{
var
  png : TPngImage;
begin
  png := TPngImage.Create;
  try
    png.Assign(Self);
    //png.Transparent := FTransparent;
    //png.TransparencyMode := FTransparentMode;
    //if FTransparent then png.TransparentColor := FTransparentColor;
    png.SaveToFile(Filename);
  finally
    png.Free;
  end;
  }
end;

// アスペクトル比を合わせた範囲を取得 r : 変形先としての範囲 aWidth,aHeight:元画像ファイル
procedure RectToStreachRect(var r : TRect;const aWidth,aHeight : Integer);
//var
//  xh,yh : Integer;
begin
  if aWidth = 0 then exit;
  if aHeight = 0 then exit;
  if r.Width > aWidth then begin
    r.Height := r.Height * aWidth div r.Width;
    r.Width := aWidth;
  end;
  if r.Height > aHeight then begin
    r.Width := r.Width * aHeight div r.Height;
    r.Height := aHeight;
  end;

  {
  if aWidth > aHeight then begin
    yh := r.Width * aHeight div aWidth;
    r.Height := yh;
  end
  else begin
    xh := r.Height * aWidth div aHeight;
    r.Width := xh;
  end;
  }
end;

procedure RectToCenterRect(var r : TRect;const aWidth,aHeight : Integer);
var
  xh,yh,xhr,yhr : Integer;
begin
  if aWidth = 0 then exit;
  if aHeight = 0 then exit;

  xhr := r.Width;
  yhr := r.Height;
  if aWidth > aHeight then begin
    yh := r.Width * aHeight div aWidth;
    r.Top := (yhr - yh) div 2;
    r.Height := yh;
  end
  else begin
    xh := r.Height * aWidth div aHeight;
    r.Left := (xhr - xh) div 2;
    r.Width := xh;
  end;
end;

procedure TBitmapEx.StretchDraw(const aWidth, aHeight: Integer; bmp: TBitmap);
var
  r : TRect;
begin
  r := Rect(0,0,bmp.Width,bmp.Height);
  RectToStreachRect(r,aWidth,aHeight);
  SetSize(r.Width,r.Height);
  Clear;
  Canvas.StretchDraw(r,bmp);
end;

procedure TBitmapEx.AssignJpeg(jpeg: TJPEGImage);
var
  bmp :TBitmapEx;
begin
  bmp := TBitmapEx.Create;
  try
    bmp.Assign(jpeg);
    DrawInvert(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TBitmapEx.AssignTransparent(Source: TBitmapEx);
begin
  FTransparent := Source.FTransparent;
  FTransparentColor := Source.FTransparentColor;
  FTransparencyMode := Source.FTransparencyMode;
end;

procedure TBitmapEx.CenterDraw(const aWidth, aHeight: Integer; bmp: TBitmap);
var
  r : TRect;
begin
  r := Rect(0,0,aWidth,aHeight);
  RectToCenterRect(r,bmp.Width,bmp.Height);
  SetSize(aWidth,aHeight);
  Clear;
  Canvas.StretchDraw(r,bmp);
end;




end.
