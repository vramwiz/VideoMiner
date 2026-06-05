unit FolderWatch;

{
  Unit Name  : FolderWatch

  概要:
    このユニットは指定されたフォルダを監視し、ファイルの追加・削除・更新を
    自動で検出してイベントで通知する機能を提供します。

  主なクラス:
    - TFolderWatch
        フォルダ監視のメインクラス。プロパティを通じて監視対象フォルダや
        サブフォルダの監視可否、各種イベントハンドラを設定可能です。

    - TFolderWatchThread
        バックグラウンドで監視を実行するスレッドクラス。一定間隔でフォルダをスキャンし、
        前回のスナップショットと比較して差分を検出します。

  イベント:
    - OnFileAdd:     ファイルが追加されたときに発生します。
    - OnFileDelete:  ファイルが削除されたときに発生します。
    - OnFileUpdate:  既存ファイルが更新されたときに発生します。
    - OnFileChange:  上記すべての変更（追加・削除・更新）をまとめて通知します。

  注意点:
    - スレッドでフォルダを定期スキャンする方式であるため、
      ファイルシステムの通知API（FindFirstChangeNotification 等）は使用していません。
    - スキャン間隔や通知の粒度は内部実装に依存します。
    - スレッドはバックグラウンドで実行されますが、イベントハンドラの処理が
      メインスレッドであることは保証されません（必要に応じて同期処理を行ってください）。

  利用例:
    var
      Watcher: TFolderWatch;
    begin
      Watcher := TFolderWatch.Create;
      Watcher.FolderPath := 'C:\MyFolder';
      Watcher.OnFileAdd := MyAddHandler;
      Watcher.Start;
    end;
}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls,System.Generics.Collections;


type  TFolderWatchEvent = procedure(Sender: TObject; const FileNames: TStringList) of object;
type  TFolderWatchAllEvent = procedure(Sender: TObject; const AddFiles: TStringList; const DelFiles: TStringList; const UpdateFiles: TStringList) of object;

type
  TFolderWatchThread = class(TThread)
  private
    FFolderPath        : string;
    FFirstScanDone     : Boolean;
    FIncludeSubFolders : Boolean;
    FNotifyFilter      : DWORD;
    FExtFilters        : TStringList;
    FOwner             : TObject; // ← 型を抽象化

    FLastSnapshot: TDictionary<string, TDateTime>; // 監視キャッシュ
    FNotificationHandle: THandle;
    // 指定フォルダ内の全ファイルを走査
    procedure ScanAndCompare;
    // ファイルを検索
    procedure ScanSearch(CurrentFiles: TDictionary<string, TDateTime>);
    // 現在の情報を保存
    procedure ScanUpdate(CurrentFiles: TDictionary<string, TDateTime>);
    // スキャンを無視
    procedure ScanDone();
    // ファイル名を引数に取り、ExtFilters を参照して、表示してよければ True
    function IsVisible(const FileName: string): Boolean;
    //スレッド内部からオーナー（TFolderWatch）に対してイベントをスレッドセーフに通知します。
    procedure NotifyChanges(const AddList, DelList, ModList: TStringList);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TObject);
    destructor Destroy; override;
  end;

type
  TFolderWatch = class(TPersistent )
  private
    { Private 宣言 }
    FFolderPath        : string;
    FIncludeSubFolders : Boolean;
    FNotifyFilter      : DWORD;
    FThread            : TFolderWatchThread;
    FOnFileChange      : TFolderWatchAllEvent;
    FOnFileAdd         : TFolderWatchEvent;
    FOnFileDelete      : TFolderWatchEvent;
    FOnFileUpdate      : TFolderWatchEvent;
    FFirstScanDone     : Boolean;
    FExtFilters        : TStringList;
    procedure StartWatching;
    procedure StopWatching;
    procedure RestartWatchingIfRunning(const Action: TProc);
    procedure SetFolderPath(const Value: string);
    procedure SetIncludeSubFolders(const Value: Boolean);
    procedure SetNotifyFilter(const Value: DWORD);
    procedure SetFirstScanDone(const Value: Boolean);
  protected
    procedure DoFileAdd(const FileNames: TStringList);
    procedure DoFileDelete(const FileNames: TStringList);
    procedure DoFileUpdate(const FileNames: TStringList);
    procedure DoFileChange(const AddFiles: TStringList; const DelFiles: TStringList; const UpdateFiles: TStringList);
  public
    constructor Create();
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property FolderPath: string read FFolderPath write SetFolderPath;
    property IncludeSubFolders: Boolean read FIncludeSubFolders write SetIncludeSubFolders;
    property NotifyFilter: DWORD read FNotifyFilter write SetNotifyFilter;
    // 初回はイベントを発生させない
    property FirstScanDone : Boolean read FFirstScanDone write SetFirstScanDone;
    // 拡張子フィルター ※設定後再起動が必要
    property ExtFilters: TStringList read FExtFilters;
    property OnFileChange: TFolderWatchAllEvent read FOnFileChange write FOnFileChange;
    property OnFileAdd: TFolderWatchEvent       read FOnFileAdd    write FOnFileAdd;
    property OnFileDelete: TFolderWatchEvent    read FOnFileDelete write FOnFileDelete;
    property OnFileUpdate: TFolderWatchEvent    read FOnFileUpdate write FOnFileUpdate;
  end;

implementation

uses System.IOUtils;

const
  MinTimeGapSec = 1.0; // 1秒以内の変更は無視

{ TFolderWatch }

constructor TFolderWatch.Create;
begin
  inherited Create;

  // 初期値の設定（必要に応じて）
  FFolderPath := '';
  FIncludeSubFolders := False;

  FExtFilters := TStringList.Create;
  FExtFilters.CaseSensitive := False;

  // 初期登録（必要なら外部から追加／削除可能）
  FExtFilters.Add('.crdownload');
  FExtFilters.Add('.tmp');
  FExtFilters.Add('.part');
  FNotifyFilter := FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_LAST_WRITE;
end;

destructor TFolderWatch.Destroy;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FThread.Free;
  end;

  inherited Destroy;
end;

procedure TFolderWatch.Start;
begin
  StartWatching;
end;

procedure TFolderWatch.StartWatching;
begin
  if Assigned(FThread) then
    Exit; // すでに開始されていれば無視

  FThread := TFolderWatchThread.Create(Self);
  FThread.FFolderPath := FFolderPath;
  FThread.FIncludeSubFolders := FIncludeSubFolders;
  FThread.FNotifyFilter := FNotifyFilter;
  FThread.FreeOnTerminate := False;
  FThread.FFirstScanDone := FFirstScanDone;
  FThread.FExtFilters.Assign(FExtFilters);
  FThread.Start;
end;

procedure TFolderWatch.Stop;
begin
  StopWatching;
end;

procedure TFolderWatch.StopWatching;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

procedure TFolderWatch.SetFirstScanDone(const Value: Boolean);
begin
  FFirstScanDone := Value;
  if FFirstScanDone = Value then Exit;

  RestartWatchingIfRunning(
    procedure
    begin
      FFirstScanDone := Value;
    end);
end;

procedure TFolderWatch.SetFolderPath(const Value: string);
begin
  if SameText(FFolderPath, Value) then Exit;

  RestartWatchingIfRunning(
    procedure
    begin
      FFolderPath := Value;
    end);
end;

procedure TFolderWatch.SetIncludeSubFolders(const Value: Boolean);
begin
  if FIncludeSubFolders = Value then Exit;

  RestartWatchingIfRunning(
    procedure
    begin
      FIncludeSubFolders := Value;
    end);
end;

procedure TFolderWatch.SetNotifyFilter(const Value: DWORD);
begin
  if FNotifyFilter = Value then
    Exit;

  RestartWatchingIfRunning(
    procedure
    begin
      FNotifyFilter := Value;
    end);
end;

procedure TFolderWatch.RestartWatchingIfRunning(const Action: TProc);
var
  WasRunning: Boolean;
begin
  WasRunning := Assigned(FThread) and (FThread.Finished = False);
  if WasRunning then
    StopWatching;

  Action(); // 値の変更

  if WasRunning then
    StartWatching;
end;


procedure TFolderWatch.DoFileAdd(const FileNames: TStringList);
begin
 if Assigned(FOnFileAdd) then FOnFileAdd(Self,FileNames);
end;

procedure TFolderWatch.DoFileUpdate(const FileNames: TStringList);
begin
 if Assigned(FOnFileUpdate) then FOnFileUpdate(Self,FileNames);
end;

procedure TFolderWatch.DoFileDelete(const FileNames: TStringList);
begin
 if Assigned(FOnFileDelete) then FOnFileDelete(Self,FileNames);
end;

procedure TFolderWatch.DoFileChange(const AddFiles, DelFiles,UpdateFiles: TStringList);
begin
 if Assigned(FOnFileChange) then FOnFileChange(Self,AddFiles, DelFiles,UpdateFiles);
end;


{ TFolderWatchThread }

constructor TFolderWatchThread.Create(AOwner: TObject);
begin
  inherited Create(True); // Suspended=True（Startは外で呼ぶ）

  FreeOnTerminate := False; // 明示的に解放する想定
  FOwner := AOwner;

  FFolderPath := '';
  FIncludeSubFolders := False;
  FNotifyFilter := FILE_NOTIFY_CHANGE_FILE_NAME or
                   FILE_NOTIFY_CHANGE_LAST_WRITE or
                   FILE_NOTIFY_CHANGE_SIZE;

  FExtFilters := TStringList.Create;
  FNotificationHandle := 0;
  FLastSnapshot := TDictionary<string, TDateTime>.Create;
end;

destructor TFolderWatchThread.Destroy;
begin
  if FNotificationHandle <> 0 then
  begin
    FindCloseChangeNotification(FNotificationHandle);
    FNotificationHandle := 0;
  end;

  FLastSnapshot.Free;
  FExtFilters.Free;
  inherited;
end;

procedure TFolderWatchThread.Execute;
begin
  FNotificationHandle := FindFirstChangeNotification(
    PChar(FFolderPath),
    FIncludeSubFolders,
    FNotifyFilter
  );

  if FNotificationHandle = INVALID_HANDLE_VALUE then
    Exit;

  if FFirstScanDone then begin
    ScanDone();
  end;

  try
    // 初回スナップショット作成
    ScanAndCompare;

    while not Terminated do
    begin
      // 変更が通知されるまで待機
      case WaitForSingleObject(FNotificationHandle, 500) of
        WAIT_OBJECT_0:
        begin
          if Terminated then Break;
          Sleep(500);             // 追加・削除・変更の誤検出を避けるため、通知後に少し待つ
          ScanAndCompare;         // DL完了 or メタデータ更新の余波を吸収する

          // 次の通知を再設定
          if not FindNextChangeNotification(FNotificationHandle) then
            Break;
        end;

        WAIT_FAILED:
          Break;
      end;
    end;

  finally
    if FNotificationHandle <> 0 then
    begin
      FindCloseChangeNotification(FNotificationHandle);
      FNotificationHandle := 0;
    end;
  end;
end;

function TFolderWatchThread.IsVisible(const FileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := FExtFilters.IndexOf(Ext) = -1; // フィルターに含まれていなければ表示対象
end;

procedure TFolderWatchThread.NotifyChanges(const AddList, DelList,
  ModList: TStringList);
var
  Owner: TFolderWatch;
begin
  if not (FOwner is TFolderWatch) then
    Exit;

  Owner := TFolderWatch(FOwner);

  // 一括通知（OnFileChange）
  Synchronize(procedure begin
    Owner.DoFileChange(AddList, DelList, ModList);
  end);

  // 個別通知（DoFileAdd）
  if (AddList.Count > 0) then begin
    Synchronize(procedure begin
      Owner.DoFileAdd(AddList);
    end);
  end;

  if (DelList.Count > 0) then begin
    Synchronize(procedure begin
      Owner.DoFileDelete(DelList);
    end);
  end;

  if (ModList.Count > 0) then begin
    Synchronize(procedure begin
      Owner.DoFileUpdate(ModList);
    end);
  end;
end;

procedure TFolderWatchThread.ScanAndCompare;
var
  CurrentFiles: TDictionary<string, TDateTime>;
  FilePath: string;
  AddList, DelList, ModList: TStringList;
  Pair: TPair<string, TDateTime>;
  Value: TDateTime;
begin
  CurrentFiles := TDictionary<string, TDateTime>.Create;
  AddList := TStringList.Create;
  DelList := TStringList.Create;
  ModList := TStringList.Create;
  try
    // 再帰しない単純な走査（再帰対応はあとで改良可）
    ScanSearch(CurrentFiles);

    // 追加／更新チェック
    for Pair in CurrentFiles do
    begin
      if not FLastSnapshot.TryGetValue(Pair.Key, Value) then
      begin
        AddList.Add(Pair.Key); // 新規追加
      end
      else if (FLastSnapshot[Pair.Key] <> Pair.Value) and
              ((Now - FLastSnapshot[Pair.Key]) * 86400 > MinTimeGapSec) then
      begin
        ModList.Add(Pair.Key); // 更新あり
      end;
    end;

    // 削除チェック
    for Pair in FLastSnapshot do
    begin
      if not CurrentFiles.ContainsKey(Pair.Key) then
        DelList.Add(Pair.Key);
    end;

    // 通知実行
    NotifyChanges(AddList, DelList, ModList);

    // 現在の情報を保存
    ScanUpdate(CurrentFiles);

  finally
    AddList.Free;
    DelList.Free;
    ModList.Free;
    CurrentFiles.Free;
  end;
end;

procedure TFolderWatchThread.ScanSearch(
  CurrentFiles: TDictionary<string, TDateTime>);
var
  SearchRec: TSearchRec;
  FilePath: string;
begin
  // 再帰しない単純な走査（再帰対応はあとで改良可）
  if FindFirst(IncludeTrailingPathDelimiter(FFolderPath) + '*.*', faAnyFile, SearchRec) = 0 then
  begin
    repeat
      if (SearchRec.Attr and faDirectory) = 0 then
      begin
        if not IsVisible(SearchRec.Name) then Continue;   // 監視対象か判断
        FilePath := IncludeTrailingPathDelimiter(FFolderPath) + SearchRec.Name;
        CurrentFiles.Add(FilePath, SearchRec.TimeStamp);  // Delphi10以降対応
      end;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;
end;

procedure TFolderWatchThread.ScanUpdate(
  CurrentFiles: TDictionary<string, TDateTime>);
var
  Pair: TPair<string, TDateTime>;
begin
  FLastSnapshot.Clear;
  for Pair in CurrentFiles do begin
    if not IsVisible(Pair.Key) then Continue;   // 監視対象か判断
    FLastSnapshot.Add(Pair.Key, Pair.Value);
  end;
end;

procedure TFolderWatchThread.ScanDone;
var
  CurrentFiles: TDictionary<string, TDateTime>;
begin
  CurrentFiles := TDictionary<string, TDateTime>.Create;
  try
    ScanSearch(CurrentFiles);
    ScanUpdate(CurrentFiles);
  finally
    CurrentFiles.Free;
  end;

end;


end.
