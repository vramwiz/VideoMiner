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
  FFmpegAudioConvert, FFmpegAudioOpen;

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

  function EnsureAudioResamplerForFrame: Boolean;
  var
    AudioFrame: PAVFrame;
    AudioStream: PAVStream;
    AudioCodecPar: PAVCodecParameters;
    NewSwrContext: PSwrContext;
    OldSwrContext: PSwrContext;
    ActualSampleFormat: Integer;
  begin
    Result := False;
    AudioFrame := PAVFrame(Context.AudioFrame);
    AudioStream := PAVStream(Context.AudioStream);
    if (AudioFrame = nil) or (AudioStream = nil) or (AudioStream.codecpar = nil) then
    begin
      ErrorMessage := 'Audio frame or stream is nil.';
      Exit;
    end;

    ActualSampleFormat := AudioFrame.format;
    if ActualSampleFormat < 0 then
      ActualSampleFormat := Context.Info.Audio.SampleFormat;

    if (Context.SwrContext <> nil) and
       (ActualSampleFormat = Context.Info.Audio.SampleFormat) then
    begin
      Result := True;
      Exit;
    end;

    AudioCodecPar := AudioStream.codecpar;
    if not PrepareAudioResampler(AudioCodecPar, ActualSampleFormat, NewSwrContext,
      ErrorMessage) then
      Exit;

    OldSwrContext := PSwrContext(Context.SwrContext);
    if OldSwrContext <> nil then
      TFFmpegApi.swr_free(@OldSwrContext);

    Context.SwrContext := NewSwrContext;
    Context.Info.Audio.SampleFormat := ActualSampleFormat;
    Context.Info.Audio.SampleFormatName := SampleFormatName(ActualSampleFormat);
    Result := True;
  end;

  function AppendDecodedAudioFrame: Boolean;
  begin
    Result := False;

    if not EnsureAudioResamplerForFrame then
      Exit;

    if not ConvertAudioFrameToPcm16Stereo48k(PAVFrame(Context.AudioFrame),
      PSwrContext(Context.SwrContext), Context.Info.Audio.SampleRate, Chunk,
      ChunkSampleCount) then
      Exit;

    OldBytes := Length(Pcm);
    SetLength(Pcm, OldBytes + Length(Chunk));
    if Length(Chunk) > 0 then
      Move(Chunk[0], Pcm[OldBytes], Length(Chunk));
    Inc(SampleCount, ChunkSampleCount);
    Result := True;
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
          if not AppendDecodedAudioFrame then
            Exit;
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
          if not AppendDecodedAudioFrame then
            Exit;
      Finished := True;
    end;

    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

end.
