unit VideoMinerBossOverlay;

// ボスが来たモード中に動画を隠すための偽装画面描画を担当する
// 実在するエディタ画面ではなく、仕事中に見える程度の静的な VSCode 風表示だけを描く。
// マウスジェスチャー検出や再生停止などの状態制御は、このユニットへ持ち込まない。

interface

uses
  System.Types, Vcl.Graphics;

procedure DrawVideoMinerBossOverlay(Canvas: TCanvas; const Bounds: TRect;
  out ExitButtonRect: TRect);

implementation

uses
  System.SysUtils, Winapi.Windows;

type
  TBossCodePattern = record
    TabName: string;              // view   : 上部タブに表示するファイル名
    HeaderText: string;           // view   : 右上に置くビルド/実行状態風テキスト
    StartLine: Integer;           // editor : ダミーコードの開始行番号
    Lines: array[0..15] of string; // editor : エディタ本文として描く固定行
    StatusText: string;           // status : 下側ステータスバーの左側テキスト
  end;

const
  BOSS_COLOR_ACTIVITY = $0023221F;      // palette : 左端アクティビティバー
  BOSS_COLOR_SIDEBAR = $002A2926;       // palette : ファイルツリー背景
  BOSS_COLOR_EDITOR = $001F1E1B;        // palette : エディタ背景
  BOSS_COLOR_TAB = $002C2B28;           // palette : 選択タブ/選択行背景
  BOSS_COLOR_STATUS = $00A5642A;        // palette : ステータスバー背景
  BOSS_COLOR_TEXT = $00D6D0C4;          // palette : 通常文字
  BOSS_COLOR_DIM_TEXT = $009A9388;      // palette : 補助文字
  BOSS_COLOR_LINE_NO = $007A746B;       // palette : 行番号
  BOSS_COLOR_BUTTON = $00413B34;        // palette : Return ボタン背景
  BOSS_COLOR_BUTTON_BORDER = $00665D52; // palette : Return ボタン枠線

  BOSS_PATTERNS: array[0..3] of TBossCodePattern = (
    (
      TabName: 'VideoMinerOverlay.pas';
      HeaderText: 'Debug  Win64  VideoMiner';
      StartLine: 118;
      Lines: (
        'procedure TVideoMinerOverlaySeekBar.PaintControl(Canvas: TCanvas);',
        'var',
        '  TrackRect: TRect;',
        '  PositionRatio: Double;',
        'begin',
        '  if Bounds.IsEmpty then',
        '    Exit;',
        '',
        '  TrackRect := CalculateTrackRect;',
        '  DrawStatusControls(Canvas, TrackRect);',
        '  DrawTimeline(Canvas, TrackRect);',
        '  DrawButtons(Canvas);',
        'end;',
        '',
        'procedure TVideoMinerOverlaySeekBar.SetProgress(PositionMs, MaxMs: Integer);',
        'begin');
      StatusText: 'main  Ln 128, Col 17  UTF-8  Delphi'
    ),
    (
      TabName: 'VideoMinerMainForm.pas';
      HeaderText: 'Run  Debug  Win64';
      StartLine: 642;
      Lines: (
        'procedure TVideoMinerMainForm.UpdatePlaybackProgress(PositionMs: Integer);',
        'begin',
        '  if FUpdatingSeek then',
        '    Exit;',
        '',
        '  FSeekPositionMs := Max(0, Min(FSeekMaxMs, PositionMs));',
        '  FVideoView.SetSeekProgress(FSeekPositionMs, FSeekMaxMs);',
        '  UpdateInfoLabel;',
        'end;',
        '',
        'procedure TVideoMinerMainForm.SeekByMs(DeltaMs: Integer);',
        'var',
        '  TargetMs: Integer;',
        'begin',
        '  TargetMs := CurrentPlaybackPositionMs + DeltaMs;',
        '  SeekToMs(TargetMs);');
      StatusText: 'feature/boss-mode  Ln 651, Col 23  CRLF  Delphi'
    ),
    (
      TabName: 'VideoMinerSettings.pas';
      HeaderText: 'Settings  VideoMiner.ini';
      StartLine: 34;
      Lines: (
        'function SettingsFileName: string;',
        'var',
        '  Folder: string;',
        'begin',
        '  Folder := IncludeTrailingPathDelimiter(GetAppDataPath) + ''VideoMiner'';',
        '  ForceDirectories(Folder);',
        '  Result := IncludeTrailingPathDelimiter(Folder) + ''VideoMiner.ini'';',
        'end;',
        '',
        'procedure SaveEndAction(Value: TVideoMinerEndAction);',
        'begin',
        '  WritePrivateProfileString(''Playback'', ''EndAction'',',
        '    PChar(EndActionToString(Value)), PChar(SettingsFileName));',
        'end;',
        '',
        'function LoadEndAction: TVideoMinerEndAction;');
      StatusText: 'settings  Ln 42, Col 11  UTF-8  Delphi'
    ),
    (
      TabName: 'note.md';
      HeaderText: 'Preview  Markdown';
      StartLine: 201;
      Lines: (
        '# VideoMiner development notes',
        '',
        '- Keep the main form thin.',
        '- Route overlay actions through the video view.',
        '- Avoid decoder changes unless sync logs point there.',
        '- Prefer AppData for user settings.',
        '',
        '## Next checks',
        '',
        '- Seek display should update immediately.',
        '- Loop restart should avoid visible dead time.',
        '- Boss mode must not resume playback by accident.',
        '',
        'Implementation note:',
        'Use small units when behavior can stand alone.',
        '');
      StatusText: 'notes  Ln 214, Col 5  Markdown  UTF-8'
    )
  );

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
    LineRect.Bottom), Format('%3d', [LineNo]), BOSS_COLOR_LINE_NO, 9);
  ClipText(Canvas, Rect(LineRect.Left + 50, LineRect.Top, LineRect.Right,
    LineRect.Bottom), Value, BOSS_COLOR_TEXT, 9);
end;

// 発動タイミングごとに固定パターンの見え方を少し変える
function PatternIndex: Integer;
begin
  Result := Integer((GetTickCount64 div 577) mod UInt64(Length(BOSS_PATTERNS)));
end;

// 左側のファイルツリー風表示を描く
procedure DrawExplorer(Canvas: TCanvas; const SidebarRect: TRect);
var
  Row: TRect;
  Y: Integer;
begin
  Text(Canvas, SidebarRect.Left + 14, SidebarRect.Top + 14, 'EXPLORER',
    BOSS_COLOR_DIM_TEXT, 8, True);
  Text(Canvas, SidebarRect.Left + 14, SidebarRect.Top + 42, 'VideoMiner',
    BOSS_COLOR_TEXT, 9, True);

  Y := SidebarRect.Top + 70;
  Row := Rect(SidebarRect.Left + 16, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'Source', BOSS_COLOR_TEXT, 9);
  Inc(Y, 20);
  Row := Rect(SidebarRect.Left + 30, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'App', BOSS_COLOR_TEXT, 9);
  Inc(Y, 20);
  Row := Rect(SidebarRect.Left + 44, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'VideoMinerMainForm.pas', BOSS_COLOR_DIM_TEXT, 8);
  Inc(Y, 19);
  Row := Rect(SidebarRect.Left + 44, Y, SidebarRect.Right - 10, Y + 18);
  Fill(Canvas, Rect(SidebarRect.Left, Y - 1, SidebarRect.Right, Y + 19),
    BOSS_COLOR_TAB);
  ClipText(Canvas, Row, 'VideoMinerOverlay.pas', BOSS_COLOR_TEXT, 8);
  Inc(Y, 19);
  Row := Rect(SidebarRect.Left + 44, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'VideoMinerSettings.pas', BOSS_COLOR_DIM_TEXT, 8);
  Inc(Y, 28);
  Row := Rect(SidebarRect.Left + 30, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'Decode', BOSS_COLOR_DIM_TEXT, 9);
  Inc(Y, 20);
  Row := Rect(SidebarRect.Left + 44, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'FFmpegDecoder.pas', BOSS_COLOR_DIM_TEXT, 8);
  Inc(Y, 28);
  Row := Rect(SidebarRect.Left + 16, Y, SidebarRect.Right - 10, Y + 18);
  ClipText(Canvas, Row, 'note.md', BOSS_COLOR_DIM_TEXT, 9);
end;

procedure DrawVideoMinerBossOverlay(Canvas: TCanvas; const Bounds: TRect;
  out ExitButtonRect: TRect);
var
  ActivityRect: TRect;
  CodeLineRect: TRect;
  EditorRect: TRect;
  I: Integer;
  Pattern: TBossCodePattern;
  SidebarWidth: Integer;
  SidebarRect: TRect;
  StatusRect: TRect;
  TabRect: TRect;
  TopBarRect: TRect;
begin
  ExitButtonRect := TRect.Empty;
  if Bounds.IsEmpty then
    Exit;

  Pattern := BOSS_PATTERNS[PatternIndex];
  Fill(Canvas, Bounds, BOSS_COLOR_EDITOR);

  ActivityRect := Rect(Bounds.Left, Bounds.Top, Bounds.Left + 48,
    Bounds.Bottom);
  SidebarWidth := 220;
  if Bounds.Width < 900 then
    SidebarWidth := 190;
  SidebarRect := Rect(ActivityRect.Right, Bounds.Top,
    ActivityRect.Right + SidebarWidth, Bounds.Bottom);
  StatusRect := Rect(Bounds.Left, Bounds.Bottom - 28, Bounds.Right,
    Bounds.Bottom);
  TopBarRect := Rect(SidebarRect.Right, Bounds.Top, Bounds.Right,
    Bounds.Top + 34);
  TabRect := Rect(SidebarRect.Right, TopBarRect.Bottom, SidebarRect.Right + 230,
    TopBarRect.Bottom + 34);
  EditorRect := Rect(SidebarRect.Right, TabRect.Bottom, Bounds.Right,
    StatusRect.Top);

  Fill(Canvas, ActivityRect, BOSS_COLOR_ACTIVITY);
  Fill(Canvas, SidebarRect, BOSS_COLOR_SIDEBAR);
  Fill(Canvas, TopBarRect, BOSS_COLOR_EDITOR);
  Fill(Canvas, TabRect, BOSS_COLOR_TAB);
  Fill(Canvas, Rect(TabRect.Right, TabRect.Top, Bounds.Right, TabRect.Bottom),
    BOSS_COLOR_EDITOR);
  Fill(Canvas, EditorRect, BOSS_COLOR_EDITOR);
  Fill(Canvas, StatusRect, BOSS_COLOR_STATUS);

  Text(Canvas, ActivityRect.Left + 17, ActivityRect.Top + 16, 'E',
    BOSS_COLOR_TEXT, 13, True);
  Text(Canvas, ActivityRect.Left + 17, ActivityRect.Top + 56, 'S',
    BOSS_COLOR_DIM_TEXT, 13, True);
  Text(Canvas, ActivityRect.Left + 17, ActivityRect.Top + 96, 'G',
    BOSS_COLOR_DIM_TEXT, 13, True);

  DrawExplorer(Canvas, SidebarRect);

  ClipText(Canvas, Rect(TabRect.Left + 14, TabRect.Top, TabRect.Right - 10,
    TabRect.Bottom), Pattern.TabName, BOSS_COLOR_TEXT, 10);
  ClipText(Canvas, Rect(TopBarRect.Right - 260, TopBarRect.Top,
    TopBarRect.Right - 14, TopBarRect.Bottom), Pattern.HeaderText,
    BOSS_COLOR_DIM_TEXT, 10);

  CodeLineRect := Rect(EditorRect.Left + 24, EditorRect.Top + 18,
    EditorRect.Right - 22, EditorRect.Top + 36);
  for I := Low(Pattern.Lines) to High(Pattern.Lines) do
  begin
    if CodeLineRect.Bottom > EditorRect.Bottom - 12 then
      Break;
    DrawCodeLine(Canvas, Pattern.StartLine + I, CodeLineRect, Pattern.Lines[I]);
    OffsetRect(CodeLineRect, 0, 19);
  end;

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := $00282724;
  for I := 0 to 7 do
  begin
    Canvas.MoveTo(EditorRect.Left, EditorRect.Top + 350 + I * 26);
    Canvas.LineTo(EditorRect.Right, EditorRect.Top + 350 + I * 26);
  end;

  ExitButtonRect := Rect(Bounds.Right - 102, StatusRect.Top + 4,
    Bounds.Right - 12, StatusRect.Bottom - 4);
  Canvas.Brush.Color := BOSS_COLOR_BUTTON;
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := BOSS_COLOR_BUTTON_BORDER;
  Canvas.RoundRect(ExitButtonRect.Left, ExitButtonRect.Top,
    ExitButtonRect.Right, ExitButtonRect.Bottom, 6, 6);
  ClipText(Canvas, Rect(ExitButtonRect.Left + 12, ExitButtonRect.Top,
    ExitButtonRect.Right - 12, ExitButtonRect.Bottom), 'Return',
    BOSS_COLOR_TEXT, 9);

  ClipText(Canvas, Rect(StatusRect.Left + 10, StatusRect.Top,
    ExitButtonRect.Left - 12, StatusRect.Bottom), Pattern.StatusText,
    clWhite, 9);
end;

end.
