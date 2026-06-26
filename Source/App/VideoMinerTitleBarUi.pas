unit VideoMinerTitleBarUi;

// メインフォーム独自タイトルバーの初期表示と軽い見た目操作をまとめる。
// DFM のイベント入口はメインフォームに残し、コントロール構成の細部だけを担当する。

interface

uses
  System.Classes, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls;

// フォーム最小サイズとタイトルバー/キャプションボタンの初期色を設定する
procedure ConfigureVideoMinerTitleBar(Form: TCustomForm; TitleBar: TPanel;
  CloseButton: TPanel; MaximizeButton: TPanel; MinimizeButton: TPanel;
  TitleBarColor: TColor; MinFormWidth: Integer; MinFormHeight: Integer);
// 独自タイトルバー左端へアプリアイコンを作成して返す
function CreateVideoMinerTitleIcon(Owner: TComponent; Parent: TWinControl;
  SourceIcon: TIcon; FallbackIcon: TIcon; MouseDownHandler: TMouseEvent): TImage;
// Sender がパネルなら背景色を変更する
procedure SetPanelColor(Sender: TObject; Color: TColor);

implementation

procedure ConfigureVideoMinerTitleBar(Form: TCustomForm; TitleBar: TPanel;
  CloseButton: TPanel; MaximizeButton: TPanel; MinimizeButton: TPanel;
  TitleBarColor: TColor; MinFormWidth: Integer; MinFormHeight: Integer);
begin
  if TitleBar <> nil then
    TitleBar.Color := TitleBarColor;
  if CloseButton <> nil then
    CloseButton.Color := TitleBarColor;
  if MaximizeButton <> nil then
    MaximizeButton.Color := TitleBarColor;
  if MinimizeButton <> nil then
    MinimizeButton.Color := TitleBarColor;
  if Form <> nil then
  begin
    Form.Constraints.MinWidth := MinFormWidth;
    Form.Constraints.MinHeight := MinFormHeight;
  end;
end;

function CreateVideoMinerTitleIcon(Owner: TComponent; Parent: TWinControl;
  SourceIcon: TIcon; FallbackIcon: TIcon; MouseDownHandler: TMouseEvent): TImage;
begin
  Result := TImage.Create(Owner);
  Result.Parent := Parent;
  if Parent <> nil then
    Result.Width := Parent.Height;
  Result.Align := alLeft;
  Result.Center := True;
  Result.Proportional := True;
  Result.Stretch := False;
  Result.Transparent := True;
  Result.OnMouseDown := MouseDownHandler;
  if (SourceIcon <> nil) and (not SourceIcon.Empty) then
    Result.Picture.Icon.Assign(SourceIcon)
  else if (FallbackIcon <> nil) and (not FallbackIcon.Empty) then
    Result.Picture.Icon.Assign(FallbackIcon);
end;

procedure SetPanelColor(Sender: TObject; Color: TColor);
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

end.
