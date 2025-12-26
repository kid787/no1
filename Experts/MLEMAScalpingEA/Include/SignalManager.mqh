//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|                          ML EMA Scalping EA - Signal Module      |
//|                         v3.1 - M1 Range Breakout + EMA Strategy  |
//+------------------------------------------------------------------+
#property copyright "ML EMA Scalping EA"
#property strict

//+------------------------------------------------------------------+
//| Signal types enumeration                                         |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,      // No signal
   SIGNAL_BUY = 1,       // Buy signal
   SIGNAL_SELL = -1      // Sell signal
};

//+------------------------------------------------------------------+
//| Trading session enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_TRADING_SESSION
{
   SESSION_ASIAN = 0,    // Tokyo session (0:00-9:00 UTC)
   SESSION_LONDON = 1,   // London session (7:00-16:00 UTC)
   SESSION_NEWYORK = 2,  // New York session (13:00-22:00 UTC)
   SESSION_OVERLAP = 3,  // London/NY overlap (13:00-16:00 UTC)
   SESSION_OFF = 4       // Off-market hours
};

//+------------------------------------------------------------------+
//| Signal Manager Class                                              |
//| Handles SMA/EMA + M1 Range Breakout strategy                     |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   // Indicator handles
   int               m_handleSMA900;
   int               m_handleEMA20;
   int               m_handleATR;
   int               m_handleADX;

   // Indicator buffers
   double            m_sma900Buffer[];
   double            m_ema20Buffer[];
   double            m_atrBuffer[];
   double            m_adxBuffer[];
   double            m_plusDIBuffer[];
   double            m_minusDIBuffer[];

   // Settings
   int               m_smaPeriod;
   int               m_emaPeriod;
   int               m_atrPeriod;
   int               m_adxPeriod;
   double            m_minADX;
   double            m_minATRMultiple;

   // M1 Range Breakout settings (changed from H1)
   bool              m_useRangeBreakout;
   int               m_rangeBars;          // Number of M1 bars for range
   double            m_breakoutBuffer;     // Buffer in pips for breakout confirmation
   double            m_rangeHigh;          // Current range high
   double            m_rangeLow;           // Current range low
   datetime          m_lastRangeCalcTime;

   // State tracking
   double            m_prevEMA20;
   double            m_prevClose;
   bool              m_isInitialized;

   // Session filter
   bool              m_useSessionFilter;
   bool              m_allowAsian;
   bool              m_allowLondon;
   bool              m_allowNewYork;

public:
   // Constructor
   CSignalManager()
   {
      m_symbol = "";
      m_timeframe = PERIOD_M5;
      m_smaPeriod = 900;
      m_emaPeriod = 20;
      m_atrPeriod = 14;
      m_adxPeriod = 14;
      m_minADX = 20.0;
      m_minATRMultiple = 0.5;
      m_prevEMA20 = 0;
      m_prevClose = 0;
      m_isInitialized = false;
      m_handleSMA900 = INVALID_HANDLE;
      m_handleEMA20 = INVALID_HANDLE;
      m_handleATR = INVALID_HANDLE;
      m_handleADX = INVALID_HANDLE;

      // M1 Range Breakout defaults (30 bars = 30 minutes on M1)
      m_useRangeBreakout = true;
      m_rangeBars = 30;           // Look at last 30 M1 bars (30 minutes)
      m_breakoutBuffer = 2.0;     // 2 pips buffer (smaller for M1)
      m_rangeHigh = 0;
      m_rangeLow = 0;
      m_lastRangeCalcTime = 0;

      // Session filter defaults
      m_useSessionFilter = true;
      m_allowAsian = false;
      m_allowLondon = true;
      m_allowNewYork = true;
   }

   // Destructor
   ~CSignalManager()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize the signal manager                                    |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES timeframe,
             int smaPeriod = 900, int emaPeriod = 20, int atrPeriod = 14)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_smaPeriod = smaPeriod;
      m_emaPeriod = emaPeriod;
      m_atrPeriod = atrPeriod;

      // Set array direction
      ArraySetAsSeries(m_sma900Buffer, true);
      ArraySetAsSeries(m_ema20Buffer, true);
      ArraySetAsSeries(m_atrBuffer, true);
      ArraySetAsSeries(m_adxBuffer, true);
      ArraySetAsSeries(m_plusDIBuffer, true);
      ArraySetAsSeries(m_minusDIBuffer, true);

      // Create indicator handles
      m_handleSMA900 = iMA(m_symbol, m_timeframe, m_smaPeriod, 0, MODE_SMA, PRICE_CLOSE);
      m_handleEMA20 = iMA(m_symbol, m_timeframe, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleATR = iATR(m_symbol, m_timeframe, m_atrPeriod);
      m_handleADX = iADX(m_symbol, m_timeframe, m_adxPeriod);

      if(m_handleSMA900 == INVALID_HANDLE ||
         m_handleEMA20 == INVALID_HANDLE ||
         m_handleATR == INVALID_HANDLE ||
         m_handleADX == INVALID_HANDLE)
      {
         Print("Error creating indicator handles: ", GetLastError());
         return false;
      }

      m_isInitialized = true;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize and release resources                               |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_handleSMA900 != INVALID_HANDLE) { IndicatorRelease(m_handleSMA900); m_handleSMA900 = INVALID_HANDLE; }
      if(m_handleEMA20 != INVALID_HANDLE) { IndicatorRelease(m_handleEMA20); m_handleEMA20 = INVALID_HANDLE; }
      if(m_handleATR != INVALID_HANDLE) { IndicatorRelease(m_handleATR); m_handleATR = INVALID_HANDLE; }
      if(m_handleADX != INVALID_HANDLE) { IndicatorRelease(m_handleADX); m_handleADX = INVALID_HANDLE; }
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Update indicator data                                            |
   //+------------------------------------------------------------------+
   bool UpdateData()
   {
      if(!m_isInitialized) return false;

      if(CopyBuffer(m_handleSMA900, 0, 0, 5, m_sma900Buffer) < 5) return false;
      if(CopyBuffer(m_handleEMA20, 0, 0, 5, m_ema20Buffer) < 5) return false;
      if(CopyBuffer(m_handleATR, 0, 0, 3, m_atrBuffer) < 3) return false;
      if(CopyBuffer(m_handleADX, 0, 0, 3, m_adxBuffer) < 3) return false;
      if(CopyBuffer(m_handleADX, 1, 0, 3, m_plusDIBuffer) < 3) return false;
      if(CopyBuffer(m_handleADX, 2, 0, 3, m_minusDIBuffer) < 3) return false;

      // Update M1 range
      UpdateM1Range();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate M1 Range (High/Low of last N M1 bars)                  |
   //+------------------------------------------------------------------+
   void UpdateM1Range()
   {
      datetime currentM1Bar = iTime(m_symbol, PERIOD_M1, 0);

      // Recalculate on every new M1 bar for more responsive range
      if(currentM1Bar == m_lastRangeCalcTime) return;

      m_lastRangeCalcTime = currentM1Bar;

      // Get high/low of the range (excluding current bar)
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);

      if(CopyHigh(m_symbol, PERIOD_M1, 1, m_rangeBars, highs) < m_rangeBars) return;
      if(CopyLow(m_symbol, PERIOD_M1, 1, m_rangeBars, lows) < m_rangeBars) return;

      // Find highest high and lowest low
      m_rangeHigh = highs[0];
      m_rangeLow = lows[0];

      for(int i = 1; i < m_rangeBars; i++)
      {
         if(highs[i] > m_rangeHigh) m_rangeHigh = highs[i];
         if(lows[i] < m_rangeLow) m_rangeLow = lows[i];
      }
   }

   //+------------------------------------------------------------------+
   //| Check for M1 Range Breakout UP                                   |
   //+------------------------------------------------------------------+
   bool CheckRangeBreakoutUp()
   {
      if(!m_useRangeBreakout) return true;  // If disabled, don't filter

      if(m_rangeHigh == 0) return false;

      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pipSize = GetPipSize();
      double buffer = m_breakoutBuffer * pipSize;

      // Price must be above range high + buffer
      return currentPrice > (m_rangeHigh + buffer);
   }

   //+------------------------------------------------------------------+
   //| Check for M1 Range Breakout DOWN                                 |
   //+------------------------------------------------------------------+
   bool CheckRangeBreakoutDown()
   {
      if(!m_useRangeBreakout) return true;

      if(m_rangeLow == 0) return false;

      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pipSize = GetPipSize();
      double buffer = m_breakoutBuffer * pipSize;

      // Price must be below range low - buffer
      return currentPrice < (m_rangeLow - buffer);
   }

   //+------------------------------------------------------------------+
   //| Get pip size                                                      |
   //+------------------------------------------------------------------+
   double GetPipSize()
   {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (digits == 3 || digits == 5) ? point * 10.0 : point;
   }

   //+------------------------------------------------------------------+
   //| Get current trading session                                       |
   //+------------------------------------------------------------------+
   ENUM_TRADING_SESSION GetCurrentSession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      if(hour >= 13 && hour < 16) return SESSION_OVERLAP;
      if(hour >= 7 && hour < 16) return SESSION_LONDON;
      if(hour >= 13 && hour < 22) return SESSION_NEWYORK;
      if(hour >= 0 && hour < 9) return SESSION_ASIAN;

      return SESSION_OFF;
   }

   //+------------------------------------------------------------------+
   //| Check if current session allows trading                          |
   //+------------------------------------------------------------------+
   bool IsSessionAllowed()
   {
      if(!m_useSessionFilter) return true;

      ENUM_TRADING_SESSION session = GetCurrentSession();

      switch(session)
      {
         case SESSION_OVERLAP: return true;
         case SESSION_LONDON: return m_allowLondon;
         case SESSION_NEWYORK: return m_allowNewYork;
         case SESSION_ASIAN: return m_allowAsian;
         default: return false;
      }
   }

   //+------------------------------------------------------------------+
   //| Accessors for indicator values                                    |
   //+------------------------------------------------------------------+
   double GetSMA900(int shift = 0) { return (shift < ArraySize(m_sma900Buffer)) ? m_sma900Buffer[shift] : 0; }
   double GetEMA20(int shift = 0) { return (shift < ArraySize(m_ema20Buffer)) ? m_ema20Buffer[shift] : 0; }
   double GetATR(int shift = 0) { return (shift < ArraySize(m_atrBuffer)) ? m_atrBuffer[shift] : 0; }
   double GetADX(int shift = 0) { return (shift < ArraySize(m_adxBuffer)) ? m_adxBuffer[shift] : 0; }
   double GetRangeHigh() { return m_rangeHigh; }
   double GetRangeLow() { return m_rangeLow; }
   double GetRangeSize() { return (m_rangeHigh - m_rangeLow) / GetPipSize(); }

   // Legacy accessors for compatibility
   double GetH1RangeHigh() { return m_rangeHigh; }
   double GetH1RangeLow() { return m_rangeLow; }
   double GetH1RangeSize() { return GetRangeSize(); }

   //+------------------------------------------------------------------+
   //| Check ADX strength                                                |
   //+------------------------------------------------------------------+
   bool IsStrongTrend() { return (ArraySize(m_adxBuffer) > 0) && (m_adxBuffer[0] >= m_minADX); }
   bool IsDIBullish() { return (ArraySize(m_plusDIBuffer) > 0) && (m_plusDIBuffer[0] > m_minusDIBuffer[0]); }
   bool IsDIBearish() { return (ArraySize(m_minusDIBuffer) > 0) && (m_minusDIBuffer[0] > m_plusDIBuffer[0]); }

   //+------------------------------------------------------------------+
   //| Trend checks                                                      |
   //+------------------------------------------------------------------+
   bool IsSMAUpTrend()
   {
      if(ArraySize(m_sma900Buffer) < 4) return false;
      double slope1 = m_sma900Buffer[0] - m_sma900Buffer[1];
      double slope2 = m_sma900Buffer[1] - m_sma900Buffer[2];
      double slope3 = m_sma900Buffer[2] - m_sma900Buffer[3];
      return ((slope1 + slope2 + slope3) / 3.0 > 0) && (slope1 > 0);
   }

   bool IsSMADownTrend()
   {
      if(ArraySize(m_sma900Buffer) < 4) return false;
      double slope1 = m_sma900Buffer[0] - m_sma900Buffer[1];
      double slope2 = m_sma900Buffer[1] - m_sma900Buffer[2];
      double slope3 = m_sma900Buffer[2] - m_sma900Buffer[3];
      return ((slope1 + slope2 + slope3) / 3.0 < 0) && (slope1 < 0);
   }

   bool IsEMAUpTrend()
   {
      if(ArraySize(m_ema20Buffer) < 4) return false;
      double slope1 = m_ema20Buffer[0] - m_ema20Buffer[1];
      double slope2 = m_ema20Buffer[1] - m_ema20Buffer[2];
      double slope3 = m_ema20Buffer[2] - m_ema20Buffer[3];
      return ((slope1 + slope2 + slope3) / 3.0 > 0) && (slope1 > 0);
   }

   bool IsEMADownTrend()
   {
      if(ArraySize(m_ema20Buffer) < 4) return false;
      double slope1 = m_ema20Buffer[0] - m_ema20Buffer[1];
      double slope2 = m_ema20Buffer[1] - m_ema20Buffer[2];
      double slope3 = m_ema20Buffer[2] - m_ema20Buffer[3];
      return ((slope1 + slope2 + slope3) / 3.0 < 0) && (slope1 < 0);
   }

   bool IsPriceAboveSMA() { return SymbolInfoDouble(m_symbol, SYMBOL_BID) > m_sma900Buffer[0]; }
   bool IsPriceBelowSMA() { return SymbolInfoDouble(m_symbol, SYMBOL_BID) < m_sma900Buffer[0]; }

   //+------------------------------------------------------------------+
   //| Check for EMA breakout with candle confirmation                   |
   //+------------------------------------------------------------------+
   bool CheckEMABreakoutUp()
   {
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double prevOpen = iOpen(m_symbol, m_timeframe, 1);
      double prevHigh = iHigh(m_symbol, m_timeframe, 1);
      double prevLow = iLow(m_symbol, m_timeframe, 1);
      double prev2Close = iClose(m_symbol, m_timeframe, 2);

      double ema20Current = m_ema20Buffer[1];
      double ema20Prev = m_ema20Buffer[2];

      // Basic breakout
      bool basicBreakout = (prevClose > ema20Current) && (prev2Close <= ema20Prev);
      if(!basicBreakout) return false;

      // Confirmations
      bool isBullish = prevClose > prevOpen;
      double bodySize = MathAbs(prevClose - prevOpen);
      double totalRange = prevHigh - prevLow;
      bool hasGoodBody = totalRange > 0 && (bodySize / totalRange) >= 0.5;
      bool closeNearHigh = totalRange > 0 && (prevClose - prevLow) / totalRange >= 0.7;

      // ATR filter
      double atr = m_atrBuffer[0];
      double avgATR = (m_atrBuffer[0] + m_atrBuffer[1] + m_atrBuffer[2]) / 3.0;
      bool hasVolatility = atr >= avgATR * m_minATRMultiple;

      return isBullish && hasGoodBody && closeNearHigh && hasVolatility;
   }

   bool CheckEMABreakoutDown()
   {
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double prevOpen = iOpen(m_symbol, m_timeframe, 1);
      double prevHigh = iHigh(m_symbol, m_timeframe, 1);
      double prevLow = iLow(m_symbol, m_timeframe, 1);
      double prev2Close = iClose(m_symbol, m_timeframe, 2);

      double ema20Current = m_ema20Buffer[1];
      double ema20Prev = m_ema20Buffer[2];

      bool basicBreakout = (prevClose < ema20Current) && (prev2Close >= ema20Prev);
      if(!basicBreakout) return false;

      bool isBearish = prevClose < prevOpen;
      double bodySize = MathAbs(prevClose - prevOpen);
      double totalRange = prevHigh - prevLow;
      bool hasGoodBody = totalRange > 0 && (bodySize / totalRange) >= 0.5;
      bool closeNearLow = totalRange > 0 && (prevHigh - prevClose) / totalRange >= 0.7;

      double atr = m_atrBuffer[0];
      double avgATR = (m_atrBuffer[0] + m_atrBuffer[1] + m_atrBuffer[2]) / 3.0;
      bool hasVolatility = atr >= avgATR * m_minATRMultiple;

      return isBearish && hasGoodBody && closeNearLow && hasVolatility;
   }

   //+------------------------------------------------------------------+
   //| Generate trading signal                                          |
   //| v3.1: EMA Breakout + M1 Range Breakout confirmation              |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(!UpdateData()) return SIGNAL_NONE;

      // Session filter
      if(!IsSessionAllowed()) return SIGNAL_NONE;

      // ADX filter
      if(!IsStrongTrend()) return SIGNAL_NONE;

      // BUY CONDITIONS:
      // 1. SMA900 up trend + Price above SMA
      // 2. EMA20 up trend + EMA breakout
      // 3. ADX strong + DI bullish
      // 4. M1 Range breakout UP

      if(IsSMAUpTrend() && IsPriceAboveSMA() && IsEMAUpTrend() &&
         IsDIBullish() && CheckEMABreakoutUp() && CheckRangeBreakoutUp())
      {
         return SIGNAL_BUY;
      }

      // SELL CONDITIONS:
      // 1. SMA900 down trend + Price below SMA
      // 2. EMA20 down trend + EMA breakout
      // 3. ADX strong + DI bearish
      // 4. M1 Range breakout DOWN

      if(IsSMADownTrend() && IsPriceBelowSMA() && IsEMADownTrend() &&
         IsDIBearish() && CheckEMABreakoutDown() && CheckRangeBreakoutDown())
      {
         return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Check if position should be closed early                         |
   //+------------------------------------------------------------------+
   bool ShouldCloseEarly(ENUM_SIGNAL_TYPE positionType)
   {
      if(!UpdateData()) return false;

      if(positionType == SIGNAL_BUY)
      {
         double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double ema20 = m_ema20Buffer[0];
         double atr = m_atrBuffer[0];

         if(currentPrice < (ema20 - atr * 0.3)) return true;
         if(IsEMADownTrend()) return true;
      }

      if(positionType == SIGNAL_SELL)
      {
         double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double ema20 = m_ema20Buffer[0];
         double atr = m_atrBuffer[0];

         if(currentPrice > (ema20 + atr * 0.3)) return true;
         if(IsEMAUpTrend()) return true;
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Calculate dynamic SL based on ATR and M1 range                   |
   //+------------------------------------------------------------------+
   double CalculateDynamicSL(ENUM_SIGNAL_TYPE signalType, double atrMultiplier = 1.5)
   {
      if(!UpdateData()) return 0;

      double atr = m_atrBuffer[0];
      double ema20 = m_ema20Buffer[0];
      double currentPrice = (signalType == SIGNAL_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                            SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double slDistance = atr * atrMultiplier;

      // Minimum SL = 3x spread
      double spread = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) *
                      SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minSL = spread * 3;
      if(slDistance < minSL) slDistance = minSL;

      // For M1 breakout: SL can be at breakout level
      if(m_useRangeBreakout)
      {
         if(signalType == SIGNAL_BUY && m_rangeHigh > 0)
         {
            double rangeBasedSL = currentPrice - m_rangeHigh;
            if(rangeBasedSL > 0 && rangeBasedSL < slDistance)
               slDistance = rangeBasedSL + (atr * 0.3);  // Add small buffer
         }
         else if(signalType == SIGNAL_SELL && m_rangeLow > 0)
         {
            double rangeBasedSL = m_rangeLow - currentPrice;
            if(rangeBasedSL > 0 && rangeBasedSL < slDistance)
               slDistance = rangeBasedSL + (atr * 0.3);
         }
      }

      if(signalType == SIGNAL_BUY)
         return currentPrice - slDistance;
      else
         return currentPrice + slDistance;
   }

   //+------------------------------------------------------------------+
   //| Calculate Take Profit                                            |
   //+------------------------------------------------------------------+
   double CalculateTP(double entryPrice, double slPrice, ENUM_SIGNAL_TYPE signalType, double rrRatio = 1.0)
   {
      double slDistance = MathAbs(entryPrice - slPrice);
      double tpDistance = slDistance * rrRatio;

      if(signalType == SIGNAL_BUY)
         return entryPrice + tpDistance;
      else
         return entryPrice - tpDistance;
   }

   //+------------------------------------------------------------------+
   //| Get SL distance in points                                        |
   //+------------------------------------------------------------------+
   double GetSLDistance(ENUM_SIGNAL_TYPE signalType)
   {
      double currentPrice = (signalType == SIGNAL_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                            SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double slPrice = CalculateDynamicSL(signalType);

      return MathAbs(currentPrice - slPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   }

   //+------------------------------------------------------------------+
   //| Settings                                                          |
   //+------------------------------------------------------------------+
   void SetADXParams(double minADX) { m_minADX = minADX; }

   void SetSessionFilter(bool useFilter, bool allowAsian, bool allowLondon, bool allowNY)
   {
      m_useSessionFilter = useFilter;
      m_allowAsian = allowAsian;
      m_allowLondon = allowLondon;
      m_allowNewYork = allowNY;
   }

   // New method name for M1 range
   void SetRangeBreakoutParams(bool useBreakout, int rangeBars, double bufferPips)
   {
      m_useRangeBreakout = useBreakout;
      m_rangeBars = rangeBars;
      m_breakoutBuffer = bufferPips;
   }

   // Legacy method for compatibility
   void SetH1BreakoutParams(bool useBreakout, int rangeBars, double bufferPips)
   {
      SetRangeBreakoutParams(useBreakout, rangeBars, bufferPips);
   }

   //+------------------------------------------------------------------+
   //| Accessors                                                         |
   //+------------------------------------------------------------------+
   string GetSymbol() { return m_symbol; }
   ENUM_TIMEFRAMES GetTimeframe() { return m_timeframe; }
   bool IsInitialized() { return m_isInitialized; }
   bool IsRangeBreakoutEnabled() { return m_useRangeBreakout; }
   bool IsH1BreakoutEnabled() { return m_useRangeBreakout; }  // Legacy
};
