//+------------------------------------------------------------------+
//|                                              MLEMAScalpingEA.mq5 |
//|         Asian Box Breakout + Improved Filters EA v7.0            |
//|                                                                  |
//|  Strategy:                                                       |
//|  - Asian Session: Form range during 23:00-06:00 GMT              |
//|  - Entry Window: 07:00-10:00 GMT (London Open)                   |
//|  - Breakout with Retest Confirmation                             |
//|                                                                  |
//|  Filters (False Breakout Prevention):                            |
//|  - ATR Filter: ATR(14) > SMA(ATR, 20)                           |
//|  - Retest Logic: Wait for pullback to broken level               |
//|  - H1 EMA Trend Alignment                                        |
//|  - Range Size: 30-80 pips (skip too small or too large)          |
//|                                                                  |
//|  Fintokei Compliance:                                            |
//|  - 5% daily loss limit, 10% total loss limit                     |
//|  - Emergency close at 9% DD, block trades at 8% DD               |
//+------------------------------------------------------------------+
#property copyright "Asian Box Breakout EA v7.0"
#property link      ""
#property version   "7.00"
#property description "Asian Box Breakout with ATR Filter + Retest Confirmation"
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
input string   InpEAName           = "AsianBreakout";        // EA Name (for magic number)
input bool     InpEnableTrading    = true;                   // Enable Trading
input bool     InpShowChartInfo    = true;                   // Show Chart Information

//--- Broker Time Settings
input group "=== Broker Time Settings ==="
input int      InpGMTOffset        = 2;                      // GMT Offset (Titan FX: Winter=2, Summer=3)

//--- Trend Filter (H1)
input group "=== Trend Filter (H1) ==="
input ENUM_TIMEFRAMES InpTrendTF   = PERIOD_H1;              // Trend Timeframe
input int      InpTrendEmaPeriod   = 50;                     // Trend EMA Period

//--- Entry Settings (M5)
input group "=== Entry Settings (M5) ==="
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_M5;              // Entry Timeframe
input double   InpBreakoutBuffer   = 5.0;                    // Breakout Buffer (Pips)
input double   InpRetestBuffer     = 10.0;                   // Retest Zone (Pips)

//--- Asian Range Settings
input group "=== Asian Range Settings ==="
input double   InpMinRangePips     = 30.0;                   // Minimum Range (Pips)
input double   InpMaxRangePips     = 80.0;                   // Maximum Range (Pips)

//--- Trading Hours (GMT)
input group "=== Trading Hours (GMT) ==="
input int      InpEntryStartGMT    = 7;                      // Entry Start (GMT) - London Open
input int      InpEntryEndGMT      = 10;                     // Entry End (GMT)
input int      InpMaxTradesPerDay  = 2;                      // Max Trades Per Day

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
CSignalManager    SignalMgr;
CMLOptimizer      MLOptimizer;
CRiskManager      RiskMgr;
CReportGenerator  ReportGen;
CFintokeiRules    FintokeiRules;
CTrade            Trade;
CPositionInfo     PositionInfo;

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int               g_magicNumber;
datetime          g_lastBarTime;
bool              g_isNewBar;
int               g_totalTrades;
datetime          g_lastTradeTime;

int               g_consecutiveLosses;
datetime          g_cooldownEndTime;
bool              g_inCooldown;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("===========================================");
   Print("Asian Box Breakout EA v7.0 Initializing...");
   Print("Strategy: Asian Range + London Breakout");
   Print("===========================================");

   g_magicNumber = GenerateMagicNumber(InpEAName);
   Print("Magic Number: ", g_magicNumber);

   Trade.SetExpertMagicNumber(g_magicNumber);
   Trade.SetDeviationInPoints(InpSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   if(!SignalMgr.Init(_Symbol, InpEntryTF, InpTrendTF, InpTrendEmaPeriod, InpTrendEmaPeriod, InpATRPeriod))
   {
      Print("ERROR: Failed to initialize Signal Manager");
      return INIT_FAILED;
   }

   SignalMgr.SetGMTOffset(InpGMTOffset);
   SignalMgr.SetTradingHours(InpEntryStartGMT, InpEntryEndGMT);
   SignalMgr.SetMaxTradesPerDay(InpMaxTradesPerDay);
   SignalMgr.SetBounceZone(InpBreakoutBuffer);
   SignalMgr.SetPullbackTolerance(InpRetestBuffer);
   SignalMgr.SetMinRangePips(InpMinRangePips);
   SignalMgr.SetMaxRangePips(InpMaxRangePips);

   Print("Signal Manager initialized for Asian Breakout");
   Print("Asian Session: 23:00 - 06:00 GMT");
   Print("Entry Window: ", InpEntryStartGMT, ":00 - ", InpEntryEndGMT, ":00 GMT");
   Print("Range Filter: ", InpMinRangePips, " - ", InpMaxRangePips, " pips");
   Print("Trend EMA: ", InpTrendEmaPeriod, " on ", EnumToString(InpTrendTF));

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

   if(!FintokeiRules.Init(initialBal))
   {
      Print("ERROR: Failed to initialize Fintokei Rules");
      return INIT_FAILED;
   }
   FintokeiRules.SetDailyLossLimit(InpMaxDailyLoss);
   FintokeiRules.SetTotalLossLimit(InpMaxTotalLoss);
   FintokeiRules.SetPositionRiskLimit(InpMaxPositionRisk);

   if(!ReportGen.Init(_Symbol, InpEAName))
   {
      Print("WARNING: Report Generator initialization failed");
   }

   g_lastBarTime = 0;
   g_isNewBar = false;
   g_totalTrades = 0;
   g_lastTradeTime = 0;
   g_consecutiveLosses = 0;
   g_cooldownEndTime = 0;
   g_inCooldown = false;

   if(InpShowChartInfo)
   {
      DisplayChartInfo();
   }

   Print("===========================================");
   Print("EA Initialization Complete");
   Print("===========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Deinitializing... Reason: ", reason);
   ReportGen.SaveAllReports();
   ReportGen.PrintStatistics();
   RiskMgr.PrintStatus();
   FintokeiRules.RemoveChartDisplay();
   RemoveChartInfo();
   SignalMgr.Deinit();
   Print("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!InpEnableTrading) return;

   g_isNewBar = IsNewBar();

   if(InpShowChartInfo)
   {
      static datetime lastInfoUpdate = 0;
      if(TimeCurrent() - lastInfoUpdate >= 1)
      {
         DisplayChartInfo();
         FintokeiRules.DisplayOnChart(10, 350);
         lastInfoUpdate = TimeCurrent();
      }
   }

   // Fintokei protection
   double currentTotalLoss = FintokeiRules.GetTotalLossPercent();
   double currentDailyLoss = FintokeiRules.GetDailyLossPercent();

   if(currentTotalLoss >= InpMaxTotalLoss || currentDailyLoss >= InpMaxDailyLoss)
   {
      Print("!!! FINTOKEI LIMIT BREACHED !!!");
      CloseAllPositions();
      return;
   }

   if(FintokeiRules.ShouldEmergencyClose())
   {
      Print("EMERGENCY: Approaching Fintokei limit");
      CloseAllPositions();
      return;
   }

   if(currentTotalLoss >= InpMaxTotalLoss * 0.80 || currentDailyLoss >= InpMaxDailyLoss * 0.80)
   {
      return;
   }

   if(g_isNewBar)
   {
      ProcessTradingLogic();
   }
}

//+------------------------------------------------------------------+
//| Check cooldown                                                    |
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
         Print("Cooldown ended");
         return false;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Start cooldown                                                    |
//+------------------------------------------------------------------+
void StartCooldown()
{
   g_inCooldown = true;
   g_cooldownEndTime = TimeCurrent() + (InpCooldownBars * PeriodSeconds(InpEntryTF));
   Print("COOLDOWN STARTED: ", g_consecutiveLosses, " losses");
}

//+------------------------------------------------------------------+
//| Process trading logic                                             |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   if(IsInCooldown()) return;
   if(!FintokeiRules.IsTradingAllowed()) return;
   if(!RiskMgr.IsTradingAllowed()) return;
   if(HasOpenPosition()) return;

   ENUM_SIGNAL_TYPE signal = SignalMgr.GetSignal();

   if(signal == SIGNAL_NONE) return;

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
   double slPrice = SignalMgr.CalculateSL(SIGNAL_BUY);
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tpPrice = SignalMgr.CalculateTP(entryPrice, slPrice, SIGNAL_BUY, InpRRRatio);

   double pipSize = GetPipSize(_Symbol);
   double slPips = MathAbs(entryPrice - slPrice) / pipSize;

   double lots = FintokeiRules.CalculateSafeLotSize(_Symbol, slPips, InpRiskPercent);

   if(lots <= 0)
   {
      Print("Lot size 0 - trade cancelled");
      return;
   }

   double riskAmount = CalculateRiskAmount(lots, slPips);
   if(!FintokeiRules.ValidateTradeRisk(riskAmount))
   {
      Print("Trade risk validation failed");
      return;
   }

   string comment = StringFormat("%s_BUY_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("=== ASIAN BREAKOUT BUY ===");
      Print("Lots: ", lots, " | Entry: ", entryPrice);
      Print("SL: ", slPrice, " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", tpPrice);
      Print("Asian High: ", SignalMgr.GetAsianHigh());
      g_totalTrades++;
      g_lastTradeTime = TimeCurrent();
   }
   else
   {
      Print("BUY failed: ", Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute sell trade                                                |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
{
   double slPrice = SignalMgr.CalculateSL(SIGNAL_SELL);
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpPrice = SignalMgr.CalculateTP(entryPrice, slPrice, SIGNAL_SELL, InpRRRatio);

   double pipSize = GetPipSize(_Symbol);
   double slPips = MathAbs(slPrice - entryPrice) / pipSize;

   double lots = FintokeiRules.CalculateSafeLotSize(_Symbol, slPips, InpRiskPercent);

   if(lots <= 0)
   {
      Print("Lot size 0 - trade cancelled");
      return;
   }

   double riskAmount = CalculateRiskAmount(lots, slPips);
   if(!FintokeiRules.ValidateTradeRisk(riskAmount))
   {
      Print("Trade risk validation failed");
      return;
   }

   string comment = StringFormat("%s_SELL_%d", InpEAName, g_totalTrades + 1);

   if(Trade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice, comment))
   {
      Print("=== ASIAN BREAKOUT SELL ===");
      Print("Lots: ", lots, " | Entry: ", entryPrice);
      Print("SL: ", slPrice, " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", tpPrice);
      Print("Asian Low: ", SignalMgr.GetAsianLow());
      g_totalTrades++;
      g_lastTradeTime = TimeCurrent();
   }
   else
   {
      Print("SELL failed: ", Trade.ResultRetcodeDescription());
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
            double netProfit = profit + commission + swap;

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

            Print("Trade closed - Net: ", netProfit, " | Losses: ", g_consecutiveLosses);
         }
      }
      lastHistoryDeals = totalDeals;
   }
}

//+------------------------------------------------------------------+
//| Check open position                                               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionInfo.SelectByIndex(i)) continue;
      if(PositionInfo.Symbol() != _Symbol) continue;
      if(PositionInfo.Magic() != g_magicNumber) continue;
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
      if(!PositionInfo.SelectByIndex(i)) continue;
      if(PositionInfo.Symbol() != _Symbol) continue;
      if(PositionInfo.Magic() != g_magicNumber) continue;
      Trade.PositionClose(PositionInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Check new bar                                                     |
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
//| Generate magic number                                             |
//+------------------------------------------------------------------+
int GenerateMagicNumber(string name)
{
   int hash = 0;
   for(int i = 0; i < StringLen(name); i++)
      hash = hash * 31 + StringGetCharacter(name, i);
   return MathAbs(hash) % 1000000 + 100000;
}

//+------------------------------------------------------------------+
//| Get pip size                                                      |
//+------------------------------------------------------------------+
double GetPipSize(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

//+------------------------------------------------------------------+
//| Calculate risk amount                                             |
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
//| Display chart info                                                |
//+------------------------------------------------------------------+
void DisplayChartInfo()
{
   string prefix = "ABB_";
   int x = 10, y = 20;
   int yStep = 15;

   CreateLabel(prefix + "Title", "=== Asian Box Breakout v7.0 ===", x, y, clrGold, 10);
   y += yStep + 5;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int gmtHour = dt.hour - InpGMTOffset;
   if(gmtHour < 0) gmtHour += 24;

   CreateLabel(prefix + "Time", StringFormat("Server: %02d:%02d | GMT: %02d:%02d", dt.hour, dt.min, gmtHour, dt.min), x, y, clrWhite, 9);
   y += yStep;

   // Update indicators
   SignalMgr.UpdateIndicators();

   // Session status
   bool isAsian = (gmtHour >= 23 || gmtHour < 6);
   bool isEntry = (gmtHour >= InpEntryStartGMT && gmtHour < InpEntryEndGMT);
   string sessionStr = isAsian ? "ASIAN (Forming Range)" : (isEntry ? "ENTRY WINDOW" : "WAITING");
   color sessionColor = isAsian ? clrYellow : (isEntry ? clrLime : clrGray);
   CreateLabel(prefix + "Session", "Session: " + sessionStr, x, y, sessionColor, 9);
   y += yStep;

   // Asian range
   y += 5;
   CreateLabel(prefix + "RangeTitle", "=== Asian Range ===", x, y, clrDodgerBlue, 9);
   y += yStep;

   double asianHigh = SignalMgr.GetAsianHigh();
   double asianLow = SignalMgr.GetAsianLow();
   bool rangeValid = SignalMgr.IsAsianRangeValid();

   if(asianHigh > 0 && asianLow < DBL_MAX)
   {
      double pipSize = GetPipSize(_Symbol);
      double rangePips = (asianHigh - asianLow) / pipSize;

      color rangeColor = rangeValid ? clrLime : clrOrange;
      CreateLabel(prefix + "RangeHigh", StringFormat("High: %.5f", asianHigh), x, y, rangeColor, 9);
      y += yStep;
      CreateLabel(prefix + "RangeLow", StringFormat("Low: %.5f", asianLow), x, y, rangeColor, 9);
      y += yStep;
      CreateLabel(prefix + "RangeSize", StringFormat("Size: %.1f pips %s", rangePips, rangeValid ? "(VALID)" : "(INVALID)"), x, y, rangeColor, 9);
      y += yStep;
   }
   else
   {
      CreateLabel(prefix + "RangeHigh", "High: ---", x, y, clrGray, 9);
      y += yStep;
      CreateLabel(prefix + "RangeLow", "Low: ---", x, y, clrGray, 9);
      y += yStep;
      CreateLabel(prefix + "RangeSize", "Size: ---", x, y, clrGray, 9);
      y += yStep;
   }

   // Breakout state
   string breakoutStr = SignalMgr.GetBreakoutStateString();
   color breakoutColor = clrGray;
   ENUM_BREAKOUT_STATE bState = SignalMgr.GetBreakoutState();
   if(bState == BREAKOUT_CONFIRMED_UP || bState == BREAKOUT_CONFIRMED_DOWN) breakoutColor = clrLime;
   else if(bState == BREAKOUT_PENDING_UP || bState == BREAKOUT_PENDING_DOWN) breakoutColor = clrYellow;

   CreateLabel(prefix + "Breakout", "Breakout: " + breakoutStr, x, y, breakoutColor, 9);
   y += yStep;

   // Trend
   string trendStr = SignalMgr.GetTrendString();
   color trendColor = clrYellow;
   if(SignalMgr.GetCurrentTrend() == TREND_BULLISH) trendColor = clrLime;
   else if(SignalMgr.GetCurrentTrend() == TREND_BEARISH) trendColor = clrRed;

   CreateLabel(prefix + "Trend", StringFormat("H1 Trend: %s (EMA %.5f)", trendStr, SignalMgr.GetTrendEMA()), x, y, trendColor, 9);
   y += yStep;

   // ATR filter
   double atr = SignalMgr.GetATR();
   CreateLabel(prefix + "ATR", StringFormat("ATR(14): %.1f pips", atr * 100000), x, y, clrSilver, 9);
   y += yStep;

   // Pivot levels
   y += 5;
   CreateLabel(prefix + "PivotTitle", "=== Daily Pivot ===", x, y, clrDodgerBlue, 9);
   y += yStep;

   CreateLabel(prefix + "PivotPP", StringFormat("PP: %.5f", SignalMgr.GetPivotPP()), x, y, clrWhite, 9);
   y += yStep;
   CreateLabel(prefix + "PivotR1", StringFormat("R1: %.5f | S1: %.5f", SignalMgr.GetPivotR1(), SignalMgr.GetPivotS1()), x, y, clrSilver, 9);
   y += yStep;

   // Trade info
   y += 5;
   CreateLabel(prefix + "Trades", StringFormat("Trades Today: %d / %d", SignalMgr.GetTradesToday(), InpMaxTradesPerDay), x, y, clrSilver, 9);
   y += yStep;

   // Cooldown
   if(InpUseCooldown)
   {
      string cdStr = g_inCooldown ? StringFormat("COOLDOWN (%s)", TimeToString(g_cooldownEndTime, TIME_MINUTES)) :
                                    StringFormat("Active (Losses: %d/%d)", g_consecutiveLosses, InpMaxConsecLosses);
      color cdColor = g_inCooldown ? clrOrange : clrLime;
      CreateLabel(prefix + "Cooldown", cdStr, x, y, cdColor, 9);
      y += yStep;
   }

   // DD
   double dd = RiskMgr.GetCurrentDrawdown();
   color ddColor = (dd > 7) ? clrRed : (dd > 4) ? clrYellow : clrLime;
   CreateLabel(prefix + "DD", StringFormat("Drawdown: %.2f%%", dd), x, y, ddColor, 9);
}

//+------------------------------------------------------------------+
//| Create label                                                      |
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
//| Remove chart info                                                 |
//+------------------------------------------------------------------+
void RemoveChartInfo()
{
   ObjectsDeleteAll(0, "ABB_");
}
//+------------------------------------------------------------------+
