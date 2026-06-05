unit FFmpegDecoderNextYc48;

interface

uses
  FFmpegDecoderContext;

function DecodeNextFrameToYc48Optional(
  Context: TFFmpegDecoderContext;
  Buffer: Pointer;
  BufferStride: Integer;
  ConvertFrame: Boolean;
  out PositionMs: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.SysUtils, FFmpegApi, FFmpegFrameConvert, FFmpegStreamInfo;


function DecodeNextFrameToYc48Optional(
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
  Stream: PAVStream;
  Ret: Integer;
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
      if ConvertFrame then
        CopyFrameToYc48Buffer(Frame, Buffer, BufferStride,
          Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
          Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
      PositionMs := StreamTimestampToMs(Stream, Frame.pts);
      Result := True;
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
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if ConvertFrame then
            CopyFrameToYc48Buffer(Frame, Buffer, BufferStride,
              Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
              Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
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
