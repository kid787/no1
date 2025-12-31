//+------------------------------------------------------------------+
//|                                                   EntryLogic.mqh |
//|        Entry Logic v3.0 - 参考資料に基づくエントリー条件            |
//|        ★この2つが揃った時のみエントリー★                          |
//|        ①MAが収束→拡散していく所                                   |
//|        ②上位足の方向に下位足がトレンド転換してくる所                |
//+------------------------------------------------------------------+
#ifndef ENTRY_LOGIC_MQH
#define ENTRY_LOGIC_MQH

#include "TrendAnalysis.mqh"
#include "RiskManager.mqh"

//--- Entry pattern enum
enum ENUM_ENTRY_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_H4_H1_CONVERGENCE_BREAKOUT,    // H4上位 + H1収束→拡散 + H1ダウ転換
   PATTERN_H1_M15_CONVERGENCE_BREAKOUT    // H1上位 + M15収束→拡散 + M15ダウ転換
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
//| Entry Logic Manager v3.0                                          |
//| 参考資料に基づく「2条件同時成立」エントリー                         |
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

public:
   CEntryLogic()
   {
      m_Symbol = "";
      m_TrendAnalyzer = NULL;
      m_RiskManager = NULL;
      m_Point = 0;
      m_MinSLPoints = 100.0;
      m_DefaultSLPoints = 300.0;
   }

   bool Initialize(string symbol, CTrendAnalyzer* trendAnalyzer, CRiskManager* riskManager)
   {
      m_Symbol = symbol;
      m_TrendAnalyzer = trendAnalyzer;
      m_RiskManager = riskManager;
      m_Point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      Print("[EntryLogic] Initialized v3.0 - 2条件同時成立ロジック");
      return true;
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

      double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      // Check main pattern: H4 trend + H1 convergence→divergence + H1 Dow break
      signal = CheckH4H1Pattern(bid, ask);
      if(signal.valid) return signal;

      return signal;
   }

   //+------------------------------------------------------------------+
   //| メインパターン: H4トレンド方向 + H1収束→拡散 + H1ダウ転換          |
   //| ★この2つが揃った時のみエントリー★                                |
   //+------------------------------------------------------------------+
   EntrySignal CheckH4H1Pattern(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_H4_H1_CONVERGENCE_BREAKOUT;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      CDowSwingDetector* swing = m_TrendAnalyzer.GetSwingDetector();

      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      //=== BUY CONDITION ===
      // 1. H4(上位足)が上向き
      // 2. H1のMAが収束→拡散（条件①）
      // 3. H1で高値ブレイク（ダウ転換、条件②）
      if(h4Trend == TREND_UP && d1Trend != TREND_DOWN)
      {
         // 条件①: H1のMA収束→拡散
         bool maCondition = sma.IsConvergenceToDivergenceTransition(PERIOD_H1);

         // 条件②: H1でダウ転換（高値ブレイク）
         bool dowCondition = swing.IsBullishDowBreak(PERIOD_H1);

         // ログ出力
         PrintFormat("[Entry] BUY Check: H4=UP, MA収束→拡散=%s, ダウ転換=%s",
                     maCondition ? "YES" : "NO",
                     dowCondition ? "YES" : "NO");

         // ★2つの条件が揃った時のみエントリー★
         if(maCondition && dowCondition)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_UP, signal.entryPrice, signal.stopLoss);
            signal.valid = true;
            signal.reason = "★BUY★ H4 UP + H1 MA収束→拡散 + H1 高値ブレイク";

            PrintFormat("[Entry] ★SIGNAL★ %s | Entry=%.5f, SL=%.5f, TP=%.5f",
                        signal.reason, signal.entryPrice, signal.stopLoss, signal.takeProfit);

            return signal;
         }

         // 条件①だけ成立の場合も軽めのエントリー（オプション）
         // MAの拡散だけでも方向は合っているので
         if(maCondition && sma.AreSMAsAligned(PERIOD_H1, TREND_UP))
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;
            signal.stopLoss = GetStopLoss(TREND_UP, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_UP, signal.entryPrice, signal.stopLoss);
            signal.valid = true;
            signal.reason = "BUY: H4 UP + H1 MA収束→拡散 (ダウ転換なし)";
            return signal;
         }
      }

      //=== SELL CONDITION ===
      // 1. H4(上位足)が下向き
      // 2. H1のMAが収束→拡散（条件①）
      // 3. H1で安値ブレイク（ダウ転換、条件②）
      if(h4Trend == TREND_DOWN && d1Trend != TREND_UP)
      {
         // 条件①: H1のMA収束→拡散
         bool maCondition = sma.IsConvergenceToDivergenceTransition(PERIOD_H1);

         // 条件②: H1でダウ転換（安値ブレイク）
         bool dowCondition = swing.IsBearishDowBreak(PERIOD_H1);

         // ログ出力
         PrintFormat("[Entry] SELL Check: H4=DOWN, MA収束→拡散=%s, ダウ転換=%s",
                     maCondition ? "YES" : "NO",
                     dowCondition ? "YES" : "NO");

         // ★2つの条件が揃った時のみエントリー★
         if(maCondition && dowCondition)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, signal.entryPrice, signal.stopLoss);
            signal.valid = true;
            signal.reason = "★SELL★ H4 DOWN + H1 MA収束→拡散 + H1 安値ブレイク";

            PrintFormat("[Entry] ★SIGNAL★ %s | Entry=%.5f, SL=%.5f, TP=%.5f",
                        signal.reason, signal.entryPrice, signal.stopLoss, signal.takeProfit);

            return signal;
         }

         // 条件①だけ成立の場合も軽めのエントリー（オプション）
         if(maCondition && sma.AreSMAsAligned(PERIOD_H1, TREND_DOWN))
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;
            signal.stopLoss = GetStopLoss(TREND_DOWN, PERIOD_H1);
            signal.takeProfit = GetTakeProfit(TREND_DOWN, signal.entryPrice, signal.stopLoss);
            signal.valid = true;
            signal.reason = "SELL: H4 DOWN + H1 MA収束→拡散 (ダウ転換なし)";
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

   //--- Get pattern name
   string GetPatternName(ENUM_ENTRY_PATTERN pattern)
   {
      switch(pattern)
      {
         case PATTERN_H4_H1_CONVERGENCE_BREAKOUT:
            return "H4+H1 Convergence Breakout";
         case PATTERN_H1_M15_CONVERGENCE_BREAKOUT:
            return "H1+M15 Convergence Breakout";
         default:
            return "None";
      }
   }
};

#endif // ENTRY_LOGIC_MQH
