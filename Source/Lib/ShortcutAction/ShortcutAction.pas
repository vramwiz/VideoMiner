unit ShortcutAction;

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls;

type
  // 反応するイベント種別
  TShortcutEventKind = (sekKeyDown, sekKeyPress);

  // ショートカット全体を実行してよいかを呼び出し側で判定する
  TShortcutActionCanExecuteEvent = function: Boolean of object;
  TShortcutActionProc = procedure of object;

  // ショートカット 1 件分
  TShortcutActionItem = record
    Kind : TShortcutEventKind; // Down / Press
    KeyW : Word;               // KeyDown 用
    KeyC : Char;               // KeyPress 用
    Shift: TShiftState;        // KeyDown 用
    Proc : TShortcutActionProc;
  end;
  PShortcutActionItem = ^TShortcutActionItem;

  // ショートカット管理クラス
  TShortcutAction = class
  private
    FList   : TList;
    FEnable : Boolean;
    // Trueを返した時だけ登録済みショートカットを実行する
    FOnCanExecute: TShortcutActionCanExecuteEvent;

    function GetCount: Integer;
    function GetItem(Index: Integer): TShortcutActionItem;
    // Enabledと外部判定をまとめて確認する
    function CanExecute: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    {------------------------------------
      既存互換：KeyDown 用
    ------------------------------------}
    procedure Add(Key: Word; Shift: TShiftState; AProc: TShortcutActionProc); overload;

    {------------------------------------
      追加：KeyPress 用
    ------------------------------------}
    procedure Add(Key: Char; AProc: TShortcutActionProc); overload;

    {------------------------------------
      発火入口
    ------------------------------------}
    function KeyDown(var Key: Word; Shift: TShiftState): Boolean;
    function ProcessKeyPress(var Key: Char): Boolean;

    {------------------------------------
      管理
    ------------------------------------}
    procedure Clear;

    property Enabled: Boolean read FEnable write FEnable;
    // 編集中など、一時的に全ショートカットを抑止したい時に使う
    property OnCanExecute: TShortcutActionCanExecuteEvent read FOnCanExecute write FOnCanExecute;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TShortcutActionItem read GetItem; default;
  end;

implementation

{ TShortcutAction }

constructor TShortcutAction.Create;
begin
  inherited Create;
  FList := TList.Create;
  FEnable := True; // 初期状態は有効
end;

destructor TShortcutAction.Destroy;
begin
  Clear;
  FList.Free;
  inherited Destroy;
end;

procedure TShortcutAction.Clear;
var
  i: Integer;
begin
  for i := 0 to FList.Count - 1 do
    Dispose(PShortcutActionItem(FList[i]));
  FList.Clear;
end;

function TShortcutAction.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TShortcutAction.GetItem(Index: Integer): TShortcutActionItem;
begin
  Result := PShortcutActionItem(FList[Index])^;
end;

function TShortcutAction.CanExecute: Boolean;
begin
  Result := FEnable;
  if not Result then Exit;
  // 呼び出し側が指定した抑止条件を最後に確認する
  if Assigned(FOnCanExecute) then
    Result := FOnCanExecute();
end;

{------------------------------------
  KeyDown 用登録（既存互換）
------------------------------------}
procedure TShortcutAction.Add(Key: Word; Shift: TShiftState; AProc: TShortcutActionProc);
var
  Item: PShortcutActionItem;
begin
  New(Item);
  Item^.Kind  := sekKeyDown;
  Item^.KeyW  := Key;
  Item^.KeyC  := #0;
  Item^.Shift := Shift;
  Item^.Proc  := AProc;
  FList.Add(Item);
end;

{------------------------------------
  KeyPress 用登録
------------------------------------}
procedure TShortcutAction.Add(Key: Char; AProc: TShortcutActionProc);
var
  Item: PShortcutActionItem;
begin
  New(Item);
  Item^.Kind  := sekKeyPress;
  Item^.KeyW  := 0;
  Item^.KeyC  := Key;
  Item^.Shift := [];
  Item^.Proc  := AProc;
  FList.Add(Item);
end;

{------------------------------------
  KeyDown 発火
------------------------------------}
function TShortcutAction.KeyDown(var Key: Word;  Shift: TShiftState): Boolean;
var
  i   : Integer;
  Item: PShortcutActionItem;
begin
  Result := False;

  if not CanExecute then Exit; // 無効中

  for i := 0 to FList.Count - 1 do
  begin
    Item := PShortcutActionItem(FList[i]);

    if Item^.Kind <> sekKeyDown then Continue; // KeyDown 専用

    if (Item^.KeyW = Key) and (Item^.Shift = Shift) then
    begin
      if Assigned(Item^.Proc) then
        Item^.Proc();

      Key := 0;       // 標準処理抑止
      Result := True;
      Exit;
    end;
  end;
end;

{------------------------------------
  KeyPress 発火
------------------------------------}
function TShortcutAction.ProcessKeyPress(var Key: Char): Boolean;
var
  i   : Integer;
  Item: PShortcutActionItem;
begin
  Result := False;

  if not CanExecute then Exit; // 無効中

  for i := 0 to FList.Count - 1 do
  begin
    Item := PShortcutActionItem(FList[i]);

    if Item^.Kind <> sekKeyPress then Continue; // KeyPress 専用

    if Item^.KeyC = Key then
    begin
      if Assigned(Item^.Proc) then
        Item^.Proc();

      Key := #0;      // 文字入力抑止
      Result := True;
      Exit;
    end;
  end;
end;

end.

