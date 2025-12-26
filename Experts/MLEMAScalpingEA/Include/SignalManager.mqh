//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|                          ML EMA Scalping EA - Signal Module      |
//|                                                                  |
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

   // Indicator buffers
   double            m_sma900Buffer[];
   double            m_ema20Buffer[];
   double            m_atrBuffer[];

   // Settings
   int               m_smaPeriod;
   int               m_emaPeriod;
   int               m_atrPeriod;

   // State tracking
   double            m_prevEMA20;
   double            m_prevClose;
   bool              m_isInitialized;

public:
   // Constructor
   CSignalManager()
   {
      m_symbol = "";
      m_timeframe = PERIOD_M5;
      m_smaPeriod = 900;
      m_emaPeriod = 20;
      m_atrPeriod = 14;
      m_prevEMA20 = 0;
      m_prevClose = 0;
      m_isInitialized = false;
      m_handleSMA900 = INVALID_HANDLE;
      m_handleEMA20 = INVALID_HANDLE;
      m_handleATR = INVALID_HANDLE;
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

      // Create indicator handles
      m_handleSMA900 = iMA(m_symbol, m_timeframe, m_smaPeriod, 0, MODE_SMA, PRICE_CLOSE);
      m_handleEMA20 = iMA(m_symbol, m_timeframe, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleATR = iATR(m_symbol, m_timeframe, m_atrPeriod);

      if(m_handleSMA900 == INVALID_HANDLE ||
         m_handleEMA20 == INVALID_HANDLE ||
         m_handleATR == INVALID_HANDLE)
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
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Update indicator data                                            |
   //+------------------------------------------------------------------+
   bool UpdateData()
   {
      if(!m_isInitialized) return false;

      // Copy indicator values (need at least 3 bars for slope calculation)
      if(CopyBuffer(m_handleSMA900, 0, 0, 5, m_sma900Buffer) < 5) return false;
      if(CopyBuffer(m_handleEMA20, 0, 0, 5, m_ema20Buffer) < 5) return false;
      if(CopyBuffer(m_handleATR, 0, 0, 3, m_atrBuffer) < 3) return false;

      return true;
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
   //| Check if SMA900 is trending up                                   |
   //| Uses slope calculation over multiple bars                        |
   //+------------------------------------------------------------------+
   bool IsSMAUpTrend()
   {
      if(ArraySize(m_sma900Buffer) < 3) return false;

      // Calculate average slope over 3 bars
      double slope1 = m_sma900Buffer[0] - m_sma900Buffer[1];
      double slope2 = m_sma900Buffer[1] - m_sma900Buffer[2];
      double avgSlope = (slope1 + slope2) / 2.0;

      return avgSlope > 0;
   }

   //+------------------------------------------------------------------+
   //| Check if SMA900 is trending down                                 |
   //+------------------------------------------------------------------+
   bool IsSMADownTrend()
   {
      if(ArraySize(m_sma900Buffer) < 3) return false;

      double slope1 = m_sma900Buffer[0] - m_sma900Buffer[1];
      double slope2 = m_sma900Buffer[1] - m_sma900Buffer[2];
      double avgSlope = (slope1 + slope2) / 2.0;

      return avgSlope < 0;
   }

   //+------------------------------------------------------------------+
   //| Check if EMA20 is trending up                                    |
   //+------------------------------------------------------------------+
   bool IsEMAUpTrend()
   {
      if(ArraySize(m_ema20Buffer) < 3) return false;

      double slope1 = m_ema20Buffer[0] - m_ema20Buffer[1];
      double slope2 = m_ema20Buffer[1] - m_ema20Buffer[2];
      double avgSlope = (slope1 + slope2) / 2.0;

      return avgSlope > 0;
   }

   //+------------------------------------------------------------------+
   //| Check if EMA20 is trending down                                  |
   //+------------------------------------------------------------------+
   bool IsEMADownTrend()
   {
      if(ArraySize(m_ema20Buffer) < 3) return false;

      double slope1 = m_ema20Buffer[0] - m_ema20Buffer[1];
      double slope2 = m_ema20Buffer[1] - m_ema20Buffer[2];
      double avgSlope = (slope1 + slope2) / 2.0;

      return avgSlope < 0;
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
   //| Check for EMA breakout (price crossing EMA20)                    |
   //+------------------------------------------------------------------+
   bool CheckEMABreakoutUp()
   {
      // Get previous candle's close and open
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double prevOpen = iOpen(m_symbol, m_timeframe, 1);
      double prev2Close = iClose(m_symbol, m_timeframe, 2);

      // EMA values
      double ema20Current = m_ema20Buffer[1];  // EMA at candle 1
      double ema20Prev = m_ema20Buffer[2];     // EMA at candle 2

      // Breakout condition: previous candle closed above EMA, candle before was below or at EMA
      bool crossedUp = (prevClose > ema20Current) && (prev2Close <= ema20Prev);

      // Additional confirmation: candle body should be bullish
      bool isBullishCandle = prevClose > prevOpen;

      return crossedUp && isBullishCandle;
   }

   //+------------------------------------------------------------------+
   //| Check for EMA breakout down (price crossing EMA20)               |
   //+------------------------------------------------------------------+
   bool CheckEMABreakoutDown()
   {
      // Get previous candle's close and open
      double prevClose = iClose(m_symbol, m_timeframe, 1);
      double prevOpen = iOpen(m_symbol, m_timeframe, 1);
      double prev2Close = iClose(m_symbol, m_timeframe, 2);

      // EMA values
      double ema20Current = m_ema20Buffer[1];
      double ema20Prev = m_ema20Buffer[2];

      // Breakout condition: previous candle closed below EMA, candle before was above or at EMA
      bool crossedDown = (prevClose < ema20Current) && (prev2Close >= ema20Prev);

      // Additional confirmation: candle body should be bearish
      bool isBearishCandle = prevClose < prevOpen;

      return crossedDown && isBearishCandle;
   }

   //+------------------------------------------------------------------+
   //| Generate trading signal based on strategy                        |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(!UpdateData()) return SIGNAL_NONE;

      // BUY CONDITIONS:
      // 1. SMA900 is trending up
      // 2. Price is above SMA900
      // 3. EMA20 is trending up
      // 4. Price breaks EMA20 from below

      if(IsSMAUpTrend() && IsPriceAboveSMA() && IsEMAUpTrend() && CheckEMABreakoutUp())
      {
         return SIGNAL_BUY;
      }

      // SELL CONDITIONS:
      // 1. SMA900 is trending down
      // 2. Price is below SMA900
      // 3. EMA20 is trending down
      // 4. Price breaks EMA20 from above

      if(IsSMADownTrend() && IsPriceBelowSMA() && IsEMADownTrend() && CheckEMABreakoutDown())
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
         double threshold = ema20 - (atr * 0.3);  // Small buffer to avoid premature exits

         if(currentPrice < threshold)
         {
            return true;
         }
      }

      // For SELL position: close if price breaks above EMA20
      if(positionType == SIGNAL_SELL)
      {
         double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double ema20 = m_ema20Buffer[0];

         double atr = m_atrBuffer[0];
         double threshold = ema20 + (atr * 0.3);

         if(currentPrice > threshold)
         {
            return true;
         }
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
   //| Calculate Take Profit (1:1 Risk Reward)                          |
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
   //| Accessors                                                         |
   //+------------------------------------------------------------------+
   string GetSymbol() { return m_symbol; }
   ENUM_TIMEFRAMES GetTimeframe() { return m_timeframe; }
   bool IsInitialized() { return m_isInitialized; }
};
