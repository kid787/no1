//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|                          ML EMA Scalping EA - Signal Module      |
//|                         v4.0 - Session Breakout Strategy         |
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
//| Signal Manager Class                                              |
//| Session Breakout Strategy                                         |
//| - Calculates Asian session range                                  |
//| - Trades breakout at London open                                  |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   // Indicator handles
   int               m_handleATR;

   // Indicator buffers
   double            m_atrBuffer[];

   // Settings
   int               m_atrPeriod;

   // Session times (server time hours)
   int               m_asianStartHour;    // Asian session start (default 0 = 00:00)
   int               m_asianEndHour;      // Asian session end (default 7 = 07:00)
   int               m_londonStartHour;   // London trading window start (default 7)
   int               m_londonEndHour;     // London trading window end (default 16)

   // Breakout settings
   double            m_breakoutBuffer;    // Buffer in pips for breakout confirmation
   double            m_minRangeSize;      // Minimum range size in pips
   double            m_maxRangeSize;      // Maximum range size in pips

   // Daily range tracking
   double            m_asianHigh;         // Today's Asian session high
   double            m_asianLow;          // Today's Asian session low
   datetime          m_rangeDate;         // Date of current range
   bool              m_rangeCalculated;   // Range has been calculated today

   // Trade tracking (one trade per direction per day)
   datetime          m_lastBuyDate;
   datetime          m_lastSellDate;
   bool              m_buyTakenToday;
   bool              m_sellTakenToday;

   // State
   bool              m_isInitialized;

public:
   // Constructor
   CSignalManager()
   {
      m_symbol = "";
      m_timeframe = PERIOD_M5;
      m_atrPeriod = 14;
      m_handleATR = INVALID_HANDLE;

      // Default session times (UTC/Server time)
      m_asianStartHour = 0;    // 00:00
      m_asianEndHour = 7;      // 07:00
      m_londonStartHour = 7;   // 07:00
      m_londonEndHour = 16;    // 16:00

      // Breakout settings
      m_breakoutBuffer = 5.0;   // 5 pips buffer
      m_minRangeSize = 15.0;    // Min 15 pips range
      m_maxRangeSize = 80.0;    // Max 80 pips range (avoid news days)

      // Range tracking
      m_asianHigh = 0;
      m_asianLow = 0;
      m_rangeDate = 0;
      m_rangeCalculated = false;

      // Trade tracking
      m_lastBuyDate = 0;
      m_lastSellDate = 0;
      m_buyTakenToday = false;
      m_sellTakenToday = false;

      m_isInitialized = false;
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
      m_atrPeriod = atrPeriod;

      // Set array direction
      ArraySetAsSeries(m_atrBuffer, true);

      // Create ATR handle
      m_handleATR = iATR(m_symbol, m_timeframe, m_atrPeriod);

      if(m_handleATR == INVALID_HANDLE)
      {
         Print("Error creating ATR handle: ", GetLastError());
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
      if(m_handleATR != INVALID_HANDLE) { IndicatorRelease(m_handleATR); m_handleATR = INVALID_HANDLE; }
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Set session times                                                 |
   //+------------------------------------------------------------------+
   void SetSessionTimes(int asianStart, int asianEnd, int londonStart, int londonEnd)
   {
      m_asianStartHour = asianStart;
      m_asianEndHour = asianEnd;
      m_londonStartHour = londonStart;
      m_londonEndHour = londonEnd;
   }

   //+------------------------------------------------------------------+
   //| Set breakout parameters                                           |
   //+------------------------------------------------------------------+
   void SetBreakoutParams(double bufferPips, double minRange, double maxRange)
   {
      m_breakoutBuffer = bufferPips;
      m_minRangeSize = minRange;
      m_maxRangeSize = maxRange;
   }

   //+------------------------------------------------------------------+
   //| Update indicator data                                            |
   //+------------------------------------------------------------------+
   bool UpdateData()
   {
      if(!m_isInitialized) return false;

      if(CopyBuffer(m_handleATR, 0, 0, 3, m_atrBuffer) < 3) return false;

      // Check if we need to reset daily flags
      ResetDailyFlags();

      // Calculate Asian range if needed
      CalculateAsianRange();

      return true;
   }

   //+------------------------------------------------------------------+
   //| Reset daily trading flags                                         |
   //+------------------------------------------------------------------+
   void ResetDailyFlags()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

      // Reset buy flag if different day
      if(m_lastBuyDate != today)
      {
         m_buyTakenToday = false;
      }

      // Reset sell flag if different day
      if(m_lastSellDate != today)
      {
         m_sellTakenToday = false;
      }

      // Reset range if new day
      if(m_rangeDate != today)
      {
         m_rangeCalculated = false;
         m_asianHigh = 0;
         m_asianLow = 0;
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Asian session high/low range                           |
   //+------------------------------------------------------------------+
   void CalculateAsianRange()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int currentHour = dt.hour;

      // Only calculate range after Asian session ends
      if(currentHour < m_asianEndHour) return;

      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

      // Already calculated today
      if(m_rangeCalculated && m_rangeDate == today) return;

      // Calculate range from Asian session
      datetime asianStart = today + m_asianStartHour * 3600;
      datetime asianEnd = today + m_asianEndHour * 3600;

      // Find bars within Asian session
      int startBar = iBarShift(m_symbol, PERIOD_M5, asianStart);
      int endBar = iBarShift(m_symbol, PERIOD_M5, asianEnd);

      if(startBar < 0 || endBar < 0 || startBar <= endBar) return;

      // Get high and low of Asian session
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);

      int barsCount = startBar - endBar + 1;
      if(CopyHigh(m_symbol, PERIOD_M5, endBar, barsCount, highs) < barsCount) return;
      if(CopyLow(m_symbol, PERIOD_M5, endBar, barsCount, lows) < barsCount) return;

      // Find highest high and lowest low
      m_asianHigh = highs[0];
      m_asianLow = lows[0];

      for(int i = 1; i < barsCount; i++)
      {
         if(highs[i] > m_asianHigh) m_asianHigh = highs[i];
         if(lows[i] < m_asianLow) m_asianLow = lows[i];
      }

      m_rangeDate = today;
      m_rangeCalculated = true;

      double rangeSize = GetRangeSize();
      Print("Asian Range calculated: High=", m_asianHigh, " Low=", m_asianLow,
            " Size=", DoubleToString(rangeSize, 1), " pips");
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
   //| Check if current time is in London trading window                |
   //+------------------------------------------------------------------+
   bool IsLondonTradingTime()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      return (hour >= m_londonStartHour && hour < m_londonEndHour);
   }

   //+------------------------------------------------------------------+
   //| Check if range is valid (within min/max bounds)                  |
   //+------------------------------------------------------------------+
   bool IsRangeValid()
   {
      if(!m_rangeCalculated) return false;

      double rangeSize = GetRangeSize();
      return (rangeSize >= m_minRangeSize && rangeSize <= m_maxRangeSize);
   }

   //+------------------------------------------------------------------+
   //| Get range size in pips                                           |
   //+------------------------------------------------------------------+
   double GetRangeSize()
   {
      if(m_asianHigh == 0 || m_asianLow == 0) return 0;
      return (m_asianHigh - m_asianLow) / GetPipSize();
   }

   //+------------------------------------------------------------------+
   //| Generate trading signal - Session Breakout                       |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(!UpdateData()) return SIGNAL_NONE;

      // Must be in London trading window
      if(!IsLondonTradingTime()) return SIGNAL_NONE;

      // Range must be calculated and valid
      if(!IsRangeValid()) return SIGNAL_NONE;

      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pipSize = GetPipSize();
      double buffer = m_breakoutBuffer * pipSize;

      // BUY: Price breaks above Asian high
      if(!m_buyTakenToday && currentPrice > (m_asianHigh + buffer))
      {
         Print("BUY Signal: Price ", currentPrice, " > Asian High ", m_asianHigh, " + buffer");
         return SIGNAL_BUY;
      }

      // SELL: Price breaks below Asian low
      if(!m_sellTakenToday && currentPrice < (m_asianLow - buffer))
      {
         Print("SELL Signal: Price ", currentPrice, " < Asian Low ", m_asianLow, " - buffer");
         return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Mark that a trade was taken today                                |
   //+------------------------------------------------------------------+
   void MarkTradeTaken(ENUM_SIGNAL_TYPE signalType)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

      if(signalType == SIGNAL_BUY)
      {
         m_buyTakenToday = true;
         m_lastBuyDate = today;
         Print("Buy trade marked as taken for today");
      }
      else if(signalType == SIGNAL_SELL)
      {
         m_sellTakenToday = true;
         m_lastSellDate = today;
         Print("Sell trade marked as taken for today");
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate SL for session breakout                                |
   //+------------------------------------------------------------------+
   double CalculateDynamicSL(ENUM_SIGNAL_TYPE signalType, double atrMultiplier = 1.5)
   {
      if(!m_rangeCalculated) return 0;

      double currentPrice = (signalType == SIGNAL_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                            SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double pipSize = GetPipSize();
      double atr = m_atrBuffer[0];

      // SL options:
      // Option 1: Opposite side of range
      // Option 2: Middle of range
      // Option 3: ATR-based

      double slPrice;

      if(signalType == SIGNAL_BUY)
      {
         // SL below Asian low or middle of range
         double rangeMid = (m_asianHigh + m_asianLow) / 2.0;
         slPrice = MathMin(m_asianLow - (5 * pipSize), rangeMid);

         // Ensure minimum SL distance
         double minSL = atr * 1.0;
         if((currentPrice - slPrice) < minSL)
            slPrice = currentPrice - minSL;
      }
      else // SELL
      {
         double rangeMid = (m_asianHigh + m_asianLow) / 2.0;
         slPrice = MathMax(m_asianHigh + (5 * pipSize), rangeMid);

         double minSL = atr * 1.0;
         if((slPrice - currentPrice) < minSL)
            slPrice = currentPrice + minSL;
      }

      return slPrice;
   }

   //+------------------------------------------------------------------+
   //| Calculate Take Profit                                            |
   //+------------------------------------------------------------------+
   double CalculateTP(double entryPrice, double slPrice, ENUM_SIGNAL_TYPE signalType, double rrRatio = 1.5)
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
   //| Check if position should be closed early                         |
   //+------------------------------------------------------------------+
   bool ShouldCloseEarly(ENUM_SIGNAL_TYPE positionType)
   {
      // For session breakout, we generally let SL/TP handle exit
      // But close if we're past London session
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      // Close positions after London close (optional)
      if(dt.hour >= 20) return true;

      return false;
   }

   //+------------------------------------------------------------------+
   //| Accessors                                                         |
   //+------------------------------------------------------------------+
   double GetAsianHigh() { return m_asianHigh; }
   double GetAsianLow() { return m_asianLow; }
   double GetATR(int shift = 0) { return (shift < ArraySize(m_atrBuffer)) ? m_atrBuffer[shift] : 0; }
   bool IsRangeCalculated() { return m_rangeCalculated; }
   bool IsBuyTakenToday() { return m_buyTakenToday; }
   bool IsSellTakenToday() { return m_sellTakenToday; }

   // Legacy accessors for compatibility (return 0 or neutral values)
   double GetSMA900(int shift = 0) { return 0; }
   double GetEMA20(int shift = 0) { return 0; }
   double GetADX(int shift = 0) { return 0; }
   double GetH1RangeHigh() { return m_asianHigh; }
   double GetH1RangeLow() { return m_asianLow; }
   double GetH1RangeSize() { return GetRangeSize(); }
   double GetRangeHigh() { return m_asianHigh; }
   double GetRangeLow() { return m_asianLow; }

   //+------------------------------------------------------------------+
   //| Legacy method stubs for compatibility                            |
   //+------------------------------------------------------------------+
   void SetADXParams(double minADX) { }
   void SetSessionFilter(bool useFilter, bool allowAsian, bool allowLondon, bool allowNY) { }
   void SetRangeBreakoutParams(bool useBreakout, int rangeBars, double bufferPips) { }
   void SetH1BreakoutParams(bool useBreakout, int rangeBars, double bufferPips) { }

   bool IsStrongTrend() { return true; }
   bool IsDIBullish() { return true; }
   bool IsDIBearish() { return true; }
   bool IsSMAUpTrend() { return false; }
   bool IsSMADownTrend() { return false; }
   bool IsEMAUpTrend() { return false; }
   bool IsEMADownTrend() { return false; }
   bool IsPriceAboveSMA() { return false; }
   bool IsPriceBelowSMA() { return false; }
   bool IsSessionAllowed() { return IsLondonTradingTime(); }
   bool IsRangeBreakoutEnabled() { return true; }
   bool IsH1BreakoutEnabled() { return true; }

   string GetSymbol() { return m_symbol; }
   ENUM_TIMEFRAMES GetTimeframe() { return m_timeframe; }
   bool IsInitialized() { return m_isInitialized; }
};
