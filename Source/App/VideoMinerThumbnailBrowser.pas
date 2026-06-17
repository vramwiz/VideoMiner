unit VideoMinerThumbnailBrowser;

// 同一フォルダ内の動画を見渡すサムネイル一覧モードを描画する。
// 表示中タイルのサムネイルを少しずつ生成し、クリック選択をメインフォームへ通知する。

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Math, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder, FFmpegDecoderTypes,
  VideoMinerMediaList, VideoMinerThumbnailCache, VideoMinerWindowChrome;

type
  TVideoMinerThumbnailSelectedEvent = procedure(Sender: TObject;
    Index: Integer; const FileName: string) of object;

  TVideoMinerThumbnailState = (tsNone, tsQueued, tsReady, tsFailed);

  TVideoMinerThumbnailBrowser = class(TCustomControl)
  private
    FCurrentIndex : Integer;              // 現在再生中として強調する一覧位置
    FHoverIndex   : Integer;              // マウスが重なっているタイル位置
    FMediaList    : TVideoMinerMediaList; // 表示対象になる同一フォルダ内の動画一覧
    FOnSelected   : TVideoMinerThumbnailSelectedEvent; // タイル選択の通知先
    FScrollOffset : Integer;              // タイル一覧の縦スクロール量 px
    FThumbnailFiles  : TArray<string>;    // サムネイル状態が対応するファイル名
    FThumbnailStates : TArray<TVideoMinerThumbnailState>; // サムネイル生成状態
    FThumbnails      : TArray<TBitmap>;   // 生成済みサムネイル画像
    FThumbnailTimer  : TTimer;            // サムネイルを少しずつ生成するタイマー
    FTileHeight      : Integer;           // 現在のタイル高さ px
    FTileWidth       : Integer;           // 現在のタイル幅 px
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
    // サムネイル配列を現在のメディア一覧へ合わせる
    procedure EnsureThumbnailSlots;
    // 保持しているサムネイルを破棄する
    procedure ClearThumbnails;
    // 表示中タイルのサムネイル生成を予約する
    procedure QueueThumbnail(Index: Integer);
    // 次に生成する予約済みタイルを返す
    function NextQueuedThumbnailIndex: Integer;
    // キャッシュ済みサムネイルを読み込めたら True を返す
    function TryLoadCachedThumbnail(Index: Integer;
      const FileName: string): Boolean;
    // 指定タイルのサムネイルを生成する
    procedure GenerateThumbnail(Index: Integer;
      const FileName: string);
    // タイマーでサムネイルを 1 枚ずつ生成する
    procedure ThumbnailTimer(Sender: TObject);
    // タイル内にサムネイル画像または生成状態を描く
    procedure DrawThumbnail(Canvas: TCanvas; Index: Integer; const Bounds: TRect);
    // タイル下部に表示するファイル名を描く
    procedure DrawFileName(Canvas: TCanvas; const Bounds: TRect; const FileName: string);
    // 1 つのタイルを描く
    procedure DrawTile(Canvas: TCanvas; Index: Integer; const Bounds: TRect);
    // 表示時に現在ファイルが見える位置へスクロールする
    procedure ScrollToCurrent;
    // ホイール入力でサムネイルサイズを拡大縮小する
    procedure ZoomByWheel(WheelDelta: Integer; const MousePos: TPoint);
  protected
    // 背景消去を抑止する
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    // サムネイル表示中もフォーム端のリサイズ判定を親フォームへ通す
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    // タイル hover を更新する
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    // 一覧外へ出たら hover を解除する
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    // マウスホイールで一覧を縦スクロールする
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    // タイルクリックを選択通知に変換する
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // タイル一覧を描画する
    procedure Paint; override;
    // サイズ変更時にスクロール位置を補正する
    procedure Resize; override;
  public
    // 表示コントロールの初期状態を作る
    constructor Create(AOwner: TComponent); override;
    // 保持したサムネイル画像を解放する
    destructor Destroy; override;
    // 表示するメディア一覧を差し替える
    procedure SetMediaList(MediaList: TVideoMinerMediaList);
    // フォーム経由で届いたホイール入力を一覧スクロールとして処理する
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    // 一覧モードを開く
    procedure Open;
    // 一覧モードを閉じる
    procedure Close;
    // 一覧モードの表示/非表示を切り替える
    procedure Toggle;
    property OnSelected: TVideoMinerThumbnailSelectedEvent
      read FOnSelected write FOnSelected;
  end;

implementation

const
  BROWSER_BACKGROUND_COLOR  = $00111111; // 一覧モード全体の背景色
  TILE_BACKGROUND_COLOR     = $00202020; // 画像未生成タイルの背景色
  TILE_HOVER_COLOR          = $00303030; // hover 中タイルの背景色
  TILE_CURRENT_BORDER_COLOR = $0000A5FF; // 現在再生中タイルの強調枠色
  TILE_HOVER_BORDER_COLOR   = $00FFCC66; // hover 中タイルの強調枠色
  TILE_BORDER_COLOR         = $00404040; // 通常タイルの枠色
  TILE_WIDTH                = 220;       // タイルの基本幅 px
  TILE_HEIGHT               = 132;       // タイルの基本高さ px
  TILE_MIN_WIDTH            = 150;       // タイルの最小幅 px
  TILE_MAX_WIDTH            = 380;       // タイルの最大幅 px
  TILE_ZOOM_STEP            = 24;        // ホイール 1 ノッチあたりのサイズ変更量 px
  TILE_GAP                  = 14;        // タイル間の余白 px
  TILE_MARGIN               = 22;        // 一覧外周の余白 px
  NAME_BAND_HEIGHT          = 28;        // ファイル名を重ねる帯の高さ px
  THUMBNAIL_TIMER_INTERVAL  = 80;        // サムネイルを 1 枚ずつ生成する間隔 ms
  THUMBNAIL_MAX_WIDTH       = 320;       // 生成サムネイルの最大幅 px
  THUMBNAIL_MAX_HEIGHT      = 180;       // 生成サムネイルの最大高さ px
  THUMBNAIL_CACHE_BURST     = 24;        // 1 tick で読み込むキャッシュ済みサムネイル数

constructor TVideoMinerThumbnailBrowser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := False;
  Visible := False;
  FCurrentIndex := -1;
  FHoverIndex := -1;
  FTileWidth := TILE_WIDTH;
  FTileHeight := TILE_HEIGHT;
  FThumbnailTimer := TTimer.Create(Self);
  FThumbnailTimer.Enabled := False;
  FThumbnailTimer.Interval := THUMBNAIL_TIMER_INTERVAL;
  FThumbnailTimer.OnTimer := ThumbnailTimer;
end;

destructor TVideoMinerThumbnailBrowser.Destroy;
begin
  ClearThumbnails;
  inherited Destroy;
end;

function TVideoMinerThumbnailBrowser.ColumnCount: Integer;
begin
  Result := Max(1, (ClientWidth - TILE_MARGIN * 2 + TILE_GAP) div
    (FTileWidth + TILE_GAP));
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
  Result := TILE_MARGIN * 2 + Rows * FTileHeight + Max(0, Rows - 1) * TILE_GAP;
end;

procedure TVideoMinerThumbnailBrowser.ClampScrollOffset;
var
  MaxOffset: Integer;
begin
  MaxOffset := Max(0, ContentHeight - ClientHeight);
  FScrollOffset := Max(0, Min(FScrollOffset, MaxOffset));
end;

procedure TVideoMinerThumbnailBrowser.ClearThumbnails;
var
  I: Integer;
begin
  if FThumbnailTimer <> nil then
    FThumbnailTimer.Enabled := False;

  for I := 0 to Length(FThumbnails) - 1 do
    FThumbnails[I].Free;
  SetLength(FThumbnails, 0);
  SetLength(FThumbnailStates, 0);
  SetLength(FThumbnailFiles, 0);
end;

procedure TVideoMinerThumbnailBrowser.EnsureThumbnailSlots;
var
  Count: Integer;
  FileName: string;
  I: Integer;
begin
  if FMediaList = nil then
    Count := 0
  else
    Count := FMediaList.Count;

  if Length(FThumbnails) <> Count then
  begin
    ClearThumbnails;
    SetLength(FThumbnails, Count);
    SetLength(FThumbnailStates, Count);
    SetLength(FThumbnailFiles, Count);
  end;

  for I := 0 to Count - 1 do
  begin
    FileName := FMediaList.FileAt(I);
    if not SameText(FThumbnailFiles[I], FileName) then
    begin
      FThumbnails[I].Free;
      FThumbnails[I] := nil;
      FThumbnailStates[I] := tsNone;
      FThumbnailFiles[I] := FileName;
    end;
  end;
end;

procedure TVideoMinerThumbnailBrowser.QueueThumbnail(Index: Integer);
begin
  EnsureThumbnailSlots;
  if (Index < 0) or (Index >= Length(FThumbnailStates)) then
    Exit;

  if FThumbnailStates[Index] <> tsNone then
    Exit;

  FThumbnailStates[Index] := tsQueued;
  if Visible and (FThumbnailTimer <> nil) then
    FThumbnailTimer.Enabled := True;
end;

function TVideoMinerThumbnailBrowser.NextQueuedThumbnailIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Length(FThumbnailStates) - 1 do
  begin
    if FThumbnailStates[I] = tsQueued then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TVideoMinerThumbnailBrowser.TryLoadCachedThumbnail(Index: Integer;
  const FileName: string): Boolean;
var
  Dest: TBitmap;
begin
  Result := False;
  if (Index < 0) or (Index >= Length(FThumbnailStates)) or
     (FileName = '') then
    Exit;

  Dest := TBitmap.Create;
  try
    if not LoadVideoMinerThumbnailCache(FileName, Dest) then
      Exit;

    FThumbnails[Index].Free;
    FThumbnails[Index] := Dest;
    Dest := nil;
    FThumbnailStates[Index] := tsReady;
    Result := True;
  finally
    Dest.Free;
  end;
end;
procedure TVideoMinerThumbnailBrowser.GenerateThumbnail(Index: Integer;
  const FileName: string);
var
  Buffer: Pointer;
  BufferStride: Integer;
  Decoder: TFFmpegDecoder;
  Dest: TBitmap;
  DurationMs: Integer;
  ErrorMessage: string;
  Info: TVideoInfo;
  PositionMs: Integer;
  Scale: Double;
  Source: TBitmap;
  ThumbHeight: Integer;
  ThumbWidth: Integer;
begin
  if (Index < 0) or (Index >= Length(FThumbnailStates)) or
     (FileName = '') then
    Exit;

  Source := TBitmap.Create;
  Decoder := TFFmpegDecoder.Create;
  try
    try

      if not Decoder.Open(FileName, Info, ErrorMessage) then
      begin
        FThumbnailStates[Index] := tsFailed;
        Exit;
      end;

      DurationMs := Round(Info.DurationSec * 1000);
      if DurationMs <= 0 then
        PositionMs := 0
      else if DurationMs < 1000 then
        PositionMs := Max(0, DurationMs div 2)
      else
        PositionMs := Min(DurationMs - 1, Max(500, DurationMs div 10));

      if (Info.Width <= 0) or (Info.Height <= 0) then
      begin
        FThumbnailStates[Index] := tsFailed;
        Exit;
      end;

      Source.PixelFormat := pf32bit;
      Source.SetSize(Info.Width, Info.Height);
      if Info.Height > 1 then
        BufferStride := Abs(NativeInt(Source.ScanLine[1]) -
          NativeInt(Source.ScanLine[0]))
      else
        BufferStride := Info.Width * 4;
      Buffer := Source.ScanLine[Info.Height - 1];

      if (Buffer = nil) or (BufferStride <= 0) or
         (not Decoder.DecodeFrameToBgrx32(PositionMs, Buffer, BufferStride,
           ErrorMessage)) then
      begin
        FThumbnailStates[Index] := tsFailed;
        Exit;
      end;

      Scale := Min(THUMBNAIL_MAX_WIDTH / Source.Width,
        THUMBNAIL_MAX_HEIGHT / Source.Height);
      ThumbWidth := Max(1, Round(Source.Width * Scale));
      ThumbHeight := Max(1, Round(Source.Height * Scale));

      Dest := TBitmap.Create;
      try
        Dest.PixelFormat := pf32bit;
        Dest.SetSize(ThumbWidth, ThumbHeight);
        Dest.Canvas.Brush.Color := clBlack;
        Dest.Canvas.FillRect(Rect(0, 0, ThumbWidth, ThumbHeight));
        Dest.Canvas.StretchDraw(Rect(0, 0, ThumbWidth, ThumbHeight), Source);
        FThumbnails[Index].Free;
        SaveVideoMinerThumbnailCache(FileName, Dest);
        FThumbnails[Index] := Dest;
        Dest := nil;
        FThumbnailStates[Index] := tsReady;
      finally
        Dest.Free;
      end;
    except
      FThumbnailStates[Index] := tsFailed;
    end;
  finally
    Decoder.Free;
    Source.Free;
  end;
end;
procedure TVideoMinerThumbnailBrowser.ThumbnailTimer(Sender: TObject);
var
  CacheLoads: Integer;
  FileName: string;
  Index: Integer;
  Updated: Boolean;
begin
  Updated := False;
  CacheLoads := 0;

  while CacheLoads < THUMBNAIL_CACHE_BURST do
  begin
    Index := NextQueuedThumbnailIndex;
    if Index < 0 then
      Break;

    FileName := FThumbnailFiles[Index];
    if not TryLoadCachedThumbnail(Index, FileName) then
      Break;

    Updated := True;
    Inc(CacheLoads);
  end;

  Index := NextQueuedThumbnailIndex;
  if Index >= 0 then
  begin
    FileName := FThumbnailFiles[Index];
    GenerateThumbnail(Index, FileName);
    Updated := True;
  end;

  if Updated then
    Invalidate;

  if NextQueuedThumbnailIndex < 0 then
    FThumbnailTimer.Enabled := False;
end;

procedure TVideoMinerThumbnailBrowser.Close;
begin
  Visible := False;
  if FThumbnailTimer <> nil then
    FThumbnailTimer.Enabled := False;
end;

procedure TVideoMinerThumbnailBrowser.DrawThumbnail(Canvas: TCanvas;
  Index: Integer; const Bounds: TRect);
var
  Bitmap: TBitmap;
  DestRect: TRect;
  Scale: Double;
  TextRect: TRect;
  ThumbHeight: Integer;
  ThumbWidth: Integer;
begin
  Canvas.Brush.Color := TILE_BACKGROUND_COLOR;
  Canvas.FillRect(Bounds);

  EnsureThumbnailSlots;
  if (Index < 0) or (Index >= Length(FThumbnailStates)) then
    Exit;

  case FThumbnailStates[Index] of
    tsReady:
      begin
        Bitmap := FThumbnails[Index];
        if (Bitmap <> nil) and (Bitmap.Width > 0) and (Bitmap.Height > 0) then
        begin
          Scale := Min(Bounds.Width / Bitmap.Width, Bounds.Height / Bitmap.Height);
          ThumbWidth := Max(1, Round(Bitmap.Width * Scale));
          ThumbHeight := Max(1, Round(Bitmap.Height * Scale));
          DestRect := Rect(
            Bounds.Left + (Bounds.Width - ThumbWidth) div 2,
            Bounds.Top + (Bounds.Height - ThumbHeight) div 2,
            Bounds.Left + (Bounds.Width - ThumbWidth) div 2 + ThumbWidth,
            Bounds.Top + (Bounds.Height - ThumbHeight) div 2 + ThumbHeight);
          Canvas.StretchDraw(DestRect, Bitmap);
          Exit;
        end;
      end;
    tsFailed:
      begin
        TextRect := Bounds;
        Canvas.Font.Color := $00808080;
        Canvas.Font.Size := 10;
        DrawText(Canvas.Handle, PChar('Failed'), -1, TextRect,
          DT_CENTER or DT_VCENTER or DT_SINGLELINE);
        Exit;
      end;
    tsQueued:
      begin
        TextRect := Bounds;
        Canvas.Font.Color := $00808080;
        Canvas.Font.Size := 10;
        DrawText(Canvas.Handle, PChar('Loading'), -1, TextRect,
          DT_CENTER or DT_VCENTER or DT_SINGLELINE);
        Exit;
      end;
  end;

  QueueThumbnail(Index);
  TextRect := Bounds;
  Canvas.Font.Color := $00909090;
  Canvas.Font.Size := 10;
  DrawText(Canvas.Handle, PChar('Thumbnail'), -1, TextRect,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
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
  if Index = FHoverIndex then
  begin
    Canvas.Pen.Color := TILE_HOVER_BORDER_COLOR;
    Canvas.Pen.Width := 4;
  end
  else
  begin
    Canvas.Pen.Color := TILE_BORDER_COLOR;
    Canvas.Pen.Width := 1;
  end;
  Canvas.Rectangle(Bounds);
  Canvas.Pen.Width := 1;

  TextRect := Rect(Bounds.Left + 1, Bounds.Top + 1, Bounds.Right - 1,
    Bounds.Bottom - NAME_BAND_HEIGHT);
  DrawThumbnail(Canvas, Index, TextRect);

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
  ZoomByWheel(WheelDelta, MousePos);
  Result := True;
end;

function TVideoMinerThumbnailBrowser.HandleMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := DoMouseWheel(Shift, WheelDelta, MousePos);
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
  TotalWidth := Cols * FTileWidth + Max(0, Cols - 1) * TILE_GAP;
  LeftStart := Max(TILE_MARGIN, (ClientWidth - TotalWidth) div 2);

  for I := 0 to Count - 1 do
  begin
    Row := I div Cols;
    Col := I mod Cols;
    FTileRects[I] := Rect(
      LeftStart + Col * (FTileWidth + TILE_GAP),
      TILE_MARGIN + Row * (FTileHeight + TILE_GAP) - FScrollOffset,
      LeftStart + Col * (FTileWidth + TILE_GAP) + FTileWidth,
      TILE_MARGIN + Row * (FTileHeight + TILE_GAP) + FTileHeight -
        FScrollOffset);
  end;
end;

procedure TVideoMinerThumbnailBrowser.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHoverIndex >= 0 then
  begin
    FHoverIndex := -1;
    Cursor := crDefault;
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
  if NewHoverIndex >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if FHoverIndex <> NewHoverIndex then
  begin
    FHoverIndex := NewHoverIndex;
    Invalidate;
  end;
end;

procedure TVideoMinerThumbnailBrowser.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  FileName: string;
  Index: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbRight then
  begin
    Close;
    Exit;
  end;

  if (Button <> mbLeft) or (FMediaList = nil) then
    Exit;

  Index := HitTile(Point(X, Y));
  if Index < 0 then
    Exit;

  FileName := FMediaList.FileAt(Index);
  if (FileName <> '') and Assigned(FOnSelected) then
    FOnSelected(Self, Index, FileName);
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
  if (FThumbnailTimer <> nil) and (NextQueuedThumbnailIndex >= 0) then
    FThumbnailTimer.Enabled := True;
  Invalidate;
end;

procedure TVideoMinerThumbnailBrowser.Paint;
var
  I: Integer;
  TextRect: TRect;
begin
  Canvas.Brush.Color := BROWSER_BACKGROUND_COLOR;
  Canvas.FillRect(ClientRect);

  EnsureThumbnailSlots;
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
  TileTop := TILE_MARGIN + Row * (FTileHeight + TILE_GAP);
  TileBottom := TileTop + FTileHeight;
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
  EnsureThumbnailSlots;
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

procedure TVideoMinerThumbnailBrowser.ZoomByWheel(WheelDelta: Integer;
  const MousePos: TPoint);
var
  AnchorClient: TPoint;
  AnchorIndex: Integer;
  AnchorOffset: Integer;
  AnchorRow: Integer;
  NewHeight: Integer;
  NewWidth: Integer;
begin
  if WheelDelta = 0 then
    Exit;

  AnchorClient := ScreenToClient(MousePos);
  AnchorIndex := HitTile(AnchorClient);
  if AnchorIndex < 0 then
    AnchorIndex := FHoverIndex;
  if (AnchorIndex < 0) and (FMediaList <> nil) then
    AnchorIndex := FMediaList.CurrentIndex;

  AnchorOffset := AnchorClient.Y;
  if AnchorIndex >= 0 then
    AnchorOffset := AnchorClient.Y - FTileRects[AnchorIndex].Top;

  NewWidth := FTileWidth;
  if WheelDelta > 0 then
    Inc(NewWidth, TILE_ZOOM_STEP)
  else
    Dec(NewWidth, TILE_ZOOM_STEP);
  NewWidth := Max(TILE_MIN_WIDTH, Min(TILE_MAX_WIDTH, NewWidth));
  if NewWidth = FTileWidth then
    Exit;

  NewHeight := Max(1, Round(NewWidth * TILE_HEIGHT / TILE_WIDTH));
  FTileWidth := NewWidth;
  FTileHeight := NewHeight;

  if AnchorIndex >= 0 then
  begin
    AnchorRow := AnchorIndex div ColumnCount;
    FScrollOffset := TILE_MARGIN + AnchorRow * (FTileHeight + TILE_GAP) -
      AnchorClient.Y + AnchorOffset;
  end;

  ClampScrollOffset;
  LayoutTiles;
  Invalidate;
end;
procedure TVideoMinerThumbnailBrowser.WMEraseBkgnd(
  var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TVideoMinerThumbnailBrowser.WMNCHitTest(var Message: TWMNCHitTest);
var
  ClientPoint: TPoint;
  BorderSize: Integer;
begin
  inherited;
  if Message.Result <> HTCLIENT then
    Exit;

  BorderSize := VIDEO_MINER_RESIZE_BORDER;
  ClientPoint := ScreenToClient(Point(Message.XPos, Message.YPos));
  if (ClientPoint.X < BorderSize) or
     (ClientPoint.X >= ClientWidth - BorderSize) or
     (ClientPoint.Y >= ClientHeight - BorderSize) then
    Message.Result := HTTRANSPARENT;
end;

end.
