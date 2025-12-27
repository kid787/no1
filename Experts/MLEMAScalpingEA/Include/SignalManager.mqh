//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|                     MTF Trend Scalping - Signal Module v5.0     |
//|                                                                  |
//|  Strategy:                                                       |
//|  - H1/H4 200 EMA determines trend direction                      |
//|  - M5 20 EMA pullback for entry                                  |
//|  - Only trade in trend direction                                 |
//|  - RSI confirmation for better entries                           |
//+------------------------------------------------------------------+
#property copyright "MTF Trend Scalping EA v5.0"
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
//| Signal Manager Class                                             |
//| MTF Trend Following with M5 Pullback Entries                     |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_entryTimeframe;     // M5 for entry
   ENUM_TIMEFRAMES   m_trendTimeframe;     // H1 or H4 for trend

   // Indicator handles
   int               m_trendEmaHandle;     // 200 EMA on H1/H4
   int               m_entryEmaHandle;     // 20 EMA on M5
   int               m_rsiHandle;          // RSI on M5
   int               m_atrHandle;          // ATR for SL/TP
   int               m_adxHandle;          // ADX for trend strength

   // EMA settings
   int               m_trendEmaPeriod;     // 200
   int               m_entryEmaPeriod;     // 20

   // RSI settings
   int               m_rsiPeriod;          // 14
   double            m_rsiOversold;        // 30
   double            m_rsiOverbought;      // 70

   // ADX settings
   int               m_adxPeriod;          // 14
   double            m_adxMinStrength;     // 20 minimum for trend

   // ATR settings
   int               m_atrPeriod;          // 14

   // Pullback settings
   double            m_pullbackTolerance;  // Pips tolerance for "at EMA"

   // Session filter (GMT times)
   int               m_gmtOffset;
   int               m_tradingStartGMT;    // 7 = London open
   int               m_tradingEndGMT;      // 20 = NY close

   // Current state
   ENUM_TREND_STATE  m_currentTrend;

   // Trade management
   datetime          m_lastTradeDate;
   int               m_tradesToday;
   int               m_maxTradesPerDay;

   // Cached values
   double            m_trendEmaValue;
   double            m_entryEmaValue;
   double            m_rsiValue;
   double            m_adxValue;
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
      m_adxHandle = INVALID_HANDLE;

      m_trendEmaPeriod = 200;
      m_entryEmaPeriod = 20;
      m_rsiPeriod = 14;
      m_rsiOversold = 30;
      m_rsiOverbought = 70;
      m_adxPeriod = 14;
      m_adxMinStrength = 20;
      m_atrPeriod = 14;

      m_pullbackTolerance = 10.0;  // 10 pips

      m_gmtOffset = 2;
      m_tradingStartGMT = 7;
      m_tradingEndGMT = 20;

      m_currentTrend = TREND_NONE;

      m_lastTradeDate = 0;
      m_tradesToday = 0;
      m_maxTradesPerDay = 3;

      m_trendEmaValue = 0;
      m_entryEmaValue = 0;
      m_rsiValue = 50;
      m_adxValue = 0;
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

      // Create trend EMA indicator (200 EMA on H1/H4)
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

      // Create ADX indicator
      m_adxHandle = iADX(m_symbol, m_trendTimeframe, m_adxPeriod);
      if(m_adxHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create ADX indicator");
         return false;
      }

      m_isInitialized = true;
      Print("Signal Manager initialized for MTF Trend Scalping");
      Print("Trend TF: ", EnumToString(m_trendTimeframe), " | Entry TF: ", EnumToString(m_entryTimeframe));
      Print("Trend EMA: ", m_trendEmaPeriod, " | Entry EMA: ", m_entryEmaPeriod);

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
      if(m_adxHandle != INVALID_HANDLE) { IndicatorRelease(m_adxHandle); m_adxHandle = INVALID_HANDLE; }
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Update all indicator values                                      |
   //+------------------------------------------------------------------+
   bool UpdateIndicators()
   {
      if(!m_isInitialized) return false;

      double trendEma[], entryEma[], rsi[], atr[], adx[];
      ArraySetAsSeries(trendEma, true);
      ArraySetAsSeries(entryEma, true);
      ArraySetAsSeries(rsi, true);
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(adx, true);

      // Get trend EMA
      if(CopyBuffer(m_trendEmaHandle, 0, 0, 3, trendEma) < 3) return false;
      m_trendEmaValue = trendEma[0];

      // Get entry EMA
      if(CopyBuffer(m_entryEmaHandle, 0, 0, 3, entryEma) < 3) return false;
      m_entryEmaValue = entryEma[0];

      // Get RSI
      if(CopyBuffer(m_rsiHandle, 0, 0, 3, rsi) < 3) return false;
      m_rsiValue = rsi[0];

      // Get ATR
      if(CopyBuffer(m_atrHandle, 0, 0, 3, atr) < 3) return false;
      m_atrValue = atr[0];

      // Get ADX (main line is buffer 0)
      if(CopyBuffer(m_adxHandle, 0, 0, 3, adx) < 3) return false;
      m_adxValue = adx[0];

      return true;
   }

   //+------------------------------------------------------------------+
   //| Determine trend from higher timeframe                            |
   //+------------------------------------------------------------------+
   ENUM_TREND_STATE GetTrend()
   {
      if(!UpdateIndicators()) return TREND_NONE;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      // Check ADX for trend strength
      if(m_adxValue < m_adxMinStrength)
      {
         m_currentTrend = TREND_NONE;
         return TREND_NONE;
      }

      // Price above 200 EMA = Bullish
      // Price below 200 EMA = Bearish
      double buffer = m_atrValue * 0.3;  // Small buffer to avoid whipsaws

      if(price > m_trendEmaValue + buffer)
      {
         m_currentTrend = TREND_BULLISH;
      }
      else if(price < m_trendEmaValue - buffer)
      {
         m_currentTrend = TREND_BEARISH;
      }
      else
      {
         m_currentTrend = TREND_NONE;  // Too close to EMA
      }

      return m_currentTrend;
   }

   //+------------------------------------------------------------------+
   //| Check for pullback entry signal                                  |
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

      // Get current price and EMA
      double pipSize = GetPipSize();
      double tolerance = m_pullbackTolerance * pipSize;

      // Check for pullback entry
      if(trend == TREND_BULLISH)
      {
         return CheckBuyPullback(tolerance);
      }
      else if(trend == TREND_BEARISH)
      {
         return CheckSellPullback(tolerance);
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Check for BUY pullback entry                                     |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE CheckBuyPullback(double tolerance)
   {
      // In uptrend, wait for pullback to 20 EMA
      // Entry when price bounces up from EMA with RSI confirmation

      double ema = m_entryEmaValue;

      // Check if price bounced from EMA (previous candle low touched EMA, close above)
      double low[], close[], open[], high[];
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);

      if(CopyLow(m_symbol, m_entryTimeframe, 0, 5, low) < 5) return SIGNAL_NONE;
      if(CopyClose(m_symbol, m_entryTimeframe, 0, 5, close) < 5) return SIGNAL_NONE;
      if(CopyOpen(m_symbol, m_entryTimeframe, 0, 5, open) < 5) return SIGNAL_NONE;
      if(CopyHigh(m_symbol, m_entryTimeframe, 0, 5, high) < 5) return SIGNAL_NONE;

      // Conditions for BUY (check bar[1] - completed bar):
      // 1. Price pulled back to 20 EMA (low touched or came close to EMA)
      // 2. Bullish candle (close > open)
      // 3. RSI not overbought (< 70) and recovering from lower levels
      // 4. Close above EMA

      bool lowTouchedEma = (low[1] <= ema + tolerance && low[1] >= ema - tolerance * 2);
      bool bullishCandle = (close[1] > open[1]);
      bool closeAboveEma = (close[1] > ema);
      bool rsiOk = (m_rsiValue < m_rsiOverbought && m_rsiValue > 35);

      // Additional: Check that bar[2] or bar[3] came down to EMA (confirming pullback)
      bool hadPullback = (low[2] <= ema + tolerance * 1.5) || (low[3] <= ema + tolerance * 1.5);

      if((lowTouchedEma || hadPullback) && bullishCandle && closeAboveEma && rsiOk)
      {
         Print("=== BUY Signal Generated ===");
         Print("Trend: BULLISH | H1 EMA(200): ", DoubleToString(m_trendEmaValue, 5));
         Print("M5 EMA(20): ", DoubleToString(ema, 5), " | RSI: ", DoubleToString(m_rsiValue, 1));
         Print("ADX: ", DoubleToString(m_adxValue, 1), " | Low[1]: ", DoubleToString(low[1], 5));
         return SIGNAL_BUY;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Check for SELL pullback entry                                    |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE CheckSellPullback(double tolerance)
   {
      // In downtrend, wait for pullback to 20 EMA
      // Entry when price bounces down from EMA with RSI confirmation

      double ema = m_entryEmaValue;

      // Check if price bounced from EMA (previous candle high touched EMA, close below)
      double high[], close[], open[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(low, true);

      if(CopyHigh(m_symbol, m_entryTimeframe, 0, 5, high) < 5) return SIGNAL_NONE;
      if(CopyClose(m_symbol, m_entryTimeframe, 0, 5, close) < 5) return SIGNAL_NONE;
      if(CopyOpen(m_symbol, m_entryTimeframe, 0, 5, open) < 5) return SIGNAL_NONE;
      if(CopyLow(m_symbol, m_entryTimeframe, 0, 5, low) < 5) return SIGNAL_NONE;

      // Conditions for SELL (check bar[1] - completed bar):
      // 1. Price pulled back to 20 EMA (high touched or came close to EMA)
      // 2. Bearish candle (close < open)
      // 3. RSI not oversold (> 30) and coming down from higher levels
      // 4. Close below EMA

      bool highTouchedEma = (high[1] >= ema - tolerance && high[1] <= ema + tolerance * 2);
      bool bearishCandle = (close[1] < open[1]);
      bool closeBelowEma = (close[1] < ema);
      bool rsiOk = (m_rsiValue > m_rsiOversold && m_rsiValue < 65);

      // Additional: Check that bar[2] or bar[3] came up to EMA (confirming pullback)
      bool hadPullback = (high[2] >= ema - tolerance * 1.5) || (high[3] >= ema - tolerance * 1.5);

      if((highTouchedEma || hadPullback) && bearishCandle && closeBelowEma && rsiOk)
      {
         Print("=== SELL Signal Generated ===");
         Print("Trend: BEARISH | H1 EMA(200): ", DoubleToString(m_trendEmaValue, 5));
         Print("M5 EMA(20): ", DoubleToString(ema, 5), " | RSI: ", DoubleToString(m_rsiValue, 1));
         Print("ADX: ", DoubleToString(m_adxValue, 1), " | High[1]: ", DoubleToString(high[1], 5));
         return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Calculate dynamic SL based on ATR and recent swing              |
   //+------------------------------------------------------------------+
   double CalculateSL(ENUM_SIGNAL_TYPE signal)
   {
      double price = (signal == SIGNAL_BUY) ?
                     SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                     SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double pipSize = GetPipSize();

      // SL based on ATR (1.5x ATR)
      double atrSL = m_atrValue * 1.5;

      // Also check recent swing low/high
      double swingSL = GetSwingSL(signal);

      // Use the larger of the two for safety
      double slDistance = MathMax(atrSL, swingSL);

      // Minimum SL of 15 pips, maximum of 50 pips
      double minSL = 15 * pipSize;
      double maxSL = 50 * pipSize;

      slDistance = MathMax(minSL, MathMin(maxSL, slDistance));

      if(signal == SIGNAL_BUY)
         m_lastSL = price - slDistance;
      else
         m_lastSL = price + slDistance;

      return m_lastSL;
   }

   //+------------------------------------------------------------------+
   //| Get swing low/high for SL                                        |
   //+------------------------------------------------------------------+
   double GetSwingSL(ENUM_SIGNAL_TYPE signal)
   {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pipSize = GetPipSize();

      if(signal == SIGNAL_BUY)
      {
         // Find recent swing low
         double low[];
         ArraySetAsSeries(low, true);
         if(CopyLow(m_symbol, m_entryTimeframe, 0, 20, low) < 20)
            return m_atrValue * 1.5;

         double swingLow = low[0];
         for(int i = 1; i < 20; i++)
         {
            if(low[i] < swingLow) swingLow = low[i];
         }

         return price - swingLow + (5 * pipSize);  // 5 pip buffer
      }
      else
      {
         // Find recent swing high
         double high[];
         ArraySetAsSeries(high, true);
         if(CopyHigh(m_symbol, m_entryTimeframe, 0, 20, high) < 20)
            return m_atrValue * 1.5;

         double swingHigh = high[0];
         for(int i = 1; i < 20; i++)
         {
            if(high[i] > swingHigh) swingHigh = high[i];
         }

         return swingHigh - price + (5 * pipSize);  // 5 pip buffer
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate TP based on R:R ratio                                  |
   //+------------------------------------------------------------------+
   double CalculateTP(double entryPrice, double slPrice, ENUM_SIGNAL_TYPE signal, double rrRatio)
   {
      double slDistance = MathAbs(entryPrice - slPrice);
      double tpDistance = slDistance * rrRatio;

      if(signal == SIGNAL_BUY)
         m_lastTP = entryPrice + tpDistance;
      else
         m_lastTP = entryPrice - tpDistance;

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

      // Trading during London + NY sessions (GMT 7-20)
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

      if(digits == 3 || digits == 5)
         return point * 10.0;
      else
         return point;
   }

   //+------------------------------------------------------------------+
   //| Setters                                                          |
   //+------------------------------------------------------------------+
   void SetGMTOffset(int offset) { m_gmtOffset = offset; }
   void SetTradingHours(int startGMT, int endGMT)
   {
      m_tradingStartGMT = startGMT;
      m_tradingEndGMT = endGMT;
   }
   void SetMaxTradesPerDay(int max) { m_maxTradesPerDay = max; }
   void SetPullbackTolerance(double pips) { m_pullbackTolerance = pips; }
   void SetRSILevels(double oversold, double overbought)
   {
      m_rsiOversold = oversold;
      m_rsiOverbought = overbought;
   }
   void SetADXMinStrength(double strength) { m_adxMinStrength = strength; }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   double GetTrendEMA() { return m_trendEmaValue; }
   double GetEntryEMA() { return m_entryEmaValue; }
   double GetRSI() { return m_rsiValue; }
   double GetADX() { return m_adxValue; }
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

   //+------------------------------------------------------------------+
   //| Get trend as string for display                                  |
   //+------------------------------------------------------------------+
   string GetTrendString()
   {
      switch(m_currentTrend)
      {
         case TREND_BULLISH: return "BULLISH (BUY Only)";
         case TREND_BEARISH: return "BEARISH (SELL Only)";
         default: return "NO TREND (No Trade)";
      }
   }

   //+------------------------------------------------------------------+
   //| Legacy compatibility methods                                     |
   //+------------------------------------------------------------------+
   double GetAsianHigh() { return 0; }
   double GetAsianLow() { return 0; }
   double GetRangeSize() { return 0; }
   bool IsRangeCalculated() { return false; }
   bool IsBuyTakenToday() { return false; }
   bool IsSellTakenToday() { return false; }
   int GetAsianStartServer() { return 0; }
   int GetAsianEndServer() { return 0; }
   int GetLondonStartServer() { return m_tradingStartGMT + m_gmtOffset; }
   int GetLondonEndServer() { return m_tradingEndGMT + m_gmtOffset; }
   bool IsLondonTradingTime() { return IsTradingTime(); }
   void SetSessionTimesGMT(int a, int b, int c, int d) { m_tradingStartGMT = c; m_tradingEndGMT = d; }
   void SetBreakoutParams(double a, double b, double c) { }
   double CalculateDynamicSL(ENUM_SIGNAL_TYPE signal) { return CalculateSL(signal); }
};
