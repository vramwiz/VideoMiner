unit FFmpegD3D11TextureProbe;

// D3D11 texture 表示経路の見込みを測るため、NV12 frame の texture upload だけを計測する。
// 通常表示は変えず、VIDEOMINER_TEXTURE_PROBE=1 の Debug 実行時だけログを出す。

interface

uses
  Winapi.Windows, System.Types, FFmpegApi;

type
  TD3D11SeekBarOverlayChapter = record
    PositionMs : Integer; // シークバー上に出すチャプター位置 ms
    Severity   : Integer; // 0=green, 1=yellow, 2=red
  end;

  TD3D11SeekBarOverlayState = record
    Visible        : Boolean; // D3D 側で簡易 seek bar を描くか
    Bounds         : TRect;   // 下部バー全体の client 座標
    Track          : TRect;   // progress track の client 座標
    PositionMs     : Integer; // 表示する現在位置 ms
    MaxMs          : Integer; // 動画長 ms
    HoverPositionMs: Integer; // hover/drag で指している位置 ms、なしなら -1
    Dragging       : Boolean; // シークバーをドラッグ中か
    CheckEnabled   : Boolean; // Check 中は時刻ではなくフレーム番号表示にする
    FrameStepMs    : Integer; // Check 中の 1 フレーム相当 ms
    VolumePercent  : Integer; // 音量パーセント
    Muted          : Boolean; // ミュート中か
    VolumeHovered  : Boolean; // 音量バー上にマウスがあるか
    VolumeDragging : Boolean; // 音量バーをドラッグ中か
    MuteHovered    : Boolean; // ミュートボタン上にマウスがあるか
    MutePressed    : Boolean; // ミュートボタン押下中か
    PlaybackRateText: string; // 再生速度表示
    PlaybackRateHovered: Boolean; // 再生速度ボタン上にマウスがあるか
    PlaybackRatePressed: Boolean; // 再生速度ボタン押下中か
    EndActionText  : string; // 終端到達時動作表示
    EndActionHovered: Boolean; // 終端動作ボタン上にマウスがあるか
    EndActionPressed: Boolean; // 終端動作ボタン押下中か
    CheckHovered   : Boolean; // Check ボタン上にマウスがあるか
    CheckPressed   : Boolean; // Check ボタン押下中か
    AddChapterHovered: Boolean; // チャプター追加ボタン上にマウスがあるか
    AddChapterPressed: Boolean; // チャプター追加ボタン押下中か
    DeleteChapterHovered: Boolean; // チャプター削除ボタン上にマウスがあるか
    DeleteChapterPressed: Boolean; // チャプター削除ボタン押下中か
    FullScreen     : Boolean; // 全画面表示中か
    FullScreenHovered: Boolean; // 全画面ボタン上にマウスがあるか
    FullScreenPressed: Boolean; // 全画面ボタン押下中か
    TransportVisible: Boolean; // 中央の再生/シーク操作ボタンを描くか
    TransportPlaying: Boolean; // 中央ボタンに一時停止アイコンを出すか
    FirstButton    : TRect;   // 先頭へ移動する中央ボタン
    SkipBackwardButton: TRect; // 10 秒戻し中央ボタン
    PlayPauseButton: TRect;   // 再生/一時停止中央ボタン
    SkipForwardButton: TRect; // 10 秒進み中央ボタン
    LastButton     : TRect;   // 末尾へ移動する中央ボタン
    Chapters       : TArray<TD3D11SeekBarOverlayChapter>; // D3D 側で描くチャプター目盛り
  end;

// NV12 frame を D3D11 texture へアップロードし、計測ログを出す。
procedure ProbeNv12TextureUpload(Frame: PAVFrame);
procedure SetNv12TextureProbeTargetWindow(WindowHandle: HWND; Width, Height: Integer);
function PresentNv12TextureFrame(Frame: PAVFrame): Boolean;
function PresentBgrx32TextureFrame(Buffer: Pointer; BufferStride, Width,
  Height: Integer): Boolean;
function PresentCurrentNv12TextureFrame: Boolean;
function Nv12TextureD3DDisplayEnabled: Boolean;
function Nv12TextureD3DFramePresented: Boolean;
procedure ClearNv12TextureD3DFramePresented;
procedure SetNv12TextureD3DDisplayAllowed(Allowed: Boolean);
procedure SetNv12TextureD3DSeekBarOverlay(const State: TD3D11SeekBarOverlayState);

implementation

uses
  Winapi.D3D11, Winapi.D3DCommon, Winapi.D3DCompiler, Winapi.DXGI, Winapi.DxgiFormat,
  Winapi.DxgiType, System.Diagnostics, System.Math, System.SysUtils, VideoMinerDebugLog;

type
  TNv12TextureProbe = class
  private
    FDevice         : ID3D11Device;        // probe 用 D3D11 device
    FDeviceContext  : ID3D11DeviceContext; // probe 用 immediate context
    FFeatureLevel   : D3D_FEATURE_LEVEL;   // 作成された feature level
    FTexture        : ID3D11Texture2D;     // NV12 upload 先 texture
    FYTexture       : ID3D11Texture2D;     // Y plane upload 先 texture
    FUvTexture      : ID3D11Texture2D;     // UV plane upload 先 texture
    FYResourceView  : ID3D11ShaderResourceView; // Y plane shader 入力
    FUvResourceView : ID3D11ShaderResourceView; // UV plane shader 入力
    FBgrxTexture    : ID3D11Texture2D;     // CPU BGRX32 upload 先 texture
    FBgrxResourceView: ID3D11ShaderResourceView; // CPU BGRX32 shader 入力
    FBgrxPixelShader: ID3D11PixelShader;   // BGRX32 texture 表示用 pixel shader
    FRenderTexture  : ID3D11Texture2D;     // shader 出力先 render target
    FRenderView     : ID3D11RenderTargetView; // shader 出力先 view
    FSwapChain      : IDXGISwapChain;      // 非表示 window への Present 計測用 swap chain
    FSwapRenderView : ID3D11RenderTargetView; // swap chain backbuffer view
    FDisplaySwapChain: IDXGISwapChain;     // 実表示用 swap chain
    FDisplayRenderView: ID3D11RenderTargetView; // 実表示 backbuffer view
    FVertexShader   : ID3D11VertexShader;  // fullscreen triangle vertex shader
    FPixelShader    : ID3D11PixelShader;   // NV12 -> RGB pixel shader
    FRectVertexShader  : ID3D11VertexShader; // overlay 矩形描画用 vertex shader
    FRectPixelShader   : ID3D11PixelShader;  // overlay 矩形描画用 pixel shader
    FRectConstantBuffer: ID3D11Buffer;        // overlay 矩形描画用 constant buffer
    FAlphaBlendState   : ID3D11BlendState;    // overlay 半透明合成用 blend state
    FSampler        : ID3D11SamplerState;  // texture sampler
    FTargetWindow   : HWND;                // Present 計測先 HWND
    FTargetWidth    : Integer;             // Present 計測先幅
    FTargetHeight   : Integer;             // Present 計測先高さ
    FProbeWindow    : HWND;                // ちらつきを避ける非表示 Present 計測用 HWND
    FSwapWindow     : HWND;                // swap chain 作成時の HWND
    FSwapWidth      : Integer;             // swap chain 幅
    FSwapHeight     : Integer;             // swap chain 高さ
    FDisplayWindow  : HWND;                // 実表示 swap chain 作成時の HWND
    FDisplayWidth   : Integer;             // 実表示 swap chain 幅
    FDisplayHeight  : Integer;             // 実表示 swap chain 高さ
    FTextureWidth   : Integer;             // texture 幅
    FTextureHeight  : Integer;             // texture 高さ
    FBgrxWidth      : Integer;             // BGRX32 texture 幅
    FBgrxHeight     : Integer;             // BGRX32 texture 高さ
    FPackedBuffer   : TBytes;              // plane が連続していない時の退避バッファ
    FBgrxPackedBuffer: TBytes;             // 負 stride の BGRX32 を詰め直す退避バッファ
    FCurrentFrameIsBgrx32: Boolean;        // 保持中 frame が BGRX32 upload 由来か
    FLastError      : string;              // 同じ失敗を毎 frame 出さないための記録
    FLoggedDisabled : Boolean;             // 非 NV12 などのスキップ理由を一度だけ出す
    function EnsureDevice(out ErrorMessage: string): Boolean;
    function EnsureTexture(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    function EnsurePlaneTextures(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    function EnsureShaderPipeline(Width, Height: Integer; out ErrorMessage: string): Boolean;
    function EnsureBgrxTexture(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    function EnsureBgrxShaderPipeline(out ErrorMessage: string): Boolean;
    function EnsureRectPipeline(out ErrorMessage: string): Boolean;
    function EnsureProbeWindow(out ErrorMessage: string): Boolean;
    function EnsureSwapChain(out Recreated: Boolean; out ErrorMessage: string): Boolean;
    function EnsureDisplaySwapChain(out Recreated: Boolean; out ErrorMessage: string): Boolean;
    procedure ReleaseD3DContextReferences;
    procedure LogErrorOnce(const ErrorMessage: string);
    procedure ProbePlaneTextures(Frame: PAVFrame);
    procedure ProbeShaderDraw(Frame: PAVFrame);
    procedure ProbeSwapChainPresent(Frame: PAVFrame);
    procedure DrawOverlayRect(const Rect: TRect; R, G, B, A: Single);
    procedure DrawOverlayLine(X1, Y1, X2, Y2, Thickness: Integer; R, G, B, A: Single);
    procedure DrawOverlayCircleApprox(CenterX, CenterY, Radius: Integer;
      R, G, B, A: Single);
    procedure DrawOverlayDigit(X, Y, Scale, Digit: Integer; R, G, B, A: Single);
    procedure DrawOverlayColon(X, Y, Scale: Integer; R, G, B, A: Single);
    procedure DrawOverlaySlash(X, Y, Scale: Integer; R, G, B, A: Single);
    procedure DrawOverlayDot(X, Y, Scale: Integer; R, G, B, A: Single);
    procedure DrawOverlayX(X, Y, Scale: Integer; R, G, B, A: Single);
    procedure DrawOverlayLetter(X, Y, Scale: Integer; Ch: Char; R, G, B,
      A: Single);
    procedure DrawOverlayPlus(X, Y, Scale: Integer; R, G, B, A: Single);
    procedure DrawOverlayMinus(X, Y, Scale: Integer; R, G, B, A: Single);
    procedure DrawOverlayText(X, Y, Scale: Integer; const Text: string; R, G, B, A: Single);
    procedure DrawSeekBarMuteIcon(const IconRect: TRect; const State: TD3D11SeekBarOverlayState);
    procedure DrawSeekBarTimeText(const State: TD3D11SeekBarOverlayState);
    procedure DrawSeekBarVolume(const State: TD3D11SeekBarOverlayState);
    procedure DrawSeekBarPlaybackRate(const State: TD3D11SeekBarOverlayState);
    procedure DrawSeekBarEndAction(const State: TD3D11SeekBarOverlayState);
    procedure DrawSeekBarChapterButtons(const State: TD3D11SeekBarOverlayState);
    procedure DrawSeekBarFullScreen(const State: TD3D11SeekBarOverlayState);
    procedure DrawTransportButtonBackground(const ButtonRect: TRect);
    procedure DrawTransportTriangle(CenterX, CenterY, Width, Height,
      Direction: Integer; R, G, B, A: Single);
    procedure DrawTransportEdgeIcon(const ButtonRect: TRect; Forward: Boolean);
    procedure DrawTransportSkipIcon(const ButtonRect: TRect; Forward: Boolean);
    procedure DrawTransportPlayPauseIcon(const ButtonRect: TRect; Playing: Boolean);
    procedure DrawTransportOverlay(const State: TD3D11SeekBarOverlayState);
    function DrawSeekBarOverlay(const State: TD3D11SeekBarOverlayState): Double;
  public
    destructor Destroy; override;
    procedure Probe(Frame: PAVFrame);
    function PresentFrame(Frame: PAVFrame): Boolean;
    function PresentBgrx32Frame(Buffer: Pointer; BufferStride, Width,
      Height: Integer): Boolean;
    function PresentCurrentFrame: Boolean;
    procedure SetTargetWindow(WindowHandle: HWND; Width, Height: Integer);
  end;

var
  GlobalProbe: TNv12TextureProbe;
  GlobalD3DDisplayAllowed: Boolean;
  GlobalD3DFramePresented: Boolean;
  GlobalD3DSeekBarOverlay: TD3D11SeekBarOverlayState;
  LastD3DPresentLogTick: UInt64;
  LastD3DMemoryLogTick: UInt64;
  LastD3DPresentOverlayVisible: Boolean;
  LastD3DPresentDragging: Boolean;
  LastD3DPresentTransportVisible: Boolean;

type
  TProcessMemoryCountersEx = record
    cb: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize: NativeUInt;
    WorkingSetSize: NativeUInt;
    QuotaPeakPagedPoolUsage: NativeUInt;
    QuotaPagedPoolUsage: NativeUInt;
    QuotaPeakNonPagedPoolUsage: NativeUInt;
    QuotaNonPagedPoolUsage: NativeUInt;
    PagefileUsage: NativeUInt;
    PeakPagefileUsage: NativeUInt;
    PrivateUsage: NativeUInt;
  end;

function GetProcessMemoryInfo(Process: THandle;
  var Counters: TProcessMemoryCountersEx; Size: DWORD): BOOL; stdcall;
  external 'psapi.dll';

procedure LogD3DMemoryUsage(const Context: string; Force: Boolean = False);
var
  Counters: TProcessMemoryCountersEx;
  NowTick: UInt64;
begin
  NowTick := GetTickCount64;
  if (not Force) and (NowTick - LastD3DMemoryLogTick < 1000) then
    Exit;

  FillChar(Counters, SizeOf(Counters), 0);
  Counters.cb := SizeOf(Counters);
  if not GetProcessMemoryInfo(GetCurrentProcess, Counters, SizeOf(Counters)) then
    Exit;

  LastD3DMemoryLogTick := NowTick;
  WriteVideoMinerD3DLog(Format(
    'd3d_memory context=%s private_mb=%.1f working_mb=%.1f peak_working_mb=%.1f pagefile_mb=%.1f',
    [Context, Counters.PrivateUsage / 1048576.0,
     Counters.WorkingSetSize / 1048576.0,
     Counters.PeakWorkingSetSize / 1048576.0,
     Counters.PagefileUsage / 1048576.0]));
end;

function TextureProbeEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := SameText(GetEnvironmentVariable('VIDEOMINER_TEXTURE_PROBE'), '1');
{$ELSE}
  Result := False;
{$ENDIF}
end;

function Nv12TextureD3DDisplayEnabled: Boolean;
var
  DisplayFlag: string;
begin
  DisplayFlag := GetEnvironmentVariable('VIDEOMINER_D3D11_DISPLAY');
  Result := not (SameText(DisplayFlag, '0') or SameText(DisplayFlag, 'off') or
    SameText(DisplayFlag, 'false'));
end;

function Nv12TextureD3DFramePresented: Boolean;
begin
  Result := GlobalD3DFramePresented;
end;

procedure TNv12TextureProbe.ReleaseD3DContextReferences;
begin
  if not Assigned(FDeviceContext) then
    Exit;

  FDeviceContext.ClearState;
  FDeviceContext.Flush;
end;

procedure ClearNv12TextureD3DFramePresented;
begin
  GlobalD3DFramePresented := False;
end;

procedure SetNv12TextureD3DDisplayAllowed(Allowed: Boolean);
begin
  GlobalD3DDisplayAllowed := Allowed;
end;

procedure SetNv12TextureD3DSeekBarOverlay(const State: TD3D11SeekBarOverlayState);
begin
  GlobalD3DSeekBarOverlay := State;
  GlobalD3DSeekBarOverlay.Chapters := Copy(State.Chapters);
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

  ReleaseD3DContextReferences;
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
  if Assigned(FYTexture) and Assigned(FUvTexture) and Assigned(FYResourceView) and
     Assigned(FUvResourceView) and
     (FTextureWidth = Width) and (FTextureHeight = Height) then
    Exit;

  ReleaseD3DContextReferences;
  FYTexture := nil;
  FUvTexture := nil;
  FYResourceView := nil;
  FUvResourceView := nil;
  FRenderTexture := nil;
  FRenderView := nil;
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
  Ret := FDevice.CreateShaderResourceView(FYTexture, nil, FYResourceView);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateShaderResourceView Y plane failed. HRESULT=$%.8x', [Cardinal(Ret)]);
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
  Ret := FDevice.CreateShaderResourceView(FUvTexture, nil, FUvResourceView);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateShaderResourceView UV plane failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit(False);
  end;

  FTextureWidth := Width;
  FTextureHeight := Height;
  Recreated := True;
end;

function CompileShader(const Source, EntryPoint, Target: AnsiString;
  out Blob: ID3DBlob; out ErrorMessage: string): Boolean;
var
  ErrorBlob: ID3DBlob;
  Ret: HRESULT;
begin
  Result := False;
  ErrorMessage := '';
  Blob := nil;
  ErrorBlob := nil;
  try
    Ret := D3DCompile(PAnsiChar(Source), Length(Source), nil, nil, nil,
      PAnsiChar(EntryPoint), PAnsiChar(Target), 0, 0, Blob, ErrorBlob);
  except
    on E: Exception do
    begin
      ErrorMessage := E.ClassName + ': ' + E.Message;
      Exit;
    end;
  end;

  if not Succeeded(Ret) then
  begin
    if Assigned(ErrorBlob) then
      ErrorMessage := string(AnsiString(PAnsiChar(ErrorBlob.GetBufferPointer)))
    else
      ErrorMessage := Format('D3DCompile failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;
  Result := True;
end;

function TNv12TextureProbe.EnsureShaderPipeline(Width, Height: Integer;
  out ErrorMessage: string): Boolean;
const
  VERTEX_SHADER_SOURCE: AnsiString =
    'struct VSOut { float4 pos : SV_Position; float2 uv : TEXCOORD0; };' + #10 +
    'VSOut main(uint id : SV_VertexID) {' + #10 +
    '  float2 pos[3] = { float2(-1.0, -1.0), float2(-1.0, 3.0), float2(3.0, -1.0) };' + #10 +
    '  float2 uv[3] = { float2(0.0, 1.0), float2(0.0, -1.0), float2(2.0, 1.0) };' + #10 +
    '  VSOut o; o.pos = float4(pos[id], 0.0, 1.0); o.uv = uv[id]; return o;' + #10 +
    '}';
  PIXEL_SHADER_SOURCE: AnsiString =
    'Texture2D yTex : register(t0);' + #10 +
    'Texture2D uvTex : register(t1);' + #10 +
    'SamplerState samp0 : register(s0);' + #10 +
    'float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target {' + #10 +
    '  float y = saturate((yTex.Sample(samp0, uv).r - (16.0 / 255.0)) * (255.0 / 219.0));' + #10 +
    '  float2 chroma = (uvTex.Sample(samp0, uv).rg - float2(128.0 / 255.0, 128.0 / 255.0)) * (255.0 / 224.0);' + #10 +
    '  float r = y + 1.5748 * chroma.y;' + #10 +
    '  float g = y - 0.1873 * chroma.x - 0.4681 * chroma.y;' + #10 +
    '  float b = y + 1.8556 * chroma.x;' + #10 +
    '  return float4(saturate(float3(r, g, b)), 1.0);' + #10 +
    '}';
var
  Desc: D3D11_TEXTURE2D_DESC;
  PixelBlob: ID3DBlob;
  Ret: HRESULT;
  SamplerDesc: D3D11_SAMPLER_DESC;
  TempVertexShader: ID3D11VertexShader;
  VertexBlob: ID3DBlob;
begin
  Result := False;
  ErrorMessage := '';

  if not Assigned(FVertexShader) then
  begin
    if not CompileShader(VERTEX_SHADER_SOURCE, 'main', 'vs_4_0', VertexBlob, ErrorMessage) then
      Exit;
    TempVertexShader := nil;
    Ret := FDevice.CreateVertexShader(VertexBlob.GetBufferPointer,
      VertexBlob.GetBufferSize, nil, @TempVertexShader);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateVertexShader failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
    FVertexShader := TempVertexShader;
  end;

  if not Assigned(FPixelShader) then
  begin
    if not CompileShader(PIXEL_SHADER_SOURCE, 'main', 'ps_4_0', PixelBlob, ErrorMessage) then
      Exit;
    Ret := FDevice.CreatePixelShader(PixelBlob.GetBufferPointer,
      PixelBlob.GetBufferSize, nil, FPixelShader);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreatePixelShader failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  if not Assigned(FSampler) then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.Filter := D3D11_FILTER_MIN_MAG_MIP_POINT;
    SamplerDesc.AddressU := D3D11_TEXTURE_ADDRESS_CLAMP;
    SamplerDesc.AddressV := D3D11_TEXTURE_ADDRESS_CLAMP;
    SamplerDesc.AddressW := D3D11_TEXTURE_ADDRESS_CLAMP;
    SamplerDesc.MinLOD := 0;
    SamplerDesc.MaxLOD := D3D11_FLOAT32_MAX;
    Ret := FDevice.CreateSamplerState(SamplerDesc, FSampler);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateSamplerState failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  if Assigned(FRenderTexture) and Assigned(FRenderView) and
     (FTextureWidth = Width) and (FTextureHeight = Height) then
    Exit(True);

  ReleaseD3DContextReferences;
  FRenderTexture := nil;
  FRenderView := nil;
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.Width := Width;
  Desc.Height := Height;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Desc.SampleDesc.Count := 1;
  Desc.SampleDesc.Quality := 0;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Desc.BindFlags := D3D11_BIND_RENDER_TARGET;
  Desc.CPUAccessFlags := 0;
  Desc.MiscFlags := 0;

  Ret := FDevice.CreateTexture2D(Desc, nil, FRenderTexture);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateTexture2D render target failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;
  Ret := FDevice.CreateRenderTargetView(FRenderTexture, nil, FRenderView);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateRenderTargetView failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  Result := True;
end;

function TNv12TextureProbe.EnsureBgrxTexture(Width, Height: Integer;
  out Recreated: Boolean; out ErrorMessage: string): Boolean;
var
  Desc: D3D11_TEXTURE2D_DESC;
  Ret: HRESULT;
begin
  Result := True;
  Recreated := False;
  ErrorMessage := '';
  if Assigned(FBgrxTexture) and Assigned(FBgrxResourceView) and
     (FBgrxWidth = Width) and (FBgrxHeight = Height) then
    Exit;

  ReleaseD3DContextReferences;
  FBgrxTexture := nil;
  FBgrxResourceView := nil;
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.Width := Width;
  Desc.Height := Height;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Desc.SampleDesc.Count := 1;
  Desc.SampleDesc.Quality := 0;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Desc.BindFlags := D3D11_BIND_SHADER_RESOURCE;
  Desc.CPUAccessFlags := 0;
  Desc.MiscFlags := 0;

  Ret := FDevice.CreateTexture2D(Desc, nil, FBgrxTexture);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateTexture2D BGRX32 failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit(False);
  end;
  Ret := FDevice.CreateShaderResourceView(FBgrxTexture, nil, FBgrxResourceView);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateShaderResourceView BGRX32 failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit(False);
  end;

  FBgrxWidth := Width;
  FBgrxHeight := Height;
  Recreated := True;
end;

function TNv12TextureProbe.EnsureBgrxShaderPipeline(out ErrorMessage: string): Boolean;
const
  VERTEX_SHADER_SOURCE: AnsiString =
    'struct VSOut { float4 pos : SV_Position; float2 uv : TEXCOORD0; };' + #10 +
    'VSOut main(uint id : SV_VertexID) {' + #10 +
    '  float2 pos[3] = { float2(-1.0, -1.0), float2(-1.0, 3.0), float2(3.0, -1.0) };' + #10 +
    '  float2 uv[3] = { float2(0.0, 1.0), float2(0.0, -1.0), float2(2.0, 1.0) };' + #10 +
    '  VSOut o; o.pos = float4(pos[id], 0.0, 1.0); o.uv = uv[id]; return o;' + #10 +
    '}';
  PIXEL_SHADER_SOURCE: AnsiString =
    'Texture2D frameTex : register(t0);' + #10 +
    'SamplerState samp0 : register(s0);' + #10 +
    'float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target {' + #10 +
    '  return float4(frameTex.Sample(samp0, uv).rgb, 1.0);' + #10 +
    '}';
var
  PixelBlob: ID3DBlob;
  Ret: HRESULT;
  SamplerDesc: D3D11_SAMPLER_DESC;
  TempVertexShader: ID3D11VertexShader;
  VertexBlob: ID3DBlob;
begin
  Result := False;
  ErrorMessage := '';

  if not Assigned(FVertexShader) then
  begin
    if not CompileShader(VERTEX_SHADER_SOURCE, 'main', 'vs_4_0',
      VertexBlob, ErrorMessage) then
      Exit;
    TempVertexShader := nil;
    Ret := FDevice.CreateVertexShader(VertexBlob.GetBufferPointer,
      VertexBlob.GetBufferSize, nil, @TempVertexShader);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateVertexShader BGRX32 failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
    FVertexShader := TempVertexShader;
  end;

  if not Assigned(FBgrxPixelShader) then
  begin
    if not CompileShader(PIXEL_SHADER_SOURCE, 'main', 'ps_4_0',
      PixelBlob, ErrorMessage) then
      Exit;
    Ret := FDevice.CreatePixelShader(PixelBlob.GetBufferPointer,
      PixelBlob.GetBufferSize, nil, FBgrxPixelShader);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreatePixelShader BGRX32 failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  if not Assigned(FSampler) then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.Filter := D3D11_FILTER_MIN_MAG_MIP_POINT;
    SamplerDesc.AddressU := D3D11_TEXTURE_ADDRESS_CLAMP;
    SamplerDesc.AddressV := D3D11_TEXTURE_ADDRESS_CLAMP;
    SamplerDesc.AddressW := D3D11_TEXTURE_ADDRESS_CLAMP;
    SamplerDesc.MinLOD := 0;
    SamplerDesc.MaxLOD := D3D11_FLOAT32_MAX;
    Ret := FDevice.CreateSamplerState(SamplerDesc, FSampler);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateSamplerState BGRX32 failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  Result := True;
end;

function TNv12TextureProbe.EnsureRectPipeline(out ErrorMessage: string): Boolean;
const
  RECT_VERTEX_SHADER_SOURCE: AnsiString =
    'cbuffer RectConstants : register(b0) {' + #10 +
    '  float4 rectPx;' + #10 +
    '  float4 targetPx;' + #10 +
    '  float4 color;' + #10 +
    '};' + #10 +
    'struct VSOut { float4 pos : SV_Position; float4 color : COLOR0; };' + #10 +
    'VSOut main(uint id : SV_VertexID) {' + #10 +
    '  float2 p0 = rectPx.xy;' + #10 +
    '  float2 p1 = rectPx.zw;' + #10 +
    '  float2 pos[6] = { p0, float2(p1.x, p0.y), float2(p0.x, p1.y),' + #10 +
    '                    float2(p0.x, p1.y), float2(p1.x, p0.y), p1 };' + #10 +
    '  float2 ndc = float2(pos[id].x / targetPx.x * 2.0 - 1.0,' + #10 +
    '                      1.0 - pos[id].y / targetPx.y * 2.0);' + #10 +
    '  VSOut o; o.pos = float4(ndc, 0.0, 1.0); o.color = color; return o;' + #10 +
    '}';
  RECT_PIXEL_SHADER_SOURCE: AnsiString =
    'float4 main(float4 pos : SV_Position, float4 color : COLOR0) : SV_Target {' + #10 +
    '  return color;' + #10 +
    '}';
var
  BlendDesc: D3D11_BLEND_DESC;
  BufferDesc: D3D11_BUFFER_DESC;
  PixelBlob: ID3DBlob;
  Ret: HRESULT;
  TempRectVertexShader: ID3D11VertexShader;
  VertexBlob: ID3DBlob;
begin
  Result := False;
  ErrorMessage := '';

  if not Assigned(FRectVertexShader) then
  begin
    if not CompileShader(RECT_VERTEX_SHADER_SOURCE, 'main', 'vs_4_0',
      VertexBlob, ErrorMessage) then
      Exit;
    TempRectVertexShader := nil;
    Ret := FDevice.CreateVertexShader(VertexBlob.GetBufferPointer,
      VertexBlob.GetBufferSize, nil, @TempRectVertexShader);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateVertexShader rect failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
    FRectVertexShader := TempRectVertexShader;
  end;

  if not Assigned(FRectPixelShader) then
  begin
    if not CompileShader(RECT_PIXEL_SHADER_SOURCE, 'main', 'ps_4_0',
      PixelBlob, ErrorMessage) then
      Exit;
    Ret := FDevice.CreatePixelShader(PixelBlob.GetBufferPointer,
      PixelBlob.GetBufferSize, nil, FRectPixelShader);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreatePixelShader rect failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  if not Assigned(FRectConstantBuffer) then
  begin
    FillChar(BufferDesc, SizeOf(BufferDesc), 0);
    BufferDesc.ByteWidth := 48;
    BufferDesc.Usage := D3D11_USAGE_DEFAULT;
    BufferDesc.BindFlags := D3D11_BIND_CONSTANT_BUFFER;
    Ret := FDevice.CreateBuffer(BufferDesc, nil, FRectConstantBuffer);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateBuffer rect constants failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  if not Assigned(FAlphaBlendState) then
  begin
    FillChar(BlendDesc, SizeOf(BlendDesc), 0);
    BlendDesc.RenderTarget[0].BlendEnable := True;
    BlendDesc.RenderTarget[0].SrcBlend := D3D11_BLEND_SRC_ALPHA;
    BlendDesc.RenderTarget[0].DestBlend := D3D11_BLEND_INV_SRC_ALPHA;
    BlendDesc.RenderTarget[0].BlendOp := D3D11_BLEND_OP_ADD;
    BlendDesc.RenderTarget[0].SrcBlendAlpha := D3D11_BLEND_ONE;
    BlendDesc.RenderTarget[0].DestBlendAlpha := D3D11_BLEND_INV_SRC_ALPHA;
    BlendDesc.RenderTarget[0].BlendOpAlpha := D3D11_BLEND_OP_ADD;
    BlendDesc.RenderTarget[0].RenderTargetWriteMask := Byte(D3D11_COLOR_WRITE_ENABLE_ALL);
    Ret := FDevice.CreateBlendState(BlendDesc, FAlphaBlendState);
    if not Succeeded(Ret) then
    begin
      ErrorMessage := Format('CreateBlendState rect failed. HRESULT=$%.8x', [Cardinal(Ret)]);
      Exit;
    end;
  end;

  Result := True;
end;

function TNv12TextureProbe.EnsureProbeWindow(out ErrorMessage: string): Boolean;
begin
  Result := False;
  ErrorMessage := '';

  if (FTargetWindow = 0) or (FTargetWidth <= 0) or (FTargetHeight <= 0) then
  begin
    ErrorMessage := 'swap chain target window is not ready.';
    Exit;
  end;

  if FProbeWindow <> 0 then
    Exit(True);

  FProbeWindow := CreateWindowEx(WS_EX_TOOLWINDOW, 'STATIC',
    'VideoMinerTextureProbe', WS_POPUP, -32000, -32000,
    FTargetWidth, FTargetHeight, 0, 0, HInstance, nil);
  if FProbeWindow = 0 then
  begin
    ErrorMessage := Format('CreateWindowEx probe window failed. GetLastError=%d',
      [GetLastError]);
    Exit;
  end;

  Result := True;
end;

function TNv12TextureProbe.EnsureSwapChain(out Recreated: Boolean;
  out ErrorMessage: string): Boolean;
var
  BackBuffer: ID3D11Texture2D;
  Desc: TDXGISwapChainDesc;
  Factory: IDXGIFactory;
  Ret: HRESULT;
begin
  Result := False;
  Recreated := False;
  ErrorMessage := '';

  if not EnsureProbeWindow(ErrorMessage) then
    Exit;

  if Assigned(FSwapChain) and Assigned(FSwapRenderView) and
     (FSwapWindow = FProbeWindow) and (FSwapWidth = FTargetWidth) and
     (FSwapHeight = FTargetHeight) then
    Exit(True);

  ReleaseD3DContextReferences;
  FSwapRenderView := nil;
  FSwapChain := nil;
  FSwapWindow := 0;
  FSwapWidth := 0;
  FSwapHeight := 0;

  Ret := CreateDXGIFactory(IID_IDXGIFactory, Factory);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateDXGIFactory failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  FillChar(Desc, SizeOf(Desc), 0);
  Desc.BufferDesc.Width := FTargetWidth;
  Desc.BufferDesc.Height := FTargetHeight;
  Desc.BufferDesc.RefreshRate.Numerator := 0;
  Desc.BufferDesc.RefreshRate.Denominator := 1;
  Desc.BufferDesc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Desc.BufferDesc.ScanlineOrdering := DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
  Desc.BufferDesc.Scaling := DXGI_MODE_SCALING_UNSPECIFIED;
  Desc.SampleDesc.Count := 1;
  Desc.SampleDesc.Quality := 0;
  Desc.BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
  Desc.BufferCount := 1;
  Desc.OutputWindow := FProbeWindow;
  Desc.Windowed := True;
  Desc.SwapEffect := DXGI_SWAP_EFFECT_DISCARD;
  Desc.Flags := 0;

  Ret := Factory.CreateSwapChain(FDevice as IUnknown, Desc, FSwapChain);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateSwapChain failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  BackBuffer := nil;
  Ret := FSwapChain.GetBuffer(0, ID3D11Texture2D, BackBuffer);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('IDXGISwapChain.GetBuffer failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  Ret := FDevice.CreateRenderTargetView(BackBuffer, nil, FSwapRenderView);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateRenderTargetView swap chain failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  FSwapWindow := FProbeWindow;
  FSwapWidth := FTargetWidth;
  FSwapHeight := FTargetHeight;
  Recreated := True;
  Result := True;
end;

function TNv12TextureProbe.EnsureDisplaySwapChain(out Recreated: Boolean;
  out ErrorMessage: string): Boolean;
var
  BackBuffer: ID3D11Texture2D;
  Desc: TDXGISwapChainDesc;
  Factory: IDXGIFactory;
  Ret: HRESULT;
begin
  Result := False;
  Recreated := False;
  ErrorMessage := '';

  if (FTargetWindow = 0) or (FTargetWidth <= 0) or (FTargetHeight <= 0) then
  begin
    ErrorMessage := 'D3D display target window is not ready.';
    Exit;
  end;

  if Assigned(FDisplaySwapChain) and Assigned(FDisplayRenderView) and
     (FDisplayWindow = FTargetWindow) and (FDisplayWidth = FTargetWidth) and
     (FDisplayHeight = FTargetHeight) then
    Exit(True);

  ReleaseD3DContextReferences;
  FDisplayRenderView := nil;
  FDisplaySwapChain := nil;
  FDisplayWindow := 0;
  FDisplayWidth := 0;
  FDisplayHeight := 0;

  Ret := CreateDXGIFactory(IID_IDXGIFactory, Factory);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateDXGIFactory display failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  FillChar(Desc, SizeOf(Desc), 0);
  Desc.BufferDesc.Width := FTargetWidth;
  Desc.BufferDesc.Height := FTargetHeight;
  Desc.BufferDesc.RefreshRate.Numerator := 0;
  Desc.BufferDesc.RefreshRate.Denominator := 1;
  Desc.BufferDesc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
  Desc.BufferDesc.ScanlineOrdering := DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
  Desc.BufferDesc.Scaling := DXGI_MODE_SCALING_UNSPECIFIED;
  Desc.SampleDesc.Count := 1;
  Desc.SampleDesc.Quality := 0;
  Desc.BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
  Desc.BufferCount := 1;
  Desc.OutputWindow := FTargetWindow;
  Desc.Windowed := True;
  Desc.SwapEffect := DXGI_SWAP_EFFECT_DISCARD;
  Desc.Flags := 0;

  Ret := Factory.CreateSwapChain(FDevice as IUnknown, Desc, FDisplaySwapChain);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateSwapChain display failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  BackBuffer := nil;
  Ret := FDisplaySwapChain.GetBuffer(0, ID3D11Texture2D, BackBuffer);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('IDXGISwapChain.GetBuffer display failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  Ret := FDevice.CreateRenderTargetView(BackBuffer, nil, FDisplayRenderView);
  if not Succeeded(Ret) then
  begin
    ErrorMessage := Format('CreateRenderTargetView display failed. HRESULT=$%.8x', [Cardinal(Ret)]);
    Exit;
  end;

  FDisplayWindow := FTargetWindow;
  FDisplayWidth := FTargetWidth;
  FDisplayHeight := FTargetHeight;
  Recreated := True;
  Result := True;
end;

destructor TNv12TextureProbe.Destroy;
begin
  ReleaseD3DContextReferences;
  FDisplayRenderView := nil;
  FDisplaySwapChain := nil;
  FSwapRenderView := nil;
  FSwapChain := nil;
  if FProbeWindow <> 0 then
  begin
    DestroyWindow(FProbeWindow);
    FProbeWindow := 0;
  end;
  inherited;
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

procedure TNv12TextureProbe.ProbeShaderDraw(Frame: PAVFrame);
var
  ChromaHeight : Integer;    // NV12 UV plane の高さ
  ErrorMessage : string;     // shader probe 失敗理由
  FlushMs      : Double;     // Flush 呼び出し時間
  ResourceViews: array[0..1] of ID3D11ShaderResourceView;
  StepWatch    : TStopwatch; // 各 step の計測
  TotalWatch   : TStopwatch; // probe 全体の計測
  UploadMs     : Double;     // Y/UV plane upload 合計時間
  Viewport     : D3D11_VIEWPORT;
begin
  if not EnsureShaderPipeline(Frame.width, Frame.height, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;

  TotalWatch := TStopwatch.StartNew;
  ChromaHeight := (Frame.height + 1) div 2;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FYTexture, 0, nil, Frame.data[0],
    Cardinal(Frame.linesize[0]), Cardinal(Frame.linesize[0] * Frame.height));
  FDeviceContext.UpdateSubresource(FUvTexture, 0, nil, Frame.data[1],
    Cardinal(Frame.linesize[1]), Cardinal(Frame.linesize[1] * ChromaHeight));
  UploadMs := StepWatch.Elapsed.TotalMilliseconds;

  FillChar(Viewport, SizeOf(Viewport), 0);
  Viewport.TopLeftX := 0;
  Viewport.TopLeftY := 0;
  Viewport.Width := Frame.width;
  Viewport.Height := Frame.height;
  Viewport.MinDepth := 0;
  Viewport.MaxDepth := 1;
  ResourceViews[0] := FYResourceView;
  ResourceViews[1] := FUvResourceView;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.IASetInputLayout(nil);
  FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  FDeviceContext.VSSetShader(FVertexShader, nil, 0);
  FDeviceContext.PSSetShader(FPixelShader, nil, 0);
  FDeviceContext.PSSetShaderResources(0, Length(ResourceViews), ResourceViews[0]);
  FDeviceContext.PSSetSamplers(0, 1, FSampler);
  FDeviceContext.RSSetViewports(1, @Viewport);
  FDeviceContext.OMSetRenderTargets(1, FRenderView, nil);
  FDeviceContext.Draw(3, 0);
  UploadMs := UploadMs + StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.Flush;
  FlushMs := StepWatch.Elapsed.TotalMilliseconds;

  WriteVideoMinerSlowLog(Format(
    'nv12_shader_probe frame=%dx%d y_stride=%d uv_stride=%d feature_level=$%.4x upload_draw_ms=%.3f flush_ms=%.3f total_ms=%.3f',
    [Frame.width, Frame.height, Frame.linesize[0], Frame.linesize[1],
     Cardinal(FFeatureLevel), UploadMs, FlushMs, TotalWatch.Elapsed.TotalMilliseconds]));
end;

procedure TNv12TextureProbe.ProbeSwapChainPresent(Frame: PAVFrame);
var
  ChromaHeight : Integer;    // NV12 UV plane の高さ
  DrawMs       : Double;     // swap chain backbuffer への描画時間
  ErrorMessage : string;     // swap chain probe 失敗理由
  PresentMs    : Double;     // Present 呼び出し時間
  Recreated    : Boolean;    // swap chain を今回作り直したか
  ResourceViews: array[0..1] of ID3D11ShaderResourceView;
  StepWatch    : TStopwatch; // 各 step の計測
  TotalWatch   : TStopwatch; // probe 全体の計測
  UploadMs     : Double;     // Y/UV plane upload 合計時間
  Viewport     : D3D11_VIEWPORT;
begin
  if not EnsureShaderPipeline(Frame.width, Frame.height, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureSwapChain(Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;

  TotalWatch := TStopwatch.StartNew;
  ChromaHeight := (Frame.height + 1) div 2;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FYTexture, 0, nil, Frame.data[0],
    Cardinal(Frame.linesize[0]), Cardinal(Frame.linesize[0] * Frame.height));
  FDeviceContext.UpdateSubresource(FUvTexture, 0, nil, Frame.data[1],
    Cardinal(Frame.linesize[1]), Cardinal(Frame.linesize[1] * ChromaHeight));
  UploadMs := StepWatch.Elapsed.TotalMilliseconds;

  FillChar(Viewport, SizeOf(Viewport), 0);
  Viewport.TopLeftX := 0;
  Viewport.TopLeftY := 0;
  Viewport.Width := FTargetWidth;
  Viewport.Height := FTargetHeight;
  Viewport.MinDepth := 0;
  Viewport.MaxDepth := 1;
  ResourceViews[0] := FYResourceView;
  ResourceViews[1] := FUvResourceView;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.IASetInputLayout(nil);
  FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  FDeviceContext.VSSetShader(FVertexShader, nil, 0);
  FDeviceContext.PSSetShader(FPixelShader, nil, 0);
  FDeviceContext.PSSetShaderResources(0, Length(ResourceViews), ResourceViews[0]);
  FDeviceContext.PSSetSamplers(0, 1, FSampler);
  FDeviceContext.RSSetViewports(1, @Viewport);
  FDeviceContext.OMSetRenderTargets(1, FSwapRenderView, nil);
  FDeviceContext.Draw(3, 0);
  DrawMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  FSwapChain.Present(0, 0);
  PresentMs := StepWatch.Elapsed.TotalMilliseconds;

  WriteVideoMinerSlowLog(Format(
    'nv12_swapchain_probe frame=%dx%d target=%dx%d y_stride=%d uv_stride=%d recreated=%s feature_level=$%.4x upload_ms=%.3f draw_ms=%.3f present_ms=%.3f total_ms=%.3f',
    [Frame.width, Frame.height, FTargetWidth, FTargetHeight,
     Frame.linesize[0], Frame.linesize[1], BoolToStr(Recreated, True),
     Cardinal(FFeatureLevel), UploadMs, DrawMs, PresentMs,
     TotalWatch.Elapsed.TotalMilliseconds]));
end;

procedure TNv12TextureProbe.DrawOverlayRect(const Rect: TRect; R, G, B, A: Single);
type
  TRectConstants = record
    RectPx  : array[0..3] of Single;
    TargetPx: array[0..3] of Single;
    Color   : array[0..3] of Single;
  end;
var
  BlendFactor: TFourSingleArray;
  Constants: TRectConstants;
begin
  if Rect.IsEmpty or (FTargetWidth <= 0) or (FTargetHeight <= 0) then
    Exit;

  Constants.RectPx[0] := Rect.Left;
  Constants.RectPx[1] := Rect.Top;
  Constants.RectPx[2] := Rect.Right;
  Constants.RectPx[3] := Rect.Bottom;
  Constants.TargetPx[0] := FTargetWidth;
  Constants.TargetPx[1] := FTargetHeight;
  Constants.TargetPx[2] := 0;
  Constants.TargetPx[3] := 0;
  Constants.Color[0] := R;
  Constants.Color[1] := G;
  Constants.Color[2] := B;
  Constants.Color[3] := A;

  FDeviceContext.UpdateSubresource(FRectConstantBuffer, 0, nil, @Constants, 0, 0);
  FDeviceContext.IASetInputLayout(nil);
  FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  FDeviceContext.VSSetShader(FRectVertexShader, nil, 0);
  FDeviceContext.VSSetConstantBuffers(0, 1, FRectConstantBuffer);
  FDeviceContext.PSSetShader(FRectPixelShader, nil, 0);
  FDeviceContext.PSSetConstantBuffers(0, 1, FRectConstantBuffer);
  FillChar(BlendFactor, SizeOf(BlendFactor), 0);
  FDeviceContext.OMSetBlendState(FAlphaBlendState, BlendFactor, $FFFFFFFF);
  FDeviceContext.Draw(6, 0);
end;

procedure TNv12TextureProbe.DrawOverlayLine(X1, Y1, X2, Y2, Thickness: Integer;
  R, G, B, A: Single);
var
  HalfThickness: Integer;
  I: Integer;
  Steps: Integer;
  X: Integer;
  Y: Integer;
begin
  Thickness := Max(1, Thickness);
  HalfThickness := Thickness div 2;
  Steps := Max(Abs(X2 - X1), Abs(Y2 - Y1));
  if Steps <= 0 then
  begin
    DrawOverlayRect(Rect(X1 - HalfThickness, Y1 - HalfThickness,
      X1 + HalfThickness + 1, Y1 + HalfThickness + 1), R, G, B, A);
    Exit;
  end;

  for I := 0 to Steps do
  begin
    X := X1 + Round((X2 - X1) * I / Steps);
    Y := Y1 + Round((Y2 - Y1) * I / Steps);
    DrawOverlayRect(Rect(X - HalfThickness, Y - HalfThickness,
      X + HalfThickness + 1, Y + HalfThickness + 1), R, G, B, A);
  end;
end;

procedure TNv12TextureProbe.DrawOverlayCircleApprox(CenterX, CenterY,
  Radius: Integer; R, G, B, A: Single);
var
  BandHeight: Integer;
  BandTop: Integer;
  BandY: Integer;
  HalfWidth: Integer;
begin
  if Radius <= 0 then
    Exit;

  BandHeight := Max(2, Radius div 5);
  BandTop := -Radius;
  while BandTop <= Radius do
  begin
    BandY := BandTop + BandHeight div 2;
    HalfWidth := Round(Sqrt(Max(0, Radius * Radius - BandY * BandY)));
    DrawOverlayRect(Rect(CenterX - HalfWidth, CenterY + BandTop,
      CenterX + HalfWidth + 1, CenterY + Min(Radius + 1, BandTop + BandHeight)),
      R, G, B, A);
    Inc(BandTop, BandHeight);
  end;
end;

function SeekBarTimeText(ValueMs: Integer): string;
var
  Hours: Integer;
  Minutes: Integer;
  Seconds: Integer;
  TotalSeconds: Integer;
begin
  TotalSeconds := Max(0, (ValueMs + 500) div 1000);
  Hours := TotalSeconds div 3600;
  Minutes := (TotalSeconds div 60) mod 60;
  Seconds := TotalSeconds mod 60;
  if Hours > 0 then
    Result := Format('%d:%.2d:%.2d', [Hours, Minutes, Seconds])
  else
    Result := Format('%d:%.2d', [Minutes, Seconds]);
end;

function SeekBarFrameText(PositionMs, MaxMs, FrameStepMs: Integer): string;
var
  SafeStepMs: Integer;
begin
  SafeStepMs := Max(1, FrameStepMs);
  Result := Format('%d / %d',
    [Max(0, PositionMs) div SafeStepMs + 1,
     Max(1, Max(0, MaxMs) div SafeStepMs + 1)]);
end;

function OverlayTextWidth(const Text: string; Scale: Integer): Integer;
var
  Ch: Char;
begin
  Result := 0;
  for Ch in Text do
  begin
    case Ch of
      '0'..'9':
        Inc(Result, Scale * 7);
      ':':
        Inc(Result, Scale * 3);
      '/':
        Inc(Result, Scale * 5);
      '.':
        Inc(Result, Scale * 3);
      'x', 'X':
        Inc(Result, Scale * 7);
      '%':
        Inc(Result, Scale * 7);
      '+', '-':
        Inc(Result, Scale * 7);
      'l', 'L':
        Inc(Result, Scale * 4);
      ' ':
        Inc(Result, Scale * 4);
    else
      Inc(Result, Scale * 7);
    end;
  end;
end;

function SeekBarToolRowTop(const State: TD3D11SeekBarOverlayState): Integer;
begin
  Result := State.Bounds.Bottom - 40;
end;

function SeekBarButtonBackAlpha(Hovered, Pressed, Active: Boolean): Single;
begin
  if Pressed then
    Result := 0.30
  else if Hovered then
    Result := 0.20
  else
    Result := 0;
end;

procedure TNv12TextureProbe.DrawOverlayDigit(X, Y, Scale, Digit: Integer;
  R, G, B, A: Single);
const
  SEGMENTS: array[0..9] of Byte = (
    $3F, $06, $5B, $4F, $66, $6D, $7D, $07, $7F, $6F);
var
  Mask: Byte;
  T: Integer;
  W: Integer;
begin
  if (Digit < 0) or (Digit > 9) then
    Exit;

  Mask := SEGMENTS[Digit];
  T := Max(1, Scale);
  W := Scale * 5;
  if (Mask and $01) <> 0 then
    DrawOverlayRect(Rect(X + T, Y, X + W, Y + T), R, G, B, A);
  if (Mask and $02) <> 0 then
    DrawOverlayRect(Rect(X + W, Y + T, X + W + T, Y + Scale * 5), R, G, B, A);
  if (Mask and $04) <> 0 then
    DrawOverlayRect(Rect(X + W, Y + Scale * 6, X + W + T, Y + Scale * 10), R, G, B, A);
  if (Mask and $08) <> 0 then
    DrawOverlayRect(Rect(X + T, Y + Scale * 10, X + W, Y + Scale * 11), R, G, B, A);
  if (Mask and $10) <> 0 then
    DrawOverlayRect(Rect(X, Y + Scale * 6, X + T, Y + Scale * 10), R, G, B, A);
  if (Mask and $20) <> 0 then
    DrawOverlayRect(Rect(X, Y + T, X + T, Y + Scale * 5), R, G, B, A);
  if (Mask and $40) <> 0 then
    DrawOverlayRect(Rect(X + T, Y + Scale * 5, X + W, Y + Scale * 6), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlayColon(X, Y, Scale: Integer; R, G, B,
  A: Single);
var
  Dot: Integer;
begin
  Dot := Max(1, Scale);
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 3, X + Scale + Dot,
    Y + Scale * 3 + Dot), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 7, X + Scale + Dot,
    Y + Scale * 7 + Dot), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlaySlash(X, Y, Scale: Integer; R, G, B,
  A: Single);
begin
  DrawOverlayRect(Rect(X + Scale * 3, Y + Scale * 2, X + Scale * 4,
    Y + Scale * 5), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale * 2, Y + Scale * 5, X + Scale * 3,
    Y + Scale * 8), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 8, X + Scale * 2,
    Y + Scale * 11), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlayDot(X, Y, Scale: Integer; R, G, B,
  A: Single);
var
  Dot: Integer;
begin
  Dot := Max(1, Scale);
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 10, X + Scale + Dot,
    Y + Scale * 10 + Dot), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlayX(X, Y, Scale: Integer; R, G, B,
  A: Single);
begin
  DrawOverlayRect(Rect(X, Y + Scale * 2, X + Scale, Y + Scale * 4),
    R, G, B, A);
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 4, X + Scale * 2,
    Y + Scale * 6), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale * 2, Y + Scale * 6, X + Scale * 3,
    Y + Scale * 8), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale * 3, Y + Scale * 4, X + Scale * 4,
    Y + Scale * 6), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 2, X + Scale * 5,
    Y + Scale * 4), R, G, B, A);
  DrawOverlayRect(Rect(X, Y + Scale * 8, X + Scale, Y + Scale * 10),
    R, G, B, A);
  DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 8, X + Scale * 5,
    Y + Scale * 10), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlayLetter(X, Y, Scale: Integer; Ch: Char;
  R, G, B, A: Single);
begin
  if Ch = 'p' then
  begin
    DrawOverlayRect(Rect(X, Y + Scale * 3, X + Scale, Y + Scale * 12),
      R, G, B, A);
    DrawOverlayRect(Rect(X + Scale, Y + Scale * 3, X + Scale * 5,
      Y + Scale * 4), R, G, B, A);
    DrawOverlayRect(Rect(X + Scale * 5, Y + Scale * 4, X + Scale * 6,
      Y + Scale * 7), R, G, B, A);
    DrawOverlayRect(Rect(X + Scale, Y + Scale * 7, X + Scale * 5,
      Y + Scale * 8), R, G, B, A);
    Exit;
  end;

  case UpCase(Ch) of
    'V':
    begin
      DrawOverlayRect(Rect(X, Y + Scale, X + Scale, Y + Scale * 8), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 8, X + Scale * 2,
        Y + Scale * 10), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 2, Y + Scale * 10, X + Scale * 4,
        Y + Scale * 11), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 8, X + Scale * 5,
        Y + Scale * 10), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 5, Y + Scale, X + Scale * 6,
        Y + Scale * 8), R, G, B, A);
    end;
    'O':
    begin
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 3, X + Scale * 5,
        Y + Scale * 4), R, G, B, A);
      DrawOverlayRect(Rect(X, Y + Scale * 4, X + Scale, Y + Scale * 9),
        R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 5, Y + Scale * 4, X + Scale * 6,
        Y + Scale * 9), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 9, X + Scale * 5,
        Y + Scale * 10), R, G, B, A);
    end;
    'L':
    begin
      DrawOverlayRect(Rect(X, Y + Scale, X + Scale, Y + Scale * 10),
        R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 9, X + Scale * 4,
        Y + Scale * 10), R, G, B, A);
    end;
    'P':
    begin
      DrawOverlayRect(Rect(X, Y + Scale, X + Scale, Y + Scale * 10),
        R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale, X + Scale * 5,
        Y + Scale * 2), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 5, Y + Scale * 2, X + Scale * 6,
        Y + Scale * 5), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 5, X + Scale * 5,
        Y + Scale * 6), R, G, B, A);
    end;
    'S':
    begin
      DrawOverlayRect(Rect(X + Scale, Y + Scale, X + Scale * 6,
        Y + Scale * 2), R, G, B, A);
      DrawOverlayRect(Rect(X, Y + Scale * 2, X + Scale,
        Y + Scale * 5), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 5, X + Scale * 5,
        Y + Scale * 6), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 5, Y + Scale * 6, X + Scale * 6,
        Y + Scale * 9), R, G, B, A);
      DrawOverlayRect(Rect(X, Y + Scale * 9, X + Scale * 5,
        Y + Scale * 10), R, G, B, A);
    end;
    'T':
    begin
      DrawOverlayRect(Rect(X, Y + Scale, X + Scale * 6,
        Y + Scale * 2), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 2, Y + Scale * 2, X + Scale * 4,
        Y + Scale * 10), R, G, B, A);
    end;
    'N':
    begin
      DrawOverlayRect(Rect(X, Y + Scale, X + Scale, Y + Scale * 10),
        R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 5, Y + Scale, X + Scale * 6,
        Y + Scale * 10), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 2, X + Scale * 2,
        Y + Scale * 4), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 2, Y + Scale * 4, X + Scale * 3,
        Y + Scale * 6), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 3, Y + Scale * 6, X + Scale * 4,
        Y + Scale * 8), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 8, X + Scale * 5,
        Y + Scale * 10), R, G, B, A);
    end;
    'E':
    begin
      DrawOverlayRect(Rect(X, Y + Scale, X + Scale, Y + Scale * 10),
        R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale, X + Scale * 6,
        Y + Scale * 2), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 5, X + Scale * 5,
        Y + Scale * 6), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale, Y + Scale * 9, X + Scale * 6,
        Y + Scale * 10), R, G, B, A);
    end;
    '%':
    begin
      DrawOverlayRect(Rect(X, Y + Scale * 2, X + Scale * 3,
        Y + Scale * 3), R, G, B, A);
      DrawOverlayRect(Rect(X, Y + Scale * 3, X + Scale,
        Y + Scale * 5), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 2, Y + Scale * 3, X + Scale * 3,
        Y + Scale * 5), R, G, B, A);
      DrawOverlayRect(Rect(X, Y + Scale * 5, X + Scale * 3,
        Y + Scale * 6), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 6, X + Scale * 7,
        Y + Scale * 7), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 7, X + Scale * 5,
        Y + Scale * 9), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 6, Y + Scale * 7, X + Scale * 7,
        Y + Scale * 9), R, G, B, A);
      DrawOverlayRect(Rect(X + Scale * 4, Y + Scale * 9, X + Scale * 7,
        Y + Scale * 10), R, G, B, A);
      DrawOverlaySlash(X + Scale, Y, Scale, R, G, B, A);
    end;
  end;
end;

procedure TNv12TextureProbe.DrawOverlayPlus(X, Y, Scale: Integer; R, G, B,
  A: Single);
begin
  DrawOverlayRect(Rect(X + Scale * 3, Y + Scale * 3, X + Scale * 4,
    Y + Scale * 9), R, G, B, A);
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 5, X + Scale * 6,
    Y + Scale * 7), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlayMinus(X, Y, Scale: Integer; R, G, B,
  A: Single);
begin
  DrawOverlayRect(Rect(X + Scale, Y + Scale * 5, X + Scale * 6,
    Y + Scale * 7), R, G, B, A);
end;

procedure TNv12TextureProbe.DrawOverlayText(X, Y, Scale: Integer;
  const Text: string; R, G, B, A: Single);
var
  Ch: Char;
begin
  for Ch in Text do
  begin
    case Ch of
      '0'..'9':
      begin
        DrawOverlayDigit(X, Y, Scale, Ord(Ch) - Ord('0'), R, G, B, A);
        Inc(X, Scale * 7);
      end;
      ':':
      begin
        DrawOverlayColon(X, Y, Scale, R, G, B, A);
        Inc(X, Scale * 3);
      end;
      '/':
      begin
        DrawOverlaySlash(X, Y, Scale, R, G, B, A);
        Inc(X, Scale * 5);
      end;
      '.':
      begin
        DrawOverlayDot(X, Y, Scale, R, G, B, A);
        Inc(X, Scale * 3);
      end;
      'x', 'X':
      begin
        DrawOverlayX(X, Y, Scale, R, G, B, A);
        Inc(X, Scale * 7);
      end;
      '%':
      begin
        DrawOverlayLetter(X, Y, Scale, Ch, R, G, B, A);
        Inc(X, Scale * 7);
      end;
      '+':
      begin
        DrawOverlayPlus(X, Y, Scale, R, G, B, A);
        Inc(X, Scale * 7);
      end;
      '-':
      begin
        DrawOverlayMinus(X, Y, Scale, R, G, B, A);
        Inc(X, Scale * 7);
      end;
      'l', 'L':
      begin
        DrawOverlayLetter(X, Y, Scale, Ch, R, G, B, A);
        Inc(X, Scale * 4);
      end;
      ' ':
        Inc(X, Scale * 4);
    else
    begin
      DrawOverlayLetter(X, Y, Scale, Ch, R, G, B, A);
      Inc(X, Scale * 7);
    end;
    end;
  end;
end;

procedure TNv12TextureProbe.DrawSeekBarTimeText(
  const State: TD3D11SeekBarOverlayState);
var
  Scale: Integer;
  Text: string;
  TextWidth: Integer;
  X: Integer;
  Y: Integer;
begin
  if (State.MaxMs <= 0) or State.Bounds.IsEmpty then
    Exit;

  Scale := 2;
  if State.CheckEnabled then
    Text := SeekBarFrameText(State.PositionMs, State.MaxMs, State.FrameStepMs)
  else
    Text := SeekBarTimeText(State.PositionMs) + ' / ' + SeekBarTimeText(State.MaxMs);
  TextWidth := OverlayTextWidth(Text, Scale);
  X := State.Bounds.Left + (State.Bounds.Width - TextWidth) div 2;
  Y := State.Bounds.Bottom - 35;
  DrawOverlayText(X + 1, Y + 1, Scale, Text, 0, 0, 0, 0.55);
  DrawOverlayText(X, Y, Scale, Text, 1, 1, 1, 0.86);
end;

procedure TNv12TextureProbe.DrawSeekBarMuteIcon(const IconRect: TRect;
  const State: TD3D11SeekBarOverlayState);
var
  Alpha: Single;
  CenterY: Integer;
begin
  if IconRect.IsEmpty then
    Exit;

  if State.Muted or (State.VolumePercent <= 0) then
    Alpha := 0.88
  else
    Alpha := 0.72;
  CenterY := IconRect.Top + IconRect.Height div 2;
  DrawOverlayRect(Rect(IconRect.Left + 5, CenterY - 4, IconRect.Left + 10,
    CenterY + 5), 1, 1, 1, Alpha);
  DrawOverlayRect(Rect(IconRect.Left + 10, CenterY - 7, IconRect.Left + 14,
    CenterY + 8), 1, 1, 1, Alpha);
  DrawOverlayRect(Rect(IconRect.Left + 15, CenterY - 8, IconRect.Left + 17,
    CenterY - 5), 1, 1, 1, Alpha);
  DrawOverlayRect(Rect(IconRect.Left + 17, CenterY - 5, IconRect.Left + 19,
    CenterY + 6), 1, 1, 1, Alpha);
  DrawOverlayRect(Rect(IconRect.Left + 15, CenterY + 6, IconRect.Left + 17,
    CenterY + 9), 1, 1, 1, Alpha);
  if State.Muted or (State.VolumePercent <= 0) then
  begin
    DrawOverlayRect(Rect(IconRect.Left + 21, CenterY - 7, IconRect.Left + 23,
      CenterY + 8), 0.93, 0.20, 0.18, 0.92);
    DrawOverlayRect(Rect(IconRect.Left + 18, CenterY - 1, IconRect.Left + 26,
      CenterY + 2), 0.93, 0.20, 0.18, 0.92);
  end;
end;

procedure TNv12TextureProbe.DrawSeekBarVolume(
  const State: TD3D11SeekBarOverlayState);
var
  BackAlpha: Single;
  FilledRect: TRect;
  FillRatio: Double;
  LabelText: string;
  LabelY: Integer;
  Scale: Integer;
  ToolTop: Integer;
  TrackRect: TRect;
begin
  if State.Bounds.IsEmpty then
    Exit;

  Scale := 2;
  ToolTop := SeekBarToolRowTop(State);
  LabelText := Format('Vol %d%%', [Max(0, Min(100, State.VolumePercent))]);
  LabelY := ToolTop;
  DrawOverlayText(State.Bounds.Left + 22 + 1, LabelY + 1, Scale, LabelText,
    0, 0, 0, 0.55);
  DrawOverlayText(State.Bounds.Left + 22, LabelY, Scale, LabelText,
    1, 1, 1, 0.86);

  TrackRect := Rect(State.Bounds.Left + 22, ToolTop + Scale * 13,
    State.Bounds.Left + 112, ToolTop + Scale * 13 + 5);
  BackAlpha := SeekBarButtonBackAlpha(State.VolumeHovered,
    State.VolumeDragging, False);
  if BackAlpha > 0 then
    DrawOverlayRect(Rect(TrackRect.Left - 8, LabelY - 4, TrackRect.Right + 8,
      TrackRect.Bottom + 6), 1, 1, 1, BackAlpha);
  DrawOverlayRect(TrackRect, 1, 1, 1, 0.26);

  FillRatio := Max(0, Min(100, State.VolumePercent)) / 100;
  FilledRect := TrackRect;
  FilledRect.Right := FilledRect.Left + Round(FilledRect.Width * FillRatio);
  if FilledRect.Right <= FilledRect.Left then
    Exit;

  if State.Muted then
    DrawOverlayRect(FilledRect, 0.93, 0.20, 0.18, 0.72)
  else
    DrawOverlayRect(FilledRect, 0.52, 0.82, 1.0, 0.82);
end;

procedure TNv12TextureProbe.DrawSeekBarPlaybackRate(
  const State: TD3D11SeekBarOverlayState);
var
  Active: Boolean;
  BackAlpha: Single;
  MuteRect: TRect;
  RateRect: TRect;
  Scale: Integer;
  Text: string;
  TextWidth: Integer;
  ToolTop: Integer;
  X: Integer;
  Y: Integer;
begin
  if State.Bounds.IsEmpty then
    Exit;

  ToolTop := SeekBarToolRowTop(State);
  MuteRect := Rect(State.Bounds.Left + 134, ToolTop, State.Bounds.Left + 162,
    ToolTop + 28);
  BackAlpha := SeekBarButtonBackAlpha(State.MuteHovered, State.MutePressed,
    State.Muted);
  if BackAlpha > 0 then
    DrawOverlayRect(MuteRect, 1, 1, 1, BackAlpha);
  DrawSeekBarMuteIcon(MuteRect, State);

  Text := State.PlaybackRateText;
  if Text = '' then
    Text := '1.0x';
  Scale := 2;
  TextWidth := OverlayTextWidth(Text, Scale);
  RateRect := Rect(MuteRect.Right + 12, MuteRect.Top, MuteRect.Right + 66,
    MuteRect.Bottom);
  X := RateRect.Left + (RateRect.Width - TextWidth) div 2;
  Y := RateRect.Top + (RateRect.Height - Scale * 11) div 2;
  Active := not SameText(Text, '1.0x');
  BackAlpha := SeekBarButtonBackAlpha(State.PlaybackRateHovered,
    State.PlaybackRatePressed, Active);
  if BackAlpha > 0 then
    DrawOverlayRect(Rect(X - 8, Y - 6, X + TextWidth + 8, Y + Scale * 12 + 4),
      0.95, 0.78, 0.20, BackAlpha);
  DrawOverlayText(X + 1, Y + 1, Scale, Text, 0, 0, 0, 0.55);
  if Active then
    DrawOverlayText(X, Y, Scale, Text, 0.95, 0.78, 0.20, 0.92)
  else
    DrawOverlayText(X, Y, Scale, Text, 1, 1, 1, 0.72);
end;

procedure TNv12TextureProbe.DrawSeekBarEndAction(
  const State: TD3D11SeekBarOverlayState);
var
  BackAlpha: Single;
  ButtonRect: TRect;
  Scale: Integer;
  Text: string;
  TextWidth: Integer;
  ToolTop: Integer;
  X: Integer;
  Y: Integer;
begin
  if State.Bounds.IsEmpty then
    Exit;

  Text := State.EndActionText;
  if Text = '' then
    Text := 'Stop';
  Scale := 2;
  TextWidth := OverlayTextWidth(Text, Scale);
  ToolTop := SeekBarToolRowTop(State);
  ButtonRect := Rect(State.Bounds.Right - 110, ToolTop, State.Bounds.Right - 56,
    ToolTop + 28);
  X := ButtonRect.Left + (ButtonRect.Width - TextWidth) div 2;
  Y := ButtonRect.Top + (ButtonRect.Height - Scale * 11) div 2;
  BackAlpha := SeekBarButtonBackAlpha(State.EndActionHovered,
    State.EndActionPressed, False);
  if BackAlpha > 0 then
    DrawOverlayRect(ButtonRect, 1, 1, 1, BackAlpha);
  DrawOverlayText(X + 1, Y + 1, Scale, Text, 0, 0, 0, 0.55);
  DrawOverlayText(X, Y, Scale, Text, 1, 1, 1, 0.78);
end;

procedure TNv12TextureProbe.DrawSeekBarChapterButtons(
  const State: TD3D11SeekBarOverlayState);
var
  AddRect: TRect;
  BackAlpha: Single;
  CheckRect: TRect;
  DeleteRect: TRect;
  EndRect: TRect;
  FullRect: TRect;
  Scale: Integer;
  TextWidth: Integer;
  ToolTop: Integer;
  X: Integer;
  Y: Integer;
begin
  if State.Bounds.IsEmpty or (State.Bounds.Width < 520) then
    Exit;

  Scale := 2;
  ToolTop := SeekBarToolRowTop(State);
  FullRect := Rect(State.Bounds.Right - 48, ToolTop - 1, State.Bounds.Right - 14,
    ToolTop + 33);
  EndRect := Rect(FullRect.Left - 62, FullRect.Top, FullRect.Left - 8,
    FullRect.Bottom);
  CheckRect := Rect(EndRect.Left - 84, EndRect.Top, EndRect.Left - 8,
    EndRect.Bottom);
  DeleteRect := Rect(CheckRect.Left - 38, CheckRect.Top, CheckRect.Left - 6,
    CheckRect.Bottom);
  AddRect := Rect(DeleteRect.Left - 38, DeleteRect.Top, DeleteRect.Left - 6,
    DeleteRect.Bottom);

  BackAlpha := SeekBarButtonBackAlpha(State.AddChapterHovered,
    State.AddChapterPressed, False);
  if BackAlpha > 0 then
    DrawOverlayRect(AddRect, 1, 1, 1, BackAlpha);
  TextWidth := OverlayTextWidth('+', Scale);
  X := AddRect.Left + (AddRect.Width - TextWidth) div 2;
  Y := AddRect.Top + (AddRect.Height - Scale * 11) div 2;
  DrawOverlayText(X + 1, Y + 1, Scale, '+', 0, 0, 0, 0.55);
  DrawOverlayText(X, Y, Scale, '+', 1, 1, 1, 0.78);

  BackAlpha := SeekBarButtonBackAlpha(State.DeleteChapterHovered,
    State.DeleteChapterPressed, False);
  if BackAlpha > 0 then
    DrawOverlayRect(DeleteRect, 1, 1, 1, BackAlpha);
  TextWidth := OverlayTextWidth('-', Scale);
  X := DeleteRect.Left + (DeleteRect.Width - TextWidth) div 2;
  Y := DeleteRect.Top + (DeleteRect.Height - Scale * 11) div 2;
  DrawOverlayText(X + 1, Y + 1, Scale, '-', 0, 0, 0, 0.55);
  DrawOverlayText(X, Y, Scale, '-', 1, 1, 1, 0.78);

  BackAlpha := SeekBarButtonBackAlpha(State.CheckHovered, State.CheckPressed,
    State.CheckEnabled);
  if BackAlpha > 0 then
    DrawOverlayRect(CheckRect, 0.91, 0.14, 0.14, BackAlpha);
  TextWidth := OverlayTextWidth('Check', Scale);
  X := CheckRect.Left + (CheckRect.Width - TextWidth) div 2;
  Y := CheckRect.Top + (CheckRect.Height - Scale * 11) div 2;
  DrawOverlayText(X + 1, Y + 1, Scale, 'Check', 0, 0, 0, 0.55);
  if State.CheckEnabled then
    DrawOverlayText(X, Y, Scale, 'Check', 0.95, 0.20, 0.20, 0.95)
  else
    DrawOverlayText(X, Y, Scale, 'Check', 1, 1, 1, 0.78);
end;

procedure TNv12TextureProbe.DrawSeekBarFullScreen(
  const State: TD3D11SeekBarOverlayState);
var
  BackAlpha: Single;
  Bottom: Integer;
  CenterX: Integer;
  CenterY: Integer;
  Head: Integer;
  IconRect: TRect;
  Inset: Integer;
  L: Integer;
  Left: Integer;
  PenWidth: Integer;
  R: Integer;
  Right: Integer;
  T: Integer;
  Top: Integer;
  B: Integer;
  ToolTop: Integer;
  WindowRect: TRect;
begin
  if State.Bounds.IsEmpty then
    Exit;

  ToolTop := SeekBarToolRowTop(State);
  IconRect := Rect(State.Bounds.Right - 48, ToolTop - 1,
    State.Bounds.Right - 14, ToolTop + 33);
  BackAlpha := SeekBarButtonBackAlpha(State.FullScreenHovered,
    State.FullScreenPressed, False);
  if BackAlpha > 0 then
    DrawOverlayRect(IconRect, 1, 1, 1, BackAlpha);
  Left := IconRect.Left;
  Top := IconRect.Top;
  Right := IconRect.Right - 1;
  Bottom := IconRect.Bottom - 1;
  CenterX := IconRect.Left + IconRect.Width div 2;
  CenterY := IconRect.Top + IconRect.Height div 2;
  Inset := 7;
  Head := 7;
  PenWidth := 2;

  if State.FullScreen then
  begin
    WindowRect := Rect(CenterX - 7, CenterY - 6, CenterX + 8, CenterY + 7);
    DrawOverlayLine(WindowRect.Left, WindowRect.Top, WindowRect.Right,
      WindowRect.Top, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Right, WindowRect.Top, WindowRect.Right,
      WindowRect.Bottom, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Right, WindowRect.Bottom, WindowRect.Left,
      WindowRect.Bottom, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Left, WindowRect.Bottom, WindowRect.Left,
      WindowRect.Top, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(Left + Inset, Top + Inset, WindowRect.Left,
      WindowRect.Top, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Left, WindowRect.Top, WindowRect.Left - Head,
      WindowRect.Top, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Left, WindowRect.Top, WindowRect.Left,
      WindowRect.Top - Head, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(Right - Inset, Top + Inset, WindowRect.Right,
      WindowRect.Top, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Right, WindowRect.Top, WindowRect.Right + Head,
      WindowRect.Top, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Right, WindowRect.Top, WindowRect.Right,
      WindowRect.Top - Head, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(Left + Inset, Bottom - Inset, WindowRect.Left,
      WindowRect.Bottom, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Left, WindowRect.Bottom, WindowRect.Left - Head,
      WindowRect.Bottom, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Left, WindowRect.Bottom, WindowRect.Left,
      WindowRect.Bottom + Head, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(Right - Inset, Bottom - Inset, WindowRect.Right,
      WindowRect.Bottom, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Right, WindowRect.Bottom, WindowRect.Right + Head,
      WindowRect.Bottom, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(WindowRect.Right, WindowRect.Bottom, WindowRect.Right,
      WindowRect.Bottom + Head, PenWidth, 1, 1, 1, 0.78);
  end
  else
  begin
    L := Left + Inset;
    T := Top + Inset;
    R := Right - Inset;
    B := Bottom - Inset;

    DrawOverlayLine(CenterX - 5, CenterY - 5, L, T, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(L, T, L + Head, T, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(L, T, L, T + Head, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(CenterX + 5, CenterY - 5, R, T, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(R, T, R - Head, T, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(R, T, R, T + Head, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(CenterX - 5, CenterY + 5, L, B, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(L, B, L + Head, B, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(L, B, L, B - Head, PenWidth, 1, 1, 1, 0.78);

    DrawOverlayLine(CenterX + 5, CenterY + 5, R, B, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(R, B, R - Head, B, PenWidth, 1, 1, 1, 0.78);
    DrawOverlayLine(R, B, R, B - Head, PenWidth, 1, 1, 1, 0.78);
  end;
end;

procedure TNv12TextureProbe.DrawTransportButtonBackground(
  const ButtonRect: TRect);
begin
  if ButtonRect.IsEmpty then
    Exit;

  DrawOverlayRect(ButtonRect, 0, 0, 0, 0.36);
end;

procedure TNv12TextureProbe.DrawTransportTriangle(CenterX, CenterY, Width,
  Height, Direction: Integer; R, G, B, A: Single);
var
  HalfHeight: Integer;
  I: Integer;
  Ratio: Double;
  X: Integer;
begin
  if (Width <= 0) or (Height <= 0) then
    Exit;

  for I := 0 to Width - 1 do
  begin
    Ratio := (I + 1) / Width;
    HalfHeight := Max(1, Round(Height * Ratio / 2));
    if Direction >= 0 then
      X := CenterX + Width div 2 - I
    else
      X := CenterX - Width div 2 + I;
    DrawOverlayRect(Rect(X, CenterY - HalfHeight, X + 2,
      CenterY + HalfHeight + 1), R, G, B, A);
  end;
end;

procedure TNv12TextureProbe.DrawTransportEdgeIcon(const ButtonRect: TRect;
  Forward: Boolean);
var
  CenterX: Integer;
  CenterY: Integer;
  Height: Integer;
  LineX: Integer;
  TriangleCenterX: Integer;
  Width: Integer;
begin
  if ButtonRect.IsEmpty then
    Exit;

  DrawTransportButtonBackground(ButtonRect);
  CenterX := (ButtonRect.Left + ButtonRect.Right) div 2;
  CenterY := (ButtonRect.Top + ButtonRect.Bottom) div 2;
  Width := Max(12, ButtonRect.Width div 4);
  Height := Max(18, ButtonRect.Height div 3);
  if Forward then
  begin
    LineX := CenterX + Width div 2 + 5;
    TriangleCenterX := CenterX - 2;
    DrawTransportTriangle(TriangleCenterX, CenterY, Width, Height, 1,
      1, 1, 1, 0.82);
  end
  else
  begin
    LineX := CenterX - Width div 2 - 5;
    TriangleCenterX := CenterX + 2;
    DrawTransportTriangle(TriangleCenterX, CenterY, Width, Height, -1,
      1, 1, 1, 0.82);
  end;
  DrawOverlayRect(Rect(LineX - 2, CenterY - Height div 2, LineX + 2,
    CenterY + Height div 2), 1, 1, 1, 0.82);
end;

procedure TNv12TextureProbe.DrawTransportSkipIcon(const ButtonRect: TRect;
  Forward: Boolean);
var
  Angle: Double;
  CenterY: Double;
  CurrentPoint: TPoint;
  HeadX: Integer;
  HeadY: Integer;
  I: Integer;
  LocalX: Integer;
  NextPoint: TPoint;
  PenWidth: Integer;
  RadiusX: Double;
  RadiusY: Double;
  Size: Integer;
begin
  if ButtonRect.IsEmpty then
    Exit;

  DrawTransportButtonBackground(ButtonRect);
  Size := Min(ButtonRect.Width, ButtonRect.Height);
  CenterY := ButtonRect.Top + Size * 0.55;
  RadiusX := Size * 0.29;
  RadiusY := Size * 0.28;
  PenWidth := Max(3, Round(Size * 0.075));

  CurrentPoint := Point(0, 0);
  for I := 0 to 23 do
  begin
    Angle := (210 - (190 * I / 23)) * Pi / 180;
    LocalX := Round(Size * 0.50 + Cos(Angle) * RadiusX);
    if not Forward then
      LocalX := Size - LocalX;
    NextPoint := Point(ButtonRect.Left + LocalX,
      Round(CenterY + Sin(Angle) * RadiusY));
    if I > 0 then
      DrawOverlayLine(CurrentPoint.X, CurrentPoint.Y, NextPoint.X,
        NextPoint.Y, PenWidth, 1, 1, 1, 0.80);
    CurrentPoint := NextPoint;
  end;

  if Forward then
  begin
    HeadX := ButtonRect.Left + Round(Size * 0.70);
    HeadY := ButtonRect.Top + Round(Size * 0.44);
    DrawTransportTriangle(HeadX, HeadY, Max(8, Round(Size * 0.17)),
      Max(12, Round(Size * 0.22)), 1, 1, 1, 1, 0.80);
  end
  else
  begin
    HeadX := ButtonRect.Left + Round(Size * 0.30);
    HeadY := ButtonRect.Top + Round(Size * 0.44);
    DrawTransportTriangle(HeadX, HeadY, Max(8, Round(Size * 0.17)),
      Max(12, Round(Size * 0.22)), -1, 1, 1, 1, 0.80);
  end;
end;

procedure TNv12TextureProbe.DrawTransportPlayPauseIcon(const ButtonRect: TRect;
  Playing: Boolean);
var
  BarHeight: Integer;
  BarWidth: Integer;
  CenterX: Integer;
  CenterY: Integer;
  Gap: Integer;
  TriangleHeight: Integer;
  TriangleWidth: Integer;
begin
  if ButtonRect.IsEmpty then
    Exit;

  DrawTransportButtonBackground(ButtonRect);
  CenterX := (ButtonRect.Left + ButtonRect.Right) div 2;
  CenterY := (ButtonRect.Top + ButtonRect.Bottom) div 2;
  if Playing then
  begin
    BarWidth := Max(5, ButtonRect.Width div 10);
    BarHeight := Max(20, ButtonRect.Height div 3);
    Gap := Max(5, ButtonRect.Width div 12);
    DrawOverlayRect(Rect(CenterX - Gap - BarWidth, CenterY - BarHeight div 2,
      CenterX - Gap, CenterY + BarHeight div 2), 1, 1, 1, 0.86);
    DrawOverlayRect(Rect(CenterX + Gap, CenterY - BarHeight div 2,
      CenterX + Gap + BarWidth, CenterY + BarHeight div 2), 1, 1, 1, 0.86);
  end
  else
  begin
    TriangleWidth := Max(18, ButtonRect.Width div 3);
    TriangleHeight := Max(24, ButtonRect.Height div 3);
    DrawTransportTriangle(CenterX + 2, CenterY, TriangleWidth,
      TriangleHeight, 1, 1, 1, 1, 0.86);
  end;
end;

procedure TNv12TextureProbe.DrawTransportOverlay(
  const State: TD3D11SeekBarOverlayState);
begin
  if not State.TransportVisible then
    Exit;

  DrawTransportEdgeIcon(State.FirstButton, False);
  DrawTransportSkipIcon(State.SkipBackwardButton, False);
  DrawTransportPlayPauseIcon(State.PlayPauseButton, State.TransportPlaying);
  DrawTransportSkipIcon(State.SkipForwardButton, True);
  DrawTransportEdgeIcon(State.LastButton, True);
end;

function TNv12TextureProbe.DrawSeekBarOverlay(
  const State: TD3D11SeekBarOverlayState): Double;
var
  Chapter: TD3D11SeekBarOverlayChapter;
  ErrorMessage: string;
  FilledRect: TRect;
  HighlightRect: TRect;
  HoverGuideRect: TRect;
  HoverRatio: Double;
  HoverX: Integer;
  KnobCenterY: Integer;
  KnobCoreRadius: Integer;
  KnobHaloRadius: Integer;
  KnobInnerRadius: Integer;
  MarkerRect: TRect;
  MarkerX: Integer;
  PositionRatio: Double;
  StepWatch: TStopwatch;
  TrackRect: TRect;
  BlendFactor: TFourSingleArray;
  DrawSeekBar: Boolean;
  Viewport: D3D11_VIEWPORT;
begin
  Result := 0;
  DrawSeekBar := State.Visible and (not State.Bounds.IsEmpty) and
    (not State.Track.IsEmpty) and (State.MaxMs > 0);
  if (not DrawSeekBar) and (not State.TransportVisible) then
    Exit;
  if not EnsureRectPipeline(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;

  StepWatch := TStopwatch.StartNew;
  FillChar(Viewport, SizeOf(Viewport), 0);
  Viewport.TopLeftX := 0;
  Viewport.TopLeftY := 0;
  Viewport.Width := FTargetWidth;
  Viewport.Height := FTargetHeight;
  Viewport.MinDepth := 0;
  Viewport.MaxDepth := 1;
  FDeviceContext.RSSetViewports(1, @Viewport);
  FDeviceContext.OMSetRenderTargets(1, FDisplayRenderView, nil);

  DrawTransportOverlay(State);

  if DrawSeekBar then
  begin
    DrawOverlayRect(State.Bounds, 0, 0, 0, 0.36);

    TrackRect := State.Track;
    DrawOverlayRect(Rect(TrackRect.Left - 1, TrackRect.Top - 3,
      TrackRect.Right + 1, TrackRect.Bottom + 3), 0, 0, 0, 0.24);
    DrawOverlayRect(TrackRect, 1, 1, 1, 0.32);

    PositionRatio := State.PositionMs / State.MaxMs;
    PositionRatio := Max(0.0, Min(1.0, PositionRatio));
    MarkerX := TrackRect.Left + Round(TrackRect.Width * PositionRatio);
    FilledRect := TrackRect;
    FilledRect.Right := Max(FilledRect.Left + 1, MarkerX);
    DrawOverlayRect(FilledRect, 0.25, 0.63, 0.94, 0.90);
    HighlightRect := FilledRect;
    HighlightRect.Bottom := Min(HighlightRect.Bottom, HighlightRect.Top + 2);
    DrawOverlayRect(HighlightRect, 0.58, 0.84, 1.0, 0.52);

    if (State.HoverPositionMs >= 0) and (State.HoverPositionMs <= State.MaxMs) then
    begin
      HoverRatio := State.HoverPositionMs / State.MaxMs;
      HoverRatio := Max(0.0, Min(1.0, HoverRatio));
      HoverX := TrackRect.Left + Round(TrackRect.Width * HoverRatio);
      if State.Dragging then
        HoverGuideRect := Rect(HoverX - 2, TrackRect.Top - 17, HoverX + 3,
          TrackRect.Bottom + 24)
      else
        HoverGuideRect := Rect(HoverX - 1, TrackRect.Top - 12, HoverX + 2,
          TrackRect.Bottom + 18);
      if State.Dragging then
        DrawOverlayRect(HoverGuideRect, 0.70, 0.88, 1.0, 0.72)
      else
        DrawOverlayRect(HoverGuideRect, 1.0, 1.0, 1.0, 0.34);
    end;

    for Chapter in State.Chapters do
    begin
      if (Chapter.PositionMs < 0) or (Chapter.PositionMs > State.MaxMs) then
        Continue;
      MarkerX := TrackRect.Left + Round(TrackRect.Width * Chapter.PositionMs / State.MaxMs);
      MarkerRect := Rect(MarkerX - 1, TrackRect.Top - 6, MarkerX + 2, TrackRect.Bottom + 9);
      case Chapter.Severity of
        2:
        begin
          DrawOverlayRect(MarkerRect, 0.93, 0.20, 0.18, 0.95);
          DrawOverlayRect(Rect(MarkerX - 4, TrackRect.Bottom + 8,
            MarkerX + 5, TrackRect.Bottom + 11), 0.93, 0.20, 0.18, 0.88);
        end;
        1:
        begin
          DrawOverlayRect(MarkerRect, 0.95, 0.78, 0.20, 0.95);
          DrawOverlayRect(Rect(MarkerX - 4, TrackRect.Bottom + 8,
            MarkerX + 5, TrackRect.Bottom + 11), 0.95, 0.78, 0.20, 0.88);
        end;
      else
        begin
          DrawOverlayRect(MarkerRect, 0.18, 0.85, 0.38, 0.95);
          DrawOverlayRect(Rect(MarkerX - 4, TrackRect.Bottom + 8,
            MarkerX + 5, TrackRect.Bottom + 11), 0.18, 0.85, 0.38, 0.88);
        end;
      end;
    end;

    MarkerX := TrackRect.Left + Round(TrackRect.Width * PositionRatio);
    KnobCenterY := TrackRect.Top + TrackRect.Height div 2;
    if State.Dragging then
    begin
      KnobHaloRadius := 24;
      KnobCoreRadius := 13;
      KnobInnerRadius := 8;
    end
    else if (State.HoverPositionMs >= 0) and (State.HoverPositionMs <= State.MaxMs) then
    begin
      KnobHaloRadius := 22;
      KnobCoreRadius := 12;
      KnobInnerRadius := 7;
    end
    else
    begin
      KnobHaloRadius := 20;
      KnobCoreRadius := 11;
      KnobInnerRadius := 6;
    end;
    DrawOverlayCircleApprox(MarkerX, KnobCenterY, KnobHaloRadius,
      0.25, 0.63, 0.94, 0.18);
    DrawOverlayCircleApprox(MarkerX, KnobCenterY, KnobCoreRadius,
      0.25, 0.63, 0.94, 0.96);
    DrawOverlayCircleApprox(MarkerX, KnobCenterY, KnobInnerRadius,
      0.52, 0.82, 1.0, 1.0);

    DrawSeekBarTimeText(State);
    DrawSeekBarVolume(State);
    DrawSeekBarPlaybackRate(State);
    DrawSeekBarEndAction(State);
    DrawSeekBarChapterButtons(State);
    DrawSeekBarFullScreen(State);
  end;

  FillChar(BlendFactor, SizeOf(BlendFactor), 0);
  FDeviceContext.OMSetBlendState(nil, BlendFactor, $FFFFFFFF);
  Result := StepWatch.Elapsed.TotalMilliseconds;
end;

function TNv12TextureProbe.PresentFrame(Frame: PAVFrame): Boolean;
var
  ChromaHeight : Integer;    // NV12 UV plane の高さ
  ClearColor   : TFourSingleArray; // letterbox 領域を塗る黒
  ClearMs      : Double;     // backbuffer clear 時間
  DrawMs       : Double;     // 実 backbuffer への描画時間
  ErrorMessage : string;     // D3D 表示失敗理由
  PresentMs    : Double;     // Present 呼び出し時間
  Recreated    : Boolean;    // swap chain を今回作り直したか
  OverlayMs    : Double;     // D3D overlay 描画時間
  ResourceViews: array[0..1] of ID3D11ShaderResourceView;
  StepWatch    : TStopwatch; // 各 step の計測
  TotalWatch   : TStopwatch; // D3D 表示全体の計測
  UploadMs     : Double;     // Y/UV plane upload 合計時間
  ViewHeight   : Integer;    // アスペクト比維持後の描画高さ
  ViewLeft     : Integer;    // アスペクト比維持後の描画左位置
  ViewTop      : Integer;    // アスペクト比維持後の描画上位置
  Viewport     : D3D11_VIEWPORT;
  ViewWidth    : Integer;    // アスペクト比維持後の描画幅
begin
  Result := False;
  GlobalD3DFramePresented := False;
  if (not Nv12TextureD3DDisplayEnabled) or (not GlobalD3DDisplayAllowed) then
    Exit;
  if (Frame = nil) or (Frame.format <> AV_PIX_FMT_NV12) or
     (Frame.data[0] = nil) or (Frame.data[1] = nil) or
     (Frame.linesize[0] <= 0) or (Frame.linesize[1] <= 0) then
    Exit;
  if not EnsureDevice(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsurePlaneTextures(Frame.width, Frame.height, Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureShaderPipeline(Frame.width, Frame.height, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureDisplaySwapChain(Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureRectPipeline(ErrorMessage) then
    LogErrorOnce(ErrorMessage);

  TotalWatch := TStopwatch.StartNew;
  ChromaHeight := (Frame.height + 1) div 2;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FYTexture, 0, nil, Frame.data[0],
    Cardinal(Frame.linesize[0]), Cardinal(Frame.linesize[0] * Frame.height));
  FDeviceContext.UpdateSubresource(FUvTexture, 0, nil, Frame.data[1],
    Cardinal(Frame.linesize[1]), Cardinal(Frame.linesize[1] * ChromaHeight));
  UploadMs := StepWatch.Elapsed.TotalMilliseconds;

  ViewWidth := FTargetWidth;
  ViewHeight := (Int64(FTargetWidth) * Frame.height) div Frame.width;
  if ViewHeight > FTargetHeight then
  begin
    ViewHeight := FTargetHeight;
    ViewWidth := (Int64(FTargetHeight) * Frame.width) div Frame.height;
  end;
  if ViewWidth < 1 then
    ViewWidth := 1;
  if ViewHeight < 1 then
    ViewHeight := 1;
  ViewLeft := (FTargetWidth - ViewWidth) div 2;
  ViewTop := (FTargetHeight - ViewHeight) div 2;

  FillChar(Viewport, SizeOf(Viewport), 0);
  Viewport.TopLeftX := ViewLeft;
  Viewport.TopLeftY := ViewTop;
  Viewport.Width := ViewWidth;
  Viewport.Height := ViewHeight;
  Viewport.MinDepth := 0;
  Viewport.MaxDepth := 1;
  ResourceViews[0] := FYResourceView;
  ResourceViews[1] := FUvResourceView;

  StepWatch := TStopwatch.StartNew;
  ClearColor[0] := 0;
  ClearColor[1] := 0;
  ClearColor[2] := 0;
  ClearColor[3] := 1;
  FDeviceContext.ClearRenderTargetView(FDisplayRenderView, ClearColor);
  ClearMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.IASetInputLayout(nil);
  FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  FDeviceContext.VSSetShader(FVertexShader, nil, 0);
  FDeviceContext.PSSetShader(FPixelShader, nil, 0);
  FDeviceContext.PSSetShaderResources(0, Length(ResourceViews), ResourceViews[0]);
  FDeviceContext.PSSetSamplers(0, 1, FSampler);
  FDeviceContext.RSSetViewports(1, @Viewport);
  FDeviceContext.OMSetRenderTargets(1, FDisplayRenderView, nil);
  FDeviceContext.Draw(3, 0);
  DrawMs := StepWatch.Elapsed.TotalMilliseconds;

  OverlayMs := DrawSeekBarOverlay(GlobalD3DSeekBarOverlay);

  StepWatch := TStopwatch.StartNew;
  FDisplaySwapChain.Present(0, 0);
  PresentMs := StepWatch.Elapsed.TotalMilliseconds;

  FCurrentFrameIsBgrx32 := False;
  GlobalD3DFramePresented := True;
  Result := True;
  LogD3DMemoryUsage('present_nv12');
  if VideoMinerSlowLogEnabled then
    WriteVideoMinerSlowLog(Format(
      'd3d11_display_present frame=%dx%d target=%dx%d viewport=%d,%d,%d,%d y_stride=%d uv_stride=%d range=%d space=%d recreated=%s overlay=%s transport=%s dragging=%s upload_ms=%.3f clear_ms=%.3f draw_ms=%.3f overlay_ms=%.3f present_ms=%.3f total_ms=%.3f',
      [Frame.width, Frame.height, FTargetWidth, FTargetHeight,
       ViewLeft, ViewTop, ViewLeft + ViewWidth, ViewTop + ViewHeight,
       Frame.linesize[0], Frame.linesize[1], Frame.color_range,
       Frame.colorspace, BoolToStr(Recreated, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.TransportVisible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True), UploadMs, ClearMs,
       DrawMs, OverlayMs, PresentMs, TotalWatch.Elapsed.TotalMilliseconds]))
  else if Recreated or
          (LastD3DPresentOverlayVisible <> GlobalD3DSeekBarOverlay.Visible) or
          (LastD3DPresentTransportVisible <> GlobalD3DSeekBarOverlay.TransportVisible) or
          (LastD3DPresentDragging <> GlobalD3DSeekBarOverlay.Dragging) or
          (GetTickCount64 - LastD3DPresentLogTick >= 1000) then
  begin
    LastD3DPresentLogTick := GetTickCount64;
    LastD3DPresentOverlayVisible := GlobalD3DSeekBarOverlay.Visible;
    LastD3DPresentTransportVisible := GlobalD3DSeekBarOverlay.TransportVisible;
    LastD3DPresentDragging := GlobalD3DSeekBarOverlay.Dragging;
    WriteVideoMinerD3DLog(Format(
      'd3d11_display_present_lite frame=%dx%d target=%dx%d overlay=%s transport=%s dragging=%s recreated=%s total_ms=%.3f',
      [Frame.width, Frame.height, FTargetWidth, FTargetHeight,
       BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.TransportVisible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True),
       BoolToStr(Recreated, True), TotalWatch.Elapsed.TotalMilliseconds]));
  end;
end;

function TNv12TextureProbe.PresentBgrx32Frame(Buffer: Pointer;
  BufferStride, Width, Height: Integer): Boolean;
var
  ClearColor   : TFourSingleArray; // letterbox 領域を塗る黒
  DrawMs       : Double;           // 実 backbuffer への描画時間
  ErrorMessage : string;           // D3D 表示失敗理由
  OverlayMs    : Double;           // D3D overlay 描画時間
  PresentMs    : Double;           // Present 呼び出し時間
  Recreated    : Boolean;          // swap chain または texture を今回作り直したか
  ResourceView : ID3D11ShaderResourceView;
  RowBytes     : Integer;          // BGRX32 1 行の byte 数
  SrcData      : Pointer;          // UpdateSubresource に渡す先頭
  SrcPitch     : Cardinal;         // UpdateSubresource に渡す row pitch
  StepWatch    : TStopwatch;       // 各 step の計測
  TextureRecreated: Boolean;       // BGRX32 texture を今回作り直したか
  TotalWatch   : TStopwatch;       // D3D 表示全体の計測
  UploadMs     : Double;           // BGRX32 upload 時間
  ViewHeight   : Integer;          // アスペクト比維持後の描画高さ
  ViewLeft     : Integer;          // アスペクト比維持後の描画左位置
  ViewTop      : Integer;          // アスペクト比維持後の描画上位置
  Viewport     : D3D11_VIEWPORT;
  ViewWidth    : Integer;          // アスペクト比維持後の描画幅
  Y            : Integer;          // 負 stride 詰め直し中の行番号
begin
  Result := False;
  GlobalD3DFramePresented := False;
  if (not Nv12TextureD3DDisplayEnabled) or (not GlobalD3DDisplayAllowed) then
    Exit;
  if (Buffer = nil) or (Width <= 0) or (Height <= 0) then
    Exit;

  RowBytes := Width * 4;
  if Abs(BufferStride) < RowBytes then
    Exit;
  if not EnsureDevice(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureBgrxTexture(Width, Height, TextureRecreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureBgrxShaderPipeline(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureDisplaySwapChain(Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  Recreated := Recreated or TextureRecreated;
  if not EnsureRectPipeline(ErrorMessage) then
    LogErrorOnce(ErrorMessage);

  TotalWatch := TStopwatch.StartNew;
  SrcData := Buffer;
  SrcPitch := Cardinal(BufferStride);
  if BufferStride < 0 then
  begin
    SetLength(FBgrxPackedBuffer, RowBytes * Height);
    for Y := 0 to Height - 1 do
      Move(PByte(NativeInt(Buffer) + NativeInt(Y) * BufferStride)^,
        FBgrxPackedBuffer[Y * RowBytes], RowBytes);
    SrcData := @FBgrxPackedBuffer[0];
    SrcPitch := Cardinal(RowBytes);
  end;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.UpdateSubresource(FBgrxTexture, 0, nil, SrcData, SrcPitch,
    Cardinal(SrcPitch * Cardinal(Height)));
  UploadMs := StepWatch.Elapsed.TotalMilliseconds;

  ViewWidth := FTargetWidth;
  ViewHeight := (Int64(FTargetWidth) * Height) div Width;
  if ViewHeight > FTargetHeight then
  begin
    ViewHeight := FTargetHeight;
    ViewWidth := (Int64(FTargetHeight) * Width) div Height;
  end;
  if ViewWidth < 1 then
    ViewWidth := 1;
  if ViewHeight < 1 then
    ViewHeight := 1;
  ViewLeft := (FTargetWidth - ViewWidth) div 2;
  ViewTop := (FTargetHeight - ViewHeight) div 2;

  FillChar(Viewport, SizeOf(Viewport), 0);
  Viewport.TopLeftX := ViewLeft;
  Viewport.TopLeftY := ViewTop;
  Viewport.Width := ViewWidth;
  Viewport.Height := ViewHeight;
  Viewport.MinDepth := 0;
  Viewport.MaxDepth := 1;
  ResourceView := FBgrxResourceView;

  ClearColor[0] := 0;
  ClearColor[1] := 0;
  ClearColor[2] := 0;
  ClearColor[3] := 1;
  FDeviceContext.ClearRenderTargetView(FDisplayRenderView, ClearColor);

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.IASetInputLayout(nil);
  FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  FDeviceContext.VSSetShader(FVertexShader, nil, 0);
  FDeviceContext.PSSetShader(FBgrxPixelShader, nil, 0);
  FDeviceContext.PSSetShaderResources(0, 1, ResourceView);
  FDeviceContext.PSSetSamplers(0, 1, FSampler);
  FDeviceContext.RSSetViewports(1, @Viewport);
  FDeviceContext.OMSetRenderTargets(1, FDisplayRenderView, nil);
  FDeviceContext.Draw(3, 0);
  DrawMs := StepWatch.Elapsed.TotalMilliseconds;

  OverlayMs := DrawSeekBarOverlay(GlobalD3DSeekBarOverlay);

  StepWatch := TStopwatch.StartNew;
  FDisplaySwapChain.Present(0, 0);
  PresentMs := StepWatch.Elapsed.TotalMilliseconds;

  FCurrentFrameIsBgrx32 := True;
  GlobalD3DFramePresented := True;
  Result := True;
  LogD3DMemoryUsage('present_bgrx32');
  if VideoMinerSlowLogEnabled then
    WriteVideoMinerSlowLog(Format(
      'd3d11_display_present_bgrx32 frame=%dx%d target=%dx%d viewport=%d,%d,%d,%d stride=%d recreated=%s overlay=%s transport=%s dragging=%s upload_ms=%.3f draw_ms=%.3f overlay_ms=%.3f present_ms=%.3f total_ms=%.3f',
      [Width, Height, FTargetWidth, FTargetHeight, ViewLeft, ViewTop,
       ViewLeft + ViewWidth, ViewTop + ViewHeight, BufferStride,
       BoolToStr(Recreated, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.TransportVisible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True), UploadMs, DrawMs,
       OverlayMs, PresentMs, TotalWatch.Elapsed.TotalMilliseconds]))
  else if Recreated or
          (LastD3DPresentOverlayVisible <> GlobalD3DSeekBarOverlay.Visible) or
          (LastD3DPresentTransportVisible <> GlobalD3DSeekBarOverlay.TransportVisible) or
          (LastD3DPresentDragging <> GlobalD3DSeekBarOverlay.Dragging) or
          (GetTickCount64 - LastD3DPresentLogTick >= 1000) then
  begin
    LastD3DPresentLogTick := GetTickCount64;
    LastD3DPresentOverlayVisible := GlobalD3DSeekBarOverlay.Visible;
    LastD3DPresentTransportVisible := GlobalD3DSeekBarOverlay.TransportVisible;
    LastD3DPresentDragging := GlobalD3DSeekBarOverlay.Dragging;
    WriteVideoMinerD3DLog(Format(
      'd3d11_display_present_bgrx32_lite frame=%dx%d target=%dx%d overlay=%s transport=%s dragging=%s recreated=%s total_ms=%.3f',
      [Width, Height, FTargetWidth, FTargetHeight,
       BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.TransportVisible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True),
       BoolToStr(Recreated, True), TotalWatch.Elapsed.TotalMilliseconds]));
  end;
end;

function TNv12TextureProbe.PresentCurrentFrame: Boolean;
var
  ClearColor   : TFourSingleArray; // letterbox 領域を塗る黒
  ErrorMessage : string;           // D3D 表示失敗理由
  OverlayMs    : Double;           // D3D overlay 描画時間
  PresentMs    : Double;           // Present 呼び出し時間
  Recreated    : Boolean;          // swap chain を今回作り直したか
  ResourceView : ID3D11ShaderResourceView;
  ResourceViews: array[0..1] of ID3D11ShaderResourceView;
  StepWatch    : TStopwatch;       // 各 step の計測
  TotalWatch   : TStopwatch;       // D3D 表示全体の計測
  ViewHeight   : Integer;          // アスペクト比維持後の描画高さ
  ViewLeft     : Integer;          // アスペクト比維持後の描画左位置
  ViewTop      : Integer;          // アスペクト比維持後の描画上位置
  Viewport     : D3D11_VIEWPORT;
  ViewWidth    : Integer;          // アスペクト比維持後の描画幅
begin
  Result := False;
  GlobalD3DFramePresented := False;
  if not Nv12TextureD3DDisplayEnabled then
    Exit;
  if FCurrentFrameIsBgrx32 then
  begin
    if (FBgrxWidth <= 0) or (FBgrxHeight <= 0) or
       (not Assigned(FBgrxResourceView)) then
      Exit;
    if not EnsureDevice(ErrorMessage) then
    begin
      LogErrorOnce(ErrorMessage);
      Exit;
    end;
    if not EnsureBgrxShaderPipeline(ErrorMessage) then
    begin
      LogErrorOnce(ErrorMessage);
      Exit;
    end;
    if not EnsureDisplaySwapChain(Recreated, ErrorMessage) then
    begin
      LogErrorOnce(ErrorMessage);
      Exit;
    end;
    if not EnsureRectPipeline(ErrorMessage) then
      LogErrorOnce(ErrorMessage);

    TotalWatch := TStopwatch.StartNew;
    ViewWidth := FTargetWidth;
    ViewHeight := (Int64(FTargetWidth) * FBgrxHeight) div FBgrxWidth;
    if ViewHeight > FTargetHeight then
    begin
      ViewHeight := FTargetHeight;
      ViewWidth := (Int64(FTargetHeight) * FBgrxWidth) div FBgrxHeight;
    end;
    if ViewWidth < 1 then
      ViewWidth := 1;
    if ViewHeight < 1 then
      ViewHeight := 1;
    ViewLeft := (FTargetWidth - ViewWidth) div 2;
    ViewTop := (FTargetHeight - ViewHeight) div 2;

    FillChar(Viewport, SizeOf(Viewport), 0);
    Viewport.TopLeftX := ViewLeft;
    Viewport.TopLeftY := ViewTop;
    Viewport.Width := ViewWidth;
    Viewport.Height := ViewHeight;
    Viewport.MinDepth := 0;
    Viewport.MaxDepth := 1;
    ResourceView := FBgrxResourceView;

    ClearColor[0] := 0;
    ClearColor[1] := 0;
    ClearColor[2] := 0;
    ClearColor[3] := 1;
    FDeviceContext.ClearRenderTargetView(FDisplayRenderView, ClearColor);

    FDeviceContext.IASetInputLayout(nil);
    FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    FDeviceContext.VSSetShader(FVertexShader, nil, 0);
    FDeviceContext.PSSetShader(FBgrxPixelShader, nil, 0);
    FDeviceContext.PSSetShaderResources(0, 1, ResourceView);
    FDeviceContext.PSSetSamplers(0, 1, FSampler);
    FDeviceContext.RSSetViewports(1, @Viewport);
    FDeviceContext.OMSetRenderTargets(1, FDisplayRenderView, nil);
    FDeviceContext.Draw(3, 0);

    OverlayMs := DrawSeekBarOverlay(GlobalD3DSeekBarOverlay);

    StepWatch := TStopwatch.StartNew;
    FDisplaySwapChain.Present(0, 0);
    PresentMs := StepWatch.Elapsed.TotalMilliseconds;

    GlobalD3DFramePresented := True;
    Result := True;
    LogD3DMemoryUsage('represent_bgrx32');
    if VideoMinerSlowLogEnabled then
      WriteVideoMinerSlowLog(Format(
        'd3d11_display_represent_bgrx32 frame=%dx%d target=%dx%d viewport=%d,%d,%d,%d overlay=%s transport=%s dragging=%s overlay_ms=%.3f present_ms=%.3f total_ms=%.3f',
        [FBgrxWidth, FBgrxHeight, FTargetWidth, FTargetHeight,
         ViewLeft, ViewTop, ViewLeft + ViewWidth, ViewTop + ViewHeight,
         BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
         BoolToStr(GlobalD3DSeekBarOverlay.TransportVisible, True),
         BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True), OverlayMs,
         PresentMs, TotalWatch.Elapsed.TotalMilliseconds]));
    Exit;
  end;

  if (FTextureWidth <= 0) or (FTextureHeight <= 0) or
     (not Assigned(FYResourceView)) or (not Assigned(FUvResourceView)) then
    Exit;
  if not EnsureDevice(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureShaderPipeline(FTextureWidth, FTextureHeight, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureDisplaySwapChain(Recreated, ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;
  if not EnsureRectPipeline(ErrorMessage) then
    LogErrorOnce(ErrorMessage);

  TotalWatch := TStopwatch.StartNew;
  ViewWidth := FTargetWidth;
  ViewHeight := (Int64(FTargetWidth) * FTextureHeight) div FTextureWidth;
  if ViewHeight > FTargetHeight then
  begin
    ViewHeight := FTargetHeight;
    ViewWidth := (Int64(FTargetHeight) * FTextureWidth) div FTextureHeight;
  end;
  if ViewWidth < 1 then
    ViewWidth := 1;
  if ViewHeight < 1 then
    ViewHeight := 1;
  ViewLeft := (FTargetWidth - ViewWidth) div 2;
  ViewTop := (FTargetHeight - ViewHeight) div 2;

  FillChar(Viewport, SizeOf(Viewport), 0);
  Viewport.TopLeftX := ViewLeft;
  Viewport.TopLeftY := ViewTop;
  Viewport.Width := ViewWidth;
  Viewport.Height := ViewHeight;
  Viewport.MinDepth := 0;
  Viewport.MaxDepth := 1;
  ResourceViews[0] := FYResourceView;
  ResourceViews[1] := FUvResourceView;

  ClearColor[0] := 0;
  ClearColor[1] := 0;
  ClearColor[2] := 0;
  ClearColor[3] := 1;
  FDeviceContext.ClearRenderTargetView(FDisplayRenderView, ClearColor);

  FDeviceContext.IASetInputLayout(nil);
  FDeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  FDeviceContext.VSSetShader(FVertexShader, nil, 0);
  FDeviceContext.PSSetShader(FPixelShader, nil, 0);
  FDeviceContext.PSSetShaderResources(0, Length(ResourceViews), ResourceViews[0]);
  FDeviceContext.PSSetSamplers(0, 1, FSampler);
  FDeviceContext.RSSetViewports(1, @Viewport);
  FDeviceContext.OMSetRenderTargets(1, FDisplayRenderView, nil);
  FDeviceContext.Draw(3, 0);

  OverlayMs := DrawSeekBarOverlay(GlobalD3DSeekBarOverlay);

  StepWatch := TStopwatch.StartNew;
  FDisplaySwapChain.Present(0, 0);
  PresentMs := StepWatch.Elapsed.TotalMilliseconds;

  GlobalD3DFramePresented := True;
  Result := True;
  LogD3DMemoryUsage('represent_nv12');
  if VideoMinerSlowLogEnabled then
    WriteVideoMinerSlowLog(Format(
      'd3d11_display_represent frame=%dx%d target=%dx%d viewport=%d,%d,%d,%d overlay=%s transport=%s dragging=%s overlay_ms=%.3f present_ms=%.3f total_ms=%.3f',
      [FTextureWidth, FTextureHeight, FTargetWidth, FTargetHeight,
       ViewLeft, ViewTop, ViewLeft + ViewWidth, ViewTop + ViewHeight,
       BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.TransportVisible, True),
       BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True), OverlayMs, PresentMs,
       TotalWatch.Elapsed.TotalMilliseconds]));
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
  ProbeShaderDraw(Frame);
  ProbeSwapChainPresent(Frame);

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

procedure TNv12TextureProbe.SetTargetWindow(WindowHandle: HWND; Width, Height: Integer);
begin
  if (FTargetWidth <> Width) or (FTargetHeight <> Height) then
  begin
    ReleaseD3DContextReferences;
    FDisplayRenderView := nil;
    FDisplaySwapChain := nil;
    FDisplayWindow := 0;
    FDisplayWidth := 0;
    FDisplayHeight := 0;
    FSwapRenderView := nil;
    FSwapChain := nil;
    FSwapWindow := 0;
    FSwapWidth := 0;
    FSwapHeight := 0;
    if FProbeWindow <> 0 then
    begin
      DestroyWindow(FProbeWindow);
      FProbeWindow := 0;
    end;
  end;
  FTargetWindow := WindowHandle;
  FTargetWidth := Width;
  FTargetHeight := Height;
end;

procedure ProbeNv12TextureUpload(Frame: PAVFrame);
begin
  if not TextureProbeEnabled then
    Exit;
  if GlobalProbe = nil then
    GlobalProbe := TNv12TextureProbe.Create;
  GlobalProbe.Probe(Frame);
end;

function PresentNv12TextureFrame(Frame: PAVFrame): Boolean;
begin
  Result := False;
  if not Nv12TextureD3DDisplayEnabled then
    Exit;
  if GlobalProbe = nil then
    GlobalProbe := TNv12TextureProbe.Create;
  Result := GlobalProbe.PresentFrame(Frame);
end;

function PresentBgrx32TextureFrame(Buffer: Pointer; BufferStride, Width,
  Height: Integer): Boolean;
begin
  Result := False;
  if not Nv12TextureD3DDisplayEnabled then
    Exit;
  if GlobalProbe = nil then
    GlobalProbe := TNv12TextureProbe.Create;
  Result := GlobalProbe.PresentBgrx32Frame(Buffer, BufferStride, Width, Height);
end;

function PresentCurrentNv12TextureFrame: Boolean;
begin
  Result := False;
  if not Nv12TextureD3DDisplayEnabled then
    Exit;
  if GlobalProbe = nil then
    Exit;
  Result := GlobalProbe.PresentCurrentFrame;
end;

procedure SetNv12TextureProbeTargetWindow(WindowHandle: HWND; Width, Height: Integer);
begin
  if (not TextureProbeEnabled) and (not Nv12TextureD3DDisplayEnabled) then
    Exit;
  if GlobalProbe = nil then
    GlobalProbe := TNv12TextureProbe.Create;
  GlobalProbe.SetTargetWindow(WindowHandle, Width, Height);
end;

initialization

finalization
  try
    WriteVideoMinerStartupLog('d3d11_texture_probe_finalization begin');
    GlobalProbe.Free;
    GlobalProbe := nil;
    WriteVideoMinerStartupLog('d3d11_texture_probe_finalization done');
  except
    on E: Exception do
      WriteVideoMinerStartupLog('d3d11_texture_probe_finalization_exception class="' +
        E.ClassName + '" message="' + E.Message + '"');
  end;

end.
