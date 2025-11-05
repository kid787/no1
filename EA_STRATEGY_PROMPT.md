# MT5 EA トレード戦略仕様書 - ゴールド（XAUUSD）ロング専用

## 戦略概要
2本のローソク足パターンを使用したゴールド専用の押し目買い戦略（ロングのみ）

**エントリー時間足**: 15分足と1時間足の両方でシグナル確認
**決済条件**: 1時間足のレジスタンスゾーンで利確

---

## エントリー条件（ロング）

### 時間足設定
- **監視時間足**: M15（15分足）とH1（1時間足）
- **エントリー判定**: 両方の時間足で2本のローソク足パターンを確認

### 必須条件
1. **ローソク足パターン**
   - 1本目：陰線（終値 < 始値）
   - 2本目：陽線（終値 > 始値）

2. **安値（Low）の確認**
   - 2本目のLowが1本目のLowより明確に下（長いひげ）
   - 判定基準：`candle2.Low < candle1.Low - MinWickDifference_pips`
   - 推奨設定：MinWickDifference_pips = 5〜10pips

3. **実体サイズの確認**
   - 両方のローソク足の実体が一定以上のサイズ
   - 判定基準：`MathAbs(Close - Open) >= MinBodySize_pips`
   - 推奨設定：MinBodySize_pips = 3〜5pips

### エントリー見送り条件（フィルター）
- どちらかのローソク足の実体が小さすぎる
- 2本目の安値が1本目とほぼ同じ、または微妙な差しかない

---

## 勝率向上フィルター（オプション）

### 高勝率パターン
1. **上ひげ比較**
   - 2本目の高値（High）が1本目の高値より低い
   - 条件：`candle2.High < candle1.High`

2. **2本目の上ひげが短い**
   - 2本目の上ひげサイズが一定以下
   - 条件：`(candle2.High - candle2.Close) <= MaxUpperWick_pips`
   - 推奨設定：MaxUpperWick_pips = 3〜5pips

---

## ショートエントリー
- **実装しない**（ゴールドロング専用のため）

---

## 決済条件

### 利確（Take Profit）

#### 主要利確条件：1時間足レジスタンスゾーン
- **レジスタンスゾーンの定義**：
  - 1時間足の過去100本分の高値を分析
  - 同じ価格帯（±50ポイント以内）に複数の高値が集中している領域
  - 最低3回以上タッチされた価格帯をレジスタンスと判定

- **利確ロジック**：
  - 現在価格がレジスタンスゾーン（±20ポイント以内）に到達
  - かつ、利益が出ている状態（浮き利益 > 0）
  - レジスタンスに到達したら即座に決済

#### 補助的利確条件（条件付き）
- 現在のポジションが利益状態（浮き利益 > 0）
- かつ、陰線の実体が完成した時
- 判定：`(Close[1] < Open[1]) AND (PositionProfit > 0)`
- **注意**: レジスタンスゾーン利確が優先

**注意点：**
- 損失状態では陰線が出ても決済しない
- レジスタンスゾーン検出失敗時は条件付き利確を使用

### 損切り（Stop Loss）
- エントリーの2本目（陽線）の安値から35ドル（350ポイント）下に設定
- SL価格 = `candle2.Low - 350 * Point`

---

## EA パラメータ設定

### 基本設定
```
input double LotSize = 0.01;                    // ロットサイズ
input int MagicNumber = 123456;                 // マジックナンバー
input string TradeComment = "GoldLongEA";       // コメント
input string TargetSymbol = "XAUUSD";           // 対象通貨（ゴールド固定）
```

### エントリー条件パラメータ（ゴールド用）
```
input double MinWickDifference_points = 80.0;   // 安値の最小差（ポイント）※ゴールドは100ポイント=1ドル
input double MinBodySize_points = 30.0;         // 最小実体サイズ（ポイント）
input bool UseHighFilter = true;                // 勝率フィルター使用
input double MaxUpperWick_points = 50.0;        // 2本目の最大上ひげ（ポイント）
```

### 決済パラメータ（ゴールド用）
```
input double StopLoss_points = 350.0;           // 損切り（ポイント）※35ドル = 350ポイント
input bool UseResistanceZone = true;            // レジスタンスゾーン利確の使用
input int ResistanceZoneLookback = 100;         // レジスタンス検出用の過去足数（H1）
input double ResistanceZoneRange_Points = 50.0; // レジスタンスゾーン判定範囲（±50pt）
input int MinResistanceTouches = 3;             // レジスタンス判定の最小タッチ回数
input double ResistanceExitRange_Points = 20.0; // レジスタンス到達判定範囲（±20pt）
input bool UseConditionalTP = true;             // 条件付き利確の使用（補助）
```

### トレード設定
```
input int MaxPositions = 1;                     // 最大ポジション数（ロング専用）
input ENUM_TIMEFRAMES EntryTimeframe1 = PERIOD_M15; // エントリー時間足1（15分足）
input ENUM_TIMEFRAMES EntryTimeframe2 = PERIOD_H1;  // エントリー時間足2（1時間足）
input bool RequireBothTimeframes = true;        // 両方の時間足でシグナル必要
```

---

## 実装ロジックフロー

### OnTick()処理
1. 新しいバーの検出（各時間足で）
2. 既存ポジションの確認
   - ポジションがある場合：
     - レジスタンスゾーン到達チェック（最優先）
     - 条件付き利確のチェック（補助）
   - ポジションがない場合：
     - エントリー条件のチェック（複数時間足）
3. エントリーシグナル判定
4. オーダー送信

### エントリーチェック関数（複数時間足対応）
```
bool CheckLongEntry()
{
   bool signal_m15 = CheckLongEntryOnTimeframe(PERIOD_M15);
   bool signal_h1 = CheckLongEntryOnTimeframe(PERIOD_H1);

   if(RequireBothTimeframes)
      return (signal_m15 && signal_h1);
   else
      return (signal_m15 || signal_h1);
}

bool CheckLongEntryOnTimeframe(ENUM_TIMEFRAMES tf)
{
   // 指定時間足で1本目（index=2）、2本目（index=1）を確認
   // 1. 陰線→陽線パターン
   // 2. 安値の差をチェック
   // 3. 実体サイズチェック
   // 4. 勝率フィルター（オプション）
   return true/false;
}
```

### レジスタンスゾーン検出関数
```
double FindResistanceZone()
{
   // 1時間足の過去100本分の高値を取得
   // 高値を価格帯ごとにグループ化
   // 各価格帯のタッチ回数をカウント
   // 最小タッチ回数以上の価格帯をレジスタンスと判定
   // 最も近いレジスタンスゾーンの価格を返す
   return resistance_price;
}
```

### 決済チェック関数
```
void CheckTakeProfit()
{
   // レジスタンスゾーン利確チェック（優先）
   if(UseResistanceZone)
   {
      double resistance = FindResistanceZone();
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // レジスタンス到達判定
      if(MathAbs(currentPrice - resistance) <= ResistanceExitRange_Points * _Point)
      {
         if(PositionProfit > 0)
            ClosePosition(); // 決済
      }
   }

   // 条件付き利確チェック（補助）
   if(UseConditionalTP)
   {
      // 利益状態かチェック
      // 最新の完成バーが陰線かチェック
      // 条件を満たせば決済
   }
}
```

---

## 注意事項

1. **ローソク足の参照**
   - index=1：完成した最新バー
   - index=2：1つ前のバー
   - 未確定バー（index=0）は使用しない

2. **ゴールドのポイント計算**
   - ゴールド（XAUUSD）：100ポイント = 1ドル
   - 計算式：価格差 / _Point
   - 例：35ドルの損切り = 350ポイント = 3.5pips相当

3. **スリッページ対策**
   - OrderSend時にスリッページ設定
   - 推奨：3〜5pips

4. **バックテスト推奨設定**
   - 時間足：H1（1時間足）推奨、H4も可
   - 通貨ペア：XAUUSD（ゴールド）固定
   - 期間：最低1年間
   - スプレッド：30〜50ポイント程度を想定

---

## 推奨拡張機能（将来的に）

- トレーリングストップ機能
- 時間帯フィルター（東京・ロンドン・NY時間）
- 複数通貨ペア対応
- リスク管理（口座残高の％でロット計算）
- メール/プッシュ通知

---

## 実装優先度

**Phase 1（最優先）:**
- ロングエントリーロジック
- 固定損切り（35pips）
- 条件付き利確

**Phase 2:**
- 勝率フィルター実装
- パラメータ最適化

**Phase 3（オプション）:**
- ショートエントリー
- 拡張機能
