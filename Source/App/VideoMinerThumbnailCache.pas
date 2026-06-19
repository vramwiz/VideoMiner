unit VideoMinerThumbnailCache;

// サムネイル一覧で使う縮小済み画像を、起動をまたいで再利用するための簡易ディスクキャッシュ。
// 元ファイルのパス、更新日時、サイズをファイル名に含め、内容が変わった場合は別キャッシュとして扱う。

interface

uses
  Vcl.Graphics;

// キャッシュに対応するサムネイル画像を読み込む。
function LoadVideoMinerThumbnailCache(const FileName: string;
  Bitmap: Vcl.Graphics.TBitmap): Boolean;

// 生成済みサムネイル画像をキャッシュへ保存する。
procedure SaveVideoMinerThumbnailCache(const FileName: string;
  Bitmap: Vcl.Graphics.TBitmap);

implementation

uses
  System.IOUtils, System.SysUtils, Winapi.ShlObj, Winapi.Windows;

const
  THUMBNAIL_CACHE_DIR = 'ThumbnailCache';

function CacheRootDir: string;
var
  AppDataPath: array[0..MAX_PATH - 1] of Char;
begin
  if Succeeded(SHGetFolderPath(0, CSIDL_APPDATA or CSIDL_FLAG_CREATE, 0,
    SHGFP_TYPE_CURRENT, AppDataPath)) then
    Result := IncludeTrailingPathDelimiter(AppDataPath) + 'VideoMiner'
  else
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
      'VideoMiner';

  Result := IncludeTrailingPathDelimiter(Result) + THUMBNAIL_CACHE_DIR;
  ForceDirectories(Result);
end;

function HashText64(const Value: string): string;
var
  C: Char;
  Hash: UInt64;
begin
  Hash := UInt64($CBF29CE484222325);
  for C in Value do
  begin
    Hash := Hash xor UInt64(Ord(C));
    Hash := Hash * UInt64($100000001B3);
  end;
  Result := IntToHex(Hash, 16);
end;

function CacheFileName(const FileName: string): string;
var
  ExpandedFileName: string;
  LastWriteTime: TDateTime;
  Size: Int64;
  StampText: string;
begin
  Result := '';
  if (FileName = '') or (not TFile.Exists(FileName)) then
    Exit;

  try
    ExpandedFileName := ExpandFileName(FileName);
    LastWriteTime := TFile.GetLastWriteTimeUtc(ExpandedFileName);
    Size := TFile.GetSize(ExpandedFileName);
    StampText := FormatDateTime('yyyymmddhhnnsszzz', LastWriteTime);
    Result := IncludeTrailingPathDelimiter(CacheRootDir) +
      HashText64(LowerCase(ExpandedFileName)) + '_' + StampText + '_' +
      IntToStr(Size) + '.bmp';
  except
    Result := '';
  end;
end;

function LoadVideoMinerThumbnailCache(const FileName: string;
  Bitmap: Vcl.Graphics.TBitmap): Boolean;
var
  CacheName: string;
begin
  Result := False;
  if Bitmap = nil then
    Exit;

  CacheName := CacheFileName(FileName);
  if (CacheName = '') or (not FileExists(CacheName)) then
    Exit;

  try
    Bitmap.LoadFromFile(CacheName);
    Result := (Bitmap.Width > 0) and (Bitmap.Height > 0);
  except
    Result := False;
  end;
end;

procedure SaveVideoMinerThumbnailCache(const FileName: string;
  Bitmap: Vcl.Graphics.TBitmap);
var
  CacheName: string;
begin
  if (Bitmap = nil) or (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;

  CacheName := CacheFileName(FileName);
  if CacheName = '' then
    Exit;

  try
    Bitmap.SaveToFile(CacheName);
  except
    // キャッシュ保存失敗は一覧表示の本体機能を止めない。
  end;
end;

end.
