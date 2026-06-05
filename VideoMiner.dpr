program VideoMiner;

uses
  Vcl.Forms,
  VideoMinerMainForm in 'Source\App\VideoMinerMainForm.pas' {VideoMinerForm},
  VideoMinerSettings in 'Source\App\VideoMinerSettings.pas',
  DropAgent in 'Source\Lib\DropAgent\DropAgent.pas',
  FFmpegApi in 'Source\FFmpeg\FFmpegApi.pas',  FFmpegFrameConvert in 'Source\FFmpeg\FFmpegFrameConvert.pas',
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

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TVideoMinerMainForm, VideoMinerForm);
  if ParamCount > 0 then
    VideoMinerForm.OpenAndPlayFile(ParamStr(1));
  Application.Run;
end.

