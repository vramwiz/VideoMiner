unit VideoMinerMediaOpen;

// 動画ファイルを開く前後の検証と、前回ファイルの解決を担当する。
// メインフォームが UI 状態をリセットする前に失敗を判定できるよう、
// ファイル存在確認、デコーダ open、メディア一覧構築をまとめて扱う。

interface

uses
  System.Diagnostics, System.SysUtils, FFmpegDecoder, FFmpegDecoderTypes,
  VideoMinerDebugLog, VideoMinerMediaList, VideoMinerSettings
{$IFDEF DEBUG}
  , Winapi.Windows
{$ENDIF}
  ;

type
  TVideoMinerMediaOpenResult = record
    ErrorMessage : string;     // 失敗時に UI へ表示する理由
    FileName     : string;     // 実際に開けた動画ファイル
    Info         : TVideoInfo; // メインデコーダから得た動画情報
  end;

// UI 状態を壊す前に、指定ファイルが開く対象として存在するか確認する
function ValidateVideoMinerMediaFile(const FileName: string;
  out ErrorMessage: string): Boolean;
// 指定されたファイルまたはフォルダから、実際に開く動画ファイルを返す
function ResolveVideoMinerMediaOpenTarget(const Path: string;
  out FileName: string; out ErrorMessage: string): Boolean;

// ファイル選択ダイアログで最初に表示するフォルダを決める
function VideoMinerOpenDialogInitialDir(const CurrentFileName: string): string;
// 正常に開けたファイルを、次回起動や次回ダイアログの基準として保存する
procedure RememberVideoMinerMediaFile(const FileName: string);
// 保存済みの前回ファイルを、現在開ける絶対パスとして解決する
function ResolveRememberedVideoMinerMediaFile(out FileName: string;
  out ErrorMessage: string): Boolean;

// メイン/プレビューデコーダを開き、同じフォルダの動画一覧を更新する
function OpenVideoMinerMediaFile(const FileName: string; Decoder,
  PreviewDecoder: TFFmpegDecoder; MediaList: TVideoMinerMediaList;
  out OpenResult: TVideoMinerMediaOpenResult): Boolean;

implementation

{$IFDEF DEBUG}
function VideoMinerPathKindText(const FileName: string): string;
var
  DriveRoot: string;
begin
  if FileName = '' then
    Exit('empty');

  DriveRoot := IncludeTrailingPathDelimiter(ExtractFileDrive(FileName));
  case GetDriveType(PChar(DriveRoot)) of
    DRIVE_REMOTE:
      Result := 'remote';
    DRIVE_FIXED:
      Result := 'fixed';
    DRIVE_REMOVABLE:
      Result := 'removable';
    DRIVE_CDROM:
      Result := 'cdrom';
    DRIVE_RAMDISK:
      Result := 'ramdisk';
    DRIVE_NO_ROOT_DIR:
      Result := 'no_root';
    DRIVE_UNKNOWN:
      Result := 'unknown';
  else
    Result := 'other';
  end;
end;
{$ENDIF}

function ResolveVideoMinerMediaOpenTarget(const Path: string;
  out FileName: string; out ErrorMessage: string): Boolean;
var
  Folder: string;
begin
  Result := False;
  ErrorMessage := '';
  FileName := '';

  if Path = '' then
  begin
    ErrorMessage := 'File or folder name is empty.';
    Exit;
  end;

  if DirectoryExists(Path) then
  begin
    FileName := TVideoMinerMediaList.FirstMediaFileInFolder(Path);
    if FileName = '' then
    begin
      ErrorMessage := 'No video file found in folder: ' + Path;
      Exit;
    end;

    Result := True;
    Exit;
  end;

  FileName := Path;
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

function ValidateVideoMinerMediaFile(const FileName: string;
  out ErrorMessage: string): Boolean;
var
  TargetFileName: string;
begin
  Result := ResolveVideoMinerMediaOpenTarget(FileName, TargetFileName,
    ErrorMessage);
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
  TargetFileName: string;
{$IFDEF DEBUG}
  MediaCount: Integer;
  StepWatch: TStopwatch;
  TotalWatch: TStopwatch;
  ValidateMs: Double;
  DecoderOpenMs: Double;
  PreviewOpenMs: Double;
  MediaListMs: Double;
{$ENDIF}
begin
  Result := False;
  OpenResult.ErrorMessage := '';
  OpenResult.FileName := '';
  FillChar(OpenResult.Info, SizeOf(OpenResult.Info), 0);

{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  if not ResolveVideoMinerMediaOpenTarget(FileName, TargetFileName,
    OpenResult.ErrorMessage) then
  begin
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'media_open_failed step="validate" file="%s" drive="%s" path_kind=%s validate_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       VideoMinerPathKindText(FileName), StepWatch.Elapsed.TotalMilliseconds,
       TotalWatch.Elapsed.TotalMilliseconds, OpenResult.ErrorMessage]));
{$ENDIF}
    Exit;
  end;
{$IFDEF DEBUG}
  ValidateMs := StepWatch.Elapsed.TotalMilliseconds;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}

  if not Decoder.Open(TargetFileName, OpenResult.Info,
    OpenResult.ErrorMessage) then
  begin
{$IFDEF DEBUG}
    DecoderOpenMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}
    OpenResult.ErrorMessage := 'Failed to open video: ' + OpenResult.ErrorMessage;
    if MediaList <> nil then
      MediaList.Clear;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'media_open_failed step="decoder_open" file="%s" drive="%s" path_kind=%s validate_ms=%.3f decoder_open_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       VideoMinerPathKindText(FileName), ValidateMs, DecoderOpenMs,
       TotalWatch.Elapsed.TotalMilliseconds,
       OpenResult.ErrorMessage]));
{$ENDIF}
    Exit;
  end;
{$IFDEF DEBUG}
  DecoderOpenMs := StepWatch.Elapsed.TotalMilliseconds;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}

  if not PreviewDecoder.Open(TargetFileName, PreviewInfo,
    OpenResult.ErrorMessage) then
  begin
{$IFDEF DEBUG}
    PreviewOpenMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}
    Decoder.Close;
    OpenResult.ErrorMessage := 'Failed to open preview decoder: ' +
      OpenResult.ErrorMessage;
    if MediaList <> nil then
      MediaList.Clear;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'media_open_failed step="preview_open" file="%s" drive="%s" path_kind=%s validate_ms=%.3f decoder_open_ms=%.3f preview_open_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(FileName), ExtractFileDrive(FileName),
       VideoMinerPathKindText(FileName), ValidateMs, DecoderOpenMs,
       PreviewOpenMs, TotalWatch.Elapsed.TotalMilliseconds,
       OpenResult.ErrorMessage]));
{$ENDIF}
    Exit;
  end;
{$IFDEF DEBUG}
  PreviewOpenMs := StepWatch.Elapsed.TotalMilliseconds;
  StepWatch := TStopwatch.StartNew;
{$ENDIF}

  if MediaList <> nil then
    MediaList.BuildForFile(TargetFileName);
{$IFDEF DEBUG}
  MediaListMs := StepWatch.Elapsed.TotalMilliseconds;
  if MediaList <> nil then
    MediaCount := MediaList.Count
  else
    MediaCount := 0;
{$ENDIF}
  OpenResult.FileName := TargetFileName;
  Result := True;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'media_open_done file="%s" drive="%s" path_kind=%s validate_ms=%.3f decoder_open_ms=%.3f preview_open_ms=%.3f media_list_ms=%.3f total_ms=%.3f media_count=%d duration_ms=%d fps=%.3f',
    [ExtractFileName(FileName), ExtractFileDrive(FileName),
     VideoMinerPathKindText(FileName), ValidateMs, DecoderOpenMs, PreviewOpenMs, MediaListMs,
     TotalWatch.Elapsed.TotalMilliseconds,
     MediaCount,
     Round(OpenResult.Info.DurationSec * 1000), OpenResult.Info.Fps]));
{$ENDIF}
end;

end.
