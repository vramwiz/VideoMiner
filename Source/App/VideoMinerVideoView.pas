unit VideoMinerVideoView;

interface

uses
  System.SysUtils, Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder,
  VideoMinerVideoSurface;

type
  TVideoMinerVideoView = class
  private
    FSurface: TVideoMinerVideoSurface;
    function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
      out BufferStride: Integer; out ErrorMessage: string): Boolean;
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

  Present(FSurface.Bitmap);
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
