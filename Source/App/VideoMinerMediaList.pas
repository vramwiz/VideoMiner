unit VideoMinerMediaList;

// 開いた動画と同じフォルダを作業単位として扱うメディア一覧を管理する。
// ファイル収集、作成日時順の並び替え、前後ファイルへの移動可否だけを担当する。

interface

uses
  System.Classes, System.IOUtils, System.SysUtils;

type
  TVideoMinerMediaList = class
  private
    FFiles        : TArray<string>; // 現在のフォルダ内で移動対象になる動画ファイル一覧
    FCurrentIndex : Integer;        // 一覧内で現在開いているファイル位置
    class function IsMediaFile(const FileName: string): Boolean; static;
    function GetCount: Integer;
    function GetCurrentFile: string;
  public
    constructor Create;
    // 一覧と現在位置を未構築状態へ戻す
    procedure Clear;
    // 指定ファイルのフォルダから動画一覧を作り、指定ファイルを現在位置にする
    procedure BuildForFile(const FileName: string);
    // 一覧外なら空文字を返し、一覧内なら指定位置のファイル名を返す
    function FileAt(Index: Integer): string;
    // 現在位置から Delta 分だけ移動できるか返す
    function CanNavigate(Delta: Integer): Boolean;
    // 現在位置から Delta 分だけ移動した先のファイル名を返す
    function NavigateFile(Delta: Integer): string;
    property Count: Integer read GetCount;
    property CurrentIndex: Integer read FCurrentIndex;
    property CurrentFile: string read GetCurrentFile;
  end;

implementation

type
  TMediaFileSortInfo = class
  public
    SortTime: TDateTime; // 作成日時順ソートに使う時刻
  end;

// 作成日時が古い順に並べ、同時刻ならファイル名順で安定させる
function CompareMediaFilesByTime(List: TStringList; Index1, Index2: Integer): Integer;
var
  Info1: TMediaFileSortInfo;
  Info2: TMediaFileSortInfo;
begin
  Info1 := TMediaFileSortInfo(List.Objects[Index1]);
  Info2 := TMediaFileSortInfo(List.Objects[Index2]);

  if Info1.SortTime < Info2.SortTime then
    Result := -1
  else if Info1.SortTime > Info2.SortTime then
    Result := 1
  else
    Result := CompareText(ExtractFileName(List[Index1]), ExtractFileName(List[Index2]));
end;

// 作成日時を取得できないファイルでは 0 を返して呼び出し側で代替時刻を使わせる
function GetFileCreationTime(const FileName: string): TDateTime;
begin
  try
    Result := TFile.GetCreationTime(FileName);
  except
    Result := 0;
  end;
end;

constructor TVideoMinerMediaList.Create;
begin
  inherited Create;
  FCurrentIndex := -1;
end;

procedure TVideoMinerMediaList.Clear;
begin
  SetLength(FFiles, 0);
  FCurrentIndex := -1;
end;

// 対象拡張子だけをフォルダ内ナビゲーションへ含める
class function TVideoMinerMediaList.IsMediaFile(const FileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result :=
    (Ext = '.mp4') or (Ext = '.mov') or (Ext = '.mkv') or
    (Ext = '.avi') or (Ext = '.wmv') or (Ext = '.m4v') or
    (Ext = '.webm') or (Ext = '.mpg') or (Ext = '.mpeg') or
    (Ext = '.ts') or (Ext = '.m2ts');
end;

// フォルダ内の対象ファイルを収集し、作成日時の古い順で保持する
procedure TVideoMinerMediaList.BuildForFile(const FileName: string);
var
  Folder: string;
  SearchRec: TSearchRec;
  Files: TStringList;
  I: Integer;
  Candidate: string;
  SortInfo: TMediaFileSortInfo;
begin
  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(FileName));
  Files := TStringList.Create;
  try
    Files.CaseSensitive := False;
    Files.Duplicates := dupIgnore;

    if FindFirst(Folder + '*.*', faAnyFile, SearchRec) = 0 then
    try
      repeat
        if (SearchRec.Attr and faDirectory) = 0 then
        begin
          Candidate := Folder + SearchRec.Name;
          if IsMediaFile(Candidate) then
          begin
            SortInfo := TMediaFileSortInfo.Create;
            SortInfo.SortTime := GetFileCreationTime(Candidate);
            if SortInfo.SortTime <= 0 then
              SortInfo.SortTime := SearchRec.TimeStamp;
            Files.AddObject(Candidate, SortInfo);
          end;
        end;
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;

    if Files.IndexOf(FileName) < 0 then
    begin
      SortInfo := TMediaFileSortInfo.Create;
      SortInfo.SortTime := GetFileCreationTime(FileName);
      Files.AddObject(FileName, SortInfo);
    end;

    Files.CustomSort(CompareMediaFilesByTime);

    SetLength(FFiles, Files.Count);
    for I := 0 to Files.Count - 1 do
      FFiles[I] := Files[I];

    FCurrentIndex := Files.IndexOf(FileName);
  finally
    for I := 0 to Files.Count - 1 do
      Files.Objects[I].Free;
    Files.Free;
  end;
end;

// 現在構築済みのファイル数を返す
function TVideoMinerMediaList.GetCount: Integer;
begin
  Result := Length(FFiles);
end;

// 現在位置が無効な場合は空文字を返す
function TVideoMinerMediaList.GetCurrentFile: string;
begin
  Result := FileAt(FCurrentIndex);
end;

function TVideoMinerMediaList.FileAt(Index: Integer): string;
begin
  if (Index < 0) or (Index >= Length(FFiles)) then
    Result := ''
  else
    Result := FFiles[Index];
end;

function TVideoMinerMediaList.CanNavigate(Delta: Integer): Boolean;
var
  NewIndex: Integer;
begin
  NewIndex := FCurrentIndex + Delta;
  Result := (FCurrentIndex >= 0) and (NewIndex >= 0) and
    (NewIndex < Length(FFiles));
end;

function TVideoMinerMediaList.NavigateFile(Delta: Integer): string;
begin
  if CanNavigate(Delta) then
    Result := FileAt(FCurrentIndex + Delta)
  else
    Result := '';
end;

end.
