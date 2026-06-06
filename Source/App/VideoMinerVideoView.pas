unit VideoMinerVideoView;

interface

uses
  System.SysUtils, Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder,
  VideoMinerVideoSurface;

type
  TVideoMinerVideoView = class
  private
    FSurface: TVideoMinerVideoSurface;
  public
    constructor Create(Image: TImage);
    destructor Destroy; override;
    procedure Clear;
    function ShowFrameAt(Decoder: TFFmpegDecoder; PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    function ShowNextFrame(Decoder: TFFmpegDecoder; out PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    procedure Present(Bitmap: TBitmap);
  end;

implementation

constructor TVideoMinerVideoView.Create(Image: TImage);
begin
  inherited Create;

  FSurface := TVideoMinerVideoSurface.Create(Image.Owner);
  FSurface.Parent := Image.Parent;
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
begin
  ErrorMessage := '';
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if (FSurface = nil) or
     (not Decoder.DecodeFrameToBitmap(PositionMs, FSurface.Bitmap, ErrorMessage)) then
    Exit;

  Present(FSurface.Bitmap);
  Result := True;
end;

function TVideoMinerVideoView.ShowNextFrame(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if (FSurface = nil) or
     (not Decoder.DecodeNextFrameToBitmap(FSurface.Bitmap, PositionMs, ErrorMessage)) then
    Exit;

  Present(FSurface.Bitmap);
  Result := True;
end;

end.
