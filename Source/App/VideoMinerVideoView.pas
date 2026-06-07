unit VideoMinerVideoView;

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Graphics, FFmpegDecoder, VideoMinerOverlay, VideoMinerVideoSurface;

type
  TVideoMinerVideoView = class
  private
    FSurface: TVideoMinerVideoSurface;
    function GetSurfaceControl: TWinControl;
    function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
      out BufferStride: Integer; out ErrorMessage: string): Boolean;
    procedure SetBossMode(Value: Boolean);
    procedure SetCanNavigateNext(Value: Boolean);
    procedure SetCanNavigatePrevious(Value: Boolean);
    procedure SetEndActionText(const Value: string);
    procedure SetFullScreen(Value: Boolean);
    procedure SetOnEndActionClick(Value: TNotifyEvent);
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    procedure SetOnFullScreenClick(Value: TNotifyEvent);
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    procedure SetMuted(Value: Boolean);
    procedure SetOnBossExitClick(Value: TNotifyEvent);
    procedure SetOnBossGesture(Value: TNotifyEvent);
    procedure SetOnMuteClick(Value: TNotifyEvent);
    procedure SetOnNavigateNextClick(Value: TNotifyEvent);
    procedure SetOnNavigatePreviousClick(Value: TNotifyEvent);
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    procedure SetOnSkipBackwardClick(Value: TNotifyEvent);
    procedure SetOnSkipForwardClick(Value: TNotifyEvent);
    procedure SetOnVolumeChange(Value: TVideoMinerOverlayVolumeEvent);
    procedure SetPlaybackActive(Value: Boolean);
    procedure SetVolumePercent(Value: Integer);
  public
    constructor Create(Image: TImage);
    destructor Destroy; override;
    procedure Clear;
    function ShowFrameAt(Decoder: TFFmpegDecoder; PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    function DecodeNextFrame(Decoder: TFFmpegDecoder; ConvertFrame: Boolean;
      out PositionMs: Integer; out ErrorMessage: string): Boolean;
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    function ShowNextFrame(Decoder: TFFmpegDecoder; out PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    procedure Present(Bitmap: TBitmap);
    procedure PresentImmediate(Bitmap: TBitmap);
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    property BossMode: Boolean write SetBossMode;
    property CanNavigateNext: Boolean write SetCanNavigateNext;
    property CanNavigatePrevious: Boolean write SetCanNavigatePrevious;
    property EndActionText: string write SetEndActionText;
    property FullScreen: Boolean write SetFullScreen;
    property OnBossExitClick: TNotifyEvent write SetOnBossExitClick;
    property OnBossGesture: TNotifyEvent write SetOnBossGesture;
    property OnEndActionClick: TNotifyEvent write SetOnEndActionClick;
    property OnFirstFrameClick: TNotifyEvent write SetOnFirstFrameClick;
    property OnFullScreenClick: TNotifyEvent write SetOnFullScreenClick;
    property OnLastFrameClick: TNotifyEvent write SetOnLastFrameClick;
    property OnMuteClick: TNotifyEvent write SetOnMuteClick;
    property OnNavigateNextClick: TNotifyEvent write SetOnNavigateNextClick;
    property OnNavigatePreviousClick: TNotifyEvent write SetOnNavigatePreviousClick;
    property OnPlayPauseClick: TNotifyEvent write SetOnPlayPauseClick;
    property OnSeek: TVideoMinerOverlaySeekEvent write SetOnSeek;
    property OnSkipBackwardClick: TNotifyEvent write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent write SetOnSkipForwardClick;
    property OnVolumeChange: TVideoMinerOverlayVolumeEvent write SetOnVolumeChange;
    property PlaybackActive: Boolean write SetPlaybackActive;
    property SurfaceControl: TWinControl read GetSurfaceControl;
    property Muted: Boolean write SetMuted;
    property VolumePercent: Integer write SetVolumePercent;
  end;

implementation

function TVideoMinerVideoView.GetSurfaceControl: TWinControl;
begin
  Result := FSurface;
end;

function TVideoMinerVideoView.PrepareFrameBuffer(Decoder: TFFmpegDecoder;
  out Buffer: Pointer; out BufferStride: Integer;
  out ErrorMessage: string): Boolean;
begin
  Buffer := nil;
  BufferStride := 0;
  ErrorMessage := '';
  Result := False;

  if (Decoder.Info.Width <= 0) or (Decoder.Info.Height <= 0) then
  begin
    ErrorMessage := 'Video size is invalid.';
    Exit;
  end;

  if (FSurface = nil) or
     (not FSurface.PrepareBgrx32Frame(Decoder.Info.Width, Decoder.Info.Height,
       Buffer, BufferStride)) then
  begin
    ErrorMessage := 'Failed to prepare video surface.';
    Exit;
  end;

  Result := True;
end;

constructor TVideoMinerVideoView.Create(Image: TImage);
begin
  inherited Create;

  FSurface := TVideoMinerVideoSurface.Create(Image.Owner);
  FSurface.Parent := Image.Parent;
  FSurface.Align := Image.Align;
  FSurface.SetBounds(Image.Left, Image.Top, Image.Width, Image.Height);
  FSurface.Anchors := Image.Anchors;
  FSurface.Visible := Image.Visible;
  FSurface.TabStop := False;
  FSurface.SendToBack;

  Image.Visible := False;
end;

destructor TVideoMinerVideoView.Destroy;
begin
  FSurface.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoView.Clear;
begin
  if FSurface <> nil then
    FSurface.Clear;
end;

procedure TVideoMinerVideoView.Present(Bitmap: TBitmap);
begin
  if FSurface <> nil then
    FSurface.Present;
end;

procedure TVideoMinerVideoView.PresentImmediate(Bitmap: TBitmap);
begin
  if FSurface <> nil then
    FSurface.PresentImmediate;
end;

procedure TVideoMinerVideoView.SetOnPlayPauseClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnPlayPauseClick := Value;
end;

procedure TVideoMinerVideoView.SetBossMode(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.BossMode := Value;
end;

procedure TVideoMinerVideoView.SetFullScreen(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.FullScreen := Value;
end;

procedure TVideoMinerVideoView.SetOnFullScreenClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnFullScreenClick := Value;
end;

procedure TVideoMinerVideoView.SetOnBossExitClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnBossExitClick := Value;
end;

procedure TVideoMinerVideoView.SetOnBossGesture(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnBossGesture := Value;
end;

procedure TVideoMinerVideoView.SetOnMuteClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnMuteClick := Value;
end;

procedure TVideoMinerVideoView.SetOnEndActionClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnEndActionClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
begin
  if FSurface <> nil then
    FSurface.OnSeek := Value;
end;

procedure TVideoMinerVideoView.SetOnVolumeChange(
  Value: TVideoMinerOverlayVolumeEvent);
begin
  if FSurface <> nil then
    FSurface.OnVolumeChange := Value;
end;

procedure TVideoMinerVideoView.SetOnFirstFrameClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnFirstFrameClick := Value;
end;

procedure TVideoMinerVideoView.SetOnLastFrameClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnLastFrameClick := Value;
end;

procedure TVideoMinerVideoView.SetOnNavigatePreviousClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnNavigatePreviousClick := Value;
end;

procedure TVideoMinerVideoView.SetOnNavigateNextClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnNavigateNextClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSkipBackwardClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnSkipBackwardClick := Value;
end;

procedure TVideoMinerVideoView.SetOnSkipForwardClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnSkipForwardClick := Value;
end;

procedure TVideoMinerVideoView.SetPlaybackActive(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.PlaybackActive := Value;
end;

procedure TVideoMinerVideoView.SetCanNavigatePrevious(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.CanNavigatePrevious := Value;
end;

procedure TVideoMinerVideoView.SetCanNavigateNext(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.CanNavigateNext := Value;
end;

procedure TVideoMinerVideoView.SetEndActionText(const Value: string);
begin
  if FSurface <> nil then
    FSurface.EndActionText := Value;
end;

procedure TVideoMinerVideoView.SetSeekProgress(PositionMs, MaxMs: Integer);
begin
  if FSurface <> nil then
    FSurface.SetSeekProgress(PositionMs, MaxMs);
end;

procedure TVideoMinerVideoView.SetVolumePercent(Value: Integer);
begin
  if FSurface <> nil then
    FSurface.VolumePercent := Value;
end;

procedure TVideoMinerVideoView.SetMuted(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.Muted := Value;
end;

function TVideoMinerVideoView.ShowFrameAt(Decoder: TFFmpegDecoder;
  PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
begin
  ErrorMessage := '';
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if (not PrepareFrameBuffer(Decoder, Buffer, BufferStride, ErrorMessage)) or
     (not Decoder.DecodeFrameToBgrx32(PositionMs, Buffer, BufferStride, ErrorMessage)) then
    Exit;

  PresentImmediate(FSurface.Bitmap);
  Result := True;
end;

function TVideoMinerVideoView.DecodeNextFrame(Decoder: TFFmpegDecoder;
  ConvertFrame: Boolean; out PositionMs: Integer;
  out ErrorMessage: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;
  Buffer := nil;
  BufferStride := 0;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if ConvertFrame and
     (not PrepareFrameBuffer(Decoder, Buffer, BufferStride, ErrorMessage)) then
    Exit;

  if not Decoder.DecodeNextFrameToBgrx32Optional(Buffer, BufferStride,
    ConvertFrame, PositionMs, ErrorMessage) then
    Exit;

  if ConvertFrame then
    Present(FSurface.Bitmap);

  Result := True;
end;

function TVideoMinerVideoView.HandleMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := (FSurface <> nil) and
    FSurface.HandleMouseWheel(Shift, WheelDelta, MousePos);
end;

function TVideoMinerVideoView.ShowNextFrame(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  Result := DecodeNextFrame(Decoder, True, PositionMs, ErrorMessage);
end;

end.
