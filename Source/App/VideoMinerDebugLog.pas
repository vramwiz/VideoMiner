unit VideoMinerDebugLog;

interface

procedure ClearVideoMinerDebugLog(const Reason: string);
procedure WriteVideoMinerDebugLog(const Msg: string);
function VideoMinerDebugLogEnabled: Boolean;
function VideoMinerDebugLogFileName: string;

implementation

uses
  Winapi.Windows, System.SysUtils;

const
  VIDEO_MINER_DEBUG_LOG_ENABLED = False;

function VideoMinerDebugLogEnabled: Boolean;
begin
{$IFDEF DEBUG}
  Result := VIDEO_MINER_DEBUG_LOG_ENABLED;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function VideoMinerDebugLogFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    'VideoMiner_playback_debug.log';
end;

procedure WriteVideoMinerDebugLine(const Msg: string);
{$IFDEF DEBUG}
var
  F: TextFile;
  LogFileName: string;
  Line: string;
begin
  if not VideoMinerDebugLogEnabled then
    Exit;

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
  F: TextFile;
  Line: string;
begin
  if not VideoMinerDebugLogEnabled then
    Exit;

  AssignFile(F, VideoMinerDebugLogFileName);
  Rewrite(F);
  try
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) +
      ' [VideoMiner] log_clear ' + Reason;
    Writeln(F, Line);
    OutputDebugString(PChar(Line));
  finally
    CloseFile(F);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure WriteVideoMinerDebugLog(const Msg: string);
begin
  WriteVideoMinerDebugLine(Msg);
end;

end.
