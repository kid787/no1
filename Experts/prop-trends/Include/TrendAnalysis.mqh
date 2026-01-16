//+------------------------------------------------------------------+
//|                                                TrendAnalysis.mqh |
//|        Dow Theory & SMA Multi-Timeframe Trend Analysis v2.2      |
//|        ADXトレンド強度フィルター追加                                |
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

//--- MA convergence/divergence state
enum ENUM_MA_STATE
{
   MA_STATE_CONVERGING,    // 収束中（MAが近づいている）
   MA_STATE_DIVERGING,     // 拡散中（MAが離れている）
   MA_STATE_TRANSITION,    // 遷移中（収束→拡散の瞬間）
   MA_STATE_UNKNOWN
};

//+------------------------------------------------------------------+
//| Multi-Timeframe SMA Manager with Convergence/Divergence Detection|
//+------------------------------------------------------------------+
class CSMAManager
{
private:
   string            m_Symbol;
   int               m_HandleH1_20, m_HandleH1_80, m_HandleH1_480;
   int               m_HandleH4_20, m_HandleH4_80, m_HandleH4_120, m_HandleH4_600;
   int               m_HandleM15_20;
   int               m_HandleD1_20;

   // State tracking for convergence/divergence
   double            m_PrevGapH1;     // Previous H1 SMA gap
   double            m_PrevGapH4;     // Previous H4 SMA gap
   bool              m_WasConvergingH1;
   bool              m_WasConvergingH4;

public:
   CSMAManager()
   {
      m_Symbol = "";
      m_PrevGapH1 = 0;
      m_PrevGapH4 = 0;
      m_WasConvergingH1 = false;
      m_WasConvergingH4 = false;
   }

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

      // 15分足 SMA
      m_HandleM15_20 = iMA(symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);

      // 日足 SMA
      m_HandleD1_20 = iMA(symbol, PERIOD_D1, 20, 0, MODE_SMA, PRICE_CLOSE);

      if(m_HandleH1_20 == INVALID_HANDLE || m_HandleH1_80 == INVALID_HANDLE ||
         m_HandleH1_480 == INVALID_HANDLE || m_HandleH4_20 == INVALID_HANDLE ||
         m_HandleH4_80 == INVALID_HANDLE || m_HandleH4_120 == INVALID_HANDLE ||
         m_HandleH4_600 == INVALID_HANDLE || m_HandleM15_20 == INVALID_HANDLE ||
         m_HandleD1_20 == INVALID_HANDLE)
      {
         Print("[SMAManager] Failed to create indicator handles");
         return false;
      }

      // Initialize gap tracking
      m_PrevGapH1 = GetMAGap(PERIOD_H1);
      m_PrevGapH4 = GetMAGap(PERIOD_H4);

      Print("[SMAManager] Initialized v2.2");
      return true;
   }

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

   double GetSMA(int handle, int shift = 0)
   {
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
         return 0;
      return buffer[0];
   }

   // SMA Getters
   double GetH1_SMA20(int shift = 0) { return GetSMA(m_HandleH1_20, shift); }
   double GetH1_SMA80(int shift = 0) { return GetSMA(m_HandleH1_80, shift); }
   double GetH1_SMA480(int shift = 0) { return GetSMA(m_HandleH1_480, shift); }
   double GetH4_SMA20(int shift = 0) { return GetSMA(m_HandleH4_20, shift); }
   double GetH4_SMA80(int shift = 0) { return GetSMA(m_HandleH4_80, shift); }
   double GetH4_SMA120(int shift = 0) { return GetSMA(m_HandleH4_120, shift); }
   double GetH4_SMA600(int shift = 0) { return GetSMA(m_HandleH4_600, shift); }
   double GetM15_SMA20(int shift = 0) { return GetSMA(m_HandleM15_20, shift); }
   double GetD1_SMA20(int shift = 0) { return GetSMA(m_HandleD1_20, shift); }

   //--- Get current MA gap (SMA20 - SMA80)
   double GetMAGap(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      if(tf == PERIOD_H1)
         return GetH1_SMA20(shift) - GetH1_SMA80(shift);
      else if(tf == PERIOD_H4)
         return GetH4_SMA20(shift) - GetH4_SMA80(shift);
      return 0;
   }

   //--- Get MA gap absolute (distance between SMAs)
   double GetMAGapAbs(ENUM_TIMEFRAMES tf, int shift = 0)
   {
      return MathAbs(GetMAGap(tf, shift));
   }

   //--- Check if currently converging (gap getting smaller)
   bool IsConverging(ENUM_TIMEFRAMES tf)
   {
      double gap0 = GetMAGapAbs(tf, 0);
      double gap3 = GetMAGapAbs(tf, 3);
      double gap5 = GetMAGapAbs(tf, 5);

      // Converging if gap is consistently decreasing
      return (gap0 < gap3) && (gap3 < gap5);
   }

   //--- Check if currently diverging (gap getting larger)
   bool IsDiverging(ENUM_TIMEFRAMES tf)
   {
      double gap0 = GetMAGapAbs(tf, 0);
      double gap3 = GetMAGapAbs(tf, 3);
      double gap5 = GetMAGapAbs(tf, 5);

      // Diverging if gap is consistently increasing
      return (gap0 > gap3) && (gap3 > gap5);
   }

   //--- ★重要★ 収束→拡散の遷移を検出
   bool IsConvergenceToDivergenceTransition(ENUM_TIMEFRAMES tf)
   {
      // 過去に収束していて、今拡散し始めた瞬間
      double gap0 = GetMAGapAbs(tf, 0);
      double gap1 = GetMAGapAbs(tf, 1);
      double gap2 = GetMAGapAbs(tf, 2);
      double gap3 = GetMAGapAbs(tf, 3);
      double gap5 = GetMAGapAbs(tf, 5);

      // Was converging: gap was decreasing (gap5 > gap3 > gap2)
      bool wasConverging = (gap5 > gap3) && (gap3 > gap2);

      // Now diverging: gap is increasing (gap0 > gap1)
      bool nowDiverging = (gap0 > gap1) && (gap0 > gap2);

      // Transition point: minimum gap was around bar 1-2
      bool atTransition = wasConverging && nowDiverging;

      if(atTransition)
      {
         PrintFormat("[SMA] Convergence→Divergence detected on %s! Gap: %.1f→%.1f→%.1f→%.1f→%.1f",
                     EnumToString(tf), gap5, gap3, gap2, gap1, gap0);
      }

      return atTransition;
   }

   //--- Update state tracking (call once per bar)
   void UpdateState()
   {
      // Save current state as previous
      m_WasConvergingH1 = IsConverging(PERIOD_H1);
      m_WasConvergingH4 = IsConverging(PERIOD_H4);
      m_PrevGapH1 = GetMAGapAbs(PERIOD_H1);
      m_PrevGapH4 = GetMAGapAbs(PERIOD_H4);
   }

   //--- Get MA direction based on position (SMA20 vs SMA80)
   ENUM_TREND_DIRECTION GetMADirection(ENUM_TIMEFRAMES tf)
   {
      double gap = GetMAGap(tf);
      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);

      // SMA20 > SMA80 = bullish, SMA20 < SMA80 = bearish
      if(gap > 50 * point)  // 50 points threshold
         return TREND_UP;
      else if(gap < -50 * point)
         return TREND_DOWN;

      return TREND_NEUTRAL;
   }

   //--- Get SMA slope
   double GetSMASlope(int handle, int period = 5)
   {
      double sma0 = GetSMA(handle, 0);
      double sma1 = GetSMA(handle, period);
      if(sma1 == 0) return 0;
      return (sma0 - sma1) / sma1 * 100.0;
   }

   //--- Check SMA alignment
   bool AreSMAsAligned(ENUM_TIMEFRAMES tf, ENUM_TREND_DIRECTION direction)
   {
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

      if(direction == TREND_UP)
         return sma20 > sma80;
      else if(direction == TREND_DOWN)
         return sma20 < sma80;

      return false;
   }
};

//+------------------------------------------------------------------+
//| Dow Theory Swing Detector - 下位足のダウ転換検出                   |
//+------------------------------------------------------------------+
class CDowSwingDetector
{
private:
   string   m_Symbol;
   int      m_SwingBars;     // Bars to look back for swing detection
   double   m_Point;

   // State tracking
   double   m_PrevSwingHigh;
   double   m_PrevSwingLow;

public:
   CDowSwingDetector()
   {
      m_Symbol = "";
      m_SwingBars = 5;
      m_Point = 0;
      m_PrevSwingHigh = 0;
      m_PrevSwingLow = 0;
   }

   bool Initialize(string symbol, int swingBars = 5)
   {
      m_Symbol = symbol;
      m_SwingBars = swingBars;
      m_Point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      Print("[DowSwing] Initialized");
      return true;
   }

   //--- Find recent swing high (local maximum)
   double FindRecentSwingHigh(ENUM_TIMEFRAMES tf, int lookback = 30)
   {
      double highs[];
      ArraySetAsSeries(highs, true);

      if(CopyHigh(m_Symbol, tf, 0, lookback, highs) < lookback)
         return 0;

      // Find most recent swing high
      for(int i = m_SwingBars; i < lookback - m_SwingBars; i++)
      {
         bool isSwing = true;
         for(int j = 1; j <= m_SwingBars; j++)
         {
            if(highs[i] <= highs[i - j] || highs[i] <= highs[i + j])
            {
               isSwing = false;
               break;
            }
         }
         if(isSwing)
            return highs[i];
      }

      // Fallback: highest of last N bars
      double highest = highs[1];
      for(int i = 2; i < lookback / 2; i++)
      {
         if(highs[i] > highest)
            highest = highs[i];
      }
      return highest;
   }

   //--- Find recent swing low (local minimum)
   double FindRecentSwingLow(ENUM_TIMEFRAMES tf, int lookback = 30)
   {
      double lows[];
      ArraySetAsSeries(lows, true);

      if(CopyLow(m_Symbol, tf, 0, lookback, lows) < lookback)
         return 0;

      // Find most recent swing low
      for(int i = m_SwingBars; i < lookback - m_SwingBars; i++)
      {
         bool isSwing = true;
         for(int j = 1; j <= m_SwingBars; j++)
         {
            if(lows[i] >= lows[i - j] || lows[i] >= lows[i + j])
            {
               isSwing = false;
               break;
            }
         }
         if(isSwing)
            return lows[i];
      }

      // Fallback: lowest of last N bars
      double lowest = lows[1];
      for(int i = 2; i < lookback / 2; i++)
      {
         if(lows[i] < lowest)
            lowest = lows[i];
      }
      return lowest;
   }

   //--- ★重要★ 下位足のダウ転換検出 - 高値ブレイク（買いシグナル）
   bool IsBullishDowBreak(ENUM_TIMEFRAMES tf)
   {
      double closes[];
      ArraySetAsSeries(closes, true);

      if(CopyClose(m_Symbol, tf, 0, 3, closes) < 3)
         return false;

      double currentClose = closes[0];
      double prevClose = closes[1];
      double swingHigh = FindRecentSwingHigh(tf, 30);

      if(swingHigh == 0)
         return false;

      // Current close broke above swing high, prev close was below
      bool breakout = (currentClose > swingHigh) && (prevClose <= swingHigh);

      if(breakout)
      {
         PrintFormat("[DowSwing] Bullish breakout on %s! Close %.5f > SwingHigh %.5f",
                     EnumToString(tf), currentClose, swingHigh);
      }

      return breakout;
   }

   //--- ★重要★ 下位足のダウ転換検出 - 安値ブレイク（売りシグナル）
   bool IsBearishDowBreak(ENUM_TIMEFRAMES tf)
   {
      double closes[];
      ArraySetAsSeries(closes, true);

      if(CopyClose(m_Symbol, tf, 0, 3, closes) < 3)
         return false;

      double currentClose = closes[0];
      double prevClose = closes[1];
      double swingLow = FindRecentSwingLow(tf, 30);

      if(swingLow == 0)
         return false;

      // Current close broke below swing low, prev close was above
      bool breakout = (currentClose < swingLow) && (prevClose >= swingLow);

      if(breakout)
      {
         PrintFormat("[DowSwing] Bearish breakout on %s! Close %.5f < SwingLow %.5f",
                     EnumToString(tf), currentClose, swingLow);
      }

      return breakout;
   }

   //--- Get swing high/low for SL calculation
   double GetSwingHighForSL(ENUM_TIMEFRAMES tf) { return FindRecentSwingHigh(tf, 20); }
   double GetSwingLowForSL(ENUM_TIMEFRAMES tf) { return FindRecentSwingLow(tf, 20); }
};

//+------------------------------------------------------------------+
//| Main Trend Analyzer v2.2 with ADX Filter                          |
//+------------------------------------------------------------------+
class CTrendAnalyzer
{
private:
   string            m_Symbol;
   CSMAManager       m_SMAManager;
   CDowSwingDetector m_SwingDetector;

   ENUM_TREND_DIRECTION m_TrendD1;
   ENUM_TREND_DIRECTION m_TrendH4;
   ENUM_TREND_DIRECTION m_TrendH1;

   bool              m_IsWarState;

   // ADX Filter
   bool              m_UseADXFilter;
   int               m_ADXPeriod;
   double            m_ADXMinLevel;
   int               m_HandleADX_D1;
   int               m_HandleADX_H4;
   int               m_HandleADX_H1;
   double            m_CurrentADX_D1;
   double            m_CurrentADX_H4;
   double            m_CurrentADX_H1;

   // D1トレンド閾値 (points)
   int               m_D1TrendThreshold;

   // D1 ATR (自動計算用)
   int               m_HandleATR_D1;
   double            m_CurrentATR_D1;

public:
   CTrendAnalyzer()
   {
      m_Symbol = "";
      m_TrendD1 = TREND_NEUTRAL;
      m_TrendH4 = TREND_NEUTRAL;
      m_TrendH1 = TREND_NEUTRAL;
      m_IsWarState = false;

      m_UseADXFilter = true;
      m_ADXPeriod = 14;
      m_ADXMinLevel = 20.0;
      m_HandleADX_D1 = INVALID_HANDLE;
      m_HandleADX_H4 = INVALID_HANDLE;
      m_HandleADX_H1 = INVALID_HANDLE;
      m_CurrentADX_D1 = 0;
      m_CurrentADX_H4 = 0;
      m_CurrentADX_H1 = 0;

      m_D1TrendThreshold = 2000;  // デフォルト: 2000 points
      m_HandleATR_D1 = INVALID_HANDLE;
      m_CurrentATR_D1 = 0;
   }

   //--- D1トレンド閾値を設定
   void SetD1TrendThreshold(int threshold)
   {
      m_D1TrendThreshold = threshold;
      PrintFormat("[TrendAnalyzer] D1 Trend Threshold set to %d points", m_D1TrendThreshold);
   }

   bool Initialize(string symbol, bool useADX = true, int adxPeriod = 14, double adxMinLevel = 20.0)
   {
      m_Symbol = symbol;
      m_UseADXFilter = useADX;
      m_ADXPeriod = adxPeriod;
      m_ADXMinLevel = adxMinLevel;

      if(!m_SMAManager.Initialize(symbol))
         return false;

      if(!m_SwingDetector.Initialize(symbol))
         return false;

      // Initialize ADX indicators
      if(m_UseADXFilter)
      {
         m_HandleADX_D1 = iADX(symbol, PERIOD_D1, m_ADXPeriod);
         m_HandleADX_H4 = iADX(symbol, PERIOD_H4, m_ADXPeriod);
         m_HandleADX_H1 = iADX(symbol, PERIOD_H1, m_ADXPeriod);

         if(m_HandleADX_D1 == INVALID_HANDLE || m_HandleADX_H4 == INVALID_HANDLE || m_HandleADX_H1 == INVALID_HANDLE)
         {
            Print("[TrendAnalyzer] Failed to create ADX handles");
            return false;
         }
         PrintFormat("[TrendAnalyzer] ADX Filter enabled (Period=%d, MinLevel=%.1f)",
                     m_ADXPeriod, m_ADXMinLevel);
      }

      // Initialize ATR for auto threshold calculation
      m_HandleATR_D1 = iATR(symbol, PERIOD_D1, 14);
      if(m_HandleATR_D1 == INVALID_HANDLE)
      {
         Print("[TrendAnalyzer] Failed to create ATR handle");
         return false;
      }

      Print("[TrendAnalyzer] Initialized v2.4 with D1 Regime Filter + ATR");
      return true;
   }

   void Deinitialize()
   {
      m_SMAManager.Deinitialize();
      if(m_HandleADX_D1 != INVALID_HANDLE) IndicatorRelease(m_HandleADX_D1);
      if(m_HandleADX_H4 != INVALID_HANDLE) IndicatorRelease(m_HandleADX_H4);
      if(m_HandleADX_H1 != INVALID_HANDLE) IndicatorRelease(m_HandleADX_H1);
      if(m_HandleATR_D1 != INVALID_HANDLE) IndicatorRelease(m_HandleATR_D1);
   }

   void Update()
   {
      // Get MA direction for each timeframe
      m_TrendD1 = GetTrendFromPrice(PERIOD_D1);
      m_TrendH4 = m_SMAManager.GetMADirection(PERIOD_H4);
      m_TrendH1 = m_SMAManager.GetMADirection(PERIOD_H1);

      // Update ADX values
      if(m_UseADXFilter)
      {
         m_CurrentADX_D1 = GetADXValue(m_HandleADX_D1);
         m_CurrentADX_H4 = GetADXValue(m_HandleADX_H4);
         m_CurrentADX_H1 = GetADXValue(m_HandleADX_H1);
      }

      // Update ATR value
      m_CurrentATR_D1 = GetATRValue(m_HandleATR_D1);

      UpdateWarState();
      m_SMAManager.UpdateState();
   }

   //--- Get ATR value from handle
   double GetATRValue(int handle, int shift = 0)
   {
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
         return 0;
      return buffer[0];
   }

   //--- Get current D1 ATR
   double GetATR_D1() { return m_CurrentATR_D1; }

   //--- ★自動計算: D1 ATRからトレンド閾値を算出★
   //--- 閾値 = ATR × 係数(0.3) ÷ Point値
   int CalculateAutoThreshold(double atrMultiplier = 0.3)
   {
      if(m_CurrentATR_D1 <= 0)
         return 1000;  // フォールバック値

      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
      if(point <= 0)
         return 1000;

      // ATRの30%をポイント数に変換
      int threshold = (int)MathRound((m_CurrentATR_D1 * atrMultiplier) / point);

      // 最小値/最大値を制限
      threshold = MathMax(500, MathMin(threshold, 50000));

      return threshold;
   }

   //--- 自動閾値を設定して適用
   void ApplyAutoThreshold(double atrMultiplier = 0.3)
   {
      int autoThreshold = CalculateAutoThreshold(atrMultiplier);
      m_D1TrendThreshold = autoThreshold;
      PrintFormat("[TrendAnalyzer] Auto Threshold: ATR=%.2f × %.0f%% = %d points",
                  m_CurrentATR_D1, atrMultiplier * 100, m_D1TrendThreshold);
   }

   //--- Get ADX value from handle
   double GetADXValue(int handle, int shift = 0)
   {
      double buffer[];
      ArraySetAsSeries(buffer, true);
      if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
         return 0;
      return buffer[0];
   }

   //--- Check if trend is strong enough (ADX above minimum)
   bool IsTrendStrong()
   {
      if(!m_UseADXFilter)
         return true;  // No filter = always strong

      // H4のADXがMinLevel以上ならトレンドあり
      return (m_CurrentADX_H4 >= m_ADXMinLevel);
   }

   //--- ★D1レジーム判定: トレンド相場かレンジ相場か★
   bool IsD1TrendingMarket(double d1ADXThreshold = 25.0)
   {
      if(!m_UseADXFilter)
         return true;  // フィルターOFF時は常にトレンド扱い

      // D1 ADXが閾値以上 かつ D1 SMAが順配列 → トレンド相場
      bool adxStrong = (m_CurrentADX_D1 >= d1ADXThreshold);
      bool smaAligned = (m_TrendD1 != TREND_NEUTRAL);

      return adxStrong && smaAligned;
   }

   //--- D1トレンド方向を取得 (SMA配列から)
   ENUM_TREND_DIRECTION GetD1TrendDirection()
   {
      double sma20 = m_SMAManager.GetD1_SMA20();
      double price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);

      // ★閾値は外部パラメータで設定可能★
      // 価格がSMA20より上 → 上昇トレンド
      if(price > sma20 + m_D1TrendThreshold * point)
         return TREND_UP;
      else if(price < sma20 - m_D1TrendThreshold * point)
         return TREND_DOWN;

      return TREND_NEUTRAL;
   }

   //--- Get current ADX values
   double GetADX_D1() { return m_CurrentADX_D1; }
   double GetADX_H4() { return m_CurrentADX_H4; }
   double GetADX_H1() { return m_CurrentADX_H1; }

   //--- Get trend from price position relative to SMA
   ENUM_TREND_DIRECTION GetTrendFromPrice(ENUM_TIMEFRAMES tf)
   {
      double price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      double sma = 0;

      if(tf == PERIOD_D1)
         sma = m_SMAManager.GetD1_SMA20();
      else if(tf == PERIOD_H4)
         sma = m_SMAManager.GetH4_SMA80();
      else if(tf == PERIOD_H1)
         sma = m_SMAManager.GetH1_SMA80();

      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);

      // ★閾値は外部パラメータで設定可能★
      if(price > sma + m_D1TrendThreshold * point)
         return TREND_UP;
      else if(price < sma - m_D1TrendThreshold * point)
         return TREND_DOWN;

      return TREND_NEUTRAL;
   }

   void UpdateWarState()
   {
      m_IsWarState = false;

      // War state only if D1 and H4 are directly opposing
      if(m_TrendD1 == TREND_UP && m_TrendH4 == TREND_DOWN)
         m_IsWarState = true;
      else if(m_TrendD1 == TREND_DOWN && m_TrendH4 == TREND_UP)
         m_IsWarState = true;
   }

   // Getters
   ENUM_TREND_DIRECTION GetTrendD1() { return m_TrendD1; }
   ENUM_TREND_DIRECTION GetTrendH4() { return m_TrendH4; }
   ENUM_TREND_DIRECTION GetTrendH1() { return m_TrendH1; }
   bool IsWarState() { return m_IsWarState; }

   CSMAManager* GetSMAManager() { return &m_SMAManager; }
   CDowSwingDetector* GetSwingDetector() { return &m_SwingDetector; }

   string GetTrendString()
   {
      if(m_UseADXFilter)
      {
         return StringFormat("D1=%s | H4=%s | H1=%s | War=%s | ADX(H4)=%.1f%s",
                             TrendToString(m_TrendD1),
                             TrendToString(m_TrendH4),
                             TrendToString(m_TrendH1),
                             m_IsWarState ? "YES" : "NO",
                             m_CurrentADX_H4,
                             IsTrendStrong() ? "" : " [WEAK]");
      }
      else
      {
         return StringFormat("D1=%s | H4=%s | H1=%s | War=%s",
                             TrendToString(m_TrendD1),
                             TrendToString(m_TrendH4),
                             TrendToString(m_TrendH1),
                             m_IsWarState ? "YES" : "NO");
      }
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
