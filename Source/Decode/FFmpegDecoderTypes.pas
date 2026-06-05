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
