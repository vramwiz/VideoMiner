unit FFmpegDecoderContext;

// FFmpeg デコーダ処理で共有する実行時状態を保持する。
// 型付き FFmpeg ポインタは各処理ユニット側で必要な型へ戻して使う。

interface

uses
  System.SysUtils,
  FFmpegDecoderTypes;

type
  TFFmpegDecoderContext = class
  public
    FileName                : string;     // 現在開いている入力ファイル
    InputBuffer             : TObject;    // custom AVIO 用の一時前方読み込みバッファ
    FormatContext           : Pointer;    // 入力コンテナを読む AVFormatContext
    CodecContext            : Pointer;    // 動画ストリーム用の AVCodecContext
    Stream                  : Pointer;    // 選択された動画 AVStream
    StreamIndex             : Integer;    // 選択された動画ストリーム番号
    AudioCodecContext       : Pointer;    // 音声ストリーム用の AVCodecContext
    AudioStream             : Pointer;    // 選択された音声 AVStream
    AudioStreamIndex        : Integer;    // 選択された音声ストリーム番号
    AudioFrame              : Pointer;    // 音声デコード結果を受け取る AVFrame
    AudioDiscardUntilSample : Integer;    // シーク直後に破棄する音声サンプル位置
    SwrContext              : Pointer;    // 音声を PCM16 stereo 48kHz へ変換する SwrContext
    Packet                  : Pointer;    // 読み取った AVPacket を使い回す領域
    Frame                   : Pointer;    // 動画デコード結果を受け取る AVFrame
    TransferFrame           : Pointer;    // QSV などから CPU 側へ転送した AVFrame
    QsvDeviceContext        : Pointer;    // QSV デコードで使うハードウェア device context
    DirectSwsContext        : Pointer;    // 表示用バッファへ直接変換する SwsContext
    DirectSwsSrcWidth       : Integer;    // DirectSwsContext を作った元フレーム幅
    DirectSwsSrcHeight      : Integer;    // DirectSwsContext を作った元フレーム高さ
    DirectSwsSrcFormat      : Integer;    // DirectSwsContext を作った元ピクセル形式
    DirectSwsDstFormat      : Integer;    // DirectSwsContext を作った出力ピクセル形式
    Bgrx32TempBuffer        : TBytes;     // 負 stride 回避で再利用する BGRX32 一時バッファ
    Bgrx32TempStride        : Integer;    // BGRX32 一時バッファの stride
    Bgrx32TempHeight        : Integer;    // BGRX32 一時バッファの高さ
    VideoDecoderName        : string;     // 実際に開いた動画デコーダ名
    VideoUsesQsv            : Boolean;    // 動画デコードに QSV を使っているか
    Info                    : TVideoInfo; // UI 層へ返す動画/音声情報
  end;

implementation

end.
