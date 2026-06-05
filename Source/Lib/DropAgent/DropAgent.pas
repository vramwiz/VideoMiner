unit DropAgent;

{
  Unit Name:
    DropFileHandler

  Description:
    本ユニットは、Delphiアプリケーションでファイルのドラッグ＆ドロップ
    （HDROP形式）を受け取るための基本的な処理を提供します。
    エクスプローラーや対応する外部アプリケーションからファイルをドロップした際に
    そのファイルパスを取得し、処理に渡すことが可能です。

  対応形式:
    ・Windows Shell による HDROP（ファイルパスを渡す形式）に対応。
    ・画像データ（CF_BITMAP, CF_DIBなど）のような実バイナリデータのドロップには対応していません。

  使い方：
  　ドロップ先のクラスをAttachで指定
    ※DelphiVCLの仕様によりフォームのみ対応
    AcceptKindsで受け入れる形式を指定
    OnDropText :テキストがドロップされると発火、タグを除去した後のテキストを取得
    OnDropHtml ：装飾付きテキストがドロップされると発火、タグ付きのテキストを取得
    OnDropFiles：ファイルがドロップされると発火、ファイルリストを取得

  備考:
    ・DragAcceptFiles、WM_DROPFILES を使用。
    ・DragQueryFile によりファイル名一覧を取得。
    ・cfFormat が 15（CF_LOCALE）などのケースは、HDROP 以外のドラッグ形式であるため無視されます。

  注意点:
    ・一部の古いアプリケーションまたは特殊なドラッグ元からのデータは受信できない可能性があります。
    ・画像やテキストをファイルとしてではなく「実データ」としてドロップする形式には非対応です。

  更新履歴:
    2025-09-29 初版作成
    2025-09-30 HTML関係の処理を正しく行えるように修正

  作者:
    VRAMの魔術師
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, ActiveX, ShlObj,Vcl.StdCtrls,Vcl.ExtCtrls,  Winapi.ShellAPI;

type
  // ドロップ可能な形式の列挙
  TDropAcceptKind = (dakFiles, dakText, dakHtml, dakVirtualFiles);
  TDropAcceptKinds = set of TDropAcceptKind;

  // テキストがドロップされたときのイベント
  TDropTextEvent = procedure(Sender: TObject; Control: TWinControl; const Text: string) of object;

  // ファイルがドロップされたときのイベント
  TDropFilesEvent = procedure(Sender: TObject; Control: TWinControl; const FileNames: TArray<string>) of object;

  // ドロップ受け入れクラス（テキスト・ファイル両対応）
  TDropAgent = class(TInterfacedObject, IDropTarget)
  private
    FControl     : TWinControl;                     // ドロップ対象コントロール
    FAcceptKinds : TDropAcceptKinds;                // 受け入れるドロップ形式（テキスト・ファイル等）
    FOnDropText  : TDropTextEvent;                  // テキストドロップ時のイベントハンドラ
    FOnDropHtml  : TDropTextEvent;                  // Htmlドロップ時のイベントハンドラ
    FOnDropFiles : TDropFilesEvent;                 // ファイルドロップ時のイベントハンドラ
    FDataObj     : IDataObject;                     // ドラッグされようとしているオブジェクト
    // デバッグ用ログ出力（DEBUG時のみ）
    // HTML Clipboard Format（MS仕様）のテキストを普通のテキスト形式に変換
    function ExtractHtmlFragment(const HtmlData: string): string;
    function StripHtmlTags(const HtmlText: string): string;
     // 指定フォーマットが含まれているか
    function HasFormat(DataObj: IDataObject; Format: TClipFormat): Boolean;
    // テキストデータを取得
    function GetDataObjToText(DataObj: IDataObject; out Text: string): Boolean;
    // Html データを取得
    function GetDataObjToHtml(DataObj: IDataObject;out Html: string): Boolean;
    // CF_HTML フォーマットのヘッダ部分に含まれる情報からオフセット値（整数）を抽出する。
    function ParseStartHtmlOffset(const RawBytes: TBytes): Integer;
    function ParseEndHtmlOffset(const RawBytes: TBytes): Integer;
    function ExtractHtmlOffset(const RawBytes: TBytes; const Tag: string): Integer;
    // ファイル一覧を取得
    function GetDataObjToFiles(DataObj: IDataObject; out Files: TArray<string>): Boolean;
    function GetDropEffect(const dataObj: IDataObject): DWORD;
  protected
    // COM参照カウントを無効化（DelphiがCOM管理しないようにする）
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;

    // IDropTarget 実装部
    // ドラッグがコントロールに入ったとき
    function DragEnter(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    // ドラッグ中（マウス移動時）
    function DragOver(grfKeyState: Longint; pt: TPoint;
      var dwEffect: Longint): HResult; stdcall;
     // ドラッグがコントロールから離れたとき
    function DragLeave: HResult; stdcall;
    // ドロップされたとき
    function Drop(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;

    procedure DoDropText(Control: TWinControl; const Text: string); virtual;
    procedure DoDropHtml(Control: TWinControl; const Html: string); virtual;
    procedure DoDropFiles(Control: TWinControl; const Files: TArray<string>); virtual;
  public
    // 初期化（AcceptKindsの初期設定）
    constructor Create;
    // 終了処理（Detach実行）
    destructor Destroy; override;
    // コントロールへのD&D登録
    procedure Attach(Control: TWinControl);
    // D&D登録解除
    procedure Detach;

    // 現在の対象コントロール
    property Control: TWinControl read FControl;
    // 受け入れ形式セット
    property AcceptKinds: TDropAcceptKinds read FAcceptKinds write FAcceptKinds;
    // テキスト受信イベント
    property OnDropText: TDropTextEvent read FOnDropText write FOnDropText;
    // Html受信イベント
    property OnDropHtml: TDropTextEvent read FOnDropHtml write FOnDropHtml;
    // ファイル受信イベント
    property OnDropFiles: TDropFilesEvent read FOnDropFiles write FOnDropFiles;
  end;

implementation

uses System.RegularExpressions,Math;

{ TDropAgent }

constructor TDropAgent.Create;
begin
  inherited Create;
  FAcceptKinds := [dakText, dakFiles]; // デフォルトは両方受け入れる
end;



destructor TDropAgent.Destroy;
begin
  Detach;
  inherited;
end;

procedure TDropAgent.Attach(Control: TWinControl);
begin
  if not Assigned(Control) or (FControl = Control) then Exit;

  FControl := Control;
  RegisterDragDrop(FControl.Handle, Self);
end;

procedure TDropAgent.Detach;
begin
  if Assigned(FControl) then
  begin
    try
      RevokeDragDrop(FControl.Handle);
    except
      // フォーム破棄時に HWND が死んでいることがあるので無視
    end;
    FControl := nil;
  end;
end;

procedure TDropAgent.DoDropText(Control: TWinControl; const Text: string);
begin
  if Assigned(FOnDropText) then
    FOnDropText(Self, Control, Text);
end;

procedure TDropAgent.DoDropHtml(Control: TWinControl; const Html: string);
begin
  if Assigned(FOnDropHtml) then
    FOnDropHtml(Self, Control, Html);
end;

procedure TDropAgent.DoDropFiles(Control: TWinControl; const Files: TArray<string>);
begin
  if Assigned(FOnDropFiles) then
    FOnDropFiles(Self, Control, Files);
end;
//begin
//  {$IFDEF DEBUG}
//end;

function TDropAgent.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TDropAgent.StripHtmlTags(const HtmlText: string): string;
begin
  // 正規表現でタグを除去
  Result := TRegEx.Replace(HtmlText, '<[^>]+>', '');
end;

function TDropAgent._AddRef: Integer;
begin
  Result := -1; // 参照カウント無効
end;

function TDropAgent._Release: Integer;
begin
  Result := -1; // 参照カウント無効
end;

function TDropAgent.DragEnter(const dataObj: IDataObject;
  grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult;
begin
  FDataObj := dataObj;
  dwEffect := GetDropEffect(dataObj);
  Result := S_OK;
end;

function TDropAgent.DragOver(grfKeyState: Longint; pt: TPoint;
  var dwEffect: Longint): HResult;
begin
  dwEffect := GetDropEffect(FDataObj); // FDataObj は DragEnter で保存済み
  Result := S_OK;
end;

function TDropAgent.DragLeave: HResult;
begin
  Result := S_OK;
end;

function TDropAgent.Drop(const dataObj: IDataObject;
  grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult;
var
  Text,s: string;
  Files: TArray<string>;
begin
  dwEffect := DROPEFFECT_NONE;

  if (dakText in FAcceptKinds)  then
    if GetDataObjToText(dataObj, Text) then
    begin
      DoDropText(FControl, Text);
      dwEffect := DROPEFFECT_COPY;
    end;

    if GetDataObjToHtml(DataObj, Text) then
    begin
      s := Text;
      s := ExtractHtmlFragment(s);
      DoDropHtml(FControl, s);
      s := StripHtmlTags(s);
      DoDropText(FControl, s);
      dwEffect := DROPEFFECT_COPY;
    end;

  if (dakFiles in FAcceptKinds)  then
    if GetDataObjToFiles(dataObj, Files) then
    begin
      DoDropFiles(FControl, Files);
      dwEffect := DROPEFFECT_COPY;
    end;

  Result := S_OK;
end;

function TDropAgent.ExtractHtmlFragment(const HtmlData: string): string;
var
  StartPos, EndPos: Integer;
  StartTag, EndTag: string;
begin
  StartTag := '<!--StartFragment-->';
  EndTag := '<!--EndFragment-->';

  StartPos := Pos(StartTag, HtmlData);
  EndPos := Pos(EndTag, HtmlData);

  if (StartPos > 0) and (EndPos > StartPos) then
  begin
    Inc(StartPos, Length(StartTag));
    Result := Copy(HtmlData, StartPos, EndPos - StartPos);
  end
  else
    Result := '';
end;

function TDropAgent.ExtractHtmlOffset(const RawBytes: TBytes; const Tag: string): Integer;
var
  Text: string;
  TagPos, ValueStart, ValueEnd: Integer;
  OffsetStr: string;
begin
  Result := -1; // 失敗時

  // ANSI系のヘッダなので CP_ACP など ANSI系で読んで問題ない
  Text := TEncoding.Default.GetString(RawBytes);

  TagPos := Pos(Tag, Text);
  if TagPos > 0 then
  begin
    ValueStart := TagPos + Length(Tag);
    ValueEnd := ValueStart;

    // 数字部分だけ取り出す
    while (ValueEnd <= Length(Text)) and CharInSet(Text[ValueEnd], ['0'..'9']) do
      Inc(ValueEnd);

    OffsetStr := Copy(Text, ValueStart, ValueEnd - ValueStart);
    if TryStrToInt(OffsetStr, Result) then
      Exit;
  end;
end;

function TDropAgent.GetDataObjToText(DataObj: IDataObject;
  out Text: string): Boolean;
var
  FormatEtc: TFormatEtc;
  Medium: TStgMedium;
  P: PChar;
begin
  Result := False;
  Text := '';
  FillChar(FormatEtc, SizeOf(FormatEtc), 0);
  FormatEtc.cfFormat := CF_UNICODETEXT;
  FormatEtc.tymed := TYMED_HGLOBAL;
  FormatEtc.dwAspect := DVASPECT_CONTENT;

  if DataObj.GetData(FormatEtc, Medium) = S_OK then
  try
    P := GlobalLock(Medium.hGlobal);
    if Assigned(P) then
    begin
      Text := P;
      Result := True;
    end;
  finally
    GlobalUnlock(Medium.hGlobal);
    ReleaseStgMedium(Medium);
  end;
end;

function TDropAgent.GetDataObjToHtml(DataObj: IDataObject;
  out Html: string): Boolean;
const
  CF_HTML: string = 'HTML Format';
var
  FormatEtc: TFormatEtc;
  Medium: TStgMedium;
  CF_HTML_ID: UINT;
  DataHandle: HGLOBAL;
  Src: PAnsiChar;
  DataSize: Integer;
  RawBytes, HtmlBytes: TBytes;
  HeaderText: string;
  StartOffset, EndOffset: Integer;
begin
  Result := False;
  Html := '';

  CF_HTML_ID := RegisterClipboardFormat(PChar(CF_HTML));
  if CF_HTML_ID = 0 then Exit;

  ZeroMemory(@FormatEtc, SizeOf(FormatEtc));
  FormatEtc.cfFormat := CF_HTML_ID;
  FormatEtc.tymed := TYMED_HGLOBAL;
  FormatEtc.dwAspect := DVASPECT_CONTENT;
  FormatEtc.lindex := -1;

  if DataObj.GetData(FormatEtc, Medium) <> S_OK then Exit;

  try
    DataHandle := Medium.hGlobal;
    if DataHandle = 0 then Exit;

    DataSize := GlobalSize(DataHandle);
    if DataSize = 0 then Exit;

    Src := GlobalLock(DataHandle);
    if Src = nil then Exit;

    try
      // 1. 全体をバイト列としてコピー
      SetLength(RawBytes, DataSize);
      Move(Src^, RawBytes[0], DataSize);

      // 2. ヘッダーは TEncoding.Default で読み取って解析
      HeaderText := TEncoding.Default.GetString(RawBytes);

      StartOffset := ParseStartHtmlOffset(RawBytes);
      EndOffset   := ParseEndHtmlOffset(RawBytes);

      if (StartOffset < 0) or (EndOffset > DataSize) or (StartOffset >= EndOffset) then Exit;

      // 3. バイト列で HTML 本体を抽出
      HtmlBytes := Copy(RawBytes, StartOffset, EndOffset - StartOffset);

      // 4. UTF-8 でデコード（ここが今回の焦点）
      Html := TEncoding.UTF8.GetString(HtmlBytes);

      Result := True;
    finally
      GlobalUnlock(DataHandle);
    end;
  finally
    ReleaseStgMedium(Medium);
  end;
end;




function TDropAgent.GetDropEffect(const dataObj: IDataObject): DWORD;
begin
  if (dakFiles in FAcceptKinds) and HasFormat(dataObj, CF_HDROP) then
    Result := DROPEFFECT_COPY
  else if (dakText in FAcceptKinds) and HasFormat(dataObj, CF_UNICODETEXT) then
    Result := DROPEFFECT_COPY
  else
    Result := DROPEFFECT_NONE;
end;

function TDropAgent.GetDataObjToFiles(DataObj: IDataObject;
  out Files: TArray<string>): Boolean;
var
  FormatEtc: TFormatEtc;
  Medium: TStgMedium;
  DropHandle: HDROP;
  Count, I: Integer;
  Buffer: array[0..MAX_PATH] of Char;
begin
  Result := False;
  Files := [];
  FillChar(FormatEtc, SizeOf(FormatEtc), 0);
  FormatEtc.cfFormat := CF_HDROP;
  FormatEtc.tymed := TYMED_HGLOBAL;
  FormatEtc.dwAspect := DVASPECT_CONTENT;

  if DataObj.GetData(FormatEtc, Medium) = S_OK then
  try
    DropHandle := HDROP(Medium.hGlobal);
    Count := DragQueryFile(DropHandle, $FFFFFFFF, nil, 0);
    SetLength(Files, Count);
    for I := 0 to Count - 1 do
    begin
      DragQueryFile(DropHandle, I, Buffer, MAX_PATH);
      Files[I] := Buffer;
    end;
    Result := Count > 0;
  finally
    ReleaseStgMedium(Medium);
  end;
end;



function TDropAgent.HasFormat(DataObj: IDataObject;
  Format: TClipFormat): Boolean;
var
  FormatEtc: TFormatEtc;
begin
  FillChar(FormatEtc, SizeOf(FormatEtc), 0);
  FormatEtc.cfFormat := Format;
  FormatEtc.tymed := TYMED_HGLOBAL;
  FormatEtc.dwAspect := DVASPECT_CONTENT;
  Result := DataObj.QueryGetData(FormatEtc) = S_OK;
end;


function TDropAgent.ParseEndHtmlOffset(const RawBytes: TBytes): Integer;
begin
  Result := ExtractHtmlOffset(RawBytes, 'EndHTML:');
end;

function TDropAgent.ParseStartHtmlOffset(const RawBytes: TBytes): Integer;
begin
  Result := ExtractHtmlOffset(RawBytes, 'StartHTML:');
end;

end.
