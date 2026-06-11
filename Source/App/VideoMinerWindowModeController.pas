unit VideoMinerWindowModeController;

interface

uses
  Winapi.Messages, Winapi.Windows, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.StdCtrls, VideoMinerSettings, VideoMinerVideoView;

type
  TVideoMinerWindowModeAction = procedure of object;

  TVideoMinerWindowModeController = class
  private
    FBossMode: Boolean;
    FForm: TCustomForm;
    FFullScreen: Boolean;
    FMaximizeLabel: TLabel;
    FNormalWindowBounds: TVideoMinerWindowBounds;
    FStopPlayback: TVideoMinerWindowModeAction;
    FTitleBar: TPanel;
    FVideoView: TVideoMinerVideoView;
  public
    constructor Create(Form: TCustomForm; TitleBar: TPanel;
      MaximizeLabel: TLabel; VideoView: TVideoMinerVideoView;
      StopPlayback: TVideoMinerWindowModeAction);
    procedure ApplySavedWindowBounds;
    procedure EnterBossMode;
    procedure EnterFullScreen;
    procedure ExitBossMode;
    procedure ExitFullScreen;
    procedure HandleMove;
    procedure HandleSize;
    procedure HitTestBorderlessResize(const ScreenPoint: TPoint;
      var HitTestResult: LRESULT);
    procedure SaveWindowBounds;
    procedure ToggleFullScreen;
    procedure UpdateMaximizeButton;
    property BossMode: Boolean read FBossMode;
    property FullScreen: Boolean read FFullScreen;
  end;

implementation

uses
  ResizeEdges, VideoMinerWindowChrome;

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
  if FFullScreen or (FForm = nil) then
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
  if (not FFullScreen) or (FForm = nil) then
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
  VideoMinerWindowChrome.RememberNormalWindowBounds(FForm, FFullScreen,
    FNormalWindowBounds);
end;

procedure TVideoMinerWindowModeController.HandleSize;
begin
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
  VideoMinerWindowChrome.HitTestBorderlessResize(FForm, FFullScreen,
    VIDEO_MINER_RESIZE_BORDER, ScreenPoint, HitTestResult);
end;

procedure TVideoMinerWindowModeController.SaveWindowBounds;
begin
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
  if (FForm = nil) or (FMaximizeLabel = nil) then
    Exit;

  if FForm.WindowState = wsMaximized then
    FMaximizeLabel.Caption := WideChar($2750)
  else
    FMaximizeLabel.Caption := WideChar($25A1);
end;

end.
