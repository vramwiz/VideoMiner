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
    FBossHelpPageIndex      : Integer;                           // ボスが来たモード中に表示するヘルプページ
    FBossMode               : Boolean;                           // 動画を隠して偽装画面を表示中か
    FPaintBuffer            : TBitmap;                           // overlay 表示時のちらつきを抑える描画用バッファ
    FFirstFrameButton       : TVideoMinerOverlayEdgeButton;      // 先頭フレームへ移動する中央ボタン
    FLastFrameButton        : TVideoMinerOverlayEdgeButton;      // 末尾フレームへ移動する中央ボタン
    FLoadingActive          : Boolean;                           // 動画読み込み中のインジケータを表示するか
    FLoadingTick            : Integer;                           // 読み込み中インジケータのアニメーション段階
    FLoadingTimer           : TTimer;                            // 読み込み中インジケータを再描画するタイマー
    FLastD3DStateLogText    : string;                            // 直近に出した D3D 表示判定ログ
    FLastD3DStateLogTick    : UInt64;                            // 直近に D3D 表示判定ログを出した時刻
    FForceCompactSeekBarPaint : Boolean;                         // ループ再開中の一時 GDI 表示でも D3D 風に描くか
    FLiveResizeActive       : Boolean;                           // フォームのドラッグリサイズ中か
    FLastSeekBarPaintLogText: string;                            // 直近に出した GDI seek bar 描画ログ
    FLastSeekBarPaintLogTick: UInt64;                            // 直近に GDI seek bar 描画ログを出した時刻
    FLastD3DFramePresentedTick: UInt64;                           // 直近に D3D frame を表示した時刻
    FNextFileButton         : TVideoMinerOverlayFileNavButton;   // 次動画へ移動する右端ボタン
    FPanMoved               : Boolean;                           // 押下後にパン移動が発生したか
    FPanning                : Boolean;                           // ズーム中のドラッグ移動を処理中か
    FPanStartCenterX        : Double;                            // パン開始時の画像中心 X
    FPanStartCenterY        : Double;                            // パン開始時の画像中心 Y
    FPanStartPoint          : TPoint;                            // パン開始時のクライアント座標
    FPendingSurfaceClick    : Boolean;                           // ダブルクリック判定待ちの単クリックがあるか
    FSurfaceClickArmed      : Boolean;                           // 現在の押下が単クリック候補か
    FSurfaceClickTimer      : TTimer;                            // ダブルクリック猶予後に再生切替を発火するタイマー
    FSuppressSurfaceClickUp : Boolean;                           // ダブルクリック成立後の MouseUp で単クリック扱いしないか
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
    FOnSurfaceRightClick    : TNotifyEvent;                      // 動画面右クリックの通知先
    FOnToggleChapterClick   : TVideoMinerOverlaySeekEvent;       // シークバー右クリックのチャプタートグル通知先
    FOnSeek                 : TVideoMinerOverlaySeekEvent;       // シークバー操作の通知先
    FOnSeekByWheel          : TVideoMinerOverlaySeekEvent;       // シークバー上ホイール操作の通知先
    FOnSeekHoverPreview     : TVideoMinerOverlaySeekHoverEvent;  // シークバー hover プレビュー要求先
    FOnSeekHoverPreviewEnd  : TNotifyEvent;                      // シークバー hover プレビュー終了通知先
    FOnSkipBackwardClick    : TNotifyEvent;                      // 10 秒戻しボタンの通知先
    FOnSkipForwardClick     : TNotifyEvent;                      // 10 秒進みボタンの通知先
    FOnVolumeChange         : TVideoMinerOverlayVolumeEvent;     // 音量変更の通知先
    FOverlayVisible         : Boolean;                           // 中央 overlay ボタン群を表示中か
    FPlaybackActive         : Boolean;                           // 現在再生中か
    FSeekBarHoverPositionMs : Integer;                           // D3D overlay 用の hover/drag 位置 ms
    FPlayPauseButton        : TVideoMinerOverlayPlayPauseButton; // 再生/一時停止の中央ボタン
    FPreviousFileButton     : TVideoMinerOverlayFileNavButton;   // 前動画へ移動する左端ボタン
    FPreviewRect            : TRect;                             // 動画フレームが実際に描画される領域
    FSafeAreaVisible        : Boolean;                           // 90% セーフエリア確認枠を表示中か
    FSeekBar                : TVideoMinerOverlaySeekBar;         // 下側のシーク/音量/状態操作バー
    FSeekBarLastHitTick     : UInt64;                            // シークバー hover 維持用の最終ヒット tick
    FSeekBarVisible         : Boolean;                           // 下側シークバーを表示中か
    FSeekBarVisibleRequestSource: string;                        // シークバー表示切替要求元の調査用ラベル
    FSeekPreviewAnchor      : TPoint;                            // hover プレビューを寄せるクライアント座標
    FSeekPreviewBitmap      : TBitmap;                           // シークバー hover 用の小型プレビュー
    FSeekPreviewPositionMs  : Integer;                           // hover プレビューの対象位置 ms
    FSeekPreviewVisible     : Boolean;                           // シークバー hover プレビューを表示中か
    FSeekWheelFrameStepMs   : Integer;                           // フレーム単位ホイールシークの 1 ステップ幅 ms
    FSkipBackwardButton     : TVideoMinerOverlaySkipButton;      // 10 秒戻しの中央ボタン
    FSkipForwardButton      : TVideoMinerOverlaySkipButton;      // 10 秒進みの中央ボタン
    FSourceHasAlpha         : Boolean;                           // 現在の動画が alpha を持つ形式か
    FZoomCenterX            : Double;                            // ズーム表示の画像中心 X
    FZoomCenterY            : Double;                            // ズーム表示の画像中心 Y
    FZoomFrameRefreshNeeded : Boolean;                           // D3D 表示後にズーム用 CPU frame 再取得が必要か
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
    // 動画座標の中央 90% を確認用ガイドとして描く
    procedure DrawSafeAreaGuide(Canvas: TCanvas; const DestRect: TRect);
    // シークバー hover 位置のフレームプレビューを描く
    procedure DrawSeekHoverPreview(Canvas: TCanvas);
    // 旧パネルを含まない最小 seek bar fallback を描く
    procedure DrawMinimalSeekBarFallback(Canvas: TCanvas);
    // 読み込み中であることを示すテキストを描く
    procedure DrawLoadingIndicator(Canvas: TCanvas);
    // alpha 確認用の市松模様合成 Bitmap を最新化する
    procedure EnsureAlphaCompositeBitmap;
    // クライアント領域内に動画全体が収まる描画矩形を返す
    function FitRect: TRect;
    // 中央 overlay ボタン群の配置を現在の動画表示矩形へ合わせる
    procedure UpdateCenterOverlayButtonLayouts;
    // 中央 overlay ボタン群を 1 つの操作領域として扱う矩形を返す
    function CenterOverlayGroupBounds: TRect;
    // 中央 overlay ボタン群に当たっているか返す
    function HitAnyOverlayButton(const Point: TPoint): Boolean;
    // 下側シークバーに当たっているか返す
    function HitSeekBar(const Point: TPoint): Boolean;
    // 表示中の下側シークバーを維持する領域に当たっているか返す
    function HitSeekBarKeepAlive(const Point: TPoint): Boolean;
    // 下側シークバーを配置するフォーム側の基準領域を返す
    function SeekBarLayoutRect: TRect;
    // D3D 表示中に backbuffer 上へ描く簡易シークバー状態を更新する
    procedure UpdateD3DSeekBarOverlayState;
    // D3D 表示中の動画 texture 拡大表示状態を更新する
    procedure UpdateD3DVideoZoomState;
    // 保持中の D3D frame へ現在の簡易シークバー状態を重ねて再表示する
    function RefreshD3DFramePresentation: Boolean;
    // D3D11 直接表示を止めている最初の理由を返す
    function D3DFramePresentationBlockReason: string;
    function D3DFramePresentationBlockReasonEx(AllowAlpha: Boolean): string;
    // D3D11 直接表示の現在状態を状態変化時または低頻度でログへ出す
    procedure LogD3DFramePresentationState(const Context: string;
      Force: Boolean = False; AllowAlpha: Boolean = False);
    // GDI seek bar を描いた時の見た目と状態を状態変化時または低頻度でログへ出す
    procedure LogSeekBarPaintState(CompactStyle, D3DFrameCurrent: Boolean);
    // 直近に D3D frame を表示していて backbuffer を維持できる可能性があるか返す
    function D3DFrameRecentlyPresented: Boolean;
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
    // 下側シークバーの表示状態を、要求元ラベル付きで切り替える
    procedure SetSeekBarVisibleFrom(const Source: string; Value: Boolean);
    // 90% セーフエリア確認枠の表示状態を切り替える
    procedure SetSafeAreaVisible(Value: Boolean);
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
    // 動画面右クリックの通知先を設定する
    procedure SetOnSurfaceRightClick(Value: TNotifyEvent);
    // シークバー操作の通知先を設定する
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    // シークバー上ホイール操作の通知先を設定する
    procedure SetOnSeekByWheel(Value: TVideoMinerOverlaySeekEvent);
    // シークバー hover プレビュー要求先を設定する
    procedure SetOnSeekHoverPreview(Value: TVideoMinerOverlaySeekHoverEvent);
    // シークバー hover プレビュー終了通知先を設定する
    procedure SetOnSeekHoverPreviewEnd(Value: TNotifyEvent);
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
    // 読み込み中インジケータを 1 段階進める
    procedure LoadingTimer(Sender: TObject);
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
    // リサイズ直後に D3D backbuffer と overlay 座標を現在サイズへ同期する
    procedure Resize; override;
  public
    // 動画表示用 Bitmap、overlay 部品、入力タイマーを生成する
    constructor Create(AOwner: TComponent); override;
    // 生成した overlay 部品と描画バッファを解放する
    destructor Destroy; override;
    // 表示フレームと overlay 状態を空にする
    procedure Clear;
    // 読み込み中インジケータを表示し始める
    procedure BeginLoadingIndicator;
    // フォームのライブリサイズ中は D3D 再表示を抑えて VCL 再描画と競合しないようにする
    procedure BeginLiveResize;
    // ボスが来たモード中のヘルプページを前後へ切り替える
    procedure ChangeBossHelpPage(Delta: Integer);
    // 外部から渡されたホイール操作をこの表示面で処理する
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
    // 停止状態から再生へ入る直前に、停止中 overlay の残りを閉じる
    procedure HidePlaybackStartOverlays;
    // 現在表示中フレームの四隅が暗いか返す
    function CurrentFrameCornersMostlyDark: Boolean;
    // 現在表示中フレームの簡易署名を返す
    function CurrentFrameSignature(out Signature: TVideoMinerFrameSignature): Boolean;
    // シークバー上の指定 pixel 幅を動画時間 ms へ変換する
    function ChapterMarkerToleranceMs(MaxMs, PixelTolerance: Integer): Integer;
    // D3D11 直接表示で動画本体だけを描いてよい状態か返す
    function CanUseD3DFramePresentation: Boolean;
    // alpha 合成済み BGRX32 など、CPU 確定フレームを D3D 表示してよい状態か返す
    function CanUseD3DCompositedFramePresentation: Boolean;
    // D3D overlay を更新するため、表示用フレームを確保したい状態か返す
    function NeedsD3DOverlayFrame: Boolean;
    // D3D11 直接表示直前に target window と overlay 座標を同期する
    function PrepareD3DFramePresentation: Boolean;
    // CPU 側で確定した BGRX32 フレームを D3D 表示する直前に target window と overlay 座標を同期する
    function PrepareD3DCompositedFramePresentation: Boolean;
    // 現在の BGRX32 フレームを必要なら alpha 市松合成して D3D 表示する
    function PresentCurrentBgrx32FrameWithD3D: Boolean;
    // D3D11 直接表示で実際に frame が出たことを記録する
    procedure MarkD3DFramePresented;
    // ズーム操作後に現在位置の CPU frame 再表示が必要なら True を返して消費する
    function ConsumeZoomFrameRefreshNeeded: Boolean;
    // FBitmap を BGRX32 の direct デコード先として使える状態にする
    function PrepareBgrx32Frame(Width, Height: Integer; out Buffer: Pointer;
      out BufferStride: Integer): Boolean;
    // 通常の再描画タイミングで現在フレームを表示する
    procedure Present;
    // すぐに現在フレームを表示する
    procedure PresentImmediate;
    // 再生継続中の CPU fallback としてすぐに現在フレームを表示する
    procedure PresentImmediateAsPlaybackFallback;
    // 下側シークバーの現在位置を更新する
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    // シークバー hover 位置の小型プレビューを表示する
    procedure SetSeekHoverPreview(Bitmap: TBitmap; PositionMs: Integer; const AnchorPoint: TPoint);
    // シークバー hover プレビューを消す
    procedure ClearSeekHoverPreview;
    // 読み込み中インジケータを消す
    procedure EndLoadingIndicator;
    // フォームのライブリサイズ終了後に通常の D3D 表示へ戻れる状態にする
    procedure EndLiveResize;
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
    property OnSurfaceRightClick: TNotifyEvent read FOnSurfaceRightClick write SetOnSurfaceRightClick;
    property OnToggleChapterClick: TVideoMinerOverlaySeekEvent read FOnToggleChapterClick write FOnToggleChapterClick;
    property OnSeek: TVideoMinerOverlaySeekEvent read FOnSeek write SetOnSeek;
    property OnSeekByWheel: TVideoMinerOverlaySeekEvent read FOnSeekByWheel write SetOnSeekByWheel;
    property OnSeekHoverPreview: TVideoMinerOverlaySeekHoverEvent read FOnSeekHoverPreview
      write SetOnSeekHoverPreview;
    property OnSeekHoverPreviewEnd: TNotifyEvent read FOnSeekHoverPreviewEnd
      write SetOnSeekHoverPreviewEnd;
    property OnSkipBackwardClick: TNotifyEvent read FOnSkipBackwardClick write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent read FOnSkipForwardClick write SetOnSkipForwardClick;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent read FOnVolumeChange write SetOnVolumeChange;
    property PlaybackActive: Boolean write SetPlaybackActive;
    property PlaybackRateText: string write SetPlaybackRateText;
    property SafeAreaVisible: Boolean read FSafeAreaVisible write SetSafeAreaVisible;
    property SourceHasAlpha: Boolean read FSourceHasAlpha write SetSourceHasAlpha;
    property Muted: Boolean write SetMuted;
    property VolumePercent: Integer write SetVolumePercent;
  end;

implementation

uses
  System.Diagnostics, System.Math, System.SysUtils, VideoMinerBossOverlay,
  VideoMinerDebugLog, FFmpegD3D11TextureProbe;

const
  MAX_ZOOM              = 8.0;  // ホイールズームで許可する最大倍率
  MIN_ZOOM              = 1.0;  // 全体表示として扱う最小倍率
  DEFAULT_FRAME_STEP_MS = 33;   // FPS 不明時の 1 フレーム相当ステップ ms
  SEEK_WHEEL_STEP_MS    = 1000; // 通常時のホイールシーク幅 ms
  WHEEL_ZOOM_STEP       = 1.20; // ホイール 1 ノッチあたりのズーム倍率
  ALPHA_CHECK_SIZE      = 16;   // alpha 確認表示の市松模様 1 マス px
  HIDE_LEGACY_SEEK_BAR_PAINT = True; // D3D seek bar 移行中は旧 GDI seek bar を描かない
  HIDE_LEGACY_CENTER_OVERLAY_PAINT = True; // 中央操作も D3D overlay 側へ寄せる
  SEEK_PREVIEW_WIDTH    = 160;  // シークバー hover プレビューの標準幅 px
  SEEK_PREVIEW_MARGIN   = 8;    // シークバー hover プレビューの余白 px
  SEEK_FALLBACK_ACCENT_COLOR = $00C040FF; // 最小 fallback seek bar を識別しやすくするマゼンタ
  LOADING_TIMER_MS      = 80;    // 読み込み中インジケータを進める間隔 ms
  LOADING_SEGMENTS      = 36;    // 欠け丸を構成する線分数
  LOADING_GAP_SEGMENTS  = 7;     // 欠けとして空ける線分数
  LOADING_LAP_TICKS     = 24;    // 色を切り替える周回の tick 数

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
  FSeekPreviewBitmap := TBitmap.Create;
  FSeekPreviewBitmap.PixelFormat := pf32bit;
  FOverlayVisible := False;
  FSeekBarVisible := False;
  FSeekBarHoverPositionMs := -1;
  FSeekPreviewVisible := False;
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
  FLoadingTimer := TTimer.Create(Self);
  FLoadingTimer.Enabled := False;
  FLoadingTimer.Interval := LOADING_TIMER_MS;
  FLoadingTimer.OnTimer := LoadingTimer;
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
  FLoadingTimer.Free;
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
  FSeekPreviewBitmap.Free;
  FPaintBuffer.Free;
  FAlphaCompositeBitmap.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoSurface.BeginLoadingIndicator;
begin
  FLoadingTick := 0;
  FLoadingActive := True;
  if FLoadingTimer <> nil then
    FLoadingTimer.Enabled := True;
  Invalidate;
  Repaint;
end;

procedure TVideoMinerVideoSurface.BeginLiveResize;
begin
  if FLiveResizeActive then
    Exit;

  FLiveResizeActive := True;
  ClearNv12TextureD3DFramePresented;
  FLastD3DFramePresentedTick := 0;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.DblClick;
begin
  inherited DblClick;
  if FBossMode then
    Exit;

  CancelPendingSurfaceClick;
  FSuppressSurfaceClickUp := True;
  if Assigned(FOnFullScreenClick) then
    FOnFullScreenClick(Self);
end;

procedure TVideoMinerVideoSurface.CancelPendingSurfaceClick;
begin
  FPendingSurfaceClick := False;
  FSurfaceClickArmed := False;
  FSuppressSurfaceClickUp := False;
  if FSurfaceClickTimer <> nil then
    FSurfaceClickTimer.Enabled := False;
end;

procedure TVideoMinerVideoSurface.ChangeBossHelpPage(Delta: Integer);
var
  PageCount: Integer;
begin
  if Delta = 0 then
    Exit;

  PageCount := VideoMinerBossHelpPageCount;
  if PageCount <= 0 then
    Exit;

  FBossHelpPageIndex := (FBossHelpPageIndex + Delta) mod PageCount;
  if FBossHelpPageIndex < 0 then
    Inc(FBossHelpPageIndex, PageCount);
  if FBossMode then
    Invalidate;
end;
procedure TVideoMinerVideoSurface.Clear;
begin
  CancelPendingSurfaceClick;
  ClearNv12TextureD3DFramePresented;
  FLastD3DFramePresentedTick := 0;
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
  FSeekBarHoverPositionMs := -1;
  ClearSeekHoverPreview;
  SetSeekBarVisibleFrom('clear_display_state', False);
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
  SetNv12TextureProbeTargetWindow(Handle, ClientWidth, ClientHeight);
  UpdateD3DSeekBarOverlayState;

  Buffer := FBitmap.ScanLine[0];
  if Height > 1 then
    BufferStride := NativeInt(FBitmap.ScanLine[1]) - NativeInt(Buffer)
  else
    BufferStride := Width * 4;

  FAlphaCompositeDirty := True;
  Result := (Buffer <> nil) and (BufferStride <> 0);
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

function TVideoMinerVideoSurface.D3DFramePresentationBlockReason: string;
begin
  Result := D3DFramePresentationBlockReasonEx(False);
end;

function TVideoMinerVideoSurface.D3DFramePresentationBlockReasonEx(
  AllowAlpha: Boolean): string;
begin
  Result := '';
  if FSourceHasAlpha and (not AllowAlpha) then
    Result := 'source_has_alpha'
  else if FSeekPreviewVisible then
    Result := 'seek_preview_visible'
  else if FSafeAreaVisible then
    Result := 'safe_area_visible'
  else if FLoadingActive then
    Result := 'loading_active'
end;

procedure TVideoMinerVideoSurface.LogD3DFramePresentationState(
  const Context: string; Force, AllowAlpha: Boolean);
var
  D3DReady: Boolean;
  NowTick: UInt64;
  Reason: string;
  Text: string;
begin
  Reason := D3DFramePresentationBlockReasonEx(AllowAlpha);
  D3DReady := Reason = '';
  if D3DReady and ((ClientWidth <= 0) or (ClientHeight <= 0)) then
  begin
    D3DReady := False;
    Reason := 'empty_client';
  end;
  if D3DReady and (not HandleAllocated) then
  begin
    D3DReady := False;
    Reason := 'handle_not_allocated';
  end;
  if Reason = '' then
    Reason := 'ready';

  Text := Format(
    'd3d_surface_state context=%s ready=%s reason=%s playback=%s seek_bar=%s ' +
    'seek_preview=%s overlay=%s safe_area=%s loading=%s zoom=%.3f alpha=%s ' +
    'prev_nav=%s next_nav=%s client=%dx%d',
    [Context, BoolToStr(D3DReady, True), Reason, BoolToStr(FPlaybackActive, True),
     BoolToStr(FSeekBarVisible, True), BoolToStr(FSeekPreviewVisible, True),
     BoolToStr(FOverlayVisible, True), BoolToStr(FSafeAreaVisible, True),
     BoolToStr(FLoadingActive, True), FZoomScale, BoolToStr(FSourceHasAlpha, True),
     BoolToStr((FPreviousFileButton <> nil) and FPreviousFileButton.Visible, True),
     BoolToStr((FNextFileButton <> nil) and FNextFileButton.Visible, True),
     ClientWidth, ClientHeight]);

  NowTick := GetTickCount64;
  if Force or (Text <> FLastD3DStateLogText) or
     (NowTick - FLastD3DStateLogTick >= 1000) then
  begin
    FLastD3DStateLogText := Text;
    FLastD3DStateLogTick := NowTick;
    WriteVideoMinerD3DLog(Text);
  end;
end;

procedure TVideoMinerVideoSurface.LogSeekBarPaintState(CompactStyle,
  D3DFrameCurrent: Boolean);
var
  NowTick: UInt64;
  Reason: string;
  Text: string;
begin
  Reason := D3DFramePresentationBlockReason;
  if Reason = '' then
    Reason := 'ready';

  Text := Format(
    'seekbar_gdi_paint compact=%s playback=%s force_compact=%s visible=%s ' +
    'dragging=%s hover_ms=%d seek_preview=%s overlay=%s d3d_frame_current=%s reason=%s',
    [BoolToStr(CompactStyle, True), BoolToStr(FPlaybackActive, True),
     BoolToStr(FForceCompactSeekBarPaint, True), BoolToStr(FSeekBarVisible, True),
     BoolToStr((FSeekBar <> nil) and FSeekBar.Dragging, True),
     FSeekBarHoverPositionMs, BoolToStr(FSeekPreviewVisible, True),
     BoolToStr(FOverlayVisible, True), BoolToStr(D3DFrameCurrent, True), Reason]);

  NowTick := GetTickCount64;
  if (Text <> FLastSeekBarPaintLogText) or
     (NowTick - FLastSeekBarPaintLogTick >= 250) then
  begin
    FLastSeekBarPaintLogText := Text;
    FLastSeekBarPaintLogTick := NowTick;
    WriteVideoMinerD3DLog(Text);
  end;
end;

function TVideoMinerVideoSurface.CanUseD3DFramePresentation: Boolean;
begin
  Result := D3DFramePresentationBlockReason = '';
end;

function TVideoMinerVideoSurface.CanUseD3DCompositedFramePresentation: Boolean;
begin
  Result := D3DFramePresentationBlockReasonEx(True) = '';
end;

function TVideoMinerVideoSurface.NeedsD3DOverlayFrame: Boolean;
begin
  Result := CanUseD3DCompositedFramePresentation and FPlaybackActive and
    (FSeekBarVisible or
     ((FSeekBar <> nil) and FSeekBar.Dragging) or
     FOverlayVisible or
     ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible) or
     ((FNextFileButton <> nil) and FNextFileButton.Visible));
end;

function TVideoMinerVideoSurface.D3DFrameRecentlyPresented: Boolean;
begin
  Result := (FLastD3DFramePresentedTick > 0) and
    (GetTickCount64 - FLastD3DFramePresentedTick <= 1000);
end;

function TVideoMinerVideoSurface.PrepareD3DFramePresentation: Boolean;
begin
  Result := CanUseD3DFramePresentation and (ClientWidth > 0) and
    (ClientHeight > 0) and HandleAllocated;
  LogD3DFramePresentationState('prepare', not Result);
  if not Result then
  begin
    SetNv12TextureD3DSeekBarOverlay(Default(TD3D11SeekBarOverlayState));
    Exit;
  end;

  SetNv12TextureProbeTargetWindow(Handle, ClientWidth, ClientHeight);
  UpdateD3DVideoZoomState;
  UpdateD3DSeekBarOverlayState;
end;

function TVideoMinerVideoSurface.PrepareD3DCompositedFramePresentation: Boolean;
begin
  Result := CanUseD3DCompositedFramePresentation and (ClientWidth > 0) and
    (ClientHeight > 0) and HandleAllocated;
  LogD3DFramePresentationState('prepare_composited', not Result, True);
  if not Result then
  begin
    SetNv12TextureD3DSeekBarOverlay(Default(TD3D11SeekBarOverlayState));
    Exit;
  end;

  SetNv12TextureProbeTargetWindow(Handle, ClientWidth, ClientHeight);
  UpdateD3DVideoZoomState;
  UpdateD3DSeekBarOverlayState;
end;

function TVideoMinerVideoSurface.PresentCurrentBgrx32FrameWithD3D: Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
  FrameBitmap: TBitmap;
begin
  Result := False;
  if (FBitmap = nil) or (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;
  if not PrepareD3DCompositedFramePresentation then
    Exit;

  FrameBitmap := FBitmap;
  if FSourceHasAlpha then
  begin
    EnsureAlphaCompositeBitmap;
    if (FAlphaCompositeBitmap.Width <> FBitmap.Width) or
       (FAlphaCompositeBitmap.Height <> FBitmap.Height) then
      Exit;
    FrameBitmap := FAlphaCompositeBitmap;
  end;

  if FrameBitmap.PixelFormat <> pf32bit then
    FrameBitmap.PixelFormat := pf32bit;
  Buffer := FrameBitmap.ScanLine[0];
  if FrameBitmap.Height > 1 then
    BufferStride := NativeInt(FrameBitmap.ScanLine[1]) - NativeInt(Buffer)
  else
    BufferStride := FrameBitmap.Width * 4;
  if (Buffer = nil) or (BufferStride = 0) then
    Exit;

  SetNv12TextureD3DDisplayAllowed(True);
  try
    Result := PresentBgrx32TextureFrame(Buffer, BufferStride,
      FrameBitmap.Width, FrameBitmap.Height);
  finally
    SetNv12TextureD3DDisplayAllowed(False);
  end;
  if Result then
    MarkD3DFramePresented;
end;

function TVideoMinerVideoSurface.ConsumeZoomFrameRefreshNeeded: Boolean;
begin
  Result := FZoomFrameRefreshNeeded;
  FZoomFrameRefreshNeeded := False;
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

procedure TVideoMinerVideoSurface.DrawSafeAreaGuide(Canvas: TCanvas; const DestRect: TRect);
var
  ClipState: Integer;
  GuideRect: TRect;
  SafeBottom: Double;
  SafeLeft: Double;
  SafeRight: Double;
  SafeTop: Double;
  SourceHeight: Double;
  SourceLeft: Double;
  SourceRect: TRect;
  SourceTop: Double;
  SourceWidth: Double;

  function MapX(ImageX: Double): Integer;
  begin
    Result := DestRect.Left + Round((ImageX - SourceLeft) * DestRect.Width / SourceWidth);
  end;

  function MapY(ImageY: Double): Integer;
  begin
    Result := DestRect.Top + Round((ImageY - SourceTop) * DestRect.Height / SourceHeight);
  end;

  procedure DrawGuideRectangle(Width: Integer; Color: TColor);
  begin
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := Width;
    Canvas.Pen.Color := Color;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(GuideRect);
  end;

begin
  if (not FSafeAreaVisible) or DestRect.IsEmpty or
     (FBitmap.Width <= 0) or (FBitmap.Height <= 0) then
    Exit;

  if FZoomScale <= MIN_ZOOM then
  begin
    SourceLeft := 0;
    SourceTop := 0;
    SourceWidth := FBitmap.Width;
    SourceHeight := FBitmap.Height;
  end
  else
  begin
    ClampZoomCenter;
    SourceWidth := Max(1.0, FBitmap.Width / FZoomScale);
    SourceHeight := Max(1.0, FBitmap.Height / FZoomScale);
    SourceRect.Left := Round(FZoomCenterX - SourceWidth / 2);
    SourceRect.Top := Round(FZoomCenterY - SourceHeight / 2);
    SourceRect.Right := SourceRect.Left + Round(SourceWidth);
    SourceRect.Bottom := SourceRect.Top + Round(SourceHeight);

    if SourceRect.Left < 0 then
      OffsetRect(SourceRect, -SourceRect.Left, 0);
    if SourceRect.Top < 0 then
      OffsetRect(SourceRect, 0, -SourceRect.Top);
    if SourceRect.Right > FBitmap.Width then
      OffsetRect(SourceRect, FBitmap.Width - SourceRect.Right, 0);
    if SourceRect.Bottom > FBitmap.Height then
      OffsetRect(SourceRect, 0, FBitmap.Height - SourceRect.Bottom);

    SourceLeft := SourceRect.Left;
    SourceTop := SourceRect.Top;
    SourceWidth := Max(1.0, SourceRect.Width);
    SourceHeight := Max(1.0, SourceRect.Height);
  end;

  SafeLeft := FBitmap.Width * 0.05;
  SafeTop := FBitmap.Height * 0.05;
  SafeRight := FBitmap.Width * 0.95;
  SafeBottom := FBitmap.Height * 0.95;

  GuideRect := Rect(MapX(SafeLeft), MapY(SafeTop), MapX(SafeRight), MapY(SafeBottom));
  ClipState := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle, DestRect.Left, DestRect.Top, DestRect.Right, DestRect.Bottom);
    DrawGuideRectangle(8, clBlack);
    DrawGuideRectangle(5, RGB(0, 255, 96));
  finally
    RestoreDC(Canvas.Handle, ClipState);
  end;
end;

procedure TVideoMinerVideoSurface.DrawSeekHoverPreview(Canvas: TCanvas);
var
  BorderRect: TRect;
  DrawRect: TRect;
  PreviewHeight: Integer;
  PreviewWidth: Integer;
  SeekBarTop: Integer;
begin
  if (not FSeekPreviewVisible) or (FSeekPreviewBitmap = nil) or
     (FSeekPreviewBitmap.Width <= 0) or (FSeekPreviewBitmap.Height <= 0) then
    Exit;

  PreviewWidth := Min(SEEK_PREVIEW_WIDTH, Max(80, ClientWidth - SEEK_PREVIEW_MARGIN * 2 - 4));
  PreviewHeight := Max(1, Round(PreviewWidth * FSeekPreviewBitmap.Height /
    Max(1, FSeekPreviewBitmap.Width)));
  if PreviewHeight > 120 then
  begin
    PreviewHeight := 120;
    PreviewWidth := Max(1, Round(PreviewHeight * FSeekPreviewBitmap.Width /
      Max(1, FSeekPreviewBitmap.Height)));
  end;

  BorderRect := Rect(FSeekPreviewAnchor.X - PreviewWidth div 2 - 2, 0,
    FSeekPreviewAnchor.X - PreviewWidth div 2 + PreviewWidth + 2, 0);
  if BorderRect.Left < SEEK_PREVIEW_MARGIN then
    OffsetRect(BorderRect, SEEK_PREVIEW_MARGIN - BorderRect.Left, 0)
  else if BorderRect.Right > ClientWidth - SEEK_PREVIEW_MARGIN then
    OffsetRect(BorderRect, ClientWidth - SEEK_PREVIEW_MARGIN - BorderRect.Right, 0);

  SeekBarTop := ClientHeight;
  if FSeekBar <> nil then
    SeekBarTop := FSeekBar.BoundsRect.Top;
  BorderRect.Top := Max(SEEK_PREVIEW_MARGIN, SeekBarTop - PreviewHeight -
    SEEK_PREVIEW_MARGIN - 4);
  BorderRect.Bottom := BorderRect.Top + PreviewHeight + 4;
  DrawRect := Rect(BorderRect.Left + 2, BorderRect.Top + 2,
    BorderRect.Right - 2, BorderRect.Bottom - 2);

  Canvas.Brush.Color := clBlack;
  Canvas.FillRect(BorderRect);
  Canvas.StretchDraw(DrawRect, FSeekPreviewBitmap);
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := $00F0A040;
  Canvas.Pen.Width := 2;
  Canvas.Rectangle(BorderRect);
  Canvas.Brush.Style := bsSolid;
end;

procedure TVideoMinerVideoSurface.DrawMinimalSeekBarFallback(Canvas: TCanvas);
var
  FilledRect: TRect;
  HoverMs: Integer;
  HoverRatio: Double;
  HoverX: Integer;
  KnobRadius: Integer;
  KnobX: Integer;
  KnobY: Integer;
  MaxMs: Integer;
  PositionMs: Integer;
  PositionRatio: Double;
  TrackRect: TRect;
begin
  if (FSeekBar = nil) or (not FSeekBarVisible) then
    Exit;

  FSeekBar.UpdateLayout(SeekBarLayoutRect);
  TrackRect := FSeekBar.CurrentTrackRect;
  if TrackRect.IsEmpty then
    Exit;

  MaxMs := FSeekBar.MaxMs;
  if MaxMs <= 0 then
    Exit;

  PositionMs := FSeekBar.CurrentDisplayPositionMs;
  PositionRatio := Max(0.0, Min(1.0, PositionMs / MaxMs));
  KnobX := TrackRect.Left + Round(TrackRect.Width * PositionRatio);
  KnobY := TrackRect.Top + TrackRect.Height div 2;

  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := clBlack;
  Canvas.RoundRect(TrackRect.Left - 2, TrackRect.Top - 4,
    TrackRect.Right + 2, TrackRect.Bottom + 4, TrackRect.Height + 6,
    TrackRect.Height + 6);
  Canvas.Brush.Color := $00505050;
  Canvas.RoundRect(TrackRect.Left, TrackRect.Top, TrackRect.Right,
    TrackRect.Bottom, TrackRect.Height, TrackRect.Height);

  FilledRect := TrackRect;
  FilledRect.Right := Max(FilledRect.Left + TrackRect.Height, KnobX);
  Canvas.Brush.Color := SEEK_FALLBACK_ACCENT_COLOR;
  Canvas.RoundRect(FilledRect.Left, FilledRect.Top, FilledRect.Right,
    FilledRect.Bottom, TrackRect.Height, TrackRect.Height);

  HoverMs := FSeekBarHoverPositionMs;
  if (HoverMs < 0) and FSeekPreviewVisible then
    HoverMs := FSeekPreviewPositionMs;
  if (HoverMs >= 0) and (HoverMs <= MaxMs) then
  begin
    HoverRatio := Max(0.0, Min(1.0, HoverMs / MaxMs));
    HoverX := TrackRect.Left + Round(TrackRect.Width * HoverRatio);
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 1;
    Canvas.Pen.Color := clWhite;
    Canvas.MoveTo(HoverX, TrackRect.Top - 8);
    Canvas.LineTo(HoverX, TrackRect.Bottom + 12);
    Canvas.Pen.Style := psClear;
  end;

  KnobRadius := 9;
  Canvas.Brush.Color := SEEK_FALLBACK_ACCENT_COLOR;
  Canvas.Ellipse(KnobX - KnobRadius, KnobY - KnobRadius,
    KnobX + KnobRadius, KnobY + KnobRadius);
  Canvas.Brush.Color := $00FFD18A;
  Canvas.Ellipse(KnobX - 4, KnobY - 4, KnobX + 4, KnobY + 4);

  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
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
var
  GroupBounds: TRect;
begin
  UpdateCenterOverlayButtonLayouts;
  GroupBounds := CenterOverlayGroupBounds;
  Result := (not GroupBounds.IsEmpty) and PtInRect(GroupBounds, Point);
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
var
  HitRect: TRect;
  TrackHitMs: Integer;
begin
  if FSeekBar <> nil then
    FSeekBar.UpdateLayout(SeekBarLayoutRect);
  Result := (FSeekBar <> nil) and
    (FSeekBar.BoundsHitTest(Point) or
     FSeekBar.HoverPositionFromPoint(Point, TrackHitMs));
  if (not Result) and (FSeekBar <> nil) then
  begin
    HitRect := FSeekBar.BoundsRect;
    InflateRect(HitRect, 16, 30);
    Result := PtInRect(HitRect, Point);
  end;
end;

function TVideoMinerVideoSurface.HitSeekBarKeepAlive(
  const Point: TPoint): Boolean;
var
  HitRect: TRect;
begin
  Result := False;
  if FSeekBar = nil then
    Exit;

  FSeekBar.UpdateLayout(SeekBarLayoutRect);
  HitRect := FSeekBar.BoundsRect;
  if HitRect.IsEmpty then
    Exit;

  InflateRect(HitRect, 28, 54);
  HitRect.Left := Max(0, HitRect.Left);
  HitRect.Right := Min(ClientWidth, HitRect.Right);
  HitRect.Top := Max(0, HitRect.Top);
  HitRect.Bottom := Min(ClientHeight, HitRect.Bottom);
  Result := PtInRect(HitRect, Point);
end;

function TVideoMinerVideoSurface.ChapterMarkerToleranceMs(MaxMs,
  PixelTolerance: Integer): Integer;
var
  TrackRect: TRect;
begin
  Result := 0;
  if (FSeekBar = nil) or (MaxMs <= 0) or (PixelTolerance <= 0) then
    Exit;

  FSeekBar.UpdateLayout(SeekBarLayoutRect);
  TrackRect := FSeekBar.CurrentTrackRect;
  if TrackRect.Width <= 0 then
    Exit;

  Result := Ceil(Int64(MaxMs) * PixelTolerance / TrackRect.Width);
  Result := Max(1, Result);
end;

function TVideoMinerVideoSurface.SeekBarLayoutRect: TRect;
begin
  Result := ClientRect;
end;

procedure TVideoMinerVideoSurface.UpdateCenterOverlayButtonLayouts;
var
  PreviewRect: TRect;
begin
  PreviewRect := FitRect;
  if PreviewRect.IsEmpty then
    Exit;

  FPreviewRect := PreviewRect;
  if FFirstFrameButton <> nil then
    FFirstFrameButton.UpdateLayout(PreviewRect);
  if FSkipBackwardButton <> nil then
    FSkipBackwardButton.UpdateLayout(PreviewRect);
  if FPlayPauseButton <> nil then
    FPlayPauseButton.UpdateLayout(PreviewRect);
  if FSkipForwardButton <> nil then
    FSkipForwardButton.UpdateLayout(PreviewRect);
  if FLastFrameButton <> nil then
    FLastFrameButton.UpdateLayout(PreviewRect);
end;

function TVideoMinerVideoSurface.CenterOverlayGroupBounds: TRect;
begin
  Result := TRect.Empty;
  if (FFirstFrameButton <> nil) and (not FFirstFrameButton.BoundsRect.IsEmpty) then
    Result := FFirstFrameButton.BoundsRect;
  if (FSkipBackwardButton <> nil) and (not FSkipBackwardButton.BoundsRect.IsEmpty) then
    UnionRect(Result, Result, FSkipBackwardButton.BoundsRect);
  if (FPlayPauseButton <> nil) and (not FPlayPauseButton.BoundsRect.IsEmpty) then
    UnionRect(Result, Result, FPlayPauseButton.BoundsRect);
  if (FSkipForwardButton <> nil) and (not FSkipForwardButton.BoundsRect.IsEmpty) then
    UnionRect(Result, Result, FSkipForwardButton.BoundsRect);
  if (FLastFrameButton <> nil) and (not FLastFrameButton.BoundsRect.IsEmpty) then
    UnionRect(Result, Result, FLastFrameButton.BoundsRect);
  if not Result.IsEmpty then
    InflateRect(Result, 10, 8);
end;

procedure TVideoMinerVideoSurface.UpdateD3DSeekBarOverlayState;
var
  ChapterIndex: Integer;
  State: TD3D11SeekBarOverlayState;
  TrackRect: TRect;
begin
  FillChar(State, SizeOf(State), 0);
  if (FPreviousFileButton <> nil) and FPreviousFileButton.Visible and
     (not FSafeAreaVisible) and (not FLoadingActive) then
  begin
    FPreviousFileButton.UpdateLayout(ClientRect);
    State.PreviousFileVisible := not FPreviousFileButton.BoundsRect.IsEmpty;
    State.PreviousFileButton := FPreviousFileButton.BoundsRect;
  end;
  if (FNextFileButton <> nil) and FNextFileButton.Visible and
     (not FSafeAreaVisible) and (not FLoadingActive) then
  begin
    FNextFileButton.UpdateLayout(ClientRect);
    State.NextFileVisible := not FNextFileButton.BoundsRect.IsEmpty;
    State.NextFileButton := FNextFileButton.BoundsRect;
  end;
  if FOverlayVisible and (not FSeekPreviewVisible) and
     (not FSafeAreaVisible) and (not FLoadingActive) then
  begin
    UpdateCenterOverlayButtonLayouts;
    State.TransportVisible := True;
    State.TransportPlaying := FPlaybackActive;
    State.TransportBounds := CenterOverlayGroupBounds;
    if FFirstFrameButton <> nil then
      State.FirstButton := FFirstFrameButton.BoundsRect;
    if FSkipBackwardButton <> nil then
      State.SkipBackwardButton := FSkipBackwardButton.BoundsRect;
    if FPlayPauseButton <> nil then
      State.PlayPauseButton := FPlayPauseButton.BoundsRect;
    if FSkipForwardButton <> nil then
      State.SkipForwardButton := FSkipForwardButton.BoundsRect;
    if FLastFrameButton <> nil then
      State.LastButton := FLastFrameButton.BoundsRect;
  end;
  if (FSeekBar <> nil) and (FSeekBarVisible or FSeekBar.Dragging) and
     (not FSafeAreaVisible) and
     (not FLoadingActive) then
  begin
    FSeekBar.UpdateLayout(SeekBarLayoutRect);
    TrackRect := FSeekBar.CurrentTrackRect;
    State.Visible := (FSeekBar.MaxMs > 0) and (not FSeekBar.BoundsRect.IsEmpty) and
      (not TrackRect.IsEmpty);
    State.Bounds := FSeekBar.BoundsRect;
    State.Track := TrackRect;
    State.PositionMs := FSeekBar.CurrentDisplayPositionMs;
    State.MaxMs := FSeekBar.MaxMs;
    State.HoverPositionMs := FSeekBarHoverPositionMs;
    State.Dragging := FSeekBar.Dragging;
    State.CheckEnabled := FSeekBar.CheckEnabled;
    State.FrameStepMs := FSeekBar.FrameStepMs;
    State.VolumePercent := FSeekBar.VolumePercent;
    State.Muted := FSeekBar.Muted;
    State.VolumeHovered := FSeekBar.VolumeHovered;
    State.VolumeDragging := FSeekBar.VolumeDragging;
    State.MuteHovered := FSeekBar.MuteButtonHovered;
    State.MutePressed := FSeekBar.MuteButtonPressed;
    State.PlaybackRateText := FSeekBar.PlaybackRateText;
    State.PlaybackRateHovered := FSeekBar.PlaybackRateButtonHovered;
    State.PlaybackRatePressed := FSeekBar.PlaybackRateButtonPressed;
    State.EndActionText := FSeekBar.EndActionText;
    State.EndActionHovered := FSeekBar.EndActionButtonHovered;
    State.EndActionPressed := FSeekBar.EndActionButtonPressed;
    State.CheckHovered := FSeekBar.CheckButtonHovered;
    State.CheckPressed := FSeekBar.CheckButtonPressed;
    State.AddChapterHovered := FSeekBar.AddChapterButtonHovered;
    State.AddChapterPressed := FSeekBar.AddChapterButtonPressed;
    State.DeleteChapterHovered := FSeekBar.DeleteChapterButtonHovered;
    State.DeleteChapterPressed := FSeekBar.DeleteChapterButtonPressed;
    State.FullScreen := FSeekBar.FullScreen;
    State.FullScreenHovered := FSeekBar.FullScreenButtonHovered;
    State.FullScreenPressed := FSeekBar.FullScreenButtonPressed;
    SetLength(State.Chapters, Length(FSeekBar.Chapters));
    for ChapterIndex := 0 to High(State.Chapters) do
    begin
      State.Chapters[ChapterIndex].PositionMs := FSeekBar.Chapters[ChapterIndex].PositionMs;
      State.Chapters[ChapterIndex].Severity := Ord(FSeekBar.Chapters[ChapterIndex].Severity);
    end;
  end;
  SetNv12TextureD3DSeekBarOverlay(State);
end;

procedure TVideoMinerVideoSurface.UpdateD3DVideoZoomState;
var
  SourceHeight: Integer;
  SourceRect: TRect;
  SourceWidth: Integer;
  State: TD3D11VideoZoomState;
begin
  State := Default(TD3D11VideoZoomState);
  if (FBitmap = nil) or (FBitmap.Width <= 0) or (FBitmap.Height <= 0) or
     (FZoomScale <= MIN_ZOOM) then
  begin
    SetNv12TextureD3DVideoZoom(State);
    Exit;
  end;

  ClampZoomCenter;
  if FZoomScale <= MIN_ZOOM then
  begin
    SetNv12TextureD3DVideoZoom(State);
    Exit;
  end;

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

  State.Active := True;
  State.Left := SourceRect.Left / FBitmap.Width;
  State.Top := SourceRect.Top / FBitmap.Height;
  State.Width := Max(1, SourceRect.Width) / FBitmap.Width;
  State.Height := Max(1, SourceRect.Height) / FBitmap.Height;
  SetNv12TextureD3DVideoZoom(State);
end;

function TVideoMinerVideoSurface.RefreshD3DFramePresentation: Boolean;
begin
  Result := False;
  if (FLastD3DFramePresentedTick = 0) or
     (not CanUseD3DCompositedFramePresentation) then
    Exit;

  SetNv12TextureProbeTargetWindow(Handle, ClientWidth, ClientHeight);
  UpdateD3DVideoZoomState;
  UpdateD3DSeekBarOverlayState;
  Result := PresentCurrentNv12TextureFrame;
  if Result then
    MarkD3DFramePresented;
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
    not HitAnyOverlayButton(Point) and
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
  LogD3DFramePresentationState('overlay_visible', True);
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
  UpdateD3DSeekBarOverlayState;
  RefreshD3DFramePresentation;
  InvalidateAllOverlayControls;
end;

procedure TVideoMinerVideoSurface.SetBossMode(Value: Boolean);
begin
  if FBossMode = Value then
    Exit;

  FBossMode := Value;
  if Value then
    FBossHelpPageIndex := 0;
  CancelPendingSurfaceClick;
  if FBossGestureDetector <> nil then
    FBossGestureDetector.Reset;
  if Value then
  begin
    SetOverlayVisible(False);
    SetSeekBarVisibleFrom('boss_mode_enter', False);
    if FPreviousFileButton <> nil then
      FPreviousFileButton.Visible := False;
    if FNextFileButton <> nil then
      FNextFileButton.Visible := False;
  end;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.SetSeekBarVisible(Value: Boolean);
var
  RequestSource: string;
begin
  RequestSource := FSeekBarVisibleRequestSource;
  if RequestSource = '' then
    RequestSource := 'direct';
  if FSeekBarVisible = Value then
    Exit;

  WriteVideoMinerD3DLog(Format(
    'seekbar_visible_change source=%s value=%s playback=%s preview=%s overlay=%s alpha=%s ' +
    'loading=%s zoom=%.3f reason_before=%s',
    [RequestSource, BoolToStr(Value, True), BoolToStr(FPlaybackActive, True),
     BoolToStr(FSeekPreviewVisible, True), BoolToStr(FOverlayVisible, True),
     BoolToStr(FSourceHasAlpha, True), BoolToStr(FLoadingActive, True),
     FZoomScale, D3DFramePresentationBlockReason]));
  FSeekBarVisible := Value;
  LogD3DFramePresentationState('seek_bar_visible', True);
  if FSeekBar <> nil then
    FSeekBar.Visible := Value;
  if not Value then
  begin
    FSeekBarLastHitTick := 0;
    FSeekBarHoverPositionMs := -1;
    ClearSeekHoverPreview;
    if Assigned(FOnSeekHoverPreviewEnd) then
      FOnSeekHoverPreviewEnd(Self);
  end;
  UpdateD3DSeekBarOverlayState;
  RefreshD3DFramePresentation;
  InvalidateOverlayControl(FSeekBar);
end;

procedure TVideoMinerVideoSurface.SetSeekBarVisibleFrom(const Source: string;
  Value: Boolean);
begin
  FSeekBarVisibleRequestSource := Source;
  try
    SetSeekBarVisible(Value);
  finally
    FSeekBarVisibleRequestSource := '';
  end;
end;

procedure TVideoMinerVideoSurface.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  TogglePositionMs: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FBossMode then
  begin
    CancelPendingSurfaceClick;
    Exit;
  end;

  if Button = mbRight then
  begin
    CancelPendingSurfaceClick;
    if FSeekBar <> nil then
    begin
      FSeekBar.UpdateLayout(SeekBarLayoutRect);
      if FSeekBar.HoverPositionFromPoint(Point(X, Y), TogglePositionMs) and
         Assigned(FOnToggleChapterClick) then
      begin
        FOnToggleChapterClick(Self, TogglePositionMs);
        Exit;
      end;
    end;
    if CanStartSurfaceClick(Point(X, Y)) and Assigned(FOnSurfaceRightClick) then
      FOnSurfaceRightClick(Self);
    Exit;
  end;

  if Button = mbLeft then
  begin
    CancelPendingSurfaceClick;
    if ssDouble in Shift then
    begin
      FSuppressSurfaceClickUp := True;
      Exit;
    end;
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
    SetSeekBarVisibleFrom('mouse_down_hit_seekbar', True);
    ClearSeekHoverPreview;
    if Assigned(FOnSeekHoverPreviewEnd) then
      FOnSeekHoverPreviewEnd(Self);
    if FSeekBar.MouseDown(Point(X, Y)) then
    begin
      FSeekBarHoverPositionMs := FSeekBar.CurrentDisplayPositionMs;
      UpdateD3DSeekBarOverlayState;
      InvalidateOverlayControl(FSeekBar);
    end;
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
  D3DRefreshed: Boolean;
  DestRect: TRect;
  HoverPositionMs: Integer;
  KeepAliveHit: Boolean;
  KeepSeekBarVisible: Boolean;
  MousePoint: TPoint;
  NavOverlayChanged: Boolean;
  NextFileVisible: Boolean;
  PreviousFileVisible: Boolean;
  SeekBarHit: Boolean;
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
      UpdateD3DVideoZoomState;
      D3DRefreshed := RefreshD3DFramePresentation;
      if not D3DRefreshed then
        D3DRefreshed := PresentCurrentBgrx32FrameWithD3D;
      if not D3DRefreshed then
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
  SeekBarHit := HitSeekBar(MousePoint);
  KeepAliveHit := FSeekBarVisible and HitSeekBarKeepAlive(MousePoint);
  if SeekBarHit or KeepAliveHit then
    FSeekBarLastHitTick := GetTickCount64;
  KeepSeekBarVisible := SeekBarHit or KeepAliveHit or
    ((FSeekBar <> nil) and FSeekBar.Dragging) or
    (FSeekBarVisible and (FSeekBarLastHitTick > 0) and
      (GetTickCount64 - FSeekBarLastHitTick <= 350));
  SetSeekBarVisibleFrom('mouse_move_keepalive', KeepSeekBarVisible);

  NavOverlayChanged := False;
  if FPreviousFileButton <> nil then
  begin
    PreviousFileVisible := HitPreviousFileButton(MousePoint);
    if FPreviousFileButton.Visible <> PreviousFileVisible then
    begin
      FPreviousFileButton.Visible := PreviousFileVisible;
      NavOverlayChanged := True;
    end;
    if FPreviousFileButton.MouseMove(MousePoint) then
    begin
      InvalidateOverlayControl(FPreviousFileButton);
      NavOverlayChanged := True;
    end;
  end;
  if FNextFileButton <> nil then
  begin
    NextFileVisible := HitNextFileButton(MousePoint);
    if FNextFileButton.Visible <> NextFileVisible then
    begin
      FNextFileButton.Visible := NextFileVisible;
      NavOverlayChanged := True;
    end;
    if FNextFileButton.MouseMove(MousePoint) then
    begin
      InvalidateOverlayControl(FNextFileButton);
      NavOverlayChanged := True;
    end;
  end;
  if NavOverlayChanged then
  begin
    UpdateD3DSeekBarOverlayState;
    RefreshD3DFramePresentation;
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

  if FSeekBarVisible and (FSeekBar <> nil) then
  begin
    FSeekBar.UpdateLayout(SeekBarLayoutRect);
    if FSeekBar.HoverPositionFromPoint(MousePoint, HoverPositionMs) then
      FSeekBarHoverPositionMs := HoverPositionMs
    else if not FSeekBar.Dragging then
      FSeekBarHoverPositionMs := -1;
    if FSeekBar.MouseMove(MousePoint) then
    begin
      if FSeekBar.Dragging then
        FSeekBarHoverPositionMs := FSeekBar.CurrentDisplayPositionMs;
      UpdateD3DSeekBarOverlayState;
      RefreshD3DFramePresentation;
      InvalidateOverlayControl(FSeekBar);
    end
    else
    begin
      UpdateD3DSeekBarOverlayState;
      RefreshD3DFramePresentation;
    end;
  end;

  if ((not FPlaybackActive) and FSeekBarVisible and (FSeekBar <> nil) and
      (not FSeekBar.Dragging) and
      FSeekBar.HoverPositionFromPoint(MousePoint, HoverPositionMs)) then
  begin
    if HIDE_LEGACY_SEEK_BAR_PAINT and CanUseD3DCompositedFramePresentation and
       (Nv12TextureD3DFramePresented or D3DFrameRecentlyPresented) then
    begin
      if FSeekPreviewVisible and Assigned(FOnSeekHoverPreviewEnd) then
        FOnSeekHoverPreviewEnd(Self);
    end
    else if Assigned(FOnSeekHoverPreview) then
      FOnSeekHoverPreview(Self, HoverPositionMs, MousePoint);
  end
  else if (not KeepSeekBarVisible) and Assigned(FOnSeekHoverPreviewEnd) then
    FOnSeekHoverPreviewEnd(Self);
end;

procedure TVideoMinerVideoSurface.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  OverlayHandled: Boolean;
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

  if (Button = mbLeft) and FSuppressSurfaceClickUp then
  begin
    FSuppressSurfaceClickUp := False;
    FSurfaceClickArmed := False;
    FPanning := False;
    MouseCapture := False;
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
    begin
      if not FSeekBar.HoverPositionFromPoint(Point(X, Y), FSeekBarHoverPositionMs) then
        FSeekBarHoverPositionMs := -1;
      UpdateD3DSeekBarOverlayState;
      InvalidateOverlayControl(FSeekBar);
    end;
    MouseCapture := False;
    SetSeekBarVisibleFrom('mouse_up_after_seekbar', HitSeekBar(Point(X, Y)));
  end;

  if (Button = mbLeft) and FOverlayVisible then
  begin
    OverlayHandled := False;
    if (FFirstFrameButton <> nil) and FFirstFrameButton.MouseUp(Point(X, Y)) then
    begin
      InvalidateOverlayControl(FFirstFrameButton);
      OverlayHandled := True;
    end;
    if (FSkipBackwardButton <> nil) and FSkipBackwardButton.MouseUp(Point(X, Y)) then
    begin
      InvalidateOverlayControl(FSkipBackwardButton);
      OverlayHandled := True;
    end;
    if (FPlayPauseButton <> nil) and FPlayPauseButton.MouseUp(Point(X, Y)) then
    begin
      InvalidateOverlayControl(FPlayPauseButton);
      OverlayHandled := True;
    end;
    if (FSkipForwardButton <> nil) and FSkipForwardButton.MouseUp(Point(X, Y)) then
    begin
      InvalidateOverlayControl(FSkipForwardButton);
      OverlayHandled := True;
    end;
    if (FLastFrameButton <> nil) and FLastFrameButton.MouseUp(Point(X, Y)) then
    begin
      InvalidateOverlayControl(FLastFrameButton);
      OverlayHandled := True;
    end;
    if OverlayHandled then
    begin
      FSurfaceClickArmed := False;
      Exit;
    end;
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
  D3DRefreshed: Boolean;
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
    FSeekBar.UpdateLayout(SeekBarLayoutRect);
    if FSeekBar.BoundsHitTest(LocalPoint) then
    begin
      SetSeekBarVisibleFrom('mouse_wheel_seekbar', True);
      if FSeekBar.CheckEnabled or (not FPlaybackActive) then
        StepMs := FSeekWheelFrameStepMs
      else
        StepMs := SEEK_WHEEL_STEP_MS;
      SeekPositionMs := FSeekBar.WheelPosition(WheelDelta, StepMs);
      if SeekPositionMs < FSeekBar.CurrentDisplayPositionMs then
      begin
        FSeekBar.SetProgress(SeekPositionMs, FSeekBar.MaxMs);
        FSeekBarHoverPositionMs := SeekPositionMs;
        UpdateD3DSeekBarOverlayState;
        RefreshD3DFramePresentation;
        InvalidateOverlayControl(FSeekBar);
      end;
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
    UpdateD3DVideoZoomState;
    D3DRefreshed := RefreshD3DFramePresentation;
    if not D3DRefreshed then
      D3DRefreshed := PresentCurrentBgrx32FrameWithD3D;
    if D3DRefreshed then
      FZoomFrameRefreshNeeded := False
    else
    begin
      FZoomFrameRefreshNeeded := True;
      Invalidate;
    end;
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

  UpdateD3DVideoZoomState;
  D3DRefreshed := RefreshD3DFramePresentation;
  if not D3DRefreshed then
    D3DRefreshed := PresentCurrentBgrx32FrameWithD3D;
  if D3DRefreshed then
    FZoomFrameRefreshNeeded := False
  else
  begin
    FZoomFrameRefreshNeeded := True;
    Invalidate;
  end;
  Result := True;
end;

procedure TVideoMinerVideoSurface.Resize;
begin
  inherited Resize;
  if (csDestroying in ComponentState) or (ClientWidth <= 0) or
     (ClientHeight <= 0) or (not HandleAllocated) then
    Exit;

  if FLiveResizeActive then
  begin
    ClearNv12TextureD3DFramePresented;
    FLastD3DFramePresentedTick := 0;
    Invalidate;
    Exit;
  end;

  SetNv12TextureProbeTargetWindow(Handle, ClientWidth, ClientHeight);
  UpdateD3DVideoZoomState;
  UpdateD3DSeekBarOverlayState;
  ClearNv12TextureD3DFramePresented;
  FLastD3DFramePresentedTick := 0;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.Paint;
var
{$IFDEF DEBUG}
  PaintWatch: TStopwatch;
{$ENDIF}
  DrawCanvas: TCanvas;
  DestRect: TRect;
  CenterOverlayDrawnByD3D: Boolean;
  D3DFrameCurrent: Boolean;
  PaintLegacyCenterOverlay: Boolean;
  SeekBarCompactStyle: Boolean;
  UsePaintBuffer: Boolean;
begin
{$IFDEF DEBUG}
  PaintWatch := TStopwatch.StartNew;
{$ENDIF}
  if (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;

  if FBossMode then
  begin
    DrawVideoMinerBossOverlay(Canvas, ClientRect, FBossHelpPageIndex, FBossExitButtonRect);
    Exit;
  end;

  D3DFrameCurrent := Nv12TextureD3DFramePresented and CanUseD3DCompositedFramePresentation;
  CenterOverlayDrawnByD3D := D3DFrameCurrent;
  if (not FLiveResizeActive) and (not D3DFrameCurrent) and
     CanUseD3DCompositedFramePresentation and
     (FOverlayVisible or FSeekBarVisible or
      ((FSeekBar <> nil) and FSeekBar.Dragging) or
      ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible) or
      ((FNextFileButton <> nil) and FNextFileButton.Visible)) then
  begin
    if FLastD3DFramePresentedTick > 0 then
      D3DFrameCurrent := RefreshD3DFramePresentation;
    if (not D3DFrameCurrent) and (FBitmap.Width > 0) and
       (FBitmap.Height > 0) then
      D3DFrameCurrent := PresentCurrentBgrx32FrameWithD3D;
    CenterOverlayDrawnByD3D := D3DFrameCurrent;
  end;
  UsePaintBuffer := FOverlayVisible or FSeekBarVisible or FSeekPreviewVisible or
    ((FPreviousFileButton <> nil) and FPreviousFileButton.Visible) or
    ((FNextFileButton <> nil) and FNextFileButton.Visible);
  if D3DFrameCurrent then
  begin
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'paint_skip_d3d_frame client_w=%d client_h=%d surface_ready=%s d3d_current=%s d3d_recent=%s paint_ms=%.3f',
      [ClientWidth, ClientHeight, BoolToStr(CanUseD3DCompositedFramePresentation, True),
       BoolToStr(Nv12TextureD3DFramePresented, True),
       BoolToStr(D3DFrameRecentlyPresented, True),
       PaintWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
    Exit;
  end;
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
    if FSeekBar <> nil then
    begin
      SeekBarCompactStyle := (not FSourceHasAlpha) and
        (FPlaybackActive or FForceCompactSeekBarPaint or HIDE_LEGACY_SEEK_BAR_PAINT);
      FSeekBar.CompactPlaybackStyle := SeekBarCompactStyle;
      FSeekBar.UpdateLayout(SeekBarLayoutRect);
      if FSeekBarVisible and (not FLoadingActive) then
      begin
        if SeekBarCompactStyle then
          DrawMinimalSeekBarFallback(DrawCanvas)
        else
          FSeekBar.Paint(DrawCanvas);
      end;
    end;
    DrawSeekHoverPreview(DrawCanvas);
    DrawLoadingIndicator(DrawCanvas);
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
  DrawSafeAreaGuide(DrawCanvas, DestRect);
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
  begin
    SeekBarCompactStyle := (not FSourceHasAlpha) and
      (FPlaybackActive or FForceCompactSeekBarPaint or HIDE_LEGACY_SEEK_BAR_PAINT);
    FSeekBar.CompactPlaybackStyle := SeekBarCompactStyle;
    FSeekBar.UpdateLayout(SeekBarLayoutRect);
  end;

  if (FPreviousFileButton <> nil) and FPreviousFileButton.Visible then
    FPreviousFileButton.Paint(DrawCanvas);
  PaintLegacyCenterOverlay := FOverlayVisible and
    ((not HIDE_LEGACY_CENTER_OVERLAY_PAINT) or (not CenterOverlayDrawnByD3D));
  if PaintLegacyCenterOverlay and (FFirstFrameButton <> nil) then
  begin
    FFirstFrameButton.Paint(DrawCanvas);
  end;
  if PaintLegacyCenterOverlay and (FSkipBackwardButton <> nil) then
  begin
    FSkipBackwardButton.Paint(DrawCanvas);
  end;
  if PaintLegacyCenterOverlay and (FPlayPauseButton <> nil) then
  begin
    FPlayPauseButton.Paint(DrawCanvas);
  end;
  if PaintLegacyCenterOverlay and (FSkipForwardButton <> nil) then
  begin
    FSkipForwardButton.Paint(DrawCanvas);
  end;
  if PaintLegacyCenterOverlay and (FLastFrameButton <> nil) then
  begin
    FLastFrameButton.Paint(DrawCanvas);
  end;
  if (FNextFileButton <> nil) and FNextFileButton.Visible then
    FNextFileButton.Paint(DrawCanvas);
  if FSeekBarVisible and (FSeekBar <> nil) then
  begin
    SeekBarCompactStyle := (not FSourceHasAlpha) and
      (FPlaybackActive or FForceCompactSeekBarPaint or HIDE_LEGACY_SEEK_BAR_PAINT);
    FSeekBar.CompactPlaybackStyle := SeekBarCompactStyle;
    LogSeekBarPaintState(SeekBarCompactStyle, D3DFrameCurrent);
    if (not FLoadingActive) and SeekBarCompactStyle then
    begin
      DrawMinimalSeekBarFallback(DrawCanvas);
    end
    else if not FLoadingActive then
    begin
      FSeekBar.Paint(DrawCanvas);
    end;
  end;
  DrawSeekHoverPreview(DrawCanvas);
  DrawLoadingIndicator(DrawCanvas);
  if UsePaintBuffer then
    Canvas.Draw(0, 0, FPaintBuffer);
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'paint width=%d height=%d client_w=%d client_h=%d dest=%d,%d,%d,%d buffered=%s paint_ms=%.3f',
    [FBitmap.Width, FBitmap.Height, ClientWidth, ClientHeight,
     DestRect.Left, DestRect.Top, DestRect.Right, DestRect.Bottom,
     BoolToStr(UsePaintBuffer, True), PaintWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

procedure TVideoMinerVideoSurface.DrawLoadingIndicator(Canvas: TCanvas);
var
  DotCount: Integer;
  Text: string;
  TextSize: TSize;
begin
  if not FLoadingActive then
    Exit;

  DotCount := FLoadingTick mod 4;
  Text := 'Now loading' + StringOfChar('.', DotCount);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 12;
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  Canvas.Brush.Style := bsClear;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  TextSize := Canvas.TextExtent(Text);
  Canvas.TextOut((ClientWidth - TextSize.cx) div 2,
    (ClientHeight - TextSize.cy) div 2, Text);
  Canvas.Brush.Style := bsSolid;

  {
  円形インジケータ案は、同期ロード中に UI タイマーが止まりやすいため保留する。
  復活させる場合はロード処理の worker 化と合わせて使う。

  const
    COLORS: array[0..3] of TColor = ($0024B6FF, $0024E8A7, $00F0D24A, $00D88CFF);
  var
    Angle1: Double;
    Angle2: Double;
    Center: TPoint;
    ColorIndex: Integer;
    I: Integer;
    Radius: Integer;
    SegmentIndex: Integer;
    StartSegment: Integer;
    X1: Integer;
    X2: Integer;
    Y1: Integer;
    Y2: Integer;
  begin
    Radius := Max(18, Min(36, Min(ClientWidth, ClientHeight) div 12));
    Center := Point(ClientWidth div 2, ClientHeight div 2);
    StartSegment := FLoadingTick mod LOADING_SEGMENTS;
    ColorIndex := (FLoadingTick div LOADING_LAP_TICKS) mod Length(COLORS);
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := Max(4, Radius div 5);
    Canvas.Pen.Color := COLORS[ColorIndex];
    Canvas.Brush.Style := bsClear;
    for I := LOADING_GAP_SEGMENTS to LOADING_SEGMENTS - 1 do
    begin
      SegmentIndex := (StartSegment + I) mod LOADING_SEGMENTS;
      Angle1 := (SegmentIndex / LOADING_SEGMENTS * 2 * Pi) - Pi / 2;
      Angle2 := ((SegmentIndex + 0.72) / LOADING_SEGMENTS * 2 * Pi) - Pi / 2;
      X1 := Center.X + Round(Cos(Angle1) * Radius);
      Y1 := Center.Y + Round(Sin(Angle1) * Radius);
      X2 := Center.X + Round(Cos(Angle2) * Radius);
      Y2 := Center.Y + Round(Sin(Angle2) * Radius);
      Canvas.MoveTo(X1, Y1);
      Canvas.LineTo(X2, Y2);
    end;
    Canvas.Brush.Style := bsSolid;
  end;
  }
end;

procedure TVideoMinerVideoSurface.EndLoadingIndicator;
begin
  if not FLoadingActive then
    Exit;

  FLoadingActive := False;
  if FLoadingTimer <> nil then
    FLoadingTimer.Enabled := False;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.EndLiveResize;
begin
  if not FLiveResizeActive then
    Exit;

  FLiveResizeActive := False;
  SetNv12TextureProbeTargetWindow(Handle, ClientWidth, ClientHeight);
  UpdateD3DVideoZoomState;
  UpdateD3DSeekBarOverlayState;
  ClearNv12TextureD3DFramePresented;
  FLastD3DFramePresentedTick := 0;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.Present;
begin
  ClearNv12TextureD3DFramePresented;
  FLastD3DFramePresentedTick := 0;
  FAlphaCompositeDirty := True;
  Invalidate;
end;

procedure TVideoMinerVideoSurface.PresentImmediate;
begin
  ClearNv12TextureD3DFramePresented;
  FLastD3DFramePresentedTick := 0;
  FAlphaCompositeDirty := True;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'surface_present_immediate bitmap=%dx%d client=%dx%d visible=%s handle=%d',
    [FBitmap.Width, FBitmap.Height, ClientWidth, ClientHeight,
     BoolToStr(Visible, True), Handle]));
{$ENDIF}
  Repaint;
end;

procedure TVideoMinerVideoSurface.MarkD3DFramePresented;
begin
  FLastD3DFramePresentedTick := GetTickCount64;
end;

procedure TVideoMinerVideoSurface.PresentImmediateAsPlaybackFallback;
var
  D3DFrameRecentlyPresented: Boolean;
begin
  D3DFrameRecentlyPresented := Self.D3DFrameRecentlyPresented;
  if (Nv12TextureD3DFramePresented or D3DFrameRecentlyPresented) and
     (not FSourceHasAlpha) and FPlaybackActive and FSeekBarVisible then
  begin
    UpdateD3DSeekBarOverlayState;
    WriteVideoMinerD3DLog(Format(
      'surface_present_immediate_playback_fallback_keep_d3d seek_bar=%s playback=%s d3d_current=%s d3d_recent=%s client=%dx%d',
      [BoolToStr(FSeekBarVisible, True), BoolToStr(FPlaybackActive, True),
       BoolToStr(Nv12TextureD3DFramePresented, True),
       BoolToStr(D3DFrameRecentlyPresented, True), ClientWidth, ClientHeight]));
    Exit;
  end;

  FForceCompactSeekBarPaint := True;
  try
    PresentImmediate;
  finally
    FForceCompactSeekBarPaint := False;
  end;
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
  if FPlaybackActive = Value then
    Exit;

  FPlaybackActive := Value;
  LogD3DFramePresentationState('playback_active', True);
  UpdateD3DSeekBarOverlayState;
  if (FPlayPauseButton <> nil) and (FPlayPauseButton.IsPlaying <> Value) then
  begin
    FPlayPauseButton.IsPlaying := Value;
    RefreshD3DFramePresentation;
    Invalidate;
  end;
end;

procedure TVideoMinerVideoSurface.HidePlaybackStartOverlays;
var
  MousePoint: TPoint;
  KeepCenterOverlay: Boolean;
begin
  MousePoint := ScreenToClient(Mouse.CursorPos);
  KeepCenterOverlay := HitAnyOverlayButton(MousePoint);

  ClearSeekHoverPreview;
  if not KeepCenterOverlay then
    SetOverlayVisible(False)
  else
  begin
    UpdateD3DSeekBarOverlayState;
    RefreshD3DFramePresentation;
  end;
  SetSeekBarVisibleFrom('hide_playback_start_overlays', False);
  UpdateD3DSeekBarOverlayState;
end;

procedure TVideoMinerVideoSurface.SetSeekProgress(PositionMs, MaxMs: Integer);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.SetProgress(PositionMs, MaxMs);
    if FSeekBarVisible then
    begin
      if FSeekBar.Dragging then
        FSeekBarHoverPositionMs := FSeekBar.CurrentDisplayPositionMs;
      UpdateD3DSeekBarOverlayState;
      RefreshD3DFramePresentation;
      InvalidateOverlayControl(FSeekBar);
    end;
  end;
end;

procedure TVideoMinerVideoSurface.SetSeekHoverPreview(Bitmap: TBitmap;
  PositionMs: Integer; const AnchorPoint: TPoint);
begin
  if (Bitmap = nil) or (Bitmap.Width <= 0) or (Bitmap.Height <= 0) or
     (FSeekPreviewBitmap = nil) then
  begin
    ClearSeekHoverPreview;
    Exit;
  end;

  FSeekPreviewBitmap.Assign(Bitmap);
  FSeekPreviewPositionMs := PositionMs;
  FSeekPreviewAnchor := AnchorPoint;
  FSeekPreviewVisible := True;
  WriteVideoMinerD3DLog(Format(
    'seek_preview_visible_change value=True position_ms=%d anchor=%d,%d seek_bar=%s ' +
    'playback=%s alpha=%s reason_before=%s',
    [PositionMs, AnchorPoint.X, AnchorPoint.Y, BoolToStr(FSeekBarVisible, True),
     BoolToStr(FPlaybackActive, True), BoolToStr(FSourceHasAlpha, True),
     D3DFramePresentationBlockReason]));
  LogD3DFramePresentationState('seek_preview_show', True);
  Invalidate;
end;

procedure TVideoMinerVideoSurface.ClearSeekHoverPreview;
begin
  if not FSeekPreviewVisible then
    Exit;

  FSeekPreviewVisible := False;
  WriteVideoMinerD3DLog(Format(
    'seek_preview_visible_change value=False seek_bar=%s playback=%s alpha=%s reason_before=%s',
    [BoolToStr(FSeekBarVisible, True), BoolToStr(FPlaybackActive, True),
     BoolToStr(FSourceHasAlpha, True), D3DFramePresentationBlockReason]));
  LogD3DFramePresentationState('seek_preview_clear', True);
  if FSeekPreviewBitmap <> nil then
    FSeekPreviewBitmap.SetSize(0, 0);
  Invalidate;
end;

procedure TVideoMinerVideoSurface.SetSafeAreaVisible(Value: Boolean);
begin
  if FSafeAreaVisible = Value then
    Exit;

  FSafeAreaVisible := Value;
  LogD3DFramePresentationState('safe_area_visible', True);
  Invalidate;
end;
procedure TVideoMinerVideoSurface.SetSeekWheelFrameStepMs(Value: Integer);
begin
  FSeekWheelFrameStepMs := Max(1, Value);
  if FSeekBar <> nil then
  begin
    FSeekBar.FrameStepMs := FSeekWheelFrameStepMs;
    if FSeekBarVisible then
      UpdateD3DSeekBarOverlayState;
  end;
end;

procedure TVideoMinerVideoSurface.SetFullScreen(Value: Boolean);
begin
  if FSeekBar <> nil then
  begin
    FSeekBar.FullScreen := Value;
    if FSeekBarVisible then
      UpdateD3DSeekBarOverlayState;
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
      UpdateD3DSeekBarOverlayState;
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
      UpdateD3DSeekBarOverlayState;
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
      UpdateD3DSeekBarOverlayState;
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
      UpdateD3DSeekBarOverlayState;
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
      UpdateD3DSeekBarOverlayState;
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
      UpdateD3DSeekBarOverlayState;
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

procedure TVideoMinerVideoSurface.SetOnSurfaceRightClick(Value: TNotifyEvent);
begin
  FOnSurfaceRightClick := Value;
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

procedure TVideoMinerVideoSurface.SetOnSeekHoverPreview(
  Value: TVideoMinerOverlaySeekHoverEvent);
begin
  FOnSeekHoverPreview := Value;
end;

procedure TVideoMinerVideoSurface.SetOnSeekHoverPreviewEnd(Value: TNotifyEvent);
begin
  FOnSeekHoverPreviewEnd := Value;
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

procedure TVideoMinerVideoSurface.LoadingTimer(Sender: TObject);
begin
  if not FLoadingActive then
  begin
    if FLoadingTimer <> nil then
      FLoadingTimer.Enabled := False;
    Exit;
  end;

  Inc(FLoadingTick);
  Invalidate;
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
