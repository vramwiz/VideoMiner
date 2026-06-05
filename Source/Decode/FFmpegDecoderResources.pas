unit FFmpegDecoderResources;

interface

uses
  FFmpegDecoderContext;

procedure ReleaseDecoderResources(Context: TFFmpegDecoderContext);

implementation

uses
  FFmpegApi;

procedure ReleaseDecoderResources(Context: TFFmpegDecoderContext);
var
  TypedPacket            : PAVPacket;
  TypedFrame             : PAVFrame;
  TypedTransferFrame     : PAVFrame;
  TypedAudioFrame        : PAVFrame;
  TypedSwrContext        : PSwrContext;
  TypedAudioCodecContext : PAVCodecContext;
  TypedCodecContext      : PAVCodecContext;
  TypedQsvDeviceContext  : PAVBufferRef;
  TypedFormatContext     : PAVFormatContext;
begin
  if Context = nil then
    Exit;

  if Context.DirectSwsContext <> nil then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(Context.DirectSwsContext));
    Context.DirectSwsContext := nil;
  end;
  Context.DirectSwsSrcWidth := 0;
  Context.DirectSwsSrcHeight := 0;
  Context.DirectSwsSrcFormat := 0;
  Context.DirectSwsDstFormat := 0;

  TypedPacket := PAVPacket(Context.Packet);
  if Assigned(TypedPacket) then
  begin
    TFFmpegApi.av_packet_free(@TypedPacket);
    Context.Packet := nil;
  end;

  TypedFrame := PAVFrame(Context.Frame);
  if Assigned(TypedFrame) then
  begin
    TFFmpegApi.av_frame_free(@TypedFrame);
    Context.Frame := nil;
  end;

  TypedTransferFrame := PAVFrame(Context.TransferFrame);
  if Assigned(TypedTransferFrame) then
  begin
    TFFmpegApi.av_frame_free(@TypedTransferFrame);
    Context.TransferFrame := nil;
  end;

  TypedAudioFrame := PAVFrame(Context.AudioFrame);
  if Assigned(TypedAudioFrame) then
  begin
    TFFmpegApi.av_frame_free(@TypedAudioFrame);
    Context.AudioFrame := nil;
  end;

  TypedSwrContext := PSwrContext(Context.SwrContext);
  if Assigned(TypedSwrContext) then
  begin
    TFFmpegApi.swr_free(@TypedSwrContext);
    Context.SwrContext := nil;
  end;

  TypedAudioCodecContext := PAVCodecContext(Context.AudioCodecContext);
  if Assigned(TypedAudioCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@TypedAudioCodecContext);
    Context.AudioCodecContext := nil;
  end;

  TypedCodecContext := PAVCodecContext(Context.CodecContext);
  if Assigned(TypedCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@TypedCodecContext);
    Context.CodecContext := nil;
  end;

  TypedQsvDeviceContext := PAVBufferRef(Context.QsvDeviceContext);
  if Assigned(TypedQsvDeviceContext) then
  begin
    TFFmpegApi.av_buffer_unref(@TypedQsvDeviceContext);
    Context.QsvDeviceContext := nil;
  end;

  TypedFormatContext := PAVFormatContext(Context.FormatContext);
  if Assigned(TypedFormatContext) then
  begin
    TFFmpegApi.avformat_close_input(@TypedFormatContext);
    Context.FormatContext := nil;
  end;
end;

end.
