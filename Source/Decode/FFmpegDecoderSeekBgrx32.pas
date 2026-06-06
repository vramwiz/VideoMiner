unit FFmpegDecoderSeekBgrx32;

interface

uses
  FFmpegDecoderContext;

function DecodeFrameToBgrx32(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.SysUtils, FFmpegApi, FFmpegFrameConvert, FFmpegQsvDecode, FFmpegStreamInfo;


function DecodeFrameToBgrx32(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
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
  FrameTs: Int64;
  TargetTs: Int64;
  DidTransfer: Boolean;
  TransferErrorMessage: string;
begin
  ErrorMessage := '';
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
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, Context.StreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if Context.AudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(Context.AudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = Context.StreamIndex then
        begin
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
          FrameTs := Frame.pts;
          if (FrameTs <> AV_NOPTS_VALUE) and (FrameTs >= TargetTs) then
          begin
            ConvertSourceFrame := Frame;
            DidTransfer := False;
            if not TransferFrameToCpuIfNeeded(Frame, PAVFrame(Context.TransferFrame),
              ConvertSourceFrame, DidTransfer, TransferErrorMessage) then
            begin
              ErrorMessage := 'Failed to transfer video frame: ' + TransferErrorMessage;
              Exit;
            end;
            CopyFrameToBgrx32Buffer(ConvertSourceFrame, Buffer, BufferStride,
              Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
              Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
