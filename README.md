# VideoMiner

VideoMiner は、動画ファイルをフォルダ単位で続けて確認するための Windows 用ビューアです。

通常のメディアプレイヤーのように 1 ファイルずつ開くのではなく、開いた動画と同じフォルダ内のファイルを作業対象として扱い、前後の動画へ素早く移動できます。素材確認、動画確認、フォルダ内の連続チェックを軽く行うためのアプリです。

## ダウンロード

最新版は GitHub Releases からダウンロードしてください。

- [最新版をダウンロード](https://github.com/vramwiz/VideoMiner/releases/latest)
- [すべてのリリース履歴を見る](https://github.com/vramwiz/VideoMiner/releases)

リリースには、用途に応じて複数のファイルがあります。

| ファイル | 内容 | 使い方 |
| --- | --- | --- |
| `VideoMiner_Setup.exe` | インストーラ本体 | 通常はこちらを実行してインストールします。 |
| `VideoMiner_Setup.zip` | インストーラを ZIP にしたもの | ブラウザや環境によって `.exe` を直接扱いにくい場合はこちらを展開して使います。 |
| `VideoMiner_Portable.zip` | インストール不要版 | 任意のフォルダへ展開し、`VideoMiner.exe` を直接起動します。 |

どの形式にも、実行に必要な FFmpeg DLL と GPL-3.0 のライセンス文書を含める想定です。

## 主な特徴

- 動画ファイルの再生
- 開いたファイルと同じフォルダ内の前後動画へ移動
- ファイルのドラッグ&ドロップ対応
- シーク、再生/停止、音量、ミュート
- 全画面表示
- マウスホイールによるズーム
- 拡大中のドラッグ移動
- 前回開いたファイルやウィンドウ位置の保存

## 基本操作

| 操作 | 内容 |
| --- | --- |
| `Ctrl+O` | ファイルを開く |
| `Space` | 再生/停止 |
| `Left` / `Right` | 前後の動画へ移動 |
| `Home` / `End` | 先頭/末尾付近へ移動 |
| `Up` / `Down` | 音量を変更 |
| `M` | ミュート切り替え |
| `F11` | 全画面切り替え |
| `Esc` | 全画面解除 |
| マウスホイール | 動画表示部分の拡大/縮小 |
| 左ドラッグ | 拡大中の表示位置移動 |

## 動作環境

- Windows 64bit

## 設定ファイル

VideoMiner は、ユーザー設定を次の場所に保存します。

```text
%APPDATA%\VideoMiner\VideoMiner.ini
```

アンインストールしても設定ファイルは残る場合があります。不要な場合は、このフォルダを手動で削除してください。

## ライセンス

VideoMiner は [GNU General Public License version 3](LICENSE) に従って配布します。

動画の読み込みとデコードには FFmpeg を使用します。FFmpeg は VideoMiner 本体とは別の著作物であり、FFmpeg 側のライセンス条件が適用されます。

- [FFmpeg](https://ffmpeg.org/)
- [FFmpeg License and Legal Considerations](https://ffmpeg.org/legal.html)

## 開発メモ

詳細な作業メモや設計方針は [note.md](note.md) に記載しています。
