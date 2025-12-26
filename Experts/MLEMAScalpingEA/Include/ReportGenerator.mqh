//+------------------------------------------------------------------+
//|                                              ReportGenerator.mqh |
//|                          ML EMA Scalping EA - Report Module      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ML EMA Scalping EA"
#property strict

//+------------------------------------------------------------------+
//| Trade record for reporting                                        |
//+------------------------------------------------------------------+
struct STradeReportRecord
{
   long              ticket;
   datetime          openTime;
   datetime          closeTime;
   string            symbol;
   int               type;           // 0=Buy, 1=Sell
   double            lots;
   double            openPrice;
   double            closePrice;
   double            sl;
   double            tp;
   double            profit;
   double            profitPips;
   double            commission;
   double            swap;
   string            comment;
};

//+------------------------------------------------------------------+
//| Daily statistics structure                                        |
//+------------------------------------------------------------------+
struct SDailyStats
{
   datetime          date;
   int               totalTrades;
   int               wins;
   int               losses;
   double            profit;
   double            drawdown;
   double            winRate;
   double            profitFactor;
};

//+------------------------------------------------------------------+
//| Report Generator Class                                            |
//| Handles performance analysis and CSV export                       |
//+------------------------------------------------------------------+
class CReportGenerator
{
private:
   string            m_symbol;
   string            m_eaName;
   string            m_basePath;

   // Trade history
   STradeReportRecord m_trades[];
   int               m_tradeCount;

   // Daily statistics
   SDailyStats       m_dailyStats[];
   int               m_daysCount;

   // Overall statistics
   double            m_totalProfit;
   double            m_totalLoss;
   int               m_totalWins;
   int               m_totalLosses;
   double            m_maxDrawdown;
   double            m_maxProfit;
   double            m_sharpeRatio;
   double            m_profitFactor;
   double            m_averageWin;
   double            m_averageLoss;

   // Returns array for Sharpe calculation
   double            m_dailyReturns[];
   int               m_returnsCount;

   bool              m_isInitialized;

public:
   // Constructor
   CReportGenerator()
   {
      m_symbol = "";
      m_eaName = "MLEMAScalping";
      m_basePath = "MLEMAScalping\\Reports\\";
      m_tradeCount = 0;
      m_daysCount = 0;
      m_totalProfit = 0;
      m_totalLoss = 0;
      m_totalWins = 0;
      m_totalLosses = 0;
      m_maxDrawdown = 0;
      m_maxProfit = 0;
      m_sharpeRatio = 0;
      m_profitFactor = 0;
      m_averageWin = 0;
      m_averageLoss = 0;
      m_returnsCount = 0;
      m_isInitialized = false;
   }

   // Destructor
   ~CReportGenerator()
   {
      // Auto-save on destruction
      if(m_tradeCount > 0)
         SaveAllReports();
   }

   //+------------------------------------------------------------------+
   //| Initialize report generator                                      |
   //+------------------------------------------------------------------+
   bool Init(string symbol, string eaName = "MLEMAScalping")
   {
      m_symbol = symbol;
      m_eaName = eaName;

      // Ensure directory exists
      FolderCreate("MLEMAScalping");
      FolderCreate("MLEMAScalping\\Reports");

      // Load existing trade history
      LoadTradeHistory();

      m_isInitialized = true;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Add trade record                                                 |
   //+------------------------------------------------------------------+
   void AddTrade(long ticket, datetime openTime, datetime closeTime,
                 string symbol, int type, double lots,
                 double openPrice, double closePrice,
                 double sl, double tp, double profit,
                 double commission = 0, double swap = 0, string comment = "")
   {
      ArrayResize(m_trades, m_tradeCount + 1);

      m_trades[m_tradeCount].ticket = ticket;
      m_trades[m_tradeCount].openTime = openTime;
      m_trades[m_tradeCount].closeTime = closeTime;
      m_trades[m_tradeCount].symbol = symbol;
      m_trades[m_tradeCount].type = type;
      m_trades[m_tradeCount].lots = lots;
      m_trades[m_tradeCount].openPrice = openPrice;
      m_trades[m_tradeCount].closePrice = closePrice;
      m_trades[m_tradeCount].sl = sl;
      m_trades[m_tradeCount].tp = tp;
      m_trades[m_tradeCount].profit = profit;
      m_trades[m_tradeCount].commission = commission;
      m_trades[m_tradeCount].swap = swap;
      m_trades[m_tradeCount].comment = comment;

      // Calculate profit in pips
      double pipSize = GetPipSize(symbol);
      if(type == 0)  // Buy
         m_trades[m_tradeCount].profitPips = (closePrice - openPrice) / pipSize;
      else  // Sell
         m_trades[m_tradeCount].profitPips = (openPrice - closePrice) / pipSize;

      m_tradeCount++;

      // Update statistics
      if(profit > 0)
      {
         m_totalWins++;
         m_totalProfit += profit;
      }
      else
      {
         m_totalLosses++;
         m_totalLoss += MathAbs(profit);
      }

      // Periodic save
      if(m_tradeCount % 10 == 0)
      {
         CalculateAllStatistics();
         SaveTradeHistory();
      }
   }

   //+------------------------------------------------------------------+
   //| Get pip size for symbol                                          |
   //+------------------------------------------------------------------+
   double GetPipSize(string symbol)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      if(digits == 3 || digits == 5)
         return point * 10.0;
      else
         return point;
   }

   //+------------------------------------------------------------------+
   //| Calculate all statistics                                         |
   //+------------------------------------------------------------------+
   void CalculateAllStatistics()
   {
      if(m_tradeCount == 0) return;

      // Basic statistics
      m_averageWin = m_totalWins > 0 ? m_totalProfit / m_totalWins : 0;
      m_averageLoss = m_totalLosses > 0 ? m_totalLoss / m_totalLosses : 0;
      m_profitFactor = m_totalLoss > 0 ? m_totalProfit / m_totalLoss : 999.0;

      // Calculate daily returns for Sharpe ratio
      CalculateDailyReturns();

      // Calculate Sharpe ratio
      CalculateSharpeRatio();

      // Calculate max drawdown
      CalculateMaxDrawdown();
   }

   //+------------------------------------------------------------------+
   //| Calculate daily returns                                          |
   //+------------------------------------------------------------------+
   void CalculateDailyReturns()
   {
      if(m_tradeCount == 0) return;

      // Group trades by date
      ArrayResize(m_dailyStats, 0);
      m_daysCount = 0;

      for(int i = 0; i < m_tradeCount; i++)
      {
         datetime tradeDate = m_trades[i].closeTime;
         MqlDateTime dt;
         TimeToStruct(tradeDate, dt);
         dt.hour = 0;
         dt.min = 0;
         dt.sec = 0;
         datetime dayStart = StructToTime(dt);

         // Find or create daily record
         int dayIndex = -1;
         for(int j = 0; j < m_daysCount; j++)
         {
            if(m_dailyStats[j].date == dayStart)
            {
               dayIndex = j;
               break;
            }
         }

         if(dayIndex == -1)
         {
            ArrayResize(m_dailyStats, m_daysCount + 1);
            m_dailyStats[m_daysCount].date = dayStart;
            m_dailyStats[m_daysCount].totalTrades = 0;
            m_dailyStats[m_daysCount].wins = 0;
            m_dailyStats[m_daysCount].losses = 0;
            m_dailyStats[m_daysCount].profit = 0;
            dayIndex = m_daysCount;
            m_daysCount++;
         }

         // Update daily statistics
         m_dailyStats[dayIndex].totalTrades++;
         m_dailyStats[dayIndex].profit += m_trades[i].profit;

         if(m_trades[i].profit > 0)
            m_dailyStats[dayIndex].wins++;
         else
            m_dailyStats[dayIndex].losses++;
      }

      // Calculate daily metrics
      ArrayResize(m_dailyReturns, m_daysCount);
      m_returnsCount = m_daysCount;

      for(int i = 0; i < m_daysCount; i++)
      {
         m_dailyReturns[i] = m_dailyStats[i].profit;

         if(m_dailyStats[i].totalTrades > 0)
            m_dailyStats[i].winRate = (double)m_dailyStats[i].wins / m_dailyStats[i].totalTrades;
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Sharpe Ratio                                           |
   //| Using daily returns, annualized                                  |
   //+------------------------------------------------------------------+
   void CalculateSharpeRatio()
   {
      if(m_returnsCount < 2)
      {
         m_sharpeRatio = 0;
         return;
      }

      // Calculate mean return
      double sum = 0;
      for(int i = 0; i < m_returnsCount; i++)
         sum += m_dailyReturns[i];

      double mean = sum / m_returnsCount;

      // Calculate standard deviation
      double sumSqDiff = 0;
      for(int i = 0; i < m_returnsCount; i++)
      {
         double diff = m_dailyReturns[i] - mean;
         sumSqDiff += diff * diff;
      }

      double stdDev = MathSqrt(sumSqDiff / (m_returnsCount - 1));

      // Calculate Sharpe ratio (assuming 0 risk-free rate)
      // Annualized: multiply by sqrt(252) for daily returns
      if(stdDev > 0)
         m_sharpeRatio = (mean / stdDev) * MathSqrt(252);
      else
         m_sharpeRatio = 0;
   }

   //+------------------------------------------------------------------+
   //| Calculate maximum drawdown                                       |
   //+------------------------------------------------------------------+
   void CalculateMaxDrawdown()
   {
      if(m_tradeCount == 0)
      {
         m_maxDrawdown = 0;
         return;
      }

      double peak = 0;
      double cumulative = 0;
      m_maxDrawdown = 0;

      for(int i = 0; i < m_tradeCount; i++)
      {
         cumulative += m_trades[i].profit;

         if(cumulative > peak)
            peak = cumulative;

         double drawdown = peak - cumulative;
         if(drawdown > m_maxDrawdown)
            m_maxDrawdown = drawdown;
      }
   }

   //+------------------------------------------------------------------+
   //| Load trade history from file                                     |
   //+------------------------------------------------------------------+
   bool LoadTradeHistory()
   {
      string filename = m_basePath + m_symbol + "_trades.csv";

      int fileHandle = FileOpen(filename, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
         return false;

      // Skip header
      if(!FileIsEnding(fileHandle))
         FileReadString(fileHandle);

      ArrayResize(m_trades, 0);
      m_tradeCount = 0;

      while(!FileIsEnding(fileHandle))
      {
         STradeReportRecord record;

         string ticketStr = FileReadString(fileHandle);
         if(StringLen(ticketStr) == 0) break;

         record.ticket = StringToInteger(ticketStr);
         record.openTime = StringToTime(FileReadString(fileHandle));
         record.closeTime = StringToTime(FileReadString(fileHandle));
         record.symbol = FileReadString(fileHandle);
         record.type = (int)StringToInteger(FileReadString(fileHandle));
         record.lots = StringToDouble(FileReadString(fileHandle));
         record.openPrice = StringToDouble(FileReadString(fileHandle));
         record.closePrice = StringToDouble(FileReadString(fileHandle));
         record.sl = StringToDouble(FileReadString(fileHandle));
         record.tp = StringToDouble(FileReadString(fileHandle));
         record.profit = StringToDouble(FileReadString(fileHandle));
         record.profitPips = StringToDouble(FileReadString(fileHandle));
         record.commission = StringToDouble(FileReadString(fileHandle));
         record.swap = StringToDouble(FileReadString(fileHandle));
         record.comment = FileReadString(fileHandle);

         ArrayResize(m_trades, m_tradeCount + 1);
         m_trades[m_tradeCount] = record;
         m_tradeCount++;

         // Update totals
         if(record.profit > 0)
         {
            m_totalWins++;
            m_totalProfit += record.profit;
         }
         else
         {
            m_totalLosses++;
            m_totalLoss += MathAbs(record.profit);
         }
      }

      FileClose(fileHandle);
      CalculateAllStatistics();
      return true;
   }

   //+------------------------------------------------------------------+
   //| Save trade history to CSV                                        |
   //+------------------------------------------------------------------+
   bool SaveTradeHistory()
   {
      if(m_tradeCount == 0) return true;

      string filename = m_basePath + m_symbol + "_trades.csv";

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
      {
         Print("Error saving trade history: ", GetLastError());
         return false;
      }

      // Write header
      FileWrite(fileHandle, "Ticket", "OpenTime", "CloseTime", "Symbol", "Type",
                "Lots", "OpenPrice", "ClosePrice", "SL", "TP", "Profit",
                "ProfitPips", "Commission", "Swap", "Comment");

      // Write records
      for(int i = 0; i < m_tradeCount; i++)
      {
         FileWrite(fileHandle,
                   m_trades[i].ticket,
                   TimeToString(m_trades[i].openTime, TIME_DATE | TIME_MINUTES),
                   TimeToString(m_trades[i].closeTime, TIME_DATE | TIME_MINUTES),
                   m_trades[i].symbol,
                   m_trades[i].type == 0 ? "Buy" : "Sell",
                   m_trades[i].lots,
                   m_trades[i].openPrice,
                   m_trades[i].closePrice,
                   m_trades[i].sl,
                   m_trades[i].tp,
                   m_trades[i].profit,
                   m_trades[i].profitPips,
                   m_trades[i].commission,
                   m_trades[i].swap,
                   m_trades[i].comment);
      }

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Export daily statistics to CSV                                   |
   //+------------------------------------------------------------------+
   bool ExportDailyStats()
   {
      CalculateDailyReturns();

      string filename = m_basePath + m_symbol + "_daily.csv";

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
         return false;

      FileWrite(fileHandle, "Date", "Trades", "Wins", "Losses", "WinRate",
                "Profit", "Drawdown");

      for(int i = 0; i < m_daysCount; i++)
      {
         FileWrite(fileHandle,
                   TimeToString(m_dailyStats[i].date, TIME_DATE),
                   m_dailyStats[i].totalTrades,
                   m_dailyStats[i].wins,
                   m_dailyStats[i].losses,
                   m_dailyStats[i].winRate * 100,
                   m_dailyStats[i].profit,
                   m_dailyStats[i].drawdown);
      }

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Export summary report to CSV                                     |
   //+------------------------------------------------------------------+
   bool ExportSummaryReport()
   {
      CalculateAllStatistics();

      string filename = m_basePath + m_symbol + "_summary.csv";

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
         return false;

      FileWrite(fileHandle, "Metric", "Value");
      FileWrite(fileHandle, "Symbol", m_symbol);
      FileWrite(fileHandle, "EA Name", m_eaName);
      FileWrite(fileHandle, "Report Date", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
      FileWrite(fileHandle, "Total Trades", m_tradeCount);
      FileWrite(fileHandle, "Wins", m_totalWins);
      FileWrite(fileHandle, "Losses", m_totalLosses);
      FileWrite(fileHandle, "Win Rate (%)", m_tradeCount > 0 ? (double)m_totalWins / m_tradeCount * 100 : 0);
      FileWrite(fileHandle, "Total Profit", m_totalProfit);
      FileWrite(fileHandle, "Total Loss", m_totalLoss);
      FileWrite(fileHandle, "Net Profit", m_totalProfit - m_totalLoss);
      FileWrite(fileHandle, "Profit Factor", m_profitFactor);
      FileWrite(fileHandle, "Average Win", m_averageWin);
      FileWrite(fileHandle, "Average Loss", m_averageLoss);
      FileWrite(fileHandle, "Max Drawdown", m_maxDrawdown);
      FileWrite(fileHandle, "Sharpe Ratio", m_sharpeRatio);
      FileWrite(fileHandle, "Trading Days", m_daysCount);

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Export weekly statistics                                        |
   //+------------------------------------------------------------------+
   bool ExportWeeklyStats()
   {
      if(m_tradeCount == 0) return true;

      string filename = m_basePath + m_symbol + "_weekly.csv";

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
         return false;

      // Group by week
      FileWrite(fileHandle, "WeekStart", "Trades", "Wins", "Losses", "WinRate", "Profit");

      // Simple weekly aggregation
      datetime currentWeekStart = 0;
      int weekTrades = 0, weekWins = 0, weekLosses = 0;
      double weekProfit = 0;

      for(int i = 0; i < m_tradeCount; i++)
      {
         MqlDateTime dt;
         TimeToStruct(m_trades[i].closeTime, dt);

         // Calculate week start (Monday)
         int daysFromMonday = (dt.day_of_week == 0) ? 6 : dt.day_of_week - 1;
         dt.hour = 0;
         dt.min = 0;
         dt.sec = 0;
         datetime weekStart = StructToTime(dt) - (daysFromMonday * 86400);

         if(weekStart != currentWeekStart && currentWeekStart > 0)
         {
            // Write previous week
            FileWrite(fileHandle,
                      TimeToString(currentWeekStart, TIME_DATE),
                      weekTrades, weekWins, weekLosses,
                      weekTrades > 0 ? (double)weekWins / weekTrades * 100 : 0,
                      weekProfit);

            weekTrades = 0;
            weekWins = 0;
            weekLosses = 0;
            weekProfit = 0;
         }

         currentWeekStart = weekStart;
         weekTrades++;
         weekProfit += m_trades[i].profit;

         if(m_trades[i].profit > 0)
            weekWins++;
         else
            weekLosses++;
      }

      // Write last week
      if(weekTrades > 0)
      {
         FileWrite(fileHandle,
                   TimeToString(currentWeekStart, TIME_DATE),
                   weekTrades, weekWins, weekLosses,
                   (double)weekWins / weekTrades * 100,
                   weekProfit);
      }

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Export monthly statistics                                       |
   //+------------------------------------------------------------------+
   bool ExportMonthlyStats()
   {
      if(m_tradeCount == 0) return true;

      string filename = m_basePath + m_symbol + "_monthly.csv";

      int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fileHandle == INVALID_HANDLE)
         return false;

      FileWrite(fileHandle, "Month", "Trades", "Wins", "Losses", "WinRate", "Profit");

      // Group by month
      int currentYear = 0, currentMonth = 0;
      int monthTrades = 0, monthWins = 0, monthLosses = 0;
      double monthProfit = 0;

      for(int i = 0; i < m_tradeCount; i++)
      {
         MqlDateTime dt;
         TimeToStruct(m_trades[i].closeTime, dt);

         if((dt.year != currentYear || dt.mon != currentMonth) && currentMonth > 0)
         {
            // Write previous month
            FileWrite(fileHandle,
                      StringFormat("%d-%02d", currentYear, currentMonth),
                      monthTrades, monthWins, monthLosses,
                      monthTrades > 0 ? (double)monthWins / monthTrades * 100 : 0,
                      monthProfit);

            monthTrades = 0;
            monthWins = 0;
            monthLosses = 0;
            monthProfit = 0;
         }

         currentYear = dt.year;
         currentMonth = dt.mon;
         monthTrades++;
         monthProfit += m_trades[i].profit;

         if(m_trades[i].profit > 0)
            monthWins++;
         else
            monthLosses++;
      }

      // Write last month
      if(monthTrades > 0)
      {
         FileWrite(fileHandle,
                   StringFormat("%d-%02d", currentYear, currentMonth),
                   monthTrades, monthWins, monthLosses,
                   (double)monthWins / monthTrades * 100,
                   monthProfit);
      }

      FileClose(fileHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Save all reports                                                 |
   //+------------------------------------------------------------------+
   bool SaveAllReports()
   {
      bool success = true;

      success &= SaveTradeHistory();
      success &= ExportDailyStats();
      success &= ExportWeeklyStats();
      success &= ExportMonthlyStats();
      success &= ExportSummaryReport();

      if(success)
         Print("All reports saved successfully to ", m_basePath);

      return success;
   }

   //+------------------------------------------------------------------+
   //| Print current statistics                                        |
   //+------------------------------------------------------------------+
   void PrintStatistics()
   {
      CalculateAllStatistics();

      Print("=== Trading Performance Report ===");
      Print("Symbol: ", m_symbol);
      Print("Total Trades: ", m_tradeCount);
      Print("Wins: ", m_totalWins, " | Losses: ", m_totalLosses);
      Print("Win Rate: ", m_tradeCount > 0 ?
            DoubleToString((double)m_totalWins / m_tradeCount * 100, 1) : "0", "%");
      Print("Net Profit: ", DoubleToString(m_totalProfit - m_totalLoss, 2));
      Print("Profit Factor: ", DoubleToString(m_profitFactor, 2));
      Print("Average Win: ", DoubleToString(m_averageWin, 2));
      Print("Average Loss: ", DoubleToString(m_averageLoss, 2));
      Print("Max Drawdown: ", DoubleToString(m_maxDrawdown, 2));
      Print("Sharpe Ratio: ", DoubleToString(m_sharpeRatio, 2));
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   int GetTradeCount() { return m_tradeCount; }
   int GetWinCount() { return m_totalWins; }
   int GetLossCount() { return m_totalLosses; }
   double GetTotalProfit() { return m_totalProfit; }
   double GetTotalLoss() { return m_totalLoss; }
   double GetNetProfit() { return m_totalProfit - m_totalLoss; }
   double GetProfitFactor() { return m_profitFactor; }
   double GetSharpeRatio() { return m_sharpeRatio; }
   double GetMaxDrawdown() { return m_maxDrawdown; }
   double GetWinRate() { return m_tradeCount > 0 ? (double)m_totalWins / m_tradeCount : 0; }
   bool IsInitialized() { return m_isInitialized; }
};
