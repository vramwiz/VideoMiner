unit FFmpegDecoderAudioPlayback;

// waveOut を使った低レベル音声出力を扱う。
// PCM バッファの投入、再生済み位置の取得、音量反映、終了時の解放を担当する。

interface

uses
  Winapi.Windows, Winapi.MMSystem, System.Generics.Collections, System.SysUtils,
  FFmpegApi, FFmpegDecoderContext, FFmpegDecoderTypes;

// waveOut を開き、PCM キューを受けられる音声出力状態へ移行する。
function StartAudioPlayback(
  Context: TFFmpegDecoderContext;
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  out ErrorMessage: string
): Boolean;

// 再生中の waveOut と未完了 PCM バッファをすべて停止・解放する。
procedure StopAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>
);

// waveOut ハンドルを保持したまま、再生中の PCM キューだけを停止・解放する。
procedure ResetAudioPlayback(
  WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>
);

// PCM16 stereo 48kHz のデータを waveOut キューへ投入する。
function QueueAudioPcm16Stereo48k(
  WaveOut: HWAVEOUT;
  AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  const Pcm: TBytes;
  out ErrorMessage: string
): Boolean;

// waveOut の左右チャンネル音量を同じ値で更新する。
procedure SetAudioOutputVolume(WaveOut: HWAVEOUT; VolumePercent: Integer);

// waveOut へ投入済みで、まだ完了していない PCM サンプル数を返す。
function QueuedAudioSampleCount(WaveOut: HWAVEOUT;
  AudioBuffers: TList<PAudioWaveBuffer>): Integer;

// waveOut が再生済みとして報告する PCM サンプル位置を返す。
function PlayedAudioSampleCount(WaveOut: HWAVEOUT): Integer;

implementation

// waveOut の左右チャンネル音量を同じ値で更新する。
procedure SetAudioOutputVolume(WaveOut: HWAVEOUT; VolumePercent: Integer);
var
  Volume: DWORD;
  ChannelVolume: DWORD;
begin
  if WaveOut = 0 then
    Exit;

  if VolumePercent < 0 then
    VolumePercent := 0
  else if VolumePercent > 100 then
    VolumePercent := 100;

  ChannelVolume := DWORD(Round($FFFF * VolumePercent / 100));
  Volume := ChannelVolume or (ChannelVolume shl 16);
  waveOutSetVolume(WaveOut, Volume);
end;

// waveOut が再生完了した PCM バッファだけを回収する。
procedure CleanupDoneBuffers(WaveOut: HWAVEOUT; AudioBuffers: TList<PAudioWaveBuffer>);
var
  I: Integer;
  Buffer: PAudioWaveBuffer;
begin
  if (WaveOut = 0) or (AudioBuffers = nil) then
    Exit;

  I := AudioBuffers.Count - 1;
  while I >= 0 do
  begin
    Buffer := AudioBuffers[I];
    if (Buffer <> nil) and ((Buffer.Header.dwFlags and WHDR_DONE) <> 0) then
    begin
      waveOutUnprepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      AudioBuffers.Delete(I);
    end;
    Dec(I);
  end;
end;

// waveOut に渡した PCM バッファをすべて unprepare して解放する。
procedure ReleaseAudioBuffers(WaveOut: HWAVEOUT; AudioBuffers: TList<PAudioWaveBuffer>);
var
  Buffer: PAudioWaveBuffer;
begin
  if AudioBuffers = nil then
    Exit;

  while AudioBuffers.Count > 0 do
  begin
    Buffer := AudioBuffers[AudioBuffers.Count - 1];
    if Buffer <> nil then
    begin
      if WaveOut <> 0 then
        waveOutUnprepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
    end;
    AudioBuffers.Delete(AudioBuffers.Count - 1);
  end;
end;

// waveOut へ投入済みで、まだ完了していない PCM サンプル数を返す。
function QueuedAudioSampleCount(WaveOut: HWAVEOUT;
  AudioBuffers: TList<PAudioWaveBuffer>): Integer;
var
  Buffer: PAudioWaveBuffer;
begin
  Result := 0;
  CleanupDoneBuffers(WaveOut, AudioBuffers);

  if AudioBuffers = nil then
    Exit;

  for Buffer in AudioBuffers do
    if Buffer <> nil then
      Inc(Result, Buffer.Size div (AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt)));
end;

// waveOut が再生済みとして報告する PCM サンプル位置を返す。
function PlayedAudioSampleCount(WaveOut: HWAVEOUT): Integer;
var
  Time: TMMTime;
begin
  Result := 0;
  if WaveOut = 0 then
    Exit;

  FillChar(Time, SizeOf(Time), 0);
  Time.wType := TIME_SAMPLES;
  if waveOutGetPosition(WaveOut, @Time, SizeOf(Time)) <> MMSYSERR_NOERROR then
    Exit;

  if Time.wType = TIME_SAMPLES then
    Result := Time.sample
  else if Time.wType = TIME_BYTES then
    Result := Time.cb div (AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
end;

// waveOut を開き、PCM キューを受けられる音声出力状態へ移行する。
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

  if WaveOut <> 0 then
  begin
    ResetAudioPlayback(WaveOut, AudioPlaybackActive, AudioBuffers);
    SetAudioOutputVolume(WaveOut, 100);
    AudioPlaybackActive := True;
    Result := True;
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

  SetAudioOutputVolume(WaveOut, 100);
  AudioPlaybackActive := True;
  Result := True;
end;

// PCM16 stereo 48kHz のデータを waveOut キューへ投入する。
function QueueAudioPcm16Stereo48k(
  WaveOut: HWAVEOUT;
  AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>;
  const Pcm: TBytes;
  out ErrorMessage: string
): Boolean;
var
  Buffer: PAudioWaveBuffer;
  Ret: MMRESULT;
begin
  ErrorMessage := '';
  Result := False;

  CleanupDoneBuffers(WaveOut, AudioBuffers);

  if Length(Pcm) = 0 then
  begin
    Result := True;
    Exit;
  end;

  if (WaveOut = 0) or (not AudioPlaybackActive) or (AudioBuffers = nil) then
  begin
    ErrorMessage := 'Audio playback is not active.';
    Exit;
  end;

  New(Buffer);
  FillChar(Buffer^, SizeOf(Buffer^), 0);
  try
    Buffer.Size := Length(Pcm);
    GetMem(Buffer.Data, Buffer.Size);
    Move(Pcm[0], Buffer.Data^, Buffer.Size);

    Buffer.Header.lpData := Buffer.Data;
    Buffer.Header.dwBufferLength := Buffer.Size;

    Ret := waveOutPrepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
    if Ret <> MMSYSERR_NOERROR then
    begin
      ErrorMessage := Format('waveOutPrepareHeader failed: %d', [Ret]);
      FreeMem(Buffer.Data);
      Dispose(Buffer);
      Exit;
    end;

    Ret := waveOutWrite(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
    if Ret <> MMSYSERR_NOERROR then
    begin
      waveOutUnprepareHeader(WaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      ErrorMessage := Format('waveOutWrite failed: %d', [Ret]);
      FreeMem(Buffer.Data);
      Dispose(Buffer);
      Exit;
    end;

    AudioBuffers.Add(Buffer);
    Result := True;
  except
    on E: Exception do
    begin
      if Buffer <> nil then
      begin
        if Buffer.Data <> nil then
          FreeMem(Buffer.Data);
        Dispose(Buffer);
      end;
      ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

// 再生中の waveOut と未完了 PCM バッファをすべて停止・解放する。
procedure StopAudioPlayback(
  var WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>
);
begin
  ResetAudioPlayback(WaveOut, AudioPlaybackActive, AudioBuffers);

  if WaveOut <> 0 then
  begin
    waveOutClose(WaveOut);
    WaveOut := 0;
  end;
end;

procedure ResetAudioPlayback(
  WaveOut: HWAVEOUT;
  var AudioPlaybackActive: Boolean;
  AudioBuffers: TList<PAudioWaveBuffer>
);
begin
  AudioPlaybackActive := False;

  if WaveOut <> 0 then
  begin
    SetAudioOutputVolume(WaveOut, 0);
    waveOutReset(WaveOut);
  end;

  ReleaseAudioBuffers(WaveOut, AudioBuffers);
end;

end.
