unit PluginInputSettings;

interface

uses
  Winapi.Windows, Winapi.Messages;

type
  TVideoDecoderMode = (vdmAuto, vdmQsv, vdmSoftware);

function GetVideoDecoderMode: TVideoDecoderMode;
function VideoDecoderModeToText(Mode: TVideoDecoderMode): string;
function ShowPluginSettingsDialog(Parent: HWND; DllInstance: HINST): BOOL;

implementation

uses
  System.IniFiles, System.SysUtils;

const
  PLUGIN_DISPLAY_NAME = '動画IN';
  SETTINGS_SECTION = 'VW_Media_Input';
  SETTINGS_DECODER_MODE = 'VideoDecoderMode';

  IDC_MODE_AUTO = 1001;
  IDC_MODE_QSV = 1002;
  IDC_MODE_SOFTWARE = 1003;
  IDC_BUTTON_OK = IDOK;
  IDC_BUTTON_CANCEL = IDCANCEL;

var
  CurrentVideoDecoderMode: TVideoDecoderMode = vdmAuto;
  SettingsLoaded: Boolean = False;

function SettingsFileName: string;
var
  ModulePath: array[0..MAX_PATH - 1] of Char;
begin
  if GetModuleFileName(HInstance, ModulePath, Length(ModulePath)) > 0 then
    Result := ChangeFileExt(ModulePath, '.ini')
  else
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'VW_Media_Input.ini';
end;

function TextToVideoDecoderMode(const Value: string): TVideoDecoderMode;
begin
  if SameText(Value, 'qsv') then
    Result := vdmQsv
  else if SameText(Value, 'software') then
    Result := vdmSoftware
  else
    Result := vdmAuto;
end;

function VideoDecoderModeToText(Mode: TVideoDecoderMode): string;
begin
  case Mode of
    vdmQsv:
      Result := 'qsv';
    vdmSoftware:
      Result := 'software';
  else
    Result := 'auto';
  end;
end;

type
  TGetDpiForWindow = function(Window: HWND): UINT; stdcall;

function DpiForWindow(Window: HWND): Integer;
var
  User32: HMODULE;
  GetDpiForWindowProc: TGetDpiForWindow;
  Dc: HDC;
begin
  Result := 96;

  User32 := GetModuleHandle('user32.dll');
  if User32 <> 0 then
  begin
    @GetDpiForWindowProc := GetProcAddress(User32, 'GetDpiForWindow');
    if Assigned(GetDpiForWindowProc) then
    begin
      Result := GetDpiForWindowProc(Window);
      if Result > 0 then
        Exit;
    end;
  end;

  Dc := GetDC(Window);
  if Dc <> 0 then
  begin
    Result := GetDeviceCaps(Dc, LOGPIXELSX);
    ReleaseDC(Window, Dc);
  end;

  if Result <= 0 then
    Result := 96;
end;

function DpiForParent(Parent: HWND): Integer;
begin
  if (Parent <> 0) and IsWindow(Parent) then
    Result := DpiForWindow(Parent)
  else
    Result := DpiForWindow(0);
end;

function ScaleByDpi(Value, Dpi: Integer): Integer;
begin
  Result := MulDiv(Value, Dpi, 96);
end;

procedure LoadSettings;
var
  Ini: TIniFile;
begin
  if SettingsLoaded then
    Exit;

  SettingsLoaded := True;
  Ini := TIniFile.Create(SettingsFileName);
  try
    CurrentVideoDecoderMode := TextToVideoDecoderMode(
      Ini.ReadString(SETTINGS_SECTION, SETTINGS_DECODER_MODE, 'auto'));
  finally
    Ini.Free;
  end;
end;

procedure SaveSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteString(SETTINGS_SECTION, SETTINGS_DECODER_MODE,
      VideoDecoderModeToText(CurrentVideoDecoderMode));
  finally
    Ini.Free;
  end;
end;

function GetVideoDecoderMode: TVideoDecoderMode;
begin
  LoadSettings;
  Result := CurrentVideoDecoderMode;
end;

type
  PSettingsDialogState = ^TSettingsDialogState;
  TSettingsDialogState = record
    Parent: HWND;
    Mode: TVideoDecoderMode;
    Done: Boolean;
    Result: BOOL;
  end;

procedure SelectModeRadio(Window: HWND; Mode: TVideoDecoderMode);
begin
  CheckRadioButton(Window, IDC_MODE_AUTO, IDC_MODE_SOFTWARE,
    IDC_MODE_AUTO + Ord(Mode));
end;

function SelectedMode(Window: HWND): TVideoDecoderMode;
begin
  if SendMessage(GetDlgItem(Window, IDC_MODE_QSV), BM_GETCHECK, 0, 0) = BST_CHECKED then
    Result := vdmQsv
  else if SendMessage(GetDlgItem(Window, IDC_MODE_SOFTWARE), BM_GETCHECK, 0, 0) = BST_CHECKED then
    Result := vdmSoftware
  else
    Result := vdmAuto;
end;

procedure CenterWindow(Window, Parent: HWND);
var
  Rect: TRect;
  ParentRect: TRect;
  X: Integer;
  Y: Integer;
begin
  GetWindowRect(Window, Rect);
  if (Parent <> 0) and IsWindow(Parent) then
    GetWindowRect(Parent, ParentRect)
  else
  begin
    ParentRect.Left := 0;
    ParentRect.Top := 0;
    ParentRect.Right := GetSystemMetrics(SM_CXSCREEN);
    ParentRect.Bottom := GetSystemMetrics(SM_CYSCREEN);
  end;

  X := ParentRect.Left + ((ParentRect.Right - ParentRect.Left) - (Rect.Right - Rect.Left)) div 2;
  Y := ParentRect.Top + ((ParentRect.Bottom - ParentRect.Top) - (Rect.Bottom - Rect.Top)) div 2;
  SetWindowPos(Window, 0, X, Y, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
end;

function SettingsDialogProc(Window: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  State: PSettingsDialogState;
  Font: HFONT;
  Dpi: Integer;

  function S(Value: Integer): Integer;
  begin
    Result := ScaleByDpi(Value, Dpi);
  end;

  function AddControl(ExStyle: DWORD; const ClassName, Text: string; Style: DWORD;
    X, Y, Width, Height: Integer; ControlId: Integer): HWND;
  begin
    Result := CreateWindowEx(ExStyle, PChar(ClassName), PChar(Text),
      Style, S(X), S(Y), S(Width), S(Height), Window, HMENU(ControlId),
      HInstance, nil);
    if Result <> 0 then
      SendMessage(Result, WM_SETFONT, NativeUInt(Font), 0);
  end;
begin
  State := PSettingsDialogState(GetWindowLongPtr(Window, GWLP_USERDATA));
  case Msg of
    WM_NCCREATE:
    begin
      SetWindowLongPtr(Window, GWLP_USERDATA,
        NativeInt(PCREATESTRUCT(LParam)^.lpCreateParams));
      Result := 1;
      Exit;
    end;
    WM_CREATE:
    begin
      State := PSettingsDialogState(GetWindowLongPtr(Window, GWLP_USERDATA));
      Font := HFONT(GetStockObject(DEFAULT_GUI_FONT));
      Dpi := DpiForWindow(Window);
      SetWindowText(Window, PChar(PLUGIN_DISPLAY_NAME + ' 設定'));

      AddControl(0, 'STATIC', 'デコード方式',
        WS_CHILD or WS_VISIBLE, 16, 16, 260, 20, 0);

      AddControl(0, 'BUTTON', '自動（QSVを優先し、失敗時はソフトウェア）',
        WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_AUTORADIOBUTTON,
        22, 44, 330, 24, IDC_MODE_AUTO);
      AddControl(0, 'BUTTON', 'ハードウェア固定（QSV）',
        WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_AUTORADIOBUTTON,
        22, 74, 330, 24, IDC_MODE_QSV);
      AddControl(0, 'BUTTON', 'ソフトウェア',
        WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_AUTORADIOBUTTON,
        22, 104, 330, 24, IDC_MODE_SOFTWARE);

      AddControl(0, 'BUTTON', 'OK',
        WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_DEFPUSHBUTTON,
        182, 148, 82, 28, IDC_BUTTON_OK);
      AddControl(0, 'BUTTON', 'キャンセル',
        WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_PUSHBUTTON,
        272, 148, 82, 28, IDC_BUTTON_CANCEL);

      SendMessage(Window, WM_SETFONT, NativeUInt(Font), 0);

      SelectModeRadio(Window, State^.Mode);
      CenterWindow(Window, State^.Parent);
      Result := 0;
      Exit;
    end;
    WM_COMMAND:
    begin
      case LOWORD(WParam) of
        IDC_BUTTON_OK:
        begin
          State^.Mode := SelectedMode(Window);
          State^.Result := True;
          State^.Done := True;
          DestroyWindow(Window);
          Result := 0;
          Exit;
        end;
        IDC_BUTTON_CANCEL:
        begin
          State^.Result := False;
          State^.Done := True;
          DestroyWindow(Window);
          Result := 0;
          Exit;
        end;
      end;
    end;
    WM_CLOSE:
    begin
      if State <> nil then
      begin
        State^.Result := False;
        State^.Done := True;
      end;
      DestroyWindow(Window);
      Result := 0;
      Exit;
    end;
  end;

  Result := DefWindowProc(Window, Msg, WParam, LParam);
end;

function ShowPluginSettingsDialog(Parent: HWND; DllInstance: HINST): BOOL;
var
  ClassName: string;
  WindowClass: WNDCLASS;
  State: TSettingsDialogState;
  Window: HWND;
  Msg: TMsg;
  ParentEnabled: Boolean;
  DialogTitle: string;
  Dpi: Integer;
begin
  LoadSettings;
  Result := False;
  ClassName := 'VW_Media_Input_Settings';
  DialogTitle := PLUGIN_DISPLAY_NAME + ' 設定';
  Dpi := DpiForParent(Parent);

  FillChar(WindowClass, SizeOf(WindowClass), 0);
  WindowClass.lpfnWndProc := @SettingsDialogProc;
  WindowClass.hInstance := DllInstance;
  WindowClass.hCursor := LoadCursor(0, IDC_ARROW);
  WindowClass.hbrBackground := HBRUSH(COLOR_BTNFACE + 1);
  WindowClass.lpszClassName := PChar(ClassName);
  RegisterClass(WindowClass);

  State.Parent := Parent;
  State.Mode := CurrentVideoDecoderMode;
  State.Done := False;
  State.Result := False;

  Window := CreateWindowEx(WS_EX_DLGMODALFRAME, PChar(ClassName), PChar(DialogTitle),
    WS_POPUP or WS_CAPTION or WS_SYSMENU,
    CW_USEDEFAULT, CW_USEDEFAULT, ScaleByDpi(380, Dpi), ScaleByDpi(220, Dpi),
    Parent, 0, DllInstance, @State);
  if Window = 0 then
    Exit;
  SetWindowText(Window, PChar(DialogTitle));

  ParentEnabled := False;
  if (Parent <> 0) and IsWindow(Parent) and IsWindowEnabled(Parent) then
  begin
    ParentEnabled := True;
    EnableWindow(Parent, False);
  end;

  ShowWindow(Window, SW_SHOW);
  UpdateWindow(Window);

  while (not State.Done) and (GetMessage(Msg, 0, 0, 0)) do
  begin
    if not IsDialogMessage(Window, Msg) then
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  end;

  if ParentEnabled then
  begin
    EnableWindow(Parent, True);
    SetActiveWindow(Parent);
  end;

  if State.Result then
  begin
    CurrentVideoDecoderMode := State.Mode;
    SaveSettings;
  end;

  Result := True;
end;

initialization
  LoadSettings;

end.
