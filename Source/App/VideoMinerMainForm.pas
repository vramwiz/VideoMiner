unit VideoMinerMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, ActiveX, DropAgent, FFmpegDecoder, FFmpegDecoderTypes;

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
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FDecoder: TFFmpegDecoder; // 開いた動画を保持するFFmpegデコーダ
    FVideoFile: string; // 現在開いている動画ファイル名
    FVideoInfo: TVideoInfo; // 現在開いている動画の基本情報
    FUpdatingSeek: Boolean; // コードからのシークバー更新中かどうか
    FSeeking: Boolean;
    FSeekGuardTargetMs: Integer;
    FSeekGuardRemaining: Integer;
    FDropAgent: TDropAgent;
    FOleInitialized: Boolean;
    FMediaFiles: TArray<string>;
    FCurrentIndex: Integer;
    FPendingOpenFiles: TStringList;
    FProcessingOpenQueue: Boolean;
    function LoadVideoFile(const FileName: string; AutoPlay: Boolean): Boolean;
    procedure DropFiles(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>);
    procedure BuildMediaListForFile(const FileName: string);
    function IsMediaFile(const FileName: string): Boolean;
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
  FPendingOpenFiles := TStringList.Create;
  FCurrentIndex := -1;
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
  FPendingOpenFiles.Free;
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

  LabelInfo.Caption := Format('%s  /  %d of %d  /  %dx%d  /  %.3f sec  /  %.3f fps'#13#10'%s',
    [ExtractFileName(FVideoFile), FCurrentIndex + 1, Length(FMediaFiles),
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
  FDecoder.StopAudioPlayback;
  FSeeking := False;
  FSeekGuardRemaining := 0;
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
    FCurrentIndex := -1;
    SetLength(FMediaFiles, 0);
    Caption := 'VideoMiner';
    UpdateNavigationButtons;
    LabelInfo.Caption := 'Failed to open video: ' + ErrorMessage;
    Exit;
  end;

  BuildMediaListForFile(FileName);
  FVideoFile := FileName;
  Caption := Format('%s (%d/%d)', [ExtractFileName(FVideoFile), FCurrentIndex + 1, Length(FMediaFiles)]);

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
  if FSeeking then
    Exit;

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

procedure TVideoMinerMainForm.ButtonPreviousClick(Sender: TObject);
begin
  NavigateBy(-1);
end;

procedure TVideoMinerMainForm.ButtonNextClick(Sender: TObject);
begin
  NavigateBy(1);
end;


function TVideoMinerMainForm.IsMediaFile(const FileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result :=
    (Ext = '.mp4') or (Ext = '.mov') or (Ext = '.mkv') or
    (Ext = '.avi') or (Ext = '.wmv') or (Ext = '.m4v') or
    (Ext = '.webm') or (Ext = '.mpg') or (Ext = '.mpeg') or
    (Ext = '.ts') or (Ext = '.m2ts');
end;

procedure TVideoMinerMainForm.BuildMediaListForFile(const FileName: string);
var
  Folder: string;
  SearchRec: TSearchRec;
  Files: TStringList;
  I: Integer;
  Candidate: string;
begin
  Folder := IncludeTrailingPathDelimiter(ExtractFilePath(FileName));
  Files := TStringList.Create;
  try
    Files.CaseSensitive := False;
    Files.Sorted := True;
    Files.Duplicates := dupIgnore;

    if FindFirst(Folder + '*.*', faAnyFile, SearchRec) = 0 then
    try
      repeat
        if (SearchRec.Attr and faDirectory) = 0 then
        begin
          Candidate := Folder + SearchRec.Name;
          if IsMediaFile(Candidate) then
            Files.Add(Candidate);
        end;
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;

    if Files.IndexOf(FileName) < 0 then
      Files.Add(FileName);

    SetLength(FMediaFiles, Files.Count);
    for I := 0 to Files.Count - 1 do
      FMediaFiles[I] := Files[I];

    FCurrentIndex := Files.IndexOf(FileName);
  finally
    Files.Free;
  end;
end;

procedure TVideoMinerMainForm.UpdateNavigationButtons;
begin
  ButtonPrevious.Enabled := (FCurrentIndex > 0) and (FCurrentIndex < Length(FMediaFiles));
  ButtonNext.Enabled := (FCurrentIndex >= 0) and (FCurrentIndex < Length(FMediaFiles) - 1);
end;

procedure TVideoMinerMainForm.NavigateBy(Delta: Integer);
var
  NewIndex: Integer;
begin
  if FCurrentIndex < 0 then
    Exit;

  NewIndex := FCurrentIndex + Delta;
  if (NewIndex < 0) or (NewIndex >= Length(FMediaFiles)) then
  begin
    UpdateNavigationButtons;
    Exit;
  end;

  LoadVideoFile(FMediaFiles[NewIndex], True);
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
  FDecoder.StopAudioPlayback;

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
