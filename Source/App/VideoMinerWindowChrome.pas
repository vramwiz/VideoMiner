unit VideoMinerWindowChrome;

interface

uses
  Winapi.Messages, Winapi.Windows, System.Types, Vcl.Controls, Vcl.Forms,
  VideoMinerSettings;

const
  VIDEO_MINER_RESIZE_BORDER = 6;

procedure ConfigureBorderlessCreateParams(var Params: TCreateParams);
procedure HandleBorderlessNCCalcSize(var Message: TMessage);
procedure HitTestBorderlessResize(Form: TCustomForm; FullScreen: Boolean;
  BorderSize: Integer; const ScreenPoint: TPoint; var HitTestResult: LRESULT);
procedure ApplySavedWindowBounds(Form: TCustomForm;
  var NormalWindowBounds: TVideoMinerWindowBounds);
procedure RememberNormalWindowBounds(Form: TCustomForm; FullScreen: Boolean;
  var NormalWindowBounds: TVideoMinerWindowBounds);
procedure RestoreAndRememberNormalWindowBoundsForSave(Form: TCustomForm;
  FullScreen: Boolean; var NormalWindowBounds: TVideoMinerWindowBounds);

implementation

procedure ConfigureBorderlessCreateParams(var Params: TCreateParams);
begin
  Params.Style := (Params.Style or WS_MINIMIZEBOX or WS_MAXIMIZEBOX) and
    not WS_CAPTION and not WS_THICKFRAME;
end;

procedure HandleBorderlessNCCalcSize(var Message: TMessage);
begin
  if Message.WParam <> 0 then
    Message.Result := 0;
end;

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

procedure ApplySavedWindowBounds(Form: TCustomForm;
  var NormalWindowBounds: TVideoMinerWindowBounds);
var
  Bounds: TVideoMinerWindowBounds;
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
