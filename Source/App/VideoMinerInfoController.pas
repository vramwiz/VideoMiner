unit VideoMinerInfoController;

// フォーム caption、独自タイトルバー、シーク進捗、動画情報表示をまとめる。

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms, Vcl.StdCtrls,
  VideoMinerAudioPlayback, VideoMinerMediaList, VideoMinerMediaSession,
  VideoMinerVideoView;

type
  TVideoMinerInfoPositionFunc = function: Integer of object;

  TVideoMinerInfoController = class
  private
    FAudioPlayback: TVideoMinerAudioPlayback;
    FHostForm: TCustomForm;
    FLastInfoUpdateTick: UInt64;
    FMediaList: TVideoMinerMediaList;
    FMediaSession: TVideoMinerMediaSession;
    FOnCurrentPosition: TVideoMinerInfoPositionFunc;
    FTitleLabel: TLabel;
    FVideoView: TVideoMinerVideoView;
  public
    constructor Create(AHostForm: TCustomForm; ATitleLabel: TLabel;
      AMediaSession: TVideoMinerMediaSession; AMediaList: TVideoMinerMediaList;
      AAudioPlayback: TVideoMinerAudioPlayback; AVideoView: TVideoMinerVideoView);
    procedure SetStatusCaption(const Text: string);
    procedure SetTitleBarText(const Text: string);
    procedure UpdateInfo;
    procedure UpdatePlaybackProgress(PositionMs: Integer);
    property OnCurrentPosition: TVideoMinerInfoPositionFunc read FOnCurrentPosition
      write FOnCurrentPosition;
  end;

implementation

const
  UI_INFO_UPDATE_INTERVAL_MS = 250; // 再生中の情報表示を更新する最短間隔 ms

constructor TVideoMinerInfoController.Create(AHostForm: TCustomForm;
  ATitleLabel: TLabel; AMediaSession: TVideoMinerMediaSession;
  AMediaList: TVideoMinerMediaList; AAudioPlayback: TVideoMinerAudioPlayback;
  AVideoView: TVideoMinerVideoView);
begin
  inherited Create;
  FHostForm := AHostForm;
  FTitleLabel := ATitleLabel;
  FMediaSession := AMediaSession;
  FMediaList := AMediaList;
  FAudioPlayback := AAudioPlayback;
  FVideoView := AVideoView;
end;

procedure TVideoMinerInfoController.SetStatusCaption(const Text: string);
begin
  if FHostForm <> nil then
  begin
    if Text = '' then
      FHostForm.Caption := 'VideoMiner'
    else
      FHostForm.Caption := 'VideoMiner - ' + Text;
    SetTitleBarText(FHostForm.Caption);
  end
  else
    SetTitleBarText(Text);
end;

procedure TVideoMinerInfoController.SetTitleBarText(const Text: string);
begin
  if FTitleLabel <> nil then
    FTitleLabel.Caption := Text;
end;

procedure TVideoMinerInfoController.UpdateInfo;
var
  AudioPositionMs: Integer;
  AlphaText: string;
  AudioText: string;
  CurrentPositionMs: Integer;
  VideoPositionMs: Integer;
begin
  if (FMediaSession = nil) or (FMediaSession.VideoFile = '') then
  begin
    SetStatusCaption('No video loaded');
    if FVideoView <> nil then
      FVideoView.SetSeekProgress(0, 0);
    Exit;
  end;

  if FMediaSession.VideoInfo.Audio.Present then
  begin
    AudioText := Format('audio: %d Hz / %d ch / %s',
      [FMediaSession.VideoInfo.Audio.SampleRate,
       FMediaSession.VideoInfo.Audio.Channels,
       FMediaSession.VideoInfo.Audio.SampleFormatName]);
    if FMediaSession.VideoInfo.Audio.OpenError <> '' then
      AudioText := AudioText + ' / open: ' +
        FMediaSession.VideoInfo.Audio.OpenError;
  end
  else
    AudioText := 'audio: none';

  if FMediaSession.VideoInfo.HasAlpha then
    AlphaText := Format(' / pix_fmt: %s / alpha',
      [FMediaSession.VideoInfo.PixelFormatName])
  else if FMediaSession.VideoInfo.PixelFormatName <> '' then
    AlphaText := Format(' / pix_fmt: %s',
      [FMediaSession.VideoInfo.PixelFormatName])
  else
    AlphaText := '';

  if Assigned(FOnCurrentPosition) then
    CurrentPositionMs := FOnCurrentPosition()
  else
    CurrentPositionMs := FMediaSession.SeekPositionMs;

  VideoPositionMs := FMediaSession.CurrentVideoPositionMs;
  if VideoPositionMs < 0 then
    VideoPositionMs := 0;

  AudioPositionMs := 0;
  if FAudioPlayback <> nil then
    AudioPositionMs := FAudioPlayback.PlaybackPositionMs;
  if AudioPositionMs < 0 then
    AudioPositionMs := 0
  else if AudioPositionMs > FMediaSession.SeekMaxMs then
    AudioPositionMs := FMediaSession.SeekMaxMs;

  if FHostForm <> nil then
    FHostForm.Caption := Format('%s (%d/%d) - %.3f/%.3f sec  video %.3f  audio %.3f - %dx%d / %.3f fps / %s',
      [ExtractFileName(FMediaSession.VideoFile), FMediaList.CurrentIndex + 1,
       FMediaList.Count, CurrentPositionMs / 1000,
       FMediaSession.SeekMaxMs / 1000, VideoPositionMs / 1000,
       AudioPositionMs / 1000, FMediaSession.VideoInfo.Width,
       FMediaSession.VideoInfo.Height, FMediaSession.VideoInfo.Fps,
       AudioText + AlphaText]);

  SetTitleBarText(Format('%s (%d/%d)',
    [ExtractFileName(FMediaSession.VideoFile), FMediaList.CurrentIndex + 1,
     FMediaList.Count]));
  if FVideoView <> nil then
    FVideoView.SetSeekProgress(CurrentPositionMs, FMediaSession.SeekMaxMs);
  FLastInfoUpdateTick := GetTickCount64;
end;

procedure TVideoMinerInfoController.UpdatePlaybackProgress(PositionMs: Integer);
var
  CurrentTick: UInt64;
begin
  if (FVideoView <> nil) and (FMediaSession <> nil) then
    FVideoView.SetSeekProgress(PositionMs, FMediaSession.SeekMaxMs);

  CurrentTick := GetTickCount64;
  if (FLastInfoUpdateTick = 0) or
     (CurrentTick - FLastInfoUpdateTick >= UI_INFO_UPDATE_INTERVAL_MS) then
    UpdateInfo;
end;

end.
