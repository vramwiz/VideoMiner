unit VideoMinerMainForm;

interface

uses
  Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, FFmpegDecoder, FFmpegDecoderTypes,
  FFmpegOutputConfig, FFmpegOutputTest, FFmpegOutputSettingsDialog;

type
  TVideoMinerMainForm = class(TForm)
    ButtonOpen: TButton; // 動画ファイルを開くボタン
    ButtonPlay: TButton; // 順方向デコード再生を開始するボタン
    ButtonStop: TButton; // 再生タイマーを停止するボタン
    ImagePreview: TImage; // デコードしたフレームを表示する画像領域
    TrackBarSeek: TTrackBar; // 動画位置をミリ秒単位で扱うシークバー
    OpenDialogVideo: TOpenDialog; // 読み込む動画ファイルを選択するダイアログ
    LabelInfo: TLabel; // 読み込んだ動画情報やエラーを表示するラベル
    TimerPlayback: TTimer; // 再生中に次フレームを読むためのタイマー
    ButtonOutput: TButton; // 読み込み済み動画を出力するテストボタン
    // フォーム生成時にデコーダを用意する
    procedure FormCreate(Sender: TObject);
    // フォーム破棄時にデコーダを解放する
    procedure FormDestroy(Sender: TObject);
    // 動画ファイルを開いて先頭フレームを表示する
    procedure ButtonOpenClick(Sender: TObject);
    // 順方向デコード再生を開始する
    procedure ButtonPlayClick(Sender: TObject);
    // 再生を停止する
    procedure ButtonStopClick(Sender: TObject);
    // 再生中に次フレームを順方向デコードする
    procedure TimerPlaybackTimer(Sender: TObject);
    // シークバー操作に合わせて指定位置のフレームを表示する
    procedure TrackBarSeekChange(Sender: TObject);
    // 出力プラグイン相当のコールバック経由でMP4を書き出す
    procedure ButtonOutputClick(Sender: TObject);
  private
    FDecoder: TFFmpegDecoder; // 開いた動画を保持するFFmpegデコーダ
    FVideoFile: string; // 現在開いている動画ファイル名
    FVideoInfo: TVideoInfo; // 現在開いている動画の基本情報
    FUpdatingSeek: Boolean; // コードからのシークバー更新中かどうか
    FOutputActive: Boolean; // 出力処理中かどうか
    // 指定ミリ秒位置のフレームを表示する
    procedure ShowFrameAtMs(const PositionMs: Integer);
    // 動画情報ラベルを更新する
    procedure UpdateInfoLabel;
    // 出力中の進捗を表示する
    procedure OutputProgress(Current, Total: Integer; CurrentFps, AverageFps,
      MinFps, MaxFps: Double);
  public
    { Public declarations }
  end;

var
  VideoMinerForm: TVideoMinerMainForm;

implementation

{$R *.dfm}

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
begin
  FDecoder := TFFmpegDecoder.Create;
  LabelInfo.Caption := 'No video loaded';
end;

// フォーム破棄時にデコーダを解放する
procedure TVideoMinerMainForm.FormDestroy(Sender: TObject);
begin
  TimerPlayback.Enabled := False;
  FDecoder.Free;
end;

// 指定ミリ秒位置のフレームを表示する
procedure TVideoMinerMainForm.ShowFrameAtMs(const PositionMs: Integer);
var
  Bitmap: TBitmap;
  ErrorMessage: string;
begin
  if (FVideoFile = '') or (FDecoder = nil) then
    Exit;

  Bitmap := TBitmap.Create;
  try
    if not FDecoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage) then
    begin
      LabelInfo.Caption := 'Failed to decode frame: ' + ErrorMessage;
      Exit;
    end;

    ImagePreview.Picture.Bitmap.Assign(Bitmap);
  finally
    Bitmap.Free;
  end;

  UpdateInfoLabel;
end;

// 動画情報ラベルを更新する
procedure TVideoMinerMainForm.UpdateInfoLabel;
var
  AudioText: string;
  AudioStats: TAudioPlaybackStats;
  AudioStatsText: string;
  DecodeStats: TDecodeLoadStats;
  VideoLoadText: string;
  AudioLoadText: string;
  VideoLoadPercent: Double;
begin
  if FVideoFile = '' then
  begin
    LabelInfo.Caption := 'No video loaded';
    Exit;
  end;

  if FVideoInfo.Audio.Present then
  begin
    AudioText := Format('audio: %d Hz / %d ch / %s / %.3f sec',
      [FVideoInfo.Audio.SampleRate, FVideoInfo.Audio.Channels,
       FVideoInfo.Audio.SampleFormatName, FVideoInfo.Audio.DurationSec]);
    if FVideoInfo.Audio.OpenError <> '' then
      AudioText := AudioText + ' / open: ' + FVideoInfo.Audio.OpenError;
  end
  else
    AudioText := 'audio: none';

  if Assigned(FDecoder) and FVideoInfo.Audio.Present then
  begin
    AudioStats := FDecoder.AudioStats;
    AudioStatsText := Format('audio decode: packets %d / frames %d / samples %d / pts %d ms / peak %d / rms %.1f / non-zero %.1f%% / queued %d / send err %d / conv err %d',
      [AudioStats.AudioPackets, AudioStats.DecodedFrames, AudioStats.DecodedSamples,
       AudioStats.LastPtsMs, AudioStats.Peak, AudioStats.Rms, AudioStats.NonZeroPercent,
       AudioStats.QueuedBuffers, AudioStats.SendErrors, AudioStats.ConvertErrors]);
  end
  else
    AudioStatsText := 'audio decode: none';

  if Assigned(FDecoder) then
    DecodeStats := FDecoder.DecodeStats
  else
    FillChar(DecodeStats, SizeOf(DecodeStats), 0);

  if TimerPlayback.Interval > 0 then
    VideoLoadPercent := DecodeStats.VideoAverageMs * 100.0 / TimerPlayback.Interval
  else
    VideoLoadPercent := 0;
  VideoLoadText := Format('video load: last %.2f ms / avg %.2f ms / max %.2f ms / %.1f%% of %d ms / frames %d',
    [DecodeStats.VideoLastMs, DecodeStats.VideoAverageMs, DecodeStats.VideoMaxMs,
     VideoLoadPercent, TimerPlayback.Interval, DecodeStats.VideoFrames]);
  VideoLoadText := VideoLoadText + Format(#13#10'video split: decode %.2f / %.2f / %.2f ms, transfer %.2f / %.2f / %.2f ms, convert %.2f / %.2f / %.2f ms',
    [DecodeStats.VideoDecodeLastMs, DecodeStats.VideoDecodeAverageMs, DecodeStats.VideoDecodeMaxMs,
     DecodeStats.VideoTransferLastMs, DecodeStats.VideoTransferAverageMs, DecodeStats.VideoTransferMaxMs,
     DecodeStats.VideoConvertLastMs, DecodeStats.VideoConvertAverageMs, DecodeStats.VideoConvertMaxMs]);
  AudioLoadText := Format('audio packet load: last %.2f ms / avg %.2f ms / max %.2f ms / packets %d',
    [DecodeStats.AudioLastMs, DecodeStats.AudioAverageMs, DecodeStats.AudioMaxMs,
     DecodeStats.AudioPackets]);

  LabelInfo.Caption := Format('%s  /  %dx%d  /  %.3f sec  /  %.3f fps'#13#10'%s'#13#10'%s'#13#10'%s'#13#10'%s',
    [ExtractFileName(FVideoFile), FVideoInfo.Width, FVideoInfo.Height,
     FVideoInfo.DurationSec, FVideoInfo.Fps, AudioText, AudioStatsText, VideoLoadText, AudioLoadText]);
end;

// 動画ファイルを開いて先頭フレームを表示する
procedure TVideoMinerMainForm.ButtonOpenClick(Sender: TObject);
var
  ErrorMessage: string;
  NewFileName: string;
begin
  if not OpenDialogVideo.Execute then
    Exit;

  TimerPlayback.Enabled := False;
  FDecoder.StopAudioPlayback;
  NewFileName := OpenDialogVideo.FileName;
  ImagePreview.Picture.Assign(nil);

  FUpdatingSeek := True;
  try
    TrackBarSeek.Position := 0;
    TrackBarSeek.Max := 0;
  finally
    FUpdatingSeek := False;
  end;

  if not FDecoder.Open(NewFileName, FVideoInfo, ErrorMessage) then
  begin
    FVideoFile := '';
    Caption := 'FFmpeg Decode Test';
    LabelInfo.Caption := 'Failed to open video: ' + ErrorMessage;
    Exit;
  end;

  FVideoFile := NewFileName;
  Caption := ExtractFileName(FVideoFile);

  FUpdatingSeek := True;
  try
    TrackBarSeek.Max := Round(FVideoInfo.DurationSec * 1000);
    TrackBarSeek.Position := 0;
  finally
    FUpdatingSeek := False;
  end;
  if FVideoInfo.Fps > 0 then
    TimerPlayback.Interval := Round(1000 / FVideoInfo.Fps)
  else
    TimerPlayback.Interval := 33;
  if TimerPlayback.Interval < 1 then
    TimerPlayback.Interval := 1;

  UpdateInfoLabel;
  ShowFrameAtMs(0);
end;

// 順方向デコード再生を開始する
procedure TVideoMinerMainForm.ButtonPlayClick(Sender: TObject);
var
  ErrorMessage: string;
begin
  if FVideoFile = '' then
    Exit;

  if TrackBarSeek.Position >= TrackBarSeek.Max then
  begin
    FUpdatingSeek := True;
    try
      TrackBarSeek.Position := 0;
    finally
      FUpdatingSeek := False;
    end;
    ShowFrameAtMs(0);
  end;

  if FVideoInfo.Audio.Present and not FDecoder.StartAudioPlayback(ErrorMessage) then
  begin
    LabelInfo.Caption := 'Failed to start audio playback: ' + ErrorMessage;
    Exit;
  end;

  TimerPlayback.Enabled := True;
end;
// 再生を停止する
procedure TVideoMinerMainForm.ButtonStopClick(Sender: TObject);
begin
  TimerPlayback.Enabled := False;
  FDecoder.StopAudioPlayback;
  UpdateInfoLabel;
end;

// 再生中に次フレームを順方向デコードする
procedure TVideoMinerMainForm.TimerPlaybackTimer(Sender: TObject);
var
  Bitmap: TBitmap;
  ErrorMessage: string;
  PositionMs: Integer;
begin
  if (FVideoFile = '') or (FDecoder = nil) then
  begin
    TimerPlayback.Enabled := False;
    Exit;
  end;

  Bitmap := TBitmap.Create;
  try
    if not FDecoder.DecodeNextFrameToBitmap(Bitmap, PositionMs, ErrorMessage) then
    begin
      TimerPlayback.Enabled := False;
      FDecoder.StopAudioPlayback;
      if ErrorMessage <> 'End of stream.' then
        LabelInfo.Caption := 'Failed to decode next frame: ' + ErrorMessage;
      Exit;
    end;

    ImagePreview.Picture.Bitmap.Assign(Bitmap);
    if PositionMs >= 0 then
    begin
      FUpdatingSeek := True;
      try
        if PositionMs > TrackBarSeek.Max then
          TrackBarSeek.Position := TrackBarSeek.Max
        else
          TrackBarSeek.Position := PositionMs;
      finally
        FUpdatingSeek := False;
      end;
    end;
  finally
    Bitmap.Free;
  end;

  UpdateInfoLabel;
end;
// シークバー操作に合わせて指定位置のフレームを表示する
procedure TVideoMinerMainForm.TrackBarSeekChange(Sender: TObject);
begin
  if FUpdatingSeek then
    Exit;

  ShowFrameAtMs(TrackBarSeek.Position);
end;

// 出力中の進捗を表示する
procedure TVideoMinerMainForm.OutputProgress(Current, Total: Integer; CurrentFps, AverageFps,
  MinFps, MaxFps: Double);
begin
  LabelInfo.Caption := Format(
    'Output MP4: %d / %d frames'#13#10'fps current %.2f / avg %.2f / min %.2f / max %.2f',
    [Current, Total, CurrentFps, AverageFps, MinFps, MaxFps]);
  Application.ProcessMessages;
end;

// 出力プラグイン相当のコールバック経由でMP4を書き出す
procedure TVideoMinerMainForm.ButtonOutputClick(Sender: TObject);
var
  ErrorMessage: string;
  Settings: TOutputTestSettings;
begin
  if FOutputActive then
  begin
    RequestOutputAbort;
    ButtonOutput.Caption := 'Stopping...';
    ButtonOutput.Enabled := False;
    Exit;
  end;

  if FVideoFile = '' then
  begin
    LabelInfo.Caption := 'Open a video before output.';
    Exit;
  end;

  TimerPlayback.Enabled := False;
  FDecoder.StopAudioPlayback;
  InitDefaultOutputSettings(Settings);
  Settings.SaveFileName := ChangeFileExt(FVideoFile, '_output.mp4');
  if not ExecuteOutputSettingsDialog(Handle, Settings) then
    Exit;

  FOutputActive := True;
  ButtonOutput.Caption := 'Stop Output';
  try
    if ExportVideoWithOutputCallbacks(FVideoFile, Settings, FVideoInfo,
      OutputProgress, ErrorMessage) then
      LabelInfo.Caption := 'Output complete: ' + Settings.SaveFileName
    else if Pos('Output was stopped.', ErrorMessage) = 1 then
      LabelInfo.Caption := ErrorMessage + ' ' + Settings.SaveFileName
    else
      LabelInfo.Caption := 'Output failed: ' + ErrorMessage;
  finally
    FOutputActive := False;
    ButtonOutput.Caption := 'Output MP4';
    ButtonOutput.Enabled := True;
  end;
end;

end.





