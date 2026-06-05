unit FFmpegDecoderSeekYc48;

interface

uses
  FFmpegDecoderContext;

function DecodeFrameToYc48(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  Buffer: Pointer;
  BufferStride: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  System.Diagnostics, System.SysUtils, Winapi.Windows,
  FFmpegApi, FFmpegDecodeStats, FFmpegFrameConvert, FFmpegStreamInfo;

const
{$IFDEF DEBUG}
  DECODE_TRACE_ENABLED = True;
{$ELSE}
  DECODE_TRACE_ENABLED = False;
{$ENDIF}

procedure DecodeTrace(const Msg: string);
var
  F: TextFile;
  LogFileName: string;
  Line: string;
begin
  if not DECODE_TRACE_ENABLED then
    Exit;

  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [FFmpegDecoder] ' + Msg;
  OutputDebugString(PChar(Line));
  LogFileName := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'VW_Media_Input_decode.log';
  AssignFile(F, LogFileName);
  try
    if FileExists(LogFileName) then
      Append(F)
    else
      Rewrite(F);
    Writeln(F, Line);
  finally
    CloseFile(F);
  end;
end;

function DecodeFrameToYc48(
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
  Stream: PAVStream;
  Ret: Integer;
  TargetTs: Int64;
{$IFDEF DEBUG}
  Stopwatch: TStopwatch;
  TotalStopwatch: TStopwatch;
  ReadPacketCount: Integer;
  VideoPacketCount: Integer;
  DecodedFrameCount: Integer;
{$ENDIF}
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
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
    begin
      ReadPacketCount := 0;
      VideoPacketCount := 0;
      DecodedFrameCount := 0;
    end;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      TotalStopwatch := TStopwatch.StartNew;
{$ENDIF}
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
{$IFDEF DEBUG}
      if DECODE_TRACE_ENABLED then
        Inc(ReadPacketCount);
{$ENDIF}
      try
        if Packet.stream_index = Context.StreamIndex then
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
            Inc(VideoPacketCount);
{$ENDIF}
        end;

        if Packet.stream_index <> Context.StreamIndex then
          Continue;

{$IFDEF DEBUG}
        if DECODE_TRACE_ENABLED then
          Stopwatch := TStopwatch.StartNew;
{$ENDIF}
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
{$IFDEF DEBUG}
          if DECODE_TRACE_ENABLED then
            Inc(DecodedFrameCount);
{$ENDIF}
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            CopyFrameToYc48Buffer(Frame, Buffer, BufferStride,
              Context.DirectSwsContext, Context.DirectSwsSrcWidth, Context.DirectSwsSrcHeight,
              Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat);
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
            begin
              Stopwatch.Stop;
              TotalStopwatch.Stop;
              FFmpegDecodeStats.UpdateVideoLoadStats(Context.DecodeStats, Stopwatch.Elapsed.TotalMilliseconds);
            end;
{$ENDIF}
{$IFDEF DEBUG}
            if DECODE_TRACE_ENABLED then
              DecodeTrace(Format('seek_decode_yc48 file="%s" pos_ms=%d target_ts=%d frame_pts=%d read_packets=%d video_packets=%d decoded_frames=%d src_fmt=%d dst_fmt=%d elapsed_ms=%.3f convert_ms=%.3f',
                [Context.FileName, PositionMs, TargetTs, Frame.pts, ReadPacketCount, VideoPacketCount, DecodedFrameCount,
                 Context.DirectSwsSrcFormat, Context.DirectSwsDstFormat,
                 TotalStopwatch.Elapsed.TotalMilliseconds, Stopwatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      TotalStopwatch.Stop;
{$ENDIF}
{$IFDEF DEBUG}
    if DECODE_TRACE_ENABLED then
      DecodeTrace(Format('seek_decode_yc48_failed file="%s" pos_ms=%d target_ts=%d read_packets=%d video_packets=%d decoded_frames=%d elapsed_ms=%.3f',
        [Context.FileName, PositionMs, TargetTs, ReadPacketCount, VideoPacketCount, DecodedFrameCount,
         TotalStopwatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
