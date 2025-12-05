//+------------------------------------------------------------------+
//|                                                  GranvilleEA.mq5 |
//|                                  Granville's Law Gold Trading EA |
//|                                      Optimized for Prop Trading  |
//+------------------------------------------------------------------+
#property copyright "Granville Gold Trading System"
#property link      ""
#property version   "1.00"
#property description "XAU/USD Expert Advisor based on Granville's 8 Laws"
#property description "Multi-timeframe trend following with strict risk management"

//+------------------------------------------------------------------+
//| Input Parameters (Optimized)                                     |
//+------------------------------------------------------------------+
// Basic Settings
input string   Symbol_to_Trade = "XAUUSD";
input double   Risk_Percent = 2.0;                 // Risk (% of account balance)
input double   Max_Lot_Size = 10.0;                // Maximum lot size

// Moving Average Settings
input int      MA_Period_Mid = 75;                 // Mid-term EMA period
input int      MA_Period_Long = 200;               // Long-term EMA period
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H4;   // MTF trend confirmation timeframe
input int      MA_Proximity_Pips = 100;            // MA proximity threshold (pips)
input double   TakeProfit_Ratio = 2.0;             // Risk:Reward ratio

// Trend Filter
input int      ADX_Period = 14;                    // ADX period
input double   ADX_Min_Level = 20.0;               // Minimum ADX level

// Volatility Filter
input int      ATR_Period = 14;                    // ATR period
input double   ATR_Min_Multiplier = 0.5;           // Minimum ATR multiplier
input double   ATR_Max_Multiplier = 2.0;           // Maximum ATR multiplier

// Risk Management
input bool     BreakEven_Enable = true;            // Enable break-even
input double   BreakEven_Trigger_Percent = 50.0;   // Break-even trigger (% of SL)
input int      BreakEven_Offset_Pips = 10;         // Break-even offset (pips)

input bool     PartialTP_Enable = true;            // Enable partial take profit
input double   PartialTP_Close_Percent = 50.0;     // Partial TP close percent
input double   PartialTP_Trigger_Percent = 50.0;   // Partial TP trigger (% of TP)

// Prop Trading Features
input bool     DailyLossLimit_Enable = true;       // Enable daily loss limit
input double   DailyLossLimit_Percent = 4.0;       // Daily loss limit (%)

// Time Filter
input bool     TimeFilter_Enable = true;           // Enable time filter
input int      Trade_Start_Hour = 12;              // Trading start hour (server time)
input int      Trade_End_Hour = 5;                 // Trading end hour (server time)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
// Indicator handles
int handleEMA_Mid;           // 75 EMA handle
int handleEMA_Long;          // 200 EMA handle
int handleEMA_MTF;           // H4 75 EMA handle
int handleADX;               // ADX handle
int handleATR;               // ATR handle

// Buffers
double bufferEMA_Mid[];
double bufferEMA_Long[];
double bufferEMA_MTF[];
double bufferADX[];
double bufferATR[];

// Bar tracking
datetime lastBarTime = 0;

// Daily loss tracking
datetime lastResetDate = 0;
double dailyStartBalance = 0;
bool dailyLimitReached = false;

// Position tracking
bool partialTPExecuted = false;
bool breakEvenExecuted = false;
ulong currentTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Granville Gold Trading EA - Initializing");
   Print("========================================");
   Print("Symbol: ", Symbol_to_Trade);
   Print("Risk: ", Risk_Percent, "%");
   Print("MA Mid: ", MA_Period_Mid, " | MA Long: ", MA_Period_Long);
   Print("MTF Timeframe: ", EnumToString(MTF_Timeframe));
   Print("ADX Min: ", ADX_Min_Level);
   Print("ATR Range: ", ATR_Min_Multiplier, " - ", ATR_Max_Multiplier);
   Print("R:R Ratio: ", TakeProfit_Ratio);
   Print("========================================");

   // Set arrays as series
   ArraySetAsSeries(bufferEMA_Mid, true);
   ArraySetAsSeries(bufferEMA_Long, true);
   ArraySetAsSeries(bufferEMA_MTF, true);
   ArraySetAsSeries(bufferADX, true);
   ArraySetAsSeries(bufferATR, true);

   // Create indicator handles on current symbol
   handleEMA_Mid = iMA(Symbol_to_Trade, PERIOD_CURRENT, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Long = iMA(Symbol_to_Trade, PERIOD_CURRENT, MA_Period_Long, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_MTF = iMA(Symbol_to_Trade, MTF_Timeframe, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleADX = iADX(Symbol_to_Trade, PERIOD_CURRENT, ADX_Period);
   handleATR = iATR(Symbol_to_Trade, PERIOD_CURRENT, ATR_Period);

   // Check if handles are valid
   if(handleEMA_Mid == INVALID_HANDLE || handleEMA_Long == INVALID_HANDLE ||
      handleEMA_MTF == INVALID_HANDLE || handleADX == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }

   // Initialize daily loss tracking
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastResetDate = TimeCurrent();

   Print("Initialization successful!");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleEMA_Mid != INVALID_HANDLE) IndicatorRelease(handleEMA_Mid);
   if(handleEMA_Long != INVALID_HANDLE) IndicatorRelease(handleEMA_Long);
   if(handleEMA_MTF != INVALID_HANDLE) IndicatorRelease(handleEMA_MTF);
   if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);

   Print("Granville EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Check for new bar
   if(!IsNewBar()) return;

   // 2. Check and reset daily loss limit
   CheckDailyReset();

   // 3. If we have an existing position, manage it
   if(PositionSelect(Symbol_to_Trade))
   {
      ManagePosition();
      return;
   }
   else
   {
      // Reset position tracking when no position
      partialTPExecuted = false;
      breakEvenExecuted = false;
      currentTicket = 0;
   }

   // 4. Check if daily limit is reached
   if(dailyLimitReached)
   {
      return;
   }

   // 5. Check time filter
   if(TimeFilter_Enable && !CheckTimeFilter())
   {
      return;
   }

   // 6. Copy indicator data
   if(!CopyIndicatorData())
   {
      return;
   }

   // 7. Check ATR volatility filter
   if(!CheckATRFilter())
   {
      return;
   }

   // 8. MTF Trend Analysis
   int mtfTrend = GetMTFTrend();
   if(mtfTrend == 0) return; // Range or no clear trend

   // 9. Check for entry signals
   int signal = CheckGranvilleSignal(mtfTrend);

   // 10. Execute trade if signal is valid
   if(signal != 0)
   {
      ExecuteTrade(signal);
   }
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check and reset daily loss tracking                              |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime currentTime, lastResetTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastResetDate, lastResetTime);

   // Check if date has changed
   if(currentTime.day != lastResetTime.day ||
      currentTime.mon != lastResetTime.mon ||
      currentTime.year != lastResetTime.year)
   {
      // New day - reset tracking
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyLimitReached = false;
      lastResetDate = TimeCurrent();
      Print("Daily loss limit reset. New start balance: ", dailyStartBalance);
   }

   // Check if daily loss limit is reached
   if(DailyLossLimit_Enable && !dailyLimitReached)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double lossPercent = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;

      if(lossPercent >= DailyLossLimit_Percent)
      {
         dailyLimitReached = true;
         Print("!!! DAILY LOSS LIMIT REACHED !!!");
         Print("Loss: ", lossPercent, "% | Limit: ", DailyLossLimit_Percent, "%");
         Print("Trading suspended until next day.");
      }
   }
}

//+------------------------------------------------------------------+
//| Copy indicator data to buffers                                   |
//+------------------------------------------------------------------+
bool CopyIndicatorData()
{
   if(CopyBuffer(handleEMA_Mid, 0, 0, 5, bufferEMA_Mid) < 5) return false;
   if(CopyBuffer(handleEMA_Long, 0, 0, 3, bufferEMA_Long) < 3) return false;
   if(CopyBuffer(handleEMA_MTF, 0, 0, 21, bufferEMA_MTF) < 21) return false;
   if(CopyBuffer(handleADX, 0, 0, 3, bufferADX) < 3) return false;
   if(CopyBuffer(handleATR, 0, 0, 21, bufferATR) < 21) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check time filter                                                |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;

   // Handle wrap-around (e.g., 12:00 to 05:00 next day)
   if(Trade_Start_Hour > Trade_End_Hour)
   {
      return (currentHour >= Trade_Start_Hour || currentHour < Trade_End_Hour);
   }
   else
   {
      return (currentHour >= Trade_Start_Hour && currentHour < Trade_End_Hour);
   }
}

//+------------------------------------------------------------------+
//| Check ATR volatility filter                                      |
//+------------------------------------------------------------------+
bool CheckATRFilter()
{
   double currentATR = bufferATR[0];

   // Calculate average ATR over 20 periods
   double sumATR = 0;
   for(int i = 0; i < 20; i++)
   {
      sumATR += bufferATR[i];
   }
   double avgATR = sumATR / 20.0;

   if(avgATR == 0) return false;

   double atrRatio = currentATR / avgATR;

   // Check if ATR is within acceptable range
   if(atrRatio < ATR_Min_Multiplier || atrRatio > ATR_Max_Multiplier)
   {
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Get MTF (H4) trend direction                                     |
//+------------------------------------------------------------------+
int GetMTFTrend()
{
   // Compare current H4 EMA with 20 bars ago
   double currentEMA = bufferEMA_MTF[0];
   double pastEMA = bufferEMA_MTF[20];

   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
   double threshold = 10 * 10 * point; // 10 pips (gold is typically 5 digits)

   double diff = currentEMA - pastEMA;

   if(diff > threshold)
      return 1;  // Uptrend
   else if(diff < -threshold)
      return -1; // Downtrend
   else
      return 0;  // Range
}

//+------------------------------------------------------------------+
//| Check Granville's Law signals                                    |
//+------------------------------------------------------------------+
int CheckGranvilleSignal(int mtfTrend)
{
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
   double proximityThreshold = MA_Proximity_Pips * 10 * point; // Convert pips to price

   double close0 = iClose(Symbol_to_Trade, PERIOD_CURRENT, 0);
   double close1 = iClose(Symbol_to_Trade, PERIOD_CURRENT, 1);
   double close2 = iClose(Symbol_to_Trade, PERIOD_CURRENT, 2);

   double ema0 = bufferEMA_Mid[0];
   double ema1 = bufferEMA_Mid[1];
   double ema2 = bufferEMA_Mid[2];
   double ema3 = bufferEMA_Mid[3];

   double ema200 = bufferEMA_Long[0];
   double adx = bufferADX[0];

   // Filter 1: MTF trend must match
   // (already passed via mtfTrend parameter)

   // Filter 2: Local trend check - 3 consecutive EMA rises/falls
   bool localUptrend = (ema0 > ema1) && (ema1 > ema2) && (ema2 > ema3);
   bool localDowntrend = (ema0 < ema1) && (ema1 < ema2) && (ema2 < ema3);

   // Filter 3: ADX trend strength
   if(adx < ADX_Min_Level)
      return 0;

   // Filter 4: ATR already checked in OnTick

   // Filter 5: 200 EMA filter
   bool above200 = close0 > ema200;
   bool below200 = close0 < ema200;

   // Filter 6: MA proximity check
   double distanceToMA = MathAbs(close0 - ema0);
   bool nearMA = distanceToMA <= proximityThreshold;

   // Check for MA touch on previous bar
   double distancePrev = MathAbs(close1 - ema1);
   bool touchedMA = distancePrev <= proximityThreshold;

   // Filter 7: Time filter already checked in OnTick

   // === BUY SIGNALS ===
   if(mtfTrend == 1 && localUptrend && above200)
   {
      // Rule 1: Price crosses above MA (new trend)
      if(close1 <= ema1 && close0 > ema0)
      {
         Print("BUY Signal: Granville Rule 1 (New uptrend)");
         return 1;
      }

      // Rule 2: Price dips below MA then recovers (false break)
      if(close2 < ema2 && close1 < ema1 && close0 > ema0)
      {
         Print("BUY Signal: Granville Rule 2 (False break recovery)");
         return 1;
      }

      // Rule 3: Pullback to MA (dip buying)
      if(touchedMA && close0 > ema0)
      {
         Print("BUY Signal: Granville Rule 3 (Pullback to MA)");
         return 1;
      }

      // Alternative: Near MA and bouncing
      if(nearMA && close0 > close1)
      {
         Print("BUY Signal: Granville Rule 3 variant (Near MA bounce)");
         return 1;
      }
   }

   // === SELL SIGNALS ===
   if(mtfTrend == -1 && localDowntrend && below200)
   {
      // Rule 5: Price crosses below MA (new downtrend)
      if(close1 >= ema1 && close0 < ema0)
      {
         Print("SELL Signal: Granville Rule 5 (New downtrend)");
         return -1;
      }

      // Rule 6: Price spikes above MA then falls (false break)
      if(close2 > ema2 && close1 > ema1 && close0 < ema0)
      {
         Print("SELL Signal: Granville Rule 6 (False break recovery)");
         return -1;
      }

      // Rule 7: Rally to MA (rally selling)
      if(touchedMA && close0 < ema0)
      {
         Print("SELL Signal: Granville Rule 7 (Rally to MA)");
         return -1;
      }

      // Alternative: Near MA and falling
      if(nearMA && close0 < close1)
      {
         Print("SELL Signal: Granville Rule 7 variant (Near MA fall)");
         return -1;
      }
   }

   return 0; // No signal
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   double price = (signal > 0) ? SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK) :
                                  SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   // Calculate SL based on swing high/low
   double sl = CalculateStopLoss(signal);

   // Calculate lot size
   double lotSize = CalculateLotSize(price, sl);

   // Calculate TP
   double slDistance = MathAbs(price - sl);
   double tp = (signal > 0) ? price + (slDistance * TakeProfit_Ratio) :
                               price - (slDistance * TakeProfit_Ratio);

   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol_to_Trade;
   request.volume = lotSize;
   request.type = (signal > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = "Granville EA";

   // Send order
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
      {
         currentTicket = result.order;
         Print("=== TRADE OPENED ===");
         Print("Type: ", (signal > 0 ? "BUY" : "SELL"));
         Print("Price: ", price);
         Print("SL: ", sl, " (", slDistance / SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) / 10, " pips)");
         Print("TP: ", tp);
         Print("Lot: ", lotSize);
         Print("Ticket: ", result.order);
      }
      else
      {
         Print("Order failed: ", result.retcode);
      }
   }
   else
   {
      Print("OrderSend error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate stop loss based on swing high/low                      |
//+------------------------------------------------------------------+
double CalculateStopLoss(int signal)
{
   double swingLevel = 0;
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // Look for swing high/low in last 20 bars
   if(signal > 0) // Buy - find swing low
   {
      double lowest = iLow(Symbol_to_Trade, PERIOD_CURRENT, 1);
      for(int i = 2; i <= 20; i++)
      {
         double low = iLow(Symbol_to_Trade, PERIOD_CURRENT, i);
         if(low < lowest) lowest = low;
      }
      swingLevel = lowest - (10 * 10 * point); // 10 pips below swing low
   }
   else // Sell - find swing high
   {
      double highest = iHigh(Symbol_to_Trade, PERIOD_CURRENT, 1);
      for(int i = 2; i <= 20; i++)
      {
         double high = iHigh(Symbol_to_Trade, PERIOD_CURRENT, i);
         if(high > highest) highest = high;
      }
      swingLevel = highest + (10 * 10 * point); // 10 pips above swing high
   }

   // Fallback: if swing level is too close or not found, use 2% of entry price
   double price = (signal > 0) ? SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK) :
                                  SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
   double fallbackSL = (signal > 0) ? price * 0.98 : price * 1.02;

   if(swingLevel == 0 || MathAbs(price - swingLevel) < 50 * 10 * point)
   {
      swingLevel = fallbackSL;
   }

   return swingLevel;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   double slDistance = MathAbs(entryPrice - stopLoss);
   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   if(slDistance == 0 || tickSize == 0) return minLot;

   double lotSize = (riskAmount * tickSize) / (slDistance * tickValue);

   // Round to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   // Apply limits
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   if(lotSize > Max_Lot_Size) lotSize = Max_Lot_Size;

   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage existing position (partial TP, break-even)                |
//+------------------------------------------------------------------+
void ManagePosition()
{
   if(!PositionSelect(Symbol_to_Trade)) return;

   double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double positionSL = PositionGetDouble(POSITION_SL);
   double positionTP = PositionGetDouble(POSITION_TP);
   double positionVolume = PositionGetDouble(POSITION_VOLUME);
   long positionType = PositionGetInteger(POSITION_TYPE);

   double currentPrice = (positionType == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID) :
                         SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);

   double slDistance = MathAbs(positionOpenPrice - positionSL);
   double tpDistance = MathAbs(positionTP - positionOpenPrice);

   // Partial Take Profit
   if(PartialTP_Enable && !partialTPExecuted)
   {
      double triggerDistance = tpDistance * (PartialTP_Trigger_Percent / 100.0);
      double currentProfit = (positionType == POSITION_TYPE_BUY) ?
                             (currentPrice - positionOpenPrice) :
                             (positionOpenPrice - currentPrice);

      if(currentProfit >= triggerDistance)
      {
         double closeVolume = positionVolume * (PartialTP_Close_Percent / 100.0);
         closeVolume = NormalizeDouble(closeVolume, 2);

         MqlTradeRequest request = {};
         MqlTradeResult result = {};

         request.action = TRADE_ACTION_DEAL;
         request.symbol = Symbol_to_Trade;
         request.volume = closeVolume;
         request.type = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = currentPrice;
         request.deviation = 10;
         request.magic = 123456;
         request.comment = "Partial TP";

         if(OrderSend(request, result))
         {
            Print("=== PARTIAL TP EXECUTED ===");
            Print("Closed: ", closeVolume, " lots at ", currentPrice);
            partialTPExecuted = true;
         }
      }
   }

   // Break Even
   if(BreakEven_Enable && !breakEvenExecuted)
   {
      double triggerDistance = slDistance * (BreakEven_Trigger_Percent / 100.0);
      double currentProfit = (positionType == POSITION_TYPE_BUY) ?
                             (currentPrice - positionOpenPrice) :
                             (positionOpenPrice - currentPrice);

      if(currentProfit >= triggerDistance)
      {
         double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
         double newSL = (positionType == POSITION_TYPE_BUY) ?
                        positionOpenPrice + (BreakEven_Offset_Pips * 10 * point) :
                        positionOpenPrice - (BreakEven_Offset_Pips * 10 * point);

         MqlTradeRequest request = {};
         MqlTradeResult result = {};

         request.action = TRADE_ACTION_SLTP;
         request.symbol = Symbol_to_Trade;
         request.sl = newSL;
         request.tp = positionTP;

         if(OrderSend(request, result))
         {
            Print("=== BREAK-EVEN ACTIVATED ===");
            Print("New SL: ", newSL);
            breakEvenExecuted = true;
         }
      }
   }
}
//+------------------------------------------------------------------+
