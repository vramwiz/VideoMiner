unit VideoMinerMediaOpen;

interface

uses
  System.SysUtils, FFmpegDecoder, FFmpegDecoderTypes, VideoMinerMediaList,
  VideoMinerSettings;

type
  TVideoMinerMediaOpenResult = record
    ErrorMessage: string;
    FileName: string;
    Info: TVideoInfo;
  end;

function ValidateVideoMinerMediaFile(const FileName: string;
  out ErrorMessage: string): Boolean;

function VideoMinerOpenDialogInitialDir(const CurrentFileName: string): string;
procedure RememberVideoMinerMediaFile(const FileName: string);
function ResolveRememberedVideoMinerMediaFile(out FileName: string;
  out ErrorMessage: string): Boolean;

function OpenVideoMinerMediaFile(const FileName: string; Decoder,
  PreviewDecoder: TFFmpegDecoder; MediaList: TVideoMinerMediaList;
  out OpenResult: TVideoMinerMediaOpenResult): Boolean;

implementation

function ValidateVideoMinerMediaFile(const FileName: string;
  out ErrorMessage: string): Boolean;
var
  Folder: string;
begin
  Result := False;
  ErrorMessage := '';

  if FileName = '' then
  begin
    ErrorMessage := 'File name is empty.';
    Exit;
  end;

  Folder := ExtractFilePath(FileName);
  if (Folder <> '') and (not DirectoryExists(Folder)) then
  begin
    ErrorMessage := 'Folder not found: ' + Folder;
    Exit;
  end;

  if not FileExists(FileName) then
  begin
    ErrorMessage := 'File not found: ' + FileName;
    Exit;
  end;

  Result := True;
end;

function VideoMinerOpenDialogInitialDir(const CurrentFileName: string): string;
var
  LastMedia: TVideoMinerLastMedia;
begin
  Result := '';
  if CurrentFileName <> '' then
    Result := ExtractFilePath(CurrentFileName);

  if (Result = '') or (not DirectoryExists(Result)) then
  begin
    LastMedia := LoadLastMedia;
    Result := LastMedia.Folder;
  end;

  if (Result = '') or (not DirectoryExists(Result)) then
    Result := '';
end;

procedure RememberVideoMinerMediaFile(const FileName: string);
var
  Folder: string;
begin
  if FileName = '' then
    Exit;

  Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(FileName));
  SaveLastMedia(Folder, FileName);
end;

function ResolveRememberedVideoMinerMediaFile(out FileName: string;
  out ErrorMessage: string): Boolean;
var
  Folder: string;
  LastMedia: TVideoMinerLastMedia;
begin
  Result := False;
  ErrorMessage := '';
  FileName := '';

  LastMedia := LoadLastMedia;
  if not LastMedia.Available then
    Exit;

  Folder := LastMedia.Folder;
  FileName := LastMedia.FileName;
  if (FileName <> '') and (ExtractFilePath(FileName) = '') and
     (Folder <> '') then
    FileName := IncludeTrailingPathDelimiter(Folder) + FileName;

  if (Folder <> '') and (not DirectoryExists(Folder)) then
  begin
    ErrorMessage := 'Last folder not found: ' + Folder;
    Exit;
  end;

  if FileName = '' then
  begin
    ErrorMessage := 'Last file is not stored.';
    Exit;
  end;

  if not FileExists(FileName) then
  begin
    ErrorMessage := 'Last file not found: ' + FileName;
    Exit;
  end;

  Result := True;
end;

function OpenVideoMinerMediaFile(const FileName: string; Decoder,
  PreviewDecoder: TFFmpegDecoder; MediaList: TVideoMinerMediaList;
  out OpenResult: TVideoMinerMediaOpenResult): Boolean;
var
  PreviewInfo: TVideoInfo;
begin
  Result := False;
  OpenResult.ErrorMessage := '';
  OpenResult.FileName := '';
  FillChar(OpenResult.Info, SizeOf(OpenResult.Info), 0);

  if not ValidateVideoMinerMediaFile(FileName, OpenResult.ErrorMessage) then
    Exit;

  if not Decoder.Open(FileName, OpenResult.Info, OpenResult.ErrorMessage) then
  begin
    OpenResult.ErrorMessage := 'Failed to open video: ' + OpenResult.ErrorMessage;
    if MediaList <> nil then
      MediaList.Clear;
    Exit;
  end;

  if not PreviewDecoder.Open(FileName, PreviewInfo, OpenResult.ErrorMessage) then
  begin
    Decoder.Close;
    OpenResult.ErrorMessage := 'Failed to open preview decoder: ' +
      OpenResult.ErrorMessage;
    if MediaList <> nil then
      MediaList.Clear;
    Exit;
  end;

  if MediaList <> nil then
    MediaList.BuildForFile(FileName);
  OpenResult.FileName := FileName;
  Result := True;
end;

end.
