unit VideoMinerDebugLog;

interface

procedure ClearVideoMinerDebugLog(const Reason: string);
procedure WriteVideoMinerDebugLog(const Msg: string);
procedure WriteVideoMinerSlowLog(const Msg: string);
function VideoMinerDebugLogEnabled: Boolean;
function VideoMinerSlowLogEnabled: Boolean;
function VideoMinerDebugLogFileName: string;

implementation

uses
  Winapi.Windows, System.SysUtils;

const
  VIDEO_MINER_DEBUG_LOG_ENABLED = False;
  VIDEO_MINER_SLOW_LOG_ENABLED = True;

function VideoMinerDebugLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := VIDEO_MINER_DEBUG_LOG_ENABLED;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function VideoMinerSlowLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := VIDEO_MINER_SLOW_LOG_ENABLED;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function VideoMinerDebugLogFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    'VideoMiner_playback_debug.log';
end;

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
