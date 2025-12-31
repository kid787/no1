//+------------------------------------------------------------------+
//|                                                   EntryLogic.mqh |
//|                4 Iron Entry Patterns + Resistance Check          |
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
   PATTERN_D1_PULLBACK,        // 日足レベルの押し目・戻り目
   PATTERN_H4_TREND_REVERSAL   // 4時間足レベルのトレンド転換
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
//| Resistance/Support Level Detector                                |
//+------------------------------------------------------------------+
class CResistanceDetector
{
private:
   string            m_Symbol;
   double            m_LevelBuffer;    // Buffer zone around levels (points)

public:
   //--- Constructor
   CResistanceDetector()
   {
      m_Symbol = "";
      m_LevelBuffer = 100.0;  // 100 points buffer
   }

   //--- Initialize
   bool Initialize(string symbol, double buffer = 100.0)
   {
      m_Symbol = symbol;
      m_LevelBuffer = buffer;
      return true;
   }

   //--- Get daily high
   double GetDailyHigh(int shift = 0)
   {
      double highs[];
      ArraySetAsSeries(highs, true);
      if(CopyHigh(m_Symbol, PERIOD_D1, shift, 1, highs) == 1)
         return highs[0];
      return 0;
   }

   //--- Get daily low
   double GetDailyLow(int shift = 0)
   {
      double lows[];
      ArraySetAsSeries(lows, true);
      if(CopyLow(m_Symbol, PERIOD_D1, shift, 1, lows) == 1)
         return lows[0];
      return 0;
   }

   //--- Check if resistance exists above current price (for buy)
   bool HasResistanceAbove(double currentPrice, double targetPrice, CSMAManager* smaManager)
   {
      // Check D1 high levels
      for(int i = 1; i <= 5; i++)
      {
         double dailyHigh = GetDailyHigh(i);
         if(dailyHigh > currentPrice && dailyHigh < targetPrice)
         {
            PrintFormat("[Resistance] D1 High at %.5f blocks target %.5f", dailyHigh, targetPrice);
            return true;
         }
      }

      // Check higher TF SMAs as resistance
      double h4_sma80 = smaManager.GetH4_SMA80();
      double h4_sma120 = smaManager.GetH4_SMA120();
      double h1_sma480 = smaManager.GetH1_SMA480();

      if(h4_sma80 > currentPrice && h4_sma80 < targetPrice &&
         (h4_sma80 - currentPrice) < m_LevelBuffer * 2)
      {
         PrintFormat("[Resistance] H4 SMA80 at %.5f is too close", h4_sma80);
         return true;
      }

      if(h4_sma120 > currentPrice && h4_sma120 < targetPrice &&
         (h4_sma120 - currentPrice) < m_LevelBuffer * 2)
      {
         PrintFormat("[Resistance] H4 SMA120 at %.5f is too close", h4_sma120);
         return true;
      }

      if(h1_sma480 > currentPrice && h1_sma480 < targetPrice &&
         (h1_sma480 - currentPrice) < m_LevelBuffer * 2)
      {
         PrintFormat("[Resistance] H1 SMA480 (D1相当) at %.5f is too close", h1_sma480);
         return true;
      }

      return false;
   }

   //--- Check if support exists below current price (for sell)
   bool HasSupportBelow(double currentPrice, double targetPrice, CSMAManager* smaManager)
   {
      // Check D1 low levels
      for(int i = 1; i <= 5; i++)
      {
         double dailyLow = GetDailyLow(i);
         if(dailyLow < currentPrice && dailyLow > targetPrice)
         {
            PrintFormat("[Support] D1 Low at %.5f blocks target %.5f", dailyLow, targetPrice);
            return true;
         }
      }

      // Check higher TF SMAs as support
      double h4_sma80 = smaManager.GetH4_SMA80();
      double h4_sma120 = smaManager.GetH4_SMA120();
      double h1_sma480 = smaManager.GetH1_SMA480();

      if(h4_sma80 < currentPrice && h4_sma80 > targetPrice &&
         (currentPrice - h4_sma80) < m_LevelBuffer * 2)
      {
         PrintFormat("[Support] H4 SMA80 at %.5f is too close", h4_sma80);
         return true;
      }

      if(h4_sma120 < currentPrice && h4_sma120 > targetPrice &&
         (currentPrice - h4_sma120) < m_LevelBuffer * 2)
      {
         PrintFormat("[Support] H4 SMA120 at %.5f is too close", h4_sma120);
         return true;
      }

      if(h1_sma480 < currentPrice && h1_sma480 > targetPrice &&
         (currentPrice - h1_sma480) < m_LevelBuffer * 2)
      {
         PrintFormat("[Support] H1 SMA480 (D1相当) at %.5f is too close", h1_sma480);
         return true;
      }

      return false;
   }

   //--- Find next resistance level (for TP)
   double FindNextResistance(double currentPrice, CSMAManager* smaManager)
   {
      double levels[];
      int count = 0;

      // Collect potential resistance levels
      ArrayResize(levels, 20);

      // D1 highs
      for(int i = 1; i <= 10; i++)
      {
         double high = GetDailyHigh(i);
         if(high > currentPrice)
         {
            levels[count++] = high;
         }
      }

      // Higher TF SMAs above price
      double smas[] = {
         smaManager.GetH4_SMA80(),
         smaManager.GetH4_SMA120(),
         smaManager.GetH4_SMA600(),
         smaManager.GetH1_SMA480()
      };

      for(int i = 0; i < ArraySize(smas); i++)
      {
         if(smas[i] > currentPrice && count < 20)
         {
            levels[count++] = smas[i];
         }
      }

      if(count == 0)
         return 0;

      // Find minimum (nearest)
      ArrayResize(levels, count);
      ArraySort(levels);

      return levels[0];
   }

   //--- Find next support level (for TP)
   double FindNextSupport(double currentPrice, CSMAManager* smaManager)
   {
      double levels[];
      int count = 0;

      ArrayResize(levels, 20);

      // D1 lows
      for(int i = 1; i <= 10; i++)
      {
         double low = GetDailyLow(i);
         if(low < currentPrice && low > 0)
         {
            levels[count++] = low;
         }
      }

      // Higher TF SMAs below price
      double smas[] = {
         smaManager.GetH4_SMA80(),
         smaManager.GetH4_SMA120(),
         smaManager.GetH4_SMA600(),
         smaManager.GetH1_SMA480()
      };

      for(int i = 0; i < ArraySize(smas); i++)
      {
         if(smas[i] < currentPrice && smas[i] > 0 && count < 20)
         {
            levels[count++] = smas[i];
         }
      }

      if(count == 0)
         return 0;

      // Find maximum (nearest to current price from below)
      ArrayResize(levels, count);
      ArraySort(levels);

      return levels[count - 1];
   }
};

//+------------------------------------------------------------------+
//| Entry Logic Manager                                               |
//| 4つの鉄板エントリーロジック:                                        |
//| 1. 4時間足レベルの押し目・戻り目                                   |
//| 2. 1時間足レベルの押し目・戻り目                                   |
//| 3. 日足レベルの押し目・戻り目                                      |
//| 4. 4時間足レベルのトレンド転換                                     |
//+------------------------------------------------------------------+
class CEntryLogic
{
private:
   string            m_Symbol;
   CTrendAnalyzer*   m_TrendAnalyzer;
   CRiskManager*     m_RiskManager;
   CResistanceDetector m_ResistanceDetector;

   double            m_MinSLPoints;      // Minimum SL distance in points
   double            m_Point;

   // Previous trend states for reversal detection
   ENUM_TREND_DIRECTION m_PrevH4Trend;
   ENUM_TREND_DIRECTION m_PrevH1Trend;

   // Convergence tracking
   bool              m_WasH4Converging;
   bool              m_WasH1Converging;

public:
   //--- Constructor
   CEntryLogic()
   {
      m_Symbol = "";
      m_TrendAnalyzer = NULL;
      m_RiskManager = NULL;
      m_MinSLPoints = 200.0;  // Minimum 200 points SL
      m_Point = 0;

      m_PrevH4Trend = TREND_NEUTRAL;
      m_PrevH1Trend = TREND_NEUTRAL;
      m_WasH4Converging = false;
      m_WasH1Converging = false;
   }

   //--- Initialize
   bool Initialize(string symbol, CTrendAnalyzer* trendAnalyzer, CRiskManager* riskManager)
   {
      m_Symbol = symbol;
      m_TrendAnalyzer = trendAnalyzer;
      m_RiskManager = riskManager;
      m_Point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      if(!m_ResistanceDetector.Initialize(symbol))
         return false;

      Print("[EntryLogic] Initialized");
      return true;
   }

   //--- Update convergence tracking
   void UpdateState()
   {
      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();

      // Save previous states
      m_PrevH4Trend = m_TrendAnalyzer.GetTrendH4();
      m_PrevH1Trend = m_TrendAnalyzer.GetTrendH1();

      m_WasH4Converging = sma.IsConverging(PERIOD_H4);
      m_WasH1Converging = sma.IsConverging(PERIOD_H1);
   }

   //--- Check all entry patterns and return signal
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

      // Pre-check: Is trading allowed by risk manager?
      if(!m_RiskManager.IsTradeAllowed())
      {
         signal.reason = "Risk limits reached";
         return signal;
      }

      // Pre-check: Is war state? (conflicting trends)
      if(m_TrendAnalyzer.IsWarState())
      {
         signal.reason = "War state - conflicting trends";
         return signal;
      }

      // Get current price
      double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      // Check patterns in priority order
      signal = CheckH4Pullback(bid, ask);
      if(signal.valid) return signal;

      signal = CheckH1Pullback(bid, ask);
      if(signal.valid) return signal;

      signal = CheckD1Pullback(bid, ask);
      if(signal.valid) return signal;

      signal = CheckH4TrendReversal(bid, ask);
      if(signal.valid) return signal;

      return signal;
   }

   //--- Pattern 1: 4時間足レベルの押し目・戻り目
   //--- 4時間足MA（上位足）に対し、1時間足MA（下位足）が収束から拡散するポイント
   EntrySignal CheckH4Pullback(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_H4_PULLBACK;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      CDowTheoryAnalyzer* dow = m_TrendAnalyzer.GetDowAnalyzer();

      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      // Check for convergence to divergence transition
      bool wasConverging = m_WasH4Converging;
      bool isDiverging = sma.IsDiverging(PERIOD_H4);

      if(!wasConverging || !isDiverging)
         return signal;

      // H1 SMA20 crossing H4 SMA80 in trend direction
      double h1_sma20 = sma.GetH1_SMA20();
      double h4_sma80 = sma.GetH4_SMA80();
      double h1_sma20_prev = sma.GetH1_SMA20(1);

      // For buy signal
      if(h4Trend == TREND_UP && (d1Trend == TREND_UP || d1Trend == TREND_NEUTRAL))
      {
         // H1 SMA20 crossed above H4 SMA80 (or price near H4 SMA and turning up)
         if(h1_sma20 > h4_sma80 && h1_sma20_prev <= h4_sma80)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;

            // SL: Below recent H1 swing low
            int h1_20Handle = iMA(m_Symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
            dow.FindSwingLowsUsingSMA(PERIOD_H1, h1_20Handle, 3);
            IndicatorRelease(h1_20Handle);

            double swingLow = dow.GetLatestSwingLow();
            if(swingLow > 0)
               signal.stopLoss = swingLow - m_MinSLPoints * m_Point;
            else
               signal.stopLoss = bid - 500 * m_Point;

            // Ensure minimum SL distance
            if((signal.entryPrice - signal.stopLoss) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice - m_MinSLPoints * m_Point;

            // TP: Next resistance level
            double resistance = m_ResistanceDetector.FindNextResistance(ask, sma);
            if(resistance > 0)
               signal.takeProfit = resistance - 50 * m_Point;
            else
               signal.takeProfit = ask + 1000 * m_Point;

            // Check for blocking resistance
            if(!m_ResistanceDetector.HasResistanceAbove(ask, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "H4 Pullback Buy: H1 diverging above H4 SMA";
            }
         }
      }
      // For sell signal
      else if(h4Trend == TREND_DOWN && (d1Trend == TREND_DOWN || d1Trend == TREND_NEUTRAL))
      {
         // H1 SMA20 crossed below H4 SMA80
         if(h1_sma20 < h4_sma80 && h1_sma20_prev >= h4_sma80)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;

            // SL: Above recent H1 swing high
            int h1_20Handle = iMA(m_Symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
            dow.FindSwingHighsUsingSMA(PERIOD_H1, h1_20Handle, 3);
            IndicatorRelease(h1_20Handle);

            double swingHigh = dow.GetLatestSwingHigh();
            if(swingHigh > 0)
               signal.stopLoss = swingHigh + m_MinSLPoints * m_Point;
            else
               signal.stopLoss = ask + 500 * m_Point;

            // Ensure minimum SL distance
            if((signal.stopLoss - signal.entryPrice) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice + m_MinSLPoints * m_Point;

            // TP: Next support level
            double support = m_ResistanceDetector.FindNextSupport(bid, sma);
            if(support > 0)
               signal.takeProfit = support + 50 * m_Point;
            else
               signal.takeProfit = bid - 1000 * m_Point;

            // Check for blocking support
            if(!m_ResistanceDetector.HasSupportBelow(bid, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "H4 Pullback Sell: H1 diverging below H4 SMA";
            }
         }
      }

      return signal;
   }

   //--- Pattern 2: 1時間足レベルの押し目・戻り目
   //--- 1時間足MAに対し、15分足がトレンド転換するポイント
   EntrySignal CheckH1Pullback(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_H1_PULLBACK;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      CDowTheoryAnalyzer* dow = m_TrendAnalyzer.GetDowAnalyzer();

      ENUM_TREND_DIRECTION h1Trend = m_TrendAnalyzer.GetTrendH1();
      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      // Need H1 diverging after convergence
      bool wasConverging = m_WasH1Converging;
      bool isDiverging = sma.IsDiverging(PERIOD_H1);

      if(!wasConverging || !isDiverging)
         return signal;

      // M15 SMA20 relative to H1 SMA20
      double m15_sma20 = sma.GetM15_SMA20();
      double h1_sma20 = sma.GetH1_SMA20();
      double m15_sma20_prev = sma.GetM15_SMA20(1);

      // For buy signal
      if(h1Trend == TREND_UP && h4Trend == TREND_UP &&
         (d1Trend == TREND_UP || d1Trend == TREND_NEUTRAL))
      {
         // M15 crossing above H1 SMA
         if(m15_sma20 > h1_sma20 && m15_sma20_prev <= h1_sma20)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;

            // SL: Below recent swing low (tighter for H1 level)
            int m15_handle = iMA(m_Symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);
            dow.FindSwingLowsUsingSMA(PERIOD_M15, m15_handle, 3);
            IndicatorRelease(m15_handle);

            double swingLow = dow.GetLatestSwingLow();
            if(swingLow > 0)
               signal.stopLoss = swingLow - 50 * m_Point;
            else
               signal.stopLoss = bid - 300 * m_Point;

            // Ensure minimum SL
            if((signal.entryPrice - signal.stopLoss) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice - m_MinSLPoints * m_Point;

            // TP: Next H4 level resistance
            double resistance = m_ResistanceDetector.FindNextResistance(ask, sma);
            if(resistance > 0)
               signal.takeProfit = resistance - 30 * m_Point;
            else
               signal.takeProfit = ask + 600 * m_Point;

            if(!m_ResistanceDetector.HasResistanceAbove(ask, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "H1 Pullback Buy: M15 trend reversal in H1 uptrend";
            }
         }
      }
      // For sell signal
      else if(h1Trend == TREND_DOWN && h4Trend == TREND_DOWN &&
              (d1Trend == TREND_DOWN || d1Trend == TREND_NEUTRAL))
      {
         // M15 crossing below H1 SMA
         if(m15_sma20 < h1_sma20 && m15_sma20_prev >= h1_sma20)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;

            // SL: Above recent swing high
            int m15_handle = iMA(m_Symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);
            dow.FindSwingHighsUsingSMA(PERIOD_M15, m15_handle, 3);
            IndicatorRelease(m15_handle);

            double swingHigh = dow.GetLatestSwingHigh();
            if(swingHigh > 0)
               signal.stopLoss = swingHigh + 50 * m_Point;
            else
               signal.stopLoss = ask + 300 * m_Point;

            // Ensure minimum SL
            if((signal.stopLoss - signal.entryPrice) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice + m_MinSLPoints * m_Point;

            // TP: Next support
            double support = m_ResistanceDetector.FindNextSupport(bid, sma);
            if(support > 0)
               signal.takeProfit = support + 30 * m_Point;
            else
               signal.takeProfit = bid - 600 * m_Point;

            if(!m_ResistanceDetector.HasSupportBelow(bid, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "H1 Pullback Sell: M15 trend reversal in H1 downtrend";
            }
         }
      }

      return signal;
   }

   //--- Pattern 3: 日足レベルの押し目・戻り目
   //--- 日足MA付近で、4時間足または1時間足が反転する初動
   EntrySignal CheckD1Pullback(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_D1_PULLBACK;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      CDowTheoryAnalyzer* dow = m_TrendAnalyzer.GetDowAnalyzer();

      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      // Get daily SMA area
      double d1_sma20 = sma.GetD1_SMA20();
      double h1_sma480 = sma.GetH1_SMA480();  // Proxy for daily level

      // Price should be near daily MA
      double priceDistance = MathAbs(bid - h1_sma480);
      double threshold = 300 * m_Point;  // Within 300 points of daily MA

      if(priceDistance > threshold)
         return signal;

      // Check H4 or H1 reversal in direction of D1 trend
      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION h1Trend = m_TrendAnalyzer.GetTrendH1();

      // For buy signal - D1 uptrend, price near D1 SMA, H4/H1 turning up
      if(d1Trend == TREND_UP && bid > h1_sma480 - threshold)
      {
         // Was H4 down/neutral, now turning up
         if((m_PrevH4Trend == TREND_DOWN || m_PrevH4Trend == TREND_NEUTRAL) &&
            h4Trend == TREND_UP)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;

            // SL: Below the daily MA zone
            signal.stopLoss = h1_sma480 - 100 * m_Point;

            // Ensure minimum SL
            if((signal.entryPrice - signal.stopLoss) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice - m_MinSLPoints * m_Point;

            // TP: Next major resistance (D1 high area)
            double d1High = m_ResistanceDetector.GetDailyHigh(1);
            if(d1High > ask)
               signal.takeProfit = d1High - 50 * m_Point;
            else
               signal.takeProfit = ask + 1500 * m_Point;

            if(!m_ResistanceDetector.HasResistanceAbove(ask, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "D1 Pullback Buy: H4 reversal at D1 SMA support";
            }
         }
      }
      // For sell signal - D1 downtrend, price near D1 SMA, H4/H1 turning down
      else if(d1Trend == TREND_DOWN && bid < h1_sma480 + threshold)
      {
         if((m_PrevH4Trend == TREND_UP || m_PrevH4Trend == TREND_NEUTRAL) &&
            h4Trend == TREND_DOWN)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;

            // SL: Above the daily MA zone
            signal.stopLoss = h1_sma480 + 100 * m_Point;

            // Ensure minimum SL
            if((signal.stopLoss - signal.entryPrice) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice + m_MinSLPoints * m_Point;

            // TP: Next major support (D1 low area)
            double d1Low = m_ResistanceDetector.GetDailyLow(1);
            if(d1Low < bid && d1Low > 0)
               signal.takeProfit = d1Low + 50 * m_Point;
            else
               signal.takeProfit = bid - 1500 * m_Point;

            if(!m_ResistanceDetector.HasSupportBelow(bid, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "D1 Pullback Sell: H4 reversal at D1 SMA resistance";
            }
         }
      }

      return signal;
   }

   //--- Pattern 4: 4時間足レベルのトレンド転換
   //--- それまでのトレンドが終了し、第1波が発生する局面
   EntrySignal CheckH4TrendReversal(double bid, double ask)
   {
      EntrySignal signal;
      signal.valid = false;
      signal.pattern = PATTERN_H4_TREND_REVERSAL;
      signal.reason = "";

      CSMAManager* sma = m_TrendAnalyzer.GetSMAManager();
      CDowTheoryAnalyzer* dow = m_TrendAnalyzer.GetDowAnalyzer();

      ENUM_TREND_DIRECTION h4Trend = m_TrendAnalyzer.GetTrendH4();
      ENUM_TREND_DIRECTION d1Trend = m_TrendAnalyzer.GetTrendD1();

      // Need a clear trend reversal on H4
      bool wasDownNowUp = (m_PrevH4Trend == TREND_DOWN) && (h4Trend == TREND_UP);
      bool wasUpNowDown = (m_PrevH4Trend == TREND_UP) && (h4Trend == TREND_DOWN);

      if(!wasDownNowUp && !wasUpNowDown)
         return signal;

      // Additional confirmation: Check if D1 is neutral or aligning
      // For bullish reversal
      if(wasDownNowUp && (d1Trend == TREND_UP || d1Trend == TREND_NEUTRAL))
      {
         // Check for breakout above previous swing high
         int h4_handle = iMA(m_Symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
         dow.FindSwingHighsUsingSMA(PERIOD_H4, h4_handle, 5);
         double prevHigh = dow.GetPreviousSwingHigh();
         IndicatorRelease(h4_handle);

         if(prevHigh > 0 && bid > prevHigh)
         {
            signal.direction = TREND_UP;
            signal.entryPrice = ask;

            // SL: Below recent H4 swing low
            dow.FindSwingLowsUsingSMA(PERIOD_H4, h4_handle, 3);
            double swingLow = dow.GetLatestSwingLow();
            if(swingLow > 0)
               signal.stopLoss = swingLow - 100 * m_Point;
            else
               signal.stopLoss = bid - 600 * m_Point;

            // Ensure minimum SL
            if((signal.entryPrice - signal.stopLoss) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice - m_MinSLPoints * m_Point;

            // TP: Extended target for wave 1
            double resistance = m_ResistanceDetector.FindNextResistance(ask, sma);
            if(resistance > 0)
               signal.takeProfit = resistance - 50 * m_Point;
            else
               signal.takeProfit = ask + 2000 * m_Point;

            if(!m_ResistanceDetector.HasResistanceAbove(ask, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "H4 Trend Reversal Buy: First wave bullish breakout";
            }
         }
      }
      // For bearish reversal
      else if(wasUpNowDown && (d1Trend == TREND_DOWN || d1Trend == TREND_NEUTRAL))
      {
         // Check for breakout below previous swing low
         int h4_handle = iMA(m_Symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
         dow.FindSwingLowsUsingSMA(PERIOD_H4, h4_handle, 5);
         double prevLow = dow.GetPreviousSwingLow();
         IndicatorRelease(h4_handle);

         if(prevLow > 0 && bid < prevLow)
         {
            signal.direction = TREND_DOWN;
            signal.entryPrice = bid;

            // SL: Above recent H4 swing high
            dow.FindSwingHighsUsingSMA(PERIOD_H4, h4_handle, 3);
            double swingHigh = dow.GetLatestSwingHigh();
            if(swingHigh > 0)
               signal.stopLoss = swingHigh + 100 * m_Point;
            else
               signal.stopLoss = ask + 600 * m_Point;

            // Ensure minimum SL
            if((signal.stopLoss - signal.entryPrice) < m_MinSLPoints * m_Point)
               signal.stopLoss = signal.entryPrice + m_MinSLPoints * m_Point;

            // TP: Extended target for wave 1
            double support = m_ResistanceDetector.FindNextSupport(bid, sma);
            if(support > 0)
               signal.takeProfit = support + 50 * m_Point;
            else
               signal.takeProfit = bid - 2000 * m_Point;

            if(!m_ResistanceDetector.HasSupportBelow(bid, signal.takeProfit, sma))
            {
               signal.valid = true;
               signal.reason = "H4 Trend Reversal Sell: First wave bearish breakout";
            }
         }
      }

      return signal;
   }

   //--- Get pattern name
   string GetPatternName(ENUM_ENTRY_PATTERN pattern)
   {
      switch(pattern)
      {
         case PATTERN_H4_PULLBACK: return "H4 Pullback";
         case PATTERN_H1_PULLBACK: return "H1 Pullback";
         case PATTERN_D1_PULLBACK: return "D1 Pullback";
         case PATTERN_H4_TREND_REVERSAL: return "H4 Trend Reversal";
         default: return "None";
      }
   }
};

#endif // ENTRY_LOGIC_MQH
