//+------------------------------------------------------------------+
//|                                                 MLOptimizer.mqh |
//|                            ML EMA Scalping EA - ML Module        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ML EMA Scalping EA"
#property strict

//+------------------------------------------------------------------+
//| Trade record structure for learning                              |
//+------------------------------------------------------------------+
struct STradeRecord
{
   datetime          openTime;
   datetime          closeTime;
   int               hour;          // 0-23
   int               dayOfWeek;     // 0=Sunday, 6=Saturday
   double            profit;
   double            profitPips;
   bool              isWin;
   double            riskReward;
   bool              wasEarlyExit;  // True if closed by EMA reversal
};

//+------------------------------------------------------------------+
//| Hourly statistics structure                                       |
//+------------------------------------------------------------------+
struct SHourlyStats
{
   int               hour;
   int               totalTrades;
   int               wins;
   int               losses;
   double            totalProfit;
   double            totalLoss;
   double            winRate;
   double            expectancy;    // Average expected value per trade
   double            profitFactor;
   bool              isOptimal;     // True if hour has positive expectancy
};

//+------------------------------------------------------------------+
//| ML Optimizer Class                                                |
//| Handles historical data learning and optimal time detection       |
//+------------------------------------------------------------------+
class CMLOptimizer
{
private:
   string            m_symbol;
   string            m_dataFilePath;

   // Trade history
   STradeRecord      m_tradeHistory[];
   int               m_historyCount;

   // Hourly statistics (24 hours)
   SHourlyStats      m_hourlyStats[24];

   // Settings
   int               m_learningDays;      // Days of history to analyze
   double            m_minExpectancy;     // Minimum expectancy to allow trading
   int               m_minSampleSize;     // Minimum trades per hour for confidence
   double            m_confidenceLevel;   // Statistical confidence level

   // State
   bool              m_isInitialized;
   datetime          m_lastUpdateTime;

public:
   // Constructor
   CMLOptimizer()
   {
      m_symbol = "";
      m_dataFilePath = "";
      m_historyCount = 0;
      m_learningDays = 30;
      m_minExpectancy = 0.0;
      m_minSampleSize = 5;
      m_confidenceLevel = 0.95;
      m_isInitialized = false;
      m_lastUpdateTime = 0;

      // Initialize hourly stats
      for(int i = 0; i < 24; i++)
      {
         m_hourlyStats[i].hour = i;
         m_hourlyStats[i].totalTrades = 0;
         m_hourlyStats[i].wins = 0;
         m_hourlyStats[i].losses = 0;
         m_hourlyStats[i].totalProfit = 0;
         m_hourlyStats[i].totalLoss = 0;
         m_hourlyStats[i].winRate = 0;
         m_hourlyStats[i].expectancy = 0;
         m_hourlyStats[i].profitFactor = 0;
         m_hourlyStats[i].isOptimal = true;  // Default allow all hours
      }
   }

   // Destructor
   ~CMLOptimizer()
   {
      SaveTradeHistory();
   }

   //+------------------------------------------------------------------+
   //| Initialize ML Optimizer                                          |
   //+------------------------------------------------------------------+
   bool Init(string symbol, int learningDays = 30, double minExpectancy = 0.0)
   {
      m_symbol = symbol;
      m_learningDays = learningDays;
      m_minExpectancy = minExpectancy;

      // Create data file path
      m_dataFilePath = "MLEMAScalping\\" + m_symbol + "_trades.csv";

      // Load existing trade history
      LoadTradeHistory();

      // Calculate initial statistics
      CalculateHourlyStatistics();

      m_isInitialized = true;
      m_lastUpdateTime = TimeCurrent();

      Print("ML Optimizer initialized for ", m_symbol);
      Print("Loaded ", m_historyCount, " historical trades");

      return true;
   }

   //+------------------------------------------------------------------+
   //| Load trade history from file                                     |
   //+------------------------------------------------------------------+
   bool LoadTradeHistory()
   {
      // Ensure directory exists
      FolderCreate("MLEMAScalping");

      int fileHandle = FileOpen(m_dataFilePath, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
      {
         Print("No existing trade history found. Starting fresh.");
         return false;
      }

      // Skip header
      if(!FileIsEnding(fileHandle))
      {
         FileReadString(fileHandle);  // Read and discard header line
      }

      // Read trade records
      ArrayResize(m_tradeHistory, 0);
      m_historyCount = 0;

      datetime cutoffDate = TimeCurrent() - (m_learningDays * 86400);

      while(!FileIsEnding(fileHandle))
      {
         STradeRecord record;

         string openTimeStr = FileReadString(fileHandle);
         if(StringLen(openTimeStr) == 0) break;

         record.openTime = StringToTime(openTimeStr);

         // Skip records older than learning period
         if(record.openTime < cutoffDate)
         {
            // Skip rest of line
            FileReadString(fileHandle);  // closeTime
            FileReadString(fileHandle);  // hour
            FileReadString(fileHandle);  // dayOfWeek
            FileReadString(fileHandle);  // profit
            FileReadString(fileHandle);  // profitPips
            FileReadString(fileHandle);  // isWin
            FileReadString(fileHandle);  // riskReward
            FileReadString(fileHandle);  // wasEarlyExit
            continue;
         }

         record.closeTime = StringToTime(FileReadString(fileHandle));
         record.hour = (int)StringToInteger(FileReadString(fileHandle));
         record.dayOfWeek = (int)StringToInteger(FileReadString(fileHandle));
         record.profit = StringToDouble(FileReadString(fileHandle));
         record.profitPips = StringToDouble(FileReadString(fileHandle));
         record.isWin = (bool)StringToInteger(FileReadString(fileHandle));
         record.riskReward = StringToDouble(FileReadString(fileHandle));
         record.wasEarlyExit = (bool)StringToInteger(FileReadString(fileHandle));

         ArrayResize(m_tradeHistory, m_historyCount + 1);
         m_tradeHistory[m_historyCount] = record;
         m_historyCount++;
      }

      FileClose(fileHandle);
      Print("Loaded ", m_historyCount, " trades from history");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Save trade history to file                                       |
   //+------------------------------------------------------------------+
   bool SaveTradeHistory()
   {
      if(m_historyCount == 0) return true;

      FolderCreate("MLEMAScalping");

      int fileHandle = FileOpen(m_dataFilePath, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
      {
         Print("Error saving trade history: ", GetLastError());
         return false;
      }

      // Write header
      FileWrite(fileHandle, "OpenTime", "CloseTime", "Hour", "DayOfWeek",
                "Profit", "ProfitPips", "IsWin", "RiskReward", "WasEarlyExit");

      // Write records
      for(int i = 0; i < m_historyCount; i++)
      {
         FileWrite(fileHandle,
                   TimeToString(m_tradeHistory[i].openTime, TIME_DATE | TIME_MINUTES),
                   TimeToString(m_tradeHistory[i].closeTime, TIME_DATE | TIME_MINUTES),
                   IntegerToString(m_tradeHistory[i].hour),
                   IntegerToString(m_tradeHistory[i].dayOfWeek),
                   DoubleToString(m_tradeHistory[i].profit, 2),
                   DoubleToString(m_tradeHistory[i].profitPips, 1),
                   IntegerToString(m_tradeHistory[i].isWin ? 1 : 0),
                   DoubleToString(m_tradeHistory[i].riskReward, 2),
                   IntegerToString(m_tradeHistory[i].wasEarlyExit ? 1 : 0));
      }

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Add new trade record                                             |
   //+------------------------------------------------------------------+
   void AddTradeRecord(datetime openTime, datetime closeTime,
                       double profit, double profitPips, bool wasEarlyExit = false)
   {
      STradeRecord record;
      record.openTime = openTime;
      record.closeTime = closeTime;

      MqlDateTime dt;
      TimeToStruct(openTime, dt);
      record.hour = dt.hour;
      record.dayOfWeek = dt.day_of_week;

      record.profit = profit;
      record.profitPips = profitPips;
      record.isWin = (profit > 0);
      record.wasEarlyExit = wasEarlyExit;

      // Calculate approximate risk-reward (simplified)
      record.riskReward = profitPips > 0 ? 1.0 : -1.0;  // Will be refined with SL data

      ArrayResize(m_tradeHistory, m_historyCount + 1);
      m_tradeHistory[m_historyCount] = record;
      m_historyCount++;

      // Recalculate statistics periodically
      if(m_historyCount % 10 == 0)
      {
         CalculateHourlyStatistics();
         SaveTradeHistory();
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate hourly statistics                                      |
   //+------------------------------------------------------------------+
   void CalculateHourlyStatistics()
   {
      // Reset statistics
      for(int i = 0; i < 24; i++)
      {
         m_hourlyStats[i].totalTrades = 0;
         m_hourlyStats[i].wins = 0;
         m_hourlyStats[i].losses = 0;
         m_hourlyStats[i].totalProfit = 0;
         m_hourlyStats[i].totalLoss = 0;
         m_hourlyStats[i].winRate = 0;
         m_hourlyStats[i].expectancy = 0;
         m_hourlyStats[i].profitFactor = 0;
         m_hourlyStats[i].isOptimal = true;
      }

      // Calculate statistics from history
      for(int i = 0; i < m_historyCount; i++)
      {
         int hour = m_tradeHistory[i].hour;

         m_hourlyStats[hour].totalTrades++;

         if(m_tradeHistory[i].isWin)
         {
            m_hourlyStats[hour].wins++;
            m_hourlyStats[hour].totalProfit += m_tradeHistory[i].profit;
         }
         else
         {
            m_hourlyStats[hour].losses++;
            m_hourlyStats[hour].totalLoss += MathAbs(m_tradeHistory[i].profit);
         }
      }

      // Calculate derived metrics
      for(int i = 0; i < 24; i++)
      {
         if(m_hourlyStats[i].totalTrades > 0)
         {
            m_hourlyStats[i].winRate = (double)m_hourlyStats[i].wins /
                                       (double)m_hourlyStats[i].totalTrades;

            // Calculate expectancy (average profit per trade)
            double netProfit = m_hourlyStats[i].totalProfit - m_hourlyStats[i].totalLoss;
            m_hourlyStats[i].expectancy = netProfit / (double)m_hourlyStats[i].totalTrades;

            // Profit factor
            if(m_hourlyStats[i].totalLoss > 0)
               m_hourlyStats[i].profitFactor = m_hourlyStats[i].totalProfit / m_hourlyStats[i].totalLoss;
            else
               m_hourlyStats[i].profitFactor = m_hourlyStats[i].totalProfit > 0 ? 999.0 : 0.0;

            // Determine if hour is optimal for trading
            // Requires minimum sample size and positive expectancy
            if(m_hourlyStats[i].totalTrades >= m_minSampleSize)
            {
               m_hourlyStats[i].isOptimal = (m_hourlyStats[i].expectancy >= m_minExpectancy);
            }
            else
            {
               // Not enough data - default to allowing trading
               m_hourlyStats[i].isOptimal = true;
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if current hour is optimal for trading                     |
   //+------------------------------------------------------------------+
   bool IsOptimalTime()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      return m_hourlyStats[dt.hour].isOptimal;
   }

   //+------------------------------------------------------------------+
   //| Check specific hour                                              |
   //+------------------------------------------------------------------+
   bool IsHourOptimal(int hour)
   {
      if(hour < 0 || hour > 23) return false;
      return m_hourlyStats[hour].isOptimal;
   }

   //+------------------------------------------------------------------+
   //| Get expectancy for current hour                                  |
   //+------------------------------------------------------------------+
   double GetCurrentHourExpectancy()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      return m_hourlyStats[dt.hour].expectancy;
   }

   //+------------------------------------------------------------------+
   //| Get hourly statistics                                            |
   //+------------------------------------------------------------------+
   SHourlyStats GetHourlyStats(int hour)
   {
      if(hour >= 0 && hour < 24)
         return m_hourlyStats[hour];

      SHourlyStats empty;
      ZeroMemory(empty);
      return empty;
   }

   //+------------------------------------------------------------------+
   //| Get best trading hours                                           |
   //+------------------------------------------------------------------+
   void GetBestHours(int &hours[], int maxHours = 5)
   {
      // Create sorted list of hours by expectancy
      double expectancies[24];
      int indices[24];

      for(int i = 0; i < 24; i++)
      {
         expectancies[i] = m_hourlyStats[i].expectancy;
         indices[i] = i;
      }

      // Simple bubble sort (24 items is small)
      for(int i = 0; i < 23; i++)
      {
         for(int j = 0; j < 23 - i; j++)
         {
            if(expectancies[j] < expectancies[j + 1])
            {
               // Swap
               double tempExp = expectancies[j];
               expectancies[j] = expectancies[j + 1];
               expectancies[j + 1] = tempExp;

               int tempIdx = indices[j];
               indices[j] = indices[j + 1];
               indices[j + 1] = tempIdx;
            }
         }
      }

      // Return top hours
      ArrayResize(hours, maxHours);
      for(int i = 0; i < maxHours; i++)
      {
         hours[i] = indices[i];
      }
   }

   //+------------------------------------------------------------------+
   //| Get trading confidence level for current hour                    |
   //+------------------------------------------------------------------+
   double GetConfidenceLevel()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      if(m_hourlyStats[hour].totalTrades == 0)
         return 0.5;  // Default 50% confidence

      // Calculate confidence based on sample size
      // Using simplified confidence interval estimation
      int n = m_hourlyStats[hour].totalTrades;
      double confidence = 1.0 - (1.0 / MathSqrt((double)n));

      return MathMin(confidence, 0.99);
   }

   //+------------------------------------------------------------------+
   //| Get filter multiplier based on hour quality                      |
   //+------------------------------------------------------------------+
   double GetHourQualityMultiplier()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      SHourlyStats stats = m_hourlyStats[hour];

      if(stats.totalTrades < m_minSampleSize)
         return 1.0;  // Not enough data, use normal settings

      // Calculate multiplier based on performance
      // Range: 0.5 (poor hour) to 1.5 (excellent hour)
      double avgExpectancy = 0;
      int validHours = 0;

      for(int i = 0; i < 24; i++)
      {
         if(m_hourlyStats[i].totalTrades >= m_minSampleSize)
         {
            avgExpectancy += m_hourlyStats[i].expectancy;
            validHours++;
         }
      }

      if(validHours > 0)
         avgExpectancy /= validHours;

      if(avgExpectancy == 0)
         return 1.0;

      double multiplier = 1.0 + (stats.expectancy - avgExpectancy) / (MathAbs(avgExpectancy) + 0.001);
      return MathMax(0.5, MathMin(1.5, multiplier));
   }

   //+------------------------------------------------------------------+
   //| Print hourly statistics report                                   |
   //+------------------------------------------------------------------+
   void PrintStatisticsReport()
   {
      Print("=== ML Optimizer Hourly Statistics ===");
      Print("Symbol: ", m_symbol, " | Learning Period: ", m_learningDays, " days");
      Print("Total Trades Analyzed: ", m_historyCount);
      Print("");
      Print("Hour | Trades | WinRate | Expectancy | PF    | Optimal");
      Print("-----|--------|---------|------------|-------|--------");

      for(int i = 0; i < 24; i++)
      {
         Print(StringFormat("%02d   | %6d | %6.1f%% | %10.2f | %5.2f | %s",
                            i,
                            m_hourlyStats[i].totalTrades,
                            m_hourlyStats[i].winRate * 100,
                            m_hourlyStats[i].expectancy,
                            m_hourlyStats[i].profitFactor,
                            m_hourlyStats[i].isOptimal ? "Yes" : "No"));
      }
   }

   //+------------------------------------------------------------------+
   //| Export statistics to CSV                                        |
   //+------------------------------------------------------------------+
   bool ExportStatisticsToCSV(string filename = "")
   {
      if(filename == "")
         filename = "MLEMAScalping\\" + m_symbol + "_hourly_stats.csv";

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
      {
         Print("Error creating statistics file: ", GetLastError());
         return false;
      }

      FileWrite(fileHandle, "Hour", "TotalTrades", "Wins", "Losses",
                "WinRate", "TotalProfit", "TotalLoss", "Expectancy",
                "ProfitFactor", "IsOptimal");

      for(int i = 0; i < 24; i++)
      {
         FileWrite(fileHandle,
                   i,
                   m_hourlyStats[i].totalTrades,
                   m_hourlyStats[i].wins,
                   m_hourlyStats[i].losses,
                   m_hourlyStats[i].winRate,
                   m_hourlyStats[i].totalProfit,
                   m_hourlyStats[i].totalLoss,
                   m_hourlyStats[i].expectancy,
                   m_hourlyStats[i].profitFactor,
                   m_hourlyStats[i].isOptimal);
      }

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   int GetTradeCount() { return m_historyCount; }
   bool IsInitialized() { return m_isInitialized; }
   string GetSymbol() { return m_symbol; }
};
