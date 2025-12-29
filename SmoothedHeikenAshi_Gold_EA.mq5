//+------------------------------------------------------------------+
//|                                   SmoothedHeikenAshi_Gold_EA.mq5 |
//|                                  Smoothed Heiken Ashi Strategy EA |
//|                                       For XAUUSD (Gold) Trading   |
//|                                                        v1.10      |
//+------------------------------------------------------------------+
#property copyright "Smoothed Heiken Ashi Gold EA"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Smoothed Heiken Ashi Settings ==="
input int                InpSmoothingLength    = 15;              // Smoothing Length
input ENUM_TIMEFRAMES    InpTimeframe          = PERIOD_CURRENT;  // Timeframe for Calculation

input group "=== Breakout Detection Settings ==="
input int                InpLookbackPeriod     = 20;              // Lookback Period for Support/Resistance
input int                InpBreakoutLookback   = 5;               // Bars to Skip for S/R Calculation
input double             InpBreakoutPips       = 1.0;             // Breakout Buffer (Pips/Dollars for Gold)

input group "=== Pullback Settings ==="
input int                InpPullbackBars       = 10;              // Max Bars to Wait for Pullback
input double             InpPullbackPips       = 3.0;             // Pullback Tolerance (Pips/Dollars)

input group "=== Money Management ==="
input double             InpRiskPercent        = 1.0;             // Risk Percent of Balance (0 = Fixed Lot)
input double             InpFixedLot           = 0.1;             // Fixed Lot Size (if Risk% = 0)
input double             InpRiskRewardRatio    = 2.0;             // Risk:Reward Ratio
input double             InpSLPips             = 5.0;             // SL Buffer from SHA (Pips/Dollars)
input bool               InpUseSwingTargets    = false;           // Use Swing High/Low for TP

input group "=== Trading Filters ==="
input int                InpMaxSpreadPips      = 50;              // Maximum Spread (Pips, 0=Disable)
input int                InpSlippage           = 50;              // Slippage (Points)

input group "=== Time Filter ==="
input bool               InpUseTimeFilter      = false;           // Use Time Filter
input int                InpStartHour          = 8;               // Start Hour (Server Time)
input int                InpStartMinute        = 0;               // Start Minute
input int                InpEndHour            = 22;              // End Hour (Server Time)
input int                InpEndMinute          = 0;               // End Minute

input group "=== General Settings ==="
input ulong              InpMagicNumber        = 202412001;       // Magic Number
input string             InpTradeComment       = "SHA_Gold_EA";   // Trade Comment
input bool               InpDebugMode          = true;            // Debug Mode (Print detailed logs)

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

// Pip value for normalization
double pipValue = 0.01;  // For XAUUSD, 1 pip = $0.01 typically

// State Tracking for Strategy
enum ENUM_SETUP_STATE
{
   STATE_NONE,               // No setup
   STATE_TREND_CONFIRMED,    // Trend confirmed by SHA color
   STATE_BREAKOUT_DETECTED,  // Breakout above resistance / below support
   STATE_WAITING_PULLBACK,   // Waiting for pullback to SHA
   STATE_ENTRY_READY         // Ready to enter on bounce
};

ENUM_SETUP_STATE longState = STATE_NONE;
ENUM_SETUP_STATE shortState = STATE_NONE;

double savedResistance = 0;
double savedSupport = 0;
int longBreakoutBar = 0;
int shortBreakoutBar = 0;

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
      pipValue = 0.01;      // XAUUSD with 2 decimals
   else if(digits == 3)
      pipValue = 0.001;     // XAUUSD with 3 decimals
   else if(digits == 5)
      pipValue = 0.00001;   // Forex pairs
   else if(digits == 4)
      pipValue = 0.0001;    // JPY pairs or old forex
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

   Print("==============================================");
   Print("SmoothedHeikenAshi Gold EA v1.10 Initialized");
   Print("Symbol: ", _Symbol, " | Digits: ", digits);
   Print("Pip Value: ", pipValue);
   Print("Smoothing Length: ", InpSmoothingLength);
   Print("Breakout Buffer: ", InpBreakoutPips, " pips = $", InpBreakoutPips * pipValue * 100);
   Print("Pullback Tolerance: ", InpPullbackPips, " pips = $", InpPullbackPips * pipValue * 100);
   Print("SL Buffer: ", InpSLPips, " pips = $", InpSLPips * pipValue * 100);
   Print("Max Spread: ", InpMaxSpreadPips, " pips");
   Print("Debug Mode: ", InpDebugMode ? "ON" : "OFF");
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("SmoothedHeikenAshi Gold EA deinitialized. Reason: ", reason);
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
      return;  // Not a new bar

   lastBarTime = currentBarTime;

   // Update symbol info
   if(!symbolInfo.RefreshRates())
      return;

   // Check spread (convert pips to points)
   double currentSpreadPips = symbolInfo.Spread() * symbolInfo.Point() / pipValue;
   if(InpMaxSpreadPips > 0 && currentSpreadPips > InpMaxSpreadPips)
   {
      if(InpDebugMode)
         Print("Spread too high: ", DoubleToString(currentSpreadPips, 1), " > ", InpMaxSpreadPips, " pips");
      return;
   }

   // Check time filter
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

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

   // Execute trading logic with state machine
   ProcessTradingLogic();
}

//+------------------------------------------------------------------+
//| Calculate Smoothed Heiken Ashi                                    |
//+------------------------------------------------------------------+
bool CalculateSmoothedHeikenAshi()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   int barsNeeded = InpLookbackPeriod + InpSmoothingLength + InpPullbackBars + 20;

   // Resize arrays
   ArrayResize(shaOpen, barsNeeded);
   ArrayResize(shaHigh, barsNeeded);
   ArrayResize(shaLow, barsNeeded);
   ArrayResize(shaClose, barsNeeded);
   ArrayResize(shaColor, barsNeeded);

   // Get OHLC data
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int totalBars = barsNeeded + InpSmoothingLength;
   if(CopyOpen(_Symbol, tf, 0, totalBars, open) < totalBars)
      return false;
   if(CopyHigh(_Symbol, tf, 0, totalBars, high) < totalBars)
      return false;
   if(CopyLow(_Symbol, tf, 0, totalBars, low) < totalBars)
      return false;
   if(CopyClose(_Symbol, tf, 0, totalBars, close) < totalBars)
      return false;

   // Calculate smoothed OHLC using EMA
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

   // Initialize first values
   int startIdx = barsNeeded - 1;
   smoothedOpen[startIdx] = open[startIdx];
   smoothedHigh[startIdx] = high[startIdx];
   smoothedLow[startIdx] = low[startIdx];
   smoothedClose[startIdx] = close[startIdx];

   // Calculate EMA for each OHLC
   for(int i = startIdx - 1; i >= 0; i--)
   {
      smoothedOpen[i] = alpha * open[i] + (1 - alpha) * smoothedOpen[i + 1];
      smoothedHigh[i] = alpha * high[i] + (1 - alpha) * smoothedHigh[i + 1];
      smoothedLow[i] = alpha * low[i] + (1 - alpha) * smoothedLow[i + 1];
      smoothedClose[i] = alpha * close[i] + (1 - alpha) * smoothedClose[i + 1];
   }

   // Calculate Heiken Ashi on smoothed data
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

      // Determine color: 0 = White (Bullish), 1 = Pink (Bearish)
      shaColor[i] = (shaClose[i] >= shaOpen[i]) ? 0.0 : 1.0;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Get SHA Middle Line                                               |
//+------------------------------------------------------------------+
double GetSHAMiddle(int shift)
{
   if(shift < 0 || shift >= ArraySize(shaOpen))
      return 0;
   return (shaOpen[shift] + shaClose[shift]) / 2.0;
}

//+------------------------------------------------------------------+
//| Check if SHA is Bullish (White)                                   |
//+------------------------------------------------------------------+
bool IsSHABullish(int shift)
{
   if(shift < 0 || shift >= ArraySize(shaColor))
      return false;
   return shaColor[shift] == 0.0;
}

//+------------------------------------------------------------------+
//| Check if SHA is Bearish (Pink)                                    |
//+------------------------------------------------------------------+
bool IsSHABearish(int shift)
{
   if(shift < 0 || shift >= ArraySize(shaColor))
      return false;
   return shaColor[shift] == 1.0;
}

//+------------------------------------------------------------------+
//| Get Resistance Level (excluding recent bars)                      |
//+------------------------------------------------------------------+
double GetResistanceLevel(int skipBars)
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double highest = 0;

   // Start from skipBars+1 to exclude recent price action
   for(int i = skipBars + 1; i <= skipBars + InpLookbackPeriod; i++)
   {
      double h = iHigh(_Symbol, tf, i);
      if(h > highest)
         highest = h;
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

   // Start from skipBars+1 to exclude recent price action
   for(int i = skipBars + 1; i <= skipBars + InpLookbackPeriod; i++)
   {
      double l = iLow(_Symbol, tf, i);
      if(l < lowest)
         lowest = l;
   }

   return lowest;
}

//+------------------------------------------------------------------+
//| Process Trading Logic with State Machine                          |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;

   double currentClose = iClose(_Symbol, tf, 1);
   double currentHigh = iHigh(_Symbol, tf, 1);
   double currentLow = iLow(_Symbol, tf, 1);
   double currentOpen = iOpen(_Symbol, tf, 1);
   double shaMiddle = GetSHAMiddle(1);

   double breakoutBuffer = InpBreakoutPips * pipValue;
   double pullbackTolerance = InpPullbackPips * pipValue;

   // ==================== LONG SETUP ====================
   // Check if SHA is bullish (White)
   bool shaBullish = IsSHABullish(1) && IsSHABullish(2);

   if(shaBullish && currentClose > shaMiddle)
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
         // Check for pullback - price came back close to SHA
         double distanceToSHA = currentLow - shaMiddle;

         if(InpDebugMode)
         {
            Print("LONG Check: Resistance=", resistance, " | SHA=", shaMiddle,
                  " | Close=", currentClose, " | Low=", currentLow,
                  " | Distance to SHA=", distanceToSHA);
         }

         // Pullback condition: Low is close to or touched SHA, but close is above
         bool pullbackOK = (distanceToSHA <= pullbackTolerance && distanceToSHA >= -pullbackTolerance);

         // Price should not have closed below SHA
         bool priceAboveSHA = currentClose > shaMiddle;

         // Current bar should be bullish (reversal from pullback)
         bool bullishBar = currentClose > currentOpen;

         if(pullbackOK && priceAboveSHA && bullishBar)
         {
            Print("==> LONG ENTRY SIGNAL!");
            ExecuteLongEntry();
            return;
         }
      }
   }

   // ==================== SHORT SETUP ====================
   // Check if SHA is bearish (Pink)
   bool shaBearish = IsSHABearish(1) && IsSHABearish(2);

   if(shaBearish && currentClose < shaMiddle)
   {
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
         // Check for pullback - price came back close to SHA
         double distanceToSHA = shaMiddle - currentHigh;

         if(InpDebugMode)
         {
            Print("SHORT Check: Support=", support, " | SHA=", shaMiddle,
                  " | Close=", currentClose, " | High=", currentHigh,
                  " | Distance to SHA=", distanceToSHA);
         }

         // Pullback condition: High is close to or touched SHA, but close is below
         bool pullbackOK = (distanceToSHA <= pullbackTolerance && distanceToSHA >= -pullbackTolerance);

         // Price should not have closed above SHA
         bool priceBelowSHA = currentClose < shaMiddle;

         // Current bar should be bearish (reversal from pullback)
         bool bearishBar = currentClose < currentOpen;

         if(pullbackOK && priceBelowSHA && bearishBar)
         {
            Print("==> SHORT ENTRY SIGNAL!");
            ExecuteShortEntry();
            return;
         }
      }
   }

   // Debug output for monitoring
   static int debugCounter = 0;
   debugCounter++;
   if(InpDebugMode && debugCounter >= 50)  // Print every 50 bars
   {
      debugCounter = 0;
      Print("Status: SHA ", (IsSHABullish(1) ? "BULLISH" : (IsSHABearish(1) ? "BEARISH" : "NEUTRAL")),
            " | Price=", currentClose, " | SHA Middle=", shaMiddle);
   }
}

//+------------------------------------------------------------------+
//| Execute Long Entry                                                |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   double ask = symbolInfo.Ask();
   double shaMiddle = GetSHAMiddle(1);
   double slBuffer = InpSLPips * pipValue;

   // Calculate Stop Loss (below SHA)
   double sl = shaMiddle - slBuffer;
   double slDistance = ask - sl;

   if(slDistance <= 0)
   {
      Print("Invalid SL distance for Long entry! Ask=", ask, " SL=", sl);
      return;
   }

   // Calculate Take Profit
   double tp;
   if(InpUseSwingTargets)
   {
      ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
      double highest = 0;
      for(int i = 1; i <= InpLookbackPeriod * 2; i++)
      {
         double h = iHigh(_Symbol, tf, i);
         if(h > highest) highest = h;
      }
      tp = highest;
      if(tp <= ask)
         tp = ask + slDistance * InpRiskRewardRatio;
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
      Print("Invalid lot size calculated!");
      return;
   }

   // Execute trade
   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, InpTradeComment))
   {
      Print("========================================");
      Print("LONG POSITION OPENED!");
      Print("Entry: ", ask, " | SL: ", sl, " | TP: ", tp);
      Print("Lot Size: ", lotSize, " | RR: 1:", InpRiskRewardRatio);
      Print("SL Distance: $", slDistance, " | TP Distance: $", tp - ask);
      Print("========================================");
   }
   else
   {
      Print("Failed to open Long position! Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Execute Short Entry                                               |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
   double bid = symbolInfo.Bid();
   double shaMiddle = GetSHAMiddle(1);
   double slBuffer = InpSLPips * pipValue;

   // Calculate Stop Loss (above SHA)
   double sl = shaMiddle + slBuffer;
   double slDistance = sl - bid;

   if(slDistance <= 0)
   {
      Print("Invalid SL distance for Short entry! Bid=", bid, " SL=", sl);
      return;
   }

   // Calculate Take Profit
   double tp;
   if(InpUseSwingTargets)
   {
      ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
      double lowest = DBL_MAX;
      for(int i = 1; i <= InpLookbackPeriod * 2; i++)
      {
         double l = iLow(_Symbol, tf, i);
         if(l < lowest) lowest = l;
      }
      tp = lowest;
      if(tp >= bid)
         tp = bid - slDistance * InpRiskRewardRatio;
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
      Print("Invalid lot size calculated!");
      return;
   }

   // Execute trade
   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, InpTradeComment))
   {
      Print("========================================");
      Print("SHORT POSITION OPENED!");
      Print("Entry: ", bid, " | SL: ", sl, " | TP: ", tp);
      Print("Lot Size: ", lotSize, " | RR: 1:", InpRiskRewardRatio);
      Print("SL Distance: $", slDistance, " | TP Distance: $", bid - tp);
      Print("========================================");
   }
   else
   {
      Print("Failed to open Short position! Error: ", GetLastError());
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

   // Get tick value
   double tickSize = symbolInfo.TickSize();
   double tickValue = symbolInfo.TickValue();

   if(tickSize == 0 || tickValue == 0)
   {
      Print("Warning: Invalid tick info, using fixed lot");
      return InpFixedLot;
   }

   // Calculate lot size
   double slTicks = slDistance / tickSize;
   double lotSize = riskAmount / (slTicks * tickValue);

   // Normalize lot size
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
   // Currently let position run to SL or TP
   // Optional: Add trailing stop logic here
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
   {
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   }
   else
   {
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   }
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Handle chart events if needed
}
//+------------------------------------------------------------------+
