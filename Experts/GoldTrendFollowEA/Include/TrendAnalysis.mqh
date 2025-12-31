//+------------------------------------------------------------------+
//|                                                TrendAnalysis.mqh |
//|           Dow Theory & SMA Multi-Timeframe Trend Analysis        |
//|                          v2.0 - Improved Logic                   |
//+------------------------------------------------------------------+
#ifndef TREND_ANALYSIS_MQH
#define TREND_ANALYSIS_MQH

//--- Trend direction enum
enum ENUM_TREND_DIRECTION
{
   TREND_UP = 1,        // 上昇トレンド
   TREND_DOWN = -1,     // 下降トレンド
   TREND_NEUTRAL = 0    // 中立・レンジ
};

//--- Swing point structure
struct SwingPoint
{
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
};

//+------------------------------------------------------------------+
//| Multi-Timeframe SMA Manager                                       |
//+------------------------------------------------------------------+
class CSMAManager
{
private:
   string            m_Symbol;
   int               m_HandleH1_20, m_HandleH1_80, m_HandleH1_480;
   int               m_HandleH4_20, m_HandleH4_80, m_HandleH4_120, m_HandleH4_600;
   int               m_HandleM15_20;
   int               m_HandleD1_20;

public:
   //--- Constructor
   CSMAManager() { m_Symbol = ""; }

   //--- Initialize SMA handles for all timeframes
   bool Initialize(string symbol)
   {
      m_Symbol = symbol;

      // 1時間足 SMA
      m_HandleH1_20 = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
      m_HandleH1_80 = iMA(symbol, PERIOD_H1, 80, 0, MODE_SMA, PRICE_CLOSE);
      m_HandleH1_480 = iMA(symbol, PERIOD_H1, 480, 0, MODE_SMA, PRICE_CLOSE);

      // 4時間足 SMA
      m_HandleH4_20 = iMA(symbol, PERIOD_H4, 20, 0, MODE_SMA, PRICE_CLOSE);
      m_HandleH4_80 = iMA(symbol, PERIOD_H4, 80, 0, MODE_SMA, PRICE_CLOSE);
      m_HandleH4_120 = iMA(symbol, PERIOD_H4, 120, 0, MODE_SMA, PRICE_CLOSE);
      m_HandleH4_600 = iMA(symbol, PERIOD_H4, 600, 0, MODE_SMA, PRICE_CLOSE);

      // 15分足 SMA (エントリー用)
      m_HandleM15_20 = iMA(symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);

      // 日足 SMA
      m_HandleD1_20 = iMA(symbol, PERIOD_D1, 20, 0, MODE_SMA, PRICE_CLOSE);

      // Verify all handles
      if(m_HandleH1_20 == INVALID_HANDLE || m_HandleH1_80 == INVALID_HANDLE ||
         m_HandleH1_480 == INVALID_HANDLE || m_HandleH4_20 == INVALID_HANDLE ||
         m_HandleH4_80 == INVALID_HANDLE || m_HandleH4_120 == INVALID_HANDLE ||
         m_HandleH4_600 == INVALID_HANDLE || m_HandleM15_20 == INVALID_HANDLE ||
         m_HandleD1_20 == INVALID_HANDLE)
      {
         Print("[SMAManager] Failed to create indicator handles");
         return false;
      }

      Print("[SMAManager] Initialized successfully");
      return true;
   }

   //--- Release handles
   void Deinitialize()
   {
      if(m_HandleH1_20 != INVALID_HANDLE) IndicatorRelease(m_HandleH1_20);
      if(m_HandleH1_80 != INVALID_HANDLE) IndicatorRelease(m_HandleH1_80);
      if(m_HandleH1_480 != INVALID_HANDLE) IndicatorRelease(m_HandleH1_480);
      if(m_HandleH4_20 != INVALID_HANDLE) IndicatorRelease(m_HandleH4_20);
      if(m_HandleH4_80 != INVALID_HANDLE) IndicatorRelease(m_HandleH4_80);
      if(m_HandleH4_120 != INVALID_HANDLE) IndicatorRelease(m_HandleH4_120);
      if(m_HandleH4_600 != INVALID_HANDLE) IndicatorRelease(m_HandleH4_600);
      if(m_HandleM15_20 != INVALID_HANDLE) IndicatorRelease(m_HandleM15_20);
      if(m_HandleD1_20 != INVALID_HANDLE) IndicatorRelease(m_HandleD1_20);
   }

   //--- Get SMA value
   double GetSMA(int handle, int shift = 0)
   {
      double buffer[];
      ArraySetAsSeries(buffer, true);

      if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
         return 0;

      return buffer[0];
   }

   //--- H1 SMA getters
   double GetH1_SMA20(int shift = 0) { return GetSMA(m_HandleH1_20, shift); }
   double GetH1_SMA80(int shift = 0) { return GetSMA(m_HandleH1_80, shift); }
   double GetH1_SMA480(int shift = 0) { return GetSMA(m_HandleH1_480, shift); }

   //--- H4 SMA getters
   double GetH4_SMA20(int shift = 0) { return GetSMA(m_HandleH4_20, shift); }
   double GetH4_SMA80(int shift = 0) { return GetSMA(m_HandleH4_80, shift); }
   double GetH4_SMA120(int shift = 0) { return GetSMA(m_HandleH4_120, shift); }
   double GetH4_SMA600(int shift = 0) { return GetSMA(m_HandleH4_600, shift); }

   //--- M15 SMA getter
   double GetM15_SMA20(int shift = 0) { return GetSMA(m_HandleM15_20, shift); }

   //--- D1 SMA getter
   double GetD1_SMA20(int shift = 0) { return GetSMA(m_HandleD1_20, shift); }

   //--- Get SMA slope (direction) - percentage change over period
   double GetSMASlope(int handle, int period = 5)
   {
      double sma0 = GetSMA(handle, 0);
      double sma1 = GetSMA(handle, period);

      if(sma1 == 0) return 0;

      return (sma0 - sma1) / sma1 * 100.0;
   }

   //--- Simplified trend detection using SMA position and slope
   ENUM_TREND_DIRECTION GetSimpleTrend(ENUM_TIMEFRAMES tf)
   {
      double price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double sma20 = 0, sma80 = 0;
      double slope20 = 0;

      if(tf == PERIOD_H1)
      {
         sma20 = GetH1_SMA20();
         sma80 = GetH1_SMA80();
         slope20 = GetSMASlope(m_HandleH1_20, 3);
      }
      else if(tf == PERIOD_H4)
      {
         sma20 = GetH4_SMA20();
         sma80 = GetH4_SMA80();
         slope20 = GetSMASlope(m_HandleH4_20, 3);
      }
      else if(tf == PERIOD_D1)
      {
         sma20 = GetD1_SMA20();
         sma80 = GetH1_SMA480();  // Use H1 480 as proxy
         slope20 = GetSMASlope(m_HandleD1_20, 3);
      }

      // Simple trend logic:
      // UP: Price above both SMAs AND SMA20 above SMA80
      // DOWN: Price below both SMAs AND SMA20 below SMA80
      if(price > sma20 && price > sma80 && sma20 > sma80)
         return TREND_UP;
      if(price < sma20 && price < sma80 && sma20 < sma80)
         return TREND_DOWN;

      // Alternative: just use slope
      if(slope20 > 0.05)  // 0.05% positive slope
         return TREND_UP;
      if(slope20 < -0.05)
         return TREND_DOWN;

      return TREND_NEUTRAL;
   }

   //--- Check if SMAs are aligned (all pointing same direction)
   bool AreSMAsAligned(ENUM_TIMEFRAMES tf, ENUM_TREND_DIRECTION direction)
   {
      double sma20 = 0, sma80 = 0;
      double slope20 = 0;

      if(tf == PERIOD_H1)
      {
         sma20 = GetH1_SMA20();
         sma80 = GetH1_SMA80();
         slope20 = GetSMASlope(m_HandleH1_20, 3);
      }
      else if(tf == PERIOD_H4)
      {
         sma20 = GetH4_SMA20();
         sma80 = GetH4_SMA80();
         slope20 = GetSMASlope(m_HandleH4_20, 3);
      }

      if(direction == TREND_UP)
      {
         return (sma20 > sma80) && (slope20 > 0);
      }
      else if(direction == TREND_DOWN)
      {
         return (sma20 < sma80) && (slope20 < 0);
      }

      return false;
   }

   //--- Check convergence state (SMAs getting closer)
   bool IsConverging(ENUM_TIMEFRAMES tf)
   {
      double sma20_0, sma80_0, sma20_5, sma80_5;

      if(tf == PERIOD_H1)
      {
         sma20_0 = GetH1_SMA20(0);
         sma80_0 = GetH1_SMA80(0);
         sma20_5 = GetH1_SMA20(5);
         sma80_5 = GetH1_SMA80(5);
      }
      else if(tf == PERIOD_H4)
      {
         sma20_0 = GetH4_SMA20(0);
         sma80_0 = GetH4_SMA80(0);
         sma20_5 = GetH4_SMA20(5);
         sma80_5 = GetH4_SMA80(5);
      }
      else
         return false;

      double gap0 = MathAbs(sma20_0 - sma80_0);
      double gap5 = MathAbs(sma20_5 - sma80_5);

      return gap0 < gap5;
   }

   //--- Check divergence (expanding)
   bool IsDiverging(ENUM_TIMEFRAMES tf)
   {
      double sma20_0, sma80_0, sma20_5, sma80_5;

      if(tf == PERIOD_H1)
      {
         sma20_0 = GetH1_SMA20(0);
         sma80_0 = GetH1_SMA80(0);
         sma20_5 = GetH1_SMA20(5);
         sma80_5 = GetH1_SMA80(5);
      }
      else if(tf == PERIOD_H4)
      {
         sma20_0 = GetH4_SMA20(0);
         sma80_0 = GetH4_SMA80(0);
         sma20_5 = GetH4_SMA20(5);
         sma80_5 = GetH4_SMA80(5);
      }
      else
         return false;

      double gap0 = MathAbs(sma20_0 - sma80_0);
      double gap5 = MathAbs(sma20_5 - sma80_5);

      return gap0 > gap5;
   }

   //--- Check for pullback to SMA (price near SMA20 or SMA80)
   bool IsPullbackToSMA(ENUM_TIMEFRAMES tf, double thresholdPoints = 200)
   {
      double price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double sma20 = 0, sma80 = 0;

      if(tf == PERIOD_H1)
      {
         sma20 = GetH1_SMA20();
         sma80 = GetH1_SMA80();
      }
      else if(tf == PERIOD_H4)
      {
         sma20 = GetH4_SMA20();
         sma80 = GetH4_SMA80();
      }

      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
      double threshold = thresholdPoints * point;

      return (MathAbs(price - sma20) < threshold) || (MathAbs(price - sma80) < threshold);
   }

   //--- Detect golden cross (SMA20 crosses above SMA80)
   bool IsGoldenCross(ENUM_TIMEFRAMES tf)
   {
      double sma20_0, sma80_0, sma20_1, sma80_1;

      if(tf == PERIOD_H1)
      {
         sma20_0 = GetH1_SMA20(0);
         sma80_0 = GetH1_SMA80(0);
         sma20_1 = GetH1_SMA20(1);
         sma80_1 = GetH1_SMA80(1);
      }
      else if(tf == PERIOD_H4)
      {
         sma20_0 = GetH4_SMA20(0);
         sma80_0 = GetH4_SMA80(0);
         sma20_1 = GetH4_SMA20(1);
         sma80_1 = GetH4_SMA80(1);
      }
      else
         return false;

      return (sma20_0 > sma80_0) && (sma20_1 <= sma80_1);
   }

   //--- Detect dead cross (SMA20 crosses below SMA80)
   bool IsDeadCross(ENUM_TIMEFRAMES tf)
   {
      double sma20_0, sma80_0, sma20_1, sma80_1;

      if(tf == PERIOD_H1)
      {
         sma20_0 = GetH1_SMA20(0);
         sma80_0 = GetH1_SMA80(0);
         sma20_1 = GetH1_SMA20(1);
         sma80_1 = GetH1_SMA80(1);
      }
      else if(tf == PERIOD_H4)
      {
         sma20_0 = GetH4_SMA20(0);
         sma80_0 = GetH4_SMA80(0);
         sma20_1 = GetH4_SMA20(1);
         sma80_1 = GetH4_SMA80(1);
      }
      else
         return false;

      return (sma20_0 < sma80_0) && (sma20_1 >= sma80_1);
   }
};

//+------------------------------------------------------------------+
//| Simple High-Low Finder for Dow Theory                            |
//+------------------------------------------------------------------+
class CSwingFinder
{
private:
   string   m_Symbol;
   int      m_Lookback;

public:
   CSwingFinder() { m_Symbol = ""; m_Lookback = 10; }

   bool Initialize(string symbol, int lookback = 10)
   {
      m_Symbol = symbol;
      m_Lookback = lookback;
      return true;
   }

   //--- Find recent swing high
   double FindSwingHigh(ENUM_TIMEFRAMES tf, int barsBack = 50)
   {
      double highs[];
      ArraySetAsSeries(highs, true);

      if(CopyHigh(m_Symbol, tf, 0, barsBack, highs) < barsBack)
         return 0;

      double swingHigh = 0;

      for(int i = m_Lookback; i < barsBack - m_Lookback; i++)
      {
         bool isSwing = true;
         for(int j = 1; j <= m_Lookback; j++)
         {
            if(highs[i] <= highs[i - j] || highs[i] <= highs[i + j])
            {
               isSwing = false;
               break;
            }
         }
         if(isSwing)
         {
            swingHigh = highs[i];
            break;
         }
      }

      return swingHigh;
   }

   //--- Find recent swing low
   double FindSwingLow(ENUM_TIMEFRAMES tf, int barsBack = 50)
   {
      double lows[];
      ArraySetAsSeries(lows, true);

      if(CopyLow(m_Symbol, tf, 0, barsBack, lows) < barsBack)
         return 0;

      double swingLow = 0;

      for(int i = m_Lookback; i < barsBack - m_Lookback; i++)
      {
         bool isSwing = true;
         for(int j = 1; j <= m_Lookback; j++)
         {
            if(lows[i] >= lows[i - j] || lows[i] >= lows[i + j])
            {
               isSwing = false;
               break;
            }
         }
         if(isSwing)
         {
            swingLow = lows[i];
            break;
         }
      }

      return swingLow;
   }

   //--- Find recent high (simpler - just highest of N bars)
   double FindRecentHigh(ENUM_TIMEFRAMES tf, int bars = 20)
   {
      double highs[];
      ArraySetAsSeries(highs, true);

      if(CopyHigh(m_Symbol, tf, 1, bars, highs) < bars)
         return 0;

      double maxHigh = highs[0];
      for(int i = 1; i < bars; i++)
      {
         if(highs[i] > maxHigh)
            maxHigh = highs[i];
      }

      return maxHigh;
   }

   //--- Find recent low (simpler - just lowest of N bars)
   double FindRecentLow(ENUM_TIMEFRAMES tf, int bars = 20)
   {
      double lows[];
      ArraySetAsSeries(lows, true);

      if(CopyLow(m_Symbol, tf, 1, bars, lows) < bars)
         return 0;

      double minLow = lows[0];
      for(int i = 1; i < bars; i++)
      {
         if(lows[i] < minLow)
            minLow = lows[i];
      }

      return minLow;
   }
};

//+------------------------------------------------------------------+
//| Main Trend Analyzer combining SMA and Dow Theory                 |
//+------------------------------------------------------------------+
class CTrendAnalyzer
{
private:
   string            m_Symbol;
   CSMAManager       m_SMAManager;
   CSwingFinder      m_SwingFinder;

   ENUM_TREND_DIRECTION m_TrendD1;
   ENUM_TREND_DIRECTION m_TrendH4;
   ENUM_TREND_DIRECTION m_TrendH1;

   bool              m_IsWarState;

public:
   CTrendAnalyzer()
   {
      m_Symbol = "";
      m_TrendD1 = TREND_NEUTRAL;
      m_TrendH4 = TREND_NEUTRAL;
      m_TrendH1 = TREND_NEUTRAL;
      m_IsWarState = false;
   }

   bool Initialize(string symbol)
   {
      m_Symbol = symbol;

      if(!m_SMAManager.Initialize(symbol))
         return false;

      if(!m_SwingFinder.Initialize(symbol))
         return false;

      Print("[TrendAnalyzer] Initialized v2.0");
      return true;
   }

   void Deinitialize()
   {
      m_SMAManager.Deinitialize();
   }

   //--- Update all trend analysis (simplified)
   void Update()
   {
      // Use simple SMA-based trend detection
      m_TrendD1 = m_SMAManager.GetSimpleTrend(PERIOD_D1);
      m_TrendH4 = m_SMAManager.GetSimpleTrend(PERIOD_H4);
      m_TrendH1 = m_SMAManager.GetSimpleTrend(PERIOD_H1);

      // Update war state
      UpdateWarState();
   }

   //--- Updated war state logic (more lenient)
   void UpdateWarState()
   {
      m_IsWarState = false;

      // Only consider war state if D1 and H4 are DIRECTLY opposing
      // (both have clear trends in opposite directions)
      if(m_TrendD1 == TREND_UP && m_TrendH4 == TREND_DOWN)
         m_IsWarState = true;
      else if(m_TrendD1 == TREND_DOWN && m_TrendH4 == TREND_UP)
         m_IsWarState = true;

      // H1 can be different - it's used for entry timing
      // Don't block trades just because H1 is against H4
   }

   //--- Check if higher TF supports trade direction
   bool IsHigherTFAligned(ENUM_TREND_DIRECTION tradeDirection)
   {
      // D1 must not be opposing
      if(tradeDirection == TREND_UP && m_TrendD1 == TREND_DOWN)
         return false;
      if(tradeDirection == TREND_DOWN && m_TrendD1 == TREND_UP)
         return false;

      // H4 should ideally match or be neutral
      if(tradeDirection == TREND_UP)
         return (m_TrendH4 == TREND_UP || m_TrendH4 == TREND_NEUTRAL);
      if(tradeDirection == TREND_DOWN)
         return (m_TrendH4 == TREND_DOWN || m_TrendH4 == TREND_NEUTRAL);

      return false;
   }

   //--- Getters
   ENUM_TREND_DIRECTION GetTrendD1() { return m_TrendD1; }
   ENUM_TREND_DIRECTION GetTrendH4() { return m_TrendH4; }
   ENUM_TREND_DIRECTION GetTrendH1() { return m_TrendH1; }
   bool IsWarState() { return m_IsWarState; }

   CSMAManager* GetSMAManager() { return &m_SMAManager; }
   CSwingFinder* GetSwingFinder() { return &m_SwingFinder; }

   string GetTrendString()
   {
      return StringFormat("D1=%s | H4=%s | H1=%s | War=%s",
                          TrendToString(m_TrendD1),
                          TrendToString(m_TrendH4),
                          TrendToString(m_TrendH1),
                          m_IsWarState ? "YES" : "NO");
   }

   string TrendToString(ENUM_TREND_DIRECTION trend)
   {
      switch(trend)
      {
         case TREND_UP: return "UP";
         case TREND_DOWN: return "DOWN";
         default: return "NEUTRAL";
      }
   }
};

#endif // TREND_ANALYSIS_MQH
