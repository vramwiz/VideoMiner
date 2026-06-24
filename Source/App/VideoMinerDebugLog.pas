unit VideoMinerDebugLog;

// 調査ログ出力を担当する。
// 詳細ログと slow log は Debug 専用、倍速再生ログは Release でも使えるようにする。

interface

// ログファイルを削除し、削除理由を先頭行として記録する
procedure ClearVideoMinerDebugLog(const Reason: string);
// 詳細調査用ログが有効な場合だけ 1 行出力する
procedure WriteVideoMinerDebugLog(const Msg: string);
// 遅い処理の調査ログが有効な場合だけ 1 行出力する
procedure WriteVideoMinerSlowLog(const Msg: string);
// 倍速再生の調査ログが有効な場合だけ 1 行出力する
procedure WriteVideoMinerRateLog(const Msg: string);
// 詳細調査用ログが有効か返す
function VideoMinerDebugLogEnabled: Boolean;
// slow log が有効か返す
function VideoMinerSlowLogEnabled: Boolean;
// 倍速再生ログが有効か返す
function VideoMinerRateLogEnabled: Boolean;
// VideoMiner の調査ログファイル名を返す
function VideoMinerDebugLogFileName: string;

implementation

uses
  Winapi.Windows, System.SysUtils, Winapi.ShlObj;

const
  DEBUG_LOG_ENABLED = False; // 毎 tick 系の詳細ログを出すか
  SLOW_LOG_ENABLED  = False; // 遅い処理だけを slow log として出すか
  RATE_LOG_ENABLED  = True;  // 倍速再生の切り分けログを出すか

function VideoMinerDebugLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := DEBUG_LOG_ENABLED or SameText(GetEnvironmentVariable(
    'VIDEOMINER_DEBUG_LOG'), '1');
{$ELSE}
  Result := False;
{$ENDIF}
end;

function VideoMinerSlowLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := SLOW_LOG_ENABLED or SameText(GetEnvironmentVariable(
    'VIDEOMINER_SLOW_LOG'), '1') or VideoMinerDebugLogEnabled;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function VideoMinerRateLogEnabled: Boolean;
begin
  Result := RATE_LOG_ENABLED or SameText(GetEnvironmentVariable(
    'VIDEOMINER_RATE_LOG'), '1') or VideoMinerDebugLogEnabled;
end;

// マイドキュメント配下の VideoMiner フォルダへ再生調査ログを集約する
function VideoMinerDebugLogFileName: string;
var
  DataPath: array[0..MAX_PATH - 1] of Char;
  LogDir: string;
begin
  if Succeeded(SHGetFolderPath(0, CSIDL_PERSONAL or CSIDL_FLAG_CREATE, 0,
    SHGFP_TYPE_CURRENT, DataPath)) then
    LogDir := IncludeTrailingPathDelimiter(DataPath) + 'VideoMiner'
  else
    LogDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'VideoMiner';

  try
    ForceDirectories(LogDir);
  except
    LogDir := GetEnvironmentVariable('LOCALAPPDATA');
    if LogDir = '' then
      LogDir := ExtractFilePath(ParamStr(0));
    LogDir := IncludeTrailingPathDelimiter(LogDir) + 'VideoMiner';
    ForceDirectories(LogDir);
  end;
  Result := IncludeTrailingPathDelimiter(LogDir) +
    'VideoMiner_playback_debug.log';
end;

// OutputDebugString とログファイルの両方へ 1 行出力する
procedure WriteVideoMinerLogLine(const Msg: string);
var
  F: TextFile;
  LogFileName: string;
  Line: string;
begin
  try
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
      ' [VideoMiner] ' + Msg;
    OutputDebugString(PChar(Line));

    LogFileName := VideoMinerDebugLogFileName;
    AssignFile(F, LogFileName);
    try
      if FileExists(LogFileName) then
        Append(F)
      else
        Rewrite(F);
      Writeln(F, Line);
    finally
      CloseFile(F);
    end;
  except
    // Logging must never prevent playback or startup.
  end;
end;

procedure ClearVideoMinerDebugLog(const Reason: string);
var
  LogFileName: string;
begin
  if not (VideoMinerDebugLogEnabled or VideoMinerSlowLogEnabled or
     VideoMinerRateLogEnabled) then
    Exit;

  LogFileName := VideoMinerDebugLogFileName;
  if FileExists(LogFileName) then
    DeleteFile(LogFileName);
  WriteVideoMinerLogLine('log_clear ' + Reason);
end;

procedure WriteVideoMinerDebugLog(const Msg: string);
begin
  if VideoMinerDebugLogEnabled then
    WriteVideoMinerLogLine(Msg);
end;

procedure WriteVideoMinerSlowLog(const Msg: string);
begin
  if VideoMinerSlowLogEnabled then
    WriteVideoMinerLogLine(Msg);
end;

procedure WriteVideoMinerRateLog(const Msg: string);
begin
  if VideoMinerRateLogEnabled then
    WriteVideoMinerLogLine(Msg);
end;

end.
