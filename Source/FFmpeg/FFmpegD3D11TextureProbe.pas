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
    Dragging       : Boolean; // シークバーをドラッグ中か
    Chapters       : TArray<TD3D11SeekBarOverlayChapter>; // D3D 側で描くチャプター目盛り
  end;

// NV12 frame を D3D11 texture へアップロードし、計測ログを出す。
procedure ProbeNv12TextureUpload(Frame: PAVFrame);
procedure SetNv12TextureProbeTargetWindow(WindowHandle: HWND; Width, Height: Integer);
function PresentNv12TextureFrame(Frame: PAVFrame): Boolean;
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
    FPackedBuffer   : TBytes;              // plane が連続していない時の退避バッファ
    FLastError      : string;              // 同じ失敗を毎 frame 出さないための記録
    FLoggedDisabled : Boolean;             // 非 NV12 などのスキップ理由を一度だけ出す
    function EnsureDevice(out ErrorMessage: string): Boolean;
    function EnsureTexture(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    function EnsurePlaneTextures(Width, Height: Integer; out Recreated: Boolean;
      out ErrorMessage: string): Boolean;
    function EnsureShaderPipeline(Width, Height: Integer; out ErrorMessage: string): Boolean;
    function EnsureRectPipeline(out ErrorMessage: string): Boolean;
    function EnsureProbeWindow(out ErrorMessage: string): Boolean;
    function EnsureSwapChain(out Recreated: Boolean; out ErrorMessage: string): Boolean;
    function EnsureDisplaySwapChain(out Recreated: Boolean; out ErrorMessage: string): Boolean;
    procedure LogErrorOnce(const ErrorMessage: string);
    procedure ProbePlaneTextures(Frame: PAVFrame);
    procedure ProbeShaderDraw(Frame: PAVFrame);
    procedure ProbeSwapChainPresent(Frame: PAVFrame);
    procedure DrawOverlayRect(const Rect: TRect; R, G, B, A: Single);
    function DrawSeekBarOverlay(const State: TD3D11SeekBarOverlayState): Double;
  public
    destructor Destroy; override;
    procedure Probe(Frame: PAVFrame);
    function PresentFrame(Frame: PAVFrame): Boolean;
    procedure SetTargetWindow(WindowHandle: HWND; Width, Height: Integer);
  end;

var
  GlobalProbe: TNv12TextureProbe;
  GlobalD3DDisplayAllowed: Boolean;
  GlobalD3DFramePresented: Boolean;
  GlobalD3DSeekBarOverlay: TD3D11SeekBarOverlayState;

function TextureProbeEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := SameText(GetEnvironmentVariable('VIDEOMINER_TEXTURE_PROBE'), '1');
{$ELSE}
  Result := False;
{$ENDIF}
end;

function Nv12TextureD3DDisplayEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := SameText(GetEnvironmentVariable('VIDEOMINER_D3D11_DISPLAY'), '1');
{$ELSE}
  Result := False;
{$ENDIF}
end;

function Nv12TextureD3DFramePresented: Boolean;
begin
  Result := GlobalD3DFramePresented;
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

function TNv12TextureProbe.DrawSeekBarOverlay(
  const State: TD3D11SeekBarOverlayState): Double;
var
  Chapter: TD3D11SeekBarOverlayChapter;
  ErrorMessage: string;
  FilledRect: TRect;
  HighlightRect: TRect;
  KnobCenterY: Integer;
  KnobCorePad: Integer;
  KnobHaloPadX: Integer;
  KnobHaloPadY: Integer;
  KnobRect: TRect;
  KnobPadX: Integer;
  KnobPadY: Integer;
  MarkerRect: TRect;
  MarkerX: Integer;
  PositionRatio: Double;
  StepWatch: TStopwatch;
  TrackRect: TRect;
  BlendFactor: TFourSingleArray;
begin
  Result := 0;
  if (not State.Visible) or State.Bounds.IsEmpty or State.Track.IsEmpty or
     (State.MaxMs <= 0) then
    Exit;
  if not EnsureRectPipeline(ErrorMessage) then
  begin
    LogErrorOnce(ErrorMessage);
    Exit;
  end;

  StepWatch := TStopwatch.StartNew;
  FDeviceContext.OMSetRenderTargets(1, FDisplayRenderView, nil);
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
    KnobHaloPadX := 26;
    KnobHaloPadY := 23;
    KnobCorePad := 13;
    KnobPadX := 11;
    KnobPadY := 9;
  end
  else
  begin
    KnobHaloPadX := 22;
    KnobHaloPadY := 20;
    KnobCorePad := 11;
    KnobPadX := 7;
    KnobPadY := 5;
  end;
  DrawOverlayRect(Rect(MarkerX - KnobHaloPadX, KnobCenterY - KnobPadY,
    MarkerX + KnobHaloPadX, KnobCenterY + KnobPadY + 1), 0.25, 0.63, 0.94, 0.20);
  DrawOverlayRect(Rect(MarkerX - KnobPadX, KnobCenterY - KnobHaloPadY,
    MarkerX + KnobPadX, KnobCenterY + KnobHaloPadY + 1), 0.25, 0.63, 0.94, 0.20);
  KnobRect := Rect(MarkerX - KnobCorePad, KnobCenterY - KnobCorePad,
    MarkerX + KnobCorePad, KnobCenterY + KnobCorePad);
  DrawOverlayRect(KnobRect, 0.25, 0.63, 0.94, 0.96);
  DrawOverlayRect(Rect(MarkerX - KnobPadX, KnobCenterY - KnobPadY,
    MarkerX + KnobPadX, KnobCenterY + KnobPadY + 1), 0.52, 0.82, 1.0, 1.0);

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

  GlobalD3DFramePresented := True;
  Result := True;
  WriteVideoMinerSlowLog(Format(
    'd3d11_display_present frame=%dx%d target=%dx%d viewport=%d,%d,%d,%d y_stride=%d uv_stride=%d range=%d space=%d recreated=%s overlay=%s dragging=%s upload_ms=%.3f clear_ms=%.3f draw_ms=%.3f overlay_ms=%.3f present_ms=%.3f total_ms=%.3f',
    [Frame.width, Frame.height, FTargetWidth, FTargetHeight,
     ViewLeft, ViewTop, ViewLeft + ViewWidth, ViewTop + ViewHeight,
     Frame.linesize[0], Frame.linesize[1], Frame.color_range,
     Frame.colorspace, BoolToStr(Recreated, True),
     BoolToStr(GlobalD3DSeekBarOverlay.Visible, True),
     BoolToStr(GlobalD3DSeekBarOverlay.Dragging, True), UploadMs, ClearMs,
     DrawMs, OverlayMs, PresentMs, TotalWatch.Elapsed.TotalMilliseconds]));
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
  GlobalProbe.Free;

end.
