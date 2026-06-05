unit VideoMinerVideoView;

interface

uses
  System.SysUtils, Vcl.ExtCtrls, Vcl.Graphics, FFmpegDecoder;

type
  TVideoMinerVideoView = class
  private
    FImage: TImage;
  public
    constructor Create(Image: TImage);
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
  FImage := Image;
end;

procedure TVideoMinerVideoView.Clear;
begin
  if FImage <> nil then
    FImage.Picture.Assign(nil);
end;

procedure TVideoMinerVideoView.Present(Bitmap: TBitmap);
begin
  if (FImage <> nil) and (Bitmap <> nil) then
    FImage.Picture.Bitmap.Assign(Bitmap);
end;

function TVideoMinerVideoView.ShowFrameAt(Decoder: TFFmpegDecoder;
  PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  Bitmap: TBitmap;
begin
  ErrorMessage := '';
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  Bitmap := TBitmap.Create;
  try
    if not Decoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage) then
      Exit;

    Present(Bitmap);
    Result := True;
  finally
    Bitmap.Free;
  end;
end;

function TVideoMinerVideoView.ShowNextFrame(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  Bitmap: TBitmap;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  Bitmap := TBitmap.Create;
  try
    if not Decoder.DecodeNextFrameToBitmap(Bitmap, PositionMs, ErrorMessage) then
      Exit;

    Present(Bitmap);
    Result := True;
  finally
    Bitmap.Free;
  end;
end;

end.
