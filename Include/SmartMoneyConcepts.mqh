//+------------------------------------------------------------------+
//|                                          SmartMoneyConcepts.mqh  |
//|              Smart Money Concepts (SMC) Analysis Module           |
//|              Order Blocks, FVG, BOS Detection                     |
//|                     Copyright 2024, Your Company                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"

//--- Order Block Type
enum ENUM_OB_TYPE
{
   OB_BULLISH = 1,    // Bullish Order Block (demand zone)
   OB_BEARISH = -1,   // Bearish Order Block (supply zone)
   OB_NONE = 0        // No order block
};

//--- Fair Value Gap Type
enum ENUM_FVG_TYPE
{
   FVG_BULLISH = 1,   // Bullish FVG (price should revisit upward)
   FVG_BEARISH = -1,  // Bearish FVG (price should revisit downward)
   FVG_NONE = 0       // No FVG
};

//--- Break of Structure Type
enum ENUM_BOS_TYPE
{
   BOS_BULLISH = 1,   // Bullish break of structure
   BOS_BEARISH = -1,  // Bearish break of structure
   BOS_NONE = 0       // No break of structure
};

//--- Order Block Structure
struct OrderBlock
{
   ENUM_OB_TYPE type;
   double       highPrice;
   double       lowPrice;
   datetime     time;
   int          barIndex;
   bool         isMitigated;  // True if price has returned to this OB
   bool         isValid;
};

//--- Fair Value Gap Structure
struct FairValueGap
{
   ENUM_FVG_TYPE type;
   double        highPrice;    // Top of the gap
   double        lowPrice;     // Bottom of the gap
   datetime      time;
   int           barIndex;
   bool          isFilled;     // True if gap has been filled
   bool          isValid;
};

//--- Break of Structure Structure
struct BreakOfStructure
{
   ENUM_BOS_TYPE type;
   double        breakPrice;   // Price where structure broke
   datetime      time;
   int           barIndex;
   bool          isConfirmed;
};

//--- Smart Money Concepts Class
class CSmartMoneyConcepts
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   int               m_lookbackBars;

   // Order Blocks array
   OrderBlock        m_orderBlocks[];
   int               m_obCount;
   int               m_maxOrderBlocks;

   // Fair Value Gaps array
   FairValueGap      m_fvgArray[];
   int               m_fvgCount;
   int               m_maxFVGs;

   // Break of Structure history
   BreakOfStructure  m_bosHistory[];
   int               m_bosCount;

   // Swing points for BOS detection
   double            m_lastSwingHigh;
   double            m_lastSwingLow;
   datetime          m_lastSwingHighTime;
   datetime          m_lastSwingLowTime;

   // Internal methods
   void              DetectOrderBlocks();
   void              DetectFairValueGaps();
   void              DetectBreakOfStructure();
   void              UpdateMitigation();
   void              UpdateFVGFill();
   bool              IsSwingHigh(int index, int leftBars, int rightBars);
   bool              IsSwingLow(int index, int leftBars, int rightBars);

public:
                     CSmartMoneyConcepts();
                    ~CSmartMoneyConcepts();

   bool              Init(string symbol, ENUM_TIMEFRAMES period, int lookbackBars = 100);
   void              Deinit();
   bool              Update();

   // Order Block methods
   int               GetOrderBlockCount() { return m_obCount; }
   bool              GetOrderBlock(int index, OrderBlock &ob);
   bool              GetNearestBullishOB(double price, OrderBlock &ob);
   bool              GetNearestBearishOB(double price, OrderBlock &ob);
   bool              IsPriceInOrderBlock(double price, OrderBlock &ob);

   // Fair Value Gap methods
   int               GetFVGCount() { return m_fvgCount; }
   bool              GetFVG(int index, FairValueGap &fvg);
   bool              GetNearestBullishFVG(double price, FairValueGap &fvg);
   bool              GetNearestBearishFVG(double price, FairValueGap &fvg);
   bool              IsPriceInFVG(double price, FairValueGap &fvg);

   // Break of Structure methods
   ENUM_BOS_TYPE     GetLastBOS();
   bool              HasRecentBullishBOS(int barsBack = 10);
   bool              HasRecentBearishBOS(int barsBack = 10);

   // Combined analysis
   bool              IsBullishSetup();   // OB + FVG + BOS alignment
   bool              IsBearishSetup();   // OB + FVG + BOS alignment

   // Entry zone detection
   bool              GetBullishEntryZone(double &zoneHigh, double &zoneLow);
   bool              GetBearishEntryZone(double &zoneHigh, double &zoneLow);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSmartMoneyConcepts::CSmartMoneyConcepts()
{
   m_symbol = "";
   m_period = PERIOD_H1;
   m_lookbackBars = 100;
   m_obCount = 0;
   m_fvgCount = 0;
   m_bosCount = 0;
   m_maxOrderBlocks = 20;
   m_maxFVGs = 20;
   m_lastSwingHigh = 0;
   m_lastSwingLow = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSmartMoneyConcepts::~CSmartMoneyConcepts()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::Init(string symbol, ENUM_TIMEFRAMES period, int lookbackBars = 100)
{
   m_symbol = symbol;
   m_period = period;
   m_lookbackBars = lookbackBars;

   ArrayResize(m_orderBlocks, m_maxOrderBlocks);
   ArrayResize(m_fvgArray, m_maxFVGs);
   ArrayResize(m_bosHistory, 50);

   m_obCount = 0;
   m_fvgCount = 0;
   m_bosCount = 0;

   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CSmartMoneyConcepts::Deinit()
{
   ArrayFree(m_orderBlocks);
   ArrayFree(m_fvgArray);
   ArrayFree(m_bosHistory);
}

//+------------------------------------------------------------------+
//| Update - Call on new bar                                          |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::Update()
{
   DetectOrderBlocks();
   DetectFairValueGaps();
   DetectBreakOfStructure();
   UpdateMitigation();
   UpdateFVGFill();

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                      |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::IsSwingHigh(int index, int leftBars, int rightBars)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_period, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return false;

   if(index < rightBars || index >= m_lookbackBars - leftBars) return false;

   double high = rates[index].high;

   for(int i = 1; i <= leftBars; i++)
   {
      if(rates[index + i].high >= high) return false;
   }

   for(int i = 1; i <= rightBars; i++)
   {
      if(rates[index - i].high >= high) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                       |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::IsSwingLow(int index, int leftBars, int rightBars)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_period, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return false;

   if(index < rightBars || index >= m_lookbackBars - leftBars) return false;

   double low = rates[index].low;

   for(int i = 1; i <= leftBars; i++)
   {
      if(rates[index + i].low <= low) return false;
   }

   for(int i = 1; i <= rightBars; i++)
   {
      if(rates[index - i].low <= low) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Detect Order Blocks                                               |
//| Order Block = Last bearish candle before bullish move (demand)    |
//|             = Last bullish candle before bearish move (supply)    |
//+------------------------------------------------------------------+
void CSmartMoneyConcepts::DetectOrderBlocks()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_period, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return;

   m_obCount = 0;

   for(int i = 3; i < m_lookbackBars - 3 && m_obCount < m_maxOrderBlocks; i++)
   {
      // Bullish Order Block detection
      // Look for: bearish candle followed by strong bullish move that breaks structure
      if(rates[i].close < rates[i].open) // Bearish candle
      {
         // Check if next candles make a strong bullish move
         double moveUp = 0;
         for(int j = 1; j <= 3 && (i - j) >= 0; j++)
         {
            moveUp += rates[i - j].close - rates[i - j].open;
         }

         // Strong bullish move criteria
         double atr = 0;
         for(int k = i; k < i + 14 && k < m_lookbackBars; k++)
         {
            atr += rates[k].high - rates[k].low;
         }
         atr /= 14;

         if(moveUp > atr * 1.5) // Strong move
         {
            OrderBlock ob;
            ob.type = OB_BULLISH;
            ob.highPrice = rates[i].high;
            ob.lowPrice = rates[i].low;
            ob.time = rates[i].time;
            ob.barIndex = i;
            ob.isMitigated = false;
            ob.isValid = true;

            m_orderBlocks[m_obCount] = ob;
            m_obCount++;
         }
      }

      // Bearish Order Block detection
      if(rates[i].close > rates[i].open) // Bullish candle
      {
         // Check if next candles make a strong bearish move
         double moveDown = 0;
         for(int j = 1; j <= 3 && (i - j) >= 0; j++)
         {
            moveDown += rates[i - j].open - rates[i - j].close;
         }

         double atr = 0;
         for(int k = i; k < i + 14 && k < m_lookbackBars; k++)
         {
            atr += rates[k].high - rates[k].low;
         }
         atr /= 14;

         if(moveDown > atr * 1.5) // Strong move
         {
            OrderBlock ob;
            ob.type = OB_BEARISH;
            ob.highPrice = rates[i].high;
            ob.lowPrice = rates[i].low;
            ob.time = rates[i].time;
            ob.barIndex = i;
            ob.isMitigated = false;
            ob.isValid = true;

            m_orderBlocks[m_obCount] = ob;
            m_obCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps                                            |
//| FVG = Gap between candle 1's low and candle 3's high (bullish)   |
//|     = Gap between candle 1's high and candle 3's low (bearish)   |
//+------------------------------------------------------------------+
void CSmartMoneyConcepts::DetectFairValueGaps()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_period, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return;

   m_fvgCount = 0;

   for(int i = 2; i < m_lookbackBars - 1 && m_fvgCount < m_maxFVGs; i++)
   {
      // Bullish FVG: Gap between bar[i+1] low and bar[i-1] high
      // This occurs during strong bullish moves
      if(rates[i - 1].high < rates[i + 1].low)
      {
         FairValueGap fvg;
         fvg.type = FVG_BULLISH;
         fvg.lowPrice = rates[i - 1].high;
         fvg.highPrice = rates[i + 1].low;
         fvg.time = rates[i].time;
         fvg.barIndex = i;
         fvg.isFilled = false;
         fvg.isValid = true;

         m_fvgArray[m_fvgCount] = fvg;
         m_fvgCount++;
      }

      // Bearish FVG: Gap between bar[i+1] high and bar[i-1] low
      if(rates[i - 1].low > rates[i + 1].high)
      {
         FairValueGap fvg;
         fvg.type = FVG_BEARISH;
         fvg.highPrice = rates[i - 1].low;
         fvg.lowPrice = rates[i + 1].high;
         fvg.time = rates[i].time;
         fvg.barIndex = i;
         fvg.isFilled = false;
         fvg.isValid = true;

         m_fvgArray[m_fvgCount] = fvg;
         m_fvgCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                         |
//+------------------------------------------------------------------+
void CSmartMoneyConcepts::DetectBreakOfStructure()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_period, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return;

   // Find swing highs and lows
   for(int i = 5; i < m_lookbackBars - 5; i++)
   {
      if(IsSwingHigh(i, 5, 5))
      {
         if(m_lastSwingHigh > 0 && rates[i].high > m_lastSwingHigh)
         {
            // Bullish BOS - new higher high
            BreakOfStructure bos;
            bos.type = BOS_BULLISH;
            bos.breakPrice = m_lastSwingHigh;
            bos.time = rates[i].time;
            bos.barIndex = i;
            bos.isConfirmed = true;

            if(m_bosCount < 50)
            {
               m_bosHistory[m_bosCount] = bos;
               m_bosCount++;
            }
         }
         m_lastSwingHigh = rates[i].high;
         m_lastSwingHighTime = rates[i].time;
      }

      if(IsSwingLow(i, 5, 5))
      {
         if(m_lastSwingLow > 0 && rates[i].low < m_lastSwingLow)
         {
            // Bearish BOS - new lower low
            BreakOfStructure bos;
            bos.type = BOS_BEARISH;
            bos.breakPrice = m_lastSwingLow;
            bos.time = rates[i].time;
            bos.barIndex = i;
            bos.isConfirmed = true;

            if(m_bosCount < 50)
            {
               m_bosHistory[m_bosCount] = bos;
               m_bosCount++;
            }
         }
         m_lastSwingLow = rates[i].low;
         m_lastSwingLowTime = rates[i].time;
      }
   }
}

//+------------------------------------------------------------------+
//| Update Order Block Mitigation Status                              |
//+------------------------------------------------------------------+
void CSmartMoneyConcepts::UpdateMitigation()
{
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   for(int i = 0; i < m_obCount; i++)
   {
      if(!m_orderBlocks[i].isValid) continue;
      if(m_orderBlocks[i].isMitigated) continue;

      // Check if price has visited the order block
      if(currentPrice >= m_orderBlocks[i].lowPrice &&
         currentPrice <= m_orderBlocks[i].highPrice)
      {
         m_orderBlocks[i].isMitigated = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Update FVG Fill Status                                            |
//+------------------------------------------------------------------+
void CSmartMoneyConcepts::UpdateFVGFill()
{
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   for(int i = 0; i < m_fvgCount; i++)
   {
      if(!m_fvgArray[i].isValid) continue;
      if(m_fvgArray[i].isFilled) continue;

      // Check if price has filled the gap
      if(m_fvgArray[i].type == FVG_BULLISH)
      {
         // Bullish FVG filled when price drops into it
         if(currentPrice <= m_fvgArray[i].highPrice)
         {
            m_fvgArray[i].isFilled = true;
         }
      }
      else if(m_fvgArray[i].type == FVG_BEARISH)
      {
         // Bearish FVG filled when price rises into it
         if(currentPrice >= m_fvgArray[i].lowPrice)
         {
            m_fvgArray[i].isFilled = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get Order Block by Index                                          |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetOrderBlock(int index, OrderBlock &ob)
{
   if(index < 0 || index >= m_obCount) return false;
   ob = m_orderBlocks[index];
   return true;
}

//+------------------------------------------------------------------+
//| Get Nearest Bullish Order Block                                   |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetNearestBullishOB(double price, OrderBlock &ob)
{
   double minDistance = DBL_MAX;
   int nearestIndex = -1;

   for(int i = 0; i < m_obCount; i++)
   {
      if(m_orderBlocks[i].type != OB_BULLISH) continue;
      if(!m_orderBlocks[i].isValid || m_orderBlocks[i].isMitigated) continue;

      // Look for OB below current price
      if(m_orderBlocks[i].highPrice < price)
      {
         double distance = price - m_orderBlocks[i].highPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestIndex = i;
         }
      }
   }

   if(nearestIndex >= 0)
   {
      ob = m_orderBlocks[nearestIndex];
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get Nearest Bearish Order Block                                   |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetNearestBearishOB(double price, OrderBlock &ob)
{
   double minDistance = DBL_MAX;
   int nearestIndex = -1;

   for(int i = 0; i < m_obCount; i++)
   {
      if(m_orderBlocks[i].type != OB_BEARISH) continue;
      if(!m_orderBlocks[i].isValid || m_orderBlocks[i].isMitigated) continue;

      // Look for OB above current price
      if(m_orderBlocks[i].lowPrice > price)
      {
         double distance = m_orderBlocks[i].lowPrice - price;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestIndex = i;
         }
      }
   }

   if(nearestIndex >= 0)
   {
      ob = m_orderBlocks[nearestIndex];
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if Price is in Order Block                                  |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::IsPriceInOrderBlock(double price, OrderBlock &ob)
{
   for(int i = 0; i < m_obCount; i++)
   {
      if(!m_orderBlocks[i].isValid) continue;

      if(price >= m_orderBlocks[i].lowPrice && price <= m_orderBlocks[i].highPrice)
      {
         ob = m_orderBlocks[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get FVG by Index                                                  |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetFVG(int index, FairValueGap &fvg)
{
   if(index < 0 || index >= m_fvgCount) return false;
   fvg = m_fvgArray[index];
   return true;
}

//+------------------------------------------------------------------+
//| Get Nearest Bullish FVG                                           |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetNearestBullishFVG(double price, FairValueGap &fvg)
{
   double minDistance = DBL_MAX;
   int nearestIndex = -1;

   for(int i = 0; i < m_fvgCount; i++)
   {
      if(m_fvgArray[i].type != FVG_BULLISH) continue;
      if(!m_fvgArray[i].isValid || m_fvgArray[i].isFilled) continue;

      if(m_fvgArray[i].highPrice < price)
      {
         double distance = price - m_fvgArray[i].highPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestIndex = i;
         }
      }
   }

   if(nearestIndex >= 0)
   {
      fvg = m_fvgArray[nearestIndex];
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get Nearest Bearish FVG                                           |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetNearestBearishFVG(double price, FairValueGap &fvg)
{
   double minDistance = DBL_MAX;
   int nearestIndex = -1;

   for(int i = 0; i < m_fvgCount; i++)
   {
      if(m_fvgArray[i].type != FVG_BEARISH) continue;
      if(!m_fvgArray[i].isValid || m_fvgArray[i].isFilled) continue;

      if(m_fvgArray[i].lowPrice > price)
      {
         double distance = m_fvgArray[i].lowPrice - price;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestIndex = i;
         }
      }
   }

   if(nearestIndex >= 0)
   {
      fvg = m_fvgArray[nearestIndex];
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if Price is in FVG                                          |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::IsPriceInFVG(double price, FairValueGap &fvg)
{
   for(int i = 0; i < m_fvgCount; i++)
   {
      if(!m_fvgArray[i].isValid) continue;

      if(price >= m_fvgArray[i].lowPrice && price <= m_fvgArray[i].highPrice)
      {
         fvg = m_fvgArray[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get Last Break of Structure Type                                  |
//+------------------------------------------------------------------+
ENUM_BOS_TYPE CSmartMoneyConcepts::GetLastBOS()
{
   if(m_bosCount == 0) return BOS_NONE;
   return m_bosHistory[m_bosCount - 1].type;
}

//+------------------------------------------------------------------+
//| Check for Recent Bullish BOS                                      |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::HasRecentBullishBOS(int barsBack = 10)
{
   for(int i = m_bosCount - 1; i >= 0; i--)
   {
      if(m_bosHistory[i].barIndex <= barsBack && m_bosHistory[i].type == BOS_BULLISH)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for Recent Bearish BOS                                      |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::HasRecentBearishBOS(int barsBack = 10)
{
   for(int i = m_bosCount - 1; i >= 0; i--)
   {
      if(m_bosHistory[i].barIndex <= barsBack && m_bosHistory[i].type == BOS_BEARISH)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for Bullish Setup (OB + FVG + BOS alignment)               |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::IsBullishSetup()
{
   // Need recent bullish BOS
   if(!HasRecentBullishBOS(20)) return false;

   // Need a valid bullish order block nearby
   double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   OrderBlock ob;
   if(!GetNearestBullishOB(price, ob)) return false;

   // Check if OB is within reasonable distance (1% of price)
   if((price - ob.highPrice) > price * 0.01) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check for Bearish Setup (OB + FVG + BOS alignment)               |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::IsBearishSetup()
{
   // Need recent bearish BOS
   if(!HasRecentBearishBOS(20)) return false;

   // Need a valid bearish order block nearby
   double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   OrderBlock ob;
   if(!GetNearestBearishOB(price, ob)) return false;

   // Check if OB is within reasonable distance (1% of price)
   if((ob.lowPrice - price) > price * 0.01) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get Bullish Entry Zone                                            |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetBullishEntryZone(double &zoneHigh, double &zoneLow)
{
   double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // Try to get nearest bullish OB first
   OrderBlock ob;
   if(GetNearestBullishOB(price, ob))
   {
      zoneHigh = ob.highPrice;
      zoneLow = ob.lowPrice;
      return true;
   }

   // Otherwise try FVG
   FairValueGap fvg;
   if(GetNearestBullishFVG(price, fvg))
   {
      zoneHigh = fvg.highPrice;
      zoneLow = fvg.lowPrice;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get Bearish Entry Zone                                            |
//+------------------------------------------------------------------+
bool CSmartMoneyConcepts::GetBearishEntryZone(double &zoneHigh, double &zoneLow)
{
   double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // Try to get nearest bearish OB first
   OrderBlock ob;
   if(GetNearestBearishOB(price, ob))
   {
      zoneHigh = ob.highPrice;
      zoneLow = ob.lowPrice;
      return true;
   }

   // Otherwise try FVG
   FairValueGap fvg;
   if(GetNearestBearishFVG(price, fvg))
   {
      zoneHigh = fvg.highPrice;
      zoneLow = fvg.lowPrice;
      return true;
   }

   return false;
}
