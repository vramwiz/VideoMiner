unit VideoMinerSeekHoverPreviewController;

// シークバー hover 位置のフレームプレビューを制御する。
// MainForm からタイマー、Bitmap、デコード調停を分離し、表示先の VideoView だけを更新する。

interface

uses
  System.Classes, System.Diagnostics, System.Math, System.SysUtils, System.Types,
  Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder, FFmpegDecoderTypes, VideoMinerVideoView;

type
  TVideoMinerSeekHoverPreviewController = class
  private
    FBitmap         : TBitmap;             // hover プレビュー用 Bitmap
    FCurrentFile    : string;              // 現在プレビュー対象にできるファイル名
    FDecodeCount    : Int64;               // 実デコードした hover プレビュー回数
    FLastPositionMs : Integer;             // 最後にデコードしたプレビュー位置 ms
    FMaxMs          : Integer;             // 現在ファイルのシーク可能な最大位置 ms
    FPending        : Boolean;             // timer で処理待ちの hover 要求があるか
    FPendingTick    : Int64;               // 現在の hover 要求を受けた時刻
    FPoint          : TPoint;              // プレビュー表示位置
    FPositionMs     : Integer;             // プレビュー要求位置 ms
    FPreviewDecoder : TFFmpegDecoder;      // hover プレビュー用に使う補助デコーダ
    FPreviewActive  : Boolean;             // プレビュー表示済みで追従更新中か
    FRequestCount   : Int64;               // 受け取った hover 要求数
    FReuseCount     : Int64;               // 既存 preview を再利用した回数
    FTimer          : TTimer;              // hover 要求を間引いてデコードする timer
    FVideoView      : TVideoMinerVideoView;// プレビュー表示先
    // timer で遅延実行された hover プレビューをデコードする
    procedure TimerTick(Sender: TObject);
  public
    // 必要な表示先、デコーダ、timer を構成する
    constructor Create(AOwner: TComponent; AVideoView: TVideoMinerVideoView;
      APreviewDecoder: TFFmpegDecoder);
    // timer と Bitmap を解放する
    destructor Destroy; override;
    // 現在の動画ファイルとシーク範囲を設定する
    procedure ConfigureMedia(const FileName: string; MaxMs: Integer);
    // hover プレビュー状態を消す
    procedure Clear;
    // 現在メディアとの対応を切り、hover 用デコーダを閉じる
    procedure ResetMedia;
    // シークバー hover 位置のプレビュー要求を受ける
    procedure SeekHoverPreview(Sender: TObject; PositionMs: Integer; const Point: TPoint);
    // シークバー hover プレビューを閉じる
    procedure SeekHoverPreviewEnd(Sender: TObject);
  end;

implementation

uses
  VideoMinerDebugLog;

const
  SEEK_HOVER_PREVIEW_INITIAL_DELAY_MS = 140; // 最初の hover でプレビュー表示を始めるまでの待ち時間 ms
  SEEK_HOVER_PREVIEW_UPDATE_DELAY_MS  = 5;   // 表示済みプレビューを別位置へ更新するまでの待ち時間 ms
  SEEK_HOVER_PREVIEW_REUSE_MS         = 80;  // 近い hover 位置では前回プレビューを再利用する幅 ms

function ElapsedMsFromTick(StartTick: Int64): Double;
begin
  if StartTick <= 0 then
    Result := 0
  else
    Result := (TStopwatch.GetTimeStamp - StartTick) * 1000.0 / TStopwatch.Frequency;
end;

constructor TVideoMinerSeekHoverPreviewController.Create(AOwner: TComponent;
  AVideoView: TVideoMinerVideoView; APreviewDecoder: TFFmpegDecoder);
begin
  inherited Create;
  FVideoView := AVideoView;
  FPreviewDecoder := APreviewDecoder;
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf32bit;
  FLastPositionMs := -1;
  FTimer := TTimer.Create(AOwner);
  FTimer.Enabled := False;
  FTimer.Interval := SEEK_HOVER_PREVIEW_INITIAL_DELAY_MS;
  FTimer.OnTimer := TimerTick;
end;

destructor TVideoMinerSeekHoverPreviewController.Destroy;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  FTimer.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TVideoMinerSeekHoverPreviewController.ConfigureMedia(
  const FileName: string; MaxMs: Integer);
var
  ErrorMessage: string;
  Info: TVideoInfo;
begin
  Clear;
  FCurrentFile := '';
  FMaxMs := 0;
  FLastPositionMs := -1;
  if FPreviewDecoder <> nil then
    FPreviewDecoder.Close;
  if (FileName = '') or (MaxMs <= 0) or (FPreviewDecoder = nil) then
    Exit;

  if FPreviewDecoder.Open(FileName, Info, ErrorMessage) then
  begin
    FCurrentFile := FileName;
    FMaxMs := Max(0, MaxMs);
  end
  else if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'seek_hover_preview_open_failed file="%s" err="%s"',
      [ExtractFileName(FileName), ErrorMessage]));
end;

procedure TVideoMinerSeekHoverPreviewController.Clear;
begin
  FPending := False;
  FPreviewActive := False;
  FPendingTick := 0;
  if FTimer <> nil then
    FTimer.Enabled := False;
  if FVideoView <> nil then
    FVideoView.ClearSeekHoverPreview;
end;

procedure TVideoMinerSeekHoverPreviewController.ResetMedia;
begin
  Clear;
  FCurrentFile := '';
  FMaxMs := 0;
  FLastPositionMs := -1;
  FDecodeCount := 0;
  FRequestCount := 0;
  FReuseCount := 0;
  if FPreviewDecoder <> nil then
    FPreviewDecoder.Close;
end;

procedure TVideoMinerSeekHoverPreviewController.SeekHoverPreview(
  Sender: TObject; PositionMs: Integer; const Point: TPoint);
begin
  if (FCurrentFile = '') or (FMaxMs <= 0) or (FVideoView = nil) then
  begin
    SeekHoverPreviewEnd(Sender);
    Exit;
  end;

  FPositionMs := Max(0, Min(FMaxMs, PositionMs));
  FPoint := Point;
  Inc(FRequestCount);

  if (FBitmap <> nil) and (FBitmap.Width > 0) and
     (FLastPositionMs >= 0) and
     (Abs(FPositionMs - FLastPositionMs) <= SEEK_HOVER_PREVIEW_REUSE_MS) then
  begin
    Inc(FReuseCount);
    FVideoView.SetSeekHoverPreview(FBitmap, FLastPositionMs, FPoint);
    FPreviewActive := True;
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_hover_preview_reuse request=%d reuse=%d requested_ms=%d cached_ms=%d delta_ms=%d x=%d y=%d',
        [FRequestCount, FReuseCount, FPositionMs, FLastPositionMs,
         Abs(FPositionMs - FLastPositionMs), Point.X, Point.Y]));
    Exit;
  end;

  FPending := True;
  FPendingTick := TStopwatch.GetTimeStamp;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    if FPreviewActive then
      FTimer.Interval := SEEK_HOVER_PREVIEW_UPDATE_DELAY_MS
    else
      FTimer.Interval := SEEK_HOVER_PREVIEW_INITIAL_DELAY_MS;
    FTimer.Enabled := True;
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_hover_preview_schedule request=%d position_ms=%d x=%d y=%d interval_ms=%d active=%s',
        [FRequestCount, FPositionMs, Point.X, Point.Y, FTimer.Interval,
         BoolToStr(FPreviewActive, True)]));
  end;
end;

procedure TVideoMinerSeekHoverPreviewController.SeekHoverPreviewEnd(Sender: TObject);
begin
  Clear;
end;

procedure TVideoMinerSeekHoverPreviewController.TimerTick(Sender: TObject);
var
  ErrorMessage: string;
  FallbackMs: Double;
  FastMs: Double;
  FastOk: Boolean;
  PositionMs: Integer;
  SetMs: Double;
  StepWatch: TStopwatch;
  TotalWatch: TStopwatch;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  if not FPending then
    Exit;

  FPending := False;
  if (FCurrentFile = '') or (FMaxMs <= 0) or (FPreviewDecoder = nil) or
     (FVideoView = nil) or (FBitmap = nil) then
    Exit;

  PositionMs := Max(0, Min(FMaxMs, FPositionMs));
  Inc(FDecodeCount);
  TotalWatch := TStopwatch.StartNew;

  StepWatch := TStopwatch.StartNew;
  FastOk := FVideoView.DecodeFrameToBitmap(FPreviewDecoder, PositionMs,
    FBitmap, ErrorMessage, True);
  FastMs := StepWatch.Elapsed.TotalMilliseconds;
  FallbackMs := 0;
  if (not FastOk) then
  begin
    StepWatch := TStopwatch.StartNew;
    FastOk := FVideoView.DecodeFrameToBitmap(FPreviewDecoder, PositionMs,
      FBitmap, ErrorMessage, False);
    FallbackMs := StepWatch.Elapsed.TotalMilliseconds;
  end;

  if FastOk then
  begin
    FLastPositionMs := PositionMs;
    StepWatch := TStopwatch.StartNew;
    FVideoView.SetSeekHoverPreview(FBitmap, PositionMs, FPoint);
    SetMs := StepWatch.Elapsed.TotalMilliseconds;
    FPreviewActive := True;
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_hover_preview_decode request=%d decode=%d position_ms=%d wait_ms=%.3f fast_ms=%.3f fallback_ms=%.3f set_ms=%.3f total_ms=%.3f reuse=%d',
        [FRequestCount, FDecodeCount, PositionMs, ElapsedMsFromTick(FPendingTick),
         FastMs, FallbackMs, SetMs, TotalWatch.Elapsed.TotalMilliseconds,
         FReuseCount]));
    FPendingTick := 0;
  end
  else
  begin
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_hover_preview_decode_failed request=%d decode=%d position_ms=%d wait_ms=%.3f fast_ms=%.3f fallback_ms=%.3f total_ms=%.3f err="%s"',
        [FRequestCount, FDecodeCount, PositionMs, ElapsedMsFromTick(FPendingTick),
         FastMs, FallbackMs, TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
    if FVideoView <> nil then
      FVideoView.ClearSeekHoverPreview;
    FPreviewActive := False;
    FPendingTick := 0;
  end;
end;

end.
