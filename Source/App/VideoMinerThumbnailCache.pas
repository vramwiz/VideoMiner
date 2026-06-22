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

// PNG 形式のサムネイルディスクキャッシュを使う。
{$DEFINE THUMBNAIL_DISK_CACHE_ENABLED}

{$IFDEF THUMBNAIL_DISK_CACHE_ENABLED}
uses
  System.IOUtils, System.SysUtils, Vcl.Imaging.pngimage, Winapi.ShlObj,
  Winapi.Windows, VideoMinerSettings;
{$ENDIF}

{$IFDEF THUMBNAIL_DISK_CACHE_ENABLED}
const
  THUMBNAIL_CACHE_VERSION = 'r1';
  THUMBNAIL_CACHE_DIR = 'ThumbnailCache';

function CacheRootDir: string;
var
  DataPath: array[0..MAX_PATH - 1] of Char;
begin
  if Succeeded(SHGetFolderPath(0, CSIDL_PERSONAL or CSIDL_FLAG_CREATE, 0,
    SHGFP_TYPE_CURRENT, DataPath)) then
    Result := IncludeTrailingPathDelimiter(DataPath) + 'VideoMiner'
  else
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
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
      HashText64(THUMBNAIL_CACHE_VERSION + '|' +
        VideoRotationOverrideToText(GetVideoRotationOverride) + '|' +
        LowerCase(ExpandedFileName)) +
      '_' + StampText + '_' + IntToStr(Size) + '.png';
  except
    Result := '';
  end;
end;

function LoadPngToBitmap(const CacheName: string;
  Bitmap: Vcl.Graphics.TBitmap): Boolean;
var
  Png: TPngImage;
begin
  Png := TPngImage.Create;
  try
    Png.LoadFromFile(CacheName);
    Bitmap.Assign(Png);
    Result := (Bitmap.Width > 0) and (Bitmap.Height > 0);
  finally
    Png.Free;
  end;
end;

procedure SaveBitmapToPng(const CacheName: string;
  Bitmap: Vcl.Graphics.TBitmap);
var
  Png: TPngImage;
begin
  Png := TPngImage.Create;
  try
    Png.Assign(Bitmap);
    Png.SaveToFile(CacheName);
  finally
    Png.Free;
  end;
end;
{$ENDIF}

function LoadVideoMinerThumbnailCache(const FileName: string;
  Bitmap: Vcl.Graphics.TBitmap): Boolean;
{$IFDEF THUMBNAIL_DISK_CACHE_ENABLED}
var
  CacheName: string;
{$ENDIF}
begin
  Result := False;
{$IFDEF THUMBNAIL_DISK_CACHE_ENABLED}
  if Bitmap = nil then
    Exit;

  CacheName := CacheFileName(FileName);
  if (CacheName = '') or (not FileExists(CacheName)) then
    Exit;

  try
    Result := LoadPngToBitmap(CacheName, Bitmap);
  except
    Result := False;
  end;
{$ENDIF}
end;

procedure SaveVideoMinerThumbnailCache(const FileName: string;
  Bitmap: Vcl.Graphics.TBitmap);
{$IFDEF THUMBNAIL_DISK_CACHE_ENABLED}
var
  CacheName: string;
{$ENDIF}
begin
{$IFDEF THUMBNAIL_DISK_CACHE_ENABLED}
  if (Bitmap = nil) or (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;

  CacheName := CacheFileName(FileName);
  if CacheName = '' then
    Exit;

  try
    SaveBitmapToPng(CacheName, Bitmap);
  except
    // キャッシュ保存失敗は一覧表示の本体機能を止めない。
  end;
{$ENDIF}
end;

end.
