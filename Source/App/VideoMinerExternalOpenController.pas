unit VideoMinerExternalOpenController;

// ドラッグ&ドロップ、二重起動からの COPYDATA、保留 open キューを扱う。

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.SysUtils,
  Vcl.Controls, Vcl.Forms,
  ActiveX, DropAgent;

type
  TVideoMinerExternalOpenFunc = function(const FileName: string): Boolean of object;

  TVideoMinerExternalOpenController = class
  private
    FDropAgent: TDropAgent;
    FHostForm: TCustomForm;
    FOleInitialized: Boolean;
    FOnOpenAndPlay: TVideoMinerExternalOpenFunc;
    FPendingMessage: Cardinal;
    FPendingOpenFiles: TStringList;
    FProcessingOpenQueue: Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl;
      const FileNames: TArray<string>);
  public
    constructor Create(AHostForm: TCustomForm; APendingMessage: Cardinal);
    destructor Destroy; override;
    function HandleCopyData(var Message: TWMCopyData): Boolean;
    procedure ProcessOpenQueue;
    procedure QueueOpenAndPlayFile(const FileName: string);
    property OleInitialized: Boolean read FOleInitialized;
    property OnOpenAndPlay: TVideoMinerExternalOpenFunc read FOnOpenAndPlay
      write FOnOpenAndPlay;
  end;

implementation

const
  COPYDATA_OPEN_FILE = $564D0001; // 別プロセスからファイル名を受け取る COPYDATA 種別

constructor TVideoMinerExternalOpenController.Create(AHostForm: TCustomForm;
  APendingMessage: Cardinal);
begin
  inherited Create;
  FHostForm := AHostForm;
  FPendingMessage := APendingMessage;
  FPendingOpenFiles := TStringList.Create;

  FOleInitialized := OleInitialize(nil) >= 0;
  FDropAgent := TDropAgent.Create;
  if FOleInitialized and (FHostForm <> nil) then
  begin
    FDropAgent.AcceptKinds := [dakFiles];
    FDropAgent.OnDropFiles := DropFiles;
    FDropAgent.Attach(FHostForm);
  end;
end;

destructor TVideoMinerExternalOpenController.Destroy;
begin
  FDropAgent.Free;
  FPendingOpenFiles.Free;
  if FOleInitialized then
    OleUninitialize;
  inherited;
end;

procedure TVideoMinerExternalOpenController.DropFiles(Sender: TObject;
  Control: TWinControl; const FileNames: TArray<string>);
begin
  if (Length(FileNames) > 0) and Assigned(FOnOpenAndPlay) then
    FOnOpenAndPlay(FileNames[0]);
end;

function TVideoMinerExternalOpenController.HandleCopyData(
  var Message: TWMCopyData): Boolean;
var
  FileName: string;
begin
  Result := False;
  if (Message.CopyDataStruct = nil) or
     (Message.CopyDataStruct.dwData <> COPYDATA_OPEN_FILE) then
    Exit;

  Result := True;
  if FHostForm <> nil then
  begin
    if FHostForm.WindowState = wsMinimized then
      FHostForm.WindowState := wsNormal;
    Application.Restore;
    FHostForm.BringToFront;
    SetForegroundWindow(FHostForm.Handle);
  end;

  FileName := '';
  if (Message.CopyDataStruct.cbData > SizeOf(Char)) and
     (Message.CopyDataStruct.lpData <> nil) then
    FileName := PChar(Message.CopyDataStruct.lpData);

  if FileName <> '' then
    QueueOpenAndPlayFile(FileName);

  Message.Result := 1;
end;

procedure TVideoMinerExternalOpenController.ProcessOpenQueue;
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
      if Assigned(FOnOpenAndPlay) then
        FOnOpenAndPlay(FileName);
    end;
  finally
    FProcessingOpenQueue := False;
  end;
end;

procedure TVideoMinerExternalOpenController.QueueOpenAndPlayFile(
  const FileName: string);
begin
  if (FileName = '') or (FHostForm = nil) then
    Exit;

  FPendingOpenFiles.Add(FileName);
  PostMessage(FHostForm.Handle, FPendingMessage, 0, 0);
end;

end.
