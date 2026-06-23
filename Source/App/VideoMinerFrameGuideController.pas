unit VideoMinerFrameGuideController;

// 枠なしフォームの端やタイトルバー hover 時だけ表示する細いガイド枠を制御する。
// MainForm から、枠表示用 Panel 群、timer、マウス位置判定を分離する。

interface

uses
  Winapi.Windows, System.Classes, System.Math, System.Types, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, VideoMinerWindowModeController;

type
  TVideoMinerFrameGuideController = class
  private
    FBottom               : TPanel;                         // 下端外側の枠
    FForm                 : TCustomForm;                    // 枠を表示するフォーム
    FInnerBottom          : TPanel;                         // 下端内側の枠
    FInnerLeft            : TPanel;                         // 左端内側の枠
    FInnerRight           : TPanel;                         // 右端内側の枠
    FInnerTop             : TPanel;                         // 上端内側の枠
    FLeft                 : TPanel;                         // 左端外側の枠
    FRight                : TPanel;                         // 右端外側の枠
    FTimer                : TTimer;                         // hover 状態確認 timer
    FTitleBar             : TWinControl;                    // タイトルバー領域
    FTop                  : TPanel;                         // 上端外側の枠
    FVisible              : Boolean;                        // 枠を表示中か
    FWindowModeController : TVideoMinerWindowModeController;// 全画面/偽装画面の状態参照先
    // hover 枠用の Panel を作る
    procedure CreateGuidePanel(out Panel: TPanel; Color: TColor);
    // 指定 Panel を最前面へ出す
    procedure BringGuidePanelToFront(Panel: TPanel);
    // 指定 Panel の表示状態を揃える
    procedure SetGuidePanelVisible(Panel: TPanel);
    // timer から hover 状態を更新する
    procedure TimerTick(Sender: TObject);
    // hover 枠の表示/非表示を切り替える
    procedure SetVisible(Value: Boolean);
  public
    // Panel 群と timer を生成する
    constructor Create(AOwner: TComponent; AForm: TCustomForm;
      ATitleBar: TWinControl; AWindowModeController: TVideoMinerWindowModeController);
    // timer と Panel 群を解放する
    destructor Destroy; override;
    // hover 枠を現在のフォームサイズへ合わせる
    procedure UpdateLayout;
    // マウス位置から hover 枠の表示状態を更新する
    procedure UpdateVisibility;
  end;

implementation

const
  FRAME_GUIDE_INNER_COLOR       = clWhite; // hover 枠の内側色
  FRAME_GUIDE_OUTER_COLOR       = clWhite; // hover 枠の外側色
  FRAME_GUIDE_EDGE_SIZE         = 12;      // hover 枠を出すフォーム端の幅 px
  FRAME_GUIDE_LINE_SIZE         = 1;       // hover 枠 1 本ぶんの太さ px
  FRAME_GUIDE_TIMER_INTERVAL_MS = 80;      // hover 枠表示状態を確認する間隔 ms

constructor TVideoMinerFrameGuideController.Create(AOwner: TComponent;
  AForm: TCustomForm; ATitleBar: TWinControl;
  AWindowModeController: TVideoMinerWindowModeController);
begin
  inherited Create;
  FForm := AForm;
  FTitleBar := ATitleBar;
  FWindowModeController := AWindowModeController;

  CreateGuidePanel(FTop, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FBottom, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FLeft, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FRight, FRAME_GUIDE_OUTER_COLOR);
  CreateGuidePanel(FInnerTop, FRAME_GUIDE_INNER_COLOR);
  CreateGuidePanel(FInnerBottom, FRAME_GUIDE_INNER_COLOR);
  CreateGuidePanel(FInnerLeft, FRAME_GUIDE_INNER_COLOR);
  CreateGuidePanel(FInnerRight, FRAME_GUIDE_INNER_COLOR);
  UpdateLayout;

  FTimer := TTimer.Create(AOwner);
  FTimer.Enabled := True;
  FTimer.Interval := FRAME_GUIDE_TIMER_INTERVAL_MS;
  FTimer.OnTimer := TimerTick;
end;

destructor TVideoMinerFrameGuideController.Destroy;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  FTimer.Free;
  FInnerRight.Free;
  FInnerLeft.Free;
  FInnerBottom.Free;
  FInnerTop.Free;
  FRight.Free;
  FLeft.Free;
  FBottom.Free;
  FTop.Free;
  inherited Destroy;
end;

procedure TVideoMinerFrameGuideController.CreateGuidePanel(out Panel: TPanel;
  Color: TColor);
begin
  Panel := TPanel.Create(FForm);
  Panel.Parent := FForm;
  Panel.BevelOuter := bvNone;
  Panel.Caption := '';
  Panel.Color := Color;
  Panel.ParentBackground := False;
  Panel.Enabled := False;
  Panel.Visible := False;
end;

procedure TVideoMinerFrameGuideController.BringGuidePanelToFront(Panel: TPanel);
begin
  if Panel <> nil then
    Panel.BringToFront;
end;

procedure TVideoMinerFrameGuideController.SetGuidePanelVisible(Panel: TPanel);
begin
  if Panel <> nil then
    Panel.Visible := FVisible;
end;

procedure TVideoMinerFrameGuideController.SetVisible(Value: Boolean);
begin
  if (FVisible = Value) and (not Value) then
    Exit;

  if FVisible <> Value then
  begin
    FVisible := Value;
    SetGuidePanelVisible(FTop);
    SetGuidePanelVisible(FBottom);
    SetGuidePanelVisible(FLeft);
    SetGuidePanelVisible(FRight);
    SetGuidePanelVisible(FInnerTop);
    SetGuidePanelVisible(FInnerBottom);
    SetGuidePanelVisible(FInnerLeft);
    SetGuidePanelVisible(FInnerRight);
  end;

  if Value then
  begin
    UpdateLayout;
    BringGuidePanelToFront(FTop);
    BringGuidePanelToFront(FBottom);
    BringGuidePanelToFront(FLeft);
    BringGuidePanelToFront(FRight);
    BringGuidePanelToFront(FInnerTop);
    BringGuidePanelToFront(FInnerBottom);
    BringGuidePanelToFront(FInnerLeft);
    BringGuidePanelToFront(FInnerRight);
  end;
end;

procedure TVideoMinerFrameGuideController.UpdateLayout;
var
  InnerHeight: Integer;
  InnerWidth: Integer;
  Thickness: Integer;
begin
  if (FForm = nil) or (FForm.ClientWidth <= 0) or (FForm.ClientHeight <= 0) then
    Exit;

  Thickness := FRAME_GUIDE_LINE_SIZE;
  InnerWidth := Max(0, FForm.ClientWidth - Thickness * 2);
  InnerHeight := Max(0, FForm.ClientHeight - Thickness * 2);

  if FTop <> nil then
    FTop.SetBounds(0, 0, FForm.ClientWidth, Thickness);
  if FBottom <> nil then
    FBottom.SetBounds(0, FForm.ClientHeight - Thickness, FForm.ClientWidth,
      Thickness);
  if FLeft <> nil then
    FLeft.SetBounds(0, 0, Thickness, FForm.ClientHeight);
  if FRight <> nil then
    FRight.SetBounds(FForm.ClientWidth - Thickness, 0, Thickness,
      FForm.ClientHeight);
  if FInnerTop <> nil then
    FInnerTop.SetBounds(Thickness, Thickness, InnerWidth, Thickness);
  if FInnerBottom <> nil then
    FInnerBottom.SetBounds(Thickness, FForm.ClientHeight - Thickness * 2,
      InnerWidth, Thickness);
  if FInnerLeft <> nil then
    FInnerLeft.SetBounds(Thickness, Thickness, Thickness, InnerHeight);
  if FInnerRight <> nil then
    FInnerRight.SetBounds(FForm.ClientWidth - Thickness * 2, Thickness,
      Thickness, InnerHeight);
end;

procedure TVideoMinerFrameGuideController.UpdateVisibility;
var
  ClientPoint: TPoint;
  CursorPoint: TPoint;
  InEdge: Boolean;
  InForm: Boolean;
  InTitleBar: Boolean;
begin
  if FForm = nil then
    Exit;

  if (FWindowModeController <> nil) and
     (FWindowModeController.FullScreen or FWindowModeController.BossMode) then
  begin
    SetVisible(False);
    Exit;
  end;

  if FForm.WindowState = wsMinimized then
  begin
    SetVisible(False);
    Exit;
  end;

  GetCursorPos(CursorPoint);
  ClientPoint := FForm.ScreenToClient(CursorPoint);
  InForm := PtInRect(Rect(0, 0, FForm.ClientWidth, FForm.ClientHeight), ClientPoint);
  if not InForm then
  begin
    SetVisible(False);
    Exit;
  end;

  InTitleBar := (FTitleBar <> nil) and FTitleBar.Visible and
    PtInRect(FTitleBar.BoundsRect, ClientPoint);
  InEdge := (ClientPoint.X < FRAME_GUIDE_EDGE_SIZE) or
    (ClientPoint.X >= FForm.ClientWidth - FRAME_GUIDE_EDGE_SIZE) or
    (ClientPoint.Y < FRAME_GUIDE_EDGE_SIZE) or
    (ClientPoint.Y >= FForm.ClientHeight - FRAME_GUIDE_EDGE_SIZE);

  SetVisible(InTitleBar or InEdge);
end;

procedure TVideoMinerFrameGuideController.TimerTick(Sender: TObject);
begin
  UpdateVisibility;
end;

end.
