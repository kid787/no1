//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                          ML EMA Scalping EA - Risk Module        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ML EMA Scalping EA"
#property strict

//+------------------------------------------------------------------+
//| Risk Level Enumeration                                            |
//+------------------------------------------------------------------+
enum ENUM_RISK_LEVEL
{
   RISK_LEVEL_NORMAL = 0,    // Normal risk
   RISK_LEVEL_REDUCED = 1,   // Reduced risk (50%)
   RISK_LEVEL_MINIMAL = 2,   // Minimal risk (25%)
   RISK_LEVEL_BLOCKED = 3    // Trading blocked
};

//+------------------------------------------------------------------+
//| Risk Manager Class                                                |
//| Handles VaR, correlation, DD control, and lot sizing             |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   string            m_symbol;

   // Account info
   double            m_initialBalance;
   double            m_dailyStartEquity;
   datetime          m_dailyResetTime;

   // Risk parameters
   double            m_maxDailyLossPercent;      // Fintokei 5% rule
   double            m_maxTotalLossPercent;      // Fintokei 10% rule
   double            m_maxPositionRiskPercent;   // Max risk per position (3%)
   double            m_maxDrawdownPercent;       // DD threshold for lot reduction (20%)
   double            m_lotReductionFactor;       // Lot reduction multiplier (0.5)

   // VaR parameters
   double            m_varConfidenceLevel;       // 99% confidence
   int               m_varLookbackPeriod;        // Days for VaR calculation

   // Correlation parameters
   string            m_correlationSymbol1;       // USDJPY
   string            m_correlationSymbol2;       // GBPJPY
   double            m_maxCorrelation;           // 0.8 threshold
   int               m_correlationPeriod;        // Bars for correlation

   // State
   ENUM_RISK_LEVEL   m_currentRiskLevel;
   double            m_currentDrawdown;
   double            m_currentDailyPnL;
   double            m_correlationValue;
   double            m_varValue;
   bool              m_isInitialized;

   // Historical returns for VaR
   double            m_returns[];
   int               m_returnsCount;

public:
   // Constructor
   CRiskManager()
   {
      m_symbol = "";
      m_initialBalance = 0;
      m_dailyStartEquity = 0;
      m_dailyResetTime = 0;

      m_maxDailyLossPercent = 5.0;      // Fintokei rule
      m_maxTotalLossPercent = 10.0;     // Fintokei rule
      m_maxPositionRiskPercent = 3.0;   // Fintokei rule
      m_maxDrawdownPercent = 20.0;
      m_lotReductionFactor = 0.5;

      m_varConfidenceLevel = 0.99;
      m_varLookbackPeriod = 30;

      m_correlationSymbol1 = "USDJPY";
      m_correlationSymbol2 = "GBPJPY";
      m_maxCorrelation = 0.8;
      m_correlationPeriod = 100;

      m_currentRiskLevel = RISK_LEVEL_NORMAL;
      m_currentDrawdown = 0;
      m_currentDailyPnL = 0;
      m_correlationValue = 0;
      m_varValue = 0;
      m_isInitialized = false;
      m_returnsCount = 0;
   }

   // Destructor
   ~CRiskManager() {}

   //+------------------------------------------------------------------+
   //| Initialize Risk Manager                                          |
   //+------------------------------------------------------------------+
   bool Init(string symbol, double initialBalance = 0)
   {
      m_symbol = symbol;

      // Get account info
      m_initialBalance = (initialBalance > 0) ? initialBalance :
                          AccountInfoDouble(ACCOUNT_BALANCE);
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dailyResetTime = GetDailyResetTime();

      // Initialize VaR calculation
      CalculateHistoricalReturns();

      m_isInitialized = true;
      Print("Risk Manager initialized. Initial Balance: ", m_initialBalance);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get UTC midnight (daily reset time for Fintokei)                 |
   //+------------------------------------------------------------------+
   datetime GetDailyResetTime()
   {
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);

      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;

      return StructToTime(dt);
   }

   //+------------------------------------------------------------------+
   //| Check and update daily reset                                     |
   //+------------------------------------------------------------------+
   void CheckDailyReset()
   {
      datetime currentResetTime = GetDailyResetTime();

      if(currentResetTime > m_dailyResetTime)
      {
         // New trading day - reset daily equity baseline
         m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_dailyResetTime = currentResetTime;
         m_currentDailyPnL = 0;

         Print("Daily reset. New baseline equity: ", m_dailyStartEquity);
      }
   }

   //+------------------------------------------------------------------+
   //| Update all risk calculations                                     |
   //+------------------------------------------------------------------+
   void Update()
   {
      CheckDailyReset();
      UpdateDrawdown();
      UpdateDailyPnL();
      CalculateVaR();
      CalculateCorrelation();
      UpdateRiskLevel();
   }

   //+------------------------------------------------------------------+
   //| Update current drawdown                                          |
   //+------------------------------------------------------------------+
   void UpdateDrawdown()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Calculate drawdown from initial balance
      m_currentDrawdown = ((m_initialBalance - equity) / m_initialBalance) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Update daily P&L                                                  |
   //+------------------------------------------------------------------+
   void UpdateDailyPnL()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_currentDailyPnL = currentEquity - m_dailyStartEquity;
   }

   //+------------------------------------------------------------------+
   //| Calculate historical returns for VaR                             |
   //+------------------------------------------------------------------+
   void CalculateHistoricalReturns()
   {
      // Get daily close prices
      double closes[];
      ArraySetAsSeries(closes, true);

      int copied = CopyClose(m_symbol, PERIOD_D1, 0, m_varLookbackPeriod + 1, closes);
      if(copied < m_varLookbackPeriod + 1)
      {
         Print("Not enough data for VaR calculation");
         return;
      }

      // Calculate daily returns
      ArrayResize(m_returns, m_varLookbackPeriod);
      m_returnsCount = m_varLookbackPeriod;

      for(int i = 0; i < m_varLookbackPeriod; i++)
      {
         m_returns[i] = (closes[i] - closes[i + 1]) / closes[i + 1];
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Value at Risk (99% confidence)                        |
   //+------------------------------------------------------------------+
   void CalculateVaR()
   {
      if(m_returnsCount < 10)
      {
         m_varValue = 0;
         return;
      }

      // Sort returns for percentile calculation
      double sortedReturns[];
      ArrayCopy(sortedReturns, m_returns);
      ArraySort(sortedReturns);

      // Find the 1st percentile (for 99% VaR)
      int percentileIndex = (int)MathFloor(m_returnsCount * (1.0 - m_varConfidenceLevel));
      if(percentileIndex < 0) percentileIndex = 0;

      // VaR is the absolute value of the worst-case return at confidence level
      m_varValue = MathAbs(sortedReturns[percentileIndex]);

      // Convert to monetary value based on position size
      // This gives us the expected max loss at 99% confidence
   }

   //+------------------------------------------------------------------+
   //| Calculate correlation between two symbols                        |
   //+------------------------------------------------------------------+
   void CalculateCorrelation()
   {
      // Check if correlation symbols are available
      if(!SymbolSelect(m_correlationSymbol1, true) ||
         !SymbolSelect(m_correlationSymbol2, true))
      {
         m_correlationValue = 0;
         return;
      }

      // Get close prices for both symbols
      double closes1[], closes2[];
      ArraySetAsSeries(closes1, true);
      ArraySetAsSeries(closes2, true);

      if(CopyClose(m_correlationSymbol1, PERIOD_H1, 0, m_correlationPeriod, closes1) < m_correlationPeriod ||
         CopyClose(m_correlationSymbol2, PERIOD_H1, 0, m_correlationPeriod, closes2) < m_correlationPeriod)
      {
         m_correlationValue = 0;
         return;
      }

      // Calculate Pearson correlation coefficient
      double sum1 = 0, sum2 = 0, sum1Sq = 0, sum2Sq = 0, sumProduct = 0;

      for(int i = 0; i < m_correlationPeriod; i++)
      {
         sum1 += closes1[i];
         sum2 += closes2[i];
         sum1Sq += closes1[i] * closes1[i];
         sum2Sq += closes2[i] * closes2[i];
         sumProduct += closes1[i] * closes2[i];
      }

      double n = (double)m_correlationPeriod;
      double numerator = n * sumProduct - sum1 * sum2;
      double denominator = MathSqrt((n * sum1Sq - sum1 * sum1) * (n * sum2Sq - sum2 * sum2));

      if(denominator != 0)
         m_correlationValue = numerator / denominator;
      else
         m_correlationValue = 0;
   }

   //+------------------------------------------------------------------+
   //| Update risk level based on current conditions                    |
   //+------------------------------------------------------------------+
   void UpdateRiskLevel()
   {
      // Check for total loss limit (10%)
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double totalLossLimit = m_initialBalance * (m_maxTotalLossPercent / 100.0);

      if(m_initialBalance - equity >= totalLossLimit * 0.95)  // 95% of limit as warning
      {
         m_currentRiskLevel = RISK_LEVEL_BLOCKED;
         Print("RISK BLOCKED: Approaching total loss limit");
         return;
      }

      // Check for daily loss limit (5%)
      double dailyLossLimit = m_dailyStartEquity * (m_maxDailyLossPercent / 100.0);

      if(MathAbs(m_currentDailyPnL) >= dailyLossLimit * 0.9 && m_currentDailyPnL < 0)
      {
         m_currentRiskLevel = RISK_LEVEL_BLOCKED;
         Print("RISK BLOCKED: Approaching daily loss limit");
         return;
      }

      // Check for drawdown threshold (20%)
      if(m_currentDrawdown >= m_maxDrawdownPercent)
      {
         m_currentRiskLevel = RISK_LEVEL_REDUCED;
         Print("RISK REDUCED: Drawdown ", m_currentDrawdown, "% exceeds threshold");
         return;
      }

      // Normal risk level
      m_currentRiskLevel = RISK_LEVEL_NORMAL;
   }

   //+------------------------------------------------------------------+
   //| Check if trading is allowed                                      |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      Update();
      return (m_currentRiskLevel != RISK_LEVEL_BLOCKED);
   }

   //+------------------------------------------------------------------+
   //| Check if new entry is allowed for symbol                        |
   //+------------------------------------------------------------------+
   bool IsEntryAllowed(string symbol)
   {
      // Check if trading is blocked
      if(!IsTradingAllowed())
         return false;

      // Check correlation filter
      if(MathAbs(m_correlationValue) > m_maxCorrelation)
      {
         // If correlation is too high, only allow one of the correlated pairs
         if(symbol == m_correlationSymbol1 || symbol == m_correlationSymbol2)
         {
            // Check if we have open position in the other symbol
            if(symbol == m_correlationSymbol1 && HasOpenPosition(m_correlationSymbol2))
               return false;
            if(symbol == m_correlationSymbol2 && HasOpenPosition(m_correlationSymbol1))
               return false;
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if symbol has open position                                |
   //+------------------------------------------------------------------+
   bool HasOpenPosition(string symbol)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)))
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
               return true;
         }
      }
      return false;
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
   //| Calculate loss per lot for given SL distance                    |
   //+------------------------------------------------------------------+
   double CalculateLossPerLot(string symbol, double slPips)
   {
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double pipSize = GetPipSize(symbol);

      double slDistance = slPips * pipSize;
      double numTicks = slDistance / tickSize;

      return numTicks * tickValue;
   }

   //+------------------------------------------------------------------+
   //| Normalize lot size according to broker constraints              |
   //+------------------------------------------------------------------+
   double NormalizeLotSize(string symbol, double lots)
   {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(lots < minLot) lots = minLot;
      if(lots > maxLot) lots = maxLot;

      lots = MathFloor(lots / lotStep) * lotStep;

      if(lots < minLot) lots = minLot;

      return lots;
   }

   //+------------------------------------------------------------------+
   //| Calculate optimal lot size based on risk                        |
   //| Incorporates Fintokei rules and VaR constraints                 |
   //+------------------------------------------------------------------+
   double CalculateLotSize(string symbol, double slPips)
   {
      Update();  // Update all risk metrics

      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Step 1: Calculate maximum allowed risk for this position
      double maxRiskAmount = accountBalance * (m_maxPositionRiskPercent / 100.0);

      // Step 2: Apply daily loss constraint
      double dailyLossLimit = m_dailyStartEquity * (m_maxDailyLossPercent / 100.0);
      double remainingDailyRisk = dailyLossLimit - MathAbs(MathMin(0, m_currentDailyPnL));
      if(remainingDailyRisk < maxRiskAmount)
         maxRiskAmount = remainingDailyRisk;

      // Step 3: Apply total loss constraint
      double totalLossLimit = m_initialBalance * (m_maxTotalLossPercent / 100.0);
      double remainingTotalRisk = totalLossLimit - (m_initialBalance - accountEquity);
      if(remainingTotalRisk < maxRiskAmount)
         maxRiskAmount = remainingTotalRisk;

      // Step 4: Apply risk level reduction
      switch(m_currentRiskLevel)
      {
         case RISK_LEVEL_REDUCED:
            maxRiskAmount *= m_lotReductionFactor;
            break;
         case RISK_LEVEL_MINIMAL:
            maxRiskAmount *= 0.25;
            break;
         case RISK_LEVEL_BLOCKED:
            return 0;
      }

      // Step 5: Apply VaR constraint
      if(m_varValue > 0)
      {
         // Adjust risk based on VaR - higher VaR = lower position size
         double varAdjustment = 1.0 / (1.0 + m_varValue * 10);
         maxRiskAmount *= varAdjustment;
      }

      // Step 6: Calculate lot size from risk amount
      double lossPerLot = CalculateLossPerLot(symbol, slPips);
      if(lossPerLot <= 0)
      {
         Print("Error: Invalid loss per lot calculation");
         return 0;
      }

      double lots = maxRiskAmount / lossPerLot;

      // Normalize and return
      return NormalizeLotSize(symbol, lots);
   }

   //+------------------------------------------------------------------+
   //| Calculate dynamic SL/TP based on ATR and spread                 |
   //+------------------------------------------------------------------+
   void CalculateDynamicSLTP(string symbol, ENUM_TIMEFRAMES timeframe,
                              double &slPips, double &tpPips,
                              double atrMultiplier = 1.5, double rrRatio = 1.0)
   {
      // Get ATR value
      int atrHandle = iATR(symbol, timeframe, 14);
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);

      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) < 1)
      {
         IndicatorRelease(atrHandle);
         slPips = 20;  // Default
         tpPips = 20 * rrRatio;
         return;
      }

      double atr = atrBuffer[0];
      IndicatorRelease(atrHandle);

      // Get spread in pips
      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) *
                      SymbolInfoDouble(symbol, SYMBOL_POINT);
      double pipSize = GetPipSize(symbol);
      double spreadPips = spread / pipSize;

      // Calculate SL based on ATR
      slPips = (atr * atrMultiplier) / pipSize;

      // Minimum SL = 3x spread
      double minSL = spreadPips * 3;
      if(slPips < minSL) slPips = minSL;

      // Calculate TP maintaining R:R ratio
      tpPips = slPips * rrRatio;
   }

   //+------------------------------------------------------------------+
   //| Check if we should close positions due to risk limits           |
   //+------------------------------------------------------------------+
   bool ShouldCloseAllPositions()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Check total loss limit
      double totalLossLimit = m_initialBalance * (m_maxTotalLossPercent / 100.0);
      if(m_initialBalance - equity >= totalLossLimit * 0.98)  // 98% of limit
         return true;

      // Check daily loss limit
      double dailyLossLimit = m_dailyStartEquity * (m_maxDailyLossPercent / 100.0);
      if(m_currentDailyPnL < 0 && MathAbs(m_currentDailyPnL) >= dailyLossLimit * 0.98)
         return true;

      return false;
   }

   //+------------------------------------------------------------------+
   //| Get remaining daily risk amount                                  |
   //+------------------------------------------------------------------+
   double GetRemainingDailyRisk()
   {
      double dailyLossLimit = m_dailyStartEquity * (m_maxDailyLossPercent / 100.0);
      double usedRisk = MathMax(0, MathAbs(MathMin(0, m_currentDailyPnL)));
      return dailyLossLimit - usedRisk;
   }

   //+------------------------------------------------------------------+
   //| Get remaining total risk amount                                  |
   //+------------------------------------------------------------------+
   double GetRemainingTotalRisk()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double totalLossLimit = m_initialBalance * (m_maxTotalLossPercent / 100.0);
      double usedRisk = MathMax(0, m_initialBalance - equity);
      return totalLossLimit - usedRisk;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   double GetCurrentDrawdown() { return m_currentDrawdown; }
   double GetDailyPnL() { return m_currentDailyPnL; }
   double GetCorrelation() { return m_correlationValue; }
   double GetVaR() { return m_varValue; }
   ENUM_RISK_LEVEL GetRiskLevel() { return m_currentRiskLevel; }
   double GetInitialBalance() { return m_initialBalance; }
   double GetDailyStartEquity() { return m_dailyStartEquity; }
   bool IsInitialized() { return m_isInitialized; }

   //+------------------------------------------------------------------+
   //| Set custom parameters                                            |
   //+------------------------------------------------------------------+
   void SetDailyLossLimit(double percent) { m_maxDailyLossPercent = percent; }
   void SetTotalLossLimit(double percent) { m_maxTotalLossPercent = percent; }
   void SetPositionRiskLimit(double percent) { m_maxPositionRiskPercent = percent; }
   void SetDrawdownThreshold(double percent) { m_maxDrawdownPercent = percent; }
   void SetCorrelationThreshold(double threshold) { m_maxCorrelation = threshold; }
   void SetCorrelationSymbols(string sym1, string sym2)
   {
      m_correlationSymbol1 = sym1;
      m_correlationSymbol2 = sym2;
   }

   //+------------------------------------------------------------------+
   //| Print risk status                                                |
   //+------------------------------------------------------------------+
   void PrintStatus()
   {
      Print("=== Risk Manager Status ===");
      Print("Initial Balance: ", m_initialBalance);
      Print("Daily Start Equity: ", m_dailyStartEquity);
      Print("Current Equity: ", AccountInfoDouble(ACCOUNT_EQUITY));
      Print("Daily P&L: ", m_currentDailyPnL);
      Print("Drawdown: ", m_currentDrawdown, "%");
      Print("Correlation (", m_correlationSymbol1, "/", m_correlationSymbol2, "): ", m_correlationValue);
      Print("VaR (99%): ", m_varValue * 100, "%");
      Print("Risk Level: ", EnumToString(m_currentRiskLevel));
      Print("Remaining Daily Risk: ", GetRemainingDailyRisk());
      Print("Remaining Total Risk: ", GetRemainingTotalRisk());
   }
};
