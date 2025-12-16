//+------------------------------------------------------------------+
//|                                                  DailyPivot.mqh |
//|                     Daily Pivot Points for Dow Theory EA         |
//|                              Copyright 2024                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""

//+------------------------------------------------------------------+
//| Daily Pivot Class                                                 |
//+------------------------------------------------------------------+
class CDailyPivot
{
private:
   string            m_symbol;

   // Pivot Levels
   double            m_pivotPoint;    // ピボットポイント (PP)
   double            m_r1;            // レジスタンス1
   double            m_r2;            // レジスタンス2
   double            m_r3;            // レジスタンス3
   double            m_s1;            // サポート1
   double            m_s2;            // サポート2
   double            m_s3;            // サポート3

   // Previous day OHLC
   double            m_prevHigh;
   double            m_prevLow;
   double            m_prevClose;

   datetime          m_lastCalculated;

public:
                     CDailyPivot();
                    ~CDailyPivot();

   // Initialization
   bool              Init(string symbol);

   // Update and Calculate
   bool              Update();
   bool              CalculatePivots();

   // Get Pivot Levels
   double            GetPivotPoint()  { return m_pivotPoint; }
   double            GetR1()          { return m_r1; }
   double            GetR2()          { return m_r2; }
   double            GetR3()          { return m_r3; }
   double            GetS1()          { return m_s1; }
   double            GetS2()          { return m_s2; }
   double            GetS3()          { return m_s3; }

   // Get nearest pivot level for take profit
   double            GetNearestResistance(double currentPrice);
   double            GetNearestSupport(double currentPrice);

   // Get TP level based on trade direction
   double            GetTakeProfitLevel(double entryPrice, bool isBuy, double fallbackTP, double maxDistanceRatio);

   // Debug info
   void              PrintPivotLevels();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CDailyPivot::CDailyPivot()
{
   m_symbol = "";
   m_pivotPoint = 0;
   m_r1 = 0;
   m_r2 = 0;
   m_r3 = 0;
   m_s1 = 0;
   m_s2 = 0;
   m_s3 = 0;
   m_prevHigh = 0;
   m_prevLow = 0;
   m_prevClose = 0;
   m_lastCalculated = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CDailyPivot::~CDailyPivot()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CDailyPivot::Init(string symbol)
{
   m_symbol = symbol;
   Print("Daily Pivot initialized for ", m_symbol);
   return Update();
}

//+------------------------------------------------------------------+
//| Update pivot levels (call at start of each day or on each tick)  |
//+------------------------------------------------------------------+
bool CDailyPivot::Update()
{
   // Get current day start time
   datetime currentDayStart = iTime(m_symbol, PERIOD_D1, 0);

   // Only recalculate if day has changed
   if(m_lastCalculated == currentDayStart && m_pivotPoint > 0)
      return true;

   return CalculatePivots();
}

//+------------------------------------------------------------------+
//| Calculate Standard Pivot Points                                   |
//| PP = (High + Low + Close) / 3                                    |
//| R1 = 2*PP - Low                                                  |
//| R2 = PP + (High - Low)                                           |
//| R3 = High + 2*(PP - Low)                                         |
//| S1 = 2*PP - High                                                 |
//| S2 = PP - (High - Low)                                           |
//| S3 = Low - 2*(High - PP)                                         |
//+------------------------------------------------------------------+
bool CDailyPivot::CalculatePivots()
{
   // Get previous day OHLC
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   // Copy previous day data (index 1 = yesterday)
   if(CopyHigh(m_symbol, PERIOD_D1, 1, 1, high) <= 0)
   {
      Print("Error copying daily high: ", GetLastError());
      return false;
   }
   if(CopyLow(m_symbol, PERIOD_D1, 1, 1, low) <= 0)
   {
      Print("Error copying daily low: ", GetLastError());
      return false;
   }
   if(CopyClose(m_symbol, PERIOD_D1, 1, 1, close) <= 0)
   {
      Print("Error copying daily close: ", GetLastError());
      return false;
   }

   m_prevHigh = high[0];
   m_prevLow = low[0];
   m_prevClose = close[0];

   // Calculate Standard Pivot Points
   m_pivotPoint = (m_prevHigh + m_prevLow + m_prevClose) / 3.0;

   // Resistance levels
   m_r1 = 2.0 * m_pivotPoint - m_prevLow;
   m_r2 = m_pivotPoint + (m_prevHigh - m_prevLow);
   m_r3 = m_prevHigh + 2.0 * (m_pivotPoint - m_prevLow);

   // Support levels
   m_s1 = 2.0 * m_pivotPoint - m_prevHigh;
   m_s2 = m_pivotPoint - (m_prevHigh - m_prevLow);
   m_s3 = m_prevLow - 2.0 * (m_prevHigh - m_pivotPoint);

   // Normalize values
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_pivotPoint = NormalizeDouble(m_pivotPoint, digits);
   m_r1 = NormalizeDouble(m_r1, digits);
   m_r2 = NormalizeDouble(m_r2, digits);
   m_r3 = NormalizeDouble(m_r3, digits);
   m_s1 = NormalizeDouble(m_s1, digits);
   m_s2 = NormalizeDouble(m_s2, digits);
   m_s3 = NormalizeDouble(m_s3, digits);

   m_lastCalculated = iTime(m_symbol, PERIOD_D1, 0);

   PrintPivotLevels();

   return true;
}

//+------------------------------------------------------------------+
//| Get nearest resistance level above current price                  |
//+------------------------------------------------------------------+
double CDailyPivot::GetNearestResistance(double currentPrice)
{
   // Collect all resistance levels above current price
   double levels[4];
   int count = 0;

   if(m_pivotPoint > currentPrice) levels[count++] = m_pivotPoint;
   if(m_r1 > currentPrice) levels[count++] = m_r1;
   if(m_r2 > currentPrice) levels[count++] = m_r2;
   if(m_r3 > currentPrice) levels[count++] = m_r3;

   if(count == 0)
      return 0;  // No resistance above current price

   // Find the nearest (smallest) resistance
   double nearest = levels[0];
   for(int i = 1; i < count; i++)
   {
      if(levels[i] < nearest)
         nearest = levels[i];
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| Get nearest support level below current price                     |
//+------------------------------------------------------------------+
double CDailyPivot::GetNearestSupport(double currentPrice)
{
   // Collect all support levels below current price
   double levels[4];
   int count = 0;

   if(m_pivotPoint < currentPrice) levels[count++] = m_pivotPoint;
   if(m_s1 < currentPrice) levels[count++] = m_s1;
   if(m_s2 < currentPrice) levels[count++] = m_s2;
   if(m_s3 < currentPrice) levels[count++] = m_s3;

   if(count == 0)
      return 0;  // No support below current price

   // Find the nearest (largest) support
   double nearest = levels[0];
   for(int i = 1; i < count; i++)
   {
      if(levels[i] > nearest)
         nearest = levels[i];
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| Get take profit level based on pivot                              |
//| Returns pivot-based TP if within acceptable distance,             |
//| otherwise returns fallbackTP                                      |
//+------------------------------------------------------------------+
double CDailyPivot::GetTakeProfitLevel(double entryPrice, bool isBuy, double fallbackTP, double maxDistanceRatio)
{
   double pivotTP = 0;
   double fallbackDistance = 0;

   if(isBuy)
   {
      // For buy orders, find nearest resistance
      pivotTP = GetNearestResistance(entryPrice);
      fallbackDistance = fallbackTP - entryPrice;
   }
   else
   {
      // For sell orders, find nearest support
      pivotTP = GetNearestSupport(entryPrice);
      fallbackDistance = entryPrice - fallbackTP;
   }

   // If no pivot level found, use fallback
   if(pivotTP == 0)
   {
      Print("No pivot level found, using fallback TP: ", fallbackTP);
      return fallbackTP;
   }

   // Calculate pivot distance
   double pivotDistance = isBuy ? (pivotTP - entryPrice) : (entryPrice - pivotTP);

   // Check if pivot is too far (more than maxDistanceRatio times the fallback distance)
   if(fallbackDistance > 0 && pivotDistance > fallbackDistance * maxDistanceRatio)
   {
      Print("Pivot TP (", pivotTP, ") too far (", pivotDistance, " pips), using fallback TP: ", fallbackTP);
      return fallbackTP;
   }

   // Check if pivot is too close (less than 50% of fallback distance) - use fallback instead
   if(fallbackDistance > 0 && pivotDistance < fallbackDistance * 0.3)
   {
      Print("Pivot TP (", pivotTP, ") too close, using fallback TP: ", fallbackTP);
      return fallbackTP;
   }

   Print("Using Pivot TP: ", pivotTP, " (entry: ", entryPrice, ", distance: ", pivotDistance, ")");
   return pivotTP;
}

//+------------------------------------------------------------------+
//| Print pivot levels for debugging                                  |
//+------------------------------------------------------------------+
void CDailyPivot::PrintPivotLevels()
{
   Print("=== Daily Pivot Levels ===");
   Print("Previous Day - H: ", m_prevHigh, " L: ", m_prevLow, " C: ", m_prevClose);
   Print("R3: ", m_r3);
   Print("R2: ", m_r2);
   Print("R1: ", m_r1);
   Print("PP: ", m_pivotPoint);
   Print("S1: ", m_s1);
   Print("S2: ", m_s2);
   Print("S3: ", m_s3);
   Print("========================");
}
//+------------------------------------------------------------------+
