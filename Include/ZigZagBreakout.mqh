//+------------------------------------------------------------------+
//|                                              ZigZagBreakout.mqh |
//|                     ZigZag Breakout Filter for Dow Theory EA     |
//|                              Copyright 2024                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""

//+------------------------------------------------------------------+
//| ZigZag Breakout Class                                            |
//+------------------------------------------------------------------+
class CZigZagBreakout
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_zigzagHandle;

   // ZigZag Parameters
   int               m_depth;
   int               m_deviation;
   int               m_backstep;

   // Detected peaks and valleys
   double            m_lastHigh;        // 直近のZigZag高値
   double            m_lastLow;         // 直近のZigZag安値
   double            m_prevHigh;        // 1つ前のZigZag高値
   double            m_prevLow;         // 1つ前のZigZag安値
   int               m_lastHighBar;     // 直近高値のバー位置
   int               m_lastLowBar;      // 直近安値のバー位置

   // Breakout state
   bool              m_bullishBreakout; // 上方ブレイクアウト発生
   bool              m_bearishBreakout; // 下方ブレイクアウト発生

public:
                     CZigZagBreakout();
                    ~CZigZagBreakout();

   // Initialization
   bool              Init(string symbol, ENUM_TIMEFRAMES timeframe,
                          int depth = 12, int deviation = 5, int backstep = 3);
   void              Deinit();

   // Update and Analysis
   bool              Update();
   bool              FindZigZagPoints(int lookback = 200);

   // Signal Methods
   bool              IsBullishBreakout();    // 買いブレイクアウト確認
   bool              IsBearishBreakout();    // 売りブレイクアウト確認
   bool              ConfirmBuySignal();     // 買いシグナルフィルター
   bool              ConfirmSellSignal();    // 売りシグナルフィルター

   // Getters
   double            GetLastHigh()     { return m_lastHigh; }
   double            GetLastLow()      { return m_lastLow; }
   double            GetPrevHigh()     { return m_prevHigh; }
   double            GetPrevLow()      { return m_prevLow; }
   int               GetLastHighBar()  { return m_lastHighBar; }
   int               GetLastLowBar()   { return m_lastLowBar; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CZigZagBreakout::CZigZagBreakout()
{
   m_symbol = "";
   m_timeframe = PERIOD_CURRENT;
   m_zigzagHandle = INVALID_HANDLE;

   m_depth = 12;
   m_deviation = 5;
   m_backstep = 3;

   m_lastHigh = 0;
   m_lastLow = 0;
   m_prevHigh = 0;
   m_prevLow = 0;
   m_lastHighBar = 0;
   m_lastLowBar = 0;

   m_bullishBreakout = false;
   m_bearishBreakout = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CZigZagBreakout::~CZigZagBreakout()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize ZigZag indicator                                       |
//+------------------------------------------------------------------+
bool CZigZagBreakout::Init(string symbol, ENUM_TIMEFRAMES timeframe,
                           int depth, int deviation, int backstep)
{
   m_symbol = symbol;
   m_timeframe = timeframe;
   m_depth = depth;
   m_deviation = deviation;
   m_backstep = backstep;

   // Create ZigZag indicator handle
   m_zigzagHandle = iCustom(m_symbol, m_timeframe, "Examples\\ZigZag",
                            m_depth, m_deviation, m_backstep);

   if(m_zigzagHandle == INVALID_HANDLE)
   {
      Print("Error creating ZigZag indicator handle: ", GetLastError());
      return false;
   }

   Print("ZigZag Breakout Filter initialized: Depth=", m_depth,
         " Deviation=", m_deviation, " Backstep=", m_backstep);

   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CZigZagBreakout::Deinit()
{
   if(m_zigzagHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_zigzagHandle);
      m_zigzagHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Update ZigZag data                                                |
//+------------------------------------------------------------------+
bool CZigZagBreakout::Update()
{
   if(m_zigzagHandle == INVALID_HANDLE)
      return false;

   // Find ZigZag peaks and valleys
   if(!FindZigZagPoints(200))
      return false;

   // Check for breakouts
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // Bullish breakout: price breaks above last ZigZag high
   m_bullishBreakout = (currentPrice > m_lastHigh && m_lastHigh > 0);

   // Bearish breakout: price breaks below last ZigZag low
   m_bearishBreakout = (currentPrice < m_lastLow && m_lastLow > 0);

   return true;
}

//+------------------------------------------------------------------+
//| Find ZigZag peaks and valleys                                     |
//+------------------------------------------------------------------+
bool CZigZagBreakout::FindZigZagPoints(int lookback)
{
   double zigzagBuffer[];
   ArraySetAsSeries(zigzagBuffer, true);

   // Copy ZigZag buffer
   if(CopyBuffer(m_zigzagHandle, 0, 0, lookback, zigzagBuffer) <= 0)
   {
      Print("Error copying ZigZag buffer: ", GetLastError());
      return false;
   }

   // Get High/Low prices for comparison
   double highPrices[];
   double lowPrices[];
   ArraySetAsSeries(highPrices, true);
   ArraySetAsSeries(lowPrices, true);

   if(CopyHigh(m_symbol, m_timeframe, 0, lookback, highPrices) <= 0)
      return false;
   if(CopyLow(m_symbol, m_timeframe, 0, lookback, lowPrices) <= 0)
      return false;

   // Find peaks (highs) and valleys (lows)
   int highCount = 0;
   int lowCount = 0;
   double highs[4];
   double lows[4];
   int highBars[4];
   int lowBars[4];

   ArrayInitialize(highs, 0);
   ArrayInitialize(lows, 0);
   ArrayInitialize(highBars, 0);
   ArrayInitialize(lowBars, 0);

   for(int i = 1; i < lookback && (highCount < 4 || lowCount < 4); i++)
   {
      double zz = zigzagBuffer[i];

      if(zz == 0)
         continue;

      // Normalize for comparison
      double zzNorm = NormalizeDouble(zz, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      double highNorm = NormalizeDouble(highPrices[i], (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      double lowNorm = NormalizeDouble(lowPrices[i], (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));

      // Check if this is a peak (high)
      if(zzNorm == highNorm && highCount < 4)
      {
         highs[highCount] = zz;
         highBars[highCount] = i;
         highCount++;
      }
      // Check if this is a valley (low)
      else if(zzNorm == lowNorm && lowCount < 4)
      {
         lows[lowCount] = zz;
         lowBars[lowCount] = i;
         lowCount++;
      }
   }

   // Store the last two highs and lows
   if(highCount >= 2)
   {
      m_lastHigh = highs[0];
      m_prevHigh = highs[1];
      m_lastHighBar = highBars[0];
   }

   if(lowCount >= 2)
   {
      m_lastLow = lows[0];
      m_prevLow = lows[1];
      m_lastLowBar = lowBars[0];
   }

   return (highCount >= 1 && lowCount >= 1);
}

//+------------------------------------------------------------------+
//| Check for bullish breakout                                        |
//+------------------------------------------------------------------+
bool CZigZagBreakout::IsBullishBreakout()
{
   return m_bullishBreakout;
}

//+------------------------------------------------------------------+
//| Check for bearish breakout                                        |
//+------------------------------------------------------------------+
bool CZigZagBreakout::IsBearishBreakout()
{
   return m_bearishBreakout;
}

//+------------------------------------------------------------------+
//| Confirm buy signal with ZigZag filter                             |
//| 条件: 価格がZigZag直近高値を上抜け、または高値切り上げ中           |
//+------------------------------------------------------------------+
bool CZigZagBreakout::ConfirmBuySignal()
{
   if(m_lastHigh == 0 || m_lastLow == 0)
      return true;  // ZigZagデータ不足時はフィルターをパス

   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // 条件1: 現在価格がZigZag直近高値を上抜け（ブレイクアウト）
   if(currentPrice > m_lastHigh)
      return true;

   // 条件2: 高値切り上げパターン（上昇トレンド確認）
   if(m_prevHigh > 0 && m_lastHigh > m_prevHigh)
   {
      // さらに安値も切り上げていれば強い買いシグナル
      if(m_prevLow > 0 && m_lastLow > m_prevLow)
         return true;
   }

   // 条件3: 価格がZigZag直近安値より上にある（下降トレンドではない）
   if(currentPrice > m_lastLow)
   {
      // 直近高値に近づいている（ブレイクアウト寸前）
      double range = m_lastHigh - m_lastLow;
      if(range > 0 && currentPrice > m_lastLow + range * 0.7)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Confirm sell signal with ZigZag filter                            |
//| 条件: 価格がZigZag直近安値を下抜け、または安値切り下げ中           |
//+------------------------------------------------------------------+
bool CZigZagBreakout::ConfirmSellSignal()
{
   if(m_lastHigh == 0 || m_lastLow == 0)
      return true;  // ZigZagデータ不足時はフィルターをパス

   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // 条件1: 現在価格がZigZag直近安値を下抜け（ブレイクアウト）
   if(currentPrice < m_lastLow)
      return true;

   // 条件2: 安値切り下げパターン（下降トレンド確認）
   if(m_prevLow > 0 && m_lastLow < m_prevLow)
   {
      // さらに高値も切り下げていれば強い売りシグナル
      if(m_prevHigh > 0 && m_lastHigh < m_prevHigh)
         return true;
   }

   // 条件3: 価格がZigZag直近高値より下にある（上昇トレンドではない）
   if(currentPrice < m_lastHigh)
   {
      // 直近安値に近づいている（ブレイクアウト寸前）
      double range = m_lastHigh - m_lastLow;
      if(range > 0 && currentPrice < m_lastHigh - range * 0.7)
         return true;
   }

   return false;
}
//+------------------------------------------------------------------+
