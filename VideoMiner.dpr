program VideoMiner;

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, Vcl.Forms,
  VideoMinerAudioPlayback in 'Source\App\VideoMinerAudioPlayback.pas',
  VideoMinerBossGesture in 'Source\App\VideoMinerBossGesture.pas',
  VideoMinerBossOverlay in 'Source\App\VideoMinerBossOverlay.pas',
  VideoMinerChapterManager in 'Source\App\VideoMinerChapterManager.pas',
  VideoMinerCommandController in 'Source\App\VideoMinerCommandController.pas',
  VideoMinerDebugLog in 'Source\App\VideoMinerDebugLog.pas',
  VideoMinerFrameCheck in 'Source\App\VideoMinerFrameCheck.pas',
  VideoMinerMediaOpen in 'Source\App\VideoMinerMediaOpen.pas',
  VideoMinerPlaybackController in 'Source\App\VideoMinerPlaybackController.pas',
  VideoMinerPlaybackTiming in 'Source\App\VideoMinerPlaybackTiming.pas',
  VideoMinerMediaList in 'Source\App\VideoMinerMediaList.pas',
  VideoMinerOverlay in 'Source\App\VideoMinerOverlay.pas',
  VideoMinerShortcutBindings in 'Source\App\VideoMinerShortcutBindings.pas',
  VideoMinerVideoSurface in 'Source\App\VideoMinerVideoSurface.pas',
  VideoMinerVideoView in 'Source\App\VideoMinerVideoView.pas',
  VideoMinerWindowChrome in 'Source\App\VideoMinerWindowChrome.pas',
  VideoMinerWindowModeController in 'Source\App\VideoMinerWindowModeController.pas',
  VideoMinerMainForm in 'Source\App\VideoMinerMainForm.pas' {VideoMinerForm},
  VideoMinerSettings in 'Source\App\VideoMinerSettings.pas',
  DropAgent in 'Source\Lib\DropAgent\DropAgent.pas',
  FolderWatch in 'Source\Lib\FolderWatch\FolderWatch.pas',
  ResizeEdges in 'Source\Lib\ResizeEdges\ResizeEdges.pas',
  ShortcutAction in 'Source\Lib\ShortcutAction\ShortcutAction.pas',
  FFmpegApi in 'Source\FFmpeg\FFmpegApi.pas',
  FFmpegAudioTempo in 'Source\FFmpeg\FFmpegAudioTempo.pas',
  FFmpegFrameConvert in 'Source\FFmpeg\FFmpegFrameConvert.pas',
  FFmpegQsvDecode in 'Source\FFmpeg\FFmpegQsvDecode.pas',
  FFmpegStreamInfo in 'Source\FFmpeg\FFmpegStreamInfo.pas',
  FFmpegAudioConvert in 'Source\Decode\FFmpegAudioConvert.pas',
  FFmpegAudioOpen in 'Source\Decode\FFmpegAudioOpen.pas',
  FFmpegDecoder in 'Source\Decode\FFmpegDecoder.pas',
  FFmpegDecoderAudioPlayback in 'Source\Decode\FFmpegDecoderAudioPlayback.pas',
  FFmpegDecoderAudioRead in 'Source\Decode\FFmpegDecoderAudioRead.pas',
  FFmpegDecoderContext in 'Source\Decode\FFmpegDecoderContext.pas',
  FFmpegDecoderNextBgr24 in 'Source\Decode\FFmpegDecoderNextBgr24.pas',
  FFmpegDecoderNextBgrx32 in 'Source\Decode\FFmpegDecoderNextBgrx32.pas',
  FFmpegDecoderNextI420 in 'Source\Decode\FFmpegDecoderNextI420.pas',
  FFmpegDecoderNextYc48 in 'Source\Decode\FFmpegDecoderNextYc48.pas',
  FFmpegDecoderNextYuy2 in 'Source\Decode\FFmpegDecoderNextYuy2.pas',
  FFmpegDecoderResources in 'Source\Decode\FFmpegDecoderResources.pas',
  FFmpegDecoderSeekBgr24 in 'Source\Decode\FFmpegDecoderSeekBgr24.pas',
  FFmpegDecoderSeekBgrx32 in 'Source\Decode\FFmpegDecoderSeekBgrx32.pas',
  FFmpegDecoderSeekI420 in 'Source\Decode\FFmpegDecoderSeekI420.pas',
  FFmpegDecoderSeekYc48 in 'Source\Decode\FFmpegDecoderSeekYc48.pas',
  FFmpegDecoderSeekYuy2 in 'Source\Decode\FFmpegDecoderSeekYuy2.pas',
  FFmpegDecoderTypes in 'Source\Decode\FFmpegDecoderTypes.pas';

{$R *.res}
{$R Version.res}

const
  SINGLE_INSTANCE_MUTEX = 'Local\VideoMiner.SingleInstance';
  COPYDATA_OPEN_FILE = $564D0001;

function SendCommandToExistingInstance: Boolean;
var
  TargetWindow: HWND;
  CopyData: TCopyDataStruct;
  FileName: string;
  I: Integer;
begin
  Result := False;
  for I := 0 to 49 do
  begin
    TargetWindow := FindWindow('TVideoMinerMainForm', nil);
    if TargetWindow <> 0 then
      Break;
    Sleep(100);
  end;

  if TargetWindow = 0 then
    Exit;

  if ParamCount > 0 then
    FileName := ParamStr(1)
  else
    FileName := '';

  FillChar(CopyData, SizeOf(CopyData), 0);
  CopyData.dwData := COPYDATA_OPEN_FILE;
  CopyData.cbData := (Length(FileName) + 1) * SizeOf(Char);
  CopyData.lpData := PChar(FileName);

  SendMessage(TargetWindow, WM_COPYDATA, 0, LPARAM(@CopyData));
  Result := True;
end;

var
  InstanceMutex: THandle;
  AlreadyRunning: Boolean;

begin
  InstanceMutex := CreateMutex(nil, True, PChar(SINGLE_INSTANCE_MUTEX));
  AlreadyRunning := (InstanceMutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS);

  if AlreadyRunning then
  begin
    SendCommandToExistingInstance;
    if InstanceMutex <> 0 then
      CloseHandle(InstanceMutex);
    Halt(0);
  end;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TVideoMinerMainForm, VideoMinerForm);
  if ParamCount > 0 then
    VideoMinerForm.OpenAndPlayFile(ParamStr(1))
  else
    VideoMinerForm.OpenRememberedFile;
  try
    Application.Run;
  finally
    if InstanceMutex <> 0 then
      CloseHandle(InstanceMutex);
  end;
end.
