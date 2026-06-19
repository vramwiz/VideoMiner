unit VideoMinerVideoView;

// メインフォームや controller から動画表示サーフェスを扱うための薄い窓口。
// フレームデコード先の準備、サーフェスへの表示、overlay 状態とイベントの中継を担当する。

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Graphics, FFmpegDecoder, VideoMinerFrameCheck, VideoMinerOverlay,
  VideoMinerVideoSurface;

type
  TVideoMinerVideoView = class
  private
    FDecodeScratch           : TBitmap;                 // 表示せずに次フレームを確認するための作業用 Bitmap
    FShownFrameCache         : TBitmap;                 // 直近の明示表示フレームを即時再表示するためのキャッシュ
    FShownFrameCachePosition : Integer;                 // キャッシュしている明示表示フレームの位置 ms
    FSurface                 : TVideoMinerVideoSurface; // 実際の動画表示と overlay 描画を持つサーフェス
    // 現在の表示フレームを指定位置の即時再表示用に保存する
    procedure CacheShownFrame(PositionMs: Integer);
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
    // サムネイル一覧表示右クリックの通知先を設定する
    procedure SetOnThumbnailBrowserClick(Value: TNotifyEvent);
    // シークバー操作の通知先を設定する
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    // シークバー上ホイール操作の通知先を設定する
    procedure SetOnSeekByWheel(Value: TVideoMinerOverlaySeekEvent);
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
    // ボスが来たモード中のヘルプページを前後へ切り替える
    procedure ChangeBossHelpPage(Delta: Integer);
    // 指定位置のフレームをデコードし、必要なら表示へ反映する
    function ShowFrameAt(Decoder: TFFmpegDecoder; PositionMs: Integer;
      out ErrorMessage: string; PresentFrame: Boolean = True;
      FastSeek: Boolean = False): Boolean;
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
    property OnThumbnailBrowserClick: TNotifyEvent write SetOnThumbnailBrowserClick;
    property OnSeek: TVideoMinerOverlaySeekEvent write SetOnSeek;
    property OnSeekByWheel: TVideoMinerOverlaySeekEvent write SetOnSeekByWheel;
    property OnSkipBackwardClick: TNotifyEvent write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent write SetOnSkipForwardClick;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent write SetOnVolumeChange;
    property PlaybackActive: Boolean write SetPlaybackActive;
    property PlaybackRateText: string write SetPlaybackRateText;
    property SafeAreaVisible: Boolean write SetSafeAreaVisible;
    property SourceHasAlpha: Boolean write SetSourceHasAlpha;
    property SeekWheelFrameStepMs: Integer write SetSeekWheelFrameStepMs;
    property CurrentFrameBitmap: TBitmap read GetCurrentFrameBitmap;
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

  if Height > 1 then
    BufferStride := Abs(NativeInt(Bitmap.ScanLine[1]) - NativeInt(Bitmap.ScanLine[0]))
  else
    BufferStride := Width * 4;

  Buffer := Bitmap.ScanLine[Height - 1];
  Result := (Buffer <> nil) and (BufferStride > 0);
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
begin
  inherited Create;

  FDecodeScratch := TBitmap.Create;
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
begin
  FSurface.Free;
  FShownFrameCache.Free;
  FDecodeScratch.Free;
  inherited Destroy;
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
  if FShownFrameCache <> nil then
    FShownFrameCache.SetSize(0, 0);
  FShownFrameCachePosition := -1;
  if FSurface <> nil then
  begin
    FSurface.SourceHasAlpha := False;
    FSurface.Clear;
  end;
end;

function TVideoMinerVideoView.TryPresentCachedFrame(PositionMs: Integer): Boolean;
begin
  Result := (FSurface <> nil) and (FShownFrameCache <> nil) and
    (FShownFrameCachePosition = PositionMs) and
    (FShownFrameCache.Width > 0) and (FShownFrameCache.Height > 0);
  if not Result then
    Exit;

  FSurface.Bitmap.Assign(FShownFrameCache);
  FSurface.PresentImmediate;
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

procedure TVideoMinerVideoView.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnPlayPauseClick := Value;
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

procedure TVideoMinerVideoView.SetOnThumbnailBrowserClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnThumbnailBrowserClick := Value;
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

function TVideoMinerVideoView.ShowFrameAt(Decoder: TFFmpegDecoder;
  PositionMs: Integer; out ErrorMessage: string; PresentFrame: Boolean;
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

  if FastSeek then
    Result := Decoder.DecodeFrameToBgrx32Fast(PositionMs, Buffer,
      BufferStride, ErrorMessage)
  else
    Result := Decoder.DecodeFrameToBgrx32(PositionMs, Buffer, BufferStride,
      ErrorMessage);
  if not Result then
  begin
    Result := False;
    Exit;
  end;

  if PresentFrame then
  begin
    PresentImmediate(FSurface.Bitmap);
    CacheShownFrame(PositionMs);
  end;
  Result := True;
end;

function TVideoMinerVideoView.DecodeNextFrame(Decoder: TFFmpegDecoder;
  ConvertFrame: Boolean; out PositionMs: Integer;
  out ErrorMessage: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
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

  if not Decoder.DecodeNextFrameToBgrx32Optional(Buffer, BufferStride,
    ConvertFrame, PositionMs, ErrorMessage) then
    Exit;

  if ConvertFrame then
    Present(FSurface.Bitmap);

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
