//+------------------------------------------------------------------+
//|                                               SignalManager.mqh |
//|            Asian Box Breakout + Improved Filters v7.0            |
//|                                                                  |
//|  Strategy:                                                       |
//|  - Asian Session: Form range during 23:00-06:00 GMT              |
//|  - Entry Window: 07:00-10:00 GMT (London Open)                   |
//|  - Breakout: Price closes outside Asian range + buffer           |
//|                                                                  |
//|  Filters (False Breakout Prevention):                            |
//|  - ATR Filter: ATR(14) > SMA(ATR, 20)                           |
//|  - Retest Logic: Wait for pullback to broken level               |
//|  - H1 EMA Trend Alignment                                        |
//|  - Range Size: 30-80 pips (skip too small or too large)          |
//|                                                                  |
//|  Exit:                                                           |
//|  - TP: Pivot R1/S1 or 2:1 RR                                    |
//|  - SL: Opposite side of range + buffer                           |
//+------------------------------------------------------------------+
#property copyright "Asian Box Breakout EA v7.0"
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
//| Breakout State Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_BREAKOUT_STATE
{
   BREAKOUT_NONE = 0,
   BREAKOUT_PENDING_UP = 1,      // Broke up, waiting for retest
   BREAKOUT_PENDING_DOWN = -1,   // Broke down, waiting for retest
   BREAKOUT_CONFIRMED_UP = 2,    // Retest complete, ready to buy
   BREAKOUT_CONFIRMED_DOWN = -2  // Retest complete, ready to sell
};

//+------------------------------------------------------------------+
//| Pivot Levels Structure                                           |
//+------------------------------------------------------------------+
struct SPivotLevels
{
   double PP;
   double R1, R2, R3;
   double S1, S2, S3;
   datetime calcDate;
};

//+------------------------------------------------------------------+
//| Asian Range Structure                                            |
//+------------------------------------------------------------------+
struct SAsianRange
{
   double high;
   double low;
   datetime rangeStart;
   datetime rangeEnd;
   bool isValid;
   bool breakoutUp;
   bool breakoutDown;
   datetime breakoutTime;
   double breakoutPrice;
   bool retestComplete;
};

//+------------------------------------------------------------------+
//| Signal Manager Class - Asian Box Breakout v7.0                   |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_entryTimeframe;     // M5 for entry
   ENUM_TIMEFRAMES   m_trendTimeframe;     // H1 for trend filter

   // Indicator handles
   int               m_trendEmaHandle;     // EMA on H1 for trend
   int               m_atrHandle;          // ATR for volatility filter
   int               m_atrSmaHandle;       // SMA of ATR
   int               m_rsiHandle;          // RSI

   // EMA settings
   int               m_trendEmaPeriod;

   // ATR settings
   int               m_atrPeriod;

   // Asian Session settings (GMT hours)
   int               m_asianStartGMT;      // 23:00 GMT
   int               m_asianEndGMT;        // 06:00 GMT
   int               m_entryStartGMT;      // 07:00 GMT
   int               m_entryEndGMT;        // 10:00 GMT

   // Range filter settings
   double            m_minRangePips;       // Minimum 30 pips
   double            m_maxRangePips;       // Maximum 80 pips
   double            m_breakoutBuffer;     // Buffer pips for entry
   double            m_retestBuffer;       // Buffer for retest zone

   // Broker time offset
   int               m_gmtOffset;

   // Current state
   SAsianRange       m_asianRange;
   ENUM_TREND_STATE  m_currentTrend;
   ENUM_BREAKOUT_STATE m_breakoutState;
   SPivotLevels      m_pivotLevels;

   // Trade management
   datetime          m_lastTradeDate;
   int               m_tradesToday;
   int               m_maxTradesPerDay;

   // Cached values
   double            m_trendEmaValue;
   double            m_atrValue;
   double            m_atrSmaValue;
   double            m_rsiValue;
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
      m_atrHandle = INVALID_HANDLE;
      m_atrSmaHandle = INVALID_HANDLE;
      m_rsiHandle = INVALID_HANDLE;

      m_trendEmaPeriod = 50;
      m_atrPeriod = 14;

      // Asian session: 23:00-06:00 GMT (7 hours)
      m_asianStartGMT = 23;
      m_asianEndGMT = 6;
      // Entry window: 07:00-10:00 GMT (London open)
      m_entryStartGMT = 7;
      m_entryEndGMT = 10;

      m_minRangePips = 30.0;
      m_maxRangePips = 80.0;
      m_breakoutBuffer = 5.0;
      m_retestBuffer = 10.0;

      m_gmtOffset = 2;

      ResetAsianRange();
      m_currentTrend = TREND_NONE;
      m_breakoutState = BREAKOUT_NONE;
      ZeroMemory(m_pivotLevels);

      m_lastTradeDate = 0;
      m_tradesToday = 0;
      m_maxTradesPerDay = 3;

      m_trendEmaValue = 0;
      m_atrValue = 0;
      m_atrSmaValue = 0;
      m_rsiValue = 50;
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
   //| Reset Asian Range                                                |
   //+------------------------------------------------------------------+
   void ResetAsianRange()
   {
      m_asianRange.high = 0;
      m_asianRange.low = DBL_MAX;
      m_asianRange.rangeStart = 0;
      m_asianRange.rangeEnd = 0;
      m_asianRange.isValid = false;
      m_asianRange.breakoutUp = false;
      m_asianRange.breakoutDown = false;
      m_asianRange.breakoutTime = 0;
      m_asianRange.breakoutPrice = 0;
      m_asianRange.retestComplete = false;
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
      m_atrPeriod = atrPeriod;

      // Create trend EMA indicator (H1)
      m_trendEmaHandle = iMA(m_symbol, m_trendTimeframe, m_trendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(m_trendEmaHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create trend EMA indicator");
         return false;
      }

      // Create ATR indicator (M5)
      m_atrHandle = iATR(m_symbol, m_entryTimeframe, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create ATR indicator");
         return false;
      }

      // Create RSI indicator
      m_rsiHandle = iRSI(m_symbol, m_entryTimeframe, 14, PRICE_CLOSE);
      if(m_rsiHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create RSI indicator");
         return false;
      }

      m_isInitialized = true;
      Print("=== Asian Box Breakout v7.0 ===");
      Print("Asian Session: ", m_asianStartGMT, ":00 - ", m_asianEndGMT, ":00 GMT");
      Print("Entry Window: ", m_entryStartGMT, ":00 - ", m_entryEndGMT, ":00 GMT");
      Print("Range Filter: ", m_minRangePips, " - ", m_maxRangePips, " pips");
      Print("Trend EMA: ", m_trendEmaPeriod, " on ", EnumToString(m_trendTimeframe));

      return true;
   }

   //+------------------------------------------------------------------+
   //| Deinitialize                                                     |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      if(m_trendEmaHandle != INVALID_HANDLE) { IndicatorRelease(m_trendEmaHandle); m_trendEmaHandle = INVALID_HANDLE; }
      if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
      if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
      m_isInitialized = false;
   }

   //+------------------------------------------------------------------+
   //| Update all indicator values                                      |
   //+------------------------------------------------------------------+
   bool UpdateIndicators()
   {
      if(!m_isInitialized) return false;

      double trendEma[], atr[], rsi[];
      ArraySetAsSeries(trendEma, true);
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(rsi, true);

      // Get trend EMA
      if(CopyBuffer(m_trendEmaHandle, 0, 0, 25, trendEma) < 25) return false;
      m_trendEmaValue = trendEma[0];

      // Get ATR (need 25 bars for SMA calculation)
      if(CopyBuffer(m_atrHandle, 0, 0, 25, atr) < 25) return false;
      m_atrValue = atr[0];

      // Calculate ATR SMA(20) manually
      double atrSum = 0;
      for(int i = 0; i < 20; i++)
         atrSum += atr[i];
      m_atrSmaValue = atrSum / 20.0;

      // Get RSI
      if(CopyBuffer(m_rsiHandle, 0, 0, 3, rsi) < 3) return false;
      m_rsiValue = rsi[0];

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

      if(m_pivotLevels.calcDate == today) return;

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

      m_pivotLevels.PP = (h + l + c) / 3;
      m_pivotLevels.R1 = 2 * m_pivotLevels.PP - l;
      m_pivotLevels.S1 = 2 * m_pivotLevels.PP - h;
      m_pivotLevels.R2 = m_pivotLevels.PP + (h - l);
      m_pivotLevels.S2 = m_pivotLevels.PP - (h - l);
      m_pivotLevels.R3 = h + 2 * (m_pivotLevels.PP - l);
      m_pivotLevels.S3 = l - 2 * (h - m_pivotLevels.PP);
      m_pivotLevels.calcDate = today;

      Print("=== Daily Pivot Updated ===");
      Print("PP: ", DoubleToString(m_pivotLevels.PP, 5));
      Print("R1: ", DoubleToString(m_pivotLevels.R1, 5), " | S1: ", DoubleToString(m_pivotLevels.S1, 5));
   }

   //+------------------------------------------------------------------+
   //| Get current GMT hour from server time                            |
   //+------------------------------------------------------------------+
   int GetGMTHour()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int gmtHour = dt.hour - m_gmtOffset;
      if(gmtHour < 0) gmtHour += 24;
      if(gmtHour >= 24) gmtHour -= 24;
      return gmtHour;
   }

   //+------------------------------------------------------------------+
   //| Check if in Asian session                                        |
   //+------------------------------------------------------------------+
   bool IsAsianSession()
   {
      int gmtHour = GetGMTHour();
      // Asian: 23:00-06:00 (crosses midnight)
      return (gmtHour >= m_asianStartGMT || gmtHour < m_asianEndGMT);
   }

   //+------------------------------------------------------------------+
   //| Check if in entry window                                         |
   //+------------------------------------------------------------------+
   bool IsEntryWindow()
   {
      int gmtHour = GetGMTHour();
      return (gmtHour >= m_entryStartGMT && gmtHour < m_entryEndGMT);
   }

   //+------------------------------------------------------------------+
   //| Update Asian Range during session                                |
   //+------------------------------------------------------------------+
   void UpdateAsianRange()
   {
      if(!IsAsianSession()) return;

      int gmtHour = GetGMTHour();

      // Reset at start of Asian session (23:00 GMT)
      if(gmtHour == m_asianStartGMT && m_asianRange.rangeStart == 0)
      {
         ResetAsianRange();
         m_asianRange.rangeStart = TimeCurrent();
         m_breakoutState = BREAKOUT_NONE;
         Print("=== Asian Session Started - Forming Range ===");
      }

      // Update high/low during session
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      if(CopyHigh(m_symbol, m_entryTimeframe, 0, 1, high) < 1) return;
      if(CopyLow(m_symbol, m_entryTimeframe, 0, 1, low) < 1) return;

      if(high[0] > m_asianRange.high)
         m_asianRange.high = high[0];
      if(low[0] < m_asianRange.low)
         m_asianRange.low = low[0];
   }

   //+------------------------------------------------------------------+
   //| Finalize Asian Range at session end                              |
   //+------------------------------------------------------------------+
   void FinalizeAsianRange()
   {
      int gmtHour = GetGMTHour();

      // Finalize at 06:00 GMT
      if(gmtHour == m_asianEndGMT && !m_asianRange.isValid && m_asianRange.rangeStart > 0)
      {
         m_asianRange.rangeEnd = TimeCurrent();

         double pipSize = GetPipSize();
         double rangePips = (m_asianRange.high - m_asianRange.low) / pipSize;

         // Validate range size
         if(rangePips >= m_minRangePips && rangePips <= m_maxRangePips)
         {
            m_asianRange.isValid = true;
            Print("=== Asian Range VALID ===");
            Print("High: ", DoubleToString(m_asianRange.high, 5));
            Print("Low: ", DoubleToString(m_asianRange.low, 5));
            Print("Range: ", DoubleToString(rangePips, 1), " pips");
         }
         else
         {
            Print("Asian Range INVALID - Size: ", DoubleToString(rangePips, 1), " pips (Need ", m_minRangePips, "-", m_maxRangePips, ")");
            m_asianRange.isValid = false;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get trend from H1 EMA                                            |
   //+------------------------------------------------------------------+
   ENUM_TREND_STATE GetTrend()
   {
      if(!UpdateIndicators()) return TREND_NONE;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      // Simple trend: price vs EMA
      if(price > m_trendEmaValue)
         m_currentTrend = TREND_BULLISH;
      else if(price < m_trendEmaValue)
         m_currentTrend = TREND_BEARISH;
      else
         m_currentTrend = TREND_NONE;

      return m_currentTrend;
   }

   //+------------------------------------------------------------------+
   //| Check ATR volatility filter                                      |
   //+------------------------------------------------------------------+
   bool IsVolatilityOK()
   {
      // ATR must be above its 20-period average (expanding volatility)
      return (m_atrValue > m_atrSmaValue);
   }

   //+------------------------------------------------------------------+
   //| Check for breakout                                               |
   //+------------------------------------------------------------------+
   void CheckBreakout()
   {
      if(!m_asianRange.isValid) return;
      if(!IsEntryWindow()) return;
      if(m_asianRange.breakoutUp || m_asianRange.breakoutDown) return;

      double pipSize = GetPipSize();
      double buffer = m_breakoutBuffer * pipSize;

      double close[];
      ArraySetAsSeries(close, true);
      if(CopyClose(m_symbol, m_entryTimeframe, 0, 2, close) < 2) return;

      // Breakout UP: Close above Asian high + buffer
      if(close[1] > m_asianRange.high + buffer)
      {
         m_asianRange.breakoutUp = true;
         m_asianRange.breakoutTime = TimeCurrent();
         m_asianRange.breakoutPrice = close[1];
         m_breakoutState = BREAKOUT_PENDING_UP;
         Print("=== BREAKOUT UP Detected ===");
         Print("Price: ", close[1], " > Asian High: ", m_asianRange.high);
      }
      // Breakout DOWN: Close below Asian low - buffer
      else if(close[1] < m_asianRange.low - buffer)
      {
         m_asianRange.breakoutDown = true;
         m_asianRange.breakoutTime = TimeCurrent();
         m_asianRange.breakoutPrice = close[1];
         m_breakoutState = BREAKOUT_PENDING_DOWN;
         Print("=== BREAKOUT DOWN Detected ===");
         Print("Price: ", close[1], " < Asian Low: ", m_asianRange.low);
      }
   }

   //+------------------------------------------------------------------+
   //| Check for retest confirmation                                    |
   //+------------------------------------------------------------------+
   void CheckRetest()
   {
      if(m_breakoutState != BREAKOUT_PENDING_UP && m_breakoutState != BREAKOUT_PENDING_DOWN)
         return;

      double pipSize = GetPipSize();
      double retestZone = m_retestBuffer * pipSize;

      double low[], high[], close[];
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(close, true);

      if(CopyLow(m_symbol, m_entryTimeframe, 0, 3, low) < 3) return;
      if(CopyHigh(m_symbol, m_entryTimeframe, 0, 3, high) < 3) return;
      if(CopyClose(m_symbol, m_entryTimeframe, 0, 3, close) < 3) return;

      // Retest for UP breakout: price pulls back toward Asian high
      if(m_breakoutState == BREAKOUT_PENDING_UP)
      {
         // Check if price retested (came back near Asian high)
         if(low[1] <= m_asianRange.high + retestZone)
         {
            // And bounced (current close above retest low)
            if(close[1] > low[1] && close[1] > m_asianRange.high)
            {
               m_breakoutState = BREAKOUT_CONFIRMED_UP;
               m_asianRange.retestComplete = true;
               Print("=== RETEST COMPLETE - BUY Confirmed ===");
            }
         }
         // Alternative: Skip retest if strong momentum (2+ candles above)
         else if(close[1] > m_asianRange.high + retestZone * 2 && close[2] > m_asianRange.high)
         {
            m_breakoutState = BREAKOUT_CONFIRMED_UP;
            m_asianRange.retestComplete = true;
            Print("=== STRONG MOMENTUM - BUY Confirmed (no retest needed) ===");
         }
      }
      // Retest for DOWN breakout: price pulls back toward Asian low
      else if(m_breakoutState == BREAKOUT_PENDING_DOWN)
      {
         // Check if price retested (came back near Asian low)
         if(high[1] >= m_asianRange.low - retestZone)
         {
            // And bounced down (current close below retest high)
            if(close[1] < high[1] && close[1] < m_asianRange.low)
            {
               m_breakoutState = BREAKOUT_CONFIRMED_DOWN;
               m_asianRange.retestComplete = true;
               Print("=== RETEST COMPLETE - SELL Confirmed ===");
            }
         }
         // Alternative: Skip retest if strong momentum
         else if(close[1] < m_asianRange.low - retestZone * 2 && close[2] < m_asianRange.low)
         {
            m_breakoutState = BREAKOUT_CONFIRMED_DOWN;
            m_asianRange.retestComplete = true;
            Print("=== STRONG MOMENTUM - SELL Confirmed (no retest needed) ===");
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Main signal function                                             |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(!m_isInitialized) return SIGNAL_NONE;

      // Update indicators
      if(!UpdateIndicators()) return SIGNAL_NONE;

      // Daily trade limit
      CheckDailyReset();
      if(m_tradesToday >= m_maxTradesPerDay) return SIGNAL_NONE;

      // Phase 1: Form Asian range during session
      UpdateAsianRange();

      // Phase 2: Finalize range at session end
      FinalizeAsianRange();

      // Phase 3: Check for breakout during entry window
      CheckBreakout();

      // Phase 4: Check for retest confirmation
      CheckRetest();

      // Phase 5: Generate signal if confirmed
      if(!IsEntryWindow()) return SIGNAL_NONE;
      if(!m_asianRange.isValid) return SIGNAL_NONE;

      // Get trend for filter
      ENUM_TREND_STATE trend = GetTrend();

      // ATR volatility filter
      if(!IsVolatilityOK())
      {
         // Print("ATR Filter: Volatility too low (ATR: ", m_atrValue, " < SMA: ", m_atrSmaValue, ")");
         return SIGNAL_NONE;
      }

      // BUY Signal: Breakout up confirmed + bullish trend
      if(m_breakoutState == BREAKOUT_CONFIRMED_UP)
      {
         if(trend == TREND_BULLISH)
         {
            Print("=== BUY SIGNAL GENERATED ===");
            Print("Asian High: ", m_asianRange.high, " | Trend: BULLISH");
            Print("ATR: ", DoubleToString(m_atrValue * 100000, 1), " > SMA: ", DoubleToString(m_atrSmaValue * 100000, 1));
            return SIGNAL_BUY;
         }
         else
         {
            Print("BUY blocked - Trend not bullish");
         }
      }

      // SELL Signal: Breakout down confirmed + bearish trend
      if(m_breakoutState == BREAKOUT_CONFIRMED_DOWN)
      {
         if(trend == TREND_BEARISH)
         {
            Print("=== SELL SIGNAL GENERATED ===");
            Print("Asian Low: ", m_asianRange.low, " | Trend: BEARISH");
            Print("ATR: ", DoubleToString(m_atrValue * 100000, 1), " > SMA: ", DoubleToString(m_atrSmaValue * 100000, 1));
            return SIGNAL_SELL;
         }
         else
         {
            Print("SELL blocked - Trend not bearish");
         }
      }

      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| Calculate SL - opposite side of Asian range                      |
   //+------------------------------------------------------------------+
   double CalculateSL(ENUM_SIGNAL_TYPE signal)
   {
      double pipSize = GetPipSize();
      double buffer = 5 * pipSize;  // 5 pips buffer

      if(signal == SIGNAL_BUY)
      {
         // SL below Asian low
         m_lastSL = m_asianRange.low - buffer;
      }
      else
      {
         // SL above Asian high
         m_lastSL = m_asianRange.high + buffer;
      }

      return m_lastSL;
   }

   //+------------------------------------------------------------------+
   //| Calculate TP using Pivot or RR                                   |
   //+------------------------------------------------------------------+
   double CalculateTP(double entryPrice, double slPrice, ENUM_SIGNAL_TYPE signal, double rrRatio)
   {
      double pipSize = GetPipSize();
      double slDistance = MathAbs(entryPrice - slPrice);

      if(signal == SIGNAL_BUY)
      {
         // Target R1 if it gives good RR, else use fixed RR
         double distToR1 = m_pivotLevels.R1 - entryPrice;
         if(distToR1 > slDistance * 1.5 && distToR1 > 0)
         {
            m_lastTP = m_pivotLevels.R1;
         }
         else
         {
            m_lastTP = entryPrice + slDistance * rrRatio;
         }
      }
      else
      {
         // Target S1 if it gives good RR, else use fixed RR
         double distToS1 = entryPrice - m_pivotLevels.S1;
         if(distToS1 > slDistance * 1.5 && distToS1 > 0)
         {
            m_lastTP = m_pivotLevels.S1;
         }
         else
         {
            m_lastTP = entryPrice - slDistance * rrRatio;
         }
      }

      return m_lastTP;
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
         // Reset Asian range for new day
         ResetAsianRange();
         m_breakoutState = BREAKOUT_NONE;
      }
   }

   //+------------------------------------------------------------------+
   //| Record trade taken                                               |
   //+------------------------------------------------------------------+
   void MarkTradeTaken(ENUM_SIGNAL_TYPE signal = SIGNAL_NONE)
   {
      m_tradesToday++;
      // Reset breakout state after trade
      m_breakoutState = BREAKOUT_NONE;
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
   void SetTradingHours(int startGMT, int endGMT) { m_entryStartGMT = startGMT; m_entryEndGMT = endGMT; }
   void SetMaxTradesPerDay(int max) { m_maxTradesPerDay = max; }
   void SetBounceZone(double pips) { m_breakoutBuffer = pips; }
   void SetRSILevels(double oversold, double overbought) { }
   void SetPullbackTolerance(double pips) { m_retestBuffer = pips; }
   void SetADXMinStrength(double strength) { }
   void SetMinRangePips(double pips) { m_minRangePips = pips; }
   void SetMaxRangePips(double pips) { m_maxRangePips = pips; }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   double GetTrendEMA() { return m_trendEmaValue; }
   double GetEntryEMA() { return m_trendEmaValue; }
   double GetRSI() { return m_rsiValue; }
   double GetADX() { return 0; }
   double GetATR() { return m_atrValue; }
   ENUM_TREND_STATE GetCurrentTrend() { return m_currentTrend; }
   int GetTradesToday() { return m_tradesToday; }
   int GetMaxTradesPerDay() { return m_maxTradesPerDay; }
   double GetLastSL() { return m_lastSL; }
   double GetLastTP() { return m_lastTP; }
   bool IsInitialized() { return m_isInitialized; }
   int GetTradingStartGMT() { return m_entryStartGMT; }
   int GetTradingEndGMT() { return m_entryEndGMT; }
   ENUM_TIMEFRAMES GetTrendTimeframe() { return m_trendTimeframe; }
   ENUM_TIMEFRAMES GetEntryTimeframe() { return m_entryTimeframe; }
   int GetTrendEmaPeriod() { return m_trendEmaPeriod; }
   int GetEntryEmaPeriod() { return m_trendEmaPeriod; }

   // Pivot getters
   double GetPivotPP() { return m_pivotLevels.PP; }
   double GetPivotR1() { return m_pivotLevels.R1; }
   double GetPivotR2() { return m_pivotLevels.R2; }
   double GetPivotS1() { return m_pivotLevels.S1; }
   double GetPivotS2() { return m_pivotLevels.S2; }

   // Asian range getters
   double GetAsianHigh() { return m_asianRange.high; }
   double GetAsianLow() { return m_asianRange.low; }
   bool IsAsianRangeValid() { return m_asianRange.isValid; }
   ENUM_BREAKOUT_STATE GetBreakoutState() { return m_breakoutState; }

   //+------------------------------------------------------------------+
   //| Get trend as string for display                                  |
   //+------------------------------------------------------------------+
   string GetTrendString()
   {
      switch(m_currentTrend)
      {
         case TREND_BULLISH: return "BULLISH";
         case TREND_BEARISH: return "BEARISH";
         default: return "NO TREND";
      }
   }

   //+------------------------------------------------------------------+
   //| Get breakout state string                                        |
   //+------------------------------------------------------------------+
   string GetBreakoutStateString()
   {
      switch(m_breakoutState)
      {
         case BREAKOUT_PENDING_UP: return "PENDING UP (wait retest)";
         case BREAKOUT_PENDING_DOWN: return "PENDING DOWN (wait retest)";
         case BREAKOUT_CONFIRMED_UP: return "CONFIRMED UP - READY";
         case BREAKOUT_CONFIRMED_DOWN: return "CONFIRMED DOWN - READY";
         default: return "NONE";
      }
   }

   //+------------------------------------------------------------------+
   //| Check if trading time                                            |
   //+------------------------------------------------------------------+
   bool IsTradingTime()
   {
      return IsEntryWindow();
   }

   //+------------------------------------------------------------------+
   //| Legacy compatibility                                             |
   //+------------------------------------------------------------------+
   bool IsTradingTime2() { return IsTradingTime(); }
   double CalculateDynamicSL(ENUM_SIGNAL_TYPE s) { return CalculateSL(s); }
};
