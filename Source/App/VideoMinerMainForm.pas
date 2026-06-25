unit VideoMinerMainForm;

// VideoMiner のメインフォーム。GUI イベントを受け、各 controller と表示/音声/設定を接続する。
// 実処理は専用ユニットへ寄せ、ここではアプリ全体の状態橋渡しと Windows メッセージ受け口を担当する。

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  System.Diagnostics, System.Math, System.Types,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls, FFmpegDecoder,
  FFmpegDecoderTypes, ResizeEdges, ShortcutAction,
  VideoMinerAudioPlayback,
  VideoMinerChapterController, VideoMinerCommandController,
  VideoMinerCurrentFileReloadController, VideoMinerMediaList, VideoMinerDebugLog,
  VideoMinerExternalOpenController, VideoMinerFrameClipboard, VideoMinerFrameGuideController,
  VideoMinerInfoController, VideoMinerMediaLoadController, VideoMinerMediaOpen,
  VideoMinerMediaSession, VideoMinerSettings,
  VideoMinerNavigationController, VideoMinerSeekHoverPreviewController, VideoMinerThumbnailBrowserController,
  VideoMinerPlaybackController, VideoMinerPlaybackTiming,
  VideoMinerVideoView, VideoMinerWindowChrome, VideoMinerWindowModeController;

const
  WM_VM_OPEN_PENDING = WM_APP + 1; // 他プロセスから受けたファイルを安全なタイミングで開く独自メッセージ
  WM_VM_STARTUP_OPEN = WM_APP + 2; // フォーム表示後に起動時ファイルを開く独自メッセージ
  WM_VM_NAVIGATE = WM_APP + 3; // マウス戻る/進むなどからの前後動画移動を遅延実行する独自メッセージ

type
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
    FSeekHoverPreviewDecoder         : TFFmpegDecoder;                  // シークバー hover プレビュー専用デコーダ
    FAudioPlayback                   : TVideoMinerAudioPlayback;        // 音声出力と音量状態の管理
    FMediaList                       : TVideoMinerMediaList;            // 同じフォルダ内の動画一覧
    FMediaLoadController             : TVideoMinerMediaLoadController;  // 動画読み込み前後の状態反映
    FMediaSession                    : TVideoMinerMediaSession;         // 現在動画と再生位置の状態
    FVideoView                       : TVideoMinerVideoView;            // 動画表示と overlay 入力の窓口
    FUpdatingSeek                    : Boolean;                         // コードからシーク位置を更新中か
    FMainDecoderPreparedFrameMs      : Integer;                         // main decoder で直前表示した再生準備済みフレーム位置
    FSeeking                         : Boolean;                         // シーク処理中か
    FSeekGuardTargetMs               : Integer;                         // シーク直後に再生 tick を守る対象位置 ms
    FSeekGuardRemaining              : Integer;                         // シーク guard を残す tick 数
    FReverseWheelSeekPending         : Boolean;                         // 逆方向ホイールシークの実デコードを保留中か
    FReverseWheelSeekPositionMs      : Integer;                         // 保留中の逆方向ホイールシーク先 ms
    FReverseWheelSeekTimer           : TTimer;                          // 逆方向ホイールシークを落ち着くまで遅延するタイマー
    FRestartPlaybackTimer            : TTimer;                          // シーク後に再生再開を遅延させるタイマー
    FCurrentFileReloadController     : TVideoMinerCurrentFileReloadController; // 現在ファイルの外部更新監視
    FExternalOpenController          : TVideoMinerExternalOpenController; // 外部からの open 要求制御
    FInfoController                  : TVideoMinerInfoController;       // caption/情報表示/シーク進捗制御
    FNavigationController            : TVideoMinerNavigationController; // フォルダ内前後移動と入力抑止
    FPlaybackController              : TVideoMinerPlaybackController;   // 再生/シーク/終端処理の制御
    FCommandController               : TVideoMinerCommandController;    // overlay とショートカットのコマンド接続
    FSeekHoverPreviewController      : TVideoMinerSeekHoverPreviewController; // シークバー hover プレビュー制御
    FWindowModeController            : TVideoMinerWindowModeController; // 全画面/枠なし/ボスが来たモードの制御
    FChapterController               : TVideoMinerChapterController;    // 手動/自動チャプターとチェック状態の管理
    FThumbnailBrowserController      : TVideoMinerThumbnailBrowserController; // 同一フォルダ内動画の一覧表示制御
    FSafeAreaVisible                 : Boolean;                         // 90% セーフエリア確認枠を表示中か
    FShortcuts                       : TShortcutAction;                 // キーボードショートカット登録先
    FStartupOpenAutoPlay             : Boolean;                         // 起動後に開くファイルを自動再生するか
    FStartupOpenFile                 : string;                          // 起動後に開く指定ファイル
    FStartupOpenRemembered           : Boolean;                         // 起動後に前回ファイルを復元するか
    FStartupOpenTimer                : TTimer;                          // 初回描画後に起動時 open を遅延実行するタイマー
    FTitleIcon                       : TImage;                          // 独自タイトルバー左端のアイコン
    FFrameGuideController            : TVideoMinerFrameGuideController; // hover 用フォーム枠制御
    FLoadingVideo                    : Boolean;                         // 動画読み込み処理中か
    FPreviousApplicationOnMessage    : TMessageEvent;                   // 前段のアプリ全体メッセージフック
    // 子コントロールへ届いたマウス戻る/進む系入力を前後動画移動として扱う
    procedure ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
    // 独自タイトルバー左端のアプリアイコンを作る
    procedure InitializeTitleIcon;
    // タイトルバーのボタン背景色を切り替える
    procedure SetCaptionButtonColor(Sender: TObject; Color: TColor);
    // 動画終端時の動作を順に切り替える
    procedure CycleEndAction;
    // 現在フレームをクリップボードへコピーする
    procedure CopyCurrentFrameToClipboard;
    // 再生速度を順に切り替える
    procedure CyclePlaybackRate;
    // 表示だけを90度ずつ回転する
    procedure RotateDisplay90;
    // overlay の終端動作ボタンから切り替えを実行する
    procedure EndActionOverlayClick(Sender: TObject);
    // 全画面表示を切り替える
    procedure ToggleFullScreen;
    // 90% セーフエリア確認枠を切り替える
    procedure ToggleSafeArea;
    // 終端動作ボタンの表示を更新する
    procedure UpdateEndActionButton;
    // 再生速度ボタンの表示を更新する
    procedure UpdatePlaybackRateButton;
    // 最大化ボタンの表示を現在状態に合わせる
    procedure UpdateMaximizeButton;
    // 指定ファイルを開き、必要なら自動再生する
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean;
      RestoreLoopPosition: Boolean = True): Boolean;
    // 前後チャプターへ移動する
    procedure NavigateChapterBy(Delta: Integer);
    // ファイル選択ダイアログから動画を開く
    procedure OpenFromDialog;
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
    // 動画面右クリックからサムネイル一覧を開閉する
    procedure SurfaceRightClick(Sender: TObject);
    // ヘルプキーからヘルプ兼用画面を表示する
    procedure ShowHelpOverlay;
    // 再生中または再生再開待ちか返す
    function PlaybackActiveOrPending: Boolean;
    // controller と UI 状態から現在再生位置を返す
    function CurrentPlaybackPositionMs: Integer;
    // 再生 tick から指定位置へシークする
    procedure SeekPlaybackTickToMs(PositionMs: Integer; FrameAlreadyShown: Boolean);
    // 指定位置へシークし、必要なら再生状態を復元する
    procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
    // ホイール操作の指定位置シーク。停止中の逆方向だけ実デコードを少し遅延する
    procedure SeekByWheelToMs(PositionMs: Integer);
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
    // 起動時 open を初回描画後に実行する
    procedure StartupOpenTimer(Sender: TObject);
    // シーク後の遅延再生再開を処理する
    procedure RestartPlaybackTimer(Sender: TObject);
    // 保留中の逆方向ホイールシークを実行する
    procedure ReverseWheelSeekTimer(Sender: TObject);
    // 終端到達時の停止/ループ/次動画動作を処理する
    procedure FinishPlaybackAtEnd;
    // 別プロセスから渡されたファイル名を受け取る
    procedure WMCopyData(var Message: TWMCopyData); message WM_COPYDATA;
    // マウスの戻る/進むボタンを前後動画移動として扱う
    procedure WMXButtonDown(var Message: TMessage); message WM_XBUTTONDOWN;
    // 通常表示時の移動を window controller へ通知する
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    // 枠なしフォームのリサイズ hit test を window controller へ委譲する
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    // 枠なしフォームの非クライアント領域を調整する
    procedure WMNCCalcSize(var Message: TMessage); message WM_NCCALCSIZE;
    // 保留中の open キュー処理を実行する
    procedure WMOpenPending(var Message: TMessage); message WM_VM_OPEN_PENDING;
    // 起動時のファイル読み込みをフォーム表示後に実行する
    procedure WMStartupOpen(var Message: TMessage); message WM_VM_STARTUP_OPEN;
    // 入力フックから予約された前後動画移動を実行する
    procedure WMNavigate(var Message: TMessage); message WM_VM_NAVIGATE;
    // 通常表示時のサイズ変更を window controller へ通知する
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    // VCL のフォーカス移動処理より先に Tab を一覧切り替えとして拾う
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    // 指定ミリ秒位置のフレームを表示する
    function ShowFrameAtMs(const PositionMs: Integer): Boolean;
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
    // 起動後に指定ファイルを開くよう予約する
    procedure QueueStartupOpenFile(const FileName: string; AutoPlay: Boolean);
    // 起動後に前回ファイルを開くよう予約する
    procedure QueueStartupOpenRemembered;
  end;

var
  VideoMinerForm: TVideoMinerMainForm;

implementation

const
  REVERSE_WHEEL_SEEK_DELAY_MS  = 350;       // 逆方向ホイールの連続入力をまとめる待ち時間 ms
  SEEK_RESTART_DELAY_MS         = 15;        // シーク後に再生再開を遅延させる時間 ms
  TITLE_BAR_COLOR               = $00171617; // 独自タイトルバーの通常背景色
  CLOSE_BUTTON_HOVER_COLOR      = $00232323; // 閉じるボタン hover 時の背景色
  CAPTION_BUTTON_HOVER_COLOR    = $00232323; // 最小化/最大化ボタン hover 時の背景色
  MIN_FORM_WIDTH                = 520;        // 下部操作バーが破綻しない最小フォーム幅
  MIN_FORM_HEIGHT               = 360;        // 動画表示と下部操作バーを残せる最小フォーム高さ

{$R *.dfm}

procedure TVideoMinerMainForm.ApplicationMessage(var Msg: TMsg;
  var Handled: Boolean);
const
  VK_BROWSER_BACK = $A6;
  VK_BROWSER_FORWARD = $A7;
  WM_XBUTTONDBLCLK = $020D;
var
  AppCommand: Word;
  Button: Word;
  ClassName: array[0..127] of Char;
  ClassText: string;
  ShouldLog: Boolean;
begin
  if Assigned(FPreviousApplicationOnMessage) then
    FPreviousApplicationOnMessage(Msg, Handled);

  Button := Word((NativeUInt(Msg.wParam) shr 16) and $FFFF);
  AppCommand := Word((NativeUInt(Msg.lParam) shr 16) and $FFFF);
  ShouldLog := False;
  case Msg.message of
    WM_XBUTTONDOWN, WM_XBUTTONUP, WM_XBUTTONDBLCLK, WM_APPCOMMAND:
      ShouldLog := True;
    WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP:
      ShouldLog := (Msg.wParam = VK_BROWSER_BACK) or
        (Msg.wParam = VK_BROWSER_FORWARD);
  end;

  if ShouldLog and VideoMinerDebugLogEnabled then
  begin
    ClassText := '';
    if (Msg.hwnd <> 0) and (GetClassName(Msg.hwnd, ClassName,
      Length(ClassName)) > 0) then
      ClassText := ClassName;

    WriteVideoMinerDebugLog(Format(
      'input_msg hwnd=$%s class="%s" msg=$%s wparam=$%s lparam=$%s key=%d xbutton=%d appcmd_raw=$%s handled=%s',
      [IntToHex(NativeInt(Msg.hwnd), 8), ClassText, IntToHex(Msg.message, 4),
       IntToHex(NativeInt(Msg.wParam), 8), IntToHex(NativeInt(Msg.lParam), 8),
       Msg.wParam and $FFFF, Button, IntToHex(AppCommand, 4),
       BoolToStr(Handled, True)]));
  end;

  if Handled or (FNavigationController = nil) then
    Exit;

  if Msg.message = WM_XBUTTONDOWN then
  begin
    case Button of
      1:
        begin
          Handled := True;
          if FLoadingVideo then
            WriteVideoMinerDebugLog('input_xbutton_ignore_loading delta=-1')
          else
          begin
            PostMessage(Handle, WM_VM_NAVIGATE, 1, 0);
            WriteVideoMinerDebugLog('input_xbutton_queue delta=-1');
          end;
        end;
      2:
        begin
          Handled := True;
          if FLoadingVideo then
            WriteVideoMinerDebugLog('input_xbutton_ignore_loading delta=1')
          else
          begin
            PostMessage(Handle, WM_VM_NAVIGATE, 2, 0);
            WriteVideoMinerDebugLog('input_xbutton_queue delta=1');
          end;
        end;
    end;
  end
  else if (Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN) then
  begin
    case Msg.wParam of
      VK_BROWSER_BACK:
        begin
          Handled := True;
          if FLoadingVideo then
            WriteVideoMinerDebugLog('input_browser_key_ignore_loading delta=-1')
          else
          begin
            PostMessage(Handle, WM_VM_NAVIGATE, 1, 0);
            WriteVideoMinerDebugLog('input_browser_key_queue delta=-1');
          end;
        end;
      VK_BROWSER_FORWARD:
        begin
          Handled := True;
          if FLoadingVideo then
            WriteVideoMinerDebugLog('input_browser_key_ignore_loading delta=1')
          else
          begin
            PostMessage(Handle, WM_VM_NAVIGATE, 2, 0);
            WriteVideoMinerDebugLog('input_browser_key_queue delta=1');
          end;
        end;
    end;
  end;
end;

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
var
  AudioSettings: TVideoMinerAudioSettings;
{$IFDEF DEBUG}
  StepWatch: TStopwatch;
  TotalWatch: TStopwatch;
{$ENDIF}
begin
{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;
  StepWatch := TStopwatch.StartNew;
  WriteVideoMinerSlowLog('form_create begin');
{$ENDIF}
  OnKeyUp := FormKeyUp;
  PanelTitleBar.Color := TITLE_BAR_COLOR;
  PanelCloseButton.Color := TITLE_BAR_COLOR;
  PanelMaximizeButton.Color := TITLE_BAR_COLOR;
  PanelMinimizeButton.Color := TITLE_BAR_COLOR;
  Constraints.MinWidth := MIN_FORM_WIDTH;
  Constraints.MinHeight := MIN_FORM_HEIGHT;
  InitializeTitleIcon;
  FMainDecoderPreparedFrameMs := -1;
  FMediaSession := TVideoMinerMediaSession.Create;
  FMediaSession.EndAction := LoadEndAction;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create base_ui_settings_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FShortcuts := TShortcutAction.Create;
  FExternalOpenController := TVideoMinerExternalOpenController.Create(Self,
    WM_VM_OPEN_PENDING);
  FExternalOpenController.OnOpenAndPlay := OpenAndPlayFile;
  FDecoder := TFFmpegDecoder.Create;
  FPreviewDecoder := TFFmpegDecoder.Create;
  FSeekHoverPreviewDecoder := TFFmpegDecoder.Create;
  FAudioPlayback := TVideoMinerAudioPlayback.Create;
  FMediaList := TVideoMinerMediaList.Create;
  FVideoView := TVideoMinerVideoView.Create(ImagePreview);
  FInfoController := TVideoMinerInfoController.Create(Self, LabelAppTitle,
    FMediaSession, FMediaList, FAudioPlayback, FVideoView);
  FInfoController.OnCurrentPosition := CurrentPlaybackPositionMs;
  FNavigationController := TVideoMinerNavigationController.Create(FMediaList,
    FVideoView);
  FNavigationController.OnOpenFile := LoadVideoFile;
  FChapterController := TVideoMinerChapterController.Create(FMediaSession,
    FVideoView);
  FChapterController.OnCurrentPosition := CurrentPlaybackPositionMs;
  FChapterController.OnConfigureLoop := ConfigureLoopSegment;
  FAudioPlayback.OnPcmDecoded := FChapterController.MaybeAutoCheckAudio;
  FThumbnailBrowserController := TVideoMinerThumbnailBrowserController.Create(Self,
    FVideoView.SurfaceControl, FMediaList, FMediaSession);
  FThumbnailBrowserController.OnOpenFile := LoadVideoFile;
  FSeekHoverPreviewController := TVideoMinerSeekHoverPreviewController.Create(Self,
    FVideoView, FSeekHoverPreviewDecoder);
  FVideoView.OnSurfaceRightClick := SurfaceRightClick;
  FVideoView.OnSeekHoverPreview := FSeekHoverPreviewController.SeekHoverPreview;
  FVideoView.OnSeekHoverPreviewEnd := FSeekHoverPreviewController.SeekHoverPreviewEnd;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create core_objects_ms=%.3f total_ms=%.3f ole=%s',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds,
     BoolToStr(FExternalOpenController.OleInitialized, True)]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create thumbnail_browser_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FWindowModeController := TVideoMinerWindowModeController.Create(Self,
    PanelTitleBar, LabelMaximizeButton, FVideoView, StopPlayback);
  FFrameGuideController := TVideoMinerFrameGuideController.Create(Self, Self,
    PanelTitleBar, FWindowModeController);
  FCommandController := TVideoMinerCommandController.Create(FAudioPlayback,
    FVideoView);
  FCommandController.OnAddChapter := FChapterController.AddChapterClick;
  FCommandController.OnChapterNavigate := NavigateChapterBy;
  FCommandController.OnCheckToggle := FChapterController.ToggleCheckClick;
  FCommandController.OnCopyCurrentFrame := CopyCurrentFrameToClipboard;
  FCommandController.OnDeleteChapter := FChapterController.DeleteChapterClick;
  FCommandController.OnEndActionCycle := EndActionOverlayClick;
  FCommandController.OnToggleChapter := FChapterController.ToggleManualChapterAt;
  FCommandController.OnNavigate := FNavigationController.NavigateBy;
  FCommandController.OnOpenDialog := OpenFromDialog;
  FCommandController.OnPlaybackActiveOrPending := PlaybackActiveOrPending;
  FCommandController.OnPlaybackRateCycle := CyclePlaybackRate;
  FCommandController.OnPlayFromCurrentPosition := PlayFromCurrentPosition;
  FCommandController.OnRotateDisplay := RotateDisplay90;
  FCommandController.OnSaveAudioSettings := SaveAudioPlaybackSettings;
  FCommandController.OnSeekByMs := SeekByMs;
  FCommandController.OnSeekByWheel := SeekByWheelToMs;
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
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create controllers_shortcuts_bounds_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  TResizeEdgeHelper.AttachEdges(PanelTitleBar, VIDEO_MINER_RESIZE_BORDER,
    [rdTop]);
  TResizeEdgeHelper.AttachEdges(FVideoView.SurfaceControl,
    VIDEO_MINER_RESIZE_BORDER, [rdBottom, rdLeft, rdRight]);
  if FThumbnailBrowserController <> nil then
    FThumbnailBrowserController.AttachResizeEdges(VIDEO_MINER_RESIZE_BORDER);
  FVideoView.OnBossExitClick := BossExitClick;
  FVideoView.OnBossGesture := BossGesture;
  FChapterController.RefreshOverlay;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create overlays_resize_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FRestartPlaybackTimer := TTimer.Create(Self);
  FRestartPlaybackTimer.Enabled := False;
  FRestartPlaybackTimer.Interval := SEEK_RESTART_DELAY_MS;
  FRestartPlaybackTimer.OnTimer := RestartPlaybackTimer;
  FReverseWheelSeekTimer := TTimer.Create(Self);
  FReverseWheelSeekTimer.Enabled := False;
  FReverseWheelSeekTimer.Interval := REVERSE_WHEEL_SEEK_DELAY_MS;
  FReverseWheelSeekTimer.OnTimer := ReverseWheelSeekTimer;
  FReverseWheelSeekPositionMs := -1;
  FStartupOpenTimer := TTimer.Create(Self);
  FStartupOpenTimer.Enabled := False;
  FStartupOpenTimer.Interval := 120;
  FStartupOpenTimer.OnTimer := StartupOpenTimer;
  FCurrentFileReloadController :=
    TVideoMinerCurrentFileReloadController.Create(FMediaSession);
  FCurrentFileReloadController.OnReload := LoadVideoFile;
  FPlaybackController := TVideoMinerPlaybackController.Create(TimerPlayback,
    FRestartPlaybackTimer, FAudioPlayback, FVideoView, FPreviewDecoder);
  FMediaLoadController := TVideoMinerMediaLoadController.Create(Self,
    FMediaSession, FMediaList, TimerPlayback, FPlaybackController,
    FAudioPlayback, FPreviewDecoder, FVideoView, FCurrentFileReloadController,
    FChapterController, FSeekHoverPreviewController, FNavigationController,
    FThumbnailBrowserController);
  FMediaLoadController.OnSetStatus := FInfoController.SetStatusCaption;
  FMediaLoadController.OnSetTitleBar := FInfoController.SetTitleBarText;
  FMediaLoadController.OnUpdateInfo := FInfoController.UpdateInfo;
  UpdateEndActionButton;
  UpdatePlaybackRateButton;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create timers_watchers_playback_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FMediaSession.CurrentVideoPositionMs := -1;
  FMediaSession.SeekPositionMs := 0;
  FMediaSession.SeekMaxMs := 0;
  FMediaSession.LoopSegmentStartMs := -1;
  FMediaSession.LoopSegmentEndMs := -1;
  AudioSettings := LoadAudioSettings;
  FAudioPlayback.VolumePercent := AudioSettings.VolumePercent;
  FAudioPlayback.Muted := AudioSettings.Muted;
  FVideoView.Muted := FAudioPlayback.Muted;
  if FAudioPlayback.Muted then
    FVideoView.VolumePercent := 0
  else
    FVideoView.VolumePercent := FAudioPlayback.VolumePercent;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create audio_settings_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FInfoController.SetStatusCaption('No video loaded');
  FPreviousApplicationOnMessage := Application.OnMessage;
  Application.OnMessage := ApplicationMessage;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('form_create drop_agent_status_ms=%.3f total_ms=%.3f',
    [StepWatch.Elapsed.TotalMilliseconds, TotalWatch.Elapsed.TotalMilliseconds]));
  WriteVideoMinerSlowLog(Format('form_create done total_ms=%.3f',
    [TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

// フォーム破棄時にデコーダを解放する
procedure TVideoMinerMainForm.FormDestroy(Sender: TObject);
begin
  WriteVideoMinerStartupLog('form_destroy begin');
  try
    Application.OnMessage := FPreviousApplicationOnMessage;
    if FChapterController <> nil then
    begin
      FChapterController.SaveManualChapterState;
      FChapterController.SaveLoopPlaybackPosition;
    end;
    SaveAudioPlaybackSettings;
    if TimerPlayback <> nil then
      TimerPlayback.Enabled := False;
    if FVideoView <> nil then
      FVideoView.PlaybackActive := False;
    if FRestartPlaybackTimer <> nil then
      FRestartPlaybackTimer.Enabled := False;
    if FReverseWheelSeekTimer <> nil then
      FReverseWheelSeekTimer.Enabled := False;
    if FStartupOpenTimer <> nil then
      FStartupOpenTimer.Enabled := False;
    if FCurrentFileReloadController <> nil then
      FCurrentFileReloadController.Stop;
    if FAudioPlayback <> nil then
      FAudioPlayback.Stop;
    FCommandController.Free;
    FShortcuts.Free;
    FExternalOpenController.Free;
    FMediaLoadController.Free;
    FPlaybackController.Free;
    FCurrentFileReloadController.Free;
    if FWindowModeController <> nil then
      FWindowModeController.SaveWindowBounds;
    SaveEndAction(FMediaSession.EndAction);
    FFrameGuideController.Free;
    FWindowModeController.Free;
    FThumbnailBrowserController.Free;
    FSeekHoverPreviewController.Free;
    FChapterController.Free;
    FNavigationController.Free;
    FInfoController.Free;
    FVideoView.Free;
    FMediaList.Free;
    FMediaSession.Free;
    FAudioPlayback.Free;
    FSeekHoverPreviewDecoder.Free;
    FPreviewDecoder.Free;
    FDecoder.Free;
    FTitleIcon.Free;
    WriteVideoMinerStartupLog('form_destroy done');
  except
    on E: Exception do
      WriteVideoMinerStartupLog('form_destroy_exception class="' + E.ClassName +
        '" message="' + E.Message + '"');
  end;
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
    FInfoController.SetStatusCaption('90% safe area guide on.')
  else
    FInfoController.SetStatusCaption('90% safe area guide off.');
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
  Result := (FThumbnailBrowserController <> nil) and
    FThumbnailBrowserController.HandleMouseWheel(Shift, WheelDelta, MousePos);
  if Result then
    Exit;

  Result := (FVideoView <> nil) and
    FVideoView.HandleMouseWheel(Shift, WheelDelta, MousePos);
  if Result and (FVideoView <> nil) and
     FVideoView.ConsumeZoomFrameRefreshNeeded and
     (not PlaybackActiveOrPending) and (FMediaSession.VideoFile <> '') then
    ShowFrameAtMs(CurrentPlaybackPositionMs);
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
  FMainDecoderPreparedFrameMs := -1;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_show_frame_at_begin requested_ms=%d current_ms=%d seek_ms=%d',
    [PositionMs, FMediaSession.CurrentVideoPositionMs,
     FMediaSession.SeekPositionMs]));
{$ENDIF}
  if (FMediaSession.VideoFile = '') or (FDecoder = nil) then
  begin
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'main_show_frame_at_skip requested_ms=%d video_empty=%s decoder_nil=%s',
      [PositionMs, BoolToStr(FMediaSession.VideoFile = '', True),
       BoolToStr(FDecoder = nil, True)]));
{$ENDIF}
    Exit;
  end;

  if not FPlaybackController.ShowFrameNearMs(PositionMs, FMediaSession.SeekMaxMs,
    ShownPositionMs, ErrorMessage) then
  begin
    if (FVideoView <> nil) and FVideoView.ShowFrameAt(FDecoder, PositionMs,
      ErrorMessage, True, False) then
    begin
      ShownPositionMs := PositionMs;
      FMainDecoderPreparedFrameMs := PositionMs;
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'main_show_frame_at_fallback_main requested_ms=%d shown_ms=%d',
        [PositionMs, ShownPositionMs]));
{$ENDIF}
    end
    else
    begin
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'main_show_frame_at_failed requested_ms=%d err="%s"',
        [PositionMs, ErrorMessage]));
{$ENDIF}
      FInfoController.SetStatusCaption('Failed to decode frame: ' + ErrorMessage);
      Exit;
    end;
  end;

  FMediaSession.CurrentVideoPositionMs := ShownPositionMs;
  FInfoController.UpdateInfo;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_show_frame_at_done requested_ms=%d shown_ms=%d seek_ms=%d',
    [PositionMs, ShownPositionMs, FMediaSession.SeekPositionMs]));
{$ENDIF}
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
  PositionMs: Integer;
begin
  if PlaybackActiveOrPending then
  begin
    FInfoController.SetStatusCaption('Pause video before copying frame.');
    Exit;
  end;

  if FMediaSession.VideoFile <> '' then
  begin
    PositionMs := CurrentPlaybackPositionMs;
    ShowFrameAtMs(PositionMs);
  end;

  FrameBitmap := nil;
  if FVideoView <> nil then
    FrameBitmap := FVideoView.CurrentFrameBitmap;
  if (FrameBitmap = nil) or (FrameBitmap.Width <= 0) or (FrameBitmap.Height <= 0) then
  begin
    FInfoController.SetStatusCaption('No frame to copy.');
    Exit;
  end;

  if CopyVideoFrameBitmapToClipboard(FrameBitmap, FMediaSession.VideoInfo.HasAlpha, ErrorMessage) then
    FInfoController.SetStatusCaption('Copied current frame to clipboard.')
  else
    FInfoController.SetStatusCaption('Failed to copy frame: ' + ErrorMessage);
end;

procedure TVideoMinerMainForm.CycleEndAction;
begin
  FMediaSession.EndAction := FPlaybackController.NextEndAction(FMediaSession.EndAction);
  UpdateEndActionButton;
  ConfigureLoopSegment(CurrentPlaybackPositionMs);
  SaveEndAction(FMediaSession.EndAction);
  if FChapterController <> nil then
    FChapterController.SaveLoopPlaybackPosition;
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
    FInfoController.UpdateInfo;
end;

procedure TVideoMinerMainForm.RotateDisplay90;
var
  FrameShown: Boolean;
  PositionMs: Integer;
  WasPlaying: Boolean;
begin
  if FVideoView = nil then
    Exit;

  WasPlaying := PlaybackActiveOrPending;
  PositionMs := CurrentPlaybackPositionMs;
  if FPlaybackController <> nil then
    FPlaybackController.StopForSeek;
  FVideoView.RotateDisplay90;
  if FSeekHoverPreviewController <> nil then
    FSeekHoverPreviewController.Clear;

  if FMediaSession.VideoFile <> '' then
  begin
    PositionMs := Max(0, Min(FMediaSession.SeekMaxMs, PositionMs));
    FrameShown := ShowFrameAtMs(PositionMs);
    if WasPlaying then
      StartPlaybackAtMs(PositionMs, FrameShown)
    else if FInfoController <> nil then
      FInfoController.UpdateInfo;
  end;

  if FInfoController <> nil then
    FInfoController.SetStatusCaption(Format('Display rotation: +%d degrees.',
      [FVideoView.DisplayRotationOffset]));
end;

procedure TVideoMinerMainForm.EndActionOverlayClick(Sender: TObject);
begin
  CycleEndAction;
end;

procedure TVideoMinerMainForm.UpdateEndActionButton;
begin
  if (FVideoView = nil) or (FPlaybackController = nil) then
    Exit;

  FVideoView.EndActionText := FPlaybackController.EndActionText(FMediaSession.EndAction);
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

procedure TVideoMinerMainForm.OpenFromDialog;
begin
  OpenDialogVideo.InitialDir := VideoMinerOpenDialogInitialDir(FMediaSession.VideoFile);
  if OpenDialogVideo.Execute then
    LoadVideoFile(OpenDialogVideo.FileName, False);
end;

function TVideoMinerMainForm.TryRestoreLoopPlaybackPosition: Boolean;
var
  ErrorMessage: string;
  PositionMs: Integer;
  ShownPositionMs: Integer;
begin
  Result := False;
  if (FChapterController = nil) or (FMediaSession.VideoFile = '') or
     (FPlaybackController = nil) or (FMediaSession.EndAction <> eaLoop) or
     (not FChapterController.HasManualChapters) then
    Exit;

  if not LoadManualChapterPlaybackPosition(FMediaSession.VideoFile, FMediaSession.SeekMaxMs,
    PositionMs) then
    Exit;

  if not FPlaybackController.ShowFrameNearMs(PositionMs, FMediaSession.SeekMaxMs,
    ShownPositionMs, ErrorMessage) then
    Exit;

  FMediaSession.CurrentVideoPositionMs := ShownPositionMs;
  FUpdatingSeek := True;
  try
    FMediaSession.SeekPositionMs := ShownPositionMs;
  finally
    FUpdatingSeek := False;
  end;
  FInfoController.UpdatePlaybackProgress(FMediaSession.SeekPositionMs);
  ConfigureLoopSegment(FMediaSession.SeekPositionMs);
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
    Result := Max(0, Min(FMediaSession.SeekMaxMs, FMediaSession.SeekPositionMs));
    Exit;
  end;

  Result := FPlaybackController.CurrentPositionMs(PlaybackActiveOrPending,
    FMediaSession.SeekPositionMs, FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekMaxMs);
end;

function TVideoMinerMainForm.LoadVideoFile(const FileName: string;
  AutoPlay: Boolean; RestoreLoopPosition: Boolean): Boolean;
var
  ErrorMessage: string;
  OpenResult: TVideoMinerMediaOpenResult;
{$IFDEF DEBUG}
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  ValidateMs: Double;
  CleanupMs: Double;
  OpenMs: Double;
  FirstFrameMs: Double;
  AutoPlayMs: Double;
{$ENDIF}
begin
  Result := False;
  if FLoadingVideo then
  begin
    WriteVideoMinerDebugLog('open_skip already_loading file="' +
      ExtractFileName(FileName) + '"');
    Exit;
  end;
  FLoadingVideo := True;
  try
    try
      WriteVideoMinerStartupLog(Format(
        'open_begin file="%s" drive="%s" autoplay=%s restore_loop=%s',
        [ExtractFileName(FileName), ExtractFileDrive(FileName),
         BoolToStr(AutoPlay, True), BoolToStr(RestoreLoopPosition, True)]));
{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;

  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  if not ValidateVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
{$IFDEF DEBUG}
    ValidateMs := StepWatch.Elapsed.TotalMilliseconds;
    WriteVideoMinerSlowLog(Format(
      'open_failed step="validate" file="%s" drive="%s" autoplay=%s validate_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       BoolToStr(AutoPlay, True), ValidateMs, TotalWatch.Elapsed.TotalMilliseconds,
       ErrorMessage]));
{$ENDIF}
    FInfoController.SetStatusCaption(ErrorMessage);
    Exit;
  end;
{$IFDEF DEBUG}
  ValidateMs := StepWatch.Elapsed.TotalMilliseconds;

  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  if FVideoView <> nil then
    FVideoView.BeginLoadingIndicator;
  Application.ProcessMessages;
  try
    FMediaLoadController.BeginLoadCleanup(FUpdatingSeek, FSeeking,
      FSeekGuardRemaining);
    Application.ProcessMessages;
{$IFDEF DEBUG}
    CleanupMs := StepWatch.Elapsed.TotalMilliseconds;

    StepWatch := TStopwatch.StartNew;
{$ENDIF}
    if not OpenVideoMinerMediaFile(FileName, FDecoder, FPreviewDecoder,
      FMediaList, OpenResult) then
    begin
{$IFDEF DEBUG}
      OpenMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}
      FMediaLoadController.ApplyOpenFailure(OpenResult.ErrorMessage);
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'open_failed step="decoder_open" file="%s" drive="%s" autoplay=%s validate_ms=%.3f cleanup_ms=%.3f open_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(FileName), ExtractFileDrive(FileName),
         BoolToStr(AutoPlay, True), ValidateMs, CleanupMs, OpenMs,
         TotalWatch.Elapsed.TotalMilliseconds, OpenResult.ErrorMessage]));
{$ENDIF}
      Exit;
    end;
{$IFDEF DEBUG}
    OpenMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}

    FMediaLoadController.ApplyOpenSuccess(OpenResult, FUpdatingSeek);
    Application.ProcessMessages;
{$IFDEF DEBUG}
    StepWatch := TStopwatch.StartNew;
{$ENDIF}
    if (not RestoreLoopPosition) or (not TryRestoreLoopPlaybackPosition) then
      ShowFrameAtMs(0);
{$IFDEF DEBUG}
    FirstFrameMs := StepWatch.Elapsed.TotalMilliseconds;

    StepWatch := TStopwatch.StartNew;
{$ENDIF}
    if AutoPlay then
      PlayFromCurrentPosition;
{$IFDEF DEBUG}
    AutoPlayMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}

    RememberVideoMinerMediaFile(OpenResult.FileName);
    Result := True;
    WriteVideoMinerStartupLog(Format(
      'open_done_release file="%s" duration_ms=%d fps=%.3f',
      [ExtractFileName(FMediaSession.VideoFile), FMediaSession.SeekMaxMs,
       FMediaSession.VideoInfo.Fps]));
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'open_done file="%s" drive="%s" autoplay=%s restore_loop=%s validate_ms=%.3f cleanup_ms=%.3f open_ms=%.3f first_frame_ms=%.3f autoplay_ms=%.3f total_ms=%.3f duration_ms=%d fps=%.3f',
      [ExtractFileName(FMediaSession.VideoFile), ExtractFileDrive(FMediaSession.VideoFile),
       BoolToStr(AutoPlay, True), BoolToStr(RestoreLoopPosition, True),
       ValidateMs, CleanupMs, OpenMs, FirstFrameMs, AutoPlayMs,
       TotalWatch.Elapsed.TotalMilliseconds, FMediaSession.SeekMaxMs, FMediaSession.VideoInfo.Fps]));
{$ENDIF}
  finally
    if FVideoView <> nil then
      FVideoView.EndLoadingIndicator;
  end;
    except
      on E: Exception do
      begin
        ErrorMessage := E.ClassName + ': ' + E.Message;
        WriteVideoMinerStartupLog('open_exception file="' +
          ExtractFileName(FileName) + '" message="' + ErrorMessage + '"');
        if FInfoController <> nil then
          FInfoController.SetStatusCaption(ErrorMessage);
        Result := False;
      end;
    end;
  finally
    FLoadingVideo := False;
  end;
end;

function TVideoMinerMainForm.OpenAndPlayFile(const FileName: string): Boolean;
begin
  Result := LoadVideoFile(FileName, True);
end;

function TVideoMinerMainForm.OpenRememberedFile: Boolean;
var
  ErrorMessage: string;
  FileName: string;
{$IFDEF DEBUG}
  ResolveWatch: TStopwatch;
{$ENDIF}
begin
  Result := False;
  WriteVideoMinerStartupLog('startup_remembered_resolve_begin');

{$IFDEF DEBUG}
  ResolveWatch := TStopwatch.StartNew;
{$ENDIF}
  if not ResolveRememberedVideoMinerMediaFile(FileName, ErrorMessage) then
  begin
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'startup remembered_resolve_failed resolve_ms=%.3f err="%s"',
      [ResolveWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
    WriteVideoMinerStartupLog('startup_remembered_resolve_failed err="' +
      ErrorMessage + '"');
    if ErrorMessage <> '' then
      FInfoController.SetStatusCaption(ErrorMessage);
    Exit;
  end;
  WriteVideoMinerStartupLog('startup_remembered_resolve_done file="' +
    ExtractFileName(FileName) + '" drive="' + ExtractFileDrive(FileName) + '"');
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'startup remembered_resolve_done file="%s" drive="%s" resolve_ms=%.3f',
    [ExtractFileName(FileName), ExtractFileDrive(FileName),
     ResolveWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}

  Result := LoadVideoFile(FileName, False);
end;

procedure TVideoMinerMainForm.QueueStartupOpenFile(const FileName: string;
  AutoPlay: Boolean);
begin
  FStartupOpenFile := FileName;
  FStartupOpenAutoPlay := AutoPlay;
  FStartupOpenRemembered := False;
  PostMessage(Handle, WM_VM_STARTUP_OPEN, 0, 0);
end;

procedure TVideoMinerMainForm.QueueStartupOpenRemembered;
begin
  if SameText(GetEnvironmentVariable('VIDEOMINER_DISABLE_STARTUP_RESTORE'), '1') then
  begin
    WriteVideoMinerStartupLog('startup_remembered_skip disabled_by_env');
    Exit;
  end;

  FStartupOpenFile := '';
  FStartupOpenAutoPlay := False;
  FStartupOpenRemembered := True;
  PostMessage(Handle, WM_VM_STARTUP_OPEN, 0, 0);
end;

procedure TVideoMinerMainForm.PlayFromCurrentPosition;
var
  FrameShown: Boolean;
  RestartFromBeginning: Boolean;
begin
  if FMediaSession.VideoFile = '' then
    Exit;

  FReverseWheelSeekPending := False;
  if FReverseWheelSeekTimer <> nil then
    FReverseWheelSeekTimer.Enabled := False;

  if FVideoView <> nil then
    FVideoView.HidePlaybackStartOverlays;

  FrameShown := FMediaSession.CurrentVideoPositionMs = FMediaSession.SeekPositionMs;
  RestartFromBeginning := (FMediaSession.SeekMaxMs > 0) and
    (FMediaSession.SeekPositionMs >= LastFrameSeekPositionMs);
  if RestartFromBeginning then
  begin
    FUpdatingSeek := True;
    try
      FMediaSession.SeekPositionMs := 0;
    finally
      FUpdatingSeek := False;
    end;
    FrameShown := ShowFrameAtMs(0);
  end;

  StartPlaybackAtMs(FMediaSession.SeekPositionMs, FrameShown);
end;

procedure TVideoMinerMainForm.BossGesture(Sender: TObject);
begin
  FWindowModeController.EnterBossMode;
end;

procedure TVideoMinerMainForm.SurfaceRightClick(Sender: TObject);
begin
  if (FWindowModeController <> nil) and FWindowModeController.BossMode then
    Exit;

  if FThumbnailBrowserController <> nil then
    FThumbnailBrowserController.Toggle;
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
  FInfoController.UpdateInfo;
end;

// 再生 tick 処理を再生 controller へ委譲する
procedure TVideoMinerMainForm.TimerPlaybackTimer(Sender: TObject);
begin
  if FLoadingVideo then
  begin
    WriteVideoMinerDebugLog('playback_timer_skip loading');
    Exit;
  end;

  try
    FPlaybackController.Tick(FDecoder, FMediaSession.VideoFile, FMediaSession.EndAction, FSeeking,
      FMediaSession.SeekMaxMs, FMediaSession.LoopSegmentStartMs, FMediaSession.LoopSegmentEndMs,
      FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs, FSeekGuardTargetMs,
      FSeekGuardRemaining, FUpdatingSeek, FInfoController.SetStatusCaption, FinishPlaybackAtEnd,
      SeekPlaybackTickToMs, FInfoController.UpdatePlaybackProgress, FChapterController.MaybeAutoCheckFrame);
  except
    on E: Exception do
    begin
      WriteVideoMinerSlowLog(Format('playback_timer_exception class="%s" message="%s"',
        [E.ClassName, E.Message]));
      if FPlaybackController <> nil then
        FPlaybackController.StopPlayback;
      if FInfoController <> nil then
        FInfoController.SetStatusCaption('Playback stopped by error: ' + E.Message);
    end;
  end;
end;


procedure TVideoMinerMainForm.NavigateChapterBy(Delta: Integer);
var
  TargetMs: Integer;
begin
  if (FChapterController = nil) or (Delta = 0) or (FMediaSession.SeekMaxMs <= 0) then
    Exit;

  TargetMs := FChapterController.FindNavigationTarget(Delta,
    CurrentPlaybackPositionMs, LastFrameSeekPositionMs);
  if TargetMs >= 0 then
    SeekToMs(TargetMs);
end;

procedure TVideoMinerMainForm.SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean);
var
  PreviewInfo: TVideoInfo;
  ErrorMessage: string;
begin
  FReverseWheelSeekPending := False;
  if FReverseWheelSeekTimer <> nil then
    FReverseWheelSeekTimer.Enabled := False;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_seek_to_ms_call requested_ms=%d resume_if_playing=%s current_ms=%d seek_ms=%d max_ms=%d',
    [PositionMs, BoolToStr(ResumeIfPlaying, True),
     FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs,
     FMediaSession.SeekMaxMs]));
{$ENDIF}
  if FVideoView <> nil then
  begin
    FVideoView.ClearSeekHoverPreview;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog('main_seek_to_ms clear_seek_hover_preview');
{$ENDIF}
  end;
  if (FPreviewDecoder <> nil) and (FMediaSession.VideoFile <> '') then
  begin
    if FPreviewDecoder.IsOpenForFile(FMediaSession.VideoFile) then
    begin
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'main_seek_to_ms reuse_preview file="%s"',
        [ExtractFileName(FMediaSession.VideoFile)]));
{$ENDIF}
    end
    else if FPreviewDecoder.Open(FMediaSession.VideoFile, PreviewInfo, ErrorMessage) then
    begin
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'main_seek_to_ms open_preview ok file="%s" width=%d height=%d',
        [ExtractFileName(FMediaSession.VideoFile), PreviewInfo.Width, PreviewInfo.Height]));
{$ENDIF}
    end
    else
    begin
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'main_seek_to_ms open_preview failed file="%s" err="%s"',
        [ExtractFileName(FMediaSession.VideoFile), ErrorMessage]));
{$ENDIF}
    end;
  end;
  FPlaybackController.SeekToMs(FMediaSession.VideoFile, PositionMs, ResumeIfPlaying,
    FMediaSession.SeekMaxMs, FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FUpdatingSeek, FSeeking, FInfoController.SetStatusCaption,
    FInfoController.UpdateInfo);
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_seek_to_ms_return requested_ms=%d current_ms=%d seek_ms=%d guard_target_ms=%d guard_remaining=%d',
    [PositionMs, FMediaSession.CurrentVideoPositionMs,
     FMediaSession.SeekPositionMs, FSeekGuardTargetMs,
     FSeekGuardRemaining]));
{$ENDIF}
end;

procedure TVideoMinerMainForm.SeekByWheelToMs(PositionMs: Integer);
var
  BaseMs: Integer;
  TargetMs: Integer;
begin
  if (FMediaSession.VideoFile = '') or (FMediaSession.SeekMaxMs <= 0) then
    Exit;

  TargetMs := Max(0, Min(FMediaSession.SeekMaxMs, PositionMs));
  BaseMs := FMediaSession.CurrentVideoPositionMs;
  if BaseMs < 0 then
    BaseMs := FMediaSession.SeekPositionMs;

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_wheel_seek target_ms=%d base_ms=%d current_ms=%d seek_ms=%d playback=%s pending=%s',
    [TargetMs, BaseMs, FMediaSession.CurrentVideoPositionMs,
     FMediaSession.SeekPositionMs, BoolToStr(PlaybackActiveOrPending, True),
     BoolToStr(FReverseWheelSeekPending, True)]));
{$ENDIF}

  if (not PlaybackActiveOrPending) and (TargetMs < BaseMs) then
  begin
    FReverseWheelSeekPending := True;
    FReverseWheelSeekPositionMs := TargetMs;
    FUpdatingSeek := True;
    try
      FMediaSession.SeekPositionMs := TargetMs;
    finally
      FUpdatingSeek := False;
    end;
    if FInfoController <> nil then
      FInfoController.UpdatePlaybackProgress(TargetMs);
    if FReverseWheelSeekTimer <> nil then
    begin
      FReverseWheelSeekTimer.Enabled := False;
      FReverseWheelSeekTimer.Enabled := True;
    end;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'main_reverse_wheel_seek_defer target_ms=%d base_ms=%d delay_ms=%d',
      [TargetMs, BaseMs, REVERSE_WHEEL_SEEK_DELAY_MS]));
{$ENDIF}
    Exit;
  end;

  SeekToMs(TargetMs, True);
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
  else if TargetMs >= FMediaSession.SeekMaxMs then
    SeekToLastFrame
  else
    SeekToMs(TargetMs);
end;

procedure TVideoMinerMainForm.SeekPlaybackTickToMs(PositionMs: Integer;
  FrameAlreadyShown: Boolean);
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
  if FPlaybackController <> nil then
    FPlaybackController.StopForSeek;
  FUpdatingSeek := True;
  try
    FMediaSession.SeekPositionMs := PositionMs;
    FMediaSession.CurrentVideoPositionMs := PositionMs;
  finally
    FUpdatingSeek := False;
  end;
  FInfoController.UpdatePlaybackProgress(PositionMs);

{$IFDEF DEBUG}
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  FrameShown := FrameAlreadyShown;
  if not FrameShown then
    FrameShown := ShowFrameAtMs(PositionMs);
{$IFDEF DEBUG}
  PreviewMs := StepWatch.Elapsed.TotalMilliseconds;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  StartPlaybackAtMs(PositionMs, FrameShown);
{$IFDEF DEBUG}
  RestartMs := StepWatch.Elapsed.TotalMilliseconds;
  WriteVideoMinerSlowLog(Format(
    'loop_tick_seek file="%s" target_ms=%d frame_already_shown=%s frame_shown=%s preview_ms=%.3f restart_ms=%.3f total_ms=%.3f current_ms=%d seek_ms=%d guard_target_ms=%d guard_remaining=%d',
    [ExtractFileName(FMediaSession.VideoFile), PositionMs,
     BoolToStr(FrameAlreadyShown, True), BoolToStr(FrameShown, True),
     PreviewMs, RestartMs, TotalWatch.Elapsed.TotalMilliseconds,
     FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs, FSeekGuardTargetMs,
     FSeekGuardRemaining]));
{$ENDIF}
end;

procedure TVideoMinerMainForm.SeekToFirstFrame;
begin
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_seek_first current_ms=%d seek_ms=%d max_ms=%d',
    [FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs,
     FMediaSession.SeekMaxMs]));
{$ENDIF}
  if FVideoView <> nil then
  begin
    FVideoView.ClearFrameCache;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog('main_seek_first clear_frame_cache');
{$ENDIF}
  end;
  if FPlaybackController <> nil then
    FPlaybackController.StopForSeek;
  if FVideoView <> nil then
  begin
    FVideoView.ClearSeekHoverPreview;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog('main_seek_first clear_seek_hover_preview');
{$ENDIF}
  end;
  SeekToMs(0, False);
end;

procedure TVideoMinerMainForm.SeekToLastFrame;
begin
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_seek_last current_ms=%d seek_ms=%d max_ms=%d last_ms=%d',
    [FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs,
     FMediaSession.SeekMaxMs, LastFrameSeekPositionMs]));
{$ENDIF}
  if FVideoView <> nil then
  begin
    FVideoView.ClearFrameCache;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog('main_seek_last clear_frame_cache');
{$ENDIF}
  end;
  if FPlaybackController <> nil then
    FPlaybackController.StopForSeek;
  if FVideoView <> nil then
  begin
    FVideoView.ClearSeekHoverPreview;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog('main_seek_last clear_seek_hover_preview');
{$ENDIF}
  end;
  SeekToMs(LastFrameSeekPositionMs, False);
end;

function TVideoMinerMainForm.LastFrameSeekPositionMs: Integer;
begin
  Result := VideoMinerLastFrameSeekPositionMs(FMediaSession.SeekMaxMs, FMediaSession.VideoInfo.Fps);
end;

function TVideoMinerMainForm.LoopStartPositionMs: Integer;
begin
  if FChapterController = nil then
    Result := 0
  else
    Result := FChapterController.LoopStartPositionMs(LastFrameSeekPositionMs);
end;

procedure TVideoMinerMainForm.ConfigureLoopSegment(PositionMs: Integer);
begin
  FPlaybackController.ConfigureLoopSegment(FMediaSession.EndAction, FChapterController.Manager,
    PositionMs, FMediaSession.SeekMaxMs, LastFrameSeekPositionMs, FMediaSession.LoopSegmentStartMs,
    FMediaSession.LoopSegmentEndMs);
end;

procedure TVideoMinerMainForm.StartPlaybackAtMs(PositionMs: Integer;
  FrameAlreadyShown: Boolean);
var
  SkipVideoSeek: Boolean;
begin
  SkipVideoSeek := FrameAlreadyShown and
    (FMainDecoderPreparedFrameMs = PositionMs);
  FMainDecoderPreparedFrameMs := -1;
  FPlaybackController.StartPlaybackAtMs(FDecoder, FMediaSession.VideoFile, FMediaSession.VideoInfo,
    FMediaSession.EndAction, FChapterController.Manager, FMediaSession.SeekMaxMs, PositionMs, LastFrameSeekPositionMs,
    FrameAlreadyShown, False, SkipVideoSeek, FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs,
    FMediaSession.LoopSegmentStartMs, FMediaSession.LoopSegmentEndMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FInfoController.SetStatusCaption);
end;

procedure TVideoMinerMainForm.FinishPlaybackAtEnd;
var
  CanNavigateNext: Boolean;
begin
  CanNavigateNext := (FNavigationController <> nil) and
    FNavigationController.CanNavigateNext;
  FPlaybackController.FinishAtEnd(FMediaSession.EndAction, CanNavigateNext,
    LoopStartPositionMs, FMediaSession.SeekMaxMs, LastFrameSeekPositionMs,
    FMediaSession.SeekPositionMs, FUpdatingSeek, ShowFrameAtMs, StartPlaybackAtMs,
    FNavigationController.NavigateNextPlaybackFile, FInfoController.UpdateInfo);
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

  if (FThumbnailBrowserController <> nil) and
     FThumbnailBrowserController.HandleKeyDown(Key, Shift) then
    Exit;

  if (Key = VK_TAB) and (Shift = []) then
  begin
    if FThumbnailBrowserController <> nil then
      FThumbnailBrowserController.Toggle;
    Key := 0;
    Exit;
  end;

  if (Key = VK_ESCAPE) and FWindowModeController.FullScreen then
  begin
    FWindowModeController.ExitFullScreen;
    Key := 0;
    Exit;
  end;

  if (FNavigationController <> nil) and
     FNavigationController.HandleKeyDown(Key, Shift) then
    Exit;

  if (FShortcuts <> nil) and FShortcuts.KeyDown(Key, Shift) then
    Exit;
end;

procedure TVideoMinerMainForm.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if FNavigationController <> nil then
    FNavigationController.HandleKeyUp(Key);
end;

procedure TVideoMinerMainForm.WMXButtonDown(var Message: TMessage);
const
  VIDEO_MINER_XBUTTON_BACK = 1;
  VIDEO_MINER_XBUTTON_FORWARD = 2;
var
  Button: Word;
begin
  Message.Result := 0;
  Button := Word((NativeUInt(Message.WParam) shr 16) and $FFFF);
  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'mainform_wm_xbutton_down wparam=$%s lparam=$%s xbutton=%d',
      [IntToHex(NativeInt(Message.WParam), 8),
       IntToHex(NativeInt(Message.LParam), 8), Button]));

  if FNavigationController = nil then
    Exit;

  case Button of
    VIDEO_MINER_XBUTTON_BACK:
      begin
        PostMessage(Handle, WM_VM_NAVIGATE, VIDEO_MINER_XBUTTON_BACK, 0);
        Message.Result := 1;
      end;
    VIDEO_MINER_XBUTTON_FORWARD:
      begin
        PostMessage(Handle, WM_VM_NAVIGATE, VIDEO_MINER_XBUTTON_FORWARD, 0);
        Message.Result := 1;
      end;
  end;
end;

procedure TVideoMinerMainForm.WMNavigate(var Message: TMessage);
begin
  if FLoadingVideo then
  begin
    WriteVideoMinerDebugLog('navigate_message_ignore_loading');
    Message.Result := 1;
    Exit;
  end;

  if FNavigationController <> nil then
  begin
    case Message.WParam of
      1:
        begin
          WriteVideoMinerDebugLog('navigate_message delta=-1');
          FNavigationController.NavigateBy(-1);
        end;
      2:
        begin
          WriteVideoMinerDebugLog('navigate_message delta=1');
          FNavigationController.NavigateBy(1);
        end;
    end;
  end;
  Message.Result := 1;
end;

procedure TVideoMinerMainForm.WMOpenPending(var Message: TMessage);
begin
  if FExternalOpenController <> nil then
    FExternalOpenController.ProcessOpenQueue;
  Message.Result := 1;
end;

procedure TVideoMinerMainForm.WMStartupOpen(var Message: TMessage);
begin
  if FStartupOpenTimer <> nil then
  begin
    FStartupOpenTimer.Enabled := False;
    FStartupOpenTimer.Enabled := True;
  end;
  Message.Result := 1;
end;

procedure TVideoMinerMainForm.StartupOpenTimer(Sender: TObject);
var
  AutoPlay: Boolean;
  FileName: string;
  OpenRemembered: Boolean;
begin
  WriteVideoMinerStartupLog('startup_open_timer begin');
  try
    if FStartupOpenTimer <> nil then
      FStartupOpenTimer.Enabled := False;

    FileName := FStartupOpenFile;
    AutoPlay := FStartupOpenAutoPlay;
    OpenRemembered := FStartupOpenRemembered;
    FStartupOpenFile := '';
    FStartupOpenAutoPlay := False;
    FStartupOpenRemembered := False;

    if OpenRemembered then
    begin
      WriteVideoMinerStartupLog('startup_open_timer mode=remembered');
      FInfoController.SetStatusCaption('Loading last video...');
      OpenRememberedFile;
    end
    else if FileName <> '' then
    begin
      WriteVideoMinerStartupLog('startup_open_timer mode=file file="' +
        ExtractFileName(FileName) + '"');
      FInfoController.SetStatusCaption('Loading video...');
      LoadVideoFile(FileName, AutoPlay);
    end
    else
      WriteVideoMinerStartupLog('startup_open_timer mode=none');
    WriteVideoMinerStartupLog('startup_open_timer done');
  except
    on E: Exception do
      WriteVideoMinerStartupLog('startup_open_timer_exception class="' +
        E.ClassName + '" message="' + E.Message + '"');
  end;
end;

procedure TVideoMinerMainForm.RestartPlaybackTimer(Sender: TObject);
var
  TargetMs: Integer;
  FrameAlreadyShown: Boolean;
  FastSeek: Boolean;
begin
  if FLoadingVideo then
  begin
    if FRestartPlaybackTimer <> nil then
      FRestartPlaybackTimer.Enabled := False;
    if FPlaybackController <> nil then
      FPlaybackController.ClearRestart;
    WriteVideoMinerDebugLog('restart_playback_skip loading');
    Exit;
  end;

  if not FPlaybackController.ConsumeRestart(TargetMs, FrameAlreadyShown,
    FastSeek) then
    Exit;

  if (FMediaSession.VideoFile = '') or (TargetMs < 0) or (TargetMs >= FMediaSession.SeekMaxMs) then
    Exit;

  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format('restart_playback target_ms=%d',
      [TargetMs]));
  FPlaybackController.StartPlaybackAtMs(FDecoder, FMediaSession.VideoFile, FMediaSession.VideoInfo,
    FMediaSession.EndAction, FChapterController.Manager, FMediaSession.SeekMaxMs, TargetMs, LastFrameSeekPositionMs,
    FrameAlreadyShown, FastSeek, False, FMediaSession.CurrentVideoPositionMs, FMediaSession.SeekPositionMs,
    FMediaSession.LoopSegmentStartMs, FMediaSession.LoopSegmentEndMs, FSeekGuardTargetMs,
    FSeekGuardRemaining, FInfoController.SetStatusCaption);
end;

procedure TVideoMinerMainForm.ReverseWheelSeekTimer(Sender: TObject);
var
  TargetMs: Integer;
begin
  if FReverseWheelSeekTimer <> nil then
    FReverseWheelSeekTimer.Enabled := False;

  if (not FReverseWheelSeekPending) or FLoadingVideo then
  begin
    FReverseWheelSeekPending := False;
    Exit;
  end;

  TargetMs := FReverseWheelSeekPositionMs;
  FReverseWheelSeekPending := False;
  FReverseWheelSeekPositionMs := -1;
  if (FMediaSession.VideoFile = '') or (TargetMs < 0) or
     (TargetMs > FMediaSession.SeekMaxMs) then
    Exit;

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'main_reverse_wheel_seek_fire target_ms=%d current_ms=%d seek_ms=%d',
    [TargetMs, FMediaSession.CurrentVideoPositionMs,
     FMediaSession.SeekPositionMs]));
{$ENDIF}
  SeekToMs(TargetMs, True);
end;

procedure TVideoMinerMainForm.WMNCHitTest(var Message: TWMNCHitTest);
begin
  inherited;
  if FFrameGuideController <> nil then
    FFrameGuideController.UpdateVisibility;
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
  if FThumbnailBrowserController <> nil then
    FThumbnailBrowserController.AdjustResizeEdges;
  if FFrameGuideController <> nil then
    FFrameGuideController.UpdateLayout;
end;

procedure TVideoMinerMainForm.CMDialogKey(var Message: TCMDialogKey);
begin
  if (Message.CharCode = VK_TAB) and
     (KeyDataToShiftState(Message.KeyData) = []) then
  begin
    WriteVideoMinerSlowLog('thumbnail tab_dialog_key');
    if (FWindowModeController <> nil) and
       (not FWindowModeController.BossMode) and
       (FThumbnailBrowserController <> nil) then
      FThumbnailBrowserController.Toggle;
    Message.Result := 1;
    Exit;
  end;

  inherited;
end;

procedure TVideoMinerMainForm.WMCopyData(var Message: TWMCopyData);
begin
  if (FExternalOpenController = nil) or
     (not FExternalOpenController.HandleCopyData(Message)) then
    inherited;
end;

end.
