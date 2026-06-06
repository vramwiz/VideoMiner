unit VideoMinerVideoView;

interface

uses
  System.Classes, System.SysUtils, Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder,
  VideoMinerOverlay, VideoMinerVideoSurface;

type
  TVideoMinerVideoView = class
  private
    FSurface: TVideoMinerVideoSurface;
    function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
      out BufferStride: Integer; out ErrorMessage: string): Boolean;
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    procedure SetOnPlayPauseClick(Value: TNotifyEvent);
    procedure SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
    procedure SetOnSkipBackwardClick(Value: TNotifyEvent);
    procedure SetOnSkipForwardClick(Value: TNotifyEvent);
    procedure SetPlaybackActive(Value: Boolean);
  public
    constructor Create(Image: TImage);
    destructor Destroy; override;
    procedure Clear;
    function ShowFrameAt(Decoder: TFFmpegDecoder; PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    function DecodeNextFrame(Decoder: TFFmpegDecoder; ConvertFrame: Boolean;
      out PositionMs: Integer; out ErrorMessage: string): Boolean;
    function ShowNextFrame(Decoder: TFFmpegDecoder; out PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    procedure Present(Bitmap: TBitmap);
    procedure PresentImmediate(Bitmap: TBitmap);
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    property OnFirstFrameClick: TNotifyEvent write SetOnFirstFrameClick;
    property OnLastFrameClick: TNotifyEvent write SetOnLastFrameClick;
    property OnPlayPauseClick: TNotifyEvent write SetOnPlayPauseClick;
    property OnSeek: TVideoMinerOverlaySeekEvent write SetOnSeek;
    property OnSkipBackwardClick: TNotifyEvent write SetOnSkipBackwardClick;
    property OnSkipForwardClick: TNotifyEvent write SetOnSkipForwardClick;
    property PlaybackActive: Boolean write SetPlaybackActive;
  end;

implementation

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

procedure TVideoMinerVideoView.SetOnSeek(Value: TVideoMinerOverlaySeekEvent);
begin
  if FSurface <> nil then
    FSurface.OnSeek := Value;
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

procedure TVideoMinerVideoView.SetSeekProgress(PositionMs, MaxMs: Integer);
begin
  if FSurface <> nil then
    FSurface.SetSeekProgress(PositionMs, MaxMs);
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

function TVideoMinerVideoView.ShowNextFrame(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  Result := DecodeNextFrame(Decoder, True, PositionMs, ErrorMessage);
end;

end.
