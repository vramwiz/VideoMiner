unit VideoMinerPlaybackController;

// 動画再生の開始、停止、seek、tick、音声同期、終端処理を担当する。
// メインフォームから再生中の状態管理を分離し、デコーダ、音声再生、
// 動画ビュー、チャプター管理をつないで 1 tick ごとの再生制御を進める。

interface

uses
  System.Diagnostics, Vcl.ExtCtrls, FFmpegDecoder, FFmpegDecoderTypes,
  VideoMinerAudioPlayback, VideoMinerChapterManager, VideoMinerSettings,
  VideoMinerVideoView;

type
  // 再生終端に到達した時に caller が行う処理
  TVideoMinerPlaybackEndResult = (perStop, perLoop, perNext);
  // 1 フレーム読み取りの結果
  TVideoMinerPlaybackDecodeResult = (pdrFrame, pdrEndOfStream, pdrError);
  // 音声より遅れた動画フレームの補正結果
  TVideoMinerLaggingVideoResult = (lvrNoAction, lvrDropped, lvrSyncedToAudio,
    lvrError);
  // seek guard が初期フレームをどう扱ったか
  TVideoMinerSeekGuardResult = (sgrNotGuarded, sgrAccepted, sgrContinue,
    sgrSyncedToTarget, sgrGuardError, sgrPresentError);
  // 引数なしで main form 側の処理を呼び戻す callback
  TVideoMinerPlaybackNotifyProc = procedure of object;
  // 再生位置 ms を main form 側へ渡す callback
  TVideoMinerPlaybackPositionProc = procedure(PositionMs: Integer) of object;
  // ループ再開位置と、そのフレームをすでに表示済みかを main form 側へ渡す callback
  TVideoMinerPlaybackLoopSeekProc = procedure(PositionMs: Integer;
    FrameAlreadyShown: Boolean) of object;
  // 再生状態表示文字列を main form 側へ渡す callback
  TVideoMinerPlaybackStatusProc = procedure(const Text: string) of object;
  // 指定位置のフレーム表示を main form 側へ依頼する callback
  TVideoMinerPlaybackFrameFunc = function(const PositionMs: Integer): Boolean of object;
  // 指定位置からの再生開始を main form 側へ依頼する callback
  TVideoMinerPlaybackStartProc = procedure(PositionMs: Integer;
    FrameAlreadyShown: Boolean) of object;

  TVideoMinerPlaybackController = class
  private
    FAudioPlayback            : TVideoMinerAudioPlayback; // 音声開始/停止と音声位置取得を行う再生ラッパ
    FPlaybackRate             : Double;                   // 現在の再生速度倍率
    FRestartFastSeek          : Boolean;                  // 再開予約時に軽い seek として扱うか
    FRestartFrameAlreadyShown : Boolean;                  // 再開位置のフレームがすでに表示済みか
    FRestartPending           : Boolean;                  // seek 後の再生再開予約があるか
    FRestartPositionMs        : Integer;                  // 再開予約された再生位置 ms
    FRestartTimer             : TTimer;                   // seek 後の遅延再開を発火する timer
    FRateClock                : TStopwatch;               // 倍速再生時の映像位置を進める単調時計
    FRateClockActive          : Boolean;                  // 倍速用単調時計が有効か
    FRateClockBaseMs          : Integer;                  // 倍速用単調時計の開始位置 ms
    FRateTickLogClock         : TStopwatch;               // 倍速 tick ログの間引きに使う単調時計
    FLastRateTickLogMs        : Int64;                    // 最後に倍速 tick ログを出した経過 ms
    FPreviewShownPositionMs   : Integer;                  // preview decoder で最後に表示した位置 ms
    FPreviewShownGeneration   : Int64;                    // 最後に表示した時点の preview decoder 世代番号
    FVideoView                : TVideoMinerVideoView;     // 表示更新と scratch frame 表示を行う動画ビュー
    FPlaybackTimer            : TTimer;                   // 再生 tick を発火する timer
    FPreviewDecoder           : TFFmpegDecoder;           // seek preview 用に使うデコーダ
    FTimerPeriodActive        : Boolean;                  // 再生中に高分解能 timer を要求しているか
    procedure BeginPlaybackTimerPeriod;
    procedure EndPlaybackTimerPeriod;
    procedure SetPlaybackTimerEnabled(Value: Boolean);
  public
    // timer、音声再生、動画ビュー、preview decoder を受け取る
    constructor Create(PlaybackTimer, RestartTimer: TTimer;
      AudioPlayback: TVideoMinerAudioPlayback; VideoView: TVideoMinerVideoView;
      PreviewDecoder: TFFmpegDecoder);
    destructor Destroy; override;
    // 再生中、または seek 後の再開待ちかを返す
    function ActiveOrPending: Boolean;
    // seek 後の再開予約を破棄する
    procedure ClearRestart;
    // 再開予約を取り出し、取り出した予約をクリアする
    function ConsumeRestart(out PositionMs: Integer;
      out FrameAlreadyShown: Boolean; out FastSeek: Boolean): Boolean;
    // UI 表示や保存に使う現在再生位置を決める
    function CurrentPositionMs(UsePlaybackPosition: Boolean;
      SeekPositionMs, CurrentVideoPositionMs, SeekMaxMs: Integer): Integer;
    // 次の動画フレームを読み、終端やエラーを結果で返す
    function DecodeNextFrame(Decoder: TFFmpegDecoder; UseScratchFrame: Boolean;
      var ConvertFrame: Boolean; out PositionMs: Integer;
      out ErrorMessage: string): TVideoMinerPlaybackDecodeResult;
    // seek 直後に古いフレームが返る場合の初期破棄と補正を行う
    function HandleSeekGuard(Decoder: TFFmpegDecoder; const VideoFile: string;
      DebugLogEnabled: Boolean; SeekGuardTargetMs: Integer;
      var SeekGuardRemaining: Integer; var PositionMs: Integer;
      var CurrentVideoPositionMs: Integer; var ConvertFrame: Boolean;
      out ErrorMessage: string): TVideoMinerSeekGuardResult;
    // 音声より遅れた動画をフレーム破棄または音声位置 seek で補正する
    function HandleLaggingVideo(Decoder: TFFmpegDecoder; SeekMaxMs,
      AudioPositionMs, DropElapsedMs: Integer; var DropCount: Integer;
      var CurrentVideoPositionMs: Integer; var PositionMs: Integer;
      var ConvertFrame: Boolean; out ErrorMessage: string):
      TVideoMinerLaggingVideoResult;
    // scratch decode で現在位置より戻ったフレームを破棄すべきか判定する
    function ShouldDropBackwardScratchFrame(const VideoFile: string;
      DebugLogEnabled: Boolean; CurrentVideoPositionMs, PositionMs: Integer):
      Boolean;
    // scratch buffer に読んだフレームを動画ビューへ表示する
    function PresentScratchFrame(var ConvertFrame: Boolean;
      out ErrorMessage: string): Boolean;
    // 音声位置と動画位置の差分 ms を返す
    function PlaybackLagMs(AudioPositionMs, PositionMs: Integer): Integer;
    // 音声再生ラッパから見た現在の再生位置 ms を返す
    function PlaybackPositionMs: Integer;
    // 倍速用単調時計から現在の再生位置 ms を求める
    function RateClockPositionMs(SeekMaxMs: Integer): Integer;
    // 終了時動作を overlay 表示用の文字列へ変換する
    function EndActionText(EndAction: TVideoMinerEndAction): string;
    // 終了時動作を次の設定値へ進める
    function NextEndAction(EndAction: TVideoMinerEndAction):
      TVideoMinerEndAction;
    // 終端到達時に stop / loop / next のどれを行うか決める
    function FinishResult(EndAction: TVideoMinerEndAction;
      CanNavigateNext: Boolean): TVideoMinerPlaybackEndResult;
    // 終端到達時の停止、ループ再開、次ファイル移動を実行する
    procedure FinishAtEnd(EndAction: TVideoMinerEndAction;
      CanNavigateNext: Boolean; LoopStartMs, SeekMaxMs,
      LastFrameSeekPositionMs: Integer; var SeekPositionMs: Integer;
      var UpdatingSeek: Boolean;
      ShowFrameAtMs: TVideoMinerPlaybackFrameFunc;
      StartPlaybackAtMs: TVideoMinerPlaybackStartProc;
      NavigateNext: TVideoMinerPlaybackNotifyProc;
      UpdateInfo: TVideoMinerPlaybackNotifyProc);
    // 現在位置とチャプター状態からループ区間を更新する
    procedure ConfigureLoopSegment(EndAction: TVideoMinerEndAction;
      ChapterManager: TVideoMinerChapterManager; PositionMs, SeekMaxMs,
      LastFrameSeekPositionMs: Integer; var LoopSegmentStartMs,
      LoopSegmentEndMs: Integer);
    // 再生 tick の主要な所要時間と同期状態を debug log へ出力する
    procedure LogPlaybackTick(const VideoFile: string; AudioPositionMs,
      PositionMs, LagMs, DropCount: Integer; DidSeekToAudio: Boolean;
      PumpMs, DecodeMs, SyncMs, TotalMs: Double; TimerInterval: Integer);
    // tick 前に再生可能状態、音声 pump、音声位置を準備する
    function PrepareTick(IsSeeking, HasVideo: Boolean; SeekMaxMs: Integer;
      out AudioPositionMs: Integer; out ErrorMessage: string): Boolean;
    // tick 後にシークバーへ反映する位置を求める
    function SeekPositionForTick(PositionMs, AudioPositionMs,
      SeekMaxMs: Integer): Integer;
    // seek 後に指定位置から再生を再開する予約を入れる
    procedure ScheduleRestart(PositionMs: Integer; FrameAlreadyShown: Boolean = True;
      FastSeek: Boolean = False);
    // 再生速度を設定し、倍速用単調時計の状態を更新する
    procedure SetPlaybackRate(Value: Double);
    // 現在のループ区間終端に到達したか判定し、戻り先を返す
    function ShouldRestartLoop(EndAction: TVideoMinerEndAction;
      LoopSegmentStartMs, LoopSegmentEndMs, CurrentVideoPositionMs: Integer;
      PlaybackPositionMs: Integer; out TargetMs: Integer): Boolean;
    // デコーダと音声再生を指定位置から開始する
    function StartAtMs(Decoder: TFFmpegDecoder; const VideoFile: string;
      const VideoInfo: TVideoInfo; SeekMaxMs, PositionMs: Integer;
      FrameAlreadyShown: Boolean; FastSeek: Boolean; SkipVideoSeek: Boolean;
      out TargetMs: Integer; out ErrorMessage: string): Boolean;
    // 再生開始時の位置、音声、ループ区間、seek guard、表示状態をまとめて更新する
    procedure StartPlaybackAtMs(Decoder: TFFmpegDecoder; const VideoFile: string;
      const VideoInfo: TVideoInfo; EndAction: TVideoMinerEndAction;
      ChapterManager: TVideoMinerChapterManager; SeekMaxMs, PositionMs,
      LastFrameSeekPositionMs: Integer; FrameAlreadyShown: Boolean;
      FastSeek: Boolean; SkipVideoSeek: Boolean;
      var CurrentVideoPositionMs, SeekPositionMs, LoopSegmentStartMs,
      LoopSegmentEndMs, SeekGuardTargetMs, SeekGuardRemaining: Integer;
      SetStatus: TVideoMinerPlaybackStatusProc);
    // 動画を音声位置へ追従させるため、必要な位置のフレームを表示する
    function SyncVideoToAudio(Decoder: TFFmpegDecoder; SeekMaxMs: Integer;
      var PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 指定位置付近のフレーム表示を試し、失敗時は近い位置へ fallback する
    function ShowFrameNearMs(PositionMs, SeekMaxMs: Integer;
      out ShownPositionMs: Integer; out ErrorMessage: string): Boolean;
    // preview decoder の現在位置から次フレームを読むだけで済む場合は seek せず表示する
    function TryShowNextPreviewFrame(TargetMs, CurrentVideoPositionMs,
      SeekMaxMs: Integer; out ShownPositionMs: Integer;
      out ErrorMessage: string): Boolean;
    // 指定位置へ seek し、必要なら再生再開を予約する
    procedure SeekToMs(const VideoFile: string; PositionMs: Integer;
      ResumeIfPlaying: Boolean; SeekMaxMs: Integer;
      var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
      SeekGuardRemaining: Integer; var UpdatingSeek, Seeking: Boolean;
      SetStatus: TVideoMinerPlaybackStatusProc;
      UpdateInfo: TVideoMinerPlaybackNotifyProc);
    // 再生中の 1 tick 全体を進め、表示、同期、終端、チェックを処理する
    procedure Tick(Decoder: TFFmpegDecoder; const VideoFile: string;
      EndAction: TVideoMinerEndAction; IsSeeking: Boolean; SeekMaxMs,
      LoopSegmentStartMs, LoopSegmentEndMs: Integer;
      var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
      SeekGuardRemaining: Integer; var UpdatingSeek: Boolean;
      SetStatus: TVideoMinerPlaybackStatusProc;
      FinishPlaybackAtEnd: TVideoMinerPlaybackNotifyProc;
      SeekToMs: TVideoMinerPlaybackLoopSeekProc;
      UpdatePlaybackProgress: TVideoMinerPlaybackPositionProc;
      MaybeAutoCheckFrame: TVideoMinerPlaybackPositionProc);
    // seek のために現在の再生出力を停止する
    procedure StopForSeek;
    // 終端停止時の timer と表示状態を停止状態へ戻す
    procedure StopAtEnd;
    // 再生 timer、再開予約、音声出力を停止する
    procedure StopPlayback;
    property PlaybackRate: Double read FPlaybackRate write SetPlaybackRate;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.MMSystem, VideoMinerDebugLog,
  VideoMinerPlaybackTiming;

const
  SLOW_PREVIEW_LOG_MS           = 120;  // preview frame 表示を slow log に出す閾値 ms
  SLOW_START_LOG_MS             = 150;  // 再生開始処理を slow log に出す閾値 ms
  SLOW_TICK_LOG_MS              = 80;   // 再生 tick を slow log に出す閾値 ms
  RATE_TICK_LOG_MS              = 1000; // 倍速 tick ログを通常サンプル出力する間隔 ms
  RATE_LAG_LOG_MS               = 120;  // 倍速 tick ログを即時出力する同期ズレ幅 ms
  RATE_SLOW_LOG_MS              = 50;   // 倍速 tick ログを即時出力する処理時間 ms
  PREVIEW_NEXT_MAX_STEP_MS      = 80;   // preview decoder の順方向読みで代替する最大移動幅 ms
  PREVIEW_POSITION_TOLERANCE_MS = 3;    // preview decoder 位置と表示位置を同一視する許容誤差 ms
  VIDEO_AHEAD_SKIP_TOLERANCE_MS = 5;    // 音声より少し先の映像を進めず待つ許容差 ms

constructor TVideoMinerPlaybackController.Create(PlaybackTimer,
  RestartTimer: TTimer; AudioPlayback: TVideoMinerAudioPlayback;
  VideoView: TVideoMinerVideoView; PreviewDecoder: TFFmpegDecoder);
begin
  inherited Create;
  FPlaybackTimer := PlaybackTimer;
  FRestartTimer := RestartTimer;
  FAudioPlayback := AudioPlayback;
  FVideoView := VideoView;
  FPreviewDecoder := PreviewDecoder;
  FPlaybackRate := 1.0;
  FRateClockActive := False;
  FRateClockBaseMs := 0;
  FRateTickLogClock := TStopwatch.StartNew;
  FLastRateTickLogMs := -1;
  FRestartFastSeek := False;
  FRestartFrameAlreadyShown := True;
  FRestartPending := False;
  FRestartPositionMs := -1;
  FPreviewShownPositionMs := -1;
  FPreviewShownGeneration := -1;
  FTimerPeriodActive := False;
end;

destructor TVideoMinerPlaybackController.Destroy;
begin
  SetPlaybackTimerEnabled(False);
  inherited;
end;

procedure TVideoMinerPlaybackController.BeginPlaybackTimerPeriod;
begin
  if FTimerPeriodActive then
    Exit;

  if timeBeginPeriod(1) = TIMERR_NOERROR then
  begin
    FTimerPeriodActive := True;
    WriteVideoMinerRateLog('playback_timer_period_begin ms=1');
  end
  else
    WriteVideoMinerRateLog('playback_timer_period_begin_failed ms=1');
end;

procedure TVideoMinerPlaybackController.EndPlaybackTimerPeriod;
begin
  if not FTimerPeriodActive then
    Exit;

  timeEndPeriod(1);
  FTimerPeriodActive := False;
  WriteVideoMinerRateLog('playback_timer_period_end ms=1');
end;

procedure TVideoMinerPlaybackController.SetPlaybackTimerEnabled(
  Value: Boolean);
begin
  if Value then
    BeginPlaybackTimerPeriod;

  if FPlaybackTimer <> nil then
    FPlaybackTimer.Enabled := Value;

  if not Value then
    EndPlaybackTimerPeriod;
end;

function TVideoMinerPlaybackController.ActiveOrPending: Boolean;
begin
  Result := ((FPlaybackTimer <> nil) and FPlaybackTimer.Enabled) or
    FRestartPending or
    ((FRestartTimer <> nil) and FRestartTimer.Enabled);
end;

procedure TVideoMinerPlaybackController.ClearRestart;
begin
  FRestartPending := False;
  FRestartFastSeek := False;
  FRestartFrameAlreadyShown := True;
  FRestartPositionMs := -1;
  if FRestartTimer <> nil then
    FRestartTimer.Enabled := False;
end;

function TVideoMinerPlaybackController.ConsumeRestart(
  out PositionMs: Integer; out FrameAlreadyShown: Boolean;
  out FastSeek: Boolean): Boolean;
begin
  if FRestartTimer <> nil then
    FRestartTimer.Enabled := False;

  Result := FRestartPending;
  if not Result then
  begin
    PositionMs := -1;
    FrameAlreadyShown := True;
    FastSeek := False;
    Exit;
  end;

  FRestartPending := False;
  PositionMs := FRestartPositionMs;
  FrameAlreadyShown := FRestartFrameAlreadyShown;
  FastSeek := FRestartFastSeek;
  FRestartPositionMs := -1;
  FRestartFastSeek := False;
  FRestartFrameAlreadyShown := True;
end;

function TVideoMinerPlaybackController.CurrentPositionMs(
  UsePlaybackPosition: Boolean; SeekPositionMs, CurrentVideoPositionMs,
  SeekMaxMs: Integer): Integer;
begin
  if UsePlaybackPosition and FRateClockActive then
    Result := RateClockPositionMs(SeekMaxMs)
  else if UsePlaybackPosition and (FAudioPlayback <> nil) then
    Result := FAudioPlayback.PlaybackPositionMs
  else
    Result := SeekPositionMs;

  if Result < 0 then
  begin
    if CurrentVideoPositionMs >= 0 then
      Result := CurrentVideoPositionMs
    else
      Result := SeekPositionMs;
  end;

  if Result < 0 then
    Result := 0
  else if Result > SeekMaxMs then
    Result := SeekMaxMs;
end;

function TVideoMinerPlaybackController.DecodeNextFrame(Decoder: TFFmpegDecoder;
  UseScratchFrame: Boolean; var ConvertFrame: Boolean; out PositionMs: Integer;
  out ErrorMessage: string): TVideoMinerPlaybackDecodeResult;
var
  Decoded: Boolean;
begin
  Result := pdrFrame;
  ErrorMessage := '';
  if FVideoView = nil then
  begin
    ErrorMessage := 'Video view is not initialized.';
    Result := pdrError;
    Exit;
  end;

  if UseScratchFrame then
    Decoded := FVideoView.DecodeNextFrameToScratch(Decoder, PositionMs,
      ErrorMessage)
  else
    Decoded := FVideoView.DecodeNextFrame(Decoder, ConvertFrame, PositionMs,
      ErrorMessage);

  if Decoded then
    Exit;

  SetPlaybackTimerEnabled(False);
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;

  if ErrorMessage = 'End of stream.' then
    Result := pdrEndOfStream
  else
    Result := pdrError;
end;

function TVideoMinerPlaybackController.HandleSeekGuard(Decoder: TFFmpegDecoder;
  const VideoFile: string; DebugLogEnabled: Boolean; SeekGuardTargetMs: Integer;
  var SeekGuardRemaining: Integer; var PositionMs: Integer;
  var CurrentVideoPositionMs: Integer; var ConvertFrame: Boolean;
  out ErrorMessage: string): TVideoMinerSeekGuardResult;
begin
  Result := sgrNotGuarded;
  ErrorMessage := '';

  if (SeekGuardRemaining <= 0) or (PositionMs < 0) then
    Exit;

  if FVideoView = nil then
  begin
    ErrorMessage := 'Video view is not initialized.';
    Result := sgrGuardError;
    Exit;
  end;

  Dec(SeekGuardRemaining);
  if not VideoMinerSeekGuardAccepts(SeekGuardTargetMs, PositionMs) then
  begin
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'seek_guard_drop file="%s" target_ms=%d decoded_ms=%d remaining=%d',
        [ExtractFileName(VideoFile), SeekGuardTargetMs, PositionMs,
         SeekGuardRemaining]));

    if SeekGuardRemaining <= 0 then
    begin
      if FVideoView.ShowFrameAt(Decoder, SeekGuardTargetMs, ErrorMessage) then
      begin
        PositionMs := SeekGuardTargetMs;
        CurrentVideoPositionMs := SeekGuardTargetMs;
        Result := sgrSyncedToTarget;
        Exit;
      end;

      Result := sgrGuardError;
      Exit;
    end;

    Result := sgrContinue;
    Exit;
  end;

  SeekGuardRemaining := 0;
  if DebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'seek_guard_accept file="%s" target_ms=%d decoded_ms=%d present=False',
      [ExtractFileName(VideoFile), SeekGuardTargetMs, PositionMs]));
  ConvertFrame := True;
  Result := sgrAccepted;
end;

function TVideoMinerPlaybackController.HandleLaggingVideo(
  Decoder: TFFmpegDecoder; SeekMaxMs, AudioPositionMs, DropElapsedMs: Integer;
  var DropCount: Integer; var CurrentVideoPositionMs: Integer;
  var PositionMs: Integer; var ConvertFrame: Boolean;
  out ErrorMessage: string): TVideoMinerLaggingVideoResult;
begin
  Result := lvrNoAction;
  ErrorMessage := '';

  if not VideoMinerVideoLagsAudio(CurrentVideoPositionMs, AudioPositionMs) then
    Exit;

  if FVideoView = nil then
  begin
    ErrorMessage := 'Video view is not initialized.';
    Result := lvrError;
    Exit;
  end;

  if VideoMinerShouldDropFrame(CurrentVideoPositionMs, AudioPositionMs,
    DropCount, DropElapsedMs) then
  begin
    ConvertFrame := False;
    Inc(DropCount);
    Result := lvrDropped;
    Exit;
  end;

  if VideoMinerNearEnd(SeekMaxMs, AudioPositionMs) then
  begin
    ErrorMessage := '';
    PositionMs := AudioPositionMs;
    CurrentVideoPositionMs := AudioPositionMs;
    Result := lvrSyncedToAudio;
    Exit;
  end;

  Result := lvrNoAction;
end;

function TVideoMinerPlaybackController.EndActionText(
  EndAction: TVideoMinerEndAction): string;
begin
  case EndAction of
    eaLoop:
      Result := 'Loop';
    eaNext:
      Result := 'Next';
  else
    Result := 'Stop';
  end;
end;

function TVideoMinerPlaybackController.FinishResult(
  EndAction: TVideoMinerEndAction;
  CanNavigateNext: Boolean): TVideoMinerPlaybackEndResult;
begin
  case EndAction of
    eaLoop:
      Result := perLoop;
    eaNext:
      begin
        if CanNavigateNext then
          Result := perNext
        else
          Result := perStop;
      end;
  else
    Result := perStop;
  end;
end;

procedure TVideoMinerPlaybackController.FinishAtEnd(
  EndAction: TVideoMinerEndAction; CanNavigateNext: Boolean; LoopStartMs,
  SeekMaxMs, LastFrameSeekPositionMs: Integer; var SeekPositionMs: Integer;
  var UpdatingSeek: Boolean;
  ShowFrameAtMs: TVideoMinerPlaybackFrameFunc;
  StartPlaybackAtMs: TVideoMinerPlaybackStartProc;
  NavigateNext: TVideoMinerPlaybackNotifyProc;
  UpdateInfo: TVideoMinerPlaybackNotifyProc);
var
  FrameShown: Boolean;
  LoopFrameCacheShown: Boolean;
  StopFrameMs: Integer;
begin
  case FinishResult(EndAction, CanNavigateNext) of
    perLoop:
      begin
        if FVideoView <> nil then
          FVideoView.PlaybackActive := True;
        LoopFrameCacheShown := (FVideoView <> nil) and
          FVideoView.TryPresentLoopFrameCache(LoopStartMs);
        WriteVideoMinerRateLog(Format(
          'finish_at_end_loop_summary target_ms=%d cache_shown=%s',
          [LoopStartMs, BoolToStr(LoopFrameCacheShown, True)]));
{$IFDEF DEBUG}
        WriteVideoMinerSlowLog(Format(
          'finish_at_end_loop target_ms=%d cache_shown=%s',
          [LoopStartMs, BoolToStr(LoopFrameCacheShown, True)]));
{$ENDIF}
        UpdatingSeek := True;
        try
          SeekPositionMs := LoopStartMs;
        finally
          UpdatingSeek := False;
        end;
        FrameShown := LoopFrameCacheShown;
        if (not FrameShown) and Assigned(ShowFrameAtMs) then
          FrameShown := ShowFrameAtMs(LoopStartMs);
        if Assigned(StartPlaybackAtMs) then
          StartPlaybackAtMs(LoopStartMs, FrameShown);
        Exit;
      end;
    perNext:
      begin
        if Assigned(NavigateNext) then
          NavigateNext;
        Exit;
      end;
  end;

  StopFrameMs := LastFrameSeekPositionMs;
  if StopFrameMs < 0 then
    StopFrameMs := SeekMaxMs
  else if StopFrameMs > SeekMaxMs then
    StopFrameMs := SeekMaxMs;

  UpdatingSeek := True;
  try
    SeekPositionMs := StopFrameMs;
  finally
    UpdatingSeek := False;
  end;
  FrameShown := Assigned(ShowFrameAtMs) and ShowFrameAtMs(StopFrameMs);
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'finish_at_end_stop seek_max_ms=%d last_frame_ms=%d shown=%s',
    [SeekMaxMs, StopFrameMs, BoolToStr(FrameShown, True)]));
{$ENDIF}
  StopAtEnd;
  if Assigned(UpdateInfo) then
    UpdateInfo;
end;

procedure TVideoMinerPlaybackController.ConfigureLoopSegment(
  EndAction: TVideoMinerEndAction; ChapterManager: TVideoMinerChapterManager;
  PositionMs, SeekMaxMs, LastFrameSeekPositionMs: Integer;
  var LoopSegmentStartMs, LoopSegmentEndMs: Integer);
var
  Segment: TVideoMinerLoopSegment;
begin
  if (EndAction <> eaLoop) or (SeekMaxMs <= 0) then
  begin
    LoopSegmentStartMs := -1;
    LoopSegmentEndMs := -1;
    Exit;
  end;

  if ChapterManager = nil then
  begin
    LoopSegmentStartMs := 0;
    LoopSegmentEndMs := LastFrameSeekPositionMs;
    Exit;
  end;

  Segment := ChapterManager.LoopSegmentForPosition(PositionMs,
    LastFrameSeekPositionMs);
  LoopSegmentStartMs := Segment.StartMs;
  LoopSegmentEndMs := Segment.EndMs;
end;

function TVideoMinerPlaybackController.NextEndAction(
  EndAction: TVideoMinerEndAction): TVideoMinerEndAction;
begin
  case EndAction of
    eaStop:
      Result := eaLoop;
    eaLoop:
      Result := eaNext;
  else
    Result := eaStop;
  end;
end;

function TVideoMinerPlaybackController.PrepareTick(IsSeeking,
  HasVideo: Boolean; SeekMaxMs: Integer; out AudioPositionMs: Integer;
  out ErrorMessage: string): Boolean;
begin
  Result := False;
  AudioPositionMs := -1;
  ErrorMessage := '';

  if IsSeeking then
    Exit;

  if not HasVideo then
  begin
    SetPlaybackTimerEnabled(False);
    if FVideoView <> nil then
      FVideoView.PlaybackActive := False;
    Exit;
  end;

  if FAudioPlayback = nil then
  begin
    ErrorMessage := 'Audio playback is not initialized.';
    Exit;
  end;

  if not FAudioPlayback.Pump(ErrorMessage) then
  begin
    ErrorMessage := 'Failed to play audio: ' + ErrorMessage;
    Exit;
  end;

  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if (AudioPositionMs < 0) and FRateClockActive then
    AudioPositionMs := RateClockPositionMs(SeekMaxMs)
  else if (AudioPositionMs < 0) and (not SameValue(FPlaybackRate, 1.0)) then
  begin
    FRateClockBaseMs := 0;
    FRateClock := TStopwatch.StartNew;
    FRateClockActive := True;
    AudioPositionMs := RateClockPositionMs(SeekMaxMs);
  end;
  if AudioPositionMs > SeekMaxMs then
    AudioPositionMs := SeekMaxMs;

  Result := True;
end;

function TVideoMinerPlaybackController.PresentScratchFrame(
  var ConvertFrame: Boolean; out ErrorMessage: string): Boolean;
begin
  if FVideoView = nil then
  begin
    ErrorMessage := 'Video view is not initialized.';
    Result := False;
    Exit;
  end;

  Result := FVideoView.PresentScratchFrame(ErrorMessage);
  if Result then
    ConvertFrame := True;
end;

function TVideoMinerPlaybackController.PlaybackLagMs(AudioPositionMs,
  PositionMs: Integer): Integer;
begin
  if (AudioPositionMs >= 0) and (PositionMs >= 0) then
    Result := AudioPositionMs - PositionMs
  else
    Result := 0;
end;

function TVideoMinerPlaybackController.PlaybackPositionMs: Integer;
begin
  if FRateClockActive then
    Result := RateClockPositionMs(MaxInt)
  else if FAudioPlayback <> nil then
    Result := FAudioPlayback.PlaybackPositionMs
  else
    Result := -1;
end;

function TVideoMinerPlaybackController.RateClockPositionMs(
  SeekMaxMs: Integer): Integer;
begin
  if not FRateClockActive then
  begin
    Result := -1;
    Exit;
  end;

  Result := FRateClockBaseMs +
    Round(FRateClock.Elapsed.TotalMilliseconds * FPlaybackRate);
  if Result < 0 then
    Result := 0
  else if (SeekMaxMs >= 0) and (Result > SeekMaxMs) then
    Result := SeekMaxMs;
end;

procedure TVideoMinerPlaybackController.LogPlaybackTick(const VideoFile: string;
  AudioPositionMs, PositionMs, LagMs, DropCount: Integer;
  DidSeekToAudio: Boolean; PumpMs, DecodeMs, SyncMs, TotalMs: Double;
  TimerInterval: Integer);
begin
{$IFDEF DEBUG}
  WriteVideoMinerDebugLog(Format(
    'playback_tick file="%s" audio_ms=%d video_ms=%d lag_ms=%d drop_count=%d seek_to_audio=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f timer_interval=%d',
    [ExtractFileName(VideoFile), AudioPositionMs, PositionMs, LagMs, DropCount,
     BoolToStr(DidSeekToAudio, True), PumpMs, DecodeMs, SyncMs, TotalMs,
     TimerInterval]));
{$ENDIF}
end;

procedure TVideoMinerPlaybackController.ScheduleRestart(PositionMs: Integer;
  FrameAlreadyShown: Boolean; FastSeek: Boolean);
begin
  FRestartPending := True;
  FRestartPositionMs := PositionMs;
  FRestartFastSeek := FastSeek;
  FRestartFrameAlreadyShown := FrameAlreadyShown;
  if FRestartTimer <> nil then
  begin
    FRestartTimer.Enabled := False;
    FRestartTimer.Enabled := True;
  end;
end;

procedure TVideoMinerPlaybackController.SetPlaybackRate(Value: Double);
var
  OldRate: Double;
begin
  if Value <= 0 then
    Value := 1.0;
  if SameValue(FPlaybackRate, Value) then
    Exit;

  OldRate := FPlaybackRate;
  FPlaybackRate := Value;
  FRateTickLogClock := TStopwatch.StartNew;
  FLastRateTickLogMs := -1;
  WriteVideoMinerRateLog(Format('rate_change old_rate=%.3f new_rate=%.3f',
    [OldRate, FPlaybackRate]));
end;

function TVideoMinerPlaybackController.SeekPositionForTick(PositionMs,
  AudioPositionMs, SeekMaxMs: Integer): Integer;
begin
  Result := PositionMs;
  if PositionMs < 0 then
    Exit;

  if AudioPositionMs >= 0 then
    Result := AudioPositionMs
  else if PositionMs > SeekMaxMs then
    Result := SeekMaxMs;
end;

function TVideoMinerPlaybackController.ShowFrameNearMs(PositionMs,
  SeekMaxMs: Integer; out ShownPositionMs: Integer;
  out ErrorMessage: string): Boolean;
const
  FALLBACK_OFFSETS: array[0..10] of Integer =
    (0, -33, 33, -100, 100, -250, 250, -500, 500, -1000, 1000);
var
  AttemptMs: Integer;
  I: Integer;
  LastErrorMessage: string;
  TriedPositions: array[0..High(FALLBACK_OFFSETS)] of Integer;
  TriedCount: Integer;
  J: Integer;
  AlreadyTried: Boolean;
{$IFDEF DEBUG}
  TotalWatch: TStopwatch;
  TotalMs: Double;
{$ENDIF}
begin
  Result := False;
{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;
{$ENDIF}
  ShownPositionMs := PositionMs;
  ErrorMessage := '';
  LastErrorMessage := '';
  TriedCount := 0;
  if (FVideoView = nil) or (FPreviewDecoder = nil) then
  begin
    ErrorMessage := 'Preview video view is not initialized.';
    Exit;
  end;

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format('show_frame_near_begin target_ms=%d seek_max_ms=%d',
    [PositionMs, SeekMaxMs]));
{$ENDIF}

  for I := Low(FALLBACK_OFFSETS) to High(FALLBACK_OFFSETS) do
  begin
    AttemptMs := PositionMs + FALLBACK_OFFSETS[I];
    if AttemptMs < 0 then
      AttemptMs := 0
    else if AttemptMs > SeekMaxMs then
      AttemptMs := SeekMaxMs;

    AlreadyTried := False;
    for J := 0 to TriedCount - 1 do
    begin
      if TriedPositions[J] = AttemptMs then
      begin
        AlreadyTried := True;
        Break;
      end;
    end;
    if AlreadyTried then
      Continue;

    TriedPositions[TriedCount] := AttemptMs;
    Inc(TriedCount);

{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format('show_frame_near_attempt attempt_ms=%d',
      [AttemptMs]));
{$ENDIF}
    if FVideoView.ShowFrameAt(FPreviewDecoder, AttemptMs,
      LastErrorMessage) then
    begin
      ShownPositionMs := AttemptMs;
      FPreviewShownPositionMs := ShownPositionMs;
      FPreviewShownGeneration := FPreviewDecoder.DecodeGeneration;
      Result := True;
{$IFDEF DEBUG}
      TotalMs := TotalWatch.Elapsed.TotalMilliseconds;
      if TotalMs >= SLOW_PREVIEW_LOG_MS then
        WriteVideoMinerSlowLog(Format(
          'show_frame_near_slow target_ms=%d shown_ms=%d attempts=%d total_ms=%.3f',
          [PositionMs, ShownPositionMs, TriedCount, TotalMs]));
{$ENDIF}
      Exit;
    end;
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format('show_frame_near_attempt_failed attempt_ms=%d err="%s"',
      [AttemptMs, LastErrorMessage]));
{$ENDIF}
  end;

  ErrorMessage := LastErrorMessage;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'show_frame_near_failed target_ms=%d attempts=%d total_ms=%.3f err="%s"',
    [PositionMs, TriedCount, TotalWatch.Elapsed.TotalMilliseconds,
     ErrorMessage]));
{$ENDIF}
end;

function TVideoMinerPlaybackController.TryShowNextPreviewFrame(TargetMs,
  CurrentVideoPositionMs, SeekMaxMs: Integer; out ShownPositionMs: Integer;
  out ErrorMessage: string): Boolean;
var
  NextPositionMs: Integer;
{$IFDEF DEBUG}
  TotalWatch: TStopwatch;
{$ENDIF}
begin
  Result := False;
  ShownPositionMs := TargetMs;
  ErrorMessage := '';
  if (FVideoView = nil) or (FPreviewDecoder = nil) or
     (FPreviewShownPositionMs < 0) then
    Exit;
  if FPreviewShownGeneration <> FPreviewDecoder.DecodeGeneration then
    Exit;
  if TargetMs <= FPreviewShownPositionMs then
    Exit;
  if TargetMs > SeekMaxMs then
    Exit;
  if TargetMs - FPreviewShownPositionMs > PREVIEW_NEXT_MAX_STEP_MS then
    Exit;
  if Abs(CurrentVideoPositionMs - FPreviewShownPositionMs) >
     PREVIEW_POSITION_TOLERANCE_MS then
    Exit;

{$IFDEF DEBUG}
  TotalWatch := TStopwatch.StartNew;
  WriteVideoMinerSlowLog(Format(
    'show_frame_next_begin target_ms=%d preview_ms=%d current_ms=%d',
    [TargetMs, FPreviewShownPositionMs, CurrentVideoPositionMs]));
{$ENDIF}
  if not FVideoView.DecodeNextFrame(FPreviewDecoder, True, NextPositionMs,
    ErrorMessage) then
  begin
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'show_frame_next_failed target_ms=%d preview_ms=%d err="%s"',
      [TargetMs, FPreviewShownPositionMs, ErrorMessage]));
{$ENDIF}
    Exit;
  end;

  ShownPositionMs := NextPositionMs;
  FPreviewShownPositionMs := NextPositionMs;
  FPreviewShownGeneration := FPreviewDecoder.DecodeGeneration;
  Result := True;
{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'show_frame_next_done target_ms=%d shown_ms=%d total_ms=%.3f',
    [TargetMs, ShownPositionMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

procedure TVideoMinerPlaybackController.SeekToMs(const VideoFile: string;
  PositionMs: Integer; ResumeIfPlaying: Boolean; SeekMaxMs: Integer;
  var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
  SeekGuardRemaining: Integer; var UpdatingSeek, Seeking: Boolean;
  SetStatus: TVideoMinerPlaybackStatusProc;
  UpdateInfo: TVideoMinerPlaybackNotifyProc);
var
  ErrorMessage: string;
  OpenInfo: TVideoInfo;
  ShownPositionMs: Integer;
  TargetMs: Integer;
  WasPlaying: Boolean;
{$IFDEF DEBUG}
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  StopMs: Double;
  PreviewMs: Double;
  DebugLogEnabled: Boolean;
{$ENDIF}
  FastRestart: Boolean;
  ReverseSeek: Boolean;
begin
  if (VideoFile = '') or (SeekMaxMs <= 0) then
    Exit;

{$IFDEF DEBUG}
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  TotalWatch := TStopwatch.StartNew;
{$ENDIF}

  WasPlaying := ActiveOrPending;
{$IFDEF DEBUG}
  StepWatch := TStopwatch.StartNew;
{$ENDIF}
  StopForSeek;
{$IFDEF DEBUG}
  StopMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > SeekMaxMs then
    TargetMs := SeekMaxMs;
  ReverseSeek := (CurrentVideoPositionMs >= 0) and
    (TargetMs < CurrentVideoPositionMs);

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'seek_begin target_ms=%d requested_ms=%d current_ms=%d reverse=%s was_playing=%s resume_if_playing=%s stop_ms=%.3f',
    [TargetMs, PositionMs, CurrentVideoPositionMs,
     BoolToStr(ReverseSeek, True), BoolToStr(WasPlaying, True),
     BoolToStr(ResumeIfPlaying, True), StopMs]));
{$ENDIF}

  if ReverseSeek then
  begin
    FPreviewShownPositionMs := -1;
    FPreviewShownGeneration := -1;
    if FPreviewDecoder <> nil then
    begin
      FPreviewDecoder.Close;
      if not FPreviewDecoder.Open(VideoFile, OpenInfo, ErrorMessage) then
      begin
{$IFDEF DEBUG}
        WriteVideoMinerSlowLog(Format(
          'seek_reverse_preview_reopen_failed target_ms=%d current_ms=%d err="%s"',
          [TargetMs, CurrentVideoPositionMs, ErrorMessage]));
{$ENDIF}
        if Assigned(SetStatus) then
          SetStatus('Failed to reopen preview decoder: ' + ErrorMessage);
        Exit;
      end;
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'seek_reverse_preview_reopen target_ms=%d current_ms=%d',
        [TargetMs, CurrentVideoPositionMs]));
{$ENDIF}
    end;
  end;

{$IFDEF DEBUG}
  PreviewMs := 0;
{$ENDIF}
  FastRestart := False;
  Seeking := True;
  try
    if FastRestart then
    begin
      ShownPositionMs := TargetMs;
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'seek_fast_restart target_ms=%d stop_ms=%.3f total_ms=%.3f',
        [TargetMs, StopMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
    end
    else
    begin
{$IFDEF DEBUG}
      StepWatch := TStopwatch.StartNew;
{$ENDIF}
      if (not WasPlaying) and TryShowNextPreviewFrame(TargetMs,
        CurrentVideoPositionMs, SeekMaxMs, ShownPositionMs, ErrorMessage) then
      begin
{$IFDEF DEBUG}
        WriteVideoMinerSlowLog(Format(
          'seek_preview_next target_ms=%d shown_ms=%d',
          [TargetMs, ShownPositionMs]));
{$ENDIF}
      end
      else if not ShowFrameNearMs(TargetMs, SeekMaxMs, ShownPositionMs,
        ErrorMessage) then
      begin
{$IFDEF DEBUG}
        PreviewMs := StepWatch.Elapsed.TotalMilliseconds;
        if DebugLogEnabled then
          WriteVideoMinerDebugLog(Format(
            'seek_failed step="preview" target_ms=%d was_playing=%s stop_ms=%.3f preview_ms=%.3f total_ms=%.3f err="%s"',
            [TargetMs, BoolToStr(WasPlaying, True), StopMs, PreviewMs,
             TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
        if Assigned(SetStatus) then
          SetStatus('Failed to decode frame: ' + ErrorMessage);
        Exit;
      end;
{$IFDEF DEBUG}
      PreviewMs := StepWatch.Elapsed.TotalMilliseconds;
{$ENDIF}
    end;

    CurrentVideoPositionMs := ShownPositionMs;
    UpdatingSeek := True;
    try
      SeekPositionMs := ShownPositionMs;
    finally
      UpdatingSeek := False;
    end;

    if Assigned(UpdateInfo) then
      UpdateInfo;
    SeekGuardTargetMs := ShownPositionMs;
    if ResumeIfPlaying and WasPlaying and (ShownPositionMs < SeekMaxMs) then
      SeekGuardRemaining := VideoMinerDefaultSeekGuardFrames
    else
      SeekGuardRemaining := 0;
  finally
    Seeking := False;
  end;

  if ResumeIfPlaying and WasPlaying and (ShownPositionMs < SeekMaxMs) then
    ScheduleRestart(ShownPositionMs, not FastRestart, FastRestart);

{$IFDEF DEBUG}
  WriteVideoMinerSlowLog(Format(
    'seek_done target_ms=%d shown_ms=%d was_playing=%s resume=%s guard_target_ms=%d guard_remaining=%d stop_ms=%.3f preview_ms=%.3f total_ms=%.3f',
    [TargetMs, ShownPositionMs, BoolToStr(WasPlaying, True),
     BoolToStr(ResumeIfPlaying and WasPlaying and (ShownPositionMs < SeekMaxMs), True),
     SeekGuardTargetMs, SeekGuardRemaining, StopMs, PreviewMs,
     TotalWatch.Elapsed.TotalMilliseconds]));
  if (TotalWatch.Elapsed.TotalMilliseconds >= SLOW_START_LOG_MS) or
     (StopMs >= SLOW_PREVIEW_LOG_MS) or (PreviewMs >= SLOW_PREVIEW_LOG_MS) then
    WriteVideoMinerSlowLog(Format(
      'seek_slow target_ms=%d shown_ms=%d was_playing=%s resume=%s stop_ms=%.3f preview_ms=%.3f total_ms=%.3f',
      [TargetMs, ShownPositionMs, BoolToStr(WasPlaying, True),
       BoolToStr(ResumeIfPlaying and WasPlaying and (ShownPositionMs < SeekMaxMs), True),
       StopMs, PreviewMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
end;

function TVideoMinerPlaybackController.ShouldRestartLoop(
  EndAction: TVideoMinerEndAction; LoopSegmentStartMs, LoopSegmentEndMs,
  CurrentVideoPositionMs, PlaybackPositionMs: Integer;
  out TargetMs: Integer): Boolean;
var
  EffectivePositionMs: Integer;
begin
  TargetMs := LoopSegmentStartMs;
  EffectivePositionMs := CurrentVideoPositionMs;
  if PlaybackPositionMs >= 0 then
    EffectivePositionMs := Max(EffectivePositionMs, PlaybackPositionMs);
  Result := (EndAction = eaLoop) and (LoopSegmentStartMs >= 0) and
    (LoopSegmentEndMs > LoopSegmentStartMs) and
    (EffectivePositionMs >= LoopSegmentEndMs);
end;

function TVideoMinerPlaybackController.StartAtMs(Decoder: TFFmpegDecoder;
  const VideoFile: string; const VideoInfo: TVideoInfo; SeekMaxMs,
  PositionMs: Integer; FrameAlreadyShown: Boolean; FastSeek: Boolean;
  SkipVideoSeek: Boolean; out TargetMs: Integer; out ErrorMessage: string): Boolean;
var
  OpenInfo: TVideoInfo;
  ReuseErrorMessage: string;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  VideoPrepareMs: Double;
  VideoSeekMs: Double;
  AudioStartMs: Double;
  VideoReopened: Boolean;
  DebugLogEnabled: Boolean;
begin
  Result := False;
  ErrorMessage := '';
  DebugLogEnabled := VideoMinerDebugLogEnabled;

  if VideoFile = '' then
    Exit;

  if (FVideoView = nil) or (FAudioPlayback = nil) or
     (FPlaybackTimer = nil) then
  begin
    ErrorMessage := 'Playback controller is not initialized.';
    Exit;
  end;

  TotalWatch := TStopwatch.StartNew;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > SeekMaxMs then
    TargetMs := SeekMaxMs;

{$IFDEF DEBUG}
  if DebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'start_playback file="%s" requested_ms=%d target_ms=%d frame_already_shown=%s',
      [ExtractFileName(VideoFile), PositionMs, TargetMs,
       BoolToStr(FrameAlreadyShown, True)]));
{$ENDIF}

  VideoPrepareMs := 0;
  VideoReopened := False;
  VideoSeekMs := 0;

  if not SkipVideoSeek then
  begin
    StepWatch := TStopwatch.StartNew;
    if not FVideoView.ShowFrameAt(Decoder, TargetMs, ReuseErrorMessage,
      not FrameAlreadyShown, FastSeek) then
    begin
      VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
      WriteVideoMinerRateLog(Format(
        'start_playback_reuse_failed_summary file="%s" target_ms=%d frame_already_shown=%s fast_seek=%s video_seek_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(VideoFile), TargetMs, BoolToStr(FrameAlreadyShown, True),
         BoolToStr(FastSeek, True), VideoSeekMs,
         TotalWatch.Elapsed.TotalMilliseconds, ReuseErrorMessage]));
{$IFDEF DEBUG}
      if DebugLogEnabled then
        WriteVideoMinerDebugLog(Format(
          'start_playback_reuse_failed file="%s" target_ms=%d video_seek_ms=%.3f total_ms=%.3f err="%s"',
          [ExtractFileName(VideoFile), TargetMs, VideoSeekMs,
           TotalWatch.Elapsed.TotalMilliseconds, ReuseErrorMessage]));
{$ENDIF}
{$IFDEF DEBUG}
      WriteVideoMinerSlowLog(Format(
        'start_playback_reuse_failed file="%s" target_ms=%d video_seek_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(VideoFile), TargetMs, VideoSeekMs,
         TotalWatch.Elapsed.TotalMilliseconds, ReuseErrorMessage]));
{$ENDIF}

      StepWatch := TStopwatch.StartNew;
      Decoder.Close;
      if not Decoder.Open(VideoFile, OpenInfo, ErrorMessage) then
      begin
        VideoPrepareMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
        if DebugLogEnabled then
          WriteVideoMinerDebugLog(Format(
            'start_playback_failed step="video_open_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f total_ms=%.3f err="%s"',
            [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs,
             TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
{$IFDEF DEBUG}
        WriteVideoMinerSlowLog(Format(
          'start_playback_failed step="video_open_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f total_ms=%.3f err="%s"',
          [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs,
           TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
        if FVideoView <> nil then
          FVideoView.PlaybackActive := False;
        ErrorMessage := 'Failed to reopen video decoder: ' + ErrorMessage;
        Exit;
      end;
      VideoPrepareMs := StepWatch.Elapsed.TotalMilliseconds;
      VideoReopened := True;

      StepWatch := TStopwatch.StartNew;
      if not FVideoView.ShowFrameAt(Decoder, TargetMs, ErrorMessage,
        not FrameAlreadyShown, FastSeek) then
      begin
        VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
        if DebugLogEnabled then
          WriteVideoMinerDebugLog(Format(
            'start_playback_failed step="video_seek_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f total_ms=%.3f err="%s"',
            [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
             TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
{$IFDEF DEBUG}
        WriteVideoMinerSlowLog(Format(
          'start_playback_failed step="video_seek_fallback" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f total_ms=%.3f err="%s"',
          [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
           TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
        if FVideoView <> nil then
          FVideoView.PlaybackActive := False;
        ErrorMessage := 'Failed to seek video decoder: ' + ErrorMessage;
        Exit;
      end;
    end;
    VideoSeekMs := StepWatch.Elapsed.TotalMilliseconds;
  end;

  FAudioPlayback.PlaybackRate := FPlaybackRate;
  FRateClockActive := False;
  StepWatch := TStopwatch.StartNew;
  if not FAudioPlayback.StartAt(VideoFile, VideoInfo, TargetMs,
    ErrorMessage) then
  begin
    AudioStartMs := StepWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'start_playback_failed step="audio_start" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f err="%s"',
        [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
         AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'start_playback_failed step="audio_start" file="%s" target_ms=%d video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f err="%s"',
      [ExtractFileName(VideoFile), TargetMs, VideoPrepareMs, VideoSeekMs,
       AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds, ErrorMessage]));
{$ENDIF}
    if FVideoView <> nil then
      FVideoView.PlaybackActive := False;
    ErrorMessage := 'Failed to start audio playback: ' + ErrorMessage;
    Exit;
  end;
  AudioStartMs := StepWatch.Elapsed.TotalMilliseconds;
  if (not SameValue(FPlaybackRate, 1.0)) and
     (FAudioPlayback.PlaybackPositionMs < 0) then
  begin
    FRateClockBaseMs := TargetMs;
    FRateClock := TStopwatch.StartNew;
    FRateClockActive := True;
  end;

  FPlaybackTimer.Interval := Max(1, VideoMinerPlaybackTimerIntervalMs(
    VideoInfo.Fps, FPlaybackRate) div 2);
  SetPlaybackTimerEnabled(True);
  FVideoView.PlaybackActive := True;
  WriteVideoMinerRateLog(Format(
    'start_playback_summary file="%s" target_ms=%d frame_already_shown=%s video_reopen=%s video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f',
    [ExtractFileName(VideoFile), TargetMs, BoolToStr(FrameAlreadyShown, True),
     BoolToStr(VideoReopened, True), VideoPrepareMs, VideoSeekMs,
     AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$IFDEF DEBUG}
  if DebugLogEnabled then
    WriteVideoMinerDebugLog(Format(
      'start_playback_done file="%s" target_ms=%d frame_already_shown=%s video_reopen=%s video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f',
      [ExtractFileName(VideoFile), TargetMs, BoolToStr(FrameAlreadyShown, True),
       BoolToStr(VideoReopened, True), VideoPrepareMs, VideoSeekMs,
       AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
  if not SameValue(FPlaybackRate, 1.0) then
    WriteVideoMinerRateLog(Format(
      'start_playback_rate file="%s" rate=%.3f target_ms=%d frame_already_shown=%s rate_clock_active=%s video_reopen=%s video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f',
      [ExtractFileName(VideoFile), FPlaybackRate, TargetMs,
       BoolToStr(FrameAlreadyShown, True), BoolToStr(FRateClockActive, True),
       BoolToStr(VideoReopened, True), VideoPrepareMs, VideoSeekMs,
       AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$IFDEF DEBUG}
  if (TotalWatch.Elapsed.TotalMilliseconds >= SLOW_START_LOG_MS) or
     (VideoSeekMs >= SLOW_PREVIEW_LOG_MS) or
     (AudioStartMs >= SLOW_PREVIEW_LOG_MS) then
    WriteVideoMinerSlowLog(Format(
      'start_playback_slow file="%s" target_ms=%d frame_already_shown=%s video_reopen=%s video_prepare_ms=%.3f video_seek_ms=%.3f audio_start_ms=%.3f total_ms=%.3f',
      [ExtractFileName(VideoFile), TargetMs, BoolToStr(FrameAlreadyShown, True),
       BoolToStr(VideoReopened, True), VideoPrepareMs, VideoSeekMs,
       AudioStartMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}

  Result := True;
end;

procedure TVideoMinerPlaybackController.StartPlaybackAtMs(
  Decoder: TFFmpegDecoder; const VideoFile: string; const VideoInfo: TVideoInfo;
  EndAction: TVideoMinerEndAction; ChapterManager: TVideoMinerChapterManager;
  SeekMaxMs, PositionMs, LastFrameSeekPositionMs: Integer;
  FrameAlreadyShown: Boolean; FastSeek: Boolean; SkipVideoSeek: Boolean;
  var CurrentVideoPositionMs, SeekPositionMs,
  LoopSegmentStartMs, LoopSegmentEndMs, SeekGuardTargetMs,
  SeekGuardRemaining: Integer; SetStatus: TVideoMinerPlaybackStatusProc);
var
  ErrorMessage: string;
  EffectiveFrameAlreadyShown: Boolean;
  FrameToleranceMs: Integer;
  RequestedTargetMs: Integer;
  TargetMs: Integer;
begin
  if VideoFile = '' then
    Exit;

  RequestedTargetMs := PositionMs;
  if RequestedTargetMs < 0 then
    RequestedTargetMs := 0
  else if RequestedTargetMs > SeekMaxMs then
    RequestedTargetMs := SeekMaxMs;

  EffectiveFrameAlreadyShown := FrameAlreadyShown;
  if not EffectiveFrameAlreadyShown then
  begin
    FrameToleranceMs := VideoMinerFrameDurationMs(VideoInfo.Fps);
    EffectiveFrameAlreadyShown := (CurrentVideoPositionMs >= 0) and
      (Abs(CurrentVideoPositionMs - RequestedTargetMs) <= FrameToleranceMs);
  end;

  if not StartAtMs(Decoder, VideoFile, VideoInfo, SeekMaxMs, PositionMs,
    EffectiveFrameAlreadyShown, FastSeek, SkipVideoSeek and EffectiveFrameAlreadyShown,
    TargetMs, ErrorMessage) then
  begin
    if (ErrorMessage <> '') and Assigned(SetStatus) then
      SetStatus(ErrorMessage);
    Exit;
  end;

  CurrentVideoPositionMs := TargetMs;
  SeekPositionMs := TargetMs;
  ConfigureLoopSegment(EndAction, ChapterManager, TargetMs, SeekMaxMs,
    LastFrameSeekPositionMs, LoopSegmentStartMs, LoopSegmentEndMs);
  if (EndAction = eaLoop) and (FVideoView <> nil) and
     (LoopSegmentStartMs = TargetMs) then
    FVideoView.BeginLoopFrameCacheCapture(TargetMs, True);

  SeekGuardTargetMs := TargetMs;
  SeekGuardRemaining := VideoMinerDefaultSeekGuardFrames;
end;

function TVideoMinerPlaybackController.ShouldDropBackwardScratchFrame(
  const VideoFile: string; DebugLogEnabled: Boolean; CurrentVideoPositionMs,
  PositionMs: Integer): Boolean;
begin
  Result := VideoMinerBackwardScratchFrame(PositionMs, CurrentVideoPositionMs);
  if Result and DebugLogEnabled then
{$IFDEF DEBUG}
    WriteVideoMinerDebugLog(Format(
      'playback_backward_drop file="%s" current_ms=%d decoded_ms=%d',
      [ExtractFileName(VideoFile), CurrentVideoPositionMs, PositionMs]));
{$ENDIF}
end;

function TVideoMinerPlaybackController.SyncVideoToAudio(Decoder: TFFmpegDecoder;
  SeekMaxMs: Integer; var PositionMs: Integer;
  out ErrorMessage: string): Boolean;
var
  AudioPositionMs: Integer;
begin
  ErrorMessage := '';
  Result := True;

  if PositionMs < 0 then
    Exit;

  if (FAudioPlayback = nil) or (FVideoView = nil) then
  begin
    ErrorMessage := 'Playback controller is not initialized.';
    Result := False;
    Exit;
  end;

  AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if (AudioPositionMs < 0) and FRateClockActive then
    AudioPositionMs := RateClockPositionMs(SeekMaxMs);
  if AudioPositionMs < 0 then
    Exit;

  if AudioPositionMs > SeekMaxMs then
    AudioPositionMs := SeekMaxMs;

  if not VideoMinerShouldSeekVideoToAudio(PositionMs, AudioPositionMs) then
    Exit;

  WriteVideoMinerD3DLog(Format(
    'sync_video_to_audio_skip_seek_during_playback video_ms=%d audio_ms=%d lag_ms=%d',
    [PositionMs, AudioPositionMs, AudioPositionMs - PositionMs]));
end;

procedure TVideoMinerPlaybackController.Tick(Decoder: TFFmpegDecoder;
  const VideoFile: string; EndAction: TVideoMinerEndAction; IsSeeking: Boolean;
  SeekMaxMs, LoopSegmentStartMs, LoopSegmentEndMs: Integer;
  var CurrentVideoPositionMs, SeekPositionMs, SeekGuardTargetMs,
  SeekGuardRemaining: Integer; var UpdatingSeek: Boolean;
  SetStatus: TVideoMinerPlaybackStatusProc;
  FinishPlaybackAtEnd: TVideoMinerPlaybackNotifyProc;
  SeekToMs: TVideoMinerPlaybackLoopSeekProc;
  UpdatePlaybackProgress: TVideoMinerPlaybackPositionProc;
  MaybeAutoCheckFrame: TVideoMinerPlaybackPositionProc);
var
  ErrorMessage: string;
  PositionMs: Integer;
  AudioPositionMs: Integer;
  LagMs: Integer;
  DropCount: Integer;
  DropWatch: TStopwatch;
  LoopTargetMs: Integer;
  TotalWatch: TStopwatch;
  StepWatch: TStopwatch;
  PumpMs: Double;
  DecodeMs: Double;
  SyncMs: Double;
  ConvertFrame: Boolean;
  DidSeekToAudio: Boolean;
  DebugLogEnabled: Boolean;
  DecodeResult: TVideoMinerPlaybackDecodeResult;
  GuardingSeek: Boolean;
  LaggingVideoResult: TVideoMinerLaggingVideoResult;
  SeekGuardResult: TVideoMinerSeekGuardResult;
  UseScratchFrame: Boolean;
  SlowLogEnabled: Boolean;
  RateLogEnabled: Boolean;
  RateElapsedMs: Int64;
  ShouldLogRateTick: Boolean;
  TotalMs: Double;
  NextSeekPositionMs: Integer;
  LoopFrameCacheShown: Boolean;
begin
  DebugLogEnabled := VideoMinerDebugLogEnabled;
  SlowLogEnabled := VideoMinerSlowLogEnabled;
  RateLogEnabled := VideoMinerRateLogEnabled;
  if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
    TotalWatch := TStopwatch.StartNew;
  PumpMs := 0;
  DecodeMs := 0;
  SyncMs := 0;

  if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
    StepWatch := TStopwatch.StartNew;
  if not PrepareTick(IsSeeking, (VideoFile <> '') and (Decoder <> nil),
    SeekMaxMs, AudioPositionMs, ErrorMessage) then
  begin
    if (ErrorMessage <> '') and Assigned(SetStatus) then
      SetStatus(ErrorMessage);
    Exit;
  end;
  if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
    PumpMs := StepWatch.Elapsed.TotalMilliseconds;

  if (AudioPositionMs >= 0) and (CurrentVideoPositionMs >= 0) and
     (CurrentVideoPositionMs > AudioPositionMs + VIDEO_AHEAD_SKIP_TOLERANCE_MS) then
  begin
    UpdatingSeek := True;
    try
      SeekPositionMs := SeekPositionForTick(CurrentVideoPositionMs,
        AudioPositionMs, SeekMaxMs);
    finally
      UpdatingSeek := False;
    end;
    if Assigned(UpdatePlaybackProgress) then
      UpdatePlaybackProgress(SeekPositionMs);
    if DebugLogEnabled then
      WriteVideoMinerDebugLog(Format(
        'playback_tick_wait_audio file="%s" audio_ms=%d video_ms=%d ahead_ms=%d pump_ms=%.3f timer_interval=%d',
        [ExtractFileName(VideoFile), AudioPositionMs, CurrentVideoPositionMs,
         CurrentVideoPositionMs - AudioPositionMs, PumpMs, FPlaybackTimer.Interval]));
    Exit;
  end;

  PositionMs := -1;
  DropCount := 0;
  DropWatch := TStopwatch.StartNew;
  DidSeekToAudio := False;
  repeat
    ConvertFrame := True;
    GuardingSeek := SeekGuardRemaining > 0;
    if GuardingSeek then
      ConvertFrame := False;

    if not GuardingSeek then
    begin
      LaggingVideoResult := HandleLaggingVideo(Decoder, SeekMaxMs,
        AudioPositionMs, DropWatch.ElapsedMilliseconds, DropCount,
        CurrentVideoPositionMs, PositionMs, ConvertFrame, ErrorMessage);
      case LaggingVideoResult of
        lvrSyncedToAudio:
          begin
            DidSeekToAudio := True;
            Break;
          end;
        lvrError:
          begin
            if Assigned(SetStatus) then
              SetStatus('Failed to sync video: ' + ErrorMessage);
            Exit;
          end;
      end;
    end;

    UseScratchFrame := ConvertFrame and (AudioPositionMs < 0);

    if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
      StepWatch := TStopwatch.StartNew;
    DecodeResult := DecodeNextFrame(Decoder, UseScratchFrame, ConvertFrame,
      PositionMs, ErrorMessage);
    if DecodeResult <> pdrFrame then
    begin
      if DecodeResult = pdrEndOfStream then
      begin
        if Assigned(FinishPlaybackAtEnd) then
          FinishPlaybackAtEnd;
      end
      else if Assigned(SetStatus) then
        SetStatus('Failed to decode next frame: ' + ErrorMessage);
      Exit;
    end;
    if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
      DecodeMs := DecodeMs + StepWatch.Elapsed.TotalMilliseconds;

    if UseScratchFrame and ShouldDropBackwardScratchFrame(VideoFile,
      DebugLogEnabled, CurrentVideoPositionMs, PositionMs) then
    begin
      ConvertFrame := False;
      Continue;
    end;

    SeekGuardResult := HandleSeekGuard(Decoder, VideoFile, DebugLogEnabled,
      SeekGuardTargetMs, SeekGuardRemaining, PositionMs, CurrentVideoPositionMs,
      ConvertFrame, ErrorMessage);
    case SeekGuardResult of
      sgrContinue:
        Continue;
      sgrSyncedToTarget:
        begin
          DidSeekToAudio := True;
          Break;
        end;
      sgrGuardError:
        begin
          if Assigned(SetStatus) then
            SetStatus('Failed to guard seek frame: ' + ErrorMessage);
          Exit;
        end;
      sgrPresentError:
        begin
          if Assigned(SetStatus) then
            SetStatus('Failed to present guarded frame: ' + ErrorMessage);
          Exit;
        end;
    end;

    if UseScratchFrame then
    begin
      if not PresentScratchFrame(ConvertFrame, ErrorMessage) then
      begin
        if Assigned(SetStatus) then
          SetStatus('Failed to present next frame: ' + ErrorMessage);
        Exit;
      end;
    end;

    if PositionMs >= 0 then
      CurrentVideoPositionMs := PositionMs;
  until ConvertFrame;

  if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
    StepWatch := TStopwatch.StartNew;
  if (not DidSeekToAudio) and
     (not SyncVideoToAudio(Decoder, SeekMaxMs, PositionMs, ErrorMessage)) then
  begin
    if Assigned(SetStatus) then
      SetStatus('Failed to sync video: ' + ErrorMessage);
    Exit;
  end;
  if PositionMs >= 0 then
    CurrentVideoPositionMs := PositionMs;
  if DebugLogEnabled or SlowLogEnabled or RateLogEnabled then
    SyncMs := StepWatch.Elapsed.TotalMilliseconds;

  if PositionMs >= 0 then
    NextSeekPositionMs := SeekPositionForTick(PositionMs, AudioPositionMs,
      SeekMaxMs)
  else
    NextSeekPositionMs := SeekPositionMs;

  if ShouldRestartLoop(EndAction, LoopSegmentStartMs, LoopSegmentEndMs,
    CurrentVideoPositionMs, NextSeekPositionMs, LoopTargetMs) then
  begin
    LoopFrameCacheShown := (FVideoView <> nil) and
      FVideoView.TryPresentLoopFrameCache(LoopTargetMs);
    WriteVideoMinerRateLog(Format(
      'loop_restart_summary file="%s" current_ms=%d position_ms=%d seek_candidate_ms=%d audio_ms=%d target_ms=%d segment_start_ms=%d segment_end_ms=%d cache_shown=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f',
      [ExtractFileName(VideoFile), CurrentVideoPositionMs, PositionMs,
       NextSeekPositionMs, AudioPositionMs, LoopTargetMs, LoopSegmentStartMs,
       LoopSegmentEndMs, BoolToStr(LoopFrameCacheShown, True), PumpMs,
       DecodeMs, SyncMs, TotalWatch.Elapsed.TotalMilliseconds]));
{$IFDEF DEBUG}
    WriteVideoMinerSlowLog(Format(
      'loop_restart_request file="%s" current_ms=%d position_ms=%d seek_candidate_ms=%d audio_ms=%d target_ms=%d segment_start_ms=%d segment_end_ms=%d cache_shown=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f',
      [ExtractFileName(VideoFile), CurrentVideoPositionMs, PositionMs,
       NextSeekPositionMs, AudioPositionMs, LoopTargetMs, LoopSegmentStartMs,
       LoopSegmentEndMs, BoolToStr(LoopFrameCacheShown, True), PumpMs, DecodeMs, SyncMs,
       TotalWatch.Elapsed.TotalMilliseconds]));
{$ENDIF}
    if Assigned(SeekToMs) then
    begin
      UpdatingSeek := True;
      try
        SeekPositionMs := LoopTargetMs;
        CurrentVideoPositionMs := LoopTargetMs;
      finally
        UpdatingSeek := False;
      end;
      if Assigned(UpdatePlaybackProgress) then
        UpdatePlaybackProgress(SeekPositionMs);
      SeekToMs(LoopTargetMs, LoopFrameCacheShown);
    end;
    Exit;
  end;

  if PositionMs >= 0 then
  begin
    UpdatingSeek := True;
    try
      SeekPositionMs := NextSeekPositionMs;
    finally
      UpdatingSeek := False;
    end;
  end;

  AudioPositionMs := PlaybackPositionMs;
  LagMs := PlaybackLagMs(AudioPositionMs, PositionMs);
  if Assigned(UpdatePlaybackProgress) then
    UpdatePlaybackProgress(SeekPositionMs);
  if Assigned(MaybeAutoCheckFrame) then
    MaybeAutoCheckFrame(CurrentVideoPositionMs);
  if DebugLogEnabled then
  begin
    if FPlaybackTimer <> nil then
      LogPlaybackTick(VideoFile, AudioPositionMs, PositionMs, LagMs, DropCount,
        DidSeekToAudio, PumpMs, DecodeMs, SyncMs,
        TotalWatch.Elapsed.TotalMilliseconds, FPlaybackTimer.Interval)
    else
      LogPlaybackTick(VideoFile, AudioPositionMs, PositionMs, LagMs, DropCount,
        DidSeekToAudio, PumpMs, DecodeMs, SyncMs,
        TotalWatch.Elapsed.TotalMilliseconds, 0);
  end;
  if RateLogEnabled and (not SameValue(FPlaybackRate, 1.0)) then
  begin
    RateElapsedMs := FRateTickLogClock.ElapsedMilliseconds;
    TotalMs := TotalWatch.Elapsed.TotalMilliseconds;
    ShouldLogRateTick := (FLastRateTickLogMs < 0) or
      (RateElapsedMs - FLastRateTickLogMs >= RATE_TICK_LOG_MS) or
      (Abs(LagMs) >= RATE_LAG_LOG_MS) or (DropCount > 0) or
      DidSeekToAudio or (PumpMs >= RATE_SLOW_LOG_MS) or
      (DecodeMs >= RATE_SLOW_LOG_MS) or (SyncMs >= RATE_SLOW_LOG_MS) or
      (TotalMs >= RATE_SLOW_LOG_MS);
    if ShouldLogRateTick then
    begin
      FLastRateTickLogMs := RateElapsedMs;
      if FPlaybackTimer <> nil then
        WriteVideoMinerRateLog(Format(
          'playback_tick_rate file="%s" rate=%.3f audio_ms=%d video_ms=%d seek_ms=%d lag_ms=%d drop_count=%d seek_to_audio=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f timer_interval=%d',
          [ExtractFileName(VideoFile), FPlaybackRate, AudioPositionMs,
           PositionMs, SeekPositionMs, LagMs, DropCount,
           BoolToStr(DidSeekToAudio, True), PumpMs, DecodeMs, SyncMs, TotalMs,
           FPlaybackTimer.Interval]))
      else
        WriteVideoMinerRateLog(Format(
          'playback_tick_rate file="%s" rate=%.3f audio_ms=%d video_ms=%d seek_ms=%d lag_ms=%d drop_count=%d seek_to_audio=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f timer_interval=%d',
          [ExtractFileName(VideoFile), FPlaybackRate, AudioPositionMs,
           PositionMs, SeekPositionMs, LagMs, DropCount,
           BoolToStr(DidSeekToAudio, True), PumpMs, DecodeMs, SyncMs, TotalMs,
           0]));
    end;
  end;
  if SlowLogEnabled then
  begin
    TotalMs := TotalWatch.Elapsed.TotalMilliseconds;
{$IFDEF DEBUG}
    if (TotalMs >= SLOW_TICK_LOG_MS) or (PumpMs >= SLOW_TICK_LOG_MS) or
       (DecodeMs >= SLOW_TICK_LOG_MS) or (SyncMs >= SLOW_TICK_LOG_MS) then
      WriteVideoMinerSlowLog(Format(
        'playback_tick_slow file="%s" audio_ms=%d video_ms=%d lag_ms=%d drop_count=%d seek_to_audio=%s pump_ms=%.3f decode_ms=%.3f sync_ms=%.3f total_ms=%.3f',
        [ExtractFileName(VideoFile), AudioPositionMs, PositionMs, LagMs,
         DropCount, BoolToStr(DidSeekToAudio, True), PumpMs, DecodeMs, SyncMs,
         TotalMs]));
{$ENDIF}
  end;
end;

procedure TVideoMinerPlaybackController.StopForSeek;
begin
  if FAudioPlayback <> nil then
    FAudioPlayback.SilenceOutput;
  SetPlaybackTimerEnabled(False);
  FRateClockActive := False;
  ClearRestart;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;
end;

procedure TVideoMinerPlaybackController.StopAtEnd;
begin
  SetPlaybackTimerEnabled(False);
  FRateClockActive := False;
  ClearRestart;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
end;

procedure TVideoMinerPlaybackController.StopPlayback;
begin
  SetPlaybackTimerEnabled(False);
  if FVideoView <> nil then
    FVideoView.PlaybackActive := False;
  FRateClockActive := False;
  ClearRestart;
  if FAudioPlayback <> nil then
    FAudioPlayback.StopOutput;
end;

end.
