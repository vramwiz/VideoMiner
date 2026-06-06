# VideoMiner note

## アプリの目的

VideoMiner は、動画や画像を快適に見るための Windows/VCL アプリとして設計する。

単純な再生アプリではなく、既存のメディアプレイヤーやフォトアプリで感じる不満を減らすことを目的にする。

想定する不満:

- いま開いているファイルと同じフォルダ内の別ファイルへ移動しにくい。
- 次の動画や画像を見るために、毎回ファイルを開き直す必要がある。
- 動画や画像の一部を確認したいとき、ズームや表示位置の操作が弱い。
- フォルダ内の素材を続けて確認する作業に向いていない。

VideoMiner は、素材確認・動画確認・画像確認を軽く行えるビューアを目指す。

## 基本仕様

### ファイル表示

- 動画ファイルを開いて表示できる。
- 将来的には画像ファイルも同じ操作感で表示できるようにする。
- 開いたファイルのフォルダを自動的に認識する。
- 同じフォルダ内の前後のファイルへ簡単に移動できるようにする。
- ファイルをあらためて開き直さなくても、次のファイルを表示できるようにする。

### フォルダ内ナビゲーション

- 開いたファイルを基準に、同じフォルダのメディア一覧を作る。
- 「次へ」「前へ」でフォルダ内のファイルを切り替える。
- 動画と画像を同じ一覧で扱うか、種類ごとに分けるかは今後決める。
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
  - アプリ本体、メインフォーム。
- `Source\Decode`
  - 既存のメディア処理ユニット。
- `Source\FFmpeg`
  - FFmpeg API、変換、ストリーム情報などの共通部分。
- `Source\Lib`
  - アプリから使う汎用補助ユニット。
  - 現在はドラッグ&ドロップ用の `DropAgent` と、タイマー補助の `MMTimer` がある。

## 現在の状態

- プロジェクト名は `VideoMiner`。
- メインフォームは `VideoMinerMainForm`。
- ルート直下に多数あった `.pas` は `Source` 配下へ移動済み。
- 現時点では、VideoMiner アプリ本体として動画表示機能を整理している。
- メインフォームはデバッグ用の操作ボタンや情報ラベルを外し、動画ビューだけを表示する構成へ移行中。
- 出力系、AviUtl 連携、入力プラグイン由来の処理は削除済み。
- デバッグ用・テスト場由来の処理は、アプリに不要なものから削除している。

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
- キーボード操作で `-10s` / `+10s` 相当の移動を行う。
- `-10s` は 10 秒未満なら開始位置へ移動する。
- `+10s` は残り 10 秒未満なら終了位置へ移動する。
- 10 秒スキップ直後に再生タイマー側の古い位置更新でシークバーが揺れないよう、シーク中フラグとシーク直後のガードを入れている。
- 2026-06-06 時点で、デバッグ用の画面上ボタン類は削除し、操作はキーボードとファイルドロップ中心に移行した。

## ビルド

Debug Win64 ビルド例:

```powershell
$env:BDS='C:\Program Files (x86)\Embarcadero\Studio\37.0'
& 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe' `
  'D:\DelphiProg\test\VideoMiner\VideoMiner.dproj' `
  /t:Build /p:Config=Debug /p:Platform=Win64
```

直近の確認:

- Debug Win64 ビルド成功。
- 生成物:
  - `D:\DelphiProg\test\VideoMiner\Win64\Debug\VideoMiner.exe`
- エラー 0。
- 警告 0。

## 共通メモ

- Delphi ソースは文字コードが混在しやすいので、編集後は文字化けが起きていないか差分を確認する。
- `.pas` / `.dfm` を触った後は、必ず Debug Win64 ビルドで確認する。
- Debug ビルド時のみ、再生同期調査ログを `%TEMP%\VideoMiner_playback_debug.log` に出力する。
  - 実装は `Source\App\VideoMinerDebugLog.pas`。
  - `VideoMiner.dproj` の Debug 構成は `DEBUG` define を持つため、ログ出力は `{$IFDEF DEBUG}` で Release ビルドには入れない。
  - 主な行は `playback_tick`、`paint`、`start_playback`、`restart_playback`。
  - `playback_tick` では `audio_ms`、`video_ms`、`lag_ms`、`drop_count`、`pump_ms`、`decode_ms`、`sync_ms`、`total_ms`、`timer_interval` を確認する。
  - `paint` では `paint_ms` を確認し、`Canvas.StretchDraw` を含む描画負荷を見る。
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

### シーク時の同期

- シークバーを再生中に動かした場合、以前は `ShowFrameAtMs` だけを呼んでいたため、映像だけ移動して音声は元位置のまま続いていた。
- 現在は再生中のシークバー操作では `SeekToMs` を通し、タイマー停止、音声停止、映像表示、必要なら再生再開を行う。
- シーク位置での映像と音声の同期は、現在の確認では正常。
- 音声再生用デコーダは別インスタンスなので、音声開始前に動画フレームを読むシークではなく、音声ストリームへ `SeekAudioToMs` するようにした。
- `SeekAudioToMs` 後は、シーク直後の先頭だけ target より前の音声サンプルを捨てるため `AudioDiscardUntilSample` を使う。

### 解消済みの同期問題

- 2026-06-06 の確認では、再生中に音声と映像がだんだんズレる症状は解消した。
- 以前は約 44.7 秒付近から音声キュー判定が壊れ、音声が止まる、または音声位置が正しく扱えなくなる症状が出ていた。
- 原因は `PlaybackPositionMs * AUDIO_OUTPUT_SAMPLE_RATE` が 32bit `Integer` 計算になり、`44700 * 48000` 付近でオーバーフローしていたこと。
- 対策として `PlaybackSamplePosition`、`PlaybackSampleCount`、`RawQueuedSampleCount`、`queued_ms` 計算を `Int64` ベースにした。
- 修正後のログでは、以前止まっていた 44.7 秒以降も `audio_pump` が継続し、`queue_full` や負の `queued_ms` は出ていない。
- 修正後の確認ログでは `lag_ms` はおおむね `-30..30` ms の範囲で、再生中に差が蓄積する挙動は見られない。
- `audio_pump` に 45ms 程度の一時的なスパイクはあるが、音声キューは約 960..1010ms で維持されており、現時点では同期ズレの原因ではなさそう。

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

- ズーム表示とパン操作。
- 画像ファイル対応。
- ビュー専用フォームに重ねる最小限の本番用オーバーレイ UI を検討する。
- アプリ本体で使わない既存補助ユニットの必要性を整理し、不要なら外す。

設計メモ:

- VideoMiner は「出力する」よりも「見る」「探す」「確認する」を中心にする。
- ファイルを開いた瞬間に、そのフォルダ全体を作業対象として扱う。
- ユーザーがファイル選択ダイアログを何度も開かなくて済む操作にする。
- 動画と画像を横断して確認できるビューアを目指す。

