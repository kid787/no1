//+------------------------------------------------------------------+
//|                                                   EntryLogic.mqh |
//|        Simplified Entry Logic v2.0 - More Practical              |
//+------------------------------------------------------------------+
#ifndef ENTRY_LOGIC_MQH
#define ENTRY_LOGIC_MQH

#include "TrendAnalysis.mqh"
#include "RiskManager.mqh"

//--- Entry pattern enum
enum ENUM_ENTRY_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_H4_PULLBACK,        // 4時間足レベルの押し目・戻り目
   PATTERN_H1_PULLBACK,        // 1時間足レベルの押し目・戻り目
   PATTERN_SMA_CROSS,          // SMAクロス（ゴールデン/デッドクロス）
   PATTERN_TREND_FOLLOW        // シンプルなトレンドフォロー
};

//--- Entry signal structure
struct EntrySignal
{
   bool              valid;
   ENUM_ENTRY_PATTERN pattern;
   ENUM_TREND_DIRECTION direction;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   string            reason;
};

//+------------------------------------------------------------------+
//| Entry Logic Manager v2.0                                          |
//| よりシンプルで実用的なエントリーロジック                            |
//+------------------------------------------------------------------+
class CEntryLogic
{
private:
   string            m_Symbol;
   CTrendAnalyzer*   m_TrendAnalyzer;
   CRiskManager*     m_RiskManager;

   double            m_Point;
   double            m_MinSLPoints;      // Minimum SL distance
   double            m_DefaultSLPoints;  // Default SL if swing not found
   double            m_MinTPPoints;      // Minimum TP distance

   // State tracking
   ENUM_TREND_DIRECTION m_PrevH4Trend;
   ENUM_TREND_DIRECTION m_PrevH1Trend;

public:
   CEntryLogic()
   {
      m_Symbol = "";
      m_TrendAnalyzer = NULL;
      m_RiskManager = NULL;
      m_Point = 0;
      m_MinSLPoints = 150.0;    // Min 150 points SL
      m_DefaultSLPoints = 300.0; // Default 300 points SL
      m_MinTPPoints = 300.0;    // Min 300 points TP

      m_PrevH4Trend = TREND_NEUTRAL;
      m_PrevH1Trend = TREND_NEUTRAL;
   }

   bool Initialize(string symbol, CTrendAnalyzer* trendAnalyzer, CRiskManager* riskManager)
   {
      m_Symbol = symbol;
      m_TrendAnalyzer = trendAnalyzer;
      m_RiskManager = riskManager;
      m_Point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      Print("[EntryLogic] Initialized v2.0");
      return true;
   }

   void UpdateState()
   {
      m_PrevH4Trend = m_TrendAnalyzer.GetTrendH4();
      m_PrevH1Trend = m_TrendAnalyzer.GetTrendH1();
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
      signal.reason = "";

      // Risk check
      if(!m_RiskManager.IsTradeAllowed())
      {
         signal.reason = "Risk limits reached";
         return signal;
      }

      // War state check (only D1 vs H4 direct conflict)
      if(m_TrendAnalyzer.IsWarState())
      {
         signal.reason = "War state - D1 and H4 conflicting";
         return signal;
      }

      double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      // Check patterns in order
      signal = CheckSMACrossEntry(bid, ask);
      if(signal.valid) return signal;

      signal = CheckPullbackEntry(bid, ask);
      if(signal.valid) return signal;

      signal = CheckTrendFollowEntry(bid, ask);
      if(signal.valid) return signal;

      return signal;
   }

   //--- Pattern: SMA Cross (Golden/Dead Cross)
   EntrySignal CheckSMACrossEntry(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_SMA_CROSS;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();

      // Check H4 golden cross for buy
      if(sma.IsGoldenCross(PERIOD_H4))
      {
         ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();
         if(d1Trend != TREND_DOWN)  // D1 not opposing
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, bid, PERIOD_H4);
            signal.takeProfit = GetTakeProfit(TREND_UP, ask, signal.stopLoss);
            signal.valid = true;
            signal.reason = "H4 Golden Cross - Buy";
            return signal;
         }
      }

      // Check H4 dead cross for sell
      if(sma.IsDeadCross(PERIOD_H4))
      {
         ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();
         if(d1Trend != TREND_UP)  // D1 not opposing
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, ask, PERIOD_H4);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, bid, signal.stopLoss);
            signal.valid = true;
            signal.reason = "H4 Dead Cross - Sell";
            return signal;
         }
      }

      // Check H1 crosses too
      if(sma.IsGoldenCross(PERIOD_H1))
      {
         ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
         if(h4Trend == TREND_UP || h4Trend == TREND_NEUTRAL)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, bid, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_UP, ask, signal.stopLoss);
            signal.valid = true;
            signal.reason = "H1 Golden Cross (H4 aligned) - Buy";
            return signal;
         }
      }

      if(sma.IsDeadCross(PERIOD_H1))
      {
         ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
         if(h4Trend == TREND_DOWN || h4Trend == TREND_NEUTRAL)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, ask, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, bid, signal.stopLoss);
            signal.valid = true;
            signal.reason = "H1 Dead Cross (H4 aligned) - Sell";
            return signal;
         }
      }

      return signal;
   }

   //--- Pattern: Pullback to SMA in trend direction
   EntrySignal CheckPullbackEntry(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_H4_PULLBACK;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION h1Trend = m_TrendAnalyzer.GetTrendH1();

      // H4 uptrend + price pulled back near SMA + H1 turning up
      if(h4Trend == TREND_UP && sma.IsPullbackToSMA(PERIOD_H4, 400))
      {
         // Wait for H1 to turn bullish after pullback
         if(m_PrevH1Trend != TREND_UP && h1Trend == TREND_UP)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, bid, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_UP, ask, signal.stopLoss);
            signal.valid = true;
            signal.reason = "H4 Pullback Buy - H1 turned bullish";
            return signal;
         }
      }

      // H4 downtrend + price pulled back near SMA + H1 turning down
      if(h4Trend == TREND_DOWN && sma.IsPullbackToSMA(PERIOD_H4, 400))
      {
         if(m_PrevH1Trend != TREND_DOWN && h1Trend == TREND_DOWN)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, ask, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, bid, signal.stopLoss);
            signal.valid = true;
            signal.reason = "H4 Pullback Sell - H1 turned bearish";
            return signal;
         }
      }

      return signal;
   }

   //--- Pattern: Simple Trend Follow (H4 and H1 aligned)
   EntrySignal CheckTrendFollowEntry(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_TREND_FOLLOW;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();
      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION h1Trend = m_TrendAnalyzer.GetTrendH1();

      // All timeframes aligned for buy
      if(h4Trend == TREND_UP && h1Trend == TREND_UP &&
         (d1Trend == TREND_UP || d1Trend == TREND_NEUTRAL))
      {
         // Check if SMAs are diverging (trend strengthening)
         if(sma.IsDiverging(PERIOD_H4) || sma.IsDiverging(PERIOD_H1))
         {
            // Check previous trend wasn't already up (avoid multiple entries)
            if(m_PrevH4Trend != TREND_UP || m_PrevH1Trend != TREND_UP)
            {
               signal.direction = TREND_UP;
               signal.entryPrice = ask;
               signal.stopLoss = GetStopLoss(TREND_UP, bid, PERIOD_H1);
               signal.takeProfit = GetTakeProfit(TREND_UP, ask, signal.stopLoss);
               signal.valid = true;
               signal.reason = "Trend Follow Buy - All TFs aligned & diverging";
               return signal;
            }
         }
      }

      // All timeframes aligned for sell
      if(h4Trend == TREND_DOWN && h1Trend == TREND_DOWN &&
         (d1Trend == TREND_DOWN || d1Trend == TREND_NEUTRAL))
      {
         if(sma.IsDiverging(PERIOD_H4) || sma.IsDiverging(PERIOD_H1))
         {
            if(m_PrevH4Trend != TREND_DOWN || m_PrevH1Trend != TREND_DOWN)
            {
               signal.direction = TREND_DOWN;
               signal.entryPrice = bid;
               signal.stopLoss = GetStopLoss(TREND_DOWN, ask, PERIOD_H1);
               signal.takeProfit = GetTakeProfit(TREND_DOWN, bid, signal.stopLoss);
               signal.valid = true;
               signal.reason = "Trend Follow Sell - All TFs aligned & diverging";
               return signal;
            }
         }
      }

      return signal;
   }

   //--- Calculate stop loss
   double GetStopLoss(ENUM_TREND_DIRECTION direction, double currentPrice, ENUM_TIMEFRAMES tf)
   {
      CSwingFinder* swingFinder = m_TrendAnalyzer.GetSwingFinder();
      double sl = 0;

      if(direction == TREND_UP)
      {
         // SL below recent swing low
         double swingLow = swingFinder.FindRecentLow(tf, 20);
         if(swingLow > 0)
         {
            sl = swingLow - 50 * m_Point;
         }
         else
         {
            sl = currentPrice - m_DefaultSLPoints * m_Point;
         }

         // Ensure minimum SL distance
         if((currentPrice - sl) < m_MinSLPoints * m_Point)
         {
            sl = currentPrice - m_MinSLPoints * m_Point;
         }
      }
      else
      {
         // SL above recent swing high
         double swingHigh = swingFinder.FindRecentHigh(tf, 20);
         if(swingHigh > 0)
         {
            sl = swingHigh + 50 * m_Point;
         }
         else
         {
            sl = currentPrice + m_DefaultSLPoints * m_Point;
         }

         // Ensure minimum SL distance
         if((sl - currentPrice) < m_MinSLPoints * m_Point)
         {
            sl = currentPrice + m_MinSLPoints * m_Point;
         }
      }

      return sl;
   }

   //--- Calculate take profit (at least 1.5 RR)
   double GetTakeProfit(ENUM_TREND_DIRECTION direction, double entryPrice, double stopLoss)
   {
      double slDistance = MathAbs(entryPrice - stopLoss);
      double tpDistance = slDistance * 2.0;  // 2:1 RR target

      if(tpDistance < m_MinTPPoints * m_Point)
         tpDistance = m_MinTPPoints * m_Point;

      if(direction == TREND_UP)
         return entryPrice + tpDistance;
      else
         return entryPrice - tpDistance;
   }

   //--- Get pattern name
   string GetPatternName(ENUM_ENTRY_PATTERN pattern)
   {
      switch(pattern)
      {
         case PATTERN_H4_PULLBACK: return "H4 Pullback";
         case PATTERN_H1_PULLBACK: return "H1 Pullback";
         case PATTERN_SMA_CROSS: return "SMA Cross";
         case PATTERN_TREND_FOLLOW: return "Trend Follow";
         default: return "None";
      }
   }
};

#endif // ENTRY_LOGIC_MQH
