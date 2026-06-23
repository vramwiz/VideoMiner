unit VideoMinerCurrentFileReloadController;

// 現在開いている動画ファイルの外部更新を監視し、更新が落ち着いてから再読込する。

interface

uses
  System.Classes, System.SysUtils,
  Vcl.ExtCtrls,
  FolderWatch, VideoMinerMediaSession;

type
  TVideoMinerCurrentFileReloadFunc = function(const FileName: string;
    AutoPlay: Boolean; RestoreLoopPosition: Boolean = True): Boolean of object;

  TVideoMinerCurrentFileReloadController = class
  private
    FMediaSession: TVideoMinerMediaSession;
    FReloadTimer: TTimer;
    FFolderWatcher: TFolderWatch;
    FWatchedFolder: string;
    FReloadingCurrentFile: Boolean;
    FPendingReloadHasStamp: Boolean;
    FPendingReloadLastWriteTime: TDateTime;
    FPendingReloadSize: Int64;
    FVideoFileLastWriteTime: TDateTime;
    FVideoFileSize: Int64;
    FOnReload: TVideoMinerCurrentFileReloadFunc;
    function CurrentFileCanBeRead: Boolean;
    function CurrentFileInList(const FileNames: TStringList): Boolean;
    function ReadCurrentFileStamp(out LastWriteTime: TDateTime;
      out Size: Int64): Boolean;
    procedure FolderWatchFileChange(Sender: TObject; const AddFiles: TStringList;
      const DelFiles: TStringList; const UpdateFiles: TStringList);
    procedure ReloadTimer(Sender: TObject);
    procedure ScheduleReload;
  public
    constructor Create(AMediaSession: TVideoMinerMediaSession);
    destructor Destroy; override;
    procedure BeginLoad;
    procedure ConfigureWatch;
    procedure Stop;
    procedure UpdateOpenedFileStamp;
    property OnReload: TVideoMinerCurrentFileReloadFunc read FOnReload
      write FOnReload;
  end;

implementation

const
  CURRENT_FILE_RELOAD_SETTLE_MS = 1500; // ファイル更新が落ち着くまで再読込を待つ時間 ms

constructor TVideoMinerCurrentFileReloadController.Create(
  AMediaSession: TVideoMinerMediaSession);
begin
  inherited Create;
  FMediaSession := AMediaSession;
  FVideoFileSize := -1;
  FPendingReloadSize := -1;

  FReloadTimer := TTimer.Create(nil);
  FReloadTimer.Enabled := False;
  FReloadTimer.Interval := CURRENT_FILE_RELOAD_SETTLE_MS;
  FReloadTimer.OnTimer := ReloadTimer;

  FFolderWatcher := TFolderWatch.Create;
  FFolderWatcher.FirstScanDone := True;
  FFolderWatcher.OnFileChange := FolderWatchFileChange;
end;

destructor TVideoMinerCurrentFileReloadController.Destroy;
begin
  Stop;
  FFolderWatcher.Free;
  FReloadTimer.Free;
  inherited;
end;

procedure TVideoMinerCurrentFileReloadController.BeginLoad;
begin
  if FReloadTimer <> nil then
    FReloadTimer.Enabled := False;
  FPendingReloadHasStamp := False;
end;

procedure TVideoMinerCurrentFileReloadController.ConfigureWatch;
var
  Folder: string;
begin
  if FFolderWatcher = nil then
    Exit;

  if (FMediaSession = nil) or (FMediaSession.VideoFile = '') then
  begin
    FFolderWatcher.Stop;
    FWatchedFolder := '';
    Exit;
  end;

  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(FMediaSession.VideoFile));
  if SameText(FWatchedFolder, Folder) then
    Exit;

  FFolderWatcher.Stop;
  FWatchedFolder := Folder;
  FFolderWatcher.FolderPath := Folder;
  FFolderWatcher.IncludeSubFolders := False;
  FFolderWatcher.FirstScanDone := True;
  FFolderWatcher.Start;
end;

function TVideoMinerCurrentFileReloadController.CurrentFileCanBeRead: Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  if (FMediaSession = nil) or (FMediaSession.VideoFile = '') then
    Exit;

  try
    Stream := TFileStream.Create(FMediaSession.VideoFile,
      fmOpenRead or fmShareDenyNone);
    try
      Result := True;
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

function TVideoMinerCurrentFileReloadController.CurrentFileInList(
  const FileNames: TStringList): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (FileNames = nil) or (FMediaSession = nil) or
     (FMediaSession.VideoFile = '') then
    Exit;

  for I := 0 to FileNames.Count - 1 do
  begin
    if SameText(ExpandFileName(FileNames[I]),
      ExpandFileName(FMediaSession.VideoFile)) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TVideoMinerCurrentFileReloadController.FolderWatchFileChange(
  Sender: TObject; const AddFiles, DelFiles, UpdateFiles: TStringList);
begin
  if FReloadingCurrentFile then
    Exit;

  if CurrentFileInList(AddFiles) or CurrentFileInList(DelFiles) or
     CurrentFileInList(UpdateFiles) then
    ScheduleReload;
end;

function TVideoMinerCurrentFileReloadController.ReadCurrentFileStamp(
  out LastWriteTime: TDateTime; out Size: Int64): Boolean;
var
  SearchRec: TSearchRec;
begin
  LastWriteTime := 0;
  Size := -1;
  Result := False;
  if (FMediaSession = nil) or (FMediaSession.VideoFile = '') then
    Exit;

  if FindFirst(FMediaSession.VideoFile, faAnyFile, SearchRec) <> 0 then
    Exit;
  try
    if (SearchRec.Attr and faDirectory) <> 0 then
      Exit;

    LastWriteTime := SearchRec.TimeStamp;
    Size := SearchRec.Size;
    Result := True;
  finally
    FindClose(SearchRec);
  end;
end;

procedure TVideoMinerCurrentFileReloadController.ReloadTimer(Sender: TObject);
var
  FileName: string;
  LastWriteTime: TDateTime;
  Size: Int64;
begin
  if FReloadTimer <> nil then
    FReloadTimer.Enabled := False;

  if (FMediaSession = nil) or (FMediaSession.VideoFile = '') or
     FReloadingCurrentFile then
    Exit;

  if (not ReadCurrentFileStamp(LastWriteTime, Size)) or
     (not CurrentFileCanBeRead) then
  begin
    if FReloadTimer <> nil then
      FReloadTimer.Enabled := True;
    Exit;
  end;

  if (not FPendingReloadHasStamp) or
     (FPendingReloadLastWriteTime <> LastWriteTime) or
     (FPendingReloadSize <> Size) then
  begin
    FPendingReloadLastWriteTime := LastWriteTime;
    FPendingReloadSize := Size;
    FPendingReloadHasStamp := True;
    if FReloadTimer <> nil then
      FReloadTimer.Enabled := True;
    Exit;
  end;

  FPendingReloadHasStamp := False;
  if (FVideoFileLastWriteTime = LastWriteTime) and (FVideoFileSize = Size) then
    Exit;

  if not Assigned(FOnReload) then
    Exit;

  FileName := FMediaSession.VideoFile;
  FReloadingCurrentFile := True;
  try
    FOnReload(FileName, False, False);
  finally
    FReloadingCurrentFile := False;
  end;
end;

procedure TVideoMinerCurrentFileReloadController.ScheduleReload;
begin
  if (FReloadTimer = nil) or (FMediaSession = nil) or
     (FMediaSession.VideoFile = '') or FReloadingCurrentFile then
    Exit;

  FPendingReloadHasStamp := False;
  FReloadTimer.Enabled := False;
  FReloadTimer.Enabled := True;
end;

procedure TVideoMinerCurrentFileReloadController.Stop;
begin
  if FReloadTimer <> nil then
    FReloadTimer.Enabled := False;
  if FFolderWatcher <> nil then
    FFolderWatcher.Stop;
end;

procedure TVideoMinerCurrentFileReloadController.UpdateOpenedFileStamp;
begin
  if not ReadCurrentFileStamp(FVideoFileLastWriteTime, FVideoFileSize) then
  begin
    FVideoFileLastWriteTime := 0;
    FVideoFileSize := -1;
  end;
end;

end.
