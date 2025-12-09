# MT5 XAUUSD Data Fetcher

MetaTrader5からXAUUSD（金/米ドル）の1分足データを取得し、CSVファイルに保存するPythonスクリプトです。

## 機能

- MT5からXAUUSDの1分足データを取得
- 取得期間：2024年1月1日～2024年12月31日
- 最大50,000本のローソク足データを取得
- OHLCデータをCSVファイルに保存
- エラーハンドリング機能
- データ要約の表示

## 必要な環境

### 前提条件

1. **MetaTrader5がインストールされていること**
   - MT5のターミナルが起動している必要があります
   - デモアカウントまたは実際のアカウントにログインしている必要があります

2. **XAUUSDのシンボルが利用可能であること**
   - ブローカーによって提供されるシンボル名が異なる場合があります
   - 例：`XAUUSD`, `GOLD`, `XAUUSD.i` など

### 必要なライブラリ

```bash
pip install MetaTrader5 pandas
```

## 使い方

### 1. 必要なライブラリのインストール

```bash
pip install MetaTrader5 pandas
```

### 2. MT5の準備

- MetaTrader5を起動
- アカウントにログイン
- XAUUSDがマーケットウォッチに表示されていることを確認

### 3. スクリプトの実行

```bash
python mt5_xauusd_data_fetch.py
```

### 4. 出力ファイル

スクリプトは `xauusd_m1_2024.csv` というファイルを作成します。

## 出力データの形式

CSVファイルには以下のカラムが含まれます：

| カラム名 | 説明 |
|---------|------|
| time | 日時（UTC） |
| open | 始値 |
| high | 高値 |
| low | 安値 |
| close | 終値 |
| tick_volume | ティックボリューム |
| spread | スプレッド |
| real_volume | 実ボリューム |

## 設定のカスタマイズ

`mt5_xauusd_data_fetch.py` の `main()` 関数内で以下の設定を変更できます：

```python
SYMBOL = "XAUUSD"              # シンボル名
TIMEFRAME = mt5.TIMEFRAME_M1   # タイムフレーム
START_DATE = datetime(2024, 1, 1)  # 開始日
END_DATE = datetime(2024, 12, 31, 23, 59, 59)  # 終了日
MAX_BARS = 50000               # 最大取得本数
OUTPUT_FILE = "xauusd_m1_2024.csv"  # 出力ファイル名
```

### タイムフレームの選択肢

- `mt5.TIMEFRAME_M1` - 1分足
- `mt5.TIMEFRAME_M5` - 5分足
- `mt5.TIMEFRAME_M15` - 15分足
- `mt5.TIMEFRAME_M30` - 30分足
- `mt5.TIMEFRAME_H1` - 1時間足
- `mt5.TIMEFRAME_H4` - 4時間足
- `mt5.TIMEFRAME_D1` - 日足
- `mt5.TIMEFRAME_W1` - 週足
- `mt5.TIMEFRAME_MN1` - 月足

## トラブルシューティング

### MT5の初期化に失敗する場合

1. MT5のターミナルが起動していることを確認
2. アカウントにログインしていることを確認
3. MT5が最新版であることを確認

### シンボルが見つからない場合

1. ブローカーが提供するシンボル名を確認
   - 例：`XAUUSD`, `GOLD`, `XAUUSD.i` など
2. MT5のマーケットウォッチでシンボルを確認
3. スクリプト内の `SYMBOL` 変数を適切な名前に変更

### データが取得できない場合

1. ブローカーが提供する履歴データの範囲を確認
2. インターネット接続を確認
3. MT5のアカウントが有効であることを確認

## 注意事項

- データの取得には時間がかかる場合があります（特に大量のデータを取得する場合）
- ブローカーによって提供される履歴データの範囲が異なります
- 1分足データは大量になる可能性があるため、ディスク容量を確認してください
- スクリプト実行中はMT5を閉じないでください

## ライセンス

このスクリプトは自由に使用・改変できます。

## 参考リンク

- [MetaTrader5 Python ドキュメント](https://www.mql5.com/en/docs/python_metatrader5)
- [Pandas ドキュメント](https://pandas.pydata.org/docs/)
