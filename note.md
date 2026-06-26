# VideoMiner note

作業再開時に最初に見るメモ。ここには現在の課題、開発方法、ルールだけを置く。

- 日付付きの作業記録、試行錯誤、計測結果は `HISTORY.md` へ置く。
- 仕様、操作説明、構成説明は `README.md` へ置く。
- 課題が完了したら、完了内容を `HISTORY.md` へ移し、このファイルから削る。

## 優先課題

1. 中央 overlay の操作感を整える。
   - シークバー小 fallback はかなり減ったため、非常時 fallback を完全になくすより D3D overlay と入力判定の違和感を減らす。
   - 中央の先頭/10秒戻し/再生一時停止/10秒進み/末尾ボタンは、各ボタンの隙間で hover が切れないよう、5つをまとめた長方形の操作領域として扱う。
   - 中央ボタン群はフォームサイズ追従のまま、従来より一回り小さくする。

2. 別環境の ZIP 展開版で `Runtime error 217 at 00007ff614c32422` が出る原因を特定する。
   - デコード高速化対策の 1 つ前のバージョンでは発生しないため、高速化対策以降の差分を優先して疑う。
   - Delphi の unit initialization / finalization 中例外、配布物の不整合、DLL 混在、PATH 依存を優先して見る。
   - Release / Debug の DCU、EXE、RSM、MAP、配布 ZIP の更新日時を確認し、必要なら `Win64\Release` と `Win64\Debug` の生成物を掃除してからフルビルドする。
   - ZIP 展開状態、インストール先、開発用 Release フォルダの EXE/DLL 一覧、サイズ、更新日時を比較する。

3. 長い読み込み中に止まっていないことを見せる。
   - 大きい動画やネットワーク越しの動画では、フォーム表示後の読み込み中に固まったように見える可能性がある。
   - `Loading` 表示や周辺の軽いアニメーションで処理中であることを伝える。
   - 実際の読み込み時間短縮とは別の UI 課題として扱う。
   - ファイル前方読み込み buffer は通常 off。NAS/低速ストレージ向けに再挑戦する場合は、decoder 個別ではなく main decoder 限定またはファイル単位共有 cache を検討する。

4. 映像再生が少しカクつく場合の原因を切り分ける。
   - 同期ズレではなく、描画、デコード、タイマー周りの負荷や間隔が原因の可能性がある。
   - まず Debug ログ量を絞り、`playback_tick`、`paint`、`decode_ms`、`paint_ms`、`timer_interval` を確認する。

5. D3D 表示統合を詰める。
   - 現在の基本方針は、動画本体と UI を同じ D3D 描画パスで backbuffer 上に合成し、最後に 1 回だけ `Present` する形。
   - 入力判定、位置計算、進捗値、ドラッグ/ホイールのイベント処理は既存の `TVideoMinerOverlaySeekBar` / `TVideoMinerVideoSurface` 側を使い回す。
   - ソフトウェアデコードとハードウェアデコードで GUI を 2 系統に分けない。CPU frame も最終表示段階で D3D texture へ upload し、同じ presenter と overlay state を使う。
   - D3D backbuffer の上へ VCL/GDI overlay を直接重ねる案はちらつくため避ける。
   - hover preview 小窓は bitmap/texture 合成が必要なので、seek bar 本体と基本操作の後で扱う。
   - ホイールズーム/パンは D3D viewport 方式を正式採用済み。画質優先で調整するなら linear sampler 化を後続候補にする。

6. D3D シークバー下段ツール行の縦位置を仕上げる。
   - 現在、Debug ビルドでは下段ツール行確認用の緑の水平ラインを表示中。
   - 左側の `Vol`、スピーカー、`1.0x` のグループ内はおおむね揃っている。
   - 中央の時刻と右側の `+` / `-` / `E` / `Stop` は左側へ寄せる方向で調整済み。
   - 残りはスピーカー、倍速表示、全画面アイコンだけ微調整が必要。
   - 調整対象は主に `Source\FFmpeg\FFmpegD3D11TextureProbe.pas` の D3D overlay 側。GDI 側 `Source\App\VideoMinerOverlay.pas` にも Debug 用水平ラインが残っている。
   - 完了時は Debug 用水平ラインを削除または無効化し、`HISTORY.md` に移す。

## 後続課題

- D3D 表示に乗らない動画、または初回だけ D3D 表示に乗らない動画を切り分ける。
  - 動画形式、pixel format、alpha、回転、色空間などの動画仕様側の問題か、初回だけの同期遅れ/drop 判定かを分ける。
  - 同じ動画を最初に開いた時、別動画を表示した後に再度開いた時、一時停止後に再生した時で、`d3d_decode_state`、`convert_frame_false`、`d3d11_display_present_*`、`lagging_video_sync_for_d3d_overlay` を比較する。
  - 比較代表は `C:\Users\zan12\Videos\magnific_8vzvBH6IrU.mp4` と `C:\Users\zan12\Videos\x_33.mp4`。

- 旧 GDI seek bar 側に残っている入力処理を、D3D overlay 表示と矛盾しない形で整理する。
  - Vol drag、mute、速度切替、Loop/Stop/Next、Check、`+`/`-`、全画面、seek drag を D3D 表示と同じ位置・状態で動くように詰める。
  - 停止中 seek bar を D3D 化する場合は、D3D 表示済み frame がない状態で backbuffer を更新する必要があるため、現在 CPU bitmap / preview / D3D frame の所有関係を整理してから着手する。

- チェック機能の UI を育てる。
  - チャプター種別を表示する。
  - チャプターへジャンプした時に短い理由を表示する。
  - 検知種類ごとの ON/OFF を追加する。
  - 実動画で誤検知が見えてきたらしきい値を設定化する。
  - チェック結果の一覧表示や外部出力を検討する。

- シークバー hover 表示を、現在の時刻テキストではなく該当位置のフレーム画像 preview にする。
  - 現状は停止中のみ既存 bitmap preview を使う。
  - 完全 D3D 合成へ寄せる場合は、preview bitmap の texture 化と sprite 合成を検討する。

- サムネイル一覧の操作性をさらに整える。
  - hover しながら高速移動した時の追従感とデコード負荷を確認する。
  - ホバー時ダイジェストは、基本一覧が安定してから検討する。
  - Alpha 表示バッジや詳細情報表示は後回しでよい。

- サムネイル生成のバックグラウンド worker 化を再挑戦する。
  - UI タイマーによる同期生成では、大量の動画や重い動画で限界がある。
  - 通常再生、シーク、hover 実動画プレビューを阻害しないことを最優先にする。
  - 再生中、シーク中、hover 実動画プレビュー中は生成を止める。
  - まずはディスクキャッシュ miss の 1 枚生成だけを worker 化し、キャッシュ hit や hover 実動画プレビューとは分離して検証する。
  - worker ごとに専用デコーダを持ち、UI 反映は main thread 側で生存確認と世代確認を行ってから反映する。

- ループ再生の先頭戻りをさらに滑らかにする。
  - 現状かなり改善済みなので優先順位は低め。
  - 目標は seek / 再同期 / 音声再開の待ちを 0ms に近づけること。
  - 先頭フレームキャッシュを再検討する場合は、動画ファイル、ループ開始位置、表示回転、ループ区間をキーにし、動画切り替えやチャプター変更で破棄する。

- ボスが来たモードの偽装表示を改善する。
  - 画面サイズごとの情報密度、実作業中らしさ、解除ボタンの目立ちすぎ防止、文字や行の自然さを調整する。

- アプリ本体で使わない補助ユニットを整理する。
  - `Source\Lib` などの既存補助ユニットが現行アプリで必要か確認し、不要なら外す。

- `VideoMinerMainForm.pas` の肥大化を引き続き防ぐ。
  - GUI イベント受け口、再生制御、ウィンドウ制御、ショートカット、設定、メディア管理の責務を機能単位へ逃がす。
  - 次の候補は、シーク/再生橋渡し、`LoadVideoFile`、`FormCreate` 内 controller 配線のどれかを小さな builder / coordinator へ寄せること。

## D3D デバッグ方法

- テスト代表:
  - `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4`
  - `C:\Users\zan12\Videos\magnific_8vzvBH6IrU.mp4`
  - `C:\Users\zan12\Videos\x_33.mp4`
- Debug Win64 / `VIDEOMINER_DEBUG_LOG=1` / `VIDEOMINER_SLOW_LOG=1` で確認する。D3D11 実表示は既定で有効。
- VideoMiner は単一インスタンスなので、古いプロセスが残っていると新しい EXE を起動しても既存プロセスへファイルを渡すだけになる。確認前に `VideoMiner.exe` を全終了する。
- Release では `WriteVideoMinerSlowLog` が無効なので、D3D present の確認は Debug ログで行う。Release 側の切り分けが必要なら、D3D 有効/退避理由だけを Release でも出せる軽量ログを追加する。
- まずマウスを動かさない再生で、`d3d11_display_present total_ms`、`next_bgrx32_detail convert_ms`、`playback_tick total_ms`、drop を見る。
- 次に再生中にシークバー領域へマウスを載せて、`bgrx32_convert` が増えないか、`d3d11_display_present` が継続するか、ちらつきがないかを見る。
- 目安: D3D 維持時は `next_bgrx32_detail convert_ms` p50 が 3-4ms 程度、`playback_tick total_ms` p50 が 10-13ms 程度。CPU 退避時は `bgrx32_convert` が増え、`playback_tick` が 20ms 以上へ寄る。
- ログ比較用の保存先は `D:\Users\take6\VideoMiner\VideoMiner_playback_debug_*.log`。
- 現在この環境の実ログは `D:\Users\take6\VideoMiner\VideoMiner_playback_debug.log` に出る。
- ちらついたら、GDI/VCL が同じ HWND へ描いていないか、`Paint` が seek bar を描いていないか、D3D `Present` と GDI overlay が混在していないかを最初に疑う。

## コンパイル方法

Debug Win64 ビルド例:

```powershell
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild VideoMiner.dproj /t:Build /p:Config=Debug /p:Platform=Win64"
```

文字コード確認:

```powershell
powershell -ExecutionPolicy Bypass -File tools\EnsureUtf8Bom.ps1 -Check
```

## コメントルール

- コメントは、処理を読めば分かることではなく、目的、責務、注意点、状態の意味を補うために書く。
- 古い仕様や現在の実装と食い違うコメントは、見つけた時点で更新する。
- 不要なコメントや重複したコメントを増やしすぎない。
- `var` ブロック内にローカル関数やローカル手続きを内包しない。必要な補助処理は同じ `implementation` 内の独立した関数/手続きとして切り出す。
- ユニット先頭には、そのユニットの目的や担当範囲を `//` コメントで記述する。
- フォーム系ユニットは GUI と実処理の境界が曖昧になりやすいため、`implementation` 直下にも `//` コメントを置き、実装部に残す責務と他ユニットへ逃がす責務を書く。ここは複数行でもよい。
- フィールドや定数のコメントは右側に 1 行で置き、同じブロック内では `:`、`=`、`//` の位置を揃える。
- コメントと対象の宣言/実装の間には空行を入れない。
- `property`、`procedure`、`function` 宣言は、横幅 112 文字以内に収まる場合は折り返さない。

## 保守ルール

- このファイルには課題以外の最新状態説明を増やさない。
- 日付付きの記録は `HISTORY.md` へ移す。
- 完了した課題は `HISTORY.md` へ移して、このファイルから削る。
