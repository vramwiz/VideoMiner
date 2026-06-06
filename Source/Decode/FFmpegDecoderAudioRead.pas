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

function SeekAudioToMs(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  out ErrorMessage: string
): Boolean;

implementation

uses
  FFmpegAudioConvert, FFmpegAudioOpen;

function SeekAudioToMs(
  Context: TFFmpegDecoderContext;
  PositionMs: Integer;
  out ErrorMessage: string
): Boolean;
var
  Ret: Integer;
  TargetTs: Int64;
begin
  ErrorMessage := '';
  Result := False;

  if (Context = nil) or (Context.FormatContext = nil) or
     (Context.AudioCodecContext = nil) or (Context.AudioStream = nil) or
     (Context.AudioStreamIndex < 0) then
  begin
    ErrorMessage := 'Audio decoder is not open.';
    Exit;
  end;

  TargetTs := StreamTimestampFromMs(PAVStream(Context.AudioStream), PositionMs);
  Ret := TFFmpegApi.av_seek_frame(PAVFormatContext(Context.FormatContext),
    Context.AudioStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
  if Ret < 0 then
  begin
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(Context.AudioCodecContext));
  Context.AudioDiscardUntilSample := (Int64(PositionMs) * AUDIO_OUTPUT_SAMPLE_RATE + 500) div 1000;
  Result := True;
end;

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
  FrameStartMs: Integer;
  FrameStartSample: Integer;
  DiscardUntilSample: Integer;
  TrimSampleCount: Integer;
  TrimByteCount: Integer;

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
  var
    AudioFrame: PAVFrame;
    AudioStream: PAVStream;
  begin
    Result := False;
    AudioFrame := PAVFrame(Context.AudioFrame);
    AudioStream := PAVStream(Context.AudioStream);

    if not EnsureAudioResamplerForFrame then
      Exit;

    if not ConvertAudioFrameToPcm16Stereo48k(AudioFrame,
      PSwrContext(Context.SwrContext), Context.Info.Audio.SampleRate, Chunk,
      ChunkSampleCount) then
      Exit;

    if (Context.AudioDiscardUntilSample >= 0) and (ChunkSampleCount > 0) then
    begin
      DiscardUntilSample := Context.AudioDiscardUntilSample;
      FrameStartMs := StreamTimestampToMs(AudioStream, AudioFrame.pts);
      if FrameStartMs < 0 then
        Context.AudioDiscardUntilSample := -1
      else
      begin
        FrameStartSample := (Int64(FrameStartMs) * AUDIO_OUTPUT_SAMPLE_RATE + 500) div 1000;
        if FrameStartSample + ChunkSampleCount <= DiscardUntilSample then
        begin
          Result := True;
          Exit;
        end;

        if FrameStartSample < DiscardUntilSample then
        begin
          TrimSampleCount := DiscardUntilSample - FrameStartSample;
          if TrimSampleCount > ChunkSampleCount then
            TrimSampleCount := ChunkSampleCount;
          TrimByteCount := TrimSampleCount * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt);
          if TrimByteCount > 0 then
          begin
            if TrimByteCount < Length(Chunk) then
              Move(Chunk[TrimByteCount], Chunk[0], Length(Chunk) - TrimByteCount);
            SetLength(Chunk, Length(Chunk) - TrimByteCount);
            Dec(ChunkSampleCount, TrimSampleCount);
          end;
          SampleCount := DiscardUntilSample;
        end;
        Context.AudioDiscardUntilSample := -1;
      end;
    end;

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
