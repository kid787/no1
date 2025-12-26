//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|                          ML EMA Scalping EA - Signal Module      |
//|                                  v2.0 - Enhanced Signal Quality  |
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
//| Handles SMA/EMA logic based on the 5-minute scalping strategy    |
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
   int               m_handleADX;       // ADX for trend strength

   // Indicator buffers
   double            m_sma900Buffer[];
   double            m_ema20Buffer[];
   double            m_atrBuffer[];
   double            m_adxBuffer[];     // ADX main line
   double            m_plusDIBuffer[];  // +DI
   double            m_minusDIBuffer[]; // -DI

   // Settings
   int               m_smaPeriod;
   int               m_emaPeriod;
   int               m_atrPeriod;
   int               m_adxPeriod;
   double            m_minADX;          // Minimum ADX for entry
   double            m_minATRMultiple;  // Minimum ATR for volatility filter

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
      m_minADX = 20.0;         // Minimum ADX value for trend
      m_minATRMultiple = 0.5;  // Minimum volatility
      m_prevEMA20 = 0;
      m_prevClose = 0;
      m_isInitialized = false;
      m_handleSMA900 = INVALID_HANDLE;
      m_handleEMA20 = INVALID_HANDLE;
      m_handleATR = INVALID_HANDLE;
      m_handleADX = INVALID_HANDLE;

      // Session filter defaults
      m_useSessionFilter = true;
      m_allowAsian = false;      // Skip low volatility Asian session
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
      if(m_handleSMA900 != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleSMA900);
         m_handleSMA900 = INVALID_HANDLE;
      }
      if(m_handleEMA20 != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleEMA20);
         m_handleEMA20 = INVALID_HANDLE;
      }
      if(m_handleATR != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleATR);
         m_handleATR = INVALID_HANDLE;
      }
      if(m_handleADX != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleADX);
         m_handleADX = INVALID_HANDLE;
      }
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Update indicator data                                            |
   //+------------------------------------------------------------------+
   bool UpdateData()
   {
      if(!m_isInitialized) return false;

      // Copy indicator values (need at least 5 bars for slope calculation)
      if(CopyBuffer(m_handleSMA900, 0, 0, 5, m_sma900Buffer) < 5) return false;
      if(CopyBuffer(m_handleEMA20, 0, 0, 5, m_ema20Buffer) < 5) return false;
      if(CopyBuffer(m_handleATR, 0, 0, 3, m_atrBuffer) < 3) return false;
      if(CopyBuffer(m_handleADX, 0, 0, 3, m_adxBuffer) < 3) return false;      // ADX main
      if(CopyBuffer(m_handleADX, 1, 0, 3, m_plusDIBuffer) < 3) return false;   // +DI
      if(CopyBuffer(m_handleADX, 2, 0, 3, m_minusDIBuffer) < 3) return false;  // -DI

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get current trading session                                       |
   //+------------------------------------------------------------------+
   ENUM_TRADING_SESSION GetCurrentSession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;  // Server time (usually UTC or UTC+2/3)

      // Adjust for broker server time if needed
      // These times assume UTC

      // London/NY Overlap (best volatility)
      if(hour >= 13 && hour < 16)
         return SESSION_OVERLAP;

      // London session
      if(hour >= 7 && hour < 16)
         return SESSION_LONDON;

      // New York session
      if(hour >= 13 && hour < 22)
         return SESSION_NEWYORK;

      // Asian session
      if(hour >= 0 && hour < 9)
         return SESSION_ASIAN;

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
         case SESSION_OVERLAP:
            return true;  // Always allow overlap (best liquidity)
         case SESSION_LONDON:
            return m_allowLondon;
         case SESSION_NEWYORK:
            return m_allowNewYork;
         case SESSION_ASIAN:
            return m_allowAsian;
         default:
            return false;
      }
   }

   //+------------------------------------------------------------------+
   //| Get current SMA900 value                                         |
   //+------------------------------------------------------------------+
   double GetSMA900(int shift = 0)
   {
      if(shift < ArraySize(m_sma900Buffer))
         return m_sma900Buffer[shift];
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get current EMA20 value                                          |
   //+------------------------------------------------------------------+
   double GetEMA20(int shift = 0)
   {
      if(shift < ArraySize(m_ema20Buffer))
         return m_ema20Buffer[shift];
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get current ATR value                                            |
   //+------------------------------------------------------------------+
   double GetATR(int shift = 0)
   {
      if(shift < ArraySize(m_atrBuffer))
         return m_atrBuffer[shift];
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get current ADX value                                            |
   //+------------------------------------------------------------------+
   double GetADX(int shift = 0)
   {
      if(shift < ArraySize(m_adxBuffer))
         return m_adxBuffer[shift];
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Check if ADX indicates strong trend                              |
   //+------------------------------------------------------------------+
   bool IsStrongTrend()
   {
      if(ArraySize(m_adxBuffer) < 1) return false;
      return m_adxBuffer[0] >= m_minADX;
   }

   //+------------------------------------------------------------------+
   //| Check if +DI > -DI (bullish)                                     |
   //+------------------------------------------------------------------+
   bool IsDIBullish()
   {
      if(ArraySize(m_plusDIBuffer) < 1 || ArraySize(m_minusDIBuffer) < 1) return false;
      return m_plusDIBuffer[0] > m_minusDIBuffer[0];
   }

   //+------------------------------------------------------------------+
   //| Check if -DI > +DI (bearish)                                     |
   //+------------------------------------------------------------------+
   bool IsDIBearish()
   {
      if(ArraySize(m_plusDIBuffer) < 1 || ArraySize(m_minusDIBuffer) < 1) return false;
      return m_minusDIBuffer[0] > m_plusDIBuffer[0];
   }

   //+------------------------------------------------------------------+
   //| Check if SMA900 is trending up                                   |
   //| Uses slope calculation over multiple bars                        |
   //+------------------------------------------------------------------+
   bool IsSMAUpTrend()
   {
      if(ArraySize(m_sma900Buffer) < 4) return false;

      // Calculate average slope over 3 bars
      double slope1 = m_sma900Buffer[0] - m_sma900Buffer[1];
      double slope2 = m_sma900Buffer[1] - m_sma900Buffer[2];
      double slope3 = m_sma900Buffer[2] - m_sma900Buffer[3];
      double avgSlope = (slope1 + slope2 + slope3) / 3.0;

      // Require consistent upward slope
      return avgSlope > 0 && slope1 > 0;
   }

   //+------------------------------------------------------------------+
   //| Check if SMA900 is trending down                                 |
   //+------------------------------------------------------------------+
   bool IsSMADownTrend()
   {
      if(ArraySize(m_sma900Buffer) < 4) return false;

      double slope1 = m_sma900Buffer[0] - m_sma900Buffer[1];
      double slope2 = m_sma900Buffer[1] - m_sma900Buffer[2];
      double slope3 = m_sma900Buffer[2] - m_sma900Buffer[3];
      double avgSlope = (slope1 + slope2 + slope3) / 3.0;

      return avgSlope < 0 && slope1 < 0;
   }

   //+------------------------------------------------------------------+
   //| Check if EMA20 is trending up                                    |
   //+------------------------------------------------------------------+
   bool IsEMAUpTrend()
   {
      if(ArraySize(m_ema20Buffer) < 4) return false;

      double slope1 = m_ema20Buffer[0] - m_ema20Buffer[1];
      double slope2 = m_ema20Buffer[1] - m_ema20Buffer[2];
      double slope3 = m_ema20Buffer[2] - m_ema20Buffer[3];
      double avgSlope = (slope1 + slope2 + slope3) / 3.0;

      return avgSlope > 0 && slope1 > 0;
   }

   //+------------------------------------------------------------------+
   //| Check if EMA20 is trending down                                  |
   //+------------------------------------------------------------------+
   bool IsEMADownTrend()
   {
      if(ArraySize(m_ema20Buffer) < 4) return false;

      double slope1 = m_ema20Buffer[0] - m_ema20Buffer[1];
      double slope2 = m_ema20Buffer[1] - m_ema20Buffer[2];
      double slope3 = m_ema20Buffer[2] - m_ema20Buffer[3];
      double avgSlope = (slope1 + slope2 + slope3) / 3.0;

      return avgSlope < 0 && slope1 < 0;
   }

   //+------------------------------------------------------------------+
   //| Check if price is above SMA900                                   |
   //+------------------------------------------------------------------+
   bool IsPriceAboveSMA()
   {
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return currentPrice > m_sma900Buffer[0];
   }

   //+------------------------------------------------------------------+
   //| Check if price is below SMA900                                   |
   //+------------------------------------------------------------------+
   bool IsPriceBelowSMA()
   {
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return currentPrice < m_sma900Buffer[0];
   }

   //+------------------------------------------------------------------+
   //| Check for EMA breakout UP with confirmation                      |
   //| Improved: requires stronger confirmation candle                  |
   //+------------------------------------------------------------------+
   bool CheckEMABreakoutUp()
   {
      // Get candle data
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double prevOpen = iOpen(m_symbol, m_timeframe, 1);
      double prevHigh = iHigh(m_symbol, m_timeframe, 1);
      double prevLow = iLow(m_symbol, m_timeframe, 1);
      double prev2Close = iClose(m_symbol, m_timeframe, 2);
      double prev2Low = iLow(m_symbol, m_timeframe, 2);

      // EMA values
      double ema20Current = m_ema20Buffer[1];
      double ema20Prev = m_ema20Buffer[2];

      // Basic breakout: close above EMA, previous close at or below
      bool basicBreakout = (prevClose > ema20Current) && (prev2Close <= ema20Prev);

      if(!basicBreakout) return false;

      // Confirmation 1: Bullish candle (close > open)
      bool isBullish = prevClose > prevOpen;

      // Confirmation 2: Candle body is at least 50% of total range
      double bodySize = MathAbs(prevClose - prevOpen);
      double totalRange = prevHigh - prevLow;
      bool hasGoodBody = totalRange > 0 && (bodySize / totalRange) >= 0.5;

      // Confirmation 3: Close in upper 30% of candle range
      bool closeNearHigh = totalRange > 0 && (prevClose - prevLow) / totalRange >= 0.7;

      // Confirmation 4: ATR filter - ensure sufficient volatility
      double atr = m_atrBuffer[0];
      double avgATR = (m_atrBuffer[0] + m_atrBuffer[1] + m_atrBuffer[2]) / 3.0;
      bool hasVolatility = atr >= avgATR * m_minATRMultiple;

      return isBullish && hasGoodBody && closeNearHigh && hasVolatility;
   }

   //+------------------------------------------------------------------+
   //| Check for EMA breakout DOWN with confirmation                    |
   //+------------------------------------------------------------------+
   bool CheckEMABreakoutDown()
   {
      // Get candle data
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double prevOpen = iOpen(m_symbol, m_timeframe, 1);
      double prevHigh = iHigh(m_symbol, m_timeframe, 1);
      double prevLow = iLow(m_symbol, m_timeframe, 1);
      double prev2Close = iClose(m_symbol, m_timeframe, 2);
      double prev2High = iHigh(m_symbol, m_timeframe, 2);

      // EMA values
      double ema20Current = m_ema20Buffer[1];
      double ema20Prev = m_ema20Buffer[2];

      // Basic breakout: close below EMA, previous close at or above
      bool basicBreakout = (prevClose < ema20Current) && (prev2Close >= ema20Prev);

      if(!basicBreakout) return false;

      // Confirmation 1: Bearish candle (close < open)
      bool isBearish = prevClose < prevOpen;

      // Confirmation 2: Candle body is at least 50% of total range
      double bodySize = MathAbs(prevClose - prevOpen);
      double totalRange = prevHigh - prevLow;
      bool hasGoodBody = totalRange > 0 && (bodySize / totalRange) >= 0.5;

      // Confirmation 3: Close in lower 30% of candle range
      bool closeNearLow = totalRange > 0 && (prevHigh - prevClose) / totalRange >= 0.7;

      // Confirmation 4: ATR filter - ensure sufficient volatility
      double atr = m_atrBuffer[0];
      double avgATR = (m_atrBuffer[0] + m_atrBuffer[1] + m_atrBuffer[2]) / 3.0;
      bool hasVolatility = atr >= avgATR * m_minATRMultiple;

      return isBearish && hasGoodBody && closeNearLow && hasVolatility;
   }

   //+------------------------------------------------------------------+
   //| Generate trading signal based on strategy                        |
   //| v2.0: Added ADX, DI, and session filters                        |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(!UpdateData()) return SIGNAL_NONE;

      // Session filter
      if(!IsSessionAllowed())
         return SIGNAL_NONE;

      // ADX filter - require strong trend
      if(!IsStrongTrend())
         return SIGNAL_NONE;

      // BUY CONDITIONS:
      // 1. SMA900 is trending up
      // 2. Price is above SMA900
      // 3. EMA20 is trending up
      // 4. ADX shows strong trend with +DI > -DI
      // 5. Price breaks EMA20 from below with confirmation

      if(IsSMAUpTrend() && IsPriceAboveSMA() && IsEMAUpTrend() &&
         IsDIBullish() && CheckEMABreakoutUp())
      {
         return SIGNAL_BUY;
      }

      // SELL CONDITIONS:
      // 1. SMA900 is trending down
      // 2. Price is below SMA900
      // 3. EMA20 is trending down
      // 4. ADX shows strong trend with -DI > +DI
      // 5. Price breaks EMA20 from above with confirmation

      if(IsSMADownTrend() && IsPriceBelowSMA() && IsEMADownTrend() &&
         IsDIBearish() && CheckEMABreakoutDown())
      {
         return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Check if position should be closed early (reversal protection)   |
   //+------------------------------------------------------------------+
   bool ShouldCloseEarly(ENUM_SIGNAL_TYPE positionType)
   {
      if(!UpdateData()) return false;

      // For BUY position: close if price breaks below EMA20
      if(positionType == SIGNAL_BUY)
      {
         double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double ema20 = m_ema20Buffer[0];

         // Check if current price is significantly below EMA20
         double atr = m_atrBuffer[0];
         double threshold = ema20 - (atr * 0.3);

         if(currentPrice < threshold)
            return true;

         // Also close if EMA20 turns down
         if(IsEMADownTrend())
            return true;
      }

      // For SELL position: close if price breaks above EMA20
      if(positionType == SIGNAL_SELL)
      {
         double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double ema20 = m_ema20Buffer[0];

         double atr = m_atrBuffer[0];
         double threshold = ema20 + (atr * 0.3);

         if(currentPrice > threshold)
            return true;

         // Also close if EMA20 turns up
         if(IsEMAUpTrend())
            return true;
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Calculate dynamic Stop Loss based on ATR                         |
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

      // Minimum SL distance based on spread
      double spread = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) *
                      SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minSL = spread * 3;  // At least 3x spread

      if(slDistance < minSL) slDistance = minSL;

      // SL should be beyond EMA20 for better protection
      if(signalType == SIGNAL_BUY)
      {
         double emaBasedSL = currentPrice - ema20;
         if(emaBasedSL > 0 && slDistance < emaBasedSL * 1.2)
            slDistance = emaBasedSL * 1.2;
         return currentPrice - slDistance;
      }
      else // SELL
      {
         double emaBasedSL = ema20 - currentPrice;
         if(emaBasedSL > 0 && slDistance < emaBasedSL * 1.2)
            slDistance = emaBasedSL * 1.2;
         return currentPrice + slDistance;
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Take Profit (Risk Reward Ratio)                        |
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
   //| Set ADX parameters                                               |
   //+------------------------------------------------------------------+
   void SetADXParams(double minADX) { m_minADX = minADX; }

   //+------------------------------------------------------------------+
   //| Set session filter parameters                                    |
   //+------------------------------------------------------------------+
   void SetSessionFilter(bool useFilter, bool allowAsian, bool allowLondon, bool allowNY)
   {
      m_useSessionFilter = useFilter;
      m_allowAsian = allowAsian;
      m_allowLondon = allowLondon;
      m_allowNewYork = allowNY;
   }

   //+------------------------------------------------------------------+
   //| Accessors                                                         |
   //+------------------------------------------------------------------+
   string GetSymbol() { return m_symbol; }
   ENUM_TIMEFRAMES GetTimeframe() { return m_timeframe; }
   bool IsInitialized() { return m_isInitialized; }
};
