# MTF Conscious Line Detector - インストールガイド

## 目次
1. [必要要件](#必要要件)
2. [インストール手順](#インストール手順)
3. [初期設定](#初期設定)
4. [動作確認](#動作確認)
5. [よくある問題と解決方法](#よくある問題と解決方法)

## 必要要件

### システム要件
- **OS**: Windows 7/8/10/11, macOS, Linux
- **メモリ**: 最低4GB RAM（8GB以上推奨）
- **MT5バージョン**: Build 3000以降（最新版推奨）

### 対応ブローカー
- MT5に対応している全てのブローカー
- デモ口座・リアル口座の両方で利用可能

## インストール手順

### 方法1: 自動インストール（推奨）

1. **ファイルのダウンロード**
   - `MTF_Conscious_Line_Detector.mq5` をダウンロード

2. **MT5のデータフォルダを開く**
   - MT5を起動
   - メニューから「ファイル」→「データフォルダを開く」を選択
   - または、`Ctrl + Shift + D` キーを押す

3. **ファイルのコピー**
   - 開いたフォルダから `MQL5` → `Indicators` フォルダに移動
   - `MTF_Conscious_Line_Detector.mq5` をこのフォルダにコピー

4. **コンパイル**
   - MT5のツールバーから「ツール」→「MetaQuotes Language Editor」を選択（MetaEditorが開く）
   - 左側のナビゲーターで「Indicators」→「MTF_Conscious_Line_Detector.mq5」をダブルクリック
   - `F7` キーを押してコンパイル
   - 「0 error(s), 0 warning(s)」と表示されたら成功

5. **MT5の再起動**
   - MT5を一度閉じて、再起動

6. **インジケーターの確認**
   - MT5のナビゲーターウィンドウ（`Ctrl + N`）を開く
   - 「インジケーター」→「カスタム」を展開
   - 「MTF Conscious Line Detector」が表示されていることを確認

### 方法2: 手動インストール

MT5のデータフォルダの場所が分かる場合：

**Windows:**
```
C:\Users\[ユーザー名]\AppData\Roaming\MetaQuotes\Terminal\[インスタンスID]\MQL5\Indicators\
```

**macOS:**
```
~/Library/Application Support/MetaQuotes/Terminal/[インスタンスID]/MQL5/Indicators/
```

**Linux:**
```
~/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Indicators/
```

上記のパスに `MTF_Conscious_Line_Detector.mq5` をコピーし、MetaEditorでコンパイルしてください。

## 初期設定

### チャートへの適用

1. **チャートを開く**
   - 任意の通貨ペア（推奨: USD/JPY, EUR/USD, GBP/USDなど）
   - 1分足チャート（M1）を開く

2. **インジケーターを適用**
   - ナビゲーターから「MTF Conscious Line Detector」をチャートにドラッグ＆ドロップ
   - または、チャートを右クリック→「表示中のインジケーター」→「追加」

3. **パラメーター設定**
   - 初回は**デフォルト設定のまま**「OK」をクリック
   - 後でカスタマイズ可能

### 推奨初期設定（初心者向け）

```
基本設定:
  InpPivotPeriod = 5
  InpLookbackBars = 500
  InpZoneWidthPips = 5.0
  InpMinTryCount = 2      ← 信頼性の高いラインのみ表示
  InpMaxLinesPerTF = 8    ← ライン数を制限

表示設定:
  InpShowMonthly = true
  InpShowWeekly = true
  InpShowDaily = true
  InpShow4H = true
  InpShow1H = true
  InpShow30M = false      ← 下位足は非表示（チャートをシンプルに）
  InpShow15M = false
  InpShow5M = false
  InpShowNecklines = true
  InpShowLabels = true
```

## 動作確認

### 正常に動作している場合

チャート上に以下が表示されます：

1. **水平線**
   - 異なる色と太さの水平線が複数表示される
   - 上位足のラインほど重要度が高い

2. **ラベル**
   - 各ラインの右側に「H4-R:3x」のような情報が表示される
   - フォーマット: `[時間足]-[タイプ]:[トライ回数]x`

3. **ネックライン**
   - 黄色の点線が表示される場合がある
   - トレンド転換パターンのネックライン

### チェックポイント

✅ **インジケーターが動作しているか確認:**
- チャート左上の「インジケーター名」欄に「MTF Conscious Line Detector」が表示されている
- エキスパートログ（ツール→オプション→エキスパート）に「MTF Conscious Line Detector 初期化完了」が表示されている

✅ **ラインが描画されているか確認:**
- 少なくとも1-2本のラインが表示されている
- 表示されない場合は、パラメーター設定を調整（`InpMinTryCount = 1` に変更）

## よくある問題と解決方法

### 問題1: インジケーターが表示されない

**原因と対策:**

1. **コンパイルエラー**
   - MetaEditorで再度コンパイル（F7）
   - エラーメッセージを確認し、ファイルが正しくコピーされているか確認

2. **MT5の再起動不足**
   - MT5を完全に終了して再起動

3. **ファイルの配置場所が間違っている**
   - データフォルダ→MQL5→Indicators に配置されているか確認

### 問題2: ラインが表示されない

**対策:**

1. **パラメーター調整**
   ```
   InpMinTryCount = 1       ← 最小値に設定
   InpLookbackBars = 1000   ← 計算範囲を拡大
   ```

2. **時間足の確認**
   - 1分足チャート（M1）で使用しているか確認
   - 他の時間足でも動作しますが、1分足が推奨

3. **通貨ペアの確認**
   - メジャー通貨ペア（USD/JPY, EUR/USDなど）で試す
   - マイナー通貨ペアはデータが不足している場合がある

### 問題3: ラインが多すぎる

**対策:**

```
InpMinTryCount = 3-5      ← 強いラインのみ表示
InpMaxLinesPerTF = 5      ← ライン数を制限
InpShowXXX = false        ← 不要な時間足をOFF
```

### 問題4: 動作が重い・フリーズする

**対策:**

1. **計算負荷を軽減**
   ```
   InpLookbackBars = 300    ← 計算範囲を縮小
   InpMaxLinesPerTF = 5     ← ライン数を制限
   ```

2. **時間足を絞る**
   ```
   InpShow5M = false
   InpShow15M = false
   InpShow30M = false
   ```
   上位足（H4, D, W, MN）のみ表示

3. **PCのスペック確認**
   - メモリ使用率を確認
   - 他のアプリケーションを終了

### 問題5: ラベルが見づらい

**対策:**

- ラベルを非表示にする
  ```
  InpShowLabels = false
  ```

- チャートのズームレベルを調整
  - `Ctrl + マウスホイール` でズーム

### 問題6: エラーログに警告が表示される

**よくある警告メッセージ:**

1. **"Array out of range"**
   - データが不足している可能性
   - `InpLookbackBars` を小さくする（300-500に設定）

2. **"Chart symbol data error"**
   - 通貨ペアのヒストリカルデータが不足
   - ツール→オプション→チャート→「ヒストリー内の最大バー数」を増やす

3. **"Not enough memory"**
   - メモリ不足
   - `InpLookbackBars` を減らす
   - 表示する時間足を減らす

## アップデート方法

新しいバージョンがリリースされた場合：

1. 既存のファイルをバックアップ
2. 新しい `.mq5` ファイルを同じフォルダにコピー（上書き）
3. MetaEditorで再コンパイル（F7）
4. MT5を再起動

## アンインストール方法

1. チャートからインジケーターを削除
   - チャートを右クリック→「表示中のインジケーター」→「MTF Conscious Line Detector」を選択→「削除」

2. ファイルを削除
   - データフォルダ→MQL5→Indicators→`MTF_Conscious_Line_Detector.mq5` を削除
   - データフォルダ→MQL5→Indicators→`MTF_Conscious_Line_Detector.ex5` を削除

3. MT5を再起動

## サポート

問題が解決しない場合は、以下の情報を準備してサポートに連絡してください：

1. MT5のバージョン（ヘルプ→MT5について）
2. OS（Windows/macOS/Linux）とバージョン
3. エキスパートログのスクリーンショット
4. パラメーター設定のスクリーンショット
5. 問題の詳細な説明

---

**次のステップ:**
- [README.md](README.md) で使い方とトレード活用例を確認
- [EXAMPLES.md](EXAMPLES.md) で設定例を確認
