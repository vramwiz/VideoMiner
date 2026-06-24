unit VideoMinerSettings;

// VideoMiner のユーザー設定を INI ファイルへ保存/読込する。
// UI 状態、再生設定、手動チャプター位置など、起動をまたいで保持する値だけを扱う。

interface

type
  // 手動チャプター位置を ms 単位で保持する配列
  TVideoMinerChapterPositions = TArray<Integer>;
  // 最近開いたフォルダを順位付きで保持する配列
  TVideoMinerFolderHistory = TArray<string>;
  // デコード方式の希望値。Debug/Release とも同じ設定値を使う。
  TVideoDecoderMode = (vdmAuto, vdmQsv, vdmSoftware);
  // 動画終端へ到達したときの再生動作
  TVideoMinerEndAction = (eaStop, eaLoop, eaNext);
  // 表示回転メタデータのテスト用上書き
  TVideoRotationOverride = (vroAuto, vroIgnore, vroForce90, vroForce180,
    vroForce270);

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
// 表示回転メタデータのテスト用上書きを返す
function GetVideoRotationOverride: TVideoRotationOverride;
// 入力動画の回転角度へテスト用上書きを反映した表示回転角度を返す
function EffectiveVideoRotationDegrees(SourceDegrees: Integer): Integer;
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
// 指定ファイルに対応する動画時間を読み込む
function LoadCachedVideoDurationMs(const FileName: string;
  out DurationMs: Integer): Boolean;
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
// 指定ファイルに対応する動画時間を保存する
procedure SaveCachedVideoDurationMs(const FileName: string; DurationMs: Integer);
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
// 表示回転上書きを INI 保存用の文字列へ変換する
function VideoRotationOverrideToText(Value: TVideoRotationOverride): string;

implementation

uses
  System.IniFiles, System.IOUtils, System.Math, System.SysUtils, Winapi.ShlObj,
  Winapi.Windows, VideoMinerDebugLog;

const
  SECTION_SETTINGS       = 'VideoMiner';         // アプリ全体設定の INI セクション
  KEY_DECODER_MODE       = 'VideoDecoderMode';   // デコード方式の INI キー
  KEY_ROTATION_OVERRIDE  = 'VideoRotationOverride'; // 表示回転メタデータ上書きの INI キー
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
  FOLDER_HISTORY_MAX     = 16;                   // 保存するフォルダ閲覧履歴の最大件数
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
  SECTION_VIDEO_META_PREFIX = 'VideoMeta:';      // ファイル別動画メタ情報のセクション接頭辞
  KEY_VIDEO_META_FILE       = 'FileName';        // 動画メタ情報対象ファイルの INI キー
  KEY_VIDEO_META_SIZE       = 'Size';            // 動画メタ情報対象ファイルサイズの INI キー
  KEY_VIDEO_META_TIME_UTC   = 'LastWriteUtc';    // 動画メタ情報対象更新日時の INI キー
  KEY_VIDEO_META_DURATION   = 'DurationMs';      // 動画時間 ms の INI キー

var
  CurrentVideoDecoderMode : TVideoDecoderMode = vdmAuto; // 読み込み済みのデコード方式
  CurrentRotationOverride : TVideoRotationOverride = vroAuto; // 読み込み済みの表示回転上書き
  SettingsLoaded          : Boolean = False;             // 初期設定を読み込み済みか

// INI ファイルの保存先を返し、必要なら設定ディレクトリを作る
function SettingsFileName: string;
var
  DataPath: array[0..MAX_PATH - 1] of Char;
  SettingsDir: string;
begin
  if Succeeded(SHGetFolderPath(0, CSIDL_PERSONAL or CSIDL_FLAG_CREATE, 0,
    SHGFP_TYPE_CURRENT, DataPath)) then
    SettingsDir := IncludeTrailingPathDelimiter(DataPath) + 'VideoMiner'
  else
    SettingsDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'VideoMiner';

  try
    ForceDirectories(SettingsDir);
  except
    SettingsDir := GetEnvironmentVariable('LOCALAPPDATA');
    if SettingsDir = '' then
      SettingsDir := ExtractFilePath(ParamStr(0));
    SettingsDir := IncludeTrailingPathDelimiter(SettingsDir) + 'VideoMiner';
    ForceDirectories(SettingsDir);
  end;
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

// INI 上の文字列を表示回転上書きへ変換する
function TextToVideoRotationOverride(const Value: string): TVideoRotationOverride;
begin
  if SameText(Value, 'ignore') or SameText(Value, 'none') or
    SameText(Value, '0') then
    Result := vroIgnore
  else if SameText(Value, 'force90') or SameText(Value, '90') then
    Result := vroForce90
  else if SameText(Value, 'force180') or SameText(Value, '180') then
    Result := vroForce180
  else if SameText(Value, 'force270') or SameText(Value, '270') then
    Result := vroForce270
  else
    Result := vroAuto;
end;

function VideoRotationOverrideToText(Value: TVideoRotationOverride): string;
begin
  case Value of
    vroIgnore:
      Result := 'ignore';
    vroForce90:
      Result := 'force90';
    vroForce180:
      Result := 'force180';
    vroForce270:
      Result := 'force270';
  else
    Result := 'auto';
  end;
end;

// 表示回転角度を 0 / 90 / 180 / 270 の範囲へ丸める
function NormalizeRotationDegrees(Value: Integer): Integer;
begin
  Value := Value mod 360;
  if Value < 0 then
    Inc(Value, 360);
  case Value of
    90, 180, 270:
      Result := Value;
  else
    Result := 0;
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

// ファイルごとの動画メタ情報保存セクション名を作る
function VideoMetaSectionName(const FileName: string): string;
begin
  Result := SECTION_VIDEO_META_PREFIX + ExpandFileName(FileName);
end;

// 初回参照時にアプリ全体設定だけをキャッシュする
procedure LoadSettings;
var
  Ini: TMemIniFile;
begin
  if SettingsLoaded then
    Exit;

  try
    Ini := TMemIniFile.Create(SettingsFileName, TEncoding.UTF8);
    try
      CurrentVideoDecoderMode := TextToVideoDecoderMode(
        Ini.ReadString(SECTION_SETTINGS, KEY_DECODER_MODE, 'auto'));
      CurrentRotationOverride := TextToVideoRotationOverride(
        Ini.ReadString(SECTION_SETTINGS, KEY_ROTATION_OVERRIDE, 'auto'));
      WriteVideoMinerSlowLog(Format(
        'settings_loaded decoder_mode=%s rotation_override=%s',
        [VideoDecoderModeToText(CurrentVideoDecoderMode),
         VideoRotationOverrideToText(CurrentRotationOverride)]));
    finally
      Ini.Free;
    end;
  except
    CurrentVideoDecoderMode := vdmAuto;
    CurrentRotationOverride := vroAuto;
  end;
  SettingsLoaded := True;
end;

function GetVideoDecoderMode: TVideoDecoderMode;
begin
  LoadSettings;
  Result := CurrentVideoDecoderMode;
end;

function GetVideoRotationOverride: TVideoRotationOverride;
begin
  LoadSettings;
  Result := CurrentRotationOverride;
end;

function EffectiveVideoRotationDegrees(SourceDegrees: Integer): Integer;
begin
  case GetVideoRotationOverride of
    vroIgnore:
      Result := 0;
    vroForce90:
      Result := 90;
    vroForce180:
      Result := 180;
    vroForce270:
      Result := 270;
  else
    Result := NormalizeRotationDegrees(SourceDegrees);
  end;
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

function LoadCachedVideoDurationMs(const FileName: string;
  out DurationMs: Integer): Boolean;
var
  CachedSize: Int64;
  CachedTimeUtc: Double;
  CurrentSize: Int64;
  CurrentTimeUtc: TDateTime;
  Ini: TIniFile;
  Section: string;
begin
  Result := False;
  DurationMs := 0;
  if (FileName = '') or (not TFile.Exists(FileName)) then
    Exit;

  Section := VideoMetaSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    if not Ini.ValueExists(Section, KEY_VIDEO_META_DURATION) then
      Exit;

    CurrentSize := TFile.GetSize(FileName);
    CurrentTimeUtc := TFile.GetLastWriteTimeUtc(FileName);
    CachedSize := StrToInt64Def(Ini.ReadString(Section, KEY_VIDEO_META_SIZE,
      '-1'), -1);
    CachedTimeUtc := Ini.ReadFloat(Section, KEY_VIDEO_META_TIME_UTC, -1);
    if (CachedSize <> CurrentSize) or
       (Abs(CachedTimeUtc - CurrentTimeUtc) > 1 / MSecsPerDay) then
      Exit;

    DurationMs := Ini.ReadInteger(Section, KEY_VIDEO_META_DURATION, 0);
    Result := DurationMs > 0;
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

procedure SaveCachedVideoDurationMs(const FileName: string; DurationMs: Integer);
var
  Ini: TIniFile;
  Section: string;
begin
  if (FileName = '') or (DurationMs <= 0) or (not TFile.Exists(FileName)) then
    Exit;

  Section := VideoMetaSectionName(FileName);
  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteString(Section, KEY_VIDEO_META_FILE, ExpandFileName(FileName));
    Ini.WriteString(Section, KEY_VIDEO_META_SIZE,
      IntToStr(TFile.GetSize(FileName)));
    Ini.WriteFloat(Section, KEY_VIDEO_META_TIME_UTC,
      TFile.GetLastWriteTimeUtc(FileName));
    Ini.WriteInteger(Section, KEY_VIDEO_META_DURATION, DurationMs);
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

end.
