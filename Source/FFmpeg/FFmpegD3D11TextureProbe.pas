unit FFmpegD3D11TextureProbe;

// D3D11 texture 表示経路の見込みを測るため、NV12 frame の texture upload だけを計測する。
// 通常表示は変えず、VIDEOMINER_TEXTURE_PROBE=1 の Debug 実行時だけログを出す。

interface

uses
  FFmpegApi;

// NV12 frame を D3D11 texture へアップロードし、計測ログを出す。
procedure ProbeNv12TextureUpload(Frame: PAVFrame);

implementation

uses
  Winapi.Windows, Winapi.D3D11, Winapi.D3DCommon, Winapi.DxgiFormat,
  System.Diagnostics, System.SysUtils, VideoMinerDebugLog;

type
  TNv12TextureProbe = class
  private
    FDevice         : ID3D11Device;        // probe 用 D3D11 device
    FDeviceContext  : ID3D11DeviceContext; // probe 用 immediate context
    FFeatureLevel   : D3D_FEATURE_LEVEL;   // 作成された feature level
    FTexture        : ID3D11Texture2D;     // NV12 upload 先 texture
    FYTexture       : ID3D11Texture2D;     // Y plane upload 先 texture
    FUvTexture      : ID3D11Texture2D;     // UV plane upload 先 texture
    FTextureWidth   : Integer;             // texture 幅
    FTextureHeight  : Integer;             // texture 高さ
    FPackedBuffer   : TBytes;              // plane が連続していない時の退避バッファ
    FLastError      : string;              // 同じ失敗を毎 frame 出さないための記録
    FLoggedDisabled : Boolean;             // 非 NV12 などのスキップ理由を一度だけ出す
    function EnsureDevice(out ErrorMessage: string): Boolean;
    function EnsureTexture(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    function EnsurePlaneTextures(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    procedure LogErrorOnce(const ErrorMessage: string);
    procedure ProbePlaneTextures(Frame: PAVFrame);
  public
    procedure Probe(Frame: PAVFrame);
  end;

var
  GlobalProbe: TNv12TextureProbe;

function TextureProbeEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := SameText(GetEnvironmentVariable('VIDEOMINER_TEXTURE_PROBE'), '1');
{$ELSE}
  Result := False;
{$ENDIF}
end;

function TNv12TextureProbe.EnsureDevice(out ErrorMessage: string): Boolean;
var
  FeatureLevels: array[0..2] of D3D_FEATURE_LEVEL;
  Ret: HRESULT;
begin
  Result := True;
  ErrorMessage := '';
  if Assigned(FDevice) and Assigned(FDeviceContext) then
    Exit;

  FeatureLevels[0] := D3D_FEATURE_LEVEL_11_0;
  FeatureLevels[1] := D3D_FEATURE_LEVEL_10_1;
  FeatureLevels[2] := D3D_FEATURE_LEVEL_10_0;

  try
    Ret := D3D11CreateDevice(nil, D3D_DRIVER_TYPE_HARDWARE, 0, 0,
      @FeatureLevels[0], Length(FeatureLevels), D3D11_SDK_VERSION,
      FDevice, FFeatureLevel, FDeviceContext);
  except
    on E: Exception do
    begin
      ErrorMessage := E.ClassName + ': ' + E.Message;
      Exit(False);
    end;
  end;

  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('D3D11CreateDevice failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Result := False;
  end;
end;

function TNv12TextureProbe.EnsureTexture(Width, Height: Integer; out Recreated: Boolean;
  out ErrorMessage: string): Boolean;
var
  Desc: D3D11_TEXTURE2D_DESC;
  Ret: HRESULT;
begin
  Result := True;
  Recreated := False;
  ErrorMessage := '';
  if Assigned(FTexture) and (FTextureWidth = Width) and (FTextureHeight = Height) then
    Exit;

  FTexture := nil;
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.Width := Width;
  Desc.Height := Height;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_NV12;
  Desc.SampleDesc.Count := 1;
  Desc.SampleDesc.Quality := 0;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Desc.BindFlags := D3D11_BIND_SHADER_RESOURCE;
  Desc.CPUAccessFlags := 0;
  Desc.MiscFlags := 0;

  Ret := FDevice.CreateTexture2D(Desc, nil, FTexture);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateTexture2D NV12 failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit(False);
  end;

  FTextureWidth := Width;
  FTextureHeight := Height;
  Recreated := True;
end;

function TNv12TextureProbe.EnsurePlaneTextures(Width, Height: Integer;
  out Recreated: Boolean; out ErrorMessage: string): Boolean;
var
  Desc: D3D11_TEXTURE2D_DESC;
  Ret: HRESULT;
begin
  Result := True;
  Recreated := False;
  ErrorMessage := '';
  if Assigned(FYTexture) and Assigned(FUvTexture) and
     (FTextureWidth = Width) and (FTextureHeight = Height) then
    Exit;

  FYTexture := nil;
  FUvTexture := nil;
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.Width := Width;
  Desc.Height := Height;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_R8_UNORM;
  Desc.SampleDesc.Count := 1;
  Desc.SampleDesc.Quality := 0;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Desc.BindFlags := D3D11_BIND_SHADER_RESOURCE;
  Desc.CPUAccessFlags := 0;
  Desc.MiscFlags := 0;

  Ret := FDevice.CreateTexture2D(Desc, nil, FYTexture);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateTexture2D Y plane failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit(False);
  end;

  Desc.Width := (Width + 1) div 2;
  Desc.Height := (Height + 1) div 2;
  Desc.Format := DXGI_FORMAT_R8G8_UNORM;
  Ret := FDevice.CreateTexture2D(Desc, nil, FUvTexture);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateTexture2D UV plane failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit(False);
  end;

  FTextureWidth := Width;
  FTextureHeight := Height;
  Recreated := True;
end;

procedure TNv12TextureProbe.LogErrorOnce(const ErrorMessage: string);
begin
  if ErrorMessage = '' then
    Exit;
  if SameText(FLastError, ErrorMessage) then
    Exit;
  FLastError := ErrorMessage;
  WriteVideoMinerSlowLog('nv12_texture_probe_error err="' + ErrorMessage + '"');
end;

procedure TNv12TextureProbe.ProbePlaneTextures(Frame: PAVFrame);
var
  ErrorMessage : string;     // D3D11 texture 作成失敗の理由
  Recreated    : Boolean;    // texture を今回作り直したか
  StepWatch    : TStopwatch; // 各 step の計測
  TotalWatch   : TStopwatch; // probe 全体の計測
  UploadYMs    : Double;     // Y plane UpdateSubresource 時間
  UploadUvMs   : Double;     // UV plane UpdateSubresource 時間
  FlushMs      : Double;     // Flush 呼び出し時間
  ChromaHeight : Integer;    // NV12 UV plane の高さ
begin
  if not EnsurePlaneTextures(Frame.width, Frame.height, Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;

  TotalWatch := TStopwatch.StartNew;
  ChromaHeight := (Frame.height + 1) div 2;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FYTexture, 0, nil, Frame.data[0],
    Cardinal(Frame.linesize[0]), Cardinal(Frame.linesize[0] * Frame.height));
  UploadYMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FUvTexture, 0, nil, Frame.data[1],
    Cardinal(Frame.linesize[1]), Cardinal(Frame.linesize[1] * ChromaHeight));
  UploadUvMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.Flush;
  FlushMs := StepWatch.Elapsed.TotalMilliseconds;

  WriteVideoMinerSlowLog(Format(
    'nv12_plane_texture_probe frame=%dx%d y_stride=%d uv_stride=%d recreated=%s feature_level=$%.4x upload_y_ms=%.3f upload_uv_ms=%.3f flush_ms=%.3f total_ms=%.3f',
    [Frame.width, Frame.height, Frame.linesize[0], Frame.linesize[1],
     BoolToStr(Recreated, True), Cardinal(FFeatureLevel), UploadYMs,
     UploadUvMs, FlushMs, TotalWatch.Elapsed.TotalMilliseconds]));
end;

procedure TNv12TextureProbe.Probe(Frame: PAVFrame);
var
  ErrorMessage : string;     // D3D11 初期化/texture 作成失敗の理由
  Recreated    : Boolean;    // texture を今回作り直したか
  NeedsPack    : Boolean;    // D3D11 が期待する連続 NV12 に詰め直す必要があるか
  SrcData      : Pointer;    // UpdateSubresource に渡す先頭
  SrcPitch     : Cardinal;   // UpdateSubresource に渡す row pitch
  SrcDepth     : Cardinal;   // NV12 全体の byte size
  Y            : Integer;    // plane copy 中の行番号
  ChromaHeight : Integer;    // NV12 UV plane の高さ
  PackedOffset : Integer;    // packed buffer 内のコピー位置
  StepWatch    : TStopwatch; // 各 step の計測
  TotalWatch   : TStopwatch; // probe 全体の計測
  PackMs       : Double;     // packed buffer 作成時間
  UploadMs     : Double;     // UpdateSubresource 呼び出し時間
  FlushMs      : Double;     // Flush 呼び出し時間
begin
  if (Frame = nil) or (Frame.format <> AV_PIX_FMT_NV12) then
  begin
    if not FLoggedDisabled then
    begin
      FLoggedDisabled := True;
      if Frame <> nil then
        WriteVideoMinerSlowLog(Format('nv12_texture_probe_skip frame=%dx%d fmt=%d',
          [Frame.width, Frame.height, Frame.format]));
    end;
    Exit;
  end;

  if (Frame.data[0] = nil) or (Frame.data[1] = nil) or
     (Frame.linesize[0] <= 0) or (Frame.linesize[1] <= 0) then
  begin
    LogErrorOnce('NV12 frame has invalid planes.');
    Exit;
  end;

  if not EnsureDevice(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureTexture(Frame.width, Frame.height, Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;

  ProbePlaneTextures(Frame);

  TotalWatch := TStopwatch.StartNew;
  PackMs := 0;
  ChromaHeight := (Frame.height + 1) div 2;
  NeedsPack := (Frame.linesize[1] <> Frame.linesize[0]) or
    (NativeUInt(Frame.data[1]) <> NativeUInt(Frame.data[0]) +
      NativeUInt(Frame.linesize[0]) * NativeUInt(Frame.height));

  SrcPitch := Cardinal(Frame.linesize[0]);
  SrcDepth := Cardinal(Frame.linesize[0] * (Frame.height + ChromaHeight));
  SrcData := Frame.data[0];

  if NeedsPack then
  begin
    StepWatch := TStopwatch.StartNew;
    SetLength(FPackedBuffer, SrcDepth);
    PackedOffset := 0;
    for Y := 0 to Frame.height - 1 do
    begin
      Move(PByte(NativeUInt(Frame.data[0]) + NativeUInt(Y * Frame.linesize[0]))^,
        FPackedBuffer[PackedOffset], Frame.linesize[0]);
      Inc(PackedOffset, Frame.linesize[0]);
    end;
    for Y := 0 to ChromaHeight - 1 do
    begin
      Move(PByte(NativeUInt(Frame.data[1]) + NativeUInt(Y * Frame.linesize[1]))^,
        FPackedBuffer[PackedOffset], Frame.linesize[1]);
      Inc(PackedOffset, Frame.linesize[0]);
    end;
    SrcData := @FPackedBuffer[0];
    PackMs := StepWatch.Elapsed.TotalMilliseconds;
  end;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FTexture, 0, nil, SrcData, SrcPitch, SrcDepth);
  UploadMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.Flush;
  FlushMs := StepWatch.Elapsed.TotalMilliseconds;

  WriteVideoMinerSlowLog(Format(
    'nv12_texture_probe frame=%dx%d y_stride=%d uv_stride=%d packed=%s recreated=%s feature_level=$%.4x pack_ms=%.3f upload_ms=%.3f flush_ms=%.3f total_ms=%.3f',
    [Frame.width, Frame.height, Frame.linesize[0], Frame.linesize[1],
     BoolToStr(NeedsPack, True), BoolToStr(Recreated, True), Cardinal(FFeatureLevel),
     PackMs, UploadMs, FlushMs, TotalWatch.Elapsed.TotalMilliseconds]));
end;

procedure ProbeNv12TextureUpload(Frame: PAVFrame);
begin
  if not TextureProbeEnabled then
    Exit;
  if GlobalProbe = nil then
    GlobalProbe := TNv12TextureProbe.Create;
  GlobalProbe.Probe(Frame);
end;

initialization

finalization
  GlobalProbe.Free;

end.
