unit VideoMinerSettings;

interface

type
  TVideoMinerChapterPositions = TArray<Integer>;
  TVideoDecoderMode = (vdmAuto, vdmQsv, vdmSoftware);
  TVideoMinerEndAction = (eaStop, eaLoop, eaNext);

  TVideoMinerLastMedia = record
    Available: Boolean;
    Folder: string;
    FileName: string;
  end;

  TVideoMinerWindowBounds = record
    Available: Boolean;
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Height: Integer;
  end;

function GetVideoDecoderMode: TVideoDecoderMode;
function LoadEndAction: TVideoMinerEndAction;
function LoadLastMedia: TVideoMinerLastMedia;
function LoadManualChapterPositions(const FileName: string): TVideoMinerChapterPositions;
function LoadMainFormBounds: TVideoMinerWindowBounds;
procedure SaveEndAction(Value: TVideoMinerEndAction);
procedure SaveLastMedia(const Folder, FileName: string);
procedure SaveManualChapterPositions(const FileName: string;
  const Positions: TVideoMinerChapterPositions);
procedure SaveMainFormBounds(const Bounds: TVideoMinerWindowBounds);
function VideoDecoderModeToText(Mode: TVideoDecoderMode): string;

implementation

uses
  System.IniFiles, System.SysUtils, Winapi.ShlObj, Winapi.Windows;

const
  SETTINGS_SECTION = 'VideoMiner';
  SETTINGS_DECODER_MODE = 'VideoDecoderMode';
  WINDOW_SECTION = 'MainForm';
  WINDOW_LEFT = 'Left';
  WINDOW_TOP = 'Top';
  WINDOW_WIDTH = 'Width';
  WINDOW_HEIGHT = 'Height';
  LAST_MEDIA_SECTION = 'LastMedia';
  LAST_MEDIA_FOLDER = 'Folder';
  LAST_MEDIA_FILE = 'FileName';
  PLAYBACK_SECTION = 'Playback';
  PLAYBACK_END_ACTION = 'EndAction';
  MANUAL_CHAPTER_SECTION_PREFIX = 'ManualChapters:';
  MANUAL_CHAPTER_FILE = 'FileName';
  MANUAL_CHAPTER_COUNT = 'Count';
  MANUAL_CHAPTER_POSITION_PREFIX = 'Position';

var
  CurrentVideoDecoderMode: TVideoDecoderMode = vdmAuto;
  SettingsLoaded: Boolean = False;

function SettingsFileName: string;
var
  AppDataPath: array[0..MAX_PATH - 1] of Char;
  SettingsDir: string;
begin
  if Succeeded(SHGetFolderPath(0, CSIDL_APPDATA or CSIDL_FLAG_CREATE, 0,
    SHGFP_TYPE_CURRENT, AppDataPath)) then
    SettingsDir := IncludeTrailingPathDelimiter(AppDataPath) + 'VideoMiner'
  else
    SettingsDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'VideoMiner';

  ForceDirectories(SettingsDir);
  Result := IncludeTrailingPathDelimiter(SettingsDir) + 'VideoMiner.ini';
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

function TextToEndAction(const Value: string): TVideoMinerEndAction;
begin
  if SameText(Value, 'loop') then
    Result := eaLoop
  else if SameText(Value, 'next') then
    Result := eaNext
  else
    Result := eaStop;
end;

function EndActionToText(Value: TVideoMinerEndAction): string;
begin
  case Value of
    eaLoop:
      Result := 'loop';
    eaNext:
      Result := 'next';
  else
    Result := 'stop';
  end;
end;

function ManualChapterSectionName(const FileName: string): string;
begin
  Result := MANUAL_CHAPTER_SECTION_PREFIX + ExpandFileName(FileName);
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

function GetVideoDecoderMode: TVideoDecoderMode;
begin
  LoadSettings;
  Result := CurrentVideoDecoderMode;
end;

function LoadEndAction: TVideoMinerEndAction;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(SettingsFileName);
  try
    Result := TextToEndAction(Ini.ReadString(PLAYBACK_SECTION,
      PLAYBACK_END_ACTION, 'stop'));
  finally
    Ini.Free;
  end;
end;

function LoadMainFormBounds: TVideoMinerWindowBounds;
var
  Ini: TIniFile;
begin
  FillChar(Result, SizeOf(Result), 0);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Result.Available :=
      Ini.ValueExists(WINDOW_SECTION, WINDOW_LEFT) and
      Ini.ValueExists(WINDOW_SECTION, WINDOW_TOP) and
      Ini.ValueExists(WINDOW_SECTION, WINDOW_WIDTH) and
      Ini.ValueExists(WINDOW_SECTION, WINDOW_HEIGHT);
    if not Result.Available then
      Exit;

    Result.Left := Ini.ReadInteger(WINDOW_SECTION, WINDOW_LEFT, 0);
    Result.Top := Ini.ReadInteger(WINDOW_SECTION, WINDOW_TOP, 0);
    Result.Width := Ini.ReadInteger(WINDOW_SECTION, WINDOW_WIDTH, 0);
    Result.Height := Ini.ReadInteger(WINDOW_SECTION, WINDOW_HEIGHT, 0);
    if (Result.Width < 320) or (Result.Height < 240) then
      Result.Available := False;
  finally
    Ini.Free;
  end;
end;

function LoadLastMedia: TVideoMinerLastMedia;
var
  Ini: TIniFile;
begin
  Result.Available := False;
  Result.Folder := '';
  Result.FileName := '';
  Ini := TIniFile.Create(SettingsFileName);
  try
    Result.Folder := Ini.ReadString(LAST_MEDIA_SECTION, LAST_MEDIA_FOLDER, '');
    Result.FileName := Ini.ReadString(LAST_MEDIA_SECTION, LAST_MEDIA_FILE, '');
    Result.Available := (Result.Folder <> '') or (Result.FileName <> '');
  finally
    Ini.Free;
  end;
end;

function LoadManualChapterPositions(
  const FileName: string): TVideoMinerChapterPositions;
var
  Count: Integer;
  I: Integer;
  Ini: TIniFile;
  PositionMs: Integer;
  Section: string;
begin
  SetLength(Result, 0);
  if FileName = '' then
    Exit;

  Section := ManualChapterSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Count := Ini.ReadInteger(Section, MANUAL_CHAPTER_COUNT, 0);
    if Count <= 0 then
      Exit;

    SetLength(Result, Count);
    Count := 0;
    for I := 0 to High(Result) do
    begin
      PositionMs := Ini.ReadInteger(Section,
        MANUAL_CHAPTER_POSITION_PREFIX + IntToStr(I), -1);
      if PositionMs < 0 then
        Continue;

      Result[Count] := PositionMs;
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Ini.Free;
  end;
end;

procedure SaveEndAction(Value: TVideoMinerEndAction);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteString(PLAYBACK_SECTION, PLAYBACK_END_ACTION,
      EndActionToText(Value));
  finally
    Ini.Free;
  end;
end;

procedure SaveLastMedia(const Folder, FileName: string);
var
  Ini: TIniFile;
begin
  if (Folder = '') and (FileName = '') then
    Exit;

  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteString(LAST_MEDIA_SECTION, LAST_MEDIA_FOLDER, Folder);
    Ini.WriteString(LAST_MEDIA_SECTION, LAST_MEDIA_FILE, FileName);
  finally
    Ini.Free;
  end;
end;

procedure SaveManualChapterPositions(const FileName: string;
  const Positions: TVideoMinerChapterPositions);
var
  I: Integer;
  Ini: TIniFile;
  Section: string;
begin
  if FileName = '' then
    Exit;

  Section := ManualChapterSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.EraseSection(Section);
    Ini.WriteString(Section, MANUAL_CHAPTER_FILE, ExpandFileName(FileName));
    Ini.WriteInteger(Section, MANUAL_CHAPTER_COUNT, Length(Positions));
    for I := 0 to High(Positions) do
      Ini.WriteInteger(Section, MANUAL_CHAPTER_POSITION_PREFIX + IntToStr(I),
        Positions[I]);
  finally
    Ini.Free;
  end;
end;

procedure SaveMainFormBounds(const Bounds: TVideoMinerWindowBounds);
var
  Ini: TIniFile;
begin
  if (not Bounds.Available) or (Bounds.Width < 320) or (Bounds.Height < 240) then
    Exit;

  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteInteger(WINDOW_SECTION, WINDOW_LEFT, Bounds.Left);
    Ini.WriteInteger(WINDOW_SECTION, WINDOW_TOP, Bounds.Top);
    Ini.WriteInteger(WINDOW_SECTION, WINDOW_WIDTH, Bounds.Width);
    Ini.WriteInteger(WINDOW_SECTION, WINDOW_HEIGHT, Bounds.Height);
  finally
    Ini.Free;
  end;
end;

initialization
  LoadSettings;

end.
