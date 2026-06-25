unit VideoMinerVideoView;

// メインフォームや controller から動画表示サーフェスを扱うための薄い窓口。
// フレームデコード先の準備、サーフェスへの表示、overlay 状態とイベントの中継を担当する。

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Graphics, FFmpegDecoder, VideoMinerBitmapRotation, VideoMinerFrameCheck,
  VideoMinerDebugLog, VideoMinerOverlay, VideoMinerSettings,
  VideoMinerVideoSurface, FFmpegD3D11TextureProbe;

type
  TVideoMinerVideoView = class
  private
    FLoopFrameCache          : array[0..3] of TBitmap;  // ループ戻り直後に見せる先頭側フレーム列
    FLoopFrameCacheCount     : Integer;                 // キャッシュ済みループ先頭フレーム数
    FLoopFrameCacheStartMs   : Integer;                 // キャッシュ対象のループ開始位置 ms
    FLoopFrameCaptureActive  : Boolean;                 // ループ先頭フレームを学習中か
    FDecodeScratch           : TBitmap;                 // 表示せずに次フレームを確認するための作業用 Bitmap
    FDisplayRotationOffset   : Integer;                 // ユーザー操作で追加する表示回転角度
    FShownFrameCache         : TBitmap;                 // 直近の明示表示フレームを即時再表示するためのキャッシュ
    FShownFrameCachePosition : Integer;                 // キャッシュしている明示表示フレームの位置 ms
    FSurface                 : TVideoMinerVideoSurface; // 実際の動画表示と overlay 描画を持つサーフェス
    // ループ先頭フレームキャッシュを破棄する
    procedure ClearLoopFrameCache;
    // 再生中に表示されたフレームをループ先頭キャッシュへ追加する
    procedure StoreLoopFrameCache(PositionMs: Integer);
    // 現在の表示フレームを指定位置の即時再表示用に保存する
    procedure CacheShownFrame(PositionMs: Integer);
    // 現在の表示フレームキャッシュを破棄する
    procedure ClearShownFrameCache;
    // metadata 回転とユーザー操作の追加回転を合成した角度を返す
    function DisplayRotationDegrees(SourceDegrees: Integer): Integer;
    // フォーム側で親子関係やフォーカス対象として扱うサーフェスを返す
    function GetSurfaceControl: TWinControl;
    // 現在表示中の動画フレーム Bitmap を返す
    function GetCurrentFrameBitmap: TBitmap;
    // Bitmap を BGRX32 デコード先として使える状態にする
    function PrepareBitmapFrameBuffer(Bitmap: TBitmap; Width, Height: Integer;
      out Buffer: Pointer; out BufferStride: Integer): Boolean;
    // 表示サーフェスを BGRX32 デコード先として使える状態にする
    function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
      out BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 指定位置のキャッシュがあれば、デコード完了を待たずに表示する
    function TryPresentCachedFrame(PositionMs: Integer): Boolean;
    // ボスが来たモードの表示状態をサーフェスへ渡す
    procedure SetBossMode(Value: Boolean);
    // 次動画へ移動できるかを overlay 表示へ渡す
    procedure SetCanNavigateNext(Value: Boolean);
    // 前動画へ移動できるかを overlay 表示へ渡す
    procedure SetCanNavigatePrevious(Value: Boolean);
    // Check 操作の有効状態を overlay 表示へ渡す
    procedure SetCheckEnabled(Value: Boolean);
    // 表示用チャプター位置を overlay 表示へ渡す
    procedure SetChapters(const Value: TVideoMinerOverlayChapters);
    // 終端到達時動作の表示文字列を overlay 表示へ渡す
    procedure SetEndActionText(const Value: string);
    // 全画面状態をサーフェスへ渡す
    procedure SetFullScreen(Value: Boolean);
    // 終端到達時動作ボタンのクリック先を設定する
    procedure SetOnEndActionClick(Value: TNotifyEvent);
    // 先頭フレームボタンのクリック先を設定する
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    // 全画面ボタンのクリック先を設定する
    procedure SetOnFullScreenClick(Value: TNotifyEvent);
    // 末尾フレームボタンのクリック先を設定する
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    // ミュート状態を overlay 表示へ渡す
    procedure SetMuted(Value: Boolean);
    // ボスが来たモード解除ボタンのクリック先を設定する
    procedure SetOnBossExitClick(Value: TNotifyEvent);
    // ボスが来たモード発動ジェスチャーの通知先を設定する
    procedure SetOnBossGesture(Value: TNotifyEvent);
    // チャプター追加ボタンのクリック先を設定する
    procedure SetOnAddChapterClick(Value: TNotifyEvent);
    // Check ボタンのクリック先を設定する
    procedure SetOnCheckClick(Value: TNotifyEvent);
    // チャプター削除ボタンのクリック先を設定する
    procedure SetOnDeleteChapterClick(Value: TNotifyEvent);
    // ミュートボタンのクリック先を設定する
    procedure SetOnMuteClick(Value: TNotifyEvent);
    // 次動画ボタンのクリック先を設定する
    procedure SetOnNavigateNextClick(Value: TNotifyEvent);
    // 前動画ボタンのクリック先を設定する
    procedure SetOnNavigatePreviousClick(Value: TNotifyEvent);
    // 再生速度ボタンのクリック先を設定する
    procedure SetOnPlaybackRateClick(Value: TNotifyEvent);
    // 再生/一時停止ボタンのクリック先を設定する
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
    // 動画面右クリックの通知先を設定する
    procedure SetOnSurfaceRightClick(Value: TNotifyEvent);
    // シークバー右クリックのチャプタートグル通知先を設定する
    procedure SetOnToggleChapterClick(Value: TVideoMinerOverlaySeekEvent);
    // シークバー操作の通知先を設定する
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    // シークバー上ホイール操作の通知先を設定する
    procedure SetOnSeekByWheel(Value: TVideoMinerOverlaySeekEvent);
    // シークバー hover プレビュー要求先を設定する
    procedure SetOnSeekHoverPreview(Value: TVideoMinerOverlaySeekHoverEvent);
    // シークバー hover プレビュー終了通知先を設定する
    procedure SetOnSeekHoverPreviewEnd(Value: TNotifyEvent);
    // 10 秒戻しボタンのクリック先を設定する
    procedure SetOnSkipBackwardClick(Value: TNotifyEvent);
    // 10 秒進みボタンのクリック先を設定する
    procedure SetOnSkipForwardClick(Value: TNotifyEvent);
    // 音量変更の通知先を設定する
    procedure SetOnVolumeChange(Value: TVideoMinerOverlayVolumeEvent);
    // 再生中かどうかを overlay 表示へ渡す
    procedure SetPlaybackActive(Value: Boolean);
    // 再生速度の表示文字列を overlay 表示へ渡す
    procedure SetPlaybackRateText(const Value: string);
    // 現在の動画が alpha を持つかを表示面へ渡す
    procedure SetSourceHasAlpha(Value: Boolean);
    // Check 中ホイールシークの 1 ステップ幅を設定する
    procedure SetSeekWheelFrameStepMs(Value: Integer);
    // 90% セーフエリア確認枠の表示状態を設定する
    procedure SetSafeAreaVisible(Value: Boolean);
    // 音量パーセントを overlay 表示へ渡す
    procedure SetVolumePercent(Value: Integer);
  public
    // 既存の TImage 配置を引き継いで専用サーフェスへ差し替える
    constructor Create(Image: TImage);
    // サーフェスと scratch frame を解放する
    destructor Destroy; override;
    // 表示フレームと scratch frame を空にする
    procedure Clear;
    // 読み込み中インジケータを表示し始める
    procedure BeginLoadingIndicator;
    // 次の明示デコード前に表示フレームキャッシュだけを空にする
    procedure ClearFrameCache;
    // 次に表示されるループ先頭側フレームを小さくキャッシュし始める
    procedure BeginLoopFrameCacheCapture(StartMs: Integer;
      CaptureCurrentFrame: Boolean = False);
    // 表示だけを90度ずつ回転し、以降の再生フレームにも反映する
    procedure RotateDisplay90;
    // ボスが来たモード中のヘルプページを前後へ切り替える
    procedure ChangeBossHelpPage(Delta: Integer);
    // 指定位置のフレームをデコードし、必要なら表示へ反映する
    function ShowFrameAt(Decoder: TFFmpegDecoder; PositionMs: Integer;
      out ErrorMessage: string; PresentFrame: Boolean = True;
      FastSeek: Boolean = False): Boolean;
    // キャッシュ済みループ先頭フレームがあれば即時表示する
    function TryPresentLoopFrameCache(StartMs: Integer): Boolean;
    // 指定位置のフレームを任意 Bitmap へデコードする
    function DecodeFrameToBitmap(Decoder: TFFmpegDecoder; PositionMs: Integer;
      Bitmap: TBitmap; out ErrorMessage: string; FastSeek: Boolean = False): Boolean;
    // 次フレームを読み、必要なら表示用 BGRX32 へ変換する
    function DecodeNextFrame(Decoder: TFFmpegDecoder; ConvertFrame: Boolean;
      out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 次フレームを画面には出さず scratch frame へデコードする
    function DecodeNextFrameToScratch(Decoder: TFFmpegDecoder;
      out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在表示中フレームの四隅が暗いか返す
    function CurrentFrameCornersMostlyDark: Boolean;
    // 現在表示中フレームの簡易署名を返す
    function CurrentFrameSignature(out Signature: TVideoMinerFrameSignature): Boolean;
    // サーフェス上のホイール操作をズーム/シークとして処理する
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;MousePos: TPoint): Boolean;
    // 次フレームを読み込んで表示する
    function ShowNextFrame(Decoder: TFFmpegDecoder; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // scratch frame にあるフレームを現在表示へ反映する
    function PresentScratchFrame(out ErrorMessage: string): Boolean;
    // サーフェスの現在 Bitmap を通常の描画タイミングで表示する
    procedure Present(Bitmap: TBitmap);
    // サーフェスの現在 Bitmap を即時表示する
    procedure PresentImmediate(Bitmap: TBitmap);
    // overlay のシーク進捗を更新する
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    // シークバー hover 位置の小型プレビューを表示する
    procedure SetSeekHoverPreview(Bitmap: TBitmap; PositionMs: Integer; const AnchorPoint: TPoint);
    // シークバー hover プレビューを消す
    procedure ClearSeekHoverPreview;
    // 読み込み中インジケータを消す
    procedure EndLoadingIndicator;
    property BossMode: Boolean write SetBossMode;
    property CanNavigateNext: Boolean write SetCanNavigateNext;
    property CanNavigatePrevious: Boolean write SetCanNavigatePrevious;
    property CheckEnabled: Boolean write SetCheckEnabled;
    property Chapters: TVideoMinerOverlayChapters write SetChapters;
    property EndActionText: string write SetEndActionText;
    property FullScreen: Boolean write SetFullScreen;
    property OnBossExitClick: TNotifyEvent write SetOnBossExitClick;
    property OnBossGesture: TNotifyEvent write SetOnBossGesture;
    property OnAddChapterClick: TNotifyEvent write SetOnAddChapterClick;
    property OnCheckClick: TNotifyEvent write SetOnCheckClick;
    property OnDeleteChapterClick: TNotifyEvent write SetOnDeleteChapterClick;
    property OnEndActionClick: TNotifyEvent write SetOnEndActionClick;
    property OnFirstFrameClick: TNotifyEvent write SetOnFirstFrameClick;
    property OnFullScreenClick: TNotifyEvent write SetOnFullScreenClick;
    property OnLastFrameClick: TNotifyEvent write SetOnLastFrameClick;
    property OnMuteClick: TNotifyEvent write SetOnMuteClick;
    property OnNavigateNextClick: TNotifyEvent write SetOnNavigateNextClick;
    property OnNavigatePreviousClick: TNotifyEvent write SetOnNavigatePreviousClick;
    property OnPlaybackRateClick: TNotifyEvent write SetOnPlaybackRateClick;
    property OnPlayPauseClick: TNotifyEvent write SetOnPlayPauseClick;
    property OnSurfaceRightClick: TNotifyEvent write SetOnSurfaceRightClick;
    property OnToggleChapterClick: TVideoMinerOverlaySeekEvent write SetOnToggleChapterClick;
    property OnSeek: TVideoMinerOverlaySeekEvent write SetOnSeek;
    property OnSeekByWheel: TVideoMinerOverlaySeekEvent write SetOnSeekByWheel;
    property OnSeekHoverPreview: TVideoMinerOverlaySeekHoverEvent write SetOnSeekHoverPreview;
    property OnSeekHoverPreviewEnd: TNotifyEvent write SetOnSeekHoverPreviewEnd;
    property OnSkipBackwardClick: TNotifyEvent write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent write SetOnSkipForwardClick;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent write SetOnVolumeChange;
    property PlaybackActive: Boolean write SetPlaybackActive;
    property PlaybackRateText: string write SetPlaybackRateText;
    property SafeAreaVisible: Boolean write SetSafeAreaVisible;
    property SourceHasAlpha: Boolean write SetSourceHasAlpha;
    property SeekWheelFrameStepMs: Integer write SetSeekWheelFrameStepMs;
    property CurrentFrameBitmap: TBitmap read GetCurrentFrameBitmap;
    property DisplayRotationOffset: Integer read FDisplayRotationOffset;
    property SurfaceControl: TWinControl read GetSurfaceControl;
    property Muted: Boolean write SetMuted;
    property VolumePercent: Integer write SetVolumePercent;
  end;

implementation

function TVideoMinerVideoView.GetSurfaceControl: TWinControl;
begin
  Result := FSurface;
end;

function TVideoMinerVideoView.GetCurrentFrameBitmap: TBitmap;
begin
  Result := nil;
  if FSurface <> nil then
    Result := FSurface.Bitmap;
end;

function TVideoMinerVideoView.CurrentFrameCornersMostlyDark: Boolean;
begin
  Result := (FSurface <> nil) and FSurface.CurrentFrameCornersMostlyDark;
end;

function TVideoMinerVideoView.CurrentFrameSignature(
  out Signature: TVideoMinerFrameSignature): Boolean;
begin
  Result := (FSurface <> nil) and FSurface.CurrentFrameSignature(Signature);
end;

function TVideoMinerVideoView.PrepareBitmapFrameBuffer(Bitmap: TBitmap;
  Width, Height: Integer; out Buffer: Pointer; out BufferStride: Integer): Boolean;
begin
  Buffer := nil;
  BufferStride := 0;
  Result := False;

  if (Bitmap = nil) or (Width <= 0) or (Height <= 0) then
    Exit;

  if Bitmap.PixelFormat <> pf32bit then
    Bitmap.PixelFormat := pf32bit;
  if (Bitmap.Width <> Width) or (Bitmap.Height <> Height) then
    Bitmap.SetSize(Width, Height);

  Buffer := Bitmap.ScanLine[0];
  if Height > 1 then
    BufferStride := NativeInt(Bitmap.ScanLine[1]) - NativeInt(Buffer)
  else
    BufferStride := Width * 4;

  Result := (Buffer <> nil) and (BufferStride <> 0);
end;

function TVideoMinerVideoView.PrepareFrameBuffer(Decoder: TFFmpegDecoder;
  out Buffer: Pointer; out BufferStride: Integer;
  out ErrorMessage: string): Boolean;
begin
  Buffer := nil;
  BufferStride := 0;
  ErrorMessage := '';
  Result := False;

  if (Decoder.Info.Width <= 0) or (Decoder.Info.Height <= 0) then
  begin
    ErrorMessage := 'Video size is invalid.';
    Exit;
  end;

  if (FSurface = nil) or
     (not FSurface.PrepareBgrx32Frame(Decoder.Info.Width, Decoder.Info.Height,
       Buffer, BufferStride)) then
  begin
    ErrorMessage := 'Failed to prepare video surface.';
    Exit;
  end;

  Result := True;
end;

constructor TVideoMinerVideoView.Create(Image: TImage);
var
  I: Integer;
begin
  inherited Create;

  FDecodeScratch := TBitmap.Create;
  FDisplayRotationOffset := 0;
  FLoopFrameCacheCount := 0;
  FLoopFrameCacheStartMs := -1;
  FLoopFrameCaptureActive := False;
  for I := Low(FLoopFrameCache) to High(FLoopFrameCache) do
    FLoopFrameCache[I] := TBitmap.Create;
  FShownFrameCache := TBitmap.Create;
  FShownFrameCachePosition := -1;
  FSurface := TVideoMinerVideoSurface.Create(Image.Owner);
  FSurface.Parent := Image.Parent;
  FSurface.Align := Image.Align;
  FSurface.SetBounds(Image.Left, Image.Top, Image.Width, Image.Height);
  FSurface.Anchors := Image.Anchors;
  FSurface.Visible := Image.Visible;
  FSurface.TabStop := False;
  FSurface.SendToBack;

  Image.Visible := False;
end;

destructor TVideoMinerVideoView.Destroy;
var
  I: Integer;
begin
  FSurface.Free;
  FShownFrameCache.Free;
  for I := Low(FLoopFrameCache) to High(FLoopFrameCache) do
    FLoopFrameCache[I].Free;
  FDecodeScratch.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoView.ClearLoopFrameCache;
var
  I: Integer;
begin
  for I := Low(FLoopFrameCache) to High(FLoopFrameCache) do
    if FLoopFrameCache[I] <> nil then
      FLoopFrameCache[I].SetSize(0, 0);
  FLoopFrameCacheCount := 0;
  FLoopFrameCacheStartMs := -1;
  FLoopFrameCaptureActive := False;
end;

procedure TVideoMinerVideoView.BeginLoopFrameCacheCapture(StartMs: Integer;
  CaptureCurrentFrame: Boolean);
begin
  if StartMs < 0 then
    Exit;

  if FLoopFrameCacheStartMs <> StartMs then
    ClearLoopFrameCache;

  FLoopFrameCacheStartMs := StartMs;
  FLoopFrameCacheCount := 0;
  FLoopFrameCaptureActive := True;
  if CaptureCurrentFrame then
    StoreLoopFrameCache(StartMs);
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'loop_frame_cache_capture_begin start_ms=%d capture_current=%s count=%d',
    [StartMs, BoolToStr(CaptureCurrentFrame, True), FLoopFrameCacheCount]));
{$ENDIF}
end;

procedure TVideoMinerVideoView.StoreLoopFrameCache(PositionMs: Integer);
var
  Index: Integer;
begin
  if (not FLoopFrameCaptureActive) or (FSurface = nil) or
     (FSurface.Bitmap = nil) or (FSurface.Bitmap.Width <= 0) or
     (FSurface.Bitmap.Height <= 0) then
    Exit;

  if (FLoopFrameCacheStartMs >= 0) and
     (PositionMs + 5 < FLoopFrameCacheStartMs) then
    Exit;

  if FLoopFrameCacheCount > High(FLoopFrameCache) then
  begin
    FLoopFrameCaptureActive := False;
    Exit;
  end;

  Index := FLoopFrameCacheCount;
  FLoopFrameCache[Index].Assign(FSurface.Bitmap);
  Inc(FLoopFrameCacheCount);
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'loop_frame_cache_store start_ms=%d position_ms=%d index=%d size=%dx%d',
    [FLoopFrameCacheStartMs, PositionMs, Index,
     FLoopFrameCache[Index].Width, FLoopFrameCache[Index].Height]));
{$ENDIF}

  if FLoopFrameCacheCount > High(FLoopFrameCache) then
    FLoopFrameCaptureActive := False;
end;

procedure TVideoMinerVideoView.CacheShownFrame(PositionMs: Integer);
begin
  if (FSurface = nil) or (FSurface.Bitmap = nil) or
     (FSurface.Bitmap.Width <= 0) or (FSurface.Bitmap.Height <= 0) then
  begin
    FShownFrameCache.SetSize(0, 0);
    FShownFrameCachePosition := -1;
    Exit;
  end;

  FShownFrameCache.Assign(FSurface.Bitmap);
  FShownFrameCachePosition := PositionMs;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('shown_frame_cache_store position_ms=%d size=%dx%d',
    [PositionMs, FShownFrameCache.Width, FShownFrameCache.Height]));
{$ENDIF}
end;

procedure TVideoMinerVideoView.ClearShownFrameCache;
begin
  if FShownFrameCache <> nil then
    FShownFrameCache.SetSize(0, 0);
  FShownFrameCachePosition := -1;
end;

function TVideoMinerVideoView.DisplayRotationDegrees(
  SourceDegrees: Integer): Integer;
begin
  Result := (EffectiveVideoRotationDegrees(SourceDegrees) +
    FDisplayRotationOffset) mod 360;
  if Result < 0 then
    Inc(Result, 360);
end;

procedure TVideoMinerVideoView.ChangeBossHelpPage(Delta: Integer);
begin
  if FSurface <> nil then
    FSurface.ChangeBossHelpPage(Delta);
end;

procedure TVideoMinerVideoView.Clear;
begin
  if FDecodeScratch <> nil then
    FDecodeScratch.SetSize(0, 0);
  ClearShownFrameCache;
  ClearLoopFrameCache;
  if FSurface <> nil then
  begin
    FSurface.SourceHasAlpha := False;
    FSurface.Clear;
  end;
end;

procedure TVideoMinerVideoView.ClearFrameCache;
begin
  ClearShownFrameCache;
end;

procedure TVideoMinerVideoView.RotateDisplay90;
begin
  FDisplayRotationOffset := (FDisplayRotationOffset + 90) mod 360;
  ClearShownFrameCache;
  ClearLoopFrameCache;
end;

function TVideoMinerVideoView.TryPresentCachedFrame(PositionMs: Integer): Boolean;
begin
  Result := (FSurface <> nil) and (FShownFrameCache <> nil) and
    (FShownFrameCachePosition = PositionMs) and
    (FShownFrameCache.Width > 0) and (FShownFrameCache.Height > 0);
  if not Result then
    Exit;

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('shown_frame_cache_hit position_ms=%d size=%dx%d',
    [PositionMs, FShownFrameCache.Width, FShownFrameCache.Height]));
{$ENDIF}
  FSurface.Bitmap.Assign(FShownFrameCache);
  FSurface.PresentImmediate;
end;

function TVideoMinerVideoView.TryPresentLoopFrameCache(StartMs: Integer): Boolean;
var
  HitText: string;
begin
  Result := (FSurface <> nil) and (FLoopFrameCacheStartMs = StartMs) and
    (FLoopFrameCacheCount > 0) and (FLoopFrameCache[0] <> nil) and
    (FLoopFrameCache[0].Width > 0) and (FLoopFrameCache[0].Height > 0);
{$IFDEF DEBUG}
  if Result then
    HitText := 'hit'
  else
    HitText := 'miss';
  WriteVideoMinerSlowLog(Format(
    'loop_frame_cache_%s start_ms=%d cached_start_ms=%d count=%d',
    [HitText, StartMs, FLoopFrameCacheStartMs, FLoopFrameCacheCount]));
{$ENDIF}
  if not Result then
    Exit;

  FSurface.Bitmap.Assign(FLoopFrameCache[0]);
  FSurface.PresentImmediate;
end;

procedure TVideoMinerVideoView.BeginLoadingIndicator;
begin
  if FSurface <> nil then
    FSurface.BeginLoadingIndicator;
end;

procedure TVideoMinerVideoView.Present(Bitmap: TBitmap);
begin
  if FSurface <> nil then
    FSurface.Present;
end;

procedure TVideoMinerVideoView.PresentImmediate(Bitmap: TBitmap);
begin
  if FSurface <> nil then
    FSurface.PresentImmediate;
end;

function FrameSignatureLogText(const Signature: TVideoMinerFrameSignature): string;
var
  I: Integer;
  Sum: Integer;
begin
  Sum := 0;
  for I := Low(Signature.Values) to High(Signature.Values) do
    Inc(Sum, Signature.Values[I]);

  Result := Format('sum=%d head=%d,%d,%d,%d,%d,%d,%d,%d',
    [Sum, Signature.Values[0], Signature.Values[1], Signature.Values[2],
     Signature.Values[3], Signature.Values[4], Signature.Values[5],
     Signature.Values[6], Signature.Values[7]]);
end;

procedure TVideoMinerVideoView.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnPlayPauseClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSurfaceRightClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnSurfaceRightClick := Value;
end;

procedure TVideoMinerVideoView.SetBossMode(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.BossMode := Value;
end;

procedure TVideoMinerVideoView.SetFullScreen(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.FullScreen := Value;
end;

procedure TVideoMinerVideoView.SetOnToggleChapterClick(
  Value: TVideoMinerOverlaySeekEvent);
begin
  if FSurface <> nil then
    FSurface.OnToggleChapterClick := Value;
end;
procedure TVideoMinerVideoView.SetOnFullScreenClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnFullScreenClick := Value;
end;

procedure TVideoMinerVideoView.SetOnBossExitClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnBossExitClick := Value;
end;

procedure TVideoMinerVideoView.SetOnBossGesture(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnBossGesture := Value;
end;

procedure TVideoMinerVideoView.SetOnMuteClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnMuteClick := Value;
end;

procedure TVideoMinerVideoView.SetOnPlaybackRateClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnPlaybackRateClick := Value;
end;

procedure TVideoMinerVideoView.SetOnEndActionClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnEndActionClick := Value;
end;

procedure TVideoMinerVideoView.SetOnCheckClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnCheckClick := Value;
end;

procedure TVideoMinerVideoView.SetOnAddChapterClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnAddChapterClick := Value;
end;

procedure TVideoMinerVideoView.SetOnDeleteChapterClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnDeleteChapterClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
begin
  if FSurface <> nil then
    FSurface.OnSeek := Value;
end;

procedure TVideoMinerVideoView.SetOnSeekByWheel(
  Value: TVideoMinerOverlaySeekEvent);
begin
  if FSurface <> nil then
    FSurface.OnSeekByWheel := Value;
end;

procedure TVideoMinerVideoView.SetOnSeekHoverPreview(
  Value: TVideoMinerOverlaySeekHoverEvent);
begin
  if FSurface <> nil then
    FSurface.OnSeekHoverPreview := Value;
end;

procedure TVideoMinerVideoView.SetOnSeekHoverPreviewEnd(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnSeekHoverPreviewEnd := Value;
end;

procedure TVideoMinerVideoView.SetOnVolumeChange(
  Value: TVideoMinerOverlayVolumeEvent);
begin
  if FSurface <> nil then
    FSurface.OnVolumeChange := Value;
end;

procedure TVideoMinerVideoView.SetOnFirstFrameClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnFirstFrameClick := Value;
end;

procedure TVideoMinerVideoView.SetOnLastFrameClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnLastFrameClick := Value;
end;

procedure TVideoMinerVideoView.SetOnNavigatePreviousClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnNavigatePreviousClick := Value;
end;

procedure TVideoMinerVideoView.SetOnNavigateNextClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnNavigateNextClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSkipBackwardClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnSkipBackwardClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSkipForwardClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnSkipForwardClick := Value;
end;

procedure TVideoMinerVideoView.SetPlaybackActive(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.PlaybackActive := Value;
end;

procedure TVideoMinerVideoView.SetPlaybackRateText(const Value: string);
begin
  if FSurface <> nil then
    FSurface.PlaybackRateText := Value;
end;

procedure TVideoMinerVideoView.SetSafeAreaVisible(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.SafeAreaVisible := Value;
end;
procedure TVideoMinerVideoView.SetSourceHasAlpha(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.SourceHasAlpha := Value;
end;

procedure TVideoMinerVideoView.SetCanNavigatePrevious(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.CanNavigatePrevious := Value;
end;

procedure TVideoMinerVideoView.SetCanNavigateNext(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.CanNavigateNext := Value;
end;

procedure TVideoMinerVideoView.SetEndActionText(const Value: string);
begin
  if FSurface <> nil then
    FSurface.EndActionText := Value;
end;

procedure TVideoMinerVideoView.SetCheckEnabled(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.CheckEnabled := Value;
end;

procedure TVideoMinerVideoView.SetChapters(
  const Value: TVideoMinerOverlayChapters);
begin
  if FSurface <> nil then
    FSurface.Chapters := Value;
end;

procedure TVideoMinerVideoView.SetSeekProgress(PositionMs, MaxMs: Integer);
begin
  if FSurface <> nil then
    FSurface.SetSeekProgress(PositionMs, MaxMs);
end;

procedure TVideoMinerVideoView.SetSeekHoverPreview(Bitmap: TBitmap;
  PositionMs: Integer; const AnchorPoint: TPoint);
begin
  if FSurface <> nil then
    FSurface.SetSeekHoverPreview(Bitmap, PositionMs, AnchorPoint);
end;

procedure TVideoMinerVideoView.ClearSeekHoverPreview;
begin
  if FSurface <> nil then
    FSurface.ClearSeekHoverPreview;
end;

procedure TVideoMinerVideoView.EndLoadingIndicator;
begin
  if FSurface <> nil then
    FSurface.EndLoadingIndicator;
end;

procedure TVideoMinerVideoView.SetSeekWheelFrameStepMs(Value: Integer);
begin
  if FSurface <> nil then
    FSurface.SeekWheelFrameStepMs := Value;
end;

procedure TVideoMinerVideoView.SetVolumePercent(Value: Integer);
begin
  if FSurface <> nil then
    FSurface.VolumePercent := Value;
end;

procedure TVideoMinerVideoView.SetMuted(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.Muted := Value;
end;

function TVideoMinerVideoView.DecodeFrameToBitmap(Decoder: TFFmpegDecoder;
  PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string;
  FastSeek: Boolean): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
begin
  ErrorMessage := '';
  Result := False;
  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;
  if Bitmap = nil then
  begin
    ErrorMessage := 'Bitmap is nil.';
    Exit;
  end;

  if not PrepareBitmapFrameBuffer(Bitmap, Decoder.Info.Width,
    Decoder.Info.Height, Buffer, BufferStride) then
  begin
    ErrorMessage := 'Failed to prepare preview frame buffer.';
    Exit;
  end;

  if FastSeek then
    Result := Decoder.DecodeFrameToBgrx32Fast(PositionMs, Buffer,
      BufferStride, ErrorMessage)
  else
    Result := Decoder.DecodeFrameToBgrx32(PositionMs, Buffer, BufferStride,
      ErrorMessage);
  if not Result then
    Exit;

  RotateBitmapByDegrees(Bitmap, DisplayRotationDegrees(Decoder.Info.RotationDegrees));
end;

function TVideoMinerVideoView.ShowFrameAt(Decoder: TFFmpegDecoder;
  PositionMs: Integer; out ErrorMessage: string; PresentFrame: Boolean;
  FastSeek: Boolean): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
  EffectiveRotation: Integer;
{$IFDEF DEBUG}
  Signature: TVideoMinerFrameSignature;
  BeforeWidth: Integer;
  BeforeHeight: Integer;
  AfterWidth: Integer;
  AfterHeight: Integer;
{$ENDIF}
begin
  ErrorMessage := '';
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if PresentFrame then
  begin
    TryPresentCachedFrame(PositionMs);
    if not PrepareFrameBuffer(Decoder, Buffer, BufferStride, ErrorMessage) then
      Exit;
  end
  else
  begin
    if not PrepareBitmapFrameBuffer(FDecodeScratch, Decoder.Info.Width,
      Decoder.Info.Height, Buffer, BufferStride) then
    begin
      ErrorMessage := 'Failed to prepare scratch frame buffer.';
      Exit;
    end;
  end;

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'show_frame_decode_begin position_ms=%d present=%s fast=%s',
    [PositionMs, BoolToStr(PresentFrame, True), BoolToStr(FastSeek, True)]));
{$ENDIF}
  if FastSeek then
    Result := Decoder.DecodeFrameToBgrx32Fast(PositionMs, Buffer,
      BufferStride, ErrorMessage)
  else
    Result := Decoder.DecodeFrameToBgrx32(PositionMs, Buffer, BufferStride,
      ErrorMessage);
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'show_frame_decode_end position_ms=%d result=%s err="%s"',
    [PositionMs, BoolToStr(Result, True), ErrorMessage]));
{$ENDIF}
  if not Result then
  begin
    Result := False;
    Exit;
  end;

  EffectiveRotation := DisplayRotationDegrees(Decoder.Info.RotationDegrees);
{$IFDEF DEBUG}
  if PresentFrame then
  begin
    BeforeWidth := FSurface.Bitmap.Width;
    BeforeHeight := FSurface.Bitmap.Height;
  end
  else
  begin
    BeforeWidth := FDecodeScratch.Width;
    BeforeHeight := FDecodeScratch.Height;
  end;
  WriteVideoMinerSlowLog(Format(
    'show_frame_rotation position_ms=%d present=%s source_rotation=%d effective_rotation=%d before=%dx%d',
    [PositionMs, BoolToStr(PresentFrame, True), Decoder.Info.RotationDegrees,
     EffectiveRotation, BeforeWidth, BeforeHeight]));
{$ENDIF}
  if PresentFrame then
    RotateBitmapByDegrees(FSurface.Bitmap, EffectiveRotation);
{$IFDEF DEBUG}
  if PresentFrame then
  begin
    AfterWidth := FSurface.Bitmap.Width;
    AfterHeight := FSurface.Bitmap.Height;
  end
  else
  begin
    AfterWidth := FDecodeScratch.Width;
    AfterHeight := FDecodeScratch.Height;
  end;
  WriteVideoMinerSlowLog(Format(
    'show_frame_rotation_done position_ms=%d present=%s effective_rotation=%d after=%dx%d',
    [PositionMs, BoolToStr(PresentFrame, True), EffectiveRotation,
     AfterWidth, AfterHeight]));
{$ENDIF}

  if PresentFrame then
  begin
    PresentImmediate(FSurface.Bitmap);
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'show_frame_present_immediate position_ms=%d bitmap=%dx%d',
      [PositionMs, FSurface.Bitmap.Width, FSurface.Bitmap.Height]));
    if CurrentFrameSignature(Signature) then
      WriteVideoMinerSlowLog(Format(
        'show_frame_signature position_ms=%d %s',
        [PositionMs, FrameSignatureLogText(Signature)]));
{$ENDIF}
    CacheShownFrame(PositionMs);
    StoreLoopFrameCache(PositionMs);
  end;
  Result := True;
end;

function TVideoMinerVideoView.DecodeNextFrame(Decoder: TFFmpegDecoder;
  ConvertFrame: Boolean; out PositionMs: Integer;
  out ErrorMessage: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
  EffectiveRotation: Integer;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;
  Buffer := nil;
  BufferStride := 0;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if ConvertFrame and
     (not PrepareFrameBuffer(Decoder, Buffer, BufferStride, ErrorMessage)) then
    Exit;

  EffectiveRotation := DisplayRotationDegrees(Decoder.Info.RotationDegrees);
  SetNv12TextureD3DDisplayAllowed(ConvertFrame and (EffectiveRotation = 0) and
    (not FLoopFrameCaptureActive));
{$IFDEF DEBUG}
  if ConvertFrame then
    WriteVideoMinerSlowLog(Format(
      'decode_next_d3d_allowed allowed=%s effective_rotation=%d loop_cache_capture=%s',
      [BoolToStr((EffectiveRotation = 0) and (not FLoopFrameCaptureActive), True),
       EffectiveRotation, BoolToStr(FLoopFrameCaptureActive, True)]));
{$ENDIF}
  ClearNv12TextureD3DFramePresented;
  if not Decoder.DecodeNextFrameToBgrx32Optional(Buffer, BufferStride,
    ConvertFrame, PositionMs, ErrorMessage) then
    Exit;

  if ConvertFrame and Nv12TextureD3DFramePresented then
  begin
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'decode_next_d3d_presented position_ms=%d source_rotation=%d display_rotation_offset=%d',
      [PositionMs, Decoder.Info.RotationDegrees, FDisplayRotationOffset]));
{$ENDIF}
    Result := True;
    Exit;
  end;

  if ConvertFrame then
  begin
    WriteVideoMinerSlowLog(Format(
      'decode_next_rotation position_ms=%d source_rotation=%d effective_rotation=%d before=%dx%d',
      [PositionMs, Decoder.Info.RotationDegrees, EffectiveRotation,
       FSurface.Bitmap.Width, FSurface.Bitmap.Height]));
    RotateBitmapByDegrees(FSurface.Bitmap, EffectiveRotation);
    WriteVideoMinerSlowLog(Format(
      'decode_next_rotation_done position_ms=%d after=%dx%d',
      [PositionMs, FSurface.Bitmap.Width, FSurface.Bitmap.Height]));
  end;

  if ConvertFrame then
  begin
    Present(FSurface.Bitmap);
    StoreLoopFrameCache(PositionMs);
  end;

  Result := True;
end;

function TVideoMinerVideoView.DecodeNextFrameToScratch(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if not PrepareBitmapFrameBuffer(FDecodeScratch, Decoder.Info.Width,
    Decoder.Info.Height, Buffer, BufferStride) then
  begin
    ErrorMessage := 'Failed to prepare scratch frame buffer.';
    Exit;
  end;

  Result := Decoder.DecodeNextFrameToBgrx32Optional(Buffer, BufferStride,
    True, PositionMs, ErrorMessage);
  if Result then
    RotateBitmapByDegrees(FDecodeScratch,
      DisplayRotationDegrees(Decoder.Info.RotationDegrees));
end;

function TVideoMinerVideoView.HandleMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := (FSurface <> nil) and
    FSurface.HandleMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVideoMinerVideoView.ShowNextFrame(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  Result := DecodeNextFrame(Decoder, True, PositionMs, ErrorMessage);
end;

function TVideoMinerVideoView.PresentScratchFrame(
  out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  Result := False;

  if (FSurface = nil) or (FDecodeScratch = nil) or
     (FDecodeScratch.Width <= 0) or (FDecodeScratch.Height <= 0) then
  begin
    ErrorMessage := 'Scratch frame is empty.';
    Exit;
  end;

  FSurface.Bitmap.Assign(FDecodeScratch);
  Present(FSurface.Bitmap);
  Result := True;
end;

end.
