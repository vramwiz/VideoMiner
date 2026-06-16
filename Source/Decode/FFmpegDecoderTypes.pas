unit FFmpegDecoderTypes;

// FFmpeg デコーダ層で共有する基本型を定義する。
// UI や具体的な読み取り処理には依存させず、動画/音声情報と waveOut バッファの受け渡しに集中する。

interface

uses
  Winapi.MMSystem;

type
  PAudioWaveBuffer = ^TAudioWaveBuffer;
  TAudioWaveBuffer = record
    Header : TWaveHdr; // waveOut に渡すバッファヘッダ
    Data   : Pointer;  // PCM データを保持するメモリ
    Size   : Integer;  // Data のバイト数
  end;

  TAudioInfo = record
    Present          : Boolean; // 入力ファイルに音声ストリームがあるか
    StreamIndex      : Integer; // FFmpeg が選択した音声ストリーム番号
    SampleRate       : Integer; // 入力音声のサンプルレート Hz
    Channels         : Integer; // 入力音声のチャンネル数
    SampleFormat     : Integer; // FFmpeg の音声サンプル形式
    SampleFormatName : string;  // 調査表示用のサンプル形式名
    DurationSec      : Double;  // 音声ストリームの長さ 秒
    OpenError        : string;  // 音声デコーダ初期化時の失敗理由
  end;

  TVideoInfo = record
    Width       : Integer;    // 動画フレームの幅 px
    Height      : Integer;    // 動画フレームの高さ px
    DurationSec : Double;     // 動画全体の長さ 秒
    FpsText     : string;     // UI 表示用の FPS 文字列
    Fps         : Double;     // 再生制御に使う FPS 値
    Audio       : TAudioInfo; // 同じ入力ファイルから読んだ音声情報
  end;

implementation

end.
