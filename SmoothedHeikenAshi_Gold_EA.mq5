//+------------------------------------------------------------------+
//|                                   SmoothedHeikenAshi_Gold_EA.mq5 |
//|                                  Smoothed Heiken Ashi Strategy EA |
//|                                       For XAUUSD (Gold) Trading   |
//|                                    Fintokei Challenge Compliant   |
//|                              Multi-Timeframe Edition (M1/H1/H4)   |
//|                                                        v3.10      |
//+------------------------------------------------------------------+
#property copyright "Smoothed Heiken Ashi Gold EA v3.10 - MTF Fintokei Edition"
#property link      ""
#property version   "3.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Multi-Timeframe Settings (NEW) ==="
input ENUM_TIMEFRAMES    InpEntryTimeframe     = PERIOD_M1;        // Entry Timeframe (M1 for precision)
input ENUM_TIMEFRAMES    InpTrendTF1           = PERIOD_H1;        // Trend Timeframe 1 (H1)
input ENUM_TIMEFRAMES    InpTrendTF2           = PERIOD_H4;        // Trend Timeframe 2 (H4)
input int                InpTrendConfirmBars   = 2;                // Trend Confirm Bars (Higher TF)
input bool               InpRequireBothTFAlign = true;             // Require Both TF Trend Alignment

input group "=== Fintokei Risk Management (CRITICAL) ==="
input double             InpInitialCapital     = 2000000.0;        // Initial Capital (JPY) - Set Your Plan Size
input double             InpDailyLossLimit     = 5.0;              // Daily Loss Limit (%) - Fintokei: 5%
input double             InpOverallLossLimit   = 10.0;             // Overall Loss Limit (%) - Fintokei: 10%
input double             InpMaxRiskPerTrade    = 3.0;              // Max Risk Per Trade (%) - Recommended: 3%
input double             InpSafetyBuffer       = 0.5;              // Safety Buffer (%) - Extra margin before limit
input bool               InpAutoCloseOnRisk    = true;             // Auto-Close Positions Near Limit
input int                InpServerUTCOffset    = 0;                // Server UTC Offset (hours)

input group "=== Lot Size Optimization (High Lot Strategy) ==="
input bool               InpUseTightSL         = true;             // Use Tight SL for Higher Lots
input double             InpTightSLMultiplier  = 0.6;              // Tight SL Multiplier (0.5-0.8)
input double             InpMinSLPipsOptimized = 150.0;            // Min SL for Optimized Entry [Gold: 150=$1.5]

input group "=== Smoothed Heiken Ashi Settings ==="
input int                InpSmoothingLength    = 15;               // Smoothing Length
input int                InpSHAConfirmBars     = 2;                // SHA Consecutive Bars for Entry (M1)

input group "=== Entry Conditions (M1) ==="
input double             InpPullbackPips       = 100.0;            // Pullback Tolerance (Pips) [Gold: 100=$1]
input bool               InpRequireBounce      = true;             // Require Bounce Confirmation
input int                InpBounceStrength     = 1;                // Bounce Strength (1=Weak, 2=Medium, 3=Strong)
input int                InpPullbackBars       = 10;               // Max Bars to Wait for Pullback

input group "=== ATR Filter Settings ==="
input bool               InpUseATRFilter       = true;             // Use ATR Filter
input int                InpATRPeriod          = 14;               // ATR Period
input double             InpATRMultiplierSL    = 1.0;              // ATR Multiplier for SL (M1)
input double             InpATRMultiplierTP    = 2.0;              // ATR Multiplier for TP
input double             InpMinATRPips         = 50.0;             // Min ATR (Pips) [M1: 50=$0.5]
input double             InpMaxATRPips         = 500.0;            // Max ATR (Pips) [M1: 500=$5]

input group "=== ADX Filter Settings ==="
input bool               InpUseADXFilter       = true;             // Use ADX Filter (on Trend TF)
input int                InpADXPeriod          = 14;               // ADX Period
input double             InpMinADX             = 20.0;             // Minimum ADX for Entry
input double             InpMaxADX             = 50.0;             // Maximum ADX (Avoid Overextended)

input group "=== Short Trade Settings ==="
input bool               InpEnableShort        = true;             // Enable Short Trades

input group "=== Money Management ==="
input double             InpRiskPercent        = 2.0;              // Risk Percent of Balance (0 = Fixed Lot)
input double             InpFixedLot           = 0.1;              // Fixed Lot Size (if Risk% = 0)
input double             InpRiskRewardRatio    = 2.0;              // Risk:Reward Ratio
input double             InpMinSLPips          = 100.0;            // Min SL Distance (Pips) [M1: 100=$1]
input double             InpMaxSLPips          = 500.0;            // Max SL Distance (Pips) [M1: 500=$5]

input group "=== Trading Filters ==="
input int                InpMaxSpreadPips      = 30;               // Maximum Spread (Pips, 0=Disable)
input int                InpSlippage           = 50;               // Slippage (Points)
input int                InpMaxDailyTrades     = 5;                // Max Trades Per Day (0=Unlimited)
input int                InpMinBarsBetweenTrades = 30;             // Min Bars Between Trades (M1)

input group "=== Time Filter ==="
input bool               InpUseTimeFilter      = true;             // Use Time Filter
input int                InpStartHour          = 9;                // Start Hour (Server Time)
input int                InpStartMinute        = 0;                // Start Minute
input int                InpEndHour            = 21;               // End Hour (Server Time)
input int                InpEndMinute          = 0;                // End Minute
input bool               InpAvoidFriday        = true;             // Avoid Trading on Friday After 18:00

input group "=== General Settings ==="
input ulong              InpMagicNumber        = 202412004;        // Magic Number
input string             InpTradeComment       = "SHA_MTF_v3.1";   // Trade Comment
input bool               InpDebugMode          = true;             // Debug Mode

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CSymbolInfo    symbolInfo;

// Smoothed Heiken Ashi Buffers (for each timeframe)
double shaOpenM1[], shaHighM1[], shaLowM1[], shaCloseM1[], shaColorM1[];
double shaOpenH1[], shaHighH1[], shaLowH1[], shaCloseH1[], shaColorH1[];
double shaOpenH4[], shaHighH4[], shaLowH4[], shaCloseH4[], shaColorH4[];

// Indicator Handles
int atrHandleM1 = INVALID_HANDLE;
int atrHandleH1 = INVALID_HANDLE;
int adxHandleH1 = INVALID_HANDLE;

// Pip value for normalization
double pipValue = 0.01;

// Daily trade counter
int dailyTradeCount = 0;
datetime lastTradeDate = 0;
datetime lastTradeBarTime = 0;

// ===== Fintokei Risk Management Variables =====
double g_initialCapital = 0;
double g_dailyStartEquity = 0;
datetime g_lastDailyReset = 0;
double g_dailyLossLimit = 0;
double g_overallLossLimit = 0;
double g_maxDrawdownToday = 0;
bool g_tradingAllowed = true;

// Trend direction cache
int g_trendH1 = 0;  // 1=Bullish, -1=Bearish, 0=Neutral
int g_trendH4 = 0;

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
   if(digits == 2)
      pipValue = 0.01;
   else if(digits == 3)
      pipValue = 0.001;
   else if(digits == 5)
      pipValue = 0.00001;
   else if(digits == 4)
      pipValue = 0.0001;
   else
      pipValue = symbolInfo.Point();

   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("Warning: This EA is optimized for XAUUSD (Gold). Current symbol: ", _Symbol);
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetMarginMode();

   // Set arrays as series
   ArraySetAsSeries(shaOpenM1, true); ArraySetAsSeries(shaHighM1, true);
   ArraySetAsSeries(shaLowM1, true); ArraySetAsSeries(shaCloseM1, true);
   ArraySetAsSeries(shaColorM1, true);

   ArraySetAsSeries(shaOpenH1, true); ArraySetAsSeries(shaHighH1, true);
   ArraySetAsSeries(shaLowH1, true); ArraySetAsSeries(shaCloseH1, true);
   ArraySetAsSeries(shaColorH1, true);

   ArraySetAsSeries(shaOpenH4, true); ArraySetAsSeries(shaHighH4, true);
   ArraySetAsSeries(shaLowH4, true); ArraySetAsSeries(shaCloseH4, true);
   ArraySetAsSeries(shaColorH4, true);

   // Create indicator handles for M1
   atrHandleM1 = iATR(_Symbol, InpEntryTimeframe, InpATRPeriod);
   if(atrHandleM1 == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle for M1!");
      return INIT_FAILED;
   }

   // Create ATR handle for H1 (for SL/TP calculation)
   atrHandleH1 = iATR(_Symbol, InpTrendTF1, InpATRPeriod);
   if(atrHandleH1 == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle for H1!");
      return INIT_FAILED;
   }

   if(InpUseADXFilter)
   {
      adxHandleH1 = iADX(_Symbol, InpTrendTF1, InpADXPeriod);
      if(adxHandleH1 == INVALID_HANDLE)
      {
         Print("Failed to create ADX handle!");
         return INIT_FAILED;
      }
   }

   InitializeFintokeiRiskManagement();

   Print("==============================================");
   Print("SmoothedHeikenAshi Gold EA v3.10 - MTF EDITION");
   Print("==============================================");
   Print("Symbol: ", _Symbol, " | Digits: ", digits);
   Print("----------------------------------------------");
   Print("MULTI-TIMEFRAME SETTINGS:");
   Print("  Entry TF: ", EnumToString(InpEntryTimeframe), " (M1)");
   Print("  Trend TF1: ", EnumToString(InpTrendTF1), " (H1)");
   Print("  Trend TF2: ", EnumToString(InpTrendTF2), " (H4)");
   Print("  Require Both TF Align: ", InpRequireBothTFAlign ? "YES" : "NO");
   Print("----------------------------------------------");
   Print("FINTOKEI RISK SETTINGS:");
   Print("  Initial Capital: ", DoubleToString(g_initialCapital, 0), " JPY");
   Print("  Daily Loss Limit: ", InpDailyLossLimit, "%");
   Print("  Overall Loss Limit: ", InpOverallLossLimit, "%");
   Print("  Max Risk Per Trade: ", InpMaxRiskPerTrade, "%");
   Print("----------------------------------------------");
   Print("Debug Mode: ", InpDebugMode ? "ON" : "OFF");
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Initialize Fintokei Risk Management                               |
//+------------------------------------------------------------------+
void InitializeFintokeiRiskManagement()
{
   if(InpInitialCapital > 0)
      g_initialCapital = InpInitialCapital;
   else
      g_initialCapital = AccountInfoDouble(ACCOUNT_BALANCE);

   g_overallLossLimit = g_initialCapital * (InpOverallLossLimit / 100.0);
   ResetDailyRiskTracking();
}

//+------------------------------------------------------------------+
//| Reset Daily Risk Tracking                                         |
//+------------------------------------------------------------------+
void ResetDailyRiskTracking()
{
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyLossLimit = g_dailyStartEquity * (InpDailyLossLimit / 100.0);
   g_maxDrawdownToday = 0;
   g_lastDailyReset = GetUTCDate();
   g_tradingAllowed = true;

   Print("=== DAILY RISK RESET ===");
   Print("Start Equity: ", DoubleToString(g_dailyStartEquity, 0), " JPY");
   Print("Daily Loss Limit: ", DoubleToString(g_dailyLossLimit, 0), " JPY");
}

//+------------------------------------------------------------------+
//| Get Current UTC Date                                              |
//+------------------------------------------------------------------+
datetime GetUTCDate()
{
   datetime serverTime = TimeCurrent();
   datetime utcTime = serverTime - InpServerUTCOffset * 3600;
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);
   return StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
}

//+------------------------------------------------------------------+
//| Check if New UTC Day                                              |
//+------------------------------------------------------------------+
bool IsNewUTCDay()
{
   return (GetUTCDate() != g_lastDailyReset);
}

//+------------------------------------------------------------------+
//| Monitor Fintokei Risk Limits                                      |
//+------------------------------------------------------------------+
bool MonitorFintokeiRiskLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(IsNewUTCDay())
      ResetDailyRiskTracking();

   // Check Overall Loss Limit (10%)
   double overallDrawdown = g_initialCapital - currentEquity;
   double overallFailLine = g_initialCapital - g_overallLossLimit;
   double safetyMargin = g_initialCapital * (InpSafetyBuffer / 100.0);

   if(currentEquity <= overallFailLine + safetyMargin)
   {
      Print("!!! CRITICAL: Approaching Overall Loss Limit !!!");
      if(InpAutoCloseOnRisk && HasOpenPosition())
         CloseAllPositions();
      g_tradingAllowed = false;
      return false;
   }

   // Check Daily Loss Limit (5%)
   double dailyDrawdown = g_dailyStartEquity - currentEquity;
   double dailyFailLine = g_dailyStartEquity - g_dailyLossLimit;
   double dailySafetyMargin = g_dailyStartEquity * (InpSafetyBuffer / 100.0);

   if(dailyDrawdown > g_maxDrawdownToday)
      g_maxDrawdownToday = dailyDrawdown;

   if(currentEquity <= dailyFailLine + dailySafetyMargin)
   {
      Print("!!! WARNING: Approaching Daily Loss Limit !!!");
      if(InpAutoCloseOnRisk && HasOpenPosition())
         CloseAllPositions();
      g_tradingAllowed = false;
      return false;
   }

   g_tradingAllowed = true;
   return true;
}

//+------------------------------------------------------------------+
//| Get Maximum Allowed Risk                                          |
//+------------------------------------------------------------------+
double GetMaxAllowedRisk()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   double dailyDrawdown = g_dailyStartEquity - currentEquity;
   double dailyRemaining = g_dailyLossLimit - dailyDrawdown;
   double dailySafetyMargin = g_dailyStartEquity * (InpSafetyBuffer / 100.0);

   double overallDrawdown = g_initialCapital - currentEquity;
   double overallRemaining = g_overallLossLimit - overallDrawdown;
   double overallSafetyMargin = g_initialCapital * (InpSafetyBuffer / 100.0);

   double maxRiskAmount = MathMin(dailyRemaining - dailySafetyMargin,
                                   overallRemaining - overallSafetyMargin);

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
            Print("Emergency closed position #", positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandleM1 != INVALID_HANDLE) IndicatorRelease(atrHandleM1);
   if(atrHandleH1 != INVALID_HANDLE) IndicatorRelease(atrHandleH1);
   if(adxHandleH1 != INVALID_HANDLE) IndicatorRelease(adxHandleH1);

   Print("=== Final Report ===");
   Print("Max Drawdown Today: ", DoubleToString(g_maxDrawdownToday, 0), " JPY");
   Print("Final Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 0), " JPY");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Fintokei risk monitoring
   if(!MonitorFintokeiRiskLimits())
      return;

   // Check for new M1 bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpEntryTimeframe, 0);

   if(lastBarTime == currentBarTime)
      return;

   lastBarTime = currentBarTime;

   // Reset daily counter
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(currentDate != lastTradeDate)
   {
      dailyTradeCount = 0;
      lastTradeDate = currentDate;
   }

   if(!symbolInfo.RefreshRates())
      return;

   // Check spread
   double currentSpreadPips = symbolInfo.Spread() * symbolInfo.Point() / pipValue;
   if(InpMaxSpreadPips > 0 && currentSpreadPips > InpMaxSpreadPips)
      return;

   // Time filter
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

   if(InpAvoidFriday && IsFridayEvening())
      return;

   // Trade limit
   if(InpMaxDailyTrades > 0 && dailyTradeCount >= InpMaxDailyTrades)
      return;

   // Min bars between trades
   if(lastTradeBarTime > 0)
   {
      int barsSinceTrade = iBarShift(_Symbol, InpEntryTimeframe, lastTradeBarTime);
      if(barsSinceTrade < InpMinBarsBetweenTrades)
         return;
   }

   // Check if position exists
   if(HasOpenPosition())
      return;

   // Calculate SHA for all timeframes
   if(!CalculateAllSHA())
      return;

   // Determine higher TF trends
   UpdateTrendDirections();

   // Execute trading logic
   ProcessTradingLogic();
}

//+------------------------------------------------------------------+
//| Calculate Smoothed Heiken Ashi for All Timeframes                 |
//+------------------------------------------------------------------+
bool CalculateAllSHA()
{
   if(!CalculateSHA(InpEntryTimeframe, shaOpenM1, shaHighM1, shaLowM1, shaCloseM1, shaColorM1))
      return false;

   if(!CalculateSHA(InpTrendTF1, shaOpenH1, shaHighH1, shaLowH1, shaCloseH1, shaColorH1))
      return false;

   if(!CalculateSHA(InpTrendTF2, shaOpenH4, shaHighH4, shaLowH4, shaCloseH4, shaColorH4))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Calculate Smoothed Heiken Ashi for Specific Timeframe             |
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
      shaColor[i] = (shaClose[i] >= shaOpen[i]) ? 0.0 : 1.0;  // 0=Bullish, 1=Bearish
   }

   return true;
}

//+------------------------------------------------------------------+
//| Update Trend Directions from Higher Timeframes                    |
//+------------------------------------------------------------------+
void UpdateTrendDirections()
{
   // Check H1 trend
   g_trendH1 = GetTrendDirection(shaColorH1, InpTrendConfirmBars);

   // Check H4 trend
   g_trendH4 = GetTrendDirection(shaColorH4, InpTrendConfirmBars);

   if(InpDebugMode)
   {
      static datetime lastLogTime = 0;
      if(TimeCurrent() - lastLogTime >= 300)
      {
         string h1Trend = (g_trendH1 == 1) ? "BULLISH" : (g_trendH1 == -1) ? "BEARISH" : "NEUTRAL";
         string h4Trend = (g_trendH4 == 1) ? "BULLISH" : (g_trendH4 == -1) ? "BEARISH" : "NEUTRAL";
         Print("Trend Status - H1: ", h1Trend, " | H4: ", h4Trend);
         lastLogTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| Get Trend Direction from SHA Color                                |
//+------------------------------------------------------------------+
int GetTrendDirection(double &shaColor[], int confirmBars)
{
   // Check for bullish (all bars = 0)
   bool allBullish = true;
   bool allBearish = true;

   for(int i = 1; i <= confirmBars; i++)
   {
      if(i >= ArraySize(shaColor)) return 0;

      if(shaColor[i] != 0.0) allBullish = false;
      if(shaColor[i] != 1.0) allBearish = false;
   }

   if(allBullish) return 1;   // Bullish
   if(allBearish) return -1;  // Bearish
   return 0;  // Neutral/Mixed
}

//+------------------------------------------------------------------+
//| Check if Both Timeframes Align                                    |
//+------------------------------------------------------------------+
bool AreTrendsAligned(int requiredDirection)
{
   if(InpRequireBothTFAlign)
   {
      return (g_trendH1 == requiredDirection && g_trendH4 == requiredDirection);
   }
   else
   {
      // At least one must match
      return (g_trendH1 == requiredDirection || g_trendH4 == requiredDirection);
   }
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                     |
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
   if(!GetADXValues(adx, plusDI, minusDI))
      return true;

   if(adx < InpMinADX || adx > InpMaxADX)
      return false;

   if(isLong && plusDI <= minusDI)
      return false;

   if(!isLong && minusDI <= plusDI)
      return false;

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

   if(atrPips < InpMinATRPips || atrPips > InpMaxATRPips)
   {
      if(InpDebugMode)
         Print("ATR out of range: ", DoubleToString(atrPips, 1), " pips");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Get SHA Middle (M1)                                               |
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
   // Check M1 SHA confirms direction
   for(int i = 1; i <= InpSHAConfirmBars; i++)
   {
      if(i >= ArraySize(shaColorM1)) return false;

      if(isLong && shaColorM1[i] != 0.0) return false;  // Need bullish
      if(!isLong && shaColorM1[i] != 1.0) return false; // Need bearish
   }

   // Check price is on correct side of SHA
   double currentClose = iClose(_Symbol, InpEntryTimeframe, 1);
   double shaMiddle = GetSHAMiddleM1(1);

   if(isLong && currentClose <= shaMiddle) return false;
   if(!isLong && currentClose >= shaMiddle) return false;

   // Check for pullback
   if(!DetectPullbackM1(isLong))
      return false;

   // Check bounce if required
   if(InpRequireBounce && !CheckBounceM1(isLong))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Detect Pullback on M1                                             |
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
         double distanceToSHA = barLow - shaMiddle;
         if(distanceToSHA <= tolerance && distanceToSHA >= -tolerance * 0.5)
         {
            if(barClose > shaMiddle)
               return true;
         }
      }
      else
      {
         double distanceToSHA = shaMiddle - barHigh;
         if(distanceToSHA <= tolerance && distanceToSHA >= -tolerance * 0.5)
         {
            if(barClose < shaMiddle)
               return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check Bounce on M1                                                |
//+------------------------------------------------------------------+
bool CheckBounceM1(bool isLong)
{
   double open1 = iOpen(_Symbol, InpEntryTimeframe, 1);
   double close1 = iClose(_Symbol, InpEntryTimeframe, 1);
   double high1 = iHigh(_Symbol, InpEntryTimeframe, 1);
   double low1 = iLow(_Symbol, InpEntryTimeframe, 1);

   if(high1 == low1) return false;

   double body = MathAbs(close1 - open1);
   double shaMiddle = GetSHAMiddleM1(1);

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
   if(!g_tradingAllowed)
      return;

   if(!CheckATRFilter())
      return;

   // ===== LONG SETUP =====
   // Check if H1 and H4 are both bullish
   if(AreTrendsAligned(1))  // 1 = Bullish
   {
      if(CheckADXFilter(true))
      {
         if(CheckM1EntrySignal(true))
         {
            Print("=================================================");
            Print("LONG ENTRY - MTF Aligned (H4+H1 Bullish, M1 Entry)");
            Print("=================================================");
            ExecuteLongEntry();
            return;
         }
      }
   }

   // ===== SHORT SETUP =====
   if(!InpEnableShort)
      return;

   // Check if H1 and H4 are both bearish
   if(AreTrendsAligned(-1))  // -1 = Bearish
   {
      if(CheckADXFilter(false))
      {
         if(CheckM1EntrySignal(false))
         {
            Print("=================================================");
            Print("SHORT ENTRY - MTF Aligned (H4+H1 Bearish, M1 Entry)");
            Print("=================================================");
            ExecuteShortEntry();
            return;
         }
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
//| Calculate Fintokei Lot Size                                       |
//+------------------------------------------------------------------+
double CalculateFintokeiLotSize(double slDistance)
{
   double maxRiskAmount = GetMaxAllowedRisk();
   if(maxRiskAmount <= 0) return 0;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double desiredRisk = currentEquity * (InpRiskPercent / 100.0);
   double riskAmount = MathMin(desiredRisk, maxRiskAmount);

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
   if(!InpUseTightSL)
      return baseSL;

   double baseDistance = isLong ? (entryPrice - baseSL) : (baseSL - entryPrice);
   double optimizedDistance = baseDistance * InpTightSLMultiplier;

   double minDistance = InpMinSLPipsOptimized * pipValue;
   if(optimizedDistance < minDistance)
      optimizedDistance = minDistance;

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

   // Use M1 ATR for tighter SL
   double baseSL = ask - atrM1 * InpATRMultiplierSL;
   double sl = GetOptimizedSL(baseSL, ask, true);

   double slDistance = ask - sl;
   double minSL = InpMinSLPips * pipValue;
   double maxSL = InpMaxSLPips * pipValue;

   if(slDistance < minSL)
   {
      sl = ask - minSL;
      slDistance = minSL;
   }
   else if(slDistance > maxSL)
   {
      sl = ask - maxSL;
      slDistance = maxSL;
   }

   // Use H1 ATR for TP (bigger moves)
   double tp = ask + atrH1 * InpATRMultiplierTP;
   if(atrH1 == 0)
      tp = ask + slDistance * InpRiskRewardRatio;

   int digits = symbolInfo.Digits();
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lotSize = CalculateFintokeiLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("Cannot open trade: No risk capacity!");
      return;
   }

   double tradeRisk = CalculateLossPerLot(slDistance) * lotSize;
   double maxAllowed = GetMaxAllowedRisk();

   if(tradeRisk > maxAllowed)
   {
      Print("Trade risk exceeds limit!");
      return;
   }

   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;
      lastTradeBarTime = iTime(_Symbol, InpEntryTimeframe, 0);

      Print("========================================");
      Print("LONG OPENED (MTF Strategy)");
      Print("Entry: ", ask, " | SL: ", sl, " | TP: ", tp);
      Print("Lot: ", lotSize, " | Risk: ", DoubleToString(tradeRisk, 0), " JPY");
      Print("H1 Trend: BULLISH | H4 Trend: BULLISH");
      Print("========================================");
   }
   else
   {
      Print("Failed to open Long! Error: ", GetLastError());
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

   if(slDistance < minSL)
   {
      sl = bid + minSL;
      slDistance = minSL;
   }
   else if(slDistance > maxSL)
   {
      sl = bid + maxSL;
      slDistance = maxSL;
   }

   double tp = bid - atrH1 * InpATRMultiplierTP;
   if(atrH1 == 0)
      tp = bid - slDistance * InpRiskRewardRatio;

   int digits = symbolInfo.Digits();
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lotSize = CalculateFintokeiLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("Cannot open trade: No risk capacity!");
      return;
   }

   double tradeRisk = CalculateLossPerLot(slDistance) * lotSize;
   double maxAllowed = GetMaxAllowedRisk();

   if(tradeRisk > maxAllowed)
   {
      Print("Trade risk exceeds limit!");
      return;
   }

   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;
      lastTradeBarTime = iTime(_Symbol, InpEntryTimeframe, 0);

      Print("========================================");
      Print("SHORT OPENED (MTF Strategy)");
      Print("Entry: ", bid, " | SL: ", sl, " | TP: ", tp);
      Print("Lot: ", lotSize, " | Risk: ", DoubleToString(tradeRisk, 0), " JPY");
      Print("H1 Trend: BEARISH | H4 Trend: BEARISH");
      Print("========================================");
   }
   else
   {
      Print("Failed to open Short! Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check if we have an open position                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);

   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int startMinutes = InpStartHour * 60 + InpStartMinute;
   int endMinutes = InpEndHour * 60 + InpEndMinute;

   if(startMinutes < endMinutes)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   else
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
}

//+------------------------------------------------------------------+
//| Check if Friday Evening                                           |
//+------------------------------------------------------------------+
bool IsFridayEvening()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   return (currentTime.day_of_week == 5 && currentTime.hour >= 18);
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
}
//+------------------------------------------------------------------+
