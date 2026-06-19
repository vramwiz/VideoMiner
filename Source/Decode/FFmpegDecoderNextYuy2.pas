unit FFmpegDecoderNextYuy2;

// 現在位置から次の動画フレームを読み、YUY2 バッファへ変換する。
// 形式別の順方向デコード処理として BGRX32 系から分離する。

interface

uses
  FFmpegDecoderContext;

// 次の動画フレームを読み、必要なら YUY2 バッファへ変換する。
function DecodeNextFrameToYuy2Optional(
  Context: TFFmpegDecoderContext;
  Buffer: Pointer;
  BufferStride: Integer;
  ConvertFrame: Boolean;
  out PositionMs: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.SysUtils, FFmpegApi, FFmpegFrameConvert, FFmpegQsvDecode, FFmpegStreamInfo;


// 次の動画フレームを読み、必要なら YUY2 バッファへ変換する。
function DecodeNextFrameToYuy2Optional(
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

  function FinishFrame(const SourceName: string): Boolean;
  begin
    Result := False;
    if ConvertFrame then
    begin
      ConvertSourceFrame := Frame;
      DidTransfer := False;
      if not TransferFrameToCpuIfNeeded(Frame, PAVFrame(Context.TransferFrame),
        ConvertSourceFrame, DidTransfer, TransferErrorMessage) then
      begin
        ErrorMessage := 'Failed to transfer video frame: ' + TransferErrorMessage;
        Exit;
      end;
      CopyFrameToYuy2Buffer(ConvertSourceFrame, Buffer, BufferStride,
        Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
        Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
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
