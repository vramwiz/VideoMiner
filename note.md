# VideoMiner note

作業再開時に見る課題だけを置く。仕様説明や開発ルールは `README.md`、日付ごとの作業記録や調査メモは `HISTORY.md` を参照する。

## 優先課題

1. 別環境の ZIP 展開版で `Runtime error 217 at 00007ff614c32422` が出る原因を特定する。
   - 別環境で ZIP を展開し、`VideoMiner.exe` を直接実行すると発生する。
   - デコード高速化対策の 1 つ前のバージョンでは発生しないため、高速化対策以降の差分を優先して疑う。
   - Delphi 側でコンパイルキャッシュが効き、ソース変更が正しく反映されていない配布物を作っている疑いもある。
   - Release / Debug の DCU、EXE、RSM、MAP、配布 ZIP の更新日時を確認し、必要なら `Win64\Release` と `Win64\Debug` の生成物を掃除してからフルビルドする。
   - 直前まで起動できていた環境で起動できなくなったため、新規 DLL 不足だけでなく、配布物、起動時初期化、DLL 混在を優先して疑う。
   - 開発環境にも配布 ZIP を展開した環境と同じ DLL 状態を作り、その状態で実行して再現を狙う。
   - `Win64\Release` や開発PCにだけ存在する DLL / 設定 / PATH 依存で動いていないか、インストール先と ZIP 展開先のファイル構成を比較する。
   - 217 は Delphi の unit initialization / finalization 中例外でも出るため、通常ログが出る前に落ちるケースとして調査する。
   - まずは ZIP 展開状態、インストール先、開発用 Release フォルダの EXE/DLL 一覧、サイズ、更新日時を揃えて比較する。
2. 長い読み込み中に止まっていないことを見せる。
   - 大きい動画やネットワーク越しの動画では、フォーム表示後の読み込み中に固まったように見える可能性がある。
   - `Loading` 表示や周辺の軽いアニメーションで、処理中であることを伝える。
   - 実際の読み込み時間短縮とは別の UI 課題として扱う。
3. 映像再生が少しカクつく場合の原因を切り分ける。
   - 同期ズレではなく、描画、デコード、タイマー周りの負荷や間隔が原因の可能性がある。
   - まず Debug ログ量を絞り、`playback_tick`、`paint`、`decode_ms`、`paint_ms`、`timer_interval` を確認する。
4. 4K 以上のデコード表示経路を段階的に改善する。
   - 直近の 4K30 高負荷テストでは、QSV の主負担は GPU->CPU 転送ではなく、NV12 -> BGRA の `sws_scale` と負 stride 回避コピーだった。
   - CPU 側の変換削減として `SWS_FAST_BILINEAR`、`BGR0` 出力、単一スレッドの自前 NV12 -> BGRX32 直接変換を試したが、QSV 4K30 ではいずれも悪化したため不採用。
   - FFmpeg 同梱範囲では `sws_scale` がかなり最適化されており、外部 SIMD ライブラリを増やさない前提では CPU 変換の追加改善余地は小さい。
   - 次は、QSV/D3D11VA から GPU texture を受け取り、D3D11 swap chain や shader で表示する経路が成立するかを調査する段階。
   - D3D11 texture upload + shader draw の probe では現行 CPU BGRX32 変換より十分軽かったため、3D texture 表示経路を採用方針で進める。
   - `UpdateSubresource + shader draw + Present` の probe でも現行 CPU BGRX32 変換より十分軽かった。
   - 実表示 HWND に計測用 Present を混ぜると VCL/GDI 描画と競合して大きくちらつくため、この方式は不採用。
   - D3D11 実表示経路を既定で有効化し、再生中だけ NV12 を D3D11 swap chain へ直接表示し、CPU BGRX32 変換をスキップできるようにした。
   - 起動時に `VIDEOMINER_D3D11_DISPLAY` が未指定なら `1` を設定するため、IDE/通常ビルドからの起動でも D3D11 実表示が既定になる。
   - 切り戻し確認が必要な場合だけ `VIDEOMINER_D3D11_DISPLAY=0` / `off` / `false` で D3D11 実表示を無効化する。
   - 4K30 QSV では `next_convert` p50 が約 15.4ms から約 2.7ms、`playback_tick` p50 が約 20.5ms から約 7.9ms へ改善したため採用方針。
   - D3D 実表示へ中央 fit / letterbox を追加した。4K30 QSV では `d3d11_display_present total_ms` p50 約 2.6ms、`playback_tick` p50 約 11.0ms で、clear 追加コストは p50 約 0.01ms。
   - 回転が必要なフレームは現時点では D3D 実表示を使わず、既存 CPU BGRX32 経路へ戻す。
   - D3D shader の NV12 -> RGB を BT.709 limited range 前提に補正した。4K30 QSV のログでは `range=1`、`space=2`。色空間が未指定扱いの可能性があるため、BT.601 / BT.709 / BT.2020 / full range の分岐は後続課題。
   - D3D backbuffer の上へ VCL/GDI overlay を直接重ねるとちらつくため不採用。overlay / seek bar / seek preview / safe area / loading / zoom が必要な間は CPU BGRX32 + GDI 描画へ戻す。
   - D3D 実表示後に一時停止してズームする場合は、現在位置の CPU frame を再取得してから GDI ズーム表示へ戻す。
   - D3D 実表示後に現在フレームをコピーする場合は、コピー直前に現在位置の CPU frame を再取得してから `CurrentFrameBitmap` を使う。
   - シークバー hover preview の負荷は表示反映ではなく hover 用 fast seek/decode が主因。再生中は hover preview デコードを止め、停止中のみ preview を出す。
   - シークバー自体は再生中も必要。単なる hover ではサムネイル preview を出さないが、シークバー表示やクリック/ドラッグ/ホイール操作は維持する。
   - 今の制約:
     - 動画は D3D11 swap chain backbuffer へ `Present` している。
     - overlay / seek bar / seek preview は VCL/GDI で同じ HWND へ描いている。
     - D3D backbuffer の上へ GDI を直接重ねると、次の D3D `Present` で上書きされてちらつく。
     - そのため上物表示が必要な状態では原則 `CanUseD3DFramePresentation=False` になり、CPU BGRX32 + GDI 経路へ退避している。
     - 例外として、再生中の簡易 seek bar は D3D backbuffer へ合成できるようにした。
   - D3D overlay 化の現状。
     - 発想は「仮想画面」ではなく、同じ D3D 描画パスで動画と UI を backbuffer 上に合成し、最後に 1 回だけ `Present` する形。
     - 入力判定、位置計算、進捗値、ドラッグ/ホイールのイベント処理は既存の `TVideoMinerOverlaySeekBar` / `TVideoMinerVideoSurface` 側を使い回す。
     - `FFmpegD3D11TextureProbe.pas` に単色矩形 overlay pass を追加し、動画描画後・`Present` 前に下部バー背景、再生位置、チャプター目盛り、ノブを描くようにした。
     - `TVideoMinerVideoSurface` から D3D 側へ seek bar state を渡す。
     - D3D seek bar 表示中は VCL `Paint` 側の seek bar 描画を止め、`paint_skip_d3d_frame` のまま D3D 表示を継続する。
     - D3D 簡易 seek bar には現在位置 / 動画長の 7-segment 風時刻表示を追加済み。数字は当面この簡易表現でよい。
     - 2026-06-25: Check 中は D3D 簡易 seek bar の中央表示を時刻ではなくフレーム番号形式へ切り替えるようにした。
     - 2026-06-25: D3D 簡易 seek bar の左下へ音量レールを追加し、ミュート時は赤寄りに表示するようにした。
     - 2026-06-25: D3D 簡易 seek bar の右下へ再生速度表示を追加した。
     - 2026-06-25: 基準スクリーンショットに合わせ、音量表示、ミュートアイコン、再生速度を旧 GDI と同じ左下クラスタへ寄せた。
     - 2026-06-25: D3D 簡易 seek bar の右側へ Loop / Stop などの終端到達時動作表示を追加した。
     - 2026-06-25: 終端到達時動作の `Loop` / `Stop` / `Next` 切替表示は D3D 側へ移植済み。簡易フォントに `S` / `T` / `N` / `E` グリフを追加し、`Stop` / `Next` の欠け表示を修正した。
       - 保留: `T` の縦線が少し太く見える。機能上は問題ないため、見た目調整として後回しにする。
     - 2026-06-25: D3D 簡易 seek bar の右側へチャプター追加/削除の `+` / `-` 表示を追加した。
     - 2026-06-25: D3D 簡易 seek bar の右端へ全画面ボタン表示を追加した。
     - 2026-06-25: D3D 全画面ボタンを四角形から、旧 GDI 基準画像に近い四隅へ広がる矢印形へ変更した。
     - 2026-06-25: D3D 簡易 seek bar の右側へ `Check` 表示を追加した。
     - 2026-06-25: 切替系ボタンの状態背景は hover / 押下時だけ出すようにし、active 状態の常時背景は出さないようにした。
     - 2026-06-25: 再生中 D3D 表示で下段操作群が消えるケースがあったため、音量/速度/Loop/チャプター/全画面の表示行は旧 GDI に近い seek bar パネル下端基準へ戻した。
     - 2026-06-25: D3D seek bar の機能確認を優先するため、旧 GDI seek bar の paint は一時的に `HIDE_LEGACY_SEEK_BAR_PAINT=True` で止めている。入力判定や操作処理は旧 `TVideoMinerOverlaySeekBar` を使い続ける。
     - 旧 GDI seek bar の基準画像は `Image\seekbar_reference_old_gdi_20260625.png` に保存済み。移行作業中はこの画像を見た目と配置の比較基準として使う。
     - シーク位置ノブは四角ではなく丸が理想。現状は D3D 矩形 pass だけで段付きの円形近似にしている。
     - 2026-06-25 時点のユーザー側ビルドでは、何度ビルドしても旧 VCL/GDI の下部 UI が出ると報告あり。
       - 共有スクリーンショットでは `frame 0`、hover preview 小窓、`Vol / 1.0x / Check / Loop` 付きのフル操作 UI が表示されていた。
       - この状態は `FPlaybackActive=False` または `FSeekPreviewVisible=True` のため、現行設計では `CanUseD3DFramePresentation=False` になり CPU BGRX32 + GDI 経路へ退避する。
       - つまり「D3D が常に無効」とは限らず、「停止中 / hover preview 中 / フル overlay 表示中は旧 UI」が現状仕様。
       - 2026-06-25: Release でも出る軽量ログ `d3d_surface_state` / `d3d_decode_state` / `d3d11_display_present_lite` を追加した。
       - 2026-06-25: 通常 open は自動再生するが、起動時の前回ファイル復元は `AutoPlay=False` のため、初回停止表示では旧 UI になることを確認した。
       - 2026-06-25: 再生開始時に停止中の hover preview と中央 overlay を閉じ、D3D seek bar state を更新する対策を入れた。
       - 2026-06-25: 旧 GDI seek bar から新 D3D seek bar へ同じ場所で切り替わる違和感を避けるため、ユーザー操作で停止状態から再生へ入る直前だけ旧 seek bar も一度閉じるようにした。
       - 2026-06-25: ループや内部再開では seek bar を消さないよう、上記の掃除処理は `SetPlaybackActive(True)` ではなく `PlayFromCurrentPosition` 直前に限定した。
       - 2026-06-25: ループ先頭フレームキャッシュの `PresentImmediate` は CPU/GDI paint を通るため、再生中でも一瞬だけ旧フル seek bar が出ることがあった。再生中の CPU/GDI fallback では `CompactPlaybackStyle` で D3D 風の簡易 seek bar を描くようにした。
       - 2026-06-25: 終端 loop では EOS 検出で一度 `PlaybackActive=False` になってから loop cache を表示していたため、cache 表示前に `PlaybackActive=True` を戻し、D3D seek bar overlay state も再同期するようにした。
       - 2026-06-25: loop cache 表示直後の通常 `Paint` が 1 frame だけ GDI compact seek bar を描いていたため、直近 D3D frame の表示時刻を surface 側で保持し、再生中かつ seek bar 表示中は `paint_skip_d3d_frame` で backbuffer を維持するようにした。
       - 2026-06-25: ユーザー確認で、ループ時に旧/GDI seek bar へ一瞬切り替わる違和感は解消した。
     - seek bar の今後の方針:
       - ソフトウェアデコードとハードウェアデコードで GUI を 2 系統に分けて育てない。
       - 本命は、ソフトウェアデコードの CPU frame も最後の表示段階で D3D texture へ upload し、ハード/ソフトどちらでも同じ D3D presenter と `DrawSeekBarOverlay` で動画本体 + seek bar を描く構成に寄せる。
       - これは「ソフトウェアデコードをやめる」ではなく、「描画と overlay 合成を D3D に統一する」という意味。
       - 短期的には GDI compact seek bar は暫定 fallback として最低限残すが、見た目や機能追加を GDI 側へ積み増していかない。
       - 避けること: D3D seek bar と GDI seek bar の両方に音量、速度、Loop、Check、チャプター、全画面、DPI 対応を個別実装していくこと。
       - 移行手順の目安:
         - 1. 旧/GDI 通常 seek bar の描画入口を閉じ、残す場合も暫定 fallback であることを明確にする。
         - 2. ソフトウェアデコード用に CPU BGRX/BGRA frame -> D3D texture -> Present の経路を追加する。
         - 3. ハード/ソフト両方で同じ `TD3D11SeekBarOverlayState` と `DrawSeekBarOverlay` を使う。
         - 4. 安定後、GDI seek bar 描画は非常用 fallback だけに縮小または削除する。
     - 次は旧 GDI seek bar 側に残っている入力処理を、D3D overlay 表示と矛盾しない形で整理する。
       - 現状、表示はおおむね D3D 側へ寄ってきたが、実操作はまだ旧 seek bar の hit test / callbacks に依存している。
       - 次の優先は「仮表示だけになっている箇所がないか」を確認し、Vol drag、mute、速度切替、Loop/Stop/Next、Check、`+`/`-`、全画面、seek drag を D3D 表示と同じ位置・状態で動くように詰める。
       - hover preview 小窓は bitmap/texture 合成が必要なので、seek bar 本体と基本操作の後で扱う。
     - 2026-06-25: 旧 GDI / fallback seek bar の描画入口を塞いだ結果、余計な旧表示は消えたが、起動直後の停止状態ではマウスを動かしても新 D3D seek bar が表示されない。
       - 試したこと:
         - `ShowFrameAt` の指定位置デコードでも、回転なしなら NV12 frame を D3D backbuffer へ同時に Present する変更を入れた。
         - `FFmpegD3D11TextureProbe.pas` に保持中の NV12 texture を再描画する `PresentCurrentNv12TextureFrame` を追加した。
         - 停止中の `seek_bar_visible_while_paused` ブロックを外し、停止中 hover / drag でも `UpdateD3DSeekBarOverlayState` が D3D 側へ状態を渡すようにした。
         - hover preview など表示目的でない seek decode が誤って D3D Present しないよう、D3D display allowed は各デコード呼び出し中だけ有効にした。
       - それでもユーザー確認では、起動直後にシークバー領域へマウスを動かしても新 D3D seek bar は出ない。
       - 次回はコードだけで推測せず、Debug ログで初期停止フレームの `d3d11_display_present` / hover 時の `d3d11_display_represent` / `surface_present_immediate` / `paint_skip_d3d_frame` の有無を確認する。
       - 特に、起動直後の前回ファイル復元が本当に `ShowFrameAt` の D3D 許可経路を通っているか、また hover 時に `RefreshD3DFramePresentation` が呼ばれているかを見る。
       - 必要なら一時的に、起動直後の停止フレーム D3D Present と hover 再Present の成否を Release でも出る軽量ログへ追加する。
   - D3D overlay 化のデバッグ方法:
     - テストファイルは `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4`。
     - Debug Win64 / `VIDEOMINER_DEBUG_LOG=1` / `VIDEOMINER_SLOW_LOG=1` で確認する。D3D11 実表示は既定で有効。
     - VideoMiner は単一インスタンスなので、古いプロセスが残っていると新しい EXE を起動しても既存プロセスへファイルを渡すだけになる。確認前に `VideoMiner.exe` を全終了する。
     - Release では `WriteVideoMinerSlowLog` が無効なので、D3D present の確認は Debug ログで行う。Release 側の切り分けが必要なら、D3D 有効/退避理由だけを Release でも出せる軽量ログを追加する。
     - まずマウスを動かさない再生で、`d3d11_display_present total_ms`、`next_bgrx32_detail convert_ms`、`playback_tick total_ms`、drop を見る。
     - 次に再生中にシークバー領域へマウスを載せて、`bgrx32_convert` が増えないか、`d3d11_display_present` が継続するか、ちらつきがないかを見る。
     - 目安: D3D 維持時は `next_bgrx32_detail convert_ms` p50 が 3-4ms 程度、`playback_tick total_ms` p50 が 10-13ms 程度。CPU 退避時は `bgrx32_convert` が増え、`playback_tick` が 20ms 以上へ寄る。
     - ログ比較用の保存先は `D:\Users\take6\VideoMiner\VideoMiner_playback_debug_*.log`。
     - ちらついたら、GDI/VCL が同じ HWND へ描いていないか、`Paint` が seek bar を描いていないか、D3D `Present` と GDI overlay が混在していないかを最初に疑う。
   - 次に進めること:
     - 旧 GDI seek bar の残機能を D3D overlay 側へ移す順番を決める。
     - 最初は停止中 seek bar の見た目を D3D seek bar に合わせるか、停止中も D3D backbuffer を更新できる設計へ寄せる。
     - 停止中 seek bar を D3D 化する場合は、D3D 表示済み frame がない状態で backbuffer を更新する必要があるため、現在 CPU bitmap / preview / D3D frame の所有関係を整理してから着手する。
     - hover preview 小窓まで D3D 化するには、preview bitmap を D3D texture 化して sprite 合成する段階が必要。これは seek bar 本体より後回しでよい。
   - 次は D3D 表示の統合を詰める。overlay、ズーム、シークプレビュー、フレームコピー機能との整合を順に見る。

## 後続課題

- チェック機能の UI を育てる。
  - チャプター種別を表示する。
  - チャプターへジャンプした時に短い理由を表示する。
  - 検知種類ごとの ON/OFF を追加する。
  - 実動画で誤検知が見えてきたらしきい値を設定化する。
  - チェック結果の一覧表示や外部出力を検討する。
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
  - 一覧を閉じた時、動画を切り替えた時、再読み込みした時に古い worker 結果を確実に捨てる。
- ループ再生の先頭戻りをさらに滑らかにする。
  - 2026-06-25: ループ再生で、終端到達時に数フレームだけ前のフレームが表示された後に先頭フレームになる現象がある。2 回目は正常で、初回だけの可能性がある。
  - D3D11 実表示経路では D3D present 成功時に `DecodeNextFrame` が早期 return するため、ループ先頭フレームキャッシュの保存がスキップされる点を疑う。
  - 2026-06-25: 再生開始時点で loop 先頭フレームキャッシュを事前作成し、終端 loop の cache hit 時は `ShowFrameAtMs(0)` を重ねないようにした。ログ上は初回 loop から `loop_frame_cache_hit` になり、loop 時の `main_show_frame_at_begin requested_ms=0` は出なくなった。
  - loop 再開直後の `seek_guard_drop target_ms=0 decoded_ms=7800/7833 present=False` は残るが、表示しない破棄ログなので、実画面で最終フレームがまだ見えるか確認する。
  - 現状かなり改善済みなので優先順位は下げる。
  - 目標は seek / 再同期 / 音声再開の待ちを 0ms に近づけること。
  - ループ先頭フレームの事前準備、再生用デコーダ位置の維持、音声再開の先行準備をまとめて見る。
  - 先頭フレームキャッシュを再検討する場合は、動画ファイル、ループ開始位置、表示回転、ループ区間をキーにし、動画切り替えやチャプター変更で破棄する。
- ボスが来たモードの偽装表示を改善する。
  - 画面サイズごとの情報密度、実作業中らしさ、解除ボタンの目立ちすぎ防止、文字や行の自然さを調整する。
- アプリ本体で使わない補助ユニットを整理する。
  - `Source\Lib` などの既存補助ユニットが現行アプリで必要か確認し、不要なら外す。
- `VideoMinerMainForm.pas` の肥大化を引き続き防ぐ。
  - GUI イベント受け口、再生制御、ウィンドウ制御、ショートカット、設定、メディア管理の責務を機能単位へ逃がす。

## コンパイル方法

Debug Win64 ビルド例:

```powershell
$env:BDS='C:\Program Files (x86)\Embarcadero\Studio\37.0'
& 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe' `
  'D:\DelphiProg\test\VideoMiner\VideoMiner.dproj' `
  /t:Build /p:Config=Debug /p:Platform=Win64
```

文字コード確認:

```powershell
powershell -ExecutionPolicy Bypass -File tools\EnsureUtf8Bom.ps1 -Check
```

## デバッグログ

- Debug ビルド時の再生調査ログ:
  - `マイドキュメント\VideoMiner\VideoMiner_playback_debug.log`
- 主に見るタグ:
  - `audio_pump`
  - `audio_tempo_fallback`
  - `playback_tick`
  - `seek`
  - `audio_start`
  - `paint`
- サムネイルやフリーズ系を再調査する場合は、先にログ量を絞り、UI スレッド上での動画デコード、PNG 読み込み、フォルダ履歴描画、VCL タイマー再入を分けて測る。

## コメントルール

- コメントは、処理を読めば分かることではなく、目的、責務、注意点、状態の意味を補うために書く。
- 古い仕様や現在の実装と食い違うコメントは、見つけた時点で更新する。
- 不要なコメントや重複したコメントを増やしすぎない。
- `var` ブロック内にローカル関数やローカル手続きを内包しない。必要な補助処理は同じ `implementation` 内の独立した関数/手続きとして切り出す。
- ユニット先頭には、そのユニットの目的や担当範囲を `//` コメントで記述する。
- フィールドや定数のコメントは右側に 1 行で置き、同じブロック内では `:`、`=`、`//` の位置を揃える。
- コメントと対象の宣言/実装の間には空行を入れない。
- `property`、`procedure`、`function` 宣言は、横幅 112 文字以内に収まる場合は折り返さない。

## 保守メモ

- このファイルには課題以外の最新状態説明を増やさない。
- 仕様、操作、構成などの説明は `README.md` へ置く。
- 日付付きの作業記録、試行錯誤、調査結果は `HISTORY.md` へ置く。
- 課題が完了したら、完了内容を `HISTORY.md` へ移し、このファイルから削る。
