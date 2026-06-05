unit VideoMinerMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, ActiveX, DropAgent, FFmpegDecoder,
  FFmpegDecoderTypes, VideoMinerAudioPlayback, VideoMinerMediaList,
  VideoMinerVideoView;

const
  WM_VM_OPEN_PENDING = WM_APP + 1;

type
  TVideoMinerMainForm = class(TForm)
    ButtonOpen: TButton; // 動画ファイルを開くボタン
    ButtonPlay: TButton; // 順方向デコード再生を開始するボタン
    ButtonStop: TButton; // 再生タイマーを停止するボタン
    ButtonPrevious: TButton;
    ButtonNext: TButton;
    ButtonSkipBackward: TButton;
    ButtonSkipForward: TButton;
    TrackBarVolume: TTrackBar;
    CheckBoxMute: TCheckBox;
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
    procedure ButtonPreviousClick(Sender: TObject);
    procedure ButtonNextClick(Sender: TObject);
    procedure ButtonSkipBackwardClick(Sender: TObject);
    procedure ButtonSkipForwardClick(Sender: TObject);
    // 再生中に次フレームを順方向デコードする
    procedure TimerPlaybackTimer(Sender: TObject);
    // シークバー操作に合わせて指定位置のフレームを表示する
    procedure TrackBarSeekChange(Sender: TObject);
    procedure TrackBarVolumeChange(Sender: TObject);
    procedure CheckBoxMuteClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FDecoder: TFFmpegDecoder; // 開いた動画を保持するFFmpegデコーダ
    FAudioPlayback: TVideoMinerAudioPlayback;
    FMediaList: TVideoMinerMediaList;
    FVideoView: TVideoMinerVideoView;
    FVideoFile: string; // 現在開いている動画ファイル名
    FVideoInfo: TVideoInfo; // 現在開いている動画の基本情報
    FUpdatingSeek: Boolean; // コードからのシークバー更新中かどうか
    FSeeking: Boolean;
    FSeekGuardTargetMs: Integer;
    FSeekGuardRemaining: Integer;
    FDropAgent: TDropAgent;
    FOleInitialized: Boolean;
    FPendingOpenFiles: TStringList;
    FProcessingOpenQueue: Boolean;
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    procedure UpdateNavigationButtons;
    procedure NavigateBy(Delta: Integer);
    procedure SeekToMs(PositionMs: Integer);
    procedure SeekByMs(DeltaMs: Integer);
    procedure SeekToFirstFrame;
    procedure SeekToLastFrame;
    procedure QueueOpenAndPlayFile(const FileName: string);
    procedure ProcessOpenQueue;
    procedure WMCopyData(var Message: TWMCopyData); message WM_COPYDATA;
    procedure WMOpenPending(var Message: TMessage); message WM_VM_OPEN_PENDING;
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

const
  COPYDATA_OPEN_FILE = $564D0001;

{$R *.dfm}

// フォーム生成時にデコーダを用意する
procedure TVideoMinerMainForm.FormCreate(Sender: TObject);
begin
  FOleInitialized := OleInitialize(nil) >= 0;
  FDecoder := TFFmpegDecoder.Create;
  FAudioPlayback := TVideoMinerAudioPlayback.Create;
  FMediaList := TVideoMinerMediaList.Create;
  FVideoView := TVideoMinerVideoView.Create(ImagePreview);
  FPendingOpenFiles := TStringList.Create;
  FAudioPlayback.VolumePercent := TrackBarVolume.Position;
  FAudioPlayback.Muted := CheckBoxMute.Checked;
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
  FAudioPlayback.Stop;
  FDropAgent.Free;
  FPendingOpenFiles.Free;
  FVideoView.Free;
  FMediaList.Free;
  FAudioPlayback.Free;
  FDecoder.Free;
  if FOleInitialized then
    OleUninitialize;
end;

// 指定ミリ秒位置のフレームを表示する
procedure TVideoMinerMainForm.ShowFrameAtMs(const PositionMs: Integer);
var
  ErrorMessage: string;
begin
  if (FVideoFile = '') or (FDecoder = nil) then
    Exit;

  if not FVideoView.ShowFrameAt(FDecoder, PositionMs, ErrorMessage) then
  begin
    LabelInfo.Caption := 'Failed to decode frame: ' + ErrorMessage;
    Exit;
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

  LabelInfo.Caption := Format('%s  /  %d of %d  /  %dx%d  /  %.3f sec  /  %.3f fps'#13#10'%s',
    [ExtractFileName(FVideoFile), FMediaList.CurrentIndex + 1, FMediaList.Count,
     FVideoInfo.Width, FVideoInfo.Height, FVideoInfo.DurationSec, FVideoInfo.Fps, AudioText]);
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
  FAudioPlayback.Stop;
  FSeeking := False;
  FSeekGuardRemaining := 0;
  FVideoView.Clear;

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
    FMediaList.Clear;
    Caption := 'VideoMiner';
    UpdateNavigationButtons;
    LabelInfo.Caption := 'Failed to open video: ' + ErrorMessage;
    Exit;
  end;

  FMediaList.BuildForFile(FileName);
  FVideoFile := FileName;
  Caption := Format('%s (%d/%d)', [ExtractFileName(FVideoFile),
    FMediaList.CurrentIndex + 1, FMediaList.Count]);

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

  UpdateNavigationButtons;
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

  if not FAudioPlayback.StartAt(FVideoFile, FVideoInfo, TrackBarSeek.Position,
    ErrorMessage) then
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
  FAudioPlayback.Stop;
  UpdateInfoLabel;
end;

// 再生中に次フレームを順方向デコードする
procedure TVideoMinerMainForm.TimerPlaybackTimer(Sender: TObject);
var
  ErrorMessage: string;
  PositionMs: Integer;
begin
  if FSeeking then
    Exit;

  if (FVideoFile = '') or (FDecoder = nil) then
  begin
    TimerPlayback.Enabled := False;
    Exit;
  end;

  if not FVideoView.ShowNextFrame(FDecoder, PositionMs, ErrorMessage) then
  begin
    TimerPlayback.Enabled := False;
    FAudioPlayback.Stop;
    if ErrorMessage <> 'End of stream.' then
      LabelInfo.Caption := 'Failed to decode next frame: ' + ErrorMessage;
    Exit;
  end;

  if (FSeekGuardRemaining > 0) and (PositionMs >= 0) then
  begin
    Dec(FSeekGuardRemaining);
    if Abs(PositionMs - FSeekGuardTargetMs) > 1500 then
    begin
      FSeeking := True;
      try
        FUpdatingSeek := True;
        try
          TrackBarSeek.Position := FSeekGuardTargetMs;
        finally
          FUpdatingSeek := False;
        end;
        ShowFrameAtMs(FSeekGuardTargetMs);
      finally
        FSeeking := False;
      end;
      Exit;
    end;
    FSeekGuardRemaining := 0;
  end;

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

  UpdateInfoLabel;
  if not FAudioPlayback.Pump(ErrorMessage) then
    LabelInfo.Caption := 'Failed to play audio: ' + ErrorMessage;
end;
// シークバー操作に合わせて指定位置のフレームを表示する
procedure TVideoMinerMainForm.TrackBarSeekChange(Sender: TObject);
begin
  if FUpdatingSeek then
    Exit;

  ShowFrameAtMs(TrackBarSeek.Position);
end;

procedure TVideoMinerMainForm.TrackBarVolumeChange(Sender: TObject);
begin
  FAudioPlayback.VolumePercent := TrackBarVolume.Position;
end;

procedure TVideoMinerMainForm.CheckBoxMuteClick(Sender: TObject);
begin
  FAudioPlayback.Muted := CheckBoxMute.Checked;
end;

procedure TVideoMinerMainForm.ButtonPreviousClick(Sender: TObject);
begin
  NavigateBy(-1);
end;

procedure TVideoMinerMainForm.ButtonNextClick(Sender: TObject);
begin
  NavigateBy(1);
end;


procedure TVideoMinerMainForm.UpdateNavigationButtons;
begin
  ButtonPrevious.Enabled := FMediaList.CanNavigate(-1);
  ButtonNext.Enabled := FMediaList.CanNavigate(1);
end;

procedure TVideoMinerMainForm.NavigateBy(Delta: Integer);
var
  FileName: string;
begin
  FileName := FMediaList.NavigateFile(Delta);
  if FileName = '' then
  begin
    UpdateNavigationButtons;
    Exit;
  end;

  LoadVideoFile(FileName, True);
end;

procedure TVideoMinerMainForm.SeekToMs(PositionMs: Integer);
var
  TargetMs: Integer;
  WasPlaying: Boolean;
begin
  if (FVideoFile = '') or (TrackBarSeek.Max <= 0) then
    Exit;

  WasPlaying := TimerPlayback.Enabled;
  TimerPlayback.Enabled := False;
  FAudioPlayback.Stop;

  TargetMs := PositionMs;
  if TargetMs < 0 then
    TargetMs := 0
  else if TargetMs > TrackBarSeek.Max then
    TargetMs := TrackBarSeek.Max;

  FSeeking := True;
  try
    FUpdatingSeek := True;
    try
      TrackBarSeek.Position := TargetMs;
    finally
      FUpdatingSeek := False;
    end;

    ShowFrameAtMs(TargetMs);
    FSeekGuardTargetMs := TargetMs;
    FSeekGuardRemaining := 3;
  finally
    FSeeking := False;
  end;

  if WasPlaying and (TargetMs < TrackBarSeek.Max) then
    ButtonPlayClick(Self);
end;

procedure TVideoMinerMainForm.SeekByMs(DeltaMs: Integer);
begin
  SeekToMs(TrackBarSeek.Position + DeltaMs);
end;

procedure TVideoMinerMainForm.SeekToFirstFrame;
begin
  SeekToMs(0);
end;

procedure TVideoMinerMainForm.SeekToLastFrame;
begin
  SeekToMs(TrackBarSeek.Max);
end;

procedure TVideoMinerMainForm.ButtonSkipBackwardClick(Sender: TObject);
begin
  SeekByMs(-10000);
end;

procedure TVideoMinerMainForm.ButtonSkipForwardClick(Sender: TObject);
begin
  SeekByMs(10000);
end;

procedure TVideoMinerMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift <> [] then
    Exit;

  case Key of
    VK_HOME:
      begin
        SeekToFirstFrame;
        Key := 0;
      end;
    VK_END:
      begin
        SeekToLastFrame;
        Key := 0;
      end;
  end;
end;

procedure TVideoMinerMainForm.QueueOpenAndPlayFile(const FileName: string);
begin
  if FileName = '' then
    Exit;

  FPendingOpenFiles.Add(FileName);
  PostMessage(Handle, WM_VM_OPEN_PENDING, 0, 0);
end;

procedure TVideoMinerMainForm.ProcessOpenQueue;
var
  FileName: string;
begin
  if FProcessingOpenQueue then
    Exit;

  FProcessingOpenQueue := True;
  try
    while FPendingOpenFiles.Count > 0 do
    begin
      FileName := FPendingOpenFiles[0];
      FPendingOpenFiles.Delete(0);
      OpenAndPlayFile(FileName);
    end;
  finally
    FProcessingOpenQueue := False;
  end;
end;

procedure TVideoMinerMainForm.WMOpenPending(var Message: TMessage);
begin
  ProcessOpenQueue;
  Message.Result := 1;
end;

procedure TVideoMinerMainForm.WMCopyData(var Message: TWMCopyData);
var
  FileName: string;
begin
  if (Message.CopyDataStruct <> nil) and
     (Message.CopyDataStruct.dwData = COPYDATA_OPEN_FILE) then
  begin
    if WindowState = wsMinimized then
      WindowState := wsNormal;
    Application.Restore;
    BringToFront;
    SetForegroundWindow(Handle);

    FileName := '';
    if (Message.CopyDataStruct.cbData > SizeOf(Char)) and
       (Message.CopyDataStruct.lpData <> nil) then
      FileName := PChar(Message.CopyDataStruct.lpData);

    if FileName <> '' then
      QueueOpenAndPlayFile(FileName);

    Message.Result := 1;
  end
  else
    inherited;
end;

end.
