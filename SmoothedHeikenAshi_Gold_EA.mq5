//+------------------------------------------------------------------+
//|                                   SmoothedHeikenAshi_Gold_EA.mq5 |
//|                                  Smoothed Heiken Ashi Strategy EA |
//|                                       For XAUUSD (Gold) Trading   |
//|                                                        v2.00      |
//+------------------------------------------------------------------+
#property copyright "Smoothed Heiken Ashi Gold EA v2.0"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Smoothed Heiken Ashi Settings ==="
input int                InpSmoothingLength    = 15;              // Smoothing Length
input ENUM_TIMEFRAMES    InpTimeframe          = PERIOD_H1;       // Timeframe (H1 Recommended)
input int                InpSHAConfirmBars     = 3;               // SHA Consecutive Bars for Trend Confirmation

input group "=== Breakout Detection Settings ==="
input int                InpLookbackPeriod     = 30;              // Lookback Period for Support/Resistance
input int                InpBreakoutLookback   = 8;               // Bars to Check for Breakout
input double             InpBreakoutPips       = 200.0;           // Breakout Buffer (Pips) [Gold: 200=$2]

input group "=== Pullback Detection Settings ==="
input int                InpPullbackBars       = 12;              // Max Bars to Wait for Pullback
input double             InpPullbackPips       = 500.0;           // Pullback Tolerance (Pips) [Gold: 500=$5]
input bool               InpRequireBounce      = true;            // Require Bounce Confirmation
input int                InpBounceStrength     = 2;               // Bounce Strength (1=Weak, 2=Medium, 3=Strong)

input group "=== ATR Filter Settings ==="
input bool               InpUseATRFilter       = true;            // Use ATR Filter
input int                InpATRPeriod          = 14;              // ATR Period
input double             InpATRMultiplierSL    = 1.5;             // ATR Multiplier for SL
input double             InpATRMultiplierTP    = 3.0;             // ATR Multiplier for TP
input double             InpMinATRPips         = 300.0;           // Min ATR (Pips) [Gold H1: 300=$3, skip low vol]
input double             InpMaxATRPips         = 5000.0;          // Max ATR (Pips) [Gold H1: 5000=$50, skip extreme]

input group "=== ADX Filter Settings ==="
input bool               InpUseADXFilter       = true;            // Use ADX Filter
input int                InpADXPeriod          = 14;              // ADX Period
input double             InpMinADX             = 20.0;            // Minimum ADX for Long Entry
input double             InpMinADXShort        = 25.0;            // Minimum ADX for Short Entry (Higher = Stricter)
input double             InpMaxADX             = 50.0;            // Maximum ADX (Avoid Overextended)

input group "=== Short Trade Settings ==="
input bool               InpEnableShort        = true;            // Enable Short Trades
input int                InpShortConfirmBars   = 4;               // SHA Bearish Bars for Short (More = Stricter)
input int                InpShortBounceStrength = 3;              // Short Bounce Strength (1-3, Higher = Stricter)

input group "=== Money Management ==="
input double             InpRiskPercent        = 1.0;             // Risk Percent of Balance (0 = Fixed Lot)
input double             InpFixedLot           = 0.1;             // Fixed Lot Size (if Risk% = 0)
input double             InpRiskRewardRatio    = 2.0;             // Risk:Reward Ratio (Used if ATR TP disabled)
input bool               InpUseATRForSLTP      = true;            // Use ATR for SL/TP Calculation
input double             InpMinSLPips          = 300.0;           // Min SL Distance (Pips) [Gold: 300=$3]
input double             InpMaxSLPips          = 2000.0;          // Max SL Distance (Pips) [Gold: 2000=$20]

input group "=== Trading Filters ==="
input int                InpMaxSpreadPips      = 30;              // Maximum Spread (Pips, 0=Disable)
input int                InpSlippage           = 50;              // Slippage (Points)
input int                InpMaxDailyTrades     = 3;               // Max Trades Per Day (0=Unlimited)

input group "=== Time Filter ==="
input bool               InpUseTimeFilter      = true;            // Use Time Filter
input int                InpStartHour          = 8;               // Start Hour (Server Time)
input int                InpStartMinute        = 0;               // Start Minute
input int                InpEndHour            = 20;              // End Hour (Server Time)
input int                InpEndMinute          = 0;               // End Minute
input bool               InpAvoidFriday        = true;            // Avoid Trading on Friday After 18:00

input group "=== General Settings ==="
input ulong              InpMagicNumber        = 202412002;       // Magic Number
input string             InpTradeComment       = "SHA_Gold_v2";   // Trade Comment
input bool               InpDebugMode          = true;            // Debug Mode

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CSymbolInfo    symbolInfo;

// Smoothed Heiken Ashi Buffers
double shaOpen[];
double shaHigh[];
double shaLow[];
double shaClose[];
double shaColor[];  // 0 = White (Bullish), 1 = Pink (Bearish)

// Indicator Handles
int atrHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;

// Pip value for normalization
double pipValue = 0.01;

// Daily trade counter
int dailyTradeCount = 0;
datetime lastTradeDate = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to get symbol info!");
      return INIT_FAILED;
   }

   // Determine pip value based on symbol
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

   // Check if trading on XAUUSD
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("Warning: This EA is optimized for XAUUSD (Gold). Current symbol: ", _Symbol);
   }

   // Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetMarginMode();

   // Allocate arrays
   ArraySetAsSeries(shaOpen, true);
   ArraySetAsSeries(shaHigh, true);
   ArraySetAsSeries(shaLow, true);
   ArraySetAsSeries(shaClose, true);
   ArraySetAsSeries(shaColor, true);

   // Create indicator handles
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;

   if(InpUseATRFilter || InpUseATRForSLTP)
   {
      atrHandle = iATR(_Symbol, tf, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle!");
         return INIT_FAILED;
      }
   }

   if(InpUseADXFilter)
   {
      adxHandle = iADX(_Symbol, tf, InpADXPeriod);
      if(adxHandle == INVALID_HANDLE)
      {
         Print("Failed to create ADX handle!");
         return INIT_FAILED;
      }
   }

   Print("==============================================");
   Print("SmoothedHeikenAshi Gold EA v2.00 Initialized");
   Print("==============================================");
   Print("Symbol: ", _Symbol, " | Digits: ", digits);
   Print("Timeframe: ", EnumToString(tf), " (H1 Recommended)");
   Print("Pip Value: ", pipValue);
   Print("----------------------------------------------");
   Print("SHA Smoothing: ", InpSmoothingLength, " | Confirm Bars: ", InpSHAConfirmBars);
   Print("Breakout: ", InpBreakoutPips, " pips | Pullback: ", InpPullbackPips, " pips");
   Print("----------------------------------------------");
   Print("ATR Filter: ", InpUseATRFilter ? "ON" : "OFF", " | Period: ", InpATRPeriod);
   Print("ADX Filter: ", InpUseADXFilter ? "ON" : "OFF", " | Min: ", InpMinADX, " Max: ", InpMaxADX);
   Print("----------------------------------------------");
   Print("Max Spread: ", InpMaxSpreadPips, " pips");
   Print("Time Filter: ", InpUseTimeFilter ? "ON" : "OFF");
   Print("Debug Mode: ", InpDebugMode ? "ON" : "OFF");
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   if(adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);

   Print("SmoothedHeikenAshi Gold EA v2.0 deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   static datetime lastBarTime = 0;
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   datetime currentBarTime = iTime(_Symbol, tf, 0);

   if(lastBarTime == currentBarTime)
      return;

   lastBarTime = currentBarTime;

   // Reset daily trade counter
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(currentDate != lastTradeDate)
   {
      dailyTradeCount = 0;
      lastTradeDate = currentDate;
   }

   // Update symbol info
   if(!symbolInfo.RefreshRates())
      return;

   // Check spread
   double currentSpreadPips = symbolInfo.Spread() * symbolInfo.Point() / pipValue;
   if(InpMaxSpreadPips > 0 && currentSpreadPips > InpMaxSpreadPips)
   {
      if(InpDebugMode)
         Print("Spread too high: ", DoubleToString(currentSpreadPips, 1), " pips");
      return;
   }

   // Check time filter
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

   // Check Friday filter
   if(InpAvoidFriday && IsFridayEvening())
      return;

   // Check daily trade limit
   if(InpMaxDailyTrades > 0 && dailyTradeCount >= InpMaxDailyTrades)
   {
      if(InpDebugMode)
         Print("Daily trade limit reached: ", dailyTradeCount);
      return;
   }

   // Calculate Smoothed Heiken Ashi
   if(!CalculateSmoothedHeikenAshi())
   {
      Print("Failed to calculate Smoothed Heiken Ashi!");
      return;
   }

   // Check if we have an open position
   if(HasOpenPosition())
   {
      ManageOpenPosition();
      return;
   }

   // Execute trading logic
   ProcessTradingLogic();
}

//+------------------------------------------------------------------+
//| Calculate Smoothed Heiken Ashi                                    |
//+------------------------------------------------------------------+
bool CalculateSmoothedHeikenAshi()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   int barsNeeded = InpLookbackPeriod + InpSmoothingLength + InpPullbackBars + 30;

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
//| Get SHA Middle Line                                               |
//+------------------------------------------------------------------+
double GetSHAMiddle(int shift)
{
   if(shift < 0 || shift >= ArraySize(shaOpen)) return 0;
   return (shaOpen[shift] + shaClose[shift]) / 2.0;
}

//+------------------------------------------------------------------+
//| Check if SHA is Bullish for N consecutive bars                    |
//+------------------------------------------------------------------+
bool IsSHABullishConsecutive(int bars)
{
   for(int i = 1; i <= bars; i++)
   {
      if(i >= ArraySize(shaColor)) return false;
      if(shaColor[i] != 0.0) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if SHA is Bearish for N consecutive bars                    |
//+------------------------------------------------------------------+
bool IsSHABearishConsecutive(int bars)
{
   for(int i = 1; i <= bars; i++)
   {
      if(i >= ArraySize(shaColor)) return false;
      if(shaColor[i] != 1.0) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                     |
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
//| Get ADX Value                                                     |
//+------------------------------------------------------------------+
double GetADX(int shift = 1)
{
   if(adxHandle == INVALID_HANDLE) return 0;

   double adx[];
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(adxHandle, 0, shift, 1, adx) <= 0) return 0;

   return adx[0];
}

//+------------------------------------------------------------------+
//| Get +DI Value                                                     |
//+------------------------------------------------------------------+
double GetPlusDI(int shift = 1)
{
   if(adxHandle == INVALID_HANDLE) return 0;

   double plusDI[];
   ArraySetAsSeries(plusDI, true);

   if(CopyBuffer(adxHandle, 1, shift, 1, plusDI) <= 0) return 0;

   return plusDI[0];
}

//+------------------------------------------------------------------+
//| Get -DI Value                                                     |
//+------------------------------------------------------------------+
double GetMinusDI(int shift = 1)
{
   if(adxHandle == INVALID_HANDLE) return 0;

   double minusDI[];
   ArraySetAsSeries(minusDI, true);

   if(CopyBuffer(adxHandle, 2, shift, 1, minusDI) <= 0) return 0;

   return minusDI[0];
}

//+------------------------------------------------------------------+
//| Check ATR Filter                                                  |
//+------------------------------------------------------------------+
bool CheckATRFilter()
{
   if(!InpUseATRFilter) return true;

   double atr = GetATR(1);
   double atrPips = atr / pipValue;

   if(atrPips < InpMinATRPips)
   {
      if(InpDebugMode)
         Print("ATR too low: ", DoubleToString(atrPips, 2), " < ", InpMinATRPips, " pips (Low volatility)");
      return false;
   }

   if(atrPips > InpMaxATRPips)
   {
      if(InpDebugMode)
         Print("ATR too high: ", DoubleToString(atrPips, 2), " > ", InpMaxATRPips, " pips (Extreme volatility)");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check ADX Filter for Long                                         |
//+------------------------------------------------------------------+
bool CheckADXFilterLong()
{
   if(!InpUseADXFilter) return true;

   double adx = GetADX(1);
   double plusDI = GetPlusDI(1);
   double minusDI = GetMinusDI(1);

   // ADX must be in valid range
   if(adx < InpMinADX)
   {
      if(InpDebugMode)
         Print("ADX too low for Long: ", DoubleToString(adx, 2), " < ", InpMinADX, " (Weak trend)");
      return false;
   }

   if(adx > InpMaxADX)
   {
      if(InpDebugMode)
         Print("ADX too high for Long: ", DoubleToString(adx, 2), " > ", InpMaxADX, " (Overextended)");
      return false;
   }

   // +DI must be above -DI for bullish trend
   if(plusDI <= minusDI)
   {
      if(InpDebugMode)
         Print("DI not bullish: +DI=", DoubleToString(plusDI, 2), " -DI=", DoubleToString(minusDI, 2));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check ADX Filter for Short                                        |
//+------------------------------------------------------------------+
bool CheckADXFilterShort()
{
   if(!InpUseADXFilter) return true;

   double adx = GetADX(1);
   double plusDI = GetPlusDI(1);
   double minusDI = GetMinusDI(1);

   // Use stricter ADX minimum for Short trades
   if(adx < InpMinADXShort)
   {
      if(InpDebugMode)
         Print("ADX too low for Short: ", DoubleToString(adx, 2), " < ", InpMinADXShort, " (Weak trend)");
      return false;
   }

   if(adx > InpMaxADX)
   {
      if(InpDebugMode)
         Print("ADX too high for Short: ", DoubleToString(adx, 2), " > ", InpMaxADX, " (Overextended)");
      return false;
   }

   // -DI must be above +DI for bearish trend
   if(minusDI <= plusDI)
   {
      if(InpDebugMode)
         Print("DI not bearish: +DI=", DoubleToString(plusDI, 2), " -DI=", DoubleToString(minusDI, 2));
      return false;
   }

   // Additional check: -DI should be significantly stronger
   double diDiff = minusDI - plusDI;
   if(diDiff < 5.0)
   {
      if(InpDebugMode)
         Print("DI difference too small for Short: ", DoubleToString(diDiff, 2), " < 5.0");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Get Resistance Level (excluding recent bars)                      |
//+------------------------------------------------------------------+
double GetResistanceLevel(int skipBars)
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double highest = 0;

   for(int i = skipBars + 1; i <= skipBars + InpLookbackPeriod; i++)
   {
      double h = iHigh(_Symbol, tf, i);
      if(h > highest) highest = h;
   }

   return highest;
}

//+------------------------------------------------------------------+
//| Get Support Level (excluding recent bars)                         |
//+------------------------------------------------------------------+
double GetSupportLevel(int skipBars)
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double lowest = DBL_MAX;

   for(int i = skipBars + 1; i <= skipBars + InpLookbackPeriod; i++)
   {
      double l = iLow(_Symbol, tf, i);
      if(l < lowest) lowest = l;
   }

   return lowest;
}

//+------------------------------------------------------------------+
//| Check for Valid Bounce (Improved Pullback Detection)              |
//+------------------------------------------------------------------+
bool CheckBounce(bool isLong, int barShift)
{
   if(!InpRequireBounce) return true;

   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;

   double open1 = iOpen(_Symbol, tf, barShift);
   double close1 = iClose(_Symbol, tf, barShift);
   double high1 = iHigh(_Symbol, tf, barShift);
   double low1 = iLow(_Symbol, tf, barShift);
   double range1 = high1 - low1;

   if(range1 == 0) return false;

   double open2 = iOpen(_Symbol, tf, barShift + 1);
   double close2 = iClose(_Symbol, tf, barShift + 1);
   double high2 = iHigh(_Symbol, tf, barShift + 1);
   double low2 = iLow(_Symbol, tf, barShift + 1);

   double shaMiddle = GetSHAMiddle(barShift);

   if(isLong)
   {
      // For Long: Check bullish bounce from SHA
      bool isBullishBar = close1 > open1;
      double lowerWick = MathMin(open1, close1) - low1;
      double upperWick = high1 - MathMax(open1, close1);
      double body = MathAbs(close1 - open1);

      // Bounce strength checks
      bool strongBounce = false;

      switch(InpBounceStrength)
      {
         case 1: // Weak - just need bullish bar
            strongBounce = isBullishBar;
            break;

         case 2: // Medium - bullish bar with lower wick touching SHA area
            strongBounce = isBullishBar &&
                          (low1 <= shaMiddle + InpPullbackPips * pipValue) &&
                          (lowerWick >= body * 0.3);
            break;

         case 3: // Strong - bullish engulfing or strong rejection
            strongBounce = isBullishBar &&
                          (low1 <= shaMiddle + InpPullbackPips * pipValue) &&
                          (lowerWick >= body * 0.5) &&
                          (close1 > high2 || body > MathAbs(close2 - open2));
            break;
      }

      if(InpDebugMode && !strongBounce)
      {
         Print("Bounce check failed (Long): Bullish=", isBullishBar,
               " | LowerWick=", DoubleToString(lowerWick, 2),
               " | Body=", DoubleToString(body, 2));
      }

      return strongBounce;
   }
   else
   {
      // For Short: Check bearish bounce from SHA
      bool isBearishBar = close1 < open1;
      double upperWick = high1 - MathMax(open1, close1);
      double lowerWick = MathMin(open1, close1) - low1;
      double body = MathAbs(close1 - open1);

      bool strongBounce = false;

      switch(InpBounceStrength)
      {
         case 1:
            strongBounce = isBearishBar;
            break;

         case 2:
            strongBounce = isBearishBar &&
                          (high1 >= shaMiddle - InpPullbackPips * pipValue) &&
                          (upperWick >= body * 0.3);
            break;

         case 3:
            strongBounce = isBearishBar &&
                          (high1 >= shaMiddle - InpPullbackPips * pipValue) &&
                          (upperWick >= body * 0.5) &&
                          (close1 < low2 || body > MathAbs(close2 - open2));
            break;
      }

      if(InpDebugMode && !strongBounce)
      {
         Print("Bounce check failed (Short): Bearish=", isBearishBar,
               " | UpperWick=", DoubleToString(upperWick, 2),
               " | Body=", DoubleToString(body, 2));
      }

      return strongBounce;
   }
}

//+------------------------------------------------------------------+
//| Check for Valid Bounce with explicit strength (for Short)         |
//+------------------------------------------------------------------+
bool CheckBounceStrict(bool isLong, int barShift, int strength)
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;

   double open1 = iOpen(_Symbol, tf, barShift);
   double close1 = iClose(_Symbol, tf, barShift);
   double high1 = iHigh(_Symbol, tf, barShift);
   double low1 = iLow(_Symbol, tf, barShift);
   double range1 = high1 - low1;

   if(range1 == 0) return false;

   double open2 = iOpen(_Symbol, tf, barShift + 1);
   double close2 = iClose(_Symbol, tf, barShift + 1);
   double high2 = iHigh(_Symbol, tf, barShift + 1);
   double low2 = iLow(_Symbol, tf, barShift + 1);

   double shaMiddle = GetSHAMiddle(barShift);

   // For Short: Check bearish bounce from SHA with specified strength
   bool isBearishBar = close1 < open1;
   double upperWick = high1 - MathMax(open1, close1);
   double lowerWick = MathMin(open1, close1) - low1;
   double body = MathAbs(close1 - open1);

   bool strongBounce = false;

   switch(strength)
   {
      case 1:
         strongBounce = isBearishBar;
         break;

      case 2:
         strongBounce = isBearishBar &&
                       (high1 >= shaMiddle - InpPullbackPips * pipValue) &&
                       (upperWick >= body * 0.3);
         break;

      case 3:
         // Strictest: Strong bearish engulfing or pin bar
         strongBounce = isBearishBar &&
                       (high1 >= shaMiddle - InpPullbackPips * pipValue) &&
                       (upperWick >= body * 0.5) &&
                       (close1 < low2 || body > MathAbs(close2 - open2) * 1.2);
         break;
   }

   if(InpDebugMode && !strongBounce)
   {
      Print("Strict Bounce check failed (Short): Bearish=", isBearishBar,
            " | UpperWick=", DoubleToString(upperWick, 2),
            " | Body=", DoubleToString(body, 2),
            " | Strength=", strength);
   }

   return strongBounce;
}

//+------------------------------------------------------------------+
//| Detect Pullback to SHA (Improved Logic)                           |
//+------------------------------------------------------------------+
bool DetectPullback(bool isLong, double &pullbackBar)
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double tolerance = InpPullbackPips * pipValue;

   pullbackBar = -1;

   for(int i = 1; i <= InpPullbackBars; i++)
   {
      double shaMiddle = GetSHAMiddle(i);
      double barHigh = iHigh(_Symbol, tf, i);
      double barLow = iLow(_Symbol, tf, i);
      double barClose = iClose(_Symbol, tf, i);

      if(isLong)
      {
         // For Long: Price should pull back DOWN to SHA
         // Low should be close to SHA middle, but close should still be above
         double distanceToSHA = barLow - shaMiddle;

         if(distanceToSHA <= tolerance && distanceToSHA >= -tolerance * 0.5)
         {
            // Found potential pullback bar
            if(barClose > shaMiddle)  // Ensure it didn't close below SHA
            {
               pullbackBar = i;

               if(InpDebugMode)
               {
                  Print("Pullback detected (Long) at bar ", i,
                        " | Low=", barLow, " | SHA=", shaMiddle,
                        " | Distance=", DoubleToString(distanceToSHA / pipValue, 2), " pips");
               }

               return true;
            }
         }
      }
      else
      {
         // For Short: Price should pull back UP to SHA
         double distanceToSHA = shaMiddle - barHigh;

         if(distanceToSHA <= tolerance && distanceToSHA >= -tolerance * 0.5)
         {
            if(barClose < shaMiddle)
            {
               pullbackBar = i;

               if(InpDebugMode)
               {
                  Print("Pullback detected (Short) at bar ", i,
                        " | High=", barHigh, " | SHA=", shaMiddle,
                        " | Distance=", DoubleToString(distanceToSHA / pipValue, 2), " pips");
               }

               return true;
            }
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Process Trading Logic                                             |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;

   double currentClose = iClose(_Symbol, tf, 1);
   double currentOpen = iOpen(_Symbol, tf, 1);
   double shaMiddle = GetSHAMiddle(1);
   double breakoutBuffer = InpBreakoutPips * pipValue;

   // ==================== COMMON FILTERS ====================
   if(!CheckATRFilter())
      return;

   // ==================== LONG SETUP ====================
   bool longChecked = false;

   if(IsSHABullishConsecutive(InpSHAConfirmBars) && currentClose > shaMiddle)
   {
      longChecked = true;

      // Check ADX for bullish trend
      if(CheckADXFilterLong())
      {
         // Get resistance from older bars
         double resistance = GetResistanceLevel(InpBreakoutLookback);

         // Check for breakout above resistance
         bool breakoutDetected = false;
         for(int i = 1; i <= InpBreakoutLookback; i++)
         {
            double barHigh = iHigh(_Symbol, tf, i);
            if(barHigh > resistance + breakoutBuffer)
            {
               breakoutDetected = true;
               break;
            }
         }

         if(breakoutDetected)
         {
            // Check for pullback with improved detection
            double pullbackBar;
            if(DetectPullback(true, pullbackBar))
            {
               // Check for bounce confirmation
               if(CheckBounce(true, 1))
               {
                  // Final confirmation: current bar is bullish
                  if(currentClose > currentOpen)
                  {
                     double adx = GetADX(1);
                     double atr = GetATR(1);

                     Print("=================================================");
                     Print("LONG ENTRY CONDITIONS MET!");
                     Print("SHA: Bullish x", InpSHAConfirmBars, " bars");
                     Print("Resistance: ", resistance, " (Broken)");
                     Print("Pullback detected, Bounce confirmed");
                     Print("ADX: ", DoubleToString(adx, 2), " | ATR: ", DoubleToString(atr / pipValue, 2), " pips");
                     Print("=================================================");

                     ExecuteLongEntry();
                     return;
                  }
               }
            }
         }
      }
   }

   // ==================== SHORT SETUP ====================
   // Check if Short trades are enabled
   if(!InpEnableShort)
      return;

   // Use stricter confirmation for Short (InpShortConfirmBars)
   if(IsSHABearishConsecutive(InpShortConfirmBars) && currentClose < shaMiddle)
   {
      // Check ADX for bearish trend (stricter for Short)
      if(!CheckADXFilterShort())
         return;

      // Get support from older bars
      double support = GetSupportLevel(InpBreakoutLookback);

      // Check for breakout below support
      bool breakoutDetected = false;
      for(int i = 1; i <= InpBreakoutLookback; i++)
      {
         double barLow = iLow(_Symbol, tf, i);
         if(barLow < support - breakoutBuffer)
         {
            breakoutDetected = true;
            break;
         }
      }

      if(breakoutDetected)
      {
         double pullbackBar;
         if(DetectPullback(false, pullbackBar))
         {
            // Use stricter bounce check for Short
            if(CheckBounceStrict(false, 1, InpShortBounceStrength))
            {
               if(currentClose < currentOpen)
               {
                  double adx = GetADX(1);
                  double atr = GetATR(1);

                  Print("=================================================");
                  Print("SHORT ENTRY CONDITIONS MET!");
                  Print("SHA: Bearish x", InpShortConfirmBars, " bars (Strict)");
                  Print("Support: ", support, " (Broken)");
                  Print("Pullback detected, Strong Bounce confirmed");
                  Print("ADX: ", DoubleToString(adx, 2), " | ATR: ", DoubleToString(atr / pipValue, 2), " pips");
                  Print("=================================================");

                  ExecuteShortEntry();
                  return;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute Long Entry                                                |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   double ask = symbolInfo.Ask();
   double shaMiddle = GetSHAMiddle(1);
   double atr = GetATR(1);

   // Calculate SL
   double sl;
   if(InpUseATRForSLTP && atr > 0)
   {
      sl = ask - atr * InpATRMultiplierSL;
   }
   else
   {
      sl = shaMiddle - InpMinSLPips * pipValue;
   }

   // Ensure SL is within limits
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

   // Calculate TP
   double tp;
   if(InpUseATRForSLTP && atr > 0)
   {
      tp = ask + atr * InpATRMultiplierTP;
   }
   else
   {
      tp = ask + slDistance * InpRiskRewardRatio;
   }

   // Normalize prices
   int digits = symbolInfo.Digits();
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("Invalid lot size!");
      return;
   }

   // Execute trade
   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;

      Print("========================================");
      Print("LONG POSITION OPENED!");
      Print("Entry: ", ask, " | SL: ", sl, " | TP: ", tp);
      Print("Lot: ", lotSize, " | SL: $", DoubleToString(slDistance, 2),
            " | TP: $", DoubleToString(tp - ask, 2));
      Print("RR: 1:", DoubleToString((tp - ask) / slDistance, 2));
      Print("Daily Trades: ", dailyTradeCount);
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
   double shaMiddle = GetSHAMiddle(1);
   double atr = GetATR(1);

   // Calculate SL
   double sl;
   if(InpUseATRForSLTP && atr > 0)
   {
      sl = bid + atr * InpATRMultiplierSL;
   }
   else
   {
      sl = shaMiddle + InpMinSLPips * pipValue;
   }

   // Ensure SL is within limits
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

   // Calculate TP
   double tp;
   if(InpUseATRForSLTP && atr > 0)
   {
      tp = bid - atr * InpATRMultiplierTP;
   }
   else
   {
      tp = bid - slDistance * InpRiskRewardRatio;
   }

   // Normalize prices
   int digits = symbolInfo.Digits();
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Calculate lot size
   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("Invalid lot size!");
      return;
   }

   // Execute trade
   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, InpTradeComment))
   {
      dailyTradeCount++;

      Print("========================================");
      Print("SHORT POSITION OPENED!");
      Print("Entry: ", bid, " | SL: ", sl, " | TP: ", tp);
      Print("Lot: ", lotSize, " | SL: $", DoubleToString(slDistance, 2),
            " | TP: $", DoubleToString(bid - tp, 2));
      Print("RR: 1:", DoubleToString((bid - tp) / slDistance, 2));
      Print("Daily Trades: ", dailyTradeCount);
      Print("========================================");
   }
   else
   {
      Print("Failed to open Short! Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   if(InpRiskPercent <= 0)
      return InpFixedLot;

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * InpRiskPercent / 100.0;

   double tickSize = symbolInfo.TickSize();
   double tickValue = symbolInfo.TickValue();

   if(tickSize == 0 || tickValue == 0)
      return InpFixedLot;

   double slTicks = slDistance / tickSize;
   double lotSize = riskAmount / (slTicks * tickValue);

   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return NormalizeDouble(lotSize, 2);
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
         if(positionInfo.Symbol() == _Symbol &&
            positionInfo.Magic() == InpMagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manage Open Position                                              |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   // Position management - let it run to SL/TP
   // Future: Add trailing stop, breakeven, partial close
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                     |
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

   // Friday = 5
   if(currentTime.day_of_week == 5 && currentTime.hour >= 18)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   // Handle chart events if needed
}
//+------------------------------------------------------------------+
