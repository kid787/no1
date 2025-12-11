//+------------------------------------------------------------------+
//|                                                   DowTheory.mqh |
//|                           XAUUSD Dow Theory Analysis Module      |
//|                     Copyright 2024, Your Company                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"

//--- Trend State Enumeration
enum ENUM_DOW_TREND
{
   DOW_TREND_UP = 1,        // Uptrend (Higher Highs, Higher Lows)
   DOW_TREND_DOWN = -1,     // Downtrend (Lower Highs, Lower Lows)
   DOW_TREND_RANGE = 0      // Range/Consolidation
};

//--- Wave Pattern Enumeration
enum ENUM_WAVE_PATTERN
{
   WAVE_N_UP = 1,           // N-wave (Bullish)
   WAVE_N_DOWN = -1,        // Inverse N-wave (Bearish)
   WAVE_NONE = 0            // No clear pattern
};

//--- Pivot Point Structure
struct PivotPoint
{
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
};

//--- Dow Theory Class
class CDowTheory
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   int               m_zigzagHandle;
   int               m_atrHandle;
   int               m_lookbackBars;
   double            m_minSwingSize;      // Minimum swing size in points

   PivotPoint        m_pivots[];          // Array of pivot points
   int               m_pivotCount;

   // Key pivot prices
   double            m_currentHigh;       // Current swing high
   double            m_currentLow;        // Current swing low
   double            m_previousHigh;      // Previous swing high
   double            m_previousLow;       // Previous swing low
   double            m_pushLow;           // 押し安値 (Oshi-yasune)
   double            m_returnHigh;        // 戻り高値 (Modori-takane)

   ENUM_DOW_TREND    m_currentTrend;
   ENUM_DOW_TREND    m_previousTrend;

   // Internal methods
   void              IdentifyPivots();
   void              CalculateKeyLevels();
   double            GetZigZagValue(int shift, int bufferIndex);

public:
                     CDowTheory();
                    ~CDowTheory();

   bool              Init(string symbol, ENUM_TIMEFRAMES period, int lookbackBars = 100, double minSwingPoints = 50);
   void              Deinit();
   bool              Update();

   // Main Dow Theory Methods (from prompt 2)
   ENUM_DOW_TREND    CheckDowTrendStatus();                    // メソッド1: トレンド状態の判定
   bool              IdentifyKeyPivotPoints(double &pushLow, double &returnHigh); // メソッド2
   bool              ConfirmTrendContinuity();                 // メソッド3: トレンド継続性の確認
   bool              CheckTrendReversalConfirmed();            // メソッド4: トレンド転換の確定判定

   // Getter methods
   ENUM_DOW_TREND    GetCurrentTrend() { return m_currentTrend; }
   double            GetCurrentHigh() { return m_currentHigh; }
   double            GetCurrentLow() { return m_currentLow; }
   double            GetPreviousHigh() { return m_previousHigh; }
   double            GetPreviousLow() { return m_previousLow; }
   double            GetPushLow() { return m_pushLow; }
   double            GetReturnHigh() { return m_returnHigh; }

   // Wave pattern detection
   ENUM_WAVE_PATTERN DetectWavePattern();
   bool              IsNWaveComplete();      // N波動完成判定
   bool              IsInverseNWaveComplete(); // 逆N波動完成判定
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CDowTheory::CDowTheory()
{
   m_symbol = "";
   m_period = PERIOD_H1;
   m_zigzagHandle = INVALID_HANDLE;
   m_atrHandle = INVALID_HANDLE;
   m_lookbackBars = 100;
   m_minSwingSize = 50;
   m_pivotCount = 0;
   m_currentTrend = DOW_TREND_RANGE;
   m_previousTrend = DOW_TREND_RANGE;

   m_currentHigh = 0;
   m_currentLow = 0;
   m_previousHigh = 0;
   m_previousLow = 0;
   m_pushLow = 0;
   m_returnHigh = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CDowTheory::~CDowTheory()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CDowTheory::Init(string symbol, ENUM_TIMEFRAMES period, int lookbackBars = 100, double minSwingPoints = 50)
{
   m_symbol = symbol;
   m_period = period;
   m_lookbackBars = lookbackBars;
   m_minSwingSize = minSwingPoints;

   // Create ZigZag indicator handle
   // Using custom pivot detection instead of ZigZag for more control
   m_atrHandle = iATR(m_symbol, m_period, 14);
   if(m_atrHandle == INVALID_HANDLE)
   {
      Print("Error creating ATR handle: ", GetLastError());
      return false;
   }

   ArrayResize(m_pivots, 0);
   m_pivotCount = 0;

   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CDowTheory::Deinit()
{
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }
   ArrayFree(m_pivots);
}

//+------------------------------------------------------------------+
//| Update - Call on each tick or new bar                            |
//+------------------------------------------------------------------+
bool CDowTheory::Update()
{
   IdentifyPivots();
   CalculateKeyLevels();
   m_previousTrend = m_currentTrend;
   m_currentTrend = CheckDowTrendStatus();
   return true;
}

//+------------------------------------------------------------------+
//| Identify Pivot Points using fractal logic                        |
//+------------------------------------------------------------------+
void CDowTheory::IdentifyPivots()
{
   ArrayResize(m_pivots, 0);
   m_pivotCount = 0;

   int fractalBars = 5;  // Number of bars on each side for fractal detection

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_period, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return;

   // Get ATR for minimum swing size
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(m_atrHandle, 0, 0, m_lookbackBars, atr) < m_lookbackBars) return;

   double minSwing = atr[0] * 0.5;  // Minimum swing is 50% of ATR

   // Identify swing highs and lows
   for(int i = fractalBars; i < m_lookbackBars - fractalBars; i++)
   {
      bool isSwingHigh = true;
      bool isSwingLow = true;

      // Check for swing high
      for(int j = 1; j <= fractalBars; j++)
      {
         if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
         {
            isSwingHigh = false;
            break;
         }
      }

      // Check for swing low
      for(int j = 1; j <= fractalBars; j++)
      {
         if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         PivotPoint pivot;
         pivot.price = rates[i].high;
         pivot.time = rates[i].time;
         pivot.barIndex = i;
         pivot.isHigh = true;

         int size = ArraySize(m_pivots);
         ArrayResize(m_pivots, size + 1);
         m_pivots[size] = pivot;
         m_pivotCount++;
      }

      if(isSwingLow)
      {
         PivotPoint pivot;
         pivot.price = rates[i].low;
         pivot.time = rates[i].time;
         pivot.barIndex = i;
         pivot.isHigh = false;

         int size = ArraySize(m_pivots);
         ArrayResize(m_pivots, size + 1);
         m_pivots[size] = pivot;
         m_pivotCount++;
      }
   }

   // Sort pivots by time (most recent first)
   // Already in order since we iterate from recent to old
}

//+------------------------------------------------------------------+
//| Calculate Key Levels from Pivots                                  |
//+------------------------------------------------------------------+
void CDowTheory::CalculateKeyLevels()
{
   if(m_pivotCount < 4) return;

   // Find the most recent 2 swing highs and 2 swing lows
   double highs[];
   double lows[];
   ArrayResize(highs, 0);
   ArrayResize(lows, 0);

   for(int i = 0; i < m_pivotCount && (ArraySize(highs) < 3 || ArraySize(lows) < 3); i++)
   {
      if(m_pivots[i].isHigh && ArraySize(highs) < 3)
      {
         int size = ArraySize(highs);
         ArrayResize(highs, size + 1);
         highs[size] = m_pivots[i].price;
      }
      else if(!m_pivots[i].isHigh && ArraySize(lows) < 3)
      {
         int size = ArraySize(lows);
         ArrayResize(lows, size + 1);
         lows[size] = m_pivots[i].price;
      }
   }

   if(ArraySize(highs) >= 2)
   {
      m_currentHigh = highs[0];
      m_previousHigh = highs[1];
   }

   if(ArraySize(lows) >= 2)
   {
      m_currentLow = lows[0];
      m_previousLow = lows[1];
   }
}

//+------------------------------------------------------------------+
//| Check Dow Trend Status (Method 1)                                 |
//| Returns: DOW_TREND_UP, DOW_TREND_DOWN, or DOW_TREND_RANGE        |
//+------------------------------------------------------------------+
ENUM_DOW_TREND CDowTheory::CheckDowTrendStatus()
{
   if(m_pivotCount < 4) return DOW_TREND_RANGE;

   // Uptrend: Higher Highs AND Higher Lows (N波動の連続)
   bool higherHighs = m_currentHigh > m_previousHigh;
   bool higherLows = m_currentLow > m_previousLow;

   // Downtrend: Lower Highs AND Lower Lows (逆N波動の連続)
   bool lowerHighs = m_currentHigh < m_previousHigh;
   bool lowerLows = m_currentLow < m_previousLow;

   if(higherHighs && higherLows)
      return DOW_TREND_UP;
   else if(lowerHighs && lowerLows)
      return DOW_TREND_DOWN;
   else
      return DOW_TREND_RANGE;
}

//+------------------------------------------------------------------+
//| Identify Key Pivot Points (Method 2)                              |
//| Identifies 押し安値 and 戻り高値                                    |
//+------------------------------------------------------------------+
bool CDowTheory::IdentifyKeyPivotPoints(double &pushLow, double &returnHigh)
{
   if(m_pivotCount < 6) return false;

   // 押し安値 (Push Low): The low that formed before the current high broke previous high
   // 戻り高値 (Return High): The high that formed before the current low broke previous low

   // Find Push Low for uptrend
   m_pushLow = 0;
   for(int i = 0; i < m_pivotCount - 1; i++)
   {
      if(!m_pivots[i].isHigh) // This is a low
      {
         // Check if the high after this low broke the previous high
         for(int j = i - 1; j >= 0; j--)
         {
            if(m_pivots[j].isHigh)
            {
               // Check if this high broke the high before the low
               for(int k = i + 1; k < m_pivotCount; k++)
               {
                  if(m_pivots[k].isHigh && m_pivots[j].price > m_pivots[k].price)
                  {
                     m_pushLow = m_pivots[i].price;
                     break;
                  }
               }
               break;
            }
         }
         if(m_pushLow > 0) break;
      }
   }

   // Find Return High for downtrend
   m_returnHigh = 0;
   for(int i = 0; i < m_pivotCount - 1; i++)
   {
      if(m_pivots[i].isHigh) // This is a high
      {
         // Check if the low after this high broke the previous low
         for(int j = i - 1; j >= 0; j--)
         {
            if(!m_pivots[j].isHigh)
            {
               // Check if this low broke the low before the high
               for(int k = i + 1; k < m_pivotCount; k++)
               {
                  if(!m_pivots[k].isHigh && m_pivots[j].price < m_pivots[k].price)
                  {
                     m_returnHigh = m_pivots[i].price;
                     break;
                  }
               }
               break;
            }
         }
         if(m_returnHigh > 0) break;
      }
   }

   pushLow = m_pushLow;
   returnHigh = m_returnHigh;

   return (m_pushLow > 0 || m_returnHigh > 0);
}

//+------------------------------------------------------------------+
//| Confirm Trend Continuity (Method 3)                               |
//+------------------------------------------------------------------+
bool CDowTheory::ConfirmTrendContinuity()
{
   if(m_pivotCount < 4) return false;

   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   if(m_currentTrend == DOW_TREND_UP)
   {
      // In uptrend, check if price is still making higher highs
      // N波動の連続性が維持されているか
      return (currentPrice > m_previousLow && m_currentHigh > m_previousHigh);
   }
   else if(m_currentTrend == DOW_TREND_DOWN)
   {
      // In downtrend, check if price is still making lower lows
      // 逆N波動の連続性が維持されているか
      return (currentPrice < m_previousHigh && m_currentLow < m_previousLow);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check Trend Reversal Confirmed (Method 4)                         |
//+------------------------------------------------------------------+
bool CDowTheory::CheckTrendReversalConfirmed()
{
   if(m_pivotCount < 4) return false;

   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // 上昇→下降への転換判定
   if(m_previousTrend == DOW_TREND_UP || m_currentTrend == DOW_TREND_UP)
   {
      // 条件1: 押し安値を明確に下抜け (買いの支配の崩壊)
      // 条件2: 高値を切り下げ (売りの圧力の優勢)
      if(m_pushLow > 0 && currentPrice < m_pushLow)
      {
         if(m_currentHigh < m_previousHigh)
         {
            return true; // 逆N波動完成 - 下降トレンドへ転換
         }
      }
   }

   // 下降→上昇への転換判定
   if(m_previousTrend == DOW_TREND_DOWN || m_currentTrend == DOW_TREND_DOWN)
   {
      // 条件1: 戻り高値を明確に上抜け (売りの支配の崩壊)
      // 条件2: 安値を切り上げ (買いの勢いの優勢)
      if(m_returnHigh > 0 && currentPrice > m_returnHigh)
      {
         if(m_currentLow > m_previousLow)
         {
            return true; // N波動完成 - 上昇トレンドへ転換
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Detect Wave Pattern                                               |
//+------------------------------------------------------------------+
ENUM_WAVE_PATTERN CDowTheory::DetectWavePattern()
{
   if(m_pivotCount < 4) return WAVE_NONE;

   // N-wave (Bullish): Low -> High -> Higher Low -> Higher High
   bool nWave = (m_currentHigh > m_previousHigh) && (m_currentLow > m_previousLow);

   // Inverse N-wave (Bearish): High -> Low -> Lower High -> Lower Low
   bool inverseNWave = (m_currentHigh < m_previousHigh) && (m_currentLow < m_previousLow);

   if(nWave) return WAVE_N_UP;
   if(inverseNWave) return WAVE_N_DOWN;

   return WAVE_NONE;
}

//+------------------------------------------------------------------+
//| Check if N-Wave is Complete (Bullish)                            |
//+------------------------------------------------------------------+
bool CDowTheory::IsNWaveComplete()
{
   return (DetectWavePattern() == WAVE_N_UP);
}

//+------------------------------------------------------------------+
//| Check if Inverse N-Wave is Complete (Bearish)                    |
//+------------------------------------------------------------------+
bool CDowTheory::IsInverseNWaveComplete()
{
   return (DetectWavePattern() == WAVE_N_DOWN);
}
