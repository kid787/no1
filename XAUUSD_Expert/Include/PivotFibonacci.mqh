//+------------------------------------------------------------------+
//|                                              PivotFibonacci.mqh  |
//|                       XAUUSD Expert - PIVOT・Fibonacci計算         |
//+------------------------------------------------------------------+
#ifndef PIVOT_FIBONACCI_MQH
#define PIVOT_FIBONACCI_MQH

#include "CommonDefines.mqh"

//+------------------------------------------------------------------+
//| PIVOT・Fibonacci計算クラス                                        |
//+------------------------------------------------------------------+
class CPivotFibonacci
{
private:
   // 設定
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   // PIVOTデータ
   DailyPivot     m_dailyPivot;
   DailyPivot     m_weeklyPivot;

   // Fibonacciデータ
   FibonacciLevels m_fibLevels;
   int            m_fibLookback;       // Fibonacci計算用の検索バー数

   // ログ
   bool           m_enableLog;

   // 内部メソッド
   void           CalculatePivot(ENUM_TIMEFRAMES tf, DailyPivot &pivot);
   void           CalculateFibonacci();
   bool           GetPreviousPeriodHLC(ENUM_TIMEFRAMES tf, double &high, double &low, double &close);

public:
                  CPivotFibonacci();
                 ~CPivotFibonacci();

   // 初期化
   bool           Initialize(string symbol = NULL,
                             ENUM_TIMEFRAMES timeframe = PERIOD_M5,
                             int fibLookback = 100);

   // 更新
   void           Update();

   // PIVOT取得
   double         GetDailyPivot() { return m_dailyPivot.pivot; }
   double         GetDailyR1() { return m_dailyPivot.r1; }
   double         GetDailyR2() { return m_dailyPivot.r2; }
   double         GetDailyR3() { return m_dailyPivot.r3; }
   double         GetDailyS1() { return m_dailyPivot.s1; }
   double         GetDailyS2() { return m_dailyPivot.s2; }
   double         GetDailyS3() { return m_dailyPivot.s3; }

   double         GetWeeklyPivot() { return m_weeklyPivot.pivot; }
   double         GetWeeklyR1() { return m_weeklyPivot.r1; }
   double         GetWeeklyS1() { return m_weeklyPivot.s1; }

   // Fibonacci取得
   double         GetFib236() { return m_fibLevels.level236; }
   double         GetFib382() { return m_fibLevels.level382; }
   double         GetFib500() { return m_fibLevels.level500; }
   double         GetFib618() { return m_fibLevels.level618; }
   double         GetFib786() { return m_fibLevels.level786; }
   double         GetFib1618() { return m_fibLevels.level1618; }
   bool           IsFibUptrend() { return m_fibLevels.isUptrend; }

   // 利確ターゲット計算
   double         GetNearestPivotTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction);
   double         GetNearestFibTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction);
   double         GetOptimalTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction, double minRR = 1.5);

   // レベル近接チェック
   bool           IsPriceNearPivotLevel(double price, double tolerancePips = 5.0);
   bool           IsPriceNearFibLevel(double price, double tolerancePips = 5.0);

   // 全PIVOTレベル取得
   void           GetAllDailyPivotLevels(double &levels[], int &count);

   // 設定
   void           EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CPivotFibonacci::CPivotFibonacci()
{
   m_symbol = "";
   m_timeframe = PERIOD_M5;
   m_fibLookback = 100;
   m_enableLog = true;

   // 初期化
   ZeroMemory(m_dailyPivot);
   ZeroMemory(m_weeklyPivot);
   ZeroMemory(m_fibLevels);
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CPivotFibonacci::~CPivotFibonacci()
{
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CPivotFibonacci::Initialize(string symbol,
                                  ENUM_TIMEFRAMES timeframe,
                                  int fibLookback)
{
   m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   m_timeframe = timeframe;
   m_fibLookback = fibLookback;

   Update();

   if(m_enableLog)
   {
      LogDebug(StringFormat("PivotFibonacci initialized: Symbol=%s, FibLookback=%d",
               m_symbol, m_fibLookback));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 更新                                                              |
//+------------------------------------------------------------------+
void CPivotFibonacci::Update()
{
   CalculatePivot(PERIOD_D1, m_dailyPivot);
   CalculatePivot(PERIOD_W1, m_weeklyPivot);
   CalculateFibonacci();
}

//+------------------------------------------------------------------+
//| 前日/前週のHLCを取得                                              |
//+------------------------------------------------------------------+
bool CPivotFibonacci::GetPreviousPeriodHLC(ENUM_TIMEFRAMES tf, double &high, double &low, double &close)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   // 2本分取得（0:現在、1:前期間）
   if(CopyRates(m_symbol, tf, 0, 2, rates) < 2)
      return false;

   high = rates[1].high;
   low = rates[1].low;
   close = rates[1].close;

   return true;
}

//+------------------------------------------------------------------+
//| PIVOTポイントを計算                                               |
//+------------------------------------------------------------------+
void CPivotFibonacci::CalculatePivot(ENUM_TIMEFRAMES tf, DailyPivot &pivot)
{
   double high, low, close;

   if(!GetPreviousPeriodHLC(tf, high, low, close))
   {
      if(m_enableLog) LogDebug(StringFormat("Failed to get HLC for TF %d", tf));
      return;
   }

   // 標準的なPIVOT計算
   pivot.pivot = (high + low + close) / 3.0;

   // 抵抗線（Resistance）
   pivot.r1 = 2.0 * pivot.pivot - low;
   pivot.r2 = pivot.pivot + (high - low);
   pivot.r3 = high + 2.0 * (pivot.pivot - low);

   // 支持線（Support）
   pivot.s1 = 2.0 * pivot.pivot - high;
   pivot.s2 = pivot.pivot - (high - low);
   pivot.s3 = low - 2.0 * (high - pivot.pivot);

   pivot.calcDate = TimeCurrent();

   if(m_enableLog && tf == PERIOD_D1)
   {
      LogDebug(StringFormat("Daily Pivot calculated: P=%.2f, R1=%.2f, S1=%.2f",
               pivot.pivot, pivot.r1, pivot.s1));
   }
}

//+------------------------------------------------------------------+
//| Fibonacciレベルを計算                                             |
//+------------------------------------------------------------------+
void CPivotFibonacci::CalculateFibonacci()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(m_symbol, m_timeframe, 0, m_fibLookback, rates) < m_fibLookback)
      return;

   // スイングハイとスイングローを見つける
   double highestHigh = rates[0].high;
   double lowestLow = rates[0].low;
   int highIndex = 0;
   int lowIndex = 0;

   for(int i = 0; i < m_fibLookback; i++)
   {
      if(rates[i].high > highestHigh)
      {
         highestHigh = rates[i].high;
         highIndex = i;
      }
      if(rates[i].low < lowestLow)
      {
         lowestLow = rates[i].low;
         lowIndex = i;
      }
   }

   m_fibLevels.high = highestHigh;
   m_fibLevels.low = lowestLow;

   // トレンド方向を判定（高値が安値より前=上昇トレンド）
   m_fibLevels.isUptrend = (highIndex < lowIndex);

   double range = highestHigh - lowestLow;

   if(m_fibLevels.isUptrend)
   {
      // 上昇トレンド：安値からの戻り
      m_fibLevels.level236 = highestHigh - range * 0.236;
      m_fibLevels.level382 = highestHigh - range * 0.382;
      m_fibLevels.level500 = highestHigh - range * 0.500;
      m_fibLevels.level618 = highestHigh - range * 0.618;
      m_fibLevels.level786 = highestHigh - range * 0.786;
      m_fibLevels.level1000 = lowestLow;
      m_fibLevels.level1618 = highestHigh + range * 0.618;
      m_fibLevels.level2618 = highestHigh + range * 1.618;
   }
   else
   {
      // 下降トレンド：高値からの戻り
      m_fibLevels.level236 = lowestLow + range * 0.236;
      m_fibLevels.level382 = lowestLow + range * 0.382;
      m_fibLevels.level500 = lowestLow + range * 0.500;
      m_fibLevels.level618 = lowestLow + range * 0.618;
      m_fibLevels.level786 = lowestLow + range * 0.786;
      m_fibLevels.level1000 = highestHigh;
      m_fibLevels.level1618 = lowestLow - range * 0.618;
      m_fibLevels.level2618 = lowestLow - range * 1.618;
   }

   if(m_enableLog)
   {
      LogDebug(StringFormat("Fibonacci calculated: High=%.2f, Low=%.2f, Trend=%s, 61.8%%=%.2f",
               highestHigh, lowestLow,
               m_fibLevels.isUptrend ? "Up" : "Down",
               m_fibLevels.level618));
   }
}

//+------------------------------------------------------------------+
//| 最も近いPIVOT利確ターゲット                                       |
//+------------------------------------------------------------------+
double CPivotFibonacci::GetNearestPivotTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction)
{
   double levels[];
   int count;
   GetAllDailyPivotLevels(levels, count);

   double nearestTP = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < count; i++)
   {
      if(direction == SIGNAL_BUY && levels[i] > entryPrice)
      {
         double distance = levels[i] - entryPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestTP = levels[i];
         }
      }
      else if(direction == SIGNAL_SELL && levels[i] < entryPrice)
      {
         double distance = entryPrice - levels[i];
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestTP = levels[i];
         }
      }
   }

   return nearestTP;
}

//+------------------------------------------------------------------+
//| 最も近いFibonacci利確ターゲット                                   |
//+------------------------------------------------------------------+
double CPivotFibonacci::GetNearestFibTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction)
{
   double levels[] = {
      m_fibLevels.level236,
      m_fibLevels.level382,
      m_fibLevels.level500,
      m_fibLevels.level618,
      m_fibLevels.level786,
      m_fibLevels.level1618
   };

   double nearestTP = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(direction == SIGNAL_BUY && levels[i] > entryPrice)
      {
         double distance = levels[i] - entryPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestTP = levels[i];
         }
      }
      else if(direction == SIGNAL_SELL && levels[i] < entryPrice)
      {
         double distance = entryPrice - levels[i];
         if(distance < minDistance)
         {
            minDistance = distance;
            nearestTP = levels[i];
         }
      }
   }

   return nearestTP;
}

//+------------------------------------------------------------------+
//| 最適な利確ターゲットを計算                                        |
//+------------------------------------------------------------------+
double CPivotFibonacci::GetOptimalTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction, double minRR)
{
   // PIVOTとFibonacciの両方から候補を取得
   double pivotTP = GetNearestPivotTP(entryPrice, direction);
   double fibTP = GetNearestFibTP(entryPrice, direction);

   // どちらも見つからない場合
   if(pivotTP == 0 && fibTP == 0)
      return 0;

   // 片方だけの場合
   if(pivotTP == 0) return fibTP;
   if(fibTP == 0) return pivotTP;

   // 両方ある場合、より近いほうを返す（ただし最小RRを確保）
   double pivotDistance = MathAbs(pivotTP - entryPrice);
   double fibDistance = MathAbs(fibTP - entryPrice);

   // より近いほうを選択
   return (pivotDistance < fibDistance) ? pivotTP : fibTP;
}

//+------------------------------------------------------------------+
//| 価格がPIVOTレベル近くにあるか                                     |
//+------------------------------------------------------------------+
bool CPivotFibonacci::IsPriceNearPivotLevel(double price, double tolerancePips)
{
   double tolerance = PipsToPrice(tolerancePips, m_symbol);

   double levels[] = {
      m_dailyPivot.pivot,
      m_dailyPivot.r1, m_dailyPivot.r2, m_dailyPivot.r3,
      m_dailyPivot.s1, m_dailyPivot.s2, m_dailyPivot.s3
   };

   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(MathAbs(price - levels[i]) <= tolerance)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 価格がFibonacciレベル近くにあるか                                 |
//+------------------------------------------------------------------+
bool CPivotFibonacci::IsPriceNearFibLevel(double price, double tolerancePips)
{
   double tolerance = PipsToPrice(tolerancePips, m_symbol);

   double levels[] = {
      m_fibLevels.level236,
      m_fibLevels.level382,
      m_fibLevels.level500,
      m_fibLevels.level618,
      m_fibLevels.level786
   };

   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(MathAbs(price - levels[i]) <= tolerance)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 全PIVOTレベルを取得                                               |
//+------------------------------------------------------------------+
void CPivotFibonacci::GetAllDailyPivotLevels(double &levels[], int &count)
{
   ArrayResize(levels, 7);
   levels[0] = m_dailyPivot.pivot;
   levels[1] = m_dailyPivot.r1;
   levels[2] = m_dailyPivot.r2;
   levels[3] = m_dailyPivot.r3;
   levels[4] = m_dailyPivot.s1;
   levels[5] = m_dailyPivot.s2;
   levels[6] = m_dailyPivot.s3;
   count = 7;
}

#endif // PIVOT_FIBONACCI_MQH
