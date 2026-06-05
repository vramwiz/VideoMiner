unit VideoMinerSettings;

interface

type
  TVideoDecoderMode = (vdmAuto, vdmQsv, vdmSoftware);

function GetVideoDecoderMode: TVideoDecoderMode;
function VideoDecoderModeToText(Mode: TVideoDecoderMode): string;

implementation

uses
  System.IniFiles, System.SysUtils, Winapi.Windows;

const
  SETTINGS_SECTION = 'VideoMiner';
  SETTINGS_DECODER_MODE = 'VideoDecoderMode';

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
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'VideoMiner.ini';
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

initialization
  LoadSettings;

end.