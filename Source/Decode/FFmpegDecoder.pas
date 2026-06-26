unit FFmpegDecoder;

// FFmpegを使って動画/音声ファイルを開き、映像フレームやPCM音声を読み出すデコーダ本体ユニット。
// High-level open/read/seek operations used by the viewer.

interface

uses
  Winapi.Windows, Winapi.MMSystem, System.SysUtils, System.Generics.Collections,
  System.SyncObjs, Vcl.Graphics, FFmpegDecoderTypes, FFmpegDecoderContext;

type
  // FFmpegデコード処理で発生した例外を表すクラス。
  EFFmpegDecoder = class(Exception);

  // 1つの入力ファイルに対するFFmpegリソースとデコード状態を管理するクラス。
  TFFmpegDecoder = class
  private
    FFileName            : string;                  // 現在開いている動画ファイル名
    FInputBuffer         : TObject;                 // custom AVIO 用の一時前方読み込みバッファ
    FFormatContext       : Pointer;                 // avformatで開いた入力コンテキスト
    FCodecContext        : Pointer;                 // avcodecで開いたデコードコンテキスト
    FStream              : Pointer;                 // 対象の映像ストリーム
    FStreamIndex         : Integer;                 // 対象の映像ストリーム番号
    FAudioCodecContext   : Pointer;                 // 音声用デコードコンテキスト
    FAudioStream         : Pointer;                 // 対象の音声ストリーム
    FAudioStreamIndex    : Integer;                 // 対象の音声ストリーム番号
    FAudioFrame          : Pointer;                 // 音声デコードに再利用するAVFrame
    FSwrContext          : Pointer;                 // PCM変換用swresampleコンテキスト
    FWaveOut             : HWAVEOUT;                // audio output handle
    FAudioPlaybackActive : Boolean;                 // 音声出力中かどうか
    FAudioBuffers        : TList<PAudioWaveBuffer>; // waveOut完了待ちのPCMバッファ
    FPacket              : Pointer;                 // 読み込みに再利用するAVPacket
    FFrame               : Pointer;                 // デコードに再利用するAVFrame
    FTransferFrame       : Pointer;                 // QSVなどのHW frameをCPUへ転送するAVFrame
    FQsvDeviceContext    : Pointer;                 // QSV device context
    FVideoDecoderName    : string;                  // 実際に開いた映像デコーダ名
    FVideoUsesQsv        : Boolean;                 // QSV decoderを使っているかどうか
    FInfo                : TVideoInfo;              // 現在開いている動画の基本情報
    FRole                : TFFmpegDecoderRole;      // この decoder の用途
    FDirectSwsContext    : Pointer;                 // VideoMinerバッファ直接出力用の色変換コンテキスト
    FDirectSwsSrcWidth   : Integer;                 // 直接出力用swsの入力幅
    FDirectSwsSrcHeight  : Integer;                 // 直接出力用swsの入力高さ
    FDirectSwsSrcFormat  : Integer;                 // 直接出力用swsの入力ピクセル形式
    FDirectSwsDstFormat  : Integer;                 // 直接出力用swsの出力ピクセル形式
    FDecodeGeneration    : Int64;                   // seek/next decode でデコーダ位置が進んだ世代番号
    FContext             : TFFmpegDecoderContext;   // サブユニットへ渡すデコード状態
    // 現在のフィールド状態をContextへ反映する
    procedure SyncContextFromFields;
    // Context側で解放/更新されたリソースポインタをフィールドへ戻す
    procedure SyncFieldsFromContext;
  public
    // デコーダインスタンスを初期化する
    constructor Create;
    // 開いている動画を閉じてインスタンスを破棄する
    destructor Destroy; override;
    // 保持しているFFmpegリソースを解放する
    procedure Close;
    // 指定ファイルをデコード可能な状態で開いているか確認する
    function IsOpenForFile(const FileName: string): Boolean;
    // 動画を開いてデコード可能な状態にする
    function Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
    function DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload;
    // 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
    function DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    function DecodeFrameToBgrx32Fast(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
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
    function SeekAudioToMs(PositionMs: Integer; out ErrorMessage: string): Boolean;
    // �����Y�
    function StartAudioPlayback(out ErrorMessage: string): Boolean;
    function QueueAudioPcm16Stereo48k(const Pcm: TBytes; out ErrorMessage: string): Boolean;
    function QueuedAudioSampleCount: Integer;
    function PlayedAudioSampleCount: Integer;
    procedure SetAudioOutputVolume(VolumePercent: Integer);
    // waveOut ハンドルを保持したまま、投入済み音声だけを止める
    procedure ResetAudioPlayback;
    // ���\bY�
    procedure StopAudioPlayback;
    // 一時デコーダで動画情報だけを読む
    class function ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean; static;
    // 一時デコーダで指定位置のフレームだけを読む
    class function DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload; static;
    property DecodeGeneration: Int64 read FDecodeGeneration;
    property Info: TVideoInfo read FInfo;
    property FileName: string read FFileName;
    property Role: TFFmpegDecoderRole read FRole write FRole;
  end;

implementation

uses
  System.Diagnostics,
  FFmpegApi, FFmpegAudioOpen, FFmpegDecoderAudioPlayback, FFmpegDecoderAudioRead, FFmpegDecoderNextBgr24, FFmpegDecoderNextBgrx32,
  FFmpegDecoderNextI420, FFmpegDecoderNextYuy2, FFmpegDecoderNextYc48,
  FFmpegDecoderResources, FFmpegDecoderSeekBgr24, FFmpegDecoderSeekBgrx32,
  FFmpegDecoderSeekI420, FFmpegDecoderSeekYuy2, FFmpegDecoderSeekYc48,
  FFmpegForwardReadBuffer, FFmpegFrameConvert, FFmpegQsvDecode, FFmpegStreamInfo,
  VideoMinerDebugLog, VideoMinerSettings;

var
  GlobalDecoderOpenSequence: Int64;

// pixel format 名から alpha channel/plane を持つ形式か推定する
function PixelFormatHasAlpha(const PixelFormatText: string): Boolean;
var
  LowerName: string;
begin
  LowerName := LowerCase(PixelFormatText);
  Result := (Pos('yuva', LowerName) = 1) or
    (Pos('rgba', LowerName) = 1) or
    (Pos('bgra', LowerName) = 1) or
    (Pos('argb', LowerName) = 1) or
    (Pos('abgr', LowerName) = 1) or
    (Pos('gbrap', LowerName) = 1) or
    (Pos('ya', LowerName) = 1);
end;

function ShouldTryQsvDecoder(DecoderMode: TVideoDecoderMode;
  CodecPar: PAVCodecParameters): Boolean;
var
  PixelCount: Int64;
begin
  Result := False;
  if CodecPar = nil then
    Exit;

  case DecoderMode of
    vdmQsv:
      Exit(True);
    vdmSoftware:
      Exit(False);
  end;

  PixelCount := Int64(CodecPar.width) * Int64(CodecPar.height);
  case CodecPar.codec_id of
    AV_CODEC_ID_H264:
      Result := PixelCount >= Int64(3840) * Int64(2160);
    AV_CODEC_ID_HEVC, AV_CODEC_ID_AV1:
      Result := PixelCount >= Int64(1920) * Int64(1080);
    AV_CODEC_ID_VP9:
      Result := PixelCount >= Int64(2560) * Int64(1440);
  else
    Result := False;
  end;
end;

// デコーダインスタンスを初期化する
constructor TFFmpegDecoder.Create;
begin
  inherited Create;
  FRole := fdrAuxiliary;
  FStreamIndex := -1;
  FAudioStreamIndex := -1;
  FWaveOut := 0;
  FAudioBuffers := TList<PAudioWaveBuffer>.Create;
  FContext := TFFmpegDecoderContext.Create;
  FContext.AudioDiscardUntilSample := -1;
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
  FContext.InputBuffer := FInputBuffer;
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
end;

procedure TFFmpegDecoder.SyncFieldsFromContext;
begin
  FFileName := FContext.FileName;
  FInputBuffer := FContext.InputBuffer;
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
end;

// 保持しているFFmpegリソースを解放する
procedure TFFmpegDecoder.Close;
begin
  StopAudioPlayback;

  SyncContextFromFields;
  ReleaseDecoderResources(FContext);
  SyncFieldsFromContext;

  FFileName := '';
  FInputBuffer := nil;
  FStream := nil;
  FStreamIndex := -1;
  FVideoDecoderName := '';
  FVideoUsesQsv := False;
  FAudioStream := nil;
  FAudioStreamIndex := -1;
  FDecodeGeneration := 0;
  FillChar(FInfo, SizeOf(FInfo), 0);
end;

// 指定ファイルをデコード可能な状態で開いているか確認する
function TFFmpegDecoder.IsOpenForFile(const FileName: string): Boolean;
begin
  Result := (FFormatContext <> nil) and (FFileName <> '') and
    SameText(ExpandFileName(FFileName), ExpandFileName(FileName));
end;



// �����Y�
function TFFmpegDecoder.StartAudioPlayback(out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderAudioPlayback.StartAudioPlayback(FContext, FWaveOut,
    FAudioPlaybackActive, FAudioBuffers, ErrorMessage);
end;

function TFFmpegDecoder.QueueAudioPcm16Stereo48k(const Pcm: TBytes; out ErrorMessage: string): Boolean;
begin
  Result := FFmpegDecoderAudioPlayback.QueueAudioPcm16Stereo48k(FWaveOut,
    FAudioPlaybackActive, FAudioBuffers, Pcm, ErrorMessage);
end;

function TFFmpegDecoder.QueuedAudioSampleCount: Integer;
begin
  Result := FFmpegDecoderAudioPlayback.QueuedAudioSampleCount(FWaveOut,
    FAudioBuffers);
end;

function TFFmpegDecoder.PlayedAudioSampleCount: Integer;
begin
  Result := FFmpegDecoderAudioPlayback.PlayedAudioSampleCount(FWaveOut);
end;

procedure TFFmpegDecoder.SetAudioOutputVolume(VolumePercent: Integer);
begin
  FFmpegDecoderAudioPlayback.SetAudioOutputVolume(FWaveOut, VolumePercent);
end;

procedure TFFmpegDecoder.ResetAudioPlayback;
begin
  FFmpegDecoderAudioPlayback.ResetAudioPlayback(FWaveOut, FAudioPlaybackActive,
    FAudioBuffers);
end;

// ���\bY�
procedure TFFmpegDecoder.StopAudioPlayback;
begin
  FFmpegDecoderAudioPlayback.StopAudioPlayback(FWaveOut, FAudioPlaybackActive,
    FAudioBuffers);
end;

// 動画を開いてデコード可能な状態にする
function TFFmpegDecoder.Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  FormatContext     : PAVFormatContext;    // avformatで開く入力コンテキスト
  InputBuffer       : TFFmpegForwardReadBuffer; // custom AVIO 用の一時読み込みバッファ
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
  OpenSequence      : Int64;
  UseForwardBuffer  : Boolean;
{$IFDEF DEBUG}
  ApiLoadMs         : Double;
  AudioOpenMs       : Double;
  CodecOpenMs       : Double;
  FindStreamMs      : Double;
  FormatOpenMs      : Double;
  StreamInfoMs      : Double;
  StepWatch         : TStopwatch;
  TotalWatch        : TStopwatch;
{$ENDIF}
begin
{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  Close;
  FillChar(Info, SizeOf(Info), 0);
  ErrorMessage := '';
  Result := False;
  FormatContext := nil;
  InputBuffer := nil;
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
  OpenSequence := TInterlocked.Increment(GlobalDecoderOpenSequence);
  UseForwardBuffer := VideoMinerForwardReadBufferEnabled(FRole);

  try
    TFFmpegApi.EnsureLoaded;
{$IFDEF DEBUG}
    ApiLoadMs := StepWatch.Elapsed.TotalMilliseconds;
    StepWatch := TStopwatch.StartNew;
{$ENDIF}

    WriteVideoMinerSlowLog(Format(
      'decoder_open_begin seq=%d role=%s file="%s" drive="%s" buffer_mode=%s buffer_enabled=%s',
      [OpenSequence, FFmpegDecoderRoleText(FRole), ExtractFileName(FileName),
       ExtractFileDrive(FileName), VideoMinerForwardReadBufferModeText,
       BoolToStr(UseForwardBuffer, True)]));

    if UseForwardBuffer then
    begin
      InputBuffer := TFFmpegForwardReadBuffer.Create(FRole, OpenSequence);
      if not InputBuffer.Open(FileName, ErrorMessage) then
        Exit;
      if not InputBuffer.CreateAvioContext(ErrorMessage) then
        Exit;
      FormatContext := TFFmpegApi.avformat_alloc_context();
      if FormatContext = nil then
      begin
        ErrorMessage := 'avformat_alloc_context failed.';
        Exit;
      end;
      FormatContext.pb := InputBuffer.AvioContext;
      Ret := TFFmpegApi.avformat_open_input(@FormatContext, nil, nil, nil);
    end
    else
    begin
      Utf8FileName := UTF8String(FileName);
      Ret := TFFmpegApi.avformat_open_input(@FormatContext, PAnsiChar(Utf8FileName), nil, nil);
    end;
{$IFDEF DEBUG}
    FormatOpenMs := StepWatch.Elapsed.TotalMilliseconds;
    StepWatch := TStopwatch.StartNew;
{$ENDIF}
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avformat_find_stream_info(FormatContext, nil);
{$IFDEF DEBUG}
    StreamInfoMs := StepWatch.Elapsed.TotalMilliseconds;
    StepWatch := TStopwatch.StartNew;
{$ENDIF}
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    if FormatContext.duration > 0 then
      Info.DurationSec := FormatContext.duration / AV_TIME_BASE;
    ReadAudioInfo(FormatContext, Info);

    StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0);
{$IFDEF DEBUG}
    FindStreamMs := StepWatch.Elapsed.TotalMilliseconds;
    StepWatch := TStopwatch.StartNew;
{$ENDIF}
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
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'decoder_qsv_choice file="%s" mode=%s codec_id=%d video=%dx%d qsv_decoder="%s" try_qsv=%s',
        [ExtractFileName(FileName), VideoDecoderModeToText(DecoderMode),
         CodecPar.codec_id, CodecPar.width, CodecPar.height,
         string(QsvDecoderName),
         BoolToStr(ShouldTryQsvDecoder(DecoderMode, CodecPar), True)]));
{$ENDIF}
      if ShouldTryQsvDecoder(DecoderMode, CodecPar) and (QsvDecoderName <> '') then
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

      Info.Width := CodecPar.width;
      Info.Height := CodecPar.height;
      Info.FpsText := RationalToText(Stream.avg_frame_rate);
      Info.Fps := RationalToDouble(Stream.avg_frame_rate);
      Info.PixelFormat := CodecPar.format;
      Info.PixelFormatName := PixelFormatName(CodecPar.format);
      Info.HasAlpha := PixelFormatHasAlpha(Info.PixelFormatName);
      Info.RotationDegrees := ReadVideoRotationDegrees(Stream);

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
{$IFDEF DEBUG}
    CodecOpenMs := StepWatch.Elapsed.TotalMilliseconds;
    StepWatch := TStopwatch.StartNew;
{$ENDIF}

    OpenAudioDecoder(FormatContext, Info, AudioCodecContext, AudioStream, AudioStreamIndex, AudioFrame, SwrContext);
{$IFDEF DEBUG}
    AudioOpenMs := StepWatch.Elapsed.TotalMilliseconds;
    StepWatch := TStopwatch.StartNew;
{$ENDIF}
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
    FInputBuffer := InputBuffer;
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
    InputBuffer := nil;
    CodecContext := nil;
    AudioCodecContext := nil;
    Packet := nil;
    Frame := nil;
    TransferFrame := nil;
    QsvDeviceContext := nil;
    AudioFrame := nil;
    SwrContext := nil;
    Result := True;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'decoder_open_detail file="%s" drive="%s" api_load_ms=%.3f format_open_ms=%.3f stream_info_ms=%.3f find_stream_ms=%.3f codec_open_ms=%.3f audio_open_ms=%.3f total_ms=%.3f decoder="%s" video=%dx%d rotation=%d audio_present=%s audio_err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName), ApiLoadMs,
       FormatOpenMs, StreamInfoMs, FindStreamMs, CodecOpenMs, AudioOpenMs,
       TotalWatch.Elapsed.TotalMilliseconds, VideoDecoderName,
       Info.Width, Info.Height, Info.RotationDegrees,
       BoolToStr(Info.Audio.Present, True), Info.Audio.OpenError]));
    WriteVideoMinerSlowLog(Format(
      'decoder_open_role seq=%d role=%s buffer_enabled=%s total_ms=%.3f',
      [OpenSequence, FFmpegDecoderRoleText(FRole),
       BoolToStr(UseForwardBuffer, True), TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
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
  InputBuffer.Free;
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
  TargetTs: Int64;
  DecodedAny: Boolean;
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
    DecodedAny := False;
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
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBitmapCached(Frame, Bitmap, FDirectSwsContext,
            FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat,
            FDirectSwsDstFormat);
          DecodedAny := True;
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    if DecodedAny then
    begin
      Result := True;
      Exit;
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
  Inc(FDecodeGeneration);
  SyncContextFromFields;
  Result := FFmpegDecoderSeekBgrx32.DecodeFrameToBgrx32(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

// 指定ミリ秒位置へシークしてフレームを24bit BGRバッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToBgrx32Fast(PositionMs: Integer;
  Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
begin
  Inc(FDecodeGeneration);
  SyncContextFromFields;
  Result := FFmpegDecoderSeekBgrx32.DecodeFrameToBgrx32Fast(
    FContext, PositionMs, Buffer, BufferStride, ErrorMessage);
  SyncFieldsFromContext;
end;

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
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBitmapCached(Frame, Bitmap, FDirectSwsContext,
            FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat,
            FDirectSwsDstFormat);
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
  Inc(FDecodeGeneration);
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
  SyncFieldsFromContext;
end;

// 一時デコーダで動画情報だけを読む
function TFFmpegDecoder.SeekAudioToMs(PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  SyncContextFromFields;
  Result := FFmpegDecoderAudioRead.SeekAudioToMs(FContext, PositionMs, ErrorMessage);
  SyncFieldsFromContext;
end;

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
