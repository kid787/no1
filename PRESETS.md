# HighWinRate Entry Filter - 設定プリセット集

## 概要

このドキュメントでは、様々なトレードスタイルや通貨ペアに最適化された設定プリセットを提供します。

**注意**: XAUUSD（金/ゴールド）については、専用版インジケーター `HighWinRate_Entry_Filter_XAUUSD.mq4` を使用してください。
詳細は [XAUUSD専用ガイド](XAUUSD_GUIDE.md) をご覧ください。

## 通貨ペア別プリセット

### EUR/USD - 標準設定

**特徴**: 最も取引量が多く、スプレッドが狭い。ロンドン・ニューヨーク時間で最適。

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 50
SR_Threshold = 0.0002
Cluster_Min_Bars = 10
Cluster_Range_Pips = 30
Alert_Cooldown_Seconds = 300
```

**推奨時間帯**: 08:00-16:00 GMT（ロンドン）、13:00-21:00 GMT（ニューヨーク）

---

### GBP/USD - 高ボラティリティ設定

**特徴**: ポンドは動きが大きいため、クラスター幅を広げる。

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 60
SR_Threshold = 0.0003
Cluster_Min_Bars = 12
Cluster_Range_Pips = 50
Alert_Cooldown_Seconds = 300
```

**推奨時間帯**: 08:00-16:00 GMT（ロンドン時間がベスト）

---

### USD/JPY - アジア・ロンドン対応

**特徴**: 東京時間とロンドン時間の両方で動く。

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 50
SR_Threshold = 0.0002
Cluster_Min_Bars = 10
Cluster_Range_Pips = 25
Alert_Cooldown_Seconds = 300
```

**推奨時間帯**: 00:00-09:00 GMT（東京）、08:00-16:00 GMT（ロンドン）

**東京時間用の追加設定**:
```
London_Start_Hour = 0
London_End_Hour = 9
```

---

### GBP/JPY - 超高ボラティリティ設定

**特徴**: 最もボラティリティが高い通貨ペア。大きな値動きに対応。

```
King_TimeFrame = PERIOD_H4
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 70
SR_Threshold = 0.0005
Cluster_Min_Bars = 15
Cluster_Range_Pips = 80
Alert_Cooldown_Seconds = 300
```

**注意**: リスク管理が特に重要。損切りは広めに設定。

---

### EUR/JPY - バランス設定

**特徴**: EUR/USDとUSD/JPYの中間的な動き。

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 50
SR_Threshold = 0.0003
Cluster_Min_Bars = 10
Cluster_Range_Pips = 40
Alert_Cooldown_Seconds = 300
```

---

### AUD/USD - コモディティ通貨設定

**特徴**: オーストラリアドルは資源価格の影響を受ける。アジア・ロンドン時間で動く。

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 50
SR_Threshold = 0.0002
Cluster_Min_Bars = 10
Cluster_Range_Pips = 35
Alert_Cooldown_Seconds = 300
```

---

### USD/CAD - 原油連動設定

**特徴**: カナダドルは原油価格と逆相関。ニューヨーク時間で活発。

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H1
SMA_Period = 21
London_Start_Hour = 13
London_End_Hour = 21
SR_Lookback_Bars = 50
SR_Threshold = 0.0002
Cluster_Min_Bars = 10
Cluster_Range_Pips = 30
Alert_Cooldown_Seconds = 300
```

**注意**: `London_Start_Hour` をニューヨーク時間に合わせて調整。

---

## トレードスタイル別プリセット

### デイトレード - 1日数回のトレード

**目的**: 1日2-5回のトレード機会を狙う。

```
King_TimeFrame = PERIOD_H4
Base_TimeFrame = PERIOD_M15
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 40
SR_Threshold = 0.0002
Cluster_Min_Bars = 8
Cluster_Range_Pips = 20
Alert_Cooldown_Seconds = 180
```

**推奨通貨ペア**: EUR/USD, GBP/USD, USD/JPY

**エントリー頻度**: 高（1日2-5回）

---

### スイングトレード - 数日保有

**目的**: ポジションを数日～数週間保有。

```
King_TimeFrame = PERIOD_W1
Base_TimeFrame = PERIOD_D1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 100
SR_Threshold = 0.0005
Cluster_Min_Bars = 20
Cluster_Range_Pips = 100
Alert_Cooldown_Seconds = 3600
```

**推奨通貨ペア**: EUR/USD, GBP/USD, AUD/USD

**エントリー頻度**: 低（週1-2回）

---

### スキャルピング - 短期売買（上級者向け）

**目的**: 数分～数十分の短期トレード。

```
King_TimeFrame = PERIOD_H1
Base_TimeFrame = PERIOD_M5
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 30
SR_Threshold = 0.0001
Cluster_Min_Bars = 5
Cluster_Range_Pips = 10
Alert_Cooldown_Seconds = 60
```

**推奨通貨ペア**: EUR/USD（スプレッドが狭い）

**エントリー頻度**: 非常に高（1日10回以上）

**注意**:
- スプレッドが狭い通貨ペアを選ぶ
- 取引コストが利益を圧迫する可能性
- 高度な集中力が必要

---

### ポジショントレード - 長期保有

**目的**: ポジションを数週間～数ヶ月保有。

```
King_TimeFrame = PERIOD_MN1
Base_TimeFrame = PERIOD_W1
SMA_Period = 21
London_Start_Hour = 8
London_End_Hour = 16
SR_Lookback_Bars = 150
SR_Threshold = 0.001
Cluster_Min_Bars = 30
Cluster_Range_Pips = 200
Alert_Cooldown_Seconds = 86400
```

**推奨通貨ペア**: 主要通貨ペア全般

**エントリー頻度**: 非常に低（月1-2回）

---

## 時間帯別プリセット

### ロンドンセッション（08:00-16:00 GMT）

```
London_Start_Hour = 8
London_End_Hour = 16
```

**最適通貨ペア**: EUR/USD, GBP/USD, EUR/GBP, EUR/JPY

---

### ニューヨークセッション（13:00-21:00 GMT）

```
London_Start_Hour = 13
London_End_Hour = 21
```

**最適通貨ペア**: EUR/USD, GBP/USD, USD/JPY, USD/CAD

---

### 東京セッション（00:00-09:00 GMT）

```
London_Start_Hour = 0
London_End_Hour = 9
```

**最適通貨ペア**: USD/JPY, EUR/JPY, AUD/JPY, AUD/USD

---

### ロンドン・ニューヨーク重複（13:00-16:00 GMT）

**最も活発な時間帯**

```
London_Start_Hour = 13
London_End_Hour = 16
```

**最適通貨ペア**: EUR/USD, GBP/USD（最高のボラティリティ）

---

## 感度調整プリセット

### 高感度設定（シグナル多め）

**用途**: トレード機会を多く見つけたい場合

```
SR_Lookback_Bars = 30
SR_Threshold = 0.0001
Cluster_Min_Bars = 5
Cluster_Range_Pips = 20
Alert_Cooldown_Seconds = 120
```

**メリット**: エントリー機会が増える
**デメリット**: ノイズ（騙しシグナル）も増える

---

### 低感度設定（シグナル厳選）

**用途**: 確実性の高いシグナルのみを求める場合

```
SR_Lookback_Bars = 100
SR_Threshold = 0.0005
Cluster_Min_Bars = 20
Cluster_Range_Pips = 50
Alert_Cooldown_Seconds = 600
```

**メリット**: 高品質なシグナルのみ
**デメリット**: エントリー機会が少ない

---

### バランス設定（推奨）

**用途**: 品質と機会のバランス

```
SR_Lookback_Bars = 50
SR_Threshold = 0.0002
Cluster_Min_Bars = 10
Cluster_Range_Pips = 30
Alert_Cooldown_Seconds = 300
```

**メリット**: 適度なエントリー機会と品質
**推奨**: 初心者から中級者向け

---

## リスク管理別プリセット

### 保守的設定（リスク低）

**対象**: リスクを抑えたいトレーダー

```
King_TimeFrame = PERIOD_D1
Base_TimeFrame = PERIOD_H4
SMA_Period = 21
SR_Lookback_Bars = 100
SR_Threshold = 0.0005
Cluster_Min_Bars = 20
Cluster_Range_Pips = 50
Alert_Cooldown_Seconds = 600
Enable_Sound_Alert = true
Enable_Popup_Alert = true
```

**特徴**:
- 大きな時間足でのトレード
- 厳選されたシグナル
- 損切り幅が広い

---

### 積極的設定（リスク中～高）

**対象**: リスクを取って機会を増やしたいトレーダー

```
King_TimeFrame = PERIOD_H4
Base_TimeFrame = PERIOD_M15
SMA_Period = 21
SR_Lookback_Bars = 30
SR_Threshold = 0.0001
Cluster_Min_Bars = 5
Cluster_Range_Pips = 15
Alert_Cooldown_Seconds = 120
Enable_Sound_Alert = true
Enable_Popup_Alert = true
```

**特徴**:
- 小さな時間足でのトレード
- 多くのエントリー機会
- 損切り幅が狭い

---

## カスタマイズのヒント

### 自分に合った設定を見つける方法

1. **まず標準設定から始める**
   - デフォルト設定で1-2週間トレード
   - 結果を記録

2. **問題点を特定**
   - シグナルが多すぎる → 感度を下げる
   - シグナルが少なすぎる → 感度を上げる
   - 時間帯が合わない → セッション時間を調整

3. **段階的に調整**
   - 一度に1つのパラメーターのみ変更
   - 変更後、再度1-2週間テスト
   - 結果を比較

4. **最適化**
   - 自分のトレードスタイルに合った設定を確立
   - 定期的に見直し（市場環境は変化する）

### パラメーター調整の優先順位

1. **最優先**: King_TimeFrame, Base_TimeFrame（トレードスタイルの基本）
2. **次に重要**: London_Start_Hour, London_End_Hour（活動時間に合わせる）
3. **微調整**: Cluster_Range_Pips, SR_Threshold（通貨ペアの特性に合わせる）
4. **快適性**: Alert_Cooldown_Seconds, 色設定（個人の好みに合わせる）

---

## プリセットの適用方法

1. MetaTrader 4でインジケーターをチャートに適用
2. インジケーターの設定画面を開く
3. 上記のプリセットから適切な設定をコピー
4. 各パラメーターに値を入力
5. 「OK」をクリック

**保存方法**:
- 設定画面の「入力」タブで設定後
- 「セット」メニューから「保存」
- 任意の名前で保存（例: "EURUSD_Day_Trade"）
- 次回から「セット」メニューから読み込み可能

---

このプリセット集を参考に、自分に最適な設定を見つけてください。
