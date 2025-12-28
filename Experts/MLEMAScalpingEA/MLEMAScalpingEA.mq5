//+------------------------------------------------------------------+
//|                                              MLEMAScalpingEA.mq5 |
//|         Granville's Law + Daily Pivot Strategy EA v6.1           |
//|                                                                  |
//|  Strategy:                                                       |
//|  - H1 75 EMA determines trend direction (with slope confirm)     |
//|  - M5 20 EMA for Granville Buy3/Sell3 bounce entry              |
//|  - Daily Pivot levels (R1/R2, S1/S2) for Take Profit            |
//|                                                                  |
//|  Entry Rules (Granville's Law):                                  |
//|  - BUY3: Uptrend, price approaches EMA but does NOT cross below  |
//|          Bullish candle confirms bounce                          |
//|  - SELL3: Downtrend, price approaches EMA but does NOT cross up  |
//|           Bearish candle confirms bounce                         |
//|                                                                  |
//|  TP Logic:                                                       |
//|  - BUY: Target R1 or R2 (whichever gives 1.5+ RR)               |
//|  - SELL: Target S1 or S2 (whichever gives 1.5+ RR)              |
//|                                                                  |
//|  Fintokei Compliance:                                            |
//|  - 5% daily loss limit, 10% total loss limit                     |
//|  - Emergency close at 9% DD, block trades at 8% DD               |
//+------------------------------------------------------------------+
#property copyright "Granville Pivot EA v6.1"
#property link      ""
#property version   "6.10"
#property description "Granville's Law (Buy3/Sell3) + Daily Pivot TP Strategy"
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
input string   InpEAName           = "Granville_Pivot";      // EA Name (for magic number)
input bool     InpEnableTrading    = true;                   // Enable Trading
input bool     InpShowChartInfo    = true;                   // Show Chart Information

//--- Broker Time Settings
input group "=== Broker Time Settings ==="
input int      InpGMTOffset        = 2;                      // GMT Offset (Titan FX: Winter=2, Summer=3)

//--- Trend Settings (H1)
input group "=== Trend Filter (H1) ==="
input ENUM_TIMEFRAMES InpTrendTF   = PERIOD_H1;              // Trend Timeframe
input int      InpTrendEmaPeriod   = 75;                     // Trend EMA Period (faster than 200)

//--- Entry Settings (M5) - Granville Bounce
input group "=== Granville Entry (M5) ==="
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_M5;              // Entry Timeframe
input int      InpEntryEmaPeriod   = 20;                     // Entry EMA Period
input double   InpBounceZone       = 20.0;                   // Bounce Zone (Pips from EMA) v6.1: relaxed

//--- RSI Filter (v6.1: relaxed to 30-70)
input group "=== RSI Filter ==="
input double   InpRSIOversold      = 30.0;                   // RSI Oversold Level (v6.1: relaxed)
input double   InpRSIOverbought    = 70.0;                   // RSI Overbought Level (v6.1: relaxed)

//--- Trading Hours (GMT)
input group "=== Trading Hours (GMT) ==="
input int      InpTradingStartGMT  = 7;                      // Trading Start (GMT) - London Open
input int      InpTradingEndGMT    = 20;                     // Trading End (GMT) - NY Close
input int      InpMaxTradesPerDay  = 3;                      // Max Trades Per Day

//--- Risk Management
input group "=== Risk Management ==="
input double   InpRiskPercent      = 1.5;                    // Risk Per Trade (%)
input double   InpRRRatio          = 2.0;                    // Risk:Reward Ratio (fallback)
input double   InpMaxDailyLoss     = 5.0;                    // Max Daily Loss (%) - Fintokei
input double   InpMaxTotalLoss     = 10.0;                   // Max Total Loss (%) - Fintokei
input double   InpMaxPositionRisk  = 3.0;                    // Max Position Risk (%) - Fintokei
input double   InpDrawdownThreshold = 5.0;                   // DD Threshold for Lot Reduction (%)

//--- Loss Cooldown Settings
input group "=== Loss Cooldown ==="
input bool     InpUseCooldown      = true;                   // Use Loss Cooldown
input int      InpMaxConsecLosses  = 3;                      // Max Consecutive Losses Before Cooldown
input int      InpCooldownBars     = 12;                     // Cooldown Period (Bars)

//--- Advanced Settings
input group "=== Advanced Settings ==="
input int      InpSlippage         = 30;                     // Max Slippage (Points)
input int      InpATRPeriod        = 14;                     // ATR Period
input double   InpInitialBalance   = 0;                      // Initial Balance (0=Auto)

//+------------------------------------------------------------------+
//| Global Objects                                                    |
//+------------------------------------------------------------------+
CSignalManager    SignalMgr;           // Signal generation
CMLOptimizer      MLOptimizer;         // ML time optimization (optional)
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
   Print("Granville Pivot EA v6.0 Initializing...");
   Print("Strategy: Granville Buy3/Sell3 + Daily Pivot TP");
   Print("===========================================");

   //--- Generate magic number from EA name
   g_magicNumber = GenerateMagicNumber(InpEAName);
   Print("Magic Number: ", g_magicNumber);

   //--- Initialize trading object
   Trade.SetExpertMagicNumber(g_magicNumber);
   Trade.SetDeviationInPoints(InpSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   //--- Initialize Signal Manager with Granville parameters
   if(!SignalMgr.Init(_Symbol, InpEntryTF, InpTrendTF, InpTrendEmaPeriod, InpEntryEmaPeriod, InpATRPeriod))
   {
      Print("ERROR: Failed to initialize Signal Manager");
      return INIT_FAILED;
   }

   // Configure Signal Manager
   SignalMgr.SetGMTOffset(InpGMTOffset);
   SignalMgr.SetTradingHours(InpTradingStartGMT, InpTradingEndGMT);
   SignalMgr.SetMaxTradesPerDay(InpMaxTradesPerDay);
   SignalMgr.SetBounceZone(InpBounceZone);
   SignalMgr.SetRSILevels(InpRSIOversold, InpRSIOverbought);

   Print("Signal Manager initialized for Granville's Law");
   Print("Trend TF: ", EnumToString(InpTrendTF), " EMA(", InpTrendEmaPeriod, ")");
   Print("Entry TF: ", EnumToString(InpEntryTF), " EMA(", InpEntryEmaPeriod, ")");
   Print("Bounce Zone: ", InpBounceZone, " pips | RSI: ", InpRSIOversold, "-", InpRSIOverbought);
   Print("Trading Hours (GMT): ", InpTradingStartGMT, ":00 - ", InpTradingEndGMT, ":00");
   Print("Max Trades/Day: ", InpMaxTradesPerDay);

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
   Print("Fintokei Rules initialized (DD protection active)");

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
   Print("Strategy: Granville Buy3/Sell3 + Pivot TP");
   Print("Risk Per Trade: ", InpRiskPercent, "%");
   Print("Risk:Reward Fallback: 1:", InpRRRatio);
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
         FintokeiRules.DisplayOnChart(10, 320);
         lastInfoUpdate = TimeCurrent();
      }
   }

   //--- CRITICAL: Check for emergency close due to Fintokei rules
   //--- This runs on EVERY tick for maximum protection
   double currentTotalLoss = FintokeiRules.GetTotalLossPercent();
   double currentDailyLoss = FintokeiRules.GetDailyLossPercent();

   // Hard stop at the limit - close everything immediately
   if(currentTotalLoss >= InpMaxTotalLoss || currentDailyLoss >= InpMaxDailyLoss)
   {
      Print("!!! FINTOKEI LIMIT BREACHED !!! Total: ", currentTotalLoss, "% Daily: ", currentDailyLoss, "%");
      Print("EMERGENCY CLOSE: Closing ALL positions immediately!");
      CloseAllPositions();
      return;
   }

   // Emergency close at 90% of limit
   if(FintokeiRules.ShouldEmergencyClose())
   {
      Print("EMERGENCY: Approaching Fintokei limit (Total: ", currentTotalLoss, "%, Daily: ", currentDailyLoss, "%)");
      Print("Closing all positions to protect account!");
      CloseAllPositions();
      return;
   }

   //--- Block new trades at 80% of limit (8% DD for 10% limit)
   if(currentTotalLoss >= InpMaxTotalLoss * 0.80 || currentDailyLoss >= InpMaxDailyLoss * 0.80)
   {
      // Don't print every tick, just when we have positions or new bars
      if(HasOpenPosition() || g_isNewBar)
      {
         Print("FINTOKEI WARNING: Approaching limit (Total: ", currentTotalLoss, "%) - new trades blocked");
      }
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
   g_cooldownEndTime = TimeCurrent() + (InpCooldownBars * PeriodSeconds(InpEntryTF));
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

   //--- Check if we already have a position
   if(HasOpenPosition())
   {
      return;
   }

   //--- Get trading signal from Granville logic
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
   double slPrice = SignalMgr.CalculateSL(SIGNAL_BUY);
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

   //--- Determine TP target type
   string tpType = "RR";
   double pivotR1 = SignalMgr.GetPivotR1();
   double pivotR2 = SignalMgr.GetPivotR2();
   if(MathAbs(tpPrice - pivotR1) < pipSize * 3)
      tpType = "R1";
   else if(MathAbs(tpPrice - pivotR2) < pipSize * 3)
      tpType = "R2";

   //--- Execute trade
   string comment = StringFormat("%s_BUY3_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("=== GRANVILLE BUY 3 ORDER EXECUTED ===");
      Print("Lots: ", lots, " | Entry: ", entryPrice);
      Print("SL: ", slPrice, " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", tpPrice, " (Target: ", tpType, ")");
      Print("Trend: ", SignalMgr.GetTrendString());
      Print("H1 EMA(", InpTrendEmaPeriod, "): ", SignalMgr.GetTrendEMA());
      Print("M5 EMA(", InpEntryEmaPeriod, "): ", SignalMgr.GetEntryEMA());
      Print("Pivot PP: ", SignalMgr.GetPivotPP(), " | R1: ", pivotR1, " | R2: ", pivotR2);
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
   double slPrice = SignalMgr.CalculateSL(SIGNAL_SELL);
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

   //--- Determine TP target type
   string tpType = "RR";
   double pivotS1 = SignalMgr.GetPivotS1();
   double pivotS2 = SignalMgr.GetPivotS2();
   if(MathAbs(tpPrice - pivotS1) < pipSize * 3)
      tpType = "S1";
   else if(MathAbs(tpPrice - pivotS2) < pipSize * 3)
      tpType = "S2";

   //--- Execute trade
   string comment = StringFormat("%s_SELL3_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("=== GRANVILLE SELL 3 ORDER EXECUTED ===");
      Print("Lots: ", lots, " | Entry: ", entryPrice);
      Print("SL: ", slPrice, " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", tpPrice, " (Target: ", tpType, ")");
      Print("Trend: ", SignalMgr.GetTrendString());
      Print("H1 EMA(", InpTrendEmaPeriod, "): ", SignalMgr.GetTrendEMA());
      Print("M5 EMA(", InpEntryEmaPeriod, "): ", SignalMgr.GetEntryEMA());
      Print("Pivot PP: ", SignalMgr.GetPivotPP(), " | S1: ", pivotS1, " | S2: ", pivotS2);
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

            //--- Record in Report Generator
            int posType = (type == DEAL_TYPE_BUY) ? 1 : 0;
            datetime openTime = time - PeriodSeconds(InpEntryTF);
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
   datetime currentBarTime = iTime(_Symbol, InpEntryTF, 0);

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
   string prefix = "GRVL_";
   int x = 10, y = 20;
   int yStep = 15;

   //--- EA Info
   CreateLabel(prefix + "Title", "=== Granville Pivot EA v6.1 ===", x, y, clrGold, 10);
   y += yStep + 5;

   //--- Symbol and time
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   CreateLabel(prefix + "Symbol", StringFormat("Symbol: %s | Server: %02d:%02d (GMT+%d)", _Symbol, dt.hour, dt.min, InpGMTOffset), x, y, clrWhite, 9);
   y += yStep;

   //--- Update indicators for display
   SignalMgr.UpdateIndicators();

   //--- Trend info
   string trendStr = SignalMgr.GetTrendString();
   color trendColor = clrYellow;
   ENUM_TREND_STATE trend = SignalMgr.GetCurrentTrend();
   if(trend == TREND_BULLISH) trendColor = clrLime;
   else if(trend == TREND_BEARISH) trendColor = clrRed;

   CreateLabel(prefix + "Trend", StringFormat("H1 Trend: %s", trendStr), x, y, trendColor, 9);
   y += yStep;

   //--- EMA values
   CreateLabel(prefix + "TrendEMA", StringFormat("H1 EMA(%d): %.5f", InpTrendEmaPeriod, SignalMgr.GetTrendEMA()), x, y, clrSilver, 9);
   y += yStep;

   CreateLabel(prefix + "EntryEMA", StringFormat("M5 EMA(%d): %.5f", InpEntryEmaPeriod, SignalMgr.GetEntryEMA()), x, y, clrSilver, 9);
   y += yStep;

   //--- Current price vs EMAs
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double trendEma = SignalMgr.GetTrendEMA();
   double entryEma = SignalMgr.GetEntryEMA();

   string posStr = "NEUTRAL";
   color posColor = clrYellow;
   if(price > trendEma && price > entryEma) { posStr = "ABOVE BOTH EMAs"; posColor = clrLime; }
   else if(price < trendEma && price < entryEma) { posStr = "BELOW BOTH EMAs"; posColor = clrRed; }
   else if(price > trendEma) { posStr = "Above H1, Near M5 EMA"; posColor = clrAqua; }
   else if(price < trendEma) { posStr = "Below H1, Near M5 EMA"; posColor = clrOrange; }

   CreateLabel(prefix + "Position", "Price Position: " + posStr, x, y, posColor, 9);
   y += yStep;

   //--- Daily Pivot Levels
   y += 5;
   CreateLabel(prefix + "PivotTitle", "=== Daily Pivot Levels ===", x, y, clrDodgerBlue, 9);
   y += yStep;

   double pp = SignalMgr.GetPivotPP();
   double r1 = SignalMgr.GetPivotR1();
   double r2 = SignalMgr.GetPivotR2();
   double s1 = SignalMgr.GetPivotS1();
   double s2 = SignalMgr.GetPivotS2();

   CreateLabel(prefix + "PivotPP", StringFormat("PP: %.5f", pp), x, y, clrWhite, 9);
   y += yStep;

   CreateLabel(prefix + "PivotR", StringFormat("R1: %.5f | R2: %.5f", r1, r2), x, y, clrLime, 9);
   y += yStep;

   CreateLabel(prefix + "PivotS", StringFormat("S1: %.5f | S2: %.5f", s1, s2), x, y, clrRed, 9);
   y += yStep;

   //--- Indicators
   y += 5;
   CreateLabel(prefix + "RSI", StringFormat("RSI(14): %.1f", SignalMgr.GetRSI()), x, y, clrSilver, 9);
   y += yStep;

   //--- Trading window
   bool isTradingTime = SignalMgr.IsTradingTime();
   string windowStr = isTradingTime ? "OPEN" : "CLOSED";
   color windowColor = isTradingTime ? clrLime : clrGray;
   CreateLabel(prefix + "Window", StringFormat("Trading Window: %s (GMT %02d:00-%02d:00)", windowStr,
               InpTradingStartGMT, InpTradingEndGMT), x, y, windowColor, 9);
   y += yStep;

   //--- Trades today
   CreateLabel(prefix + "Trades", StringFormat("Trades Today: %d / %d", SignalMgr.GetTradesToday(), InpMaxTradesPerDay), x, y, clrSilver, 9);
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
   CreateLabel(prefix + "Stats", StringFormat("Total Trades: %d | Win Rate: %.1f%%",
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
   string prefix = "GRVL_";
   ObjectsDeleteAll(0, prefix);
}
//+------------------------------------------------------------------+
