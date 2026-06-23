unit VideoMinerWindowChrome;

// 枠なしフォームを通常ウィンドウらしく扱うための Windows 連携をまとめる。
// 作成パラメータ、非クライアント領域、リサイズ判定、通常時座標の記憶を担当する。

interface

uses
  Winapi.Messages, Winapi.Windows, System.Math, System.Types, Vcl.Controls,
  Vcl.Forms, VideoMinerSettings;

const
  VIDEO_MINER_RESIZE_BORDER = 12; // 枠なしフォーム端でリサイズ判定する幅 px

// 枠なしでも最小化/最大化を持つトップレベルウィンドウとして作る
procedure ConfigureBorderlessCreateParams(var Params: TCreateParams);
// 標準枠の非クライアント領域を消し、クライアント領域だけで描画させる
procedure HandleBorderlessNCCalcSize(var Message: TMessage);
// 枠なしフォームの端/角を Windows 標準リサイズのヒットテストへ変換する
procedure HitTestBorderlessResize(Form: TCustomForm; FullScreen: Boolean;
  BorderSize: Integer; const ScreenPoint: TPoint; var HitTestResult: LRESULT);
// 保存済みの通常ウィンドウ座標を画面内へ補正して適用する
procedure ApplySavedWindowBounds(Form: TCustomForm;
  var NormalWindowBounds: TVideoMinerWindowBounds);
// 通常表示時だけ、次回復元や保存に使うウィンドウ座標を覚える
procedure RememberNormalWindowBounds(Form: TCustomForm; FullScreen: Boolean;
  var NormalWindowBounds: TVideoMinerWindowBounds);
// 終了前に最大化状態を通常化し、保存に使える座標を確定する
procedure RestoreAndRememberNormalWindowBoundsForSave(Form: TCustomForm;
  FullScreen: Boolean; var NormalWindowBounds: TVideoMinerWindowBounds);

implementation

// 標準タイトルバーと太枠を外しつつ、タスクバー操作に必要なスタイルは残す
procedure ConfigureBorderlessCreateParams(var Params: TCreateParams);
begin
  Params.Style := (Params.Style or WS_MINIMIZEBOX or WS_MAXIMIZEBOX) and
    not WS_CAPTION and not WS_THICKFRAME;
end;

// WM_NCCALCSIZE に 0 を返し、標準枠分の余白を作らせない
procedure HandleBorderlessNCCalcSize(var Message: TMessage);
begin
  if Message.WParam <> 0 then
    Message.Result := 0;
end;

// クライアント座標の端/角だけをリサイズ対象にし、全画面中は無効化する
procedure HitTestBorderlessResize(Form: TCustomForm; FullScreen: Boolean;
  BorderSize: Integer; const ScreenPoint: TPoint; var HitTestResult: LRESULT);
var
  ClientPoint: TPoint;
begin
  if (Form = nil) or FullScreen or (HitTestResult <> HTCLIENT) then
    Exit;

  ClientPoint := Form.ScreenToClient(ScreenPoint);

  if (ClientPoint.X < BorderSize) and (ClientPoint.Y < BorderSize) then
    HitTestResult := HTTOPLEFT
  else if (ClientPoint.X >= Form.ClientWidth - BorderSize) and
          (ClientPoint.Y < BorderSize) then
    HitTestResult := HTTOPRIGHT
  else if (ClientPoint.X < BorderSize) and
          (ClientPoint.Y >= Form.ClientHeight - BorderSize) then
    HitTestResult := HTBOTTOMLEFT
  else if (ClientPoint.X >= Form.ClientWidth - BorderSize) and
          (ClientPoint.Y >= Form.ClientHeight - BorderSize) then
    HitTestResult := HTBOTTOMRIGHT
  else if ClientPoint.Y < BorderSize then
    HitTestResult := HTTOP
  else if ClientPoint.Y >= Form.ClientHeight - BorderSize then
    HitTestResult := HTBOTTOM
  else if ClientPoint.X < BorderSize then
    HitTestResult := HTLEFT
  else if ClientPoint.X >= Form.ClientWidth - BorderSize then
    HitTestResult := HTRIGHT;
end;

// 保存座標が現在のモニター作業領域から外れても見失わないように補正する
procedure ApplySavedWindowBounds(Form: TCustomForm;
  var NormalWindowBounds: TVideoMinerWindowBounds);
var
  Bounds: TVideoMinerWindowBounds;
  MinHeight: Integer;
  MinWidth: Integer;
  Monitor: TMonitor;
  NewBounds: TRect;
  WorkArea: TRect;
begin
  if Form = nil then
    Exit;

  Form.WindowState := wsNormal;
  Bounds := LoadMainFormBounds;
  if not Bounds.Available then
  begin
    RememberNormalWindowBounds(Form, False, NormalWindowBounds);
    Exit;
  end;

  NewBounds := Rect(Bounds.Left, Bounds.Top, Bounds.Left + Bounds.Width,
    Bounds.Top + Bounds.Height);
  Monitor := Screen.MonitorFromRect(NewBounds, mdNearest);
  if Monitor <> nil then
    WorkArea := Monitor.WorkareaRect
  else
    WorkArea := Screen.WorkAreaRect;

  if NewBounds.Width > WorkArea.Width then
    NewBounds.Right := NewBounds.Left + WorkArea.Width;
  if NewBounds.Height > WorkArea.Height then
    NewBounds.Bottom := NewBounds.Top + WorkArea.Height;
  MinWidth := Min(Max(0, Form.Constraints.MinWidth), WorkArea.Width);
  MinHeight := Min(Max(0, Form.Constraints.MinHeight), WorkArea.Height);
  if NewBounds.Width < MinWidth then
    NewBounds.Right := NewBounds.Left + MinWidth;
  if NewBounds.Height < MinHeight then
    NewBounds.Bottom := NewBounds.Top + MinHeight;

  if NewBounds.Left < WorkArea.Left then
    OffsetRect(NewBounds, WorkArea.Left - NewBounds.Left, 0);
  if NewBounds.Top < WorkArea.Top then
    OffsetRect(NewBounds, 0, WorkArea.Top - NewBounds.Top);
  if NewBounds.Right > WorkArea.Right then
    OffsetRect(NewBounds, WorkArea.Right - NewBounds.Right, 0);
  if NewBounds.Bottom > WorkArea.Bottom then
    OffsetRect(NewBounds, 0, WorkArea.Bottom - NewBounds.Bottom);

  Form.SetBounds(NewBounds.Left, NewBounds.Top, NewBounds.Width,
    NewBounds.Height);
  RememberNormalWindowBounds(Form, False, NormalWindowBounds);
end;

// 最大化/最小化/全画面の一時的な座標を保存しないよう通常表示だけを採用する
procedure RememberNormalWindowBounds(Form: TCustomForm; FullScreen: Boolean;
  var NormalWindowBounds: TVideoMinerWindowBounds);
begin
  if (Form = nil) or FullScreen then
    Exit;
  if Form.HandleAllocated and (IsIconic(Form.Handle) or IsZoomed(Form.Handle)) then
    Exit;
  if Form.WindowState <> wsNormal then
    Exit;

  NormalWindowBounds.Available := True;
  NormalWindowBounds.Left := Form.Left;
  NormalWindowBounds.Top := Form.Top;
  NormalWindowBounds.Width := Form.Width;
  NormalWindowBounds.Height := Form.Height;
end;

// 終了時保存で最大化後の仮想サイズを拾わないよう、通常表示へ戻してから覚える
procedure RestoreAndRememberNormalWindowBoundsForSave(Form: TCustomForm;
  FullScreen: Boolean; var NormalWindowBounds: TVideoMinerWindowBounds);
begin
  if (Form = nil) or FullScreen then
    Exit;

  if Form.HandleAllocated and IsZoomed(Form.Handle) then
  begin
    ShowWindow(Form.Handle, SW_RESTORE);
    Form.WindowState := wsNormal;
  end
  else if Form.WindowState = wsMaximized then
    Form.WindowState := wsNormal;

  RememberNormalWindowBounds(Form, FullScreen, NormalWindowBounds);
end;

end.
