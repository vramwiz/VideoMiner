unit VideoMinerPlaybackUiActions;

// 再生 UI の状態表示と軽い設定保存をまとめる。
// メインフォームはイベント入口と controller 接続に集中し、表示文字列や設定反映の細部はここへ寄せる。

interface

uses
  VideoMinerAudioPlayback, VideoMinerPlaybackController, VideoMinerSettings,
  VideoMinerVideoView;

type
  TVideoMinerPlaybackUiStatusProc = procedure(const Text: string) of object;

// 90% セーフエリア表示を切り替え、動画ビューと status 表示へ反映する
procedure ToggleVideoMinerSafeArea(var SafeAreaVisible: Boolean;
  VideoView: TVideoMinerVideoView; SetStatus: TVideoMinerPlaybackUiStatusProc);
// 終端動作表示を動画 overlay へ反映する
procedure UpdateVideoMinerEndActionText(VideoView: TVideoMinerVideoView;
  PlaybackController: TVideoMinerPlaybackController;
  EndAction: TVideoMinerEndAction);
// 再生速度表示を動画 overlay へ反映する
procedure UpdateVideoMinerPlaybackRateText(VideoView: TVideoMinerVideoView;
  PlaybackRate: Double);
// 現在倍率から次の再生速度を返す
function NextVideoMinerPlaybackRate(PlaybackRate: Double): Double;
// 音量とミュート状態を設定へ保存する
procedure SaveVideoMinerAudioPlaybackSettings(AudioPlayback: TVideoMinerAudioPlayback);

implementation

uses
  System.Math;

procedure ToggleVideoMinerSafeArea(var SafeAreaVisible: Boolean;
  VideoView: TVideoMinerVideoView; SetStatus: TVideoMinerPlaybackUiStatusProc);
begin
  SafeAreaVisible := not SafeAreaVisible;
  if VideoView <> nil then
    VideoView.SafeAreaVisible := SafeAreaVisible;
  if Assigned(SetStatus) then
  begin
    if SafeAreaVisible then
      SetStatus('90% safe area guide on.')
    else
      SetStatus('90% safe area guide off.');
  end;
end;

procedure UpdateVideoMinerEndActionText(VideoView: TVideoMinerVideoView;
  PlaybackController: TVideoMinerPlaybackController;
  EndAction: TVideoMinerEndAction);
begin
  if (VideoView = nil) or (PlaybackController = nil) then
    Exit;

  VideoView.EndActionText := PlaybackController.EndActionText(EndAction);
end;

procedure UpdateVideoMinerPlaybackRateText(VideoView: TVideoMinerVideoView;
  PlaybackRate: Double);
begin
  if VideoView = nil then
    Exit;

  if SameValue(PlaybackRate, 1.5) then
    VideoView.PlaybackRateText := '1.5x'
  else if SameValue(PlaybackRate, 2.0) then
    VideoView.PlaybackRateText := '2.0x'
  else
    VideoView.PlaybackRateText := '1.0x';
end;

function NextVideoMinerPlaybackRate(PlaybackRate: Double): Double;
begin
  if SameValue(PlaybackRate, 1.0) then
    Result := 1.5
  else if SameValue(PlaybackRate, 1.5) then
    Result := 2.0
  else
    Result := 1.0;
end;

procedure SaveVideoMinerAudioPlaybackSettings(AudioPlayback: TVideoMinerAudioPlayback);
var
  Settings: TVideoMinerAudioSettings;
begin
  if AudioPlayback = nil then
    Exit;

  Settings.Muted := AudioPlayback.Muted;
  Settings.VolumePercent := AudioPlayback.VolumePercent;
  SaveAudioSettings(Settings);
end;

end.
