unit FFmpegStreamInfo;

// FFmpeg の入力コンテキストからストリーム情報を読み取る補助ユニット。
// デコーダ本体へ渡す TVideoInfo に、音声ストリームの基本情報を反映する。

interface

uses
  FFmpegApi, FFmpegDecoderTypes;

// 入力ファイル内の音声ストリーム情報を TVideoInfo へ読み込む。
procedure ReadAudioInfo(FormatContext: PAVFormatContext; var Info: TVideoInfo);
// 入力ファイル内の動画ストリームから表示回転角度を読み込む。
function ReadVideoRotationDegrees(Stream: PAVStream): Integer;

implementation

uses
  System.Math;

// 入力ファイル内の音声ストリーム情報を TVideoInfo へ読み込む。
procedure ReadAudioInfo(FormatContext: PAVFormatContext; var Info: TVideoInfo);
var
  StreamIndex : Integer;             // FFmpeg が選んだ最適な音声ストリーム番号
  Stream      : PAVStream;           // 対象の音声ストリーム
  CodecPar    : PAVCodecParameters;  // 音声ストリームのコーデック情報
begin
  StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0);
  if StreamIndex < 0 then
    Exit;

  Stream := StreamAt(FormatContext, StreamIndex);
  if not Assigned(Stream) or not Assigned(Stream.codecpar) then
    Exit;

  CodecPar := Stream.codecpar;
  Info.Audio.Present := True;
  Info.Audio.StreamIndex := StreamIndex;
  Info.Audio.SampleRate := CodecPar.sample_rate;
  Info.Audio.Channels := CodecPar.ch_layout.nb_channels;
  Info.Audio.SampleFormat := CodecPar.format;
  Info.Audio.SampleFormatName := SampleFormatName(CodecPar.format);

  if (Stream.duration > 0) and (Stream.time_base.num > 0) and (Stream.time_base.den > 0) then
    Info.Audio.DurationSec := Stream.duration * Stream.time_base.num / Stream.time_base.den
  else
    Info.Audio.DurationSec := Info.DurationSec;
end;

// 入力ファイル内の動画ストリームから表示回転角度を読み込む。
function ReadVideoRotationDegrees(Stream: PAVStream): Integer;
var
  Angle    : Integer;           // display matrix から得た回転角度
  CodecPar : PAVCodecParameters; // 対象ストリームの codec parameters
  Rotation : Double;            // FFmpeg が返す反時計回り回転角度
  SideData : PAVPacketSideData; // display matrix side data
begin
  Result := 0;
  if (Stream = nil) or (Stream.codecpar = nil) or
     (not Assigned(TFFmpegApi.av_packet_side_data_get)) or
     (not Assigned(TFFmpegApi.av_display_rotation_get)) then
    Exit;

  CodecPar := Stream.codecpar;
  SideData := TFFmpegApi.av_packet_side_data_get(
    PAVPacketSideData(CodecPar.coded_side_data), CodecPar.nb_coded_side_data,
    AV_PKT_DATA_DISPLAYMATRIX);
  if (SideData = nil) or (SideData.data = nil) or (SideData.size < 9 * SizeOf(Integer)) then
    Exit;

  Rotation := TFFmpegApi.av_display_rotation_get(PInteger(SideData.data));
  if IsNan(Rotation) then
    Exit;

  Angle := Round(Rotation) mod 360;
  if Angle < 0 then
    Inc(Angle, 360);

  if (Angle = 90) or (Angle = 180) or (Angle = 270) then
    Result := Angle;
end;

end.
