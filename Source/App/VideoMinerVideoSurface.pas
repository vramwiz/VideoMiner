unit VideoMinerVideoSurface;

// 動画フレームを直接描画し、その上に VideoMiner 専用 overlay 操作を重ねる表示面。
// ズーム/パン、マウス入力、ボスが来たモード、シークバーや中央ボタンの描画を担当する。

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Types, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.Graphics, VideoMinerBossGesture, VideoMinerFrameCheck,
  VideoMinerOverlay;

type
  TVideoMinerVideoSurface = class(TCustomControl)
  private
    FBitmap                 : TBitmap;                           // 現在表示する 32bit 動画フレーム
    FAlphaCompositeBitmap   : TBitmap;                           // alpha 確認用に市松模様へ合成した表示フレーム
    FAlphaCompositeDirty    : Boolean;                           // alpha 合成 Bitmap を作り直す必要があるか
    FAlphaMax               : Byte;                              // 現在フレームの最大 alpha 値
    FAlphaMin               : Byte;                              // 現在フレームの最小 alpha 値
    FAlphaPixelCount        : Int64;                             // 現在フレームで alpha が 255 未満のピクセル数
    FBossExitButtonRect     : TRect;                             // 偽装画面の解除ボタン位置
    FBossGestureDetector    : TVideoMinerBossGestureDetector;    // ボスが来たモード発動用のマウスジェスチャー検出器
    FBossMode               : Boolean;                           // 動画を隠して偽装画面を表示中か
    FPaintBuffer            : TBitmap;                           // overlay 表示時のちらつきを抑える描画用バッファ
    FFirstFrameButton       : TVideoMinerOverlayEdgeButton;      // 先頭フレームへ移動する中央ボタン
    FLastFrameButton        : TVideoMinerOverlayEdgeButton;      // 末尾フレームへ移動する中央ボタン
    FNextFileButton         : TVideoMinerOverlayFileNavButton;   // 次動画へ移動する右端ボタン
    FPanMoved               : Boolean;                           // 押下後にパン移動が発生したか
    FPanning                : Boolean;                           // ズーム中のドラッグ移動を処理中か
    FPanStartCenterX        : Double;                            // パン開始時の画像中心 X
    FPanStartCenterY        : Double;                            // パン開始時の画像中心 Y
    FPanStartPoint          : TPoint;                            // パン開始時のクライアント座標
    FPendingSurfaceClick    : Boolean;                           // ダブルクリック判定待ちの単クリックがあるか
    FSurfaceClickArmed      : Boolean;                           // 現在の押下が単クリック候補か
    FSurfaceClickTimer      : TTimer;                            // ダブルクリック猶予後に再生切替を発火するタイマー
    FOnBossExitClick        : TNotifyEvent;                      // 偽装画面の解除ボタンが押された通知先
    FOnBossGesture          : TNotifyEvent;                      // ボスが来たジェスチャー成立の通知先
    FOnAddChapterClick      : TNotifyEvent;                      // チャプター追加ボタンの通知先
    FOnCheckClick           : TNotifyEvent;                      // Check ボタンの通知先
    FOnDeleteChapterClick   : TNotifyEvent;                      // チャプター削除ボタンの通知先
    FOnEndActionClick       : TNotifyEvent;                      // 終端到達時動作ボタンの通知先
    FOnFirstFrameClick      : TNotifyEvent;                      // 先頭フレームボタンの通知先
    FOnFullScreenClick      : TNotifyEvent;                      // 全画面ボタンまたはダブルクリックの通知先
    FOnLastFrameClick       : TNotifyEvent;                      // 末尾フレームボタンの通知先
    FOnMuteClick            : TNotifyEvent;                      // ミュートボタンの通知先
    FOnNavigateNextClick    : TNotifyEvent;                      // 次動画ボタンの通知先
    FOnNavigatePreviousClick: TNotifyEvent;                      // 前動画ボタンの通知先
    FOnPlaybackRateClick    : TNotifyEvent;                      // 再生速度ボタンの通知先
    FOnPlayPauseClick       : TNotifyEvent;                      // 再生/一時停止ボタンまたは単クリックの通知先
    FOnSeek                 : TVideoMinerOverlaySeekEvent;       // シークバー操作の通知先
    FOnSeekByWheel          : TVideoMinerOverlaySeekEvent;       // シークバー上ホイール操作の通知先
    FOnSkipBackwardClick    : TNotifyEvent;                      // 10 秒戻しボタンの通知先
    FOnSkipForwardClick     : TNotifyEvent;                      // 10 秒進みボタンの通知先
    FOnVolumeChange         : TVideoMinerOverlayVolumeEvent;     // 音量変更の通知先
    FOverlayVisible         : Boolean;                           // 中央 overlay ボタン群を表示中か
    FPlayPauseButton        : TVideoMinerOverlayPlayPauseButton; // 再生/一時停止の中央ボタン
    FPreviousFileButton     : TVideoMinerOverlayFileNavButton;   // 前動画へ移動する左端ボタン
    FPreviewRect            : TRect;                             // 動画フレームが実際に描画される領域
    FSeekBar                : TVideoMinerOverlaySeekBar;         // 下側のシーク/音量/状態操作バー
    FSeekBarVisible         : Boolean;                           // 下側シークバーを表示中か
    FSeekWheelFrameStepMs   : Integer;                           // Check 中ホイールシークの 1 ステップ幅 ms
    FSkipBackwardButton     : TVideoMinerOverlaySkipButton;      // 10 秒戻しの中央ボタン
    FSkipForwardButton      : TVideoMinerOverlaySkipButton;      // 10 秒進みの中央ボタン
    FSourceHasAlpha         : Boolean;                           // 現在の動画が alpha を持つ形式か
    FZoomCenterX            : Double;                            // ズーム表示の画像中心 X
    FZoomCenterY            : Double;                            // ズーム表示の画像中心 Y
    FZoomScale              : Double;                            // 現在のズーム倍率
    // 保留中の単クリック再生切替を取り消す
    procedure CancelPendingSurfaceClick;
    // ズーム倍率と中心位置を画像範囲内へ収める
    procedure ClampZoomCenter;
    // 指定位置からパン操作を開始できるか返す
    function CanStartPan(const Point: TPoint): Boolean;
    // 指定位置から動画面の単クリック操作を開始できるか返す
    function CanStartSurfaceClick(const Point: TPoint): Boolean;
    // 次動画ボタンに当たっているか返す
    function HitNextFileButton(const Point: TPoint): Boolean;
    // 前動画ボタンに当たっているか返す
    function HitPreviousFileButton(const Point: TPoint): Boolean;
    // 現在のズーム状態に従って動画フレームを描画する
    procedure DrawFrame(Canvas: TCanvas; const DestRect: TRect);
    // alpha 確認用の市松模様合成 Bitmap を最新化する
    procedure EnsureAlphaCompositeBitmap;
{$IFDEF DEBUG}
    // alpha 確認状態を動画面左上へ描く
    procedure DrawAlphaStatus(Canvas: TCanvas; const DestRect: TRect);
{$ENDIF}
    // クライアント領域内に動画全体が収まる描画矩形を返す
    function FitRect: TRect;
    // 中央 overlay ボタン群に当たっているか返す
    function HitAnyOverlayButton(const Point: TPoint): Boolean;
    // 下側シークバーに当たっているか返す
    function HitSeekBar(const Point: TPoint): Boolean;
    // クライアント座標を現在のズーム状態の画像座標へ変換する
    function ImagePointFromClient(const Point: TPoint; out ImageX, ImageY: Double): Boolean;
    // overlay 部品をまとめて再描画対象にする
    procedure InvalidateAllOverlayControls;
    // 指定 overlay 部品の周辺だけを再描画対象にする
    procedure InvalidateOverlayControl(Control: TVideoMinerOverlayControl);
    // 等倍全体表示へ戻す
    procedure ResetZoom;
    // ボスが来たモード中の描画/入力状態へ切り替える
    procedure SetBossMode(Value: Boolean);
    // 次動画へ移動できるかを overlay へ渡す
    procedure SetCanNavigateNext(Value: Boolean);
    // 前動画へ移動できるかを overlay へ渡す
    procedure SetCanNavigatePrevious(Value: Boolean);
    // Check 操作の有効状態を overlay へ渡す
    procedure SetCheckEnabled(Value: Boolean);
    // 表示用チャプター位置を overlay へ渡す
    procedure SetChapters(const Value: TVideoMinerOverlayChapters);
    // 終端到達時動作の表示文字列を overlay へ渡す
    procedure SetEndActionText(const Value: string);
    // 下側シークバーの表示状態を切り替える
    procedure SetSeekBarVisible(Value: Boolean);
    // Check 中ホイールシークの 1 ステップ幅を設定する
    procedure SetSeekWheelFrameStepMs(Value: Integer);
    // 全画面状態を overlay へ渡す
    procedure SetFullScreen(Value: Boolean);
    // 中央 overlay ボタン群の表示状態を切り替える
    procedure SetOverlayVisible(Value: Boolean);
    // 先頭フレームボタンの通知先を設定する
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    // 偽装画面解除ボタンの通知先を設定する
    procedure SetOnBossExitClick(Value: TNotifyEvent);
    // ボスが来たジェスチャー成立の通知先を設定する
    procedure SetOnBossGesture(Value: TNotifyEvent);
    // チャプター追加ボタンの通知先を設定する
    procedure SetOnAddChapterClick(Value: TNotifyEvent);
    // Check ボタンの通知先を設定する
    procedure SetOnCheckClick(Value: TNotifyEvent);
    // チャプター削除ボタンの通知先を設定する
    procedure SetOnDeleteChapterClick(Value: TNotifyEvent);
    // 終端到達時動作ボタンの通知先を設定する
    procedure SetOnEndActionClick(Value: TNotifyEvent);
    // 全画面ボタンの通知先を設定する
    procedure SetOnFullScreenClick(Value: TNotifyEvent);
    // 末尾フレームボタンの通知先を設定する
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    // ミュート状態を overlay へ渡す
    procedure SetMuted(Value: Boolean);
    // ミュートボタンの通知先を設定する
    procedure SetOnMuteClick(Value: TNotifyEvent);
    // 次動画ボタンの通知先を設定する
    procedure SetOnNavigateNextClick(Value: TNotifyEvent);
    // 前動画ボタンの通知先を設定する
    procedure SetOnNavigatePreviousClick(Value: TNotifyEvent);
    // 再生速度ボタンの通知先を設定する
    procedure SetOnPlaybackRateClick(Value: TNotifyEvent);
    // 再生/一時停止ボタンと単クリックの通知先を設定する
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
    // シークバー操作の通知先を設定する
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    // シークバー上ホイール操作の通知先を設定する
    procedure SetOnSeekByWheel(Value: TVideoMinerOverlaySeekEvent);
    // 10 秒戻しボタンの通知先を設定する
    procedure SetOnSkipBackwardClick(Value: TNotifyEvent);
    // 10 秒進みボタンの通知先を設定する
    procedure SetOnSkipForwardClick(Value: TNotifyEvent);
    // 音量変更の通知先を設定する
    procedure SetOnVolumeChange(Value: TVideoMinerOverlayVolumeEvent);
    // 再生中かどうかを overlay へ渡す
    procedure SetPlaybackActive(Value: Boolean);
    // 再生速度表示文字列を overlay へ渡す
    procedure SetPlaybackRateText(const Value: string);
    // 現在の動画が alpha を持つかを表示面へ渡す
    procedure SetSourceHasAlpha(Value: Boolean);
    // 音量パーセントを overlay へ渡す
    procedure SetVolumePercent(Value: Integer);
    // 単クリックが確定した時点で再生/一時停止を発火する
    procedure SurfaceClickTimer(Sender: TObject);
    // 背景消去を抑止して動画面のちらつきを避ける
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    // ダブルクリックを全画面切り替えとして扱う
    procedure DblClick; override;
    // overlay、パン、シークバー、単クリック候補の押下状態を開始する
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // パン移動、ジェスチャー検出、overlay hover を更新する
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    // 押下中の overlay、パン、シークバー、単クリック候補を確定する
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // マウスホイールをズームまたはシークバー上シークとして処理する
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    // 動画、overlay、ボスが来た画面を現在状態に応じて描画する
    procedure Paint; override;
  public
    // 動画表示用 Bitmap、overlay 部品、入力タイマーを生成する
    constructor Create(AOwner: TComponent); override;
    // 生成した overlay 部品と描画バッファを解放する
    destructor Destroy; override;
    // 表示フレームと overlay 状態を空にする
    procedure Clear;
    // 外部から渡されたホイール操作をこの表示面で処理する
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
    // 現在表示中フレームの四隅が暗いか返す
    function CurrentFrameCornersMostlyDark: Boolean;
    // 現在表示中フレームの簡易署名を返す
    function CurrentFrameSignature(out Signature: TVideoMinerFrameSignature): Boolean;
    // FBitmap を BGRX32 の direct デコード先として使える状態にする
    function PrepareBgrx32Frame(Width, Height: Integer; out Buffer: Pointer;
      out BufferStride: Integer): Boolean;
    // 通常の再描画タイミングで現在フレームを表示する
    procedure Present;
    // すぐに現在フレームを表示する
    procedure PresentImmediate;
    // 下側シークバーの現在位置を更新する
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    property BossMode: Boolean read FBossMode write SetBossMode;
    property Bitmap: TBitmap read FBitmap;
    property CanNavigateNext: Boolean write SetCanNavigateNext;
    property CanNavigatePrevious: Boolean write SetCanNavigatePrevious;
    property CheckEnabled: Boolean write SetCheckEnabled;
    property Chapters: TVideoMinerOverlayChapters write SetChapters;
    property EndActionText: string write SetEndActionText;
    property FullScreen: Boolean write SetFullScreen;
    property SeekWheelFrameStepMs: Integer write SetSeekWheelFrameStepMs;
    property OnBossExitClick: TNotifyEvent read FOnBossExitClick write SetOnBossExitClick;
    property OnBossGesture: TNotifyEvent read FOnBossGesture write SetOnBossGesture;
    property OnAddChapterClick: TNotifyEvent read FOnAddChapterClick write SetOnAddChapterClick;
    property OnCheckClick: TNotifyEvent read FOnCheckClick write SetOnCheckClick;
    property OnDeleteChapterClick: TNotifyEvent read FOnDeleteChapterClick write SetOnDeleteChapterClick;
    property OnEndActionClick: TNotifyEvent read FOnEndActionClick write SetOnEndActionClick;
    property OnFirstFrameClick: TNotifyEvent read FOnFirstFrameClick write SetOnFirstFrameClick;
    property OnFullScreenClick: TNotifyEvent read FOnFullScreenClick write SetOnFullScreenClick;
    property OnLastFrameClick: TNotifyEvent read FOnLastFrameClick write SetOnLastFrameClick;
    property OnMuteClick: TNotifyEvent read FOnMuteClick write SetOnMuteClick;
    property OnNavigateNextClick: TNotifyEvent read FOnNavigateNextClick write SetOnNavigateNextClick;
    property OnNavigatePreviousClick: TNotifyEvent read FOnNavigatePreviousClick
      write SetOnNavigatePreviousClick;
    property OnPlaybackRateClick: TNotifyEvent read FOnPlaybackRateClick write SetOnPlaybackRateClick;
    property OnPlayPauseClick: TNotifyEvent read FOnPlayPauseClick write SetOnPlayPauseClick;
    property OnSeek: TVideoMinerOverlaySeekEvent read FOnSeek write SetOnSeek;
    property OnSeekByWheel: TVideoMinerOverlaySeekEvent read FOnSeekByWheel write SetOnSeekByWheel;
    property OnSkipBackwardClick: TNotifyEvent read FOnSkipBackwardClick write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent read FOnSkipForwardClick write SetOnSkipForwardClick;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent read FOnVolumeChange write SetOnVolumeChange;
    property PlaybackActive: Boolean write SetPlaybackActive;
    property PlaybackRateText: string write SetPlaybackRateText;
    property SourceHasAlpha: Boolean read FSourceHasAlpha write SetSourceHasAlpha;
    property Muted: Boolean write SetMuted;
    property VolumePercent: Integer write SetVolumePercent;
  end;

implementation

uses
  System.Diagnostics, System.Math, System.SysUtils, VideoMinerBossOverlay,
  VideoMinerDebugLog;

const
  MAX_ZOOM              = 8.0;  // ホイールズームで許可する最大倍率
  MIN_ZOOM              = 1.0;  // 全体表示として扱う最小倍率
  DEFAULT_FRAME_STEP_MS = 33;   // FPS 不明時の 1 フレーム相当ステップ ms
  SEEK_WHEEL_STEP_MS    = 1000; // 通常時のホイールシーク幅 ms
  WHEEL_ZOOM_STEP       = 1.20; // ホイール 1 ノッチあたりのズーム倍率
  ALPHA_CHECK_SIZE      = 16;   // alpha 確認表示の市松模様 1 マス px

constructor TVideoMinerVideoSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := False;

  FBitmap := TBitmap.Create;
  FAlphaCompositeBitmap := TBitmap.Create;
  FAlphaCompositeBitmap.PixelFormat := pf32bit;
  FAlphaCompositeDirty := True;
  FAlphaMin := 255;
  FBossGestureDetector := TVideoMinerBossGestureDetector.Create;
  FPaintBuffer := TBitmap.Create;
  FPaintBuffer.PixelFormat := pf32bit;
  FOverlayVisible := False;
  FSeekBarVisible := False;
  FSeekWheelFrameStepMs := DEFAULT_FRAME_STEP_MS;
  ResetZoom;
  FPreviousFileButton := TVideoMinerOverlayFileNavButton.Create(fndPrevious);
  FFirstFrameButton := TVideoMinerOverlayEdgeButton.Create(edFirst);
  FSkipBackwardButton := TVideoMinerOverlaySkipButton.Create(sdBackward);
  FPlayPauseButton := TVideoMinerOverlayPlayPauseButton.Create;
  FSkipForwardButton := TVideoMinerOverlaySkipButton.Create(sdForward);
  FLastFrameButton := TVideoMinerOverlayEdgeButton.Create(edLast);
  FNextFileButton := TVideoMinerOverlayFileNavButton.Create(fndNext);
  FSeekBar := TVideoMinerOverlaySeekBar.Create;
  FSeekBar.FrameStepMs := FSeekWheelFrameStepMs;
  FSeekBar.PlaybackRateText := '1.0x';
  FSurfaceClickTimer := TTimer.Create(Self);
  FSurfaceClickTimer.Enabled := False;
  FSurfaceClickTimer.Interval := GetDoubleClickTime + 20;
  FSurfaceClickTimer.OnTimer := SurfaceClickTimer;
  FPreviousFileButton.Visible := False;
  FFirstFrameButton.Visible := False;
  FSkipBackwardButton.Visible := False;
  FPlayPauseButton.Visible := False;
  FSkipForwardButton.Visible := False;
  FLastFrameButton.Visible := False;
  FNextFileButton.Visible := False;
  FSeekBar.Visible := False;
end;

destructor TVideoMinerVideoSurface.Destroy;
begin
  CancelPendingSurfaceClick;
  FSurfaceClickTimer.Free;
  FBossGestureDetector.Free;
  FSeekBar.Free;
  FNextFileButton.Free;
  FLastFrameButton.Free;
  FSkipForwardButton.Free;
  FPlayPauseButton.Free;
  FSkipBackwardButton.Free;
  FFirstFrameButton.Free;
  FPreviousFileButton.Free;
  FPaintBuffer.Free;
  FAlphaCompositeBitmap.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoSurface.DblClick;
begin
  inherited DblClick;
  if FBossMode then
    Exit;

  CancelPendingSurfaceClick;
  if Assigned(FOnFullScreenClick) then
    FOnFullScreenClick(Self);
end;

procedure TVideoMinerVideoSurface.CancelPendingSurfaceClick;
begin
  FPendingSurfaceClick := False;
  FSurfaceClickArmed := False;
  if FSurfaceClickTimer <> nil then
    FSurfaceClickTimer.Enabled := False;
end;

procedure TVideoMinerVideoSurface.Clear;
begin
  CancelPendingSurfaceClick;
  FBitmap.SetSize(0, 0);
  FAlphaCompositeBitmap.SetSize(0, 0);
  FAlphaCompositeDirty := True;
  FAlphaMin := 255;
  FAlphaMax := 0;
  FAlphaPixelCount := 0;
  FPanning := False;
  FPanMoved := False;
  FOverlayVisible := False;
  ResetZoom;
  if FPreviousFileButton <> nil then
    FPreviousFileButton.Visible := False;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.Visible := False;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.Visible := False;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.Visible := False;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.Visible := False;
  if FLastFrameButton <> nil then
    FLastFrameButton.Visible := False;
  if FNextFileButton <> nil then
    FNextFileButton.Visible := False;
  if FSeekBar <> nil then
    FSeekBar.SetProgress(0, 0);
  SetSeekBarVisible(False);
  Invalidate;
  Update;
end;

function TVideoMinerVideoSurface.PrepareBgrx32Frame(Width, Height: Integer;
  out Buffer: Pointer; out BufferStride: Integer): Boolean;
begin
  Buffer := nil;
  BufferStride := 0;
  Result := False;

  if (Width <= 0) or (Height <= 0) then
    Exit;

  if FBitmap.PixelFormat <> pf32bit then
    FBitmap.PixelFormat := pf32bit;
  if (FBitmap.Width <> Width) or (FBitmap.Height <> Height) then
    FBitmap.SetSize(Width, Height);

  if Height > 1 then
    BufferStride := Abs(NativeInt(FBitmap.ScanLine[1]) - NativeInt(FBitmap.ScanLine[0]))
  else
    BufferStride := Width * 4;

  Buffer := FBitmap.ScanLine[Height - 1];
  FAlphaCompositeDirty := True;
  Result := (Buffer <> nil) and (BufferStride > 0);
end;

function TVideoMinerVideoSurface.CurrentFrameCornersMostlyDark: Boolean;
begin
  Result := FrameCornersMostlyDark(FBitmap);
end;

function TVideoMinerVideoSurface.CurrentFrameSignature(
  out Signature: TVideoMinerFrameSignature): Boolean;
begin
  Result := BuildFrameSignature(FBitmap, Signature);
end;

procedure TVideoMinerVideoSurface.ResetZoom;
begin
  FZoomScale := MIN_ZOOM;
  if (FBitmap <> nil) and (FBitmap.Width > 0) and (FBitmap.Height > 0) then
  begin
    FZoomCenterX := FBitmap.Width / 2;
    FZoomCenterY := FBitmap.Height / 2;
  end
  else
  begin
    FZoomCenterX := 0;
    FZoomCenterY := 0;
  end;
end;

procedure TVideoMinerVideoSurface.ClampZoomCenter;
var
  HalfHeight: Double;
  HalfWidth: Double;
begin
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
  begin
    ResetZoom;
    Exit;
  end;

  FZoomScale := Max(MIN_ZOOM,
    Min(MAX_ZOOM, FZoomScale));
  if FZoomScale <= MIN_ZOOM then
  begin
    ResetZoom;
    Exit;
  end;

  HalfWidth := FBitmap.Width / FZoomScale / 2;
  HalfHeight := FBitmap.Height / FZoomScale / 2;
  FZoomCenterX := Max(HalfWidth, Min(FBitmap.Width - HalfWidth, FZoomCenterX));
  FZoomCenterY := Max(HalfHeight, Min(FBitmap.Height - HalfHeight, FZoomCenterY));
end;

function TVideoMinerVideoSurface.FitRect: TRect;
var
  Scale: Double;
  DrawWidth: Integer;
  DrawHeight: Integer;
begin
  Result := ClientRect;

  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) or
     (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;

  Scale := Min(ClientWidth / FBitmap.Width, ClientHeight / FBitmap.Height);
  DrawWidth := Max(1, Round(FBitmap.Width * Scale));
  DrawHeight := Max(1, Round(FBitmap.Height * Scale));

  Result.Left := (ClientWidth - DrawWidth) div 2;
  Result.Top := (ClientHeight - DrawHeight) div 2;
  Result.Right := Result.Left + DrawWidth;
  Result.Bottom := Result.Top + DrawHeight;
end;

procedure TVideoMinerVideoSurface.EnsureAlphaCompositeBitmap;
var
  Alpha       : Integer; // 元フレームの alpha 値
  CheckerBlue : Integer; // 市松模様の B 成分
  CheckerGreen: Integer; // 市松模様の G 成分
  CheckerRed  : Integer; // 市松模様の R 成分
  Dst         : PByte;   // 合成先 pixel
  Src         : PByte;   // 元フレーム pixel
  SrcBlue     : Integer; // 元フレームの B 成分
  SrcGreen    : Integer; // 元フレームの G 成分
  SrcRed      : Integer; // 元フレームの R 成分
  X           : Integer; // 処理中の X 座標
  Y           : Integer; // 処理中の Y 座標
begin
  if (not FSourceHasAlpha) or (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  if (not FAlphaCompositeDirty) and
     (FAlphaCompositeBitmap.Width = FBitmap.Width) and
     (FAlphaCompositeBitmap.Height = FBitmap.Height) then
    Exit;

  if FAlphaCompositeBitmap.PixelFormat <> pf32bit then
    FAlphaCompositeBitmap.PixelFormat := pf32bit;
  if (FAlphaCompositeBitmap.Width <> FBitmap.Width) or
     (FAlphaCompositeBitmap.Height <> FBitmap.Height) then
    FAlphaCompositeBitmap.SetSize(FBitmap.Width, FBitmap.Height);

  FAlphaMin := 255;
  FAlphaMax := 0;
  FAlphaPixelCount := 0;
  for Y := 0 to FBitmap.Height - 1 do
  begin
    Src := FBitmap.ScanLine[FBitmap.Height - 1 - Y];
    Dst := FAlphaCompositeBitmap.ScanLine[FAlphaCompositeBitmap.Height - 1 - Y];
    for X := 0 to FBitmap.Width - 1 do
    begin
      SrcBlue := Src^;
      Inc(Src);
      SrcGreen := Src^;
      Inc(Src);
      SrcRed := Src^;
      Inc(Src);
      Alpha := Src^;
      Inc(Src);

      if Alpha < FAlphaMin then
        FAlphaMin := Alpha;
      if Alpha > FAlphaMax then
        FAlphaMax := Alpha;
      if Alpha < 255 then
        Inc(FAlphaPixelCount);

      if (((X div ALPHA_CHECK_SIZE) + (Y div ALPHA_CHECK_SIZE)) and 1) = 0 then
      begin
        CheckerRed := 216;
        CheckerGreen := 216;
        CheckerBlue := 216;
      end
      else
      begin
        CheckerRed := 128;
        CheckerGreen := 128;
        CheckerBlue := 128;
      end;

      Dst^ := Byte((SrcBlue * Alpha + CheckerBlue * (255 - Alpha) + 127) div 255);
      Inc(Dst);
      Dst^ := Byte((SrcGreen * Alpha + CheckerGreen * (255 - Alpha) + 127) div 255);
      Inc(Dst);
      Dst^ := Byte((SrcRed * Alpha + CheckerRed * (255 - Alpha) + 127) div 255);
      Inc(Dst);
      Dst^ := 255;
      Inc(Dst);
    end;
  end;
  FAlphaCompositeDirty := False;
end;

{$IFDEF DEBUG}
procedure TVideoMinerVideoSurface.DrawAlphaStatus(Canvas: TCanvas;
  const DestRect: TRect);
var
  Percent : Double; // alpha が 255 未満の pixel 割合
  Text    : string; // 表示する診断文字列
  TextRect: TRect;  // 背景付きで描く文字領域
  TextSize: TSize;  // 診断文字列の表示サイズ
begin
  if (not FSourceHasAlpha) or DestRect.IsEmpty then
    Exit;

  EnsureAlphaCompositeBitmap;
  Percent := 0;
  if (FBitmap.Width > 0) and (FBitmap.Height > 0) then
    Percent := FAlphaPixelCount * 100.0 / (Int64(FBitmap.Width) * FBitmap.Height);
  Text := Format('Alpha preview  A %d-%d  transparent %.1f%%',
    [FAlphaMin, FAlphaMax, Percent]);

  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  TextSize := Canvas.TextExtent(Text);
  TextRect := Rect(DestRect.Left + 10, DestRect.Top + 10,
    DestRect.Left + 18 + TextSize.cx, DestRect.Top + 16 + TextSize.cy);
  Canvas.Brush.Color := clBlack;
  Canvas.Font.Color := clWhite;
  Canvas.FillRect(TextRect);
  Canvas.TextOut(TextRect.Left + 4, TextRect.Top + 3, Text);
end;
{$ENDIF}

procedure TVideoMinerVideoSurface.DrawFrame(Canvas: TCanvas; const DestRect: TRect);
var
  FrameBitmap : TBitmap;
  SourceHeight: Integer;
  SourceRect: TRect;
  SourceWidth: Integer;
begin
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  FrameBitmap := FBitmap;
  if FSourceHasAlpha then
  begin
    EnsureAlphaCompositeBitmap;
    if (FAlphaCompositeBitmap.Width = FBitmap.Width) and
       (FAlphaCompositeBitmap.Height = FBitmap.Height) then
      FrameBitmap := FAlphaCompositeBitmap;
  end;

  if FZoomScale <= MIN_ZOOM then
  begin
    Canvas.StretchDraw(DestRect, FrameBitmap);
    Exit;
  end;

  ClampZoomCenter;
  SourceWidth := Max(1, Round(FBitmap.Width / FZoomScale));
  SourceHeight := Max(1, Round(FBitmap.Height / FZoomScale));
  SourceRect.Left := Round(FZoomCenterX - SourceWidth / 2);
  SourceRect.Top := Round(FZoomCenterY - SourceHeight / 2);
  SourceRect.Right := SourceRect.Left + SourceWidth;
  SourceRect.Bottom := SourceRect.Top + SourceHeight;

  if SourceRect.Left < 0 then
    OffsetRect(SourceRect, -SourceRect.Left, 0);
  if SourceRect.Top < 0 then
    OffsetRect(SourceRect, 0, -SourceRect.Top);
  if SourceRect.Right > FBitmap.Width then
    OffsetRect(SourceRect, FBitmap.Width - SourceRect.Right, 0);
  if SourceRect.Bottom > FBitmap.Height then
    OffsetRect(SourceRect, 0, FBitmap.Height - SourceRect.Bottom);

  Canvas.CopyRect(DestRect, FrameBitmap.Canvas, SourceRect);
end;

function TVideoMinerVideoSurface.ImagePointFromClient(const Point: TPoint;
  out ImageX, ImageY: Double): Boolean;
var
  DestRect: TRect;
  SourceHeight: Double;
  SourceLeft: Double;
  SourceTop: Double;
  SourceWidth: Double;
begin
  ImageX := 0;
  ImageY := 0;
  DestRect := FitRect;
  Result := (FBitmap.Width > 0) and (FBitmap.Height > 0) and
    (not DestRect.IsEmpty) and PtInRect(DestRect, Point);
  if not Result then
    Exit;

  ClampZoomCenter;
  SourceWidth := FBitmap.Width / FZoomScale;
  SourceHeight := FBitmap.Height / FZoomScale;
  SourceLeft := FZoomCenterX - SourceWidth / 2;
  SourceTop := FZoomCenterY - SourceHeight / 2;
  ImageX := SourceLeft + (Point.X - DestRect.Left) / Max(1, DestRect.Width) *
    SourceWidth;
  ImageY := SourceTop + (Point.Y - DestRect.Top) / Max(1, DestRect.Height) *
    SourceHeight;
  ImageX := Max(0.0, Min(FBitmap.Width - 1.0, ImageX));
  ImageY := Max(0.0, Min(FBitmap.Height - 1.0, ImageY));
end;

procedure TVideoMinerVideoSurface.InvalidateOverlayControl(
  Control: TVideoMinerOverlayControl);
var
  InvalidRect: TRect;
begin
  if Control = nil then
    Exit;

  InvalidRect := Control.BoundsRect;
  InflateRect(InvalidRect, 4, 4);
  InvalidateRect(Handle, @InvalidRect, False);
end;

procedure TVideoMinerVideoSurface.InvalidateAllOverlayControls;
begin
  InvalidateOverlayControl(FPreviousFileButton);
  InvalidateOverlayControl(FFirstFrameButton);
  InvalidateOverlayControl(FSkipBackwardButton);
  InvalidateOverlayControl(FPlayPauseButton);
  InvalidateOverlayControl(FSkipForwardButton);
  InvalidateOverlayControl(FLastFrameButton);
  InvalidateOverlayControl(FNextFileButton);
end;

function TVideoMinerVideoSurface.HitAnyOverlayButton(const Point: TPoint): Boolean;
begin
  Result :=
    ((FFirstFrameButton <> nil) and FFirstFrameButton.BoundsHitTest(Point)) or
    ((FSkipBackwardButton <> nil) and FSkipBackwardButton.BoundsHitTest(Point)) or
    ((FPlayPauseButton <> nil) and FPlayPauseButton.BoundsHitTest(Point)) or
    ((FSkipForwardButton <> nil) and FSkipForwardButton.BoundsHitTest(Point)) or
    ((FLastFrameButton <> nil) and FLastFrameButton.BoundsHitTest(Point));
end;

function TVideoMinerVideoSurface.HitPreviousFileButton(
  const Point: TPoint): Boolean;
begin
  Result := (FPreviousFileButton <> nil) and
    FPreviousFileButton.BoundsHitTest(Point);
end;

function TVideoMinerVideoSurface.HitNextFileButton(
  const Point: TPoint): Boolean;
begin
  Result := (FNextFileButton <> nil) and FNextFileButton.BoundsHitTest(Point);
end;

function TVideoMinerVideoSurface.HitSeekBar(const Point: TPoint): Boolean;
begin
  Result := (FSeekBar <> nil) and FSeekBar.BoundsHitTest(Point);
end;

function TVideoMinerVideoSurface.CanStartPan(const Point: TPoint): Boolean;
begin
  Result := (FZoomScale > MIN_ZOOM) and
    (not FitRect.IsEmpty) and PtInRect(FitRect, Point) and
    not HitSeekBar(Point) and not HitAnyOverlayButton(Point) and
    not HitPreviousFileButton(Point) and not HitNextFileButton(Point);
end;

function TVideoMinerVideoSurface.CanStartSurfaceClick(
  const Point: TPoint): Boolean;
begin
  Result := not ((FSeekBarVisible or ((FSeekBar <> nil) and FSeekBar.Dragging)) and
    HitSeekBar(Point)) and
    not (FOverlayVisible and HitAnyOverlayButton(Point)) and
    not ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible and
      HitPreviousFileButton(Point)) and
    not ((FNextFileButton <> nil) and FNextFileButton.Visible and
      HitNextFileButton(Point));
end;

procedure TVideoMinerVideoSurface.SetOverlayVisible(Value: Boolean);
begin
  if FOverlayVisible = Value then
    Exit;

  FOverlayVisible := Value;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.Visible := Value;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.Visible := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.Visible := Value;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.Visible := Value;
  if FLastFrameButton <> nil then
    FLastFrameButton.Visible := Value;
  InvalidateAllOverlayControls;
end;

procedure TVideoMinerVideoSurface.SetBossMode(Value: Boolean);
begin
  if FBossMode = Value then
    Exit;

  FBossMode := Value;
  CancelPendingSurfaceClick;
  if FBossGestureDetector <> nil then
    FBossGestureDetector.Reset;
  if Value then
  begin
    SetOverlayVisible(False);
    SetSeekBarVisible(False);
    if FPreviousFileButton <> nil then
      FPreviousFileButton.Visible := False;
    if FNextFileButton <> nil then
      FNextFileButton.Visible := False;
  end;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.SetSeekBarVisible(Value: Boolean);
begin
  if FSeekBarVisible = Value then
    Exit;

  FSeekBarVisible := Value;
  if FSeekBar <> nil then
    FSeekBar.Visible := Value;
  InvalidateOverlayControl(FSeekBar);
end;

procedure TVideoMinerVideoSurface.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FBossMode then
  begin
    CancelPendingSurfaceClick;
    Exit;
  end;

  if Button = mbLeft then
  begin
    CancelPendingSurfaceClick;
    FSurfaceClickArmed := CanStartSurfaceClick(Point(X, Y));
  end;

  if (Button = mbLeft) and CanStartPan(Point(X, Y)) then
  begin
    FPanning := True;
    FPanMoved := False;
    FPanStartPoint := Point(X, Y);
    FPanStartCenterX := FZoomCenterX;
    FPanStartCenterY := FZoomCenterY;
    MouseCapture := True;
    Exit;
  end;

  if (Button = mbLeft) and (FSeekBar <> nil) and HitSeekBar(Point(X, Y)) then
  begin
    SetSeekBarVisible(True);
    if FSeekBar.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSeekBar);
    MouseCapture := True;
  end;

  if (Button = mbLeft) and FOverlayVisible then
  begin
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FFirstFrameButton);
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FSkipForwardButton);
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FLastFrameButton);
  end;

  if Button = mbLeft then
  begin
    if (FPreviousFileButton <> nil) and FPreviousFileButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FPreviousFileButton);
    if (FNextFileButton <> nil) and FNextFileButton.MouseDown(Point(X, Y)) then
      InvalidateOverlayControl(FNextFileButton);
  end;
end;

procedure TVideoMinerVideoSurface.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  DestRect: TRect;
  MousePoint: TPoint;
  SourceHeight: Double;
  SourceWidth: Double;
begin
  inherited MouseMove(Shift, X, Y);
  MousePoint := Point(X, Y);

  if FBossMode then
    Exit;

  if FPanning then
  begin
    DestRect := FitRect;
    if not DestRect.IsEmpty then
    begin
      if (Abs(MousePoint.X - FPanStartPoint.X) > 2) or
         (Abs(MousePoint.Y - FPanStartPoint.Y) > 2) then
        FPanMoved := True;
      SourceWidth := FBitmap.Width / FZoomScale;
      SourceHeight := FBitmap.Height / FZoomScale;
      FZoomCenterX := FPanStartCenterX -
        (MousePoint.X - FPanStartPoint.X) / Max(1, DestRect.Width) *
        SourceWidth;
      FZoomCenterY := FPanStartCenterY -
        (MousePoint.Y - FPanStartPoint.Y) / Max(1, DestRect.Height) *
        SourceHeight;
      ClampZoomCenter;
      Invalidate;
    end;
    Exit;
  end;

  if (FBossGestureDetector <> nil) and
     FBossGestureDetector.MouseMove(MousePoint, (Shift = []) and
       not FSeekBarVisible and
       not ((FSeekBar <> nil) and FSeekBar.Dragging)) then
  begin
    CancelPendingSurfaceClick;
    if Assigned(FOnBossGesture) then
      FOnBossGesture(Self);
    Exit;
  end;

  SetOverlayVisible(HitAnyOverlayButton(MousePoint));
  SetSeekBarVisible(HitSeekBar(MousePoint) or
    ((FSeekBar <> nil) and FSeekBar.Dragging));

  if FPreviousFileButton <> nil then
  begin
    FPreviousFileButton.Visible := HitPreviousFileButton(MousePoint);
    if FPreviousFileButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FPreviousFileButton);
  end;
  if FNextFileButton <> nil then
  begin
    FNextFileButton.Visible := HitNextFileButton(MousePoint);
    if FNextFileButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FNextFileButton);
  end;

  if FOverlayVisible then
  begin
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FFirstFrameButton);
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FSkipForwardButton);
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseMove(MousePoint) then
      InvalidateOverlayControl(FLastFrameButton);
  end;

  if FSeekBarVisible and (FSeekBar <> nil) and FSeekBar.MouseMove(MousePoint) then
    InvalidateOverlayControl(FSeekBar);

end;

procedure TVideoMinerVideoSurface.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FBossMode then
  begin
    CancelPendingSurfaceClick;
    if (Button = mbLeft) and PtInRect(FBossExitButtonRect, Point(X, Y)) and
       Assigned(FOnBossExitClick) then
      FOnBossExitClick(Self);
    Exit;
  end;

  if (Button = mbLeft) and FPanning then
  begin
    FPanning := False;
    MouseCapture := False;
    if FSurfaceClickArmed and not FPanMoved and
       CanStartSurfaceClick(Point(X, Y)) then
    begin
      FPendingSurfaceClick := True;
      FSurfaceClickTimer.Enabled := True;
    end;
    FSurfaceClickArmed := False;
    Exit;
  end;

  if (Button = mbLeft) and (FSeekBar <> nil) and
     (FSeekBarVisible or FSeekBar.Dragging) then
  begin
    if FSeekBar.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSeekBar);
    MouseCapture := False;
    SetSeekBarVisible(HitSeekBar(Point(X, Y)));
  end;

  if (Button = mbLeft) and FOverlayVisible then
  begin
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FFirstFrameButton);
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSkipBackwardButton);
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FPlayPauseButton);
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FSkipForwardButton);
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FLastFrameButton);
  end;

  if Button = mbLeft then
  begin
    if (FPreviousFileButton <> nil) and FPreviousFileButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FPreviousFileButton);
    if (FNextFileButton <> nil) and FNextFileButton.MouseUp(Point(X, Y)) then
      InvalidateOverlayControl(FNextFileButton);
    if FSurfaceClickArmed and CanStartSurfaceClick(Point(X, Y)) then
    begin
      FPendingSurfaceClick := True;
      FSurfaceClickTimer.Enabled := True;
    end;
    FSurfaceClickArmed := False;
  end;
end;

function TVideoMinerVideoSurface.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := HandleMouseWheel(Shift, WheelDelta, MousePos);
  if not Result then
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVideoMinerVideoSurface.HandleMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  DestRect: TRect;
  ImageX: Double;
  ImageY: Double;
  LocalPoint: TPoint;
  NewScale: Double;
  NewSourceHeight: Double;
  NewSourceWidth: Double;
  RatioX: Double;
  RatioY: Double;
  SeekPositionMs: Integer;
  StepMs: Integer;
begin
  Result := False;

  if FBossMode then
  begin
    Result := True;
    Exit;
  end;

  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  LocalPoint := ScreenToClient(MousePos);
  DestRect := FitRect;
  if DestRect.IsEmpty then
    Exit;

  if FSeekBar <> nil then
  begin
    FSeekBar.UpdateLayout(DestRect);
    if FSeekBar.BoundsHitTest(LocalPoint) then
    begin
      SetSeekBarVisible(True);
      if FSeekBar.CheckEnabled then
        StepMs := FSeekWheelFrameStepMs
      else
        StepMs := SEEK_WHEEL_STEP_MS;
      SeekPositionMs := FSeekBar.WheelPosition(WheelDelta, StepMs);
      if Assigned(FOnSeekByWheel) then
        FOnSeekByWheel(Self, SeekPositionMs);
      Result := True;
      Exit;
    end;
  end;

  if not PtInRect(DestRect, LocalPoint) then
    Exit;
  if not ImagePointFromClient(LocalPoint, ImageX, ImageY) then
    Exit;

  if WheelDelta > 0 then
    NewScale := FZoomScale * WHEEL_ZOOM_STEP
  else
    NewScale := FZoomScale / WHEEL_ZOOM_STEP;
  NewScale := Max(MIN_ZOOM,
    Min(MAX_ZOOM, NewScale));

  if Abs(NewScale - MIN_ZOOM) < 0.01 then
  begin
    ResetZoom;
    Invalidate;
    Result := True;
    Exit;
  end;

  RatioX := (LocalPoint.X - DestRect.Left) / Max(1, DestRect.Width);
  RatioY := (LocalPoint.Y - DestRect.Top) / Max(1, DestRect.Height);
  NewSourceWidth := FBitmap.Width / NewScale;
  NewSourceHeight := FBitmap.Height / NewScale;

  FZoomScale := NewScale;
  FZoomCenterX := ImageX - RatioX * NewSourceWidth + NewSourceWidth / 2;
  FZoomCenterY := ImageY - RatioY * NewSourceHeight + NewSourceHeight / 2;
  ClampZoomCenter;

  Invalidate;
  Result := True;
end;

procedure TVideoMinerVideoSurface.Paint;
{$IFDEF DEBUG}
var
  PaintWatch: TStopwatch;
  DebugLogEnabled: Boolean;
{$ENDIF}
var
  DrawCanvas: TCanvas;
  DestRect: TRect;
  UsePaintBuffer: Boolean;
begin
{$IFDEF DEBUG}
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  if DebugLogEnabled then
    PaintWatch := TStopwatch.StartNew;
{$ENDIF}
  if (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;

  if FBossMode then
  begin
    DrawVideoMinerBossOverlay(Canvas, ClientRect, FBossExitButtonRect);
    Exit;
  end;

  UsePaintBuffer := FOverlayVisible or FSeekBarVisible or
    ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible) or
    ((FNextFileButton <> nil) and FNextFileButton.Visible);
  if UsePaintBuffer then
  begin
    if (FPaintBuffer.Width <> ClientWidth) or
       (FPaintBuffer.Height <> ClientHeight) then
      FPaintBuffer.SetSize(ClientWidth, ClientHeight);
    DrawCanvas := FPaintBuffer.Canvas;
  end
  else
    DrawCanvas := Canvas;

  DrawCanvas.Brush.Color := clBlack;
  if (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
  begin
    DrawCanvas.FillRect(ClientRect);
    if UsePaintBuffer then
      Canvas.Draw(0, 0, FPaintBuffer);
    Exit;
  end;

  DestRect := FitRect;
  FPreviewRect := DestRect;
  if DestRect.Top > 0 then
    DrawCanvas.FillRect(Rect(0, 0, ClientWidth, DestRect.Top));
  if DestRect.Bottom < ClientHeight then
    DrawCanvas.FillRect(Rect(0, DestRect.Bottom, ClientWidth, ClientHeight));
  if DestRect.Left > 0 then
    DrawCanvas.FillRect(Rect(0, DestRect.Top, DestRect.Left, DestRect.Bottom));
  if DestRect.Right < ClientWidth then
    DrawCanvas.FillRect(Rect(DestRect.Right, DestRect.Top, ClientWidth, DestRect.Bottom));

  DrawFrame(DrawCanvas, DestRect);
{$IFDEF DEBUG}
  DrawAlphaStatus(DrawCanvas, DestRect);
{$ENDIF}
  if FPreviousFileButton <> nil then
    FPreviousFileButton.UpdateLayout(ClientRect);
  if FFirstFrameButton <> nil then
    FFirstFrameButton.UpdateLayout(FPreviewRect);
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.UpdateLayout(FPreviewRect);
  if FPlayPauseButton <> nil then
    FPlayPauseButton.UpdateLayout(FPreviewRect);
  if FSkipForwardButton <> nil then
    FSkipForwardButton.UpdateLayout(FPreviewRect);
  if FLastFrameButton <> nil then
    FLastFrameButton.UpdateLayout(FPreviewRect);
  if FNextFileButton <> nil then
    FNextFileButton.UpdateLayout(ClientRect);
  if FSeekBar <> nil then
    FSeekBar.UpdateLayout(FPreviewRect);

  if (FPreviousFileButton <> nil) and FPreviousFileButton.Visible then
    FPreviousFileButton.Paint(DrawCanvas);
  if FOverlayVisible and (FFirstFrameButton <> nil) then
  begin
    FFirstFrameButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FSkipBackwardButton <> nil) then
  begin
    FSkipBackwardButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FPlayPauseButton <> nil) then
  begin
    FPlayPauseButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FSkipForwardButton <> nil) then
  begin
    FSkipForwardButton.Paint(DrawCanvas);
  end;
  if FOverlayVisible and (FLastFrameButton <> nil) then
  begin
    FLastFrameButton.Paint(DrawCanvas);
  end;
  if (FNextFileButton <> nil) and FNextFileButton.Visible then
    FNextFileButton.Paint(DrawCanvas);
  if FSeekBarVisible and (FSeekBar <> nil) then
    FSeekBar.Paint(DrawCanvas);
  if UsePaintBuffer then
    Canvas.Draw(0, 0, FPaintBuffer);
{$IFDEF DEBUG}
  if DebugLogEnabled then
    WriteVideoMinerDebugLog(Format('paint width=%d height=%d client_w=%d client_h=%d paint_ms=%.3f',
      [FBitmap.Width, FBitmap.Height, ClientWidth, ClientHeight,
       PaintWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

procedure TVideoMinerVideoSurface.Present;
begin
  FAlphaCompositeDirty := True;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.PresentImmediate;
begin
  FAlphaCompositeDirty := True;
  Invalidate;
  Update;
end;

procedure TVideoMinerVideoSurface.SetSourceHasAlpha(Value: Boolean);
begin
  if FSourceHasAlpha = Value then
    Exit;

  FSourceHasAlpha := Value;
  FAlphaCompositeDirty := True;
  FAlphaMin := 255;
  FAlphaMax := 0;
  FAlphaPixelCount := 0;
  Invalidate;
end;
procedure TVideoMinerVideoSurface.SetPlaybackActive(Value: Boolean);
begin
  if (FPlayPauseButton <> nil) and (FPlayPauseButton.IsPlaying <> Value) then
  begin
    FPlayPauseButton.IsPlaying := Value;
    Invalidate;
  end;
end;

procedure TVideoMinerVideoSurface.SetSeekProgress(PositionMs, MaxMs: Integer);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.SetProgress(PositionMs, MaxMs);
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetSeekWheelFrameStepMs(Value: Integer);
begin
  FSeekWheelFrameStepMs := Max(1, Value);
  if FSeekBar <> nil then
    FSeekBar.FrameStepMs := FSeekWheelFrameStepMs;
end;

procedure TVideoMinerVideoSurface.SetFullScreen(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.FullScreen := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetCanNavigatePrevious(Value: Boolean);
begin
  if FPreviousFileButton <> nil then
  begin
    FPreviousFileButton.Enabled := Value;
    if not Value then
      FPreviousFileButton.Visible := False;
    InvalidateOverlayControl(FPreviousFileButton);
  end;
end;

procedure TVideoMinerVideoSurface.SetCanNavigateNext(Value: Boolean);
begin
  if FNextFileButton <> nil then
  begin
    FNextFileButton.Enabled := Value;
    if not Value then
      FNextFileButton.Visible := False;
    InvalidateOverlayControl(FNextFileButton);
  end;
end;

procedure TVideoMinerVideoSurface.SetEndActionText(const Value: string);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.EndActionText := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetCheckEnabled(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.CheckEnabled := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetChapters(
  const Value: TVideoMinerOverlayChapters);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.Chapters := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetVolumePercent(Value: Integer);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.VolumePercent := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetMuted(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.Muted := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetPlaybackRateText(const Value: string);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.PlaybackRateText := Value;
    if FSeekBarVisible then
      InvalidateOverlayControl(FSeekBar);
  end;
end;

procedure TVideoMinerVideoSurface.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  FOnPlayPauseClick := Value;
  if FPlayPauseButton <> nil then
    FPlayPauseButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnBossExitClick(Value: TNotifyEvent);
begin
  FOnBossExitClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnBossGesture(Value: TNotifyEvent);
begin
  FOnBossGesture := Value;
end;

procedure TVideoMinerVideoSurface.SetOnEndActionClick(Value: TNotifyEvent);
begin
  FOnEndActionClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnEndActionClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnCheckClick(Value: TNotifyEvent);
begin
  FOnCheckClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnCheckClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnAddChapterClick(Value: TNotifyEvent);
begin
  FOnAddChapterClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnAddChapterClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnDeleteChapterClick(Value: TNotifyEvent);
begin
  FOnDeleteChapterClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnDeleteChapterClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnFullScreenClick(Value: TNotifyEvent);
begin
  FOnFullScreenClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnFullScreenClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnMuteClick(Value: TNotifyEvent);
begin
  FOnMuteClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnMuteClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnPlaybackRateClick(Value: TNotifyEvent);
begin
  FOnPlaybackRateClick := Value;
  if FSeekBar <> nil then
    FSeekBar.OnPlaybackRateClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
begin
  FOnSeek := Value;
  if FSeekBar <> nil then
    FSeekBar.OnSeek := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSeekByWheel(
  Value: TVideoMinerOverlaySeekEvent);
begin
  FOnSeekByWheel := Value;
end;

procedure TVideoMinerVideoSurface.SetOnVolumeChange(
  Value: TVideoMinerOverlayVolumeEvent);
begin
  FOnVolumeChange := Value;
  if FSeekBar <> nil then
    FSeekBar.OnVolumeChange := Value;
end;

procedure TVideoMinerVideoSurface.SurfaceClickTimer(Sender: TObject);
begin
  FSurfaceClickTimer.Enabled := False;
  if not FPendingSurfaceClick then
    Exit;

  FPendingSurfaceClick := False;
  if Assigned(FOnPlayPauseClick) then
    FOnPlayPauseClick(Self);
end;

procedure TVideoMinerVideoSurface.SetOnFirstFrameClick(Value: TNotifyEvent);
begin
  FOnFirstFrameClick := Value;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnLastFrameClick(Value: TNotifyEvent);
begin
  FOnLastFrameClick := Value;
  if FLastFrameButton <> nil then
    FLastFrameButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnNavigatePreviousClick(Value: TNotifyEvent);
begin
  FOnNavigatePreviousClick := Value;
  if FPreviousFileButton <> nil then
    FPreviousFileButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnNavigateNextClick(Value: TNotifyEvent);
begin
  FOnNavigateNextClick := Value;
  if FNextFileButton <> nil then
    FNextFileButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSkipBackwardClick(Value: TNotifyEvent);
begin
  FOnSkipBackwardClick := Value;
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSkipForwardClick(Value: TNotifyEvent);
begin
  FOnSkipForwardClick := Value;
  if FSkipForwardButton <> nil then
    FSkipForwardButton.OnClick := Value;
end;

procedure TVideoMinerVideoSurface.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

end.
