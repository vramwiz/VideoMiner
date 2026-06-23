unit VideoMinerSeekHoverPreviewController;

// シークバー hover 位置のフレームプレビューを制御する。
// MainForm からタイマー、Bitmap、デコード調停を分離し、表示先の VideoView だけを更新する。

interface

uses
  System.Classes, System.Math, System.SysUtils, System.Types, Vcl.ExtCtrls,
  Vcl.Graphics, FFmpegDecoder, VideoMinerVideoView;

type
  TVideoMinerSeekHoverPreviewController = class
  private
    FBitmap         : TBitmap;             // hover プレビュー用 Bitmap
    FCurrentFile    : string;              // 現在プレビュー対象にできるファイル名
    FLastPositionMs : Integer;             // 最後にデコードしたプレビュー位置 ms
    FMaxMs          : Integer;             // 現在ファイルのシーク可能な最大位置 ms
    FPending        : Boolean;             // timer で処理待ちの hover 要求があるか
    FPoint          : TPoint;              // プレビュー表示位置
    FPositionMs     : Integer;             // プレビュー要求位置 ms
    FPreviewDecoder : TFFmpegDecoder;      // hover プレビュー用に使う補助デコーダ
    FPreviewActive  : Boolean;             // プレビュー表示済みで追従更新中か
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
begin
  Clear;
  FCurrentFile := FileName;
  FMaxMs := Max(0, MaxMs);
  FLastPositionMs := -1;
end;

procedure TVideoMinerSeekHoverPreviewController.Clear;
begin
  FPending := False;
  FPreviewActive := False;
  if FTimer <> nil then
    FTimer.Enabled := False;
  if FVideoView <> nil then
    FVideoView.ClearSeekHoverPreview;
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
  if VideoMinerDebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'seek_hover_preview_request position_ms=%d x=%d y=%d',
      [FPositionMs, Point.X, Point.Y]));

  if (FBitmap <> nil) and (FBitmap.Width > 0) and
     (FLastPositionMs >= 0) and
     (Abs(FPositionMs - FLastPositionMs) <= SEEK_HOVER_PREVIEW_REUSE_MS) then
  begin
    FVideoView.SetSeekHoverPreview(FBitmap, FLastPositionMs, FPoint);
    FPreviewActive := True;
    Exit;
  end;

  FPending := True;
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    if FPreviewActive then
      FTimer.Interval := SEEK_HOVER_PREVIEW_UPDATE_DELAY_MS
    else
      FTimer.Interval := SEEK_HOVER_PREVIEW_INITIAL_DELAY_MS;
    FTimer.Enabled := True;
  end;
end;

procedure TVideoMinerSeekHoverPreviewController.SeekHoverPreviewEnd(Sender: TObject);
begin
  Clear;
end;

procedure TVideoMinerSeekHoverPreviewController.TimerTick(Sender: TObject);
var
  ErrorMessage: string;
  PositionMs: Integer;
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
  if FVideoView.DecodeFrameToBitmap(FPreviewDecoder, PositionMs,
    FBitmap, ErrorMessage, True) or
     FVideoView.DecodeFrameToBitmap(FPreviewDecoder, PositionMs,
       FBitmap, ErrorMessage, False) then
  begin
    FLastPositionMs := PositionMs;
    FVideoView.SetSeekHoverPreview(FBitmap, PositionMs, FPoint);
    FPreviewActive := True;
  end
  else
  begin
    if VideoMinerDebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_hover_preview_decode_failed position_ms=%d err="%s"',
        [PositionMs, ErrorMessage]));
    if FVideoView <> nil then
      FVideoView.ClearSeekHoverPreview;
    FPreviewActive := False;
  end;
end;

end.
