//+------------------------------------------------------------------+
//|                                   SmoothedHeikenAshi_Gold_EA.mq5 |
//|                                  Smoothed Heiken Ashi Strategy EA |
//|                                       For XAUUSD (Gold) Trading   |
//+------------------------------------------------------------------+
#property copyright "Smoothed Heiken Ashi Gold EA"
#property link      ""
#property version   "1.00"
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
input double             InpBreakoutBuffer     = 0.5;             // Breakout Buffer (Points)

input group "=== Pullback Settings ==="
input int                InpPullbackBars       = 10;              // Max Bars to Wait for Pullback
input double             InpPullbackTolerance  = 2.0;             // Pullback Tolerance (Points)

input group "=== Money Management ==="
input double             InpRiskPercent        = 1.0;             // Risk Percent of Balance (0 = Fixed Lot)
input double             InpFixedLot           = 0.1;             // Fixed Lot Size (if Risk% = 0)
input double             InpRiskRewardRatio    = 2.0;             // Risk:Reward Ratio
input double             InpSLBuffer           = 3.0;             // SL Buffer from SHA (Points)
input bool               InpUseSwingTargets    = false;           // Use Swing High/Low for TP

input group "=== Trading Filters ==="
input int                InpMaxSpread          = 50;              // Maximum Spread (Points)
input int                InpSlippage           = 10;              // Slippage (Points)

input group "=== Time Filter ==="
input bool               InpUseTimeFilter      = false;           // Use Time Filter
input int                InpStartHour          = 8;               // Start Hour (Server Time)
input int                InpStartMinute        = 0;               // Start Minute
input int                InpEndHour            = 22;              // End Hour (Server Time)
input int                InpEndMinute          = 0;               // End Minute

input group "=== General Settings ==="
input ulong              InpMagicNumber        = 202412001;       // Magic Number
input string             InpTradeComment       = "SHA_Gold_EA";   // Trade Comment

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

// State Tracking
enum ENUM_TRADE_STATE
{
   STATE_WAITING_TREND,        // Waiting for trend confirmation
   STATE_WAITING_BREAKOUT,     // Waiting for breakout
   STATE_WAITING_PULLBACK,     // Waiting for pullback/retest
   STATE_READY_TO_ENTER        // Ready to enter
};

ENUM_TRADE_STATE currentState = STATE_WAITING_TREND;
int              trendDirection = 0;  // 1 = Bullish, -1 = Bearish, 0 = None
double           breakoutLevel = 0;
int              pullbackCounter = 0;
bool             breakoutConfirmed = false;

// Handles
int              maHandle = INVALID_HANDLE;

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

   // Create MA handle for smoothing
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   maHandle = iMA(_Symbol, tf, InpSmoothingLength, 0, MODE_EMA, PRICE_CLOSE);

   if(maHandle == INVALID_HANDLE)
   {
      Print("Failed to create MA handle!");
      return INIT_FAILED;
   }

   Print("SmoothedHeikenAshi Gold EA initialized successfully!");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(tf));
   Print("Smoothing Length: ", InpSmoothingLength);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);

   Print("SmoothedHeikenAshi Gold EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe, 0);

   if(lastBarTime == currentBarTime)
      return;  // Not a new bar

   lastBarTime = currentBarTime;

   // Update symbol info
   if(!symbolInfo.RefreshRates())
      return;

   // Check spread
   if(InpMaxSpread > 0 && symbolInfo.Spread() > InpMaxSpread)
   {
      Print("Spread too high: ", symbolInfo.Spread(), " > ", InpMaxSpread);
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

   // Execute trading logic
   ExecuteTradingLogic();
}

//+------------------------------------------------------------------+
//| Calculate Smoothed Heiken Ashi                                    |
//+------------------------------------------------------------------+
bool CalculateSmoothedHeikenAshi()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   int barsNeeded = InpLookbackPeriod + InpSmoothingLength + 10;

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

   if(CopyOpen(_Symbol, tf, 0, barsNeeded + InpSmoothingLength, open) < barsNeeded)
      return false;
   if(CopyHigh(_Symbol, tf, 0, barsNeeded + InpSmoothingLength, high) < barsNeeded)
      return false;
   if(CopyLow(_Symbol, tf, 0, barsNeeded + InpSmoothingLength, low) < barsNeeded)
      return false;
   if(CopyClose(_Symbol, tf, 0, barsNeeded + InpSmoothingLength, close) < barsNeeded)
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
   // First bar
   shaClose[startIdx] = (smoothedOpen[startIdx] + smoothedHigh[startIdx] +
                         smoothedLow[startIdx] + smoothedClose[startIdx]) / 4.0;
   shaOpen[startIdx] = (smoothedOpen[startIdx] + smoothedClose[startIdx]) / 2.0;
   shaHigh[startIdx] = smoothedHigh[startIdx];
   shaLow[startIdx] = smoothedLow[startIdx];

   // Calculate for remaining bars
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
//| Get SHA Middle Line (Average of Open and Close)                   |
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
//| Get Recent Resistance Level                                       |
//+------------------------------------------------------------------+
double GetResistanceLevel()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double highest = 0;

   for(int i = 1; i <= InpLookbackPeriod; i++)
   {
      double h = iHigh(_Symbol, tf, i);
      if(h > highest)
         highest = h;
   }

   return highest;
}

//+------------------------------------------------------------------+
//| Get Recent Support Level                                          |
//+------------------------------------------------------------------+
double GetSupportLevel()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double lowest = DBL_MAX;

   for(int i = 1; i <= InpLookbackPeriod; i++)
   {
      double l = iLow(_Symbol, tf, i);
      if(l < lowest)
         lowest = l;
   }

   return lowest;
}

//+------------------------------------------------------------------+
//| Get Recent Swing High for TP                                      |
//+------------------------------------------------------------------+
double GetSwingHigh()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double highest = 0;

   for(int i = 1; i <= InpLookbackPeriod * 2; i++)
   {
      double h = iHigh(_Symbol, tf, i);
      if(h > highest)
         highest = h;
   }

   return highest;
}

//+------------------------------------------------------------------+
//| Get Recent Swing Low for TP                                       |
//+------------------------------------------------------------------+
double GetSwingLow()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double lowest = DBL_MAX;

   for(int i = 1; i <= InpLookbackPeriod * 2; i++)
   {
      double l = iLow(_Symbol, tf, i);
      if(l < lowest)
         lowest = l;
   }

   return lowest;
}

//+------------------------------------------------------------------+
//| Execute Trading Logic                                             |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double currentPrice = symbolInfo.Ask();
   double shaMiddle = GetSHAMiddle(1);  // Use closed bar
   double point = symbolInfo.Point();

   // Check for Long Setup
   if(CheckLongSetup())
   {
      ExecuteLongEntry();
      return;
   }

   // Check for Short Setup
   if(CheckShortSetup())
   {
      ExecuteShortEntry();
      return;
   }
}

//+------------------------------------------------------------------+
//| Check Long Setup                                                  |
//+------------------------------------------------------------------+
bool CheckLongSetup()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double point = symbolInfo.Point();
   double currentClose = iClose(_Symbol, tf, 1);
   double prevClose = iClose(_Symbol, tf, 2);
   double currentLow = iLow(_Symbol, tf, 1);
   double shaMiddle1 = GetSHAMiddle(1);
   double shaMiddle2 = GetSHAMiddle(2);

   // 1. Trend Confirmation: SHA is White (Bullish) and price is above SHA
   if(!IsSHABullish(1) || !IsSHABullish(2))
      return false;

   if(currentClose <= shaMiddle1)
      return false;

   // 2. Look for recent breakout above resistance
   double resistance = GetResistanceLevel();
   bool hadBreakout = false;
   int breakoutBar = -1;

   // Check if there was a breakout in recent bars
   for(int i = 1; i <= InpPullbackBars; i++)
   {
      double barClose = iClose(_Symbol, tf, i);
      double barHigh = iHigh(_Symbol, tf, i);

      // Check if this bar broke above resistance
      if(barHigh > resistance + InpBreakoutBuffer * point)
      {
         hadBreakout = true;
         breakoutBar = i;
         break;
      }
   }

   if(!hadBreakout)
      return false;

   // 3. Check for Pullback to SHA (Retest)
   // Price should have pulled back close to SHA middle
   double pullbackDistance = MathAbs(currentLow - shaMiddle1);
   double tolerance = InpPullbackTolerance * point;

   bool hasPullback = (pullbackDistance <= tolerance) ||
                      (currentLow <= shaMiddle1 + tolerance && currentClose > shaMiddle1);

   if(!hasPullback)
      return false;

   // 4. Filter: Price should not have broken below SHA (White) during pullback
   for(int i = 1; i <= breakoutBar; i++)
   {
      double barLow = iLow(_Symbol, tf, i);
      double barShaMiddle = GetSHAMiddle(i);

      // If price closed below SHA, invalidate the setup
      if(iClose(_Symbol, tf, i) < barShaMiddle - tolerance)
         return false;
   }

   // 5. Confirmation: Current bar shows bullish reversal from pullback
   // Close should be higher than open (bullish bar)
   double currentOpen = iOpen(_Symbol, tf, 1);
   if(currentClose <= currentOpen)
      return false;

   Print("Long Setup Detected!");
   Print("Resistance: ", resistance, " | SHA Middle: ", shaMiddle1);
   Print("Current Close: ", currentClose, " | Pullback Distance: ", pullbackDistance);

   return true;
}

//+------------------------------------------------------------------+
//| Check Short Setup                                                 |
//+------------------------------------------------------------------+
bool CheckShortSetup()
{
   ENUM_TIMEFRAMES tf = InpTimeframe == PERIOD_CURRENT ? Period() : InpTimeframe;
   double point = symbolInfo.Point();
   double currentClose = iClose(_Symbol, tf, 1);
   double prevClose = iClose(_Symbol, tf, 2);
   double currentHigh = iHigh(_Symbol, tf, 1);
   double shaMiddle1 = GetSHAMiddle(1);
   double shaMiddle2 = GetSHAMiddle(2);

   // 1. Trend Confirmation: SHA is Pink (Bearish) and price is below SHA
   if(!IsSHABearish(1) || !IsSHABearish(2))
      return false;

   if(currentClose >= shaMiddle1)
      return false;

   // 2. Look for recent breakout below support
   double support = GetSupportLevel();
   bool hadBreakout = false;
   int breakoutBar = -1;

   // Check if there was a breakout in recent bars
   for(int i = 1; i <= InpPullbackBars; i++)
   {
      double barClose = iClose(_Symbol, tf, i);
      double barLow = iLow(_Symbol, tf, i);

      // Check if this bar broke below support
      if(barLow < support - InpBreakoutBuffer * point)
      {
         hadBreakout = true;
         breakoutBar = i;
         break;
      }
   }

   if(!hadBreakout)
      return false;

   // 3. Check for Pullback to SHA (Retest)
   // Price should have pulled back close to SHA middle
   double pullbackDistance = MathAbs(currentHigh - shaMiddle1);
   double tolerance = InpPullbackTolerance * point;

   bool hasPullback = (pullbackDistance <= tolerance) ||
                      (currentHigh >= shaMiddle1 - tolerance && currentClose < shaMiddle1);

   if(!hasPullback)
      return false;

   // 4. Filter: Price should not have broken above SHA (Pink) during pullback
   for(int i = 1; i <= breakoutBar; i++)
   {
      double barHigh = iHigh(_Symbol, tf, i);
      double barShaMiddle = GetSHAMiddle(i);

      // If price closed above SHA, invalidate the setup
      if(iClose(_Symbol, tf, i) > barShaMiddle + tolerance)
         return false;
   }

   // 5. Confirmation: Current bar shows bearish reversal from pullback
   // Close should be lower than open (bearish bar)
   double currentOpen = iOpen(_Symbol, tf, 1);
   if(currentClose >= currentOpen)
      return false;

   Print("Short Setup Detected!");
   Print("Support: ", support, " | SHA Middle: ", shaMiddle1);
   Print("Current Close: ", currentClose, " | Pullback Distance: ", pullbackDistance);

   return true;
}

//+------------------------------------------------------------------+
//| Execute Long Entry                                                |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   double point = symbolInfo.Point();
   double ask = symbolInfo.Ask();
   double shaMiddle = GetSHAMiddle(1);

   // Calculate Stop Loss (below SHA)
   double sl = shaMiddle - InpSLBuffer * point;
   double slDistance = ask - sl;

   if(slDistance <= 0)
   {
      Print("Invalid SL distance for Long entry!");
      return;
   }

   // Calculate Take Profit
   double tp;
   if(InpUseSwingTargets)
   {
      tp = GetSwingHigh();
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
      Print("Long position opened successfully!");
      Print("Entry: ", ask, " | SL: ", sl, " | TP: ", tp, " | Lot: ", lotSize);
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
   double point = symbolInfo.Point();
   double bid = symbolInfo.Bid();
   double shaMiddle = GetSHAMiddle(1);

   // Calculate Stop Loss (above SHA)
   double sl = shaMiddle + InpSLBuffer * point;
   double slDistance = sl - bid;

   if(slDistance <= 0)
   {
      Print("Invalid SL distance for Short entry!");
      return;
   }

   // Calculate Take Profit
   double tp;
   if(InpUseSwingTargets)
   {
      tp = GetSwingLow();
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
      Print("Short position opened successfully!");
      Print("Entry: ", bid, " | SL: ", sl, " | TP: ", tp, " | Lot: ", lotSize);
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
      return InpFixedLot;

   // Calculate lot size
   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);

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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol &&
            positionInfo.Magic() == InpMagicNumber)
         {
            // Optional: Implement trailing stop or other management
            // Currently, we let the position run to SL or TP

            // Check for SHA color change (optional exit signal)
            ENUM_POSITION_TYPE posType = positionInfo.PositionType();

            if(posType == POSITION_TYPE_BUY && IsSHABearish(1))
            {
               // SHA turned bearish, consider closing long
               // Uncomment below to enable this exit
               // trade.PositionClose(positionInfo.Ticket());
               // Print("Closed Long position due to SHA color change");
            }
            else if(posType == POSITION_TYPE_SELL && IsSHABullish(1))
            {
               // SHA turned bullish, consider closing short
               // Uncomment below to enable this exit
               // trade.PositionClose(positionInfo.Ticket());
               // Print("Closed Short position due to SHA color change");
            }
         }
      }
   }
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
      // Normal case: start is before end (same day)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   }
   else
   {
      // Overnight case: start is after end (spans midnight)
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   }
}

//+------------------------------------------------------------------+
//| Display Info on Chart                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Optional: Handle chart events for visual display
}
//+------------------------------------------------------------------+
