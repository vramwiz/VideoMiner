unit FFmpegDecoderAudioRead;

interface

uses
  System.SysUtils, FFmpegApi, FFmpegDecoderContext;

function DecodeAudioPcm16Stereo48kUntil(
  Context: TFFmpegDecoderContext;
  TargetSampleCount: Integer;
  var Pcm: TBytes;
  var SampleCount: Integer;
  out Finished: Boolean;
  out ErrorMessage: string
): Boolean;

implementation

uses
  FFmpegAudioConvert;

function DecodeAudioPcm16Stereo48kUntil(
  Context: TFFmpegDecoderContext;
  TargetSampleCount: Integer;
  var Pcm: TBytes;
  var SampleCount: Integer;
  out Finished: Boolean;
  out ErrorMessage: string
): Boolean;
var
  Ret: Integer;
  Chunk: TBytes;
  ChunkSampleCount: Integer;
  OldBytes: Integer;

  procedure AppendDecodedAudioFrame;
begin
    if not ConvertAudioFrameToPcm16Stereo48k(PAVFrame(Context.AudioFrame),
      PSwrContext(Context.SwrContext), Context.Info.Audio.SampleRate, Chunk,
      ChunkSampleCount) then
      Exit;

    OldBytes := Length(Pcm);
    SetLength(Pcm, OldBytes + Length(Chunk));
    if Length(Chunk) > 0 then
      Move(Chunk[0], Pcm[OldBytes], Length(Chunk));
    Inc(SampleCount, ChunkSampleCount);
  end;

begin
  ErrorMessage := '';
  Finished := False;
  Result := False;

  if TargetSampleCount <= SampleCount then
  begin
    Result := True;
    Exit;
  end;

  if (Context = nil) or (not Context.Info.Audio.Present) or
     (Context.AudioCodecContext = nil) or (Context.Packet = nil) or
     (Context.AudioFrame = nil) or (Context.SwrContext = nil) or
     (Context.FormatContext = nil) then
  begin
    if Context <> nil then
      ErrorMessage := 'Audio decoder is not open. ' + Context.Info.Audio.OpenError
    else
      ErrorMessage := 'Audio decoder context is nil.';
    Exit;
  end;

  try
    while (SampleCount < TargetSampleCount) and
      (TFFmpegApi.av_read_frame(PAVFormatContext(Context.FormatContext), PAVPacket(Context.Packet)) >= 0) do
    begin
      try
        if PAVPacket(Context.Packet).stream_index <> Context.AudioStreamIndex then
          Continue;

        Ret := TFFmpegApi.avcodec_send_packet(PAVCodecContext(Context.AudioCodecContext),
          PAVPacket(Context.Packet));
        if Ret < 0 then
          Continue;

        while (SampleCount < TargetSampleCount) and
          (TFFmpegApi.avcodec_receive_frame(PAVCodecContext(Context.AudioCodecContext),
            PAVFrame(Context.AudioFrame)) = 0) do
          AppendDecodedAudioFrame;
      finally
        TFFmpegApi.av_packet_unref(PAVPacket(Context.Packet));
      end;
    end;

    if SampleCount < TargetSampleCount then
    begin
      Ret := TFFmpegApi.avcodec_send_packet(PAVCodecContext(Context.AudioCodecContext), nil);
      if Ret >= 0 then
        while (SampleCount < TargetSampleCount) and
          (TFFmpegApi.avcodec_receive_frame(PAVCodecContext(Context.AudioCodecContext),
            PAVFrame(Context.AudioFrame)) = 0) do
          AppendDecodedAudioFrame;
      Finished := True;
    end;

    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
