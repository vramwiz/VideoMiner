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
   - `VIDEOMINER_D3D11_DISPLAY=1` の実験経路で、再生中だけ NV12 を D3D11 swap chain へ直接表示し、CPU BGRX32 変換をスキップできるようにした。
   - 4K30 QSV では `next_convert` p50 が約 15.4ms から約 2.7ms、`playback_tick` p50 が約 20.5ms から約 7.9ms へ改善したため採用方針。
   - D3D 実表示へ中央 fit / letterbox を追加した。4K30 QSV では `d3d11_display_present total_ms` p50 約 2.6ms、`playback_tick` p50 約 11.0ms で、clear 追加コストは p50 約 0.01ms。
   - 回転が必要なフレームは現時点では D3D 実表示を使わず、既存 CPU BGRX32 経路へ戻す。
   - D3D shader の NV12 -> RGB を BT.709 limited range 前提に補正した。4K30 QSV のログでは `range=1`、`space=2`。色空間が未指定扱いの可能性があるため、BT.601 / BT.709 / BT.2020 / full range の分岐は後続課題。
   - D3D backbuffer の上へ VCL/GDI overlay を直接重ねるとちらつくため不採用。overlay / seek bar / seek preview / safe area / loading / zoom が必要な間は CPU BGRX32 + GDI 描画へ戻す。
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
