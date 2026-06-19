unit MMTimer;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls;

type
  // ---- High precision clock (QPC with fallback) ----
  TMMTimerClock = class
  private
    FUseQPC : Boolean;
    FFreq   : Int64;
    function GetNowTick: Int64;
  public
    constructor Create;
    function NowTick: Int64; inline;          // raw tick (QPC or ms)
    function TickToMs(const Tick: Int64): Cardinal;
  end;

  // ---- Compatibility shells (private fields only; kept for interface compatibility) ----
  TMMTimerThread = class(TObject)
  end;

  TMMTimerDispatcher = class(TObject)
  end;

  // ---- Main timer component (TTimer-based trigger + high precision elapsed) ----
  TMMTimer = class(TComponent)
  private
    FEnabled    : Boolean;
    FInterval   : Cardinal;
    FOnTimer    : TNotifyEvent;

    FClock      : TMMTimerClock;
    FThread     : TMMTimerThread;
    FDispatcher : TMMTimerDispatcher;

    FTimer      : TTimer;

    // time state
    FStarted            : Boolean;
    FStartTick          : Int64;    // absolute base (for reference)
    FLastTick           : Int64;    // last OnTimer tick (for delta)
    FLastDeltaMs        : Cardinal; // cached delta for GetTickCnt
    FAccumulatedMs      : Cardinal; // elapsed accumulated while paused/stopped
    FLastResumeTick     : Int64;    // tick when (re)enabled

    procedure SetEnabled(Value: Boolean);
    procedure SetInterval(Value: Cardinal);

    procedure InternalStartThread;
    procedure InternalStopThread;

    procedure TimerTick(Sender: TObject);
    procedure DoTimer; // Dispatcher から呼ばれる（= TTimer から呼ぶ）
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Start; // 計測基準リセット
    procedure Stop;  // タイマー停止（スレッド停止相当）

    function GetTickCnt: Cardinal;   // 差分（ms）: 前回発火→今回発火
    function ElapsedTime: Cardinal;  // 絶対経過（ms）: Start基準（Pause考慮）
  published
    property Enabled  : Boolean  read FEnabled  write SetEnabled;
    property Interval : Cardinal read FInterval write SetInterval;
    property OnTimer  : TNotifyEvent read FOnTimer write FOnTimer;
  end;

implementation

{ TMMTimerClock }

constructor TMMTimerClock.Create;
begin
  inherited Create;
  FFreq := 0;
  FUseQPC := QueryPerformanceFrequency(FFreq) and (FFreq > 0);
end;

function TMMTimerClock.GetNowTick: Int64;
begin
  if FUseQPC then
  begin
    QueryPerformanceCounter(Result);
  end
  else
  begin
    // fallback: ms-based tick
    Result := Int64(GetTickCount64);
  end;
end;

function TMMTimerClock.NowTick: Int64;
begin
  Result := GetNowTick;
end;

function TMMTimerClock.TickToMs(const Tick: Int64): Cardinal;
var
  ms: UInt64;
begin
  if FUseQPC then
  begin
    // ms = Tick * 1000 / FFreq
    ms := UInt64((Tick * 1000) div FFreq);
  end
  else
  begin
    // already ms
    if Tick < 0 then
      ms := 0
    else
      ms := UInt64(Tick);
  end;

  if ms > High(Cardinal) then
    Result := High(Cardinal)
  else
    Result := Cardinal(ms);
end;

{ TMMTimer }

constructor TMMTimer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FClock := TMMTimerClock.Create;

  // kept only for compatibility with your previous internal structure
  FThread := TMMTimerThread.Create;
  FDispatcher := TMMTimerDispatcher.Create;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;

  FEnabled := False;
  FInterval := 15; // default (practical)
  FTimer.Interval := Integer(FInterval);

  FStarted := False;
  FStartTick := 0;
  FLastTick := 0;
  FLastDeltaMs := 0;
  FAccumulatedMs := 0;
  FLastResumeTick := 0;
end;

destructor TMMTimer.Destroy;
begin
  // ensure stopped
  try
    InternalStopThread;
  except
    // ignore on destroy
  end;

  FreeAndNil(FTimer);
  FreeAndNil(FDispatcher);
  FreeAndNil(FThread);
  FreeAndNil(FClock);

  inherited Destroy;
end;

procedure TMMTimer.Loaded;
begin
  inherited;
  // apply properties after streaming
  SetInterval(FInterval);
  SetEnabled(FEnabled);
end;

procedure TMMTimer.SetInterval(Value: Cardinal);
begin
  if Value = 0 then
    Value := 1;

  FInterval := Value;
  if Assigned(FTimer) then
    FTimer.Interval := Integer(FInterval);
end;

procedure TMMTimer.SetEnabled(Value: Boolean);
var
  nowTick: Int64;
  deltaTick: Int64;
begin
  if FEnabled = Value then
    Exit;

  nowTick := FClock.NowTick;

  if Value then
  begin
    // enabling: avoid "huge delta" by resetting last tick
    if not FStarted then
    begin
      // first enable without explicit Start -> behave sensibly
      FStarted := True;
      FAccumulatedMs := 0;
      FStartTick := nowTick;
    end;

    FLastResumeTick := nowTick;
    FLastTick := nowTick;
    FLastDeltaMs := 0;
    InternalStartThread;
    FEnabled := True;
  end
  else
  begin
    // disabling: accumulate elapsed so far (Pause)
    if FStarted then
    begin
      deltaTick := nowTick - FLastResumeTick;
      Inc(FAccumulatedMs, FClock.TickToMs(deltaTick));
    end;

    InternalStopThread;
    FEnabled := False;

    // while disabled, delta is not meaningful; keep last delta as-is or clear.
    FLastDeltaMs := 0;
  end;
end;

procedure TMMTimer.InternalStartThread;
begin
  if Assigned(FTimer) then
    FTimer.Enabled := True;
end;

procedure TMMTimer.InternalStopThread;
begin
  if Assigned(FTimer) then
    FTimer.Enabled := False;
end;

procedure TMMTimer.Start;
var
  nowTick: Int64;
begin
  nowTick := FClock.NowTick;

  FStarted := True;
  FAccumulatedMs := 0;
  FStartTick := nowTick;

  // if already enabled, reset running base too
  FLastResumeTick := nowTick;
  FLastTick := nowTick;
  FLastDeltaMs := 0;
end;

procedure TMMTimer.Stop;
begin
  // Stop = timer停止（Pause）として扱う：EnabledをFalseへ
  SetEnabled(False);
end;

function TMMTimer.GetTickCnt: Cardinal;
begin
  Result := FLastDeltaMs;
end;

function TMMTimer.ElapsedTime: Cardinal;
var
  nowTick: Int64;
  deltaTick: Int64;
  ms: UInt64;
begin
  if not FStarted then
    Exit(0);

  ms := UInt64(FAccumulatedMs);

  if FEnabled then
  begin
    nowTick := FClock.NowTick;
    deltaTick := nowTick - FLastResumeTick;
    Inc(ms, UInt64(FClock.TickToMs(deltaTick)));
  end;

  if ms > High(Cardinal) then
    Result := High(Cardinal)
  else
    Result := Cardinal(ms);
end;

procedure TMMTimer.TimerTick(Sender: TObject);
begin
  DoTimer;
end;

procedure TMMTimer.DoTimer;
var
  nowTick: Int64;
  deltaTick: Int64;
begin
  if not FEnabled then
    Exit;

  if not FStarted then
  begin
    // safety: auto-start if never started
    Start;
  end;

  nowTick := FClock.NowTick;

  // delta from last tick (real elapsed between calls)
  deltaTick := nowTick - FLastTick;
  FLastDeltaMs := FClock.TickToMs(deltaTick);

  // update last tick
  FLastTick := nowTick;

  // notify
  if Assigned(FOnTimer) then
    FOnTimer(Self);
end;

end.

