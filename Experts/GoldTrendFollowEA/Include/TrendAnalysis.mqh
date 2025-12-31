//+------------------------------------------------------------------+
//|                                                TrendAnalysis.mqh |
//|           Dow Theory & SMA Multi-Timeframe Trend Analysis        |
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

   //--- Get SMA slope (direction)
   double GetSMASlope(int handle, int period = 5)
   {
      double sma0 = GetSMA(handle, 0);
      double sma1 = GetSMA(handle, period);

      if(sma1 == 0) return 0;

      return (sma0 - sma1) / sma1 * 100.0;
   }

   //--- Check if SMAs are aligned (all pointing same direction)
   bool AreSMAsAligned(ENUM_TIMEFRAMES tf, ENUM_TREND_DIRECTION direction)
   {
      double slope20 = 0, slope80 = 0;
      double sma20 = 0, sma80 = 0;

      if(tf == PERIOD_H1)
      {
         sma20 = GetH1_SMA20();
         sma80 = GetH1_SMA80();
         slope20 = GetSMASlope(m_HandleH1_20);
         slope80 = GetSMASlope(m_HandleH1_80);
      }
      else if(tf == PERIOD_H4)
      {
         sma20 = GetH4_SMA20();
         sma80 = GetH4_SMA80();
         slope20 = GetSMASlope(m_HandleH4_20);
         slope80 = GetSMASlope(m_HandleH4_80);
      }

      if(direction == TREND_UP)
      {
         // For uptrend: SMA20 > SMA80 and both slopes positive
         return (sma20 > sma80) && (slope20 > 0) && (slope80 > 0);
      }
      else if(direction == TREND_DOWN)
      {
         // For downtrend: SMA20 < SMA80 and both slopes negative
         return (sma20 < sma80) && (slope20 < 0) && (slope80 < 0);
      }

      return false;
   }

   //--- Check convergence/divergence state
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

      // Converging if gap is decreasing
      return gap0 < gap5;
   }

   //--- Check divergence (expanding after convergence)
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

      // Diverging if gap is increasing
      return gap0 > gap5;
   }
};

//+------------------------------------------------------------------+
//| Dow Theory Trend Analyzer                                        |
//| - 高値更新＋安値切り上げ = 上昇トレンド                            |
//| - 安値更新＋高値切り下げ = 下降トレンド                            |
//| - 下位時間軸の20MAの波の高安を基準                                 |
//+------------------------------------------------------------------+
class CDowTheoryAnalyzer
{
private:
   string            m_Symbol;
   int               m_SwingLookback;       // Number of bars to look back for swing detection
   double            m_SwingThreshold;      // Minimum swing size in points

   SwingPoint        m_SwingHighs[];
   SwingPoint        m_SwingLows[];

public:
   //--- Constructor
   CDowTheoryAnalyzer()
   {
      m_Symbol = "";
      m_SwingLookback = 20;
      m_SwingThreshold = 50.0;  // 50 points minimum swing
   }

   //--- Initialize
   bool Initialize(string symbol, int lookback = 20, double threshold = 50.0)
   {
      m_Symbol = symbol;
      m_SwingLookback = lookback;
      m_SwingThreshold = threshold;

      Print("[DowTheory] Initialized");
      return true;
   }

   //--- Find swing highs using lower timeframe 20SMA wave
   void FindSwingHighsUsingSMA(ENUM_TIMEFRAMES higherTF, int smaHandle, int count = 10)
   {
      ArrayResize(m_SwingHighs, 0);

      double smaValues[];
      double highPrices[];
      datetime times[];
      ArraySetAsSeries(smaValues, true);
      ArraySetAsSeries(highPrices, true);
      ArraySetAsSeries(times, true);

      int barsNeeded = m_SwingLookback * count;

      if(CopyBuffer(smaHandle, 0, 0, barsNeeded, smaValues) < barsNeeded)
         return;
      if(CopyHigh(m_Symbol, higherTF, 0, barsNeeded, highPrices) < barsNeeded)
         return;
      if(CopyTime(m_Symbol, higherTF, 0, barsNeeded, times) < barsNeeded)
         return;

      // Find peaks where price crosses above SMA and then back below
      bool aboveSMA = false;
      double peakHigh = 0;
      int peakBar = 0;
      datetime peakTime = 0;

      for(int i = barsNeeded - 1; i >= 0; i--)
      {
         if(highPrices[i] > smaValues[i])
         {
            if(!aboveSMA)
            {
               // Just crossed above
               aboveSMA = true;
               peakHigh = highPrices[i];
               peakBar = i;
               peakTime = times[i];
            }
            else if(highPrices[i] > peakHigh)
            {
               peakHigh = highPrices[i];
               peakBar = i;
               peakTime = times[i];
            }
         }
         else if(aboveSMA)
         {
            // Crossed back below - record the swing high
            aboveSMA = false;

            SwingPoint sp;
            sp.price = peakHigh;
            sp.time = peakTime;
            sp.barIndex = peakBar;
            sp.isHigh = true;

            int size = ArraySize(m_SwingHighs);
            ArrayResize(m_SwingHighs, size + 1);
            m_SwingHighs[size] = sp;

            if(ArraySize(m_SwingHighs) >= count)
               break;
         }
      }
   }

   //--- Find swing lows using lower timeframe 20SMA wave
   void FindSwingLowsUsingSMA(ENUM_TIMEFRAMES higherTF, int smaHandle, int count = 10)
   {
      ArrayResize(m_SwingLows, 0);

      double smaValues[];
      double lowPrices[];
      datetime times[];
      ArraySetAsSeries(smaValues, true);
      ArraySetAsSeries(lowPrices, true);
      ArraySetAsSeries(times, true);

      int barsNeeded = m_SwingLookback * count;

      if(CopyBuffer(smaHandle, 0, 0, barsNeeded, smaValues) < barsNeeded)
         return;
      if(CopyLow(m_Symbol, higherTF, 0, barsNeeded, lowPrices) < barsNeeded)
         return;
      if(CopyTime(m_Symbol, higherTF, 0, barsNeeded, times) < barsNeeded)
         return;

      // Find troughs where price crosses below SMA and then back above
      bool belowSMA = false;
      double troughLow = 0;
      int troughBar = 0;
      datetime troughTime = 0;

      for(int i = barsNeeded - 1; i >= 0; i--)
      {
         if(lowPrices[i] < smaValues[i])
         {
            if(!belowSMA)
            {
               // Just crossed below
               belowSMA = true;
               troughLow = lowPrices[i];
               troughBar = i;
               troughTime = times[i];
            }
            else if(lowPrices[i] < troughLow)
            {
               troughLow = lowPrices[i];
               troughBar = i;
               troughTime = times[i];
            }
         }
         else if(belowSMA)
         {
            // Crossed back above - record the swing low
            belowSMA = false;

            SwingPoint sp;
            sp.price = troughLow;
            sp.time = troughTime;
            sp.barIndex = troughBar;
            sp.isHigh = false;

            int size = ArraySize(m_SwingLows);
            ArrayResize(m_SwingLows, size + 1);
            m_SwingLows[size] = sp;

            if(ArraySize(m_SwingLows) >= count)
               break;
         }
      }
   }

   //--- Analyze trend using Dow Theory
   ENUM_TREND_DIRECTION AnalyzeTrend(ENUM_TIMEFRAMES tf, int smaHandle)
   {
      FindSwingHighsUsingSMA(tf, smaHandle, 5);
      FindSwingLowsUsingSMA(tf, smaHandle, 5);

      if(ArraySize(m_SwingHighs) < 2 || ArraySize(m_SwingLows) < 2)
         return TREND_NEUTRAL;

      // Check for uptrend: higher highs + higher lows
      bool higherHighs = true;
      bool higherLows = true;

      for(int i = 0; i < ArraySize(m_SwingHighs) - 1; i++)
      {
         if(m_SwingHighs[i].price <= m_SwingHighs[i + 1].price)
            higherHighs = false;
      }

      for(int i = 0; i < ArraySize(m_SwingLows) - 1; i++)
      {
         if(m_SwingLows[i].price <= m_SwingLows[i + 1].price)
            higherLows = false;
      }

      if(higherHighs && higherLows)
         return TREND_UP;

      // Check for downtrend: lower highs + lower lows
      bool lowerHighs = true;
      bool lowerLows = true;

      for(int i = 0; i < ArraySize(m_SwingHighs) - 1; i++)
      {
         if(m_SwingHighs[i].price >= m_SwingHighs[i + 1].price)
            lowerHighs = false;
      }

      for(int i = 0; i < ArraySize(m_SwingLows) - 1; i++)
      {
         if(m_SwingLows[i].price >= m_SwingLows[i + 1].price)
            lowerLows = false;
      }

      if(lowerHighs && lowerLows)
         return TREND_DOWN;

      return TREND_NEUTRAL;
   }

   //--- Get latest swing high
   double GetLatestSwingHigh()
   {
      if(ArraySize(m_SwingHighs) > 0)
         return m_SwingHighs[0].price;
      return 0;
   }

   //--- Get latest swing low
   double GetLatestSwingLow()
   {
      if(ArraySize(m_SwingLows) > 0)
         return m_SwingLows[0].price;
      return 0;
   }

   //--- Get previous swing high (for resistance check)
   double GetPreviousSwingHigh()
   {
      if(ArraySize(m_SwingHighs) > 1)
         return m_SwingHighs[1].price;
      return 0;
   }

   //--- Get previous swing low (for support check)
   double GetPreviousSwingLow()
   {
      if(ArraySize(m_SwingLows) > 1)
         return m_SwingLows[1].price;
      return 0;
   }

   //--- Check if price broke above swing high (trend continuation)
   bool IsBullishBreakout(double currentPrice)
   {
      double latestHigh = GetLatestSwingHigh();
      if(latestHigh > 0 && currentPrice > latestHigh)
         return true;
      return false;
   }

   //--- Check if price broke below swing low (trend continuation)
   bool IsBearishBreakout(double currentPrice)
   {
      double latestLow = GetLatestSwingLow();
      if(latestLow > 0 && currentPrice < latestLow)
         return true;
      return false;
   }

   //--- Detect trend reversal (first wave of new trend)
   bool IsTrendReversal(ENUM_TREND_DIRECTION previousTrend, double currentPrice)
   {
      if(previousTrend == TREND_DOWN)
      {
         // Look for bullish reversal
         double latestHigh = GetLatestSwingHigh();
         if(latestHigh > 0 && currentPrice > latestHigh)
         {
            // Price broke above recent high - potential reversal
            return true;
         }
      }
      else if(previousTrend == TREND_UP)
      {
         // Look for bearish reversal
         double latestLow = GetLatestSwingLow();
         if(latestLow > 0 && currentPrice < latestLow)
         {
            // Price broke below recent low - potential reversal
            return true;
         }
      }

      return false;
   }

   //--- Get swing high array
   void GetSwingHighs(SwingPoint &arr[])
   {
      ArrayCopy(arr, m_SwingHighs);
   }

   //--- Get swing low array
   void GetSwingLows(SwingPoint &arr[])
   {
      ArrayCopy(arr, m_SwingLows);
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
   CDowTheoryAnalyzer m_DowAnalyzer;

   ENUM_TREND_DIRECTION m_TrendD1;
   ENUM_TREND_DIRECTION m_TrendH4;
   ENUM_TREND_DIRECTION m_TrendH1;
   ENUM_TREND_DIRECTION m_TrendM15;

   bool              m_IsWarState;  // 戦争状態（方向が一致しない）

public:
   //--- Constructor
   CTrendAnalyzer()
   {
      m_Symbol = "";
      m_TrendD1 = TREND_NEUTRAL;
      m_TrendH4 = TREND_NEUTRAL;
      m_TrendH1 = TREND_NEUTRAL;
      m_TrendM15 = TREND_NEUTRAL;
      m_IsWarState = false;
   }

   //--- Initialize
   bool Initialize(string symbol)
   {
      m_Symbol = symbol;

      if(!m_SMAManager.Initialize(symbol))
         return false;

      if(!m_DowAnalyzer.Initialize(symbol))
         return false;

      Print("[TrendAnalyzer] Initialized");
      return true;
   }

   //--- Deinitialize
   void Deinitialize()
   {
      m_SMAManager.Deinitialize();
   }

   //--- Update all trend analysis
   void Update()
   {
      // Get SMA handles for Dow analysis (using lower TF 20SMA as reference)
      int h1_20Handle = iMA(m_Symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
      int h4_20Handle = iMA(m_Symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
      int d1_20Handle = iMA(m_Symbol, PERIOD_H4, 20, 0, MODE_SMA, PRICE_CLOSE);

      // Analyze each timeframe using Dow Theory
      m_TrendH1 = m_DowAnalyzer.AnalyzeTrend(PERIOD_H1, h1_20Handle);
      m_TrendH4 = m_DowAnalyzer.AnalyzeTrend(PERIOD_H4, h4_20Handle);
      m_TrendD1 = m_DowAnalyzer.AnalyzeTrend(PERIOD_D1, d1_20Handle);

      // Also check with SMA alignment
      if(m_SMAManager.AreSMAsAligned(PERIOD_H1, TREND_UP))
         m_TrendH1 = TREND_UP;
      else if(m_SMAManager.AreSMAsAligned(PERIOD_H1, TREND_DOWN))
         m_TrendH1 = TREND_DOWN;

      if(m_SMAManager.AreSMAsAligned(PERIOD_H4, TREND_UP))
         m_TrendH4 = TREND_UP;
      else if(m_SMAManager.AreSMAsAligned(PERIOD_H4, TREND_DOWN))
         m_TrendH4 = TREND_DOWN;

      // Check for war state (directions not aligned)
      UpdateWarState();

      // Cleanup temp handles
      IndicatorRelease(h1_20Handle);
      IndicatorRelease(h4_20Handle);
      IndicatorRelease(d1_20Handle);
   }

   //--- Update war state (戦争状態判定)
   void UpdateWarState()
   {
      // War state exists when major timeframes have conflicting trends
      int upCount = 0;
      int downCount = 0;

      if(m_TrendD1 == TREND_UP) upCount++;
      else if(m_TrendD1 == TREND_DOWN) downCount++;

      if(m_TrendH4 == TREND_UP) upCount++;
      else if(m_TrendH4 == TREND_DOWN) downCount++;

      if(m_TrendH1 == TREND_UP) upCount++;
      else if(m_TrendH1 == TREND_DOWN) downCount++;

      // War state if we have both up and down trends across timeframes
      m_IsWarState = (upCount > 0 && downCount > 0);

      if(m_IsWarState)
      {
         PrintFormat("[TrendAnalyzer] WARNING: War state detected! D1=%d, H4=%d, H1=%d",
                     m_TrendD1, m_TrendH4, m_TrendH1);
      }
   }

   //--- Check if all higher timeframes align with trade direction
   bool IsHigherTFAligned(ENUM_TREND_DIRECTION tradeDirection)
   {
      if(m_IsWarState)
         return false;

      if(tradeDirection == TREND_UP)
      {
         return (m_TrendD1 == TREND_UP || m_TrendD1 == TREND_NEUTRAL) &&
                (m_TrendH4 == TREND_UP || m_TrendH4 == TREND_NEUTRAL);
      }
      else if(tradeDirection == TREND_DOWN)
      {
         return (m_TrendD1 == TREND_DOWN || m_TrendD1 == TREND_NEUTRAL) &&
                (m_TrendH4 == TREND_DOWN || m_TrendH4 == TREND_NEUTRAL);
      }

      return false;
   }

   //--- Get converging/diverging state for entry timing
   bool IsConvergingToDiverging(ENUM_TIMEFRAMES tf)
   {
      // Previous state was converging, now diverging
      return !m_SMAManager.IsConverging(tf) && m_SMAManager.IsDiverging(tf);
   }

   //--- Getters
   ENUM_TREND_DIRECTION GetTrendD1() { return m_TrendD1; }
   ENUM_TREND_DIRECTION GetTrendH4() { return m_TrendH4; }
   ENUM_TREND_DIRECTION GetTrendH1() { return m_TrendH1; }
   bool IsWarState() { return m_IsWarState; }

   CSMAManager* GetSMAManager() { return &m_SMAManager; }
   CDowTheoryAnalyzer* GetDowAnalyzer() { return &m_DowAnalyzer; }

   //--- Get trend string for logging
   string GetTrendString()
   {
      return StringFormat("D1=%s | H4=%s | H1=%s | War=%s",
                          TrendToString(m_TrendD1),
                          TrendToString(m_TrendH4),
                          TrendToString(m_TrendH1),
                          m_IsWarState ? "YES" : "NO");
   }

   //--- Convert trend to string
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
