unit FFmpegDecoderTypes;

interface

uses
  Winapi.MMSystem;

type
  PAudioWaveBuffer = ^TAudioWaveBuffer;
  TAudioWaveBuffer = record
    Header: TWaveHdr;
    Data: Pointer;
    Size: Integer;
  end;

  TAudioPlaybackStats = record
    AudioPackets: Int64;
    DecodedFrames: Int64;
    DecodedSamples: Int64;
    LastPtsMs: Integer;
    Peak: Integer;
    Rms: Double;
    NonZeroPercent: Double;
    QueuedBuffers: Integer;
    SendErrors: Int64;
    ConvertErrors: Int64;
  end;

  TDecodeLoadStats = record
    VideoLastMs: Double; // 直近の映像処理合計時間
    VideoAverageMs: Double; // 映像処理合計時間の移動平均
    VideoMaxMs: Double; // 映像処理合計時間の最大値
    VideoFrames: Int64; // 映像統計を更新したフレーム数
    VideoDecodeLastMs: Double; // 直近の映像decode時間
    VideoDecodeAverageMs: Double; // 映像decode時間の移動平均
    VideoDecodeMaxMs: Double; // 映像decode時間の最大値
    VideoConvertLastMs: Double; // 直近の映像変換時間
    VideoConvertAverageMs: Double; // 映像変換時間の移動平均
    VideoConvertMaxMs: Double; // 映像変換時間の最大値
    VideoTransferLastMs: Double; // 直近のHW frame転送時間
    VideoTransferAverageMs: Double; // HW frame転送時間の移動平均
    VideoTransferMaxMs: Double; // HW frame転送時間の最大値
    AudioLastMs: Double; // 直近の音声処理時間
    AudioAverageMs: Double; // 音声処理時間の移動平均
    AudioMaxMs: Double; // 音声処理時間の最大値
    AudioPackets: Int64; // 音声統計を更新したパケット数
  end;

  TAudioInfo = record
    Present: Boolean;
    StreamIndex: Integer;
    SampleRate: Integer;
    Channels: Integer;
    SampleFormat: Integer;
    SampleFormatName: string;
    DurationSec: Double;
    OpenError: string;
  end;

  TVideoInfo = record
    Width: Integer;
    Height: Integer;
    DurationSec: Double;
    FpsText: string;
    Fps: Double;
    Audio: TAudioInfo;
  end;

implementation

end.
