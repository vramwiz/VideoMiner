unit FFmpegQsvDecode;

interface

uses
  FFmpegApi;

const
  AV_CODEC_ID_MPEG2VIDEO = 2;   // MPEG-2 videoのFFmpeg codec id
  AV_CODEC_ID_MJPEG      = 7;   // MJPEGのFFmpeg codec id
  AV_CODEC_ID_H264       = 27;  // H.264のFFmpeg codec id
  AV_CODEC_ID_VP8        = 139; // VP8のFFmpeg codec id
  AV_CODEC_ID_VP9        = 167; // VP9のFFmpeg codec id
  AV_CODEC_ID_HEVC       = 173; // HEVC/H.265のFFmpeg codec id
  AV_CODEC_ID_AV1        = 225; // AV1のFFmpeg codec id

// codec idから対応するQSV decoder名を返す。
function QsvDecoderNameForCodecId(CodecId: Integer): AnsiString;
// QSV用のHW device contextを作成する。
function CreateQsvDevice(out DeviceContext: PAVBufferRef; out ErrorMessage: string): Boolean;
// QSV HW frameの場合だけCPU側フレームへ転送する。
function TransferFrameToCpuIfNeeded(SourceFrame, TransferFrame: PAVFrame;
  out CpuFrame: PAVFrame; out DidTransfer: Boolean; out ErrorMessage: string): Boolean;

implementation

// codec idから対応するQSV decoder名を返す。
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

// QSV用のHW device contextを作成する。
function CreateQsvDevice(out DeviceContext: PAVBufferRef; out ErrorMessage: string): Boolean;
var
  Ret: Integer;
begin
  DeviceContext := nil;
  ErrorMessage := '';
  Ret := TFFmpegApi.av_hwdevice_ctx_create(@DeviceContext, AV_HWDEVICE_TYPE_QSV, nil, nil, 0);
  Result := Ret >= 0;
  if not Result then
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
end;

// QSV HW frameの場合だけCPU側フレームへ転送する。
function TransferFrameToCpuIfNeeded(SourceFrame, TransferFrame: PAVFrame;
  out CpuFrame: PAVFrame; out DidTransfer: Boolean; out ErrorMessage: string): Boolean;
var
  Ret: Integer;
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
  Ret := TFFmpegApi.av_hwframe_transfer_data(TransferFrame, SourceFrame, 0);
  if Ret < 0 then
  begin
    ErrorMessage := TFFmpegApi.ErrorText(Ret);
    Result := False;
    Exit;
  end;

  CpuFrame := TransferFrame;
  DidTransfer := True;
end;

end.
