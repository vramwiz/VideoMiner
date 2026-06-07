unit VideoMinerVideoView;

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Graphics, FFmpegDecoder, VideoMinerOverlay, VideoMinerVideoSurface;

type
  TVideoMinerVideoView = class
  private
    FDecodeScratch: TBitmap;
    FSurface: TVideoMinerVideoSurface;
    function GetSurfaceControl: TWinControl;
    function PrepareBitmapFrameBuffer(Bitmap: TBitmap; Width, Height: Integer;
      out Buffer: Pointer; out BufferStride: Integer): Boolean;
    function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
      out BufferStride: Integer; out ErrorMessage: string): Boolean;
    procedure SetBossMode(Value: Boolean);
    procedure SetCanNavigateNext(Value: Boolean);
    procedure SetCanNavigatePrevious(Value: Boolean);
    procedure SetCheckEnabled(Value: Boolean);
    procedure SetChapters(const Value: TVideoMinerOverlayChapters);
    procedure SetEndActionText(const Value: string);
    procedure SetFullScreen(Value: Boolean);
    procedure SetOnEndActionClick(Value: TNotifyEvent);
    procedure SetOnFirstFrameClick(Value: TNotifyEvent);
    procedure SetOnFullScreenClick(Value: TNotifyEvent);
    procedure SetOnLastFrameClick(Value: TNotifyEvent);
    procedure SetMuted(Value: Boolean);
    procedure SetOnBossExitClick(Value: TNotifyEvent);
    procedure SetOnBossGesture(Value: TNotifyEvent);
    procedure SetOnAddChapterClick(Value: TNotifyEvent);
    procedure SetOnCheckClick(Value: TNotifyEvent);
    procedure SetOnDeleteChapterClick(Value: TNotifyEvent);
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
      out ErrorMessage: string; PresentFrame: Boolean = True): Boolean;
    function DecodeNextFrame(Decoder: TFFmpegDecoder; ConvertFrame: Boolean;
      out PositionMs: Integer; out ErrorMessage: string): Boolean;
    function DecodeNextFrameToScratch(Decoder: TFFmpegDecoder;
      out PositionMs: Integer; out ErrorMessage: string): Boolean;
    function CurrentFrameCornersMostlyDark: Boolean;
    function HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean;
    function ShowNextFrame(Decoder: TFFmpegDecoder; out PositionMs: Integer;
      out ErrorMessage: string): Boolean;
    function PresentScratchFrame(out ErrorMessage: string): Boolean;
    procedure Present(Bitmap: TBitmap);
    procedure PresentImmediate(Bitmap: TBitmap);
    procedure SetSeekProgress(PositionMs, MaxMs: Integer);
    property BossMode: Boolean write SetBossMode;
    property CanNavigateNext: Boolean write SetCanNavigateNext;
    property CanNavigatePrevious: Boolean write SetCanNavigatePrevious;
    property CheckEnabled: Boolean write SetCheckEnabled;
    property Chapters: TVideoMinerOverlayChapters write SetChapters;
    property EndActionText: string write SetEndActionText;
    property FullScreen: Boolean write SetFullScreen;
    property OnBossExitClick: TNotifyEvent write SetOnBossExitClick;
    property OnBossGesture: TNotifyEvent write SetOnBossGesture;
    property OnAddChapterClick: TNotifyEvent write SetOnAddChapterClick;
    property OnCheckClick: TNotifyEvent write SetOnCheckClick;
    property OnDeleteChapterClick: TNotifyEvent write SetOnDeleteChapterClick;
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

function TVideoMinerVideoView.CurrentFrameCornersMostlyDark: Boolean;
begin
  Result := (FSurface <> nil) and FSurface.CurrentFrameCornersMostlyDark;
end;

function TVideoMinerVideoView.PrepareBitmapFrameBuffer(Bitmap: TBitmap;
  Width, Height: Integer; out Buffer: Pointer; out BufferStride: Integer): Boolean;
begin
  Buffer := nil;
  BufferStride := 0;
  Result := False;

  if (Bitmap = nil) or (Width <= 0) or (Height <= 0) then
    Exit;

  if Bitmap.PixelFormat <> pf32bit then
    Bitmap.PixelFormat := pf32bit;
  if (Bitmap.Width <> Width) or (Bitmap.Height <> Height) then
    Bitmap.SetSize(Width, Height);

  if Height > 1 then
    BufferStride := Abs(NativeInt(Bitmap.ScanLine[1]) - NativeInt(Bitmap.ScanLine[0]))
  else
    BufferStride := Width * 4;

  Buffer := Bitmap.ScanLine[Height - 1];
  Result := (Buffer <> nil) and (BufferStride > 0);
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

  FDecodeScratch := TBitmap.Create;
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
  FDecodeScratch.Free;
  inherited Destroy;
end;

procedure TVideoMinerVideoView.Clear;
begin
  if FDecodeScratch <> nil then
    FDecodeScratch.SetSize(0, 0);
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

procedure TVideoMinerVideoView.SetOnCheckClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnCheckClick := Value;
end;

procedure TVideoMinerVideoView.SetOnAddChapterClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnAddChapterClick := Value;
end;

procedure TVideoMinerVideoView.SetOnDeleteChapterClick(Value: TNotifyEvent);
begin
  if FSurface <> nil then
    FSurface.OnDeleteChapterClick := Value;
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

procedure TVideoMinerVideoView.SetCheckEnabled(Value: Boolean);
begin
  if FSurface <> nil then
    FSurface.CheckEnabled := Value;
end;

procedure TVideoMinerVideoView.SetChapters(
  const Value: TVideoMinerOverlayChapters);
begin
  if FSurface <> nil then
    FSurface.Chapters := Value;
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
  PositionMs: Integer; out ErrorMessage: string; PresentFrame: Boolean): Boolean;
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

  if PresentFrame then
  begin
    if not PrepareFrameBuffer(Decoder, Buffer, BufferStride, ErrorMessage) then
      Exit;
  end
  else
  begin
    if not PrepareBitmapFrameBuffer(FDecodeScratch, Decoder.Info.Width,
      Decoder.Info.Height, Buffer, BufferStride) then
    begin
      ErrorMessage := 'Failed to prepare scratch frame buffer.';
      Exit;
    end;
  end;

  if not Decoder.DecodeFrameToBgrx32(PositionMs, Buffer, BufferStride,
    ErrorMessage) then
    Exit;

  if PresentFrame then
    PresentImmediate(FSurface.Bitmap);
  if (not PresentFrame) and (FSurface <> nil) then
    FSurface.PresentImmediate;
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

function TVideoMinerVideoView.DecodeNextFrameToScratch(Decoder: TFFmpegDecoder;
  out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  Buffer: Pointer;
  BufferStride: Integer;
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  if Decoder = nil then
  begin
    ErrorMessage := 'Decoder is nil.';
    Exit;
  end;

  if not PrepareBitmapFrameBuffer(FDecodeScratch, Decoder.Info.Width,
    Decoder.Info.Height, Buffer, BufferStride) then
  begin
    ErrorMessage := 'Failed to prepare scratch frame buffer.';
    Exit;
  end;

  Result := Decoder.DecodeNextFrameToBgrx32Optional(Buffer, BufferStride,
    True, PositionMs, ErrorMessage);
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

function TVideoMinerVideoView.PresentScratchFrame(
  out ErrorMessage: string): Boolean;
begin
  ErrorMessage := '';
  Result := False;

  if (FSurface = nil) or (FDecodeScratch = nil) or
     (FDecodeScratch.Width <= 0) or (FDecodeScratch.Height <= 0) then
  begin
    ErrorMessage := 'Scratch frame is empty.';
    Exit;
  end;

  FSurface.Bitmap.Assign(FDecodeScratch);
  Present(FSurface.Bitmap);
  Result := True;
end;

end.
