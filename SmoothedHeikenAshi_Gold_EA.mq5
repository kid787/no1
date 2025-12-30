//+------------------------------------------------------------------+
//|                                   SmoothedHeikenAshi_Gold_EA.mq5 |
//|                                  Smoothed Heiken Ashi Strategy EA |
//|                                       For XAUUSD (Gold) Trading   |
//|                                    Fintokei Challenge Compliant   |
//|                              v3.30 - Momentum Entry Edition       |
//|                                  H1 Entry with Simpler Logic      |
//+------------------------------------------------------------------+
#property copyright "Smoothed Heiken Ashi Gold EA v3.30 - Momentum Edition"
#property link      ""
#property version   "3.30"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== v3.30 Momentum Entry Strategy ==="
input ENUM_TIMEFRAMES    InpEntryTimeframe     = PERIOD_H1;         // Entry Timeframe (H1 for less noise)
input ENUM_TIMEFRAMES    InpTrendTF            = PERIOD_H4;         // Trend Timeframe (H4)
input int                InpTrendConfirmBars   = 2;                 // Trend Confirm Bars
input int                InpSHAConfirmBars     = 2;                 // SHA Confirm Bars for Entry

input group "=== Momentum Confirmation ==="
input bool               InpUseMomentum        = true;              // Use Momentum Filter
input int                InpEMAPeriod          = 20;                // EMA Period for Momentum
input double             InpMinMomentumPips    = 50.0;              // Min Distance from EMA (Pips)

input group "=== Fintokei Risk Management ==="
input double             InpInitialCapital     = 2000000.0;         // Initial Capital (JPY)
input double             InpDailyLossLimit     = 5.0;               // Daily Loss Limit (%)
input double             InpOverallLossLimit   = 10.0;              // Overall Loss Limit (%)
input double             InpMaxRiskPerTrade    = 2.0;               // Max Risk Per Trade (%)
input double             InpSafetyBuffer       = 0.5;               // Safety Buffer (%)
input bool               InpAutoCloseOnRisk    = true;              // Auto-Close Near Limit
input int                InpServerUTCOffset    = 0;                 // Server UTC Offset

input group "=== Dynamic Lot Reduction ==="
input bool               InpUseDynamicLot      = true;              // Use Dynamic Lot Reduction
input double             InpLotReductionThreshold = 5.0;            // DD% for Lot Reduction
input double             InpLotReductionPercent = 50.0;             // Lot Reduction %
input double             InpRecoveryThreshold  = 2.0;               // DD% to Resume Normal

input group "=== Partial Take Profit (NEW) ==="
input bool               InpUsePartialTP       = true;              // Use Partial Take Profit
input double             InpPartialTPPercent   = 50.0;              // Close % at First TP
input double             InpPartialTPRatio     = 1.0;               // First TP R:R Ratio

input group "=== Trailing Stop & Break-Even ==="
input bool               InpUseTrailingStop    = true;              // Use Trailing Stop
input double             InpTrailingStartPips  = 100.0;             // Start Trailing (Pips)
input double             InpTrailingStepPips   = 40.0;              // Trailing Step (Pips)
input bool               InpUseBreakEven       = true;              // Use Break-Even
input double             InpBreakEvenPips      = 60.0;              // BE After Pips
input double             InpBreakEvenBuffer    = 5.0;               // BE Buffer

input group "=== Time-Based Exit (NEW) ==="
input bool               InpUseTimeExit        = true;              // Exit Stale Trades
input int                InpMaxBarsInTrade     = 48;                // Max Bars Before Exit (H1=48h)

input group "=== ATR Settings ==="
input int                InpATRPeriod          = 14;                // ATR Period
input double             InpATRMultiplierSL    = 1.0;               // ATR Multiplier SL
input double             InpATRMultiplierTP    = 1.5;               // ATR Multiplier TP (Lower for higher win%)
input double             InpMinATRPips         = 50.0;              // Min ATR (Pips)
input double             InpMaxATRPips         = 250.0;             // Max ATR (Pips)

input group "=== ADX Filter ==="
input bool               InpUseADXFilter       = true;              // Use ADX Filter
input int                InpADXPeriod          = 14;                // ADX Period
input double             InpMinADX             = 20.0;              // Min ADX (Lowered for more trades)
input double             InpMaxADX             = 50.0;              // Max ADX

input group "=== Short Trade Settings ==="
input bool               InpEnableShort        = true;              // Enable Short Trades
input double             InpMinADXShort        = 22.0;              // Min ADX for Short

input group "=== Money Management ==="
input double             InpRiskPercent        = 1.5;               // Risk Percent
input double             InpFixedLot           = 0.1;               // Fixed Lot (if Risk%=0)
input double             InpMinSLPips          = 60.0;              // Min SL (Pips)
input double             InpMaxSLPips          = 300.0;             // Max SL (Pips)

input group "=== Trading Filters ==="
input int                InpMaxSpreadPips      = 30;                // Max Spread (Pips)
input int                InpSlippage           = 30;                // Slippage (Points)
input int                InpMaxDailyTrades     = 2;                 // Max Daily Trades
input int                InpMinBarsBetweenTrades = 4;               // Min Bars Between Trades

input group "=== Consecutive Loss Control ==="
input int                InpMaxConsecutiveLosses = 5;               // Max Consecutive Losses Before Pause
input int                InpCooldownBars       = 24;                // Cooldown Bars After Max Losses (H1=24h)
input bool               InpResetLossesOnWin   = true;              // Reset Counter on Win

input group "=== Time Filter ==="
input bool               InpUseTimeFilter      = true;              // Use Time Filter
input int                InpStartHour          = 8;                 // Start Hour
input int                InpEndHour            = 20;                // End Hour
input bool               InpAvoidFriday        = true;              // Avoid Friday After 18:00
input bool               InpAvoidMonday        = true;              // Avoid Monday Before 8:00

input group "=== General Settings ==="
input ulong              InpMagicNumber        = 202412006;         // Magic Number
input string             InpTradeComment       = "SHA_Mom_v3.3";    // Trade Comment
input bool               InpDebugMode          = true;              // Debug Mode

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CSymbolInfo    symbolInfo;

// SHA Buffers
double shaOpenEntry[], shaHighEntry[], shaLowEntry[], shaCloseEntry[], shaColorEntry[];
double shaOpenTrend[], shaHighTrend[], shaLowTrend[], shaCloseTrend[], shaColorTrend[];

// Indicator Handles
int atrHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;
int emaHandle = INVALID_HANDLE;

double pipValue = 0.01;

// Trade tracking
int dailyTradeCount = 0;
datetime lastTradeDate = 0;
datetime lastTradeBarTime = 0;
datetime tradeEntryBarTime = 0;

// PERSISTENT consecutive losses (NOT reset daily)
int g_consecutiveLosses = 0;
datetime g_cooldownUntil = 0;

// Fintokei Risk Management
double g_initialCapital = 0;
double g_dailyStartEquity = 0;
datetime g_lastDailyReset = 0;
double g_dailyLossLimit = 0;
double g_overallLossLimit = 0;
double g_maxDrawdownToday = 0;
bool g_tradingAllowed = true;
bool g_lotReductionActive = false;

// Position management
double g_entryPrice = 0;
double g_originalSL = 0;
double g_originalLot = 0;
bool g_breakEvenApplied = false;
bool g_partialTPTaken = false;
ulong g_currentTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to get symbol info!");
      return INIT_FAILED;
   }

   int digits = symbolInfo.Digits();
   if(digits == 2) pipValue = 0.01;
   else if(digits == 3) pipValue = 0.001;
   else if(digits == 5) pipValue = 0.00001;
   else if(digits == 4) pipValue = 0.0001;
   else pipValue = symbolInfo.Point();

   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("Warning: This EA is optimized for XAUUSD (Gold).");

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetMarginMode();

   // Set arrays
   ArraySetAsSeries(shaOpenEntry, true); ArraySetAsSeries(shaHighEntry, true);
   ArraySetAsSeries(shaLowEntry, true); ArraySetAsSeries(shaCloseEntry, true);
   ArraySetAsSeries(shaColorEntry, true);
   ArraySetAsSeries(shaOpenTrend, true); ArraySetAsSeries(shaHighTrend, true);
   ArraySetAsSeries(shaLowTrend, true); ArraySetAsSeries(shaCloseTrend, true);
   ArraySetAsSeries(shaColorTrend, true);

   // Create handles
   atrHandle = iATR(_Symbol, InpEntryTimeframe, InpATRPeriod);

   if(InpUseADXFilter)
      adxHandle = iADX(_Symbol, InpEntryTimeframe, InpADXPeriod);

   if(InpUseMomentum)
      emaHandle = iMA(_Symbol, InpEntryTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle!");
      return INIT_FAILED;
   }

   InitializeFintokeiRiskManagement();

   Print("==============================================");
   Print("SmoothedHeikenAshi Gold EA v3.30 - MOMENTUM");
   Print("==============================================");
   Print("MAJOR CHANGES:");
   Print("  - Entry TF: H1 (reduced noise from M1)");
   Print("  - Simpler momentum-based entry");
   Print("  - Lower TP ratio: ", InpATRMultiplierTP, "x ATR");
   Print("  - Partial TP at 1:1 (", InpPartialTPPercent, "%)");
   Print("  - Time-based exit: ", InpMaxBarsInTrade, " bars max");
   Print("  - Persistent consecutive loss tracking");
   Print("  - Cooldown: ", InpCooldownBars, " bars after ", InpMaxConsecutiveLosses, " losses");
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Initialize Risk Management                                        |
//+------------------------------------------------------------------+
void InitializeFintokeiRiskManagement()
{
   g_initialCapital = (InpInitialCapital > 0) ? InpInitialCapital : AccountInfoDouble(ACCOUNT_BALANCE);
   g_overallLossLimit = g_initialCapital * (InpOverallLossLimit / 100.0);
   ResetDailyRiskTracking();
}

//+------------------------------------------------------------------+
//| Reset Daily Tracking (NO consecutive loss reset!)                 |
//+------------------------------------------------------------------+
void ResetDailyRiskTracking()
{
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyLossLimit = g_dailyStartEquity * (InpDailyLossLimit / 100.0);
   g_maxDrawdownToday = 0;
   g_lastDailyReset = GetUTCDate();
   g_tradingAllowed = true;
   dailyTradeCount = 0;  // Only reset daily trade count

   // NOTE: g_consecutiveLosses is NOT reset here - it persists!

   Print("=== DAILY RESET === Start: ", DoubleToString(g_dailyStartEquity, 0),
         " JPY | Consec Losses: ", g_consecutiveLosses);
}

//+------------------------------------------------------------------+
//| Get UTC Date                                                      |
//+------------------------------------------------------------------+
datetime GetUTCDate()
{
   datetime utcTime = TimeCurrent() - InpServerUTCOffset * 3600;
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);
   return StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
}

//+------------------------------------------------------------------+
//| Check Dynamic Lot Reduction                                       |
//+------------------------------------------------------------------+
void CheckDynamicLotReduction()
{
   if(!InpUseDynamicLot) return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double overallDD = ((g_initialCapital - currentEquity) / g_initialCapital) * 100.0;

   if(overallDD >= InpLotReductionThreshold && !g_lotReductionActive)
   {
      g_lotReductionActive = true;
      Print("!!! LOT REDUCTION ACTIVATED !!! DD: ", DoubleToString(overallDD, 2), "%");
   }
   else if(overallDD <= InpRecoveryThreshold && g_lotReductionActive)
   {
      g_lotReductionActive = false;
      Print("=== LOT SIZE RESTORED === DD: ", DoubleToString(overallDD, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Monitor Risk Limits                                               |
//+------------------------------------------------------------------+
bool MonitorFintokeiRiskLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(GetUTCDate() != g_lastDailyReset)
      ResetDailyRiskTracking();

   CheckDynamicLotReduction();

   // Overall 10% limit
   double overallFailLine = g_initialCapital - g_overallLossLimit;
   double safetyMargin = g_initialCapital * (InpSafetyBuffer / 100.0);

   if(currentEquity <= overallFailLine + safetyMargin)
   {
      Print("!!! CRITICAL: Overall Loss Limit !!!");
      if(InpAutoCloseOnRisk && HasOpenPosition())
         CloseAllPositions();
      g_tradingAllowed = false;
      return false;
   }

   // Daily 5% limit
   double dailyDrawdown = g_dailyStartEquity - currentEquity;
   double dailyFailLine = g_dailyStartEquity - g_dailyLossLimit;
   double dailySafetyMargin = g_dailyStartEquity * (InpSafetyBuffer / 100.0);

   if(dailyDrawdown > g_maxDrawdownToday)
      g_maxDrawdownToday = dailyDrawdown;

   if(currentEquity <= dailyFailLine + dailySafetyMargin)
   {
      Print("!!! WARNING: Daily Loss Limit !!!");
      if(InpAutoCloseOnRisk && HasOpenPosition())
         CloseAllPositions();
      g_tradingAllowed = false;
      return false;
   }

   g_tradingAllowed = true;
   return true;
}

//+------------------------------------------------------------------+
//| Get Max Allowed Risk                                              |
//+------------------------------------------------------------------+
double GetMaxAllowedRisk()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   double dailyDrawdown = g_dailyStartEquity - currentEquity;
   double dailyRemaining = g_dailyLossLimit - dailyDrawdown - g_dailyStartEquity * (InpSafetyBuffer / 100.0);

   double overallDrawdown = g_initialCapital - currentEquity;
   double overallRemaining = g_overallLossLimit - overallDrawdown - g_initialCapital * (InpSafetyBuffer / 100.0);

   double maxRiskAmount = MathMin(dailyRemaining, overallRemaining);
   double perTradeLimit = currentEquity * (InpMaxRiskPerTrade / 100.0);
   maxRiskAmount = MathMin(maxRiskAmount, perTradeLimit);

   if(maxRiskAmount < 0) maxRiskAmount = 0;
   return maxRiskAmount;
}

//+------------------------------------------------------------------+
//| Close All Positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         {
            trade.PositionClose(positionInfo.Ticket());
            Print("Emergency closed #", positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);

   Print("=== Final Stats ===");
   Print("Max DD Today: ", DoubleToString(g_maxDrawdownToday, 0), " JPY");
   Print("Final Consecutive Losses: ", g_consecutiveLosses);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!MonitorFintokeiRiskLimits())
      return;

   // Manage existing position
   if(HasOpenPosition())
   {
      ManagePosition();
      return;
   }

   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpEntryTimeframe, 0);
   if(lastBarTime == currentBarTime) return;
   lastBarTime = currentBarTime;

   // Daily reset
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(currentDate != lastTradeDate)
   {
      dailyTradeCount = 0;
      lastTradeDate = currentDate;
   }

   if(!symbolInfo.RefreshRates()) return;

   // Spread check
   double spreadPips = symbolInfo.Spread() * symbolInfo.Point() / pipValue;
   if(InpMaxSpreadPips > 0 && spreadPips > InpMaxSpreadPips)
   {
      if(InpDebugMode) Print("Spread too high: ", spreadPips);
      return;
   }

   // Time filter
   if(InpUseTimeFilter && !IsWithinTradingHours()) return;
   if(InpAvoidFriday && IsFridayEvening()) return;
   if(InpAvoidMonday && IsMondayMorning()) return;

   // Trade limits
   if(InpMaxDailyTrades > 0 && dailyTradeCount >= InpMaxDailyTrades)
   {
      if(InpDebugMode) Print("Daily trade limit reached");
      return;
   }

   // Consecutive losses cooldown check
   if(g_consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      if(TimeCurrent() < g_cooldownUntil)
      {
         if(InpDebugMode)
            Print("In cooldown. Losses: ", g_consecutiveLosses, " Cooldown until: ", TimeToString(g_cooldownUntil));
         return;
      }
      else
      {
         // Cooldown expired, reduce counter by 1 and continue
         g_consecutiveLosses = InpMaxConsecutiveLosses - 1;
         Print("Cooldown expired. Reducing loss counter to: ", g_consecutiveLosses);
      }
   }

   // Min bars between trades
   if(lastTradeBarTime > 0)
   {
      int barsSince = iBarShift(_Symbol, InpEntryTimeframe, lastTradeBarTime);
      if(barsSince < InpMinBarsBetweenTrades) return;
   }

   // Calculate SHA
   if(!CalculateAllSHA()) return;

   // Execute logic
   ProcessTradingLogic();
}

//+------------------------------------------------------------------+
//| Manage Position                                                   |
//+------------------------------------------------------------------+
void ManagePosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber) continue;

      double entryPrice = positionInfo.PriceOpen();
      double currentSL = positionInfo.StopLoss();
      double currentTP = positionInfo.TakeProfit();
      double currentLot = positionInfo.Volume();
      ulong ticket = positionInfo.Ticket();
      ENUM_POSITION_TYPE posType = positionInfo.PositionType();

      double currentPrice = (posType == POSITION_TYPE_BUY) ? symbolInfo.Bid() : symbolInfo.Ask();
      double profit = (posType == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
      double profitPips = profit / pipValue;

      // Time-based exit
      if(InpUseTimeExit && tradeEntryBarTime > 0)
      {
         int barsInTrade = iBarShift(_Symbol, InpEntryTimeframe, tradeEntryBarTime);
         if(barsInTrade >= InpMaxBarsInTrade)
         {
            trade.PositionClose(ticket);
            Print("Time-based exit after ", barsInTrade, " bars");
            return;
         }
      }

      // Partial Take Profit
      if(InpUsePartialTP && !g_partialTPTaken && g_originalSL > 0)
      {
         double slDistance = (posType == POSITION_TYPE_BUY) ?
                            (entryPrice - g_originalSL) : (g_originalSL - entryPrice);
         double partialTPDistance = slDistance * InpPartialTPRatio;

         if(profit >= partialTPDistance)
         {
            double closeAmount = NormalizeDouble(currentLot * (InpPartialTPPercent / 100.0), 2);
            double minLot = symbolInfo.LotsMin();

            if(closeAmount >= minLot && (currentLot - closeAmount) >= minLot)
            {
               if(trade.PositionClosePartial(ticket, closeAmount))
               {
                  g_partialTPTaken = true;
                  Print("Partial TP taken: ", closeAmount, " lots at +", DoubleToString(profitPips, 1), " pips");

                  // Move SL to break-even after partial TP
                  double newSL = (posType == POSITION_TYPE_BUY) ?
                                 entryPrice + InpBreakEvenBuffer * pipValue :
                                 entryPrice - InpBreakEvenBuffer * pipValue;
                  newSL = NormalizeDouble(newSL, symbolInfo.Digits());
                  trade.PositionModify(ticket, newSL, currentTP);
                  g_breakEvenApplied = true;
               }
            }
         }
      }

      // Break-Even (if no partial TP or partial TP disabled)
      if(InpUseBreakEven && !g_breakEvenApplied && profitPips >= InpBreakEvenPips)
      {
         double newSL = (posType == POSITION_TYPE_BUY) ?
                        entryPrice + InpBreakEvenBuffer * pipValue :
                        entryPrice - InpBreakEvenBuffer * pipValue;
         newSL = NormalizeDouble(newSL, symbolInfo.Digits());

         if((posType == POSITION_TYPE_BUY && newSL > currentSL) ||
            (posType == POSITION_TYPE_SELL && (currentSL == 0 || newSL < currentSL)))
         {
            if(trade.PositionModify(ticket, newSL, currentTP))
            {
               g_breakEvenApplied = true;
               Print("Break-Even at ", newSL);
            }
         }
      }

      // Trailing Stop
      if(InpUseTrailingStop && profitPips >= InpTrailingStartPips)
      {
         double trailDistance = InpTrailingStepPips * pipValue;
         double newSL;

         if(posType == POSITION_TYPE_BUY)
         {
            newSL = currentPrice - trailDistance;
            newSL = NormalizeDouble(newSL, symbolInfo.Digits());

            if(newSL > currentSL + InpTrailingStepPips * pipValue * 0.5)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("Trailing SL: ", newSL);
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            newSL = NormalizeDouble(newSL, symbolInfo.Digits());

            if(currentSL == 0 || newSL < currentSL - InpTrailingStepPips * pipValue * 0.5)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("Trailing SL: ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Monday Morning                                              |
//+------------------------------------------------------------------+
bool IsMondayMorning()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 1 && dt.hour < 8);
}

//+------------------------------------------------------------------+
//| Calculate All SHA                                                 |
//+------------------------------------------------------------------+
bool CalculateAllSHA()
{
   if(!CalculateSHA(InpEntryTimeframe, shaOpenEntry, shaHighEntry, shaLowEntry, shaCloseEntry, shaColorEntry))
      return false;
   if(!CalculateSHA(InpTrendTF, shaOpenTrend, shaHighTrend, shaLowTrend, shaCloseTrend, shaColorTrend))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Calculate SHA for Timeframe                                       |
//+------------------------------------------------------------------+
bool CalculateSHA(ENUM_TIMEFRAMES tf, double &shaOpen[], double &shaHigh[],
                  double &shaLow[], double &shaClose[], double &shaColor[])
{
   int barsNeeded = 50;
   int smoothingLength = 10;  // Fixed for v3.30

   ArrayResize(shaOpen, barsNeeded);
   ArrayResize(shaHigh, barsNeeded);
   ArrayResize(shaLow, barsNeeded);
   ArrayResize(shaClose, barsNeeded);
   ArrayResize(shaColor, barsNeeded);

   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int totalBars = barsNeeded + smoothingLength;
   if(CopyOpen(_Symbol, tf, 0, totalBars, open) < totalBars) return false;
   if(CopyHigh(_Symbol, tf, 0, totalBars, high) < totalBars) return false;
   if(CopyLow(_Symbol, tf, 0, totalBars, low) < totalBars) return false;
   if(CopyClose(_Symbol, tf, 0, totalBars, close) < totalBars) return false;

   double smoothedOpen[], smoothedHigh[], smoothedLow[], smoothedClose[];
   ArrayResize(smoothedOpen, barsNeeded);
   ArrayResize(smoothedHigh, barsNeeded);
   ArrayResize(smoothedLow, barsNeeded);
   ArrayResize(smoothedClose, barsNeeded);
   ArraySetAsSeries(smoothedOpen, true);
   ArraySetAsSeries(smoothedHigh, true);
   ArraySetAsSeries(smoothedLow, true);
   ArraySetAsSeries(smoothedClose, true);

   double alpha = 2.0 / (smoothingLength + 1.0);
   int startIdx = barsNeeded - 1;

   smoothedOpen[startIdx] = open[startIdx];
   smoothedHigh[startIdx] = high[startIdx];
   smoothedLow[startIdx] = low[startIdx];
   smoothedClose[startIdx] = close[startIdx];

   for(int i = startIdx - 1; i >= 0; i--)
   {
      smoothedOpen[i] = alpha * open[i] + (1 - alpha) * smoothedOpen[i + 1];
      smoothedHigh[i] = alpha * high[i] + (1 - alpha) * smoothedHigh[i + 1];
      smoothedLow[i] = alpha * low[i] + (1 - alpha) * smoothedLow[i + 1];
      smoothedClose[i] = alpha * close[i] + (1 - alpha) * smoothedClose[i + 1];
   }

   shaClose[startIdx] = (smoothedOpen[startIdx] + smoothedHigh[startIdx] +
                         smoothedLow[startIdx] + smoothedClose[startIdx]) / 4.0;
   shaOpen[startIdx] = (smoothedOpen[startIdx] + smoothedClose[startIdx]) / 2.0;
   shaHigh[startIdx] = smoothedHigh[startIdx];
   shaLow[startIdx] = smoothedLow[startIdx];

   for(int i = startIdx - 1; i >= 0; i--)
   {
      shaClose[i] = (smoothedOpen[i] + smoothedHigh[i] + smoothedLow[i] + smoothedClose[i]) / 4.0;
      shaOpen[i] = (shaOpen[i + 1] + shaClose[i + 1]) / 2.0;
      shaHigh[i] = MathMax(smoothedHigh[i], MathMax(shaOpen[i], shaClose[i]));
      shaLow[i] = MathMin(smoothedLow[i], MathMin(shaOpen[i], shaClose[i]));
      shaColor[i] = (shaClose[i] >= shaOpen[i]) ? 0.0 : 1.0;  // 0=Bull, 1=Bear
   }

   return true;
}

//+------------------------------------------------------------------+
//| Get Trend Direction                                               |
//+------------------------------------------------------------------+
int GetTrendDirection(double &shaColor[], int confirmBars)
{
   bool allBullish = true, allBearish = true;

   for(int i = 1; i <= confirmBars; i++)
   {
      if(i >= ArraySize(shaColor)) return 0;
      if(shaColor[i] != 0.0) allBullish = false;
      if(shaColor[i] != 1.0) allBearish = false;
   }

   if(allBullish) return 1;
   if(allBearish) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Check Momentum Filter (Price above/below EMA)                     |
//+------------------------------------------------------------------+
bool CheckMomentum(bool isLong)
{
   if(!InpUseMomentum || emaHandle == INVALID_HANDLE) return true;

   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(emaHandle, 0, 1, 1, ema) <= 0) return true;

   double currentClose = iClose(_Symbol, InpEntryTimeframe, 1);
   double emaValue = ema[0];
   double distance = MathAbs(currentClose - emaValue) / pipValue;

   if(distance < InpMinMomentumPips)
   {
      if(InpDebugMode)
         Print("Momentum too weak: ", DoubleToString(distance, 1), " pips from EMA");
      return false;
   }

   if(isLong)
      return currentClose > emaValue;
   else
      return currentClose < emaValue;
}

//+------------------------------------------------------------------+
//| Get ATR                                                           |
//+------------------------------------------------------------------+
double GetATR(int shift = 1)
{
   if(atrHandle == INVALID_HANDLE) return 0;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, shift, 1, atr) <= 0) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| Check ATR Filter                                                  |
//+------------------------------------------------------------------+
bool CheckATRFilter()
{
   double atr = GetATR(1);
   double atrPips = atr / pipValue;

   if(atrPips < InpMinATRPips || atrPips > InpMaxATRPips)
   {
      if(InpDebugMode)
         Print("ATR out of range: ", DoubleToString(atrPips, 1), " pips");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get ADX Values                                                    |
//+------------------------------------------------------------------+
bool GetADXValues(double &adx, double &plusDI, double &minusDI, int shift = 1)
{
   if(adxHandle == INVALID_HANDLE) return false;

   double adxBuf[], plusBuf[], minusBuf[];
   ArraySetAsSeries(adxBuf, true);
   ArraySetAsSeries(plusBuf, true);
   ArraySetAsSeries(minusBuf, true);

   if(CopyBuffer(adxHandle, 0, shift, 1, adxBuf) <= 0) return false;
   if(CopyBuffer(adxHandle, 1, shift, 1, plusBuf) <= 0) return false;
   if(CopyBuffer(adxHandle, 2, shift, 1, minusBuf) <= 0) return false;

   adx = adxBuf[0];
   plusDI = plusBuf[0];
   minusDI = minusBuf[0];
   return true;
}

//+------------------------------------------------------------------+
//| Check ADX Filter                                                  |
//+------------------------------------------------------------------+
bool CheckADXFilter(bool isLong)
{
   if(!InpUseADXFilter) return true;

   double adx, plusDI, minusDI;
   if(!GetADXValues(adx, plusDI, minusDI)) return true;

   double minADX = isLong ? InpMinADX : InpMinADXShort;

   if(adx < minADX || adx > InpMaxADX)
   {
      if(InpDebugMode)
         Print("ADX out of range: ", DoubleToString(adx, 1));
      return false;
   }

   // Check DI alignment
   if(isLong && plusDI <= minusDI)
   {
      if(InpDebugMode)
         Print("DI not aligned for Long: +DI=", DoubleToString(plusDI, 1), " -DI=", DoubleToString(minusDI, 1));
      return false;
   }
   if(!isLong && minusDI <= plusDI)
   {
      if(InpDebugMode)
         Print("DI not aligned for Short: +DI=", DoubleToString(plusDI, 1), " -DI=", DoubleToString(minusDI, 1));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check Entry Signal (Simplified for v3.30)                         |
//+------------------------------------------------------------------+
bool CheckEntrySignal(bool isLong)
{
   // Check SHA color on entry timeframe
   for(int i = 1; i <= InpSHAConfirmBars; i++)
   {
      if(i >= ArraySize(shaColorEntry)) return false;
      if(isLong && shaColorEntry[i] != 0.0) return false;   // Need bullish
      if(!isLong && shaColorEntry[i] != 1.0) return false;  // Need bearish
   }

   // Check trend alignment on H4
   int trendDirection = GetTrendDirection(shaColorTrend, InpTrendConfirmBars);
   if(isLong && trendDirection != 1) return false;
   if(!isLong && trendDirection != -1) return false;

   // Check momentum (price vs EMA)
   if(!CheckMomentum(isLong)) return false;

   // Check candle strength (body > 30% of range)
   double open1 = iOpen(_Symbol, InpEntryTimeframe, 1);
   double close1 = iClose(_Symbol, InpEntryTimeframe, 1);
   double high1 = iHigh(_Symbol, InpEntryTimeframe, 1);
   double low1 = iLow(_Symbol, InpEntryTimeframe, 1);

   if(high1 == low1) return false;

   double body = MathAbs(close1 - open1);
   double range = high1 - low1;

   if(body < range * 0.3)
   {
      if(InpDebugMode)
         Print("Candle body too small: ", DoubleToString((body/range)*100, 1), "%");
      return false;
   }

   // Confirm candle direction
   if(isLong && close1 <= open1) return false;
   if(!isLong && close1 >= open1) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Process Trading Logic                                             |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   if(!g_tradingAllowed) return;
   if(!CheckATRFilter()) return;

   // LONG
   if(CheckADXFilter(true) && CheckEntrySignal(true))
   {
      if(InpDebugMode) Print("=== LONG SIGNAL ===");
      ExecuteLongEntry();
      return;
   }

   // SHORT
   if(!InpEnableShort) return;

   if(CheckADXFilter(false) && CheckEntrySignal(false))
   {
      if(InpDebugMode) Print("=== SHORT SIGNAL ===");
      ExecuteShortEntry();
      return;
   }
}

//+------------------------------------------------------------------+
//| Calculate Loss Per Lot                                            |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slDistance)
{
   double tickSize = symbolInfo.TickSize();
   double tickValue = symbolInfo.TickValue();
   if(tickSize == 0) return 0;
   return (slDistance / tickSize) * tickValue;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double maxRisk = GetMaxAllowedRisk();
   if(maxRisk <= 0) return 0;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double desiredRisk = currentEquity * (InpRiskPercent / 100.0);
   double riskAmount = MathMin(desiredRisk, maxRisk);

   // Apply lot reduction
   if(g_lotReductionActive)
   {
      riskAmount *= (InpLotReductionPercent / 100.0);
      Print("Lot reduced: Risk = ", DoubleToString(riskAmount, 0), " JPY");
   }

   double lossPerLot = CalculateLossPerLot(slDistance);
   if(lossPerLot <= 0) return InpFixedLot;

   double lotSize = riskAmount / lossPerLot;

   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Execute Long Entry                                                |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   double ask = symbolInfo.Ask();
   double atr = GetATR(1);

   double sl = ask - atr * InpATRMultiplierSL;
   double slDistance = ask - sl;

   // Enforce min/max SL
   double minSL = InpMinSLPips * pipValue;
   double maxSL = InpMaxSLPips * pipValue;

   if(slDistance < minSL) { sl = ask - minSL; slDistance = minSL; }
   else if(slDistance > maxSL) { sl = ask - maxSL; slDistance = maxSL; }

   double tp = ask + atr * InpATRMultiplierTP;

   sl = NormalizeDouble(sl, symbolInfo.Digits());
   tp = NormalizeDouble(tp, symbolInfo.Digits());

   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0) { Print("No risk capacity!"); return; }

   double tradeRisk = CalculateLossPerLot(slDistance) * lotSize;

   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;
      lastTradeBarTime = iTime(_Symbol, InpEntryTimeframe, 0);
      tradeEntryBarTime = lastTradeBarTime;
      g_entryPrice = ask;
      g_originalSL = sl;
      g_originalLot = lotSize;
      g_breakEvenApplied = false;
      g_partialTPTaken = false;
      g_currentTicket = trade.ResultOrder();

      Print("LONG: Lot=", lotSize, " SL=", DoubleToString(slDistance/pipValue, 1), " pips",
            " Risk=", DoubleToString(tradeRisk, 0), " JPY",
            " ConsecLoss=", g_consecutiveLosses,
            g_lotReductionActive ? " [REDUCED]" : "");
   }
}

//+------------------------------------------------------------------+
//| Execute Short Entry                                               |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
   double bid = symbolInfo.Bid();
   double atr = GetATR(1);

   double sl = bid + atr * InpATRMultiplierSL;
   double slDistance = sl - bid;

   // Enforce min/max SL
   double minSL = InpMinSLPips * pipValue;
   double maxSL = InpMaxSLPips * pipValue;

   if(slDistance < minSL) { sl = bid + minSL; slDistance = minSL; }
   else if(slDistance > maxSL) { sl = bid + maxSL; slDistance = maxSL; }

   double tp = bid - atr * InpATRMultiplierTP;

   sl = NormalizeDouble(sl, symbolInfo.Digits());
   tp = NormalizeDouble(tp, symbolInfo.Digits());

   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0) { Print("No risk capacity!"); return; }

   double tradeRisk = CalculateLossPerLot(slDistance) * lotSize;

   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;
      lastTradeBarTime = iTime(_Symbol, InpEntryTimeframe, 0);
      tradeEntryBarTime = lastTradeBarTime;
      g_entryPrice = bid;
      g_originalSL = sl;
      g_originalLot = lotSize;
      g_breakEvenApplied = false;
      g_partialTPTaken = false;
      g_currentTicket = trade.ResultOrder();

      Print("SHORT: Lot=", lotSize, " SL=", DoubleToString(slDistance/pipValue, 1), " pips",
            " Risk=", DoubleToString(tradeRisk, 0), " JPY",
            " ConsecLoss=", g_consecutiveLosses,
            g_lotReductionActive ? " [REDUCED]" : "");
   }
}

//+------------------------------------------------------------------+
//| Has Open Position                                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Is Within Trading Hours                                           |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int currentHour = dt.hour;
   return (currentHour >= InpStartHour && currentHour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Is Friday Evening                                                 |
//+------------------------------------------------------------------+
bool IsFridayEvening()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= 18);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Track consecutive losses                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
      {
         ulong dealTicket = trans.deal;
         if(dealTicket > 0)
         {
            if(HistoryDealSelect(dealTicket))
            {
               ulong dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
               if(dealMagic != InpMagicNumber) return;

               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
               {
                  if(profit < 0)
                  {
                     g_consecutiveLosses++;

                     // Set cooldown if max losses reached
                     if(g_consecutiveLosses >= InpMaxConsecutiveLosses)
                     {
                        g_cooldownUntil = TimeCurrent() + InpCooldownBars * PeriodSeconds(InpEntryTimeframe);
                        Print("!!! MAX LOSSES REACHED: ", g_consecutiveLosses,
                              " | Cooldown until: ", TimeToString(g_cooldownUntil));
                     }
                     else
                     {
                        Print("Loss #", g_consecutiveLosses, " recorded. P/L: ", DoubleToString(profit, 0));
                     }
                  }
                  else if(profit > 0)
                  {
                     if(InpResetLossesOnWin)
                     {
                        Print("WIN! Resetting consecutive losses from ", g_consecutiveLosses, " to 0");
                        g_consecutiveLosses = 0;
                        g_cooldownUntil = 0;
                     }
                     else
                     {
                        // Just reduce by 1
                        if(g_consecutiveLosses > 0) g_consecutiveLosses--;
                        Print("WIN! Reducing consecutive losses to ", g_consecutiveLosses);
                     }
                  }

                  // Reset position tracking
                  g_entryPrice = 0;
                  g_originalSL = 0;
                  g_breakEvenApplied = false;
                  g_partialTPTaken = false;
                  tradeEntryBarTime = 0;
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
