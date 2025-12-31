//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                     Fintokei Risk Management for Gold EA         |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

//+------------------------------------------------------------------+
//| Fintokei Risk Management Class                                   |
//| - 1日最大損失5%ルール (UTC 0時基準)                               |
//| - 全体最大損失10%ルール (初期資金基準)                             |
//| - ポジションリスク最大3%                                          |
//| - 段階的ロット削減 (5%損失で50%減、8%損失で更に50%減)              |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   double            m_InitialBalance;          // 初期資金
   double            m_DayStartEquity;          // 当日開始時の有効証拠金 (UTC 0時)
   datetime          m_LastDayUpdate;           // 最後に日次更新した日時

   double            m_MaxDailyLossPercent;     // 1日最大損失率 (5%)
   double            m_MaxTotalLossPercent;     // 全体最大損失率 (10%)
   double            m_MaxPositionRiskPercent;  // 1ポジションの最大リスク (3%)

   double            m_LotReduction1Threshold;  // ロット削減1閾値 (5%)
   double            m_LotReduction2Threshold;  // ロット削減2閾値 (8%)
   double            m_LotReduction1Factor;     // ロット削減1係数 (0.5)
   double            m_LotReduction2Factor;     // ロット削減2係数 (0.25)

   bool              m_IsInitialized;

public:
   //--- Constructor
   CRiskManager()
   {
      m_InitialBalance = 0;
      m_DayStartEquity = 0;
      m_LastDayUpdate = 0;

      m_MaxDailyLossPercent = 5.0;
      m_MaxTotalLossPercent = 10.0;
      m_MaxPositionRiskPercent = 3.0;

      m_LotReduction1Threshold = 5.0;
      m_LotReduction2Threshold = 8.0;
      m_LotReduction1Factor = 0.5;
      m_LotReduction2Factor = 0.25;

      m_IsInitialized = false;
   }

   //--- Initialize with account balance
   bool Initialize(double initialBalance = 0)
   {
      if(initialBalance > 0)
         m_InitialBalance = initialBalance;
      else
         m_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      m_DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_LastDayUpdate = GetUTCDayStart();
      m_IsInitialized = true;

      PrintFormat("[RiskManager] Initialized: InitialBalance=%.2f, DayStartEquity=%.2f",
                  m_InitialBalance, m_DayStartEquity);

      return true;
   }

   //--- Update daily equity at UTC 0:00
   void UpdateDailyEquity()
   {
      datetime currentDayStart = GetUTCDayStart();

      if(currentDayStart > m_LastDayUpdate)
      {
         m_DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_LastDayUpdate = currentDayStart;

         PrintFormat("[RiskManager] Daily equity updated: %.2f", m_DayStartEquity);
      }
   }

   //--- Get UTC day start time
   datetime GetUTCDayStart()
   {
      datetime serverTime = TimeCurrent();
      int gmtOffset = (int)((TimeLocal() - TimeGMT()) / 3600);
      datetime utcTime = serverTime - gmtOffset * 3600;

      MqlDateTime dt;
      TimeToStruct(utcTime, dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;

      return StructToTime(dt);
   }

   //--- Get current equity
   double GetCurrentEquity()
   {
      return AccountInfoDouble(ACCOUNT_EQUITY);
   }

   //--- Get current balance
   double GetCurrentBalance()
   {
      return AccountInfoDouble(ACCOUNT_BALANCE);
   }

   //--- Calculate current daily loss percentage
   double GetDailyLossPercent()
   {
      UpdateDailyEquity();
      double currentEquity = GetCurrentEquity();
      double loss = m_DayStartEquity - currentEquity;

      if(m_DayStartEquity > 0)
         return (loss / m_DayStartEquity) * 100.0;

      return 0;
   }

   //--- Calculate total loss percentage from initial balance
   double GetTotalLossPercent()
   {
      double currentEquity = GetCurrentEquity();
      double loss = m_InitialBalance - currentEquity;

      if(m_InitialBalance > 0)
         return (loss / m_InitialBalance) * 100.0;

      return 0;
   }

   //--- Get daily loss limit (失格ライン)
   double GetDailyLossLimit()
   {
      return m_DayStartEquity * (1.0 - m_MaxDailyLossPercent / 100.0);
   }

   //--- Get total loss limit (全体失格ライン)
   double GetTotalLossLimit()
   {
      return m_InitialBalance * (1.0 - m_MaxTotalLossPercent / 100.0);
   }

   //--- Check if new trade is allowed
   bool IsTradeAllowed()
   {
      UpdateDailyEquity();

      double currentEquity = GetCurrentEquity();
      double dailyLimit = GetDailyLossLimit();
      double totalLimit = GetTotalLossLimit();

      // Check daily loss limit
      if(currentEquity <= dailyLimit)
      {
         PrintFormat("[RiskManager] BLOCKED: Daily loss limit reached. Equity=%.2f, Limit=%.2f",
                     currentEquity, dailyLimit);
         return false;
      }

      // Check total loss limit
      if(currentEquity <= totalLimit)
      {
         PrintFormat("[RiskManager] BLOCKED: Total loss limit reached. Equity=%.2f, Limit=%.2f",
                     currentEquity, totalLimit);
         return false;
      }

      return true;
   }

   //--- Check if position should be closed due to risk limits
   bool ShouldClosePositions()
   {
      double currentEquity = GetCurrentEquity();
      double dailyLimit = GetDailyLossLimit();
      double totalLimit = GetTotalLossLimit();

      // Safety margin (close before hitting exact limit)
      double safetyBuffer = 0.1; // 0.1% buffer
      double dailySafeLimit = m_DayStartEquity * (1.0 - (m_MaxDailyLossPercent - safetyBuffer) / 100.0);
      double totalSafeLimit = m_InitialBalance * (1.0 - (m_MaxTotalLossPercent - safetyBuffer) / 100.0);

      if(currentEquity <= dailySafeLimit || currentEquity <= totalSafeLimit)
      {
         PrintFormat("[RiskManager] EMERGENCY CLOSE: Equity=%.2f approaching limits", currentEquity);
         return true;
      }

      return false;
   }

   //--- Calculate lot reduction multiplier based on current losses
   double GetLotReductionMultiplier()
   {
      double totalLoss = GetTotalLossPercent();

      if(totalLoss >= m_LotReduction2Threshold)
      {
         // 8%以上損失: ロット25%
         PrintFormat("[RiskManager] Lot reduction: 25%% (loss=%.2f%%)", totalLoss);
         return m_LotReduction2Factor;
      }
      else if(totalLoss >= m_LotReduction1Threshold)
      {
         // 5%以上損失: ロット50%
         PrintFormat("[RiskManager] Lot reduction: 50%% (loss=%.2f%%)", totalLoss);
         return m_LotReduction1Factor;
      }

      return 1.0; // No reduction
   }

   //--- Calculate maximum allowed risk amount for new position
   double GetMaxRiskAmount()
   {
      UpdateDailyEquity();

      double currentEquity = GetCurrentEquity();
      double currentBalance = GetCurrentBalance();

      // Calculate remaining risk capacity
      double dailyLimit = GetDailyLossLimit();
      double totalLimit = GetTotalLossLimit();

      double remainingDailyRisk = currentEquity - dailyLimit;
      double remainingTotalRisk = currentEquity - totalLimit;

      // Get existing position risk
      double existingRisk = GetExistingPositionRisk();

      // Calculate max risk for new position (considering 3% per position limit)
      double maxPositionRisk = currentBalance * (m_MaxPositionRiskPercent / 100.0);

      // Use the most restrictive limit
      double maxRisk = MathMin(remainingDailyRisk - existingRisk, remainingTotalRisk - existingRisk);
      maxRisk = MathMin(maxRisk, maxPositionRisk);

      // Apply lot reduction if applicable
      maxRisk *= GetLotReductionMultiplier();

      if(maxRisk < 0)
         maxRisk = 0;

      return maxRisk;
   }

   //--- Get total risk of existing positions
   double GetExistingPositionRisk()
   {
      double totalRisk = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket))
         {
            double posProfit = PositionGetDouble(POSITION_PROFIT);
            double posSwap = PositionGetDouble(POSITION_SWAP);

            if(posProfit + posSwap < 0)
               totalRisk += MathAbs(posProfit + posSwap);
         }
      }

      return totalRisk;
   }

   //--- Get status string for logging
   string GetStatusString()
   {
      return StringFormat(
         "InitialBal=%.0f | DayStart=%.0f | Equity=%.0f | DailyLoss=%.2f%% | TotalLoss=%.2f%% | LotMult=%.2f",
         m_InitialBalance,
         m_DayStartEquity,
         GetCurrentEquity(),
         GetDailyLossPercent(),
         GetTotalLossPercent(),
         GetLotReductionMultiplier()
      );
   }

   //--- Getters
   double GetInitialBalance() { return m_InitialBalance; }
   double GetDayStartEquity() { return m_DayStartEquity; }
   double GetMaxDailyLossPercent() { return m_MaxDailyLossPercent; }
   double GetMaxTotalLossPercent() { return m_MaxTotalLossPercent; }
   double GetMaxPositionRiskPercent() { return m_MaxPositionRiskPercent; }

   //--- Setters
   void SetInitialBalance(double balance) { m_InitialBalance = balance; }
   void SetMaxDailyLossPercent(double pct) { m_MaxDailyLossPercent = pct; }
   void SetMaxTotalLossPercent(double pct) { m_MaxTotalLossPercent = pct; }
   void SetMaxPositionRiskPercent(double pct) { m_MaxPositionRiskPercent = pct; }
};

#endif // RISK_MANAGER_MQH
