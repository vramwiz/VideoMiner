# VideoMiner

VideoMiner は、動画や画像を快適に確認するための Windows/VCL アプリです。

単純なメディアプレイヤーではなく、開いたファイルのフォルダをそのまま作業対象として扱い、次のファイルや前のファイルへ素早く移動できるビューアを目指しています。

## 目的

既存のメディアプレイヤーやフォトアプリで感じる、次のような不便を減らすことを目的にしています。

- 同じフォルダ内の別ファイルへ移動しにくい。
- 次の動画や画像を見るために、毎回ファイルを開き直す必要がある。
- 画像や動画の一部を見たいときに、ズームや表示位置の操作が弱い。
- 素材確認や連続確認の作業に向いていない。

## 予定している機能

- 動画ファイルの表示と再生。
- 画像ファイルの表示。
- 開いたファイルと同じフォルダ内のメディア一覧作成。
- 次/前ファイルへの簡単な移動。
- 任意位置のズーム表示。
- ズーム中のパン操作。
- 全体表示、等倍表示、任意倍率表示。
- シーク、停止、一時停止などの基本操作。

## 現在の状態

現在は、既存の動画表示テストをベースに `VideoMiner` アプリとして再構成している段階です。

プロジェクト名は `VideoMiner` に変更済みで、ソースは `Source` 配下に整理しています。

## 構成

- `VideoMiner.dpr`
- `VideoMiner.dproj`
- `Source\App`
- `Source\AviUtl`
- `Source\Decode`
- `Source\Encode`
- `Source\FFmpeg`
- `Source\PluginInput`
- `note.md`

## ビルド

Debug Win64 ビルド例:

```powershell
$env:BDS='C:\Program Files (x86)\Embarcadero\Studio\37.0'
& 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe' `
  'D:\DelphiProg\test\VideoMiner\VideoMiner.dproj' `
  /t:Build /p:Config=Debug /p:Platform=Win64
```

直近では Debug Win64 ビルドが成功し、以下が生成されています。

```text
D:\DelphiProg\test\VideoMiner\Win64\Debug\VideoMiner.exe
```

## FFmpeg DLL について

開発時は FFmpeg の DLL を `Win64\Debug` や `Win64\Release` に配置して動作確認します。

ただし、このリポジトリには FFmpeg の DLL や配布バイナリを同梱しません。必要な DLL は利用者が別途用意する方針です。

## メモ

詳細な作業メモや今後の設計方針は `note.md` に記載しています。
