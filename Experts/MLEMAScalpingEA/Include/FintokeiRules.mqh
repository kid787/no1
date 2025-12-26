//+------------------------------------------------------------------+
//|                                                FintokeiRules.mqh |
//|                       ML EMA Scalping EA - Fintokei Compliance   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ML EMA Scalping EA"
#property strict

//+------------------------------------------------------------------+
//| Fintokei Challenge Status Enumeration                            |
//+------------------------------------------------------------------+
enum ENUM_FINTOKEI_STATUS
{
   FINTOKEI_OK = 0,           // All rules satisfied
   FINTOKEI_WARNING = 1,      // Approaching limit
   FINTOKEI_BLOCKED = 2,      // Cannot trade (at limit)
   FINTOKEI_FAILED = 3        // Challenge failed
};

//+------------------------------------------------------------------+
//| Rule violation details                                            |
//+------------------------------------------------------------------+
struct SRuleViolation
{
   bool              dailyLossViolation;
   bool              totalLossViolation;
   bool              positionRiskViolation;
   double            dailyLossPercent;
   double            totalLossPercent;
   double            positionRiskPercent;
   string            message;
};

//+------------------------------------------------------------------+
//| Fintokei Rules Compliance Class                                   |
//| Ensures EA complies with Fintokei challenge rules                 |
//+------------------------------------------------------------------+
class CFintokeiRules
{
private:
   // Account information
   double            m_initialBalance;         // Initial capital (never changes)
   double            m_dailyStartEquity;       // Equity at day start (UTC 0:00)
   datetime          m_dailyResetTime;         // Last daily reset timestamp

   // Fintokei limits
   double            m_maxDailyLossPercent;    // 5%
   double            m_maxTotalLossPercent;    // 10%
   double            m_maxPositionRiskPercent; // 3% per position

   // Warning thresholds (percentage of limit)
   double            m_warningThreshold;       // 80% of limit triggers warning
   double            m_blockThreshold;         // 95% of limit blocks trading

   // Current status
   ENUM_FINTOKEI_STATUS m_status;
   SRuleViolation    m_violation;
   bool              m_isInitialized;

   // Position tracking
   double            m_totalOpenRisk;          // Total risk from open positions

public:
   // Constructor
   CFintokeiRules()
   {
      m_initialBalance = 0;
      m_dailyStartEquity = 0;
      m_dailyResetTime = 0;

      m_maxDailyLossPercent = 5.0;
      m_maxTotalLossPercent = 10.0;
      m_maxPositionRiskPercent = 3.0;

      m_warningThreshold = 0.80;
      m_blockThreshold = 0.95;

      m_status = FINTOKEI_OK;
      m_totalOpenRisk = 0;
      m_isInitialized = false;

      ResetViolation();
   }

   // Destructor
   ~CFintokeiRules() {}

   //+------------------------------------------------------------------+
   //| Reset violation record                                           |
   //+------------------------------------------------------------------+
   void ResetViolation()
   {
      m_violation.dailyLossViolation = false;
      m_violation.totalLossViolation = false;
      m_violation.positionRiskViolation = false;
      m_violation.dailyLossPercent = 0;
      m_violation.totalLossPercent = 0;
      m_violation.positionRiskPercent = 0;
      m_violation.message = "";
   }

   //+------------------------------------------------------------------+
   //| Initialize with account parameters                               |
   //+------------------------------------------------------------------+
   bool Init(double initialBalance = 0)
   {
      // Get initial balance (this should be set to the starting capital)
      m_initialBalance = (initialBalance > 0) ? initialBalance :
                          AccountInfoDouble(ACCOUNT_BALANCE);

      // Set daily baseline to current equity
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Initialize daily reset time
      m_dailyResetTime = GetUTCMidnight();

      m_isInitialized = true;

      Print("Fintokei Rules Initialized");
      Print("Initial Balance: ", m_initialBalance);
      Print("Daily Fail Line: ", m_dailyStartEquity * (1 - m_maxDailyLossPercent / 100));
      Print("Total Fail Line: ", m_initialBalance * (1 - m_maxTotalLossPercent / 100));

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get UTC midnight timestamp                                       |
   //+------------------------------------------------------------------+
   datetime GetUTCMidnight()
   {
      datetime now = TimeCurrent();

      // Get server time offset from UTC
      // This is a simplified approach - in production, consider using TimeGMT()
      MqlDateTime dt;
      TimeToStruct(now, dt);

      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;

      return StructToTime(dt);
   }

   //+------------------------------------------------------------------+
   //| Check and perform daily reset                                    |
   //+------------------------------------------------------------------+
   void CheckDailyReset()
   {
      datetime currentMidnight = GetUTCMidnight();

      if(currentMidnight > m_dailyResetTime)
      {
         // New trading day - update daily equity baseline
         double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

         // Important: The daily baseline is the equity at start of day
         // This includes any unrealized P&L from positions held overnight
         m_dailyStartEquity = currentEquity;
         m_dailyResetTime = currentMidnight;

         Print("=== FINTOKEI DAILY RESET ===");
         Print("New trading day started");
         Print("Daily Start Equity: ", m_dailyStartEquity);
         Print("Daily Fail Line: ", m_dailyStartEquity * (1 - m_maxDailyLossPercent / 100));

         // Clear warnings from previous day
         if(m_status == FINTOKEI_WARNING || m_status == FINTOKEI_BLOCKED)
            m_status = FINTOKEI_OK;
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate current daily loss percentage                          |
   //+------------------------------------------------------------------+
   double GetDailyLossPercent()
   {
      CheckDailyReset();

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double loss = m_dailyStartEquity - currentEquity;

      if(loss <= 0) return 0;  // No loss

      return (loss / m_dailyStartEquity) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Calculate current total loss percentage                          |
   //+------------------------------------------------------------------+
   double GetTotalLossPercent()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double loss = m_initialBalance - currentEquity;

      if(loss <= 0) return 0;  // No loss

      return (loss / m_initialBalance) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Get daily fail line (equity level that triggers failure)         |
   //+------------------------------------------------------------------+
   double GetDailyFailLine()
   {
      return m_dailyStartEquity * (1 - m_maxDailyLossPercent / 100.0);
   }

   //+------------------------------------------------------------------+
   //| Get total fail line (equity level that triggers failure)         |
   //+------------------------------------------------------------------+
   double GetTotalFailLine()
   {
      return m_initialBalance * (1 - m_maxTotalLossPercent / 100.0);
   }

   //+------------------------------------------------------------------+
   //| Check all rules and update status                                |
   //+------------------------------------------------------------------+
   ENUM_FINTOKEI_STATUS CheckRules()
   {
      CheckDailyReset();
      ResetViolation();

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Get loss percentages
      m_violation.dailyLossPercent = GetDailyLossPercent();
      m_violation.totalLossPercent = GetTotalLossPercent();

      // Check TOTAL loss rule (10%)
      if(m_violation.totalLossPercent >= m_maxTotalLossPercent)
      {
         m_status = FINTOKEI_FAILED;
         m_violation.totalLossViolation = true;
         m_violation.message = "FAILED: Total loss limit exceeded (" +
                               DoubleToString(m_violation.totalLossPercent, 2) + "%)";
         return m_status;
      }

      // Check DAILY loss rule (5%)
      if(m_violation.dailyLossPercent >= m_maxDailyLossPercent)
      {
         m_status = FINTOKEI_FAILED;
         m_violation.dailyLossViolation = true;
         m_violation.message = "FAILED: Daily loss limit exceeded (" +
                               DoubleToString(m_violation.dailyLossPercent, 2) + "%)";
         return m_status;
      }

      // Check if approaching limits (block threshold - 95%)
      if(m_violation.totalLossPercent >= m_maxTotalLossPercent * m_blockThreshold ||
         m_violation.dailyLossPercent >= m_maxDailyLossPercent * m_blockThreshold)
      {
         m_status = FINTOKEI_BLOCKED;
         m_violation.message = "BLOCKED: Approaching loss limit - trading suspended";
         return m_status;
      }

      // Check if approaching limits (warning threshold - 80%)
      if(m_violation.totalLossPercent >= m_maxTotalLossPercent * m_warningThreshold ||
         m_violation.dailyLossPercent >= m_maxDailyLossPercent * m_warningThreshold)
      {
         m_status = FINTOKEI_WARNING;
         m_violation.message = "WARNING: Approaching loss limit - reduce position size";
         return m_status;
      }

      m_status = FINTOKEI_OK;
      return m_status;
   }

   //+------------------------------------------------------------------+
   //| Check if trading is allowed                                      |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      CheckRules();
      return (m_status == FINTOKEI_OK || m_status == FINTOKEI_WARNING);
   }

   //+------------------------------------------------------------------+
   //| Calculate maximum allowed position risk                          |
   //+------------------------------------------------------------------+
   double GetMaxAllowedRisk()
   {
      CheckDailyReset();

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Base risk limit (3% of balance)
      double baseRisk = balance * (m_maxPositionRiskPercent / 100.0);

      // Calculate remaining daily risk allowance
      double dailyFailLine = GetDailyFailLine();
      double remainingDailyRisk = equity - dailyFailLine;
      if(remainingDailyRisk < 0) remainingDailyRisk = 0;

      // Calculate remaining total risk allowance
      double totalFailLine = GetTotalFailLine();
      double remainingTotalRisk = equity - totalFailLine;
      if(remainingTotalRisk < 0) remainingTotalRisk = 0;

      // Return minimum of all constraints
      double maxRisk = MathMin(baseRisk, MathMin(remainingDailyRisk, remainingTotalRisk));

      // Apply safety margin (use 80% of available risk)
      maxRisk *= 0.8;

      return maxRisk;
   }

   //+------------------------------------------------------------------+
   //| Validate proposed trade risk                                     |
   //+------------------------------------------------------------------+
   bool ValidateTradeRisk(double riskAmount)
   {
      double maxAllowed = GetMaxAllowedRisk();

      if(riskAmount > maxAllowed)
      {
         m_violation.positionRiskViolation = true;
         m_violation.positionRiskPercent = (riskAmount / AccountInfoDouble(ACCOUNT_BALANCE)) * 100;
         m_violation.message = "Position risk too high: " +
                               DoubleToString(riskAmount, 2) + " > " +
                               DoubleToString(maxAllowed, 2);
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate safe lot size based on Fintokei rules                  |
   //+------------------------------------------------------------------+
   double CalculateSafeLotSize(string symbol, double slPips, double desiredRiskPercent = 2.0)
   {
      // Get max allowed risk considering all Fintokei constraints
      double maxAllowedRisk = GetMaxAllowedRisk();

      // Calculate desired risk amount
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double desiredRiskAmount = balance * (desiredRiskPercent / 100.0);

      // Use the smaller of desired and max allowed
      double actualRiskAmount = MathMin(desiredRiskAmount, maxAllowedRisk);

      // Calculate lot size
      double pipSize = GetPipSize(symbol);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

      double slDistance = slPips * pipSize;
      double numTicks = slDistance / tickSize;
      double lossPerLot = numTicks * tickValue;

      if(lossPerLot <= 0) return 0;

      double lots = actualRiskAmount / lossPerLot;

      // Normalize lot size
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      lots = MathFloor(lots / lotStep) * lotStep;

      if(lots < minLot) lots = minLot;
      if(lots > maxLot) lots = maxLot;

      return lots;
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
   //| Check if position should be emergency closed                     |
   //+------------------------------------------------------------------+
   bool ShouldEmergencyClose()
   {
      CheckRules();

      // Emergency close if at 98% of any limit
      return (m_violation.dailyLossPercent >= m_maxDailyLossPercent * 0.98 ||
              m_violation.totalLossPercent >= m_maxTotalLossPercent * 0.98);
   }

   //+------------------------------------------------------------------+
   //| Get risk reduction multiplier based on current status            |
   //+------------------------------------------------------------------+
   double GetRiskMultiplier()
   {
      CheckRules();

      switch(m_status)
      {
         case FINTOKEI_OK:
            return 1.0;
         case FINTOKEI_WARNING:
            return 0.5;   // Reduce risk by 50%
         case FINTOKEI_BLOCKED:
            return 0.0;   // No new positions
         case FINTOKEI_FAILED:
            return 0.0;
      }

      return 0.0;
   }

   //+------------------------------------------------------------------+
   //| Get remaining daily loss allowance                               |
   //+------------------------------------------------------------------+
   double GetRemainingDailyLoss()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double failLine = GetDailyFailLine();
      return MathMax(0, currentEquity - failLine);
   }

   //+------------------------------------------------------------------+
   //| Get remaining total loss allowance                               |
   //+------------------------------------------------------------------+
   double GetRemainingTotalLoss()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double failLine = GetTotalFailLine();
      return MathMax(0, currentEquity - failLine);
   }

   //+------------------------------------------------------------------+
   //| Print current status                                             |
   //+------------------------------------------------------------------+
   void PrintStatus()
   {
      CheckRules();

      Print("=== FINTOKEI RULES STATUS ===");
      Print("Initial Balance: ", m_initialBalance);
      Print("Daily Start Equity: ", m_dailyStartEquity);
      Print("Current Equity: ", AccountInfoDouble(ACCOUNT_EQUITY));
      Print("");
      Print("Daily Loss: ", DoubleToString(m_violation.dailyLossPercent, 2), "% / ", m_maxDailyLossPercent, "%");
      Print("Total Loss: ", DoubleToString(m_violation.totalLossPercent, 2), "% / ", m_maxTotalLossPercent, "%");
      Print("");
      Print("Daily Fail Line: ", GetDailyFailLine());
      Print("Total Fail Line: ", GetTotalFailLine());
      Print("Remaining Daily Risk: ", GetRemainingDailyLoss());
      Print("Remaining Total Risk: ", GetRemainingTotalLoss());
      Print("");
      Print("Status: ", EnumToString(m_status));

      if(m_violation.message != "")
         Print("Message: ", m_violation.message);
   }

   //+------------------------------------------------------------------+
   //| Create on-chart status display                                   |
   //+------------------------------------------------------------------+
   void DisplayOnChart(int x = 10, int y = 50)
   {
      CheckRules();

      string prefix = "FTK_";
      color textColor = clrWhite;

      // Status color
      switch(m_status)
      {
         case FINTOKEI_OK:
            textColor = clrLime;
            break;
         case FINTOKEI_WARNING:
            textColor = clrYellow;
            break;
         case FINTOKEI_BLOCKED:
            textColor = clrOrange;
            break;
         case FINTOKEI_FAILED:
            textColor = clrRed;
            break;
      }

      // Create/update labels
      CreateLabel(prefix + "Title", "FINTOKEI STATUS", x, y, clrWhite, 10);

      CreateLabel(prefix + "DailyLoss",
                  StringFormat("Daily: %.2f%% / %.1f%%", m_violation.dailyLossPercent, m_maxDailyLossPercent),
                  x, y + 15,
                  m_violation.dailyLossPercent > m_maxDailyLossPercent * m_warningThreshold ? clrYellow : clrWhite, 9);

      CreateLabel(prefix + "TotalLoss",
                  StringFormat("Total: %.2f%% / %.1f%%", m_violation.totalLossPercent, m_maxTotalLossPercent),
                  x, y + 28,
                  m_violation.totalLossPercent > m_maxTotalLossPercent * m_warningThreshold ? clrYellow : clrWhite, 9);

      CreateLabel(prefix + "Status",
                  "Status: " + EnumToString(m_status),
                  x, y + 41, textColor, 9);

      CreateLabel(prefix + "RiskRemain",
                  StringFormat("Risk Remain: %.0f", GetRemainingDailyLoss()),
                  x, y + 54, clrSilver, 8);
   }

   //+------------------------------------------------------------------+
   //| Helper: Create chart label                                       |
   //+------------------------------------------------------------------+
   void CreateLabel(string name, string text, int x, int y, color clr, int fontSize)
   {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }

   //+------------------------------------------------------------------+
   //| Remove chart display                                             |
   //+------------------------------------------------------------------+
   void RemoveChartDisplay()
   {
      ObjectDelete(0, "FTK_Title");
      ObjectDelete(0, "FTK_DailyLoss");
      ObjectDelete(0, "FTK_TotalLoss");
      ObjectDelete(0, "FTK_Status");
      ObjectDelete(0, "FTK_RiskRemain");
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   ENUM_FINTOKEI_STATUS GetStatus() { return m_status; }
   SRuleViolation GetViolation() { return m_violation; }
   double GetInitialBalance() { return m_initialBalance; }
   double GetDailyStartEquity() { return m_dailyStartEquity; }
   bool IsInitialized() { return m_isInitialized; }

   //+------------------------------------------------------------------+
   //| Setters for custom limits                                        |
   //+------------------------------------------------------------------+
   void SetDailyLossLimit(double percent) { m_maxDailyLossPercent = percent; }
   void SetTotalLossLimit(double percent) { m_maxTotalLossPercent = percent; }
   void SetPositionRiskLimit(double percent) { m_maxPositionRiskPercent = percent; }
   void SetWarningThreshold(double threshold) { m_warningThreshold = threshold; }
   void SetBlockThreshold(double threshold) { m_blockThreshold = threshold; }
};
