unit VideoMinerThumbnailBrowser;

// 同一フォルダ内の動画を見渡すサムネイル一覧モードを描画する。
// 現段階では画像生成を持たず、メディア一覧をタイルとして表示する入口と基本操作だけを担当する。

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Math, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.Graphics, VideoMinerMediaList;

type
  TVideoMinerThumbnailBrowser = class(TCustomControl)
  private
    FCurrentIndex : Integer;              // 現在再生中として強調する一覧位置
    FHoverIndex   : Integer;              // マウスが重なっているタイル位置
    FMediaList    : TVideoMinerMediaList; // 表示対象になる同一フォルダ内の動画一覧
    FScrollOffset : Integer;              // タイル一覧の縦スクロール量 px
    FTileRects    : TArray<TRect>;        // 最後にレイアウトした各タイルの表示矩形
    // 現在の幅からタイルの列数を返す
    function ColumnCount: Integer;
    // タイル全体の高さを返す
    function ContentHeight: Integer;
    // スクロール量を有効範囲へ収める
    procedure ClampScrollOffset;
    // 指定位置にあるタイル index を返す
    function HitTile(const Point: TPoint): Integer;
    // 現在の一覧状態に合わせてタイル矩形を作る
    procedure LayoutTiles;
    // タイル下部に表示するファイル名を描く
    procedure DrawFileName(Canvas: TCanvas; const Bounds: TRect; const FileName: string);
    // 1 つのタイルを描く
    procedure DrawTile(Canvas: TCanvas; Index: Integer; const Bounds: TRect);
    // 表示時に現在ファイルが見える位置へスクロールする
    procedure ScrollToCurrent;
  protected
    // 背景消去を抑止する
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    // タイル hover を更新する
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    // 一覧外へ出たら hover を解除する
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    // マウスホイールで一覧を縦スクロールする
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    // タイル一覧を描画する
    procedure Paint; override;
    // サイズ変更時にスクロール位置を補正する
    procedure Resize; override;
  public
    // 表示コントロールの初期状態を作る
    constructor Create(AOwner: TComponent); override;
    // 表示するメディア一覧を差し替える
    procedure SetMediaList(MediaList: TVideoMinerMediaList);
    // 一覧モードを開く
    procedure Open;
    // 一覧モードを閉じる
    procedure Close;
    // 一覧モードの表示/非表示を切り替える
    procedure Toggle;
  end;

implementation

const
  BROWSER_BACKGROUND_COLOR  = $00111111; // 一覧モード全体の背景色
  TILE_BACKGROUND_COLOR     = $00202020; // 画像未生成タイルの背景色
  TILE_HOVER_COLOR          = $00303030; // hover 中タイルの背景色
  TILE_CURRENT_BORDER_COLOR = $0000A5FF; // 現在再生中タイルの強調枠色
  TILE_BORDER_COLOR         = $00404040; // 通常タイルの枠色
  TILE_WIDTH                = 220;       // タイルの基本幅 px
  TILE_HEIGHT               = 132;       // タイルの基本高さ px
  TILE_GAP                  = 14;        // タイル間の余白 px
  TILE_MARGIN               = 22;        // 一覧外周の余白 px
  NAME_BAND_HEIGHT          = 28;        // ファイル名を重ねる帯の高さ px
  WHEEL_SCROLL_STEP         = 90;        // ホイール 1 ノッチあたりのスクロール量 px

constructor TVideoMinerThumbnailBrowser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := False;
  Visible := False;
  FCurrentIndex := -1;
  FHoverIndex := -1;
end;

function TVideoMinerThumbnailBrowser.ColumnCount: Integer;
begin
  Result := Max(1, (ClientWidth - TILE_MARGIN * 2 + TILE_GAP) div
    (TILE_WIDTH + TILE_GAP));
end;

function TVideoMinerThumbnailBrowser.ContentHeight: Integer;
var
  Rows: Integer;
begin
  if (FMediaList = nil) or (FMediaList.Count <= 0) then
  begin
    Result := 0;
    Exit;
  end;

  Rows := Ceil(FMediaList.Count / ColumnCount);
  Result := TILE_MARGIN * 2 + Rows * TILE_HEIGHT + Max(0, Rows - 1) * TILE_GAP;
end;

procedure TVideoMinerThumbnailBrowser.ClampScrollOffset;
var
  MaxOffset: Integer;
begin
  MaxOffset := Max(0, ContentHeight - ClientHeight);
  FScrollOffset := Max(0, Min(FScrollOffset, MaxOffset));
end;

procedure TVideoMinerThumbnailBrowser.Close;
begin
  Visible := False;
end;

procedure TVideoMinerThumbnailBrowser.DrawFileName(Canvas: TCanvas;
  const Bounds: TRect; const FileName: string);
var
  TextRect: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clBlack;
  Canvas.FillRect(Bounds);
  TextRect := Bounds;
  InflateRect(TextRect, -8, 0);
  Canvas.Font.Color := clWhite;
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [];
  DrawText(Canvas.Handle, PChar(ExtractFileName(FileName)), -1, TextRect,
    DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS);
end;

procedure TVideoMinerThumbnailBrowser.DrawTile(Canvas: TCanvas; Index: Integer;
  const Bounds: TRect);
var
  FileName: string;
  NameRect: TRect;
  TextRect: TRect;
begin
  if FMediaList = nil then
    Exit;

  FileName := FMediaList.FileAt(Index);
  if Index = FHoverIndex then
    Canvas.Brush.Color := TILE_HOVER_COLOR
  else
    Canvas.Brush.Color := TILE_BACKGROUND_COLOR;
  Canvas.Pen.Color := TILE_BORDER_COLOR;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(Bounds);

  Canvas.Font.Color := $00909090;
  Canvas.Font.Size := 10;
  TextRect := Bounds;
  DrawText(Canvas.Handle, PChar('Thumbnail'), -1, TextRect,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);

  NameRect := Rect(Bounds.Left + 1, Bounds.Bottom - NAME_BAND_HEIGHT,
    Bounds.Right - 1, Bounds.Bottom - 1);
  DrawFileName(Canvas, NameRect, FileName);

  if Index = FCurrentIndex then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := TILE_CURRENT_BORDER_COLOR;
    Canvas.Pen.Width := 3;
    Canvas.Rectangle(Bounds);
    Canvas.Brush.Style := bsSolid;
    Canvas.Pen.Width := 1;
  end;
end;

function TVideoMinerThumbnailBrowser.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then
    Dec(FScrollOffset, WHEEL_SCROLL_STEP)
  else
    Inc(FScrollOffset, WHEEL_SCROLL_STEP);
  ClampScrollOffset;
  LayoutTiles;
  Invalidate;
  Result := True;
end;

function TVideoMinerThumbnailBrowser.HitTile(const Point: TPoint): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Length(FTileRects) - 1 do
  begin
    if PtInRect(FTileRects[I], Point) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TVideoMinerThumbnailBrowser.LayoutTiles;
var
  Col: Integer;
  Cols: Integer;
  Count: Integer;
  I: Integer;
  LeftStart: Integer;
  Row: Integer;
  TotalWidth: Integer;
begin
  if FMediaList = nil then
    Count := 0
  else
    Count := FMediaList.Count;

  SetLength(FTileRects, Count);
  if Count <= 0 then
    Exit;

  Cols := ColumnCount;
  TotalWidth := Cols * TILE_WIDTH + Max(0, Cols - 1) * TILE_GAP;
  LeftStart := Max(TILE_MARGIN, (ClientWidth - TotalWidth) div 2);

  for I := 0 to Count - 1 do
  begin
    Row := I div Cols;
    Col := I mod Cols;
    FTileRects[I] := Rect(
      LeftStart + Col * (TILE_WIDTH + TILE_GAP),
      TILE_MARGIN + Row * (TILE_HEIGHT + TILE_GAP) - FScrollOffset,
      LeftStart + Col * (TILE_WIDTH + TILE_GAP) + TILE_WIDTH,
      TILE_MARGIN + Row * (TILE_HEIGHT + TILE_GAP) + TILE_HEIGHT -
        FScrollOffset);
  end;
end;

procedure TVideoMinerThumbnailBrowser.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHoverIndex >= 0 then
  begin
    FHoverIndex := -1;
    Invalidate;
  end;
end;

procedure TVideoMinerThumbnailBrowser.MouseMove(Shift: TShiftState; X,
  Y: Integer);
var
  NewHoverIndex: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  NewHoverIndex := HitTile(Point(X, Y));
  if FHoverIndex <> NewHoverIndex then
  begin
    FHoverIndex := NewHoverIndex;
    Invalidate;
  end;
end;

procedure TVideoMinerThumbnailBrowser.Open;
begin
  if FMediaList <> nil then
    FCurrentIndex := FMediaList.CurrentIndex
  else
    FCurrentIndex := -1;
  ScrollToCurrent;
  Visible := True;
  BringToFront;
  SetFocus;
  Invalidate;
end;

procedure TVideoMinerThumbnailBrowser.Paint;
var
  I: Integer;
  TextRect: TRect;
begin
  Canvas.Brush.Color := BROWSER_BACKGROUND_COLOR;
  Canvas.FillRect(ClientRect);

  LayoutTiles;
  if Length(FTileRects) <= 0 then
  begin
    TextRect := ClientRect;
    Canvas.Font.Color := $00A0A0A0;
    Canvas.Font.Size := 11;
    DrawText(Canvas.Handle, PChar('No videos'), -1, TextRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    Exit;
  end;

  for I := 0 to Length(FTileRects) - 1 do
  begin
    if (FTileRects[I].Bottom < 0) or (FTileRects[I].Top > ClientHeight) then
      Continue;
    DrawTile(Canvas, I, FTileRects[I]);
  end;
end;

procedure TVideoMinerThumbnailBrowser.Resize;
begin
  inherited Resize;
  ClampScrollOffset;
  LayoutTiles;
end;

procedure TVideoMinerThumbnailBrowser.ScrollToCurrent;
var
  Cols: Integer;
  Row: Integer;
  TileBottom: Integer;
  TileTop: Integer;
begin
  FScrollOffset := 0;
  if (FMediaList = nil) or (FCurrentIndex < 0) then
    Exit;

  Cols := ColumnCount;
  Row := FCurrentIndex div Cols;
  TileTop := TILE_MARGIN + Row * (TILE_HEIGHT + TILE_GAP);
  TileBottom := TileTop + TILE_HEIGHT;
  if TileBottom > ClientHeight - TILE_MARGIN then
    FScrollOffset := TileBottom - ClientHeight + TILE_MARGIN;
  ClampScrollOffset;
  LayoutTiles;
end;

procedure TVideoMinerThumbnailBrowser.SetMediaList(
  MediaList: TVideoMinerMediaList);
begin
  FMediaList := MediaList;
  if FMediaList <> nil then
    FCurrentIndex := FMediaList.CurrentIndex
  else
    FCurrentIndex := -1;
  ClampScrollOffset;
  LayoutTiles;
  Invalidate;
end;

procedure TVideoMinerThumbnailBrowser.Toggle;
begin
  if Visible then
    Close
  else
    Open;
end;

procedure TVideoMinerThumbnailBrowser.WMEraseBkgnd(
  var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

end.
