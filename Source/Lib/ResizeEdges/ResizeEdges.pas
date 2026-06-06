{
  ResizeEdges.pas

  ■ 概要:
    透明なサイズ変更および移動用エッジを任意の TWinControl に追加するユーティリティ。
    bsNone のフォームや Align 設定されたパネル・フレームにも対応可能。

  ■ 設計思想:
    - UI に干渉しない「完全透明なハンドル」を提供（TLabel + Transparent）
    - 上下左右のサイズ変更方向は開発者が明示的に指定できる（TResizeDirectionSet）
    - 対象が Panel や Frame であっても GetParentForm を使って正しく Form にメッセージ送信
    - 四隅の斜めリサイズは方向の組み合わせから自動で生成
    - 手動でレイアウト制御する設計を前提とし、Align による自動リサイズとの干渉を避ける

  ■ 使用上の注意:
    - AttachEdges 実行後、親コントロールのサイズを変更した際は AdjustEdges を必ず呼び出すこと
    - Align が alBottom などの場合、対応方向に注意。rdTop などは指定しないこと
    - 上方向のサイズ変更と移動ハンドルは領域が重なるため同時に指定しないことを推奨
    - 移動可能エリアの幅と高さは MoveHandleWidth / MoveHandleHeight により変更可能

  ■ 利用例:
    TResizeEdgeHelper.AttachEdges(MyPanel, 10, [rdLeft, rdRight, rdBottom, rdMove]);
    MyPanel.SetBounds(...);
    TResizeEdgeHelper.AdjustEdges(MyPanel);

  ■ 最終更新:
    2025-06-30 設計確定／方向指定対応版／斜め自動生成対応
    2025-07-09 指定された幅の設定が反映されない現象を修正
}

unit ResizeEdges;

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Forms, Vcl.StdCtrls;

type
  TResizeDirection = (rdTop, rdBottom, rdLeft, rdRight, rdMove);
  TResizeDirectionSet = set of TResizeDirection;

  TResizeEdgeHelper = class
  private
    class var FHandleSize: Integer;
    class var FMoveHandleWidth: Integer;
    class var FMoveHandleHeight: Integer;
  public
    class property HandleSize: Integer read FHandleSize write FHandleSize;
    class property MoveHandleWidth: Integer read FMoveHandleWidth write FMoveHandleWidth;
    class property MoveHandleHeight: Integer read FMoveHandleHeight write FMoveHandleHeight;

    class procedure AttachEdges(Target: TWinControl; EdgeSize: Integer = 5;
      Directions: TResizeDirectionSet = [rdTop, rdBottom, rdLeft, rdRight, rdMove]);
    class procedure AdjustEdges(Target: TWinControl);
  end;

implementation

type
  TResizeEdgeLabel = class(TLabel)
  private
    FDirection: Integer;
    procedure EdgeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateEdge(AOwner: TComponent; Direction: Integer);
    procedure AdjustPosition;
  end;

{ TResizeEdgeLabel }

constructor TResizeEdgeLabel.CreateEdge(AOwner: TComponent; Direction: Integer);
begin
  inherited Create(AOwner);
  Parent := TWinControl(AOwner);
  FDirection := Direction;

  Caption := '';
  Transparent := True;
  Color := clNone;
  Visible := True;
  Enabled := True;
  Align := alNone;

  AdjustPosition;

  case FDirection of
    1, 2: Cursor := crSizeNS;
    3, 4: Cursor := crSizeWE;
    5: Cursor := crSizeAll;
    6: Cursor := crSizeNWSE;
    7: Cursor := crSizeNESW;
    8: Cursor := crSizeNESW;
    9: Cursor := crSizeNWSE;
  end;

  OnMouseDown := EdgeMouseDown;
  if FDirection <> 5 then BringToFront;
end;

procedure TResizeEdgeLabel.AdjustPosition;
begin
  if not Assigned(Parent) then Exit;

  with TResizeEdgeHelper do
    case FDirection of
      1: SetBounds(0, 0, Parent.Width, HandleSize);
      2: SetBounds(0, Parent.Height - HandleSize, Parent.Width, HandleSize);
      3: SetBounds(0, 0, HandleSize, Parent.Height);
      4: SetBounds(Parent.Width - HandleSize, 0, HandleSize, Parent.Height);
      5: begin
        Left := HandleSize;
        Top := 0;
        Width := Parent.Width - HandleSize * 2;
        Height := MoveHandleHeight;
      end;
      6: SetBounds(0, 0, HandleSize, HandleSize);
      7: SetBounds(Parent.Width - HandleSize, 0, HandleSize, HandleSize);
      8: SetBounds(0, Parent.Height - HandleSize, HandleSize, HandleSize);
      9: SetBounds(Parent.Width - HandleSize, Parent.Height - HandleSize, HandleSize, HandleSize);
    end;
end;

procedure TResizeEdgeLabel.EdgeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
const
  DirToSC: array[1..9] of Integer = (
    SC_SIZE + 3, SC_SIZE + 6, SC_SIZE + 1, SC_SIZE + 2, SC_MOVE + HTCAPTION,
    SC_SIZE + 4, SC_SIZE + 5, SC_SIZE + 7, SC_SIZE + 8
  );
var
  FormHandle: HWND;
begin
  if Button = mbLeft then
  begin
    ReleaseCapture;
    FormHandle := GetParentForm(Self).Handle;
    if FormHandle <> 0 then
      SendMessage(FormHandle, WM_SYSCOMMAND, DirToSC[FDirection], 0);
  end;
end;

{ TResizeEdgeHelper }

class procedure TResizeEdgeHelper.AttachEdges(Target: TWinControl; EdgeSize: Integer;
  Directions: TResizeDirectionSet);
begin
  HandleSize := EdgeSize;
  MoveHandleHeight := EdgeSize;

  if rdTop in Directions then
    TResizeEdgeLabel.CreateEdge(Target, 1);
  if rdBottom in Directions then
    TResizeEdgeLabel.CreateEdge(Target, 2);
  if rdLeft in Directions then
    TResizeEdgeLabel.CreateEdge(Target, 3);
  if rdRight in Directions then
    TResizeEdgeLabel.CreateEdge(Target, 4);

  // 斜めリサイズは組み合わせで判断
  if (rdTop in Directions) and (rdLeft in Directions) then
    TResizeEdgeLabel.CreateEdge(Target, 6);
  if (rdTop in Directions) and (rdRight in Directions) then
    TResizeEdgeLabel.CreateEdge(Target, 7);
  if (rdBottom in Directions) and (rdLeft in Directions) then
    TResizeEdgeLabel.CreateEdge(Target, 8);
  if (rdBottom in Directions) and (rdRight in Directions) then
    TResizeEdgeLabel.CreateEdge(Target, 9);

  if rdMove in Directions then
    TResizeEdgeLabel.CreateEdge(Target, 5);
  // ← 追加：EdgeSizeに合わせて再配置
  AdjustEdges(Target);
end;

class procedure TResizeEdgeHelper.AdjustEdges(Target: TWinControl);
var
  I: Integer;
begin
  for I := 0 to Target.ControlCount - 1 do
    if Target.Controls[I] is TResizeEdgeLabel then
      TResizeEdgeLabel(Target.Controls[I]).AdjustPosition;
end;

initialization
  TResizeEdgeHelper.FHandleSize := 10;
  TResizeEdgeHelper.FMoveHandleWidth := 80;
  TResizeEdgeHelper.FMoveHandleHeight := 10;

end.

