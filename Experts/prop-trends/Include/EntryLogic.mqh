//+------------------------------------------------------------------+
//|                                                   EntryLogic.mqh |
//|        Entry Logic v2.2 - Fintokei完全対応版                       |
//|        トレンドフォロー＋押し目/戻り目エントリー                     |
//|        ADXトレンド強度フィルター追加                                |
//+------------------------------------------------------------------+
#ifndef ENTRY_LOGIC_MQH
#define ENTRY_LOGIC_MQH

#include "TrendAnalysis.mqh"
#include "RiskManager.mqh"

//--- Entry pattern enum
enum ENUM_ENTRY_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_SMA_PULLBACK,       // SMAへの押し目/戻り目
   PATTERN_TREND_CONTINUATION, // トレンド継続
   PATTERN_SMA_CROSS           // SMAクロス
};

//--- Entry signal structure
struct EntrySignal
{
   bool              valid;
   ENUM_ENTRY_PATTERN pattern;
   ENUM_TREND_DIRECTION direction;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;    // Final TP (TP2 or RR-based)
   double            takeProfit1;   // Partial TP1 (近い目標)
   double            takeProfit2;   // Final TP2 (遠い目標)
   string            reason;
};

//+------------------------------------------------------------------+
//| Entry Logic Manager v2.2                                          |
//| Fintokei完全対応版 - ADXフィルター付きトレンドフォロー              |
//+------------------------------------------------------------------+
class CEntryLogic
{
private:
   string            m_Symbol;
   CTrendAnalyzer*   m_TrendAnalyzer;
   CRiskManager*     m_RiskManager;

   double            m_Point;
   double            m_MinSLPoints;
   double            m_DefaultSLPoints;

   // Trade direction control
   bool              m_EnableLongTrades;
   bool              m_EnableShortTrades;

public:
   CEntryLogic()
   {
      m_Symbol = "";
      m_TrendAnalyzer = NULL;
      m_RiskManager = NULL;
      m_Point = 0;
      m_MinSLPoints = 100.0;
      m_DefaultSLPoints = 300.0;
      m_EnableLongTrades = true;
      m_EnableShortTrades = false;  // Default: OFF for Fintokei
   }

   bool Initialize(string symbol, CTrendAnalyzer* trendAnalyzer, CRiskManager* riskManager)
   {
      m_Symbol = symbol;
      m_TrendAnalyzer = trendAnalyzer;
      m_RiskManager = riskManager;
      m_Point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      Print("[EntryLogic] Initialized v2.2 - Fintokei完全対応版");
      return true;
   }

   //--- Set trade direction enable/disable
   void SetTradeDirections(bool enableLong, bool enableShort)
   {
      m_EnableLongTrades = enableLong;
      m_EnableShortTrades = enableShort;
      PrintFormat("[EntryLogic] Trade directions: Long=%s, Short=%s",
                  enableLong ? "ON" : "OFF",
                  enableShort ? "ON" : "OFF");
   }

   void UpdateState()
   {
      // State is now managed inside TrendAnalyzer
   }

   //--- Main entry signal checker
   EntrySignal CheckEntrySignals()
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_NONE;
      signal.direction = TREND_NEUTRAL;
      signal.entryPrice = 0;
      signal.stopLoss = 0;
      signal.takeProfit = 0;
      signal.takeProfit1 = 0;
      signal.takeProfit2 = 0;
      signal.reason = "";

      // Risk check
      if(!m_RiskManager.IsTradeAllowed())
      {
         signal.reason = "Risk limits reached";
         return signal;
      }

      // War state check
      if(m_TrendAnalyzer.IsWarState())
      {
         signal.reason = "War state - D1 and H4 conflicting";
         return signal;
      }

      // ADX trend strength check - レンジ相場を回避
      if(!m_TrendAnalyzer.IsTrendStrong())
      {
         signal.reason = StringFormat("Weak trend (ADX=%.1f) - Skipping", m_TrendAnalyzer.GetADX_H4());
         return signal;
      }

      double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      // パターン1: SMAへの押し目/戻り目
      signal = CheckPullbackPattern(bid, ask);
      if(signal.valid) return signal;

      // パターン2: トレンド継続パターン
      signal = CheckTrendContinuation(bid, ask);
      if(signal.valid) return signal;

      return signal;
   }

   //+------------------------------------------------------------------+
   //| パターン1: SMAへの押し目/戻り目                                    |
   //| - マルチタイムフレームでトレンドが揃っている                        |
   //| - 価格がSMA20またはSMA80にタッチして反発                           |
   //+------------------------------------------------------------------+
   EntrySignal CheckPullbackPattern(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_SMA_PULLBACK;
      signal.takeProfit1 = 0;
      signal.takeProfit2 = 0;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      CDowSwingDetector* swing = m_TrendAnalyzer.GetSwingDetector();

      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION h1Trend = m_TrendAnalyzer.GetTrendH1();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      double h1Sma20 = sma.GetH1_SMA20();
      double h1Sma80 = sma.GetH1_SMA80();

      // Get recent candle data
      double close[], low[], high[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(high, true);
      CopyClose(m_Symbol, PERIOD_H1, 0, 5, close);
      CopyLow(m_Symbol, PERIOD_H1, 0, 5, low);
      CopyHigh(m_Symbol, PERIOD_H1, 0, 5, high);

      //=== BUY: 押し目買い ===
      // 条件: H4上昇 + H1上昇 + 価格がSMA20/80にタッチ後反発
      if(m_EnableLongTrades && h4Trend == TREND_UP && d1Trend != TREND_DOWN)
      {
         // SMAが上昇配列 (SMA20 > SMA80)
         bool smaAligned = (h1Sma20 > h1Sma80);

         // 押し目チェック: 最近の安値がSMA20またはSMA80にタッチ
         bool pullbackToSma20 = false;
         bool pullbackToSma80 = false;

         for(int i = 1; i <= 3; i++)
         {
            // SMA20への押し目 (安値がSMA20±20pipsに到達)
            if(low[i] <= h1Sma20 + 20 * m_Point && low[i] >= h1Sma20 - 50 * m_Point)
               pullbackToSma20 = true;
            // SMA80への押し目 (安値がSMA80±20pipsに到達)
            if(low[i] <= h1Sma80 + 20 * m_Point && low[i] >= h1Sma80 - 50 * m_Point)
               pullbackToSma80 = true;
         }

         // 反発確認: 現在の終値がSMA20より上
         bool bounced = (close[0] > h1Sma20);

         if(smaAligned && (pullbackToSma20 || pullbackToSma80) && bounced)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_UP, signal.entryPrice, signal.stopLoss);
            signal.valid = true;

            string pullbackType = pullbackToSma20 ? "SMA20" : "SMA80";
            signal.reason = StringFormat("BUY: 押し目 (%s) H4=%s H1=%s",
                                         pullbackType,
                                         TrendStr(h4Trend), TrendStr(h1Trend));

            PrintFormat("[Entry] ★SIGNAL★ %s | Entry=%.2f, SL=%.2f, TP=%.2f",
                        signal.reason, signal.entryPrice, signal.stopLoss, signal.takeProfit);

            return signal;
         }

         // ログ出力
         PrintFormat("[Entry] BUY Pullback: Aligned=%s, PB20=%s, PB80=%s, Bounce=%s",
                     smaAligned ? "Y" : "N",
                     pullbackToSma20 ? "Y" : "N",
                     pullbackToSma80 ? "Y" : "N",
                     bounced ? "Y" : "N");
      }

      //=== SELL: 戻り売り ===
      if(m_EnableShortTrades && h4Trend == TREND_DOWN && d1Trend != TREND_UP)
      {
         // SMAが下降配列 (SMA20 < SMA80)
         bool smaAligned = (h1Sma20 < h1Sma80);

         // 戻りチェック: 最近の高値がSMA20またはSMA80にタッチ
         bool pullbackToSma20 = false;
         bool pullbackToSma80 = false;

         for(int i = 1; i <= 3; i++)
         {
            if(high[i] >= h1Sma20 - 20 * m_Point && high[i] <= h1Sma20 + 50 * m_Point)
               pullbackToSma20 = true;
            if(high[i] >= h1Sma80 - 20 * m_Point && high[i] <= h1Sma80 + 50 * m_Point)
               pullbackToSma80 = true;
         }

         // 反発確認: 現在の終値がSMA20より下
         bool bounced = (close[0] < h1Sma20);

         if(smaAligned && (pullbackToSma20 || pullbackToSma80) && bounced)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, signal.entryPrice, signal.stopLoss);
            signal.valid = true;

            string pullbackType = pullbackToSma20 ? "SMA20" : "SMA80";
            signal.reason = StringFormat("SELL: 戻り (%s) H4=%s H1=%s",
                                         pullbackType,
                                         TrendStr(h4Trend), TrendStr(h1Trend));

            PrintFormat("[Entry] ★SIGNAL★ %s | Entry=%.2f, SL=%.2f, TP=%.2f",
                        signal.reason, signal.entryPrice, signal.stopLoss, signal.takeProfit);

            return signal;
         }
      }

      return signal;
   }

   //+------------------------------------------------------------------+
   //| パターン2: トレンド継続パターン                                    |
   //| - D1, H4, H1が同方向                                              |
   //| - SMAスロープが強い                                               |
   //| - 価格がSMAの上(買い)/下(売り)にある                               |
   //+------------------------------------------------------------------+
   EntrySignal CheckTrendContinuation(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_TREND_CONTINUATION;
      signal.takeProfit1 = 0;
      signal.takeProfit2 = 0;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();

      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION h1Trend = m_TrendAnalyzer.GetTrendH1();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      double h1Sma20 = sma.GetH1_SMA20();
      double h1Sma80 = sma.GetH1_SMA80();
      double h4Sma20 = sma.GetH4_SMA20();
      double h4Sma80 = sma.GetH4_SMA80();

      // SMAスロープ計算 (傾き)
      double h1Slope20 = (sma.GetH1_SMA20(0) - sma.GetH1_SMA20(3)) / 3;
      double h4Slope20 = (sma.GetH4_SMA20(0) - sma.GetH4_SMA20(3)) / 3;

      double price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);

      //=== BUY: 強いトレンド継続 ===
      if(m_EnableLongTrades && d1Trend == TREND_UP && h4Trend == TREND_UP && h1Trend == TREND_UP)
      {
         // 全SMAの上に価格がある
         bool aboveAllSma = (price > h1Sma20) && (price > h1Sma80) && (price > h4Sma20);

         // SMAが上昇配列
         bool smaAligned = (h1Sma20 > h1Sma80) && (h4Sma20 > h4Sma80);

         // SMAスロープが正 (上昇中)
         bool slopePositive = (h1Slope20 > 0) && (h4Slope20 > 0);

         if(aboveAllSma && smaAligned && slopePositive)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_UP, signal.entryPrice, signal.stopLoss);
            signal.valid = true;
            signal.reason = "BUY: トレンド継続 D1+H4+H1 UP";

            PrintFormat("[Entry] ★SIGNAL★ %s | Entry=%.2f, SL=%.2f, TP=%.2f",
                        signal.reason, signal.entryPrice, signal.stopLoss, signal.takeProfit);

            return signal;
         }

         PrintFormat("[Entry] BUY Trend: AboveAll=%s, Aligned=%s, Slope=%s",
                     aboveAllSma ? "Y" : "N",
                     smaAligned ? "Y" : "N",
                     slopePositive ? "Y" : "N");
      }

      //=== SELL: 強いトレンド継続 ===
      if(m_EnableShortTrades && d1Trend == TREND_DOWN && h4Trend == TREND_DOWN && h1Trend == TREND_DOWN)
      {
         // 全SMAの下に価格がある
         bool belowAllSma = (price < h1Sma20) && (price < h1Sma80) && (price < h4Sma20);

         // SMAが下降配列
         bool smaAligned = (h1Sma20 < h1Sma80) && (h4Sma20 < h4Sma80);

         // SMAスロープが負 (下降中)
         bool slopeNegative = (h1Slope20 < 0) && (h4Slope20 < 0);

         if(belowAllSma && smaAligned && slopeNegative)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, signal.entryPrice, signal.stopLoss);
            signal.valid = true;
            signal.reason = "SELL: トレンド継続 D1+H4+H1 DOWN";

            PrintFormat("[Entry] ★SIGNAL★ %s | Entry=%.2f, SL=%.2f, TP=%.2f",
                        signal.reason, signal.entryPrice, signal.stopLoss, signal.takeProfit);

            return signal;
         }
      }

      return signal;
   }

   //--- Calculate stop loss
   double GetStopLoss(ENUM_TREND_DIRECTION direction, ENUM_TIMEFRAMES tf)
   {
      CDowSwingDetector* swing = m_TrendAnalyzer.GetSwingDetector();
      double price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double sl = 0;

      if(direction == TREND_UP)
      {
         // SL below recent swing low
         double swingLow = swing.GetSwingLowForSL(tf);
         if(swingLow > 0)
         {
            sl = swingLow - 30 * m_Point;  // 30 points buffer
         }
         else
         {
            sl = price - m_DefaultSLPoints * m_Point;
         }

         // Ensure minimum SL
         if((price - sl) < m_MinSLPoints * m_Point)
         {
            sl = price - m_MinSLPoints * m_Point;
         }
      }
      else
      {
         // SL above recent swing high
         double swingHigh = swing.GetSwingHighForSL(tf);
         if(swingHigh > 0)
         {
            sl = swingHigh + 30 * m_Point;
         }
         else
         {
            sl = price + m_DefaultSLPoints * m_Point;
         }

         // Ensure minimum SL
         if((sl - price) < m_MinSLPoints * m_Point)
         {
            sl = price + m_MinSLPoints * m_Point;
         }
      }

      return sl;
   }

   //--- Calculate take profit (2:1 RR target)
   double GetTakeProfit(ENUM_TREND_DIRECTION direction, double entryPrice, double stopLoss)
   {
      double slDistance = MathAbs(entryPrice - stopLoss);
      double tpDistance = slDistance * 2.0;  // 2:1 RR

      if(direction == TREND_UP)
         return entryPrice + tpDistance;
      else
         return entryPrice - tpDistance;
   }

   //--- Helper: Trend to string
   string TrendStr(ENUM_TREND_DIRECTION trend)
   {
      if(trend == TREND_UP) return "UP";
      if(trend == TREND_DOWN) return "DOWN";
      return "NEUTRAL";
   }

   //--- Get pattern name
   string GetPatternName(ENUM_ENTRY_PATTERN pattern)
   {
      switch(pattern)
      {
         case PATTERN_SMA_PULLBACK:
            return "SMA Pullback";
         case PATTERN_TREND_CONTINUATION:
            return "Trend Continuation";
         case PATTERN_SMA_CROSS:
            return "SMA Cross";
         default:
            return "None";
      }
   }

   //+------------------------------------------------------------------+
   //| 分割決済用: 指定時間足の直近高値/安値を取得                        |
   //+------------------------------------------------------------------+
   double GetSwingHighByTimeframe(ENUM_TIMEFRAMES tf, int lookback = 50)
   {
      CDowSwingDetector* swing = m_TrendAnalyzer.GetSwingDetector();
      return swing.FindRecentSwingHigh(tf, lookback);
   }

   double GetSwingLowByTimeframe(ENUM_TIMEFRAMES tf, int lookback = 50)
   {
      CDowSwingDetector* swing = m_TrendAnalyzer.GetSwingDetector();
      return swing.FindRecentSwingLow(tf, lookback);
   }

   //--- Calculate TP by timeframe swing high/low
   double CalculateTPByTimeframe(ENUM_TREND_DIRECTION direction, ENUM_TIMEFRAMES tf, double entryPrice)
   {
      double tp = 0;
      double buffer = 20 * m_Point;  // 20 points buffer

      if(direction == TREND_UP)
      {
         // BUY: TPは直近高値
         tp = GetSwingHighByTimeframe(tf, 50);
         if(tp > entryPrice)
            tp = tp - buffer;  // 少し手前で決済
         else
            tp = 0;  // 無効
      }
      else
      {
         // SELL: TPは直近安値
         tp = GetSwingLowByTimeframe(tf, 50);
         if(tp < entryPrice)
            tp = tp + buffer;  // 少し手前で決済
         else
            tp = 0;  // 無効
      }

      return tp;
   }
};

#endif // ENTRY_LOGIC_MQH
