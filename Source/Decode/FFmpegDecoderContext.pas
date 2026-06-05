unit FFmpegDecoderContext;

interface

uses
  FFmpegDecoderTypes;

type
  TFFmpegDecoderContext = class
  public
    FileName            : string;
    FormatContext       : Pointer;
    CodecContext        : Pointer;
    Stream              : Pointer;
    StreamIndex         : Integer;
    AudioCodecContext   : Pointer;
    AudioStream         : Pointer;
    AudioStreamIndex    : Integer;
    AudioFrame          : Pointer;
    SwrContext          : Pointer;
    Packet              : Pointer;
    Frame               : Pointer;
    TransferFrame       : Pointer;
    QsvDeviceContext    : Pointer;
    DirectSwsContext    : Pointer;
    DirectSwsSrcWidth   : Integer;
    DirectSwsSrcHeight  : Integer;
    DirectSwsSrcFormat  : Integer;
    DirectSwsDstFormat  : Integer;
    VideoDecoderName    : string;
    VideoUsesQsv        : Boolean;
    Info                : TVideoInfo;
    DecodeStats         : TDecodeLoadStats;
  end;

implementation

end.
