unit VideoMinerDebugLog;

// Debug ビルド専用の調査ログ出力を担当する。
// 通常ログと slow log を同じファイルへ出し、Release ビルドでは何もしない。

interface

// ログファイルを削除し、削除理由を先頭行として記録する
procedure ClearVideoMinerDebugLog(const Reason: string);
// 詳細調査用ログが有効な場合だけ 1 行出力する
procedure WriteVideoMinerDebugLog(const Msg: string);
// 遅い処理の調査ログが有効な場合だけ 1 行出力する
procedure WriteVideoMinerSlowLog(const Msg: string);
// 詳細調査用ログが有効か返す
function VideoMinerDebugLogEnabled: Boolean;
// slow log が有効か返す
function VideoMinerSlowLogEnabled: Boolean;
// VideoMiner の調査ログファイル名を返す
function VideoMinerDebugLogFileName: string;

implementation

uses
  Winapi.Windows, System.SysUtils;

const
  DEBUG_LOG_ENABLED = False; // 毎 tick 系の詳細ログを出すか
  SLOW_LOG_ENABLED  = True;  // 遅い処理だけを slow log として出すか

function VideoMinerDebugLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := DEBUG_LOG_ENABLED;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function VideoMinerSlowLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := SLOW_LOG_ENABLED;
{$ELSE}
  Result := False;
{$ENDIF}
end;

// %TEMP% 配下の固定ファイルへ再生調査ログを集約する
function VideoMinerDebugLogFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    'VideoMiner_playback_debug.log';
end;

// Debug ビルドで OutputDebugString とログファイルの両方へ 1 行出力する
procedure WriteVideoMinerLogLine(const Msg: string);
{$IFDEF DEBUG}
var
  F: TextFile;
  LogFileName: string;
  Line: string;
begin
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
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure ClearVideoMinerDebugLog(const Reason: string);
{$IFDEF DEBUG}
var
  LogFileName: string;
begin
  if not (VideoMinerDebugLogEnabled or VideoMinerSlowLogEnabled) then
    Exit;

  LogFileName := VideoMinerDebugLogFileName;
  if FileExists(LogFileName) then
    DeleteFile(LogFileName);
  WriteVideoMinerLogLine('log_clear ' + Reason);
end;
{$ELSE}
begin
end;
{$ENDIF}

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

end.
