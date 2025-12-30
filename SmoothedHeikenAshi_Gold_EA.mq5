//+------------------------------------------------------------------+
//|                                   SmoothedHeikenAshi_Gold_EA.mq5 |
//|                                  Smoothed Heiken Ashi Strategy EA |
//|                                       For XAUUSD (Gold) Trading   |
//|                                    Fintokei Challenge Compliant   |
//|                              Multi-Timeframe Edition (M1/H1/H4)   |
//|                                      Advanced Risk Management     |
//|                                                        v3.20      |
//+------------------------------------------------------------------+
#property copyright "Smoothed Heiken Ashi Gold EA v3.20 - Advanced Risk Edition"
#property link      ""
#property version   "3.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Multi-Timeframe Settings ==="
input ENUM_TIMEFRAMES    InpEntryTimeframe     = PERIOD_M1;        // Entry Timeframe (M1)
input ENUM_TIMEFRAMES    InpTrendTF1           = PERIOD_H1;        // Trend Timeframe 1 (H1)
input ENUM_TIMEFRAMES    InpTrendTF2           = PERIOD_H4;        // Trend Timeframe 2 (H4)
input int                InpTrendConfirmBars   = 3;                // Trend Confirm Bars (H1/H4) - Increased
input bool               InpRequireBothTFAlign = true;             // Require Both TF Trend Alignment

input group "=== Fintokei Risk Management (CRITICAL) ==="
input double             InpInitialCapital     = 2000000.0;        // Initial Capital (JPY)
input double             InpDailyLossLimit     = 5.0;              // Daily Loss Limit (%) - Fintokei: 5%
input double             InpOverallLossLimit   = 10.0;             // Overall Loss Limit (%) - Fintokei: 10%
input double             InpMaxRiskPerTrade    = 2.0;              // Max Risk Per Trade (%) - Reduced from 3%
input double             InpSafetyBuffer       = 0.5;              // Safety Buffer (%)
input bool               InpAutoCloseOnRisk    = true;             // Auto-Close Positions Near Limit
input int                InpServerUTCOffset    = 0;                // Server UTC Offset (hours)

input group "=== Dynamic Lot Reduction (NEW) ==="
input bool               InpUseDynamicLot      = true;             // Use Dynamic Lot Reduction
input double             InpLotReductionThreshold = 5.0;           // DD% Threshold for Lot Reduction
input double             InpLotReductionPercent = 50.0;            // Lot Reduction % (50 = half lot)
input double             InpRecoveryThreshold  = 2.0;              // DD% to Resume Normal Lot

input group "=== Trailing Stop & Break-Even (NEW) ==="
input bool               InpUseTrailingStop    = true;             // Use Trailing Stop
input double             InpTrailingStartPips  = 150.0;            // Start Trailing After (Pips) [$1.5]
input double             InpTrailingStepPips   = 50.0;             // Trailing Step (Pips) [$0.5]
input bool               InpUseBreakEven       = true;             // Use Break-Even
input double             InpBreakEvenPips      = 100.0;            // Move to BE After (Pips) [$1]
input double             InpBreakEvenBuffer    = 10.0;             // Break-Even Buffer (Pips) [$0.1]

input group "=== RSI Filter (NEW) ==="
input bool               InpUseRSIFilter       = true;             // Use RSI Filter
input int                InpRSIPeriod          = 14;               // RSI Period
input double             InpRSIOverbought      = 70.0;             // RSI Overbought (No Long above)
input double             InpRSIOversold        = 30.0;             // RSI Oversold (No Short below)
input ENUM_TIMEFRAMES    InpRSITimeframe       = PERIOD_H1;        // RSI Timeframe

input group "=== Lot Size Optimization ==="
input bool               InpUseTightSL         = true;             // Use Tight SL for Higher Lots
input double             InpTightSLMultiplier  = 0.7;              // Tight SL Multiplier (Increased from 0.6)
input double             InpMinSLPipsOptimized = 100.0;            // Min SL for Optimized Entry

input group "=== Smoothed Heiken Ashi Settings ==="
input int                InpSmoothingLength    = 15;               // Smoothing Length
input int                InpSHAConfirmBars     = 3;                // SHA Consecutive Bars for Entry (Increased)

input group "=== Entry Conditions (M1) ==="
input double             InpPullbackPips       = 80.0;             // Pullback Tolerance (Pips) - Tightened
input bool               InpRequireBounce      = true;             // Require Bounce Confirmation
input int                InpBounceStrength     = 2;                // Bounce Strength (Increased)
input int                InpPullbackBars       = 8;                // Max Bars to Wait for Pullback

input group "=== ATR Filter Settings ==="
input bool               InpUseATRFilter       = true;             // Use ATR Filter
input int                InpATRPeriod          = 14;               // ATR Period
input double             InpATRMultiplierSL    = 1.2;              // ATR Multiplier for SL
input double             InpATRMultiplierTP    = 2.5;              // ATR Multiplier for TP (Increased)
input double             InpMinATRPips         = 30.0;             // Min ATR (Pips)
input double             InpMaxATRPips         = 300.0;            // Max ATR (Pips)

input group "=== ADX Filter Settings ==="
input bool               InpUseADXFilter       = true;             // Use ADX Filter
input int                InpADXPeriod          = 14;               // ADX Period
input double             InpMinADX             = 25.0;             // Min ADX (Increased from 20)
input double             InpMaxADX             = 45.0;             // Max ADX (Reduced from 50)

input group "=== Short Trade Settings ==="
input bool               InpEnableShort        = true;             // Enable Short Trades
input double             InpMinADXShort        = 28.0;             // Min ADX for Short (Stricter)

input group "=== Money Management ==="
input double             InpRiskPercent        = 1.5;              // Risk Percent (Reduced from 2%)
input double             InpFixedLot           = 0.1;              // Fixed Lot Size (if Risk% = 0)
input double             InpRiskRewardRatio    = 2.5;              // Risk:Reward Ratio (Increased)
input double             InpMinSLPips          = 80.0;             // Min SL Distance (Pips)
input double             InpMaxSLPips          = 400.0;            // Max SL Distance (Pips)

input group "=== Trading Filters ==="
input int                InpMaxSpreadPips      = 25;               // Maximum Spread (Pips)
input int                InpSlippage           = 30;               // Slippage (Points)
input int                InpMaxDailyTrades     = 3;                // Max Trades Per Day (Reduced)
input int                InpMinBarsBetweenTrades = 60;             // Min Bars Between Trades (Increased)
input int                InpMaxConsecutiveLosses = 3;              // Max Consecutive Losses Before Pause

input group "=== Time Filter ==="
input bool               InpUseTimeFilter      = true;             // Use Time Filter
input int                InpStartHour          = 10;               // Start Hour (Later start)
input int                InpStartMinute        = 0;                // Start Minute
input int                InpEndHour            = 20;               // End Hour (Earlier end)
input int                InpEndMinute          = 0;                // End Minute
input bool               InpAvoidFriday        = true;             // Avoid Friday After 18:00
input bool               InpAvoidMonday        = true;             // Avoid Monday Before 10:00

input group "=== General Settings ==="
input ulong              InpMagicNumber        = 202412005;        // Magic Number
input string             InpTradeComment       = "SHA_MTF_v3.2";   // Trade Comment
input bool               InpDebugMode          = true;             // Debug Mode

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CSymbolInfo    symbolInfo;

// SHA Buffers
double shaOpenM1[], shaHighM1[], shaLowM1[], shaCloseM1[], shaColorM1[];
double shaOpenH1[], shaHighH1[], shaLowH1[], shaCloseH1[], shaColorH1[];
double shaOpenH4[], shaHighH4[], shaLowH4[], shaCloseH4[], shaColorH4[];

// Indicator Handles
int atrHandleM1 = INVALID_HANDLE;
int atrHandleH1 = INVALID_HANDLE;
int adxHandleH1 = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;

double pipValue = 0.01;

// Trade tracking
int dailyTradeCount = 0;
datetime lastTradeDate = 0;
datetime lastTradeBarTime = 0;
int consecutiveLosses = 0;

// Fintokei Risk Management
double g_initialCapital = 0;
double g_dailyStartEquity = 0;
datetime g_lastDailyReset = 0;
double g_dailyLossLimit = 0;
double g_overallLossLimit = 0;
double g_maxDrawdownToday = 0;
bool g_tradingAllowed = true;
bool g_lotReductionActive = false;

// Trend cache
int g_trendH1 = 0;
int g_trendH4 = 0;

// Position tracking for trailing/BE
double g_entryPrice = 0;
double g_currentSL = 0;
bool g_breakEvenApplied = false;

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
   ArraySetAsSeries(shaOpenM1, true); ArraySetAsSeries(shaHighM1, true);
   ArraySetAsSeries(shaLowM1, true); ArraySetAsSeries(shaCloseM1, true);
   ArraySetAsSeries(shaColorM1, true);
   ArraySetAsSeries(shaOpenH1, true); ArraySetAsSeries(shaHighH1, true);
   ArraySetAsSeries(shaLowH1, true); ArraySetAsSeries(shaCloseH1, true);
   ArraySetAsSeries(shaColorH1, true);
   ArraySetAsSeries(shaOpenH4, true); ArraySetAsSeries(shaHighH4, true);
   ArraySetAsSeries(shaLowH4, true); ArraySetAsSeries(shaCloseH4, true);
   ArraySetAsSeries(shaColorH4, true);

   // Create handles
   atrHandleM1 = iATR(_Symbol, InpEntryTimeframe, InpATRPeriod);
   atrHandleH1 = iATR(_Symbol, InpTrendTF1, InpATRPeriod);

   if(InpUseADXFilter)
      adxHandleH1 = iADX(_Symbol, InpTrendTF1, InpADXPeriod);

   if(InpUseRSIFilter)
      rsiHandle = iRSI(_Symbol, InpRSITimeframe, InpRSIPeriod, PRICE_CLOSE);

   if(atrHandleM1 == INVALID_HANDLE || atrHandleH1 == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles!");
      return INIT_FAILED;
   }

   InitializeFintokeiRiskManagement();

   Print("==============================================");
   Print("SmoothedHeikenAshi Gold EA v3.20 - ADVANCED RISK");
   Print("==============================================");
   Print("IMPROVEMENTS:");
   Print("  - Dynamic Lot Reduction at ", InpLotReductionThreshold, "% DD");
   Print("  - Trailing Stop: Start ", InpTrailingStartPips, " pips");
   Print("  - Break-Even at ", InpBreakEvenPips, " pips profit");
   Print("  - RSI Filter: ", InpRSIOversold, "-", InpRSIOverbought);
   Print("  - Stronger trend filter: ", InpTrendConfirmBars, " bars");
   Print("  - Max consecutive losses: ", InpMaxConsecutiveLosses);
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
//| Reset Daily Tracking                                              |
//+------------------------------------------------------------------+
void ResetDailyRiskTracking()
{
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyLossLimit = g_dailyStartEquity * (InpDailyLossLimit / 100.0);
   g_maxDrawdownToday = 0;
   g_lastDailyReset = GetUTCDate();
   g_tradingAllowed = true;
   consecutiveLosses = 0;

   Print("=== DAILY RESET === Start: ", DoubleToString(g_dailyStartEquity, 0), " JPY");
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
      Print("Lot size reduced to ", InpLotReductionPercent, "% of normal");
   }
   else if(overallDD <= InpRecoveryThreshold && g_lotReductionActive)
   {
      g_lotReductionActive = false;
      Print("=== LOT SIZE RESTORED === DD recovered to: ", DoubleToString(overallDD, 2), "%");
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
   if(atrHandleM1 != INVALID_HANDLE) IndicatorRelease(atrHandleM1);
   if(atrHandleH1 != INVALID_HANDLE) IndicatorRelease(atrHandleH1);
   if(adxHandleH1 != INVALID_HANDLE) IndicatorRelease(adxHandleH1);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);

   Print("=== Final: Max DD Today: ", DoubleToString(g_maxDrawdownToday, 0), " JPY ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!MonitorFintokeiRiskLimits())
      return;

   // Manage existing position (trailing/BE)
   if(HasOpenPosition())
   {
      ManagePosition();
      return;
   }

   // Check for new M1 bar
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
   if(InpMaxSpreadPips > 0 && spreadPips > InpMaxSpreadPips) return;

   // Time filter
   if(InpUseTimeFilter && !IsWithinTradingHours()) return;
   if(InpAvoidFriday && IsFridayEvening()) return;
   if(InpAvoidMonday && IsMondayMorning()) return;

   // Trade limits
   if(InpMaxDailyTrades > 0 && dailyTradeCount >= InpMaxDailyTrades) return;

   // Consecutive losses check
   if(consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      if(InpDebugMode)
         Print("Paused: ", consecutiveLosses, " consecutive losses");
      return;
   }

   // Min bars between trades
   if(lastTradeBarTime > 0)
   {
      int barsSince = iBarShift(_Symbol, InpEntryTimeframe, lastTradeBarTime);
      if(barsSince < InpMinBarsBetweenTrades) return;
   }

   // Calculate SHA
   if(!CalculateAllSHA()) return;

   // Update trends
   UpdateTrendDirections();

   // Execute logic
   ProcessTradingLogic();
}

//+------------------------------------------------------------------+
//| Manage Position (Trailing/Break-Even)                             |
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
      ENUM_POSITION_TYPE posType = positionInfo.PositionType();

      double currentPrice = (posType == POSITION_TYPE_BUY) ? symbolInfo.Bid() : symbolInfo.Ask();
      double profit = (posType == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
      double profitPips = profit / pipValue;

      // Break-Even
      if(InpUseBreakEven && !g_breakEvenApplied)
      {
         if(profitPips >= InpBreakEvenPips)
         {
            double newSL;
            if(posType == POSITION_TYPE_BUY)
               newSL = entryPrice + InpBreakEvenBuffer * pipValue;
            else
               newSL = entryPrice - InpBreakEvenBuffer * pipValue;

            newSL = NormalizeDouble(newSL, symbolInfo.Digits());

            if((posType == POSITION_TYPE_BUY && newSL > currentSL) ||
               (posType == POSITION_TYPE_SELL && (currentSL == 0 || newSL < currentSL)))
            {
               if(trade.PositionModify(positionInfo.Ticket(), newSL, currentTP))
               {
                  g_breakEvenApplied = true;
                  Print("Break-Even applied at ", newSL);
               }
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
               if(trade.PositionModify(positionInfo.Ticket(), newSL, currentTP))
                  Print("Trailing SL moved to ", newSL);
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            newSL = NormalizeDouble(newSL, symbolInfo.Digits());

            if(currentSL == 0 || newSL < currentSL - InpTrailingStepPips * pipValue * 0.5)
            {
               if(trade.PositionModify(positionInfo.Ticket(), newSL, currentTP))
                  Print("Trailing SL moved to ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check RSI Filter                                                  |
//+------------------------------------------------------------------+
bool CheckRSIFilter(bool isLong)
{
   if(!InpUseRSIFilter || rsiHandle == INVALID_HANDLE) return true;

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsiHandle, 0, 1, 1, rsi) <= 0) return true;

   double rsiValue = rsi[0];

   if(isLong)
   {
      if(rsiValue >= InpRSIOverbought)
      {
         if(InpDebugMode)
            Print("RSI blocked Long: ", DoubleToString(rsiValue, 1), " >= ", InpRSIOverbought);
         return false;
      }
   }
   else
   {
      if(rsiValue <= InpRSIOversold)
      {
         if(InpDebugMode)
            Print("RSI blocked Short: ", DoubleToString(rsiValue, 1), " <= ", InpRSIOversold);
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check Monday Morning                                              |
//+------------------------------------------------------------------+
bool IsMondayMorning()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 1 && dt.hour < 10);
}

//+------------------------------------------------------------------+
//| Calculate All SHA                                                 |
//+------------------------------------------------------------------+
bool CalculateAllSHA()
{
   if(!CalculateSHA(InpEntryTimeframe, shaOpenM1, shaHighM1, shaLowM1, shaCloseM1, shaColorM1)) return false;
   if(!CalculateSHA(InpTrendTF1, shaOpenH1, shaHighH1, shaLowH1, shaCloseH1, shaColorH1)) return false;
   if(!CalculateSHA(InpTrendTF2, shaOpenH4, shaHighH4, shaLowH4, shaCloseH4, shaColorH4)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Calculate SHA for Timeframe                                       |
//+------------------------------------------------------------------+
bool CalculateSHA(ENUM_TIMEFRAMES tf, double &shaOpen[], double &shaHigh[],
                  double &shaLow[], double &shaClose[], double &shaColor[])
{
   int barsNeeded = 50;
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

   int totalBars = barsNeeded + InpSmoothingLength;
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

   double alpha = 2.0 / (InpSmoothingLength + 1.0);
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
      shaColor[i] = (shaClose[i] >= shaOpen[i]) ? 0.0 : 1.0;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Update Trend Directions                                           |
//+------------------------------------------------------------------+
void UpdateTrendDirections()
{
   g_trendH1 = GetTrendDirection(shaColorH1, InpTrendConfirmBars);
   g_trendH4 = GetTrendDirection(shaColorH4, InpTrendConfirmBars);
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
//| Check Trends Aligned                                              |
//+------------------------------------------------------------------+
bool AreTrendsAligned(int direction)
{
   if(InpRequireBothTFAlign)
      return (g_trendH1 == direction && g_trendH4 == direction);
   return (g_trendH1 == direction || g_trendH4 == direction);
}

//+------------------------------------------------------------------+
//| Get ATR                                                           |
//+------------------------------------------------------------------+
double GetATR(int handle, int shift = 1)
{
   if(handle == INVALID_HANDLE) return 0;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handle, 0, shift, 1, atr) <= 0) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| Get ADX Values                                                    |
//+------------------------------------------------------------------+
bool GetADXValues(double &adx, double &plusDI, double &minusDI, int shift = 1)
{
   if(adxHandleH1 == INVALID_HANDLE) return false;

   double adxBuf[], plusBuf[], minusBuf[];
   ArraySetAsSeries(adxBuf, true);
   ArraySetAsSeries(plusBuf, true);
   ArraySetAsSeries(minusBuf, true);

   if(CopyBuffer(adxHandleH1, 0, shift, 1, adxBuf) <= 0) return false;
   if(CopyBuffer(adxHandleH1, 1, shift, 1, plusBuf) <= 0) return false;
   if(CopyBuffer(adxHandleH1, 2, shift, 1, minusBuf) <= 0) return false;

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

   if(adx < minADX || adx > InpMaxADX) return false;
   if(isLong && plusDI <= minusDI) return false;
   if(!isLong && minusDI <= plusDI) return false;

   // Extra check for shorts
   if(!isLong)
   {
      double diDiff = minusDI - plusDI;
      if(diDiff < 5.0) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check ATR Filter                                                  |
//+------------------------------------------------------------------+
bool CheckATRFilter()
{
   if(!InpUseATRFilter) return true;

   double atr = GetATR(atrHandleM1, 1);
   double atrPips = atr / pipValue;

   return (atrPips >= InpMinATRPips && atrPips <= InpMaxATRPips);
}

//+------------------------------------------------------------------+
//| Get SHA Middle M1                                                 |
//+------------------------------------------------------------------+
double GetSHAMiddleM1(int shift)
{
   if(shift < 0 || shift >= ArraySize(shaOpenM1)) return 0;
   return (shaOpenM1[shift] + shaCloseM1[shift]) / 2.0;
}

//+------------------------------------------------------------------+
//| Check M1 Entry Signal                                             |
//+------------------------------------------------------------------+
bool CheckM1EntrySignal(bool isLong)
{
   for(int i = 1; i <= InpSHAConfirmBars; i++)
   {
      if(i >= ArraySize(shaColorM1)) return false;
      if(isLong && shaColorM1[i] != 0.0) return false;
      if(!isLong && shaColorM1[i] != 1.0) return false;
   }

   double currentClose = iClose(_Symbol, InpEntryTimeframe, 1);
   double shaMiddle = GetSHAMiddleM1(1);

   if(isLong && currentClose <= shaMiddle) return false;
   if(!isLong && currentClose >= shaMiddle) return false;

   if(!DetectPullbackM1(isLong)) return false;
   if(InpRequireBounce && !CheckBounceM1(isLong)) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Detect Pullback M1                                                |
//+------------------------------------------------------------------+
bool DetectPullbackM1(bool isLong)
{
   double tolerance = InpPullbackPips * pipValue;

   for(int i = 1; i <= InpPullbackBars; i++)
   {
      double shaMiddle = GetSHAMiddleM1(i);
      double barHigh = iHigh(_Symbol, InpEntryTimeframe, i);
      double barLow = iLow(_Symbol, InpEntryTimeframe, i);
      double barClose = iClose(_Symbol, InpEntryTimeframe, i);

      if(isLong)
      {
         if((barLow - shaMiddle) <= tolerance && (barLow - shaMiddle) >= -tolerance * 0.5)
            if(barClose > shaMiddle) return true;
      }
      else
      {
         if((shaMiddle - barHigh) <= tolerance && (shaMiddle - barHigh) >= -tolerance * 0.5)
            if(barClose < shaMiddle) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check Bounce M1                                                   |
//+------------------------------------------------------------------+
bool CheckBounceM1(bool isLong)
{
   double open1 = iOpen(_Symbol, InpEntryTimeframe, 1);
   double close1 = iClose(_Symbol, InpEntryTimeframe, 1);
   double high1 = iHigh(_Symbol, InpEntryTimeframe, 1);
   double low1 = iLow(_Symbol, InpEntryTimeframe, 1);

   if(high1 == low1) return false;

   double body = MathAbs(close1 - open1);

   if(isLong)
   {
      bool isBullish = close1 > open1;
      double lowerWick = MathMin(open1, close1) - low1;

      switch(InpBounceStrength)
      {
         case 1: return isBullish;
         case 2: return isBullish && (lowerWick >= body * 0.3);
         case 3: return isBullish && (lowerWick >= body * 0.5);
      }
   }
   else
   {
      bool isBearish = close1 < open1;
      double upperWick = high1 - MathMax(open1, close1);

      switch(InpBounceStrength)
      {
         case 1: return isBearish;
         case 2: return isBearish && (upperWick >= body * 0.3);
         case 3: return isBearish && (upperWick >= body * 0.5);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Process Trading Logic                                             |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   if(!g_tradingAllowed) return;
   if(!CheckATRFilter()) return;

   // LONG
   if(AreTrendsAligned(1))
   {
      if(CheckADXFilter(true) && CheckRSIFilter(true) && CheckM1EntrySignal(true))
      {
         Print("=== LONG ENTRY (H4+H1+M1 Aligned) ===");
         ExecuteLongEntry();
         return;
      }
   }

   // SHORT
   if(!InpEnableShort) return;

   if(AreTrendsAligned(-1))
   {
      if(CheckADXFilter(false) && CheckRSIFilter(false) && CheckM1EntrySignal(false))
      {
         Print("=== SHORT ENTRY (H4+H1+M1 Aligned) ===");
         ExecuteShortEntry();
         return;
      }
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

   // Apply lot reduction if active
   if(g_lotReductionActive)
   {
      riskAmount *= (InpLotReductionPercent / 100.0);
      Print("Lot reduction applied: Risk reduced to ", DoubleToString(riskAmount, 0), " JPY");
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
//| Get Optimized SL                                                  |
//+------------------------------------------------------------------+
double GetOptimizedSL(double baseSL, double entryPrice, bool isLong)
{
   if(!InpUseTightSL) return baseSL;

   double baseDistance = isLong ? (entryPrice - baseSL) : (baseSL - entryPrice);
   double optimizedDistance = baseDistance * InpTightSLMultiplier;

   double minDistance = InpMinSLPipsOptimized * pipValue;
   if(optimizedDistance < minDistance) optimizedDistance = minDistance;

   return isLong ? (entryPrice - optimizedDistance) : (entryPrice + optimizedDistance);
}

//+------------------------------------------------------------------+
//| Execute Long Entry                                                |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   double ask = symbolInfo.Ask();
   double atrM1 = GetATR(atrHandleM1, 1);
   double atrH1 = GetATR(atrHandleH1, 1);

   double baseSL = ask - atrM1 * InpATRMultiplierSL;
   double sl = GetOptimizedSL(baseSL, ask, true);

   double slDistance = ask - sl;
   double minSL = InpMinSLPips * pipValue;
   double maxSL = InpMaxSLPips * pipValue;

   if(slDistance < minSL) { sl = ask - minSL; slDistance = minSL; }
   else if(slDistance > maxSL) { sl = ask - maxSL; slDistance = maxSL; }

   double tp = ask + atrH1 * InpATRMultiplierTP;
   if(atrH1 == 0) tp = ask + slDistance * InpRiskRewardRatio;

   sl = NormalizeDouble(sl, symbolInfo.Digits());
   tp = NormalizeDouble(tp, symbolInfo.Digits());

   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0) { Print("No risk capacity!"); return; }

   double tradeRisk = CalculateLossPerLot(slDistance) * lotSize;

   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;
      lastTradeBarTime = iTime(_Symbol, InpEntryTimeframe, 0);
      g_entryPrice = ask;
      g_currentSL = sl;
      g_breakEvenApplied = false;

      Print("LONG: Lot=", lotSize, " Risk=", DoubleToString(tradeRisk, 0), " JPY",
            g_lotReductionActive ? " [REDUCED]" : "");
   }
}

//+------------------------------------------------------------------+
//| Execute Short Entry                                               |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
   double bid = symbolInfo.Bid();
   double atrM1 = GetATR(atrHandleM1, 1);
   double atrH1 = GetATR(atrHandleH1, 1);

   double baseSL = bid + atrM1 * InpATRMultiplierSL;
   double sl = GetOptimizedSL(baseSL, bid, false);

   double slDistance = sl - bid;
   double minSL = InpMinSLPips * pipValue;
   double maxSL = InpMaxSLPips * pipValue;

   if(slDistance < minSL) { sl = bid + minSL; slDistance = minSL; }
   else if(slDistance > maxSL) { sl = bid + maxSL; slDistance = maxSL; }

   double tp = bid - atrH1 * InpATRMultiplierTP;
   if(atrH1 == 0) tp = bid - slDistance * InpRiskRewardRatio;

   sl = NormalizeDouble(sl, symbolInfo.Digits());
   tp = NormalizeDouble(tp, symbolInfo.Digits());

   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0) { Print("No risk capacity!"); return; }

   double tradeRisk = CalculateLossPerLot(slDistance) * lotSize;

   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;
      lastTradeBarTime = iTime(_Symbol, InpEntryTimeframe, 0);
      g_entryPrice = bid;
      g_currentSL = sl;
      g_breakEvenApplied = false;

      Print("SHORT: Lot=", lotSize, " Risk=", DoubleToString(tradeRisk, 0), " JPY",
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

   int currentMin = dt.hour * 60 + dt.min;
   int startMin = InpStartHour * 60 + InpStartMinute;
   int endMin = InpEndHour * 60 + InpEndMinute;

   if(startMin < endMin)
      return (currentMin >= startMin && currentMin < endMin);
   return (currentMin >= startMin || currentMin < endMin);
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
               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

               if(entry == DEAL_ENTRY_OUT)
               {
                  if(profit < 0)
                  {
                     consecutiveLosses++;
                     Print("Loss recorded. Consecutive losses: ", consecutiveLosses);
                  }
                  else if(profit > 0)
                  {
                     consecutiveLosses = 0;
                     Print("Win recorded. Consecutive losses reset.");
                  }
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
