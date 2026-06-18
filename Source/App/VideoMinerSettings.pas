unit VideoMinerSettings;

// VideoMiner のユーザー設定を INI ファイルへ保存/読込する。
// UI 状態、再生設定、手動チャプター位置など、起動をまたいで保持する値だけを扱う。

interface

type
  // 手動チャプター位置を ms 単位で保持する配列
  TVideoMinerChapterPositions = TArray<Integer>;
  // 最近開いたフォルダを順位付きで保持する配列
  TVideoMinerFolderHistory = TArray<string>;
  // デコード方式の希望値。Debug では auto を software 扱いにして調査しやすくする。
  TVideoDecoderMode = (vdmAuto, vdmQsv, vdmSoftware);
  // 動画終端へ到達したときの再生動作
  TVideoMinerEndAction = (eaStop, eaLoop, eaNext);

  TVideoMinerAudioSettings = record
    Muted         : Boolean; // ミュート状態
    VolumePercent : Integer; // 音量パーセント
  end;

  TVideoMinerLastMedia = record
    Available : Boolean; // 前回メディア情報を復元に使えるか
    Folder    : string;  // 前回開いたフォルダ
    FileName  : string;  // 前回開いたファイル
  end;

  TVideoMinerWindowBounds = record
    Available : Boolean; // 保存済み座標を復元に使えるか
    Left      : Integer; // 通常表示時の左位置
    Top       : Integer; // 通常表示時の上位置
    Width     : Integer; // 通常表示時の幅
    Height    : Integer; // 通常表示時の高さ
  end;

// 現在の動画デコード方式を返す
function GetVideoDecoderMode: TVideoDecoderMode;
// 終端到達時の動作を読み込む
function LoadEndAction: TVideoMinerEndAction;
// 音量とミュート状態を読み込む
function LoadAudioSettings: TVideoMinerAudioSettings;
// 前回開いたフォルダとファイルを読み込む
function LoadLastMedia: TVideoMinerLastMedia;
// フォルダ閲覧履歴を読み込む
function LoadFolderHistory: TVideoMinerFolderHistory;
// 指定ファイルに対応する手動チャプター位置を読み込む
function LoadManualChapterPositions(const FileName: string): TVideoMinerChapterPositions;
// 指定ファイルに対応する再生再開位置を読み込む
function LoadManualChapterPlaybackPosition(const FileName: string; MaxMs: Integer;
  out PositionMs: Integer): Boolean;
// 通常表示時のメインフォーム位置とサイズを読み込む
function LoadMainFormBounds: TVideoMinerWindowBounds;
// サムネイル一覧のタイル幅を読み込む
function LoadThumbnailTileWidth(DefaultWidth, MinWidth, MaxWidth: Integer): Integer;
// 終端到達時の動作を保存する
procedure SaveEndAction(Value: TVideoMinerEndAction);
// 音量とミュート状態を保存する
procedure SaveAudioSettings(const Settings: TVideoMinerAudioSettings);
// 前回開いたフォルダとファイルを保存する
procedure SaveLastMedia(const Folder, FileName: string);
// 指定フォルダを閲覧履歴の先頭へ移動して保存する
procedure TouchFolderHistory(const Folder: string);
// 指定フォルダを閲覧履歴から削除する
procedure DeleteFolderHistory(const Folder: string);
// 指定ファイルに対応する手動チャプター位置を保存する
procedure SaveManualChapterPositions(const FileName: string;
  const Positions: TVideoMinerChapterPositions);
// 指定ファイルに対応する再生再開位置を保存する
procedure SaveManualChapterPlaybackPosition(const FileName: string;
  PositionMs, MaxMs: Integer);
// 指定ファイルに対応する再生再開位置だけを削除する
procedure ClearManualChapterPlaybackPosition(const FileName: string);
// 通常表示時のメインフォーム位置とサイズを保存する
procedure SaveMainFormBounds(const Bounds: TVideoMinerWindowBounds);
// サムネイル一覧のタイル幅を保存する
procedure SaveThumbnailTileWidth(Value, MinWidth, MaxWidth: Integer);
// デコード方式を INI 保存用の文字列へ変換する
function VideoDecoderModeToText(Mode: TVideoDecoderMode): string;

implementation

uses
  System.IniFiles, System.Math, System.SysUtils, Winapi.ShlObj, Winapi.Windows;

const
  SECTION_SETTINGS       = 'VideoMiner';         // アプリ全体設定の INI セクション
  KEY_DECODER_MODE       = 'VideoDecoderMode';   // デコード方式の INI キー
  SECTION_WINDOW         = 'MainForm';           // メインフォーム座標の INI セクション
  KEY_WINDOW_LEFT        = 'Left';               // ウィンドウ左位置の INI キー
  KEY_WINDOW_TOP         = 'Top';                // ウィンドウ上位置の INI キー
  KEY_WINDOW_WIDTH       = 'Width';              // ウィンドウ幅の INI キー
  KEY_WINDOW_HEIGHT      = 'Height';             // ウィンドウ高さの INI キー
  SECTION_LAST_MEDIA     = 'LastMedia';          // 前回メディア情報の INI セクション
  KEY_LAST_FOLDER        = 'Folder';             // 前回フォルダの INI キー
  KEY_LAST_FILE          = 'FileName';           // 前回ファイルの INI キー
  SECTION_FOLDER_HISTORY = 'FolderHistory';      // フォルダ閲覧履歴の INI セクション
  KEY_FOLDER_COUNT       = 'Count';              // フォルダ閲覧履歴件数の INI キー
  KEY_FOLDER_PREFIX      = 'Folder';             // フォルダ閲覧履歴キーの接頭辞
  FOLDER_HISTORY_MAX     = 12;                   // 保存するフォルダ閲覧履歴の最大件数
  SECTION_PLAYBACK       = 'Playback';           // 再生設定の INI セクション
  KEY_END_ACTION         = 'EndAction';          // 終端到達時動作の INI キー
  SECTION_AUDIO          = 'Audio';              // 音声設定の INI セクション
  KEY_AUDIO_MUTED        = 'Muted';              // ミュート状態の INI キー
  KEY_AUDIO_VOLUME       = 'VolumePercent';      // 音量パーセントの INI キー
  SECTION_THUMBNAIL      = 'ThumbnailBrowser';   // サムネイル一覧設定の INI セクション
  KEY_THUMBNAIL_WIDTH    = 'TileWidth';          // サムネイルタイル幅の INI キー
  SECTION_CHAPTER_PREFIX = 'ManualChapters:';    // ファイル別チャプターのセクション接頭辞
  KEY_CHAPTER_FILE       = 'FileName';           // チャプター対象ファイルの INI キー
  KEY_CHAPTER_COUNT      = 'Count';              // 手動チャプター数の INI キー
  KEY_CHAPTER_POS_PREFIX = 'Position';           // 手動チャプター位置キーの接頭辞
  KEY_CHAPTER_PLAYBACK   = 'PlaybackPositionMs'; // 手動チャプター再生位置の INI キー

var
  CurrentVideoDecoderMode : TVideoDecoderMode = vdmAuto; // 読み込み済みのデコード方式
  SettingsLoaded          : Boolean = False;             // 初期設定を読み込み済みか

// INI ファイルの保存先を返し、必要なら設定ディレクトリを作る
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

// INI 上の文字列をデコード方式へ変換する
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

// INI 上の文字列を終端到達時の動作へ変換する
function TextToEndAction(const Value: string): TVideoMinerEndAction;
begin
  if SameText(Value, 'loop') then
    Result := eaLoop
  else if SameText(Value, 'next') then
    Result := eaNext
  else
    Result := eaStop;
end;

// 終端到達時の動作を INI 保存用の文字列へ変換する
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

// ファイルごとの手動チャプター保存セクション名を作る
function ManualChapterSectionName(const FileName: string): string;
begin
  Result := SECTION_CHAPTER_PREFIX + ExpandFileName(FileName);
end;

// 初回参照時にアプリ全体設定だけをキャッシュする
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
      Ini.ReadString(SECTION_SETTINGS, KEY_DECODER_MODE, 'auto'));
  finally
    Ini.Free;
  end;
end;

function GetVideoDecoderMode: TVideoDecoderMode;
begin
  LoadSettings;
  Result := CurrentVideoDecoderMode;
{$IFDEF DEBUG}
  if Result = vdmAuto then
    Result := vdmSoftware;
{$ENDIF}
end;

function LoadEndAction: TVideoMinerEndAction;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(SettingsFileName);
  try
    Result := TextToEndAction(Ini.ReadString(SECTION_PLAYBACK,
      KEY_END_ACTION, 'stop'));
  finally
    Ini.Free;
  end;
end;

function LoadAudioSettings: TVideoMinerAudioSettings;
var
  Ini: TIniFile;
begin
  Result.Muted := False;
  Result.VolumePercent := 100;
  Ini := TIniFile.Create(SettingsFileName);
  try
    Result.VolumePercent := Max(0, Min(100,
      Ini.ReadInteger(SECTION_AUDIO, KEY_AUDIO_VOLUME, 100)));
    Result.Muted := Ini.ReadBool(SECTION_AUDIO, KEY_AUDIO_MUTED, False);
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
      Ini.ValueExists(SECTION_WINDOW, KEY_WINDOW_LEFT) and
      Ini.ValueExists(SECTION_WINDOW, KEY_WINDOW_TOP) and
      Ini.ValueExists(SECTION_WINDOW, KEY_WINDOW_WIDTH) and
      Ini.ValueExists(SECTION_WINDOW, KEY_WINDOW_HEIGHT);
    if not Result.Available then
      Exit;

    Result.Left := Ini.ReadInteger(SECTION_WINDOW, KEY_WINDOW_LEFT, 0);
    Result.Top := Ini.ReadInteger(SECTION_WINDOW, KEY_WINDOW_TOP, 0);
    Result.Width := Ini.ReadInteger(SECTION_WINDOW, KEY_WINDOW_WIDTH, 0);
    Result.Height := Ini.ReadInteger(SECTION_WINDOW, KEY_WINDOW_HEIGHT, 0);
    if (Result.Width < 320) or (Result.Height < 240) then
      Result.Available := False;
  finally
    Ini.Free;
  end;
end;

function LoadThumbnailTileWidth(DefaultWidth, MinWidth, MaxWidth: Integer): Integer;
var
  Ini: TIniFile;
begin
  Result := Max(MinWidth, Min(MaxWidth, DefaultWidth));
  Ini := TIniFile.Create(SettingsFileName);
  try
    Result := Max(MinWidth, Min(MaxWidth,
      Ini.ReadInteger(SECTION_THUMBNAIL, KEY_THUMBNAIL_WIDTH, Result)));
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
    Result.Folder := Ini.ReadString(SECTION_LAST_MEDIA, KEY_LAST_FOLDER, '');
    Result.FileName := Ini.ReadString(SECTION_LAST_MEDIA, KEY_LAST_FILE, '');
    Result.Available := (Result.Folder <> '') or (Result.FileName <> '');
  finally
    Ini.Free;
  end;
end;

function LoadFolderHistory: TVideoMinerFolderHistory;
var
  Count: Integer;
  Folder: string;
  I: Integer;
  Ini: TIniFile;
begin
  SetLength(Result, 0);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Count := Max(0, Min(FOLDER_HISTORY_MAX,
      Ini.ReadInteger(SECTION_FOLDER_HISTORY, KEY_FOLDER_COUNT, 0)));
    SetLength(Result, Count);
    Count := 0;
    for I := 0 to High(Result) do
    begin
      Folder := Ini.ReadString(SECTION_FOLDER_HISTORY,
        KEY_FOLDER_PREFIX + IntToStr(I), '');
      if Folder = '' then
        Continue;

      Result[Count] := Folder;
      Inc(Count);
    end;
    SetLength(Result, Count);
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
    Count := Ini.ReadInteger(Section, KEY_CHAPTER_COUNT, 0);
    if Count <= 0 then
      Exit;

    SetLength(Result, Count);
    Count := 0;
    for I := 0 to High(Result) do
    begin
      PositionMs := Ini.ReadInteger(Section,
        KEY_CHAPTER_POS_PREFIX + IntToStr(I), -1);
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

function LoadManualChapterPlaybackPosition(const FileName: string;
  MaxMs: Integer; out PositionMs: Integer): Boolean;
var
  Ini: TIniFile;
  Section: string;
begin
  Result := False;
  PositionMs := 0;
  if (FileName = '') or (MaxMs <= 0) then
    Exit;

  Section := ManualChapterSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    if not Ini.ValueExists(Section, KEY_CHAPTER_PLAYBACK) then
      Exit;

    PositionMs := Ini.ReadInteger(Section, KEY_CHAPTER_PLAYBACK, 0);
    PositionMs := Max(0, Min(MaxMs, PositionMs));
    Result := True;
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
    Ini.WriteString(SECTION_PLAYBACK, KEY_END_ACTION,
      EndActionToText(Value));
  finally
    Ini.Free;
  end;
end;

procedure SaveAudioSettings(const Settings: TVideoMinerAudioSettings);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteInteger(SECTION_AUDIO, KEY_AUDIO_VOLUME,
      Max(0, Min(100, Settings.VolumePercent)));
    Ini.WriteBool(SECTION_AUDIO, KEY_AUDIO_MUTED, Settings.Muted);
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
    Ini.WriteString(SECTION_LAST_MEDIA, KEY_LAST_FOLDER, Folder);
    Ini.WriteString(SECTION_LAST_MEDIA, KEY_LAST_FILE, FileName);
  finally
    Ini.Free;
  end;
end;

procedure TouchFolderHistory(const Folder: string);
var
  Count: Integer;
  Existing: TVideoMinerFolderHistory;
  I: Integer;
  Ini: TIniFile;
  NormalizedFolder: string;
begin
  if Folder = '' then
    Exit;

  NormalizedFolder := IncludeTrailingPathDelimiter(ExpandFileName(Folder));
  Existing := LoadFolderHistory;
  SetLength(Existing, Length(Existing) + 1);
  for I := High(Existing) downto 1 do
    Existing[I] := Existing[I - 1];
  Existing[0] := NormalizedFolder;

  Count := 1;
  for I := 1 to High(Existing) do
  begin
    if SameText(Existing[I], NormalizedFolder) then
      Continue;

    Existing[Count] := Existing[I];
    Inc(Count);
    if Count >= FOLDER_HISTORY_MAX then
      Break;
  end;
  SetLength(Existing, Count);

  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.EraseSection(SECTION_FOLDER_HISTORY);
    Ini.WriteInteger(SECTION_FOLDER_HISTORY, KEY_FOLDER_COUNT, Length(Existing));
    for I := 0 to High(Existing) do
      Ini.WriteString(SECTION_FOLDER_HISTORY,
        KEY_FOLDER_PREFIX + IntToStr(I), Existing[I]);
  finally
    Ini.Free;
  end;
end;

procedure DeleteFolderHistory(const Folder: string);
var
  Count: Integer;
  Existing: TVideoMinerFolderHistory;
  I: Integer;
  Ini: TIniFile;
  NormalizedFolder: string;
begin
  if Folder = '' then
    Exit;

  NormalizedFolder := IncludeTrailingPathDelimiter(ExpandFileName(Folder));
  Existing := LoadFolderHistory;

  Count := 0;
  for I := 0 to High(Existing) do
  begin
    if SameText(Existing[I], NormalizedFolder) then
      Continue;

    Existing[Count] := Existing[I];
    Inc(Count);
  end;
  SetLength(Existing, Count);

  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.EraseSection(SECTION_FOLDER_HISTORY);
    Ini.WriteInteger(SECTION_FOLDER_HISTORY, KEY_FOLDER_COUNT, Length(Existing));
    for I := 0 to High(Existing) do
      Ini.WriteString(SECTION_FOLDER_HISTORY,
        KEY_FOLDER_PREFIX + IntToStr(I), Existing[I]);
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
    Ini.WriteString(Section, KEY_CHAPTER_FILE, ExpandFileName(FileName));
    Ini.WriteInteger(Section, KEY_CHAPTER_COUNT, Length(Positions));
    for I := 0 to High(Positions) do
      Ini.WriteInteger(Section, KEY_CHAPTER_POS_PREFIX + IntToStr(I),
        Positions[I]);
  finally
    Ini.Free;
  end;
end;

procedure SaveManualChapterPlaybackPosition(const FileName: string;
  PositionMs, MaxMs: Integer);
var
  Ini: TIniFile;
  Section: string;
begin
  if (FileName = '') or (MaxMs <= 0) then
    Exit;

  Section := ManualChapterSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteString(Section, KEY_CHAPTER_FILE, ExpandFileName(FileName));
    Ini.WriteInteger(Section, KEY_CHAPTER_PLAYBACK,
      Max(0, Min(MaxMs, PositionMs)));
  finally
    Ini.Free;
  end;
end;

procedure ClearManualChapterPlaybackPosition(const FileName: string);
var
  Ini: TIniFile;
  Section: string;
begin
  if FileName = '' then
    Exit;

  Section := ManualChapterSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.DeleteKey(Section, KEY_CHAPTER_PLAYBACK);
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
    Ini.WriteInteger(SECTION_WINDOW, KEY_WINDOW_LEFT, Bounds.Left);
    Ini.WriteInteger(SECTION_WINDOW, KEY_WINDOW_TOP, Bounds.Top);
    Ini.WriteInteger(SECTION_WINDOW, KEY_WINDOW_WIDTH, Bounds.Width);
    Ini.WriteInteger(SECTION_WINDOW, KEY_WINDOW_HEIGHT, Bounds.Height);
  finally
    Ini.Free;
  end;
end;

procedure SaveThumbnailTileWidth(Value, MinWidth, MaxWidth: Integer);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteInteger(SECTION_THUMBNAIL, KEY_THUMBNAIL_WIDTH,
      Max(MinWidth, Min(MaxWidth, Value)));
  finally
    Ini.Free;
  end;
end;

initialization
  LoadSettings;

end.
