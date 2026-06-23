unit VideoMinerBossOverlay;

// ボスが来たモード中に動画を隠すための偽装ヘルプ画面描画を担当する。
// VSCode 風の静的な画面に VideoMiner の操作方法を表示し、簡易ヘルプとしても使う。
// マウスジェスチャー検出や再生停止などの状態制御は、このユニットへ持ち込まない。

interface

uses
  System.Types, Vcl.Graphics;

// ボスが来たモード中に切り替えられるヘルプページ数を返す
function VideoMinerBossHelpPageCount: Integer;

// 動画面全体へ偽装ヘルプ画面を描き、解除ボタンの矩形を返す
procedure DrawVideoMinerBossOverlay(Canvas: TCanvas; const Bounds: TRect;
  PageIndex: Integer; out ExitButtonRect: TRect);

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows;

type
  TBossHelpPage = record
    TabName    : string;                 // 上部タブに表示するファイル名
    HeaderText : string;                 // 右上に置く状態表示風テキスト
    StartLine  : Integer;                // ヘルプ本文の開始行番号
    Lines      : array[0..17] of string; // エディタ本文として描く操作説明
    StatusText : string;                 // 下側ステータスバーの左側テキスト
  end;

const
  COLOR_ACTIVITY      = $0023221F; // 左端アクティビティバー
  COLOR_SIDEBAR       = $002A2926; // ファイルツリー背景
  COLOR_EDITOR        = $001F1E1B; // エディタ背景
  COLOR_TAB           = $002C2B28; // 選択タブ/選択行背景
  COLOR_STATUS        = $00A5642A; // ステータスバー背景
  COLOR_TEXT          = $00D6D0C4; // 通常文字
  COLOR_DIM_TEXT      = $009A9388; // 補助文字
  COLOR_LINE_NO       = $007A746B; // 行番号
  COLOR_BUTTON        = $00413B34; // Return ボタン背景
  COLOR_BUTTON_BORDER = $00665D52; // Return ボタン枠線

  HELP_PAGES: array[0..3] of TBossHelpPage = ( // VSCode 風画面に表示するヘルプページ
    (
      TabName: 'basic-shortcuts.md';
      HeaderText: 'Help  Basic controls';
      StartLine: 1;
      Lines: (
        '# Basic controls',
        '',
        '| Ctrl+O | Open a video file |',
        '| Space | Play / stop |',
        '| Left / Right | Previous / next video |',
        '| PageUp / PageDown | Previous / next video |',
        '| Ctrl+Left / Ctrl+Right | Previous / next chapter |',
        '| Home / End | First / last frame area |',
        '| R | Rotate display 90 degrees |',
        '| S | Playback speed 1.0x / 1.5x / 2.0x |',
        '| Up / Down | Volume |',
        '| M | Mute |',
        '| F1 / F11 | Help screen / full screen |',
        '| Esc | Exit full screen or boss mode |',
        '',
        'Mouse:',
        '- Click: play / stop, double click: full screen',
        '- Wheel: zoom, drag while zoomed: pan');
      StatusText: 'help/basic  Ln 1, Col 1  Markdown  UTF-8'
    ),
    (
      TabName: 'review-tools.md';
      HeaderText: 'Help  Review tools';
      StartLine: 21;
      Lines: (
        '# Review and inspection',
        '',
        '| Ctrl+C | Copy current paused frame to clipboard |',
        '| Ctrl+G | Toggle 90% safe area guide |',
        '| Check | Toggle lightweight video/audio checks |',
        '| + / seekbar right click | Add/remove manual chapter |',
        '| - | Delete a nearby manual chapter |',
        '',
        'Detected check candidates:',
        '- Black frame',
        '- Silence',
        '- Left / right channel issue',
        '- Single-frame difference',
        '- Sudden volume change',
        '- Audio clipping',
        '',
        'Manual chapters are restored per video file.',
        '');
      StatusText: 'help/review  Ln 21, Col 1  Markdown  UTF-8'
    ),
    (
      TabName: 'thumbnail-browser.md';
      HeaderText: 'Help  Thumbnail browser';
      StartLine: 41;
      Lines: (
        '# Thumbnail browser',
        '',
        '| Tab | Show / hide thumbnail browser |',
        '| Esc | Close thumbnail browser |',
        '| Arrow keys | Move selected tile |',
        '| Enter | Open selected video |',
        '| Right click | Close thumbnail browser |',
        '| Mouse wheel | Scroll list |',
        '| + / - buttons | Resize thumbnails |',
        '| Middle button + wheel | Resize thumbnails |',
        '',
        'Folder history:',
        '- First row shows recent folders',
        '- Click a folder to browse its videos',
        '- Del removes selected history item only',
        '- F5 reloads history and selected folder',
        '',
        'Hover a tile to preview it without sound.');
      StatusText: 'help/thumbnails  Ln 41, Col 1  Markdown  UTF-8'
    ),
    (
      TabName: 'playback-notes.md';
      HeaderText: 'Help  Playback notes';
      StartLine: 61;
      Lines: (
        '# Playback workflow',
        '',
        '- Files in the same folder are navigated by creation time.',
        '- End action can be Stop, Loop, or Next.',
        '- Loop repeats the current chapter segment.',
        '- External file updates are detected and reloaded.',
        '- Alpha MOV is previewed over a checkerboard.',
        '- PNG frame copy preserves alpha when the source has alpha.',
        '',
        'Boss/help screen:',
        '- Fast mouse return gesture opens this screen.',
        '- Up / Down changes help page.',
        '- PageUp / PageDown also changes help page.',
        '- Return button or Esc goes back.',
        '',
        'This screen hides the video while keeping useful help visible.',
        '',
        '');
      StatusText: 'help/playback  Ln 61, Col 1  Markdown  UTF-8'
    )
  );

function VideoMinerBossHelpPageCount: Integer;
begin
  Result := Length(HELP_PAGES);
end;

// 指定矩形を単色で塗る
procedure Fill(Canvas: TCanvas; const Rect: TRect; Color: TColor);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.Pen.Style := psClear;
  Canvas.FillRect(Rect);
end;

// 偽装画面内で使う等幅フォントの基本スタイルを設定する
procedure SetTextStyle(Canvas: TCanvas; Size: Integer; Color: TColor;
  Bold: Boolean);
begin
  Canvas.Font.Name := 'Consolas';
  Canvas.Font.Size := Size;
  Canvas.Font.Color := Color;
  if Bold then
    Canvas.Font.Style := [fsBold]
  else
    Canvas.Font.Style := [];
  Canvas.Brush.Style := bsClear;
  SetBkMode(Canvas.Handle, TRANSPARENT);
end;

// クリップ不要な短い文字列を描く
procedure Text(Canvas: TCanvas; X, Y: Integer; const Value: string;
  Color: TColor; Size: Integer; Bold: Boolean = False);
begin
  SetTextStyle(Canvas, Size, Color, Bold);
  Canvas.TextOut(X, Y, Value);
end;

// はみ出しやすい文字列を矩形内へ省略表示する
procedure ClipText(Canvas: TCanvas; const Rect: TRect; const Value: string;
  Color: TColor; Size: Integer; Bold: Boolean = False);
var
  DrawRect: TRect;
begin
  if Rect.IsEmpty then
    Exit;

  DrawRect := Rect;
  SetTextStyle(Canvas, Size, Color, Bold);
  DrawText(Canvas.Handle, PChar(Value), Length(Value), DrawRect,
    DT_SINGLELINE or DT_LEFT or DT_VCENTER or DT_END_ELLIPSIS);
end;

// 行番号と本文を 1 行ぶん描く
procedure DrawCodeLine(Canvas: TCanvas; LineNo: Integer; const LineBounds: TRect;
  const Value: string);
var
  LineRect: TRect;
begin
  LineRect := LineBounds;
  ClipText(Canvas, Rect(LineRect.Left, LineRect.Top, LineRect.Left + 44,
    LineRect.Bottom), Format('%3d', [LineNo]), COLOR_LINE_NO, 9);
  ClipText(Canvas, Rect(LineRect.Left + 50, LineRect.Top, LineRect.Right,
    LineRect.Bottom), Value, COLOR_TEXT, 9);
end;

// 左側のファイルツリー風表示を描く
procedure DrawExplorer(Canvas: TCanvas; const SidebarRect: TRect;
  PageIndex: Integer);
const
  FILE_NAMES: array[0..3] of string = (
    'basic-shortcuts.md',
    'review-tools.md',
    'thumbnail-browser.md',
    'playback-notes.md'
  );
var
  I: Integer;
  Row: TRect;
  Y: Integer;
begin
  Text(Canvas, SidebarRect.Left + 14, SidebarRect.Top + 14, 'EXPLORER',
    COLOR_DIM_TEXT, 8, True);
  Text(Canvas, SidebarRect.Left + 14, SidebarRect.Top + 42, 'VideoMiner Help',
    COLOR_TEXT, 9, True);

  Y := SidebarRect.Top + 70;
  Row := Rect(SidebarRect.Left + 16, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'docs', COLOR_TEXT, 9);
  Inc(Y, 22);

  for I := Low(FILE_NAMES) to High(FILE_NAMES) do
  begin
    Row := Rect(SidebarRect.Left + 34, Y, SidebarRect.Right - 10, Y + 18);
    if I = PageIndex then
    begin
      Fill(Canvas, Rect(SidebarRect.Left, Y - 1, SidebarRect.Right, Y + 19),
        COLOR_TAB);
      ClipText(Canvas, Row, FILE_NAMES[I], COLOR_TEXT, 8);
    end
    else
      ClipText(Canvas, Row, FILE_NAMES[I], COLOR_DIM_TEXT, 8);
    Inc(Y, 20);
  end;

  Inc(Y, 18);
  Row := Rect(SidebarRect.Left + 16, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'Source', COLOR_DIM_TEXT, 9);
  Inc(Y, 20);
  Row := Rect(SidebarRect.Left + 34, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'VideoMinerMainForm.pas', COLOR_DIM_TEXT, 8);
  Inc(Y, 20);
  Row := Rect(SidebarRect.Left + 34, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'VideoMinerBossOverlay.pas', COLOR_DIM_TEXT, 8);
end;

procedure DrawVideoMinerBossOverlay(Canvas: TCanvas; const Bounds: TRect;
  PageIndex: Integer; out ExitButtonRect: TRect);
var
  ActivityRect: TRect;
  CodeLineRect: TRect;
  EditorRect: TRect;
  I: Integer;
  Page: TBossHelpPage;
  PageText: string;
  SafePageIndex: Integer;
  SidebarWidth: Integer;
  SidebarRect: TRect;
  StatusRect: TRect;
  TabRect: TRect;
  TopBarRect: TRect;
begin
  ExitButtonRect := TRect.Empty;
  if Bounds.IsEmpty then
    Exit;

  SafePageIndex := EnsureRange(PageIndex, Low(HELP_PAGES), High(HELP_PAGES));
  Page := HELP_PAGES[SafePageIndex];
  Fill(Canvas, Bounds, COLOR_EDITOR);

  ActivityRect := Rect(Bounds.Left, Bounds.Top, Bounds.Left + 48,
    Bounds.Bottom);
  SidebarWidth := 240;
  if Bounds.Width < 900 then
    SidebarWidth := 200;
  SidebarRect := Rect(ActivityRect.Right, Bounds.Top,
    ActivityRect.Right + SidebarWidth, Bounds.Bottom);
  StatusRect := Rect(Bounds.Left, Bounds.Bottom - 28, Bounds.Right,
    Bounds.Bottom);
  TopBarRect := Rect(SidebarRect.Right, Bounds.Top, Bounds.Right,
    Bounds.Top + 34);
  TabRect := Rect(SidebarRect.Right, TopBarRect.Bottom, SidebarRect.Right + 260,
    TopBarRect.Bottom + 34);
  EditorRect := Rect(SidebarRect.Right, TabRect.Bottom, Bounds.Right,
    StatusRect.Top);

  Fill(Canvas, ActivityRect, COLOR_ACTIVITY);
  Fill(Canvas, SidebarRect, COLOR_SIDEBAR);
  Fill(Canvas, TopBarRect, COLOR_EDITOR);
  Fill(Canvas, TabRect, COLOR_TAB);
  Fill(Canvas, Rect(TabRect.Right, TabRect.Top, Bounds.Right, TabRect.Bottom),
    COLOR_EDITOR);
  Fill(Canvas, EditorRect, COLOR_EDITOR);
  Fill(Canvas, StatusRect, COLOR_STATUS);

  Text(Canvas, ActivityRect.Left + 17, ActivityRect.Top + 16, 'E',
    COLOR_TEXT, 13, True);
  Text(Canvas, ActivityRect.Left + 17, ActivityRect.Top + 56, 'S',
    COLOR_DIM_TEXT, 13, True);
  Text(Canvas, ActivityRect.Left + 17, ActivityRect.Top + 96, '?',
    COLOR_DIM_TEXT, 13, True);

  DrawExplorer(Canvas, SidebarRect, SafePageIndex);

  ClipText(Canvas, Rect(TabRect.Left + 14, TabRect.Top, TabRect.Right - 10,
    TabRect.Bottom), Page.TabName, COLOR_TEXT, 10);
  ClipText(Canvas, Rect(TopBarRect.Right - 280, TopBarRect.Top,
    TopBarRect.Right - 14, TopBarRect.Bottom), Page.HeaderText,
    COLOR_DIM_TEXT, 10);

  CodeLineRect := Rect(EditorRect.Left + 24, EditorRect.Top + 18,
    EditorRect.Right - 22, EditorRect.Top + 36);
  for I := Low(Page.Lines) to High(Page.Lines) do
  begin
    if CodeLineRect.Bottom > EditorRect.Bottom - 12 then
      Break;
    DrawCodeLine(Canvas, Page.StartLine + I, CodeLineRect, Page.Lines[I]);
    OffsetRect(CodeLineRect, 0, 19);
  end;

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := $00282724;
  for I := 0 to 7 do
  begin
    Canvas.MoveTo(EditorRect.Left, EditorRect.Top + 390 + I * 26);
    Canvas.LineTo(EditorRect.Right, EditorRect.Top + 390 + I * 26);
  end;

  ExitButtonRect := Rect(Bounds.Right - 102, StatusRect.Top + 4,
    Bounds.Right - 12, StatusRect.Bottom - 4);
  Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  Canvas.RoundRect(ExitButtonRect.Left, ExitButtonRect.Top,
    ExitButtonRect.Right, ExitButtonRect.Bottom, 6, 6);
  ClipText(Canvas, Rect(ExitButtonRect.Left + 12, ExitButtonRect.Top,
    ExitButtonRect.Right - 12, ExitButtonRect.Bottom), 'Return',
    COLOR_TEXT, 9);

  PageText := Format('  Page %d/%d  -  Up/Down or PageUp/PageDown',
    [SafePageIndex + 1, Length(HELP_PAGES)]);
  ClipText(Canvas, Rect(StatusRect.Left + 10, StatusRect.Top,
    ExitButtonRect.Left - 12, StatusRect.Bottom), Page.StatusText + PageText,
    clWhite, 9);
end;

end.
