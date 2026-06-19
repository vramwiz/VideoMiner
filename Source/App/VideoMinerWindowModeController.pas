unit VideoMinerWindowModeController;

// 枠なしメインフォームの表示モードとサイズ記憶を担当する。
// fullscreen / boss mode / 通常ウィンドウ bounds をこの controller が所有し、
// メインフォーム側には Windows メッセージや UI イベントの入口だけを残す。

interface

uses
  Winapi.Messages, Winapi.Windows, System.Classes, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls, VideoMinerSettings,
  VideoMinerVideoView;

type
  // ウィンドウモード変更時に必要なアプリ側処理を呼び戻す
  TVideoMinerWindowModeAction = procedure of object;

  TVideoMinerWindowModeController = class
  private
    FBossMode           : Boolean;                       // 偽装画面で動画を隠しているか
    FForm               : TCustomForm;                   // 表示モードを切り替える対象フォーム
    FFullScreen         : Boolean;                       // 独自全画面表示中か
    FMaximizeLabel      : TLabel;                        // 最大化ボタン表示用ラベル
    FNormalWindowBounds : TVideoMinerWindowBounds;       // 全画面解除時や終了時に使う通常ウィンドウ位置
    FStopPlayback       : TVideoMinerWindowModeAction;   // boss mode へ入る前に再生を止める処理
    FTitleBar           : TPanel;                        // 全画面や boss mode で表示を切り替える独自タイトルバー
    FVideoView          : TVideoMinerVideoView;          // 表示モードを動画サーフェスへ伝える窓口
  public
    // 操作対象コントロールと、必要なアプリ側 callback を受け取る
    constructor Create(Form: TCustomForm; TitleBar: TPanel;
      MaximizeLabel: TLabel; VideoView: TVideoMinerVideoView;
      StopPlayback: TVideoMinerWindowModeAction);
    // 保存済みの通常ウィンドウ位置を起動時のフォームへ反映する
    procedure ApplySavedWindowBounds;
    // 再生を止めて動画面を偽装表示へ切り替える
    procedure EnterBossMode;
    // 現在の通常ウィンドウ位置を記憶し、対象モニタいっぱいへ広げる
    procedure EnterFullScreen;
    // 偽装表示を解除し、現在の画面モードに合うタイトルバー状態へ戻す
    procedure ExitBossMode;
    // 全画面を解除し、記憶していた通常ウィンドウ位置へ戻す
    procedure ExitFullScreen;
    // フォーム移動時に通常ウィンドウ位置を更新する
    procedure HandleMove;
    // フォームサイズ変更時にボタン表示、リサイズエッジ、位置記憶を更新する
    procedure HandleSize;
    // 枠なしフォームの端/角リサイズ用 hit-test を補完する
    procedure HitTestBorderlessResize(const ScreenPoint: TPoint;
      var HitTestResult: LRESULT);
    // 終了時に保存すべき通常ウィンドウ位置を確定して設定へ書き込む
    procedure SaveWindowBounds;
    // 独自全画面表示を切り替える
    procedure ToggleFullScreen;
    // 現在の最大化状態に合わせて独自最大化ボタンの見た目を更新する
    procedure UpdateMaximizeButton;
    property BossMode: Boolean read FBossMode;
    property FullScreen: Boolean read FFullScreen;
  end;

implementation

uses
  ResizeEdges, VideoMinerWindowChrome;

function FormUsable(Form: TCustomForm): Boolean;
begin
  Result := (Form <> nil) and (not (csDestroying in Form.ComponentState));
end;

constructor TVideoMinerWindowModeController.Create(Form: TCustomForm;
  TitleBar: TPanel; MaximizeLabel: TLabel; VideoView: TVideoMinerVideoView;
  StopPlayback: TVideoMinerWindowModeAction);
begin
  inherited Create;
  FForm := Form;
  FTitleBar := TitleBar;
  FMaximizeLabel := MaximizeLabel;
  FVideoView := VideoView;
  FStopPlayback := StopPlayback;
end;

procedure TVideoMinerWindowModeController.ApplySavedWindowBounds;
begin
  if not FormUsable(FForm) then
    Exit;

  VideoMinerWindowChrome.ApplySavedWindowBounds(FForm, FNormalWindowBounds);
end;

procedure TVideoMinerWindowModeController.EnterBossMode;
begin
  if FBossMode then
    Exit;

  if Assigned(FStopPlayback) then
    FStopPlayback;
  FBossMode := True;
  if FVideoView <> nil then
    FVideoView.BossMode := True;
  if FTitleBar <> nil then
    FTitleBar.Visible := False;
  if FForm <> nil then
    FForm.SetFocus;
end;

procedure TVideoMinerWindowModeController.EnterFullScreen;
var
  FullScreenRect: TRect;
  Monitor: TMonitor;
begin
  if FFullScreen or (not FormUsable(FForm)) then
    Exit;

  VideoMinerWindowChrome.RememberNormalWindowBounds(FForm, FFullScreen,
    FNormalWindowBounds);
  FFullScreen := True;
  if FVideoView <> nil then
    FVideoView.FullScreen := FFullScreen;
  FForm.WindowState := wsNormal;
  if FTitleBar <> nil then
    FTitleBar.Visible := False;

  Monitor := Screen.MonitorFromWindow(FForm.Handle, mdNearest);
  if Monitor <> nil then
    FullScreenRect := Monitor.BoundsRect
  else
    FullScreenRect := Screen.DesktopRect;

  FForm.SetBounds(FullScreenRect.Left, FullScreenRect.Top,
    FullScreenRect.Width, FullScreenRect.Height);
end;

procedure TVideoMinerWindowModeController.ExitBossMode;
begin
  if not FBossMode then
    Exit;

  FBossMode := False;
  if FVideoView <> nil then
    FVideoView.BossMode := False;
  if FTitleBar <> nil then
    FTitleBar.Visible := not FFullScreen;
  if FForm <> nil then
    FForm.SetFocus;
end;

procedure TVideoMinerWindowModeController.ExitFullScreen;
var
  Bounds: TVideoMinerWindowBounds;
begin
  if (not FFullScreen) or (not FormUsable(FForm)) then
    Exit;

  FFullScreen := False;
  if FVideoView <> nil then
    FVideoView.FullScreen := FFullScreen;
  if FTitleBar <> nil then
    FTitleBar.Visible := not FBossMode;
  FForm.WindowState := wsNormal;

  Bounds := FNormalWindowBounds;
  if Bounds.Available then
    FForm.SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
  VideoMinerWindowChrome.RememberNormalWindowBounds(FForm, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerWindowModeController.HandleMove;
begin
  if not FormUsable(FForm) then
    Exit;

  VideoMinerWindowChrome.RememberNormalWindowBounds(FForm, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerWindowModeController.HandleSize;
begin
  if not FormUsable(FForm) then
    Exit;

  UpdateMaximizeButton;
  if FTitleBar <> nil then
    TResizeEdgeHelper.AdjustEdges(FTitleBar);
  if FVideoView <> nil then
    TResizeEdgeHelper.AdjustEdges(FVideoView.SurfaceControl);
  VideoMinerWindowChrome.RememberNormalWindowBounds(FForm, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerWindowModeController.HitTestBorderlessResize(
  const ScreenPoint: TPoint; var HitTestResult: LRESULT);
begin
  if not FormUsable(FForm) then
    Exit;

  VideoMinerWindowChrome.HitTestBorderlessResize(FForm, FFullScreen,
    VIDEO_MINER_RESIZE_BORDER, ScreenPoint, HitTestResult);
end;

procedure TVideoMinerWindowModeController.SaveWindowBounds;
begin
  if not FormUsable(FForm) then
    Exit;

  VideoMinerWindowChrome.RestoreAndRememberNormalWindowBoundsForSave(FForm,
    FFullScreen, FNormalWindowBounds);
  SaveMainFormBounds(FNormalWindowBounds);
end;

procedure TVideoMinerWindowModeController.ToggleFullScreen;
begin
  if FFullScreen then
    ExitFullScreen
  else
    EnterFullScreen;
end;

procedure TVideoMinerWindowModeController.UpdateMaximizeButton;
begin
  if (not FormUsable(FForm)) or (FMaximizeLabel = nil) or
     (csDestroying in FMaximizeLabel.ComponentState) then
    Exit;

  if FForm.WindowState = wsMaximized then
    FMaximizeLabel.Caption := WideChar($2750)
  else
    FMaximizeLabel.Caption := WideChar($25A1);
end;

end.
