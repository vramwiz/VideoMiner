unit VideoMinerMediaSession;

// 現在開いている動画と再生位置の状態を保持する。
// MainForm から「状態置き場」を分離し、controller へ渡す値を 1 か所にまとめる。

interface

uses
  FFmpegDecoderTypes, VideoMinerSettings;

type
  TVideoMinerMediaSession = class
  public
    CurrentVideoPositionMs : Integer;               // 最後に表示できたフレーム位置 ms
    EndAction              : TVideoMinerEndAction;  // 動画終端到達時の動作
    LoopSegmentEndMs       : Integer;               // ループ再生区間の終端 ms
    LoopSegmentStartMs     : Integer;               // ループ再生区間の開始 ms
    SeekMaxMs              : Integer;               // シーク可能な最大位置 ms
    SeekPositionMs         : Integer;               // UI と再生制御で共有する現在位置 ms
    VideoFile              : string;                // 現在開いている動画ファイル名
    VideoInfo              : TVideoInfo;            // 現在開いている動画の基本情報
    // 既定の空状態を設定する
    constructor Create;
    // 現在ファイルと再生位置を空に戻す。終端動作設定は保持する
    procedure ClearMedia;
    // 動画読み込み開始時の状態へ戻す
    procedure BeginLoad;
    // 読み込みに成功した現在ファイル情報を反映する
    procedure ConfigureMedia(const FileName: string; const Info: TVideoInfo);
  end;

implementation

constructor TVideoMinerMediaSession.Create;
begin
  inherited Create;
  ClearMedia;
end;

procedure TVideoMinerMediaSession.ClearMedia;
begin
  VideoFile := '';
  VideoInfo := Default(TVideoInfo);
  BeginLoad;
end;

procedure TVideoMinerMediaSession.BeginLoad;
begin
  CurrentVideoPositionMs := -1;
  SeekPositionMs := 0;
  SeekMaxMs := 0;
  LoopSegmentStartMs := -1;
  LoopSegmentEndMs := -1;
end;

procedure TVideoMinerMediaSession.ConfigureMedia(const FileName: string;
  const Info: TVideoInfo);
begin
  BeginLoad;
  VideoFile := FileName;
  VideoInfo := Info;
  SeekMaxMs := Round(VideoInfo.DurationSec * 1000);
end;

end.
