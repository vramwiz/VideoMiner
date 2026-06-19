unit VideoMinerMainForm;

// VideoMiner のメインフォーム。GUI イベントを受け、各 controller と表示/音声/設定を接続する。
// 実処理は専用ユニットへ寄せ、ここではアプリ全体の状態橋渡しと Windows メッセージ受け口を担当する。

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Diagnostics, System.Math, System.Types,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls, ActiveX, DropAgent, FFmpegDecoder,
  FFmpegDecoderTypes, FolderWatch, ResizeEdges, ShortcutAction,
  VideoMinerAudioPlayback,
  VideoMinerChapterManager, VideoMinerCommandController, VideoMinerMediaList, VideoMinerDebugLog,
  VideoMinerFrameCheck, VideoMinerFrameClipboard, VideoMinerMediaOpen, VideoMinerSettings,
  VideoMinerThumbnailBrowser,
  VideoMinerPlaybackController, VideoMinerPlaybackTiming,
  VideoMinerVideoView, VideoMinerWindowChrome, VideoMinerWindowModeController;

const
  WM_VM_OPEN_PENDING = WM_APP + 1; // 他プロセスから受けたファイルを安全なタイミングで開く独自メッセージ

type
  // 押しっぱなし扱いとして一時的に無視するナビゲーションキー集合
  TVideoMinerKeySet = set of Byte;

  TVideoMinerMainForm = class(TForm)
    PanelTitleBar: TPanel;
    LabelAppTitle: TLabel;
    PanelCloseButton: TPanel;
    LabelCloseButton: TLabel;
    PanelMaximizeButton: TPanel;
    LabelMaximizeButton: TLabel;
    PanelMinimizeButton: TPanel;
    LabelMinimizeButton: TLabel;
    ImagePreview: TImage;          // 専用動画サーフェスへ差し替える元の配置領域
    OpenDialogVideo: TOpenDialog;  // 読み込む動画ファイルを選択するダイアログ
    TimerPlayback: TTimer;         // 再生中に次フレームを読むためのタイマー
    // フォーム生成時に controller と入出力部品を接続する
    procedure FormCreate(Sender: TObject);
    // フォーム破棄時に再生状態を保存し、生成した部品を解放する
    procedure FormDestroy(Sender: TObject);
    // 再生 tick 処理を再生 controller へ委譲する
    procedure TimerPlaybackTimer(Sender: TObject);
    // ショートカットと全画面/ボスが来たモードのキー入力を処理する
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    // 押しっぱなし抑止対象のキーを解除する
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    // 独自タイトルバーのドラッグ移動を Windows へ渡す
    procedure TitleBarMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    // 閉じるボタンを処理する
    procedure CloseButtonClick(Sender: TObject);
    // 閉じるボタン hover 色へ切り替える
    procedure CloseButtonMouseEnter(Sender: TObject);
    // 閉じるボタンの通常色へ戻す
    procedure CloseButtonMouseLeave(Sender: TObject);
    // 最大化/通常表示を切り替える
    procedure MaximizeButtonClick(Sender: TObject);
    // 最小化する
    procedure MinimizeButtonClick(Sender: TObject);
    // 最小化/最大化ボタン hover 色へ切り替える
    procedure CaptionButtonMouseEnter(Sender: TObject);
    // 最小化/最大化ボタンの通常色へ戻す
    procedure CaptionButtonMouseLeave(Sender: TObject);
  private
    FDecoder                         : TFFmpegDecoder;                  // 現在再生に使う動画デコーダ
    FPreviewDecoder                  : TFFmpegDecoder;                  // シークや先読み表示に使う補助デコーダ
    FAudioPlayback                   : TVideoMinerAudioPlayback;        // 音声出力と音量状態の管理
    FMediaList                       : TVideoMinerMediaList;            // 同じフォルダ内の動画一覧
    FVideoView                       : TVideoMinerVideoView;            // 動画表示と overlay 入力の窓口
    FVideoFile                       : string;                          // 現在開いている動画ファイル名
    FVideoInfo                       : TVideoInfo;                      // 現在開いている動画の基本情報
    FCurrentVideoPositionMs          : Integer;                         // 最後に表示できたフレーム位置 ms
    FSeekPositionMs                  : Integer;                         // UI と再生制御で共有する現在位置 ms
    FSeekMaxMs                       : Integer;                         // シーク可能な最大位置 ms
    FUpdatingSeek                    : Boolean;                         // コードからシーク位置を更新中か
    FSeeking                         : Boolean;                         // シーク処理中か
    FSeekGuardTargetMs               : Integer;                         // シーク直後に再生 tick を守る対象位置 ms
    FSeekGuardRemaining              : Integer;                         // シーク guard を残す tick 数
    FDropAgent                       : TDropAgent;                      // ファイルドロップ受け口
    FOleInitialized                  : Boolean;                         // OLE 初期化に成功しているか
    FPendingOpenFiles                : TStringList;                     // WM 経由で後から開くファイルキュー
    FProcessingOpenQueue             : Boolean;                         // ファイルキュー処理中か
    FRestartPlaybackTimer            : TTimer;                          // シーク後に再生再開を遅延させるタイマー
    FReloadCurrentFileTimer          : TTimer;                          // 現在ファイルの更新をまとめて再読込するタイマー
    FFolderWatcher                   : TFolderWatch;                    // 現在フォルダの変更監視
    FWatchedFolder                   : string;                          // 監視中フォルダ
    FReloadingCurrentFile            : Boolean;                         // 現在ファイルの再読込中か
    FPendingReloadHasStamp           : Boolean;                         // 再読込候補のファイル状態を保持しているか
    FPendingReloadLastWriteTime      : TDateTime;                       // 再読込候補の更新日時
    FPendingReloadSize               : Int64;                           // 再読込候補のサイズ
    FVideoFileLastWriteTime          : TDateTime;                       // 現在ファイルを開いた時点の更新日時
    FVideoFileSize                   : Int64;                           // 現在ファイルを開いた時点のサイズ
    FPlaybackController              : TVideoMinerPlaybackController;   // 再生/シーク/終端処理の制御
    FCommandController               : TVideoMinerCommandController;    // overlay とショートカットのコマンド接続
    FWindowModeController            : TVideoMinerWindowModeController; // 全画面/枠なし/ボスが来たモードの制御
    FChapterManager                  : TVideoMinerChapterManager;       // 手動/自動チャプターとチェック状態の管理
    FThumbnailBrowser                : TVideoMinerThumbnailBrowser;     // 同一フォルダ内動画の一覧表示モード
    FLoopSegmentEndMs                : Integer;                         // ループ再生区間の終端 ms
    FLoopSegmentStartMs              : Integer;                         // ループ再生区間の開始 ms
    FEndAction                       : TVideoMinerEndAction;            // 動画終端到達時の動作
    FSafeAreaVisible                 : Boolean;                         // 90% セーフエリア確認枠を表示中か
    FShortcuts                       : TShortcutAction;                 // キーボードショートカット登録先
    FTitleIcon                       : TImage;                          // 独自タイトルバー左端のアイコン
    FFrameGuideBottom                : TPanel;                          // hover 時だけ表示する下端外側のフォーム枠
    FFrameGuideInnerBottom           : TPanel;                          // hover 時だけ表示する下端内側のフォーム枠
    FFrameGuideInnerLeft             : TPanel;                          // hover 時だけ表示する左端内側のフォーム枠
    FFrameGuideInnerRight            : TPanel;                          // hover 時だけ表示する右端内側のフォーム枠
    FFrameGuideInnerTop              : TPanel;                          // hover 時だけ表示する上端内側のフォーム枠
    FFrameGuideLeft                  : TPanel;                          // hover 時だけ表示する左端外側のフォーム枠
    FFrameGuideRight                 : TPanel;                          // hover 時だけ表示する右端外側のフォーム枠
    FFrameGuideTop                   : TPanel;                          // hover 時だけ表示する上端外側のフォーム枠
    FFrameGuideTimer                 : TTimer;                          // マウス位置を見てフォーム枠表示を切り替える
    FFrameGuideVisible               : Boolean;                         // hover 用フォーム枠を表示中か
    FLastInfoUpdateTick              : UInt64;                          // 情報表示を最後に更新した tick
    FBlockedNavigationKeys           : TVideoMinerKeySet;               // 押しっぱなし抑止中のナビゲーションキー
    FNavigationInputBlockedUntilTick : UInt64;                          // ナビゲーション入力を無視する終了 tick
    // 独自タイトルバー左端のアプリアイコンを作る
    procedure InitializeTitleIcon;
    // hover 時だけ見えるフォーム枠を作る
    procedure InitializeFrameGuide;
    // hover 用フォーム枠の表示/非表示を切り替える
    procedure SetFrameGuideVisible(Value: Boolean);
    // hover 用フォーム枠を現在のフォームサイズへ合わせる
    procedure UpdateFrameGuideLayout;
    // マウス位置から hover 用フォーム枠の表示状態を更新する
    procedure UpdateFrameGuideVisibility;
    // hover 用フォーム枠表示の timer 処理
    procedure FrameGuideTimer(Sender: TObject);
    // タイトルバーのボタン背景色を切り替える
    procedure SetCaptionButtonColor(Sender: TObject; Color: TColor);
    // 現在位置に手動チャプターを追加する
    procedure AddChapterOverlayClick(Sender: TObject);
    // 音声 PCM から自動チェック用チャプターを更新する
    procedure MaybeAutoCheckAudio(Sender: TObject; StartSample: Int64; const Pcm: TBytes);
    // 表示中フレームから自動チェック用チャプターを更新する
    procedure MaybeAutoCheckFrame(PositionMs: Integer);
    // Check モードを切り替える
    procedure CheckOverlayClick(Sender: TObject);
    // 現在位置付近の手動チャプターを削除する
    procedure DeleteChapterOverlayClick(Sender: TObject);
    // 動画終端時の動作を順に切り替える
    procedure CycleEndAction;
    // 現在フレームをクリップボードへコピーする
    procedure CopyCurrentFrameToClipboard;
    // 再生速度を順に切り替える
    procedure CyclePlaybackRate;
    // overlay の終端動作ボタンから切り替えを実行する
    procedure EndActionOverlayClick(Sender: TObject);
    // 全画面表示を切り替える
    procedure ToggleFullScreen;
    // 90% セーフエリア確認枠を切り替える
    procedure ToggleSafeArea;
    // 動画画面右クリックでサムネイル一覧を開く
    procedure VideoSurfaceMouseDown(Sender: TObject);
    // サムネイル一覧で選択された動画へ切り替える
    procedure ThumbnailBrowserSelected(Sender: TObject; Index: Integer;
      const FileName: string);
    // サムネイル一覧モードの表示/非表示を切り替える
    procedure ToggleThumbnailBrowser;
    // サムネイル一覧モードを閉じる
    procedure CloseThumbnailBrowser;
    // manager のチャプター情報を overlay 用表示へ反映する
    procedure RefreshChapterOverlay;
    // 終端動作ボタンの表示を更新する
    procedure UpdateEndActionButton;
    // 再生速度ボタンの表示を更新する
    procedure UpdatePlaybackRateButton;
    // 最大化ボタンの表示を現在状態に合わせる
    procedure UpdateMaximizeButton;
    // 指定ファイルを開き、必要なら自動再生する
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean;
      RestoreLoopPosition: Boolean = True): Boolean;
    // ドロップされた先頭ファイルを開く
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    // 前後ファイル移動ボタンの有効状態を更新する
    procedure UpdateNavigationButtons;
    // 現在押されているナビゲーションキーを一時的にブロックする
    procedure BlockPressedNavigationKeys;
    // メッセージキューに残ったナビゲーションキー入力を捨てる
    procedure ClearBufferedNavigationKeyMessages;
    // フォルダ内動画一覧を前後へ移動する
    procedure NavigateBy(Delta: Integer);
    // 終端時の next 動作用に次動画へ移動する
    procedure NavigateNextPlaybackFile;
    // 前後チャプターへ移動する
    procedure NavigateChapterBy(Delta: Integer);
    // ファイル選択ダイアログから動画を開く
    procedure OpenFromDialog;
    // 指定ファイルの手動チャプターと再開位置を読み込む
    procedure LoadManualChapterState(const FileName: string);
    // 現在ファイルの手動チャプターを保存する
    procedure SaveManualChapterState;
    // ループ再生用の再開位置を保存する
    procedure SaveLoopPlaybackPosition;
    // 保存済みのループ再生位置を復元する
    function TryRestoreLoopPlaybackPosition: Boolean;
    // 音量とミュート状態を保存する
    procedure SaveAudioPlaybackSettings;
    // 現在位置から再生する
    procedure PlayFromCurrentPosition;
    // 再生を停止する
    procedure StopPlayback;
    // 現在位置を基準にループ再生区間を構成する
    procedure ConfigureLoopSegment(PositionMs: Integer);
    // 偽装画面の Return ボタンからボスが来たモードを解除する
    procedure BossExitClick(Sender: TObject);
    // マウス往復ジェスチャー成立時にボスが来たモードへ入る
    procedure BossGesture(Sender: TObject);
    // ヘルプキーからヘルプ兼用画面を表示する
    procedure ShowHelpOverlay;
    // 再生中または再生再開待ちか返す
    function PlaybackActiveOrPending: Boolean;
    // controller と UI 状態から現在再生位置を返す
    function CurrentPlaybackPositionMs: Integer;
    // 独自タイトルバーへ文字列を反映する
    procedure SetTitleBarText(const Text: string);
    // フォーム caption とタイトルバーを状態表示として更新する
    procedure SetStatusCaption(const Text: string);
    // 再生中に進捗と情報表示を更新する
    procedure UpdatePlaybackProgress(PositionMs: Integer);
    // 再生 tick から指定位置へシークする
    procedure SeekPlaybackTickToMs(PositionMs: Integer);
    // 指定位置へシークし、必要なら再生状態を復元する
    procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
    // 現在位置から相対移動する
    procedure SeekByMs(DeltaMs: Integer);
    // 先頭フレームへ移動する
    procedure SeekToFirstFrame;
    // 末尾フレームへ移動する
    procedure SeekToLastFrame;
    // 最終フレーム表示用の安全なシーク位置を返す
    function LastFrameSeekPositionMs: Integer;
    // ループ戻り位置を返す
    function LoopStartPositionMs: Integer;
    // 指定位置から再生を開始する
    procedure StartPlaybackAtMs(PositionMs: Integer; FrameAlreadyShown: Boolean = False);
    // シーク後の遅延再生再開を処理する
    procedure RestartPlaybackTimer(Sender: TObject);
    // 終端到達時の停止/ループ/次動画動作を処理する
    procedure FinishPlaybackAtEnd;
    // 別プロセスから渡されたファイルを後で開くキューへ積む
    procedure QueueOpenAndPlayFile(const FileName: string);
    // 保留中の open キューを順に処理する
    procedure ProcessOpenQueue;
    // 現在ファイルのあるフォルダ監視を構成する
    procedure ConfigureCurrentFileWatch;
    // 指定リストに現在ファイルが含まれるか返す
    function CurrentFileInList(const FileNames: TStringList): Boolean;
    // 現在ファイルを読み取りオープンできるか返す
    function CurrentFileCanBeRead: Boolean;
    // 現在ファイルの更新日時とサイズを読む
    function ReadCurrentFileStamp(out LastWriteTime: TDateTime; out Size: Int64): Boolean;
    // 現在ファイルの再読込を遅延実行にする
    procedure ScheduleCurrentFileReload;
    // 更新が落ち着いたら現在ファイルを開き直す
    procedure ReloadCurrentFileTimer(Sender: TObject);
    // フォルダ監視イベントから現在ファイルの変更だけを拾う
    procedure FolderWatchFileChange(Sender: TObject; const AddFiles: TStringList;
      const DelFiles: TStringList; const UpdateFiles: TStringList);
    // 現在ファイルの更新日時とサイズを記録する
    procedure UpdateCurrentFileStamp;
    // 別プロセスから渡されたファイル名を受け取る
    procedure WMCopyData(var Message: TWMCopyData); message WM_COPYDATA;
    // 通常表示時の移動を window controller へ通知する
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    // 枠なしフォームのリサイズ hit test を window controller へ委譲する
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    // 枠なしフォームの非クライアント領域を調整する
    procedure WMNCCalcSize(var Message: TMessage); message WM_NCCALCSIZE;
    // 保留中の open キュー処理を実行する
    procedure WMOpenPending(var Message: TMessage); message WM_VM_OPEN_PENDING;
    // 通常表示時のサイズ変更を window controller へ通知する
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    // VCL のフォーカス移動処理より先に Tab を一覧切り替えとして拾う
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    // 指定ミリ秒位置のフレームを表示する
    function ShowFrameAtMs(const PositionMs: Integer): Boolean;
    // 動画情報ラベルを更新する
    procedure UpdateInfoLabel;
  protected
    // 枠なしフォーム用の作成パラメータを設定する
    procedure CreateParams(var Params: TCreateParams); override;
    // 動画サーフェスのホイール操作を優先して処理する
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    // 指定ファイルを開いて再生する
    function OpenAndPlayFile(const FileName: string): Boolean;
    // 設定に残っている前回ファイルを開く
    function OpenRememberedFile: Boolean;
  end;

var
  VideoMinerForm: TVideoMinerMainForm;

implementation

const
  COPYDATA_OPEN_FILE            = $564D0001; // 別プロセスからファイル名を受け取る COPYDATA 種別
  UI_INFO_UPDATE_INTERVAL_MS    = 250;       // 再生中の情報表示を更新する最短間隔 ms
  SEEK_RESTART_DELAY_MS         = 15;        // シーク後に再生再開を遅延させる時間 ms
  CURRENT_FILE_RELOAD_SETTLE_MS = 1500;      // ファイル更新が落ち着くまで再読込を待つ時間 ms
  NAVIGATION_INPUT_BLOCK_MS     = 300;       // 前後動画移動直後に残留キー入力を無視する時間 ms
  TITLE_BAR_COLOR               = $00171617; // 独自タイトルバーの通常背景色
  CLOSE_BUTTON_HOVER_COLOR      = $00232323; // 閉じるボタン hover 時の背景色
  CAPTION_BUTTON_HOVER_COLOR    = $00232323; // 最小化/最大化ボタン hover 時の背景色
  FRAME_GUIDE_INNER_COLOR       = clWhite;   // hover 枠の内側色
  FRAME_GUIDE_OUTER_COLOR       = clWhite;   // hover 枠の外側色
  FRAME_GUIDE_EDGE_SIZE         = 12;         // hover 枠を出すフォーム端の幅 px
  FRAME_GUIDE_LINE_SIZE         = 1;          // hover 枠 1 本ぶんの太さ px
  FRAME_GUIDE_TIMER_INTERVAL_MS = 80;         // hover 枠表示状態を確認する間隔 ms
  SLOW_OPEN_LOG_MS              = 200;       // open 処理を slow log へ出す基準時間 ms

{$R *.dfm}

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
var
  AudioSettings: TVideoMinerAudioSettings;
begin
  OnKeyUp := FormKeyUp;
  ClearVideoMinerDebugLog('form_create');
  PanelTitleBar.Color := TITLE_BAR_COLOR;
  PanelCloseButton.Color := TITLE_BAR_COLOR;
  PanelMaximizeButton.Color := TITLE_BAR_COLOR;
  PanelMinimizeButton.Color := TITLE_BAR_COLOR;
  InitializeTitleIcon;
  InitializeFrameGuide;
  FEndAction := LoadEndAction;
  FShortcuts := TShortcutAction.Create;
  FOleInitialized := OleInitialize(nil) >= 0;
  FDecoder := TFFmpegDecoder.Create;
  FPreviewDecoder := TFFmpegDecoder.Create;
  FAudioPlayback := TVideoMinerAudioPlayback.Create;
  FAudioPlayback.OnPcmDecoded := MaybeAutoCheckAudio;
  FMediaList := TVideoMinerMediaList.Create;
  FChapterManager := TVideoMinerChapterManager.Create;
  FVideoView := TVideoMinerVideoView.Create(ImagePreview);
  FVideoView.OnThumbnailBrowserClick := VideoSurfaceMouseDown;
  FThumbnailBrowser := TVideoMinerThumbnailBrowser.Create(Self);
  FThumbnailBrowser.Parent := FVideoView.SurfaceControl.Parent;
  FThumbnailBrowser.Align := FVideoView.SurfaceControl.Align;
  FThumbnailBrowser.SetBounds(FVideoView.SurfaceControl.Left,
    FVideoView.SurfaceControl.Top, FVideoView.SurfaceControl.Width,
    FVideoView.SurfaceControl.Height);
  FThumbnailBrowser.Anchors := FVideoView.SurfaceControl.Anchors;
  FThumbnailBrowser.OnSelected := ThumbnailBrowserSelected;
  FThumbnailBrowser.SetMediaList(FMediaList);
  FWindowModeController := TVideoMinerWindowModeController.Create(Self,
    PanelTitleBar, LabelMaximizeButton, FVideoView, StopPlayback);
  FCommandController := TVideoMinerCommandController.Create(FAudioPlayback,
    FVideoView);
  FCommandController.OnChapterNavigate := NavigateChapterBy;
  FCommandController.OnCopyCurrentFrame := CopyCurrentFrameToClipboard;
  FCommandController.OnNavigate := NavigateBy;
  FCommandController.OnOpenDialog := OpenFromDialog;
  FCommandController.OnPlaybackActiveOrPending := PlaybackActiveOrPending;
  FCommandController.OnPlaybackRateCycle := CyclePlaybackRate;
  FCommandController.OnPlayFromCurrentPosition := PlayFromCurrentPosition;
  FCommandController.OnSaveAudioSettings := SaveAudioPlaybackSettings;
  FCommandController.OnSeekByMs := SeekByMs;
  FCommandController.OnSeekToFirstFrame := SeekToFirstFrame;
  FCommandController.OnSeekToLastFrame := SeekToLastFrame;
  FCommandController.OnShowHelp := ShowHelpOverlay;
  FCommandController.OnSeekToMs := SeekToMs;
  FCommandController.OnStopPlayback := StopPlayback;
  FCommandController.OnToggleSafeArea := ToggleSafeArea;
  FCommandController.OnToggleFullScreen := ToggleFullScreen;
  FCommandController.RegisterShortcuts(FShortcuts);
  FCommandController.BindVideoView;
  UpdateMaximizeButton;
  FWindowModeController.ApplySavedWindowBounds;
  TResizeEdgeHelper.AttachEdges(PanelTitleBar, VIDEO_MINER_RESIZE_BORDER,
    [rdTop]);
  TResizeEdgeHelper.AttachEdges(FVideoView.SurfaceControl,
    VIDEO_MINER_RESIZE_BORDER, [rdBottom, rdLeft, rdRight]);
  TResizeEdgeHelper.AttachEdges(FThumbnailBrowser, VIDEO_MINER_RESIZE_BORDER,
    [rdBottom, rdLeft, rdRight]);
  FVideoView.OnBossExitClick := BossExitClick;
  FVideoView.OnBossGesture := BossGesture;
  FVideoView.OnEndActionClick := EndActionOverlayClick;
  FVideoView.OnAddChapterClick := AddChapterOverlayClick;
  FVideoView.OnCheckClick := CheckOverlayClick;
  FVideoView.OnDeleteChapterClick := DeleteChapterOverlayClick;
  FVideoView.CheckEnabled := FChapterManager.CheckEnabled;
  RefreshChapterOverlay;
  FPendingOpenFiles := TStringList.Create;
  FRestartPlaybackTimer := TTimer.Create(Self);
  FRestartPlaybackTimer.Enabled := False;
  FRestartPlaybackTimer.Interval := SEEK_RESTART_DELAY_MS;
  FRestartPlaybackTimer.OnTimer := RestartPlaybackTimer;
  FReloadCurrentFileTimer := TTimer.Create(Self);
  FReloadCurrentFileTimer.Enabled := False;
  FReloadCurrentFileTimer.Interval := CURRENT_FILE_RELOAD_SETTLE_MS;
  FReloadCurrentFileTimer.OnTimer := ReloadCurrentFileTimer;
  FFrameGuideTimer := TTimer.Create(Self);
  FFrameGuideTimer.Enabled := True;
  FFrameGuideTimer.Interval := FRAME_GUIDE_TIMER_INTERVAL_MS;
  FFrameGuideTimer.OnTimer := FrameGuideTimer;
  FFolderWatcher := TFolderWatch.Create;
  FFolderWatcher.FirstScanDone := True;
  FFolderWatcher.OnFileChange := FolderWatchFileChange;
  FPlaybackController := TVideoMinerPlaybackController.Create(TimerPlayback,
    FRestartPlaybackTimer, FAudioPlayback, FVideoView, FPreviewDecoder);
  UpdateEndActionButton;
  UpdatePlaybackRateButton;
  FCurrentVideoPositionMs := -1;
  FSeekPositionMs := 0;
  FSeekMaxMs := 0;
  FLoopSegmentStartMs := -1;
  FLoopSegmentEndMs := -1;
  AudioSettings := LoadAudioSettings;
  FAudioPlayback.VolumePercent := AudioSettings.VolumePercent;
  FAudioPlayback.Muted := AudioSettings.Muted;
  FVideoView.Muted := FAudioPlayback.Muted;
  if FAudioPlayback.Muted then
    FVideoView.VolumePercent := 0
  else
    FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
  FDropAgent := TDropAgent.Create;
  if FOleInitialized then
  begin
    FDropAgent.AcceptKinds := [dakFiles];
    FDropAgent.OnDropFiles := DropFiles;
    FDropAgent.Attach(Self);
  end;
  SetStatusCaption('No video loaded');
end;

// フォーム破棄時にデコーダを解放する
procedure TVideoMinerMainForm.FormDestroy(Sender: TObject);
begin
  SaveManualChapterState;
  SaveLoopPlaybackPosition;
  SaveAudioPlaybackSettings;
  if TimerPlayback <> nil then
    TimerPlayback.Enabled := False;
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  if FRestartPlaybackTimer <> nil then
    FRestartPlaybackTimer.Enabled := False;
  if FReloadCurrentFileTimer <> nil then
    FReloadCurrentFileTimer.Enabled := False;
  if FFolderWatcher <> nil then
    FFolderWatcher.Stop;
  if FAudioPlayback <> nil then
    FAudioPlayback.Stop;
  FDropAgent.Free;
  FPendingOpenFiles.Free;
  FCommandController.Free;
  FShortcuts.Free;
  FPlaybackController.Free;
  FFolderWatcher.Free;
  if FWindowModeController <> nil then
    FWindowModeController.SaveWindowBounds;
  FWindowModeController.Free;
  FThumbnailBrowser.Free;
  FVideoView.Free;
  FChapterManager.Free;
  FMediaList.Free;
  FAudioPlayback.Free;
  FPreviewDecoder.Free;
  FDecoder.Free;
  FTitleIcon.Free;
  SaveEndAction(FEndAction);
  if FOleInitialized then
    OleUninitialize;
end;

procedure TVideoMinerMainForm.ToggleFullScreen;
begin
  FWindowModeController.ToggleFullScreen;
end;

procedure TVideoMinerMainForm.ToggleSafeArea;
begin
  FSafeAreaVisible := not FSafeAreaVisible;
  if FVideoView <> nil then
    FVideoView.SafeAreaVisible := FSafeAreaVisible;
  if FSafeAreaVisible then
    SetStatusCaption('90% safe area guide on.')
  else
    SetStatusCaption('90% safe area guide off.');
end;

procedure TVideoMinerMainForm.InitializeFrameGuide;

  procedure CreateGuidePanel(out Panel: TPanel; Color: TColor);
  begin
    Panel := TPanel.Create(Self);
    Panel.Parent := Self;
    Panel.BevelOuter := bvNone;
    Panel.Caption := '';
    Panel.Color := Color;
    Panel.ParentBackground := False;
    Panel.Enabled := False;
    Panel.Visible := False;
  end;

begin
  CreateGuidePanel(FFrameGuideTop, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FFrameGuideBottom, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FFrameGuideLeft, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FFrameGuideRight, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FFrameGuideInnerTop, FRAME_GUIDE_INNER_COLOR);
  CreateGuidePanel(FFrameGuideInnerBottom, FRAME_GUIDE_INNER_COLOR);
  CreateGuidePanel(FFrameGuideInnerLeft, FRAME_GUIDE_INNER_COLOR);
  CreateGuidePanel(FFrameGuideInnerRight, FRAME_GUIDE_INNER_COLOR);
  UpdateFrameGuideLayout;
end;

procedure TVideoMinerMainForm.SetFrameGuideVisible(Value: Boolean);

  procedure SetGuidePanelVisible(Panel: TPanel);
  begin
    if Panel <> nil then
      Panel.Visible := Value;
  end;

  procedure BringGuidePanelToFront(Panel: TPanel);
  begin
    if Panel <> nil then
      Panel.BringToFront;
  end;

begin
  if (FFrameGuideVisible = Value) and (not Value) then
    Exit;

  if FFrameGuideVisible <> Value then
  begin
    FFrameGuideVisible := Value;
    SetGuidePanelVisible(FFrameGuideTop);
    SetGuidePanelVisible(FFrameGuideBottom);
    SetGuidePanelVisible(FFrameGuideLeft);
    SetGuidePanelVisible(FFrameGuideRight);
    SetGuidePanelVisible(FFrameGuideInnerTop);
    SetGuidePanelVisible(FFrameGuideInnerBottom);
    SetGuidePanelVisible(FFrameGuideInnerLeft);
    SetGuidePanelVisible(FFrameGuideInnerRight);
  end;

  if Value then
  begin
    UpdateFrameGuideLayout;
    BringGuidePanelToFront(FFrameGuideTop);
    BringGuidePanelToFront(FFrameGuideBottom);
    BringGuidePanelToFront(FFrameGuideLeft);
    BringGuidePanelToFront(FFrameGuideRight);
    BringGuidePanelToFront(FFrameGuideInnerTop);
    BringGuidePanelToFront(FFrameGuideInnerBottom);
    BringGuidePanelToFront(FFrameGuideInnerLeft);
    BringGuidePanelToFront(FFrameGuideInnerRight);
  end;
end;

procedure TVideoMinerMainForm.UpdateFrameGuideLayout;
var
  InnerHeight: Integer;
  InnerWidth: Integer;
  Thickness: Integer;
begin
  Thickness := FRAME_GUIDE_LINE_SIZE;
  if (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;
  InnerWidth := Max(0, ClientWidth - Thickness * 2);
  InnerHeight := Max(0, ClientHeight - Thickness * 2);

  if FFrameGuideTop <> nil then
    FFrameGuideTop.SetBounds(0, 0, ClientWidth, Thickness);
  if FFrameGuideBottom <> nil then
    FFrameGuideBottom.SetBounds(0, ClientHeight - Thickness, ClientWidth,
      Thickness);
  if FFrameGuideLeft <> nil then
    FFrameGuideLeft.SetBounds(0, 0, Thickness, ClientHeight);
  if FFrameGuideRight <> nil then
    FFrameGuideRight.SetBounds(ClientWidth - Thickness, 0, Thickness,
      ClientHeight);
  if FFrameGuideInnerTop <> nil then
    FFrameGuideInnerTop.SetBounds(Thickness, Thickness, InnerWidth, Thickness);
  if FFrameGuideInnerBottom <> nil then
    FFrameGuideInnerBottom.SetBounds(Thickness, ClientHeight - Thickness * 2,
      InnerWidth, Thickness);
  if FFrameGuideInnerLeft <> nil then
    FFrameGuideInnerLeft.SetBounds(Thickness, Thickness, Thickness,
      InnerHeight);
  if FFrameGuideInnerRight <> nil then
    FFrameGuideInnerRight.SetBounds(ClientWidth - Thickness * 2, Thickness,
      Thickness, InnerHeight);
end;

procedure TVideoMinerMainForm.UpdateFrameGuideVisibility;
var
  ClientPoint: TPoint;
  CursorPoint: TPoint;
  InEdge: Boolean;
  InForm: Boolean;
  InTitleBar: Boolean;
begin
  if (FWindowModeController <> nil) and
     (FWindowModeController.FullScreen or FWindowModeController.BossMode) then
  begin
    SetFrameGuideVisible(False);
    Exit;
  end;

  if WindowState = wsMinimized then
  begin
    SetFrameGuideVisible(False);
    Exit;
  end;

  GetCursorPos(CursorPoint);
  ClientPoint := ScreenToClient(CursorPoint);
  InForm := PtInRect(Rect(0, 0, ClientWidth, ClientHeight), ClientPoint);
  if not InForm then
  begin
    SetFrameGuideVisible(False);
    Exit;
  end;

  InTitleBar := (PanelTitleBar <> nil) and PanelTitleBar.Visible and
    PtInRect(PanelTitleBar.BoundsRect, ClientPoint);
  InEdge := (ClientPoint.X < FRAME_GUIDE_EDGE_SIZE) or
    (ClientPoint.X >= ClientWidth - FRAME_GUIDE_EDGE_SIZE) or
    (ClientPoint.Y < FRAME_GUIDE_EDGE_SIZE) or
    (ClientPoint.Y >= ClientHeight - FRAME_GUIDE_EDGE_SIZE);

  SetFrameGuideVisible(InTitleBar or InEdge);
end;

procedure TVideoMinerMainForm.FrameGuideTimer(Sender: TObject);
begin
  UpdateFrameGuideVisibility;
end;
procedure TVideoMinerMainForm.VideoSurfaceMouseDown(Sender: TObject);
begin
  if (FThumbnailBrowser <> nil) and (not FThumbnailBrowser.Visible) then
    ToggleThumbnailBrowser;
end;
procedure TVideoMinerMainForm.ThumbnailBrowserSelected(Sender: TObject;
  Index: Integer; const FileName: string);
begin
  if FileName = '' then
    Exit;

  if SameText(FileName, FVideoFile) then
  begin
    CloseThumbnailBrowser;
    Exit;
  end;

  if LoadVideoFile(FileName, True) then
    CloseThumbnailBrowser;
end;

procedure TVideoMinerMainForm.ToggleThumbnailBrowser;
begin
  if FThumbnailBrowser = nil then
    Exit;

  FThumbnailBrowser.SetMediaList(FMediaList);
  FThumbnailBrowser.Toggle;
end;

procedure TVideoMinerMainForm.CloseThumbnailBrowser;
begin
  if FThumbnailBrowser <> nil then
    FThumbnailBrowser.Close;
end;

procedure TVideoMinerMainForm.InitializeTitleIcon;
begin
  if FTitleIcon <> nil then
    Exit;

  FTitleIcon := TImage.Create(Self);
  FTitleIcon.Parent := PanelTitleBar;
  FTitleIcon.Align := alLeft;
  FTitleIcon.Width := PanelTitleBar.Height;
  FTitleIcon.Center := True;
  FTitleIcon.Proportional := True;
  FTitleIcon.Stretch := False;
  FTitleIcon.Transparent := True;
  FTitleIcon.OnMouseDown := TitleBarMouseDown;
  if not Icon.Empty then
    FTitleIcon.Picture.Icon.Assign(Icon)
  else if not Application.Icon.Empty then
    FTitleIcon.Picture.Icon.Assign(Application.Icon);
end;

procedure TVideoMinerMainForm.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  ConfigureBorderlessCreateParams(Params);
end;

function TVideoMinerMainForm.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := (FThumbnailBrowser <> nil) and FThumbnailBrowser.Visible and
    FThumbnailBrowser.HandleMouseWheel(Shift, WheelDelta, MousePos);
  if Result then
    Exit;

  Result := (FVideoView <> nil) and
    FVideoView.HandleMouseWheel(Shift, WheelDelta, MousePos);
  if not Result then
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

// 指定ミリ秒位置のフレームを表示する
function TVideoMinerMainForm.ShowFrameAtMs(const PositionMs: Integer): Boolean;
var
  ErrorMessage: string;
  ShownPositionMs: Integer;
begin
  Result := False;
  if (FVideoFile = '') or (FDecoder = nil) then
    Exit;

  if not FPlaybackController.ShowFrameNearMs(PositionMs, FSeekMaxMs,
    ShownPositionMs, ErrorMessage) then
  begin
    SetStatusCaption('Failed to decode frame: ' + ErrorMessage);
    Exit;
  end;

  FCurrentVideoPositionMs := ShownPositionMs;
  UpdateInfoLabel;
  Result := True;
end;

procedure TVideoMinerMainForm.TitleBarMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;

  ReleaseCapture;
  SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
end;

procedure TVideoMinerMainForm.CloseButtonClick(Sender: TObject);
begin
  Close;
end;

procedure TVideoMinerMainForm.CloseButtonMouseEnter(Sender: TObject);
begin
  PanelCloseButton.Color := CLOSE_BUTTON_HOVER_COLOR;
end;

procedure TVideoMinerMainForm.CloseButtonMouseLeave(Sender: TObject);
begin
  PanelCloseButton.Color := TITLE_BAR_COLOR;
end;

procedure TVideoMinerMainForm.SetCaptionButtonColor(Sender: TObject; Color: TColor);
var
  Control: TControl;
begin
  if Sender is TPanel then
    TPanel(Sender).Color := Color
  else if Sender is TLabel then
  begin
    Control := TLabel(Sender).Parent;
    if Control is TPanel then
      TPanel(Control).Color := Color;
  end;
end;

procedure TVideoMinerMainForm.CaptionButtonMouseEnter(Sender: TObject);
begin
  SetCaptionButtonColor(Sender, CAPTION_BUTTON_HOVER_COLOR);
end;

procedure TVideoMinerMainForm.CaptionButtonMouseLeave(Sender: TObject);
begin
  SetCaptionButtonColor(Sender, TITLE_BAR_COLOR);
end;

procedure TVideoMinerMainForm.MaximizeButtonClick(Sender: TObject);
begin
  if WindowState = wsMaximized then
    WindowState := wsNormal
  else
    WindowState := wsMaximized;
  UpdateMaximizeButton;
end;

procedure TVideoMinerMainForm.MinimizeButtonClick(Sender: TObject);
begin
  WindowState := wsMinimized;
end;

procedure TVideoMinerMainForm.CopyCurrentFrameToClipboard;
var
  ErrorMessage: string;
  FrameBitmap: TBitmap;
begin
  if PlaybackActiveOrPending then
  begin
    SetStatusCaption('Pause video before copying frame.');
    Exit;
  end;

  FrameBitmap := nil;
  if FVideoView <> nil then
    FrameBitmap := FVideoView.CurrentFrameBitmap;
  if (FrameBitmap = nil) or (FrameBitmap.Width <= 0) or (FrameBitmap.Height <= 0) then
  begin
    SetStatusCaption('No frame to copy.');
    Exit;
  end;

  if CopyVideoFrameBitmapToClipboard(FrameBitmap, FVideoInfo.HasAlpha, ErrorMessage) then
    SetStatusCaption('Copied current frame to clipboard.')
  else
    SetStatusCaption('Failed to copy frame: ' + ErrorMessage);
end;

procedure TVideoMinerMainForm.CycleEndAction;
begin
  FEndAction := FPlaybackController.NextEndAction(FEndAction);
  UpdateEndActionButton;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveEndAction(FEndAction);
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerMainForm.CyclePlaybackRate;
var
  CurrentRate: Double;
  PositionMs: Integer;
  WasPlaying: Boolean;
begin
  if FPlaybackController = nil then
    Exit;

  WasPlaying := PlaybackActiveOrPending;
  PositionMs := CurrentPlaybackPositionMs;
  CurrentRate := FPlaybackController.PlaybackRate;
  if SameValue(CurrentRate, 1.0) then
    FPlaybackController.PlaybackRate := 1.5
  else if SameValue(CurrentRate, 1.5) then
    FPlaybackController.PlaybackRate := 2.0
  else
    FPlaybackController.PlaybackRate := 1.0;

  UpdatePlaybackRateButton;
  if WasPlaying then
  begin
    FPlaybackController.StopPlayback;
    StartPlaybackAtMs(PositionMs, True);
  end
  else
    UpdateInfoLabel;
end;

procedure TVideoMinerMainForm.EndActionOverlayClick(Sender: TObject);
begin
  CycleEndAction;
end;

procedure TVideoMinerMainForm.AddChapterOverlayClick(Sender: TObject);
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.AddManualChapter(CurrentPlaybackPositionMs, FSeekMaxMs);
  RefreshChapterOverlay;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveManualChapterState;
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerMainForm.MaybeAutoCheckAudio(Sender: TObject;
  StartSample: Int64; const Pcm: TBytes);
var
  Changed: Boolean;
begin
  if FChapterManager = nil then
    Exit;

  if (not FVideoInfo.Audio.Present) or (FVideoInfo.Audio.OpenError <> '') then
  begin
    FChapterManager.MaybeAutoCheckAudio(StartSample, nil, FSeekMaxMs);
    Exit;
  end;

  Changed := FChapterManager.MaybeAutoCheckAudio(StartSample, Pcm, FSeekMaxMs);
  if Changed then
  begin
    RefreshChapterOverlay;
    ConfigureLoopSegment(CurrentPlaybackPositionMs);
    SaveManualChapterState;
    SaveLoopPlaybackPosition;
  end;
end;

procedure TVideoMinerMainForm.MaybeAutoCheckFrame(PositionMs: Integer);
var
  Changed: Boolean;
  Signature: TVideoMinerFrameSignature;
begin
  if (FChapterManager = nil) or (FVideoView = nil) then
    Exit;

  if not FChapterManager.CheckEnabled then
  begin
    FChapterManager.MaybeAutoCheckFrame(PositionMs, False, FSeekMaxMs);
    FillChar(Signature, SizeOf(Signature), 0);
    FChapterManager.MaybeAutoCheckFrameDifference(PositionMs, Signature,
      FSeekMaxMs);
    Exit;
  end;

  Changed := FChapterManager.MaybeAutoCheckFrame(PositionMs,
    FVideoView.CurrentFrameCornersMostlyDark, FSeekMaxMs);
  if FVideoView.CurrentFrameSignature(Signature) then
    Changed := FChapterManager.MaybeAutoCheckFrameDifference(PositionMs,
      Signature, FSeekMaxMs) or Changed;
  if Changed then
  begin
    RefreshChapterOverlay;
    ConfigureLoopSegment(CurrentPlaybackPositionMs);
    SaveManualChapterState;
    SaveLoopPlaybackPosition;
  end;
end;

procedure TVideoMinerMainForm.CheckOverlayClick(Sender: TObject);
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.ToggleCheckEnabled;
  if FVideoView <> nil then
    FVideoView.CheckEnabled := FChapterManager.CheckEnabled;
  RefreshChapterOverlay;
end;

procedure TVideoMinerMainForm.DeleteChapterOverlayClick(Sender: TObject);
begin
  if FChapterManager = nil then
    Exit;

  if not FChapterManager.DeleteNearestManualChapter(CurrentPlaybackPositionMs,
    FSeekMaxMs) then
    Exit;

  RefreshChapterOverlay;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveManualChapterState;
  SaveLoopPlaybackPosition;
end;

procedure TVideoMinerMainForm.RefreshChapterOverlay;
begin
  if (FVideoView <> nil) and (FChapterManager <> nil) then
    FVideoView.Chapters := FChapterManager.DisplayChapters;
end;

procedure TVideoMinerMainForm.UpdateEndActionButton;
begin
  if (FVideoView = nil) or (FPlaybackController = nil) then
    Exit;

  FVideoView.EndActionText := FPlaybackController.EndActionText(FEndAction);
end;

procedure TVideoMinerMainForm.UpdatePlaybackRateButton;
var
  RateText: string;
begin
  if (FVideoView = nil) or (FPlaybackController = nil) then
    Exit;

  if SameValue(FPlaybackController.PlaybackRate, 1.5) then
    RateText := '1.5x'
  else if SameValue(FPlaybackController.PlaybackRate, 2.0) then
    RateText := '2.0x'
  else
    RateText := '1.0x';
  FVideoView.PlaybackRateText := RateText;
end;

procedure TVideoMinerMainForm.UpdateMaximizeButton;
begin
  if FWindowModeController <> nil then
    FWindowModeController.UpdateMaximizeButton;
end;

// 動画情報ラベルを更新する
procedure TVideoMinerMainForm.UpdateInfoLabel;
var
  AudioPositionMs: Integer;
  AlphaText: string;
  AudioText: string;
  CurrentPositionMs: Integer;
  VideoPositionMs: Integer;
begin
  if FVideoFile = '' then
  begin
    SetStatusCaption('No video loaded');
    FVideoView.SetSeekProgress(0, 0);
    Exit;
  end;

  if FVideoInfo.Audio.Present then
  begin
    AudioText := Format('audio: %d Hz / %d ch / %s',
      [FVideoInfo.Audio.SampleRate, FVideoInfo.Audio.Channels,
       FVideoInfo.Audio.SampleFormatName]);
    if FVideoInfo.Audio.OpenError <> '' then
      AudioText := AudioText + ' / open: ' + FVideoInfo.Audio.OpenError;
  end
  else
    AudioText := 'audio: none';

  if FVideoInfo.HasAlpha then
    AlphaText := Format(' / pix_fmt: %s / alpha', [FVideoInfo.PixelFormatName])
  else if FVideoInfo.PixelFormatName <> '' then
    AlphaText := Format(' / pix_fmt: %s', [FVideoInfo.PixelFormatName])
  else
    AlphaText := '';

  CurrentPositionMs := CurrentPlaybackPositionMs;
  VideoPositionMs := FCurrentVideoPositionMs;
  if VideoPositionMs < 0 then
    VideoPositionMs := 0;
  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if AudioPositionMs < 0 then
    AudioPositionMs := 0
  else if AudioPositionMs > FSeekMaxMs then
    AudioPositionMs := FSeekMaxMs;

  Caption := Format('%s (%d/%d) - %.3f/%.3f sec  video %.3f  audio %.3f - %dx%d / %.3f fps / %s',
    [ExtractFileName(FVideoFile), FMediaList.CurrentIndex + 1, FMediaList.Count,
     CurrentPositionMs / 1000, FSeekMaxMs / 1000,
     VideoPositionMs / 1000, AudioPositionMs / 1000,
     FVideoInfo.Width, FVideoInfo.Height, FVideoInfo.Fps, AudioText + AlphaText]);
  SetTitleBarText(Format('%s (%d/%d)', [ExtractFileName(FVideoFile),
    FMediaList.CurrentIndex + 1, FMediaList.Count]));
  FVideoView.SetSeekProgress(CurrentPositionMs, FSeekMaxMs);
  FLastInfoUpdateTick := GetTickCount64;
end;

procedure TVideoMinerMainForm.UpdatePlaybackProgress(PositionMs: Integer);
var
  CurrentTick: UInt64;
begin
  if FVideoView <> nil then
    FVideoView.SetSeekProgress(PositionMs, FSeekMaxMs);

  CurrentTick := GetTickCount64;
  if (FLastInfoUpdateTick = 0) or
     (CurrentTick - FLastInfoUpdateTick >= UI_INFO_UPDATE_INTERVAL_MS) then
    UpdateInfoLabel;
end;

procedure TVideoMinerMainForm.OpenFromDialog;
begin
  OpenDialogVideo.InitialDir := VideoMinerOpenDialogInitialDir(FVideoFile);
  if OpenDialogVideo.Execute then
    LoadVideoFile(OpenDialogVideo.FileName, False);
end;

procedure TVideoMinerMainForm.LoadManualChapterState(const FileName: string);
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.LoadManualChapterState(FileName, FSeekMaxMs);
  RefreshChapterOverlay;
end;

procedure TVideoMinerMainForm.SaveManualChapterState;
begin
  if FChapterManager = nil then
    Exit;

  FChapterManager.SaveManualChapterState(FVideoFile, FSeekMaxMs);
end;

procedure TVideoMinerMainForm.SaveLoopPlaybackPosition;
begin
  if (FChapterManager = nil) or (FPlaybackController = nil) or
     (FVideoFile = '') then
    Exit;

  if (FEndAction = eaLoop) and FChapterManager.HasManualChapters then
    SaveManualChapterPlaybackPosition(FVideoFile, CurrentPlaybackPositionMs,
      FSeekMaxMs)
  else
    ClearManualChapterPlaybackPosition(FVideoFile);
end;

function TVideoMinerMainForm.TryRestoreLoopPlaybackPosition: Boolean;
var
  ErrorMessage: string;
  PositionMs: Integer;
  ShownPositionMs: Integer;
begin
  Result := False;
  if (FChapterManager = nil) or (FVideoFile = '') or
     (FPlaybackController = nil) or (FEndAction <> eaLoop) or
     (not FChapterManager.HasManualChapters) then
    Exit;

  if not LoadManualChapterPlaybackPosition(FVideoFile, FSeekMaxMs,
    PositionMs) then
    Exit;

  if not FPlaybackController.ShowFrameNearMs(PositionMs, FSeekMaxMs,
    ShownPositionMs, ErrorMessage) then
    Exit;

  FCurrentVideoPositionMs := ShownPositionMs;
  FUpdatingSeek := True;
  try
    FSeekPositionMs := ShownPositionMs;
  finally
    FUpdatingSeek := False;
  end;
  UpdatePlaybackProgress(FSeekPositionMs);
  ConfigureLoopSegment(FSeekPositionMs);
  Result := True;
end;

procedure TVideoMinerMainForm.SaveAudioPlaybackSettings;
var
  Settings: TVideoMinerAudioSettings;
begin
  if FAudioPlayback = nil then
    Exit;

  Settings.Muted := FAudioPlayback.Muted;
  Settings.VolumePercent := FAudioPlayback.VolumePercent;
  SaveAudioSettings(Settings);
end;

function TVideoMinerMainForm.PlaybackActiveOrPending: Boolean;
begin
  Result := (FPlaybackController <> nil) and FPlaybackController.ActiveOrPending;
end;

function TVideoMinerMainForm.CurrentPlaybackPositionMs: Integer;
begin
  if FPlaybackController = nil then
  begin
    Result := Max(0, Min(FSeekMaxMs, FSeekPositionMs));
    Exit;
  end;

  Result := FPlaybackController.CurrentPositionMs(PlaybackActiveOrPending,
    FSeekPositionMs, FCurrentVideoPositionMs, FSeekMaxMs);
end;

procedure TVideoMinerMainForm.SetStatusCaption(const Text: string);
begin
  if Text = '' then
  begin
    Caption := 'VideoMiner'
  end
  else
  begin
    Caption := 'VideoMiner - ' + Text;
  end;
  SetTitleBarText(Caption);
end;

procedure TVideoMinerMainForm.SetTitleBarText(const Text: string);
begin
  if LabelAppTitle <> nil then
    LabelAppTitle.Caption := Text;
end;

function TVideoMinerMainForm.LoadVideoFile(const FileName: string;
  AutoPlay: Boolean; RestoreLoopPosition: Boolean): Boolean;
var
  ErrorMessage: string;
  OpenResult: TVideoMinerMediaOpenResult;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  ValidateMs: Double;
  CleanupMs: Double;
  OpenMs: Double;
  FirstFrameMs: Double;
  AutoPlayMs: Double;
begin
  Result := False;
  TotalWatch := TStopwatch.StartNew;

  StepWatch := TStopwatch.StartNew;
  if not ValidateVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
    ValidateMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'open_failed step="validate" file="%s" drive="%s" autoplay=%s validate_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       BoolToStr(AutoPlay, True), ValidateMs, TotalWatch.Elapsed.TotalMilliseconds,
       ErrorMessage]));
{$ENDIF}
    SetStatusCaption(ErrorMessage);
    Exit;
  end;
  ValidateMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if FReloadCurrentFileTimer <> nil then
    FReloadCurrentFileTimer.Enabled := False;
  FPendingReloadHasStamp := False;

  SaveManualChapterState;
  SaveLoopPlaybackPosition;

  TimerPlayback.Enabled := False;
  FPlaybackController.ClearRestart;
  FAudioPlayback.Stop;
  FPreviewDecoder.Close;
  FSeeking := False;
  FCurrentVideoPositionMs := -1;
  FSeekGuardRemaining := 0;
  FLoopSegmentStartMs := -1;
  FLoopSegmentEndMs := -1;
  FChapterManager.Clear;
  FVideoView.Clear;
  RefreshChapterOverlay;

  FUpdatingSeek := True;
  try
    FSeekPositionMs := 0;
    FSeekMaxMs := 0;
  finally
    FUpdatingSeek := False;
  end;
  CleanupMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if not OpenVideoMinerMediaFile(FileName, FDecoder, FPreviewDecoder,
    FMediaList, OpenResult) then
  begin
    OpenMs := StepWatch.Elapsed.TotalMilliseconds;
    FVideoFile := '';
    ConfigureCurrentFileWatch;
    UpdateCurrentFileStamp;
    FVideoView.PlaybackActive := False;
    Caption := 'VideoMiner';
    SetTitleBarText(Caption);
    UpdateNavigationButtons;
    SetStatusCaption(OpenResult.ErrorMessage);
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'open_failed step="decoder_open" file="%s" drive="%s" autoplay=%s validate_ms=%.3f cleanup_ms=%.3f open_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       BoolToStr(AutoPlay, True), ValidateMs, CleanupMs, OpenMs,
       TotalWatch.Elapsed.TotalMilliseconds, OpenResult.ErrorMessage]));
{$ENDIF}
    Exit;
  end;
  OpenMs := StepWatch.Elapsed.TotalMilliseconds;

  FVideoInfo := OpenResult.Info;
  FVideoFile := OpenResult.FileName;
  FVideoView.SourceHasAlpha := FVideoInfo.HasAlpha;
  FVideoView.SeekWheelFrameStepMs := VideoMinerFrameDurationMs(FVideoInfo.Fps);
  ConfigureCurrentFileWatch;
  UpdateCurrentFileStamp;
  Caption := Format('%s (%d/%d)', [ExtractFileName(FVideoFile),
    FMediaList.CurrentIndex + 1, FMediaList.Count]);
  SetTitleBarText(Caption);

  FUpdatingSeek := True;
  try
    FSeekMaxMs := Round(FVideoInfo.DurationSec * 1000);
    FSeekPositionMs := 0;
  finally
    FUpdatingSeek := False;
  end;

  TimerPlayback.Interval := VideoMinerTimerIntervalMs(FVideoInfo.Fps);

  LoadManualChapterState(FVideoFile);
  UpdateNavigationButtons;
  if FThumbnailBrowser <> nil then
    FThumbnailBrowser.SetMediaList(FMediaList);
  UpdateInfoLabel;
  RefreshChapterOverlay;
  StepWatch := TStopwatch.StartNew;
  if (not RestoreLoopPosition) or (not TryRestoreLoopPlaybackPosition) then
    ShowFrameAtMs(0);
  FirstFrameMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
  if AutoPlay then
    PlayFromCurrentPosition;
  AutoPlayMs := StepWatch.Elapsed.TotalMilliseconds;

  RememberVideoMinerMediaFile(FileName);
  Result := True;
{$IFDEF DEBUG}
  if (TotalWatch.Elapsed.TotalMilliseconds >= SLOW_OPEN_LOG_MS) or
     (OpenMs >= SLOW_OPEN_LOG_MS) or (FirstFrameMs >= SLOW_OPEN_LOG_MS) or
     (AutoPlayMs >= SLOW_OPEN_LOG_MS) then
    WriteVideoMinerSlowLog(Format(
      'open_done file="%s" drive="%s" autoplay=%s restore_loop=%s validate_ms=%.3f cleanup_ms=%.3f open_ms=%.3f first_frame_ms=%.3f autoplay_ms=%.3f total_ms=%.3f duration_ms=%d fps=%.3f',
      [ExtractFileName(FVideoFile), ExtractFileDrive(FVideoFile),
       BoolToStr(AutoPlay, True), BoolToStr(RestoreLoopPosition, True),
       ValidateMs, CleanupMs, OpenMs, FirstFrameMs, AutoPlayMs,
       TotalWatch.Elapsed.TotalMilliseconds, FSeekMaxMs, FVideoInfo.Fps]));
{$ENDIF}
end;

function TVideoMinerMainForm.OpenAndPlayFile(const FileName: string): Boolean;
begin
  Result := LoadVideoFile(FileName, True);
end;

function TVideoMinerMainForm.OpenRememberedFile: Boolean;
var
  ErrorMessage: string;
  FileName: string;
begin
  Result := False;

  if not ResolveRememberedVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
    if ErrorMessage <> '' then
      SetStatusCaption(ErrorMessage);
    Exit;
  end;

  Result := LoadVideoFile(FileName, False);
end;

procedure TVideoMinerMainForm.DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
begin
  if Length(FileNames) > 0 then
    OpenAndPlayFile(FileNames[0]);
end;

procedure TVideoMinerMainForm.PlayFromCurrentPosition;
var
  FrameShown: Boolean;
begin
  if FVideoFile = '' then
    Exit;

  FrameShown := FCurrentVideoPositionMs = FSeekPositionMs;
  if FSeekPositionMs >= FSeekMaxMs then
  begin
    FUpdatingSeek := True;
    try
      FSeekPositionMs := 0;
    finally
      FUpdatingSeek := False;
    end;
    FrameShown := ShowFrameAtMs(0);
  end;

  StartPlaybackAtMs(FSeekPositionMs, FrameShown);
end;

procedure TVideoMinerMainForm.BossGesture(Sender: TObject);
begin
  FWindowModeController.EnterBossMode;
end;

procedure TVideoMinerMainForm.ShowHelpOverlay;
begin
  FWindowModeController.EnterBossMode;
end;

procedure TVideoMinerMainForm.BossExitClick(Sender: TObject);
begin
  FWindowModeController.ExitBossMode;
end;

// 再生を停止する
procedure TVideoMinerMainForm.StopPlayback;
begin
  if FPlaybackController <> nil then
    FPlaybackController.StopPlayback;
  UpdateInfoLabel;
end;

// 再生 tick 処理を再生 controller へ委譲する
procedure TVideoMinerMainForm.TimerPlaybackTimer(Sender: TObject);
begin
  FPlaybackController.Tick(FDecoder, FVideoFile, FEndAction, FSeeking,
    FSeekMaxMs, FLoopSegmentStartMs, FLoopSegmentEndMs,
    FCurrentVideoPositionMs, FSeekPositionMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FUpdatingSeek, SetStatusCaption, FinishPlaybackAtEnd,
    SeekPlaybackTickToMs, UpdatePlaybackProgress, MaybeAutoCheckFrame);
end;


procedure TVideoMinerMainForm.UpdateNavigationButtons;
begin
  if FVideoView = nil then
    Exit;

  if FMediaList = nil then
  begin
    FVideoView.CanNavigatePrevious := False;
    FVideoView.CanNavigateNext := False;
    Exit;
  end;

  FVideoView.CanNavigatePrevious := FMediaList.CanNavigate(-1);
  FVideoView.CanNavigateNext := FMediaList.CanNavigate(1);
end;

function IsNavigationSwitchKey(Key: Word): Boolean;
begin
  Result := (Key = VK_LEFT) or (Key = VK_RIGHT) or
    (Key = VK_PRIOR) or (Key = VK_NEXT);
end;

procedure TVideoMinerMainForm.BlockPressedNavigationKeys;
const
  NAVIGATION_KEYS: array[0..3] of Word = (VK_LEFT, VK_RIGHT, VK_PRIOR, VK_NEXT);
var
  I: Integer;
  Key: Word;
begin
  for I := Low(NAVIGATION_KEYS) to High(NAVIGATION_KEYS) do
  begin
    Key := NAVIGATION_KEYS[I];
    if GetAsyncKeyState(Key) < 0 then
      Include(FBlockedNavigationKeys, Byte(Key));
  end;
end;

procedure TVideoMinerMainForm.ClearBufferedNavigationKeyMessages;
var
  Msg: TMsg;
begin
  while PeekMessage(Msg, 0, WM_KEYFIRST, WM_KEYLAST, PM_NOREMOVE) do
  begin
    if ((Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN)) and
       IsNavigationSwitchKey(Word(Msg.wParam)) then
    begin
      PeekMessage(Msg, Msg.hwnd, Msg.message, Msg.message, PM_REMOVE);
    end
    else
      Break;
  end;
end;

procedure TVideoMinerMainForm.NavigateBy(Delta: Integer);
var
  FileName: string;
begin
  FileName := FMediaList.NavigateFile(Delta);
  if FileName = '' then
  begin
    UpdateNavigationButtons;
    Exit;
  end;

  LoadVideoFile(FileName, True);
  FNavigationInputBlockedUntilTick := GetTickCount64 + NAVIGATION_INPUT_BLOCK_MS;
  BlockPressedNavigationKeys;
  ClearBufferedNavigationKeyMessages;
end;

procedure TVideoMinerMainForm.NavigateNextPlaybackFile;
begin
  NavigateBy(1);
end;

procedure TVideoMinerMainForm.NavigateChapterBy(Delta: Integer);
var
  TargetMs: Integer;
begin
  if (FChapterManager = nil) or (Delta = 0) or (FSeekMaxMs <= 0) then
    Exit;

  TargetMs := FChapterManager.FindNavigationTarget(Delta,
    CurrentPlaybackPositionMs, LastFrameSeekPositionMs);
  if TargetMs >= 0 then
    SeekToMs(TargetMs);
end;

procedure TVideoMinerMainForm.SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean);
begin
  FPlaybackController.SeekToMs(FVideoFile, PositionMs, ResumeIfPlaying,
    FSeekMaxMs, FCurrentVideoPositionMs, FSeekPositionMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FUpdatingSeek, FSeeking, SetStatusCaption,
    UpdateInfoLabel);
end;

procedure TVideoMinerMainForm.SeekByMs(DeltaMs: Integer);
var
  BaseMs: Integer;
  TargetMs: Integer;
begin
  BaseMs := CurrentPlaybackPositionMs;
  TargetMs := BaseMs + DeltaMs;
  if TargetMs <= 0 then
    SeekToFirstFrame
  else if TargetMs >= FSeekMaxMs then
    SeekToLastFrame
  else
    SeekToMs(TargetMs);
end;

procedure TVideoMinerMainForm.SeekPlaybackTickToMs(PositionMs: Integer);
var
  FrameShown: Boolean;
{$IFDEF DEBUG}
  PreviewMs: Double;
  RestartMs: Double;
  StepWatch: TStopwatch;
  TotalWatch: TStopwatch;
{$ENDIF}
begin
{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;
{$ENDIF}
  FUpdatingSeek := True;
  try
    FSeekPositionMs := PositionMs;
  finally
    FUpdatingSeek := False;
  end;
  UpdatePlaybackProgress(PositionMs);

{$IFDEF DEBUG}
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FrameShown := ShowFrameAtMs(PositionMs);
{$IFDEF DEBUG}
  PreviewMs := StepWatch.Elapsed.TotalMilliseconds;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  StartPlaybackAtMs(PositionMs, FrameShown);
{$IFDEF DEBUG}
  RestartMs := StepWatch.Elapsed.TotalMilliseconds;
  WriteVideoMinerSlowLog(Format(
    'loop_tick_seek file="%s" target_ms=%d frame_shown=%s preview_ms=%.3f restart_ms=%.3f total_ms=%.3f current_ms=%d seek_ms=%d guard_target_ms=%d guard_remaining=%d',
    [ExtractFileName(FVideoFile), PositionMs, BoolToStr(FrameShown, True),
     PreviewMs, RestartMs, TotalWatch.Elapsed.TotalMilliseconds,
     FCurrentVideoPositionMs, FSeekPositionMs, FSeekGuardTargetMs,
     FSeekGuardRemaining]));
{$ENDIF}
end;

procedure TVideoMinerMainForm.SeekToFirstFrame;
begin
  SeekToMs(0);
end;

procedure TVideoMinerMainForm.SeekToLastFrame;
begin
  SeekToMs(LastFrameSeekPositionMs, False);
end;

function TVideoMinerMainForm.LastFrameSeekPositionMs: Integer;
begin
  Result := VideoMinerLastFrameSeekPositionMs(FSeekMaxMs, FVideoInfo.Fps);
end;

function TVideoMinerMainForm.LoopStartPositionMs: Integer;
begin
  if FChapterManager = nil then
    Result := 0
  else
    Result := FChapterManager.LoopStartPositionMs(LastFrameSeekPositionMs);
end;

procedure TVideoMinerMainForm.ConfigureLoopSegment(PositionMs: Integer);
begin
  FPlaybackController.ConfigureLoopSegment(FEndAction, FChapterManager,
    PositionMs, FSeekMaxMs, LastFrameSeekPositionMs, FLoopSegmentStartMs,
    FLoopSegmentEndMs);
end;

procedure TVideoMinerMainForm.StartPlaybackAtMs(PositionMs: Integer;
  FrameAlreadyShown: Boolean);
begin
  FPlaybackController.StartPlaybackAtMs(FDecoder, FVideoFile, FVideoInfo,
    FEndAction, FChapterManager, FSeekMaxMs, PositionMs, LastFrameSeekPositionMs,
    FrameAlreadyShown, False, FCurrentVideoPositionMs, FSeekPositionMs,
    FLoopSegmentStartMs, FLoopSegmentEndMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, SetStatusCaption);
end;

procedure TVideoMinerMainForm.FinishPlaybackAtEnd;
var
  CanNavigateNext: Boolean;
begin
  CanNavigateNext := (FMediaList <> nil) and FMediaList.CanNavigate(1);
  FPlaybackController.FinishAtEnd(FEndAction, CanNavigateNext,
    LoopStartPositionMs, FSeekMaxMs, FSeekPositionMs, FUpdatingSeek,
    ShowFrameAtMs, StartPlaybackAtMs, NavigateNextPlaybackFile,
    UpdateInfoLabel);
end;

procedure TVideoMinerMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FWindowModeController = nil then
    Exit;

  if FWindowModeController.BossMode then
  begin
    if (Key = VK_ESCAPE) or (Key = VK_RETURN) then
      FWindowModeController.ExitBossMode
    else if (Key = VK_DOWN) or (Key = VK_NEXT) then
    begin
      if FVideoView <> nil then
        FVideoView.ChangeBossHelpPage(1);
    end
    else if (Key = VK_UP) or (Key = VK_PRIOR) then
    begin
      if FVideoView <> nil then
        FVideoView.ChangeBossHelpPage(-1);
    end;
    Key := 0;
    Exit;
  end;

  if (FThumbnailBrowser <> nil) and FThumbnailBrowser.Visible and
     FThumbnailBrowser.HandleKeyDown(Key, Shift) then
    Exit;

  if (Key = VK_ESCAPE) and (FThumbnailBrowser <> nil) and
     FThumbnailBrowser.Visible then
  begin
    CloseThumbnailBrowser;
    Key := 0;
    Exit;
  end;

  if (Key = VK_TAB) and (Shift = []) then
  begin
    ToggleThumbnailBrowser;
    Key := 0;
    Exit;
  end;

  if (Key = VK_ESCAPE) and FWindowModeController.FullScreen then
  begin
    FWindowModeController.ExitFullScreen;
    Key := 0;
    Exit;
  end;

  if (Shift = []) and IsNavigationSwitchKey(Key) and
     ((Byte(Key) in FBlockedNavigationKeys) or
      (GetTickCount64 < FNavigationInputBlockedUntilTick)) then
  begin
    Key := 0;
    Exit;
  end;

  if (FShortcuts <> nil) and FShortcuts.KeyDown(Key, Shift) then
    Exit;
end;

procedure TVideoMinerMainForm.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if IsNavigationSwitchKey(Key) then
    Exclude(FBlockedNavigationKeys, Byte(Key));
end;

procedure TVideoMinerMainForm.QueueOpenAndPlayFile(const FileName: string);
begin
  if FileName = '' then
    Exit;

  FPendingOpenFiles.Add(FileName);
  PostMessage(Handle, WM_VM_OPEN_PENDING, 0, 0);
end;

procedure TVideoMinerMainForm.ProcessOpenQueue;
var
  FileName: string;
begin
  if FProcessingOpenQueue then
    Exit;

  FProcessingOpenQueue := True;
  try
    while FPendingOpenFiles.Count > 0 do
    begin
      FileName := FPendingOpenFiles[0];
      FPendingOpenFiles.Delete(0);
      OpenAndPlayFile(FileName);
    end;
  finally
    FProcessingOpenQueue := False;
  end;
end;

procedure TVideoMinerMainForm.ConfigureCurrentFileWatch;
var
  Folder: string;
begin
  if FFolderWatcher = nil then
    Exit;

  if FVideoFile = '' then
  begin
    FFolderWatcher.Stop;
    FWatchedFolder := '';
    Exit;
  end;

  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(FVideoFile));
  if SameText(FWatchedFolder, Folder) then
    Exit;

  FFolderWatcher.Stop;
  FWatchedFolder := Folder;
  FFolderWatcher.FolderPath := Folder;
  FFolderWatcher.IncludeSubFolders := False;
  FFolderWatcher.FirstScanDone := True;
  FFolderWatcher.Start;
end;

function TVideoMinerMainForm.CurrentFileInList(
  const FileNames: TStringList): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (FileNames = nil) or (FVideoFile = '') then
    Exit;

  for I := 0 to FileNames.Count - 1 do
  begin
    if SameText(ExpandFileName(FileNames[I]), ExpandFileName(FVideoFile)) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TVideoMinerMainForm.ReadCurrentFileStamp(
  out LastWriteTime: TDateTime; out Size: Int64): Boolean;
var
  SearchRec: TSearchRec;
begin
  LastWriteTime := 0;
  Size := -1;
  Result := False;
  if FVideoFile = '' then
    Exit;

  if FindFirst(FVideoFile, faAnyFile, SearchRec) <> 0 then
    Exit;
  try
    if (SearchRec.Attr and faDirectory) <> 0 then
      Exit;

    LastWriteTime := SearchRec.TimeStamp;
    Size := SearchRec.Size;
    Result := True;
  finally
    FindClose(SearchRec);
  end;
end;

function TVideoMinerMainForm.CurrentFileCanBeRead: Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  if FVideoFile = '' then
    Exit;

  try
    Stream := TFileStream.Create(FVideoFile, fmOpenRead or fmShareDenyNone);
    try
      Result := True;
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TVideoMinerMainForm.ScheduleCurrentFileReload;
begin
  if (FReloadCurrentFileTimer = nil) or (FVideoFile = '') or
     FReloadingCurrentFile then
    Exit;

  FPendingReloadHasStamp := False;
  FReloadCurrentFileTimer.Enabled := False;
  FReloadCurrentFileTimer.Enabled := True;
end;

procedure TVideoMinerMainForm.FolderWatchFileChange(Sender: TObject;
  const AddFiles, DelFiles, UpdateFiles: TStringList);
begin
  if FReloadingCurrentFile then
    Exit;

  if CurrentFileInList(AddFiles) or CurrentFileInList(DelFiles) or
     CurrentFileInList(UpdateFiles) then
    ScheduleCurrentFileReload;
end;

procedure TVideoMinerMainForm.ReloadCurrentFileTimer(Sender: TObject);
var
  FileName: string;
  LastWriteTime: TDateTime;
  Size: Int64;
begin
  if FReloadCurrentFileTimer <> nil then
    FReloadCurrentFileTimer.Enabled := False;

  if (FVideoFile = '') or FReloadingCurrentFile then
    Exit;

  if (not ReadCurrentFileStamp(LastWriteTime, Size)) or
     (not CurrentFileCanBeRead) then
  begin
    if FReloadCurrentFileTimer <> nil then
      FReloadCurrentFileTimer.Enabled := True;
    Exit;
  end;

  if (not FPendingReloadHasStamp) or
     (FPendingReloadLastWriteTime <> LastWriteTime) or
     (FPendingReloadSize <> Size) then
  begin
    FPendingReloadLastWriteTime := LastWriteTime;
    FPendingReloadSize := Size;
    FPendingReloadHasStamp := True;
    if FReloadCurrentFileTimer <> nil then
      FReloadCurrentFileTimer.Enabled := True;
    Exit;
  end;

  FPendingReloadHasStamp := False;
  if (FVideoFileLastWriteTime = LastWriteTime) and (FVideoFileSize = Size) then
    Exit;

  FileName := FVideoFile;
  FReloadingCurrentFile := True;
  try
    LoadVideoFile(FileName, False, False);
  finally
    FReloadingCurrentFile := False;
  end;
end;

procedure TVideoMinerMainForm.UpdateCurrentFileStamp;
begin
  if not ReadCurrentFileStamp(FVideoFileLastWriteTime, FVideoFileSize) then
  begin
    FVideoFileLastWriteTime := 0;
    FVideoFileSize := -1;
  end;
end;

procedure TVideoMinerMainForm.WMOpenPending(var Message: TMessage);
begin
  ProcessOpenQueue;
  Message.Result := 1;
end;

procedure TVideoMinerMainForm.RestartPlaybackTimer(Sender: TObject);
var
  TargetMs: Integer;
  FrameAlreadyShown: Boolean;
  FastSeek: Boolean;
begin
  if not FPlaybackController.ConsumeRestart(TargetMs, FrameAlreadyShown,
    FastSeek) then
    Exit;

  if (FVideoFile = '') or (TargetMs < 0) or (TargetMs >= FSeekMaxMs) then
    Exit;

  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format('restart_playback target_ms=%d',
      [TargetMs]));
  FPlaybackController.StartPlaybackAtMs(FDecoder, FVideoFile, FVideoInfo,
    FEndAction, FChapterManager, FSeekMaxMs, TargetMs, LastFrameSeekPositionMs,
    FrameAlreadyShown, FastSeek, FCurrentVideoPositionMs, FSeekPositionMs,
    FLoopSegmentStartMs, FLoopSegmentEndMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, SetStatusCaption);
end;

procedure TVideoMinerMainForm.WMNCHitTest(var Message: TWMNCHitTest);
begin
  inherited;
  UpdateFrameGuideVisibility;
  if FWindowModeController <> nil then
    FWindowModeController.HitTestBorderlessResize(
      Point(Message.XPos, Message.YPos), Message.Result);
end;

procedure TVideoMinerMainForm.WMNCCalcSize(var Message: TMessage);
begin
  inherited;
  HandleBorderlessNCCalcSize(Message);
end;

procedure TVideoMinerMainForm.WMMove(var Message: TWMMove);
begin
  inherited;
  if FWindowModeController <> nil then
    FWindowModeController.HandleMove;
end;

procedure TVideoMinerMainForm.WMSize(var Message: TWMSize);
begin
  inherited;
  if FWindowModeController <> nil then
    FWindowModeController.HandleSize;
  if FThumbnailBrowser <> nil then
    TResizeEdgeHelper.AdjustEdges(FThumbnailBrowser);
  UpdateFrameGuideLayout;
end;

procedure TVideoMinerMainForm.CMDialogKey(var Message: TCMDialogKey);
begin
  if (Message.CharCode = VK_TAB) and
     (KeyDataToShiftState(Message.KeyData) = []) then
  begin
    if (FWindowModeController <> nil) and
       (not FWindowModeController.BossMode) then
      ToggleThumbnailBrowser;
    Message.Result := 1;
    Exit;
  end;

  inherited;
end;

procedure TVideoMinerMainForm.WMCopyData(var Message: TWMCopyData);
var
  FileName: string;
begin
  if (Message.CopyDataStruct <> nil) and
     (Message.CopyDataStruct.dwData = COPYDATA_OPEN_FILE) then
  begin
    if WindowState = wsMinimized then
      WindowState := wsNormal;
    Application.Restore;
    BringToFront;
    SetForegroundWindow(Handle);

    FileName := '';
    if (Message.CopyDataStruct.cbData > SizeOf(Char)) and
       (Message.CopyDataStruct.lpData <> nil) then
      FileName := PChar(Message.CopyDataStruct.lpData);

    if FileName <> '' then
      QueueOpenAndPlayFile(FileName);

    Message.Result := 1;
  end
  else
    inherited;
end;

end.
