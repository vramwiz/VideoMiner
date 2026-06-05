unit FFmpegDecoderAudioPlayback;

interface

uses
  Winapi.MMSystem, System.Generics.Collections, System.SysUtils,
  FFmpegApi, FFmpegDecoderContext, FFmpegDecoderTypes;

function StartAudioPlayback(
  Context: TFFmpegDecoderContext;
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  out ErrorMessage: string
): Boolean;

procedure StopAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>
);

implementation

function StartAudioPlayback(
  Context: TFFmpegDecoderContext;
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  out ErrorMessage: string
): Boolean;
var
  WaveFormat: TWaveFormatEx;
  Ret: MMRESULT;
begin
  ErrorMessage := '';
  Result := False;

  StopAudioPlayback(WaveOut, AudioPlaybackActive, AudioBuffers);

  if (Context = nil) or (not Context.Info.Audio.Present) or
     (Context.AudioCodecContext = nil) or (Context.AudioStream = nil) or
     (Context.SwrContext = nil) then
  begin
    if Context <> nil then
      ErrorMessage := Format('Audio decoder is not open. present=%s codec=%s stream=%s swr=%s %s',
        [BoolToStr(Context.Info.Audio.Present, True),
         BoolToStr(Context.AudioCodecContext <> nil, True),
         BoolToStr(Context.AudioStream <> nil, True),
         BoolToStr(Context.SwrContext <> nil, True),
         Context.Info.Audio.OpenError])
    else
      ErrorMessage := 'Audio decoder context is nil.';
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := AUDIO_OUTPUT_CHANNELS;
  WaveFormat.nSamplesPerSec := AUDIO_OUTPUT_SAMPLE_RATE;
  WaveFormat.wBitsPerSample := 16;
  WaveFormat.nBlockAlign := WaveFormat.nChannels * WaveFormat.wBitsPerSample div 8;
  WaveFormat.nAvgBytesPerSec := WaveFormat.nSamplesPerSec * WaveFormat.nBlockAlign;

  Ret := waveOutOpen(@WaveOut, WAVE_MAPPER, @WaveFormat, 0, 0, CALLBACK_NULL);
  if Ret <> MMSYSERR_NOERROR then
  begin
    WaveOut := 0;
    ErrorMessage := Format('waveOutOpen failed: %d', [Ret]);
    Exit;
  end;

  AudioPlaybackActive := True;
  Result := True;
end;

procedure StopAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>
);
var
  Buffer: PAudioWaveBuffer;
begin
  AudioPlaybackActive := False;

  if WaveOut <> 0 then
    waveOutReset(WaveOut);

  if AudioBuffers <> nil then
  begin
    while AudioBuffers.Count > 0 do
    begin
      Buffer := AudioBuffers[AudioBuffers.Count - 1];
      if WaveOut <> 0 then
        waveOutUnprepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      AudioBuffers.Delete(AudioBuffers.Count - 1);
    end;
  end;

  if WaveOut <> 0 then
  begin
    waveOutClose(WaveOut);
    WaveOut := 0;
  end;
end;

end.
