unit VideoMinerMainForm;

interface

uses
  Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, ActiveX, DropAgent, FFmpegDecoder, FFmpegDecoderTypes;

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
  private
    FDecoder: TFFmpegDecoder; // 開いた動画を保持するFFmpegデコーダ
    FVideoFile: string; // 現在開いている動画ファイル名
    FVideoInfo: TVideoInfo; // 現在開いている動画の基本情報
    FUpdatingSeek: Boolean; // コードからのシークバー更新中かどうか
    FDropAgent: TDropAgent;
    FOleInitialized: Boolean;
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    // 指定ミリ秒位置のフレームを表示する
    procedure ShowFrameAtMs(const PositionMs: Integer);
    // 動画情報ラベルを更新する
    procedure UpdateInfoLabel;
  public
    function OpenAndPlayFile(const FileName: string): Boolean;
  end;

var
  VideoMinerForm: TVideoMinerMainForm;

implementation

{$R *.dfm}

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
begin
  FOleInitialized := OleInitialize(nil) >= 0;
  FDecoder := TFFmpegDecoder.Create;
  FDropAgent := TDropAgent.Create;
  if FOleInitialized then
  begin
    FDropAgent.AcceptKinds := [dakFiles];
    FDropAgent.OnDropFiles := DropFiles;
    FDropAgent.Attach(Self);
  end;
  LabelInfo.Caption := 'No video loaded';
end;

// フォーム破棄時にデコーダを解放する
procedure TVideoMinerMainForm.FormDestroy(Sender: TObject);
begin
  TimerPlayback.Enabled := False;
  FDropAgent.Free;
  FDecoder.Free;
  if FOleInitialized then
    OleUninitialize;
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
begin
  if FVideoFile = '' then
  begin
    LabelInfo.Caption := 'No video loaded';
    Exit;
  end;

  if FVideoInfo.Audio.Present then
  begin
    AudioText := Format('audio: %d Hz / %d ch / %s',
      [FVideoInfo.Audio.SampleRate, FVideoInfo.Audio.Channels,
       FVideoInfo.Audio.SampleFormatName]);
    if FVideoInfo.Audio.OpenError <> '' then
      AudioText := AudioText + ' / open: ' + FVideoInfo.Audio.OpenError;
  end
  else
    AudioText := 'audio: none';

  LabelInfo.Caption := Format('%s  /  %dx%d  /  %.3f sec  /  %.3f fps'#13#10'%s',
    [ExtractFileName(FVideoFile), FVideoInfo.Width, FVideoInfo.Height,
     FVideoInfo.DurationSec, FVideoInfo.Fps, AudioText]);
end;

// 動画ファイルを開いて先頭フレームを表示する
procedure TVideoMinerMainForm.ButtonOpenClick(Sender: TObject);
begin
  if OpenDialogVideo.Execute then
    LoadVideoFile(OpenDialogVideo.FileName, False);
end;

function TVideoMinerMainForm.LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
var
  ErrorMessage: string;
begin
  Result := False;

  if (FileName = '') or (not FileExists(FileName)) then
  begin
    LabelInfo.Caption := 'File not found: ' + FileName;
    Exit;
  end;

  TimerPlayback.Enabled := False;
  FDecoder.StopAudioPlayback;
  ImagePreview.Picture.Assign(nil);

  FUpdatingSeek := True;
  try
    TrackBarSeek.Position := 0;
    TrackBarSeek.Max := 0;
  finally
    FUpdatingSeek := False;
  end;

  if not FDecoder.Open(FileName, FVideoInfo, ErrorMessage) then
  begin
    FVideoFile := '';
    Caption := 'VideoMiner';
    LabelInfo.Caption := 'Failed to open video: ' + ErrorMessage;
    Exit;
  end;

  FVideoFile := FileName;
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

  if AutoPlay then
    ButtonPlayClick(Self);

  Result := True;
end;

function TVideoMinerMainForm.OpenAndPlayFile(const FileName: string): Boolean;
begin
  Result := LoadVideoFile(FileName, True);
end;

procedure TVideoMinerMainForm.DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
begin
  if Length(FileNames) > 0 then
    OpenAndPlayFile(FileNames[0]);
end;

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

end.





