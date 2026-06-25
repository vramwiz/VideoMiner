# VideoMiner History

日付ごとの実装履歴と調査記録。現在の設計や作業再開時の要点は `note.md` を参照する。

## 2026-06-25 ソフトウェアデコード表示の D3D 経路追加
- ソフトウェアデコードとハードウェアデコードで seek bar / overlay GUI を二重実装しない方針に合わせ、CPU BGRX32 frame を D3D texture へ upload して表示する経路を追加した。
- 既存の NV12 D3D 表示が成功した場合はそのまま使い、NV12 D3D 表示に乗らなかった CPU fallback frame だけを `DXGI_FORMAT_B8G8R8A8_UNORM` texture として D3D backbuffer へ描く。
- BGRX32 表示でも既存の `TD3D11SeekBarOverlayState` と `DrawSeekBarOverlay` を使い、動画本体と seek bar を D3D 側で合成してから `Present` する。
- `PresentCurrentNv12TextureFrame` は直近 frame が BGRX32 upload 由来の場合も再描画できるようにし、停止中 hover などの overlay 再 Present でも同じ保持 frame を使えるようにした。
- VCL `TBitmap.ScanLine` の負 stride に備え、BGRX32 upload 前に必要な場合だけ連続バッファへ詰め直す。
- 初回実行ログで `d3d_decode_state allowed=True` なのに `d3d11_display_present_bgrx32` が出ない状態を確認した。原因は、デコード呼び出し終了時の `SetNv12TextureD3DDisplayAllowed(False)` の後に BGRX32 D3D Present を呼んでいたため、BGRX32 Present が入口で拒否されていたこと。
- BGRX32 Present 呼び出し中だけ D3D display allowed を再度有効にし、失敗時は従来どおり CPU/GDI fallback へ進むようにした。
- `C:\Users\zan12\Videos\x_31.mp4` で Debug 実行し、再生中のソフトウェアデコード経路でも `d3d11_display_present_bgrx32 ... overlay=True` と `paint_skip_d3d_frame` が出ることを確認した。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - Win64 Release: 成功、エラー 0。既存の hint 警告は残る。
  - `tools\EnsureUtf8Bom.ps1 -Check`: 既存の `Source/App/VideoMinerMainForm.dfm` が UTF-8 BOM ではないため失敗。今回変更したファイルは該当しない。

## 2026-06-25 終端停止後の再生再開
- 終端到達で停止した後に Space または再生ボタンを押しても反応がないように見える問題を修正した。
- 終端停止時の表示位置は `SeekMaxMs` ではなく `LastFrameSeekPositionMs` になるため、`PlayFromCurrentPosition` の先頭戻し判定を `SeekMaxMs` 以上から最終フレーム表示位置以上へ変更した。
- これにより、Stop 動作で最終フレームに止まった状態からの再生操作は先頭フレームへ戻してから再生開始する。
- D3D seek bar 移行中の `HIDE_LEGACY_SEEK_BAR_PAINT=True` により、停止中は hover で `FSeekBarVisible=True` になっても GDI seek bar が描かれない状態だったため、停止中だけは旧 GDI seek bar 描画を許可した。
- ただし停止中 fallback 描画が旧フル UI に戻って見えたため、`HIDE_LEGACY_SEEK_BAR_PAINT=True` 中の GDI seek bar 描画は停止中でも compact 表示へ寄せた。
- 旧 `TVideoMinerOverlaySeekBar.Paint` に入る限り旧表示へ戻りやすいため、`HIDE_LEGACY_SEEK_BAR_PAINT=True` 中は旧 Paint を呼ばず、`TVideoMinerVideoSurface.DrawMigratedSeekBarFallback` で移行済み表示に近い fallback を描くようにした。旧 seek bar は hit test / 操作 / 参考実装として残す。
- 停止中 fallback の全面角丸パネルが旧 UI の土台のように見えたため、移行済み表示ではパネル背景を描かず、track / ノブ / 操作表示だけを描くようにした。
- fallback 側に残した `Vol` / 速度 / `Stop` / `Check` / `-` / `+` / 全画面の簡易表示も旧 UI っぽく見えるため、停止中 fallback では描かず、track / ノブ / 中央時刻だけに絞った。
- 中央時刻だけが半端に残り、track が映像上へ寄って見えにくかったため、停止中 fallback は下端の track / ノブだけを描くようにした。
- それでも fallback の横バー自体が旧表示の残りに見えるため、`HIDE_LEGACY_SEEK_BAR_PAINT=True` 中は GDI fallback seek bar を描かないようにし、旧っぽい描画入口を完全に塞いだ。停止中に新 D3D seek bar を表示するには、停止中フレームを D3D backbuffer へ載せる経路が別途必要。
- 起動直後の停止フレームでも新 D3D seek bar を出せるように、指定位置の `ShowFrameAt` でも回転なしなら NV12 frame を D3D backbuffer へ同時に Present するようにした。
- D3D probe に保持中の NV12 texture を再描画する `PresentCurrentNv12TextureFrame` を追加し、seek bar の hover / 表示切替だけで動画と現在の D3D seek bar overlay を再 Present できるようにした。
- 停止中の `seek_bar_visible_while_paused` ブロックを外し、`UpdateD3DSeekBarOverlayState` も再生中限定ではなく停止中 hover / drag の状態を D3D 側へ渡すようにした。
- hover preview など表示目的でない seek decode がD3Dへ誤表示しないよう、D3D display allowed は各デコード呼び出し中だけ有効にし、終了時に必ず戻すようにした。
- 確認:
  - `tools\EnsureUtf8Bom.ps1 -Check`: 成功。
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-25 D3D seek bar の Check 表示移設
- 旧 GDI seek bar から新 D3D seek bar への段階移設として、Check 中の表示を D3D 側へ渡すようにした。
- `TD3D11SeekBarOverlayState` に `CheckEnabled` / `FrameStepMs` を追加し、Check 中は D3D overlay の中央表示を時刻ではなくフレーム番号形式 `current / max` へ切り替える。
- `TVideoMinerVideoSurface.UpdateD3DSeekBarOverlayState` で旧 seek bar の Check 状態と frame step を D3D overlay state へ反映する。
- Check 状態、frame step、チャプター一覧の変更時も、D3D seek bar 表示中なら overlay state を即更新するようにした。
- 音量表示の第一段階として、D3D seek bar 左下に音量レールを描くようにした。
  - `TD3D11SeekBarOverlayState` に `VolumePercent` / `Muted` を追加し、通常時は水色、ミュート時は赤寄りの塗りで状態を示す。
  - 音量変更とミュート変更時も、D3D seek bar 表示中なら overlay state を即更新する。
- ユーザー確認で seek bar がやや下へ寄って見えたため、共有レイアウトの下余白を少し増やし、GDI/D3D の表示位置と入力判定をまとめて上へ寄せた。
- 再生速度表示を D3D seek bar へ移した。
  - `TD3D11SeekBarOverlayState` に `PlaybackRateText` を追加し、旧 seek bar の速度表示文字列を渡すようにした。
  - D3D の簡易文字描画へ `.` と `x` を追加し、右下に `1.0x` などを表示する。
  - 等倍以外の速度では文字を黄色寄りにして、通常速度と区別しやすくした。
- 基準スクリーンショットに合わせ、D3D 側の音量/速度表示を旧 GDI の左下クラスタへ寄せた。
  - `Vol 100%` の表示、音量レール、ミュートアイコン、`1.0x` を旧 UI と同じ並びにした。
  - D3D の簡易文字描画へ `V` / `o` / `l` / `%` を追加した。
  - 速度表示は右下ではなく、ミュートアイコン右側の旧 `PlaybackRateButtonRect` 相当位置へ移した。
  - ユーザー確認で `Vol` 表示が小さめに見えたため、音量ラベルを 2px スケールへ上げた。
  - `%` の点が小さく `/` に見えやすかったため、上下の丸部分を太らせた専用描画へ変更した。
- 終端到達時動作表示を D3D seek bar へ移した。
  - `TD3D11SeekBarOverlayState` に `EndActionText` を追加し、旧 seek bar の `Loop` / `Stop` などの表示文字列を渡すようにした。
  - D3D の簡易文字描画へ `P` を追加し、旧 `EndActionButtonRect` 相当位置へ表示する。
- `Loop` の末尾は大文字 `P` より小文字風の方が自然に見えたため、`p` 専用描画を追加した。
- チャプター追加/削除表示を D3D seek bar へ移した。
  - D3D の簡易文字描画へ `+` / `-` を追加し、旧 `AddChapterButtonRect` / `DeleteChapterButtonRect` 相当位置へ表示する。
- 全画面ボタン表示を D3D seek bar へ移した。
  - `TD3D11SeekBarOverlayState` に `FullScreen` を追加し、旧 seek bar の全画面状態を渡すようにした。
  - 旧 `FullScreenButtonRect` 相当位置へ、通常時は四隅へ広がる矢印、全画面中は中央へ戻る矢印を描く。
- `Check` 表示を D3D seek bar へ移した。
  - D3D の簡易文字描画へ `C` / `h` / `e` / `k` を追加し、Check 中は赤寄りに強調する。
- 再生中 D3D 表示で下段操作群が消えるケースがあったため、音量/速度/Loop/チャプター/全画面の行位置は旧 GDI に近い seek bar パネル下端基準へ戻した。
- 確認:
  - Win64 Release: 成功、エラー 0。既存の hint 警告は残る。

## 2026-06-25 起動時前回ファイル復元後の D3D seek bar 対策
- 原因:
  - 通常のファイル open は `OpenAndPlayFile -> LoadVideoFile(..., True)` で自動再生する。
  - 起動時の前回ファイル復元だけは `OpenRememberedFile -> LoadVideoFile(..., False)` で、自動再生せず停止状態の 0 フレーム目を CPU/GDI で表示する。
  - 現行の新 D3D seek bar は再生中の D3D backbuffer に合成する方式なので、起動直後の停止状態で下部バーを出すと旧 VCL/GDI UI になる。
  - さらに停止中の hover preview や中央 overlay が残ると、再生開始直後も `seek_preview_visible` / `center_overlay_visible` で D3D へ入りにくい。
- 対策:
  - 停止中 overlay を閉じる処理を `HidePlaybackStartOverlays` として分離し、ユーザー操作の `PlayFromCurrentPosition` 直前だけで呼ぶようにした。
  - 前回ファイル復元を勝手に自動再生する挙動には変えず、ユーザーが再生開始した後に D3D seek bar へ移れるようにした。
  - 停止中の旧 GDI seek bar が表示されたまま再生開始すると、同じ位置で新 D3D seek bar へ切り替わって違和感が出るため、再生開始時は旧 seek bar も一度閉じるようにした。再生中に改めてシークバー領域へ hover した時に D3D seek bar を出す。
  - `SetPlaybackActive(True)` に直接置くと、ループや内部再開のような再生継続でも seek bar が一度消える可能性があるため、再生状態フラグの変更だけでは overlay を閉じないようにした。
  - ループ先頭フレームキャッシュは `TryPresentLoopFrameCache -> PresentImmediate` で CPU/GDI 描画を通るため、再生中でも一瞬だけ旧フル seek bar が描かれることがあった。
  - `TVideoMinerOverlaySeekBar.CompactPlaybackStyle` を追加し、再生中の CPU/GDI fallback では D3D seek bar に近い簡易表示だけを描くようにした。
  - これにより、ループ直後や内部的な CPU frame 即時表示でも、旧 `Vol / 1.0x / Check / Loop` 付きのフル UI へ見た目が戻りにくくした。
  - 追加確認で、終端到達の loop 経路では EOS 検出時に一度 `PlaybackActive=False` になり、その後の loop cache 表示時だけ停止中扱いで旧 UI が描かれることが分かった。
  - `FinishAtEnd` の loop 再開では cache 表示前に `PlaybackActive=True` へ戻し、`SetPlaybackActive` で D3D seek bar overlay state も再同期するようにした。
  - `PresentImmediateAsPlaybackFallback` を追加し、loop cache の CPU/GDI 即時表示は一時的に compact seek bar 描画を強制するようにした。
  - さらに loop cache 表示直後の通常 `Paint` が 1 frame だけ GDI compact seek bar を描いていたため、直近 D3D frame の表示時刻を surface 側で保持するようにした。
  - D3D 表示から 1 秒以内で、再生中かつ seek bar 表示中なら、FFmpeg 側の `Nv12TextureD3DFramePresented` が EOS 判定で一時的に落ちていても `Paint` は GDI 描画せず `paint_skip_d3d_frame` で backbuffer を維持する。
  - ユーザー確認で、loop 時に旧/compact GDI seek bar へ切り替わる違和感が解消した。
- 確認:
  - `tools\EnsureUtf8Bom.ps1 -Check`: 成功。
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - Win64 Release: 成功、エラー 0。既存の hint 警告は残る。

## 2026-06-25 D3D11 seek bar が出ない環境の切り分けログ
- ユーザー環境で新しい D3D seek bar が出ず、旧 VCL/GDI の下部 UI に見える状態を切り分けるため、Release でも出る軽量 D3D ログを追加した。
  - `WriteVideoMinerD3DLog` / `VideoMinerD3DLogEnabled` を追加した。既定で有効だが、出す側で状態変化または約 1 秒ごとに間引く。
  - `TVideoMinerVideoSurface.D3DFramePresentationBlockReason` を追加し、D3D 直接表示を止める理由を `source_has_alpha`、`center_overlay_visible`、`seek_bar_visible_while_paused`、`seek_preview_visible`、`safe_area_visible`、`loading_active`、`zoom_active`、左右ナビ表示などへ分けた。
  - `d3d_surface_state` で、再生状態、seek bar、hover preview、中央 overlay、safe area、loading、zoom、alpha、左右ナビ、client size を出すようにした。
  - `d3d_decode_state` で、デコード側の D3D 許可理由を `ready`、`rotation_not_zero`、`loop_frame_capture_active`、`surface_not_ready` などへ分けた。
  - `d3d11_display_present_lite` を追加し、Release でも D3D present の有無、overlay 表示、dragging、swap chain 再作成、total time を低頻度で確認できるようにした。
- 期待する見方:
  - 新 D3D seek bar が出ている時は、再生中 hover で `d3d_surface_state ... reason=ready`、`d3d_decode_state allowed=True reason=ready`、`d3d11_display_present_lite ... overlay=True` が出る。
  - 旧 UI に戻る時は、`seek_bar_visible_while_paused`、`seek_preview_visible`、`center_overlay_visible`、`rotation_not_zero` など、退避理由がログに残る。
- 確認:
  - `tools\EnsureUtf8Bom.ps1 -Check`: 成功。
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - Win64 Release: 成功、エラー 0。既存の hint 警告は残る。

## 2026-06-25 D3D11 seek bar overlay
- D3D11 実表示を既定で有効にした。
  - これまでは Debug 実行時に `VIDEOMINER_D3D11_DISPLAY=1` が必要だったが、通常起動でも D3D11 実表示経路を試すようにした。
  - アプリ起動時に `VIDEOMINER_D3D11_DISPLAY` が未指定ならプロセス環境変数へ `1` を入れ、IDE/通常ビルドからの起動でも同じ前提にした。
  - 切り戻し用に `VIDEOMINER_D3D11_DISPLAY=0` / `off` / `false` の明示指定では D3D11 実表示を無効化できる。
  - env なしの起動で `d3d11_display_present` 188 回、`d3d_presented=True` 188 回を確認した。
  - 起動時に env を補完する変更後、env 未指定の起動で `d3d11_display_present` 187 回、`d3d_presented=True` 187 回を確認した。
  - `VIDEOMINER_D3D11_DISPLAY=0` では `d3d11_display_present` 0 回、`d3d_presented=True` 0 回で、従来描画へ戻ることを確認した。
- `VIDEOMINER_D3D11_DISPLAY=1` の D3D11 実表示中に、再生中の簡易 seek bar を D3D backbuffer 上へ合成する経路を追加した。
  - `FFmpegD3D11TextureProbe.pas` に単色矩形描画用の vertex/pixel shader、constant buffer、alpha blend state を追加した。
  - `TVideoMinerVideoSurface` から seek bar の bounds、track、現在位置、動画長、チャプター位置を D3D 側へ渡すようにした。
  - 再生中の `FSeekBarVisible` だけなら `CanUseD3DFramePresentation=True` を維持し、VCL/GDI の seek bar 描画へ戻らず `paint_skip_d3d_frame` のままにした。
  - 矩形 overlay shader は D3D 表示初期化時に先に作り、再生中に初めて seek bar へ hover した瞬間の shader compile スパイクを避けるようにした。
  - フレーム 0 だけ seek bar が下へずれることがあったため、D3D 許可判定直前に target window と overlay 座標を毎回同期するようにした。
  - クリック/ドラッグ中も D3D overlay state を即時更新し、D3D ログへ `dragging` を出すようにした。ドラッグ中は D3D 側のノブを少し大きく描く。
  - D3D 簡易 seek bar の見た目を調整した。トラック影、進捗ハイライト、チャプターの小さな足、ノブのハローと芯を矩形合成で追加した。
  - D3D overlay state へ hover/drag 位置を追加し、hover 中は薄い縦ガイド、drag 中は強い縦ガイドを出すようにした。
  - D3D 簡易 seek bar に現在位置 / 動画長の時刻表示を追加した。D3D 側でフォントを持たず、矩形だけで小さな 7-segment 風数字を描く。
  - シーク位置ノブは四角ではなく丸が理想のため、D3D 側の矩形描画だけで段付きの円形近似に変更した。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VIDEOMINER_D3D11_DISPLAY=1` / `VIDEOMINER_DEBUG_LOG=1` / `VIDEOMINER_SLOW_LOG=1` で計測した。
  - 修正前の参考値: `d3d11_display_present total_ms` p50 約 2.29ms / p95 約 2.82ms、`playback_tick total_ms` p50 約 10.35ms / p95 約 13.73ms。
  - 修正後の seek bar hover 測定: `overlay=True` 563 frame、`paint_skip_d3d_frame` 693 回、`d3d_presented=True` 752 回 / `False` 12 回。
  - 修正後の `overlay_ms` は p50 約 0.028ms / p95 約 0.040ms / max 約 0.224ms。
  - 修正後の `d3d11_display_present total_ms` は overlay=True p50 約 2.74ms、overlay=False p50 約 2.74ms で、overlay 合成自体の継続コストはほぼ無視できる範囲。
  - ドラッグ操作中のログでは `dragging=True` 66 frame、`overlay_ms` p50 約 0.023ms / p95 約 0.038ms、`d3d11_display_present total_ms` p50 約 2.44ms。
  - 見た目調整後のドラッグ確認では `overlay=True` 215 frame、`dragging=True` 61 frame、`overlay_ms` p50 約 0.039ms / p95 約 0.059ms。
  - hover/drag ガイド追加後は `overlay=True` 259 frame、`dragging=True` 69 frame、`overlay_ms` p50 約 0.034ms / p95 約 0.067ms。
  - 時刻表示追加後のドラッグ確認では `overlay=True` 194 frame、`dragging=True` 36 frame、`d3d_presented=True` 272 回 / `False` 6 回。
  - 時刻表示追加後の `overlay_ms` は overlay=True p50 約 0.119ms / p95 約 0.183ms、dragging=True p50 約 0.100ms / p95 約 0.166ms。
  - 同ログの `d3d11_display_present total_ms` は overlay=True p50 約 2.32ms / p95 約 3.06ms、overlay=False p50 約 2.03ms / p95 約 2.82ms。
  - 丸ノブ近似後のドラッグ確認では `overlay=True` 201 frame、`dragging=True` 39 frame、`d3d_presented=True` 279 回 / `False` 6 回。
  - 丸ノブ近似後の `overlay_ms` は overlay=True p50 約 0.174ms / p95 約 0.250ms、dragging=True p50 約 0.191ms / p95 約 0.211ms。
  - 同ログの `d3d11_display_present total_ms` は overlay=True p50 約 2.52ms / p95 約 3.22ms、overlay=False p50 約 2.33ms / p95 約 3.37ms。
- 残り:
  - 今回の D3D overlay は簡易表示のみ。テキスト、ボタン、音量 UI、細かい hover 状態は従来 GDI 表示のまま後続課題。
  - 絶対値の `playback_tick` は測定回ごとの揺れがあるため、今後は overlay=True/False の同一ログ内比較を優先する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 direct display overlay gate
- `VIDEOMINER_D3D11_DISPLAY=1` の D3D11 実表示中に、overlay / seek bar / seek preview / safe area / loading / zoom が必要な状態では D3D 直接表示を使わず、従来の CPU BGRX32 + GDI 描画へ戻すゲートを追加した。
  - D3D backbuffer の上へ VCL/GDI overlay だけを直接重ねる案を試したが、D3D `Present` が次フレームで GDI 描画を上書きするためちらついた。現段階では不採用。
  - `TVideoMinerVideoSurface.CanUseD3DFramePresentation` で、動画本体だけを D3D 表示してよい状態かを判定するようにした。
  - `TVideoMinerVideoView.DecodeNextFrame` の D3D 許可条件へ surface 側判定を追加し、Debug ログへ `surface_ready` を出すようにした。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VIDEOMINER_D3D11_DISPLAY=1` で計測した。
  - マウス操作なし: `d3d11_display_present total_ms` p50 約 2.37ms / p90 約 2.77ms、`next_bgrx32_detail convert_ms` p50 約 3.35ms / p90 約 4.00ms、`playback_tick total_ms` p50 約 10.52ms / p90 約 13.09ms、drop は 0。
  - overlay / seek bar を出した操作あり: `surface_ready=False` が出て、D3D 直接表示から CPU BGRX32 経路へ退避した。4K CPU 変換へ戻るため `playback_tick total_ms` は p50 約 21.47ms まで重くなるが、D3D/GDI 同時描画によるちらつきは避ける方針。
- 判断:
  - 通常再生中の D3D 高速化は維持できているため、overlay 等が不要な場面では D3D 表示を継続採用する。
  - overlay 表示中の高速化まで狙う場合は、VCL/GDI を上に重ねるのではなく、D3D 側で overlay texture / sprite を合成する段階が必要。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 direct display zoom refresh
- D3D11 実表示後に一時停止してホイールズームした場合、CPU 側の最新表示フレームがないまま `Paint` が D3D frame skip してしまう可能性があったため、ズーム操作後に現在位置の CPU frame を再取得する導線を追加した。
  - CPU 表示へ戻る `TVideoMinerVideoSurface.Present` / `PresentImmediate` で `ClearNv12TextureD3DFramePresented` を呼び、D3D 表示済みフラグを残さないようにした。
  - `TVideoMinerVideoSurface` に `FZoomFrameRefreshNeeded` と `ConsumeZoomFrameRefreshNeeded` を追加し、動画面ホイールズームだけをメインフォーム側で検知できるようにした。
  - 一時停止中の動画面ホイールズームでは、`TVideoMinerMainForm.DoMouseWheel` から `ShowFrameAtMs(CurrentPlaybackPositionMs)` を呼び、現在位置を CPU BGRX32 経路で再表示する。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VIDEOMINER_D3D11_DISPLAY=1` で確認した。
  - 再生中に Space で停止し、動画中央でホイールズームしたところ、`main_show_frame_at_begin requested_ms=1770` と `surface_present_immediate` が出て、CPU frame 再表示へ戻ることを確認した。
  - マウス操作なしの通常再生では `d3d11_display_present total_ms` p50 約 2.18ms / p90 約 2.83ms、`next_bgrx32_detail convert_ms` p50 約 2.91ms / p90 約 4.04ms、`playback_tick total_ms` p50 約 9.69ms / p90 約 13.28ms、drop は 0。
- 判断:
  - ズーム中は CPU 描画へ退避するが、通常再生中の D3D 高速化は維持できている。
  - D3D 側でズーム表示まで行う場合は、shader のサンプリング座標へズーム中心/倍率を渡す段階で再検討する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 direct display frame copy refresh
- D3D11 実表示中は CPU 側の `CurrentFrameBitmap` が直近表示フレームではない可能性があるため、現在フレームをクリップボードへコピーする直前に現在位置を CPU BGRX32 経路で再表示するようにした。
  - `TVideoMinerMainForm.CopyCurrentFrameToClipboard` で、停止中かつ動画が開かれている場合に `ShowFrameAtMs(CurrentPlaybackPositionMs)` を呼んでから `CurrentFrameBitmap` を参照する。
  - コピーは元々一時停止中限定のユーザー操作なので、4K の CPU 再変換コストは通常再生の D3D 高速化とは切り分ける。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VIDEOMINER_D3D11_DISPLAY=1` で確認した。
  - 再生中に Space で停止して Ctrl+C したところ、コピー直前に `main_show_frame_at_begin requested_ms=1753`、`bgrx32_convert total_ms` 約 14.07ms、`surface_present_immediate`、`main_show_frame_at_done requested_ms=1753 shown_ms=1753` が出た。
  - D3D 表示済みフラグが残ったまま古い CPU bitmap をコピーする経路ではなく、現在位置の CPU frame を再取得してからコピーへ進むことをログで確認した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 seek hover preview load split
- シークバー hover プレビューの負荷を切り分けるため、`TVideoMinerSeekHoverPreviewController` に要求、再利用、timer 待ち、fast seek、fallback seek、表示反映の Debug ログを追加した。
  - `seek_hover_preview_schedule`: hover 要求を timer へ積んだ時点。
  - `seek_hover_preview_reuse`: 近い位置の既存 preview を再利用した時点。
  - `seek_hover_preview_decode`: timer 発火後の実デコードと表示反映の内訳。
- 再生中はシークバー hover preview のデコードを走らせないようにした。
  - 4K30 D3D 再生中にシークバー上を往復させた計測では、変更前は `seek_hover_preview_schedule` 148 回に対して実デコード 1 回だったが、その 1 回が `fast_ms` 約 348ms あり、UI スレッドを止めるには十分重かった。
  - 変更後、同じ再生中 hover 操作では `seek_hover_preview_schedule` / `seek_hover_preview_decode` ともに 0 回になり、hover preview デコード負荷は再生中から外れた。
  - この時の `playback_tick total_ms` p50 約 23.15ms は、シークバー表示中に D3D から CPU/GDI 描画へ退避する既存ゲートの影響で、hover preview デコードは発生していない。
- 停止中 hover では preview 表示を維持した。
  - Space で停止後にシークバー上を移動した計測では、`seek_hover_preview_decode` 8 回、失敗 0 回。
  - 初回は `fast_ms` 約 276ms、その後は `fast_ms` p50 約 49.15ms / `total_ms` p50 約 51.82ms、`set_ms` p50 約 1.32ms、fallback は 0 回。
- 判断:
  - 体感の大きな引っかかりは preview 表示反映ではなく、hover 用 fast seek/decode が UI スレッドで走ることによる。
  - 再生中の hover preview は停止し、停止中の確認用 preview として使う方針にする。
  - さらに軽くするなら、停止中 hover の update delay を広げる、位置を粗く丸める、または hover 用 decode を worker 化する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 texture upload probe
- `VIDEOMINER_TEXTURE_PROBE=1` の Debug 実行時だけ、QSV の NV12 frame を D3D11 texture へアップロードする計測を追加した。
  - `nv12_texture_probe`: `DXGI_FORMAT_NV12` 1 枚 texture へ渡す方式。FFmpeg の Y/UV plane が連続していない場合は packed buffer へ詰め直してから `UpdateSubresource` する。
  - `nv12_plane_texture_probe`: Y を `DXGI_FORMAT_R8_UNORM`、UV を `DXGI_FORMAT_R8G8_UNORM` の 2 枚 texture へ分けて `UpdateSubresource` する方式。plane 連続化コピーを避けるための比較対象。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VideoDecoderMode=qsv` / `VIDEOMINER_SLOW_LOG=1` / `VIDEOMINER_DEBUG_LOG=1` で約 8 秒再生して計測した。
  - 2 枚 texture upload: `nv12_plane_texture_probe total_ms` p50 約 1.46ms / p90 約 1.78ms、`upload_y_ms` p50 約 0.96ms、`upload_uv_ms` p50 約 0.45ms、`flush_ms` p50 約 0.04ms。
  - 1 枚 NV12 texture upload: `nv12_texture_probe total_ms` p50 約 2.61ms / p90 約 3.16ms。内訳は `pack_ms` p50 約 1.52ms、`upload_ms` p50 約 1.01ms。
  - 同じ QSV 再生中の CPU BGRX32 変換は `bgrx32_convert total_ms` p50 約 14.46ms / p90 約 15.46ms、`sws_ms` p50 約 11.02ms、負 stride 回避 `copy_ms` p50 約 3.35ms。
  - `playback_tick total_ms` は p50 約 25.03ms / p90 約 27.06ms、drop 最大 0。
- `VideoDecoderMode=software` では frame format が `YUV420P(fmt=0)` で、NV12 texture probe は `nv12_texture_probe_skip` になった。
- 判断:
  - QSV の NV12 を CPU BGRA へ変換せず、D3D11 shader 表示へ進める価値は高い。CPU 側だけ見ると、2 枚 texture upload は現行の `sws_scale + copy` より p50 で約 13ms 軽い。
  - 実表示へ入れる場合は、Y/UV 2 枚 texture + shader 合成を第一候補にする。NV12 1 枚 texture は packed buffer が必要になりやすく、今回の入力では余分に約 1.5ms かかった。
  - まだ shader 色変換、swap chain present、overlay 合成、回転/ズーム、コピー機能との統合コストは含んでいないため、次は小さい D3D11 表示 surface で end-to-end の描画時間を測る。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 shader draw probe
- `VIDEOMINER_TEXTURE_PROBE=1` の Debug 実行時だけ、Y/UV 2 枚 texture を pixel shader で NV12 -> RGB 変換して offscreen render target へ描く `nv12_shader_probe` を追加した。
  - 表示本体はまだ VCL/BGRX32 のままにし、通常再生を壊さず shader 表示経路の中核コストだけを測る。
  - fullscreen triangle の vertex shader と NV12 -> RGB pixel shader は `D3DCompile` で初回だけコンパイルする。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VideoDecoderMode=qsv` / `VIDEOMINER_TEXTURE_PROBE=1` で約 8 秒再生して計測した。
  - `nv12_shader_probe total_ms`: p50 約 1.69ms / p90 約 1.96ms。
  - `nv12_shader_probe upload_draw_ms`: p50 約 1.63ms / p90 約 1.89ms。
  - `nv12_shader_probe flush_ms`: p50 約 0.06ms / p90 約 0.07ms。
  - 同じログの現行 CPU 変換は `bgrx32_convert total_ms` p50 約 14.38ms / p90 約 16.59ms、`sws_ms` p50 約 11.03ms、負 stride 回避 `copy_ms` p50 約 3.32ms。
  - shader probe を追加した状態でも `playback_tick total_ms` は p50 約 27.62ms / p90 約 31.06ms、drop 最大 0。
- 判断:
  - QSV 4K30 では、NV12 を CPU で BGRA へ変換する現行経路より、Y/UV 2 枚 texture + shader RGB 変換の方が十分に軽い。
  - 3D texture 表示経路は採用方針で進める。
  - 次段階は offscreen probe ではなく、実際の `TVideoMinerVideoSurface` に D3D11 swap chain を持たせ、`UpdateSubresource + shader draw + Present` の end-to-end 表示時間を測る。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 swap chain present probe
- `VIDEOMINER_TEXTURE_PROBE=1` の Debug 実行時だけ、Y/UV 2 枚 texture を shader で変換して swap chain backbuffer へ描き、`Present(0, 0)` まで測る `nv12_swapchain_probe` を追加した。
  - `TVideoMinerVideoSurface.PrepareBgrx32Frame` から表示 surface の HWND と client size を probe 側へ渡す。
  - 最初に実表示 HWND へ直接 Present したところ、VCL/GDI 描画と競合してかなりちらついたため、計測用は同サイズの非表示 probe window へ Present する方式に変更した。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VideoDecoderMode=qsv` / `VIDEOMINER_TEXTURE_PROBE=1` で約 8 秒再生して計測した。
  - 実表示 HWND へ直接 Present した試行: `nv12_swapchain_probe total_ms` p50 約 2.41ms / p90 約 2.75ms、`present_ms` p50 約 0.47ms。ただし表示ちらつきが大きいため方式としては不採用。
  - 非表示 probe window への Present: `nv12_swapchain_probe total_ms` p50 約 2.40ms / p90 約 3.27ms、`upload_ms` p50 約 1.96ms、`draw_ms` p50 約 0.06ms、`present_ms` p50 約 0.37ms。
  - 同じログの現行 CPU 変換は `bgrx32_convert total_ms` p50 約 14.85ms、`sws_ms` p50 約 11.35ms、負 stride 回避 `copy_ms` p50 約 3.48ms。
  - probe 追加状態の `playback_tick total_ms` は p50 約 31.23ms。drop は 0。
- 判断:
  - Present 込みでも D3D11 texture + shader 表示経路は現行 CPU BGRX32 変換より十分軽く、採用方針を継続する。
  - ただし実表示 HWND へ probe Present を追加するだけでは VCL/GDI と二重描画になり、ちらつくため採用しない。
  - 次段階は `TVideoMinerVideoSurface` に D3D11 表示経路を別管理で追加し、D3D 有効時は動画フレーム本体を GDI で描かない形にして比較する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 direct display experiment
- `VIDEOMINER_D3D11_DISPLAY=1` の Debug 実行時だけ、再生中の NV12 frame を D3D11 swap chain へ直接表示し、CPU BGRX32 変換をスキップする実験経路を追加した。
  - `TVideoMinerVideoSurface.PrepareBgrx32Frame` で渡した HWND / client size を使い、decoder 側で `PresentNv12TextureFrame` を呼ぶ。
  - D3D 表示が成功したフレームでは `CopyFrameToBgrx32BufferCached` を呼ばず、`TVideoMinerVideoView.DecodeNextFrame` 側でも GDI の回転・Present・ループキャッシュ保存をスキップする。
  - seek、サムネイル、scratch frame、明示フレーム表示は安全側で従来の BGRX32 経路のまま残した。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VideoDecoderMode=qsv` で約 8 秒再生して比較した。
  - CPU BGRX32 経路: `next_bgrx32_detail convert_ms` p50 約 15.41ms / p90 約 18.36ms、`bgrx32_convert total_ms` p50 約 14.88ms、`playback_tick total_ms` p50 約 20.47ms / p90 約 24.21ms。
  - D3D11 実表示経路: `next_bgrx32_detail convert_ms` p50 約 2.74ms / p90 約 3.95ms、`d3d11_display_present total_ms` p50 約 2.06ms / p90 約 2.78ms、`playback_tick total_ms` p50 約 7.91ms / p90 約 11.53ms。
  - D3D11 実表示の内訳は `upload_ms` p50 約 1.68ms、`draw_ms` p50 約 0.06ms、`present_ms` p50 約 0.37ms。
  - D3D11 実表示では再生中 197 frame が `d3d_presented=True` になり、通常の `bgrx32_convert` は初期表示側の 1 回だけだった。
  - 両経路とも drop は 0。
- 判断:
  - 4K30 QSV 再生では D3D11 実表示による CPU 変換スキップの効果が大きいため、採用方針で進める。
  - 現段階は実験経路で、表示 target 全体への shader 描画のみ。次は中央 fit / letterbox、回転、overlay、ズーム、シークプレビュー、フレームコピーとの整合を詰める。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 direct display fit and rotation gate
- `VIDEOMINER_D3D11_DISPLAY=1` の D3D11 実表示経路へ、中央 fit / letterbox 表示を追加した。
  - swap chain backbuffer 全体を黒で clear してから、動画と表示 target のアスペクト比で viewport を計算し、その領域だけへ shader 描画する。
  - 3840x2160 を 900x638 target に出す場合は `viewport=0,66,900,572` になり、16:9 の 900x506 表示と上下黒帯になる。
  - `clear_ms` を `d3d11_display_present` ログへ追加した。
- 回転が必要な再生フレームでは、現時点の D3D 実表示を使わず CPU BGRX32 経路へ戻すゲートを追加した。
  - `TVideoMinerVideoView.DecodeNextFrame` で effective rotation が 0 の時だけ D3D 実表示を許可する。
  - 回転対応は今後 shader 側の座標変換か表示面側の統合として別途扱う。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VideoDecoderMode=qsv` / `VIDEOMINER_D3D11_DISPLAY=1` で約 8 秒再生して計測した。
  - `d3d11_display_present total_ms` p50 約 2.59ms / p90 約 2.79ms。
  - 内訳は `upload_ms` p50 約 2.02ms、`clear_ms` p50 約 0.01ms、`draw_ms` p50 約 0.07ms、`present_ms` p50 約 0.46ms。
  - `next_bgrx32_detail convert_ms` p50 約 3.67ms / p90 約 4.01ms。
  - `playback_tick total_ms` p50 約 11.02ms / p90 約 12.56ms、drop は 0。
- 判断:
  - 中央 fit / letterbox の追加コストは小さく、D3D11 実表示の採用方針は維持する。
  - 次は overlay、ズーム、シークプレビュー、フレームコピー機能との統合を順に進める。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 D3D11 loop cache gate and color range correction
- ループ再生で、終端到達時に数フレームだけ前のフレームが表示された後に先頭フレームになることがある、という観察を `note.md` に残した。
  - D3D11 実表示で `DecodeNextFrame` が早期 return すると、ループ先頭フレームキャッシュ保存がスキップされるため、キャッシュ捕捉中だけ D3D 実表示を許可しないようにした。
  - ループ込みの計測では、初回 loop は `loop_frame_cache_miss` だが、その直後に `loop_frame_cache_store` が 4 回発生し、2 回目 loop は `loop_frame_cache_hit` になった。
  - キャッシュ捕捉中の数フレームだけ CPU BGRX32 経路へ戻るため、通常再生中の D3D 高速化とは切り分けられる。
- D3D11 shader の NV12 -> RGB 変換を BT.709 limited range 前提に補正した。
  - 以前は Y を 0..1 のまま扱っていたため、sws の limited range 変換と比べて色味がずれる可能性があった。
  - Y は 16-235、UV は 16-240 相当へ正規化してから BT.709 係数で RGB へ変換する。
  - `d3d11_display_present` ログへ `range` と `space` を追加した。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を Debug Win64 / `VIDEOMINER_D3D11_DISPLAY=1` で約 10 秒再生して計測した。
  - `d3d11_display_present` の先頭ログでは `range=1`、`space=2`。range は limited と判断できるが、colorspace は未指定扱いの可能性があるため、現時点では 4K 入力を BT.709 とみなす暫定対応。
  - `d3d11_display_present total_ms` p50 約 2.09ms / p90 約 2.73ms。
  - `next_bgrx32_detail convert_ms` p50 約 2.93ms / p90 約 3.98ms。
  - `playback_tick total_ms` p50 約 9.56ms / p90 約 12.83ms、drop は 0。
- 判断:
  - limited range 補正後も D3D11 実表示の性能は維持できている。
  - 次に色味をさらに詰めるなら、BT.601 / BT.709 / BT.2020 / full range の分岐を shader constant で渡す形にする。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 loop restart cache prewarm
- ループ再生で「最終フレーム、0 フレーム、最終フレーム、0 フレームの後に再生」のように見える現象への対策を進めた。
  - 終端 loop の cache hit 時は、すでに `TryPresentLoopFrameCache` で 0 フレームを表示しているため、追加の `ShowFrameAtMs(0)` を呼ばず `StartPlaybackAtMs(0, True)` へ進むようにした。
  - 再生開始位置が loop segment start の場合、開始時点の表示フレームを loop 先頭キャッシュへ即保存し、その後の先頭側フレームもキャッシュするようにした。
  - loop restart 側で個別に `BeginLoopFrameCacheCapture` していた処理をやめ、再生開始側へ一本化した。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` / `EndAction=loop` / `VIDEOMINER_D3D11_DISPLAY=1` で約 11 秒再生して確認した。
  - 初回 loop から `loop_frame_cache_hit` になり、`loop_frame_cache_miss` は 0 回。
  - loop 到達時の追加 `main_show_frame_at_begin requested_ms=0` は出なくなり、起動時の初回表示 1 回だけになった。
  - loop 再開直後の `seek_guard_drop target_ms=0 decoded_ms=7800/7833 present=False` は残るが、表示せず破棄している。
  - drop は 0。
- 判断:
  - ログ上は二重の 0 フレーム表示と初回 cache miss は解消した。
  - 実画面でまだ最終フレームが挟まる場合は、D3D backbuffer の再 Present / VCL repaint / seek guard 中の表示状態を追加で見る。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 QSV 表示経路の内訳計測と一時バッファ再利用
- QSV/software の BGRX32 表示経路へ Debug 計測を追加した。
  - `qsv_transfer`: QSV HW frame を CPU frame へ転送した場合の時間。
  - `next_bgrx32_detail` / `seek_bgrx32_detail`: フレーム転送と BGRX32 変換の時間。
  - `bgrx32_convert`: `sws_scale`、負 stride 回避コピー、変換全体時間、temp buffer resize の有無。
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` の QSV 計測では、実フレーム形式は `AV_PIX_FMT_QSV` ではなく `NV12(fmt=23)` で、`av_hwframe_transfer_data` は発生していなかった。
  - QSV の主負担は GPU->CPU 転送ではなく、NV12 -> BGRA の `sws_scale` と負 stride 回避用の一時バッファ確保だった。
- 負 stride 回避用の BGRX32 一時バッファを毎フレーム確保せず、`TFFmpegDecoderContext` に保持して再利用するようにした。
  - 4K30 QSV: `decode_ms` p50 は約 26.3ms から約 19.4ms、p90 は約 30.9ms から約 23.7ms へ改善。
  - 4K30 QSV: `next_convert_ms` p50 は約 23.3ms から約 15.5ms、`bgrx32_convert total_ms` p50 は約 21.5ms から約 14.9ms へ改善。
  - 4K30 QSV: drop は最大 1 から 0 へ改善。
  - 4K30 software: `next_convert_ms` p50 は約 14.4ms から約 7.0ms、`bgrx32_convert total_ms` p50 は約 12.8ms から約 6.4ms へ改善。
- `C:\Users\vramw\Videos\test_out_r.mp4` でも再確認し、縦動画の負 stride 経路は初回だけ `temp_resized=True`、以降は `False` で再利用され、クラッシュせず終了した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 4K30 高負荷テスト動画での GPU/CPU 比較
- `C:\Users\vramw\Videos\videominer_4k30_motion_debug.mp4` を作成し、Debug 版で `VideoDecoderMode=qsv` と `software` を強制して比較した。
  - H.264 High / yuv420p / 3840x2160 / 30fps / 8 秒 / 240 frames / 約 40Mbps。
- QSV 強制:
  - `decoder_open_detail decoder="h264_qsv"`。
  - 初回 `open_done total_ms=1321.258`、`first_frame_ms=320.855`、`start_playback total_ms=545.724`。
  - 再生中 `decode_ms` は p50 約 24.9ms / p90 約 28.9ms / p99 約 35.4ms。
  - `tick_total_ms` は p50 約 26.2ms / p90 約 30.4ms、drop は最大 1。
  - ループ戻りは `video_seek_ms=0.000`、`start_playback total_ms=5.412`。
- software 強制:
  - `decoder_open_detail decoder="software"`。
  - 初回 `open_done total_ms=442.789`、`first_frame_ms=124.086`、`start_playback total_ms=205.829`。
  - 再生中 `decode_ms` は p50 約 45.7ms / p90 約 63.1ms / p99 約 85.8ms。
  - `tick_total_ms` は p50 約 56.3ms / p90 約 535.9ms、drop は p50 で 1、最大 2。
  - ループ戻りは `video_seek_ms=0.000`、`start_playback total_ms=6.342`。
- 結論:
  - 4K30 の高ビットレート H.264 では、QSV は初期化が重いが再生中の decode/tick が 30fps にほぼ収まる。
  - software は初回表示まで速いが、定常再生では decode が 33ms を超えやすく、音声同期待ち・drop・lag が主な負担になる。
  - `paint_ms` は QSV/software とも p50 約 0.9ms で、今回も主因ではない。

## 2026-06-25 縦動画読み込みクラッシュの修正
- `C:\Users\vramw\Videos\test_out_r.mp4` を Debug 版で開くと、初回フレームの BGRX32 変換中に `swscale-9.dll` でアクセス違反が発生することを確認した。
  - 対象動画は H.264 1080x1920、約 30fps、約 5.1 秒。
  - 直前ログでは `seek_bgrx32_copy ... frame=1080x1920 ... stride=-4320` の直後に落ちていた。
- VCL `TBitmap` の負 stride を `sws_scale` へ直接渡すと縦長動画で不安定になるため、BGRX32/BGR24 の packed 変換では負 stride の場合だけ正方向の一時バッファへ変換し、行単位で呼び出し側バッファへコピーするようにした。
- 修正後、同じ `test_out_r.mp4` は 8 秒再生してクラッシュせず、通常終了できた。
  - `media_open_done total_ms=29.764`
  - `open_done total_ms=425.517`
  - ループ戻りの `start_playback total_ms=5.679`、`video_seek_ms=0.000`
  - 再生中 `decode_ms` は p50 約 10.9ms / p90 約 15.9ms、`paint_ms` は p50 約 0.57ms。
- `C:\Users\vramw\Videos\videominer_loop_debug_60fps.mp4` でも再計測し、ループ戻りの `video_seek_ms=0.000` は維持された。
  - `open_done total_ms=415.860`
  - ループ戻りの `start_playback total_ms=4.590`
  - 再生中 `decode_ms` は p50 約 6.5ms / p90 約 10.7ms、`paint_ms` は p50 約 0.63ms。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 デコード経路の段階的改善と計測
- テスト動画 `C:\Users\vramw\Videos\videominer_loop_debug_60fps.mp4` で、修正ごとに Debug ログ計測を行った。
- Step 1: `auto` デコード判定を調整した。
  - 720p/1080p の H.264 では QSV の初期化・転送固定費が勝ちやすいため software を優先するようにした。
  - 4K H.264、1080p 以上の HEVC/AV1、1440p 以上の VP9 は QSV 候補に残した。
  - 対象動画では `auto` が `h264_qsv` ではなく `software` を選ぶようになった。
  - QSV baseline 比で `open_done total_ms` は約 1436ms から約 496ms へ改善した。
- Step 2: 初期ロード時に preview decoder を開かないようにした。
  - seek preview 用 decoder は必要になった時点で既存の `SeekToMs` 経路が遅延 open する。
  - `media_open_done total_ms` は約 39.8ms から約 26.8ms へ改善した。
- Step 3: main decoder で直前に表示したフレームを再生開始へ引き継ぐようにした。
  - preview decoder が未 open の場合は、初回フレーム表示を main decoder で直接行う fallback を追加した。
  - main decoder で表示済みの位置から再生開始する場合だけ、再生開始時の非表示 seek を省略する。
  - ループ戻り時の `video_seek_ms` は約 28ms から 0ms、`start_playback total_ms` は約 32.9ms から約 5.5ms へ改善した。
- 再生中の `paint_ms` は p50 約 0.65-0.75ms 程度で、今回の動画では TBitmap/GDI 描画が主因ではないと判断した。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-25 サムネイル選択と再生開始表示の調整
- サムネイル一覧の通常動画タイルは、シングルクリックで選択状態にし、ダブルクリックで動画へ切り替える操作へ変更した。
- キーボードの `Enter` は従来通り、選択中タイルを開く操作として維持した。
- サムネイルから別動画を開くときは、デコード開始前にサムネイル一覧を閉じるようにした。
  - 動画表示面へ先に戻すことで、`LoadVideoFile` 内の Loading 表示がすみやかに見えるようにした。

## 2026-06-25 デコード負荷とサムネイルクリック対策
- BGRX32 変換で毎フレーム `TBytes` の一時バッファを確保してから表示バッファへコピーしていた処理を、呼び出し側の表示バッファへ `sws_scale` で直接出力するようにした。
- 動画表示用 Bitmap を次フレームデコード前に毎回全消去していた処理を外し、デコード成功時の全画素上書きだけにした。
- サムネイル通常タイルの起動処理を `ActivateTile` にまとめ、マウスのダブルクリックと `Enter` 操作を同じ経路に揃えた。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-24 Smart App Control / Inno Setup 対策
- ZIP 展開版の起動は問題ないため、アプリ本体より Inno Setup 版インストーラの評価が原因である可能性が高いと判断した。
- Smart App Control で疑われやすい挙動を減らすため、FFmpeg DLL 読み込み処理を見直した。
  - `SetDllDirectory` でプロセス全体の DLL 探索パスを変更する処理を廃止した。
  - FFmpeg DLL は実行ファイルフォルダ内のフルパスを `LoadLibraryEx` + `LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR` / `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS` で明示ロードするようにした。
- Inno Setup スクリプトを Smart App Control の切り分け用に低刺激化した。
  - インストール先を `Program Files` からユーザー領域の `{localappdata}\Programs\VideoMiner` に変更し、`PrivilegesRequired=lowest` を指定した。
  - HKCR の動画ファイル関連付け登録を外した。
  - インストール後の自動起動を外した。
  - スタートメニュー項目名の文字化けを ASCII 表記に修正した。
- ZIP 版で問題がないため、サムネイルディスクキャッシュの新規保存は通常通り有効のままとした。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。
- `Release Win64` ビルド成功。既存の Release 固有ヒント警告は残るが、エラーは 0。
- Inno Setup 6.7.0 で `Setup\Output\VideoMiner_Setup.exe` の生成成功。

## 2026-06-24 アップデート直後の初回起動フリーズ対策
- アップデート直後またはインストール先変更直後の初回起動だけ、前回動画の自動復元をスキップするようにした。
- 背景:
  - ZIP 展開版は問題なく、Inno Setup 版のアップデート直後 1 回目だけ固まり、2 回目以降は正常という症状。
  - 未署名 EXE/DLL の初回検査やインストール直後のファイルスキャンと、前回動画の自動ロードが重なると UI が固まって見える可能性が高い。
- `VideoMiner.ini` の `[VideoMiner] StartupExePath` に起動 EXE パスを保存し、初回またはパス変更時は自動復元を行わず、次回以降は従来通り前回動画を復元する。

## 2026-06-24 動画再生が少し遅く感じる問題の調査と対策
- 最後に再生した `\\taketani\bbb\Balloon\test4ff182g.mp4` を Debug 版で開き、`VIDEOMINER_DEBUG_LOG=1` / `VIDEOMINER_SLOW_LOG=1` / `VIDEOMINER_RATE_LOG=1` で再生ログを取得した。
- 実際のデコードは `h264_qsv` で、Intel QSV が使われていた。
- 修正前ログ:
  - `TimerPlayback.Interval=33` に対して実発火間隔は平均約 47.2ms。
  - デコード自体は中央値約 8.4ms で 30fps の 33ms 枠内。
  - 205 tick 中 82 tick でフレーム drop が発生し、表示更新が粗くなっていた。
- 原因はデコード速度ではなく、VCL `TTimer` の発火が 30fps 再生には粗く、映像 tick が音声時計に対して遅れやすいこと。
- 対策:
  - 再生中だけ `timeBeginPeriod(1)` を要求し、停止時に `timeEndPeriod(1)` で戻すようにした。
  - 再生 timer interval をフレーム時間の半分にし、音声位置より映像が少し先行している場合はその tick のデコードを待つようにした。
- 修正後ログ:
  - 表示 tick 間隔は平均約 33.7ms。
  - デコード中央値は約 6.9ms。
  - フレーム drop は合計 3 回まで減少。

## 2026-06-24 フォルダ履歴タイルの過去フォルダ代表サムネイル修正
- サムネイル一覧 1 行目のフォルダ履歴で、現在開いているフォルダ以外の履歴タイルに代表サムネイルが表示されない問題を修正した。
- 原因は `DrawFolderHistoryTile` が現在フォルダ以外では `RepresentativeList := nil` にしており、過去フォルダの代表ファイル一覧を作らないまま描画していたこと。
- 履歴フォルダごとの代表サムネイル用 `TVideoMinerMediaList` を `TObjectDictionary` でキャッシュし、現在フォルダ以外でも代表ファイル一覧を使って履歴タイルを描けるようにした。
- `Del` で履歴を削除した時は対象フォルダの代表一覧キャッシュを削除し、`F5` 更新時は代表一覧キャッシュ全体を作り直すようにした。
- フォルダ履歴タイルの左端も通常サムネイルグリッドと同じ列計算へ揃え、ウィンドウ幅に応じて下段タイルと同じ基準で並ぶようにした。
- フォルダ履歴タイルは現在の列数ぶんだけ描くようにし、右端に次の履歴タイルが半端にはみ出して見えないようにした。
- `note.md` の優先課題を更新し、サムネイル worker 化とループ再生のさらなる滑らか化は優先度を下げた。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-24 1.5倍速再生の音声遅延軽減
- `D:\VoiceroidProj\main_14\60\proj14_60_01.mp4` を Debug Win64 で起動し、1.5倍速再生時の `VideoMiner_playback_debug.log` を確認した。
- 修正前は `audio_ms - video_ms` は大きく累積していなかったが、`audio_pump_rate` の `queued_after_ms` が平均約 608ms あり、waveOut へ先行投入した音声キュー分だけ実際の出音が遅れて聞こえる可能性が高かった。
- `TVideoMinerAudioPlayback.TargetQueueMs` を追加し、1.0倍速では従来どおり 600ms、倍速再生では 220ms を目標キュー長にするよう変更した。
- `audio_pump_rate` ログへ `target_queue_ms` を追加し、倍速再生中の目標キュー長を確認しやすくした。
- 修正後の Debug Win64 ビルドで同じ動画を 1.5倍速再生し、`queued_after_ms` が平均約 230ms、最大 248ms に下がることを確認した。
- 追加確認で、1.5倍速では映像が速く進み、音声が累積して遅れることが分かった。
  - 原因は `atempo` を小さな PCM 断片ごとに作成して flush していたため、1.5倍速の理論値である `output / input = 0.666...` に対して、実測が約 0.783 になっていたこと。
- `atempo` 後の PCM を線形リサンプリングで補正する案は、音声ピッチが変わるため撤回した。
- `atempo` の出力長が理論値から外れる場合に既存の簡易 time-stretch へフォールバックする案も、音が荒れるため撤回した。
- 音声変換は音質を優先し、元の `atempo` 出力をそのまま使う状態へ戻した。現時点で残す変更は、倍速再生中の waveOut キュー長を 220ms へ下げる部分だけとする。
- 音を加工せずに累積ズレを避けるため、映像側の基準位置を理想時計ではなく waveOut の実再生済み出力サンプルから求めるよう変更した。
  - `atempo` の出力が理論値より長い場合でも、出力サンプル数と入力サンプル数の比率から元動画上の音声位置を推定する。
  - これにより、映像は「指定倍率の理想時刻」ではなく「実際に鳴っている音声位置」へ追従する。
  - 同じ動画の 1.5倍速ログでは、`atempo` の実効音声速度が約 1.26倍で、映像もその音声位置に追従して累積ズレを抑える状態になった。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-24 マウス戻る/進むボタンの前後動画移動
- `Application.OnMessage` で子コントロールへ届いた `WM_XBUTTONDOWN` を受け取り、マウスの戻るボタンを前の動画、進むボタンを次の動画へ割り当てた。
- 動画表示面へ `WM_XBUTTONDOWN` が届いてメインフォームのメッセージハンドラだけでは拾えないケースを確認し、アプリ全体のメッセージフック経由で処理するようにした。
- 入力フック内で直接動画読み込みを始めると `Application.ProcessMessages` による再入で Loading 表示や再生状態が崩れる可能性があるため、`WM_VM_NAVIGATE` へ `PostMessage` して後段で前後移動を実行するようにした。
- `LoadVideoFile` に読み込み中ガードを追加し、読み込み中に連続した戻る/進む入力が来ても二重読み込みを開始しないようにした。
- 動画読み込み前 cleanup で `StopPlayback` を呼び、Loading 中に旧動画が再生中扱いのまま残らないようにした。
- Loading 中にキュー済みの再生 timer / 再開 timer が処理されても旧動画の decode を進めないよう、`FLoadingVideo` 中は timer 処理を即終了する guard を追加した。
- ブラウザの戻る/進むに近い感覚で、同一フォルダ内の前後動画へ移動できるようにした。

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
- `マイドキュメント\VideoMiner\ThumbnailCache` にサムネイル PNG をディスクキャッシュし、起動後も再利用する。
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

## 2026-06-18 ボスが来たモードをヘルプ兼用画面へ変更
- 素早いマウス往復で表示される VSCode 風の偽装画面を、単なるダミーコード表示ではなく VideoMiner の操作ヘルプとして使うようにした。
- 見た目は VSCode 風のまま、エディタ本文に Markdown 風の操作一覧を表示する。
- ヘルプページは基本操作、確認/チェック、サムネイル一覧、再生ワークフローの 4 ページに分けた。
- 通常表示中は `F1` でも同じヘルプ兼用画面を表示できるようにした。
- ボスが来たモード中は `Up` / `Down` または `PageUp` / `PageDown` でヘルプページを切り替える。
- `Esc` または `Return` キー、画面右下の `Return` ボタンで通常画面へ戻る。
- ページ番号は `TVideoMinerVideoSurface` が保持し、`VideoMinerBossOverlay` は指定ページを描画するだけにした。
- `Debug Win64` ビルド成功。

## 2026-06-18 hover 時のフォーム境界ガイド
- 枠なしの VSCode 風フォームでウィンドウ境界が分かりづらいため、通常時はフラット表示のまま、タイトルバーまたはフォーム端付近にマウスがある時だけ内側にガイド枠を表示するようにした。
- ダーク系 UI 上で黒線が目立ちにくかったため、ガイド枠は白 2px 相当の単色表示にした。
- 標準の非クライアント枠は戻さず、`TPanel` 8 本をフォーム内側へ重ねる軽い実装にした。
- テーマ描画や親背景の影響で黒く見える場合があるため、ガイド枠用 panel は `ParentBackground := False` を明示する。
- `TTimer` でマウス位置を確認し、全画面中とボス/ヘルプ画面中はガイド枠を非表示にする。
- timer だけでは hover 検出が届かない場合があるため、`WM_NCHITTEST` 時にもガイド枠表示を即時更新する。
- 表示確認しやすいようにガイド枠は 2px とし、表示中でも毎回前面へ戻す。
- サイズ変更時は `WM_SIZE` でガイド枠の位置を更新する。
- `Debug Win64` ビルド成功。

## 2026-06-19 フレーム切り替え前の残像対策
- 終端まで再生した後に `Space` で再生し直すと、先頭フレームへ戻るまで終端フレームが一瞬残る現象を確認した。
- 再現手順は、引数なし通常起動で履歴ファイルを停止状態ロード、`Space` 再生、終端停止後に再度 `Space`。
- `TVideoMinerVideoView` は直近の明示表示フレームを位置 ms 付きでキャッシュし、同じ位置へ戻る場合はデコード完了を待たずにキャッシュフレームを即時表示する。
- 再生中シークの再開でも同じ再生開始経路を通るため、`StartAtMs` 側では動画フレームを即時クリアしない。フレームが表示済みかどうかの判断は caller とキャッシュ表示に任せる。
- 再生中にシークバーを触った場合も、停止位置のフレームを残さずシーク先フレームを即時表示するため、`SeekToMs` では高速再開分岐でプレビュー表示を省略しない。
- 終端後に先頭へ戻して再生する場合は、`PlayFromCurrentPosition` が `ShowFrameAtMs(0)` の成否を `StartPlaybackAtMs` へ渡し、先頭フレームの二重表示/二重デコードを避ける。
- 初回再生や一時停止からの再開では、現在表示中フレーム位置と再生開始位置が同じなら表示済みとして扱い、黒表示を挟まないようにした。
- `Debug Win64` / `Release Win64` ビルド成功。
- `Release Win64` の同一再現手順で、初回再生は黒表示を挟まず、終端後の再生し直しでも終端フレームや黒表示を挟まず先頭フレームを維持することを確認した。
- 再生中シーク対策で `SeekToMs` の高速再開を止めた影響により、自動ループ終端でも手動シークと同じ経路を通り、ループ開始直後に別フレームが混ざる現象が出た。
- `Tick` 由来の自動ループだけは `SeekPlaybackTickToMs` でループ開始フレームを明示表示し、その成否を `StartPlaybackAtMs` へ渡して再始動する。手動シークバー操作は引き続き `SeekToMs` 経由でシーク先フレームを即時表示する。
- 手動シークでは、再開直後の seek guard より先に音声追従 `HandleLaggingVideo` が走り、音声位置のフレームを数フレーム表示できる経路が残っていた。`SeekGuardRemaining > 0` の間は音声追従表示を抑え、目的位置の guard 判定を先に通す。
- ループとシークを個別分岐で調整すると片方だけ再発するため、共通の `VideoMinerSeekGuardAccepts` を見直した。従来の ±1500ms 許容は広すぎて目的位置から離れたフレームを表示できたため、目標より前は 5ms、後ろは 120ms までに制限する。

## 2026-06-19 ループ再生の連続性改善案
- 現状のループ再生は、終端到達後にループ開始位置のフレーム表示と音声再開準備を行うため、正しい表示にはなったが「フレームが溜まるのを待つ」ような間が出て連続性が失われやすい。
- ループ開始位置は常に 0ms とは限らず、手動チャプター区間では `LoopSegmentStartMs` / `LoopSegmentEndMs` に従う。改善する場合は、現在のループ区間単位でプリロール対象を決める。
- 第一段階は映像のみのプリロールが現実的。再生中にループ終端へ近づいたら、別デコーダまたは scratch/cache に `LoopSegmentStartMs` のフレームを先に準備しておき、終端到達時は seek/decode 完了を待たずにそのフレームを即表示する。
- 第二段階として、音声も `LoopSegmentStartMs` から短いキューを事前生成できれば、終端到達時に音声出力を即切り替えられる。ただし音声キュー管理が複雑になるため、まずは映像プリロールだけで体感改善を見る。
- 理想形は、ループ区間を小さな仮想タイムラインとして扱い、`LoopSegmentEndMs` 到達時に表示・音声クロックを `LoopSegmentStartMs` へ巻き戻し、再開直後の数フレームだけ事前準備済みフレームを使う方式。
- 実装時は、ループ区間が変わった場合、動画を切り替えた場合、シークやチャプター編集で `LoopSegmentStartMs` が変わった場合に、プリロールキャッシュを破棄または再準備する。

## 2026-06-19 ループ再生 映像プリロール試作
- ループ終端到達時の見た目の待ちを減らす第一段階として、映像のみのプリロールを追加した。
- 再生 tick 中に現在のループ区間終端へ近づいたら、`FPreviewDecoder` を使って `LoopSegmentStartMs` のフレームを `TVideoMinerVideoView` のループ専用キャッシュへ先読みする。
- 先読みは同じ動画ファイル、同じループ開始/終端の組み合わせにつき 1 回だけ試す。失敗時に毎 tick で重い seek/decode を繰り返さないため。
- ループ再開時は、先読み済みフレームがあればそれを即時表示し、なければ従来どおり `ShowFrameAtMs` で開始フレームを表示する。
- メイン再生デコーダと音声再開処理は従来経路を維持し、今回は表示の待ちを減らすところだけに絞った。
- 動画切り替え/再読み込み時は、controller と view のループプリロール状態を明示的に破棄する。
- 変更ファイルは `VideoMinerPlaybackController.pas` / `VideoMinerVideoView.pas` / `VideoMinerMainForm.pas`。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。
- 実動画での体感確認は未実施。もし終端直前に小さな引っかかりが出る場合は、`LOOP_PREROLL_WINDOW_MS` の調整、または非同期プリロール化を次段階で検討する。

## 2026-06-19 ループ再生 プリロール位置調整
- 実動画でループ部分の改善が小さく、少しガクガクする状態が残った。
- 直前の試作は、再生 tick 中にループ終端へ近づいたタイミングで `FPreviewDecoder` の seek/decode を同期実行していたため、終端直前の tick を詰まらせる可能性があった。
- `MaybePrepareLoopPreroll` は再生 tick 中から外し、`StartPlaybackAtMs` でループ区間を `ConfigureLoopSegment` した直後に 1 回だけ準備する方式へ変更した。
- ループ再開時に開始フレームがすでに表示済みで、再開位置が現在の `FLoopSegmentStartMs` と一致する場合だけ、メインデコーダ側の再開 seek を `FastSeek` にするようにした。
- これで再生中の終端直前に重い先読みを挟まない。境界で残るガクつきがある場合は、次に音声再開の同期処理、またはメインデコーダの loop 専用 seek/decode をさらに軽くする方向を見る。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 チャプター位置再生と終端ループ戻り修正
- ループ再生は滑らかになったが、チャプターを付けた位置そのものから再生できない場合があり、少しずらすと再生できる現象を確認した。
- 再生開始側の `StartAtMs` は、プレビュー表示用の `ShowFrameNearMs` と違い、指定位置ぴったりのデコード失敗を近傍位置で救済していなかった。
- `TVideoMinerPlaybackController.ShowPlaybackFrameNearMs` を追加し、再生用メインデコーダでも `0 / ±33 / ±100 / ±250 / ±500 / ±1000 ms` の順に近傍 fallback するようにした。
- fallback で近傍フレームを使えた場合は、再生開始位置と音声開始位置も実際に使えた位置へ揃える。
- チャプター付きループで終端まで行ってもチャプターへ戻らないことがあったため、EOF 経路の `FinishPlaybackAtEnd` では、現在有効な `FLoopSegmentStartMs` があればそれを優先して戻り先にするようにした。
- これにより、最後のチャプター以降の区間でも、終端到達時は現在のループ区間開始位置へ戻る。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 チャプター境界 fallback 順の修正
- チャプター位置ぴったりの再生開始が失敗した場合、近傍 fallback が `-33ms` など目標位置の手前を先に採用していた。
- そのため終端ループ時に一瞬チャプターへ戻っても、実際の再生開始位置がチャプター手前になり、次の `ConfigureLoopSegment` で先頭区間扱いに戻る可能性があった。
- 再生用の `ShowPlaybackFrameNearMs` は fallback 順を `0 / +33 / -33 / +100 / -100 / ...` に変更し、チャプター境界ではまず境界の後ろ側を採用するようにした。
- これにより、チャプター位置そのものがデコードできない場合でも、再生開始位置がチャプター境界をまたいで手前へ戻りにくくなり、終端ループの戻り先が先頭へ化ける経路を抑える。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 先頭ループ時の数フレーム混入調査
- 終端からチャプターへ戻るループは正常になったが、先頭へ戻るループでは戻った直後に数フレーム異なる表示が混ざる現象が残った。
- 原因候補として、`StartPlaybackAtMs` がループ開始フレーム表示済みの場合に `FastSeek` を使う最適化を確認した。
- `DecodeFrameToBgrx32Fast` は通常 seek と違い、目標時刻以降のフレームまで読み進めず、seek 後に最初に取れたフレームを採用する。先頭 0ms では、表示済みの 0ms フレームとメインデコーダの再開位置が数フレームずれる可能性がある。
- 先頭ループでは正確なデコーダ位置を優先するため、`FLoopSegmentStartMs > 0` の場合だけ `FastSeek` を使うように変更した。0ms へ戻る場合は通常 seek で再開する。
- debug log の `start_playback` / `start_playback_done` に `fast_seek` を追加し、再発時に先頭ループが正確 seek になっているか確認できるようにした。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 ループ滑らかさ低下のログ確認
- `VIDEOMINER_DEBUG_LOG=1` / `VIDEOMINER_SLOW_LOG=1` を設定した Debug 実行で、`マイドキュメント\VideoMiner\VideoMiner_playback_debug.log` に詳細ログを出せるようにした。
- `finish_loop_restart` / `show_playback_frame_near` / `seek_guard_accept` を追加し、ループ戻り時に表示した戻りフレーム、再生用デコーダの seek 結果、seek guard が受理した decoded_ms を確認できるようにした。
- 実行ログでは、ループ戻り直後のフレーム位置は `1881 -> 1914 -> 1958 ...` のように戻り先以降へ進んでおり、無関係な前後フレーム混入ではなく、メインデコーダを戻す同期 seek が長いことが主因だった。
- 例として `start_playback_done target_ms=1914 video_seek_ms=974.628 total_ms=976.871` が出ており、表示済みの戻りフレームから次の再生フレームへ進むまで約 1 秒止まっている。
- fallback もすべて fast seek にする実験では、この動画で `Frame could not be decoded.` が続き、`video_seek_ms=3691ms` 以上まで悪化したため採用しない。
- 次に滑らかさを本当に戻す場合は、境界でメインデコーダを同期 seek するのではなく、先読み済みの補助デコーダを再生用デコーダとして使う、または再生用デコーダの再配置を非同期化する方向が必要。

## 2026-06-19 ループ再開直後の余計なフレーム抑制
- 滑らかさは戻ったが、ループ再開直後に余計なフレームが混入する現象を確認した。
- ループ戻りフレームは `PresentLoopPrerollFrame` または `ShowFrameAtMs` ですでに表示済みなのに、直後の `HandleSeekGuard` が受理した `decoded_ms` をさらに `ShowFrameAt` で明示表示していた。
- この guard 側の再表示は、戻り先フレームから通常再生へ進む間に中間フレームを差し込むため、見た目上の混入になり得る。
- `seek_guard_accept` ではフレーム位置だけ内部状態として受理し、画面には出さないように変更した。ログにも `present=False` を出す。
- 戻り先フレームは保持したまま、次の通常 tick の表示フレームから再生を進めるため、滑らかさを残しつつ余計な guard 再表示を抑える狙い。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 1つ前のコミットとの比較結果
- 一時的に現在の作業ツリーを stash し、`HEAD~1` の `259c927 シークジの挙動を安定` へ detached checkout して比較した。
- 比較後、stash を戻して作業状態は復元済み。
- 実動画で比較した結果、現在の修正後よりも `259c927` の方がループ再生は滑らかだった。
- 現在の修正群は、余計なフレーム混入の抑制には効果があったが、このスレッドの本来目的である「滑らかにループする」点では後退している。
- 次の作業方針は、現在のプリロール/seek guard 表示抑制/正確 seek 寄りの調整を前提に積み増すのではなく、`259c927` の滑らかな経路を基準に戻し、そこへ余計なフレーム混入だけを最小限で潰す方向がよい。
- 特に `HandleSeekGuard` の表示抑制、`FastSeek` の制限、メインデコーダの同期 seek 追加/近傍 fallback が滑らかさへ与えた影響を個別に切り分ける。

## 2026-06-19 ループ開始フレーム列キャッシュへ方針変更
- ループ改善の方針を「先読み」から「一度表示したループ開始直後フレーム列のキャッシュ」へ変更した。
- 初回ループの滑らかさは期待せず、初回に実際に通過して表示したループ開始直後のフレームを短く保存する。
- 2 回目以降のループ戻りでは、保存済みフレーム列の先頭付近を即時表示し、戻り直後の余計な表示混入を抑える狙い。
- `TVideoMinerVideoView` は、ループ区間ごとに開始から約 900ms / 最大 24 枚の表示済みフレームを `TBitmap` と位置 ms で保持する。
- キャッシュ対象は、通常再生 tick で本当に画面へ出たフレームだけに限定した。seek guard の内部受理など、画面に出ていないフレームは混ぜない。
- ループ区間、動画ファイル、動画切り替え、再読み込みなどでキャッシュは破棄する。
- 既存の `ClearLoopPreroll` / `PresentLoopPrerollFrame` 名は大きな呼び出し変更を避けるため残したが、中身は補助デコーダによる先読みではなく、表示済みフレーム列キャッシュの管理へ変わった。
- 補助デコーダで `LoopSegmentStartMs` を同期 seek/decode する `MaybePrepareLoopPreroll` は廃止し、現在のループ区間に合わせてキャッシュ受け入れ範囲を設定するだけにした。
- `Debug Win64` / `Release Win64` ビルド成功。警告 0 / エラー 0。
- 実動画での体感確認は未実施。次は 2 周目以降のループ戻りで滑らかさと余計なフレーム混入がどう変わったかを確認する。

## 2026-06-19 ループキャッシュ hit ログ確認と先頭フレーム補正
- `VIDEOMINER_DEBUG_LOG=1` / `VIDEOMINER_SLOW_LOG=1` で Debug 実行し、全体ループの戻りログを確認した。
- 最初のキャッシュ方式では、2 周目以降の戻りで `loop_frame_cache_hit requested_ms=0 cached_ms=42` になっていた。
- 原因は、再生開始時点ですでに表示済みの 0ms フレームをキャッシュへ入れておらず、再生 tick で最初に通過した 42ms フレームがキャッシュ先頭になっていたこと。
- `StartPlaybackAtMs` でループ区間を設定した直後、現在表示済みの `TargetMs` フレームも `CaptureLoopFrameCache` へ渡すようにした。
- これにより再確認ログでは `loop_frame_cache_hit requested_ms=0 cached_ms=0 index=0 delta=0 count=11` になった。
- 戻り直後の `start_playback_done target_ms=0` は `video_seek_ms=11-16ms` 程度で、今回の全体ループでは数秒単位の seek 待ちは出ていない。
- seek guard は `decoded_ms=42 present=False` として内部位置だけ受理し、画面には出さない。表示はキャッシュ済み 0ms から次の通常 tick へ進む。
- シークバーが末端から先頭へ戻る表示が遅く見えないよう、`SeekPlaybackTickToMs` で `FSeekPositionMs` 更新直後に `UpdatePlaybackProgress(PositionMs)` を呼ぶようにした。

## 2026-06-19 チャプター戻りループのキャッシュ確認
- チャプターを追加した状態で、終端からチャプター位置へ戻るループを Debug 実行ログで確認した。
- チャプター位置は `1321ms` だったが、その位置ぴったりは再生用デコーダで直接使えず、実際に表示できる開始フレームは `1354ms` だった。
- 変更前は `loop_frame_cache_hit requested_ms=1321 cached_ms=1354` の後も、再開処理が `requested_ms=1321 target_ms=1321` から探し直しており、`video_seek_ms` が約 1000ms になっていた。
- `PresentLoopPrerollFrame` が実際に表示した `cached_ms` を out 引数で返すようにし、キャッシュ hit 時は `StartPlaybackAtMs` へ `1354ms` を渡すようにした。
- 再確認では `start_playback file=... requested_ms=1354 target_ms=1354` になり、`video_seek_ms` は約 250ms まで下がった。
- cached_ms 付近で fast seek を許可する実験も行ったが、`target_ms=1354` から `shown_ms=1387` へ fallback し、`video_seek_ms` が約 1000ms へ悪化したため採用しない。fast seek は従来どおり、厳密にループ開始位置と一致する場合だけに戻した。
- 現時点では、チャプター戻りでもキャッシュ hit 自体は効いている。ただしメインデコーダを戻す同期 seek が約 250ms 残るため、完全な滑らかさにはまだ届かない。
- 次に本当に滑らかにする場合は、キャッシュ列を画面へ順に出している間に、別デコーダまたは非同期処理でメインデコーダをチャプター開始付近へ戻す必要がある。

## 2026-06-19 ループ再開直後のキャッシュ優先表示
- 実動画確認で、先頭への全体ループは戻り直後に余計なフレームが混入し、チャプターへのループは混入しないが同期 seek 待ちで遅いという状態を確認した。
- 1 枚だけキャッシュを即表示する方式では、直後の seek guard、音声同期、通常 tick が別フレームを出せるため、先頭ループの混入を完全には抑えられない。
- `ShowFrameAt(..., PresentFrame=False)` は scratch へデコードしているにもかかわらず表示面を `PresentImmediate` していたため、表示しない seek 準備では再描画しないようにした。
- ループ再開直後に `FrameAlreadyShown=True` で開始した場合は、開始から約 900ms の間、通常デコード結果よりもループ開始直後のキャッシュ済みフレームを優先して表示するようにした。
- キャッシュ優先区間中は、音声追従による別位置フレーム表示も抑える。これにより、先頭ループで戻り直後に別フレームが挟まる経路を減らす。
- チャプター戻りの遅さは、キャッシュ表示後のメインデコーダ同期 seek が残ることが原因。今回の修正では混入抑制を優先し、遅さの根本対策は別デコーダまたは非同期再配置を次段階とする。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 Bitmap コピー型ループキャッシュの無効化
- キャッシュが効いている箇所そのものが重く、滑らかさの改善よりも `TBitmap.Assign` と即時 repaint の負荷が目立つ状態になった。
- とくにループ開始直後のキャッシュ優先表示は、再生 tick 中に Bitmap コピーと `PresentImmediate` を繰り返すため、目的と逆に詰まりを作っていた。
- ループ開始直後フレーム列キャッシュは、保存側、表示側とも実行しないようにした。
- `ShowFrameAt(..., PresentFrame=False)` で表示面を即時再描画しない修正は、余計な repaint を減らすため残した。
- チャプター区間の戻り先を現在のループ区間開始へする修正、シークバー位置を先に戻す修正は残した。
- 次に改善する場合は、UI スレッド上で Bitmap をコピーするキャッシュではなく、デコーダ状態そのものを温めて切り替える方式、または非同期 seek 完了後に自然に合流する方式へ切り替える。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 ループキャッシュ試作をコミット前状態へ戻し
- ループ開始直後フレーム列を `TBitmap` として保持し、2 周目以降に表示する方式を試したが、キャッシュが効く箇所そのものが重くなり、滑らかさの改善に使えないと判断した。
- 先頭への全体ループでは余計なフレーム混入が残り、チャプターへのループでは混入は少ないものの同期 seek 待ちで遅くなる状態だった。
- `TBitmap.Assign` と `PresentImmediate` をループ境界や再生 tick 中で行う設計は、UI スレッドを詰まらせやすく、今回の目的である滑らかなループには向かない。
- `Source/App/VideoMinerMainForm.pas`、`Source/App/VideoMinerPlaybackController.pas`、`Source/App/VideoMinerVideoView.pas` は Git のコミット済み状態へ戻した。
- 今回の試作方針は採用しない。次に進める場合は、表示 Bitmap のキャッシュではなく、補助デコーダでループ開始側のデコーダ状態を準備して切り替える方式、またはメインデコーダの再配置を非同期化して表示に混ぜない方式を検討する。

## 2026-06-19 フレーム混入の最小修正
- コミット前状態へ戻した後、フレーム関係で余計な表示が入る経路を再確認した。
- `ShowFrameAt(..., PresentFrame=False)` は scratch buffer へデコードするだけの意図なのに、最後に `FSurface.PresentImmediate` を呼んでいた。このため、表示しない準備デコードでも現在の表示面が再描画され、古いフレームや直前の表示状態が混ざって見える可能性があった。
- `PresentFrame=False` の場合は一切 `PresentImmediate` しないようにした。
- seek guard が受理した初期フレームも、戻り先フレームから通常再生へ進む間の余計な差し込み表示になり得るため、画面には出さず内部位置だけ受理するようにした。Debug log には `seek_guard_accept ... present=False` を出す。
- Bitmap コピー型ループキャッシュは再導入しない。今回のコミットは、表示しない経路が画面へ出てしまう問題だけを修正する。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。

## 2026-06-19 ループ再生カクつき調査まとめ

### 目的

ループ再生で、終端からチャプター位置へ戻る瞬間に発生するカクつきの原因を特定する。

通常の再生開始ではなく、すでに再生中の状態から、以下の流れで発生する遅延を調査対象とする。

- ループ終端到達
- チャプター位置へ戻る
- 再生継続

### 調査する内容

#### 1. ループ終端到達から次フレーム表示までの時間

まず一番重要なのはここ。

調査内容:

| 項目 | 確認すること |
| --- | --- |
| ループ終端判定時刻 | どのタイミングでループ処理に入ったか |
| チャプター位置への移動開始時刻 | seek 開始までに無駄な処理がないか |
| seek 完了時刻 | seek 自体が遅いか |
| 最初のフレーム取得完了時刻 | seek 後のデコード再開が遅いか |
| 最初の描画完了時刻 | デコード後、描画側で詰まっていないか |

見るべき結論は、ループ終端から戻り先の映像が実際に描画されるまで何 ms かかっているか。

#### 2. seek 処理が重いのか

チャプター位置へ戻る処理で、毎回通常の seek を行っている場合、ここが最有力。

調査内容:

| 項目 | 確認すること |
| --- | --- |
| seek にかかった時間 | ループごとに何 ms かかるか |
| チャプター位置の直前キーフレーム | 戻り先がキーフレームから遠いか |
| seek 後に破棄しているフレーム数 | 目的位置まで何フレーム捨てているか |
| seek 時間のばらつき | 毎回遅いのか、たまに遅いのか |

ここが重い場合の改良候補:

- チャプター位置用 seek 情報の事前準備
- チャプター位置に近いキーフレーム情報の保持
- ループ用デコーダの事前待機

#### 3. seek 後の再デコードが重いのか

seek 自体は速くても、そこから目的フレームまで再デコードする時間で止まる可能性がある。

調査内容:

| 項目 | 確認すること |
| --- | --- |
| seek 後の最初のデコード時間 | 最初の 1 フレームが重いか |
| 表示可能フレームまでの時間 | 実際に画面に出せるまで何 ms か |
| デコード破棄フレーム数 | チャプター位置までに何枚読んで捨てているか |
| HW デコード時の初回遅延 | QSV などで復帰時だけ遅くないか |

ここが重い場合の改良候補:

- ループ戻り先フレームの先読み
- チャプター直後の数フレームだけ小規模キャッシュ
- ループ区間専用の軽量プリロール

#### 4. 描画側で止まっているのか

デコードは終わっているのに、描画更新が遅れている可能性もある。

調査内容:

| 項目 | 確認すること |
| --- | --- |
| デコード完了から描画開始まで | 表示待ちが発生していないか |
| 描画開始から描画完了まで | テクスチャ転送や描画が重いか |
| ループ直後の画面更新間隔 | 1 フレーム分以上空いていないか |
| 拡大表示中かどうか | 拡大・縮小処理が影響していないか |

ここが重い場合の改良候補:

- ループ直後の描画バッファ維持
- seek 中の前フレーム保持
- ループ直後だけ描画更新を優先

#### 5. 音声同期が原因で映像が待たされているか

音声もループしている場合、音声側の停止・再開・同期補正で映像が待たされる可能性がある。

調査内容:

| 項目 | 確認すること |
| --- | --- |
| 音声停止時刻 | ループ時に音声を止めているか |
| 音声 seek 時間 | 音声側の戻りが遅いか |
| 音声再開時刻 | 映像より後に再開していないか |
| 映像が音声待ちしているか | 同期処理で映像が止められていないか |

ここが重い場合の改良候補:

- ループ時の音声処理簡略化
- 映像優先のループ復帰
- 短時間ループ時の音声再同期方式見直し

#### 6. キャッシュ方式が遅くなった原因

今回、キャッシュ方式で余計に遅くなったので、キャッシュそのものの負荷も確認対象にする。

調査内容:

| 項目 | 確認すること |
| --- | --- |
| キャッシュ作成時間 | 保存処理が重いか |
| キャッシュ取得時間 | 読み出しが重いか |
| メモリコピー量 | フレームコピーが多すぎないか |
| キャッシュ破棄タイミング | ループごとに作り直していないか |
| キャッシュ対象範囲 | 範囲が広すぎないか |

ここが重い場合の改良候補:

- 全体キャッシュの廃止
- チャプター直後のみ小規模キャッシュ
- フレーム画像ではなくデコード状態の先読み化

### 改良候補の整理

#### 優先度 高

| 改良候補 | 狙い |
| --- | --- |
| チャプター位置への seek 時間をログ化 | 原因特定の中心 |
| seek 後の最初の表示フレームまでの時間をログ化 | 体感カクつきの実時間を確認 |
| チャプター位置のキーフレーム情報を事前取得 | 毎回の探索や無駄 seek を減らす |
| チャプター直後の数フレームだけ保持 | seek 中の表示空白を隠す |

#### 優先度 中

| 改良候補 | 狙い |
| --- | --- |
| ループ終端前にチャプター位置を先読み | ループ到達時の待ち時間を減らす |
| ループ専用デコーダを別に持つ | チャプター位置で待機させる |
| 音声同期処理の見直し | 音声待ちによる映像停止を防ぐ |
| seek 中は最後のフレームを維持 | 黒画面や描画停止感を減らす |

#### 優先度 低

| 改良候補 | 狙い |
| --- | --- |
| ループ範囲全体キャッシュ | 短いループ限定なら有効 |
| キーフレーム位置へループ開始を補正 | 正確な位置より滑らかさ優先の場合 |
| ループ直後だけフレームスキップ許可 | 追いつき優先の再生 |

### 現時点の方針

まずはキャッシュ方式をさらに作り込むより、ループ境界の時間計測を優先する。

特に見るべきなのは以下の 2 つ。

- チャプター位置への seek に何 ms かかっているか
- seek 開始から最初の描画完了まで何 ms かかっているか

この 2 つで、改良方針が分かれる。

| 結果 | 改良方向 |
| --- | --- |
| seek が遅い | キーフレーム情報保持、ループ用事前 seek |
| seek 後デコードが遅い | チャプター直後の先読み、小規模キャッシュ |
| 描画が遅い | 描画バッファ維持、描画優先 |
| 音声待ちしている | 音声同期方式見直し |
| キャッシュが重い | 全体キャッシュ廃止、小規模化 |

## 2026-06-19 インストーラー作成バッチ修正
- `Setup\InstallSetup.bat` が `[2] Read version from Version.inc` で `VM_APP_VERSION was not found` になり、インストーラー作成まで進まない問題を修正した。
- 原因は `Version.inc` が UTF-8 BOM 付きで、`findstr /r /c:"^#define VM_APP_VERSION "` の先頭一致が BOM に阻まれていたこと。
- `findstr /c:"VM_APP_VERSION"` で検索し、`tokens=3` からバージョン文字列を取得するようにした。
- 追加で、ファイル存在確認用の `call :RequireFile` が `LICENSE` の確認時だけ `The system cannot find the batch label specified - RequireFile` を出すことがあったため、サブルーチン呼び出しをやめて `for` ループ内の直接チェックへ変更した。
- `cmd /c "D:\DelphiProg\VideoMiner\Setup\InstallSetup.bat" nopause` で成功を確認した。
- 生成物:
  - `D:\DelphiProg\VideoMiner\Setup\Output\VideoMiner_Setup.exe`
  - `D:\DelphiProg\VideoMiner\Setup\Output\VideoMiner_Setup.zip`
  - `D:\DelphiProg\VideoMiner\Setup\Output\VideoMiner_Portable.zip`

## 2026-06-19 ループシーク計測ログ追加
- ループ終端から戻り先へ移動する経路を確認するため、Debug/slow log に以下を追加した。
  - `loop_restart_request`: 再生 tick がループ終端到達を判定した時点の位置、戻り先、区間、tick 内訳。
  - `loop_tick_seek`: `SeekPlaybackTickToMs` 内のプレビュー表示時間、再生再開時間、合計時間、seek guard 状態。
- `SeekPlaybackTickToMs` で `FSeekPositionMs` を戻した直後に `UpdatePlaybackProgress(PositionMs)` を呼び、シークバー表示だけは先にループ開始位置へ戻すようにした。
- ローカル短尺 mp4 の全体ループでは、例として `loop_tick_seek total_ms=27ms` 程度だった。
  - `preview_ms` と `restart_ms` がそれぞれ約 13ms で、プレビュー用デコーダと再生用デコーダの二重 seek になっていることを確認した。
  - ローカル全体ループでは大きな詰まりではないが、チャプター戻りやネットワーク上の動画ではこの二重 seek が効きやすい可能性がある。
- ネットワーク上の動画を自動起動してログ取得しようとしたところ、環境側で大量のエラーダイアログが出たため、以後の自動 GUI 実行は控える。
- 次に確認する場合は、ユーザー操作で対象動画を開いてループを数回発生させ、`マイドキュメント\VideoMiner\VideoMiner_playback_debug.log` の `loop_restart_request` / `loop_tick_seek` / `start_playback_done` を見る。

## 2026-06-19 Release から調査ログ文字列を除去
- Smart App Control 対策の一環として、Release 版 `VideoMiner.exe` に調査ログ用の文字列が残らないよう、ログ呼び出しを `{$IFDEF DEBUG}` 側へ寄せた。
- Release 版バイナリ内に以下が残らないことを確認した。
  - `VideoMiner_playback_debug.log`
  - `VIDEOMINER_DEBUG_LOG`
  - `VIDEOMINER_SLOW_LOG`
  - `loop_restart_request`
  - `loop_tick_seek`
  - `start_playback_done`
  - `playback_tick`
  - `audio_pump`
  - `seek_slow`
  - `open_done`
  - `audio_start`
  - `OutputDebugString`
- Debug ビルドでは従来どおり調査ログを出せる。
- ただし Smart App Control の主因は未署名・低 reputation の可能性が高く、ログ文字列除去は「疑われにくくする」ための整理に留まる。

## 2026-06-19 サムネイルのディスクキャッシュ
- Smart App Control 対策として、サムネイルの PNG ディスクキャッシュは無効に戻した。
- 現在の設定:
  - `Source\App\VideoMinerThumbnailCache.pas`
  - `{.$DEFINE THUMBNAIL_DISK_CACHE_ENABLED}`
- `マイドキュメント\VideoMiner\ThumbnailCache` へ保存する形でディスクキャッシュを有効化したところ、Smart App Control の状況が悪化した。
- そのため、キャッシュはメモリ上のみとし、起動をまたいだサムネイル再利用は行わない。
- 無効時は `System.IOUtils` / `Winapi.ShlObj` / `CSIDL_APPDATA` を含むキャッシュ実装をコンパイル対象から外す。

## 2026-06-19 データ保存先を Documents へ切り替える検証フラグ
- Smart App Control が `%APPDATA%` 配下への書き込みを嫌っている可能性を切り分けるため、VideoMiner のデータ保存先をマイドキュメントへ切り替えるフラグを追加した。
- 現在の検証設定:
  - `Source\App\VideoMinerSettings.pas`
  - `VIDEOMINER_DATA_DIR_USES_DOCUMENTS = True`
- `True` の間、設定ファイルは `マイドキュメント\VideoMiner\VideoMiner.ini` に保存する。
- `False` に戻すと、従来どおり `%APPDATA%\VideoMiner\VideoMiner.ini` に保存する。
- この変更で Smart App Control 回避に効果があったため、`%APPDATA%` 書き込みを避ける方針にする。
- サムネイルディスクキャッシュの再有効化は悪化したため、設定ファイルのみ Documents 保存を維持する。

## 2026-06-20 Smart App Control 対策の現状
- 効果があった変更:
  - 設定ファイルの保存先を `%APPDATA%\VideoMiner\VideoMiner.ini` から `マイドキュメント\VideoMiner\VideoMiner.ini` へ変更。
  - `Source\App\VideoMinerSettings.pas`
  - `VIDEOMINER_DATA_DIR_USES_DOCUMENTS = True`
- 悪化した変更:
  - サムネイルの PNG ディスクキャッシュを再有効化し、`マイドキュメント\VideoMiner\ThumbnailCache` に保存する形。
  - この構成では Smart App Control の状況がさらに悪化したため、キャッシュは再び無効にした。
- この時点の方針:
  - 設定ファイルだけ Documents 保存を維持する。
  - サムネイルディスクキャッシュは無効にする。
  - キャッシュ無効時は `System.IOUtils` / `Winapi.ShlObj` / `CSIDL_APPDATA` を含むキャッシュ実装をコンパイル対象から外す。
- 注意:
  - ソースを戻しても、既存の `Win64\Release\VideoMiner.exe` や `Setup\Output` 配下の生成物が古い状態のままだと、Smart App Control の確認結果も古い状態を見てしまう。
  - 生成済み Release exe を確認した時点では、`.png` / `VideoMiner.ini` / `VideoMiner_playback_debug.log` / `loop_tick_seek` はバイナリ内に見つからなかった。
  - `ThumbnailCache` 文字列は `VideoMinerThumbnailCache` という unit 名の一部として残ることがあるため、フォルダ名として残っているかは周辺文字列で確認する。
- 次に試すなら:
  - 最新ソースで Release を再ビルドし、その exe で再確認する。
  - それでも悪化する場合は、`VideoMinerSettings.pas` の Documents 保存も一度戻し、ログ文字列除去だけの状態へ戻して比較する。

## 2026-06-20 起動時間調査ログ追加
- 起動が遅くなった気がするため、Debug 版の slow log に起動段階ごとの計測を追加した。
- ログ出力先は `マイドキュメント\VideoMiner\VideoMiner_playback_debug.log`。
- 追加した主なログ:
  - `startup begin`: mutex 作成後、アプリ初期化前。
  - `startup application_initialize_ms`: `Application.Initialize` の時間。
  - `form_create ...`: `FormCreate` 内の UI/設定/各 controller/サムネイルブラウザ/DropAgent 生成時間。
  - `startup remembered_resolve_done`: 前回ファイルの INI 読み込み、フォルダ/ファイル存在確認時間。
  - `decoder_open_detail`: FFmpeg open 内の `EnsureLoaded`、`avformat_open_input`、`avformat_find_stream_info`、codec open、audio open の時間。
  - `media_open_done`: メインデコーダ、プレビューデコーダ、同一フォルダ一覧作成の時間。
  - `open_done`: 初期フレーム表示まで含めた `LoadVideoFile` 全体時間。Debug では速い場合も常に出す。
  - `startup initial_open_ms`: 起動直後の引数ファイル/前回ファイル open 全体時間。
- 実測対象:
  - 前回ファイル `D:\VoiceroidProj\main_14\59\06\grok-video-a2e52439-17cb-40fc-a04b-cc2cda06007d (1).mp4`
  - 同一フォルダ内動画数 15。
- 1 回目の実測では `startup initial_open_ms=425ms`、`startup total_ms=525ms` 程度だった。
  - `media_open_done total_ms=378ms`。
  - 内訳では `decoder_open_ms=362ms` が大半。
  - この時点では FFmpeg 内訳ログ追加前だったため、さらに細かい原因は未取得。
- その後の再実行では `startup initial_open_ms=45ms`、`startup total_ms=89ms` 程度まで下がった。
  - `media_open_done total_ms=26ms`。
  - メインデコーダの `decoder_open_detail total_ms=18ms`。
  - その内訳は `api_load_ms=10ms`、`stream_info_ms=7ms` が中心。
  - プレビューデコーダは `total_ms=6ms` 程度。
  - `first_frame_ms=13ms`。
- 現時点の見立て:
  - フォーム生成や INI 読み込みは主因ではない。
  - 遅い場合は動画 open、特に最初のメインデコーダ open に寄っている。
  - 2 回目以降がかなり速いので、OS ファイルキャッシュ、FFmpeg DLL 初回ロード、セキュリティスキャン、Smart App Control/Defender の初回確認が絡んでいる可能性が高い。
- 次に見るなら:
  - PC 起動直後または Release 再ビルド直後の初回起動で `decoder_open_detail` を取る。
  - Release 版で体感だけ遅い場合は、Debug の数値と Release の体感差から Smart App Control/Defender 側の影響を疑う。
  - もし `media_list_ms` が大きいログが出る場合は、フォルダ内ファイル数や作成日時取得を疑う。

## 2026-06-20 ネットワーク越し起動/オープン調査ログ追加
- ネットワーク越しの動画が少し重く感じるため、Debug 版の open ログをネットワーク調査向けに追加した。
- `media_open_done` / `media_open_failed` に `path_kind` を追加した。
  - `remote`: ネットワークドライブまたは UNC として Windows が返したパス。
  - `fixed`: ローカル固定ドライブ。
  - ほかに `removable` / `cdrom` / `unknown` なども出る。
- `TVideoMinerMediaList.BuildForFile` に `media_list_build` ログを追加した。
  - `collect_ms`: フォルダ内の動画ファイル収集時間。ネットワーク越しで重くなりやすい。
  - `sort_ms`: 作成日時順ソート時間。
  - `copy_ms`: 内部配列へのコピーと現在位置決定時間。
  - `count`: 対象動画数。
- ネットワーク越しで重い場合に見る順番:
  - `startup remembered_resolve_done`: 前回フォルダ/ファイル存在確認が遅いか。
  - `media_open_done path_kind=remote`: 全体としてネットワーク扱いか。
  - `decoder_open_detail`: `format_open_ms` / `stream_info_ms` が大きい場合は動画本体の読み取りや FFmpeg のストリーム解析が重い。
  - `media_list_build collect_ms`: 大きい場合は同一フォルダの走査や作成日時取得が重い。
  - `open_done first_frame_ms`: 初期フレーム表示だけが遅いか。
- 注意:
  - ネットワーク動画の自動 GUI 実行は過去に大量ダイアログが出たため控える。
  - 確認時はユーザー操作で Debug 版を起動し、対象のネットワーク動画を開いて `マイドキュメント\VideoMiner\VideoMiner_playback_debug.log` を見る。

## 2026-06-20 Debug ログ保存先を Documents へ変更
- Smart App Control 対策と一時フォルダ痕跡の削減のため、Debug 調査ログの保存先を一時フォルダ配下から `マイドキュメント\VideoMiner` 配下へ変更した。
- 現在の Debug ログ:
  - `マイドキュメント\VideoMiner\VideoMiner_playback_debug.log`
  - 実装は `Source\App\VideoMinerDebugLog.pas`。
- `VideoMinerSettings.pas` の設定フォルダ取得失敗時フォールバックも、一時フォルダではなく exe 配下の `VideoMiner` フォルダへ変更した。
  - 通常は従来どおり `CSIDL_PERSONAL` の `マイドキュメント\VideoMiner` を使う。
  - `SHGetFolderPath` が失敗した場合だけ exe 配下へ落とす。
- 無効中の `VideoMinerThumbnailCache.pas` についても、将来ディスクキャッシュを再有効化しても一時フォルダや AppData へ戻らないよう、保存先を `CSIDL_PERSONAL` ベースへ変更した。
- ソースと note から一時フォルダ環境変数への参照が残らないことを確認する。

## 2026-06-20 サムネイルキャッシュ実ファイルを Documents へ移動
- 過去に作成されたサムネイルキャッシュが旧保存先に残っていたため、実ファイルを `マイドキュメント\VideoMiner\ThumbnailCache` へ移動した。
  - 移動件数: 182 件。
  - 移動後サイズ: 37,077,908 bytes。
- 旧 `AppData\Roaming\VideoMiner\ThumbnailCache` は削除済み。
- 旧設定ファイルは現在の実行コードから参照されないが、念のため `マイドキュメント\VideoMiner\VideoMiner_legacy_settings.ini` へ退避した。
- `VideoMinerSettings.pas` は保存先切替フラグを廃止し、設定保存先を `CSIDL_PERSONAL` の `マイドキュメント\VideoMiner` 固定にした。
- ソース側に `CSIDL_APPDATA` / `%APPDATA%` / 一時フォルダ参照が残っていないことを確認する。

## 2026-06-20 サムネイルキャッシュ形式を PNG へ変更
- `VideoMinerThumbnailCache.pas` のディスクキャッシュ形式を BMP から PNG へ変更した。
  - キャッシュファイル名の拡張子は `.png`。
  - 保存は `TPngImage.Assign(Bitmap)` から `SaveToFile`。
  - 読み込みは `TPngImage.LoadFromFile` から `Bitmap.Assign`。
- 既存の `マイドキュメント\VideoMiner\ThumbnailCache` 配下の `.bmp` 182 件を `.png` へ変換し、変換成功後に元 BMP を削除した。
  - 変換後 PNG: 182 件。
  - 変換後サイズ: 21,400,920 bytes。
  - 残存 BMP: 0 件。

## 2026-06-20 サムネイル生成をバックグラウンド化
- サムネイル一覧の生成を、UI タイマー内の同期生成からバックグラウンドワーカー方式へ変更した。
- `TVideoMinerThumbnailBrowser` はサムネイル一覧を開いた時点で、現在フォルダ内のサムネイルを全件キューへ積む。
  - 起動直後や非表示状態の `SetMediaList` では全件キューを開始しない。
  - 動画再生中にサムネイル一覧を開いている間は、1 本のワーカーで 1 枚ずつ生成するため、再生タイマー側を大きく止めにくい。
- ワーカーは同時に 1 本だけ動かし、1 枚完了したら次の予約を処理する。
  - 古い一覧に対する結果は index と file name が現在の状態と一致する場合だけ反映する。
  - 一覧差し替えや終了時は実行中ワーカーを停止してからサムネイル配列を破棄する。
- `Loading` 表示は `tsQueued` と `tsLoading` の両方で使う。

## 2026-06-20 サムネイル表示時フリーズ対策
- サムネイル一覧を表示した時にフリーズするケースがあったため、履歴行の描画処理を見直した。
- 原因候補:
  - `DrawFolderHistoryTile` が描画中に過去履歴フォルダを `FirstMediaFileInFolder` / `BuildForFile` で同期走査していた。
  - 履歴にネットワークフォルダや重いフォルダが混ざると、`Paint` 中に UI スレッドがフォルダ走査で止まる。
- 対策:
  - 履歴行の描画中は、現在表示中フォルダ以外を走査しない。
  - 過去履歴フォルダの一覧読み込みは、履歴タイルを選択して `ShowFolderHistory` へ入った時だけ行う。
- Debug 版をローカル動画で短時間起動し、`Tab` でサムネイル一覧を開いた後もプロセスが応答状態のままであることを確認した。
- 追加調査で、バックグラウンドワーカー内から `TBitmap` / `Canvas.StretchDraw` / PNG キャッシュ処理を触っていた点も危険と判断した。
  - VCL/GDI オブジェクトはスレッド安全ではないため、ワーカー側では FFmpeg のデコードと `TBytes` の BGRX32 生バッファ作成だけを行う。
  - `TBitmap` 作成、縮小描画、PNG キャッシュ保存、画面反映は UI スレッド側の `ApplyThumbnailWorkerResult` で行う。
  - 生バッファから `TBitmap` へ戻す処理は、連続メモリ前提の一括コピーではなく scanline ごとのコピーにした。
- 引数なし起動で最後のフォルダを開き、その後 Tab でサムネイル表示する経路を再調査した。
  - 起動時の非表示 `SetMediaList` では worker を開始しないように変更した。
  - Tab / toggle 経路に `thumbnail tab_dialog_key` / `thumbnail toggle_begin` / `thumbnail toggle_end` ログを追加した。
  - worker 側または UI 反映側で例外が起きても、エラーダイアログを連発せず対象サムネイルを `Failed` 扱いにして `worker_apply_exception` ログへ落とすようにした。
- 追加対策:
  - `QueueThumbnail` / `QueueAllThumbnails` から直接 worker を開始せず、タイマー経由で開始するようにした。
    - `Open` / `Paint` / `MouseMove` の処理中に FFmpeg worker 起動まで進まないようにするため。
  - worker から `TThread.Synchronize` で UI スレッドへ戻す処理を廃止した。
    - 結果反映は `OnTerminate` 側で行い、worker が UI スレッド待ちで詰まる経路を避ける。
  - hover 実動画プレビューを停止した。
    - `MouseMove` から `Update` で即時再描画し、その後 UI スレッドで `GeneratePreviewFrame` が走る経路が残っていた。
    - サムネイル表示直後にカーソル位置の hover が入ると、サムネイル生成とは別に同期 FFmpeg デコードで固まる可能性が高い。
    - `HOVER_REAL_PREVIEW_DEFAULT = False` とし、`ResetPreview` の入口で停止する。

## 2026-06-20 サムネイルバックグラウンド生成を撤回
- サムネイル表示時のフリーズが解消しなかったため、バックグラウンド worker 方式を撤回した。
- `TVideoMinerThumbnailBrowser` から以下を削除した。
  - `TVideoMinerThumbnailWorker`
  - `FThumbnailWorker`
  - `QueueAllThumbnails`
  - worker の `OnTerminate` 反映処理
  - `WaitForSingleObject` / `CheckSynchronize` による worker 停止待ち
  - `tsLoading`
- サムネイル生成は元の方式へ戻し、表示されたタイルだけを `QueueThumbnail` で予約し、`ThumbnailTimer` から `GenerateThumbnail` を 1 枚ずつ同期生成する。
- 履歴行の描画中に過去フォルダを同期走査しない対策と、hover 実動画プレビュー停止は残した。
  - この 2 点はバックグラウンド worker とは別のフリーズ要因対策のため。

## 2026-06-20 サムネイルキャッシュ再有効化と再表示時の生成停止修正
- サムネイルキャッシュが効いていなかった直接原因:
  - `VideoMinerThumbnailCache.pas` の `THUMBNAIL_DISK_CACHE_ENABLED` がコメントアウトされたままで、`LoadVideoMinerThumbnailCache` / `SaveVideoMinerThumbnailCache` が実質何もしない状態だった。
- 対策:
  - `{$DEFINE THUMBNAIL_DISK_CACHE_ENABLED}` を有効化した。
  - キャッシュ形式は PNG のまま。
  - 保存先は `マイドキュメント\VideoMiner\ThumbnailCache`。
- Tab / Esc でサムネイル表示と再生を切り替えると生成が進まなくなる原因:
  - `Close` で `FThumbnailTimer.Enabled := False` になる。
  - その後 `Open` しても、既に `tsQueued` になっているタイルは `DrawThumbnail` で再度 `QueueThumbnail` されないため、タイマーが再起動しなかった。
- 対策:
  - `Open` 時に `NextQueuedThumbnailIndex >= 0` なら `FThumbnailTimer.Enabled := True` に戻す。
- 確認:
  - 2026-06-20 時点で `C:\Users\zan12\Documents\VideoMiner\ThumbnailCache` は存在するが PNG は 0 件。
  - この修正後にサムネイル生成を行うと、同フォルダへ PNG キャッシュが作成される想定。

## 2026-06-20 リリース前の保存先確認
- リリース時のデータ/作業ファイル保存先を確認した。
- 設定 INI:
  - 実装: `Source\App\VideoMinerSettings.pas`
  - `SettingsFileName` は `SHGetFolderPath(... CSIDL_PERSONAL ...)` を使い、通常は `マイドキュメント\VideoMiner\VideoMiner.ini` を返す。
  - `CSIDL_PERSONAL` 取得に失敗した場合だけ exe 配下の `VideoMiner\VideoMiner.ini` へフォールバックする。
- Debug 調査ログ:
  - 実装: `Source\App\VideoMinerDebugLog.pas`
  - Debug ビルド時のみ `マイドキュメント\VideoMiner\VideoMiner_playback_debug.log` を使う。
  - Release ビルドでは `VideoMinerDebugLogEnabled` / `VideoMinerSlowLogEnabled` が False になり、ログファイルは作られない。
- サムネイルキャッシュ:
  - 実装: `Source\App\VideoMinerThumbnailCache.pas`
  - `THUMBNAIL_DISK_CACHE_ENABLED` を有効化済み。
  - `CacheRootDir` は `SHGetFolderPath(... CSIDL_PERSONAL ...)` を使い、通常は `マイドキュメント\VideoMiner\ThumbnailCache` を返す。
  - キャッシュ形式は PNG。
  - 2026-06-20 の確認時点で `C:\Users\zan12\Documents\VideoMiner\ThumbnailCache` に PNG 15 件が生成済み。
- AppData/temp 参照確認:
  - `CSIDL_APPDATA`
  - `CSIDL_LOCAL_APPDATA`
  - `GetTempPath`
  - `GetTempFileName`
  - `TPath.GetTemp`
  - `%TEMP%` / `%TMP%`
  - `APPDATA` / `LOCALAPPDATA` / `Roaming`
  - 上記キーワードで `Source` と `VideoMiner.dpr` を検索し、保存先としての参照が残っていないことを確認した。
- この時点の方針:
  - サムネイルのバックグラウンド worker 方式は撤回済み。
  - サムネイルは表示されたタイルだけを `QueueThumbnail` し、`ThumbnailTimer` から 1 枚ずつ生成する。
  - Tab/Esc で閉じて再表示した場合、未処理キューがあれば `Open` で `FThumbnailTimer` を再開する。
  - hover 実動画プレビューは停止したままにする。

## 2026-06-21 サムネイル hover 実動画プレビュー再有効化
- 2026-06-20 のフリーズ対策で `HOVER_REAL_PREVIEW_DEFAULT = False` にしていたため、サムネイル hover 時の音なし実動画プレビューが入口で止まっていた。
- `HOVER_REAL_PREVIEW_DEFAULT = True` に戻し、機能を再有効化した。
- ただし、サムネイル一覧表示直後に通常サムネイル生成と hover プレビュー用デコードが同時に UI スレッドで走ると固まりやすいため、`PreviewTimer` 側で通常サムネイル生成キューが残っている間は hover プレビュー開始を短時間延期する。
- バックグラウンド worker 方式は再導入しない。通常サムネイルは従来どおり `ThumbnailTimer` で 1 枚ずつ生成し、hover プレビューは通常サムネイル生成が落ち着いてから開始する。

## 2026-06-22 縦長ショート動画の回転メタデータ対応
- ユーザー報告として、ショート動画のような縦長動画を再生すると表示がうまくいかないケースがあった。
- 原因候補として、スマホ系動画によくある「実フレームは横長、display matrix / rotate metadata で縦表示する」形式を VideoMiner が読んでいなかった点を確認した。
  - `TVideoMinerVideoSurface.FitRect` 自体は `FBitmap.Width` / `FBitmap.Height` から等倍 fit しており、本当に `1080x1920` の縦フレームなら大きく壊れにくい。
  - 問題になりやすいのは `1920x1080` などの横長フレームに、90 度回転表示のメタデータが付く形式。
- `FFmpegApi.pas` に `av_packet_side_data_get` と `av_display_rotation_get` を追加した。
- `FFmpegStreamInfo.ReadVideoRotationDegrees` を追加し、`AV_PKT_DATA_DISPLAYMATRIX` から 90 / 180 / 270 度の表示回転を読むようにした。
- `TVideoInfo` に `RotationDegrees` を追加した。
  - `Width` / `Height` は FFmpeg のデコード先として使うため、元フレームサイズのまま扱う。
  - 表示用の向き補正はデコード後の Bitmap に対して行う。
- `VideoMinerBitmapRotation.pas` を追加し、デコード済み 32bit Bitmap を 90 / 180 / 270 度回転できるようにした。
- `VideoMinerVideoView.pas` で通常再生、シーク表示、scratch frame 表示の各デコード成功後に `RotationDegrees` を反映するようにした。
- `VideoMinerThumbnailBrowser.pas` で通常サムネイルと hover 実動画プレビューにも同じ回転を反映するようにした。
- 既存の横向きサムネイルキャッシュが残ると修正後も古い向きの PNG を読んでしまうため、`VideoMinerThumbnailCache.pas` のキャッシュキーに `THUMBNAIL_CACHE_VERSION = 'r1'` を含めた。
- `Debug Win64` ビルド成功。警告 0 / エラー 0。
- 同梱 DLL に `av_display_rotation_get` / `av_packet_side_data_get` が含まれることを確認した。
- 短い mp4 を指定して Debug exe を起動し、動画 open と追加 API ロードが正常に通ることを確認した。

## 2026-06-22 表示回転の比較用上書き
- VW_Media_Output の実フレーム90度回転出力では、Media Player と VideoMiner の表示が一致することをユーザー確認済み。
- 次の切り分け用に、VideoMiner 側だけ表示回転を上書きする INI 設定を追加した。
- 設定ファイル:
  - `マイドキュメント\VideoMiner\VideoMiner.ini`
- 設定キー:

```ini
[VideoMiner]
VideoRotationOverride=auto
```

- 値:
  - `auto`: 通常動作。動画の display matrix / rotate metadata を読む。
  - `ignore` / `none` / `0`: 回転メタデータを無視して 0 度表示にする。
  - `force90` / `90`: VideoMiner 側の表示だけ 90 度回転に固定する。
  - `force180` / `180`: VideoMiner 側の表示だけ 180 度回転に固定する。
  - `force270` / `270`: VideoMiner 側の表示だけ 270 度回転に固定する。
- 実装:
  - `VideoMinerSettings.pas` に `TVideoRotationOverride` と `EffectiveVideoRotationDegrees` を追加した。
  - `VideoMinerVideoView.pas` の通常再生、シーク表示、scratch frame 表示で回転適用前に上書きを反映する。
  - `VideoMinerThumbnailBrowser.pas` の通常サムネイルと hover 実フレームプレビューにも上書きを反映する。
  - `VideoMinerThumbnailCache.pas` のキャッシュキーに `VideoRotationOverride` を含め、モード変更時に別キャッシュとして扱う。
- 注意:
  - 起動時に INI を読むため、値を変えたら VideoMiner を再起動して比較する。
  - 通常検証後は `VideoRotationOverride=auto` に戻す。
- ビルド確認:
  - Win64 Debug: 成功、警告 0。
  - Win64 Release: 成功、既存 H2077 hint 40 件のみ。

## 2026-06-22 回転上書きテスト確認
- 対象ファイル:
  - `C:\Users\vramw\Videos\test_out_r.mp4`
- ffprobe 確認:
  - video stream は `1080x1920`。
  - rotate tag / display matrix は無し。
  - つまり VW_Media_Output の回転出力は、メタデータ回転ではなく実フレームが縦向きになっている。
- このファイルでは `VideoRotationOverride=auto` と `VideoRotationOverride=ignore` は同じ表示になる。
  - `rotation=0` のため、メタデータを読んでも無視しても追加回転が無い。
  - VideoMiner 側だけ追加回転して比較する場合は `VideoRotationOverride=force90` を使う。
- デバッグ起動確認:
  - INI の `LastMedia` が `C:\Users\vramw\Videos\test_out_r.mp4` を指している状態で、引数なし起動から対象ファイルを開くことを確認した。
  - ログで `decoder_open_detail ... video=1080x1920 rotation=0` を確認した。
- 変わらなかった原因:
  - PowerShell の `Set-Content -Encoding UTF8` で INI 先頭に BOM が入り、`TIniFile` が先頭セクション `[VideoMiner]` を認識できず、`VideoRotationOverride` が既定値 `auto` になっていた。
  - `LastMedia` は2番目以降のセクションだったため読めており、ファイル復元だけは成功していた。
- 修正:
  - `VideoMinerSettings.LoadSettings` を `TMemIniFile.Create(SettingsFileName, TEncoding.UTF8)` に変更し、BOM 付き UTF-8 INI でも `[VideoMiner]` を読めるようにした。
  - Debug 起動ログへ `startup rotation_override=...` を追加した。
  - Debug の decoder open ログへ `video=<width>x<height> rotation=<degrees>` を追加した。
  - 表示時確認用に `show_frame_rotation` ログを追加した。
- 確認結果:
  - `VideoRotationOverride=force90` の INI を読んだ状態で、Debug 引数なし起動ログに `startup rotation_override=force90` が出ることを確認した。
  - Win64 Debug: 成功、警告 0。
  - Win64 Release: 成功、既存 H2077 hint 40 件のみ。

## 2026-06-22 回転上書きの実動作確認と stride 修正
- `C:\Users\vramw\Videos\test_out_r.mp4` で `VideoRotationOverride` が本当に表示方向を変えるか確認した。
- 追加で判明した問題:
  - `VideoRotationOverride=force90` は INI から読めていたが、初回フレーム表示で `show_frame_rotation` に到達する前に `swscale-9.dll` の書き込み違反が出ていた。
  - 原因は `TBitmap.ScanLine` の上下配置と `sws_scale` へ渡す出力 pointer / stride の契約が曖昧で、縦長 `1080x1920` のようなフレームで Bitmap 端へ直接 SIMD 書き込みが走ると範囲外に触れることがあったため。
- 修正:
  - `VideoMinerVideoSurface.PrepareBgrx32Frame` と `VideoMinerVideoView.PrepareBitmapFrameBuffer` は、`ScanLine[0]` と次行との差分を符号付き stride として返すようにした。
  - `FFmpegFrameConvert.CopyFrameToBgrx32Buffer` / `CopyFrameToBgr24Buffer` は、`sws_scale` の出力を一度連続した一時バッファへ受け、呼び出し側 Bitmap へ行単位でコピーする方式に変更した。
  - これにより VCL Bitmap が bottom-up / top-down のどちらでも、`sws_scale` が Bitmap 境界外へ直接書き込まない。
  - Debug ログに `show_frame_rotation ... before=<w>x<h>` と `show_frame_rotation_done ... after=<w>x<h>` を追加した。
- 実測結果:
  - `VideoRotationOverride=force90`:
    - `startup rotation_override=force90`
    - `decoder_open_detail ... video=1080x1920 rotation=0`
    - `show_frame_rotation ... source_rotation=0 effective_rotation=90 before=1080x1920`
    - `show_frame_rotation_done ... effective_rotation=90 after=1920x1080`
    - `paint width=1920 height=1080`
  - `VideoRotationOverride=ignore`:
    - `startup rotation_override=ignore`
    - `show_frame_rotation ... source_rotation=0 effective_rotation=0 before=1080x1920`
    - `show_frame_rotation_done ... effective_rotation=0 after=1080x1920`
    - `paint width=1080 height=1920`
  - 引数なし起動でも `LastMedia` から `test_out_r.mp4` を開き、`force90` で `1920x1080` 表示になることを確認した。
- 結論:
  - この INI 値で VideoMiner の再生方向は変わる。
  - `test_out_r.mp4` 自体は `rotation=0` の実フレーム縦動画なので、`auto` と `ignore` は同じ表示になる。
  - 比較用に向きを変える場合は `force90` / `force180` / `force270` を使う。
- 現在の確認用 INI:
  - `D:\Users\take6\VideoMiner\VideoMiner.ini`
  - `VideoRotationOverride=force90`
- ビルド確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - Win64 Release: 成功、既存 H2077 hint 40 件のみ / エラー 0。

## 2026-06-22 回転 metadata 動画の再生速度改善
- 対象:
  - `C:\Users\vramw\Videos\test_out_r2.mp4`
  - `1920x1080` の実フレームに Display Matrix `rotation=90` が付いた metadata 回転動画。
- 問題:
  - 回転表示は正しいが、再生時にデコード済み `TBitmap` の90度回転が重すぎた。
  - 旧 `VideoMinerBitmapRotation.RotateBitmapByDegrees` は、ピクセルごとに `Bitmap.ScanLine[...]` を呼んでおり、1920x1080 の90度回転で大きな負荷になっていた。
- 修正:
  - `VideoMinerBitmapRotation.pas`
    - 回転前に source / destination の scanline pointer を配列化する `BuildScanLineTable` を追加。
    - 回転ループ中は `ScanLine` 呼び出しを行わず、行ポインタ配列とピクセル index だけでコピーするよう変更。
  - `VideoMinerVideoView.ShowFrameAt`
    - `PresentFrame=False` の scratch デコードでは、表示に使わないため回転処理をスキップ。
- 確認:
  - `VideoRotationOverride=auto` で `test_out_r2.mp4` を Debug 起動。
  - `decoder_open_detail ... video=1920x1080 rotation=90` を確認。
  - 表示フレームは `show_frame_rotation ... before=1920x1080` から `after=1080x1920` へ回転することを確認。
  - Debug ログ上、表示フレーム回転は同一ミリ秒内に完了する程度まで改善。
  - scratch 側は `PresentFrame=False ... after=1920x1080` となり、不要回転が走らないことを確認。
- ビルド確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - Win64 Release: 成功、既存 H2077 hint 40 件のみ / エラー 0。

## 2026-06-22 stop モード終端フレーム崩れ対策
- 対象:
  - `C:\Users\vramw\Videos\test_out_r2.mp4`
  - `EndAction=stop`
- 報告:
  - 回転 metadata 動画の再生速度は改善したが、stop モードで終端に到達した時の最終フレームが崩れる。
- 原因候補:
  - 終端到達時の `FinishAtEnd` は seek bar を `SeekMaxMs` へ進めて `StopAtEnd` するだけで、表示可能な最後のフレームを明示的に表示し直していなかった。
  - `StopAtEnd` も `FVideoView.PlaybackActive := False` のみで、再生 timer / audio / restart 予約 / rate clock の停止が通常停止より弱かった。
  - EOF 近辺の scratch / decode 残り状態が最後の画面として残ると、回転後 bitmap の表示状態が崩れて見える可能性がある。
- 修正:
  - `VideoMinerPlaybackController.FinishAtEnd` に `LastFrameSeekPositionMs` を渡すよう変更。
  - stop 終端では `SeekMaxMs` ではなく `LastFrameSeekPositionMs` を `ShowFrameAtMs` で表示し直してから停止する。
  - `StopAtEnd` で `FPlaybackTimer.Enabled := False`、`FRateClockActive := False`、`ClearRestart`、`FAudioPlayback.StopOutput` も実行するよう変更。
  - Debug slow log に `finish_at_end_stop seek_max_ms=... last_frame_ms=... shown=...` を追加。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 MainForm を段階的に配線係へ寄せる移行工程
- 方針:
  - 一気に大改造せず、少しずつ `MainForm` を VCL 部品と Windows message の入口、controller 生成と接続を担当する配線係へ寄せる。
  - 表示状態、操作の意味づけ、再生/シーク/一覧/overlay の制御は、機能単位の controller / session へ移していく。
  - この 1-4 をひとつの工程として扱い、工程完了までは途中経過を `note.md` に追加しない。
- 1. `TVideoMinerMediaSession` を作る:
  - `FVideoFile`、`FVideoInfo`、`FSeekPositionMs`、`FSeekMaxMs`、`FCurrentVideoPositionMs`、ループ区間、終端動作など、現在動画の状態を MainForm から分離する。
  - 最初は状態置き場として作り、挙動変更は最小にする。
- 2. `LoadVideoFile` の状態初期化/更新を session へ寄せる:
  - validate、decoder open、UI 更新、自動再生などは急に動かさず、まず現在ファイル状態の clear / configure / restore だけを session 経由にする。
  - `MainForm` の `LoadVideoFile` は徐々に「手順の呼び出し」に近づける。
- 3. `OverlayController` を作る:
  - `VideoView` の overlay イベント接続、Check、チャプター追加/削除、終端動作、再生速度、シーク要求などを MainForm 直結から外す。
  - MainForm は overlay event を controller に渡し、controller が必要な command / session / view 更新へつなぐ。
- 4. `MainForm` を composition root 化する:
  - MainForm に残す責務を、VCL 部品保持、controller 生成と接続、フォーム固有 Windows message、最小限の UI entry point に絞る。
  - 工程 1-4 が完了した時点で、最終状態と確認結果を改めて `note.md` に記録する。

## 2026-06-23 シークバー hover プレビュー更新遅延を分離
- 報告:
  - 最初の hover で少し待ってからプレビューを出すタイミングは良い。
  - ただし、プレビュー表示中にカーソル位置が変わった場合のフレーム更新はもっと早い方が自然。
- 改善:
  - `SEEK_HOVER_PREVIEW_INITIAL_DELAY_MS = 140` を初回 hover 用の待ち時間として残した。
  - `SEEK_HOVER_PREVIEW_UPDATE_DELAY_MS = 45` を追加し、プレビュー表示済みの追従更新だけ短い待ち時間にした。
  - hover を抜けたら表示済み状態を解除し、次回 hover は再び初回待ち時間から始める。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 シークバー hover プレビュー制御を MainForm から分離
- 目的:
  - hover プレビュー追加で `VideoMinerMainForm.pas` に timer、Bitmap、デコード調停の状態が増えたため、フォーム肥大化を抑える。
- 対策:
  - `VideoMinerSeekHoverPreviewController.pas` を追加した。
  - `FSeekHoverPreview...` 一式、hover プレビュー timer、デコード処理、初回/更新 delay 定数を controller へ移した。
  - `MainForm` は controller の生成、`VideoView` へのイベント接続、動画読み込み時の `ConfigureMedia` 呼び出しだけを担当する形にした。
  - `SEEK_HOVER_PREVIEW_INITIAL_DELAY_MS = 140`、`SEEK_HOVER_PREVIEW_UPDATE_DELAY_MS = 5`、`SEEK_HOVER_PREVIEW_REUSE_MS = 80` は新 controller unit 側へ移動した。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 hover 用フォーム枠制御を MainForm から分離
- 目的:
  - `MainForm` に残っていたフォーム端/タイトルバー hover 枠の Panel 群、timer、表示判定を切り出し、フォーム肥大化をさらに抑える。
- 対策:
  - `VideoMinerFrameGuideController.pas` を追加した。
  - `FFrameGuide...` 一式、`InitializeFrameGuide`、`SetFrameGuideVisible`、`UpdateFrameGuideLayout`、`UpdateFrameGuideVisibility`、`FrameGuideTimer` を controller へ移した。
  - `MainForm` は controller の生成、`WM_NCHITTEST` での visibility 更新、`WM_SIZE` での layout 更新だけを担当する形にした。
  - hover 枠の色、端判定幅、線幅、timer 間隔の const は新 controller unit 側へ移動した。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - Win64 Release: 成功、既存 H2077 hint 40 件のみ / エラー 0。
  - Debug 引数あり起動で `test_out_r2.mp4` の自動再生開始、`rotation=90`、`audio_start` まではログ確認済み。
  - この Codex 実行経路では GUI プロセスが終端ログ前に終了したため、実画面の最終フレーム崩れ再現確認は手元操作での確認待ち。

## 2026-06-23 下部シークバーをフォーム幅基準へ変更
- 縦長ショート動画では、動画表示矩形を基準に下部シークバー/ツールを配置すると横幅が短くなり、シーク操作がしづらい。
- フォルダ内の前後動画を切り替える使い方では、動画ごとに下部 UI の位置や幅が変わることも不自然になりやすい。
- 方針:
  - 中央の再生/スキップ系 overlay は従来どおり動画表示矩形基準のままにする。
  - 下部のシーク/音量/チェック操作バーだけ、動画表示矩形ではなくフォーム側の `ClientRect` 基準で配置する。
  - ツール幅による非表示/省略制御は今回は入れない。
- 実装:
  - `VideoMinerVideoSurface.pas` に `SeekBarLayoutRect` を追加し、下部シークバーの `UpdateLayout` へ `ClientRect` を渡すようにした。
  - hit test とホイールシーク時にも同じ基準で layout を更新する。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 狭い下部バーで補助ツールを非表示
- フォームを最小サイズ付近にすると、下部バー内でチャプター追加/削除、倍速表示が混み合い、シーク位置や Check / 終端動作の視認性を下げていた。
- 対策:
  - 下部バー幅が `520px` 未満の場合、チャプター `+` / `-` と倍速表示を非表示にする。
  - 非表示時は描画だけでなく hit test 用の矩形も空にし、見えないボタンがクリック対象にならないようにした。
  - Check、終端動作、全画面、音量、シークバーは表示したままにする。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 フォーム最小サイズを設定
- 枠なしフォームのままどこまでも小さくリサイズできると、動画表示と下部操作バーが破綻する。
- 対策:
  - `VideoMinerMainForm.pas` でフォーム生成時に `Constraints.MinWidth = 520`、`Constraints.MinHeight = 360` を設定した。
  - `VideoMinerWindowChrome.ApplySavedWindowBounds` でも保存済みウィンドウ座標を復元する際、フォームの最小サイズ未満なら補正するようにした。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 シークバーの時間表示とアクセント色を調整
- メディアプレーヤーの良さは参考にしつつ、VideoMiner では配置を現状維持し、横幅いっぱいのシーク操作を優先する方針。
- 調整:
  - 時間表示を短い動画でも `0:00:00 / 0:00:05` のように常に時間付き形式へ変更した。
  - シークバーの見終わった部分と丸ノブを白から VideoMiner の青系アクセント色へ変更した。
  - 既存の白い overlay アイコンやボタン背景へ影響しないよう、半透明描画ヘルパーは色指定省略時に従来どおり白で描く。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 先頭フレーム移動の表示ずれ対策
- 報告:
  - 末尾へのシーク位置移動は表示も末尾になるが、先頭位置への移動では先頭の動画表示にならないことがある。
- 原因候補:
  - BGRX32 の通常シークでは、指定時刻以降の timestamp を持つフレームを採用していた。
  - 0ms 指定時でも、実ファイルの先頭表示フレームが負の PTS や 0ms より前の timestamp として返る場合、そのフレームを捨てて次のフレームを表示する可能性がある。
- 対策:
  - `FFmpegDecoderSeekBgrx32.pas` で `PositionMs <= 0` の場合だけ、seek 後に最初にデコードできた映像フレームを採用するようにした。
  - 通常の途中シークや末尾シークは従来どおり、目標 timestamp 以降のフレームを待つ。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 中央先頭ボタンのクリック重複対策
- 報告:
  - シークバーを 0ms へ動かす経路は先頭表示になったが、中央 overlay の先頭フレームボタンでは、シーク位置は先頭へ行くのに動画表示が 1 フレーム送られたように見える。
- 原因候補:
  - 中央 overlay ボタンのクリック処理後、同じマウス操作が動画面の単クリック候補として残ると、再生/一時停止などの動画面クリック処理が重なり、先頭表示直後に別の表示更新が走る可能性がある。
- 対策:
  - `VideoMinerVideoSurface.CanStartSurfaceClick` で、中央 overlay ボタン上は表示状態に関係なく動画面単クリック開始の対象外にした。
  - 中央 overlay ボタンの `MouseUp` が処理された場合は `FSurfaceClickArmed` を解除し、そのクリックを動画面クリックへ流さないようにした。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 先頭フレーム移動を停止シークへ変更
- 追加確認:
  - Home キーと中央 overlay の先頭フレームボタンは、どちらも `SeekToFirstFrame` へ入る同じ経路だった。
  - `SeekToFirstFrame` は `SeekToMs(0)` を呼び、既定値 `ResumeIfPlaying=True` のため、再生中に実行すると先頭表示直後に再生再開が予約される。
  - 末尾移動は `SeekToMs(LastFrameSeekPositionMs, False)` で再生再開しないため、表示が安定していた。
- 対策:
  - `SeekToFirstFrame` も `SeekToMs(0, False)` に変更し、先頭/末尾の中央ボタンと Home/End を「位置決めして停止する」操作に揃えた。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 先頭フレーム移動を先頭読み直し方式へ変更
- 追加報告:
  - 中間位置へシークしたあと Home を押すと、シークバーは先頭へ戻るが動画表示は先頭にならず、何回か Home を押すと 1 フレームずつ移動してから先頭表示になる。
- 判断:
  - 0ms への通常 `av_seek_frame` 経路が、ファイル先頭付近で安定して最初の表示フレームを返していない可能性が高い。
  - Home/先頭ボタンは「現在位置から 0ms へ seek」ではなく「ファイル先頭から最初に読める映像フレームを表示」する専用動作にした方が確実。
- 対策:
  - `VideoMinerMainForm.ShowFirstFrameFromStart` を追加した。
  - `SeekToFirstFrame` は再生出力を止めたあと、preview decoder を開き直し、`ShowNextFrame` で最初にデコードできる映像フレームを表示する。
  - 表示後の UI シーク位置は 0ms に固定する。
  - 先頭読み直しに失敗した場合だけ従来の `SeekToMs(0, False)` へ fallback する。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
- 今後の課題:
  - 今回の対応は、0ms seek の不安定さを避けるための暫定回避として扱う。
  - 根本的には、FFmpeg の seek 後にどの timestamp のフレームを VideoMiner の「先頭表示フレーム」とするかを整理する必要がある。
  - 0ms 近辺の `pts` / `best_effort_timestamp` / `pkt_dts` をログで比較し、実際にどのフレームが返っているか確認する。
  - `StreamTimestampFromMs` が `AVStream.start_time` を考慮すべきか確認する。
  - BGRX32 以外の seek 実装とも先頭付近の挙動を揃える。
  - 「UI 上の 0ms」と「実際に表示できる最初の映像フレーム」の扱いを分ける必要があるか検討する。
  - 先頭移動専用の preview decoder reopen 方式を正式仕様にするか、seek 実装側で吸収するかを後で決める。

## 2026-06-23 シークバー hover プレビューの軽量実装
- 目的:
  - シークバー上へマウスを置いたとき、その位置のフレームを小さく枠付きで確認できるようにする。
- 実装:
  - `TVideoMinerOverlaySeekBar.HoverPositionFromPoint` を追加し、トラック付近の hover 座標から対象 ms を取得できるようにした。
  - `TVideoMinerVideoSurface` に hover プレビュー用 Bitmap と描画処理を追加し、下部バーの上へ青系枠付きで表示する。
  - `TVideoMinerVideoView` に任意 Bitmap へデコードする helper を追加し、縦動画でも回転補正後のプレビューを渡せるようにした。
  - `TVideoMinerMainForm` で hover 要求を 140ms タイマーで間引いて、近い位置では前回画像を再利用する軽量動作にした。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
- 今後の調整候補:
  - hover しながら高速移動したときの追従感とデコード負荷のバランスを実機で確認する。
  - プレビューサイズ、枠色、表示位置、時間ラベル表示の有無を操作感に合わせて調整する。
  - 必要なら専用デコーダやキャッシュを検討する。

## 2026-06-23 MainForm 肥大化防止工程 完了
- 方針:
  - `VideoMinerMainForm` を VCL 部品保持、Windows message 入口、controller 生成と接続を担当する配線係へ寄せる。
  - 表示状態、操作の意味づけ、再生/シーク/一覧/overlay の制御は機能単位の controller / session へ分離する。
- 追加/分離した主なユニット:
  - `VideoMinerMediaSession.pas`
    - 現在ファイル、動画情報、シーク位置、現在表示位置、ループ区間、終端動作を保持する状態置き場。
  - `VideoMinerSeekHoverPreviewController.pas`
    - シークバー hover プレビューの timer、デコード、再利用、表示/消去を担当する。
  - `VideoMinerFrameGuideController.pas`
    - hover 用フォーム枠の Panel 群、timer、表示判定、layout 更新を担当する。
  - `VideoMinerThumbnailBrowserController.pas`
    - 同一フォルダ内動画一覧の生成、表示切り替え、選択、キー/ホイール処理を担当する。
  - `VideoMinerCurrentFileReloadController.pas`
    - 現在ファイルの外部更新監視、更新落ち着き待ち、再読込を担当する。
  - `VideoMinerChapterController.pas`
    - Check/チャプター操作、overlay 反映、手動チャプター保存/復元、ループ位置保存を担当する。
  - `VideoMinerExternalOpenController.pas`
    - ドラッグ&ドロップ、二重起動からの `WM_COPYDATA`、保留 open キュー、OLE 初期化/終了を担当する。
  - `VideoMinerNavigationController.pas`
    - フォルダ内の前後動画移動、前後ボタン状態、移動直後の残留キー入力抑止を担当する。
  - `VideoMinerMediaLoadController.pas`
    - 動画読み込み前後の停止/クリア、失敗時/成功時の各 controller 反映を担当する。
  - `VideoMinerInfoController.pas`
    - caption、独自タイトルバー、動画/音声情報表示、シーク進捗、情報更新間引きを担当する。
- `VideoMinerCommandController.pas`
  - overlay の `+` / `-` / `Check` / 終端動作クリックも command controller 経由に寄せた。
- 結果:
  - `VideoMinerMainForm.pas` は、工程開始時より大きく縮小した。
  - 2026-06-23 の最終段階で `VideoMinerMainForm.pas` は 1122 行。
  - MainForm に残す責務は、フォーム生成/破棄、VCL イベント入口、Windows message 入口、controller 接続、再生/シークの最小限の橋渡しとした。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - `tools\EnsureUtf8Bom.ps1 -Check`: 成功。

## 2026-06-23 シークバー hover プレビューが表示されない場合の改善
- 報告:
  - シークバーへ hover しても何も表示されないように見える。
- 改善:
  - hover 判定範囲を細いトラック線付近だけでなく、シークバー横幅内の下部バー領域へ広げた。
  - preview frame の fast seek が失敗した場合、通常 seek でもう一度デコードを試すようにした。
  - 一度はデコード待ち枠を先に表示する形にしたが、表示の時系列が不自然だったため、デコード完了後に枠線ごとプレビューを同時表示する形へ戻した。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。

## 2026-06-23 R キーで表示を90度回転
- 目的:
  - 回転 metadata とは別に、ユーザー操作で表示だけを 90 度ずつ回して確認できるようにする。
- 実装:
  - `R` キーを表示回転に割り当てた。
  - 既存の `R` キー再生速度切り替えは `S` キーへ移した。
  - `VideoMinerVideoView.pas` に手動表示回転 offset を追加し、metadata 回転と合成して表示するようにした。
  - 通常表示、再生中の次フレーム、scratch frame、シークバー hover プレビューのデコード結果へ同じ回転を反映する。
  - 回転切り替え時は表示キャッシュと hover プレビューを消し、現在位置のフレームを新しい向きで描き直す。
  - 再生中に押した場合は現在位置を維持して再生を再開する。
  - `README.md` の主な特徴と基本操作へ `R` 表示回転、`S` 再生速度切り替えを追加した。
  - F1 のヘルプ兼用画面にも `R` / `S` の操作を追加した。
- 確認:
  - Win64 Debug: 成功、警告 0 / エラー 0。
  - `tools\EnsureUtf8Bom.ps1 -Check`: 成功。

## 2026-06-23 起動時ファイル読み込みの2段階化
- 目的:
  - 起動直後に前回ファイルや引数ファイルの読み込みまで同期実行すると、フォーム表示まで待たされて見える。
  - 実際の読み込み時間を完全に消すのではなく、まず基本フォームを表示してからファイル読み込みへ進め、体感速度を上げる。
- 実装:
  - `VideoMiner.dpr` で `Application.Run` 前に `OpenAndPlayFile` / `OpenRememberedFile` を直接呼ぶ処理をやめた。
  - `TVideoMinerMainForm.QueueStartupOpenFile` / `QueueStartupOpenRemembered` を追加し、起動後 open を予約する形にした。
  - `WM_VM_STARTUP_OPEN` を追加し、メッセージループ開始後に前回ファイルまたは引数ファイルを読み込むようにした。
  - 起動後の読み込み中は `Loading last video...` / `Loading video...` を表示する。
- 確認:
  - Win64 Release: 成功、エラー 0。
  - 起動後、先に `VideoMiner - No video loaded` が表示され、その後 `Loading last video...`、動画タイトル、動画情報へ段階的に切り替わることを確認した。
  - 実測例では約 426ms で基本フォーム表示、約 543ms で loading 表示、約 1016ms で動画タイトル表示へ進んだ。

## 2026-06-24 サムネイルフリーズ調査メモ
- `Tab` で開くサムネイル一覧のフリーズ対策として、サムネイル生成 worker 化、hover 実プレビュー停止、キャッシュ miss 時のデコード停止、ログ追加などを試したが、ユーザー環境では改善しなかった。
- `Ctrl+F5` 後だけでなく、最初のサムネイル表示でも操作を受け付けなくなる状態が残ったため、この系統の変更はいったん破棄する。
- 最後のコミット `f09a31f 方針を追加` へ戻した上で、必要最低限の `Ctrl+F5` キャッシュ削除機能だけを再追加する方針にした。
- 今後サムネイルフリーズへ再挑戦する場合は、UI スレッド上での動画デコード、PNG 読み込み、フォルダ履歴描画、VCL タイマー再入を個別に測れるログを先に入れ、機能変更と計測を分ける。

## 2026-06-24 note.md 整理
- `note.md` が仕様説明、現在状態、実装済み機能、ビルド手順、共通ルール、調査メモ、履歴を抱えて肥大化していたため、課題リスト中心へ縮小した。
- 仕様、プロジェクト構成、ビルド、文字コード、コメント規約は `README.md` の開発向け補足へ移した。
- 日付付きのサムネイルフリーズ調査メモは `HISTORY.md` へ移した。
- 今後は、完了した課題や調査結果を `HISTORY.md` へ移し、`note.md` には作業再開時に見る未解決課題だけを残す方針にした。

## 2026-06-24 フォルダ履歴タイルの代表サムネイル表示変更
- サムネイル一覧 1 行目のフォルダ履歴タイルで、代表サムネイル表示を大 1 枚 + 小 3 枚の重ね表示から、大きめの 3 枚横並びへ変更した。
- 小さい 3 枚は視認性が低くフォルダ識別に使いにくかったため、同じ高さのサムネイルを横に並べて見やすさを優先した。
- 代表候補の選び方は既存の安定選択ロジックを維持し、描画中に過去履歴フォルダを走査しない方針も変更していない。

## 2026-06-24 サムネイル一覧の仮想スクロール位置表示
- サムネイル一覧の右下 `+` / `-` ボタンの上に、現在の縦スクロール位置だけを示す細い仮想スクロールバーを追加した。
- VCL 標準スクロールバーは使わず、一覧コントロール上へトラックとつまみを自前描画するだけにした。
- まだドラッグ操作やクリック操作は持たせず、スクロール可能な時だけ位置表示として出す。

## 2026-06-24 サムネイル一覧の仮想スクロールバー操作
- 仮想スクロールバーのつまみをドラッグして、サムネイル一覧を縦スクロールできるようにした。
- トラック部分をクリックした場合は、その位置へつまみ中心を移動してからドラッグを開始する。
- 見た目は細いままにしつつ、操作判定だけ左右へ広げて掴みやすくした。

## 2026-06-24 サムネイル右下の動画時間表示
- サムネイル画像の右下へ、動画配信サイト風の黒い時間バッジを重ねて表示するようにした。
- 表示形式は 1 時間未満を `m:ss`、1 時間以上を `h:mm:ss` とした。
- サムネイル生成時に取得した動画時間を保持し、キャッシュヒット時も動画情報だけを読んで時間表示できるようにした。

## 2026-06-24 サムネイル動画時間の文字サイズ調整
- サムネイル右下の動画時間バッジがやや小さく見えたため、文字サイズを 9pt 以上に上げた。
- サムネイル表示サイズに合わせ、9pt から 11pt の範囲で少しだけ可変にした。

## 2026-06-24 サムネイル動画時間の INI キャッシュ
- サムネイル右下に表示する動画時間を `VideoMiner.ini` の `VideoMeta:` セクションへ保存するようにした。
- 保存時は対象ファイルのサイズと UTC 更新日時も記録し、ファイルが変わっていない場合だけ動画時間キャッシュを使う。
- サムネイル画像のディスクキャッシュヒット時に、動画情報を毎回読み直さず時間表示できるようにした。

## 2026-06-24 フォルダドロップ対応
- ファイルだけでなくフォルダをドロップされた場合も、対象フォルダ内の先頭動画ファイルを開けるようにした。
- 先頭動画は既存の `TVideoMinerMediaList.FirstMediaFileInFolder` を使い、フォルダ内ナビゲーションと同じ対象拡張子/並び順で決める。
- 実際に開いた動画ファイルを前回ファイルとして保存するようにし、フォルダパスそのものを前回ファイルとして残さないようにした。

