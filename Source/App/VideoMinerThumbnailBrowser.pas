unit VideoMinerThumbnailBrowser;

// 同一フォルダ内の動画を見渡すサムネイル一覧モードを描画する。
// 表示中タイルのサムネイルを少しずつ生成し、クリック選択をメインフォームへ通知する。

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Math, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder, FFmpegDecoderTypes,
  VideoMinerMediaList, VideoMinerSettings, VideoMinerThumbnailCache, VideoMinerWindowChrome;

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
    FPreviewBitmap : TBitmap;            // hover プレビュー中に表示する一時画像
    FPreviewDecoder : TFFmpegDecoder;    // hover 本プレビュー用の一時デコーダ
    FPreviewFileName : string;           // hover 本プレビューで開いているファイル
    FPreviewIndex  : Integer;            // hover プレビュー対象の一覧位置
    FPreviewInfo   : TVideoInfo;         // hover 本プレビュー対象の動画情報
    FPreviewStarted : Boolean;           // hover 本プレビューの初回 seek が済んだか
    FPreviewStep   : Integer;            // hover プレビューの更新回数
    FPreviewTimer  : TTimer;             // hover プレビューを更新するタイマー
    FScrollOffset : Integer;              // タイル一覧の縦スクロール量 px
    FSelectedIndex : Integer;             // キーボード操作で選択中の一覧位置
    FThumbnailFiles  : TArray<string>;    // サムネイル状態が対応するファイル名
    FThumbnailStates : TArray<TVideoMinerThumbnailState>; // サムネイル生成状態
    FThumbnails      : TArray<TBitmap>;   // 生成済みサムネイル画像
    FThumbnailTimer  : TTimer;            // サムネイルを少しずつ生成するタイマー
    FTileHeight      : Integer;           // 現在のタイル高さ px
    FTileWidth       : Integer;           // 現在のタイル幅 px
    FTileRects    : TArray<TRect>;        // 最後にレイアウトした各タイルの表示矩形
    FZoomButtonHover : Integer;           // hover 中のズームボタン方向
    // 現在の幅からタイルの列数を返す
    function ColumnCount: Integer;
    // タイル全体の高さを返す
    function ContentHeight: Integer;
    // スクロール量を有効範囲へ収める
    procedure ClampScrollOffset;
    // 指定位置にあるタイル index を返す
    function HitTile(const Point: TPoint): Integer;
    // 指定位置のタイルをキーボード選択状態にする
    procedure SelectTile(Index: Integer; EnsureVisible: Boolean);
    // 選択中タイルが画面内に入るようスクロールする
    procedure ScrollToSelected;
    // 選択中タイルを指定量だけ移動する
    procedure MoveSelection(Delta: Integer);
    // 選択中タイルを開く
    procedure ActivateSelectedTile;
    // 指定方向のズームボタン矩形を返す
    function ZoomButtonRect(Direction: Integer): TRect;
    // 指定位置にあるズームボタン方向を返す
    function HitZoomButton(const Point: TPoint): Integer;
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
    // hover 本プレビュー用の次フレームを生成する
    function GeneratePreviewFrame(Index: Integer; const FileName: string): Boolean;
    // hover プレビューを開始待ち状態へ戻す
    procedure ResetPreview(Index: Integer);
    // hover プレビューを停止する
    procedure StopPreview;
    // タイマーでサムネイルを 1 枚ずつ生成する
    procedure ThumbnailTimer(Sender: TObject);
    // タイマーで hover プレビューを 1 フレーム進める
    procedure PreviewTimer(Sender: TObject);
    // タイル内にサムネイル画像または生成状態を描く
    procedure DrawThumbnail(Canvas: TCanvas; Index: Integer; const Bounds: TRect);
    // タイル下部に表示するファイル名を描く
    procedure DrawFileName(Canvas: TCanvas; const Bounds: TRect; const FileName: string);
    // 1 つのタイルを描く
    procedure DrawTile(Canvas: TCanvas; Index: Integer; const Bounds: TRect);
    // 右下のサムネイル拡大縮小ボタンを描く
    procedure DrawZoomButtons(Canvas: TCanvas);
    // 表示時に現在ファイルが見える位置へスクロールする
    procedure ScrollToCurrent;
    // ホイール入力で一覧を縦スクロールする
    procedure ScrollByWheel(WheelDelta: Integer);
    // 指定方向へサムネイルサイズを 1 段階変更する
    procedure ZoomByDirection(Direction: Integer);
    // 中央ボタン押下中のホイール入力でサムネイルサイズを拡大縮小する
    procedure ZoomByWheel(WheelDelta: Integer; const MousePos: TPoint);
    // 指定位置を基準にサムネイルサイズを変更する
    procedure ZoomAt(WheelDelta: Integer; const AnchorClient: TPoint);
  protected
    // 背景消去を抑止する
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    // 矢印キーと Enter を一覧操作として受け取れるようにする
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    // サムネイル表示中もフォーム端のリサイズ判定を親フォームへ通す
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    // タイル hover を更新する
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    // 一覧にフォーカスがあるときのキー操作を処理する
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    // 一覧外へ出たら hover を解除する
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    // 通常ホイールでスクロールし、中央ボタン押下中だけ拡大縮小する
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
    // フォーム経由で届いたホイール入力を一覧操作として処理する
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    // フォーム経由で届いたキー入力を一覧操作として処理する
    function HandleKeyDown(var Key: Word; Shift: TShiftState): Boolean;
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
  TILE_SELECTED_BORDER_COLOR = $0046FF72; // キーボード選択中タイルの強調枠色
  TILE_HOVER_BORDER_COLOR   = $00FFCC66; // hover 中タイルの強調枠色
  TILE_BORDER_COLOR         = $00404040; // 通常タイルの枠色
  TILE_WIDTH                = 220;       // タイルの基本幅 px
  TILE_HEIGHT               = 132;       // タイルの基本高さ px
  TILE_MIN_WIDTH            = 150;       // タイルの最小幅 px
  TILE_MAX_WIDTH            = 380;       // タイルの最大幅 px
  TILE_ZOOM_STEP            = 24;        // ホイール 1 ノッチあたりのサイズ変更量 px
  TILE_SCROLL_STEP          = 120;       // ホイール 1 ノッチあたりの縦スクロール量 px
  ZOOM_BUTTON_SIZE          = 38;        // 拡大縮小ボタンの直径 px
  ZOOM_BUTTON_GAP           = 10;        // 拡大縮小ボタン同士の間隔 px
  ZOOM_BUTTON_COLOR         = $00383838; // 拡大縮小ボタンの背景色
  ZOOM_BUTTON_HOVER_COLOR   = $00585858; // hover 中の拡大縮小ボタン背景色
  ZOOM_BUTTON_BORDER_COLOR  = $00C8C8C8; // 拡大縮小ボタンの枠色
  TILE_GAP                  = 14;        // タイル間の余白 px
  TILE_MARGIN               = 22;        // 一覧外周の余白 px
  NAME_BAND_HEIGHT          = 28;        // ファイル名を重ねる帯の高さ px
  THUMBNAIL_TIMER_INTERVAL  = 80;        // サムネイルを 1 枚ずつ生成する間隔 ms
  THUMBNAIL_MAX_WIDTH       = 320;       // 生成サムネイルの最大幅 px
  THUMBNAIL_MAX_HEIGHT      = 180;       // 生成サムネイルの最大高さ px
  THUMBNAIL_CACHE_BURST     = 24;        // 1 tick で読み込むキャッシュ済みサムネイル数
  PREVIEW_START_DELAY_MS    = 0;         // hover 後にプレビュー開始を待つ時間 ms
  PREVIEW_FRAME_INTERVAL_MS = 40;        // hover 本プレビューの更新間隔 ms
  PREVIEW_START_PERCENT     = 10;        // hover 本プレビューの開始位置 %
  HOVER_REAL_PREVIEW_ENABLED = True;     // False にすると入口を塞いでホバープレビューを止める

constructor TVideoMinerThumbnailBrowser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  Visible := False;
  FCurrentIndex := -1;
  FHoverIndex := -1;
  FPreviewIndex := -1;
  FPreviewStarted := False;
  FPreviewStep := -1;
  FSelectedIndex := -1;
  FZoomButtonHover := 0;
  FTileWidth := LoadThumbnailTileWidth(TILE_WIDTH, TILE_MIN_WIDTH,
    TILE_MAX_WIDTH);
  FTileHeight := Max(1, Round(FTileWidth * TILE_HEIGHT / TILE_WIDTH));
  FThumbnailTimer := TTimer.Create(Self);
  FThumbnailTimer.Enabled := False;
  FThumbnailTimer.Interval := THUMBNAIL_TIMER_INTERVAL;
  FThumbnailTimer.OnTimer := ThumbnailTimer;
  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Interval := PREVIEW_START_DELAY_MS;
  FPreviewTimer.OnTimer := PreviewTimer;
end;

destructor TVideoMinerThumbnailBrowser.Destroy;
begin
  StopPreview;
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
  StopPreview;
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

function TVideoMinerThumbnailBrowser.GeneratePreviewFrame(Index: Integer;
  const FileName: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
  Decoded: Boolean;
  Dest: TBitmap;
  DurationMs: Integer;
  ErrorMessage: string;
  PositionMs: Integer;
  Scale: Double;
  Source: TBitmap;
  StartMs: Integer;
  ThumbHeight: Integer;
  ThumbWidth: Integer;
begin
  Result := False;
  if (not HOVER_REAL_PREVIEW_ENABLED) or (Index < 0) or (FileName = '') then
    Exit;

  if (FPreviewDecoder = nil) or (FPreviewFileName <> FileName) then
  begin
    FreeAndNil(FPreviewDecoder);
    FillChar(FPreviewInfo, SizeOf(FPreviewInfo), 0);
    FPreviewFileName := '';
    FPreviewStarted := False;

    FPreviewDecoder := TFFmpegDecoder.Create;
    if not FPreviewDecoder.Open(FileName, FPreviewInfo, ErrorMessage) then
    begin
      FreeAndNil(FPreviewDecoder);
      Exit;
    end;
    FPreviewFileName := FileName;
  end;

  if (FPreviewInfo.Width <= 0) or (FPreviewInfo.Height <= 0) then
    Exit;

  Source := TBitmap.Create;
  try
    try
      Source.PixelFormat := pf32bit;
    Source.SetSize(FPreviewInfo.Width, FPreviewInfo.Height);
      if FPreviewInfo.Height > 1 then
        BufferStride := Abs(NativeInt(Source.ScanLine[1]) -
          NativeInt(Source.ScanLine[0]))
      else
        BufferStride := FPreviewInfo.Width * 4;
      Buffer := Source.ScanLine[FPreviewInfo.Height - 1];
      if (Buffer = nil) or (BufferStride <= 0) then
        Exit;

      DurationMs := Round(FPreviewInfo.DurationSec * 1000);
      if DurationMs <= 0 then
        StartMs := 0
      else
        StartMs := Min(DurationMs - 1, Max(0,
          MulDiv(DurationMs, PREVIEW_START_PERCENT, 100)));

      Decoded := False;
      if FPreviewStarted then
      begin
        Decoded := FPreviewDecoder.DecodeNextFrameToBgrx32(Buffer,
          BufferStride, PositionMs, ErrorMessage);
        if not Decoded then
          FPreviewStarted := False;
      end;

      if not Decoded then
      begin
        Decoded := FPreviewDecoder.DecodeFrameToBgrx32(StartMs, Buffer,
          BufferStride, ErrorMessage);
        FPreviewStarted := Decoded;
      end;

      if not Decoded then
        Exit;

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
        FPreviewBitmap.Free;
        FPreviewBitmap := Dest;
        Dest := nil;
        Result := True;
      finally
        Dest.Free;
      end;
    except
      Result := False;
    end;
  finally
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

procedure TVideoMinerThumbnailBrowser.PreviewTimer(Sender: TObject);
var
  FileName: string;
begin
  if (not Visible) or (FMediaList = nil) or (FPreviewIndex < 0) or
     (FPreviewIndex <> FHoverIndex) or (FPreviewIndex >= FMediaList.Count) then
  begin
    StopPreview;
    Exit;
  end;

  Inc(FPreviewStep);
  FileName := FMediaList.FileAt(FPreviewIndex);
  if GeneratePreviewFrame(FPreviewIndex, FileName) then
  begin
    FPreviewTimer.Interval := PREVIEW_FRAME_INTERVAL_MS;
    Invalidate;
  end
  else
    StopPreview;
end;

procedure TVideoMinerThumbnailBrowser.ResetPreview(Index: Integer);
begin
  if (FPreviewIndex = Index) and
     ((FPreviewBitmap <> nil) or
      ((FPreviewTimer <> nil) and FPreviewTimer.Enabled)) then
    Exit;

  StopPreview;
  if Index < 0 then
    Exit;

  FPreviewIndex := Index;
  FPreviewStep := -1;
  if PREVIEW_START_DELAY_MS <= 0 then
  begin
    PreviewTimer(FPreviewTimer);
    if (FPreviewIndex = Index) and (FPreviewTimer <> nil) then
    begin
      FPreviewTimer.Interval := PREVIEW_FRAME_INTERVAL_MS;
      FPreviewTimer.Enabled := True;
    end;
  end
  else if FPreviewTimer <> nil then
  begin
    FPreviewTimer.Interval := PREVIEW_START_DELAY_MS;
    FPreviewTimer.Enabled := True;
  end;
end;

procedure TVideoMinerThumbnailBrowser.StopPreview;
begin
  if FPreviewTimer <> nil then
    FPreviewTimer.Enabled := False;
  FPreviewIndex := -1;
  FPreviewStarted := False;
  FPreviewStep := -1;
  FPreviewFileName := '';
  FillChar(FPreviewInfo, SizeOf(FPreviewInfo), 0);
  FreeAndNil(FPreviewDecoder);
  FreeAndNil(FPreviewBitmap);
end;

procedure TVideoMinerThumbnailBrowser.Close;
begin
  StopPreview;
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

  if (Index = FHoverIndex) and (Index = FPreviewIndex) and
     (FPreviewBitmap <> nil) and
     (FPreviewBitmap.Width > 0) and (FPreviewBitmap.Height > 0) then
  begin
    Scale := Min(Bounds.Width / FPreviewBitmap.Width,
      Bounds.Height / FPreviewBitmap.Height);
    ThumbWidth := Max(1, Round(FPreviewBitmap.Width * Scale));
    ThumbHeight := Max(1, Round(FPreviewBitmap.Height * Scale));
    DestRect := Rect(
      Bounds.Left + (Bounds.Width - ThumbWidth) div 2,
      Bounds.Top + (Bounds.Height - ThumbHeight) div 2,
      Bounds.Left + (Bounds.Width - ThumbWidth) div 2 + ThumbWidth,
      Bounds.Top + (Bounds.Height - ThumbHeight) div 2 + ThumbHeight);
    Canvas.StretchDraw(DestRect, FPreviewBitmap);
    Exit;
  end;
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
  BorderRect: TRect;
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
    Canvas.Pen.Width := 4;
    Canvas.Rectangle(Bounds);
    Canvas.Brush.Style := bsSolid;
    Canvas.Pen.Width := 1;
  end;

  if Index = FSelectedIndex then
  begin
    BorderRect := Bounds;
    if Index = FCurrentIndex then
      InflateRect(BorderRect, -5, -5);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := TILE_SELECTED_BORDER_COLOR;
    Canvas.Pen.Width := 3;
    Canvas.Rectangle(BorderRect);
    Canvas.Brush.Style := bsSolid;
    Canvas.Pen.Width := 1;
  end;
end;

procedure TVideoMinerThumbnailBrowser.DrawZoomButtons(Canvas: TCanvas);
var
  Direction: Integer;
  R: TRect;
  TextRect: TRect;
begin
  for Direction in [1, -1] do
  begin
    R := ZoomButtonRect(Direction);
    if Direction = FZoomButtonHover then
      Canvas.Brush.Color := ZOOM_BUTTON_HOVER_COLOR
    else
      Canvas.Brush.Color := ZOOM_BUTTON_COLOR;
    Canvas.Pen.Color := ZOOM_BUTTON_BORDER_COLOR;
    Canvas.Pen.Width := 1;
    Canvas.Ellipse(R);

    TextRect := R;
    Canvas.Font.Color := clWhite;
    Canvas.Font.Size := 18;
    Canvas.Font.Style := [fsBold];
    if Direction > 0 then
      DrawText(Canvas.Handle, PChar('+'), -1, TextRect,
        DT_CENTER or DT_VCENTER or DT_SINGLELINE)
    else
      DrawText(Canvas.Handle, PChar('-'), -1, TextRect,
        DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    Canvas.Font.Style := [];
  end;
end;

function TVideoMinerThumbnailBrowser.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if (ssMiddle in Shift) or (GetKeyState(VK_MBUTTON) < 0) then
    ZoomByWheel(WheelDelta, MousePos)
  else
    ScrollByWheel(WheelDelta);
  Result := True;
end;

function TVideoMinerThumbnailBrowser.HandleMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVideoMinerThumbnailBrowser.HandleKeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
var
  Cols: Integer;
begin
  Result := False;
  if Shift <> [] then
    Exit;

  Cols := ColumnCount;
  case Key of
    VK_LEFT:
      MoveSelection(-1);
    VK_RIGHT:
      MoveSelection(1);
    VK_UP:
      MoveSelection(-Cols);
    VK_DOWN:
      MoveSelection(Cols);
    VK_RETURN:
      ActivateSelectedTile;
  else
    Exit;
  end;

  Key := 0;
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

function TVideoMinerThumbnailBrowser.HitZoomButton(const Point: TPoint): Integer;
var
  Center: TPoint;
  Direction: Integer;
  Radius: Integer;
  R: TRect;
begin
  Result := 0;
  Radius := ZOOM_BUTTON_SIZE div 2;
  for Direction in [1, -1] do
  begin
    R := ZoomButtonRect(Direction);
    if not PtInRect(R, Point) then
      Continue;

    Center := System.Types.Point((R.Left + R.Right) div 2,
      (R.Top + R.Bottom) div 2);
    if Sqr(Point.X - Center.X) + Sqr(Point.Y - Center.Y) <= Sqr(Radius) then
    begin
      Result := Direction;
      Exit;
    end;
  end;
end;

function TVideoMinerThumbnailBrowser.ZoomButtonRect(Direction: Integer): TRect;
var
  Bottom: Integer;
  Left: Integer;
begin
  Left := ClientWidth - TILE_MARGIN - ZOOM_BUTTON_SIZE;
  Bottom := ClientHeight - TILE_MARGIN;
  if Direction > 0 then
    Dec(Bottom, ZOOM_BUTTON_SIZE + ZOOM_BUTTON_GAP);
  Result := Rect(Left, Bottom - ZOOM_BUTTON_SIZE, Left + ZOOM_BUTTON_SIZE,
    Bottom);
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
  if (FHoverIndex >= 0) or (FZoomButtonHover <> 0) then
  begin
    FHoverIndex := -1;
    FZoomButtonHover := 0;
    StopPreview;
    Cursor := crDefault;
    Invalidate;
  end;
end;

procedure TVideoMinerThumbnailBrowser.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  HandleKeyDown(Key, Shift);
end;

procedure TVideoMinerThumbnailBrowser.MouseMove(Shift: TShiftState; X,
  Y: Integer);
var
  NewHoverIndex: Integer;
  NewZoomButtonHover: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  NewZoomButtonHover := HitZoomButton(Point(X, Y));
  if NewZoomButtonHover <> 0 then
    NewHoverIndex := -1
  else
    NewHoverIndex := HitTile(Point(X, Y));

  if (NewHoverIndex >= 0) or (NewZoomButtonHover <> 0) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;

  if (FHoverIndex <> NewHoverIndex) or
     (FZoomButtonHover <> NewZoomButtonHover) then
  begin
    FHoverIndex := NewHoverIndex;
    FZoomButtonHover := NewZoomButtonHover;
    Invalidate;
    Update;
    ResetPreview(FHoverIndex);
  end
  else if (FHoverIndex >= 0) and (FZoomButtonHover = 0) and
          (FPreviewIndex <> FHoverIndex) then
    ResetPreview(FHoverIndex);
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

  if Button <> mbLeft then
    Exit;

  Index := HitZoomButton(Point(X, Y));
  if Index <> 0 then
  begin
    ZoomByDirection(Index);
    Exit;
  end;

  if FMediaList = nil then
    Exit;

  Index := HitTile(Point(X, Y));
  if Index < 0 then
    Exit;

  SelectTile(Index, False);
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
  FSelectedIndex := FCurrentIndex;
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
    DrawZoomButtons(Canvas);
    Exit;
  end;

  for I := 0 to Length(FTileRects) - 1 do
  begin
    if (FTileRects[I].Bottom < 0) or (FTileRects[I].Top > ClientHeight) then
      Continue;
    DrawTile(Canvas, I, FTileRects[I]);
  end;
  DrawZoomButtons(Canvas);
end;

procedure TVideoMinerThumbnailBrowser.Resize;
begin
  inherited Resize;
  ClampScrollOffset;
  LayoutTiles;
end;

procedure TVideoMinerThumbnailBrowser.ActivateSelectedTile;
var
  FileName: string;
begin
  if (FMediaList = nil) or (FSelectedIndex < 0) or
     (FSelectedIndex >= FMediaList.Count) then
    Exit;

  FileName := FMediaList.FileAt(FSelectedIndex);
  if (FileName <> '') and Assigned(FOnSelected) then
    FOnSelected(Self, FSelectedIndex, FileName);
end;

procedure TVideoMinerThumbnailBrowser.MoveSelection(Delta: Integer);
var
  NewIndex: Integer;
begin
  if (FMediaList = nil) or (FMediaList.Count <= 0) then
    Exit;

  NewIndex := FSelectedIndex;
  if NewIndex < 0 then
    NewIndex := FCurrentIndex;
  if NewIndex < 0 then
    NewIndex := 0;
  NewIndex := Max(0, Min(FMediaList.Count - 1, NewIndex + Delta));
  SelectTile(NewIndex, True);
end;

procedure TVideoMinerThumbnailBrowser.ScrollToSelected;
var
  Cols: Integer;
  Row: Integer;
  TileBottom: Integer;
  TileTop: Integer;
begin
  if (FMediaList = nil) or (FSelectedIndex < 0) then
    Exit;

  Cols := ColumnCount;
  Row := FSelectedIndex div Cols;
  TileTop := TILE_MARGIN + Row * (FTileHeight + TILE_GAP);
  TileBottom := TileTop + FTileHeight;
  if TileTop < FScrollOffset + TILE_MARGIN then
    FScrollOffset := TileTop - TILE_MARGIN
  else if TileBottom > FScrollOffset + ClientHeight - TILE_MARGIN then
    FScrollOffset := TileBottom - ClientHeight + TILE_MARGIN;
  ClampScrollOffset;
  LayoutTiles;
end;

procedure TVideoMinerThumbnailBrowser.SelectTile(Index: Integer;
  EnsureVisible: Boolean);
begin
  if (FMediaList = nil) or (FMediaList.Count <= 0) then
    Index := -1
  else
    Index := Max(0, Min(FMediaList.Count - 1, Index));

  if FSelectedIndex = Index then
    Exit;

  FSelectedIndex := Index;
  if EnsureVisible then
    ScrollToSelected;
  Invalidate;
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
  StopPreview;
  FMediaList := MediaList;
  if FMediaList <> nil then
    FCurrentIndex := FMediaList.CurrentIndex
  else
    FCurrentIndex := -1;
  if FMediaList = nil then
    FSelectedIndex := -1
  else if FSelectedIndex < 0 then
    FSelectedIndex := FCurrentIndex
  else if FSelectedIndex >= FMediaList.Count then
    FSelectedIndex := FMediaList.Count - 1;
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

procedure TVideoMinerThumbnailBrowser.ScrollByWheel(WheelDelta: Integer);
begin
  if WheelDelta = 0 then
    Exit;

  FScrollOffset := FScrollOffset - MulDiv(WheelDelta, TILE_SCROLL_STEP,
    WHEEL_DELTA);
  ClampScrollOffset;
  LayoutTiles;
  Invalidate;
end;

procedure TVideoMinerThumbnailBrowser.ZoomByDirection(Direction: Integer);
begin
  if Direction > 0 then
    ZoomAt(WHEEL_DELTA, Point(ClientWidth div 2, ClientHeight div 2))
  else if Direction < 0 then
    ZoomAt(-WHEEL_DELTA, Point(ClientWidth div 2, ClientHeight div 2));
end;

procedure TVideoMinerThumbnailBrowser.ZoomByWheel(WheelDelta: Integer;
  const MousePos: TPoint);
begin
  ZoomAt(WheelDelta, ScreenToClient(MousePos));
end;

procedure TVideoMinerThumbnailBrowser.ZoomAt(WheelDelta: Integer;
  const AnchorClient: TPoint);
var
  AnchorIndex: Integer;
  AnchorOffset: Integer;
  AnchorRow: Integer;
  NewHeight: Integer;
  NewWidth: Integer;
begin
  if WheelDelta = 0 then
    Exit;

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
  SaveThumbnailTileWidth(FTileWidth, TILE_MIN_WIDTH, TILE_MAX_WIDTH);

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

procedure TVideoMinerThumbnailBrowser.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS or DLGC_WANTALLKEYS;
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
