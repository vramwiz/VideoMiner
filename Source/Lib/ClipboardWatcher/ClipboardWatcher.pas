unit ClipboardWatcher;

{
  Unit Name   : ClipboardWatcher
  Description : クリップボードの変更を監視し、テキスト・ビットマップ・PNG 形式の取得と通知を行うユニットです。
                WM_CLIPBOARDUPDATE メッセージを使用し、ポーリング不要で効率よく監視します。
                OnChange イベントにより、取得成功したデータ形式の一覧が通知されます。

  Features    :
    - クリップボードの変化を自動検出（WM_CLIPBOARDUPDATE 使用）
    - テキスト・BMP・PNG 形式のデータを自動取得
    - PNG 形式は RegisterClipboardFormat により独自に対応
    - 複数イベントを連続で受けた際のデバウンス処理あり
    - データ取得後、OnChange イベントで通知

  Usage       :
    - TClipboardWatcher.Create でインスタンス生成
    - Enabled := True で監視を開始、False で停止
    - OnChange イベントを設定し、データ取得後の処理を記述
    - Text / Bitmap / Png プロパティから取得内容にアクセス可能

  Dependencies:
    - Windows, VCL.Forms, ActiveX, VCL.Clipbrd, pngimage

  Notes       :
    - GetClipboardText/GetClipboardBitmap/GetClipboardPng の順にデータ取得を試行
    - PNG は Windows 標準ではないため、CF_PNG フォーマットを手動登録
    - OpenClipboard には排他制御のため SafeOpenClipboard を使用
    - 外部アプリが大量に書き込む場合、同一内容の連続イベントを除去可能

  クリップボードの内容を直接取得・設定するグローバル関数が用意されています。
  `TClipboardWatcher` を使用せずに、任意のタイミングで利用可能です。

  Author      : vramwiz
  Created     : 2025-07-10
  Updated     : 2025-07-25
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,System.DateUtils,Vcl.Imaging.pngimage,ExtCtrls;


const
  WM_CLIPBOARDUPDATE = $031D;
  CLIPBOARD_DEBOUNCE_MS = 500;

type
  TClipboardWatcherDataType = (cdtNone, cdtText, cdtBitmap, cdtPng);
  TClipboardWatcherDataTypes = set of TClipboardWatcherDataType;

  TClipboardWatcherChangeEvent = procedure(Sender: TObject; const DataTypes: TClipboardWatcherDataTypes) of object;

  // クリップボード監視クラス
type
  TClipboardWatcher = class(TPersistent)
  private
    FWindowHandle  : HWND;
    FTimerAgent    : TTimer;                      // 処理タイマー
    FTimerTimeout  : TTimer;                      // データの終わりを待つタイマー
    FLastTime      : TDateTime;                   // 最後に取得した時間 ※同一データ取得防止
    FEnabled       : Boolean;                     // True:変更でイベントを発生させる
    FDataTypes     : TClipboardWatcherDataTypes;  // 取得出来たデータの種類
    FPng           : TPngImage;
    FBitmap        : TBitmap;
    FText          : string;
    FOnChange      : TClipboardWatcherChangeEvent;

    function GetClipboard() : Boolean;

    procedure WndProc(var Msg: TMessage);
    procedure ClipboardExecute();
    procedure OnTimerAgent(Sender: TObject);
    procedure OnTimerTimeOut(Sender: TObject);
    function GetDelayMS: Integer;
    procedure SetDelayMS(const Value: Integer);
  protected
    procedure DoChange(const DataTypes: TClipboardWatcherDataTypes);
  public
    constructor Create;
    destructor Destroy; override;
    // True : クリップボード監視 False：監視を中断
    property Enabled : Boolean read FEnabled write FEnabled;
    property Text    : string    read FText;
    property Bitmap  : TBitmap   read FBitmap;
    property Png     : TPngImage read FPng;
    // 最後のデータからイベント発生まで待機する時間
    property DelayMS : Integer   read GetDelayMS write SetDelayMS;
    // クリップボード変更イベント
    property OnChange : TClipboardWatcherChangeEvent read FOnChange write FOnChange;

  end;

// 指定されたテキストをクリップボードにコピー
procedure SetClipboardText(const Text: string);
// 指定されたビットマップをクリップボードにコピー
procedure SetClipboardBitmap(Bmp: TBitmap);
// 指定されたPNGをクリップボードにコピー
procedure SetClipboardPng(Png: TPngImage);
// クリップボードからビットマップ取得
function GetClipboardBitmap(Bitmap : TBitmap) : Boolean;
// クリップボードからPng画像取得
function GetClipboardPng(Png : TPngImage) : Boolean;
// クリップボードからテキスト取得
function GetClipboardText(var Text : string) : Boolean;


implementation

uses
  Vcl.Clipbrd,Winapi.ActiveX;

    // PNG用クリップボード形式登録
var
  ClipboardUpdateIsSelf : Boolean;

//  クリップボードを安全に開く
function SafeOpenClipboard(hWnd: HWND = 0; Retry: Integer = 10; DelayMS: Integer = 50): Boolean;
var
  i: Integer;
begin
  for i := 1 to Retry do
  begin
    if OpenClipboard(hWnd) then
      Exit(True);
    Sleep(DelayMS);
  end;
  Result := False;
end;



constructor TClipboardWatcher.Create;
begin
  inherited;
  FLastTime := 0;
  FWindowHandle := AllocateHWnd(WndProc);
  AddClipboardFormatListener(FWindowHandle);

  FBitmap := TBitmap.Create;
  FPng    := TPngImage.Create;

  FTimerAgent := TTimer.Create(nil);
  FTimerAgent.Enabled := False;
  FTimerAgent.Interval := 10;
  FTimerAgent.OnTimer := OnTimerAgent;

  FTimerTimeout := TTimer.Create(nil);
  FTimerTimeout.Enabled := False;
  FTimerTimeout.Interval := 100;
  FTimerTimeout.OnTimer := OnTimerTimeOut;

end;

destructor TClipboardWatcher.Destroy;
begin
  FTimerTimeout.Free;
  FTimerAgent.Free;
  FPng.Free;
  FBitmap.Free;
  RemoveClipboardFormatListener(FWindowHandle);
  DeallocateHWnd(FWindowHandle);
  inherited;
end;

procedure TClipboardWatcher.DoChange(
  const DataTypes: TClipboardWatcherDataTypes);
begin
  if Assigned(FOnChange) then FOnChange(Self,DataTypes);
end;

function GetClipboardBitmapSub(Bitmap  : TBitmap): Boolean;
var
  hBmp: HBITMAP;
begin
  result := False;

  if not IsClipboardFormatAvailable(CF_BITMAP) then Exit;

  hBmp := GetClipboardData(CF_BITMAP);
  if hBmp = 0 then Exit;

  hBmp := CopyImage(hBmp, IMAGE_BITMAP, 0, 0, LR_COPYRETURNORG or LR_COPYDELETEORG);
  if hBmp = 0 then Exit;

  Bitmap.Handle := 0;
  Bitmap.Handle := hBmp;
  result := True;
end;

function GetClipboardPngSub(Png     : TPngImage): Boolean;
var
  hData: THandle;
  pData: Pointer;
  Size: Integer;
  Stream: TMemoryStream;
  CF_PNG: UINT;
begin
  Result := False;
  CF_PNG := RegisterClipboardFormat('PNG');

  // WindowsでPNG形式のクリップボードフォーマットを取得（レジスタされていない場合は0）
  if CF_PNG = 0 then
    Exit;

  if not IsClipboardFormatAvailable(CF_PNG) then Exit;

  hData := GetClipboardData(CF_PNG);
  if hData = 0 then Exit;

  pData := GlobalLock(hData);
  if not Assigned(pData) then Exit;

  try
    Size := GlobalSize(hData);
    if Size = 0 then Exit;

    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(pData^, Size);
      Stream.Position := 0;
      Png.LoadFromStream(Stream);
      Result := True;
    finally
      Stream.Free;
    end;
  finally
    GlobalUnlock(hData);
  end;
end;

function GetClipboardTextSub(var Text    : string): Boolean;
var
  hData: THandle;
  pData: PChar;
begin
  Result := False;
  Text := '';

  if not IsClipboardFormatAvailable(CF_UNICODETEXT) then Exit;

  hData := GetClipboardData(CF_UNICODETEXT);
  if hData = 0 then Exit;

  pData := GlobalLock(hData);
  if not Assigned(pData) then Exit;

  try
    Text := pData;
    Result := True;
  finally
    GlobalUnlock(hData);
  end;
end;

function TClipboardWatcher.GetClipboard() : Boolean;
var
  CF_PNG: UINT;
begin
  CF_PNG := RegisterClipboardFormat('PNG');

  result := False;
  if IsClipboardFormatAvailable(CF_BITMAP) then begin
    if not (cdtBitmap in FDataTypes) then begin
      if GetClipboardBitmapSub(FBitmap) then begin
        FDataTypes := FDataTypes + [cdtBitmap];
        result := True;
      end;
    end;
  end;
  if IsClipboardFormatAvailable(CF_PNG) then begin
    if not (cdtPng in FDataTypes) then begin
      if GetClipboardPngSub(FPng) then begin
        FDataTypes := FDataTypes + [cdtPng];
        result := True;
      end;
    end;
  end;
  if IsClipboardFormatAvailable(CF_UNICODETEXT) then begin
    if not (cdtText in FDataTypes) then begin
      if GetClipboardTextSub(FText) then begin
        FDataTypes := FDataTypes + [cdtText];
        result := True;
      end;
    end;
  end;
end;

procedure TClipboardWatcher.OnTimerAgent(Sender: TObject);
begin
  FTimerAgent.Enabled := False;
  if SafeOpenClipboard(0) then
  begin
    try
      if GetClipboard() then
      begin
        FTimerTimeout.Enabled := False;
        FTimerTimeout.Enabled := True;
      end;
    finally
      CloseClipboard;
    end;
  end;
  FTimerAgent.Enabled := True;
end;

procedure TClipboardWatcher.OnTimerTimeOut(Sender: TObject);
begin
  FTimerAgent.Enabled := False;
  FTimerTimeout.Enabled := False;
  try
    DoChange(FDataTypes);
  finally
    FDataTypes := [];
  end;
end;

procedure TClipboardWatcher.ClipboardExecute;
begin
  if MilliSecondsBetween(Now, FLastTime) >= CLIPBOARD_DEBOUNCE_MS then begin
    FLastTime := Now;
    if not ClipboardUpdateIsSelf then
    if FEnabled then begin
      FTimerAgent.Enabled := False;
      FTimerAgent.Enabled := True;
      FTimerTimeout.Enabled := False;
      FTimerTimeout.Enabled := True;
    end;
    //if FEnabled then DoClipboardChanged();
    ClipboardUpdateIsSelf := False;
  end;
end;

function TClipboardWatcher.GetDelayMS: Integer;
begin
  result := FTimerTimeout.Interval;
end;

procedure TClipboardWatcher.SetDelayMS(const Value: Integer);
begin
  FTimerTimeout.Interval := Value;
end;


procedure TClipboardWatcher.WndProc(var Msg: TMessage);
begin
  if Msg.Msg = WM_CLIPBOARDUPDATE then begin
    ClipboardExecute();
  end;

  Msg.Result := DefWindowProc(FWindowHandle, Msg.Msg, Msg.WParam, Msg.LParam);
end;


function BuildClipboardDIB(bmp: TBitmap): HGLOBAL;
var
  rowSize, dibSize: Integer;
  tmp: TBitmap;
  hDIB: HGLOBAL;
  pDIB, pBits, srcLine, dest: PByte;
  x, y: Integer;
  bih: BITMAPINFOHEADER;
begin
  Result := 0;
  if not Assigned(bmp) then Exit;

  tmp := TBitmap.Create;
  try
    tmp.PixelFormat := pf32bit;
    tmp.Width := bmp.Width;
    tmp.Height := bmp.Height;
    tmp.Canvas.Draw(0, 0, bmp);

    rowSize := ((tmp.Width * 3 + 3) div 4) * 4;
    dibSize := SizeOf(BITMAPINFOHEADER) + rowSize * tmp.Height;

    hDIB := GlobalAlloc(GMEM_MOVEABLE, dibSize);
    if hDIB = 0 then Exit;

    pDIB := GlobalLock(hDIB);
    if not Assigned(pDIB) then
    begin
      GlobalFree(hDIB);
      Exit;
    end;

    try
      FillChar(bih, SizeOf(bih), 0);
      bih.biSize := SizeOf(bih);
      bih.biWidth := tmp.Width;
      bih.biHeight := -tmp.Height; // ← 上向きにするのが超重要！
      bih.biPlanes := 1;
      bih.biBitCount := 24;
      bih.biCompression := BI_RGB;
      bih.biSizeImage := rowSize * tmp.Height;

      Move(bih, pDIB^, SizeOf(bih));
      pBits := pDIB + SizeOf(bih);

      for y := 0 to tmp.Height - 1 do
      begin
        srcLine := tmp.ScanLine[y];
        dest := pBits;
        for x := 0 to tmp.Width - 1 do
        begin
          dest^ := srcLine^;      Inc(dest); Inc(srcLine); // B
          dest^ := srcLine^;      Inc(dest); Inc(srcLine); // G
          dest^ := srcLine^;      Inc(dest); Inc(srcLine); // R
          Inc(srcLine); // skip alpha
        end;
        Inc(pBits, rowSize);
      end;

    finally
      GlobalUnlock(hDIB);
    end;

    Result := hDIB;

  finally
    tmp.Free;
  end;
end;

function BuildClipboardPNG(png: TPngImage): HGLOBAL;
var
  stream: TMemoryStream;
  hPNG: HGLOBAL;
  ptr: Pointer;
begin
  Result := 0;

  if not Assigned(png) then Exit;

  stream := TMemoryStream.Create;
  try
    png.SaveToStream(stream);
    stream.Position := 0;

    hPNG := GlobalAlloc(GMEM_MOVEABLE, stream.Size);
    if hPNG = 0 then Exit;

    ptr := GlobalLock(hPNG);
    if not Assigned(ptr) then
    begin
      GlobalFree(hPNG);
      Exit;
    end;

    try
      Move(stream.Memory^, ptr^, stream.Size);
    finally
      GlobalUnlock(hPNG);
    end;

    Result := hPNG;

  finally
    stream.Free;
  end;
end;

function BuildClipboardBitmap(bmp: TBitmap): HBITMAP;
begin
  Result := 0;
  if not Assigned(bmp) then Exit;

  // CopyImage により HBITMAP を複製
  Result := CopyImage(bmp.Handle, IMAGE_BITMAP, 0, 0,
                      LR_COPYRETURNORG or LR_COPYDELETEORG);
end;

procedure SetClipboardText(const Text: string);
begin
  ClipboardUpdateIsSelf := True;
  Clipboard.Open;
  try
    Clipboard.Clear;
    Clipboard.AsText := Text;
  finally
    Clipboard.Close;
  end;
end;

procedure SetClipboardBitmap(Bmp: TBitmap);
const
  CF_PNG_NAME = 'PNG';
var
  //CF_PNG: UINT;
  hBmp: HBITMAP;
  //hDIB: HGLOBAL;
//  hPNG: HGLOBAL;
//  png: TPngImage;
begin
  if not Assigned(Bmp) then Exit;

  //CF_PNG := RegisterClipboardFormat(CF_PNG_NAME);
  ClipboardUpdateIsSelf := True;

  // --- データ生成 ---
  hBmp := BuildClipboardBitmap(Bmp);
  //hDIB := BuildClipboardDIB(Bmp);
  {
  // PNGは一度 TBitmap → TPngImage へ変換してから保存
  png := TPngImage.Create;
  try
    png.Assign(Bmp);
    hPNG := BuildClipboardPNG(png);
  finally
    png.Free;
  end;
  }
  // --- クリップボードに登録 ---
  if OpenClipboard(0) then
  try
    EmptyClipboard;
    if hBmp <> 0 then SetClipboardData(CF_BITMAP, hBmp);
    //if hDIB <> 0 then SetClipboardData(CF_DIB, hDIB);
   // if hPNG <> 0 then SetClipboardData(CF_PNG, hPNG);
  finally
    CloseClipboard;
  end;
end;

procedure SetClipboardPng(Png: TPngImage);
const
  CF_PNG_NAME = 'PNG';
var
  CF_PNG: UINT;
  hBmp: HBITMAP;
  hDIB: HGLOBAL;
  hPNG: HGLOBAL;
  bmp: TBitmap;
begin
  if not Assigned(Png) then Exit;

  CF_PNG := RegisterClipboardFormat(CF_PNG_NAME);
  ClipboardUpdateIsSelf := True;

  // --- TPngImage → TBitmap に変換 ---
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.Width := Png.Width;
    bmp.Height := Png.Height;
    bmp.Canvas.Draw(0, 0, Png);

    // --- 各フォーマットのビルド ---
    hBmp := BuildClipboardBitmap(bmp);
    hDIB := BuildClipboardDIB(bmp);
  finally
    bmp.Free;
  end;

  // --- PNG はそのまま保存可能 ---
  hPNG := BuildClipboardPNG(Png);

  // --- クリップボードに登録 ---
  if OpenClipboard(0) then
  try
    EmptyClipboard;
    if hBmp <> 0 then SetClipboardData(CF_BITMAP, hBmp);
    if hDIB <> 0 then SetClipboardData(CF_DIB, hDIB);
    if hPNG <> 0 then SetClipboardData(CF_PNG, hPNG);
  finally
    CloseClipboard;
  end;
end;

// クリップボードからビットマップ取得
function GetClipboardBitmap(Bitmap : TBitmap) : Boolean;
begin
  Result := False;
  if not SafeOpenClipboard(0) then exit;
  try
    Result := GetClipboardBitmapSub(Bitmap);
  finally
    CloseClipboard;
  end;
end;
// クリップボードからPng画像取得
function GetClipboardPng(Png : TPngImage) : Boolean;
begin
  Result := False;
  if not SafeOpenClipboard(0) then exit;
  try
    Result := GetClipboardPngSub(Png);
  finally
    CloseClipboard;
  end;
end;
// クリップボードからテキスト取得
function GetClipboardText(var Text : string) : Boolean;
begin
  Result := False;
  if not SafeOpenClipboard(0) then exit;
  try
    Result := GetClipboardTextSub(Text);
  finally
    CloseClipboard;
  end;
end;



end.
