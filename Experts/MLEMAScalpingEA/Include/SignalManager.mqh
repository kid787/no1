//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|                  Granville's Law + Daily Pivot Strategy v6.0    |
//|                                                                  |
//|  Strategy:                                                       |
//|  - H1 75 EMA for trend direction (with slope confirmation)       |
//|  - M5 20 EMA for Granville Buy3/Sell3 bounce entry              |
//|  - Daily Pivot levels for Take Profit                            |
//|  - RSI confirmation for entry quality                            |
//|                                                                  |
//|  Granville Buy 3: In uptrend, price approaches EMA from above   |
//|                   but does NOT cross below, then bounces up      |
//|  Granville Sell 3: In downtrend, price approaches EMA from below|
//|                    but does NOT cross above, then bounces down   |
//+------------------------------------------------------------------+
#property copyright "Granville Pivot EA v6.0"
#property strict

//+------------------------------------------------------------------+
//| Signal Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1
};

//+------------------------------------------------------------------+
//| Trend State Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_TREND_STATE
{
   TREND_NONE = 0,
   TREND_BULLISH = 1,
   TREND_BEARISH = -1
};

//+------------------------------------------------------------------+
//| Pivot Levels Structure                                           |
//+------------------------------------------------------------------+
struct SPivotLevels
{
   double PP;      // Pivot Point
   double R1, R2, R3;  // Resistance levels
   double S1, S2, S3;  // Support levels
   datetime calcDate;  // Date calculated
};

//+------------------------------------------------------------------+
//| Signal Manager Class                                             |
//| Granville Buy3/Sell3 with Daily Pivot TP                         |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_entryTimeframe;     // M5 for entry
   ENUM_TIMEFRAMES   m_trendTimeframe;     // H1 for trend

   // Indicator handles
   int               m_trendEmaHandle;     // 75 EMA on H1
   int               m_entryEmaHandle;     // 20 EMA on M5
   int               m_rsiHandle;          // RSI on M5
   int               m_atrHandle;          // ATR for SL

   // EMA settings
   int               m_trendEmaPeriod;     // 75 (faster than 200 for trend)
   int               m_entryEmaPeriod;     // 20

   // RSI settings
   int               m_rsiPeriod;
   double            m_rsiOversold;
   double            m_rsiOverbought;

   // ATR settings
   int               m_atrPeriod;

   // Granville settings
   double            m_bounceZonePips;     // Pips from EMA considered "near"
   int               m_emaSlopeBars;       // Bars to check for EMA slope

   // Session filter (GMT times)
   int               m_gmtOffset;
   int               m_tradingStartGMT;
   int               m_tradingEndGMT;

   // Current state
   ENUM_TREND_STATE  m_currentTrend;
   SPivotLevels      m_pivotLevels;

   // Trade management
   datetime          m_lastTradeDate;
   int               m_tradesToday;
   int               m_maxTradesPerDay;

   // Cached values
   double            m_trendEmaValue;
   double            m_trendEmaPrev;       // Previous EMA for slope
   double            m_entryEmaValue;
   double            m_entryEmaPrev;
   double            m_rsiValue;
   double            m_atrValue;
   double            m_lastSL;
   double            m_lastTP;

   bool              m_isInitialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CSignalManager()
   {
      m_symbol = "";
      m_entryTimeframe = PERIOD_M5;
      m_trendTimeframe = PERIOD_H1;

      m_trendEmaHandle = INVALID_HANDLE;
      m_entryEmaHandle = INVALID_HANDLE;
      m_rsiHandle = INVALID_HANDLE;
      m_atrHandle = INVALID_HANDLE;

      m_trendEmaPeriod = 75;
      m_entryEmaPeriod = 20;
      m_rsiPeriod = 14;
      m_rsiOversold = 30;
      m_rsiOverbought = 70;
      m_atrPeriod = 14;

      m_bounceZonePips = 15.0;  // Within 15 pips of EMA
      m_emaSlopeBars = 5;

      m_gmtOffset = 2;
      m_tradingStartGMT = 7;
      m_tradingEndGMT = 20;

      m_currentTrend = TREND_NONE;
      ZeroMemory(m_pivotLevels);

      m_lastTradeDate = 0;
      m_tradesToday = 0;
      m_maxTradesPerDay = 3;

      m_trendEmaValue = 0;
      m_trendEmaPrev = 0;
      m_entryEmaValue = 0;
      m_entryEmaPrev = 0;
      m_rsiValue = 50;
      m_atrValue = 0;
      m_lastSL = 0;
      m_lastTP = 0;

      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
   ~CSignalManager()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                       |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES trendTF,
             int trendEmaPeriod, int entryEmaPeriod, int atrPeriod)
   {
      m_symbol = symbol;
      m_entryTimeframe = entryTF;
      m_trendTimeframe = trendTF;
      m_trendEmaPeriod = trendEmaPeriod;
      m_entryEmaPeriod = entryEmaPeriod;
      m_atrPeriod = atrPeriod;

      // Create trend EMA indicator (75 EMA on H1)
      m_trendEmaHandle = iMA(m_symbol, m_trendTimeframe, m_trendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(m_trendEmaHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create trend EMA indicator");
         return false;
      }

      // Create entry EMA indicator (20 EMA on M5)
      m_entryEmaHandle = iMA(m_symbol, m_entryTimeframe, m_entryEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(m_entryEmaHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create entry EMA indicator");
         return false;
      }

      // Create RSI indicator
      m_rsiHandle = iRSI(m_symbol, m_entryTimeframe, m_rsiPeriod, PRICE_CLOSE);
      if(m_rsiHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create RSI indicator");
         return false;
      }

      // Create ATR indicator
      m_atrHandle = iATR(m_symbol, m_entryTimeframe, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create ATR indicator");
         return false;
      }

      m_isInitialized = true;
      Print("=== Granville Pivot Signal Manager v6.0 ===");
      Print("Trend TF: ", EnumToString(m_trendTimeframe), " EMA(", m_trendEmaPeriod, ")");
      Print("Entry TF: ", EnumToString(m_entryTimeframe), " EMA(", m_entryEmaPeriod, ")");
      Print("Bounce Zone: ", m_bounceZonePips, " pips");

      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize                                                     |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_trendEmaHandle != INVALID_HANDLE) { IndicatorRelease(m_trendEmaHandle); m_trendEmaHandle = INVALID_HANDLE; }
      if(m_entryEmaHandle != INVALID_HANDLE) { IndicatorRelease(m_entryEmaHandle); m_entryEmaHandle = INVALID_HANDLE; }
      if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
      if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Update all indicator values                                      |
   //+------------------------------------------------------------------+
   bool UpdateIndicators()
   {
      if(!m_isInitialized) return false;

      double trendEma[], entryEma[], rsi[], atr[];
      ArraySetAsSeries(trendEma, true);
      ArraySetAsSeries(entryEma, true);
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(atr, true);

      // Get trend EMA (need more bars for slope calculation)
      if(CopyBuffer(m_trendEmaHandle, 0, 0, m_emaSlopeBars + 1, trendEma) < m_emaSlopeBars + 1) return false;
      m_trendEmaValue = trendEma[0];
      m_trendEmaPrev = trendEma[m_emaSlopeBars];

      // Get entry EMA
      if(CopyBuffer(m_entryEmaHandle, 0, 0, 5, entryEma) < 5) return false;
      m_entryEmaValue = entryEma[0];
      m_entryEmaPrev = entryEma[3];

      // Get RSI
      if(CopyBuffer(m_rsiHandle, 0, 0, 3, rsi) < 3) return false;
      m_rsiValue = rsi[0];

      // Get ATR
      if(CopyBuffer(m_atrHandle, 0, 0, 3, atr) < 3) return false;
      m_atrValue = atr[0];

      // Update pivot levels daily
      UpdatePivotLevels();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate Daily Pivot Levels                                     |
   //+------------------------------------------------------------------+
   void UpdatePivotLevels()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

      // Only recalculate if new day
      if(m_pivotLevels.calcDate == today) return;

      // Get yesterday's OHLC from D1
      double high[], low[], close[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);

      if(CopyHigh(m_symbol, PERIOD_D1, 1, 1, high) < 1) return;
      if(CopyLow(m_symbol, PERIOD_D1, 1, 1, low) < 1) return;
      if(CopyClose(m_symbol, PERIOD_D1, 1, 1, close) < 1) return;

      double h = high[0];
      double l = low[0];
      double c = close[0];

      // Standard Pivot calculation
      m_pivotLevels.PP = (h + l + c) / 3;
      m_pivotLevels.R1 = 2 * m_pivotLevels.PP - l;
      m_pivotLevels.S1 = 2 * m_pivotLevels.PP - h;
      m_pivotLevels.R2 = m_pivotLevels.PP + (h - l);
      m_pivotLevels.S2 = m_pivotLevels.PP - (h - l);
      m_pivotLevels.R3 = h + 2 * (m_pivotLevels.PP - l);
      m_pivotLevels.S3 = l - 2 * (h - m_pivotLevels.PP);
      m_pivotLevels.calcDate = today;

      Print("=== Daily Pivot Levels Updated ===");
      Print("PP: ", DoubleToString(m_pivotLevels.PP, 5));
      Print("R1: ", DoubleToString(m_pivotLevels.R1, 5), " | S1: ", DoubleToString(m_pivotLevels.S1, 5));
      Print("R2: ", DoubleToString(m_pivotLevels.R2, 5), " | S2: ", DoubleToString(m_pivotLevels.S2, 5));
   }

   //+------------------------------------------------------------------+
   //| Determine trend from higher timeframe with slope                 |
   //+------------------------------------------------------------------+
   ENUM_TREND_STATE GetTrend()
   {
      if(!UpdateIndicators()) return TREND_NONE;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pipSize = GetPipSize();

      // Check EMA slope (must be clearly trending)
      double slopePips = (m_trendEmaValue - m_trendEmaPrev) / pipSize;

      // Minimum slope threshold (EMA must have moved at least 3 pips in 5 bars)
      double minSlope = 3.0;

      // Bullish: Price above EMA AND EMA is rising
      if(price > m_trendEmaValue && slopePips > minSlope)
      {
         m_currentTrend = TREND_BULLISH;
      }
      // Bearish: Price below EMA AND EMA is falling
      else if(price < m_trendEmaValue && slopePips < -minSlope)
      {
         m_currentTrend = TREND_BEARISH;
      }
      else
      {
         m_currentTrend = TREND_NONE;
      }

      return m_currentTrend;
   }

   //+------------------------------------------------------------------+
   //| Check for Granville signal                                       |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(!m_isInitialized) return SIGNAL_NONE;

      // Check trading time
      if(!IsTradingTime()) return SIGNAL_NONE;

      // Check daily trade limit
      CheckDailyReset();
      if(m_tradesToday >= m_maxTradesPerDay) return SIGNAL_NONE;

      // Update indicators
      if(!UpdateIndicators()) return SIGNAL_NONE;

      // Get trend direction
      ENUM_TREND_STATE trend = GetTrend();
      if(trend == TREND_NONE) return SIGNAL_NONE;

      // Check for Granville bounce signals
      if(trend == TREND_BULLISH)
      {
         return CheckGranvilleBuy3();
      }
      else if(trend == TREND_BEARISH)
      {
         return CheckGranvilleSell3();
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Granville Buy 3: Bounce off rising EMA without crossing          |
   //| - Price is above rising 20 EMA                                   |
   //| - Price pulls back TOWARD EMA but does NOT cross below           |
   //| - Bullish candle confirms bounce                                 |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE CheckGranvilleBuy3()
   {
      double ema = m_entryEmaValue;
      double pipSize = GetPipSize();
      double bounceZone = m_bounceZonePips * pipSize;

      // Get recent price data
      double high[], low[], close[], open[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);

      if(CopyHigh(m_symbol, m_entryTimeframe, 0, 6, high) < 6) return SIGNAL_NONE;
      if(CopyLow(m_symbol, m_entryTimeframe, 0, 6, low) < 6) return SIGNAL_NONE;
      if(CopyClose(m_symbol, m_entryTimeframe, 0, 6, close) < 6) return SIGNAL_NONE;
      if(CopyOpen(m_symbol, m_entryTimeframe, 0, 6, open) < 6) return SIGNAL_NONE;

      // Get EMA values for each bar
      double emaValues[];
      ArraySetAsSeries(emaValues, true);
      if(CopyBuffer(m_entryEmaHandle, 0, 0, 6, emaValues) < 6) return SIGNAL_NONE;

      // Check EMA is rising (entry EMA slope)
      bool emaRising = (emaValues[0] > emaValues[3]);
      if(!emaRising) return SIGNAL_NONE;

      // GRANVILLE BUY 3 CONDITIONS:
      // 1. Bar[2] or Bar[3]: Price came close to EMA (pullback)
      // 2. Bar[1]: Low approached but DID NOT cross below EMA
      // 3. Bar[1]: Bullish candle (close > open) with close above EMA
      // 4. RSI is not overbought and shows recovery

      bool hadPullback = false;
      for(int i = 2; i <= 4; i++)
      {
         // Check if any recent bar came close to EMA (within bounce zone)
         if(low[i] <= emaValues[i] + bounceZone && low[i] >= emaValues[i] - pipSize * 3)
         {
            hadPullback = true;
            break;
         }
      }

      if(!hadPullback) return SIGNAL_NONE;

      // Bar[1] conditions (confirmed candle)
      bool lowNearEma = (low[1] <= emaValues[1] + bounceZone);
      bool didNotCross = (low[1] >= emaValues[1] - pipSize * 5);  // Allow tiny wick below
      bool bullishCandle = (close[1] > open[1]);
      bool closeAboveEma = (close[1] > emaValues[1]);
      bool goodCandleSize = (close[1] - open[1] > pipSize * 3);  // Meaningful bullish candle

      // RSI confirmation
      bool rsiOk = (m_rsiValue > 40 && m_rsiValue < 65);  // Not overbought, recovered from low

      if(lowNearEma && didNotCross && bullishCandle && closeAboveEma && goodCandleSize && rsiOk)
      {
         Print("=== GRANVILLE BUY 3 Signal ===");
         Print("H1 Trend: BULLISH | EMA Slope: RISING");
         Print("M5 EMA(20): ", DoubleToString(ema, 5));
         Print("Bar[1] Low: ", DoubleToString(low[1], 5), " (did not cross below)");
         Print("Bar[1] Close: ", DoubleToString(close[1], 5), " (above EMA)");
         Print("RSI: ", DoubleToString(m_rsiValue, 1));
         Print("Target R1: ", DoubleToString(m_pivotLevels.R1, 5));
         return SIGNAL_BUY;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Granville Sell 3: Bounce off falling EMA without crossing        |
   //| - Price is below falling 20 EMA                                  |
   //| - Price pulls back TOWARD EMA but does NOT cross above           |
   //| - Bearish candle confirms bounce                                 |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE CheckGranvilleSell3()
   {
      double ema = m_entryEmaValue;
      double pipSize = GetPipSize();
      double bounceZone = m_bounceZonePips * pipSize;

      // Get recent price data
      double high[], low[], close[], open[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);

      if(CopyHigh(m_symbol, m_entryTimeframe, 0, 6, high) < 6) return SIGNAL_NONE;
      if(CopyLow(m_symbol, m_entryTimeframe, 0, 6, low) < 6) return SIGNAL_NONE;
      if(CopyClose(m_symbol, m_entryTimeframe, 0, 6, close) < 6) return SIGNAL_NONE;
      if(CopyOpen(m_symbol, m_entryTimeframe, 0, 6, open) < 6) return SIGNAL_NONE;

      // Get EMA values for each bar
      double emaValues[];
      ArraySetAsSeries(emaValues, true);
      if(CopyBuffer(m_entryEmaHandle, 0, 0, 6, emaValues) < 6) return SIGNAL_NONE;

      // Check EMA is falling (entry EMA slope)
      bool emaFalling = (emaValues[0] < emaValues[3]);
      if(!emaFalling) return SIGNAL_NONE;

      // GRANVILLE SELL 3 CONDITIONS:
      // 1. Bar[2] or Bar[3]: Price came close to EMA (pullback)
      // 2. Bar[1]: High approached but DID NOT cross above EMA
      // 3. Bar[1]: Bearish candle (close < open) with close below EMA
      // 4. RSI is not oversold and shows decline

      bool hadPullback = false;
      for(int i = 2; i <= 4; i++)
      {
         // Check if any recent bar came close to EMA (within bounce zone)
         if(high[i] >= emaValues[i] - bounceZone && high[i] <= emaValues[i] + pipSize * 3)
         {
            hadPullback = true;
            break;
         }
      }

      if(!hadPullback) return SIGNAL_NONE;

      // Bar[1] conditions (confirmed candle)
      bool highNearEma = (high[1] >= emaValues[1] - bounceZone);
      bool didNotCross = (high[1] <= emaValues[1] + pipSize * 5);  // Allow tiny wick above
      bool bearishCandle = (close[1] < open[1]);
      bool closeBelowEma = (close[1] < emaValues[1]);
      bool goodCandleSize = (open[1] - close[1] > pipSize * 3);  // Meaningful bearish candle

      // RSI confirmation
      bool rsiOk = (m_rsiValue < 60 && m_rsiValue > 35);  // Not oversold, coming from high

      if(highNearEma && didNotCross && bearishCandle && closeBelowEma && goodCandleSize && rsiOk)
      {
         Print("=== GRANVILLE SELL 3 Signal ===");
         Print("H1 Trend: BEARISH | EMA Slope: FALLING");
         Print("M5 EMA(20): ", DoubleToString(ema, 5));
         Print("Bar[1] High: ", DoubleToString(high[1], 5), " (did not cross above)");
         Print("Bar[1] Close: ", DoubleToString(close[1], 5), " (below EMA)");
         Print("RSI: ", DoubleToString(m_rsiValue, 1));
         Print("Target S1: ", DoubleToString(m_pivotLevels.S1, 5));
         return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Calculate SL based on swing and ATR                              |
   //+------------------------------------------------------------------+
   double CalculateSL(ENUM_SIGNAL_TYPE signal)
   {
      double price = (signal == SIGNAL_BUY) ?
                     SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                     SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double pipSize = GetPipSize();

      // SL below/above recent swing + ATR buffer
      double swingSL = GetSwingSL(signal);
      double atrSL = m_atrValue * 1.5;

      double slDistance = MathMax(swingSL, atrSL);

      // Minimum 15 pips, maximum 40 pips
      double minSL = 15 * pipSize;
      double maxSL = 40 * pipSize;
      slDistance = MathMax(minSL, MathMin(maxSL, slDistance));

      if(signal == SIGNAL_BUY)
         m_lastSL = price - slDistance;
      else
         m_lastSL = price + slDistance;

      return m_lastSL;
   }

   //+------------------------------------------------------------------+
   //| Get swing SL distance                                            |
   //+------------------------------------------------------------------+
   double GetSwingSL(ENUM_SIGNAL_TYPE signal)
   {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pipSize = GetPipSize();

      if(signal == SIGNAL_BUY)
      {
         double low[];
         ArraySetAsSeries(low, true);
         if(CopyLow(m_symbol, m_entryTimeframe, 0, 15, low) < 15)
            return m_atrValue * 1.5;

         double swingLow = low[0];
         for(int i = 1; i < 15; i++)
            if(low[i] < swingLow) swingLow = low[i];

         return price - swingLow + (3 * pipSize);
      }
      else
      {
         double high[];
         ArraySetAsSeries(high, true);
         if(CopyHigh(m_symbol, m_entryTimeframe, 0, 15, high) < 15)
            return m_atrValue * 1.5;

         double swingHigh = high[0];
         for(int i = 1; i < 15; i++)
            if(high[i] > swingHigh) swingHigh = high[i];

         return swingHigh - price + (3 * pipSize);
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate TP using Daily Pivot levels                            |
   //+------------------------------------------------------------------+
   double CalculateTP(double entryPrice, double slPrice, ENUM_SIGNAL_TYPE signal, double rrRatio)
   {
      double pipSize = GetPipSize();
      double slDistance = MathAbs(entryPrice - slPrice);

      if(signal == SIGNAL_BUY)
      {
         // For BUY: Target R1 or R2 depending on distance
         double targetR1 = m_pivotLevels.R1;
         double targetR2 = m_pivotLevels.R2;

         // Use R1 if it gives at least 1.5 RR, otherwise use R2
         double distToR1 = targetR1 - entryPrice;
         double distToR2 = targetR2 - entryPrice;

         if(distToR1 > slDistance * 1.5 && distToR1 > 0)
         {
            m_lastTP = targetR1;
         }
         else if(distToR2 > slDistance * 1.5 && distToR2 > 0)
         {
            m_lastTP = targetR2;
         }
         else
         {
            // Fallback to fixed RR
            m_lastTP = entryPrice + slDistance * rrRatio;
         }
      }
      else
      {
         // For SELL: Target S1 or S2 depending on distance
         double targetS1 = m_pivotLevels.S1;
         double targetS2 = m_pivotLevels.S2;

         double distToS1 = entryPrice - targetS1;
         double distToS2 = entryPrice - targetS2;

         if(distToS1 > slDistance * 1.5 && distToS1 > 0)
         {
            m_lastTP = targetS1;
         }
         else if(distToS2 > slDistance * 1.5 && distToS2 > 0)
         {
            m_lastTP = targetS2;
         }
         else
         {
            // Fallback to fixed RR
            m_lastTP = entryPrice - slDistance * rrRatio;
         }
      }

      return m_lastTP;
   }

   //+------------------------------------------------------------------+
   //| Check if current time is within trading hours                    |
   //+------------------------------------------------------------------+
   bool IsTradingTime()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      int serverHour = dt.hour;
      int gmtHour = serverHour - m_gmtOffset;
      if(gmtHour < 0) gmtHour += 24;
      if(gmtHour >= 24) gmtHour -= 24;

      return (gmtHour >= m_tradingStartGMT && gmtHour < m_tradingEndGMT);
   }

   //+------------------------------------------------------------------+
   //| Check and reset daily trade counter                              |
   //+------------------------------------------------------------------+
   void CheckDailyReset()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime today = StructToTime(dt) - dt.hour * 3600 - dt.min * 60 - dt.sec;

      if(today > m_lastTradeDate)
      {
         m_tradesToday = 0;
         m_lastTradeDate = today;
      }
   }

   //+------------------------------------------------------------------+
   //| Record trade taken                                               |
   //+------------------------------------------------------------------+
   void MarkTradeTaken(ENUM_SIGNAL_TYPE signal = SIGNAL_NONE)
   {
      m_tradesToday++;
   }

   //+------------------------------------------------------------------+
   //| Get pip size                                                     |
   //+------------------------------------------------------------------+
   double GetPipSize()
   {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
   }

   //+------------------------------------------------------------------+
   //| Setters                                                          |
   //+------------------------------------------------------------------+
   void SetGMTOffset(int offset) { m_gmtOffset = offset; }
   void SetTradingHours(int startGMT, int endGMT) { m_tradingStartGMT = startGMT; m_tradingEndGMT = endGMT; }
   void SetMaxTradesPerDay(int max) { m_maxTradesPerDay = max; }
   void SetBounceZone(double pips) { m_bounceZonePips = pips; }
   void SetRSILevels(double oversold, double overbought) { m_rsiOversold = oversold; m_rsiOverbought = overbought; }
   void SetPullbackTolerance(double pips) { m_bounceZonePips = pips; }
   void SetADXMinStrength(double strength) { }  // Not used in v6.0

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   double GetTrendEMA() { return m_trendEmaValue; }
   double GetEntryEMA() { return m_entryEmaValue; }
   double GetRSI() { return m_rsiValue; }
   double GetADX() { return 0; }  // Not used
   double GetATR() { return m_atrValue; }
   ENUM_TREND_STATE GetCurrentTrend() { return m_currentTrend; }
   int GetTradesToday() { return m_tradesToday; }
   int GetMaxTradesPerDay() { return m_maxTradesPerDay; }
   double GetLastSL() { return m_lastSL; }
   double GetLastTP() { return m_lastTP; }
   bool IsInitialized() { return m_isInitialized; }
   int GetTradingStartGMT() { return m_tradingStartGMT; }
   int GetTradingEndGMT() { return m_tradingEndGMT; }
   ENUM_TIMEFRAMES GetTrendTimeframe() { return m_trendTimeframe; }
   ENUM_TIMEFRAMES GetEntryTimeframe() { return m_entryTimeframe; }
   int GetTrendEmaPeriod() { return m_trendEmaPeriod; }
   int GetEntryEmaPeriod() { return m_entryEmaPeriod; }

   // Pivot getters
   double GetPivotPP() { return m_pivotLevels.PP; }
   double GetPivotR1() { return m_pivotLevels.R1; }
   double GetPivotR2() { return m_pivotLevels.R2; }
   double GetPivotS1() { return m_pivotLevels.S1; }
   double GetPivotS2() { return m_pivotLevels.S2; }

   //+------------------------------------------------------------------+
   //| Get trend as string for display                                  |
   //+------------------------------------------------------------------+
   string GetTrendString()
   {
      switch(m_currentTrend)
      {
         case TREND_BULLISH: return "BULLISH - Buy3 Only";
         case TREND_BEARISH: return "BEARISH - Sell3 Only";
         default: return "NO TREND";
      }
   }

   //+------------------------------------------------------------------+
   //| Legacy compatibility                                             |
   //+------------------------------------------------------------------+
   bool IsTradingTime2() { return IsTradingTime(); }
   double CalculateDynamicSL(ENUM_SIGNAL_TYPE s) { return CalculateSL(s); }
};
