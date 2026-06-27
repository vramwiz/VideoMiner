unit VideoMinerVideoAdjustmentController;

// 動画本体の一時的な表示補正を扱う。
// 設定保存はせず、キー入力から D3D 表示補正と左上ステータス表示へ橋渡しする。

interface

uses
  Winapi.Windows, System.Classes, System.Math, System.SysUtils,
  VideoMinerVideoView;

type
  TVideoMinerVideoAdjustmentController = class
  private
    FBrightness: Single;
    FContrast: Single;
    FVideoView: TVideoMinerVideoView;
    function BrightnessText: string;
    procedure Apply(const LabelText: string);
  public
    constructor Create(VideoView: TVideoMinerVideoView);
    function HandleKeyDown(var Key: Word; Shift: TShiftState): Boolean;
  end;

implementation

const
  BRIGHTNESS_STEP = 0.05;
  BRIGHTNESS_MIN = -0.50;
  BRIGHTNESS_MAX = 0.50;
  CONTRAST_STEP = 0.05;
  CONTRAST_MIN = 0.50;
  CONTRAST_MAX = 1.80;

constructor TVideoMinerVideoAdjustmentController.Create(
  VideoView: TVideoMinerVideoView);
begin
  inherited Create;
  FVideoView := VideoView;
  FBrightness := 0.0;
  FContrast := 1.0;
  if FVideoView <> nil then
    FVideoView.SetVideoColorAdjustment(FBrightness, FContrast);
end;

procedure TVideoMinerVideoAdjustmentController.Apply(const LabelText: string);
begin
  if FVideoView = nil then
    Exit;

  FVideoView.SetVideoColorAdjustment(FBrightness, FContrast);
  FVideoView.ShowTransientStatus(LabelText);
end;

function TVideoMinerVideoAdjustmentController.BrightnessText: string;
var
  Value: Integer;
begin
  Value := Round(FBrightness * 100);
  if Value > 0 then
    Result := Format('+%d', [Value])
  else
    Result := IntToStr(Value);
end;

function TVideoMinerVideoAdjustmentController.HandleKeyDown(var Key: Word;
  Shift: TShiftState): Boolean;
begin
  Result := False;
  if (Key <> VK_UP) and (Key <> VK_DOWN) then
    Exit;

  if (ssCtrl in Shift) and not (ssShift in Shift) and not (ssAlt in Shift) then
  begin
    if Key = VK_UP then
      FBrightness := Min(BRIGHTNESS_MAX, FBrightness + BRIGHTNESS_STEP)
    else
      FBrightness := Max(BRIGHTNESS_MIN, FBrightness - BRIGHTNESS_STEP);
    Apply('B ' + BrightnessText);
    Key := 0;
    Result := True;
    Exit;
  end;

  if (ssShift in Shift) and not (ssCtrl in Shift) and not (ssAlt in Shift) then
  begin
    if Key = VK_UP then
      FContrast := Min(CONTRAST_MAX, FContrast + CONTRAST_STEP)
    else
      FContrast := Max(CONTRAST_MIN, FContrast - CONTRAST_STEP);
    Apply(Format('C %d%%', [Round(FContrast * 100)]));
    Key := 0;
    Result := True;
  end;
end;

end.
