unit FFmpegForwardReadBuffer;

// FFmpeg custom AVIO 用の実験的な前方読み込みバッファ。
// decoder role と環境変数で有効対象を絞り、NAS/USB向け I/O の効果と無駄を計測する。

interface

uses
  System.Classes, System.SyncObjs, System.SysUtils, FFmpegDecoderTypes;

type
  TFFmpegForwardReadBuffer = class
  private
    FFileName        : string;             // 対象ファイル
    FFileSize        : Int64;              // 対象ファイルサイズ
    FRole            : TFFmpegDecoderRole; // このバッファを持つ decoder の役割
    FOpenSequence    : Int64;              // open ログと対応させる通番
    FStream          : TFileStream;        // 同期読み込み用のファイル handle
    FLock            : TCriticalSection;   // バッファ状態の短時間保護
    FBuffer          : TBytes;             // 連続した前方読み込み領域
    FBufferStart     : Int64;              // FBuffer[0] が対応するファイル位置
    FBufferReadSize  : Integer;            // 読み込み済みバイト数
    FBufferCapacity  : Integer;            // バッファ最大サイズ
    FInitialReadSize : Integer;            // miss 時に同期で読み込む最小サイズ
    FPrefetchTrigger : Integer;            // 末尾からこの距離に近づいたら続きを読む
    FGeneration      : Int64;              // seek/miss で古い先読みを無効化する世代
    FPosition        : Int64;              // AVIO から見た現在位置
    FWorker          : TThread;            // 先読み worker
    FAvioContext     : Pointer;            // FFmpeg AVIOContext
    FAvioBuffer      : Pointer;            // AVIOContext 用の FFmpeg 管理メモリ
    FReadRequests    : Int64;              // FFmpeg からの read callback 回数
    FRequestedBytes  : Int64;              // FFmpeg から要求された総バイト数
    FHitReads        : Int64;              // バッファ hit 回数
    FHitBytes        : Int64;              // バッファから返したバイト数
    FMissReads       : Int64;              // バッファ miss 回数
    FDirectReads     : Int64;              // バッファ外から直接読んだ回数
    FDirectBytes     : Int64;              // direct read で返したバイト数
    FFillReads       : Int64;              // window 作成回数
    FFillBytes       : Int64;              // window 作成で読んだバイト数
    FPrefetchReads   : Int64;              // worker 完了回数
    FPrefetchBytes   : Int64;              // worker が追加したバイト数
    function CopyFromBuffer(Position: Int64; Dest: PByte; Size: Integer): Boolean;
    function DirectRead(Position: Int64; Dest: PByte; Size: Integer): Integer;
    function FillWindow(Position: Int64; RequestSize: Integer): Integer;
    function ReadPacket(Dest: PByte; Size: Integer): Integer;
    function Seek(Offset: Int64; Whence: Integer): Int64;
    procedure CancelWorker;
    procedure CleanupFinishedWorker;
    procedure LogSummary;
    procedure StartPrefetchIfNeeded(AfterReadPosition: Int64);
    procedure WorkerPrefetch(StartPosition, Generation: Int64);
  public
    constructor Create(Role: TFFmpegDecoderRole; OpenSequence: Int64);
    destructor Destroy; override;
    function Open(const FileName: string; out ErrorMessage: string): Boolean;
    function CreateAvioContext(out ErrorMessage: string): Boolean;
    property AvioContext: Pointer read FAvioContext;
  end;

function VideoMinerForwardReadBufferEnabled(Role: TFFmpegDecoderRole): Boolean;
function VideoMinerForwardReadBufferModeText: string;

implementation

uses
  System.Diagnostics, System.Math, FFmpegApi, VideoMinerDebugLog;

const
  AVIO_BUFFER_SIZE    = 32768;
  DEFAULT_INITIAL_MB  = 32;
  DEFAULT_CAPACITY_MB = 128;
  DEFAULT_TRIGGER_MB  = 16;
  SEEK_SET_VALUE      = 0;
  SEEK_CUR_VALUE      = 1;
  SEEK_END_VALUE      = 2;

function ReadEnvInt(const Name: string; DefaultValue, MinValue, MaxValue: Integer): Integer;
var
  Text: string;
begin
  Text := GetEnvironmentVariable(Name);
  if (Text = '') or (not TryStrToInt(Text, Result)) then
    Result := DefaultValue;
  Result := EnsureRange(Result, MinValue, MaxValue);
end;

function VideoMinerForwardReadBufferModeText: string;
begin
  Result := LowerCase(GetEnvironmentVariable('VIDEOMINER_FILE_BUFFER_MODE'));
  if Result = '' then
  begin
    if SameText(GetEnvironmentVariable('VIDEOMINER_FILE_BUFFER'), '1') or
       SameText(GetEnvironmentVariable('VIDEOMINER_FILE_BUFFER'), 'on') or
       SameText(GetEnvironmentVariable('VIDEOMINER_FILE_BUFFER'), 'true') then
      Result := 'all'
    else
      Result := 'off';
  end;
end;

function VideoMinerForwardReadBufferEnabled(Role: TFFmpegDecoderRole): Boolean;
var
  Mode: string;
begin
  Mode := VideoMinerForwardReadBufferModeText;
  if (Mode = '1') or (Mode = 'on') or (Mode = 'true') or (Mode = 'all') then
    Exit(True);
  if Mode = 'main' then
    Exit(Role = fdrPlaybackMain);
  Result := False;
end;

function AvioReadPacket(Opaque: Pointer; Buf: PByte; BufSize: Integer): Integer; cdecl;
begin
  Result := TFFmpegForwardReadBuffer(Opaque).ReadPacket(Buf, BufSize);
end;

function AvioSeek(Opaque: Pointer; Offset: Int64; Whence: Integer): Int64; cdecl;
begin
  Result := TFFmpegForwardReadBuffer(Opaque).Seek(Offset, Whence);
end;

constructor TFFmpegForwardReadBuffer.Create(Role: TFFmpegDecoderRole; OpenSequence: Int64);
begin
  inherited Create;
  FRole := Role;
  FOpenSequence := OpenSequence;
  FLock := TCriticalSection.Create;
  FInitialReadSize := ReadEnvInt('VIDEOMINER_FILE_BUFFER_INITIAL_MB',
    DEFAULT_INITIAL_MB, 1, 512) * 1024 * 1024;
  FBufferCapacity := ReadEnvInt('VIDEOMINER_FILE_BUFFER_MB',
    DEFAULT_CAPACITY_MB, 4, 1024) * 1024 * 1024;
  FPrefetchTrigger := ReadEnvInt('VIDEOMINER_FILE_BUFFER_TRIGGER_MB',
    DEFAULT_TRIGGER_MB, 1, 256) * 1024 * 1024;
end;

destructor TFFmpegForwardReadBuffer.Destroy;
begin
  LogSummary;
  CancelWorker;
  if FAvioContext <> nil then
    TFFmpegApi.avio_context_free(@FAvioContext);
  if FAvioBuffer <> nil then
  begin
    TFFmpegApi.av_free(FAvioBuffer);
    FAvioBuffer := nil;
  end;
  FStream.Free;
  FLock.Free;
  inherited Destroy;
end;

function TFFmpegForwardReadBuffer.Open(const FileName: string; out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  Result := False;
  try
    FFileName := FileName;
    FStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    FFileSize := FStream.Size;
    if FFileSize < FBufferCapacity then
      FBufferCapacity := Integer(Max(0, FFileSize));
    SetLength(FBuffer, FBufferCapacity);
    FBufferStart := 0;
    FBufferReadSize := 0;
    FPosition := 0;
    WriteVideoMinerSlowLog(Format(
      'file_buffer_open seq=%d role=%s file="%s" size=%d capacity_mb=%d initial_mb=%d trigger_mb=%d mode=%s',
      [FOpenSequence, FFmpegDecoderRoleText(FRole), ExtractFileName(FileName),
       FFileSize, FBufferCapacity div 1024 div 1024,
       FInitialReadSize div 1024 div 1024, FPrefetchTrigger div 1024 div 1024,
       VideoMinerForwardReadBufferModeText]));
    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

function TFFmpegForwardReadBuffer.CreateAvioContext(out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  Result := False;
  FAvioBuffer := TFFmpegApi.av_malloc(AVIO_BUFFER_SIZE);
  if FAvioBuffer = nil then
  begin
    ErrorMessage := 'av_malloc failed for AVIO buffer.';
    Exit;
  end;
  FAvioContext := TFFmpegApi.avio_alloc_context(PByte(FAvioBuffer), AVIO_BUFFER_SIZE,
    0, Self, @AvioReadPacket, nil, @AvioSeek);
  if FAvioContext = nil then
  begin
    ErrorMessage := 'avio_alloc_context failed.';
    Exit;
  end;
  Result := True;
end;

procedure TFFmpegForwardReadBuffer.CancelWorker;
begin
  Inc(FGeneration);
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FWorker.Free;
    FWorker := nil;
  end;
end;

procedure TFFmpegForwardReadBuffer.CleanupFinishedWorker;
begin
  if (FWorker <> nil) and FWorker.Finished then
  begin
    FWorker.WaitFor;
    FWorker.Free;
    FWorker := nil;
  end;
end;

function TFFmpegForwardReadBuffer.CopyFromBuffer(Position: Int64; Dest: PByte; Size: Integer): Boolean;
var
  Offset: Int64;
begin
  Result := False;
  FLock.Enter;
  try
    Offset := Position - FBufferStart;
    if (Offset >= 0) and (Size >= 0) and (Offset + Size <= FBufferReadSize) then
    begin
      if Size > 0 then
        Move(FBuffer[Integer(Offset)], Dest^, Size);
      Inc(FHitReads);
      Inc(FHitBytes, Size);
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFFmpegForwardReadBuffer.DirectRead(Position: Int64; Dest: PByte; Size: Integer): Integer;
var
  Watch: TStopwatch;
begin
  Result := 0;
  if (Size <= 0) or (Position >= FFileSize) then
    Exit;

  Watch := TStopwatch.StartNew;
  FLock.Enter;
  try
    FStream.Position := Position;
    Result := FStream.Read(Dest^, Min(Int64(Size), FFileSize - Position));
    Inc(FDirectReads);
    Inc(FDirectBytes, Result);
  finally
    FLock.Leave;
  end;
  WriteVideoMinerSlowLog(Format(
    'file_buffer_direct_read seq=%d role=%s pos=%d requested=%d read=%d ms=%.3f direct=%d hit=%d miss=%d',
    [FOpenSequence, FFmpegDecoderRoleText(FRole), Position, Size, Result,
     Watch.Elapsed.TotalMilliseconds, FDirectReads, FHitReads, FMissReads]));
end;

function TFFmpegForwardReadBuffer.FillWindow(Position: Int64; RequestSize: Integer): Integer;
var
  BytesToRead: Integer;
  Watch: TStopwatch;
begin
  Result := 0;
  if FBufferCapacity <= 0 then
    Exit;

  CancelWorker;
  BytesToRead := Min(FBufferCapacity, Max(RequestSize, FInitialReadSize));
  BytesToRead := Integer(Min(Int64(BytesToRead), FFileSize - Position));
  if BytesToRead <= 0 then
    Exit;

  Watch := TStopwatch.StartNew;
  FLock.Enter;
  try
    FBufferStart := Position;
    FBufferReadSize := 0;
    FStream.Position := Position;
    Result := FStream.Read(FBuffer[0], BytesToRead);
    FBufferReadSize := Result;
    Inc(FFillReads);
    Inc(FFillBytes, Result);
  finally
    FLock.Leave;
  end;
  WriteVideoMinerSlowLog(Format(
    'file_buffer_fill seq=%d role=%s pos=%d requested=%d read=%d capacity=%d ms=%.3f generation=%d',
    [FOpenSequence, FFmpegDecoderRoleText(FRole), Position, RequestSize, Result,
     FBufferCapacity, Watch.Elapsed.TotalMilliseconds, FGeneration]));
end;

function TFFmpegForwardReadBuffer.ReadPacket(Dest: PByte; Size: Integer): Integer;
var
  EffectiveSize: Integer;
begin
  if Size <= 0 then
    Exit(0);
  if FPosition >= FFileSize then
    Exit(0);

  Inc(FReadRequests);
  Inc(FRequestedBytes, Size);
  EffectiveSize := Integer(Min(Int64(Size), FFileSize - FPosition));
  if CopyFromBuffer(FPosition, Dest, EffectiveSize) then
  begin
    Result := EffectiveSize;
    Inc(FPosition, Result);
    StartPrefetchIfNeeded(FPosition);
    Exit;
  end;

  Inc(FMissReads);
  FillWindow(FPosition, EffectiveSize);
  if CopyFromBuffer(FPosition, Dest, EffectiveSize) then
  begin
    Result := EffectiveSize;
    Inc(FPosition, Result);
    StartPrefetchIfNeeded(FPosition);
    Exit;
  end;

  Result := DirectRead(FPosition, Dest, EffectiveSize);
  Inc(FPosition, Result);
  StartPrefetchIfNeeded(FPosition);
end;

function TFFmpegForwardReadBuffer.Seek(Offset: Int64; Whence: Integer): Int64;
var
  NewPosition: Int64;
begin
  if Whence = AVSEEK_SIZE then
    Exit(FFileSize);

  case Whence of
    SEEK_SET_VALUE:
      NewPosition := Offset;
    SEEK_CUR_VALUE:
      NewPosition := FPosition + Offset;
    SEEK_END_VALUE:
      NewPosition := FFileSize + Offset;
  else
    Exit(-1);
  end;

  NewPosition := EnsureRange(NewPosition, 0, FFileSize);
  if Abs(NewPosition - FPosition) > FPrefetchTrigger then
  begin
    CancelWorker;
    WriteVideoMinerSlowLog(Format(
      'file_buffer_seek seq=%d role=%s old=%d new=%d generation=%d',
      [FOpenSequence, FFmpegDecoderRoleText(FRole), FPosition, NewPosition,
       FGeneration]));
  end;
  FPosition := NewPosition;
  Result := FPosition;
end;

procedure TFFmpegForwardReadBuffer.LogSummary;
var
  PossibleUnusedBytes: Int64;
  StorageReadBytes: Int64;
begin
  if FFileName = '' then
    Exit;

  StorageReadBytes := FFillBytes + FPrefetchBytes + FDirectBytes;
  PossibleUnusedBytes := Max(Int64(0), StorageReadBytes - FHitBytes - FDirectBytes);
  WriteVideoMinerSlowLog(Format(
    'file_buffer_summary seq=%d role=%s file="%s" requests=%d requested_bytes=%d hits=%d hit_bytes=%d misses=%d direct_reads=%d direct_bytes=%d fills=%d fill_bytes=%d prefetches=%d prefetch_bytes=%d possible_unused_prefetch_bytes=%d',
    [FOpenSequence, FFmpegDecoderRoleText(FRole), ExtractFileName(FFileName),
     FReadRequests, FRequestedBytes, FHitReads, FHitBytes, FMissReads,
     FDirectReads, FDirectBytes, FFillReads, FFillBytes, FPrefetchReads,
     FPrefetchBytes, PossibleUnusedBytes]));
end;

procedure TFFmpegForwardReadBuffer.StartPrefetchIfNeeded(AfterReadPosition: Int64);
var
  EndPosition: Int64;
  Generation: Int64;
begin
  CleanupFinishedWorker;
  if FWorker <> nil then
    Exit;

  FLock.Enter;
  try
    EndPosition := FBufferStart + FBufferReadSize;
    if (FBufferReadSize >= FBufferCapacity) or
       (AfterReadPosition < EndPosition - FPrefetchTrigger) or
       (EndPosition >= FFileSize) then
      Exit;
    Generation := FGeneration;
  finally
    FLock.Leave;
  end;

  FWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      WorkerPrefetch(EndPosition, Generation);
    end);
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
end;

procedure TFFmpegForwardReadBuffer.WorkerPrefetch(StartPosition, Generation: Int64);
const
  CHUNK_SIZE = 1024 * 1024;
var
  LocalStream: TFileStream;
  OriginalStart: Int64;
  PrefetchedBytes: Int64;
  ReadBytes: Integer;
  Temp: TBytes;
  Watch: TStopwatch;
  WriteOffset: Integer;
begin
  OriginalStart := StartPosition;
  PrefetchedBytes := 0;
  Watch := TStopwatch.StartNew;
  SetLength(Temp, CHUNK_SIZE);
  LocalStream := nil;
  try
    LocalStream := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone);
    LocalStream.Position := StartPosition;
    while (Generation = FGeneration) and (StartPosition < FFileSize) do
    begin
      ReadBytes := LocalStream.Read(Temp[0],
        Min(Int64(CHUNK_SIZE), FFileSize - StartPosition));
      if ReadBytes <= 0 then
        Break;

      FLock.Enter;
      try
        if (Generation <> FGeneration) or
           (StartPosition <> FBufferStart + FBufferReadSize) or
           (FBufferReadSize >= FBufferCapacity) then
          Break;
        WriteOffset := FBufferReadSize;
        ReadBytes := Min(ReadBytes, FBufferCapacity - FBufferReadSize);
        Move(Temp[0], FBuffer[WriteOffset], ReadBytes);
        Inc(FBufferReadSize, ReadBytes);
        Inc(StartPosition, ReadBytes);
        Inc(PrefetchedBytes, ReadBytes);
      finally
        FLock.Leave;
      end;

      if ReadBytes < CHUNK_SIZE then
        Break;
    end;
  finally
    LocalStream.Free;
  end;

  FLock.Enter;
  try
    Inc(FPrefetchReads);
    Inc(FPrefetchBytes, PrefetchedBytes);
  finally
    FLock.Leave;
  end;
  WriteVideoMinerSlowLog(Format(
    'file_buffer_prefetch_done seq=%d role=%s start=%d bytes=%d buffered=%d generation=%d active_generation=%d ms=%.3f',
    [FOpenSequence, FFmpegDecoderRoleText(FRole), OriginalStart,
     PrefetchedBytes, FBufferReadSize, Generation, FGeneration,
     Watch.Elapsed.TotalMilliseconds]));
end;

end.
