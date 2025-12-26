//+------------------------------------------------------------------+
//|                                              MLEMAScalpingEA.mq5 |
//|                     ML-Enhanced 5-Minute EMA Scalping EA for MT5 |
//|                                                                  |
//|  Features:                                                       |
//|  - 900 SMA trend filter (daily level trend on 5-min chart)       |
//|  - 20 EMA entry trigger with breakout detection                  |
//|  - Machine learning time optimization                            |
//|  - VaR-based position sizing                                     |
//|  - Correlation analysis (USDJPY/GBPJPY)                          |
//|  - Fintokei challenge rule compliance                            |
//|  - Dynamic SL/TP based on ATR                                    |
//|  - Comprehensive reporting with CSV export                       |
//+------------------------------------------------------------------+
#property copyright "ML EMA Scalping EA"
#property link      ""
#property version   "1.00"
#property description "Advanced 5-minute EMA Scalping EA with ML optimization and Fintokei compliance"
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
input string   InpEAName           = "ML_EMA_Scalping";  // EA Name (for magic number)
input bool     InpEnableTrading    = true;               // Enable Trading
input bool     InpShowChartInfo    = true;               // Show Chart Information

//--- Signal Settings
input group "=== Signal Settings ==="
input int      InpSMAPeriod        = 900;                // SMA Period (Trend Filter)
input int      InpEMAPeriod        = 20;                 // EMA Period (Entry Trigger)
input int      InpATRPeriod        = 14;                 // ATR Period
input double   InpATRMultiplier    = 1.5;                // ATR Multiplier for SL

//--- Risk Management
input group "=== Risk Management ==="
input double   InpRiskPercent      = 2.0;                // Risk Per Trade (%)
input double   InpRRRatio          = 1.0;                // Risk:Reward Ratio
input double   InpMaxDailyLoss     = 5.0;                // Max Daily Loss (%) - Fintokei
input double   InpMaxTotalLoss     = 10.0;               // Max Total Loss (%) - Fintokei
input double   InpMaxPositionRisk  = 3.0;                // Max Position Risk (%) - Fintokei
input double   InpDrawdownThreshold = 20.0;              // DD Threshold for Lot Reduction (%)

//--- ML Optimization
input group "=== ML Optimization ==="
input bool     InpEnableML         = true;               // Enable ML Time Filter
input int      InpMLLearningDays   = 30;                 // ML Learning Period (Days)
input double   InpMinExpectancy    = 0.0;                // Minimum Expectancy to Trade
input int      InpMinSampleSize    = 5;                  // Minimum Trades per Hour for ML

//--- Correlation Settings
input group "=== Correlation Settings ==="
input bool     InpEnableCorrelation = true;              // Enable Correlation Filter
input string   InpCorrelationSym1  = "USDJPY";           // Correlation Symbol 1
input string   InpCorrelationSym2  = "GBPJPY";           // Correlation Symbol 2
input double   InpMaxCorrelation   = 0.8;                // Max Correlation Threshold

//--- Advanced Settings
input group "=== Advanced Settings ==="
input int      InpSlippage         = 30;                 // Max Slippage (Points)
input bool     InpUseEarlyExit     = true;               // Use Early Exit (EMA Reversal)
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

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("===========================================");
   Print("ML EMA Scalping EA Initializing...");
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
   if(!SignalMgr.Init(_Symbol, PERIOD_M5, InpSMAPeriod, InpEMAPeriod, InpATRPeriod))
   {
      Print("ERROR: Failed to initialize Signal Manager");
      return INIT_FAILED;
   }
   Print("Signal Manager initialized");

   //--- Initialize ML Optimizer
   if(!MLOptimizer.Init(_Symbol, InpMLLearningDays, InpMinExpectancy))
   {
      Print("WARNING: ML Optimizer initialization failed - continuing without ML");
   }
   else
   {
      Print("ML Optimizer initialized with ", MLOptimizer.GetTradeCount(), " historical trades");
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
   RiskMgr.SetCorrelationThreshold(InpMaxCorrelation);
   RiskMgr.SetCorrelationSymbols(InpCorrelationSym1, InpCorrelationSym2);
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

   //--- Display initial info
   if(InpShowChartInfo)
   {
      DisplayChartInfo();
   }

   Print("===========================================");
   Print("EA Initialization Complete");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: M5");
   Print("Risk Per Trade: ", InpRiskPercent, "%");
   Print("ML Enabled: ", InpEnableML ? "Yes" : "No");
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
      MLOptimizer.ExportStatisticsToCSV();
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
      if(TimeCurrent() - lastInfoUpdate >= 1)  // Update every second
      {
         DisplayChartInfo();
         FintokeiRules.DisplayOnChart(10, 180);
         lastInfoUpdate = TimeCurrent();
      }
   }

   //--- Monitor open positions for early exit
   if(InpUseEarlyExit)
   {
      MonitorPositionsForEarlyExit();
   }

   //--- Check for emergency close due to Fintokei rules
   if(FintokeiRules.ShouldEmergencyClose())
   {
      Print("EMERGENCY: Fintokei limit approaching - closing all positions");
      CloseAllPositions();
      return;
   }

   //--- Main trading logic runs on new bar
   if(g_isNewBar)
   {
      ProcessTradingLogic();
   }
}

//+------------------------------------------------------------------+
//| Process main trading logic                                       |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   //--- Check Fintokei rules first
   if(!FintokeiRules.IsTradingAllowed())
   {
      Print("Trading blocked by Fintokei rules: ", FintokeiRules.GetViolation().message);
      return;
   }

   //--- Check risk manager
   if(!RiskMgr.IsTradingAllowed())
   {
      Print("Trading blocked by Risk Manager");
      return;
   }

   //--- Check ML time filter
   if(InpEnableML && !MLOptimizer.IsOptimalTime())
   {
      // Optionally log this
      // Print("Non-optimal trading hour - skipping");
      return;
   }

   //--- Check correlation filter
   if(InpEnableCorrelation && !RiskMgr.IsEntryAllowed(_Symbol))
   {
      Print("Entry blocked due to correlation filter");
      return;
   }

   //--- Check if we already have a position
   if(HasOpenPosition())
   {
      return;  // Only one position at a time
   }

   //--- Get trading signal
   ENUM_SIGNAL_TYPE signal = SignalMgr.GetSignal();

   if(signal == SIGNAL_NONE)
      return;

   //--- Execute trade
   if(signal == SIGNAL_BUY)
   {
      ExecuteBuyTrade();
   }
   else if(signal == SIGNAL_SELL)
   {
      ExecuteSellTrade();
   }
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade()
{
   //--- Calculate SL/TP
   double slPrice = SignalMgr.CalculateDynamicSL(SIGNAL_BUY, InpATRMultiplier);
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

   //--- Apply ML quality multiplier to lot size
   if(InpEnableML)
   {
      double mlMultiplier = MLOptimizer.GetHourQualityMultiplier();
      lots = NormalizeLotSize(_Symbol, lots * mlMultiplier);
   }

   //--- Execute trade
   string comment = StringFormat("%s_BUY_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("BUY order executed: ", lots, " lots at ", entryPrice);
      Print("SL: ", slPrice, " | TP: ", tpPrice);
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
   double slPrice = SignalMgr.CalculateDynamicSL(SIGNAL_SELL, InpATRMultiplier);
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

   //--- Apply ML quality multiplier to lot size
   if(InpEnableML)
   {
      double mlMultiplier = MLOptimizer.GetHourQualityMultiplier();
      lots = NormalizeLotSize(_Symbol, lots * mlMultiplier);
   }

   //--- Execute trade
   string comment = StringFormat("%s_SELL_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("SELL order executed: ", lots, " lots at ", entryPrice);
      Print("SL: ", slPrice, " | TP: ", tpPrice);
      g_totalTrades++;
      g_lastTradeTime = TimeCurrent();
   }
   else
   {
      Print("SELL order failed: ", Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Monitor positions for early exit                                  |
//+------------------------------------------------------------------+
void MonitorPositionsForEarlyExit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionInfo.SelectByIndex(i))
         continue;

      if(PositionInfo.Symbol() != _Symbol)
         continue;

      if(PositionInfo.Magic() != g_magicNumber)
         continue;

      ENUM_POSITION_TYPE posType = PositionInfo.PositionType();
      ENUM_SIGNAL_TYPE signalType = (posType == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

      //--- Check if early exit is needed
      if(SignalMgr.ShouldCloseEarly(signalType))
      {
         double profit = PositionInfo.Profit();
         ulong ticket = PositionInfo.Ticket();

         Print("Early exit triggered for position ", ticket);
         Print("Current P&L: ", profit);

         if(Trade.PositionClose(ticket))
         {
            Print("Position closed successfully");

            //--- Record trade for ML and reporting
            RecordClosedTrade(ticket, profit, true);
         }
         else
         {
            Print("Failed to close position: ", Trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Record closed trade for ML and reporting                         |
//+------------------------------------------------------------------+
void RecordClosedTrade(ulong ticket, double profit, bool wasEarlyExit = false)
{
   //--- This would normally use history select
   //--- For simplicity, we record with current time
   datetime closeTime = TimeCurrent();
   datetime openTime = closeTime - PeriodSeconds(PERIOD_M5);  // Approximate

   //--- Calculate profit in pips
   double pipSize = GetPipSize(_Symbol);
   double profitPips = profit / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / pipSize);

   //--- Record in ML Optimizer
   if(InpEnableML)
   {
      MLOptimizer.AddTradeRecord(openTime, closeTime, profit, profitPips, wasEarlyExit);
   }

   //--- Record in Report Generator (using deal history would be more accurate)
   // This is a simplified version
}

//+------------------------------------------------------------------+
//| Trade event handler                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   //--- Check for closed positions
   static int lastHistoryDeals = 0;
   int totalDeals = HistoryDealsTotal();

   if(totalDeals > lastHistoryDeals)
   {
      //--- New deal detected
      HistorySelect(0, TimeCurrent());

      for(int i = lastHistoryDeals; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(magic != g_magicNumber) continue;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            //--- Position closed
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long type = HistoryDealGetInteger(ticket, DEAL_TYPE);

            double netProfit = profit + commission + swap;

            //--- Get entry deal for complete record
            ulong positionId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
            datetime openTime = time - PeriodSeconds(PERIOD_M5);  // Approximate
            double openPrice = price;  // Would need to find entry deal

            //--- Record in ML
            if(InpEnableML)
            {
               double pipSize = GetPipSize(symbol);
               double profitPips = profit / (SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE) / pipSize);
               MLOptimizer.AddTradeRecord(openTime, time, netProfit, profitPips, false);
            }

            //--- Record in Report Generator
            int posType = (type == DEAL_TYPE_BUY) ? 1 : 0;  // Closing deal is opposite
            ReportGen.AddTrade((long)ticket, openTime, time, symbol, posType,
                               volume, openPrice, price, 0, 0, profit, commission, swap, "");

            Print("Trade closed - Net Profit: ", netProfit);
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
   string prefix = "MLEMA_";
   int x = 10, y = 20;
   int yStep = 13;
   color textColor = clrWhite;

   //--- EA Info
   CreateLabel(prefix + "Title", "=== ML EMA Scalping EA ===", x, y, clrGold, 10);
   y += yStep + 5;

   //--- Symbol and time
   CreateLabel(prefix + "Symbol", "Symbol: " + _Symbol + " | TF: M5", x, y, clrWhite, 9);
   y += yStep;

   //--- Signal status
   string signalStr = "No Signal";
   color signalColor = clrGray;
   ENUM_SIGNAL_TYPE signal = SignalMgr.GetSignal();
   if(signal == SIGNAL_BUY) { signalStr = "BUY SIGNAL"; signalColor = clrLime; }
   else if(signal == SIGNAL_SELL) { signalStr = "SELL SIGNAL"; signalColor = clrRed; }
   CreateLabel(prefix + "Signal", "Signal: " + signalStr, x, y, signalColor, 9);
   y += yStep;

   //--- Trend info
   string trendStr = SignalMgr.IsSMAUpTrend() ? "UP" : (SignalMgr.IsSMADownTrend() ? "DOWN" : "FLAT");
   string emaTrendStr = SignalMgr.IsEMAUpTrend() ? "UP" : (SignalMgr.IsEMADownTrend() ? "DOWN" : "FLAT");
   CreateLabel(prefix + "Trend", StringFormat("SMA900: %s | EMA20: %s", trendStr, emaTrendStr), x, y, clrSilver, 9);
   y += yStep;

   //--- ML Status
   if(InpEnableML)
   {
      string mlStatus = MLOptimizer.IsOptimalTime() ? "OPTIMAL" : "SUB-OPTIMAL";
      color mlColor = MLOptimizer.IsOptimalTime() ? clrLime : clrYellow;
      double expectancy = MLOptimizer.GetCurrentHourExpectancy();
      CreateLabel(prefix + "ML", StringFormat("ML Hour: %s (Exp: %.2f)", mlStatus, expectancy), x, y, mlColor, 9);
      y += yStep;
   }

   //--- Risk info
   CreateLabel(prefix + "Risk", StringFormat("Risk Level: %s", EnumToString(RiskMgr.GetRiskLevel())), x, y, clrSilver, 9);
   y += yStep;

   double dd = RiskMgr.GetCurrentDrawdown();
   color ddColor = (dd > 10) ? clrRed : (dd > 5) ? clrYellow : clrLime;
   CreateLabel(prefix + "DD", StringFormat("Drawdown: %.2f%%", dd), x, y, ddColor, 9);
   y += yStep;

   //--- Correlation
   if(InpEnableCorrelation)
   {
      double corr = RiskMgr.GetCorrelation();
      color corrColor = (MathAbs(corr) > InpMaxCorrelation) ? clrRed : clrSilver;
      CreateLabel(prefix + "Corr", StringFormat("Correlation: %.3f", corr), x, y, corrColor, 9);
      y += yStep;
   }

   //--- Trade stats
   CreateLabel(prefix + "Trades", StringFormat("Trades: %d | Win Rate: %.1f%%",
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
   string prefix = "MLEMA_";
   ObjectsDeleteAll(0, prefix);
}
//+------------------------------------------------------------------+
