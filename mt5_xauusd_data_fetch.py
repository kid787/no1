"""
MetaTrader5 XAUUSD Data Fetcher
=================================
このスクリプトは、MT5からXAUUSD（金/米ドル）の1分足データを取得し、CSVファイルに保存します。

実行前の確認事項：
1. MetaTrader5がインストールされていること
2. MT5アカウントにログインしていること
3. XAUUSDのシンボルが利用可能であること
4. 必要なライブラリがインストールされていること：
   - pip install MetaTrader5 pandas

注意事項：
- MT5のターミナルが起動している必要があります
- データ取得には時間がかかる場合があります（最大50,000本）
- ブローカーによってはデータの利用可能範囲が異なる場合があります
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime
import sys
import os


def initialize_mt5():
    """
    MT5を初期化する

    Returns:
        bool: 初期化成功時はTrue、失敗時はFalse
    """
    print("MT5を初期化中...")
    if not mt5.initialize():
        print(f"MT5の初期化に失敗しました。エラーコード: {mt5.last_error()}")
        return False

    print(f"MT5バージョン: {mt5.version()}")
    print(f"MT5ターミナル情報: {mt5.terminal_info()}")
    print("MT5の初期化に成功しました。")
    return True


def check_symbol_availability(symbol):
    """
    シンボルの利用可能性を確認する

    Args:
        symbol (str): チェックするシンボル名

    Returns:
        bool: シンボルが利用可能な場合はTrue、そうでない場合はFalse
    """
    print(f"\n{symbol}の利用可能性をチェック中...")

    # シンボルを選択
    if not mt5.symbol_select(symbol, True):
        print(f"{symbol}の選択に失敗しました。エラー: {mt5.last_error()}")
        return False

    # シンボル情報を取得
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        print(f"{symbol}の情報を取得できませんでした。")
        return False

    if not symbol_info.visible:
        print(f"{symbol}はマーケットウォッチに表示されていません。")
        if not mt5.symbol_select(symbol, True):
            print(f"{symbol}をマーケットウォッチに追加できませんでした。")
            return False

    print(f"{symbol}は利用可能です。")
    print(f"シンボル情報: {symbol_info}")
    return True


def fetch_ohlc_data(symbol, timeframe, start_date, end_date, max_bars=50000):
    """
    OHLCデータを取得する

    Args:
        symbol (str): シンボル名（例: "XAUUSD"）
        timeframe: タイムフレーム（例: mt5.TIMEFRAME_M1）
        start_date (datetime): 開始日時
        end_date (datetime): 終了日時
        max_bars (int): 取得する最大ローソク足本数

    Returns:
        pd.DataFrame: OHLCデータのデータフレーム、失敗時はNone
    """
    print(f"\n{symbol}のデータ取得中...")
    print(f"期間: {start_date} ～ {end_date}")
    print(f"タイムフレーム: M1（1分足）")
    print(f"最大取得本数: {max_bars}本")

    # データを取得
    rates = mt5.copy_rates_range(symbol, timeframe, start_date, end_date)

    if rates is None:
        print(f"データの取得に失敗しました。エラー: {mt5.last_error()}")
        return None

    if len(rates) == 0:
        print("データが見つかりませんでした。")
        return None

    print(f"取得したローソク足の本数: {len(rates)}本")

    # 最大本数を制限
    if len(rates) > max_bars:
        print(f"データを最新の{max_bars}本に制限します。")
        rates = rates[-max_bars:]

    # DataFrameに変換
    df = pd.DataFrame(rates)

    # タイムスタンプを日時に変換
    df['time'] = pd.to_datetime(df['time'], unit='s')

    return df


def save_to_csv(df, filename):
    """
    データフレームをCSVファイルに保存する

    Args:
        df (pd.DataFrame): 保存するデータフレーム
        filename (str): 保存するファイル名

    Returns:
        bool: 保存成功時はTrue、失敗時はFalse
    """
    try:
        print(f"\nCSVファイルに保存中: {filename}")
        df.to_csv(filename, index=False)

        # ファイルサイズを確認
        file_size = os.path.getsize(filename)
        print(f"ファイルの保存に成功しました。")
        print(f"ファイルサイズ: {file_size / 1024 / 1024:.2f} MB")
        print(f"保存パス: {os.path.abspath(filename)}")

        return True
    except Exception as e:
        print(f"CSVファイルの保存に失敗しました。エラー: {e}")
        return False


def shutdown_mt5():
    """
    MT5をシャットダウンする
    """
    print("\nMT5をシャットダウン中...")
    mt5.shutdown()
    print("MT5をシャットダウンしました。")


def display_data_summary(df):
    """
    データの要約を表示する

    Args:
        df (pd.DataFrame): 表示するデータフレーム
    """
    print("\n=== データ要約 ===")
    print(f"データ件数: {len(df)}件")
    print(f"\n期間:")
    print(f"  開始: {df['time'].min()}")
    print(f"  終了: {df['time'].max()}")
    print(f"\n価格範囲:")
    print(f"  最高値: {df['high'].max()}")
    print(f"  最安値: {df['low'].min()}")
    print(f"\n最初の5件:")
    print(df.head())
    print(f"\n最後の5件:")
    print(df.tail())
    print(f"\nカラム情報:")
    print(df.dtypes)


def main():
    """
    メイン処理
    """
    # 設定
    SYMBOL = "XAUUSD"
    TIMEFRAME = mt5.TIMEFRAME_M1
    START_DATE = datetime(2024, 1, 1)
    END_DATE = datetime(2024, 12, 31, 23, 59, 59)
    MAX_BARS = 50000
    OUTPUT_FILE = "xauusd_m1_2024.csv"

    print("=" * 60)
    print("MetaTrader5 XAUUSD Data Fetcher")
    print("=" * 60)

    try:
        # MT5を初期化
        if not initialize_mt5():
            print("\n処理を中断します。")
            sys.exit(1)

        # シンボルの利用可能性を確認
        if not check_symbol_availability(SYMBOL):
            print("\n処理を中断します。")
            shutdown_mt5()
            sys.exit(1)

        # データを取得
        df = fetch_ohlc_data(SYMBOL, TIMEFRAME, START_DATE, END_DATE, MAX_BARS)

        if df is None:
            print("\n処理を中断します。")
            shutdown_mt5()
            sys.exit(1)

        # データの要約を表示
        display_data_summary(df)

        # CSVファイルに保存
        if not save_to_csv(df, OUTPUT_FILE):
            print("\n処理を中断します。")
            shutdown_mt5()
            sys.exit(1)

        print("\n" + "=" * 60)
        print("処理が正常に完了しました。")
        print("=" * 60)

    except Exception as e:
        print(f"\n予期しないエラーが発生しました: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    finally:
        # MT5をシャットダウン
        shutdown_mt5()


if __name__ == "__main__":
    main()
