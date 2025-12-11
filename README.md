# XAUUSD Dow Theory EA for MT5

## Overview

XAUUSD（Gold）専用のダウ理論ベースExpert Advisor（EA）です。Fintokeiチャレンジプラン対応のリスク管理システムを搭載し、スキャルピング/デイトレードに最適化されています。

### Key Features

- **ダウ理論コアロジック**: 高値安値の切り上げ/切り下げによるトレンド判定
- **Smart Money Concepts (SMC)**: Order Blocks, Fair Value Gaps, Break of Structure
- **マルチタイムフレーム分析**: H4（トレンド）、H1（エントリー設定）、M15（精密エントリー）
- **Fintokeiリスク管理**: 日次損失5%、全体損失10%の厳格な制限
- **セッションフィルター**: ロンドン-NYオーバーラップ時間に最適化
- **ATRベースダイナミックSL/TP**: ボラティリティに応じた損切り/利確

## Installation

### Directory Structure

```
MQL5/
├── Experts/
│   └── XAUUSD_DowTheory_EA.mq5    # メインEAファイル
└── Include/
    ├── DowTheory.mqh              # ダウ理論分析モジュール
    ├── RiskManager.mqh            # Fintokeiリスク管理
    ├── SmartMoneyConcepts.mqh     # SMC分析モジュール
    ├── TradeManager.mqh           # 取引管理モジュール
    └── ChartDisplay.mqh           # チャート情報表示
```

### Installation Steps

1. `Experts/XAUUSD_DowTheory_EA.mq5` を `MQL5/Experts/` フォルダにコピー
2. `Include/` フォルダの全ファイルを `MQL5/Include/` にコピー
3. MetaTrader 5でコンパイル
4. XAUUSDチャートにEAをアタッチ

## Configuration

### Risk Management Parameters (Fintokei)

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| InpInitialBalance | 2,000,000 | 初期残高（JPY） |
| InpDailyLossLimitPct | 5.0 | 1日の最大損失率（%） |
| InpOverallLossLimitPct | 10.0 | 全体の最大損失率（%） |
| InpSafetyBufferPct | 0.1 | 安全バッファ（%） |
| InpRiskPerTradePct | 1.0 | 1トレードあたりリスク（%） |

### Trading Parameters

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| InpMagicNumber | 202412 | マジックナンバー |
| InpMaxTradesPerDay | 3 | 1日の最大取引数 |
| InpATRMultiplierSL | 2.0 | ATR倍率（SL用） |
| InpATRMultiplierTP | 3.0 | ATR倍率（TP用） |

### Timeframe Settings

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| InpHTFPeriod | H4 | 上位時間足（トレンド判定） |
| InpBasePeriod | H1 | 基準時間足（エントリー設定） |
| InpEntryPeriod | M15 | エントリー時間足 |

### Session Filter

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| InpUseSessionFilter | true | セッションフィルター使用 |
| InpTradeOverlapOnly | true | オーバーラップ時間のみ取引 |
| InpLondonStartHour | 8 | ロンドン開始（GMT） |
| InpNYStartHour | 13 | NY開始（GMT） |

## Trading Strategy

### 1. Dow Theory Analysis

EAは以下のダウ理論メソッドを実装しています：

#### Method 1: Check_Dow_Trend_Status
- **上昇トレンド**: 高値・安値ともに切り上がり（N波動の連続）
- **下降トレンド**: 高値・安値ともに切り下がり（逆N波動の連続）
- **レンジ**: 高値・安値いずれも更新されない状態

#### Method 2: Identify_Key_Pivot_Points
- **押し安値（Oshiyasune）**: 直近高値を抜いた安値
- **戻り高値（Modoritakane）**: 直近安値を抜いた高値

#### Method 3: Confirm_Trend_Continuity
- N波動/逆N波動の連続性を確認
- トレンドの健全性をモニタリング

#### Method 4: Check_Trend_Reversal_Confirmed
- 上昇→下降: 押し安値下抜け + 高値切り下げ
- 下降→上昇: 戻り高値上抜け + 安値切り上げ

### 2. Multi-Timeframe Analysis (Method 5)

```
H4 (Higher Timeframe) → 主トレンド方向
  ↓
H1 (Base Timeframe) → エントリー設定
  ↓
M15 (Entry Timeframe) → 精密エントリー
```

全時間足のトレンドが一致した場合に高い優位性と判断。

### 3. Smart Money Concepts

#### Order Blocks (OB)
- **Bullish OB**: 強い上昇の前の最後の弱気ローソク足
- **Bearish OB**: 強い下落の前の最後の強気ローソク足

#### Fair Value Gaps (FVG)
- 価格の急激な動きによる3本ローソク足の隙間
- 価格がこの隙間を埋めに戻る傾向を利用

#### Break of Structure (BOS)
- 直近の高値/安値をブレイクした構造の変化
- トレンド転換の確認に使用

### 4. Entry Signal Generation (Method 8)

エントリーには以下の要素が3つ以上必要：

1. **HTFトレンド方向**
2. **Baseトレンド方向**
3. **MTFアライメント**
4. **EMA方向確認**
5. **グランビル反発ポイント**
6. **RSIフィルター**
7. **Order Block近接**
8. **FVG近接**
9. **BOS確認**
10. **トレンド継続確認**
11. **ATRボラティリティ適正**

### 5. Position Management (Method 9)

#### Stop Loss
- 買いポジション: 押し安値の下に設定
- 売りポジション: 戻り高値の上に設定
- ATR × 倍率でバックアップSL

#### Take Profit
- ATR × 倍率で設定
- Order Blockのサポート/レジスタンスを考慮

#### Exit Conditions
- ダウ理論によるトレンド転換検知
- トレンド継続性の崩壊（利益がある場合）
- RSI買われすぎ/売られすぎ

## Risk Management System

### Fintokei Challenge Plan Compliance

```
失格条件:
├── 全体損失: 初期資金の10%以上の損失
├── 日次損失: その日の開始時有効証拠金の5%以上の損失
└── 条件を1円でも超えると即失格
```

### Emergency Actions

1. **リアルタイム監視**: 毎ティックで有効証拠金をチェック
2. **安全バッファ**: 制限ラインの手前で警告
3. **自動決済**: ラインに到達時に全ポジション強制決済
4. **取引停止**: 緊急決済後は新規取引を完全停止

### Trading Day Counter

- 最低3日間の取引日が必要
- 取引日 = 1つ以上の新規注文が成立した日
- チャート上に現在の取引日数を表示

## Session Optimization

### Best Trading Times for XAUUSD

| セッション | GMT時間 | 特徴 |
|-----------|---------|------|
| Asian | 0:00-8:00 | 低ボラティリティ、レンジ形成 |
| London | 8:00-17:00 | 高ボラティリティ開始 |
| NY | 13:00-22:00 | 最高ボラティリティ |
| **London-NY Overlap** | **13:00-17:00** | **最適な取引時間** |

## Backtesting

### Recommended Settings

- **Symbol**: XAUUSD
- **Period**: M15 or H1
- **Modeling**: Every tick based on real ticks
- **Initial Deposit**: 2,000,000 JPY
- **Leverage**: 1:100 or higher

### Optimization Parameters

1. InpATRMultiplierSL: 1.5 - 3.0
2. InpATRMultiplierTP: 2.0 - 5.0
3. InpRiskPerTradePct: 0.5 - 2.0
4. InpMaxTradesPerDay: 1 - 5

## Chart Display

EAは以下の情報をチャート上に表示：

- **Risk Management**: 日次/全体ドローダウン、リスク状態
- **Dow Theory**: HTF/Baseトレンド状態
- **Signal**: 現在のシグナルと強度
- **Position**: 保有ポジション情報
- **Session**: 現在のセッション状態
- **Statistics**: 取引統計

## Important Notes

1. **XAUUSD専用**: 他の通貨ペアでは最適化されていません
2. **ヘッジモード**: ブローカーでヘッジモードを有効にしてください
3. **スプレッド**: 低スプレッドのブローカーを推奨
4. **VPS**: 24時間稼働にはVPSを推奨

## Research Sources

This EA incorporates strategies from:
- [GOLD_ORB EA](https://github.com/yulz008/GOLD_ORB) - Open Range Breakout strategy
- [MQL5 SMC Articles](https://www.mql5.com/en/articles/16340) - Smart Money Concepts
- [Dow Theory Indicators](https://www.mql5.com/en/market/product/109778) - Dow trend analysis

## License

This EA is provided for educational purposes. Use at your own risk.

## Disclaimer

外国為替取引およびCFD取引には高いリスクが伴います。このEAの使用による損失について、開発者は一切の責任を負いません。実際の取引を行う前に、必ずデモ口座でテストしてください。

---

*Last Updated: December 2024*
