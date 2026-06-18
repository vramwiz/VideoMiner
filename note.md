# VideoMiner note

## アプリの目的

VideoMiner は、動画を快適に見るための Windows/VCL アプリとして設計する。

単純な再生アプリではなく、既存のメディアプレイヤーで感じる不満を減らすことを目的にする。

想定する不満:

- いま開いているファイルと同じフォルダ内の別ファイルへ移動しにくい。
- 次の動画を見るために、毎回ファイルを開き直す必要がある。
- 動画の一部を確認したいとき、ズームや表示位置の操作が弱い。
- フォルダ内の素材を続けて確認する作業に向いていない。
- 動画編集者が納品前や素材整理時に、確認済み、要修正、気になる箇所を残しにくい。

VideoMiner は、素材確認・動画確認・編集チェックを軽く行えるビューアを目指す。

## 基本仕様

### ファイル表示

- 動画ファイルを開いて表示できる。
- 画像ファイル対応は行わず、動画確認に集中する。
- 開いたファイルのフォルダを自動的に認識する。
- 同じフォルダ内の前後のファイルへ簡単に移動できるようにする。
- ファイルをあらためて開き直さなくても、次のファイルを表示できるようにする。

### フォルダ内ナビゲーション

- 開いたファイルを基準に、同じフォルダのメディア一覧を作る。
- 「次へ」「前へ」でフォルダ内のファイルを切り替える。
- 一覧対象は動画ファイルに限定する。
- ファイル名順、更新日時順などの並び替えを検討する。

### 表示とズーム

- 好きな箇所をズームして確認できるようにする。
- ズーム中に表示位置を動かせるようにする。
- 全体表示、等倍表示、任意倍率表示を切り替えられるようにする。
- 動画再生中でも、必要な範囲でズーム表示を維持できるようにする。

### 再生操作

- 通常再生、一時停止、停止を行える。
- シークバーで任意位置へ移動できる。
- 現在の位置、動画時間、ファイル情報を見やすく表示する。
- 将来的にはフレーム送り、倍速、ループ再生も検討する。

### 動画編集者用チェック機能

- 動画を見ながら、確認済み、要確認、要修正などのチェック状態を付けられるようにする。
- 気になる箇所へ時刻付きメモを残せるようにする。
- チェック結果はファイル単位、必要なら時刻単位で管理できるようにする。
- フォルダ内の動画を順に確認し、未確認や要修正の動画へ戻りやすくする。
- 将来的にはチェック結果の一覧表示、絞り込み、外部出力を検討する。

## 現在のプロジェクト構成

ルート:

- `VideoMiner.dpr`
- `VideoMiner.dproj`
- `VideoMiner.res`
- `note.md`
- `Source`
- `Win64`
- `ffmpeg-8.1.1-full_build-shared`

ソースフォルダ:

- `Source\App`
  - VideoMiner アプリ本体のユニット。
  - フォーム、表示サーフェス、オーバーレイ GUI、設定、音声再生ラッパ、フォルダ内メディア一覧など、アプリ固有の責務を置く。
- `Source\Decode`
  - FFmpeg を使ったデコード処理。
  - 動画/音声ストリームを開く、シークする、次フレームを読む、音声 PCM を読む、色形式ごとにフレームを取り出す処理を置く。
- `Source\FFmpeg`
  - FFmpeg API 宣言、フレーム変換、QSV 関連、ストリーム情報取得などの低レベル共通処理。
  - `Source\Decode` から使われる土台で、アプリ UI へ直接依存させない。
- `Source\Lib`
  - アプリから使う汎用補助ユニット。
  - ドラッグ&ドロップ、ショートカット登録、タイマー補助、フォルダ監視など、VideoMiner 固有ではない再利用可能な補助処理を置く。

### 主要ユニットの意味

開発時に迷わないため、主なユニットの責務を以下のように扱う。

#### `Source\App`

- `VideoMinerMainForm.pas`
  - メインフォーム。
  - GUI コンポーネントの生成後初期化、イベント受け口、各機能ユニットの接続、現在のアプリ状態の橋渡しを担当する。
  - 今後は処理を抱え込ませすぎず、再生制御、ウィンドウ制御、設定、ショートカット、表示部品の詳細は別ユニットへ寄せる。
- `VideoMinerMainForm.dfm`
  - メインフォームの VCL デザイン定義。
  - 独自タイトルバー、動画表示元の `ImagePreview`、タイマー、ファイル選択ダイアログなどの配置を持つ。
- `VideoMinerVideoView.pas`
  - メインフォームと動画表示サーフェスの間に置く薄い窓口。
  - `TImage` から専用サーフェスへ差し替え、フレーム表示、シーク進捗、オーバーレイイベント接続を中継する。
- `VideoMinerVideoSurface.pas`
  - 実際の動画表示面。
  - 32bit Bitmap の再利用、バックバッファ描画、ズーム/パン、ホイール処理、マウス操作、オーバーレイ部品の表示制御を担当する。
- `VideoMinerOverlay.pas`
  - 動画サーフェス上に描く自前オーバーレイ GUI。
  - 再生/一時停止、10 秒戻し/進み、先頭/末尾、左右ファイル移動、下側シークバー、音量、ミュート、終了時動作、全画面ボタンなどの描画とヒットテストを担当する。
  - 中央の 5 アイコンや左右ファイルナビゲーションなど、動画上に直接重ねる操作部品の見た目もここで調整する。
- `VideoMinerAudioPlayback.pas`
  - アプリ側から使う音声再生ラッパ。
  - 音声開始/停止、シーク位置からの再生、単調時計ベースの再生位置、音量、ミュートを管理する。
- `VideoMinerMediaList.pas`
  - 開いたファイルのフォルダを作業単位として扱うためのメディア一覧。
  - 対象拡張子の収集、現在位置、前後ファイルへの移動可否、ナビゲーション先ファイルを管理する。
- `VideoMinerSettings.pas`
  - `%APPDATA%\VideoMiner\VideoMiner.ini` への設定保存/読込。
  - 通常ウィンドウ位置、最後に開いたフォルダ/ファイル、再生終了時動作を扱う。
- `VideoMinerWindowChrome.pas`
  - 枠なしフォームの Windows 連携。
  - `CreateParams`、`WM_NCCALCSIZE`、保存済みウィンドウ位置の復元と記憶を担当する。
  - 端/角の実リサイズ操作は `Source\Lib\ResizeEdges` の透明エッジに任せる。
- `VideoMinerShortcutBindings.pas`
  - VideoMiner 用ショートカット割り当て表。
  - どのキーをどの操作へ結びつけるかを持ち、`VideoMinerMainForm` からキー割り当ての詳細を分離する。
- `VideoMinerDebugLog.pas`
  - Debug ビルド専用の調査ログ。
  - 再生同期、描画負荷、音声キューなどの調査用ログを `%TEMP%\VideoMiner_playback_debug.log` へ出す。
- `VideoMinerBossGesture.pas`
  - ボスが来たモードへ入るためのマウスジェスチャー検出。
  - 方向反転型と A-B-A 往復型の検出を持ち、発動判定だけを担当する。
  - 実際の再生停止、偽装画面表示、解除処理はメインフォーム/動画サーフェス側へ任せる。
- `VideoMinerBossOverlay.pas`
  - ボスが来たモード中に動画を隠す偽装画面描画。
  - VSCode 風の静的なエディタ画面、ファイルツリー、ステータスバー、解除用 `Return` ボタンを描く。
  - マウスジェスチャー検出や再生状態制御は持たない。

#### `Source\Decode`

- `FFmpegDecoder.pas`
  - デコード処理の高レベル窓口。
  - ファイルを開く/閉じる、動画フレーム取得、音声出力音量、音声読み取り系処理への中継を担当する。
- `FFmpegDecoderTypes.pas`
  - デコーダで共有する型定義。
  - 動画情報、音声情報、フレーム形式など、Decode 層で使う共通型を置く。
- `FFmpegDecoderContext.pas`
  - FFmpeg デコード文脈の管理。
  - format/codec/sws など、複数の処理から共有される状態を扱う。
- `FFmpegAudioOpen.pas`
  - 音声ストリームを開く処理。
  - 入力ファイルから音声デコードに必要な codec/context を準備する。
- `FFmpegAudioConvert.pas`
  - 音声サンプル変換。
  - FFmpeg から得た音声フレームを waveOut へ渡せる PCM 形式へ変換する。
- `FFmpegDecoderAudioRead.pas`
  - 音声フレーム読み取りとシーク補助。
  - 指定位置から音声 PCM を読み、シーク直後の不要サンプル破棄などを扱う。
- `FFmpegDecoderAudioPlayback.pas`
  - waveOut への音声投入補助。
  - PCM キュー、音量反映、waveOut 操作など、低レベル音声出力を扱う。
- `FFmpegDecoderNext*.pas`
  - 順方向に次の動画フレームを読む処理。
  - `Bgrx32`、`Bgr24`、`I420`、`Yc48`、`Yuy2` など出力形式ごとに分かれている。
- `FFmpegDecoderSeek*.pas`
  - 指定時刻へシークして動画フレームを取得する処理。
  - 出力形式ごとに分かれており、VideoMiner の表示では主に `Bgrx32` 系を使う。
- `FFmpegDecoderResources.pas`
  - デコーダ内部リソースの解放や補助処理。
  - FFmpeg リソース管理に関わる処理をまとめる。

#### `Source\FFmpeg`

- `FFmpegApi.pas`
  - FFmpeg DLL/API への Delphi 側宣言。
  - libavformat/libavcodec/libswscale/libswresample などの関数や型を使うための土台。
- `FFmpegFrameConvert.pas`
  - 映像フレーム変換。
  - FFmpeg の frame を Bitmap や BGRX/BGR24 などの表示用バッファへコピー/変換する。
- `FFmpegQsvDecode.pas`
  - Intel QSV などハードウェアデコード関連の補助。
  - 現状で使い続けるかは、今後の不要ユニット整理時に確認する。
- `FFmpegStreamInfo.pas`
  - 入力ファイルのストリーム情報取得。
  - 動画/音声の有無、サイズ、fps、duration などの情報を読む。

#### `Source\Lib`

- `DropAgent\DropAgent.pas`
  - Windows/VCL のドラッグ&ドロップ補助。
  - フォームへファイルドロップを受けるために使う。
- `ShortcutAction\ShortcutAction.pas`
  - キーボードショートカット登録/実行補助。
  - `VideoMinerShortcutBindings` がこのクラスへ VideoMiner 用の割り当てを登録する。
- `ResizeEdges\ResizeEdges.pas`
  - 枠なしフォームや任意の `TWinControl` に透明なリサイズエッジを追加する補助。
  - VideoMiner では標準の `WS_THICKFRAME` に頼らず、白い境界線を出さずに端/角リサイズを可能にするために使う。
- `MMTimer\MMTimer.pas`
  - マルチメディアタイマー補助。
  - 現状の VideoMiner 本体で必要かは、今後の不要ユニット整理で確認する。
- `FolderWatch\FolderWatch.pas`
  - フォルダ監視補助。
  - 現状の VideoMiner 本体で必要かは、今後の不要ユニット整理で確認する。

### コメント記述ルール

基本方針:

- コメントは、処理を読めば分かることをなぞるのではなく、目的、責務、注意点、状態の意味を補うために書く。
- 古い仕様や現在の実装と食い違うコメントは、見つけた時点で更新する。
- 不要なコメントや重複したコメントを増やしすぎない。
- `var` ブロック内にローカル関数やローカル手続きを内包しない。
  - 補助処理が必要な場合は、同じ `implementation` 内の独立した関数/手続きとして切り出す。
  - この形を見つけた場合は、コメント追加だけで済ませず構造も直す。

ユニット先頭:

- 各ユニットの先頭には、そのユニットの目的や担当範囲を `//` コメントで記述する。
- 依存関係や「ここには書かない処理」が重要な場合は、その注意も先頭コメントに含める。

フィールド:

- フィールドの意味は、フィールド宣言の右側に 1 行コメントとして `//` で書く。
- 同じブロック内では、フィールド名の後ろに置く型区切りの `:` の X 座標を揃える。
- 同じブロック内では、`//` の X 座標を揃える。
- コメント本文の先頭に `file:` や `playback:` のような分類ラベルは付けない。
- コメント本文は、そのフィールド単体の意味を自然な日本語で書く。
- 同じクラス内で長い共通接頭辞を持つフィールドが並び、コメントや整列を読みにくくしている場合は、接頭辞を削ってよい。
  - 例: `FAutoCheckDarkStartMs` は、自動チェック専用 manager 内なら `FDarkStartMs` にしてよい。
  - ただし `property ... read/write ...` で外部公開名と対応している backing field は、無理に短縮しない。
  - この程度のフィールド名変更が必要なら、コメントだけで済ませずコードも追従する。
- 例:

```pascal
FVideoFile      : string;  // 現在開いている動画ファイル
FSeekPositionMs : Integer; // UI 側で保持する現在位置 ms
FSeekMaxMs      : Integer; // シーク可能な最大位置 ms
```

定数:

- 定数の意味は、定数宣言の右側に 1 行コメントとして `//` で書く。
- 同じ `const` ブロック内では、`=` の X 座標を揃える。
- 同じ `const` ブロック内では、`//` の X 座標を揃える。
- コメント本文は、その定数が判定や処理で何の基準になるかを自然な日本語で書く。
- 同じユニット内だけで使う定数は、長い共通接頭辞やユニット内の文脈で明らかな語を削ってよい。
  - 例: 自動チェック専用 manager 内なら `AUTO_CHECK_AUDIO_SILENCE_PEAK` は `SILENCE_PEAK` にしてよい。
  - 外部公開される定数や、他ユニットから参照される可能性がある定数では、意味が衝突しない名前を優先する。
  - この程度の定数名変更が必要なら、コメントだけで済ませずコードも追従する。
- 例:

```pascal
VIDEO_AUDIO_SYNC_LAG_MS       = 60;   // 音声同期のためにフレーム破棄を検討する遅れ幅 ms
VIDEO_DEFAULT_FRAME_DURATION  = 33;   // FPS 不明時に使う既定フレーム長 ms
VIDEO_END_TOLERANCE_MS        = 1500; // 終端付近として扱う残り時間 ms
```

プロパティ:

- `property` 宣言は、横幅 112 文字以内に収まる場合は折り返さない。
- 112 文字を超える場合だけ、既存の Delphi コードの読みやすい位置で折り返す。

メソッド:

- メソッドの意味は、メソッド宣言または実装の上に 1 行コメントとして書く。
- `procedure` / `function` 宣言は、横幅 112 文字以内に収まる場合は折り返さない。
- 112 文字を超える場合だけ、既存の Delphi コードの読みやすい位置で折り返す。
- 引数の意味が複雑な場合は、複数行コメントにしてよい。
- コメントと対象メソッドの間に空行は入れない。
- 例:

```pascal
// 指定位置へシークし、必要なら再生状態を復元する
procedure SeekToMs(PositionMs: Integer; ResumeIfPlaying: Boolean = True);
```

複雑な引数がある場合:

```pascal
// フレームを表示用 BGRX32 バッファへ直接デコードする
// Buffer       : 出力先バッファ先頭
// BufferStride : 1 行あたりのバイト数
function PrepareFrameBuffer(Decoder: TFFmpegDecoder; out Buffer: Pointer;
  out BufferStride: Integer; out ErrorMessage: string): Boolean;
```

空行:

- コメントと対象の宣言/実装の間には空行を入れない。
- コメントブロック内でも、意味の切れ目が明確に必要な場合以外は空行を入れない。

## 現在の状態

- プロジェクト名は `VideoMiner`。
- メインフォームは `VideoMinerMainForm`。
- ルート直下に多数あった `.pas` は `Source` 配下へ移動済み。
- 現時点では、VideoMiner アプリ本体として動画表示機能を整理している。
- メインフォームはデバッグ用の操作ボタンや情報ラベルを外し、動画ビューだけを表示する構成へ移行中。
- 出力系、AviUtl 連携、入力プラグイン由来の処理は削除済み。
- デバッグ用・テスト場由来の処理は、アプリに不要なものから削除している。
- 2026-06-16 時点では、フォルダ内動画の並び順を作成日時の古い順に変更済み。
- 2026-06-16 時点では、左右キー/PageUp/PageDown の前後動画移動で、キーリピートや残留キー入力が次々処理されにくいよう入力ガードを入れている。
- 2026-06-16 時点では、下側シークバー上のホイール操作で一時停止してシークできる。
  - 通常時は 1 秒単位で移動する。
  - `Check` ON 中は 1 フレーム目安で移動し、シークバー表示を概算の `Frame n / total` に切り替える。
- 2026-06-17 時点では、alpha 付き動画の確認用に、入力 pixel format 名と alpha 有無をデコーダ情報へ持たせるようにした。
  - `yuva` / `rgba` / `bgra` / `argb` / `abgr` / `gbrap` / `ya` 系の pixel format を alpha 付きとして扱う。
  - alpha 付き動画では、表示面で BGRA の alpha を市松模様へ手動合成して表示する。
  - Debug ビルドでは動画面左上に `Alpha preview  A min-max  transparent n%` を出し、透明情報が残っているかを自作プレイヤー側で確認できる。
  - Release ビルドでは通常利用の邪魔にならないよう、透明率などの診断文字列は表示しない。
  - 透明情報を持つ `.mov` は、再生時に市松模様へ合成して透明部分を確認できる。
- 2026-06-17 時点では、サムネイル一覧モードの入口とタイル枠表示を追加した。
  - `Tab` で一覧表示/非表示を切り替える。
  - 一覧表示中は `Esc` で閉じる。
  - `TVideoMinerThumbnailBrowser` を追加し、現在の `TVideoMinerMediaList` を使って同一フォルダ内の動画をタイル表示する。
  - 現段階ではサムネイル画像は生成せず、ファイル名付きの枠だけを表示する。
  - 現在再生中の動画は枠線で強調する。
  - マウスホイールで縦スクロールでき、一覧を開いた時点で現在動画付近へスクロールする。
- 2026-06-17 の作業終了時点では、サムネイル一覧モードは最小入口まで実装済み。
  - 追加ユニットは `Source\App\VideoMinerThumbnailBrowser.pas`。
  - `VideoMiner.dpr` / `VideoMiner.dproj` に同ユニットを登録済み。
  - `VideoMinerMainForm.pas` への追加は、一覧コントロールの生成/破棄、動画ロード後の一覧更新、`Tab` / `Esc` の表示切り替えだけに留めた。
  - `TVideoMinerMediaList` の既存リストをそのまま使うため、同一フォルダ内動画一覧の収集ロジックは新規に重複させていない。
  - 2026-06-17 の次段階で、タイルクリックから動画を切り替える処理を追加した。
    - `TVideoMinerThumbnailBrowser.OnSelected` で選択ファイルを通知し、`VideoMinerMainForm` 側で `LoadVideoFile(FileName, True)` へ流す。
    - 現在再生中のタイルをクリックした場合は、動画を開き直さず一覧だけ閉じる。
    - 読み込みに成功した場合だけ一覧を閉じ、失敗時はエラー表示を残す。
    - `Tab` が `OnKeyDown` へ届かない環境向けに、`CM_DIALOGKEY` でも一覧切り替えを拾うようにした。
    - サムネイル一覧表示中は右クリックで一覧を閉じるようにした。
  - 2026-06-17 の次段階で、フォーム端のリサイズ操作を改善した。
    - 枠なしフォーム端のリサイズ判定幅を 6px から 12px に広げた。
    - サムネイル一覧表示中でも端を掴めるよう、サムネイルブラウザにも左右・下端の透明リサイズハンドルを付けた。
    - 通常動画画面の右クリックでもサムネイル一覧を開けるようにした。
  - 2026-06-17 の次段階で、表示中タイルのサムネイル画像生成を追加した。
    - 表示されているタイルだけを生成予約し、`TTimer` で 1 枚ずつ生成する。
    - 代表フレームは動画時間の 10% 地点を基本にし、短い動画は中央付近、通常動画は最低 0.5 秒以降を使う。
    - 生成画像は最大 320x180 に縮小してメモリ保持し、タイル内にはアスペクト比を維持して表示する。
    - 生成中は `Loading`、失敗時は `Failed` を表示する。
    - 一覧表示中はフォームの `DoMouseWheel` からサムネイルブラウザへ優先的にホイール入力を渡し、縦スクロールできるようにした。
    - サムネイル生成は `DecodeFrameToBitmap` ではなく通常表示と同じ `DecodeFrameToBgrx32` 経路へ寄せ、swscale 例外はタイル単位の `Failed` に閉じ込めるようにした。
  - 2026-06-17 の次段階で、サムネイルのディスクキャッシュを追加した。
    - `%APPDATA%\VideoMiner\ThumbnailCache` に縮小済み BMP を保存する。
    - キャッシュキーは元ファイルの展開パス、更新日時、ファイルサイズから作る。
    - 起動後に同じファイルを表示する場合、元ファイルが変わっていなければ再デコードせずキャッシュ画像を読む。
    - キャッシュヒット時は 1 tick で最大 24 枚までまとめて読み込み、キャッシュミス時の実デコードは従来通り 1 枚ずつ行う。
  - キーボード上下左右選択、`Enter` 再生、ファイル更新判定付きのメモリキャッシュ、本格的な可視範囲優先生成は未実装。
  - 次回は、キーボードでタイル選択して `Enter` で再生する操作か、サムネイル生成の負荷と失敗時再試行を調整するとよい。
  - Debug Win64 ビルドは `D:\DelphiProg\VideoMiner\VideoMiner.dproj` で成功済み。警告 0、エラー 0。

## 実装済みの主な機能

### 起動とファイル受け取り

- 実行時引数で動画ファイルを渡された場合、そのファイルを開いて再生する。
- フォームへのファイルドロップで、そのファイルを開いて再生する。
- 二重起動は禁止。
- すでに起動している場合、後から起動したプロセスは既存プロセスへファイルパスを `WM_COPYDATA` で渡して終了する。
- 既存プロセス側では、受け取ったファイルを即時処理せずキューに積み、`WM_VM_OPEN_PENDING` で安全なタイミングに開く。

### フォルダ単位の管理

- VideoMiner はファイル単体ではなく、フォルダを作業単位として扱う。
- ファイルを指定された場合も、「フォルダ + 現在ファイル」として扱う。
- ファイルを開いたとき、同じフォルダ内の動画ファイル一覧を内部リストとして作る。
- フォルダ内の動画ファイル一覧は、作成日時の古い順を標準とする。
  - 同じ作成日時の場合はファイル名順で安定させる。
  - 作成日時を取得できない場合は、走査時に得られる更新日時へフォールバックする。
- 現在再生中のファイルが一覧の何番目かを保持する。
- Caption に現在ファイル名と `n/total` を表示する。
- 情報ラベルにも現在ファイル名、一覧位置、動画情報、音声情報を表示する。
- `Previous` / `Next` ボタンで同じフォルダ内の前後ファイルへ移動する。
- 一覧の端では `Previous` / `Next` ボタンの `Enabled` を切り替える。

現在の動画対象拡張子:

- `.mp4`
- `.mov`
- `.mkv`
- `.avi`
- `.wmv`
- `.m4v`
- `.webm`
- `.mpg`
- `.mpeg`
- `.ts`
- `.m2ts`

### 再生とシーク

- `Play` / `Stop` による動画再生と停止。
- シークバー操作で指定位置のフレームを表示する。
- 下側シークバー上でマウスホイールを回すと、再生中でも一時停止して位置を移動する。
  - `Check` OFF では 1 秒単位で移動する。
  - `Check` ON ではフレーム確認向けに 1 フレーム目安で移動し、シークバー表示も `Frame n / total` の概算表示へ切り替える。
- キーボード操作で `-10s` / `+10s` 相当の移動を行う。
- `-10s` は 10 秒未満なら開始位置へ移動する。
- `+10s` は残り 10 秒未満なら終了位置へ移動する。
- 10 秒スキップ直後に再生タイマー側の古い位置更新でシークバーが揺れないよう、シーク中フラグとシーク直後のガードを入れている。
- 2026-06-06 時点で、デバッグ用の画面上ボタン類は削除し、操作はキーボードとファイルドロップ中心に移行した。
- direct 系の動画表示へ通常の VCL コントロールを重ねず、動画サーフェス自身が描くオーバーレイ GUI 方式へ移行開始。
- 最初のオーバーレイとして、画面中央に半透明白の再生/一時停止ボタンを追加。
- 中央ボタンの左右に、数値なしの曲がった矢印で 10 秒戻し/10 秒進みのオーバーレイボタンを追加。
- オーバーレイ GUI は抽象基底 `TVideoMinerOverlayControl` から継承する形にし、プレビュー表示領域から割合でサイズと位置を決める方針。

### 再生速度

- 2026-06-12 に、再生速度の段階実装として `1.0x` / `1.5x` / `2.0x` の切り替えを追加した。
- 下側オーバーレイのシークバー周辺に速度ボタンを表示し、クリックまたは `R` キーで循環する。
- 状態は `VideoMinerPlaybackController` が持ち、表示とクリック判定は `VideoMinerOverlay` / `VideoMinerVideoView` / `VideoMinerCommandController` を通す。
- 2026-06-12 の次段階で、`1.5x` / `2.0x` でも簡易音声倍速を鳴らすようにした。
- 当初の簡易音声倍速は PCM の入力サンプルを間引く方式だったが、その後、窓単位の切り貼りとクロスフェードで出力 PCM を短くする簡易 time-stretch に置き換えた。
- 2026-06-12 に `avfilter-11.dll` を `Win64\Debug` / `Win64\Release` へ追加し、FFmpeg filter の `atempo` を優先して使う `FFmpegAudioTempo.pas` を追加した。
- `TVideoMinerAudioPlayback.TransformPcmForPlaybackRate` は、まず `atempo` 変換を試し、失敗した場合だけ簡易 time-stretch へフォールバックする。
- `TVideoMinerAudioPlayback` は入力側のデコード済みサンプル数と waveOut へ積んだ出力サンプル数を分けて扱う。
- `avfilter-11.dll` は `LoadLibrary` 確認済み。実動画で音質や同期を確認し、問題があれば `%TEMP%\VideoMiner_playback_debug.log` の `audio_tempo_fallback` と `audio_pump` を見る。
- `TempoSmokeTest` で 48kHz/stereo/s16 の 1 秒 PCM を `atempo=1.5` に通し、`input=48000` / `output=32080` の出力を確認済み。

## ビルド

Debug Win64 ビルド例:

```powershell
$env:BDS='C:\Program Files (x86)\Embarcadero\Studio\37.0'
& 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe' `
  'D:\DelphiProg\VideoMiner\VideoMiner.dproj' `
  /t:Build /p:Config=Debug /p:Platform=Win64
```

直近の確認:

- Debug Win64 ビルド成功。
- 生成物:
  - `D:\DelphiProg\VideoMiner\Win64\Debug\VideoMiner.exe`
- エラー 0。
- 警告 0。

## 共通メモ

- `note.md` は UTF-8 BOM 付き、改行は CRLF で保存する。ANSI / Shift-JIS へ変換しない。
- PowerShell で `note.md` を編集する場合は、`[System.Text.UTF8Encoding]::new($true)` などで UTF-8 BOM を明示して読み書きする。
- Delphi ソースを修正する場合も、UTF-8 BOM 付き、改行 CRLF で保存する。
- Delphi ソースは文字コードが混在しやすいので、編集後は文字化けが起きていないか差分を確認する。
- `.pas` / `.dfm` を触った後は、必ず Debug Win64 ビルドで確認する。
- バージョンリソースは `Version.inc` と `Version.rc` を git 管理し、`Version.res` は生成物として除外する。
  - `VideoMiner.dpr` は `{$R Version.res}` を参照する。
  - `VideoMiner.dproj` の `BuildVideoMinerVersionResource` ターゲットが `Version.rc`/`Version.inc` から `Version.res` を生成する。
- Debug ビルド時のみ、再生同期調査ログを `%TEMP%\VideoMiner_playback_debug.log` に出力する。
  - 実装は `Source\App\VideoMinerDebugLog.pas`。
  - `VideoMiner.dproj` の Debug 構成は `DEBUG` define を持つため、ログ出力は `{$IFDEF DEBUG}` で Release ビルドには入れない。
  - 主な行は `playback_tick`、`paint`、`start_playback`、`restart_playback`。
  - `playback_tick` では `audio_ms`、`video_ms`、`lag_ms`、`drop_count`、`pump_ms`、`decode_ms`、`sync_ms`、`total_ms`、`timer_interval` を確認する。
  - `paint` では `paint_ms` を確認し、`Canvas.StretchDraw` を含む描画負荷を見る。
- 2026-06-13 に、通常の毎 tick 詳細ログとは別に、DEBUG ビルドだけで遅い操作を記録する slow log を追加した。
  - `WriteVideoMinerSlowLog` は DEBUG ビルドで有効、Release では無効。
  - 主な行は `open_done`、`show_frame_near_slow`、`seek_slow`、`start_playback_slow`、`audio_start_slow`、`audio_pump_slow`、`playback_tick_slow`。
  - NAS 上の `\\taketani\bbb` の実測では、open はおおむね 196-316ms、再生開始は `audio_start_slow` の `output_start_ms` が 149-185ms 程度。
  - 10 秒送り相当のシークでは `show_frame_near_slow` が 123-191ms、`seek_slow` 全体が 157-221ms 程度。現状で最初に疑う場所はシーク後の `ShowFrameNearMs` / `FVideoView.ShowFrameAt`。
- 2026-06-13 に、再生中シークの軽量化として `seek_fast_restart` ルートを追加した。
  - 再生中に `+10s` / `-10s` などで移動する場合、従来は `PreviewDecoder` で一度フレーム表示してから再生用 `Decoder` で再開していた。
  - 新ルートでは、再生中だけプレビュー側の `ShowFrameNearMs` を省き、再開時の `StartAtMs` で一回だけフレーム取得する。
  - 停止中や末尾へのシークは従来通りプレビュー表示する。
  - さらに再生開始・再開用の映像取得だけ `DecodeFrameToBgrx32Fast` を使い、近いフレームを優先して復帰時間を短縮する。停止中プレビューは従来の正確寄り seek のまま。
  - 音声側は初期キューを 180ms から 100ms、補充目標を 1000ms から 600ms に下げ、一回の音声デコード固まりを小さくした。
  - `\\taketani\bbb\Balloon\melpo-MP4589S-MB3-01.wmv` の再計測では、`seek_fast_restart` は 2.6-6.6ms 程度。`start_playback_slow` / `audio_start_slow` は閾値以上では出なくなった。
  - その後、一時停止からの通常再生でも fast seek が効いて数フレーム前が一瞬表示される可能性があったため、fast seek は `seek_fast_restart` からの自動再開時だけ使うように限定した。
  - ユーザー確認では、今回の調整で体感はかなり改善した。残る停止感は、再開前に最低限の音声バッファを溜める処理として許容する方針。
  - ここからさらに削りすぎると音切れや同期ズレが出やすいため、現時点では初期キュー 100ms / 補充目標 600ms を当面の落としどころにする。
- ユーザー操作でシークバーを動かした場合と、コード側でシークバー位置を更新した場合を分けるため、`FUpdatingSeek` を使う。
- 再生中にシークする処理では、タイマーと音声再生を一度止めてから位置を変更し、必要なら再生を再開する。
- 二重起動時の受信処理は、`WM_COPYDATA` 内で直接重い処理をせず、キューに積んでから処理する。
- ファイルを開き直す処理では、前の再生状態、シークガード、画像表示、シークバー状態をリセットする。
- アプリの中心は「出力」ではなく「見る」「探す」「確認する」。AviUtl やプラグイン入出力に寄った処理は原則不要。
- 音声再生は waveOut へ PCM をキューし、再生済みサンプル数を見ながら一定量だけ先読みする。停止時に waveOut 音量を 0 にしない。
- 現状の映像再生は `TTimer` で次フレームを 1 枚ずつ表示する方式。描画負荷低減のため `TImage.Picture.Bitmap.Assign` を避け、専用表示サーフェスの `TBitmap` を再利用する。
- 音声位置より映像が一定以上遅れた場合は、音声位置をマスターとして映像を追従させる。現時点では大きな遅れを検出した時だけシークで追いつかせる最小補正とする。
- コンテナ上の duration と実際に映像フレームをデコードできる範囲が終端付近で一致しないファイルがある。再生中に終端付近の映像が取得できない場合、映像は最後に表示できたフレームのままとし、シークバー位置は音声再生位置に合わせて最後まで進める。

## 直近の調査メモ: 表示高速化と音声同期

2026-06-06 時点の引き継ぎメモ。

### 安定版メモ

- 2026-06-06 時点で、通常再生、再生中シーク、停止再生後の同期、音量変更、ミュート切り替えは理想に近い状態まで安定した。
- 音声をマスターにして映像を追従させる方針でよい。ログ確認では `lag_ms` はおおむね `-30..30` ms の範囲に収まり、再生中に差が蓄積する挙動は見られない。
- 音声位置計算は waveOut の再生済みサンプル数ではなく、`TStopwatch` ベースの単調時計を使う。`waveOutGetPosition` は長時間再生時やキュー状態の影響で信用しにくかった。
- 音声サンプル位置の計算は必ず `Int64` で行う。`PlaybackPositionMs * 48000` は約 44.7 秒で 32bit `Integer` を超え、音声キュー判定を壊す。
- 音声キューは `AUDIO_TARGET_QUEUE_MS = 1000` ms 程度を維持する。修正後はキュー残量が約 960..1010 ms で安定していた。
- 再生中シークは必ず `SeekToMs` を通す。`TimerPlayback`、再開予約タイマー、古い再開予約、`FAudioPlayback` を止めてから、シーク先のフレームを表示し、必要なら最新位置だけ再開予約する。
- シーク時の音声は `SeekAudioToMs` で音声ストリームへ移動し、シーク直後の前方サンプルだけ `AudioDiscardUntilSample` で捨てる。通常再生中に毎回トリムしない。
- 音量とミュートは PCM に焼き込まず、`waveOutSetVolume` へ反映する。これにより、すでに waveOut キューに入っている音声にも即時に効く。
- PCM に対して行う加工は、再生開始直後の短いフェードインだけにする。
- 表示は `TImage.Picture.Bitmap.Assign` を避け、`VideoMinerVideoSurface` の `TBitmap` を再利用する。`Present` は同期 `Update` ではなく `Invalidate` にする。
- `VideoMinerVideoSurface.PrepareBgrx32Frame` では `ScanLine[Height - 1]` を direct 出力先として渡す。`ScanLine[0]` は bottom-up Bitmap 前提の変換と合わず、`sws_scale-9.dll` の AccessViolation につながる。
- 映像が音声より遅れた場合は、小さな範囲でフレームドロップし、それでも追いつかない場合のみ音声位置へ映像シークする。大量の非表示デコードで一気に追いつかせる方針は避ける。
- Debug Win64 ビルドは成功済み。安定確認後の主なログでは、44.7 秒以降も `audio_pump` が継続し、`queue_full` や負の `queued_ms` は出ていない。
- 参照元の `D:\DelphiProg\VM_Media_Input` には、デコード改善として `CopyFrameToBitmapCached` と `FFmpegDecoder.pas` の Bitmap 変換キャッシュ利用だけを反映済み。音声シーク補助や VideoMiner 用の再生制御は、AviUtl 入力本体には現時点で反映不要。

### 表示高速化の現状

- `TImage.Picture.Bitmap.Assign` を使う表示経路は避け、`VideoMinerVideoSurface` の `TBitmap` を再利用する方針。
- 表示側は `DecodeFrameToBgrx32` / `DecodeNextFrameToBgrx32Optional` を使う direct 系へ寄せている。
- `VideoMinerVideoSurface.PrepareBgrx32Frame` で `pf32bit` の Bitmap を確保し、`ScanLine[Height - 1]` を direct 出力先として渡す。
- `ScanLine[0]` を渡すと `sws_scale-9.dll` で AccessViolation が出た。`CopyFrameToBgrx32Buffer` 側が bottom-up Bitmap 前提で、渡された先頭ポインタから内部で最終行へ調整するため、ここは `ScanLine[Height - 1]` が正しい。
- `DoubleBuffered := False` にして、動画サーフェス側の余分なコピーを減らしている。
- `CopyFrameToBitmapCached` も追加済み。従来 Bitmap 経路用に sws context を使い回すための保険として残っている。
- 2026-06-06 の高速化作業で、再生中の通常 tick ではシークバー進捗だけを軽く更新し、Caption/タイトルなどの情報更新は約 250ms 間隔へ間引いた。
- Debug ビルドでも再生中 hot path のログは既定 OFF にした。必要な場合は `VideoMinerDebugLog.pas` の `VIDEO_MINER_DEBUG_LOG_ENABLED` を一時的に True にして調査する。
- オーバーレイ非表示の通常再生時は、動画サーフェス全体を `FPaintBuffer` に合成してから転送する経路を避け、直接 `Canvas` へ描く。オーバーレイや下側シークバー表示時だけ従来どおりバックバッファを使う。
- 1 時間程度の動画終盤で重くなる症状は、音声キュー計算のサンプル位置が 32bit 計算で壊れ、`audio_pump` が毎 tick 余計に音声デコードしていたことが主因だった。
- 対策として、`TVideoMinerAudioPlayback` の `FStartSamples` / `FQueuedSamples` と、再生位置 ms からサンプル数へ変換する計算を `Int64` ベースにした。
- `FFmpegDecoderAudioRead.SeekAudioToMs` とシーク直後 discard の `FrameStartSample` 計算も `Int64` ベースへ変更した。長時間動画では `PositionMs * 48000` を `Integer` 計算に戻さない。
- 修正前ログでは `raw_queued_before_samples` と `queued_after_ms` が大きな負値になり、`playback_tick` の `pump_ms` が 50ms、100ms、200ms 以上に跳ねるケースがあった。修正後の体感では 1 時間動画終盤のカクつきは軽減した。

### シーク時の同期

- シークバーを再生中に動かした場合、以前は `ShowFrameAtMs` だけを呼んでいたため、映像だけ移動して音声は元位置のまま続いていた。
- 現在は再生中のシークバー操作では `SeekToMs` を通し、タイマー停止、音声停止、映像表示、必要なら再生再開を行う。
- シーク位置での映像と音声の同期は、現在の確認では正常。
- 音声再生用デコーダは別インスタンスなので、音声開始前に動画フレームを読むシークではなく、音声ストリームへ `SeekAudioToMs` するようにした。
- `SeekAudioToMs` 後は、シーク直後の先頭だけ target より前の音声サンプルを捨てるため `AudioDiscardUntilSample` を使う。

### GUI オーバーレイと 10 秒スキップ

- direct 系の動画表示へ通常の VCL コントロールを重ねず、`VideoMinerVideoSurface` 自身がオーバーレイ GUI を描く方針にした。
- オーバーレイ GUI の基底として `VideoMinerOverlay.pas` を追加した。
  - `TVideoMinerOverlayControl` は表示、レイアウト、描画、ヒットテスト、マウス入力の抽象基底。
  - `TVideoMinerOverlayButton` は hover / pressed / click を扱うボタン基底。
  - `TVideoMinerOverlayPlayPauseButton` は中央の半透明白い再生/一時停止ボタン。
  - `TVideoMinerOverlaySkipButton` は左右の数値なし曲線矢印ボタンで、10 秒戻し/10 秒進みに使う。
- オーバーレイ部品の位置とサイズは、フォーム全体ではなく動画のプレビュー表示領域を基準に割合で決める。
- 半透明描画は 32bit `TBitmap` に premultiplied alpha を入れ、`AlphaBlend` で合成する。
- 手動シークや一時停止中の 10 秒スキップは、再生用 `FDecoder` ではなく `FPreviewDecoder` で静止画を表示する。
- 再生開始時は再生用 `FDecoder` を開き直し、開始位置のフレームを表示してから音声再生を開始する。これにより、プレビュー用シークを繰り返した後の再生崩れを避ける。
- 10 秒戻し/進みの基準位置は、再生中は音声時計 `FAudioPlayback.PlaybackPositionMs`、一時停止中は現在の表示/シーク位置を使う。
- スキップで先頭より前へ行く場合は先頭フレーム、終端より後ろへ行く場合は duration ちょうどではなく FPS から推定した最終フレーム位置へ移動する。
- 指定位置のフレーム取得に失敗する動画があるため、手動表示では近傍時刻へのフォールバックを行う。
- direct seek では PTS 不明フレームを目的位置として採用しない。キーフレーム画像を誤って目的位置扱いするのを避けるため。
- シーク/スキップで音声を止める前に `waveOut` 出力音量を 0 に落とす。これにより、移動時のごく短い「ぷつっ」というノイズを抑える。
- 手動シーク表示は `PresentImmediate` で `Invalidate` 後に `Update` し、一時停止中でもフレーム画像を即時更新する。
- 2026-06-06 時点の安定版では、中央の再生/一時停止、10 秒戻し、10 秒進みの 3 アイコンは普段は非表示にする。
- 3 アイコンのいずれかの見えないヒット領域へカーソルが入った場合だけ、3 アイコンをまとめて表示し、クリックもその表示中だけ有効にする。
- hover / pressed 変化ではサーフェス全体を再描画せず、対象アイコン周辺だけ `InvalidateRect` する。これによりホバー時のちらつきを抑える。
- 10 秒戻し/進みのさらに外側に、先頭フレームへ移動する `|<` と最後付近のフレームへ移動する `>|` のオーバーレイボタンを追加した。
- 標準タイトルバーは外し、`bsNone` の枠なしフォームへ変更した。上部には自前のタイトルバーを配置し、ドラッグ移動、最小化、最大化/復元、閉じるボタンを実装した。
  - タイトル左側にはフォームまたはアプリのアイコンを表示する。
  - アイコン上のマウスドラッグもタイトルバー移動として扱う。
- 枠なしフォームでも端を掴んでリサイズできるよう、透明なリサイズエッジを配置する。
- アイコン群とは連動しない下側ツールグループとして、ホバー時だけ表示されるシークバーを `VideoMinerVideoSurface` のオーバーレイに追加した。
- シークバーは標準 `TTrackBar` ではなく、`TVideoMinerOverlaySeekBar` として 32bit Bitmap と `AlphaBlend` 系の自前描画で実装した。
- シークバーは半透明黒の角丸パネル上に、白いバー本体、再生済み部分、白い丸いつまみ、つまみ背後の半透明影を描く。
- シークバー下部には現在位置と動画全体の秒単位時間を `現在 / 全体` で表示する。1 時間未満は `M:SS`、1 時間以上は `H:MM:SS` 形式にする。
- シークバーのドラッグ完了時は既存の `SeekToMs` を呼ぶ。再生中シーク時の音声停止、プレビュー表示、再開予約などは既存経路へ集約する。
- シークバー追加後に hover 時のちらつきが目立ったため、`VideoMinerVideoSurface.Paint` は動画、中央アイコン群、下側シークバーを `FPaintBuffer` に一度描いてから画面へ転送するバックバッファ方式にした。
- フォームの通常ウィンドウ位置とサイズを `%APPDATA%\VideoMiner\VideoMiner.ini` に保存するようにした。
  - 設定保存先は exe 横ではなく、ユーザーごとの安全な AppData 配下に `VideoMiner` フォルダを作成して使う。
  - 起動時は必ず通常ウィンドウ状態で開始し、保存済みの位置とサイズだけを復元する。
  - 最大化、最小化、全画面状態は復元しない。
  - 終了時に最大化/最小化中でも、最後に把握している通常ウィンドウ時の位置とサイズを保存する。
  - 復元先が現在のモニター構成の作業領域から外れないよう、起動時に補正する。
- 最後に正常に開けたフォルダとファイルを `%APPDATA%\VideoMiner\VideoMiner.ini` に保存するようにした。
  - ファイルを正常に開けた時だけ `LastMedia` を更新する。
  - 引数なしで起動した場合は、保存済みの前回ファイルを再生せず開いた状態にする。
  - 前回フォルダや前回ファイルが存在しない場合は開かず、ステータス表示で理由を出す。
  - ファイル選択ダイアログは、現在ファイルのフォルダ、または最後に開いたフォルダを初期フォルダにする。
- `Source\Lib\ShortcutAction` をプロジェクトに追加し、キーボード操作を共通登録で扱うようにした。
  - `Ctrl+O` でファイルを開く。
  - `Space` で再生/停止を切り替える。
  - 左右キーで 10 秒戻し/進み、`Home` / `End` で先頭/末尾付近へ移動する。
  - `PageUp` / `PageDown` で前後ファイルへ移動する。
  - `Ctrl+Left` / `Ctrl+Right` はチャプター、先頭、終了フレームへの移動に使う。
- 全画面化と全画面解除を追加した。
  - `F11` で切り替える。
  - 全画面中は独自タイトルバーを隠し、モニター全体の bounds にフォームを広げる。
  - `Esc` は保険として全画面を強制解除する。
  - 下側ツールグループ右端に全画面ボタンを追加し、全画面中は通常ウィンドウへ戻ることが分かる解除アイコンに描き分ける。
- 左右端の前後動画ナビゲーションを追加した。
  - 動画表示矩形ではなくフォーム上の動画サーフェス全体を基準に、左右端へ見えないヒット領域を置く。
  - 左端 hover で前動画、右端 hover で次動画のシンプルな矢印を表示する。
  - クリック時は既存の `NavigateBy(-1 / 1)` を呼ぶ。
  - フォルダ一覧の先頭/末尾では該当側を無効化する。
- ショートカット操作を更新した。
  - `Left` / `Right` は前後動画へ移動する操作にした。
  - `Up` / `Down` で音量を 5% ずつ上下する。
  - `M` でミュートを切り替える。
  - 動画面のダブルクリックで全画面化し、全画面中のダブルクリックで解除する。
- 2026-06-16 に、前後動画へのキー移動でキーリピートやメッセージキューに残った入力が後続動画へ次々処理されないようにした。
  - 動画切り替え直後に残っている `Left` / `Right` / `PageUp` / `PageDown` のキー入力を捨てる。
  - 物理キーを押しっぱなしにしている間は、対象キーのリピートを `KeyUp` まで無視する。
  - 読み込み完了直後の残留キーを避けるため、短時間だけナビゲーションキー入力をブロックする。
- 下側ツールグループへ音量表示と簡易音量調整を追加した。
  - 再生時間表示の左側に `Vol n%` と小さな音量バーを表示する。
  - 音量バーは `Vol n%` の下に配置し、文字と重ならないコンパクトな音量ブロックにした。
  - 音量バーのクリック/ドラッグで `FAudioPlayback.VolumePercent` を変更する。
  - 音量ブロックの右側にミュートボタンを追加した。
  - ミュートボタンは既存の `M` キー操作と同じ経路で `FAudioPlayback.Muted` を切り替える。
  - ミュート中はスピーカーアイコンに斜線を表示し、音量バー操作や上下キーで音量変更した場合はミュート解除する。
- 下側ツールグループの全画面ボタン左に、再生終了時の動作ボタンを追加した。
  - 状態は `Stop` / `Loop` / `Next` の 3 種類。
  - クリックするたびに `Stop -> Loop -> Next -> Stop` の順で切り替える。
  - `Stop` は再生終了後にそのまま停止する。
  - `Loop` は現在位置を含むチャプター区間を繰り返し再生する。
  - チャプターがない場合は、従来通り先頭から最後付近までをループする。
  - `Next` はフォルダ内の次動画へ移動して再生する。次動画がない場合は停止する。
  - 状態は `%APPDATA%\VideoMiner\VideoMiner.ini` の `[Playback] EndAction` に `stop` / `loop` / `next` として保存し、次回起動時に復元する。
- 枠なしフォームのサイズ変更に対応した。
  - 見た目は `bsNone` の独自タイトルバーのまま、標準の太枠を出さずに透明リサイズエッジを使う。
  - `WM_NCCALCSIZE` で Windows 標準の非クライアント枠を表示領域に出さないようにする。
  - `Source\Lib\ResizeEdges\ResizeEdges.pas` を使い、フォーム端/角に透明な `TLabel` ハンドルを置いて `SC_SIZE` を送る。
  - `ResizeEdges` の透明ハンドルはウィンドウ付きコントロールの上へ重ねられないため、上端は `PanelTitleBar`、左右/下端は動画サーフェスへ attach する。
  - サイズ変更後は `TResizeEdgeHelper.AdjustEdges` でタイトルバー側と動画サーフェス側の透明エッジを再配置する。
  - これにより動画サーフェスなどの子コントロールが端まで覆っていても、通常ウィンドウでは端や角を掴んでサイズ変更できる。
- ズーム表示とパン操作を追加した。
  - 映像表示部分上のマウスホイールで拡大縮小する。
  - 下側ツールバー上ではホイールによる映像ズームを行わず、ツールバー側の操作領域として扱う。
  - 拡大はカーソル位置を基準にし、見ている箇所へ自然に寄るようにする。
  - 拡大中は映像表示部分の左ドラッグで表示位置を移動する。
  - 下側ツールバー、中央操作ボタン、左右ナビゲーション上では既存のオーバーレイ操作を優先し、パン操作と衝突させない。
  - 新しい動画を開く、または表示をクリアした場合は等倍表示へ戻す。
- オーバーレイ GUI の見た目を調整した。
  - 中央付近の 5 アイコンは、中心 X 座標を共通ステップで `-2, -1, 0, +1, +2` に並べ、X 座標間隔を揃えた。
  - 左右端の前後ファイルナビゲーションは横幅を縮め、縦長の表示領域にした。
  - 左右端の矢印背後に黒い半透明の縦長背景を描き、動画の明るさに関係なく矢印を見やすくした。
- 2026-06-07 の表示/操作調整。
  - 下側ツールグループの高さを少し増やし、時間表示がバーやつまみ影に近づきすぎないようにした。
  - 時間表示、音量表示、再生終了時動作、全画面ボタンを下段行に揃えた。
  - 左右端の前後動画ナビゲーション背景を端まで描き、矢印が端から浮いて見えないようにした。
  - 動画面の通常シングルクリックで再生/停止を切り替えるようにした。
  - ダブルクリック全画面と衝突しないよう、シングルクリックは `GetDoubleClickTime + 20ms` 待ってから確定する。
  - シークバー、表示中の中央/端オーバーレイ、左右ナビゲーション上のクリックは各オーバーレイ操作を優先する。
- ボスが来た機能を追加した。
  - `Source\App\VideoMinerBossGesture.pas` を追加し、ボスが来たモードへ入るためのマウス往復ジェスチャー検出を分離した。
  - `Source\App\VideoMinerBossOverlay.pas` を追加し、動画を隠す VSCode 風の偽装画面描画を分離した。
  - マウスボタンを押していない状態で、短時間に左右/上下へ大きく往復した場合にボスが来たモードへ移行する。
  - 方向反転型の検出に加え、A 点から B 点へ離れて A 点付近へ戻る A-B-A 型の検出も併用する。
  - ジェスチャーの有効時間、必要移動量、クールダウン、A-B-A の距離/戻り半径は `BOSS_GESTURE_*` const で調整できる。
  - ボスが来たモードへ入る時は `StopPlayback` を通して再生と音声を止め、動画サーフェスは偽装画面だけを描く。
  - ボスが来たモード中は `Esc` 以外のショートカットを無効化する。
  - 解除は `Esc` または偽装画面右下の `Return` ボタンで行う。
  - 偽装画面は複数パターンのタブ/コード/ステータス表示を持ち、発動タイミングごとに見え方が少し変わる。
  - 2026-06-07 時点で、ボスが来た機能まわりの追加調整は終了扱いとする。
- メインフォーム肥大化防止の第一段として、GUI そのものではない処理を一部別ユニットへ移した。
  - `Source\App\VideoMinerWindowChrome.pas` を追加し、枠なしフォームの作成パラメータ、非クライアント領域調整、リサイズヒットテスト、ウィンドウ位置復元/記憶を担当させる。
  - `Source\App\VideoMinerShortcutBindings.pas` を追加し、キーボードショートカットの割り当て表を担当させる。
  - `VideoMinerMainForm` は該当処理を呼び出す側に寄せ、今後もフォームは GUI イベントの受け口を中心に保つ方針。
- 動画編集者用チェック機能の第一段を追加した。
  - 下側ツールグループに `+` / `-` / `Check` ボタンを追加した。
  - `+` は現在位置へ手動チャプターを追加する。
  - `-` は現在位置から近い手動チャプターを削除する。
  - 手動チャプターは緑マーカーとしてシークバー上に表示する。
  - 手動チャプターは動画ファイルのフルパスをキーにして `%APPDATA%\VideoMiner\VideoMiner.ini` へ保存し、同じ動画を開いた時に復元する。
  - `Check` ON 中は、再生で実際に表示したフレームの四隅を軽量サンプリングして暗いフレーム区間を検知する。
  - 自動チェック結果は黄色/赤マーカーとしてシークバー上に表示する。
  - 自動チェック由来のチャプターは一時的な候補扱いで、保存対象にはしない。
  - `Check` OFF 中は自動チェック由来のチャプターを表示/移動対象から外す。
  - `Ctrl+Left` / `Ctrl+Right` は、前後のチャプター、または先頭/終了フレームへ移動する。
  - 終了時動作が `Loop` の場合は、現在位置を含むチャプター区間をループする。例: `先頭 - A - B - 終了` で A-B 間から再生した場合は、B まで再生したあと A へ戻る。
  - ループ戻り時に一部データで黒表示が残る場合があるが、現状はデータ依存の可能性が高いため保留する。
- 2026-06-16 に、下側シークバー上のホイール操作を追加した。
  - シークバー上ではホイールを動画ズームではなくシーク操作として扱う。
  - 通常時は 1 秒単位で移動する。
  - `Check` ON 中はフレーム確認を優先し、FPS から計算した 1 フレーム目安の ms で移動する。
  - ホイールシークは再生再開せず、一時停止状態で移動先フレームを表示する。
  - `Check` ON 中のシークバー下部表示は、正確なフレームテーブルではなく操作目安として `Frame n / total` の概算表示にする。
- Check 機能の担当ユニット:
  - `Source\App\VideoMinerOverlay.pas`
    - `TVideoMinerOverlaySeekBar` が `Check` / `+` / `-` ボタンのヒットテスト、押下状態、描画、クリックイベント発火を担当する。
    - `TVideoMinerOverlayChapter` / `TVideoMinerOverlayChapters` / severity / source 型を持ち、シークバー上の緑/黄/赤マーカーを描画する。
  - `Source\App\VideoMinerVideoSurface.pas`
    - `CurrentFrameCornersMostlyDark` が現在表示中の `FBitmap` の四隅をサンプリングし、暗いフレームかどうかを判定する。
    - `CheckEnabled` と `Chapters` はシークバーへ渡す表示状態として扱う。
  - `Source\App\VideoMinerVideoView.pas`
    - メインフォームと動画サーフェスの間の薄い窓口。`CurrentFrameCornersMostlyDark`、`CheckEnabled`、`Chapters`、Check 関連クリックイベントを中継する。
  - `Source\App\VideoMinerChapterManager.pas`
    - チャプター配列、Check ON/OFF 状態、暗いフレーム継続時間、自動チェックマーカー統合、表示用チャプター抽出を担当する。
    - 手動チャプターの追加/削除、保存/復元、チャプター移動先、ループ区間境界の計算もここへ移した。
    - loop segment は `TVideoMinerLoopSegment` と `LoopSegmentForPosition` で start/end をまとめて返す。個別の `LoopSegmentStartPositionMs` / `LoopSegmentEndPositionMs` は manager 内部の private helper にした。
  - `Source\App\VideoMinerMainForm.pas`
    - Check ボタンイベント、現在再生位置、現在フレームの暗さ判定結果を `VideoMinerChapterManager` へ渡す。
    - Manager から表示用チャプターを受け取り、`VideoMinerVideoView.Chapters` へ反映する。
  - `Source\App\VideoMinerSettings.pas`
    - 手動チャプター位置だけを `%APPDATA%\VideoMiner\VideoMiner.ini` に保存/復元する。現状、自動チェック結果は保存しない。
- メインフォーム肥大化防止の追加分割:
  - `Source\App\VideoMinerFrameCheck.pas`
    - `FrameCornersMostlyDark` で `TBitmap` の四隅サンプリング判定を担当する。
    - `VideoMinerVideoSurface.CurrentFrameCornersMostlyDark` はこの関数へ委譲するだけにした。
  - `Source\App\VideoMinerMediaOpen.pas`
    - ファイル名/フォルダ/存在チェック、メイン/プレビューデコーダ open、フォルダ内メディアリスト構築を担当する。
    - ファイル選択ダイアログの初期フォルダ決定、前回ファイル保存、前回ファイルの解決/検証もここへ移した。
    - `VideoMinerMainForm.LoadVideoFile` は UI 状態リセット、タイトル/情報更新、初期フレーム表示、再生開始に寄せた。
    - 存在しないファイルを指定した場合に現在状態を壊さないよう、`ValidateVideoMinerMediaFile` はリセット前に呼ぶ。
  - `Source\App\VideoMinerWindowModeController.pas`
    - fullscreen / boss mode / window bounds / maximize button 表示 / borderless resize hit-test / move-size 時の通常ウィンドウ bounds 記憶を担当する。
    - `VideoMinerMainForm` 側の `FFullScreen` / `FBossMode` / `FNormalWindowBounds` は削除し、状態はこの controller が所有する。
    - main form の `BossGesture` / `BossExitClick` / `WMNCHitTest` / `WMMove` / `WMSize` / ESC キー処理は controller 呼び出しへ寄せた。
  - `Source\App\VideoMinerCommandController.pas`
    - overlay click / seek / volume change / shortcut action の受け口を担当する。
    - main form は open / seek / navigate / playback などの実処理 callback を渡し、controller が `VideoMinerVideoView` のイベントと `ShortcutAction` 登録を束ねる。
    - main form 側の `FirstFrameOverlayClick` / `LastFrameOverlayClick` / `Navigate*OverlayClick` / `Skip*OverlayClick` / `SeekBarSeek` / `FullScreenOverlayClick` / `MuteOverlayClick` / `VolumeOverlayChange` / `Shortcut*` / `ChangeVolumeBy` / `TogglePlayPause` は削除した。
  - `Source\App\VideoMinerPlaybackTiming.pas`
    - FPS から timer interval / 最終フレーム位置を計算する処理を担当する。
    - 音声同期の遅れ判定、ドロップ継続可否、終端付近判定、逆戻りフレーム判定、seek guard 許容判定、seek guard 初期フレーム数もここへ移した。
    - 次に再生制御を分ける場合は、このユニットの純粋判定を使いながら `TimerPlaybackTimer` / `StartPlaybackAtMs` / `SeekToMs` を少しずつ薄くする。
  - `Source\App\VideoMinerPlaybackController.pas`
    - 再生制御分離の担当ユニット。
    - `ActiveOrPending` / `StopPlayback` に加えて、seek 中断用の `StopForSeek`、再開予約の `ScheduleRestart`、再開 timer からの `ConsumeRestart` を担当する。
    - 再開待ち state は main form ではなく controller が所有する。main form 側の `FRestartState` / `FPendingRestartPlayback` / `FPendingRestartMs` は不要になった。
    - `StartPlaybackAtMs` / `StartAtMs` は再生開始、音声開始、現在位置更新、ループ区間更新、seek guard 設定を担当する。
    - `SeekToMs` は seek 前の停止、プレビューフレーム表示、現在位置更新、seek guard 設定、必要時の再開予約、seek ログ出力を担当する。
    - `ShowFrameNearMs` は指定位置のフレーム表示を試し、失敗時に前後の近い位置へ fallback する。
    - `FinishAtEnd` は再生終端時の `Stop` / `Loop` / `Next` 分岐を担当する。
    - `TimerPlaybackTimer` の入口にある seeking 判定、動画有無判定、audio pump、音声位置 clamp は `PrepareTick` へ移動した。
    - `TimerPlaybackTimer` 内の次フレーム decode と失敗時停止は `DecodeNextFrame` へ移動した。戻り値は frame / end-of-stream / error の3択。
    - 音声位置への同期処理は `SyncVideoToAudio` へ移動した。
    - seek guard の表示/破棄判定は `HandleSeekGuard` へ移動した。
    - 音声より映像が遅れたときの drop / `ShowFrameAt` 分岐は `HandleLaggingVideo` へ移動した。
    - scratch frame の逆戻り破棄ログは `ShouldDropBackwardScratchFrame`、scratch frame 表示は `PresentScratchFrame` へ移動した。
    - `Tick` は再生中の 1 tick 全体を担当し、main form の `TimerPlaybackTimer` は `Tick` を呼ぶだけにした。
    - `Tick` 後半の loop 区間到達判定は `ShouldRestartLoop`、seek bar 反映位置の計算は `SeekPositionForTick`、lag 計算は `PlaybackLagMs`、tick ログは `LogPlaybackTick` へ移動した。
    - `CurrentPlaybackPositionMs` の位置決定は `CurrentPositionMs`、end action の表示文字列は `EndActionText`、end action の順送りは `NextEndAction`、終端時の分岐判定は `FinishResult`、終端停止時の view 状態変更は `StopAtEnd` へ移動した。
    - `ConfigureLoopSegment` は chapter manager の `LoopSegmentForPosition` を使って loop 区間を更新する。
    - main form 側の `TimerPlaybackTimer` / `SeekToMs` / `StartPlaybackAtMs` / `FinishPlaybackAtEnd` は controller への委譲入口になった。

### メインフォーム分散化の現在地

- 2026-06-11 時点で、`VideoMinerMainForm.pas` は 1017 行。
- この段階の方針は、main form を「GUI イベント入口」「フォーム固有の状態反映」「controller への委譲」に寄せること。
- 追加済みの主な分散先:
  - `VideoMinerCommandController.pas`
    - overlay click、seek bar 操作、volume/mute、shortcut 登録と実行を担当する。
    - main form は open / seek / navigate / playback などの実処理 callback を渡す。
  - `VideoMinerWindowModeController.pas`
    - fullscreen、boss mode、window bounds、maximize 表示、borderless resize hit-test、move/size 時の bounds 記憶を担当する。
  - `VideoMinerPlaybackController.pas`
    - 再生開始、停止、seek、再開予約、再生 tick 全体、同期、seek guard、tick ログ、end action 分岐を担当する。
  - `VideoMinerChapterManager.pas`
    - chapter/check 状態、手動 chapter 保存/復元、自動 check marker、chapter navigation、loop segment 計算を担当する。
- main form から削除済み:
  - `FFullScreen` / `FBossMode` / `FNormalWindowBounds`
  - overlay の単純 click handler 群
  - shortcut 用の `Shortcut*` 群
  - volume/mute の直接処理
  - 再生再開待ち state
  - 再生 tick の実処理
  - seek の実処理
  - 再生開始後の現在位置/loop segment/seek guard 更新
  - 再生終端時の stop/loop/next 分岐
- 今後機能追加する場合:
  - まず新機能の担当 controller/manager を決めてから実装する。
  - main form へ直接ロジックを書かず、イベント入口から controller/manager へ渡す。
  - 動画チェック機能を増やす場合は、まず `VideoMinerChapterManager` か新しい check 専用 manager に責務を寄せる。
  - UI 操作だけ増える場合は `VideoMinerCommandController`、表示状態だけ増える場合は `VideoMinerVideoView`/overlay 側に寄せる。

### 解消済みの同期問題

- 2026-06-06 の確認では、再生中に音声と映像がだんだんズレる症状は解消した。
- 以前は約 44.7 秒付近から音声キュー判定が壊れ、音声が止まる、または音声位置が正しく扱えなくなる症状が出ていた。
- 原因は `PlaybackPositionMs * AUDIO_OUTPUT_SAMPLE_RATE` が 32bit `Integer` 計算になり、`44700 * 48000` 付近でオーバーフローしていたこと。
- 対策として `PlaybackSamplePosition`、`PlaybackSampleCount`、`RawQueuedSampleCount`、`queued_ms` 計算を `Int64` ベースにした。
- 修正後のログでは、以前止まっていた 44.7 秒以降も `audio_pump` が継続し、`queue_full` や負の `queued_ms` は出ていない。
- 修正後の確認ログでは `lag_ms` はおおむね `-30..30` ms の範囲で、再生中に差が蓄積する挙動は見られない。
- `audio_pump` に 45ms 程度の一時的なスパイクはあるが、音声キューは約 960..1010ms で維持されており、現時点では同期ズレの原因ではなさそう。

### デコード系の完成状態

- 2026-06-07 時点で、動画デコード、音声再生、シーク、ループ再生まわりは完成扱いとする。
- ループ再生と再生中シークでは、同じファイルの動画デコーダと音声デコーダをできるだけ開き直さず再利用するようにした。
  - これにより、ループやシーク移動後の停止時間はかなり短くなった。
  - 音声側は出力だけ止める `StopOutput` と、デコーダも閉じる `Stop` を使い分ける。
- ループやシーク直後に、移動前のフレームが一瞬表示される問題を解消した。
  - 原因は、シーク直後の順方向デコードで、デコーダが古い終端付近のフレームを数枚返すことがあるため。
  - `StartPlaybackAtMs` 後にシークガードを設定し、最初の数フレームは表示前に位置を検査する。
  - 目標位置から大きく外れたフレームは `seek_guard_drop` として表示せず破棄する。
  - 確認では `9800ms` / `9833ms` の古い終端フレームが表示されず、先頭 `0ms` から再開できた。
- 音声なしの短い動画で、開始直後にシーク位置が前後する問題を解消した。
  - 対象例は `freepik__video-generator__93161.mp4`。
  - 原因は開始直後の PTS が `42 -> 125 -> 167 -> 0 -> 42...` のように非単調に返ること。
  - 音声なし再生では次フレームを一度スクラッチバッファへデコードし、現在位置より戻るフレームは表示せず破棄する。
  - 確認では表示 tick が `42 -> 125 -> 167 -> 167 -> 208 -> 250...` となり、シークバーの後退は出なくなった。
- `VideoMinerDebugLog.pas` のログ出力は調査時だけ `True` にし、通常状態では `False` に戻す。

### ループ時の再生位置復元

- 2026-06-12 に、手動チャプターがあり、かつ終了動作がループモードの動画だけ、再生位置を保存して次回読み込み時に復元するようにした。
- 保存先は手動チャプターと同じ INI の `ManualChapters:<絶対パス>` セクションで、キーは `PlaybackPositionMs`。
- `VideoMinerSettings.pas` に `LoadManualChapterPlaybackPosition` / `SaveManualChapterPlaybackPosition` / `ClearManualChapterPlaybackPosition` を追加した。
- `VideoMinerChapterManager.pas` に `HasManualChapters` を追加し、復元条件の判定はメインフォームからこのメソッドを使う。
- `SaveManualChapterPositions` はセクションを一度 `EraseSection` するため、再生位置を保持したい場合は必ず `SaveManualChapterState` の後に `SaveLoopPlaybackPosition` を呼ぶ。
- ループモードではない、または手動チャプターがなくなった場合は、古い `PlaybackPositionMs` を削除して誤復元を防ぐ。
- ファイル切り替え時とフォーム終了時の両方で保存するため、アプリ終了だけでなく次の動画へ移る場合も現在位置を失いにくい。

### 外部更新の自動再読み込み

- 2026-06-12 に、現在開いている動画ファイルの外部更新を検知して自動再読み込みする処理を追加した。
- `Source\Lib\FolderWatch\FolderWatch.pas` を `VideoMiner.dpr` / `VideoMiner.dproj` に登録し、現在開いている動画のフォルダを監視する。
- `TVideoMinerMainForm` に `TFolderWatch` と `FReloadCurrentFileTimer` を持たせ、`OnFileChange` で現在ファイルが含まれる場合だけ再読み込み候補にする。
- 更新イベントでは即座に開き直さず、`CURRENT_FILE_RELOAD_SETTLE_MS = 1500` のタイマーを使って連続更新をまとめる。
- タイマー発火後も、更新日時とファイルサイズが次回確認で同じになるまで待つ。出力中で読めない場合も、タイマーを再開して待つ。
- 更新日時とサイズが、動画を開いた時に記録した値から変わっていれば、外部更新されたものとして `LoadVideoFile(FileName, False, False)` で読み込み直す。
- 外部更新リロードでは、ループ位置復元を使わず先頭フレームを表示する。
- `Check` の ON/OFF、音量、終了動作などの設定状態は維持する。
- `FChapterManager.Clear` により自動チェックの一時的な警告チャプターは削除される。手動チャプターは保存状態から再読み込みされる。
- 再読み込み中の監視イベントで再帰的に処理しないよう、`FReloadingCurrentFile` でガードする。
- `FolderWatch.pas` は今回ビルド対象になったため、既存の未使用ローカル変数 `FilePath` を `ScanAndCompare` から削除した。
- Git の CRLF 警告対策として `.gitattributes` を追加し、Delphi/Markdown などのテキストは `eol=crlf`、画像や `.res` などは binary に固定した。

### 試したが注意が必要なこと

- 音声位置に追いつかせるため、表示なしで大量に `DecodeNextFrame(..., ConvertFrame=False)` を回す処理を入れたが、音声だけ先に進み、後から映像が早送りで表示される挙動になったため外した。
- 音声あり動画だけ `TimerPlayback.Interval := 5` にする処理も入れたが、上記の早送り挙動と絡むため外した。
- 音声フレームごとに PTS を見て毎回サンプルをトリムする処理は、音をガビガビにする可能性があるため、シーク直後だけに限定した。
- `SampleCount := FrameStartSample` のように、実際に waveOut へ投入していない時間ぶん音声時計だけ進める処理は、音声先行の原因になるため避ける。

### 次に見る場合の確認点

- 現状は安定しているため、同期処理を大きく変える必要はない。
- もし再び音飛びや同期ズレを見る場合は、まず `%TEMP%\VideoMiner_playback_debug.log` の `audio_pump`、`playback_tick`、`seek`、`audio_start` を確認する。
- `audio_pump` では `queued_before_ms`、`queued_after_ms`、`raw_queued_before_samples` が負になっていないかを見る。
- `playback_tick` では `lag_ms` が継続的に増え続けていないか、`drop_count` と `seek_to_audio` が暴れていないかを見る。
- `seek` では再生中シーク時に `was_playing=True` になり、古い再開予約が残っていないかを見る。
- さらなる改善を行う場合は、先に Debug ログ量を絞る。現状は調査用に出力が多い。

## 今後の作業

優先して進めること:

- 動画編集者用チェック機能を育てる。
  - シークバー上のチャプタークリック移動を追加する。
  - チャプターへマウスを近づけた時の hover 強調や、`-` ボタンで削除される対象の可視化を検討する。
  - 手動チャプターへメモや色変更を付けるか検討する。
  - 自動チェックのしきい値、サンプリング位置、誤検知抑制を実動画で調整する。
  - チェック結果の一覧表示や外部出力を検討する。

### チェック機能の今後の優先順位

VideoMiner のチェック機能は、以下を主目的にする。

- 編集ミスを発見する。
- 最終確認にかかる時間を短縮する。
- チャプターで怪しい場所へすぐ飛べるようにする。

2026-06-12 時点では、検知系は実用ラインまで一通り実装済み。

現在の自動チェック:

- 黒フレーム検出。
  - フレーム四隅の暗さから、無表示に近い区間を検知する。
  - 短い候補は黄色、長めの候補や終端付近の候補は赤。
- 無音区間検出。
  - 音声トラック消失、素材配置ミス、ミュート出力の候補を検知する。
  - 動画冒頭の無音は画面録画などで自然に起きやすいため、赤ではなく黄色に抑える。
- 左右チャンネル異常検出。
  - 左だけ無音、右だけ無音、左右の音量差が極端な区間を検知する。
- フレーム差分異常検出。
  - 前後フレームは似ているのに、1 フレームだけ大きく違う候補を検知する。
  - シーン切替との誤検知を避けるため、前後が安定している単発候補だけを黄色で扱う。
- 音量急変検出。
  - 前後の音声ブロックと比べて、音量が急に大きくなる、または小さくなる候補を検知する。
  - 通常の演出でも起きるため、基本は黄色中心で扱う。
- クリッピング検出。
  - 音声ピークが上限付近に張り付いた音割れ候補を赤で検知する。

チャプター色:

- 緑: 手動チャプター。
- 黄色: 注意候補。自然な編集や素材内容でも発生し得るため確認対象。
- 赤: 危険候補。黒画面の継続、終端付近の黒、長い無音、左右チャンネル異常の継続、クリッピングなど。

今後は検知種類の追加より、検知結果を人間が使いやすくする UI を優先する。

優先して進めたいこと:

- チャプター種別の表示。
  - 黒、無音、左右、差分、音量、音割れなど、何の異常で付いたチャプターなのか分かるようにする。
- チャプターへジャンプした時の短い理由表示。
  - 例: `無音区間`、`左右チャンネル異常`、`音量急変`。
- 検知種類ごとの ON/OFF。
  - 映像だけ見る、音声だけ見る、音量急変は切る、などを可能にする。
- しきい値設定。
  - 最初は固定値でよいが、実動画で誤検知が見えてきたら設定化する。
- チェック結果の一覧表示や外部出力。
  - チャプターだけではなく、候補を一覧で見て作業できるようにする。

追加検出をさらに行う場合は、計算負荷が軽く、誤検知が少なく、チャプター方式と相性がよいものを優先する。

優先度 S:

- 黒フレーム検出。
  - 既に実装済み。
  - 検出率が高く、誤検知も少ない。
- 無音区間検出。
  - 音声トラック消失、素材配置ミス、ミュート出力の発見に有効。
  - 音量計算だけで済むため軽い。
- 左右チャンネル異常検出。
  - 左だけ無音、右だけ無音、極端な音量差などを検出する。
  - 人間が見落としやすく、負荷は無音検出と同程度。

優先度 A:

- フレーム差分異常検出。
  - 前フレームとの差分から、単発異常フレーム、ノイズフレーム、1 フレーム混入を検出する。
  - シーン切替と誤検知しやすいため、重要度 B から C の候補として扱う。
- 音量急変検出。
  - BGM だけ急に大きくなる、音声だけ急に小さくなる、といった編集ミスの検出に使う。
- クリッピング検出。
  - 音割れの簡易検出。
  - ピーク値を見るだけで実装できる。

優先度 B:

- 長時間静止画検出。
  - フリーズや画像差し替え忘れの検出に使う。
  - 解説動画や立ち絵動画では誤検知が多い。
- 長時間黒画面検出。
  - 黒フレーム検出とは別に、数秒以上続く黒画面を検出する。
- 白フレーム検出。
  - 黒フレーム検出の派生。
  - 発生頻度は低いが、編集ミスとして起きることがある。

優先度 C:

- 色変化異常。
  - 色空間変換ミスの候補検出。
  - 発生頻度が低い。
- 長時間一定音検出。
  - ホワイトノイズやハムノイズの候補検出。
  - 誤検知が多い。
- 音声波形異常。
  - プチノイズ候補の検出。
  - 検出精度が低い。

優先度 D:

- FFT 系解析。
  - スペクトラム解析により、ホワイトノイズ、ハムノイズ、周波数異常などを検出する。
  - 実装コストに対して得られる効果が小さいため、当面は優先しない。

検知追加を再開する場合は、`長時間静止画検出`、`白フレーム検出`、`長時間一定音検出` あたりが候補。ただし、いずれも現在実装済みの検知より誤検知が増えやすいか、発生頻度が低いため優先度は下げる。
- メインフォームを含めたユニット肥大化を防ぐ。
  - GUI イベント受け口、再生制御、ウィンドウ制御、ショートカット、設定、メディア管理の責務を必要に応じて分ける。
  - 大きな機能追加前後に、フォームへ処理が集まりすぎていないか確認する。
- ボスが来たモードの偽装表示は改善の余地がある。
  - 現状の `VideoMinerBossOverlay.pas` は静的な VSCode 風画面を描くだけで、緊急時に自然に見える表示としてはまだ作り込み不足。
  - 今後見直す場合は、画面サイズごとの情報密度、実作業中らしさ、解除ボタンの目立ちすぎ防止、文字や行の自然さを調整する。
- 映像再生が少しカクつくことがある。
  - 現状は同期ズレではなく、描画/デコード/タイマー周りの負荷や間隔が原因の可能性がある。
  - 調査する場合は `%TEMP%\VideoMiner_playback_debug.log` の `playback_tick`、`paint`、`decode_ms`、`paint_ms`、`timer_interval` を確認する。
  - まずはログ量を絞り、描画負荷とフレーム取得間隔のどちらが支配的かを見る。
- アプリ本体で使わない既存補助ユニットの必要性を整理し、不要なら外す。

### サムネイル一覧モードの実装優先順位

動画フォルダを素早く見渡して目的の動画へ移動するため、再生画面とは別にサムネイル一覧モードを追加する。
最初から高度なダイジェストや永続キャッシュまで作り込まず、既存の再生処理へ影響を出しにくい入口、一覧、タイル表示、クリック切り替えを先に安定させる。

実装優先順位:

1. サムネイル一覧モードの入口を作る。
   - 再生画面とは別モードとして用意する。
   - キー操作で表示/非表示を切り替える。
   - 例: `Tab` で一覧表示、`Esc` で閉じる。
   - 最初はオーバーレイでも別ページ風でもよい。
   - 既存の再生処理にはできるだけ影響させない。
2. 同一フォルダ内の動画ファイル一覧を取得する。
   - 現在再生中の動画と同じフォルダを対象にする。
   - 対象拡張子は既存の再生対応形式に合わせる。
   - 現在再生中のファイル位置も特定する。
   - 左右キー移動の既存リストと共通化できるなら共通化する。
3. タイル表示の基本レイアウトを作る。
   - 一覧画面にサムネイル枠をタイル状に並べる。
   - まずは画像なしの枠だけでよい。
   - ファイル数が多い場合にスクロールできるようにする。
   - 現在再生中のファイルだけ分かるようにする。
4. 10% 地点の 1 フレームをサムネイル化する。
   - 動画時間の 10% 地点を代表フレームにする。
   - 取得位置が早すぎる場合は最低 0.5 秒程度にする。
   - 短い動画では中央付近に逃がす。
   - 取得失敗時は先頭、または中央で再試行する。
   - 透過動画の場合は市松模様背景に合成する。
5. サムネイル画像をタイルに表示する。
   - 取得した画像をタイル内に収めて描画する。
   - アスペクト比は維持する。
   - 余白は黒または暗めの背景でよい。
   - この時点で一覧から動画を見分けられる状態にする。
6. ファイル名をサムネイル画像内に重ねる。
   - サムネイル下部に半透明帯を描く。
   - その上にファイル名を表示する。
   - 長いファイル名は省略表示する。
   - 別テキスト行として縦幅を増やさない。
7. クリックで動画を切り替える。
   - サムネイルをクリックすると、その動画を再生対象にする。
   - 一覧を閉じて通常再生画面へ戻る。
   - 既存の左右キー移動と同じ内部処理に流す。
   - 読み込み失敗時は一覧に戻るか、エラー表示する。
8. ホバー時の表示強調を入れる。
   - 通常時は少し暗く表示する。
   - ホバー中は標準の明るさにする。
   - 現在再生中の動画は枠線などで常時強調する。
   - ホバー中と現在再生中が重なった場合も分かるようにする。
9. メモリキャッシュを入れる。
   - 一度生成したサムネイルはメモリ上に保持する。
   - 同じ一覧を開き直したときに再生成しない。
   - ファイルパス、更新日時、サイズをキーにする。
   - ファイルが更新されていたら作り直す。
10. 遅延生成にする。
    - 一覧表示時に全動画を一気に処理しない。
    - 画面に見えているタイルから順に生成する。
    - スクロールで表示された分を追加生成する。
    - 重い MOV や長い動画で固まらないようにする。
11. 生成中・失敗時の仮表示を入れる。
    - 生成待ちのタイルには簡易アイコンや `読み込み中` を表示する。
    - 失敗した動画は失敗マークを表示する。
    - 失敗しても一覧全体を止めない。
12. 操作性を整える。
    - マウスホイールで一覧スクロールできるようにする。
    - ダブルクリックで再生でもよいが、基本はクリックで十分とする。
    - キーボードの上下左右でタイル選択できるようにする。
    - `Enter` で再生する。
    - `Esc` で閉じる。
    - 一覧を開いた時点で現在の動画へスクロール位置を合わせる。

サムネイル生成方針:

- サムネイルは元動画の解像度そのままでは作らない。
- 動画のアスペクト比を維持したまま、固定の最大サイズに縮小して生成する。
- 最初は最大 320x180 程度を基本とする。
- 高 DPI や大きめ表示を考慮する場合は、将来的に 480x270 も選択肢とする。
- 表示時はタイル枠に合わせて縮小または拡大して描画する。
- 表示時もアスペクト比は維持する。
- 余白が出る場合は暗色背景で埋める。
- 縦動画や正方形動画もあるため、無理に 16:9 へ切り抜かない。
- 透過動画の場合は、サムネイル生成時点で市松模様背景に合成した画像を作る。
- 一覧表示では、その生成済みサムネイル画像を通常画像として描画する。
- サムネイル生成、キャッシュ、遅延生成の実処理は専用ユニットへ寄せる。
- `VideoMinerMainForm.pas` は一覧モードの表示切り替えと既存処理への橋渡しだけに留め、引き続き肥大化させない。

後回しでよい機能:

- ホバー時ダイジェスト。
  - ホバー中だけ複数フレームを紙芝居表示する。
  - 候補位置は 10%、25%、40%、55%、70%、85% など。
  - 最初は実装せず、基本のサムネイル一覧が安定してから検討する。
- ディスクキャッシュ。
  - 起動をまたいでサムネイルを保持する。
  - キャッシュ削除や更新判定が必要になる。
  - 便利だが最初から入れると管理が重い。
- Alpha 表示バッジ。
  - アルファ付き動画に `Alpha` 表示を重ねる。
  - 透過 MOV 確認には便利。
  - 基本一覧ができてからでよい。
- 詳細情報表示。
  - 解像度、時間、コーデック、ファイルサイズ、作成日時などを表示する。
  - 便利だがサムネイル一覧の本体ではないため後回しでよい。

設計メモ:

- VideoMiner は「出力する」よりも「見る」「探す」「確認する」を中心にする。
- ファイルを開いた瞬間に、そのフォルダ全体を作業対象として扱う。
- ユーザーがファイル選択ダイアログを何度も開かなくて済む操作にする。
- 対象は動画ファイルに集中し、画像ファイル対応は行わない。
- 動画編集者が確認結果を残し、後から未確認や要修正へ戻れるビューアを目指す。


## 2026-06-17 サムネイル表示中のフォームリサイズ修正
- サムネイルブラウザ表示中に `TCustomControl` がフォーム端の `WM_NCHITTEST` を拾ってしまい、枠なしフォーム側のリサイズ判定へ届かない問題を修正。
- `TVideoMinerThumbnailBrowser.WMNCHitTest` を追加し、左端・右端・下端のリサイズ帯では `HTTRANSPARENT` を返して親フォーム側の既存リサイズ判定へ通すようにした。
- `WM_SIZE` 後に `FThumbnailBrowser` の透明リサイズハンドルも `TResizeEdgeHelper.AdjustEdges` で再配置するようにした。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-17 サムネイル一覧のホバー表示
- `TVideoMinerThumbnailBrowser.DrawTile` でホバー中タイルの枠線を明るい 2px 枠に変更し、マウス位置が分かりやすいようにした。
- タイル上ではカーソルを `crHandPoint`、一覧外では `crDefault` に戻すようにした。
- 現在再生中タイルは既存のオレンジ枠を優先する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-17 サムネイルホバー枠の強調
- ホバー中タイルの枠色を明るい青系に変更し、枠幅を 4px に広げた。
- 現在再生中のオレンジ枠よりも、マウス操作対象として視認しやすい強さに調整。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-17 サムネイル一覧のホイールズーム
- サムネイル一覧表示中のホイール操作を、縦スクロールではなくタイル拡大縮小に変更した。
- ホイール上で拡大、ホイール下で縮小する。
- タイル幅は 150px から 380px の範囲、1 ノッチ 24px 刻みに制限した。
- ズーム後もマウス下のタイル、または現在動画のタイルがなるべく同じ位置に残るよう `FScrollOffset` を補正する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-17 サムネイル一覧 実装状況まとめ
- 同一フォルダ内動画をタイル状に表示する `TVideoMinerThumbnailBrowser` を追加済み。
- `Tab` でサムネイル一覧の表示/非表示を切り替えられる。
- 通常動画画面の右クリックでサムネイル一覧を開き、サムネイル一覧の右クリックで閉じられる。
- サムネイルクリックで対象動画へ切り替え、現在動画をクリックした場合は一覧だけ閉じる。
- 表示中タイルから順にサムネイルを遅延生成し、生成中は `Loading`、失敗時は `Failed` を表示する。
- サムネイル生成は `DecodeFrameToBgrx32` 経路を使い、壊れた動画やデコード失敗はタイル単位で失敗表示に閉じ込める。
- `%APPDATA%\VideoMiner\ThumbnailCache` にサムネイル BMP をディスクキャッシュし、起動後も再利用する。
- キャッシュヒット時は 1 tick 最大 24 枚までまとめて読み込み、一覧表示の体感速度を改善済み。
- サムネイル一覧表示中もフォーム端でリサイズできるよう、左端/右端/下端のヒットテストを親フォームへ通す。
- フォーム端のリサイズ判定幅は 12px に拡大済み。
- ホバー中タイルは明るい青系 4px 枠と `crHandPoint` で強調する。
- サムネイル一覧の通常ホイール操作は縦スクロールに割り当て済み。
- 右下の丸い `+` / `-` ボタン、または中央ボタンを押しながらホイールを回す操作で、タイル幅 150px から 380px の範囲で 24px 刻みに拡大縮小する。
- README へ追加操作を記載済み。
- 最終確認: `Debug Win64` ビルド成功。警告 0 / エラー 0。

今後の候補:

- サムネイル一覧でキーボード上下左右選択、`Enter` 決定を追加する。
- キャッシュ削除やキャッシュ上限管理を追加する。
- ホバー時の複数フレーム紙芝居表示を検討する。

## 2026-06-18 サムネイル一覧のホイール操作修正
- サムネイル一覧で通常のマウスホイール操作を縦スクロールに戻した。
- サムネイル拡大縮小は、中央ボタンを押しながらホイールを回した場合だけ行うようにした。
- 中央ボタン状態は `ssMiddle` と `GetKeyState(VK_MBUTTON)` の両方で見る。
- README の基本操作も、通常ホイールはスクロール、中央ボタン+ホイールは拡大縮小として更新した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル一覧の拡大縮小ボタン追加
- サムネイル一覧の右下に丸い `+` / `-` ボタンを追加した。
- 通常ホイールの縦スクロールを維持したまま、片手でサムネイルサイズを変更できるようにした。
- ボタン上では `crHandPoint` と hover 色で操作対象を示し、クリック時は画面中央を基準に 24px 刻みで拡大縮小する。
- 中央ボタン+ホイールの拡大縮小操作も残している。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル一覧のキーボード操作とサイズ保存
- サムネイル一覧で矢印キーによる選択移動を追加した。
  - 左右キーで前後タイルへ移動する。
  - 上下キーで前後の行へ移動する。
  - 選択中タイルが画面外へ出る場合は、自動的にスクロール位置を補正する。
- `Enter` で選択中タイルの動画へ切り替えるようにした。
- サムネイル一覧表示中は、メインフォームの通常の左右キー動画移動よりも一覧側のキー操作を優先する。
- タイル幅を `%APPDATA%\VideoMiner\VideoMiner.ini` の `ThumbnailBrowser` セクションへ保存するようにした。
- 起動時は保存済みタイル幅を読み込み、150px から 380px の範囲へ丸めて適用する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル一覧の矢印キー入力修正
- `Enter` は効くが矢印キーで選択移動できない問題を修正した。
- `TVideoMinerThumbnailBrowser` を `TabStop := True` にし、一覧自身がフォーカスを受け取れるようにした。
- `WM_GETDLGCODE` で `DLGC_WANTARROWS` / `DLGC_WANTALLKEYS` を返し、VCL のダイアログキー処理に矢印キーを奪われないようにした。
- 一覧にフォーカスがある場合のため `KeyDown` override からも `HandleKeyDown` を呼ぶようにした。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル一覧の選択枠視認性調整
- キーボード選択中タイルの枠色を白から明るいグリーン系へ変更した。
- 現在動画と選択中タイルが重なった場合は、外側に現在動画のオレンジ枠、内側に選択中のグリーン枠を描く二重枠にした。
- 現在動画の枠幅も少し太くし、選択状態と同時に見ても意味が分かるようにした。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル一覧の簡易ホバープレビュー
- ホバーが続いたタイルだけ、音なしの簡易プレビューを表示するようにした。
- 300ms 待ってから、動画の 10% / 25% / 40% / 55% / 70% / 85% 付近の代表フレームを 350ms 間隔で切り替える。
- 実再生ではなく紙芝居方式。ホバーが外れたら停止して通常サムネイルへ戻す。
- 既存の `DecodeFrameToBgrx32` 経路を使い、プレビュー画像は一時メモリだけに保持する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル一覧の本プレビュー試験入口
- 紙芝居式の簡易ホバープレビューから、音なしの本プレビューを試す入口へ変更した。
- ホバー開始後 300ms で対象動画を `TFFmpegDecoder` で開き、10% 位置を初期表示した後は `DecodeNextFrameToBgrx32` で順方向にフレームを進める。
- 更新間隔は 40ms 目安。ホバーが外れたら一時デコーダとプレビュー画像を破棄する。
- `HOVER_REAL_PREVIEW_ENABLED` を `False` にすると、この入口を塞いでホバープレビューを停止できるようにした。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 サムネイル本プレビュー開始待ち時間調整
- ホバー本プレビューの開始待ち時間を 300ms から 100ms へ短縮した。
- カーソル移動時の負荷を実際に見やすくするため、まずは本プレビュー入口を維持したまま起動を早めている。

## 2026-06-18 サムネイル本プレビュー再始動条件修正
- ホバー先が変わった時だけでなく、同じタイル上でもプレビューが停止済みなら `MouseMove` で再予約するようにした。
- デコード失敗、動画切り替え直後、スクロール/再描画直後などで `StopPreview` されたあと、カーソルが同じタイル内に残ると再開しない可能性への対策。

## 2026-06-18 サムネイル本プレビュー即時開始テスト
- 計測しやすいよう、ホバー本プレビューの開始待ちを 0ms にした。
- `ResetPreview` はタイルごとに `StopPreview` してから即座に最初のフレームを生成し、以後は 40ms タイマーで進める。
- プレビュー対象は `FPreviewIndex` ひとつだけに限定し、hover 表示と別タイルで同時に動かないようにしている。
- メディアリスト差し替え時は古いプレビューを停止するようにした。

## 2026-06-18 サムネイル本プレビュー対象の単純化
- 本プレビューの表示条件をマウス hover 中のタイルだけに限定した。
- キーボード選択カーソルは選択表示だけを担当し、プレビュー開始条件には使わない方針にした。
- `DrawThumbnail` でも `FPreviewIndex` だけでなく `FHoverIndex` と一致する場合だけプレビュー画像を描くようにし、古い対象や別タイルにプレビューが残る道を塞いだ。

## 2026-06-18 サムネイル本プレビュー開始前の hover 描画優先
- `MouseMove` で hover 対象を更新したら、先に `Invalidate` / `Update` でカーソル枠表示を描いてから本プレビュー開始処理へ進むようにした。
- プレビュー開始時の一時デコーダ open / 初回デコード負荷で、hover 表示の反応が遅れて見える問題への対策。

## 2026-06-18 サムネイル一覧 完成形として区切り
- サムネイル一覧は現時点の完成形として扱う。
- 同一フォルダ内動画をタイル表示し、クリックまたはキーボード選択 + `Enter` で動画を切り替える。
- 通常ホイールは縦スクロール、右下の丸い `+` / `-` と中央ボタン + ホイールはサムネイル拡大縮小に使う。
- タイル幅は INI に保存し、次回起動時に復元する。
- 現在動画はオレンジ枠、キーボード選択はグリーン枠、マウス hover は明るい枠で区別する。
- ホバー中の動画だけ音なし本プレビューを表示する。キーボード選択カーソルはプレビュー対象にしない。
- プレビュー開始時は hover 枠を先に描画してから初回デコードへ進め、体感反応を優先する。
- 当初の次候補はプレイリスト機能だったが、任意順の動画リストではなく、まず最近よく使う作業フォルダへ戻るためのフォルダ閲覧履歴として進める。

## 2026-06-18 フォルダ閲覧履歴 機能方針
- 次の検討対象は、プレイリストではなく「フォルダ閲覧履歴」と呼ぶ。
- 任意順の動画リストではなく、最近よく使う作業フォルダへ戻りやすくする機能として扱う。
- 履歴はファイル単位ではなくフォルダ単位で記録する。
- フォルダが開かれた、またはサムネイル一覧などから選択された時点で、そのフォルダの履歴順位を更新する。
- 選ばれなくなったフォルダは、他のフォルダが使われるたびに相対的に順位が下がる。
- 履歴件数は、サムネイル画面で横並びできる限界程度に少し余裕を加えた数にする。
- 履歴フォルダは `Del` キーで履歴から削除できるようにする。
- `Del` キーで削除するのは履歴項目だけで、実フォルダや中のファイルは削除しない。
- ネットワークフォルダや外付けドライブ上のフォルダは、一時的に存在しなくても自動削除しない。
- `F5` キーで履歴フォルダの存在確認、代表サムネイル更新、フォルダ内容の再読み込みを行う。

表示方針:

- フォルダ閲覧履歴は、サムネイル一覧の 1 行目に表示する。
- 通常の動画サムネイルとタイルレイアウト、クリック、キーボード選択、スクロールなどの処理をできるだけ共通化する。
- ただし背景色、枠線、フォルダ風の表示で、通常動画タイルとは見た目を区別する。
- フォルダ履歴タイルには、パス全体ではなくフォルダ名の右端部分を表示する。
- フォルダ履歴タイルの代表サムネイルは、5 枚程度を横または重ね気味に並べて表示する。
- 代表サムネイルは、フォルダ内動画の先頭、末尾、中間ランダムを混ぜて選ぶ。

## 2026-06-18 フォルダ閲覧履歴 1 行目領域確保
- サムネイル一覧の 1 行目をフォルダ閲覧履歴用の固定領域として確保した。
- まだ履歴データは持たず、仮の `Folder history` 表示だけを描く段階に留めている。
- 通常動画タイルは履歴行の下から表示するようにし、スクロール、現在動画へのスクロール、キーボード選択の表示位置計算も履歴行の高さを考慮するようにした。
- 履歴行上では通常動画タイルの hover / クリック判定を行わないようにした。
- スクロール時に動画タイルが履歴行へ食い込んでも、履歴行を最後に再描画して固定行として見えるようにした。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 仮タイル表示
- フォルダ閲覧履歴行に、現在開いているフォルダを仮の履歴タイルとして 1 件表示するようにした。
- まだ履歴の保存、順位更新、クリックでのフォルダ切り替え、`Del` 削除、`F5` 再読み込みは実装していない。
- フォルダ履歴タイルは通常動画タイルと同じ幅を使い、背景色と枠色を変えて通常動画と区別する。
- タイル下部には現在フォルダ名を表示する。パス全体ではなく、右端のフォルダ名だけを表示する。
- 代表サムネイルは既存の動画サムネイル状態と画像を使い、最大 5 枚を先頭から末尾まで均等に選んで並べる。
- 代表サムネイルが未生成の場合は、通常動画サムネイルと同じ生成キューへ積む。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 仮タイル hover 表示
- フォルダ閲覧履歴の仮タイルに hover 表示を追加した。
- hover 中はタイル背景を少し明るくし、枠色を明るいグリーン系にして操作対象が分かるようにした。
- フォルダ履歴タイル上では通常動画タイルの hover プレビューを開始しない。
- 左クリック時も、まだフォルダ切り替え処理へは進まず、通常動画タイル選択へ落ちないように吸収する段階に留めている。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 保存と複数タイル表示
- フォルダ閲覧履歴を `%APPDATA%\VideoMiner\VideoMiner.ini` の `FolderHistory` セクションへ保存するようにした。
- 動画を開いたフォルダを履歴の先頭へ移動し、同じフォルダが重複しないようにした。
- 保存件数は最大 12 件にした。存在しないフォルダやネットワークフォルダは、この段階では自動削除しない。
- サムネイル一覧 1 行目には、保存済みフォルダ履歴を左から複数タイルとして表示するようにした。
- 現在開いているフォルダの履歴タイルだけ、既存の動画サムネイルを代表サムネイルとして流用する。
- それ以外の履歴タイルは、まずフォルダ名と空の代表枠だけを表示する段階に留めている。
- クリックによるフォルダ切り替え、`Del` 削除、`F5` 再読み込み、過去フォルダの代表サムネイル生成は次段階以降に残す。
- `VideoMinerSettings.pas` / `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 クリック切り替え
- フォルダ閲覧履歴タイルをクリックすると、そのフォルダ内の先頭動画へ切り替えるようにした。
- 先頭動画は `TVideoMinerMediaList.FirstMediaFileInFolder` で取得し、既存のフォルダ内動画一覧と同じ作成日時順に合わせる。
- フォルダ内に開ける動画がない場合は、動画切り替えは行わずステータス表示だけに留める。
- 履歴タイル選択は `TVideoMinerThumbnailBrowser.OnFolderSelected` でメインフォームへ通知する。
- フォルダ切り替え後は通常の `LoadVideoFile` 経路に流すため、履歴順位、サムネイル一覧、タイトル表示も既存処理で更新される。
- `VideoMinerMainForm.pas` / `VideoMinerMediaList.pas` / `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 クリック動作の調整
- フォルダ閲覧履歴タイルをクリックしても、すぐに動画再生へは進まないようにした。
- 履歴クリック時はサムネイル一覧モードを開いたまま、通常動画サムネイルの一覧だけを選択フォルダの内容へ切り替える。
- 実際に再生を切り替えるのは、選択フォルダ内の動画サムネイルをクリック、またはキーボード選択 + `Enter` した時だけにした。
- 履歴フォルダ表示用に `TVideoMinerThumbnailBrowser` が一時的な `TVideoMinerMediaList` を保持し、メインフォーム側の現在再生中リストは変更しない。
- 現在再生中の動画が表示中フォルダに含まれる場合だけ、通常動画タイルの現在動画枠を表示する。
- `VideoMinerMainForm.pas` / `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 Del 削除
- フォルダ閲覧履歴タイルを選択中に `Del` キーを押すと、その履歴項目だけを削除するようにした。
- `Del` では実フォルダやフォルダ内のファイルは削除しない。
- 削除対象は hover 中タイルではなく、クリックで選択されたフォルダ履歴タイルに限定した。
- 削除後は、同じ位置に次の履歴があればそこへ選択を移し、なければ直前の履歴へ選択を移す。履歴が空になった場合は選択を解除する。
- 削除後に hover index が範囲外になった場合は解除し、無効 index を参照しないようにした。
- フォルダ履歴の削除処理は `VideoMinerSettings.DeleteFolderHistory` に置いた。
- `VideoMinerSettings.pas` / `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 代表サムネイル 2x2 表示
- フォルダ履歴タイルの代表サムネイルを横一列表示から 2x2 表示へ変更した。
- 代表サムネイル数は 5 枚から 4 枚へ変更した。
- 現在表示中フォルダの履歴タイルでは、既存サムネイルを 2x2 に並べる。
- 代表サムネイルをまだ持たない履歴フォルダでは、4 つの空枠を並べず、単一の暗いプレビュー領域だけを表示する。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 代表サムネイルを履歴全体へ表示
- 選択中または表示中のフォルダだけでなく、履歴フォルダごとに代表ファイル一覧を作って 2x2 の代表サムネイルを描くようにした。
- 現在表示中フォルダは既存のサムネイル配列と生成キューを使い、過去履歴フォルダは既存のディスクキャッシュからサムネイルを読む。
- 過去履歴フォルダの未生成サムネイルは、この段階では自動生成せず空のプレビュー領域として残す。履歴一覧の描画だけで重い生成処理を走らせないため。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 F5 再読み込み
- サムネイル一覧モードで `F5` を押すと、フォルダ閲覧履歴を設定ファイルから読み直すようにした。
- フォルダ履歴タイルを選択中の場合は、その選択フォルダの動画一覧を再スキャンして通常動画サムネイル一覧を作り直す。
- 選択フォルダに動画がない、または存在確認できない場合でも、履歴からは自動削除せず、通常動画一覧だけを空にする。
- フォルダ履歴タイル未選択の場合は、現在表示中一覧のサムネイル状態を作り直して再描画する。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 代表サムネイル 1 大 + 3 小
- フォルダ履歴タイルの代表サムネイル表示を 2x2 から、左に大きな代表 1 枚、右に小さな補助 3 枚を縦に並べる表示へ変更した。
- 2x2 より主画像を大きく見せ、フォルダ識別のしやすさを優先する。補助 3 枚で複数動画フォルダであることも残す。
- 代表ファイルの選び方は従来どおり、フォルダ内一覧から均等に 4 件を選ぶ段階のまま。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 代表サムネイル重ね表示へ修正
- フォルダ履歴タイルの代表サムネイルを、通常動画サムネイルと同じ大きな 1 枚表示を基本に戻した。
- 補助サムネイル 3 枚は、大きな代表サムネイルの下側に小さく重ねて表示する。
- 代表サムネイル枠の色は緑系ではなく白系へ変更した。フォルダ履歴らしさはタイル背景と外枠で区別する。
- 代表ファイルの選び方は従来どおり、フォルダ内一覧から均等に 4 件を選ぶ段階のまま。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 補助サムネイル位置調整
- 大きな代表サムネイル下側に重ねる補助 3 枚を、右寄せではなく中央寄せで並べるようにした。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 代表サムネイル選定
- 大きな代表サムネイルは、フォルダパス由来の固定ハッシュで中間帯から選ぶようにした。毎回表示が揺れず、先頭固定よりフォルダごとの差が出やすい。
- 補助サムネイルは、先頭、中間、末尾を優先して選ぶ。
- 動画数が少ない場合は、同じ動画を重複表示しないようにし、表示できる件数だけ補助サムネイルを出す。
- 代表候補が 4 件に満たない場合だけ、大きな代表位置から順に近い index を追加して埋める。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 保存上限 16 件
- フォルダ閲覧履歴の保存上限を 12 件から 16 件へ変更した。
- 高解像度環境でも、保存済み履歴を横一列ですべて必ず表示する必要はない。表示は従来どおり、現在の履歴行幅に収まる分だけ描画する。
- `VideoMinerSettings.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 選択時の優先順位更新
- フォルダ閲覧履歴タイルを選択した場合も、そのフォルダを履歴の先頭へ昇格するようにした。
- これにより、最近選択されたフォルダほど履歴上位に残り、保存上限 16 件を超えたときにも消えにくくなる。
- 実際に動画を開いたフォルダは従来どおり `SetMediaList` 経路で先頭へ昇格する。
- `F5` の再読み込みでは順位を動かさず、現在の履歴順を保ったまま再スキャンする。
- 選択したフォルダに動画がない、または存在確認できない場合でも、履歴からは自動削除せず、選択操作として先頭へ昇格し通常動画一覧だけを空にする。
- `VideoMinerThumbnailBrowser.pas` は UTF-8 BOM 付き、改行 CRLF で保存した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-18 フォルダ閲覧履歴 現行仕様まとめ

フォルダ閲覧履歴は、プレイリストではなく、最近よく見るフォルダへ戻るための履歴機能として扱う。

現行仕様:

- 名称は「フォルダ閲覧履歴」とする。
- 履歴は動画ファイル単位ではなくフォルダ単位で記録する。
- 動画を開いたフォルダ、または履歴タイルで選択されたフォルダは履歴の先頭へ昇格する。
- 選択されなくなったフォルダは相対的に順位が下がり、保存上限を超えると古いものから消える。
- 保存上限は 16 件。
- サムネイル一覧の 1 行目にフォルダ閲覧履歴を表示する。
- 表示は現在の履歴行幅に収まる分だけ描画する。高解像度でも 16 件すべてを必ず横一列表示する必要はない。
- フォルダ履歴タイルをクリックしても、すぐには動画再生へ切り替えない。
- 履歴クリック時はサムネイル一覧モードのまま、通常動画サムネイル一覧だけを選択フォルダの内容へ切り替える。
- 実際に再生を切り替えるのは、選択フォルダ内の通常動画サムネイルをクリック、またはキーボード選択 + `Enter` した時。
- `Del` は選択中の履歴項目だけを削除する。実フォルダやフォルダ内ファイルは削除しない。
- `F5` は履歴設定を読み直し、選択中フォルダがあればその動画一覧を再スキャンする。順位は変えない。
- ネットワークフォルダや一時的に存在しないフォルダは、自動削除しない。
- 選択フォルダに動画がない、または存在確認できない場合は、通常動画一覧だけを空にする。
- フォルダ履歴タイルは通常動画タイルと近い処理を使い、背景色、外枠、フォルダ名表示で区別する。
- フォルダ名はパス全体ではなく右端のフォルダ名を表示する。
- 代表サムネイルは、大きな 1 枚を基本に、下側へ小さな補助サムネイルを最大 3 枚重ねる。
- 大きな代表サムネイルはフォルダパス由来の固定ハッシュで中間帯から選ぶ。
- 補助サムネイルは先頭、中間、末尾を優先し、動画数が少ない場合は重複表示しない。
- 現在表示中フォルダの代表サムネイルは既存のサムネイル生成キューを使う。
- 過去履歴フォルダの代表サムネイルは既存ディスクキャッシュから読み、未生成分はこの段階では自動生成しない。

保留:

- 過去履歴フォルダの未生成サムネイルを、履歴行用に少しずつ生成するかどうか。
- キーボードだけで通常動画一覧とフォルダ履歴行を行き来する操作の追加。
- 未接続フォルダや動画なしフォルダを、見た目で薄く区別するかどうか。
- `F5` 実行時の更新対象が分かるような軽いフィードバックを出すかどうか。

## 2026-06-18 README 更新
- `README.md` の主な特徴、基本操作、開発状況、設定ファイル説明へフォルダ閲覧履歴の説明を追加した。
- 「プレイリスト」ではなく「フォルダ閲覧履歴」として説明を揃えた。
- `README.md` / `note.md` は UTF-8 BOM 付き、改行 CRLF で保存する。

## 2026-06-18 一時停止中 Ctrl+C フレームコピー
- 一時停止中に `Ctrl+C` で現在表示中フレームをクリップボードへコピーする機能を追加した。
- 画面キャプチャではなく、`TVideoMinerVideoSurface` が保持するデコード済み動画フレーム `Bitmap` を使う。
- コピー解像度は表示倍率やズーム状態ではなく、動画フレームそのものの解像度にする。
- PNG は `RegisterClipboardFormat('PNG')` のクリップボード形式へ保存する。
- PNG 非対応アプリ向けの fallback として `CF_DIB` / `CF_BITMAP` も同時に入れる。
- `FVideoInfo.HasAlpha` が True の場合は BGRA の alpha を PNG の alpha channel へ保持する。
- `FVideoInfo.HasAlpha` が False の場合は alpha を全ピクセル 255 に固定し、通常 MP4 が透明 PNG にならないようにした。
- `ClipboardWatcher` の監視処理は使わず、PNG/DIB/BITMAP をクリップボードへ入れる最小処理を `VideoMinerFrameClipboard.pas` へ内包した。
- 参照用に復活していた `Source\Lib\ClipboardWatcher` は、内包後に削除した。
- `BitmapEx.pas` の alpha 付き PNG 書き出し方針を参考にしつつ、クリップボード用には専用の stream 生成処理を持たせた。
- 作業前に `Add clipboard helper references` コミットを作り、復帰点を残した。
- `Debug Win64` ビルド成功。
- 2x2 の検証用 Bitmap でクリップボードへ PNG を入れて読み戻し、alpha 保持時は `0,128`、通常 PNG 固定時は `255,255` になることを確認した。
- 実ファイルでも、通常 MP4 は不透明 PNG として、透明 MOV は透明 PNG としてクリップボードへ正しく入ることを確認した。
- 透明 MOV の貼り付け確認では、模様画像の上へ作業員動画の透明 PNG を重ね、背景が透けることを確認した。

## 2026-06-18 90% セーフエリア確認枠
- TV 放送時の文字情報見切れ防止確認用に、動画座標中央 90% のガイド枠を表示できるようにした。
- `Ctrl+G` で表示/非表示を切り替える。起動時は非表示で、INI には保存しない。
- 動画切り替え後も、アプリ起動中の表示状態は維持する。
- 1920x1080 では `Left=96 / Top=54 / Right=1824 / Bottom=1026` 相当の位置を示す。
- ほかの解像度でも、動画フレームの幅/高さに対して 5% ずつ内側へ入った中央 90% を描く。
- 枠は動画フレームの座標系で描き、ズーム/パン中も動画内容と一緒に移動・拡大する。
- 描画は `TVideoMinerVideoSurface` の既存 paint buffer 上で行い、ちらつきを避ける。
- 明るい緑線の外側に黒い太線を重ね、背景が明るい動画でも見えるようにした。
- `Debug Win64` ビルド成功。
