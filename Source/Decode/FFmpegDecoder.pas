unit FFmpegDecoder;

// FFmpegを使って動画/音声ファイルを開き、映像フレームやPCM音声を読み出すデコーダ本体ユニット。
// AviUtl2入力プラグイン側から使う高レベルなopen/read/seek処理を担当する。

interface

uses
  Winapi.Windows, Winapi.MMSystem, System.SysUtils, System.Generics.Collections,
  System.Diagnostics, Vcl.Graphics, FFmpegDecoderTypes, FFmpegDecoderContext;

type
  // FFmpegデコード処理で発生した例外を表すクラス。
  EFFmpegDecoder = class(Exception);

  // 1つの入力ファイルに対するFFmpegリソースとデコード状態を管理するクラス。
  TFFmpegDecoder = class
  private
    FFileName            : string;                  // 現在開いている動画ファイル名
    FFormatContext       : Pointer;                 // avformatで開いた入力コンテキスト
    FCodecContext        : Pointer;                 // avcodecで開いたデコードコンテキスト
    FStream              : Pointer;                 // 対象の映像ストリーム
    FStreamIndex         : Integer;                 // 対象の映像ストリーム番号
    FAudioCodecContext   : Pointer;                 // 音声用デコードコンテキスト
    FAudioStream         : Pointer;                 // 対象の音声ストリーム
    FAudioStreamIndex    : Integer;                 // 対象の音声ストリーム番号
    FAudioFrame          : Pointer;                 // 音声デコードに再利用するAVFrame
    FSwrContext          : Pointer;                 // PCM変換用swresampleコンテキスト
    FWaveOut             : HWAVEOUT;                // デバッグ用音声出力
    FAudioPlaybackActive : Boolean;                 // 音声出力中かどうか
    FAudioBuffers        : TList<PAudioWaveBuffer>; // waveOut完了待ちのPCMバッファ
    FAudioStats          : TAudioPlaybackStats;     // 音声デコード確認用の数値
    FDecodeStats         : TDecodeLoadStats;        // デコード負荷確認用の数値
    FPacket              : Pointer;                 // 読み込みに再利用するAVPacket
    FFrame               : Pointer;                 // デコードに再利用するAVFrame
    FTransferFrame       : Pointer;                 // QSVなどのHW frameをCPUへ転送するAVFrame
    FQsvDeviceContext    : Pointer;                 // QSV device context
    FVideoDecoderName    : string;                  // 実際に開いた映像デコーダ名
    FVideoUsesQsv        : Boolean;                 // QSV decoderを使っているかどうか
    FInfo                : TVideoInfo;              // 現在開いている動画の基本情報
    FDirectSwsContext    : Pointer;                 // AviUtl2バッファ直接出力用の色変換コンテキスト
    FDirectSwsSrcWidth   : Integer;                 // 直接出力用swsの入力幅
    FDirectSwsSrcHeight  : Integer;                 // 直接出力用swsの入力高さ
    FDirectSwsSrcFormat  : Integer;                 // 直接出力用swsの入力ピクセル形式
    FDirectSwsDstFormat  : Integer;                 // 直接出力用swsの出力ピクセル形式
    FContext             : TFFmpegDecoderContext;   // サブユニットへ渡すデコード状態
    // 現在のフィールド状態をContextへ反映する
    procedure SyncContextFromFields;
    // Context側で解放/更新されたリソースポインタをフィールドへ戻す
    procedure SyncFieldsFromContext;
    // 映像デコード負荷の統計を更新する
    procedure UpdateVideoLoadStats(ElapsedMs: Double);
    // 映像処理時間をdecode/transfer/convertへ分けて統計更新する
    procedure UpdateVideoStageStats(TotalMs, DecodeMs, TransferMs, ConvertMs: Double);
  public
    // デコーダインスタンスを初期化する
    constructor Create;
    // 開いている動画を閉じてインスタンスを破棄する
    destructor Destroy; override;
    // 保持しているFFmpegリソースを解放する
    procedure Close;
    // 動画を開いてデコード可能な状態にする
    function Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
    function DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload;
    // 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
    function DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームを24bit BGRバッファへ直接変換する
    function DecodeFrameToBgr24(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをYUY2バッファへ直接変換する
    function DecodeFrameToYuy2(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをI420バッファへ直接変換する
    function DecodeFrameToI420(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをYC48バッファへ直接変換する
    function DecodeFrameToYc48(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードする
    function DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードして32bit BGRxバッファへ直接変換する
    function DecodeNextFrameToBgrx32(Buffer: Pointer; BufferStride: Integer; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードし、必要な場合だけ32bit BGRxバッファへ変換する
    function DecodeNextFrameToBgrx32Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードし、必要な場合だけ24bit BGRバッファへ変換する
    function DecodeNextFrameToBgr24Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードし、必要な場合だけYUY2バッファへ変換する
    function DecodeNextFrameToYuy2Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードし、必要な場合だけI420バッファへ変換する
    function DecodeNextFrameToI420Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードし、必要な場合だけYC48バッファへ変換する
    function DecodeNextFrameToYc48Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 開いているファイルの音声を指定サンプル数までPCM16 stereo 48kHzへ順次デコードする
    function DecodeAudioPcm16Stereo48kUntil(TargetSampleCount: Integer; var Pcm: TBytes; var SampleCount: Integer; out Finished: Boolean; out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を開始する
    function StartAudioPlayback(out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を停止する
    procedure StopAudioPlayback;
    // 一時デコーダで動画情報だけを読む
    class function ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean; static;
    // 一時デコーダで指定位置のフレームだけを読む
    class function DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload; static;
    property Info: TVideoInfo read FInfo;
    property AudioStats: TAudioPlaybackStats read FAudioStats;
    property DecodeStats: TDecodeLoadStats read FDecodeStats;
    property FileName: string read FFileName;
  end;

implementation

uses
  FFmpegApi, FFmpegAudioOpen, FFmpegDecoderAudioPlayback, FFmpegDecoderAudioRead,
  FFmpegDecodeStats, FFmpegDecoderNextBgr24, FFmpegDecoderNextBgrx32,
  FFmpegDecoderNextI420, FFmpegDecoderNextYuy2, FFmpegDecoderNextYc48,
  FFmpegDecoderResources, FFmpegDecoderSeekBgr24, FFmpegDecoderSeekBgrx32,
  FFmpegDecoderSeekI420, FFmpegDecoderSeekYuy2, FFmpegDecoderSeekYc48,
  FFmpegFrameConvert, FFmpegQsvDecode, FFmpegStreamInfo, PluginInputSettings;

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

// デコーダインスタンスを初期化する
constructor TFFmpegDecoder.Create;
begin
  inherited Create;
  FStreamIndex := -1;
  FAudioStreamIndex := -1;
  FWaveOut := 0;
  FAudioBuffers := TList<PAudioWaveBuffer>.Create;
  FContext := TFFmpegDecoderContext.Create;
end;

// 開いている動画を閉じてインスタンスを破棄する
destructor TFFmpegDecoder.Destroy;
begin
  Close;
  FAudioBuffers.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure TFFmpegDecoder.SyncContextFromFields;
begin
  FContext.FileName := FFileName;
  FContext.FormatContext := FFormatContext;
  FContext.CodecContext := FCodecContext;
  FContext.Stream := FStream;
  FContext.StreamIndex := FStreamIndex;
  FContext.AudioCodecContext := FAudioCodecContext;
  FContext.AudioStream := FAudioStream;
  FContext.AudioStreamIndex := FAudioStreamIndex;
  FContext.AudioFrame := FAudioFrame;
  FContext.SwrContext := FSwrContext;
  FContext.Packet := FPacket;
  FContext.Frame := FFrame;
  FContext.TransferFrame := FTransferFrame;
  FContext.QsvDeviceContext := FQsvDeviceContext;
  FContext.DirectSwsContext := FDirectSwsContext;
  FContext.DirectSwsSrcWidth := FDirectSwsSrcWidth;
  FContext.DirectSwsSrcHeight := FDirectSwsSrcHeight;
  FContext.DirectSwsSrcFormat := FDirectSwsSrcFormat;
  FContext.DirectSwsDstFormat := FDirectSwsDstFormat;
  FContext.VideoDecoderName := FVideoDecoderName;
  FContext.VideoUsesQsv := FVideoUsesQsv;
  FContext.Info := FInfo;
  FContext.DecodeStats := FDecodeStats;
end;

procedure TFFmpegDecoder.SyncFieldsFromContext;
begin
  FFileName := FContext.FileName;
  FFormatContext := FContext.FormatContext;
  FCodecContext := FContext.CodecContext;
  FStream := FContext.Stream;
  FStreamIndex := FContext.StreamIndex;
  FAudioCodecContext := FContext.AudioCodecContext;
  FAudioStream := FContext.AudioStream;
  FAudioStreamIndex := FContext.AudioStreamIndex;
  FAudioFrame := FContext.AudioFrame;
  FSwrContext := FContext.SwrContext;
  FPacket := FContext.Packet;
  FFrame := FContext.Frame;
  FTransferFrame := FContext.TransferFrame;
  FQsvDeviceContext := FContext.QsvDeviceContext;
  FDirectSwsContext := FContext.DirectSwsContext;
  FDirectSwsSrcWidth := FContext.DirectSwsSrcWidth;
  FDirectSwsSrcHeight := FContext.DirectSwsSrcHeight;
  FDirectSwsSrcFormat := FContext.DirectSwsSrcFormat;
  FDirectSwsDstFormat := FContext.DirectSwsDstFormat;
  FVideoDecoderName := FContext.VideoDecoderName;
  FVideoUsesQsv := FContext.VideoUsesQsv;
  FInfo := FContext.Info;
  FDecodeStats := FContext.DecodeStats;
end;

// 保持しているFFmpegリソースを解放する
procedure TFFmpegDecoder.Close;
begin
  StopAudioPlayback;

  SyncContextFromFields;
  ReleaseDecoderResources(FContext);
  SyncFieldsFromContext;

  FFileName := '';
  FStream := nil;
  FStreamIndex := -1;
  FVideoDecoderName := '';
  FVideoUsesQsv := False;
  FAudioStream := nil;
  FAudioStreamIndex := -1;
  FillChar(FInfo, SizeOf(FInfo), 0);
  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FillChar(FDecodeStats, SizeOf(FDecodeStats), 0);
  FAudioStats.LastPtsMs := -1;
end;

// 映像デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateVideoLoadStats(ElapsedMs: Double);
begin
  FFmpegDecodeStats.UpdateVideoLoadStats(FDecodeStats, ElapsedMs);
end;

// 映像処理時間をdecode/transfer/convertへ分けて統計更新する
procedure TFFmpegDecoder.UpdateVideoStageStats(TotalMs, DecodeMs,
  TransferMs, ConvertMs: Double);
begin
  FFmpegDecodeStats.UpdateVideoStageStats(FDecodeStats, TotalMs, DecodeMs, TransferMs, ConvertMs);
end;

// デバッグ用の音声再生を開始する
function TFFmpegDecoder.StartAudioPlayback(out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderAudioPlayback.StartAudioPlayback(FContext, FWaveOut,
    FAudioPlaybackActive, FAudioBuffers, FAudioStats, ErrorMessage);
end;

// デバッグ用の音声再生を停止する
procedure TFFmpegDecoder.StopAudioPlayback;
begin
  FFmpegDecoderAudioPlayback.StopAudioPlayback(FWaveOut, FAudioPlaybackActive,
    FAudioBuffers, FAudioStats);
end;

// 動画を開いてデコード可能な状態にする
function TFFmpegDecoder.Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  FormatContext     : PAVFormatContext;    // avformatで開く入力コンテキスト
  CodecContext      : PAVCodecContext;     // 映像デコードコンテキスト
  AudioCodecContext : PAVCodecContext;     // 音声デコードコンテキスト
  Codec             : PAVCodec;            // 映像ストリームに対応するFFmpegデコーダ
  SoftwareCodec     : PAVCodec;            // フォールバック用の通常デコーダ
  Packet            : PAVPacket;           // 読み込みに再利用するAVPacket
  Frame             : PAVFrame;            // 映像デコードに再利用するAVFrame
  TransferFrame     : PAVFrame;            // HW frameをCPUへ転送するAVFrame
  AudioFrame        : PAVFrame;            // 音声デコードに再利用するAVFrame
  SwrContext        : PSwrContext;         // PCM変換用swresampleコンテキスト
  Utf8FileName      : UTF8String;          // FFmpegへ渡すUTF-8ファイル名
  Ret               : Integer;             // FFmpeg APIの戻り値
  StreamIndex       : Integer;             // 対象の映像ストリーム番号
  AudioStreamIndex  : Integer;             // 対象の音声ストリーム番号
  Stream            : PAVStream;           // 対象の映像ストリーム
  AudioStream       : PAVStream;           // 対象の音声ストリーム
  CodecPar          : PAVCodecParameters;  // 映像ストリームのコーデック情報
  HasVideoStream    : Boolean;             // 映像ストリームがあるかどうか
  QsvDeviceContext  : PAVBufferRef;
  QsvDecoderName    : AnsiString;
  QsvErrorMessage   : string;
  OpenedWithQsv     : Boolean;
  VideoDecoderName  : string;
  DecoderMode       : TVideoDecoderMode;
  DecodeBackend     : string;
  GpuInferred       : string;
begin
  Close;
  FillChar(Info, SizeOf(Info), 0);
  ErrorMessage := '';
  Result := False;
  FormatContext := nil;
  CodecContext := nil;
  AudioCodecContext := nil;
  Packet := nil;
  Frame := nil;
  TransferFrame := nil;
  QsvDeviceContext := nil;
  AudioFrame := nil;
  SwrContext := nil;
  AudioStream := nil;
  AudioStreamIndex := -1;
  OpenedWithQsv := False;
  VideoDecoderName := '';
  DecoderMode := GetVideoDecoderMode;

  try
    TFFmpegApi.EnsureLoaded;

    Utf8FileName := UTF8String(FileName);
    Ret := TFFmpegApi.avformat_open_input(@FormatContext, PAnsiChar(Utf8FileName), nil, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avformat_find_stream_info(FormatContext, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    if FormatContext.duration > 0 then
      Info.DurationSec := FormatContext.duration / AV_TIME_BASE;
    ReadAudioInfo(FormatContext, Info);

    StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0);
    HasVideoStream := StreamIndex >= 0;
    Stream := nil;
    if HasVideoStream then
    begin
      Stream := StreamAt(FormatContext, StreamIndex);
      if not Assigned(Stream) then
      begin
        ErrorMessage := 'Video stream pointer is nil.';
        Exit;
      end;

      CodecPar := Stream.codecpar;
      if not Assigned(CodecPar) then
      begin
        ErrorMessage := 'Codec parameters pointer is nil.';
        Exit;
      end;

      SoftwareCodec := TFFmpegApi.avcodec_find_decoder(CodecPar.codec_id);
      if not Assigned(SoftwareCodec) then
      begin
        ErrorMessage := 'Decoder was not found.';
        Exit;
      end;

      Codec := nil;
      OpenedWithQsv := False;
      VideoDecoderName := 'software';
      QsvDecoderName := QsvDecoderNameForCodecId(CodecPar.codec_id);
      if (DecoderMode <> vdmSoftware) and (QsvDecoderName <> '') then
      begin
        Codec := TFFmpegApi.avcodec_find_decoder_by_name(PAnsiChar(QsvDecoderName));
        if Assigned(Codec) and CreateQsvDevice(QsvDeviceContext, QsvErrorMessage) then
        begin
          VideoDecoderName := string(QsvDecoderName);
          OpenedWithQsv := True;
        end
        else
        begin
          if not Assigned(Codec) then
            QsvErrorMessage := 'QSV decoder was not found.';
          DecodeTrace(Format('qsv_fallback file="%s" decode_mode=%s attempted_backend=qsv attempted_gpu="Intel Quick Sync" nvidia_nvdec_supported=False decoder="%s" reason="%s"',
            [FileName, VideoDecoderModeToText(DecoderMode), string(QsvDecoderName), QsvErrorMessage]));
          if DecoderMode = vdmQsv then
          begin
            ErrorMessage := QsvErrorMessage;
            if Assigned(QsvDeviceContext) then
              TFFmpegApi.av_buffer_unref(@QsvDeviceContext);
            Exit;
          end;
          Codec := nil;
          if Assigned(QsvDeviceContext) then
            TFFmpegApi.av_buffer_unref(@QsvDeviceContext);
        end;
      end;
      if (DecoderMode = vdmQsv) and (not OpenedWithQsv) then
      begin
        if QsvDecoderName = '' then
          ErrorMessage := 'QSV decoder is not supported for this codec.'
        else
          ErrorMessage := 'QSV decoder could not be opened.';
        Exit;
      end;

      if not Assigned(Codec) then
        Codec := SoftwareCodec;

      CodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
      if not Assigned(CodecContext) then
      begin
        ErrorMessage := 'avcodec_alloc_context3 failed.';
        Exit;
      end;

      Ret := TFFmpegApi.avcodec_parameters_to_context(CodecContext, CodecPar);
      if Ret < 0 then
      begin
        ErrorMessage := TFFmpegApi.ErrorText(Ret);
        Exit;
      end;

      Ret := TFFmpegApi.avcodec_open2(CodecContext, Codec, nil);
      if Ret < 0 then
      begin
        if OpenedWithQsv then
        begin
          DecodeTrace(Format('qsv_fallback file="%s" decode_mode=%s attempted_backend=qsv attempted_gpu="Intel Quick Sync" nvidia_nvdec_supported=False decoder="%s" reason="%s"',
            [FileName, VideoDecoderModeToText(DecoderMode), VideoDecoderName, TFFmpegApi.ErrorText(Ret)]));
          if DecoderMode = vdmQsv then
          begin
            ErrorMessage := TFFmpegApi.ErrorText(Ret);
            TFFmpegApi.avcodec_free_context(@CodecContext);
            if Assigned(QsvDeviceContext) then
              TFFmpegApi.av_buffer_unref(@QsvDeviceContext);
            Exit;
          end;
          TFFmpegApi.avcodec_free_context(@CodecContext);
          if Assigned(QsvDeviceContext) then
            TFFmpegApi.av_buffer_unref(@QsvDeviceContext);
          Codec := SoftwareCodec;
          CodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
          if not Assigned(CodecContext) then
          begin
            ErrorMessage := 'avcodec_alloc_context3 failed.';
            Exit;
          end;
          Ret := TFFmpegApi.avcodec_parameters_to_context(CodecContext, CodecPar);
          if Ret < 0 then
          begin
            ErrorMessage := TFFmpegApi.ErrorText(Ret);
            Exit;
          end;
          Ret := TFFmpegApi.avcodec_open2(CodecContext, Codec, nil);
          if Ret < 0 then
          begin
            ErrorMessage := TFFmpegApi.ErrorText(Ret);
            Exit;
          end;
          OpenedWithQsv := False;
          VideoDecoderName := 'software';
        end
        else
        begin
          ErrorMessage := TFFmpegApi.ErrorText(Ret);
          Exit;
        end;
      end;

      Frame := TFFmpegApi.av_frame_alloc();
      if Frame = nil then
      begin
        ErrorMessage := 'Failed to allocate video frame.';
        Exit;
      end;

      TransferFrame := TFFmpegApi.av_frame_alloc();
      if TransferFrame = nil then
      begin
        ErrorMessage := 'Failed to allocate transfer frame.';
        Exit;
      end;

      if OpenedWithQsv then
      begin
        DecodeBackend := 'qsv';
        GpuInferred := 'Intel Quick Sync';
      end
      else
      begin
        DecodeBackend := 'software';
        GpuInferred := 'none';
      end;

      DecodeTrace(Format('video_decoder file="%s" decode_mode=%s decode_backend=%s gpu_inferred="%s" nvidia_nvdec_supported=False decoder="%s" qsv=%s codec_id=%d',
        [FileName, VideoDecoderModeToText(DecoderMode), DecodeBackend, GpuInferred,
         VideoDecoderName, BoolToStr(OpenedWithQsv, True), CodecPar.codec_id]));

      Info.Width := CodecPar.width;
      Info.Height := CodecPar.height;
      Info.FpsText := RationalToText(Stream.avg_frame_rate);
      Info.Fps := RationalToDouble(Stream.avg_frame_rate);

      if (Info.Width <= 0) or (Info.Height <= 0) then
      begin
        ErrorMessage := 'Video stream was found, but size could not be read.';
        Exit;
      end;
    end
    else if not Info.Audio.Present then
    begin
      ErrorMessage := 'No supported video or audio stream was found.';
      Exit;
    end;

    OpenAudioDecoder(FormatContext, Info, AudioCodecContext, AudioStream, AudioStreamIndex, AudioFrame, SwrContext);
    if (not HasVideoStream) and ((not Info.Audio.Present) or (Info.Audio.OpenError <> '')) then
    begin
      ErrorMessage := 'Audio decoder is not open. ' + Info.Audio.OpenError;
      Exit;
    end;

    Packet := TFFmpegApi.av_packet_alloc();
    if Packet = nil then
    begin
      ErrorMessage := 'Failed to allocate packet.';
      Exit;
    end;

    FFileName := FileName;
    FFormatContext := FormatContext;
    FCodecContext := CodecContext;
    FStream := Stream;
    FStreamIndex := StreamIndex;
    FAudioCodecContext := AudioCodecContext;
    FAudioStream := AudioStream;
    FAudioStreamIndex := AudioStreamIndex;
    FAudioFrame := AudioFrame;
    FSwrContext := SwrContext;
    FPacket := Packet;
    FFrame := Frame;
    FTransferFrame := TransferFrame;
    FQsvDeviceContext := QsvDeviceContext;
    FVideoDecoderName := VideoDecoderName;
    FVideoUsesQsv := OpenedWithQsv;
    FInfo := Info;

    FormatContext := nil;
    CodecContext := nil;
    AudioCodecContext := nil;
    Packet := nil;
    Frame := nil;
    TransferFrame := nil;
    QsvDeviceContext := nil;
    AudioFrame := nil;
    SwrContext := nil;
    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;

  if Assigned(Frame) then
    TFFmpegApi.av_frame_free(@Frame);
  if Assigned(TransferFrame) then
    TFFmpegApi.av_frame_free(@TransferFrame);
  if Assigned(QsvDeviceContext) then
    TFFmpegApi.av_buffer_unref(@QsvDeviceContext);
  if Assigned(Packet) then
    TFFmpegApi.av_packet_free(@Packet);
  if Assigned(SwrContext) then
    TFFmpegApi.swr_free(@SwrContext);
  if Assigned(AudioFrame) then
    TFFmpegApi.av_frame_free(@AudioFrame);
  if Assigned(AudioCodecContext) then
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
  if Assigned(CodecContext) then
    TFFmpegApi.avcodec_free_context(@CodecContext);
  if Assigned(FormatContext) then
    TFFmpegApi.avformat_close_input(@FormatContext);
end;

// 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
function TFFmpegDecoder.DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // デコード結果を受け取るAVFrame
  Stream: PAVStream; // 対象の映像ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  TargetTs: Int64; // 目的位置のストリーム時間軸PTS
  Stopwatch: TStopwatch; // デコード負荷測定用タイマー
begin
  ErrorMessage := '';
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, FStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if FAudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(FAudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            CopyFrameToBitmap(Frame, Bitmap);
            Stopwatch.Stop;
            UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
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

// 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderSeekBgrx32.DecodeFrameToBgrx32(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

// 指定ミリ秒位置へシークしてフレームを24bit BGRバッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToBgr24(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderSeekBgr24.DecodeFrameToBgr24(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

// 指定ミリ秒位置へシークしてフレームをYUY2バッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToYuy2(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderSeekYuy2.DecodeFrameToYuy2(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

// 指定ミリ秒位置へシークしてフレームをI420バッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToI420(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderSeekI420.DecodeFrameToI420(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

// 指定ミリ秒位置へシークしてフレームをYC48バッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToYc48(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderSeekYc48.DecodeFrameToYc48(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

// 現在位置から次の映像フレームを順方向デコードする
function TFFmpegDecoder.DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // デコード結果を受け取るAVFrame
  Stream: PAVStream; // 対象の映像ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  Stopwatch: TStopwatch; // デコード負荷測定用タイマー
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = FAudioStreamIndex then
        begin
          Continue;
        end;

        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBitmap(Frame, Bitmap);
          Stopwatch.Stop;
          UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 現在位置から次の映像フレームを順方向デコードして32bit BGRxバッファへ直接変換する
function TFFmpegDecoder.DecodeNextFrameToBgrx32(Buffer: Pointer; BufferStride: Integer; out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  Result := DecodeNextFrameToBgrx32Optional(Buffer, BufferStride, True, PositionMs, ErrorMessage);
end;

function TFFmpegDecoder.DecodeNextFrameToBgrx32Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderNextBgrx32.DecodeNextFrameToBgrx32Optional(
    FContext, Buffer, BufferStride, ConvertFrame, PositionMs, ErrorMessage);
  SyncFieldsFromContext;
end;

function TFFmpegDecoder.DecodeNextFrameToBgr24Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderNextBgr24.DecodeNextFrameToBgr24Optional(
    FContext, Buffer, BufferStride, ConvertFrame, PositionMs, ErrorMessage);
  SyncFieldsFromContext;
end;

function TFFmpegDecoder.DecodeNextFrameToYuy2Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderNextYuy2.DecodeNextFrameToYuy2Optional(
    FContext, Buffer, BufferStride, ConvertFrame, PositionMs, ErrorMessage);
  SyncFieldsFromContext;
end;

function TFFmpegDecoder.DecodeNextFrameToI420Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderNextI420.DecodeNextFrameToI420Optional(
    FContext, Buffer, BufferStride, ConvertFrame, PositionMs, ErrorMessage);
  SyncFieldsFromContext;
end;

function TFFmpegDecoder.DecodeNextFrameToYc48Optional(Buffer: Pointer; BufferStride: Integer; ConvertFrame: Boolean; out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderNextYc48.DecodeNextFrameToYc48Optional(
    FContext, Buffer, BufferStride, ConvertFrame, PositionMs, ErrorMessage);
  SyncFieldsFromContext;
end;

// 開いているファイルの音声を指定サンプル数までPCM16 stereo 48kHzへ順次デコードする
function TFFmpegDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount: Integer; var Pcm: TBytes; var SampleCount: Integer; out Finished: Boolean; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderAudioRead.DecodeAudioPcm16Stereo48kUntil(
    FContext,
    TargetSampleCount,
    Pcm,
    SampleCount,
    Finished,
    ErrorMessage
  );
end;

// 一時デコーダで動画情報だけを読む
class function TFFmpegDecoder.ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder; // 情報取得だけに使う一時デコーダ
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

// 一時デコーダで指定位置のフレームだけを読む
class function TFFmpegDecoder.DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder; // フレーム取得だけに使う一時デコーダ
  Info: TVideoInfo; // 一時デコーダで取得する動画情報
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
    if Result then
      Result := Decoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

end.
