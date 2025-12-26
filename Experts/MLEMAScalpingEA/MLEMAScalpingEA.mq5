//+------------------------------------------------------------------+
//|                                              MLEMAScalpingEA.mq5 |
//|                     Session Breakout EA for MT5                  |
//|                                v4.0 - Asian Session Breakout     |
//|                                                                  |
//|  Strategy:                                                       |
//|  - Calculate Asian session (00:00-07:00) high/low range          |
//|  - Trade breakout during London session (07:00-16:00)            |
//|  - BUY: Price breaks above Asian high + buffer                   |
//|  - SELL: Price breaks below Asian low - buffer                   |
//|  - One trade per direction per day                               |
//|  - SL at opposite side of range                                  |
//|  - Fintokei challenge rule compliance                            |
//+------------------------------------------------------------------+
#property copyright "Session Breakout EA v4.0"
#property link      ""
#property version   "4.00"
#property description "Asian Session Breakout EA with Fintokei compliance"
#property strict

//--- Include modules
#include "Include/SignalManager.mqh"
#include "Include/MLOptimizer.mqh"
#include "Include/RiskManager.mqh"
#include "Include/ReportGenerator.mqh"
#include "Include/FintokeiRules.mqh"

//--- Include standard libraries
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//--- General Settings
input group "=== General Settings ==="
input string   InpEAName           = "Session_Breakout"; // EA Name (for magic number)
input bool     InpEnableTrading    = true;               // Enable Trading
input bool     InpShowChartInfo    = true;               // Show Chart Information

//--- Session Breakout Settings
input group "=== Session Breakout Settings ==="
input int      InpAsianStartHour   = 0;                  // Asian Session Start (Server Hour)
input int      InpAsianEndHour     = 7;                  // Asian Session End (Server Hour)
input int      InpLondonStartHour  = 7;                  // London Trading Start (Server Hour)
input int      InpLondonEndHour    = 16;                 // London Trading End (Server Hour)
input double   InpBreakoutBuffer   = 5.0;                // Breakout Buffer (Pips)
input double   InpMinRangeSize     = 15.0;               // Minimum Range Size (Pips)
input double   InpMaxRangeSize     = 80.0;               // Maximum Range Size (Pips)

//--- Risk Management
input group "=== Risk Management ==="
input double   InpRiskPercent      = 2.0;                // Risk Per Trade (%)
input double   InpRRRatio          = 1.5;                // Risk:Reward Ratio
input double   InpMaxDailyLoss     = 5.0;                // Max Daily Loss (%) - Fintokei
input double   InpMaxTotalLoss     = 10.0;               // Max Total Loss (%) - Fintokei
input double   InpMaxPositionRisk  = 3.0;                // Max Position Risk (%) - Fintokei
input double   InpDrawdownThreshold = 5.0;              // DD Threshold for Lot Reduction (%)

//--- Loss Cooldown Settings
input group "=== Loss Cooldown ==="
input bool     InpUseCooldown      = true;               // Use Loss Cooldown
input int      InpMaxConsecLosses  = 3;                  // Max Consecutive Losses Before Cooldown
input int      InpCooldownBars     = 12;                 // Cooldown Period (Bars)

//--- ML Optimization (optional)
input group "=== ML Optimization ==="
input bool     InpEnableML         = false;              // Enable ML Time Filter
input int      InpMLLearningDays   = 30;                 // ML Learning Period (Days)
input double   InpMinExpectancy    = 0.0;                // Minimum Expectancy to Trade

//--- Advanced Settings
input group "=== Advanced Settings ==="
input int      InpSlippage         = 30;                 // Max Slippage (Points)
input int      InpATRPeriod        = 14;                 // ATR Period
input double   InpInitialBalance   = 0;                  // Initial Balance (0=Auto)

//+------------------------------------------------------------------+
//| Global Objects                                                    |
//+------------------------------------------------------------------+
CSignalManager    SignalMgr;           // Signal generation
CMLOptimizer      MLOptimizer;         // ML time optimization
CRiskManager      RiskMgr;             // Risk management
CReportGenerator  ReportGen;           // Performance reporting
CFintokeiRules    FintokeiRules;       // Fintokei compliance
CTrade            Trade;               // Trading operations
CPositionInfo     PositionInfo;        // Position information

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int               g_magicNumber;       // Unique EA identifier
datetime          g_lastBarTime;       // Last processed bar time
bool              g_isNewBar;          // New bar flag
int               g_totalTrades;       // Total trades taken
datetime          g_lastTradeTime;     // Last trade timestamp

// Cooldown tracking
int               g_consecutiveLosses; // Consecutive loss counter
datetime          g_cooldownEndTime;   // Cooldown end time
bool              g_inCooldown;        // Currently in cooldown

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("===========================================");
   Print("Session Breakout EA v4.0 Initializing...");
   Print("===========================================");

   //--- Generate magic number from EA name
   g_magicNumber = GenerateMagicNumber(InpEAName);
   Print("Magic Number: ", g_magicNumber);

   //--- Initialize trading object
   Trade.SetExpertMagicNumber(g_magicNumber);
   Trade.SetDeviationInPoints(InpSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   //--- Initialize Signal Manager
   if(!SignalMgr.Init(_Symbol, PERIOD_M5, 0, 0, InpATRPeriod))
   {
      Print("ERROR: Failed to initialize Signal Manager");
      return INIT_FAILED;
   }

   // Set session times
   SignalMgr.SetSessionTimes(InpAsianStartHour, InpAsianEndHour, InpLondonStartHour, InpLondonEndHour);

   // Set breakout parameters
   SignalMgr.SetBreakoutParams(InpBreakoutBuffer, InpMinRangeSize, InpMaxRangeSize);

   Print("Signal Manager initialized");
   Print("Asian Session: ", InpAsianStartHour, ":00 - ", InpAsianEndHour, ":00");
   Print("London Trading: ", InpLondonStartHour, ":00 - ", InpLondonEndHour, ":00");
   Print("Breakout Buffer: ", InpBreakoutBuffer, " pips");
   Print("Range Limits: ", InpMinRangeSize, " - ", InpMaxRangeSize, " pips");

   //--- Initialize ML Optimizer (optional)
   if(InpEnableML)
   {
      if(!MLOptimizer.Init(_Symbol, InpMLLearningDays, InpMinExpectancy))
      {
         Print("WARNING: ML Optimizer initialization failed - continuing without ML");
      }
      else
      {
         Print("ML Optimizer initialized");
      }
   }

   //--- Initialize Risk Manager
   double initialBal = (InpInitialBalance > 0) ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   if(!RiskMgr.Init(_Symbol, initialBal))
   {
      Print("ERROR: Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   RiskMgr.SetDailyLossLimit(InpMaxDailyLoss);
   RiskMgr.SetTotalLossLimit(InpMaxTotalLoss);
   RiskMgr.SetPositionRiskLimit(InpMaxPositionRisk);
   RiskMgr.SetDrawdownThreshold(InpDrawdownThreshold);
   Print("Risk Manager initialized");

   //--- Initialize Fintokei Rules
   if(!FintokeiRules.Init(initialBal))
   {
      Print("ERROR: Failed to initialize Fintokei Rules");
      return INIT_FAILED;
   }
   FintokeiRules.SetDailyLossLimit(InpMaxDailyLoss);
   FintokeiRules.SetTotalLossLimit(InpMaxTotalLoss);
   FintokeiRules.SetPositionRiskLimit(InpMaxPositionRisk);
   Print("Fintokei Rules initialized");

   //--- Initialize Report Generator
   if(!ReportGen.Init(_Symbol, InpEAName))
   {
      Print("WARNING: Report Generator initialization failed");
   }
   Print("Report Generator initialized");

   //--- Initialize variables
   g_lastBarTime = 0;
   g_isNewBar = false;
   g_totalTrades = 0;
   g_lastTradeTime = 0;
   g_consecutiveLosses = 0;
   g_cooldownEndTime = 0;
   g_inCooldown = false;

   //--- Display initial info
   if(InpShowChartInfo)
   {
      DisplayChartInfo();
   }

   Print("===========================================");
   Print("EA Initialization Complete");
   Print("Symbol: ", _Symbol);
   Print("Strategy: Asian Session Breakout");
   Print("Risk Per Trade: ", InpRiskPercent, "%");
   Print("Risk:Reward Ratio: 1:", InpRRRatio);
   Print("===========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Deinitializing... Reason: ", reason);

   //--- Save reports
   ReportGen.SaveAllReports();
   ReportGen.PrintStatistics();

   //--- Print ML statistics
   if(InpEnableML)
   {
      MLOptimizer.PrintStatisticsReport();
   }

   //--- Print risk status
   RiskMgr.PrintStatus();

   //--- Remove chart objects
   FintokeiRules.RemoveChartDisplay();
   RemoveChartInfo();

   //--- Cleanup
   SignalMgr.Deinit();

   Print("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if trading is enabled
   if(!InpEnableTrading) return;

   //--- Check for new bar (main strategy runs on bar close)
   g_isNewBar = IsNewBar();

   //--- Update chart info periodically
   if(InpShowChartInfo)
   {
      static datetime lastInfoUpdate = 0;
      if(TimeCurrent() - lastInfoUpdate >= 1)
      {
         DisplayChartInfo();
         FintokeiRules.DisplayOnChart(10, 250);
         lastInfoUpdate = TimeCurrent();
      }
   }

   //--- CRITICAL: Check for emergency close due to Fintokei rules
   if(FintokeiRules.ShouldEmergencyClose())
   {
      Print("EMERGENCY: Fintokei limit approaching - closing all positions");
      CloseAllPositions();
      return;
   }

   //--- Additional Fintokei safety check
   double currentLoss = FintokeiRules.GetTotalLossPercent();
   if(currentLoss >= InpMaxTotalLoss * 0.9)  // 90% of limit
   {
      Print("WARNING: Approaching total loss limit (", currentLoss, "%) - blocking new trades");
      return;
   }

   //--- Main trading logic runs on new bar
   if(g_isNewBar)
   {
      ProcessTradingLogic();
   }
}

//+------------------------------------------------------------------+
//| Check if currently in cooldown period                            |
//+------------------------------------------------------------------+
bool IsInCooldown()
{
   if(!InpUseCooldown) return false;

   if(g_inCooldown)
   {
      if(TimeCurrent() >= g_cooldownEndTime)
      {
         g_inCooldown = false;
         g_consecutiveLosses = 0;
         Print("Cooldown period ended - resuming trading");
         return false;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Start cooldown period                                            |
//+------------------------------------------------------------------+
void StartCooldown()
{
   g_inCooldown = true;
   g_cooldownEndTime = TimeCurrent() + (InpCooldownBars * PeriodSeconds(PERIOD_M5));
   Print("COOLDOWN STARTED: ", g_consecutiveLosses, " consecutive losses. Resuming at ", TimeToString(g_cooldownEndTime));
}

//+------------------------------------------------------------------+
//| Process main trading logic                                       |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   //--- Check cooldown
   if(IsInCooldown())
   {
      return;
   }

   //--- Check Fintokei rules first
   if(!FintokeiRules.IsTradingAllowed())
   {
      return;
   }

   //--- Check risk manager
   if(!RiskMgr.IsTradingAllowed())
   {
      return;
   }

   //--- Check ML time filter (if enabled)
   if(InpEnableML && !MLOptimizer.IsOptimalTime())
   {
      return;
   }

   //--- Check if we already have a position
   if(HasOpenPosition())
   {
      return;
   }

   //--- Get trading signal
   ENUM_SIGNAL_TYPE signal = SignalMgr.GetSignal();

   if(signal == SIGNAL_NONE)
      return;

   //--- Execute trade
   if(signal == SIGNAL_BUY)
   {
      ExecuteBuyTrade();
      SignalMgr.MarkTradeTaken(SIGNAL_BUY);
   }
   else if(signal == SIGNAL_SELL)
   {
      ExecuteSellTrade();
      SignalMgr.MarkTradeTaken(SIGNAL_SELL);
   }
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade()
{
   //--- Calculate SL/TP
   double slPrice = SignalMgr.CalculateDynamicSL(SIGNAL_BUY);
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tpPrice = SignalMgr.CalculateTP(entryPrice, slPrice, SIGNAL_BUY, InpRRRatio);

   //--- Calculate SL in pips for lot sizing
   double pipSize = GetPipSize(_Symbol);
   double slPips = MathAbs(entryPrice - slPrice) / pipSize;

   //--- Calculate lot size using Fintokei-safe calculation
   double lots = FintokeiRules.CalculateSafeLotSize(_Symbol, slPips, InpRiskPercent);

   if(lots <= 0)
   {
      Print("Lot size calculation returned 0 - trade cancelled");
      return;
   }

   //--- Validate with risk manager
   double riskAmount = CalculateRiskAmount(lots, slPips);
   if(!FintokeiRules.ValidateTradeRisk(riskAmount))
   {
      Print("Trade risk validation failed");
      return;
   }

   //--- Execute trade
   string comment = StringFormat("%s_BUY_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("BUY order executed: ", lots, " lots at ", entryPrice);
      Print("SL: ", slPrice, " (", slPips, " pips) | TP: ", tpPrice, " | RR: 1:", InpRRRatio);
      Print("Asian Range - High: ", SignalMgr.GetAsianHigh(), " Low: ", SignalMgr.GetAsianLow());
      g_totalTrades++;
      g_lastTradeTime = TimeCurrent();
   }
   else
   {
      Print("BUY order failed: ", Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute sell trade                                                |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
{
   //--- Calculate SL/TP
   double slPrice = SignalMgr.CalculateDynamicSL(SIGNAL_SELL);
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpPrice = SignalMgr.CalculateTP(entryPrice, slPrice, SIGNAL_SELL, InpRRRatio);

   //--- Calculate SL in pips for lot sizing
   double pipSize = GetPipSize(_Symbol);
   double slPips = MathAbs(slPrice - entryPrice) / pipSize;

   //--- Calculate lot size using Fintokei-safe calculation
   double lots = FintokeiRules.CalculateSafeLotSize(_Symbol, slPips, InpRiskPercent);

   if(lots <= 0)
   {
      Print("Lot size calculation returned 0 - trade cancelled");
      return;
   }

   //--- Validate with risk manager
   double riskAmount = CalculateRiskAmount(lots, slPips);
   if(!FintokeiRules.ValidateTradeRisk(riskAmount))
   {
      Print("Trade risk validation failed");
      return;
   }

   //--- Execute trade
   string comment = StringFormat("%s_SELL_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("SELL order executed: ", lots, " lots at ", entryPrice);
      Print("SL: ", slPrice, " (", slPips, " pips) | TP: ", tpPrice, " | RR: 1:", InpRRRatio);
      Print("Asian Range - High: ", SignalMgr.GetAsianHigh(), " Low: ", SignalMgr.GetAsianLow());
      g_totalTrades++;
      g_lastTradeTime = TimeCurrent();
   }
   else
   {
      Print("SELL order failed: ", Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Trade event handler                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   static int lastHistoryDeals = 0;

   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   if(totalDeals > lastHistoryDeals)
   {
      for(int i = lastHistoryDeals; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(magic != g_magicNumber) continue;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long type = HistoryDealGetInteger(ticket, DEAL_TYPE);

            double netProfit = profit + commission + swap;

            //--- Update consecutive loss counter
            if(netProfit < 0)
            {
               g_consecutiveLosses++;
               if(InpUseCooldown && g_consecutiveLosses >= InpMaxConsecLosses)
               {
                  StartCooldown();
               }
            }
            else
            {
               g_consecutiveLosses = 0;
            }

            //--- Record in ML
            if(InpEnableML)
            {
               datetime openTime = time - PeriodSeconds(PERIOD_M5);
               double pipSize = GetPipSize(symbol);
               double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
               double profitPips = (tickValue > 0) ? profit / tickValue * pipSize : 0;
               MLOptimizer.AddTradeRecord(openTime, time, netProfit, profitPips, false);
            }

            //--- Record in Report Generator
            int posType = (type == DEAL_TYPE_BUY) ? 1 : 0;
            datetime openTime = time - PeriodSeconds(PERIOD_M5);
            ReportGen.AddTrade((long)ticket, openTime, time, symbol, posType,
                               volume, price, price, 0, 0, profit, commission, swap, "");

            Print("Trade closed - Net Profit: ", netProfit,
                  " | Consecutive Losses: ", g_consecutiveLosses);
         }
      }

      lastHistoryDeals = totalDeals;
   }
}

//+------------------------------------------------------------------+
//| Check if there's an open position                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionInfo.SelectByIndex(i))
         continue;

      if(PositionInfo.Symbol() != _Symbol)
         continue;

      if(PositionInfo.Magic() != g_magicNumber)
         continue;

      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionInfo.SelectByIndex(i))
         continue;

      if(PositionInfo.Symbol() != _Symbol)
         continue;

      if(PositionInfo.Magic() != g_magicNumber)
         continue;

      Trade.PositionClose(PositionInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Check for new bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);

   if(g_lastBarTime != currentBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Generate magic number from string                                 |
//+------------------------------------------------------------------+
int GenerateMagicNumber(string name)
{
   int hash = 0;
   for(int i = 0; i < StringLen(name); i++)
   {
      hash = hash * 31 + StringGetCharacter(name, i);
   }
   return MathAbs(hash) % 1000000 + 100000;
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
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(string symbol, double lots)
{
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return lots;
}

//+------------------------------------------------------------------+
//| Calculate risk amount for given lots and SL                      |
//+------------------------------------------------------------------+
double CalculateRiskAmount(double lots, double slPips)
{
   double pipSize = GetPipSize(_Symbol);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;

   return numTicks * tickValue * lots;
}

//+------------------------------------------------------------------+
//| Display chart information                                        |
//+------------------------------------------------------------------+
void DisplayChartInfo()
{
   string prefix = "SB_";
   int x = 10, y = 20;
   int yStep = 15;

   //--- EA Info
   CreateLabel(prefix + "Title", "=== Session Breakout EA v4.0 ===", x, y, clrGold, 10);
   y += yStep + 5;

   //--- Symbol and time
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   CreateLabel(prefix + "Symbol", StringFormat("Symbol: %s | Time: %02d:%02d", _Symbol, dt.hour, dt.min), x, y, clrWhite, 9);
   y += yStep;

   //--- Asian Range info
   double asianHigh = SignalMgr.GetAsianHigh();
   double asianLow = SignalMgr.GetAsianLow();
   double rangeSize = SignalMgr.GetRangeSize();
   bool rangeCalc = SignalMgr.IsRangeCalculated();

   string rangeStatus = rangeCalc ? StringFormat("%.5f - %.5f (%.1f pips)", asianLow, asianHigh, rangeSize) : "Not calculated yet";
   color rangeColor = rangeCalc ? clrLime : clrYellow;
   CreateLabel(prefix + "Range", "Asian Range: " + rangeStatus, x, y, rangeColor, 9);
   y += yStep;

   //--- Range validity
   if(rangeCalc)
   {
      bool validRange = (rangeSize >= InpMinRangeSize && rangeSize <= InpMaxRangeSize);
      string validStr = validRange ? "VALID" : "OUT OF BOUNDS";
      color validColor = validRange ? clrLime : clrRed;
      CreateLabel(prefix + "Valid", StringFormat("Range Status: %s (%.0f-%.0f pips)", validStr, InpMinRangeSize, InpMaxRangeSize), x, y, validColor, 9);
      y += yStep;
   }

   //--- Current price vs range
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string positionStr = "IN RANGE";
   color posColor = clrYellow;

   if(rangeCalc && asianHigh > 0)
   {
      double buffer = InpBreakoutBuffer * GetPipSize(_Symbol);
      if(currentPrice > asianHigh + buffer)
      {
         positionStr = "ABOVE RANGE (BUY ZONE)";
         posColor = clrLime;
      }
      else if(currentPrice < asianLow - buffer)
      {
         positionStr = "BELOW RANGE (SELL ZONE)";
         posColor = clrRed;
      }
   }
   CreateLabel(prefix + "Position", "Price Position: " + positionStr, x, y, posColor, 9);
   y += yStep;

   //--- Trading window
   bool isLondonTime = SignalMgr.IsLondonTradingTime();
   string windowStr = isLondonTime ? "OPEN" : "CLOSED";
   color windowColor = isLondonTime ? clrLime : clrGray;
   CreateLabel(prefix + "Window", StringFormat("Trading Window: %s (%02d:00-%02d:00)", windowStr, InpLondonStartHour, InpLondonEndHour), x, y, windowColor, 9);
   y += yStep;

   //--- Trades taken today
   bool buyTaken = SignalMgr.IsBuyTakenToday();
   bool sellTaken = SignalMgr.IsSellTakenToday();
   string takenStr = StringFormat("BUY: %s | SELL: %s", buyTaken ? "DONE" : "AVAILABLE", sellTaken ? "DONE" : "AVAILABLE");
   CreateLabel(prefix + "Taken", "Today's Trades: " + takenStr, x, y, clrSilver, 9);
   y += yStep;

   //--- Cooldown status
   if(InpUseCooldown)
   {
      string cooldownStr = g_inCooldown ?
                           StringFormat("COOLDOWN (ends: %s)", TimeToString(g_cooldownEndTime, TIME_MINUTES)) :
                           StringFormat("Active (Losses: %d/%d)", g_consecutiveLosses, InpMaxConsecLosses);
      color cooldownColor = g_inCooldown ? clrOrange : clrLime;
      CreateLabel(prefix + "Cooldown", "Status: " + cooldownStr, x, y, cooldownColor, 9);
      y += yStep;
   }

   //--- Risk info
   double dd = RiskMgr.GetCurrentDrawdown();
   color ddColor = (dd > 7) ? clrRed : (dd > 4) ? clrYellow : clrLime;
   CreateLabel(prefix + "DD", StringFormat("Drawdown: %.2f%%", dd), x, y, ddColor, 9);
   y += yStep;

   //--- Trade stats
   CreateLabel(prefix + "Trades", StringFormat("Total Trades: %d | Win Rate: %.1f%%",
               ReportGen.GetTradeCount(), ReportGen.GetWinRate() * 100), x, y, clrSilver, 9);
   y += yStep;

   CreateLabel(prefix + "PnL", StringFormat("Net P/L: %.2f | PF: %.2f",
               ReportGen.GetNetProfit(), ReportGen.GetProfitFactor()), x, y, clrSilver, 9);
}

//+------------------------------------------------------------------+
//| Create chart label                                               |
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
//| Remove chart info objects                                        |
//+------------------------------------------------------------------+
void RemoveChartInfo()
{
   string prefix = "SB_";
   ObjectsDeleteAll(0, prefix);
}
//+------------------------------------------------------------------+
