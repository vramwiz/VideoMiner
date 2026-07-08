unit VideoMinerOverlay;

// 動画サーフェス上に重ねる VideoMiner 専用 overlay GUI を定義する。
// 中央操作ボタン、左右ファイル移動、下側シーク/音量/チェック操作バーの描画と入力を担当する。

interface

uses
  System.Classes, System.Math, System.SysUtils, System.Types, Winapi.Windows,
  Vcl.Graphics;

type
  // 先頭/末尾へ移動する中央端ボタンの向き
  TVideoMinerOverlayEdgeDirection = (edFirst, edLast);
  // フォルダ内の前後ファイルへ移動する端ボタンの向き
  TVideoMinerOverlayFileNavDirection = (fndPrevious, fndNext);
  // シークバー上へ表示するチャプターマーカーの重要度
  TVideoMinerOverlayChapterSeverity = (csGreen, csYellow, csRed);
  // チャプターマーカーがどのチェックで作られたかを示す分類
  TVideoMinerOverlayChapterSource = (chsAutoCheck, chsAutoCheckAudio,
    chsAutoCheckChannel, chsAutoCheckFrameDiff, chsAutoCheckVolumeJump,
    chsAutoCheckClipping, chsUser);

  TVideoMinerOverlayChapter = record
    PositionMs : Integer;                            // チャプター位置 ms
    Severity   : TVideoMinerOverlayChapterSeverity;  // シークバー上の色分け
    Source     : TVideoMinerOverlayChapterSource;    // チャプターの発生元
  end;

  TVideoMinerOverlayChapters = TArray<TVideoMinerOverlayChapter>;
  TVideoMinerOverlaySeekEvent = procedure(Sender: TObject; PositionMs: Integer) of object;
  TVideoMinerOverlaySeekHoverEvent = procedure(Sender: TObject; PositionMs: Integer;
    const Point: TPoint) of object;
  TVideoMinerOverlaySkipDirection = (sdBackward, sdForward);
  TVideoMinerOverlayVolumeEvent = procedure(Sender: TObject; VolumePercent: Integer) of object;

  TVideoMinerOverlayControl = class abstract
  private
    FBounds  : TRect;   // 現在の描画/ヒットテスト領域
    FEnabled : Boolean; // 入力を受け付けるか
    FVisible : Boolean; // 描画対象か
  protected
    // PreviewRect に対する自分の表示領域を計算する
    function CalculateBounds(const PreviewRect: TRect): TRect; virtual; abstract;
    // 実際の部品描画を派生クラスへ任せる
    procedure PaintControl(Canvas: TCanvas); virtual; abstract;
    property Bounds: TRect read FBounds;
  public
    constructor Create; virtual;
    // PreviewRect の変化に合わせて Bounds を更新する
    procedure UpdateLayout(const PreviewRect: TRect); virtual;
    // Visible の場合だけ部品を描画する
    procedure Paint(Canvas: TCanvas); virtual;
    // Enabled を見て Bounds 内かを判定する
    function BoundsHitTest(const Point: TPoint): Boolean; virtual;
    // Visible/Enabled を含めた通常ヒットテストを行う
    function HitTest(const Point: TPoint): Boolean; virtual;
    // 押下開始を受け付けるか返す
    function MouseDown(const Point: TPoint): Boolean; virtual;
    // hover 更新が必要か返す
    function MouseMove(const Point: TPoint): Boolean; virtual;
    // 押下終了を受け付けるか返す
    function MouseUp(const Point: TPoint): Boolean; virtual;
    property BoundsRect: TRect read FBounds;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Visible: Boolean read FVisible write FVisible;
  end;

  TVideoMinerOverlayButton = class abstract(TVideoMinerOverlayControl)
  private
    FHovered : Boolean;      // マウスがボタン上にあるか
    FOnClick : TNotifyEvent; // クリック成立時の通知先
    FPressed : Boolean;      // 押下中か
  protected
    // 中央ボタン共通の半透明背景を描く
    procedure DrawCenterButtonBackground(Canvas: TCanvas);
    // 押下と解放が同じボタン上で成立したときの通知を行う
    procedure DoClick; virtual;
    property Hovered: Boolean read FHovered;
    property Pressed: Boolean read FPressed;
  public
    function MouseDown(const Point: TPoint): Boolean; override;
    function MouseMove(const Point: TPoint): Boolean; override;
    function MouseUp(const Point: TPoint): Boolean; override;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

  TVideoMinerOverlayPlayPauseButton = class(TVideoMinerOverlayButton)
  private
    FIsPlaying : Boolean; // 再生中なら一時停止アイコン、停止中なら再生アイコンを描く
    // 半透明の三角形アイコンを描く
    procedure DrawAlphaPolygon(Canvas: TCanvas; const Points: array of TPoint; Alpha: Byte);
    // 半透明の矩形アイコンを描く
    procedure DrawAlphaRect(Canvas: TCanvas; const Rect: TRect; Alpha: Byte);
    // hover/pressed 状態からアイコンの濃さを決める
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    property IsPlaying: Boolean read FIsPlaying write FIsPlaying;
  end;

  TVideoMinerOverlaySkipButton = class(TVideoMinerOverlayButton)
  private
    FDirection : TVideoMinerOverlaySkipDirection; // 10 秒戻し/進みの向き
    // 半透明の曲線矢印を描く
    procedure DrawAlphaPolyline(Canvas: TCanvas; const Points: array of TPoint;
      PenWidth: Integer; Alpha: Byte);
    // 半透明の矢印先端を描く
    procedure DrawAlphaPolygon(Canvas: TCanvas; const Points: array of TPoint; Alpha: Byte);
    // hover/pressed 状態からアイコンの濃さを決める
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    constructor Create(Direction: TVideoMinerOverlaySkipDirection); reintroduce;
    property Direction: TVideoMinerOverlaySkipDirection read FDirection write FDirection;
  end;

  TVideoMinerOverlayEdgeButton = class(TVideoMinerOverlayButton)
  private
    FDirection : TVideoMinerOverlayEdgeDirection; // 先頭/末尾のどちらへ移動するか
    // 半透明の三角形アイコンを描く
    procedure DrawAlphaPolygon(Canvas: TCanvas; const Points: array of TPoint; Alpha: Byte);
    // 半透明の縦線アイコンを描く
    procedure DrawAlphaRect(Canvas: TCanvas; const DrawRect: TRect; Alpha: Byte);
    // hover/pressed 状態からアイコンの濃さを決める
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    constructor Create(Direction: TVideoMinerOverlayEdgeDirection); reintroduce;
    property Direction: TVideoMinerOverlayEdgeDirection read FDirection write FDirection;
  end;

  TVideoMinerOverlayFileNavButton = class(TVideoMinerOverlayButton)
  private
    FDirection : TVideoMinerOverlayFileNavDirection; // 前後どちらのファイルへ移動するか
    // 端ボタンの薄い帯背景を描く
    procedure DrawAlphaRect(Canvas: TCanvas; const DrawRect: TRect; Alpha: Byte);
    // 端ボタンの矢印を描く
    procedure DrawAlphaPolyline(Canvas: TCanvas; const Points: array of TPoint;
      PenWidth: Integer; Alpha: Byte);
    // hover/pressed 状態からアイコンの濃さを決める
    function IconAlpha: Byte;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    constructor Create(Direction: TVideoMinerOverlayFileNavDirection); reintroduce;
    property Direction: TVideoMinerOverlayFileNavDirection read FDirection write FDirection;
  end;

  TVideoMinerOverlaySeekBar = class(TVideoMinerOverlayControl)
  private
    FDragPositionMs             : Integer;                     // ドラッグ中に指しているシーク位置 ms
    FDragging                   : Boolean;                     // シークバーをドラッグ中か
    FAddChapterButtonHovered    : Boolean;                     // 追加ボタン上にマウスがあるか
    FAddChapterButtonPressed    : Boolean;                     // 追加ボタンを押下中か
    FChapters                   : TVideoMinerOverlayChapters;  // シークバー上に描くチャプター群
    FCheckButtonHovered         : Boolean;                     // Check ボタン上にマウスがあるか
    FCheckButtonPressed         : Boolean;                     // Check ボタンを押下中か
    FCheckEnabled               : Boolean;                     // Check モード中か
    FCompactPlaybackStyle       : Boolean;                     // 再生中 CPU fallback 時に D3D 風の簡易表示で描くか
    FDeleteChapterButtonHovered : Boolean;                     // 削除ボタン上にマウスがあるか
    FDeleteChapterButtonPressed : Boolean;                     // 削除ボタンを押下中か
    FEndActionButtonHovered     : Boolean;                     // 終端動作ボタン上にマウスがあるか
    FEndActionButtonPressed     : Boolean;                     // 終端動作ボタンを押下中か
    FEndActionText              : string;                      // 終端動作ボタンに表示する文字列
    FFullScreen                 : Boolean;                     // 全画面表示中か
    FFullScreenButtonHovered    : Boolean;                     // 全画面ボタン上にマウスがあるか
    FFullScreenButtonPressed    : Boolean;                     // 全画面ボタンを押下中か
    FHovered                    : Boolean;                     // シークバー全体にマウスがあるか
    FFrameStepMs                : Integer;                     // Check 中の 1 フレーム相当 ms
    FMaxMs                      : Integer;                     // 動画長 ms
    FMuted                      : Boolean;                     // ミュート状態か
    FMuteButtonHovered          : Boolean;                     // ミュートボタン上にマウスがあるか
    FMuteButtonPressed          : Boolean;                     // ミュートボタンを押下中か
    FOnAddChapterClick          : TNotifyEvent;                // チャプター追加通知先
    FOnCheckClick               : TNotifyEvent;                // Check ボタン通知先
    FOnDeleteChapterClick       : TNotifyEvent;                // チャプター削除通知先
    FOnEndActionClick           : TNotifyEvent;                // 終端動作ボタン通知先
    FOnFullScreenClick          : TNotifyEvent;                // 全画面ボタン通知先
    FOnMuteClick                : TNotifyEvent;                // ミュートボタン通知先
    FOnPlaybackRateClick        : TNotifyEvent;                // 再生速度ボタン通知先
    FOnSeek                     : TVideoMinerOverlaySeekEvent; // シーク操作通知先
    FOnVolumeChange             : TVideoMinerOverlayVolumeEvent;   // 音量変更通知先
    FPlaybackRateButtonHovered  : Boolean;                     // 再生速度ボタン上にマウスがあるか
    FPlaybackRateButtonPressed  : Boolean;                     // 再生速度ボタンを押下中か
    FPlaybackRateText           : string;                      // 再生速度ボタンに表示する文字列
    FPositionMs                 : Integer;                     // 通常表示中の現在位置 ms
    FTimeViewStartMs            : Integer;                     // 拡大表示中の左端位置 ms
    FTimeViewSpanMs             : Integer;                     // 拡大表示中に見えている長さ ms
    FTimeViewPanning            : Boolean;                     // 目盛り領域ドラッグで表示範囲を移動中か
    FTimeViewPanStartMs         : Integer;                     // 表示範囲 pan 開始時の左端 ms
    FTimeViewPanStartX          : Integer;                     // 表示範囲 pan 開始時の mouse X
    FVolumeDragging             : Boolean;                     // 音量バーをドラッグ中か
    FVolumeHovered              : Boolean;                     // 音量バー上にマウスがあるか
    FVolumePercent              : Integer;                     // 音量パーセント
    // 半透明の円を描く
    procedure DrawAlphaEllipse(Canvas: TCanvas; const DrawRect: TRect; Alpha: Byte;
      Color: TColor = clWhite);
    // 下側パネルの半透明背景を描く
    procedure DrawAlphaPanel(Canvas: TCanvas; const DrawRect: TRect; Radius: Integer; Alpha: Byte);
    // 半透明の線アイコンを描く
    procedure DrawAlphaPolyline(Canvas: TCanvas; const Points: array of TPoint;
      PenWidth: Integer; Alpha: Byte);
    // 半透明の角丸矩形を描く
    procedure DrawAlphaRoundRect(Canvas: TCanvas; const DrawRect: TRect; Radius: Integer;
      Alpha: Byte; Color: TColor = clWhite);
    // 全画面/解除アイコンを描く
    procedure DrawFullScreenIcon(Canvas: TCanvas; const DrawRect: TRect; Alpha: Byte);
    // ミュート/音量アイコンを描く
    procedure DrawMuteIcon(Canvas: TCanvas; const DrawRect: TRect; Alpha: Byte);
    function AddChapterButtonHitTest(const Point: TPoint): Boolean;
    function AddChapterButtonRect: TRect;
    function ChapterColor(Severity: TVideoMinerOverlayChapterSeverity): TColor;
    function CheckButtonHitTest(const Point: TPoint): Boolean;
    function CheckButtonRect: TRect;
    function DeleteChapterButtonHitTest(const Point: TPoint): Boolean;
    function DeleteChapterButtonRect: TRect;
    function DisplayPositionMs: Integer;
    function EndActionButtonHitTest(const Point: TPoint): Boolean;
    function EndActionButtonRect: TRect;
    function FormatTimeMs(ValueMs: Integer): string;
    function FullScreenButtonAlpha: Byte;
    function FullScreenButtonHitTest(const Point: TPoint): Boolean;
    function FullScreenButtonRect: TRect;
    function MuteButtonAlpha: Byte;
    function MuteButtonHitTest(const Point: TPoint): Boolean;
    function MuteButtonRect: TRect;
    function PlaybackRateButtonHitTest(const Point: TPoint): Boolean;
    function PlaybackRateButtonRect: TRect;
    function PositionFromPoint(const Point: TPoint): Integer;
    function TimeViewActive: Boolean;
    function TimeViewEndMs: Integer;
    function TimeViewPositionVisible(PositionMs: Integer): Boolean;
    function TimeViewPositionRatio(PositionMs: Integer): Double;
    function TimeViewSpanMs: Integer;
    function SecondaryToolButtonsVisible: Boolean;
    function ToolRowCenterY: Integer;
    function ToolRowRect(Left, Width, Height: Integer): TRect;
    procedure DrawChapterMarkers(Canvas: TCanvas; const Track: TRect);
    procedure DrawTimeRuler(Canvas: TCanvas; const Track: TRect);
    procedure DrawTextButton(Canvas: TCanvas; const ButtonRect: TRect;
      const Text: string; Active, Hovered, Pressed: Boolean; ActiveColor: TColor);
    procedure PanTimeViewToPoint(const Point: TPoint);
    procedure ResetTimeView;
    procedure SetEndActionText(const Value: string);
    procedure SetCheckEnabled(Value: Boolean);
    procedure SetChapters(const Value: TVideoMinerOverlayChapters);
    procedure SetFullScreen(Value: Boolean);
    procedure SetFrameStepMs(Value: Integer);
    procedure SetMuted(Value: Boolean);
    procedure SetPlaybackRateText(const Value: string);
    procedure SetVolumePercent(Value: Integer);
    function TrackRect: TRect;
    function VolumeFromPoint(const Point: TPoint): Integer;
    function VolumeLabelRect: TRect;
    function VolumeHitTest(const Point: TPoint): Boolean;
    function VolumeTrackRect: TRect;
  protected
    function CalculateBounds(const PreviewRect: TRect): TRect; override;
    procedure PaintControl(Canvas: TCanvas); override;
  public
    function MouseDown(const Point: TPoint): Boolean; override;
    function MouseMove(const Point: TPoint): Boolean; override;
    function MouseUp(const Point: TPoint): Boolean; override;
    function CurrentDisplayPositionMs: Integer;
    function CurrentTrackRect: TRect;
    function HoverPositionFromPoint(const Point: TPoint; out PositionMs: Integer): Boolean;
    function TimeRulerHitTest(const Point: TPoint): Boolean;
    procedure SetProgress(PositionMs, MaxMs: Integer);
    function ZoomTimeViewAtPoint(const Point: TPoint; WheelDelta: Integer): Boolean;
    function WheelPosition(WheelDelta, StepMs: Integer): Integer;
    property CheckEnabled: Boolean read FCheckEnabled write SetCheckEnabled;
    property AddChapterButtonHovered: Boolean read FAddChapterButtonHovered;
    property AddChapterButtonPressed: Boolean read FAddChapterButtonPressed;
    property CheckButtonHovered: Boolean read FCheckButtonHovered;
    property CheckButtonPressed: Boolean read FCheckButtonPressed;
    property Chapters: TVideoMinerOverlayChapters read FChapters write SetChapters;
    property CompactPlaybackStyle: Boolean read FCompactPlaybackStyle
      write FCompactPlaybackStyle;
    property DeleteChapterButtonHovered: Boolean read FDeleteChapterButtonHovered;
    property DeleteChapterButtonPressed: Boolean read FDeleteChapterButtonPressed;
    property Dragging: Boolean read FDragging;
    property EndActionButtonHovered: Boolean read FEndActionButtonHovered;
    property EndActionButtonPressed: Boolean read FEndActionButtonPressed;
    property EndActionText: string read FEndActionText write SetEndActionText;
    property FullScreen: Boolean read FFullScreen write SetFullScreen;
    property FullScreenButtonHovered: Boolean read FFullScreenButtonHovered;
    property FullScreenButtonPressed: Boolean read FFullScreenButtonPressed;
    property FrameStepMs: Integer read FFrameStepMs write SetFrameStepMs;
    property MaxMs: Integer read FMaxMs;
    property TimeViewEndMsValue: Integer read TimeViewEndMs;
    property TimeViewPanning: Boolean read FTimeViewPanning;
    property TimeViewStartMs: Integer read FTimeViewStartMs;
    property TimeViewSpanMsValue: Integer read TimeViewSpanMs;
    property TimeViewZoomActive: Boolean read TimeViewActive;
    property OnAddChapterClick: TNotifyEvent read FOnAddChapterClick write FOnAddChapterClick;
    property OnCheckClick: TNotifyEvent read FOnCheckClick write FOnCheckClick;
    property OnDeleteChapterClick: TNotifyEvent read FOnDeleteChapterClick write FOnDeleteChapterClick;
    property OnEndActionClick: TNotifyEvent read FOnEndActionClick write FOnEndActionClick;
    property OnFullScreenClick: TNotifyEvent read FOnFullScreenClick write FOnFullScreenClick;
    property OnMuteClick: TNotifyEvent read FOnMuteClick write FOnMuteClick;
    property OnPlaybackRateClick: TNotifyEvent read FOnPlaybackRateClick write FOnPlaybackRateClick;
    property OnSeek: TVideoMinerOverlaySeekEvent read FOnSeek write FOnSeek;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent read FOnVolumeChange write FOnVolumeChange;
    property Muted: Boolean read FMuted write SetMuted;
    property MuteButtonHovered: Boolean read FMuteButtonHovered;
    property MuteButtonPressed: Boolean read FMuteButtonPressed;
    property PlaybackRateButtonHovered: Boolean read FPlaybackRateButtonHovered;
    property PlaybackRateButtonPressed: Boolean read FPlaybackRateButtonPressed;
    property PlaybackRateText: string read FPlaybackRateText write SetPlaybackRateText;
    property VolumeDragging: Boolean read FVolumeDragging;
    property VolumeHovered: Boolean read FVolumeHovered;
    property VolumePercent: Integer read FVolumePercent write SetVolumePercent;
  end;
implementation

const
  SECONDARY_TOOL_BUTTONS_MIN_WIDTH = 520; // 補助ツールボタンを下部バーへ表示する最小幅
  SEEK_ACCENT_COLOR = $0000A5FF;          // 旧/GDI seek bar を識別しやすくするオレンジ
  SEEK_TIME_RULER_MAJOR_MIN_PX = 92;      // 長い目盛り同士の最小間隔
  SEEK_TIME_RULER_MINOR_MIN_PX = 24;      // 短い目盛り同士の最小間隔
  SEEK_TIME_VIEW_MIN_SPAN_MS = 1000;      // 最大拡大時に見せる最小時間幅
  SEEK_TIME_VIEW_ZOOM_STEP = 1.28;        // シークバー上ホイール 1 段あたりの拡大率

type
  TRgbTripleArray = array[0..MaxInt div SizeOf(TRGBTriple) - 1] of TRGBTriple;
  PRgbTripleArray = ^TRgbTripleArray;
  TBgraQuad = packed record
    B: Byte;
    G: Byte;
    R: Byte;
    A: Byte;
  end;
  TBgraQuadArray = array[0..MaxInt div SizeOf(TBgraQuad) - 1] of TBgraQuad;
  PBgraQuadArray = ^TBgraQuadArray;

function ClampByte(Value: Integer): Byte;
begin
  Result := Byte(Max(0, Min(255, Value)));
end;

function OverlayCenterStep(const PreviewRect: TRect): Integer;
var
  BaseSize: Integer;
begin
  BaseSize := Min(PreviewRect.Width, PreviewRect.Height);
  Result := Round(BaseSize * 0.125);
  Result := Max(52, Min(96, Result));
end;

function OverlayCenterButtonSize(const PreviewRect: TRect): Integer;
begin
  Result := Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.115);
  Result := Max(42, Min(104, Result));
end;

function NiceTimeTickMs(TargetMs: Double): Integer;
const
  STEPS: array[0..17] of Integer = (1000, 2000, 5000, 10000, 15000,
    30000, 60000, 120000, 300000, 600000, 900000, 1800000, 3600000,
    7200000, 14400000, 21600000, 43200000, 86400000);
var
  Step: Integer;
begin
  Result := STEPS[High(STEPS)];
  for Step in STEPS do
  begin
    if Step >= TargetMs then
    begin
      Result := Step;
      Break;
    end;
  end;
end;

function NiceMinorTimeTickMs(MajorMs: Integer; TargetMs: Double): Integer;
const
  STEPS: array[0..20] of Integer = (100, 200, 500, 1000, 2000, 5000,
    10000, 15000, 30000, 60000, 120000, 300000, 600000, 900000,
    1800000, 3600000, 7200000, 14400000, 21600000, 43200000, 86400000);
var
  Step: Integer;
begin
  Result := MajorMs;
  for Step in STEPS do
  begin
    if (Step >= TargetMs) and (Step < MajorMs) and ((MajorMs mod Step) = 0) then
    begin
      Result := Step;
      Break;
    end;
  end;
end;

procedure DrawAlphaBlackRect(Canvas: TCanvas; const DrawRect: TRect;
  Alpha: Byte);
var
  Bitmap: TBitmap;
  Blend: TBlendFunction;
  Line: PBgraQuadArray;
  X: Integer;
  Y: Integer;
begin
  if DrawRect.IsEmpty then
    Exit;

  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(DrawRect.Width, DrawRect.Height);
    Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Bitmap.Height - 1 do
    begin
      Line := Bitmap.ScanLine[Y];
      for X := 0 to Bitmap.Width - 1 do
      begin
        Line[X].B := 0;
        Line[X].G := 0;
        Line[X].R := 0;
        Line[X].A := Alpha;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, DrawRect.Left, DrawRect.Top, DrawRect.Width,
      DrawRect.Height, Bitmap.Canvas.Handle, 0, 0, DrawRect.Width,
      DrawRect.Height, Blend);
  finally
    Bitmap.Free;
  end;
end;

procedure AlphaBlendMask(Canvas: TCanvas; const DestBounds: TRect;
  MaskBitmap: TBitmap; Alpha: Byte; Color: TColor = clWhite);
var
  Blend: TBlendFunction;
  DrawColor: TColor;
  DrawBitmap: TBitmap;
  DrawLine: PBgraQuadArray;
  Height: Integer;
  MaskLine: PRgbTripleArray;
  Blue: Byte;
  Green: Byte;
  Red: Byte;
  Width: Integer;
  X: Integer;
  Y: Integer;
begin
  Width := DestBounds.Width;
  Height := DestBounds.Height;
  if (Width <= 0) or (Height <= 0) then
    Exit;

  DrawBitmap := TBitmap.Create;
  try
    DrawColor := ColorToRGB(Color);
    Red := GetRValue(DrawColor);
    Green := GetGValue(DrawColor);
    Blue := GetBValue(DrawColor);
    DrawBitmap.PixelFormat := pf32bit;
    DrawBitmap.SetSize(Width, Height);
    DrawBitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Height - 1 do
    begin
      MaskLine := MaskBitmap.ScanLine[Y];
      DrawLine := DrawBitmap.ScanLine[Y];
      for X := 0 to Width - 1 do
      begin
        if MaskLine[X].rgbtRed > 0 then
        begin
          DrawLine[X].B := MulDiv(Blue, Alpha, 255);
          DrawLine[X].G := MulDiv(Green, Alpha, 255);
          DrawLine[X].R := MulDiv(Red, Alpha, 255);
          DrawLine[X].A := Alpha
        end
        else
        begin
          DrawLine[X].B := 0;
          DrawLine[X].G := 0;
          DrawLine[X].R := 0;
          DrawLine[X].A := 0;
        end;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, DestBounds.Left, DestBounds.Top, Width, Height,
      DrawBitmap.Canvas.Handle, 0, 0, Width, Height, Blend);
  finally
    DrawBitmap.Free;
  end;
end;

{ TVideoMinerOverlayControl }

constructor TVideoMinerOverlayControl.Create;
begin
  inherited Create;
  FEnabled := True;
  FVisible := True;
end;

function TVideoMinerOverlayControl.HitTest(const Point: TPoint): Boolean;
begin
  Result := FVisible and FEnabled and BoundsHitTest(Point);
end;

function TVideoMinerOverlayControl.BoundsHitTest(const Point: TPoint): Boolean;
begin
  Result := FEnabled and PtInRect(FBounds, Point);
end;

function TVideoMinerOverlayControl.MouseDown(const Point: TPoint): Boolean;
begin
  Result := HitTest(Point);
end;

function TVideoMinerOverlayControl.MouseMove(const Point: TPoint): Boolean;
begin
  Result := HitTest(Point);
end;

function TVideoMinerOverlayControl.MouseUp(const Point: TPoint): Boolean;
begin
  Result := HitTest(Point);
end;

procedure TVideoMinerOverlayControl.Paint(Canvas: TCanvas);
begin
  if FVisible then
    PaintControl(Canvas);
end;

procedure TVideoMinerOverlayControl.UpdateLayout(const PreviewRect: TRect);
begin
  FBounds := CalculateBounds(PreviewRect);
end;

{ TVideoMinerOverlayButton }

procedure TVideoMinerOverlayButton.DrawCenterButtonBackground(Canvas: TCanvas);
var
  Alpha: Byte;
begin
  Alpha := 92;
  if Hovered then
    Alpha := 118;
  if Pressed then
    Alpha := 145;
  DrawAlphaBlackRect(Canvas, Bounds, Alpha);
end;

procedure TVideoMinerOverlayButton.DoClick;
begin
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

function TVideoMinerOverlayButton.MouseDown(const Point: TPoint): Boolean;
begin
  Result := inherited MouseDown(Point);
  FPressed := Result;
end;

function TVideoMinerOverlayButton.MouseMove(const Point: TPoint): Boolean;
var
  NewHovered: Boolean;
begin
  NewHovered := HitTest(Point);
  Result := NewHovered <> FHovered;
  FHovered := NewHovered;
end;

function TVideoMinerOverlayButton.MouseUp(const Point: TPoint): Boolean;
var
  WasPressed: Boolean;
begin
  WasPressed := FPressed;
  FPressed := False;
  Result := inherited MouseUp(Point);
  if WasPressed and Result then
    DoClick;
  Result := WasPressed or Result;
end;

{ TVideoMinerOverlayPlayPauseButton }

function TVideoMinerOverlayPlayPauseButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  CenterX: Integer;
  CenterY: Integer;
  Size: Integer;
begin
  Size := OverlayCenterButtonSize(PreviewRect);

  CenterX := PreviewRect.Left + PreviewRect.Width div 2;
  CenterY := PreviewRect.Top + PreviewRect.Height div 2;

  Result.Left := CenterX - Size div 2;
  Result.Top := CenterY - Size div 2;
  Result.Right := Result.Left + Size;
  Result.Bottom := Result.Top + Size;
end;

procedure TVideoMinerOverlayPlayPauseButton.DrawAlphaPolygon(Canvas: TCanvas;
  const Points: array of TPoint; Alpha: Byte);
var
  Blend: TBlendFunction;
  DrawBitmap: TBitmap;
  DrawLine: PBgraQuadArray;
  Height: Integer;
  MaskBitmap: TBitmap;
  MaskLine: PRgbTripleArray;
  Width: Integer;
  X: Integer;
  Y: Integer;
begin
  Width := Bounds.Width;
  Height := Bounds.Height;
  if (Width <= 0) or (Height <= 0) then
    Exit;

  MaskBitmap := TBitmap.Create;
  DrawBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Width, Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Width, Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Polygon(Points);

    DrawBitmap.PixelFormat := pf32bit;
    DrawBitmap.SetSize(Width, Height);
    DrawBitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Height - 1 do
    begin
      MaskLine := MaskBitmap.ScanLine[Y];
      DrawLine := DrawBitmap.ScanLine[Y];
      for X := 0 to Width - 1 do
      begin
        if MaskLine[X].rgbtRed > 0 then
        begin
          DrawLine[X].B := Alpha;
          DrawLine[X].G := Alpha;
          DrawLine[X].R := Alpha;
          DrawLine[X].A := Alpha
        end
        else
        begin
          DrawLine[X].B := 0;
          DrawLine[X].G := 0;
          DrawLine[X].R := 0;
          DrawLine[X].A := 0;
        end;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Bounds.Left, Bounds.Top, Width, Height,
      DrawBitmap.Canvas.Handle, 0, 0, Width, Height, Blend);
  finally
    DrawBitmap.Free;
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlayPlayPauseButton.DrawAlphaRect(Canvas: TCanvas;
  const Rect: TRect; Alpha: Byte);
var
  Blend: TBlendFunction;
  Bitmap: TBitmap;
  Line: PBgraQuadArray;
  X: Integer;
  Y: Integer;
begin
  if Rect.IsEmpty then
    Exit;

  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Rect.Width, Rect.Height);
    Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Bitmap.Height - 1 do
    begin
      Line := Bitmap.ScanLine[Y];
      for X := 0 to Bitmap.Width - 1 do
      begin
        Line[X].B := Alpha;
        Line[X].G := Alpha;
        Line[X].R := Alpha;
        Line[X].A := Alpha;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Rect.Left, Rect.Top, Rect.Width, Rect.Height,
      Bitmap.Canvas.Handle, 0, 0, Rect.Width, Rect.Height, Blend);
  finally
    Bitmap.Free;
  end;
end;

function TVideoMinerOverlayPlayPauseButton.IconAlpha: Byte;
begin
  Result := 170;
  if Hovered then
    Result := 210;
  if Pressed then
    Result := 245;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlayPlayPauseButton.PaintControl(Canvas: TCanvas);
var
  Alpha: Byte;
  BarGap: Integer;
  BarHeight: Integer;
  BarWidth: Integer;
  CenterX: Integer;
  CenterY: Integer;
  IconSize: Integer;
  LeftBar: TRect;
  LocalPoints: array[0..2] of TPoint;
  RightBar: TRect;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  DrawCenterButtonBackground(Canvas);
  IconSize := Min(Bounds.Width, Bounds.Height);
  CenterX := Bounds.Left + Bounds.Width div 2;
  CenterY := Bounds.Top + Bounds.Height div 2;

  if FIsPlaying then
  begin
    BarWidth := Max(4, Round(IconSize * 0.16));
    BarHeight := Max(12, Round(IconSize * 0.58));
    BarGap := Max(6, Round(IconSize * 0.16));
    LeftBar := Rect(CenterX - BarGap div 2 - BarWidth,
      CenterY - BarHeight div 2, CenterX - BarGap div 2,
      CenterY + BarHeight div 2);
    RightBar := Rect(CenterX + BarGap div 2,
      CenterY - BarHeight div 2, CenterX + BarGap div 2 + BarWidth,
      CenterY + BarHeight div 2);
    DrawAlphaRect(Canvas, LeftBar, Alpha);
    DrawAlphaRect(Canvas, RightBar, Alpha);
  end
  else
  begin
    LocalPoints[0] := Point(Round(IconSize * 0.34), Round(IconSize * 0.22));
    LocalPoints[1] := Point(Round(IconSize * 0.34), Round(IconSize * 0.78));
    LocalPoints[2] := Point(Round(IconSize * 0.76), Round(IconSize * 0.50));
    DrawAlphaPolygon(Canvas, LocalPoints, Alpha);
  end;
end;

{ TVideoMinerOverlaySkipButton }

constructor TVideoMinerOverlaySkipButton.Create(
  Direction: TVideoMinerOverlaySkipDirection);
begin
  inherited Create;
  FDirection := Direction;
end;

function TVideoMinerOverlaySkipButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  CenterX: Integer;
  CenterY: Integer;
  Size: Integer;
  Step: Integer;
begin
  Size := OverlayCenterButtonSize(PreviewRect);
  Step := OverlayCenterStep(PreviewRect);

  CenterX := PreviewRect.Left + PreviewRect.Width div 2;
  if FDirection = sdBackward then
    Dec(CenterX, Step)
  else
    Inc(CenterX, Step);
  CenterY := PreviewRect.Top + PreviewRect.Height div 2;

  Result.Left := CenterX - Size div 2;
  Result.Top := CenterY - Size div 2;
  Result.Right := Result.Left + Size;
  Result.Bottom := Result.Top + Size;
end;

procedure TVideoMinerOverlaySkipButton.DrawAlphaPolygon(Canvas: TCanvas;
  const Points: array of TPoint; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Polygon(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySkipButton.DrawAlphaPolyline(Canvas: TCanvas;
  const Points: array of TPoint; PenWidth: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or (Length(Points) <= 1) then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Color := clWhite;
    MaskBitmap.Canvas.Pen.Width := PenWidth;
    MaskBitmap.Canvas.Pen.Style := psSolid;
    MaskBitmap.Canvas.Polyline(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

function TVideoMinerOverlaySkipButton.IconAlpha: Byte;
begin
  Result := 155;
  if Hovered then
    Result := 205;
  if Pressed then
    Result := 240;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlaySkipButton.PaintControl(Canvas: TCanvas);
const
  ARC_POINT_COUNT = 24; // 10 秒スキップ用の曲線矢印を構成する点数
var
  Alpha: Byte;
  Angle: Double;
  ArcPoints: array of TPoint;
  CenterX: Double;
  CenterY: Double;
  HeadPoints: array[0..2] of TPoint;
  I: Integer;
  LocalX: Integer;
  PenWidth: Integer;
  RadiusX: Double;
  RadiusY: Double;
  Size: Integer;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  DrawCenterButtonBackground(Canvas);
  Size := Min(Bounds.Width, Bounds.Height);
  CenterX := Size * 0.50;
  CenterY := Size * 0.55;
  RadiusX := Size * 0.29;
  RadiusY := Size * 0.28;

  SetLength(ArcPoints, ARC_POINT_COUNT);
  for I := 0 to ARC_POINT_COUNT - 1 do
  begin
    Angle := (210 - (190 * I / (ARC_POINT_COUNT - 1))) * Pi / 180;
    LocalX := Round(CenterX + Cos(Angle) * RadiusX);
    if FDirection = sdBackward then
      LocalX := Size - LocalX;
    ArcPoints[I] := Point(LocalX, Round(CenterY + Sin(Angle) * RadiusY));
  end;

  PenWidth := Max(3, Round(Size * 0.075));
  DrawAlphaPolyline(Canvas, ArcPoints, PenWidth, Alpha);

  if FDirection = sdForward then
  begin
    HeadPoints[0] := Point(Round(Size * 0.78), Round(Size * 0.44));
    HeadPoints[1] := Point(Round(Size * 0.61), Round(Size * 0.35));
    HeadPoints[2] := Point(Round(Size * 0.66), Round(Size * 0.57));
  end
  else
  begin
    HeadPoints[0] := Point(Round(Size * 0.22), Round(Size * 0.44));
    HeadPoints[1] := Point(Round(Size * 0.39), Round(Size * 0.35));
    HeadPoints[2] := Point(Round(Size * 0.34), Round(Size * 0.57));
  end;
  DrawAlphaPolygon(Canvas, HeadPoints, Alpha);
end;

{ TVideoMinerOverlayEdgeButton }

constructor TVideoMinerOverlayEdgeButton.Create(
  Direction: TVideoMinerOverlayEdgeDirection);
begin
  inherited Create;
  FDirection := Direction;
end;

function TVideoMinerOverlayEdgeButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  CenterX: Integer;
  CenterY: Integer;
  Size: Integer;
  Step: Integer;
begin
  Size := OverlayCenterButtonSize(PreviewRect);
  Step := OverlayCenterStep(PreviewRect);

  CenterX := PreviewRect.Left + PreviewRect.Width div 2;
  if FDirection = edFirst then
    Dec(CenterX, Step * 2)
  else
    Inc(CenterX, Step * 2);
  CenterY := PreviewRect.Top + PreviewRect.Height div 2;

  Result.Left := CenterX - Size div 2;
  Result.Top := CenterY - Size div 2;
  Result.Right := Result.Left + Size;
  Result.Bottom := Result.Top + Size;
end;

procedure TVideoMinerOverlayEdgeButton.DrawAlphaPolygon(Canvas: TCanvas;
  const Points: array of TPoint; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Polygon(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlayEdgeButton.DrawAlphaRect(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.FillRect(DrawRect);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

function TVideoMinerOverlayEdgeButton.IconAlpha: Byte;
begin
  Result := 135;
  if Hovered then
    Result := 195;
  if Pressed then
    Result := 235;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlayEdgeButton.PaintControl(Canvas: TCanvas);
var
  Alpha: Byte;
  BarRect: TRect;
  IconSize: Integer;
  TrianglePoints: array[0..2] of TPoint;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  DrawCenterButtonBackground(Canvas);
  IconSize := Min(Bounds.Width, Bounds.Height);

  if FDirection = edFirst then
  begin
    BarRect := Rect(Round(IconSize * 0.22), Round(IconSize * 0.28),
      Round(IconSize * 0.29), Round(IconSize * 0.72));
    TrianglePoints[0] := Point(Round(IconSize * 0.73), Round(IconSize * 0.24));
    TrianglePoints[1] := Point(Round(IconSize * 0.73), Round(IconSize * 0.76));
    TrianglePoints[2] := Point(Round(IconSize * 0.37), Round(IconSize * 0.50));
  end
  else
  begin
    BarRect := Rect(Round(IconSize * 0.71), Round(IconSize * 0.28),
      Round(IconSize * 0.78), Round(IconSize * 0.72));
    TrianglePoints[0] := Point(Round(IconSize * 0.27), Round(IconSize * 0.24));
    TrianglePoints[1] := Point(Round(IconSize * 0.27), Round(IconSize * 0.76));
    TrianglePoints[2] := Point(Round(IconSize * 0.63), Round(IconSize * 0.50));
  end;

  DrawAlphaRect(Canvas, BarRect, Alpha);
  DrawAlphaPolygon(Canvas, TrianglePoints, Alpha);
end;

{ TVideoMinerOverlayFileNavButton }

constructor TVideoMinerOverlayFileNavButton.Create(
  Direction: TVideoMinerOverlayFileNavDirection);
begin
  inherited Create;
  FDirection := Direction;
end;

function TVideoMinerOverlayFileNavButton.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  Height: Integer;
  Width: Integer;
begin
  Result := TRect.Empty;
  if PreviewRect.IsEmpty then
    Exit;

  Width := Round(PreviewRect.Width * 0.065);
  Width := Max(38, Min(84, Width));
  Height := Round(PreviewRect.Height * 0.64);
  Height := Max(150, Min(430, Height));

  if FDirection = fndPrevious then
  begin
    Result.Left := PreviewRect.Left;
    Result.Right := PreviewRect.Left + Width;
  end
  else
  begin
    Result.Left := PreviewRect.Right - Width;
    Result.Right := PreviewRect.Right;
  end;
  Result.Top := PreviewRect.Top + (PreviewRect.Height - Height) div 2;
  Result.Bottom := Result.Top + Height;
end;

procedure TVideoMinerOverlayFileNavButton.DrawAlphaRect(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  Bitmap: TBitmap;
  Blend: TBlendFunction;
  Line: PBgraQuadArray;
  X: Integer;
  Y: Integer;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(DrawRect.Width, DrawRect.Height);
    Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Bitmap.Height - 1 do
    begin
      Line := Bitmap.ScanLine[Y];
      for X := 0 to Bitmap.Width - 1 do
      begin
        Line[X].B := 0;
        Line[X].G := 0;
        Line[X].R := 0;
        Line[X].A := Alpha;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Bounds.Left + DrawRect.Left,
      Bounds.Top + DrawRect.Top, DrawRect.Width, DrawRect.Height,
      Bitmap.Canvas.Handle, 0, 0, DrawRect.Width, DrawRect.Height, Blend);
  finally
    Bitmap.Free;
  end;
end;

procedure TVideoMinerOverlayFileNavButton.DrawAlphaPolyline(Canvas: TCanvas;
  const Points: array of TPoint; PenWidth: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or (Length(Points) <= 1) then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Color := clWhite;
    MaskBitmap.Canvas.Pen.Width := PenWidth;
    MaskBitmap.Canvas.Pen.Style := psSolid;
    MaskBitmap.Canvas.Polyline(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

function TVideoMinerOverlayFileNavButton.IconAlpha: Byte;
begin
  Result := 120;
  if Hovered then
    Result := 190;
  if Pressed then
    Result := 230;
  Result := ClampByte(Result);
end;

procedure TVideoMinerOverlayFileNavButton.PaintControl(Canvas: TCanvas);
var
  Alpha: Byte;
  BackgroundAlpha: Byte;
  BackgroundRect: TRect;
  Chevron: array[0..2] of TPoint;
  IconCenterX: Integer;
  IconHeight: Integer;
  IconWidth: Integer;
  IconLeft: Integer;
  IconTop: Integer;
  PenWidth: Integer;
begin
  if Bounds.IsEmpty then
    Exit;

  Alpha := IconAlpha;
  IconWidth := Max(18, Min(36, Round(Bounds.Width * 0.46)));
  IconHeight := Max(58, Min(130, Round(Bounds.Height * 0.34)));
  IconTop := (Bounds.Height - IconHeight) div 2;
  PenWidth := Max(3, Round(IconWidth * 0.16));
  BackgroundRect := Rect(0, Max(8, IconTop - 28), Bounds.Width,
    Min(Bounds.Height - 8, IconTop + IconHeight + 28));
  BackgroundAlpha := 72;
  if Hovered then
    BackgroundAlpha := 104;
  if Pressed then
    BackgroundAlpha := 132;
  DrawAlphaRect(Canvas, BackgroundRect, BackgroundAlpha);

  if FDirection = fndPrevious then
  begin
    IconCenterX := BackgroundRect.Left + BackgroundRect.Width div 2;
    IconLeft := IconCenterX - IconWidth div 2;
    Chevron[0] := Point(IconLeft + IconWidth, IconTop);
    Chevron[1] := Point(IconLeft, IconTop + IconHeight div 2);
    Chevron[2] := Point(IconLeft + IconWidth, IconTop + IconHeight);
  end
  else
  begin
    IconCenterX := BackgroundRect.Left + BackgroundRect.Width div 2;
    IconLeft := IconCenterX - IconWidth div 2;
    Chevron[0] := Point(IconLeft, IconTop);
    Chevron[1] := Point(IconLeft + IconWidth, IconTop + IconHeight div 2);
    Chevron[2] := Point(IconLeft, IconTop + IconHeight);
  end;

  DrawAlphaPolyline(Canvas, Chevron, PenWidth, Alpha);
end;

{ TVideoMinerOverlaySeekBar }

function TVideoMinerOverlaySeekBar.CalculateBounds(
  const PreviewRect: TRect): TRect;
var
  BottomOffset: Integer;
  Height: Integer;
  Width: Integer;
begin
  Result := TRect.Empty;
  if PreviewRect.IsEmpty then
    Exit;

  Height := 96;
  Width := Round(PreviewRect.Width * 0.88);
  Width := Max(160, Min(PreviewRect.Width - 32, Width));
  BottomOffset := Max(18, Round(Min(PreviewRect.Width, PreviewRect.Height) * 0.075));

  Result.Left := PreviewRect.Left + (PreviewRect.Width - Width) div 2;
  Result.Right := Result.Left + Width;
  Result.Bottom := PreviewRect.Bottom - BottomOffset;
  Result.Top := Result.Bottom - Height;
  if Result.Top < PreviewRect.Top then
    OffsetRect(Result, 0, PreviewRect.Top - Result.Top);
end;

function TVideoMinerOverlaySeekBar.DisplayPositionMs: Integer;
begin
  if FDragging then
    Result := FDragPositionMs
  else
    Result := FPositionMs;

  if Result < 0 then
    Result := 0
  else if Result > FMaxMs then
    Result := FMaxMs;
end;

function TVideoMinerOverlaySeekBar.TimeViewActive: Boolean;
begin
  Result := (FMaxMs > 0) and (FTimeViewSpanMs > 0) and
    (FTimeViewSpanMs < FMaxMs);
end;

function TVideoMinerOverlaySeekBar.TimeViewSpanMs: Integer;
begin
  if TimeViewActive then
    Result := FTimeViewSpanMs
  else
    Result := FMaxMs;
  Result := Max(0, Result);
end;

function TVideoMinerOverlaySeekBar.TimeViewEndMs: Integer;
begin
  if TimeViewActive then
    Result := Min(FMaxMs, FTimeViewStartMs + FTimeViewSpanMs)
  else
    Result := FMaxMs;
end;

function TVideoMinerOverlaySeekBar.TimeViewPositionVisible(
  PositionMs: Integer): Boolean;
begin
  Result := (FMaxMs > 0) and (PositionMs >= 0) and (PositionMs <= FMaxMs);
  if Result and TimeViewActive then
    Result := (PositionMs >= FTimeViewStartMs) and
      (PositionMs <= TimeViewEndMs);
end;

function TVideoMinerOverlaySeekBar.TimeViewPositionRatio(
  PositionMs: Integer): Double;
var
  SpanMs: Integer;
  StartMs: Integer;
begin
  if FMaxMs <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  if TimeViewActive then
  begin
    StartMs := FTimeViewStartMs;
    SpanMs := FTimeViewSpanMs;
  end
  else
  begin
    StartMs := 0;
    SpanMs := FMaxMs;
  end;

  Result := (PositionMs - StartMs) / Max(1, SpanMs);
  Result := Max(0.0, Min(1.0, Result));
end;

function TVideoMinerOverlaySeekBar.TimeRulerHitTest(
  const Point: TPoint): Boolean;
var
  HitRect: TRect;
  LocalPoint: TPoint;
  Track: TRect;
begin
  Result := False;
  if (FMaxMs <= 0) or (not BoundsHitTest(Point)) then
    Exit;

  Track := TrackRect;
  if Track.IsEmpty then
    Exit;

  HitRect := Rect(Track.Left, Track.Bottom + 4, Track.Right,
    Max(Track.Bottom + 24, ToolRowCenterY - 14));
  LocalPoint := System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top);
  Result := PtInRect(HitRect, LocalPoint);
end;

function TVideoMinerOverlaySeekBar.FormatTimeMs(ValueMs: Integer): string;
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

  Result := Format('%d:%.2d:%.2d', [Hours, Minutes, Seconds]);
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaEllipse(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte; Color: TColor);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.Ellipse(DrawRect);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha, Color);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaPanel(Canvas: TCanvas;
  const DrawRect: TRect; Radius: Integer; Alpha: Byte);
var
  Bitmap: TBitmap;
  Blend: TBlendFunction;
  Line: PBgraQuadArray;
  MaskBitmap: TBitmap;
  MaskLine: PRgbTripleArray;
  X: Integer;
  Y: Integer;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  Bitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.RoundRect(DrawRect.Left, DrawRect.Top, DrawRect.Right,
      DrawRect.Bottom, Radius, Radius);

    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Bounds.Width, Bounds.Height);
    Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to Bounds.Height - 1 do
    begin
      MaskLine := MaskBitmap.ScanLine[Y];
      Line := Bitmap.ScanLine[Y];
      for X := 0 to Bounds.Width - 1 do
      begin
        if MaskLine[X].rgbtRed > 0 then
        begin
          Line[X].B := 0;
          Line[X].G := 0;
          Line[X].R := 0;
          Line[X].A := Alpha;
        end
        else
        begin
          Line[X].B := 0;
          Line[X].G := 0;
          Line[X].R := 0;
          Line[X].A := 0;
        end;
      end;
    end;

    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 255;
    Blend.AlphaFormat := AC_SRC_ALPHA;
    AlphaBlend(Canvas.Handle, Bounds.Left, Bounds.Top, Bounds.Width,
      Bounds.Height, Bitmap.Canvas.Handle, 0, 0, Bounds.Width, Bounds.Height,
      Blend);
  finally
    Bitmap.Free;
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaPolyline(Canvas: TCanvas;
  const Points: array of TPoint; PenWidth: Integer; Alpha: Byte);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or (Length(Points) <= 1) then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Color := clWhite;
    MaskBitmap.Canvas.Pen.Width := PenWidth;
    MaskBitmap.Canvas.Pen.Style := psSolid;
    MaskBitmap.Canvas.Polyline(Points);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawAlphaRoundRect(Canvas: TCanvas;
  const DrawRect: TRect; Radius: Integer; Alpha: Byte; Color: TColor);
var
  MaskBitmap: TBitmap;
begin
  if Bounds.IsEmpty or DrawRect.IsEmpty then
    Exit;

  MaskBitmap := TBitmap.Create;
  try
    MaskBitmap.PixelFormat := pf24bit;
    MaskBitmap.SetSize(Bounds.Width, Bounds.Height);
    MaskBitmap.Canvas.Brush.Color := clBlack;
    MaskBitmap.Canvas.FillRect(Rect(0, 0, Bounds.Width, Bounds.Height));
    MaskBitmap.Canvas.Pen.Style := psClear;
    MaskBitmap.Canvas.Brush.Color := clWhite;
    MaskBitmap.Canvas.RoundRect(DrawRect.Left, DrawRect.Top, DrawRect.Right,
      DrawRect.Bottom, Radius, Radius);
    AlphaBlendMask(Canvas, Bounds, MaskBitmap, Alpha, Color);
  finally
    MaskBitmap.Free;
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawFullScreenIcon(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  Bottom: Integer;
  CenterX: Integer;
  CenterY: Integer;
  Head: Integer;
  Inset: Integer;
  Left: Integer;
  PenWidth: Integer;
  Right: Integer;
  Top: Integer;
  WindowRect: TRect;
begin
  if DrawRect.IsEmpty then
    Exit;

  Left := DrawRect.Left;
  Top := DrawRect.Top;
  Right := DrawRect.Right - 1;
  Bottom := DrawRect.Bottom - 1;
  CenterX := DrawRect.Left + DrawRect.Width div 2;
  CenterY := DrawRect.Top + DrawRect.Height div 2;
  Inset := 7;
  Head := 8;
  PenWidth := 2;

  if not FFullScreen then
  begin
    DrawAlphaPolyline(Canvas, [Point(CenterX - 3, CenterY - 3),
      Point(Left + Inset, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Top + Inset),
      Point(Left + Inset + Head, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Top + Inset),
      Point(Left + Inset, Top + Inset + Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(CenterX + 3, CenterY - 3),
      Point(Right - Inset, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Top + Inset),
      Point(Right - Inset - Head, Top + Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Top + Inset),
      Point(Right - Inset, Top + Inset + Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(CenterX - 3, CenterY + 3),
      Point(Left + Inset, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Bottom - Inset),
      Point(Left + Inset + Head, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Bottom - Inset),
      Point(Left + Inset, Bottom - Inset - Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(CenterX + 3, CenterY + 3),
      Point(Right - Inset, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Bottom - Inset),
      Point(Right - Inset - Head, Bottom - Inset)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Bottom - Inset),
      Point(Right - Inset, Bottom - Inset - Head)], PenWidth, Alpha);
  end
  else
  begin
    WindowRect := Rect(CenterX - 7, CenterY - 6, CenterX + 8, CenterY + 7);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Top),
      Point(WindowRect.Right, WindowRect.Top), Point(WindowRect.Right,
      WindowRect.Bottom), Point(WindowRect.Left, WindowRect.Bottom),
      Point(WindowRect.Left, WindowRect.Top)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Top + Inset),
      Point(WindowRect.Left, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Top),
      Point(WindowRect.Left - Head, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Top),
      Point(WindowRect.Left, WindowRect.Top - Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Top + Inset),
      Point(WindowRect.Right, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Top),
      Point(WindowRect.Right + Head, WindowRect.Top)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Top),
      Point(WindowRect.Right, WindowRect.Top - Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Left + Inset, Bottom - Inset),
      Point(WindowRect.Left, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Bottom),
      Point(WindowRect.Left - Head, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Left, WindowRect.Bottom),
      Point(WindowRect.Left, WindowRect.Bottom + Head)], PenWidth, Alpha);

    DrawAlphaPolyline(Canvas, [Point(Right - Inset, Bottom - Inset),
      Point(WindowRect.Right, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Bottom),
      Point(WindowRect.Right + Head, WindowRect.Bottom)], PenWidth, Alpha);
    DrawAlphaPolyline(Canvas, [Point(WindowRect.Right, WindowRect.Bottom),
      Point(WindowRect.Right, WindowRect.Bottom + Head)], PenWidth, Alpha);
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawMuteIcon(Canvas: TCanvas;
  const DrawRect: TRect; Alpha: Byte);
var
  CenterY: Integer;
  Left: Integer;
  PenWidth: Integer;
  Speaker: array[0..4] of TPoint;
  Top: Integer;
begin
  if DrawRect.IsEmpty then
    Exit;

  Left := DrawRect.Left + 8;
  Top := DrawRect.Top + 8;
  CenterY := DrawRect.Top + DrawRect.Height div 2;
  PenWidth := 2;

  Speaker[0] := Point(Left, CenterY - 4);
  Speaker[1] := Point(Left + 5, CenterY - 4);
  Speaker[2] := Point(Left + 11, Top);
  Speaker[3] := Point(Left + 11, DrawRect.Bottom - 8);
  Speaker[4] := Point(Left + 5, CenterY + 4);
  DrawAlphaPolyline(Canvas, Speaker, PenWidth, Alpha);
  DrawAlphaPolyline(Canvas, [Speaker[4], Speaker[0]], PenWidth, Alpha);

  if FMuted or (FVolumePercent <= 0) then
  begin
    DrawAlphaPolyline(Canvas, [Point(DrawRect.Right - 9, DrawRect.Top + 8),
      Point(DrawRect.Right - 20, DrawRect.Bottom - 8)], PenWidth, Alpha);
  end
  else
  begin
    DrawAlphaPolyline(Canvas, [Point(DrawRect.Right - 13, CenterY - 7),
      Point(DrawRect.Right - 9, CenterY - 3), Point(DrawRect.Right - 9,
      CenterY + 3), Point(DrawRect.Right - 13, CenterY + 7)], PenWidth,
      Alpha);
  end;
end;

function TVideoMinerOverlaySeekBar.FullScreenButtonAlpha: Byte;
begin
  Result := 185;
  if FFullScreenButtonHovered then
    Result := 225;
  if FFullScreenButtonPressed then
    Result := 250;
  Result := ClampByte(Result);
end;

function TVideoMinerOverlaySeekBar.MuteButtonAlpha: Byte;
begin
  Result := 185;
  if FMuteButtonHovered or FMuted then
    Result := 225;
  if FMuteButtonPressed then
    Result := 250;
  Result := ClampByte(Result);
end;

function TVideoMinerOverlaySeekBar.AddChapterButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(AddChapterButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.AddChapterButtonRect: TRect;
var
  DeleteRect: TRect;
begin
  Result := TRect.Empty;
  if not SecondaryToolButtonsVisible then
    Exit;

  DeleteRect := DeleteChapterButtonRect;
  Result := ToolRowRect(DeleteRect.Left - 38, 32, DeleteRect.Height);
end;

function TVideoMinerOverlaySeekBar.ChapterColor(
  Severity: TVideoMinerOverlayChapterSeverity): TColor;
begin
  case Severity of
    csGreen:
      Result := $0046D56A;
    csYellow:
      Result := $0024D9F0;
  else
    Result := $002424E8;
  end;
end;

function TVideoMinerOverlaySeekBar.CheckButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(CheckButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.CheckButtonRect: TRect;
var
  EndRect: TRect;
begin
  EndRect := EndActionButtonRect;
  Result := ToolRowRect(EndRect.Left - 84, 76, EndRect.Height);
end;

function TVideoMinerOverlaySeekBar.DeleteChapterButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(DeleteChapterButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.DeleteChapterButtonRect: TRect;
var
  CheckRect: TRect;
begin
  Result := TRect.Empty;
  if not SecondaryToolButtonsVisible then
    Exit;

  CheckRect := CheckButtonRect;
  Result := ToolRowRect(CheckRect.Left - 38, 32, CheckRect.Height);
end;

function TVideoMinerOverlaySeekBar.EndActionButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(EndActionButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.EndActionButtonRect: TRect;
var
  FullScreenRect: TRect;
begin
  FullScreenRect := FullScreenButtonRect;
  Result := ToolRowRect(FullScreenRect.Left - 62, 54, FullScreenRect.Height);
end;

function TVideoMinerOverlaySeekBar.FullScreenButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(FullScreenButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.MuteButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(MuteButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.FullScreenButtonRect: TRect;
var
  Size: Integer;
begin
  Size := 34;
  Result := ToolRowRect(Bounds.Width - Size - 14, Size, Size);
end;

function TVideoMinerOverlaySeekBar.MuteButtonRect: TRect;
var
  LabelRect: TRect;
  Size: Integer;
begin
  LabelRect := VolumeLabelRect;
  Size := 28;
  Result := ToolRowRect(LabelRect.Right + 22, Size, Size);
end;

function TVideoMinerOverlaySeekBar.PlaybackRateButtonHitTest(
  const Point: TPoint): Boolean;
begin
  Result := BoundsHitTest(Point) and PtInRect(PlaybackRateButtonRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.PlaybackRateButtonRect: TRect;
var
  MuteRect: TRect;
begin
  Result := TRect.Empty;
  if not SecondaryToolButtonsVisible then
    Exit;

  MuteRect := MuteButtonRect;
  Result := ToolRowRect(MuteRect.Right + 12, 54, MuteRect.Height);
end;

function TVideoMinerOverlaySeekBar.SecondaryToolButtonsVisible: Boolean;
begin
  Result := Bounds.Width >= SECONDARY_TOOL_BUTTONS_MIN_WIDTH;
end;

function TVideoMinerOverlaySeekBar.ToolRowCenterY: Integer;
begin
  Result := Bounds.Height - 29;
end;

function TVideoMinerOverlaySeekBar.ToolRowRect(Left, Width,
  Height: Integer): TRect;
var
  Top: Integer;
begin
  Top := ToolRowCenterY - Height div 2;
  Result := Rect(Left, Top, Left + Width, Top + Height);
end;

function TVideoMinerOverlaySeekBar.VolumeLabelRect: TRect;
begin
  Result := ToolRowRect(22, 90, 20);
end;

function TVideoMinerOverlaySeekBar.VolumeTrackRect: TRect;
var
  LabelRect: TRect;
  TrackTop: Integer;
begin
  LabelRect := VolumeLabelRect;
  TrackTop := LabelRect.Bottom + 4;
  Result := Rect(LabelRect.Left, TrackTop, LabelRect.Right, TrackTop + 5);
end;

function TVideoMinerOverlaySeekBar.VolumeHitTest(const Point: TPoint): Boolean;
var
  HitRect: TRect;
begin
  HitRect := VolumeTrackRect;
  HitRect.Left := VolumeLabelRect.Left;
  InflateRect(HitRect, 8, 10);
  Result := BoundsHitTest(Point) and PtInRect(HitRect,
    System.Types.Point(Point.X - Bounds.Left, Point.Y - Bounds.Top));
end;

function TVideoMinerOverlaySeekBar.VolumeFromPoint(const Point: TPoint): Integer;
var
  LocalX: Integer;
  Track: TRect;
begin
  Track := VolumeTrackRect;
  LocalX := Point.X - Bounds.Left;
  if LocalX < Track.Left then
    LocalX := Track.Left
  else if LocalX > Track.Right then
    LocalX := Track.Right;

  Result := Round((LocalX - Track.Left) / Max(1, Track.Width) * 100);
  Result := Max(0, Min(100, Result));
end;

procedure TVideoMinerOverlaySeekBar.DrawChapterMarkers(Canvas: TCanvas;
  const Track: TRect);
var
  Chapter: TVideoMinerOverlayChapter;
  LineBottom: Integer;
  LineTop: Integer;
  MarkerColor: TColor;
  MarkerX: Integer;
  Ratio: Double;
  TipY: Integer;
  TriangleBaseY: Integer;
begin
  if (FMaxMs <= 0) or Track.IsEmpty then
    Exit;

  LineTop := Track.Top - 2;
  LineBottom := Track.Bottom + 6;
  TriangleBaseY := Track.Bottom + 15;
  TipY := Track.Bottom + 5;
  for Chapter in FChapters do
  begin
    if TimeViewActive and ((Chapter.PositionMs < FTimeViewStartMs) or
       (Chapter.PositionMs > TimeViewEndMs)) then
      Continue;
    Ratio := TimeViewPositionRatio(Chapter.PositionMs);
    MarkerX := Track.Left + Round(Track.Width * Ratio);
    MarkerColor := ChapterColor(Chapter.Severity);
    Canvas.Brush.Color := MarkerColor;
    Canvas.Pen.Color := MarkerColor;
    Canvas.Rectangle(Bounds.Left + MarkerX - 1, Bounds.Top + LineTop,
      Bounds.Left + MarkerX + 2, Bounds.Top + LineBottom);
    Canvas.Polygon([Point(Bounds.Left + MarkerX, Bounds.Top + TipY),
      Point(Bounds.Left + MarkerX - 5, Bounds.Top + TriangleBaseY),
      Point(Bounds.Left + MarkerX + 5, Bounds.Top + TriangleBaseY)]);
  end;
end;

procedure TVideoMinerOverlaySeekBar.DrawTimeRuler(Canvas: TCanvas;
  const Track: TRect);
var
  EndMs: Integer;
  LabelText: string;
  LabelSize: TSize;
  LastLabelRight: Integer;
  MajorMs: Integer;
  MinorMs: Integer;
  TickMs: Integer;
  TickX: Integer;
  TickY: Integer;
  Ratio: Double;
  StartMs: Integer;
begin
  if Track.IsEmpty or (Track.Width <= 0) or (FMaxMs <= 0) then
    Exit;

  StartMs := FTimeViewStartMs;
  EndMs := TimeViewEndMs;
  MajorMs := NiceTimeTickMs(TimeViewSpanMs / Max(1, Track.Width) *
    SEEK_TIME_RULER_MAJOR_MIN_PX);
  MinorMs := NiceMinorTimeTickMs(MajorMs, TimeViewSpanMs /
    Max(1, Track.Width) * SEEK_TIME_RULER_MINOR_MIN_PX);

  TickY := Track.Bottom + 6;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  LastLabelRight := Track.Left - 1000;

  TickMs := (StartMs div MinorMs) * MinorMs;
  if TickMs < StartMs then
    Inc(TickMs, MinorMs);
  while TickMs <= EndMs do
  begin
    Ratio := TimeViewPositionRatio(TickMs);
    TickX := Track.Left + Round(Track.Width * Ratio);
    if (TickMs mod MajorMs) = 0 then
    begin
      Canvas.Pen.Width := 2;
      Canvas.Pen.Color := $00D0D0D0;
      Canvas.MoveTo(Bounds.Left + TickX, Bounds.Top + TickY);
      Canvas.LineTo(Bounds.Left + TickX, Bounds.Top + TickY + 8);
      LabelText := FormatTimeMs(TickMs);
      LabelSize := Canvas.TextExtent(LabelText);
      if TickX - LabelSize.cx div 2 > LastLabelRight + 8 then
      begin
        Canvas.TextOut(Bounds.Left + TickX - LabelSize.cx div 2,
          Bounds.Top + TickY + 12, LabelText);
        LastLabelRight := TickX + LabelSize.cx div 2;
      end;
    end
    else if MinorMs < MajorMs then
    begin
      Canvas.Pen.Width := 2;
      Canvas.Pen.Color := $00B8B8B8;
      Canvas.MoveTo(Bounds.Left + TickX, Bounds.Top + TickY);
      Canvas.LineTo(Bounds.Left + TickX, Bounds.Top + TickY + 4);
    end;
    Inc(TickMs, MinorMs);
  end;

  if TimeViewActive and (FTimeViewStartMs > 0) then
  begin
    Canvas.Pen.Color := $00D0D0D0;
    Canvas.MoveTo(Bounds.Left + Track.Left, Bounds.Top + TickY + 1);
    Canvas.LineTo(Bounds.Left + Track.Left + 7, Bounds.Top + TickY + 5);
    Canvas.LineTo(Bounds.Left + Track.Left, Bounds.Top + TickY + 9);
  end;
  if TimeViewActive and (TimeViewEndMs < FMaxMs) then
  begin
    Canvas.Pen.Color := $00D0D0D0;
    Canvas.MoveTo(Bounds.Left + Track.Right, Bounds.Top + TickY + 1);
    Canvas.LineTo(Bounds.Left + Track.Right - 7, Bounds.Top + TickY + 5);
    Canvas.LineTo(Bounds.Left + Track.Right, Bounds.Top + TickY + 9);
  end;
  Canvas.Pen.Style := psClear;
end;

procedure TVideoMinerOverlaySeekBar.DrawTextButton(Canvas: TCanvas;
  const ButtonRect: TRect; const Text: string; Active, Hovered, Pressed: Boolean;
  ActiveColor: TColor);
var
  TextSize: TSize;
begin
  if ButtonRect.IsEmpty then
    Exit;

  if Hovered or Pressed or Active then
    DrawAlphaRoundRect(Canvas, ButtonRect, 8, 38);

  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  if Active then
    Canvas.Font.Color := ActiveColor
  else
    Canvas.Font.Color := clWhite;
  TextSize := Canvas.TextExtent(Text);
  Canvas.TextOut(Bounds.Left + ButtonRect.Left +
    (ButtonRect.Width - TextSize.cx) div 2,
    Bounds.Top + ButtonRect.Top + (ButtonRect.Height - TextSize.cy) div 2,
    Text);
end;

function TVideoMinerOverlaySeekBar.MouseDown(const Point: TPoint): Boolean;
var
  NewVolume: Integer;
begin
  Result := BoundsHitTest(Point);
  if not Result then
    Exit;

  if FullScreenButtonHitTest(Point) then
  begin
    FFullScreenButtonPressed := True;
    FFullScreenButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if EndActionButtonHitTest(Point) then
  begin
    FEndActionButtonPressed := True;
    FEndActionButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if CheckButtonHitTest(Point) then
  begin
    FCheckButtonPressed := True;
    FCheckButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if DeleteChapterButtonHitTest(Point) then
  begin
    FDeleteChapterButtonPressed := True;
    FDeleteChapterButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if AddChapterButtonHitTest(Point) then
  begin
    FAddChapterButtonPressed := True;
    FAddChapterButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if MuteButtonHitTest(Point) then
  begin
    FMuteButtonPressed := True;
    FMuteButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if PlaybackRateButtonHitTest(Point) then
  begin
    FPlaybackRateButtonPressed := True;
    FPlaybackRateButtonHovered := True;
    FHovered := True;
    Exit;
  end;

  if VolumeHitTest(Point) then
  begin
    FVolumeDragging := True;
    FVolumeHovered := True;
    FHovered := True;
    NewVolume := VolumeFromPoint(Point);
    if NewVolume <> FVolumePercent then
    begin
      FVolumePercent := NewVolume;
      if Assigned(FOnVolumeChange) then
        FOnVolumeChange(Self, FVolumePercent);
    end;
    Exit;
  end;

  if TimeRulerHitTest(Point) then
  begin
    FHovered := True;
    if TimeViewActive then
    begin
      FTimeViewPanning := True;
      FTimeViewPanStartMs := FTimeViewStartMs;
      FTimeViewPanStartX := Point.X;
    end;
    Exit;
  end;

  FDragging := True;
  FHovered := True;
  FDragPositionMs := PositionFromPoint(Point);
end;

function TVideoMinerOverlaySeekBar.MouseMove(const Point: TPoint): Boolean;
var
  NewAddChapterButtonHovered: Boolean;
  NewDeleteChapterButtonHovered: Boolean;
  NewEndActionButtonHovered: Boolean;
  NewFullScreenButtonHovered: Boolean;
  NewHovered: Boolean;
  NewMuteButtonHovered: Boolean;
  NewPositionMs: Integer;
  NewPlaybackRateButtonHovered: Boolean;
  NewVolume: Integer;
  NewVolumeHovered: Boolean;
begin
  NewHovered := FDragging or FTimeViewPanning or FVolumeDragging or
    BoundsHitTest(Point);
  Result := NewHovered <> FHovered;
  FHovered := NewHovered;

  NewEndActionButtonHovered := EndActionButtonHitTest(Point);
  if NewEndActionButtonHovered <> FEndActionButtonHovered then
  begin
    FEndActionButtonHovered := NewEndActionButtonHovered;
    Result := True;
  end;

  NewEndActionButtonHovered := CheckButtonHitTest(Point);
  if NewEndActionButtonHovered <> FCheckButtonHovered then
  begin
    FCheckButtonHovered := NewEndActionButtonHovered;
    Result := True;
  end;

  NewDeleteChapterButtonHovered := DeleteChapterButtonHitTest(Point);
  if NewDeleteChapterButtonHovered <> FDeleteChapterButtonHovered then
  begin
    FDeleteChapterButtonHovered := NewDeleteChapterButtonHovered;
    Result := True;
  end;

  NewAddChapterButtonHovered := AddChapterButtonHitTest(Point);
  if NewAddChapterButtonHovered <> FAddChapterButtonHovered then
  begin
    FAddChapterButtonHovered := NewAddChapterButtonHovered;
    Result := True;
  end;

  NewVolumeHovered := VolumeHitTest(Point);
  if NewVolumeHovered <> FVolumeHovered then
  begin
    FVolumeHovered := NewVolumeHovered;
    Result := True;
  end;

  NewFullScreenButtonHovered := FullScreenButtonHitTest(Point);
  if NewFullScreenButtonHovered <> FFullScreenButtonHovered then
  begin
    FFullScreenButtonHovered := NewFullScreenButtonHovered;
    Result := True;
  end;

  NewMuteButtonHovered := MuteButtonHitTest(Point);
  if NewMuteButtonHovered <> FMuteButtonHovered then
  begin
    FMuteButtonHovered := NewMuteButtonHovered;
    Result := True;
  end;

  NewPlaybackRateButtonHovered := PlaybackRateButtonHitTest(Point);
  if NewPlaybackRateButtonHovered <> FPlaybackRateButtonHovered then
  begin
    FPlaybackRateButtonHovered := NewPlaybackRateButtonHovered;
    Result := True;
  end;

  if FDragging then
  begin
    NewPositionMs := PositionFromPoint(Point);
    if NewPositionMs <> FDragPositionMs then
    begin
      FDragPositionMs := NewPositionMs;
      Result := True;
    end;
  end;

  if FTimeViewPanning then
  begin
    PanTimeViewToPoint(Point);
    Result := True;
  end;

  if FVolumeDragging then
  begin
    NewVolume := VolumeFromPoint(Point);
    if NewVolume <> FVolumePercent then
    begin
      FVolumePercent := NewVolume;
      if Assigned(FOnVolumeChange) then
        FOnVolumeChange(Self, FVolumePercent);
      Result := True;
    end;
  end;
end;

function TVideoMinerOverlaySeekBar.MouseUp(const Point: TPoint): Boolean;
var
  AddChapterButtonClicked: Boolean;
  EndActionButtonClicked: Boolean;
  CheckButtonClicked: Boolean;
  DeleteChapterButtonClicked: Boolean;
  FullScreenButtonClicked: Boolean;
  MuteButtonClicked: Boolean;
  PlaybackRateButtonClicked: Boolean;
  SeekPositionMs: Integer;
begin
  Result := FDragging or FTimeViewPanning or FVolumeDragging or
    BoundsHitTest(Point);

  if FFullScreenButtonPressed then
  begin
    FullScreenButtonClicked := FullScreenButtonHitTest(Point);
    FFullScreenButtonPressed := False;
    FFullScreenButtonHovered := FullScreenButtonClicked;
    Result := True;
    if FullScreenButtonClicked and Assigned(FOnFullScreenClick) then
      FOnFullScreenClick(Self);
    Exit;
  end;

  if FMuteButtonPressed then
  begin
    MuteButtonClicked := MuteButtonHitTest(Point);
    FMuteButtonPressed := False;
    FMuteButtonHovered := MuteButtonClicked;
    Result := True;
    if MuteButtonClicked and Assigned(FOnMuteClick) then
      FOnMuteClick(Self);
    Exit;
  end;

  if FPlaybackRateButtonPressed then
  begin
    PlaybackRateButtonClicked := PlaybackRateButtonHitTest(Point);
    FPlaybackRateButtonPressed := False;
    FPlaybackRateButtonHovered := PlaybackRateButtonClicked;
    Result := True;
    if PlaybackRateButtonClicked and Assigned(FOnPlaybackRateClick) then
      FOnPlaybackRateClick(Self);
    Exit;
  end;

  if FEndActionButtonPressed then
  begin
    EndActionButtonClicked := EndActionButtonHitTest(Point);
    FEndActionButtonPressed := False;
    FEndActionButtonHovered := EndActionButtonClicked;
    Result := True;
    if EndActionButtonClicked and Assigned(FOnEndActionClick) then
      FOnEndActionClick(Self);
    Exit;
  end;

  if FCheckButtonPressed then
  begin
    CheckButtonClicked := CheckButtonHitTest(Point);
    FCheckButtonPressed := False;
    FCheckButtonHovered := CheckButtonClicked;
    Result := True;
    if CheckButtonClicked and Assigned(FOnCheckClick) then
      FOnCheckClick(Self);
    Exit;
  end;

  if FDeleteChapterButtonPressed then
  begin
    DeleteChapterButtonClicked := DeleteChapterButtonHitTest(Point);
    FDeleteChapterButtonPressed := False;
    FDeleteChapterButtonHovered := DeleteChapterButtonClicked;
    Result := True;
    if DeleteChapterButtonClicked and Assigned(FOnDeleteChapterClick) then
      FOnDeleteChapterClick(Self);
    Exit;
  end;

  if FAddChapterButtonPressed then
  begin
    AddChapterButtonClicked := AddChapterButtonHitTest(Point);
    FAddChapterButtonPressed := False;
    FAddChapterButtonHovered := AddChapterButtonClicked;
    Result := True;
    if AddChapterButtonClicked and Assigned(FOnAddChapterClick) then
      FOnAddChapterClick(Self);
    Exit;
  end;

  if FVolumeDragging then
  begin
    FVolumePercent := VolumeFromPoint(Point);
    FVolumeDragging := False;
    FVolumeHovered := VolumeHitTest(Point);
    FHovered := BoundsHitTest(Point);
    if Assigned(FOnVolumeChange) then
      FOnVolumeChange(Self, FVolumePercent);
    Exit;
  end;

  if FTimeViewPanning then
  begin
    PanTimeViewToPoint(Point);
    FTimeViewPanning := False;
    FHovered := BoundsHitTest(Point);
    Exit;
  end;

  if not FDragging then
    Exit;

  SeekPositionMs := PositionFromPoint(Point);
  FDragPositionMs := SeekPositionMs;
  FDragging := False;
  FPositionMs := SeekPositionMs;
  FHovered := BoundsHitTest(Point);
  if Assigned(FOnSeek) then
    FOnSeek(Self, SeekPositionMs);
end;

function TVideoMinerOverlaySeekBar.CurrentDisplayPositionMs: Integer;
begin
  Result := DisplayPositionMs;
end;

function TVideoMinerOverlaySeekBar.CurrentTrackRect: TRect;
begin
  Result := TrackRect;
  if not Result.IsEmpty then
    OffsetRect(Result, Bounds.Left, Bounds.Top);
end;

procedure TVideoMinerOverlaySeekBar.PaintControl(Canvas: TCanvas);
var
  AddChapterRect: TRect;
  ButtonRect: TRect;
  CheckRect: TRect;
  DeleteChapterRect: TRect;
  EndActionRect: TRect;
  FilledRect: TRect;
  KnobCenterX: Integer;
  KnobRadius: Integer;
  PositionRatio: Double;
  ShadowRadius: Integer;
  MuteRect: TRect;
  PlaybackRateRect: TRect;
  PositionVisible: Boolean;
  Text: string;
  TextSize: TSize;
  TextTop: Integer;
  Track: TRect;
  TrackCenterY: Integer;
  VolumeFilledRect: TRect;
  VolumeLabel: TRect;
  VolumeText: string;
  VolumeTrack: TRect;
begin
  if Bounds.IsEmpty then
    Exit;

  Track := TrackRect;
  if Track.IsEmpty then
    Exit;

  DrawAlphaPanel(Canvas, Rect(0, 0, Bounds.Width, Bounds.Height), 18, 96);
{$IFDEF DEBUG}
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := clLime;
  Canvas.MoveTo(Bounds.Left, Bounds.Top + ToolRowCenterY);
  Canvas.LineTo(Bounds.Right, Bounds.Top + ToolRowCenterY);
  Canvas.Pen.Style := psClear;
{$ENDIF}
  ButtonRect := FullScreenButtonRect;
  EndActionRect := EndActionButtonRect;
  CheckRect := CheckButtonRect;
  DeleteChapterRect := DeleteChapterButtonRect;
  AddChapterRect := AddChapterButtonRect;
  MuteRect := MuteButtonRect;
  PlaybackRateRect := PlaybackRateButtonRect;

  PositionVisible := TimeViewPositionVisible(DisplayPositionMs);
  PositionRatio := TimeViewPositionRatio(DisplayPositionMs);
  KnobCenterX := Track.Left + Round(Track.Width * PositionRatio);
  TrackCenterY := Track.Top + Track.Height div 2;

  if FCompactPlaybackStyle then
  begin
    DrawAlphaPanel(Canvas, Rect(0, 0, Bounds.Width, Bounds.Height), 18, 92);
    DrawAlphaRoundRect(Canvas, Rect(Track.Left - 1, Track.Top - 3,
      Track.Right + 1, Track.Bottom + 3), Track.Height + 3, 62, clBlack);
    DrawAlphaRoundRect(Canvas, Track, Track.Height, 82);

    if PositionVisible then
    begin
      FilledRect := Track;
      FilledRect.Right := Max(FilledRect.Left + Track.Height, KnobCenterX);
      DrawAlphaRoundRect(Canvas, FilledRect, Track.Height, 230, SEEK_ACCENT_COLOR);
      if FilledRect.Right > FilledRect.Left then
        DrawAlphaRoundRect(Canvas, Rect(FilledRect.Left, FilledRect.Top,
          FilledRect.Right, Min(FilledRect.Bottom, FilledRect.Top + 2)),
          1, 132, $00FFD68F);
    end;
    DrawChapterMarkers(Canvas, Track);
    DrawTimeRuler(Canvas, Track);

    if PositionVisible then
    begin
      ShadowRadius := 20;
      KnobRadius := 11;
      if FDragging then
      begin
        ShadowRadius := 24;
        KnobRadius := 13;
      end;
      DrawAlphaEllipse(Canvas, Rect(KnobCenterX - ShadowRadius,
        TrackCenterY - ShadowRadius, KnobCenterX + ShadowRadius,
        TrackCenterY + ShadowRadius), 46, SEEK_ACCENT_COLOR);
      DrawAlphaEllipse(Canvas, Rect(KnobCenterX - KnobRadius,
        TrackCenterY - KnobRadius, KnobCenterX + KnobRadius,
        TrackCenterY + KnobRadius), 245, SEEK_ACCENT_COLOR);
      DrawAlphaEllipse(Canvas, Rect(KnobCenterX - 6,
        TrackCenterY - 6, KnobCenterX + 6, TrackCenterY + 6),
        255, $00FFD18A);
    end;

    Text := Format('%s / %s', [FormatTimeMs(DisplayPositionMs),
      FormatTimeMs(FMaxMs)]);
    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Size := 10;
    Canvas.Font.Style := [];
    Canvas.Font.Color := clWhite;
    SetBkMode(Canvas.Handle, TRANSPARENT);
    TextSize := Canvas.TextExtent(Text);
    TextTop := ToolRowCenterY - TextSize.cy div 2;
    Canvas.TextOut(Bounds.Left + (Track.Left + Track.Right - TextSize.cx) div 2,
      Bounds.Top + TextTop, Text);

    VolumeTrack := VolumeTrackRect;
    VolumeLabel := VolumeLabelRect;
    VolumeText := Format('Vol %d%%', [FVolumePercent]);
    TextSize := Canvas.TextExtent(VolumeText);
    Canvas.TextOut(Bounds.Left + VolumeLabel.Left,
      Bounds.Top + VolumeLabel.Top + (VolumeLabel.Height - TextSize.cy) div 2,
      VolumeText);
    DrawAlphaRoundRect(Canvas, VolumeTrack, VolumeTrack.Height, 72);
    VolumeFilledRect := VolumeTrack;
    VolumeFilledRect.Right := VolumeTrack.Left +
      Round(VolumeTrack.Width * Max(0, Min(100, FVolumePercent)) / 100);
    if VolumeFilledRect.Right > VolumeFilledRect.Left then
      DrawAlphaRoundRect(Canvas, VolumeFilledRect, VolumeTrack.Height, 210);

    if FMuteButtonHovered or FMuteButtonPressed or FMuted then
      DrawAlphaRoundRect(Canvas, MuteRect, 8, 38);
    DrawMuteIcon(Canvas, MuteRect, MuteButtonAlpha);

    Text := FPlaybackRateText;
    if Text = '' then
      Text := '1.0x';
    DrawTextButton(Canvas, PlaybackRateRect, Text, Text <> '1.0x',
      FPlaybackRateButtonHovered, FPlaybackRateButtonPressed, $0024D9F0);

    if FFullScreenButtonHovered or FFullScreenButtonPressed then
      DrawAlphaRoundRect(Canvas, ButtonRect, 8, 38);
    DrawFullScreenIcon(Canvas, ButtonRect, FullScreenButtonAlpha);

    if FEndActionButtonHovered or FEndActionButtonPressed then
      DrawAlphaRoundRect(Canvas, EndActionRect, 8, 38);
    Text := FEndActionText;
    if Text = '' then
      Text := 'Stop';
    Canvas.Font.Size := 9;
    TextSize := Canvas.TextExtent(Text);
    Canvas.TextOut(Bounds.Left + EndActionRect.Left +
      (EndActionRect.Width - TextSize.cx) div 2,
      Bounds.Top + EndActionRect.Top + (EndActionRect.Height - TextSize.cy) div 2,
      Text);

    DrawTextButton(Canvas, CheckRect, 'Check', FCheckEnabled,
      FCheckButtonHovered, FCheckButtonPressed, $002424E8);
    DrawTextButton(Canvas, DeleteChapterRect, '-', False,
      FDeleteChapterButtonHovered, FDeleteChapterButtonPressed, clWhite);
    DrawTextButton(Canvas, AddChapterRect, '+', False,
      FAddChapterButtonHovered, FAddChapterButtonPressed, clWhite);
    Exit;
  end;

  DrawAlphaRoundRect(Canvas, Track, Track.Height, 85);

  if PositionVisible then
  begin
    FilledRect := Track;
    FilledRect.Right := Max(FilledRect.Left + Track.Height, KnobCenterX);
    DrawAlphaRoundRect(Canvas, FilledRect, Track.Height, 230, SEEK_ACCENT_COLOR);
  end;
  DrawChapterMarkers(Canvas, Track);
  DrawTimeRuler(Canvas, Track);

  if PositionVisible then
  begin
    ShadowRadius := 22;
    DrawAlphaEllipse(Canvas, Rect(KnobCenterX - ShadowRadius,
      TrackCenterY - ShadowRadius, KnobCenterX + ShadowRadius,
      TrackCenterY + ShadowRadius), 70, SEEK_ACCENT_COLOR);

    KnobRadius := 11;
    if FHovered or FDragging then
      KnobRadius := 12;
    DrawAlphaEllipse(Canvas, Rect(KnobCenterX - KnobRadius,
      TrackCenterY - KnobRadius, KnobCenterX + KnobRadius,
      TrackCenterY + KnobRadius), 245, SEEK_ACCENT_COLOR);
  end;

  if FCheckEnabled then
    Text := Format('Frame %d / %d',
      [DisplayPositionMs div Max(1, FFrameStepMs) + 1,
       Max(1, FMaxMs div Max(1, FFrameStepMs) + 1)])
  else
    Text := Format('%s / %s', [FormatTimeMs(DisplayPositionMs),
      FormatTimeMs(FMaxMs)]);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 10;
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  TextSize := Canvas.TextExtent(Text);
  TextTop := ToolRowCenterY - TextSize.cy div 2;
  Canvas.TextOut(Bounds.Left + (Track.Left + Track.Right - TextSize.cx) div 2,
    Bounds.Top + TextTop, Text);

  VolumeTrack := VolumeTrackRect;
  VolumeLabel := VolumeLabelRect;
  VolumeText := Format('Vol %d%%', [FVolumePercent]);
  TextSize := Canvas.TextExtent(VolumeText);
  Canvas.TextOut(Bounds.Left + VolumeLabel.Left,
    Bounds.Top + VolumeLabel.Top + (VolumeLabel.Height - TextSize.cy) div 2,
    VolumeText);
  DrawAlphaRoundRect(Canvas, VolumeTrack, VolumeTrack.Height, 72);
  VolumeFilledRect := VolumeTrack;
  VolumeFilledRect.Right := VolumeTrack.Left +
    Round(VolumeTrack.Width * Max(0, Min(100, FVolumePercent)) / 100);
  if VolumeFilledRect.Right > VolumeFilledRect.Left then
    DrawAlphaRoundRect(Canvas, VolumeFilledRect, VolumeTrack.Height, 210);

  if FMuteButtonHovered or FMuteButtonPressed or FMuted then
    DrawAlphaRoundRect(Canvas, MuteRect, 8, 38);
  DrawMuteIcon(Canvas, MuteRect, MuteButtonAlpha);

  Text := FPlaybackRateText;
  if Text = '' then
    Text := '1.0x';
  DrawTextButton(Canvas, PlaybackRateRect, Text, Text <> '1.0x',
    FPlaybackRateButtonHovered, FPlaybackRateButtonPressed, $0024D9F0);

  if FFullScreenButtonHovered or FFullScreenButtonPressed then
    DrawAlphaRoundRect(Canvas, ButtonRect, 8, 38);
  DrawFullScreenIcon(Canvas, ButtonRect, FullScreenButtonAlpha);

  if FEndActionButtonHovered or FEndActionButtonPressed then
    DrawAlphaRoundRect(Canvas, EndActionRect, 8, 38);
  Text := FEndActionText;
  if Text = '' then
    Text := 'Stop';
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  TextSize := Canvas.TextExtent(Text);
  Canvas.TextOut(Bounds.Left + EndActionRect.Left +
    (EndActionRect.Width - TextSize.cx) div 2,
    Bounds.Top + EndActionRect.Top + (EndActionRect.Height - TextSize.cy) div 2,
    Text);

  DrawTextButton(Canvas, CheckRect, 'Check', FCheckEnabled,
    FCheckButtonHovered, FCheckButtonPressed, $002424E8);
  DrawTextButton(Canvas, DeleteChapterRect, '-', False,
    FDeleteChapterButtonHovered, FDeleteChapterButtonPressed, clWhite);
  DrawTextButton(Canvas, AddChapterRect, '+', False,
    FAddChapterButtonHovered, FAddChapterButtonPressed, clWhite);
end;

function TVideoMinerOverlaySeekBar.PositionFromPoint(const Point: TPoint): Integer;
var
  LocalX: Integer;
  Track: TRect;
begin
  Result := 0;
  Track := TrackRect;
  if (FMaxMs <= 0) or Track.IsEmpty then
    Exit;

  LocalX := Point.X - Bounds.Left;
  if LocalX < Track.Left then
    LocalX := Track.Left
  else if LocalX > Track.Right then
    LocalX := Track.Right;

  Result := FTimeViewStartMs + Round((LocalX - Track.Left) /
    Max(1, Track.Width) * TimeViewSpanMs);
  Result := Max(0, Min(FMaxMs, Result));
end;

function TVideoMinerOverlaySeekBar.HoverPositionFromPoint(const Point: TPoint;
  out PositionMs: Integer): Boolean;
var
  HitRect: TRect;
  Track: TRect;
begin
  PositionMs := 0;
  Result := False;
  if (FMaxMs <= 0) or Bounds.IsEmpty then
    Exit;

  Track := TrackRect;
  if Track.IsEmpty then
    Exit;

  HitRect := Rect(Bounds.Left + Track.Left, Bounds.Top + Track.Top,
    Bounds.Left + Track.Right, Bounds.Top + Track.Bottom);
  InflateRect(HitRect, 0, 34);
  if not Bounds.IsEmpty then
  begin
    HitRect.Left := Max(HitRect.Left, Bounds.Left);
    HitRect.Right := Min(HitRect.Right, Bounds.Right);
    HitRect.Top := Max(HitRect.Top, Bounds.Top);
    HitRect.Bottom := Min(HitRect.Bottom, Bounds.Bottom);
  end;
  if not PtInRect(HitRect, Point) then
    Exit;

  PositionMs := PositionFromPoint(Point);
  Result := True;
end;

function TVideoMinerOverlaySeekBar.WheelPosition(WheelDelta,
  StepMs: Integer): Integer;
var
  Steps: Integer;
begin
  if (FMaxMs <= 0) or (StepMs <= 0) then
  begin
    Result := DisplayPositionMs;
    Exit;
  end;

  Steps := WheelDelta div WHEEL_DELTA;
  if Steps = 0 then
  begin
    if WheelDelta > 0 then
      Steps := 1
    else
      Steps := -1;
  end;

  Result := Max(0, Min(FMaxMs, DisplayPositionMs + Steps * StepMs));
end;

procedure TVideoMinerOverlaySeekBar.SetProgress(PositionMs, MaxMs: Integer);
var
  OldMaxMs: Integer;
begin
  OldMaxMs := FMaxMs;
  FMaxMs := Max(0, MaxMs);
  if FMaxMs <> OldMaxMs then
    ResetTimeView;
  FPositionMs := Max(0, Min(FMaxMs, PositionMs));
  if FMaxMs <= 0 then
    ResetTimeView;
  if not FDragging then
    FDragPositionMs := FPositionMs;
end;

procedure TVideoMinerOverlaySeekBar.ResetTimeView;
begin
  FTimeViewStartMs := 0;
  FTimeViewSpanMs := 0;
  FTimeViewPanning := False;
  FTimeViewPanStartMs := 0;
  FTimeViewPanStartX := 0;
end;

procedure TVideoMinerOverlaySeekBar.PanTimeViewToPoint(const Point: TPoint);
var
  DeltaMs: Integer;
  DeltaX: Integer;
  Track: TRect;
begin
  if (not FTimeViewPanning) or (not TimeViewActive) then
    Exit;

  Track := TrackRect;
  if Track.IsEmpty then
    Exit;

  DeltaX := Point.X - FTimeViewPanStartX;
  DeltaMs := Round(DeltaX / Max(1, Track.Width) * FTimeViewSpanMs);
  FTimeViewStartMs := FTimeViewPanStartMs - DeltaMs;
  FTimeViewStartMs := Max(0, Min(FMaxMs - FTimeViewSpanMs, FTimeViewStartMs));
end;

function TVideoMinerOverlaySeekBar.ZoomTimeViewAtPoint(const Point: TPoint;
  WheelDelta: Integer): Boolean;
var
  AnchorMs: Integer;
  AnchorRatio: Double;
  LocalX: Integer;
  MinSpanMs: Integer;
  NewSpanMs: Integer;
  OldSpanMs: Integer;
  Track: TRect;
begin
  Result := False;
  if FMaxMs <= 0 then
    Exit;

  Track := TrackRect;
  if Track.IsEmpty then
    Exit;

  OldSpanMs := TimeViewSpanMs;
  if OldSpanMs <= 0 then
    OldSpanMs := FMaxMs;

  if WheelDelta > 0 then
    NewSpanMs := Round(OldSpanMs / SEEK_TIME_VIEW_ZOOM_STEP)
  else
    NewSpanMs := Round(OldSpanMs * SEEK_TIME_VIEW_ZOOM_STEP);

  MinSpanMs := Max(SEEK_TIME_VIEW_MIN_SPAN_MS, FFrameStepMs * 12);
  MinSpanMs := Min(FMaxMs, MinSpanMs);
  NewSpanMs := Max(MinSpanMs, Min(FMaxMs, NewSpanMs));
  if NewSpanMs >= FMaxMs - 1 then
  begin
    Result := TimeViewActive;
    ResetTimeView;
    Exit;
  end;

  LocalX := Max(Track.Left, Min(Track.Right, Point.X - Bounds.Left));
  AnchorRatio := (LocalX - Track.Left) / Max(1, Track.Width);
  AnchorMs := PositionFromPoint(Point);
  FTimeViewSpanMs := NewSpanMs;
  FTimeViewStartMs := AnchorMs - Round(NewSpanMs * AnchorRatio);
  FTimeViewStartMs := Max(0, Min(FMaxMs - FTimeViewSpanMs, FTimeViewStartMs));
  Result := True;
end;

procedure TVideoMinerOverlaySeekBar.SetFullScreen(Value: Boolean);
begin
  FFullScreen := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetFrameStepMs(Value: Integer);
begin
  FFrameStepMs := Max(1, Value);
end;

procedure TVideoMinerOverlaySeekBar.SetMuted(Value: Boolean);
begin
  FMuted := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetPlaybackRateText(const Value: string);
begin
  FPlaybackRateText := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetEndActionText(const Value: string);
begin
  FEndActionText := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetCheckEnabled(Value: Boolean);
begin
  FCheckEnabled := Value;
end;

procedure TVideoMinerOverlaySeekBar.SetChapters(
  const Value: TVideoMinerOverlayChapters);
begin
  FChapters := Copy(Value);
end;

procedure TVideoMinerOverlaySeekBar.SetVolumePercent(Value: Integer);
begin
  FVolumePercent := Max(0, Min(100, Value));
end;

function TVideoMinerOverlaySeekBar.TrackRect: TRect;
var
  PadX: Integer;
  TrackHeight: Integer;
  TrackY: Integer;
begin
  Result := TRect.Empty;
  if Bounds.IsEmpty then
    Exit;

  PadX := 22;
  TrackHeight := 7;
  if FHovered or FDragging then
    TrackHeight := 8;
  TrackY := 12;
  Result := Rect(PadX, TrackY, Bounds.Width - PadX, TrackY + TrackHeight);
end;

end.
