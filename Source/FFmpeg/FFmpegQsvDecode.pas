unit FFmpegQsvDecode;

// Intel QSV デコードに必要な補助処理をまとめる。
// codec id から QSV decoder 名を選び、必要な場合は HW frame を CPU frame へ転送する。

interface

uses
  FFmpegApi;

const
  AV_CODEC_ID_MPEG2VIDEO = 2;   // MPEG-2 video の FFmpeg codec id
  AV_CODEC_ID_MJPEG      = 7;   // MJPEG の FFmpeg codec id
  AV_CODEC_ID_H264       = 27;  // H.264 の FFmpeg codec id
  AV_CODEC_ID_VP8        = 139; // VP8 の FFmpeg codec id
  AV_CODEC_ID_VP9        = 167; // VP9 の FFmpeg codec id
  AV_CODEC_ID_HEVC       = 173; // HEVC/H.265 の FFmpeg codec id
  AV_CODEC_ID_AV1        = 225; // AV1 の FFmpeg codec id

// codec id から対応する QSV decoder 名を返す。
function QsvDecoderNameForCodecId(CodecId: Integer): AnsiString;
// QSV 用の HW device context を作成する。
function CreateQsvDevice(out DeviceContext: PAVBufferRef; out ErrorMessage: string): Boolean;
// QSV HW frame の場合だけ CPU 側フレームへ転送する。
function TransferFrameToCpuIfNeeded(SourceFrame, TransferFrame: PAVFrame;
  out CpuFrame: PAVFrame; out DidTransfer: Boolean; out ErrorMessage: string): Boolean;

implementation

uses
  System.Diagnostics, System.SysUtils, VideoMinerDebugLog;

// codec id から対応する QSV decoder 名を返す。
function QsvDecoderNameForCodecId(CodecId: Integer): AnsiString;
begin
  case CodecId of
    AV_CODEC_ID_H264:
      Result := 'h264_qsv';
    AV_CODEC_ID_HEVC:
      Result := 'hevc_qsv';
    AV_CODEC_ID_MPEG2VIDEO:
      Result := 'mpeg2_qsv';
    AV_CODEC_ID_MJPEG:
      Result := 'mjpeg_qsv';
    AV_CODEC_ID_VP8:
      Result := 'vp8_qsv';
    AV_CODEC_ID_VP9:
      Result := 'vp9_qsv';
    AV_CODEC_ID_AV1:
      Result := 'av1_qsv';
  else
    Result := '';
  end;
end;

// QSV 用の HW device context を作成する。
function CreateQsvDevice(out DeviceContext: PAVBufferRef; out ErrorMessage: string): Boolean;
var
  Ret : Integer; // FFmpeg API の戻り値
begin
  DeviceContext := nil;
  ErrorMessage := '';
  Ret := TFFmpegApi.av_hwdevice_ctx_create(@DeviceContext, AV_HWDEVICE_TYPE_QSV, nil, nil, 0);
  Result := Ret >= 0;
  if not Result then
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
end;

// QSV HW frame の場合だけ CPU 側フレームへ転送する。
function TransferFrameToCpuIfNeeded(SourceFrame, TransferFrame: PAVFrame;
  out CpuFrame: PAVFrame; out DidTransfer: Boolean; out ErrorMessage: string): Boolean;
var
  Ret : Integer; // FFmpeg API の戻り値
{$IFDEF DEBUG}
  Watch : TStopwatch; // HW frame 転送時間の計測
{$ENDIF}
begin
  CpuFrame := SourceFrame;
  DidTransfer := False;
  ErrorMessage := '';
  Result := True;

  if SourceFrame = nil then
    Exit;

  if SourceFrame.format <> AV_PIX_FMT_QSV then
    Exit;

  if TransferFrame = nil then
  begin
    ErrorMessage := 'Transfer frame is nil.';
    Result := False;
    Exit;
  end;

  TFFmpegApi.av_frame_unref(TransferFrame);
{$IFDEF DEBUG}
  Watch := TStopwatch.StartNew;
{$ENDIF}
  Ret := TFFmpegApi.av_hwframe_transfer_data(TransferFrame, SourceFrame, 0);
  if Ret < 0 then
  begin
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
    Result := False;
    Exit;
  end;

  CpuFrame := TransferFrame;
  DidTransfer := True;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'qsv_transfer frame=%dx%d src_fmt=%d dst_fmt=%d src_linesize0=%d dst_linesize0=%d transfer_ms=%.3f',
    [SourceFrame.width, SourceFrame.height, SourceFrame.format,
     TransferFrame.format, SourceFrame.linesize[0], TransferFrame.linesize[0],
     Watch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

end.
