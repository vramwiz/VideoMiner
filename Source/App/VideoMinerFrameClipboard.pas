unit VideoMinerFrameClipboard;

// 現在表示中の動画フレームを PNG/DIB/BITMAP としてクリップボードへコピーする。
// 画面キャプチャではなく、デコード済みの動画解像度 Bitmap をそのまま使う。

interface

uses
  Vcl.Graphics;

// 32bit 動画フレームをクリップボードへコピーする
// PreserveAlpha : True なら BGRA の alpha を PNG に保持し、False なら不透明 PNG として扱う
function CopyVideoFrameBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap; PreserveAlpha: Boolean;
  out ErrorMessage: string): Boolean;

implementation

uses
  Winapi.Windows, System.Classes, System.SysUtils, Vcl.Imaging.pngimage;

const
  CLIPBOARD_OPEN_RETRY_COUNT = 10; // 他アプリ使用中のクリップボードを開き直す回数
  CLIPBOARD_OPEN_RETRY_MS    = 50; // クリップボード再試行までの待機 ms
  CF_PNG_NAME                = 'PNG'; // PNG バイト列を入れる独自クリップボード形式名

type
  TRgbQuadArray = array[0..High(Integer) div SizeOf(RGBQUAD) - 1] of RGBQUAD;
  PRgbQuadArray = ^TRgbQuadArray;
  TRgbTripleArray = array[0..High(Integer) div SizeOf(RGBTRIPLE) - 1] of RGBTRIPLE;
  PRgbTripleArray = ^TRgbTripleArray;

// クリップボードが一時的に使われている場合に短時間だけ再試行する
function SafeOpenClipboard(WindowHandle: HWND; out ErrorMessage: string): Boolean;
var
  I: Integer;
begin
  ErrorMessage := '';
  for I := 1 to CLIPBOARD_OPEN_RETRY_COUNT do
  begin
    if OpenClipboard(WindowHandle) then
      Exit(True);
    Sleep(CLIPBOARD_OPEN_RETRY_MS);
  end;
  ErrorMessage := 'Clipboard is busy.';
  Result := False;
end;

// クリップボードへ渡す movable memory に Stream 内容を複製する
function BuildClipboardMemory(Stream: TStream; out Handle: HGLOBAL;
  out ErrorMessage: string): Boolean;
var
  Data: Pointer;
  Size: NativeInt;
begin
  Handle := 0;
  ErrorMessage := '';
  Result := False;

  if Stream = nil then
  begin
    ErrorMessage := 'PNG stream is nil.';
    Exit;
  end;

  Size := Stream.Size;
  if Size <= 0 then
  begin
    ErrorMessage := 'PNG stream is empty.';
    Exit;
  end;

  Handle := GlobalAlloc(GMEM_MOVEABLE, Size);
  if Handle = 0 then
  begin
    ErrorMessage := 'Failed to allocate clipboard memory.';
    Exit;
  end;

  Data := GlobalLock(Handle);
  if Data = nil then
  begin
    GlobalFree(Handle);
    Handle := 0;
    ErrorMessage := 'Failed to lock clipboard memory.';
    Exit;
  end;

  try
    Stream.Position := 0;
    Stream.ReadBuffer(Data^, Size);
  finally
    GlobalUnlock(Handle);
  end;

  Result := True;
end;

// Bitmap の BGRA を TPngImage の RGB + alpha channel へ明示的に詰める
function BuildPngFromBitmap(ABitmap: Vcl.Graphics.TBitmap; PreserveAlpha: Boolean;
  out Png: TPngImage; out ErrorMessage: string): Boolean;
var
  AlphaValue: Byte;
  BitmapPixel: RGBQUAD;
  DstLine: PRgbTripleArray;
  SrcLine: PRgbQuadArray;
  X: Integer;
  Y: Integer;
begin
  Png := nil;
  ErrorMessage := '';
  Result := False;

  if (ABitmap = nil) or (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
  begin
    ErrorMessage := 'Frame bitmap is empty.';
    Exit;
  end;

  if ABitmap.PixelFormat <> pf32bit then
  begin
    ErrorMessage := 'Frame bitmap is not 32bit.';
    Exit;
  end;

  Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, ABitmap.Width, ABitmap.Height);
  try
    for Y := 0 to ABitmap.Height - 1 do
    begin
      SrcLine := ABitmap.ScanLine[Y];
      DstLine := Png.ScanLine[Y];
      for X := 0 to ABitmap.Width - 1 do
      begin
        BitmapPixel := SrcLine[X];
        DstLine[X].rgbtBlue := BitmapPixel.rgbBlue;
        DstLine[X].rgbtGreen := BitmapPixel.rgbGreen;
        DstLine[X].rgbtRed := BitmapPixel.rgbRed;
        if PreserveAlpha then
          AlphaValue := BitmapPixel.rgbReserved
        else
          AlphaValue := 255;
        Png.AlphaScanline[Y]^[X] := AlphaValue;
      end;
    end;
  except
    Png.Free;
    Png := nil;
    raise;
  end;

  Result := True;
end;

// PNG 形式のクリップボード用メモリを作る
function BuildClipboardPng(Png: TPngImage; out Handle: HGLOBAL;
  out ErrorMessage: string): Boolean;
var
  Stream: TMemoryStream;
begin
  Handle := 0;
  ErrorMessage := '';
  Result := False;

  if Png = nil then
  begin
    ErrorMessage := 'PNG image is nil.';
    Exit;
  end;

  Stream := TMemoryStream.Create;
  try
    Png.SaveToStream(Stream);
    Result := BuildClipboardMemory(Stream, Handle, ErrorMessage);
  finally
    Stream.Free;
  end;
end;

// PNG を受け取れないアプリ向けに 24bit DIB fallback を作る
function BuildClipboardDib(ABitmap: Vcl.Graphics.TBitmap; out Handle: HGLOBAL;
  out ErrorMessage: string): Boolean;
var
  Bits: PByte;
  BitmapInfo: TBitmapInfoHeader;
  Dib: PByte;
  RowSize: Integer;
  Size: Integer;
  Src: PByte;
  X: Integer;
  Y: Integer;
begin
  Handle := 0;
  ErrorMessage := '';
  Result := False;

  if (ABitmap = nil) or (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
  begin
    ErrorMessage := 'Frame bitmap is empty.';
    Exit;
  end;

  RowSize := ((ABitmap.Width * 3 + 3) div 4) * 4;
  Size := SizeOf(TBitmapInfoHeader) + RowSize * ABitmap.Height;
  Handle := GlobalAlloc(GMEM_MOVEABLE, Size);
  if Handle = 0 then
  begin
    ErrorMessage := 'Failed to allocate DIB memory.';
    Exit;
  end;

  Dib := GlobalLock(Handle);
  if Dib = nil then
  begin
    GlobalFree(Handle);
    Handle := 0;
    ErrorMessage := 'Failed to lock DIB memory.';
    Exit;
  end;

  try
    FillChar(BitmapInfo, SizeOf(BitmapInfo), 0);
    BitmapInfo.biSize := SizeOf(BitmapInfo);
    BitmapInfo.biWidth := ABitmap.Width;
    BitmapInfo.biHeight := -ABitmap.Height;
    BitmapInfo.biPlanes := 1;
    BitmapInfo.biBitCount := 24;
    BitmapInfo.biCompression := BI_RGB;
    BitmapInfo.biSizeImage := RowSize * ABitmap.Height;

    Move(BitmapInfo, Dib^, SizeOf(BitmapInfo));
    Bits := Dib + SizeOf(BitmapInfo);
    for Y := 0 to ABitmap.Height - 1 do
    begin
      Src := ABitmap.ScanLine[Y];
      for X := 0 to ABitmap.Width - 1 do
      begin
        Bits^ := Src^;
        Inc(Bits);
        Inc(Src);
        Bits^ := Src^;
        Inc(Bits);
        Inc(Src);
        Bits^ := Src^;
        Inc(Bits);
        Inc(Src, 2);
      end;
      Inc(Bits, RowSize - ABitmap.Width * 3);
    end;
  finally
    GlobalUnlock(Handle);
  end;

  Result := True;
end;

// クリップボードへ渡す HBITMAP fallback を複製する
function BuildClipboardBitmap(ABitmap: Vcl.Graphics.TBitmap; out Handle: HBITMAP;
  out ErrorMessage: string): Boolean;
begin
  Handle := 0;
  ErrorMessage := '';
  Result := False;

  if (ABitmap = nil) or (ABitmap.Handle = 0) then
  begin
    ErrorMessage := 'Frame bitmap is empty.';
    Exit;
  end;

  Handle := CopyImage(ABitmap.Handle, IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION);
  if Handle = 0 then
  begin
    ErrorMessage := 'Failed to copy bitmap handle.';
    Exit;
  end;

  Result := True;
end;

// 作成済みハンドルをクリップボードへ登録する
function SetFrameClipboardData(PngHandle, DibHandle: HGLOBAL; BitmapHandle: HBITMAP;
  out ErrorMessage: string): Boolean;
var
  ClipboardPngFormat: UINT;
  DibAccepted: Boolean;
  BitmapAccepted: Boolean;
  PngAccepted: Boolean;
begin
  ErrorMessage := '';
  Result := False;

  ClipboardPngFormat := RegisterClipboardFormat(CF_PNG_NAME);
  if ClipboardPngFormat = 0 then
  begin
    ErrorMessage := 'Failed to register PNG clipboard format.';
    Exit;
  end;

  if not SafeOpenClipboard(0, ErrorMessage) then
    Exit;

  PngAccepted := False;
  DibAccepted := False;
  BitmapAccepted := False;
  try
    if not EmptyClipboard then
    begin
      ErrorMessage := 'Failed to clear clipboard.';
      Exit;
    end;

    if PngHandle <> 0 then
      PngAccepted := SetClipboardData(ClipboardPngFormat, PngHandle) <> 0;
    if DibHandle <> 0 then
      DibAccepted := SetClipboardData(CF_DIB, DibHandle) <> 0;
    if BitmapHandle <> 0 then
      BitmapAccepted := SetClipboardData(CF_BITMAP, BitmapHandle) <> 0;

    Result := PngAccepted or DibAccepted or BitmapAccepted;
    if not Result then
      ErrorMessage := 'Failed to set clipboard data.';
  finally
    CloseClipboard;
    if (not PngAccepted) and (PngHandle <> 0) then
      GlobalFree(PngHandle);
    if (not DibAccepted) and (DibHandle <> 0) then
      GlobalFree(DibHandle);
    if (not BitmapAccepted) and (BitmapHandle <> 0) then
      DeleteObject(BitmapHandle);
  end;
end;

function CopyVideoFrameBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap; PreserveAlpha: Boolean;
  out ErrorMessage: string): Boolean;
var
  BitmapHandle: HBITMAP;
  DibHandle: HGLOBAL;
  Png: TPngImage;
  PngHandle: HGLOBAL;
begin
  ErrorMessage := '';
  Result := False;
  BitmapHandle := 0;
  DibHandle := 0;
  PngHandle := 0;
  Png := nil;

  try
    if not BuildPngFromBitmap(ABitmap, PreserveAlpha, Png, ErrorMessage) then
      Exit;
    if not BuildClipboardPng(Png, PngHandle, ErrorMessage) then
      Exit;
    if not BuildClipboardDib(ABitmap, DibHandle, ErrorMessage) then
      Exit;
    if not BuildClipboardBitmap(ABitmap, BitmapHandle, ErrorMessage) then
      Exit;

    Result := SetFrameClipboardData(PngHandle, DibHandle, BitmapHandle, ErrorMessage);
    if Result then
    begin
      PngHandle := 0;
      DibHandle := 0;
      BitmapHandle := 0;
    end;
  finally
    Png.Free;
    if PngHandle <> 0 then
      GlobalFree(PngHandle);
    if DibHandle <> 0 then
      GlobalFree(DibHandle);
    if BitmapHandle <> 0 then
      DeleteObject(BitmapHandle);
  end;
end;

end.
