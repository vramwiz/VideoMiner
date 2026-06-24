unit FFmpegDecoderNextBgrx32;

// 現在位置から次の動画フレームを読み、BGRX32 バッファへ変換する。
// VideoMiner の通常表示に使う順方向デコードの中心処理を担当する。

interface

uses
  FFmpegDecoderContext;

// 次の動画フレームを読み、必要なら BGRX32 バッファへ変換する。
function DecodeNextFrameToBgrx32Optional(
  Context: TFFmpegDecoderContext;
  Buffer: Pointer;
  BufferStride: Integer;
  ConvertFrame: Boolean;
  out PositionMs: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.Diagnostics, System.SysUtils, FFmpegApi, FFmpegFrameConvert,
  FFmpegQsvDecode, FFmpegStreamInfo, VideoMinerDebugLog;


// 次の動画フレームを読み、必要なら BGRX32 バッファへ変換する。
function DecodeNextFrameToBgrx32Optional(
  Context: TFFmpegDecoderContext;
  Buffer: Pointer;
  BufferStride: Integer;
  ConvertFrame: Boolean;
  out PositionMs: Integer;
  out ErrorMessage: string
): Boolean;
var
  FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext;
  Packet: PAVPacket;
  Frame: PAVFrame;
  ConvertSourceFrame: PAVFrame;
  Stream: PAVStream;
  Ret: Integer;
  DidTransfer: Boolean;
  TransferErrorMessage: string;
{$IFDEF DEBUG}
  TransferWatch: TStopwatch;
  ConvertWatch: TStopwatch;
  TransferMs: Double;
  ConvertMs: Double;
{$ENDIF}

  function FinishFrame(const SourceName: string): Boolean;
  begin
    Result := False;
    if ConvertFrame then
    begin
      ConvertSourceFrame := Frame;
      DidTransfer := False;
{$IFDEF DEBUG}
      TransferMs := 0;
      ConvertMs := 0;
      TransferWatch := TStopwatch.StartNew;
{$ENDIF}
      if not TransferFrameToCpuIfNeeded(Frame, PAVFrame(Context.TransferFrame),
        ConvertSourceFrame, DidTransfer, TransferErrorMessage) then
      begin
        ErrorMessage := 'Failed to transfer video frame: ' + TransferErrorMessage;
        Exit;
      end;
{$IFDEF DEBUG}
      TransferMs := TransferWatch.Elapsed.TotalMilliseconds;
      ConvertWatch := TStopwatch.StartNew;
{$ENDIF}
      CopyFrameToBgrx32BufferCached(ConvertSourceFrame, Buffer, BufferStride,
        Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
        Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat,
        Context.Bgrx32TempBuffer, Context.Bgrx32TempStride,
        Context.Bgrx32TempHeight);
{$IFDEF DEBUG}
      ConvertMs := ConvertWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerSlowLog(Format(
        'next_bgrx32_detail source=%s frame=%dx%d fmt=%d linesize0=%d transferred=%s transfer_ms=%.3f convert_ms=%.3f buffer_stride=%d',
        [SourceName, ConvertSourceFrame.width, ConvertSourceFrame.height,
         ConvertSourceFrame.format, ConvertSourceFrame.linesize[0],
         BoolToStr(DidTransfer, True), TransferMs, ConvertMs, BufferStride]));
{$ENDIF}
    end;

    PositionMs := StreamTimestampToMs(Stream, Frame.pts);
    Result := True;
  end;

begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  if Context = nil then
  begin
    ErrorMessage := 'Decoder context is nil.';
    Exit;
  end;

  FormatContext := PAVFormatContext(Context.FormatContext);
  CodecContext := PAVCodecContext(Context.CodecContext);
  Packet := PAVPacket(Context.Packet);
  Frame := PAVFrame(Context.Frame);
  Stream := PAVStream(Context.Stream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    if TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 then
    begin
      Result := FinishFrame('buffered');
      Exit;
    end;

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = Context.AudioStreamIndex then
        begin
          Continue;
        end;

        if Packet.stream_index <> Context.StreamIndex then
          Continue;

        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
        begin
          Continue;
        end;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          Result := FinishFrame('packet');
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
