unit VideoMinerThumbnailBrowserController;

// サムネイル一覧モードの生成、表示切り替え、入力処理、選択時のファイル切り替えを制御する。
// MainForm から一覧モード専用の表示・操作状態を分離する。

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows, Vcl.Controls,
  VideoMinerMediaList, VideoMinerMediaSession, VideoMinerThumbnailBrowser;

type
  TVideoMinerThumbnailOpenFileFunc = function(const FileName: string;
    AutoPlay: Boolean; RestoreLoopPosition: Boolean = True): Boolean of object;

  TVideoMinerThumbnailBrowserController = class
  private
    FBrowser      : TVideoMinerThumbnailBrowser; // 一覧モードの表示コントロール
    FMediaList    : TVideoMinerMediaList;        // 表示対象の動画一覧
    FMediaSession : TVideoMinerMediaSession;     // 現在ファイル参照先
    FOnOpenFile   : TVideoMinerThumbnailOpenFileFunc; // 選択ファイルを開く委譲先
    // 一覧タイル選択時に現在動画へ切り替える
    procedure ThumbnailSelected(Sender: TObject; Index: Integer; const FileName: string);
  public
    // 動画表示面と同じ親/配置で一覧コントロールを作る
    constructor Create(AOwner: TComponent; SurfaceControl: TWinControl;
      MediaList: TVideoMinerMediaList; MediaSession: TVideoMinerMediaSession);
    // 一覧コントロールを解放する
    destructor Destroy; override;
    // 一覧用のリサイズ edge を有効化する
    procedure AttachResizeEdges(BorderSize: Integer);
    // フォームサイズ変更時にリサイズ edge を調整する
    procedure AdjustResizeEdges;
    // 現在の media list を一覧へ反映する
    procedure RefreshMediaList;
    // 一覧モードの表示/非表示を切り替える
    procedure Toggle;
    // 一覧モードを閉じる
    procedure Close;
    // 一覧表示中のホイールを処理する
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    // 一覧表示中または Tab/Esc のキー入力を処理する
    function HandleKeyDown(var Key: Word; Shift: TShiftState): Boolean;
    // 一覧モードが表示中か返す
    function Visible: Boolean;
    property Browser: TVideoMinerThumbnailBrowser read FBrowser;
    property OnOpenFile: TVideoMinerThumbnailOpenFileFunc read FOnOpenFile write FOnOpenFile;
  end;

implementation

uses
  VideoMinerDebugLog, ResizeEdges;

constructor TVideoMinerThumbnailBrowserController.Create(AOwner: TComponent;
  SurfaceControl: TWinControl; MediaList: TVideoMinerMediaList;
  MediaSession: TVideoMinerMediaSession);
begin
  inherited Create;
  FMediaList := MediaList;
  FMediaSession := MediaSession;
  FBrowser := TVideoMinerThumbnailBrowser.Create(AOwner);
  if SurfaceControl <> nil then
  begin
    FBrowser.Parent := SurfaceControl.Parent;
    FBrowser.Align := SurfaceControl.Align;
    FBrowser.SetBounds(SurfaceControl.Left, SurfaceControl.Top,
      SurfaceControl.Width, SurfaceControl.Height);
    FBrowser.Anchors := SurfaceControl.Anchors;
  end;
  FBrowser.OnSelected := ThumbnailSelected;
  FBrowser.SetMediaList(FMediaList);
end;

destructor TVideoMinerThumbnailBrowserController.Destroy;
begin
  FBrowser.Free;
  inherited Destroy;
end;

procedure TVideoMinerThumbnailBrowserController.AttachResizeEdges(BorderSize: Integer);
begin
  if FBrowser <> nil then
    TResizeEdgeHelper.AttachEdges(FBrowser, BorderSize, [rdBottom, rdLeft, rdRight]);
end;

procedure TVideoMinerThumbnailBrowserController.AdjustResizeEdges;
begin
  if FBrowser <> nil then
    TResizeEdgeHelper.AdjustEdges(FBrowser);
end;

procedure TVideoMinerThumbnailBrowserController.RefreshMediaList;
begin
  if FBrowser <> nil then
    FBrowser.SetMediaList(FMediaList);
end;

procedure TVideoMinerThumbnailBrowserController.Toggle;
begin
  if FBrowser = nil then
    Exit;

  WriteVideoMinerSlowLog(Format('thumbnail toggle_begin visible=%s',
    [BoolToStr(FBrowser.Visible, True)]));
  FBrowser.SetMediaList(FMediaList);
  if not FBrowser.Visible then
    FBrowser.ShowHistoryIfMediaListEmpty;
  FBrowser.Toggle;
  WriteVideoMinerSlowLog(Format('thumbnail toggle_end visible=%s',
    [BoolToStr(FBrowser.Visible, True)]));
end;

procedure TVideoMinerThumbnailBrowserController.Close;
begin
  if FBrowser <> nil then
    FBrowser.Close;
end;

function TVideoMinerThumbnailBrowserController.HandleMouseWheel(
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := (FBrowser <> nil) and FBrowser.Visible and
    FBrowser.HandleMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVideoMinerThumbnailBrowserController.HandleKeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
begin
  Result := False;
  if (FBrowser <> nil) and FBrowser.Visible and
     FBrowser.HandleKeyDown(Key, Shift) then
  begin
    Result := True;
    Exit;
  end;

  if (Key = VK_ESCAPE) and (FBrowser <> nil) and FBrowser.Visible then
  begin
    Close;
    Key := 0;
    Result := True;
    Exit;
  end;

  if (Key = VK_TAB) and (Shift = []) then
  begin
    Toggle;
    Key := 0;
    Result := True;
  end;
end;

function TVideoMinerThumbnailBrowserController.Visible: Boolean;
begin
  Result := (FBrowser <> nil) and FBrowser.Visible;
end;

procedure TVideoMinerThumbnailBrowserController.ThumbnailSelected(
  Sender: TObject; Index: Integer; const FileName: string);
begin
  if FileName = '' then
    Exit;

  if (FMediaSession <> nil) and SameText(FileName, FMediaSession.VideoFile) then
  begin
    Close;
    Exit;
  end;

  if Assigned(FOnOpenFile) then
  begin
    Close;
    FOnOpenFile(FileName, True, True);
  end;
end;

end.
