unit VideoMinerBossGesture;

// ボスが来たモードへ入るためのマウスジェスチャー検出を担当する
// 通常のビューア操作と衝突しにくい「短時間の往復移動」だけを拾う。
// 実際のモード切替や描画は App 側に任せ、このユニットは状態判定だけを持つ。

interface

uses
  System.Types;

const
  WINDOW_MS       = 900;  // 方向反転型ジェスチャーの有効時間 ms
  MIN_DISTANCE    = 220;  // 反転前後で必要な最小移動量 px
  COOLDOWN_MS     = 3000; // 発動直後の再発動禁止時間 ms
  AXIS_RATIO      = 2.0;  // 横/縦どちらの動きかを決める優勢比率
  NOISE_PIXELS    = 40;   // 微小なマウス揺れを無視する距離 px
  POINT_WINDOW_MS = 300;  // A-B-A 往復ジェスチャーの有効時間 ms
  POINT_DISTANCE  = 320;  // A から B 到達とみなす距離 px
  RETURN_RADIUS   = 26;   // A 付近へ戻ったとみなす半径 px
  STRONG_SEGMENTS = 2;    // 発動に必要な強い反転回数

type
  TVideoMinerBossGestureAxis = (bgaNone, bgaHorizontal, bgaVertical);

  TVideoMinerBossGestureDetector = class
  private
    FActiveAxis         : TVideoMinerBossGestureAxis; // 現在追跡中の移動軸
    FAnchorPoint        : TPoint;                     // A-B-A 判定の基準点 A
    FAnchorTick         : UInt64;                     // 基準点 A を記録した時刻
    FFarPointReached    : Boolean;                    // A から十分離れた B に到達済みか
    FDirection          : Integer;                    // 現在の軸方向。-1 または 1
    FHasLastPoint       : Boolean;                    // 前回座標が有効か
    FLastPoint          : TPoint;                     // 差分計算用の前回座標
    FLastTick           : UInt64;                     // 前回座標の時刻
    FLastTriggerTick    : UInt64;                     // 最後に発動した時刻
    FSegmentDistance    : Integer;                    // 現在方向へ積み上げた移動距離
    FStartTick          : UInt64;                     // 方向反転型判定の開始時刻
    FStrongSegmentCount : Integer;                    // 最小距離を満たして反転した回数
    // A から現在座標までの距離を返す
    function DistanceFromAnchor(const Point: TPoint): Double;
    // 発動時刻を記録し、次のジェスチャー判定状態へ戻す
    procedure MarkTriggered(Tick: UInt64);
    // 進行中のジェスチャー判定状態を初期化する
    procedure ResetGesture;
    // 方向反転型ジェスチャーの新しい区間を開始する
    procedure StartGesture(Axis: TVideoMinerBossGestureAxis; Direction,
      Distance: Integer; Tick: UInt64);
    // A から B へ離れて A 付近へ戻る往復ジェスチャーを判定する
    function UpdatePointReturnGesture(const Point: TPoint; Tick: UInt64): Boolean;
  public
    // 座標履歴を破棄し、次の MouseMove を新しい基準点として扱う
    procedure Reset;
    // マウス移動を取り込み、ボスが来たモードへ入るべきタイミングで True を返す
    function MouseMove(const Point: TPoint; Enabled: Boolean): Boolean;
  end;

implementation

uses
  System.Math, Winapi.Windows;

procedure TVideoMinerBossGestureDetector.Reset;
begin
  ResetGesture;
  FHasLastPoint := False;
end;

procedure TVideoMinerBossGestureDetector.ResetGesture;
begin
  FActiveAxis := bgaNone;
  FAnchorPoint := Point(0, 0);
  FAnchorTick := 0;
  FDirection := 0;
  FFarPointReached := False;
  FSegmentDistance := 0;
  FStartTick := 0;
  FStrongSegmentCount := 0;
end;

function TVideoMinerBossGestureDetector.DistanceFromAnchor(
  const Point: TPoint): Double;
begin
  Result := Hypot(Point.X - FAnchorPoint.X, Point.Y - FAnchorPoint.Y);
end;

procedure TVideoMinerBossGestureDetector.MarkTriggered(Tick: UInt64);
begin
  FLastTriggerTick := Tick;
  ResetGesture;
end;

procedure TVideoMinerBossGestureDetector.StartGesture(
  Axis: TVideoMinerBossGestureAxis; Direction, Distance: Integer; Tick: UInt64);
begin
  FActiveAxis := Axis;
  FDirection := Direction;
  FSegmentDistance := Distance;
  FStartTick := Tick;
  FStrongSegmentCount := 0;
end;

function TVideoMinerBossGestureDetector.UpdatePointReturnGesture(
  const Point: TPoint; Tick: UInt64): Boolean;
var
  Distance: Double;
begin
  Result := False;

  if (FAnchorTick = 0) or
     (Tick - FAnchorTick > POINT_WINDOW_MS) then
  begin
    FAnchorPoint := Point;
    FAnchorTick := Tick;
    FFarPointReached := False;
    Exit;
  end;

  Distance := DistanceFromAnchor(Point);
  if not FFarPointReached then
  begin
    if Distance >= POINT_DISTANCE then
      FFarPointReached := True;
    Exit;
  end;

  if Distance <= RETURN_RADIUS then
  begin
    Result := True;
    MarkTriggered(Tick);
  end;
end;

function TVideoMinerBossGestureDetector.MouseMove(const Point: TPoint;
  Enabled: Boolean): Boolean;
var
  AbsDx: Integer;
  AbsDy: Integer;
  Axis: TVideoMinerBossGestureAxis;
  Direction: Integer;
  Distance: Integer;
  Dx: Integer;
  Dy: Integer;
  Tick: UInt64;
begin
  Result := False;
  Tick := GetTickCount64;

  if not Enabled then
  begin
    ResetGesture;
    FHasLastPoint := False;
    Exit;
  end;

  if (FLastTriggerTick > 0) and
     (Tick - FLastTriggerTick < COOLDOWN_MS) then
  begin
    FLastPoint := Point;
    FHasLastPoint := True;
    Exit;
  end;

  if not FHasLastPoint then
  begin
    FLastPoint := Point;
    FLastTick := Tick;
    FAnchorPoint := Point;
    FAnchorTick := Tick;
    FFarPointReached := False;
    FHasLastPoint := True;
    Exit;
  end;

  if UpdatePointReturnGesture(Point, Tick) then
  begin
    Result := True;
    FLastPoint := Point;
    FLastTick := Tick;
    Exit;
  end;

  Dx := Point.X - FLastPoint.X;
  Dy := Point.Y - FLastPoint.Y;
  AbsDx := Abs(Dx);
  AbsDy := Abs(Dy);
  if AbsDx + AbsDy < NOISE_PIXELS then
    Exit;

  Axis := bgaNone;
  Direction := 0;
  Distance := 0;
  if AbsDx >= Round(AbsDy * AXIS_RATIO) then
  begin
    Axis := bgaHorizontal;
    Direction := IfThen(Dx > 0, 1, -1);
    Distance := AbsDx;
  end
  else if AbsDy >= Round(AbsDx * AXIS_RATIO) then
  begin
    Axis := bgaVertical;
    Direction := IfThen(Dy > 0, 1, -1);
    Distance := AbsDy;
  end;

  FLastPoint := Point;
  FLastTick := Tick;

  if Axis = bgaNone then
  begin
    ResetGesture;
    FAnchorPoint := Point;
    FAnchorTick := Tick;
    FFarPointReached := False;
    Exit;
  end;

  if (FActiveAxis = bgaNone) or
     (Tick - FStartTick > WINDOW_MS) or
     (Axis <> FActiveAxis) then
  begin
    StartGesture(Axis, Direction, Distance, Tick);
    Exit;
  end;

  if Direction = FDirection then
    Inc(FSegmentDistance, Distance)
  else
  begin
    if FSegmentDistance < MIN_DISTANCE then
    begin
      StartGesture(Axis, Direction, Distance, Tick);
      Exit;
    end;

    Inc(FStrongSegmentCount);
    FDirection := Direction;
    FSegmentDistance := Distance;
  end;

  if (FStrongSegmentCount >= STRONG_SEGMENTS) and
     (FSegmentDistance >= MIN_DISTANCE) and
     (Tick - FStartTick <= WINDOW_MS) then
  begin
    Result := True;
    MarkTriggered(Tick);
  end;
end;

end.
