unit FFmpegAudioTempo;

// FFmpeg avfilter の atempo を使い、48kHz/stereo/s16 PCM をピッチ保持寄りで時間圧縮する。
// 入出力は VideoMiner の waveOut 経路と同じ packed s16 stereo に固定する。

interface

uses
  System.SysUtils;

function TempoPcm16Stereo48k(const InputPcm: TBytes; Rate: Double;
  out OutputPcm: TBytes; out OutputSampleCount: Integer;
  out ErrorMessage: string): Boolean;

implementation

uses
  System.Math, FFmpegApi;

const
  TEMPO_SAMPLE_RATE = 48000;
  TEMPO_CHANNELS = 2;
  TEMPO_BYTES_PER_SAMPLE = SizeOf(SmallInt);

procedure AppendFramePcm(Frame: PAVFrame; var OutputPcm: TBytes;
  var OutputSampleCount: Integer);
var
  ByteCount: Integer;
  OldBytes: Integer;
begin
  if (Frame = nil) or (Frame.data[0] = nil) or (Frame.nb_samples <= 0) then
    Exit;

  ByteCount := Frame.nb_samples * TEMPO_CHANNELS * TEMPO_BYTES_PER_SAMPLE;
  OldBytes := Length(OutputPcm);
  SetLength(OutputPcm, OldBytes + ByteCount);
  Move(Frame.data[0]^, OutputPcm[OldBytes], ByteCount);
  Inc(OutputSampleCount, Frame.nb_samples);
end;

function NewAudioFrame(const Pcm: TBytes; SampleCount: Integer;
  out Frame: PAVFrame; out ErrorMessage: string): Boolean;
var
  ByteCount: Integer;
  Ret: Integer;
begin
  Result := False;
  Frame := nil;
  ErrorMessage := '';

  Frame := TFFmpegApi.av_frame_alloc();
  if Frame = nil then
  begin
    ErrorMessage := 'av_frame_alloc failed.';
    Exit;
  end;

  Frame.nb_samples := SampleCount;
  Frame.format := AV_SAMPLE_FMT_S16;
  Frame.sample_rate := TEMPO_SAMPLE_RATE;
  TFFmpegApi.av_channel_layout_default(@Frame.ch_layout, TEMPO_CHANNELS);

  Ret := TFFmpegApi.av_frame_get_buffer(Frame, 0);
  if Ret < 0 then
  begin
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
    TFFmpegApi.av_frame_free(@Frame);
    Exit;
  end;

  Ret := TFFmpegApi.av_frame_make_writable(Frame);
  if Ret < 0 then
  begin
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
    TFFmpegApi.av_frame_free(@Frame);
    Exit;
  end;

  ByteCount := SampleCount * TEMPO_CHANNELS * TEMPO_BYTES_PER_SAMPLE;
  if (ByteCount > 0) and (Length(Pcm) >= ByteCount) then
    Move(Pcm[0], Frame.data[0]^, ByteCount);

  Result := True;
end;

function CreateTempoGraph(Rate: Double; out Graph: PAVFilterGraph;
  out SourceContext, SinkContext: PAVFilterContext;
  out ErrorMessage: string): Boolean;
var
  Args: AnsiString;
  Ret: Integer;
  SourceFilter: PAVFilter;
  SinkFilter: PAVFilter;
  SinkName: AnsiString;
  SourceName: AnsiString;
  TempoContext: PAVFilterContext;
  TempoFilter: PAVFilter;
  TempoName: AnsiString;
  TempoText: AnsiString;
begin
  Result := False;
  Graph := nil;
  SourceContext := nil;
  SinkContext := nil;
  TempoContext := nil;
  ErrorMessage := '';

  SourceName := 'abuffer';
  TempoName := 'atempo';
  SinkName := 'abuffersink';
  SourceFilter := TFFmpegApi.avfilter_get_by_name(PAnsiChar(SourceName));
  TempoFilter := TFFmpegApi.avfilter_get_by_name(PAnsiChar(TempoName));
  SinkFilter := TFFmpegApi.avfilter_get_by_name(PAnsiChar(SinkName));
  if (SourceFilter = nil) or (TempoFilter = nil) or (SinkFilter = nil) then
  begin
    ErrorMessage := 'Required audio filters are not available.';
    Exit;
  end;

  Graph := TFFmpegApi.avfilter_graph_alloc();
  if Graph = nil then
  begin
    ErrorMessage := 'avfilter_graph_alloc failed.';
    Exit;
  end;

  Args := AnsiString('time_base=1/48000:sample_rate=48000:sample_fmt=s16:channel_layout=stereo');
  Ret := TFFmpegApi.avfilter_graph_create_filter(@SourceContext, SourceFilter,
    'tempo_in', PAnsiChar(Args), nil, Graph);
  if Ret < 0 then
  begin
    ErrorMessage := 'abuffer: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  TempoText := AnsiString(StringReplace(Format('%.6f', [Rate]), ',', '.',
    [rfReplaceAll]));
  Ret := TFFmpegApi.avfilter_graph_create_filter(@TempoContext, TempoFilter,
    'tempo', PAnsiChar(TempoText), nil, Graph);
  if Ret < 0 then
  begin
    ErrorMessage := 'atempo: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  Ret := TFFmpegApi.avfilter_graph_create_filter(@SinkContext, SinkFilter,
    'tempo_out', nil, nil, Graph);
  if Ret < 0 then
  begin
    ErrorMessage := 'abuffersink: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  Ret := TFFmpegApi.avfilter_link(SourceContext, 0, TempoContext, 0);
  if Ret < 0 then
  begin
    ErrorMessage := 'link source->tempo: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  Ret := TFFmpegApi.avfilter_link(TempoContext, 0, SinkContext, 0);
  if Ret < 0 then
  begin
    ErrorMessage := 'link tempo->sink: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  Ret := TFFmpegApi.avfilter_graph_config(Graph, nil);
  if Ret < 0 then
  begin
    ErrorMessage := 'graph config: ' + TFFmpegApi.ErrorText(Ret);
    Exit;
  end;

  Result := True;
end;

function TempoPcm16Stereo48k(const InputPcm: TBytes; Rate: Double;
  out OutputPcm: TBytes; out OutputSampleCount: Integer;
  out ErrorMessage: string): Boolean;
var
  Graph: PAVFilterGraph;
  InputFrame: PAVFrame;
  OutputFrame: PAVFrame;
  Ret: Integer;
  SampleCount: Integer;
  SinkContext: PAVFilterContext;
  SourceContext: PAVFilterContext;
begin
  Result := False;
  OutputPcm := nil;
  OutputSampleCount := 0;
  ErrorMessage := '';
  Graph := nil;
  InputFrame := nil;
  OutputFrame := nil;

  SampleCount := Length(InputPcm) div
    (TEMPO_CHANNELS * TEMPO_BYTES_PER_SAMPLE);
  if SampleCount <= 0 then
  begin
    Result := True;
    Exit;
  end;

  if SameValue(Rate, 1.0) then
  begin
    OutputPcm := Copy(InputPcm);
    OutputSampleCount := SampleCount;
    Result := True;
    Exit;
  end;

  try
    try
      TFFmpegApi.EnsureLoaded;
      if not CreateTempoGraph(Rate, Graph, SourceContext, SinkContext,
        ErrorMessage) then
        Exit;

      if not NewAudioFrame(InputPcm, SampleCount, InputFrame,
        ErrorMessage) then
        Exit;

      Ret := TFFmpegApi.av_buffersrc_add_frame_flags(SourceContext,
        InputFrame, AV_BUFFERSRC_FLAG_KEEP_REF);
      if Ret < 0 then
      begin
        ErrorMessage := 'buffersrc add frame: ' + TFFmpegApi.ErrorText(Ret);
        Exit;
      end;

      Ret := TFFmpegApi.av_buffersrc_add_frame_flags(SourceContext, nil, 0);
      if Ret < 0 then
      begin
        ErrorMessage := 'buffersrc flush: ' + TFFmpegApi.ErrorText(Ret);
        Exit;
      end;

    OutputFrame := TFFmpegApi.av_frame_alloc();
      if OutputFrame = nil then
      begin
        ErrorMessage := 'av_frame_alloc output failed.';
        Exit;
      end;

      while True do
      begin
        Ret := TFFmpegApi.av_buffersink_get_frame(SinkContext, OutputFrame);
        if Ret = AVERROR_EOF then
          Break;
        if Ret = AVERROR_EAGAIN then
          Break;
        if Ret < 0 then
        begin
          ErrorMessage := 'buffersink get frame: ' + TFFmpegApi.ErrorText(Ret);
          Exit;
        end;

        AppendFramePcm(OutputFrame, OutputPcm, OutputSampleCount);
        TFFmpegApi.av_frame_unref(OutputFrame);
      end;

      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  finally
    if OutputFrame <> nil then
      TFFmpegApi.av_frame_free(@OutputFrame);
    if InputFrame <> nil then
      TFFmpegApi.av_frame_free(@InputFrame);
    if Graph <> nil then
      TFFmpegApi.avfilter_graph_free(@Graph);
  end;
end;

end.
