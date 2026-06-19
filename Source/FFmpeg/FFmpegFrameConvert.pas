unit FFmpegFrameConvert;

// FFmpeg の AVFrame を VideoMiner が扱う表示用バッファへコピー/変換する。
// sws context の再利用、Bitmap 変換、BGR/YUV/YC48 形式への出力をここに集約する。

interface

uses
  Vcl.Graphics, FFmpegApi;

// AVFrame を下から上へ並ぶ BGRX32 表示バッファへ変換する。
procedure CopyFrameToBgrx32Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrame を下から上へ並ぶ BGR24 表示バッファへ変換する。
procedure CopyFrameToBgr24Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrame を YUY2 バッファへ変換する。
procedure CopyFrameToYuy2Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrame を I420 planar バッファへ変換する。
procedure CopyFrameToI420Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrame を YC48 バッファへ変換する。
procedure CopyFrameToYc48Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

// AVFrame を一時 sws context で Bitmap へ変換する。
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);

// AVFrame を再利用可能な sws context で Bitmap へ変換する。
procedure CopyFrameToBitmapCached(
  Frame: PAVFrame;
  Bitmap: TBitmap;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);

implementation

uses
  System.SysUtils;

// 変換元フレームと出力バッファが有効か確認する。
procedure EnsureFrameAndBuffer(Frame: PAVFrame; Buffer: Pointer);
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');
  if Buffer = nil then
    raise Exception.Create('Destination buffer is nil.');
end;

// 4 byte 境界に揃えた BGR24 stride を返す。
function Bgr24Stride(Width: Integer): Integer;
begin
  Result := ((Width * 3 + 3) div 4) * 4;
end;

// 4:2:0 の chroma plane サイズに使う半分切り上げ値を返す。
function Chroma420Size(Value: Integer): Integer;
begin
  Result := (Value + 1) div 2;
end;

// 1 plane 分のピクセルデータを stride 差を吸収しながらコピーする。
procedure CopyPlane(Src, Dst: PByte; SrcStride, DstStride, Width, Height: Integer);
var
  Y : Integer; // コピー中の行番号
begin
  if (Src = nil) or (Dst = nil) then
    raise Exception.Create('Frame plane is nil.');

  for Y := 0 to Height - 1 do
  begin
    Move(Src^, Dst^, Width);
    Inc(Src, SrcStride);
    Inc(Dst, DstStride);
  end;
end;

// 8bit Y 成分を YC48 の Y 範囲へ変換する。
function Y8ToYc48Value(Y: Byte): Integer;
begin
  Result := ((Integer(Y) * 1197) div 64) - 299;
  if Result < 0 then
    Result := 0
  else if Result > 4096 then
    Result := 4096;
end;

// 8bit Cb/Cr 成分を YC48 の Cb/Cr 範囲へ変換する。
function C8ToYc48Value(C: Byte): Integer;
begin
  Result := ((Integer(C) - 128) * 4681 + 164) div 256;
  if Result < -2048 then
    Result := -2048
  else if Result > 2048 then
    Result := 2048;
end;

// YUV420 planar の各 plane を YC48 packed バッファへ変換する。
procedure CopyYuv420ToYc48(
  YPlane, UPlane, VPlane: PByte;
  YStride, UStride, VStride: Integer;
  Width, Height: Integer;
  Buffer: Pointer;
  BufferStride: Integer
);
var
  Row       : Integer;   // 出力中の行番号
  Col       : Integer;   // 出力中の列番号
  ChromaRow : Integer;   // 参照する chroma 行番号
  ChromaCol : Integer;   // 参照する chroma 列番号
  YSrc      : PByte;     // 現在行の Y plane 先頭
  USrc      : PByte;     // 現在行に対応する U plane 先頭
  VSrc      : PByte;     // 現在行に対応する V plane 先頭
  Dst       : PSmallInt; // YC48 出力先
  Cb        : Integer;   // YC48 の Cb 値
  Cr        : Integer;   // YC48 の Cr 値
  YValue    : Integer;   // YC48 の Y 値
begin
  if (YPlane = nil) or (UPlane = nil) or (VPlane = nil) then
    raise Exception.Create('Frame plane is nil.');
  if BufferStride <= 0 then
    BufferStride := Width * 6;

  for Row := 0 to Height - 1 do
  begin
    ChromaRow := Row div 2;
    YSrc := PByte(NativeUInt(YPlane) + NativeUInt(Row * YStride));
    USrc := PByte(NativeUInt(UPlane) + NativeUInt(ChromaRow * UStride));
    VSrc := PByte(NativeUInt(VPlane) + NativeUInt(ChromaRow * VStride));
    Dst := PSmallInt(NativeUInt(Buffer) + NativeUInt(Row * BufferStride));

    Col := 0;
    while Col < Width do
    begin
      ChromaCol := Col div 2;
      Cb := C8ToYc48Value(PByte(NativeUInt(USrc) + NativeUInt(ChromaCol))^);
      Cr := C8ToYc48Value(PByte(NativeUInt(VSrc) + NativeUInt(ChromaCol))^);

      YValue := Y8ToYc48Value(PByte(NativeUInt(YSrc) + NativeUInt(Col))^);
      Dst^ := SmallInt(YValue);
      Inc(Dst);
      Dst^ := SmallInt(Cb);
      Inc(Dst);
      Dst^ := SmallInt(Cr);
      Inc(Dst);
      Inc(Col);

      if Col < Width then
      begin
        YValue := Y8ToYc48Value(PByte(NativeUInt(YSrc) + NativeUInt(Col))^);
        Dst^ := SmallInt(YValue);
        Inc(Dst);
        Dst^ := SmallInt(Cb);
        Inc(Dst);
        Dst^ := SmallInt(Cr);
        Inc(Dst);
        Inc(Col);
      end;
    end;
  end;
end;

// 変換条件が変わった場合だけ sws context を作り直す。
procedure EnsureSwsContext(
  Frame: PAVFrame;
  DstFormat: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
begin
  if Assigned(ScaleContext) and
     ((CachedSrcWidth <> Frame.width) or
      (CachedSrcHeight <> Frame.height) or
      (CachedSrcFormat <> Frame.format) or
      (CachedDstFormat <> DstFormat)) then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(ScaleContext));
    ScaleContext := nil;
  end;

  if not Assigned(ScaleContext) then
  begin
    ScaleContext := TFFmpegApi.sws_getContext(Frame.width, Frame.height, Frame.format,
      Frame.width, Frame.height, DstFormat, SWS_BILINEAR, nil, nil, nil);
    CachedSrcWidth := Frame.width;
    CachedSrcHeight := Frame.height;
    CachedSrcFormat := Frame.format;
    CachedDstFormat := DstFormat;
  end;

  if not Assigned(ScaleContext) then
    raise Exception.Create('sws_getContext failed.');
end;

// AVFrame を下から上へ並ぶ BGRX32 表示バッファへ変換する。
procedure CopyFrameToBgrx32Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData     : array[0..3] of PByte;   // sws_scale へ渡す出力 plane
  DstLinesize : array[0..3] of Integer; // sws_scale へ渡す出力 stride
  DstFormat   : Integer;                // FFmpeg の出力ピクセル形式
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Frame.width * 4;
  DstFormat := AV_PIX_FMT_BGRA;

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := PByte(NativeUInt(Buffer) + NativeUInt((Frame.height - 1) * BufferStride));
  DstLinesize[0] := -BufferStride;

  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrame を下から上へ並ぶ BGR24 表示バッファへ変換する。
procedure CopyFrameToBgr24Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData     : array[0..3] of PByte;   // sws_scale へ渡す出力 plane
  DstLinesize : array[0..3] of Integer; // sws_scale へ渡す出力 stride
  DstFormat   : Integer;                // FFmpeg の出力ピクセル形式
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Bgr24Stride(Frame.width);
  DstFormat := AV_PIX_FMT_BGR24;

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := PByte(NativeUInt(Buffer) + NativeUInt((Frame.height - 1) * BufferStride));
  DstLinesize[0] := -BufferStride;

  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrame を YUY2 バッファへ変換する。
procedure CopyFrameToYuy2Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData     : array[0..3] of PByte;   // sws_scale へ渡す出力 plane
  DstLinesize : array[0..3] of Integer; // sws_scale へ渡す出力 stride
  DstFormat   : Integer;                // FFmpeg の出力ピクセル形式
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Frame.width * 2;
  DstFormat := AV_PIX_FMT_YUYV422;

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := PByte(Buffer);
  DstLinesize[0] := BufferStride;

  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrame を I420 planar バッファへ変換する。
procedure CopyFrameToI420Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData      : array[0..3] of PByte;   // sws_scale へ渡す出力 plane
  DstLinesize  : array[0..3] of Integer; // sws_scale へ渡す出力 stride
  DstFormat    : Integer;                // FFmpeg の出力ピクセル形式
  ChromaWidth  : Integer;                // U/V plane の幅
  ChromaHeight : Integer;                // U/V plane の高さ
  YPlaneSize   : Integer;                // Y plane のバイト数
  UPlaneSize   : Integer;                // U plane のバイト数
  YDst         : PByte;                  // Y plane の出力先
  UDst         : PByte;                  // U plane の出力先
  VDst         : PByte;                  // V plane の出力先
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Frame.width;

  ChromaWidth := Chroma420Size(Frame.width);
  ChromaHeight := Chroma420Size(Frame.height);
  YPlaneSize := BufferStride * Frame.height;
  UPlaneSize := ChromaWidth * ChromaHeight;
  YDst := PByte(Buffer);
  UDst := PByte(NativeUInt(Buffer) + NativeUInt(YPlaneSize));
  VDst := PByte(NativeUInt(UDst) + NativeUInt(UPlaneSize));

  if Frame.format = AV_PIX_FMT_YUV420P then
  begin
    CopyPlane(Frame.data[0], YDst, Frame.linesize[0], BufferStride, Frame.width, Frame.height);
    CopyPlane(Frame.data[1], UDst, Frame.linesize[1], ChromaWidth, ChromaWidth, ChromaHeight);
    CopyPlane(Frame.data[2], VDst, Frame.linesize[2], ChromaWidth, ChromaWidth, ChromaHeight);
    CachedSrcWidth := Frame.width;
    CachedSrcHeight := Frame.height;
    CachedSrcFormat := Frame.format;
    CachedDstFormat := AV_PIX_FMT_YUV420P;
    Exit;
  end;

  DstFormat := AV_PIX_FMT_YUV420P;
  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := YDst;
  DstData[1] := UDst;
  DstData[2] := VDst;
  DstLinesize[0] := BufferStride;
  DstLinesize[1] := ChromaWidth;
  DstLinesize[2] := ChromaWidth;

  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrame を YC48 バッファへ変換する。
procedure CopyFrameToYc48Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  ChromaWidth  : Integer; // U/V plane の幅
  ChromaHeight : Integer; // U/V plane の高さ
  YPlaneSize   : Integer; // 一時 Y plane のバイト数
  UPlaneSize   : Integer; // 一時 U plane のバイト数
  Temp         : TBytes;  // I420 変換結果を受ける一時バッファ
  YPlane       : PByte;   // 一時 Y plane
  UPlane       : PByte;   // 一時 U plane
  VPlane       : PByte;   // 一時 V plane
begin
  EnsureFrameAndBuffer(Frame, Buffer);
  if BufferStride <= 0 then
    BufferStride := Frame.width * 6;

  if Frame.format = AV_PIX_FMT_YUV420P then
  begin
    CopyYuv420ToYc48(Frame.data[0], Frame.data[1], Frame.data[2],
      Frame.linesize[0], Frame.linesize[1], Frame.linesize[2],
      Frame.width, Frame.height, Buffer, BufferStride);
    CachedSrcWidth := Frame.width;
    CachedSrcHeight := Frame.height;
    CachedSrcFormat := Frame.format;
    CachedDstFormat := AV_PIX_FMT_YUV420P;
    Exit;
  end;

  ChromaWidth := Chroma420Size(Frame.width);
  ChromaHeight := Chroma420Size(Frame.height);
  YPlaneSize := Frame.width * Frame.height;
  UPlaneSize := ChromaWidth * ChromaHeight;
  SetLength(Temp, YPlaneSize + UPlaneSize * 2);
  YPlane := @Temp[0];
  UPlane := PByte(NativeUInt(YPlane) + NativeUInt(YPlaneSize));
  VPlane := PByte(NativeUInt(UPlane) + NativeUInt(UPlaneSize));

  CopyFrameToI420Buffer(Frame, YPlane, Frame.width, ScaleContext, CachedSrcWidth,
    CachedSrcHeight, CachedSrcFormat, CachedDstFormat);
  CopyYuv420ToYc48(YPlane, UPlane, VPlane, Frame.width, ChromaWidth, ChromaWidth,
    Frame.width, Frame.height, Buffer, BufferStride);
end;

// AVFrame を一時 sws context で Bitmap へ変換する。
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);
var
  ScaleContext : PSwsContext;            // この変換だけで使う sws context
  DstData      : array[0..3] of PByte;   // sws_scale へ渡す Bitmap 側 plane
  DstLinesize  : array[0..3] of Integer; // sws_scale へ渡す Bitmap 側 stride
  Stride       : NativeInt;              // Bitmap の実 stride
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');

  Bitmap.PixelFormat := pf24bit;
  Bitmap.SetSize(Frame.width, Frame.height);

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := Bitmap.ScanLine[0];
  if Frame.height > 1 then
    Stride := NativeInt(Bitmap.ScanLine[1]) - NativeInt(Bitmap.ScanLine[0])
  else
    Stride := Bgr24Stride(Frame.width);
  DstLinesize[0] := Integer(Stride);

  ScaleContext := TFFmpegApi.sws_getContext(Frame.width, Frame.height, Frame.format,
    Frame.width, Frame.height, AV_PIX_FMT_BGR24, SWS_BILINEAR, nil, nil, nil);
  if not Assigned(ScaleContext) then
    raise Exception.Create('sws_getContext failed.');
  try
    if TFFmpegApi.sws_scale(ScaleContext, @Frame.data[0], @Frame.linesize[0], 0,
      Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
      raise Exception.Create('sws_scale failed.');
  finally
    TFFmpegApi.sws_freeContext(ScaleContext);
  end;
end;

// AVFrame を再利用可能な sws context で Bitmap へ変換する。
procedure CopyFrameToBitmapCached(
  Frame: PAVFrame;
  Bitmap: TBitmap;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData     : array[0..3] of PByte;   // sws_scale へ渡す Bitmap 側 plane
  DstLinesize : array[0..3] of Integer; // sws_scale へ渡す Bitmap 側 stride
  Stride      : NativeInt;              // Bitmap の実 stride
  DstFormat   : Integer;                // FFmpeg の出力ピクセル形式
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');

  if Bitmap.PixelFormat <> pf32bit then
    Bitmap.PixelFormat := pf32bit;
  if (Bitmap.Width <> Frame.width) or (Bitmap.Height <> Frame.height) then
    Bitmap.SetSize(Frame.width, Frame.height);

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := Bitmap.ScanLine[0];
  if Frame.height > 1 then
    Stride := NativeInt(Bitmap.ScanLine[1]) - NativeInt(Bitmap.ScanLine[0])
  else
    Stride := Frame.width * 4;
  DstLinesize[0] := Integer(Stride);

  DstFormat := AV_PIX_FMT_BGRA;
  EnsureSwsContext(Frame, DstFormat, ScaleContext, CachedSrcWidth, CachedSrcHeight,
    CachedSrcFormat, CachedDstFormat);

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

end.