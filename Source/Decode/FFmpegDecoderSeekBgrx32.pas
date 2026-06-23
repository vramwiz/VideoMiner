unit FFmpegDecoderSeekBgrx32;

// 指定時刻へシークし、動画フレームを BGRX32 バッファへ変換する。
// 通常シークと高速シークの入口を持ち、VideoMiner の表示更新で主に使う。

interface

uses
  FFmpegDecoderContext;

// 指定時刻の動画フレームを BGRX32 バッファへ取得する。
function DecodeFrameToBgrx32(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;

// キーフレーム優先の高速シークで BGRX32 フレームを取得する。
function DecodeFrameToBgrx32Fast(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.SysUtils, FFmpegApi, FFmpegFrameConvert, FFmpegQsvDecode,
  FFmpegStreamInfo, VideoMinerDebugLog;

const
  FIRST_FRAME_EXACT_TOLERANCE_MS = 5; // 0ms シークで先頭フレームとして許容する誤差

// フレームの表示時刻を、取得できる範囲で最も信頼できる値として返す。
function DisplayFrameTimestamp(Frame: PAVFrame): Int64;
begin
  Result := AV_NOPTS_VALUE;
  if Frame = nil then
    Exit;

  if Frame.best_effort_timestamp <> AV_NOPTS_VALUE then
    Result := Frame.best_effort_timestamp
  else if Frame.pts <> AV_NOPTS_VALUE then
    Result := Frame.pts
  else
    Result := Frame.pkt_dts;
end;

// 0ms シーク時に、前回位置から残った遅延フレームを採用しないようにする。
function AcceptSeekFrame(Stream: PAVStream; PositionMs: Integer;
  TargetTs, FrameTs: Int64): Boolean;
var
  FrameMs: Integer; // フレーム timestamp を ms へ直した値
begin
  if PositionMs <= 0 then
  begin
    if FrameTs = AV_NOPTS_VALUE then
    begin
      Result := True;
      Exit;
    end;

    FrameMs := StreamTimestampToMs(Stream, FrameTs);
    Result := FrameMs <= FIRST_FRAME_EXACT_TOLERANCE_MS;
    Exit;
  end;

  Result := (FrameTs <> AV_NOPTS_VALUE) and (FrameTs >= TargetTs);
end;

// 通常シークと高速シークに共通する BGRX32 取得処理を実行する。
function DecodeFrameToBgrx32Internal(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  FastSeek: Boolean;
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
  SeekFlags: Integer;
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
    TFFmpegApi.av_packet_unref(Packet);
    TFFmpegApi.av_frame_unref(Frame);
    if Context.TransferFrame <> nil then
      TFFmpegApi.av_frame_unref(PAVFrame(Context.TransferFrame));
    SeekFlags := AVSEEK_FLAG_BACKWARD;
    if FastSeek then
      SeekFlags := SeekFlags or AVSEEK_FLAG_ANY;
    Ret := TFFmpegApi.av_seek_frame(FormatContext, Context.StreamIndex,
      TargetTs, SeekFlags);
    if (Ret < 0) and FastSeek then
      Ret := TFFmpegApi.av_seek_frame(FormatContext, Context.StreamIndex,
        TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avformat_flush(FormatContext);
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if Context.AudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(Context.AudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> Context.StreamIndex then
          Continue;

        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
        begin
          Continue;
        end;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          FrameTs := DisplayFrameTimestamp(Frame);
          if FastSeek or AcceptSeekFrame(Stream, PositionMs, TargetTs, FrameTs) then
          begin
            ConvertSourceFrame := Frame;
            DidTransfer := False;
            if not TransferFrameToCpuIfNeeded(Frame, PAVFrame(Context.TransferFrame),
              ConvertSourceFrame, DidTransfer, TransferErrorMessage) then
            begin
              ErrorMessage := 'Failed to transfer video frame: ' + TransferErrorMessage;
              if DidTransfer and (Context.TransferFrame <> nil) then
                TFFmpegApi.av_frame_unref(PAVFrame(Context.TransferFrame));
              TFFmpegApi.av_frame_unref(Frame);
              Exit;
            end;
{$IFDEF DEBUG}
            WriteVideoMinerSlowLog(Format(
              'seek_bgrx32_copy requested_ms=%d target_ts=%d frame_ts=%d frame_ms=%d fast=%s frame=%dx%d fmt=%d linesize0=%d data0=%p buffer=%p stride=%d transferred=%s',
              [PositionMs, TargetTs, FrameTs, StreamTimestampToMs(Stream,
               FrameTs), BoolToStr(FastSeek, True),
               ConvertSourceFrame.width, ConvertSourceFrame.height,
               ConvertSourceFrame.format, ConvertSourceFrame.linesize[0],
               ConvertSourceFrame.data[0], Buffer, BufferStride,
               BoolToStr(DidTransfer, True)]));
{$ENDIF}
            CopyFrameToBgrx32Buffer(ConvertSourceFrame, Buffer, BufferStride,
              Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
              Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
            if DidTransfer and (Context.TransferFrame <> nil) then
              TFFmpegApi.av_frame_unref(PAVFrame(Context.TransferFrame));
            TFFmpegApi.av_frame_unref(Frame);
            Result := True;
            Exit;
          end;
{$IFDEF DEBUG}
          if PositionMs <= 0 then
            WriteVideoMinerSlowLog(Format(
              'seek_bgrx32_skip_stale_first frame_ts=%d frame_ms=%d target_ts=%d',
              [FrameTs, StreamTimestampToMs(Stream, FrameTs), TargetTs]));
{$ENDIF}
          TFFmpegApi.av_frame_unref(Frame);
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

// 指定時刻の動画フレームを BGRX32 バッファへ取得する。
function DecodeFrameToBgrx32(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;
begin
  Result := DecodeFrameToBgrx32Internal(Context, PositionMs, Buffer,
    BufferStride, False, ErrorMessage);
end;

// キーフレーム優先の高速シークで BGRX32 フレームを取得する。
function DecodeFrameToBgrx32Fast(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;
begin
  Result := DecodeFrameToBgrx32Internal(Context, PositionMs, Buffer,
    BufferStride, True, ErrorMessage);
end;

end.
