//+------------------------------------------------------------------+
//|                                  GranvilleEA_M1_DayTrade.mq5     |
//|                      Granville's Law M1 Day Trading System       |
//|                    Based on v2.02 success (PF 1.83)              |
//+------------------------------------------------------------------+
#property copyright "Granville Gold Trading System"
#property link      ""
#property version   "2.10"
#property description "XAU/USD M1 Day Trading EA - Extended TP/SL for longer holds"
#property description "Based on v2.02 with 4x larger TP/SL"
#property description "Target: PF 1.5+, 10-30 trades/year, 2-8 hour holding"

//+------------------------------------------------------------------+
//| Input Parameters - OPTIMIZED FOR HIGH WIN RATE                   |
//+------------------------------------------------------------------+
// Basic Settings
input string   Symbol_to_Trade = "XAUUSD";
input double   Risk_Percent = 2.0;
input double   Max_Lot_Size = 10.0;

// Moving Average Settings
input int      MA_Fast = 5;
input int      MA_Mid = 13;
input int      MA_Slow = 21;
input int      MA_Filter = 50;
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_M15;
input int      MTF_MA_Period = 50;

// Day Trading Settings - EXTENDED FROM v2.02
input double   TakeProfit_Pips = 80.0;            // 20→80 pips (4x for day trading)
input double   StopLoss_Pips = 40.0;              // 10→40 pips (4x for day trading)
input double   MinRR_Ratio = 2.0;

// Filters - STRENGTHENED
input int      ADX_Period = 14;
input double   ADX_Min_Level = 18.0;              // 12→18 (STRONGER)
input int      RSI_Period = 14;
input double   RSI_OverboughtLevel = 75.0;        // 70→75
input double   RSI_OversoldLevel = 25.0;          // 30→25
input int      MinSignalCount = 2;                // NEW: Require 2+ signals

// EMA Distance Filter - NEW
input bool     UseEMADistanceFilter = true;
input double   MaxEMADistance_Pips = 30.0;        // Max distance from 13 EMA

// Risk Management - DAY TRADING OPTIMIZED
input bool     UseBreakEven = true;
input double   BreakEven_Trigger_Pips = 20.0;     // 8→20 pips (for day trading)
input int      BreakEven_Offset_Pips = 5;         // 3→5 pips

// Trailing Stop - NEW FOR DAY TRADING
input bool     UseTrailingStop = true;
input double   TrailingStop_Pips = 50.0;          // Trail at 50 pips
input double   TrailingStep_Pips = 10.0;          // Step 10 pips

// Prop Trading
input bool     DailyLossLimit_Enable = true;
input double   DailyLossLimit_Percent = 4.0;

// Time Filter - OPTIMIZED
input bool     TimeFilter_Enable = true;
input int      Trade_Start_Hour = 9;              // 8→9 (London open)
input int      Trade_End_Hour = 17;               // 22→17 (London close)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int handleEMA_Fast, handleEMA_Mid, handleEMA_Slow, handleEMA_Filter;
int handleEMA_MTF;
int handleADX, handleRSI;

double bufferEMA_Fast[], bufferEMA_Mid[], bufferEMA_Slow[], bufferEMA_Filter[];
double bufferEMA_MTF[];
double bufferADX[], bufferRSI[];

datetime lastBarTime = 0;
datetime lastResetDate = 0;
double dailyStartBalance = 0;
bool dailyLimitReached = false;
bool breakEvenExecuted = false;
ulong currentTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Granville M1 Day Trading EA v2.10");
   Print("========================================");
   Print("Symbol: ", Symbol_to_Trade);
   Print("TP: ", TakeProfit_Pips, " pips | SL: ", StopLoss_Pips, " pips");
   Print("R:R Ratio: ", (TakeProfit_Pips / StopLoss_Pips));
   Print("Trailing Stop: ", (UseTrailingStop ? "Enabled" : "Disabled"));
   Print("ADX Min: ", ADX_Min_Level);
   Print("Trading Hours: ", Trade_Start_Hour, ":00 - ", Trade_End_Hour, ":00");
   Print("Min Signals Required: ", MinSignalCount);
   Print("========================================");

   ArraySetAsSeries(bufferEMA_Fast, true);
   ArraySetAsSeries(bufferEMA_Mid, true);
   ArraySetAsSeries(bufferEMA_Slow, true);
   ArraySetAsSeries(bufferEMA_Filter, true);
   ArraySetAsSeries(bufferEMA_MTF, true);
   ArraySetAsSeries(bufferADX, true);
   ArraySetAsSeries(bufferRSI, true);

   handleEMA_Fast = iMA(Symbol_to_Trade, PERIOD_M1, MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Mid = iMA(Symbol_to_Trade, PERIOD_M1, MA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(Symbol_to_Trade, PERIOD_M1, MA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Filter = iMA(Symbol_to_Trade, PERIOD_M1, MA_Filter, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_MTF = iMA(Symbol_to_Trade, MTF_Timeframe, MTF_MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleADX = iADX(Symbol_to_Trade, PERIOD_M1, ADX_Period);
   handleRSI = iRSI(Symbol_to_Trade, PERIOD_M1, RSI_Period, PRICE_CLOSE);

   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Mid == INVALID_HANDLE ||
      handleEMA_Slow == INVALID_HANDLE || handleEMA_Filter == INVALID_HANDLE ||
      handleEMA_MTF == INVALID_HANDLE || handleADX == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastResetDate = TimeCurrent();

   ENUM_ORDER_TYPE_FILLING fillingMode = GetFillingMode(Symbol_to_Trade);
   string fillingModeStr = (fillingMode == ORDER_FILLING_FOK) ? "FOK" :
                           (fillingMode == ORDER_FILLING_IOC) ? "IOC" : "RETURN";
   Print("Filling Mode: ", fillingModeStr);

   Print("Initialization successful!");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA_Fast != INVALID_HANDLE) IndicatorRelease(handleEMA_Fast);
   if(handleEMA_Mid != INVALID_HANDLE) IndicatorRelease(handleEMA_Mid);
   if(handleEMA_Slow != INVALID_HANDLE) IndicatorRelease(handleEMA_Slow);
   if(handleEMA_Filter != INVALID_HANDLE) IndicatorRelease(handleEMA_Filter);
   if(handleEMA_MTF != INVALID_HANDLE) IndicatorRelease(handleEMA_MTF);
   if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   CheckDailyReset();

   if(PositionSelect(Symbol_to_Trade))
   {
      ManagePosition();
      return;
   }
   else
   {
      breakEvenExecuted = false;
      currentTicket = 0;
   }

   if(dailyLimitReached) return;
   if(TimeFilter_Enable && !CheckTimeFilter()) return;
   if(!CopyIndicatorData()) return;

   int mtfTrend = GetMTFTrend();
   if(mtfTrend == 0) return;

   int signal = CheckScalpingSignal_v2(mtfTrend);

   if(signal != 0)
   {
      ExecuteTrade(signal);
   }
}

//+------------------------------------------------------------------+
//| Check scalping signals v2 - STRICT MULTI-SIGNAL CONFIRMATION     |
//+------------------------------------------------------------------+
int CheckScalpingSignal_v2(int mtfTrend)
{
   double close0 = iClose(Symbol_to_Trade, PERIOD_M1, 0);
   double close1 = iClose(Symbol_to_Trade, PERIOD_M1, 1);
   double open0 = iOpen(Symbol_to_Trade, PERIOD_M1, 0);

   double emaFast0 = bufferEMA_Fast[0];
   double emaFast1 = bufferEMA_Fast[1];
   double emaMid0 = bufferEMA_Mid[0];
   double emaMid1 = bufferEMA_Mid[1];
   double emaSlow0 = bufferEMA_Slow[0];
   double emaFilter0 = bufferEMA_Filter[0];

   double adx = bufferADX[0];
   double rsi = bufferRSI[0];
   double pipSize = GetPipSize();

   // STRICT ADX filter
   if(adx < ADX_Min_Level) return 0;

   // === BUY SIGNALS ===
   if(mtfTrend == 1 && close0 > emaFilter0)
   {
      int signalCount = 0;
      string signals = "BUY Signals: ";

      // Signal 1: Fast EMA crosses above Mid EMA
      if(emaFast1 <= emaMid1 && emaFast0 > emaMid0 && emaMid0 > emaSlow0)
      {
         signalCount++;
         signals += "[EMAcross] ";
      }

      // Signal 2: Price bounces from Mid EMA
      if(close1 <= emaMid1 && close0 > emaMid0)
      {
         signalCount++;
         signals += "[Bounce] ";
      }

      // Signal 3: RSI oversold reversal
      if(rsi < RSI_OversoldLevel && close0 > emaSlow0)
      {
         signalCount++;
         signals += "[RSI] ";
      }

      // Signal 4: Triple EMA alignment + bullish candle
      bool tripleAlignment = (emaFast0 > emaMid0 && emaMid0 > emaSlow0);
      bool bullishCandle = (close0 > open0);
      if(tripleAlignment && bullishCandle && emaFast1 <= emaMid1)
      {
         signalCount++;
         signals += "[TripleEMA] ";
      }

      // Signal 5: Strong momentum (NEW)
      bool strongMomentum = (close0 - close1) > (10 * pipSize);
      if(strongMomentum && emaFast0 > emaMid0)
      {
         signalCount++;
         signals += "[Momentum] ";
      }

      // EMA Distance Filter (NEW)
      if(UseEMADistanceFilter)
      {
         double distanceToMid = MathAbs(close0 - emaMid0);
         if(distanceToMid > MaxEMADistance_Pips * pipSize)
         {
            return 0;  // Too far from EMA
         }
      }

      // Require minimum signals
      if(signalCount >= MinSignalCount)
      {
         Print(signals, "| Count: ", signalCount, " | ADX: ", adx);
         return 1;
      }
   }

   // === SELL SIGNALS ===
   if(mtfTrend == -1 && close0 < emaFilter0)
   {
      int signalCount = 0;
      string signals = "SELL Signals: ";

      // Signal 1: Fast EMA crosses below Mid EMA
      if(emaFast1 >= emaMid1 && emaFast0 < emaMid0 && emaMid0 < emaSlow0)
      {
         signalCount++;
         signals += "[EMAcross] ";
      }

      // Signal 2: Price bounces from Mid EMA
      if(close1 >= emaMid1 && close0 < emaMid0)
      {
         signalCount++;
         signals += "[Bounce] ";
      }

      // Signal 3: RSI overbought reversal
      if(rsi > RSI_OverboughtLevel && close0 < emaSlow0)
      {
         signalCount++;
         signals += "[RSI] ";
      }

      // Signal 4: Triple EMA alignment + bearish candle
      bool tripleAlignment = (emaFast0 < emaMid0 && emaMid0 < emaSlow0);
      bool bearishCandle = (close0 < open0);
      if(tripleAlignment && bearishCandle && emaFast1 >= emaMid1)
      {
         signalCount++;
         signals += "[TripleEMA] ";
      }

      // Signal 5: Strong momentum (NEW)
      bool strongMomentum = (close1 - close0) > (10 * pipSize);
      if(strongMomentum && emaFast0 < emaMid0)
      {
         signalCount++;
         signals += "[Momentum] ";
      }

      // EMA Distance Filter (NEW)
      if(UseEMADistanceFilter)
      {
         double distanceToMid = MathAbs(close0 - emaMid0);
         if(distanceToMid > MaxEMADistance_Pips * pipSize)
         {
            return 0;
         }
      }

      // Require minimum signals
      if(signalCount >= MinSignalCount)
      {
         Print(signals, "| Count: ", signalCount, " | ADX: ", adx);
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   double price = (signal > 0) ? SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK) :
                                  SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   double pipSize = GetPipSize();
   double slDistance = StopLoss_Pips * pipSize;
   double tpDistance = TakeProfit_Pips * pipSize;

   double sl = (signal > 0) ? price - slDistance : price + slDistance;
   double tp = (signal > 0) ? price + tpDistance : price - tpDistance;

   double lotSize = CalculateLotSize_v2(StopLoss_Pips);

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
   request.magic = 234568;
   request.comment = "Granville v2";
   request.type_filling = GetFillingMode(Symbol_to_Trade);

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
      {
         currentTicket = result.order;
         Print("=== TRADE OPENED v2 ===");
         Print("Type: ", (signal > 0 ? "BUY" : "SELL"));
         Print("Price: ", price, " | SL: ", sl, " | TP: ", tp);
         Print("Lot: ", lotSize, " | R:R: ", (TakeProfit_Pips/StopLoss_Pips));
      }
   }
}

//+------------------------------------------------------------------+
//| Helper functions (same as v2.01)                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_M1, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

void CheckDailyReset()
{
   MqlDateTime currentTime, lastResetTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastResetDate, lastResetTime);

   if(currentTime.day != lastResetTime.day || currentTime.mon != lastResetTime.mon ||
      currentTime.year != lastResetTime.year)
   {
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyLimitReached = false;
      lastResetDate = TimeCurrent();
      Print("Daily reset. Start balance: ", dailyStartBalance);
   }

   if(DailyLossLimit_Enable && !dailyLimitReached)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double lossPercent = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;

      if(lossPercent >= DailyLossLimit_Percent)
      {
         dailyLimitReached = true;
         Print("!!! DAILY LOSS LIMIT REACHED: ", lossPercent, "% !!!");
      }
   }
}

bool CopyIndicatorData()
{
   if(CopyBuffer(handleEMA_Fast, 0, 0, 5, bufferEMA_Fast) < 5) return false;
   if(CopyBuffer(handleEMA_Mid, 0, 0, 5, bufferEMA_Mid) < 5) return false;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 5, bufferEMA_Slow) < 5) return false;
   if(CopyBuffer(handleEMA_Filter, 0, 0, 3, bufferEMA_Filter) < 3) return false;
   if(CopyBuffer(handleEMA_MTF, 0, 0, 3, bufferEMA_MTF) < 3) return false;
   if(CopyBuffer(handleADX, 0, 0, 3, bufferADX) < 3) return false;
   if(CopyBuffer(handleRSI, 0, 0, 3, bufferRSI) < 3) return false;
   return true;
}

bool CheckTimeFilter()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;

   if(Trade_Start_Hour > Trade_End_Hour)
      return (currentHour >= Trade_Start_Hour || currentHour < Trade_End_Hour);
   else
      return (currentHour >= Trade_Start_Hour && currentHour < Trade_End_Hour);
}

int GetMTFTrend()
{
   double currentEMA = bufferEMA_MTF[0];
   double pastEMA = bufferEMA_MTF[2];
   double close = iClose(Symbol_to_Trade, MTF_Timeframe, 0);

   if(close > currentEMA && currentEMA > pastEMA)
      return 1;
   else if(close < currentEMA && currentEMA < pastEMA)
      return -1;
   else
      return 0;
}

double CalculateLotSize_v2(double slPips)
{
   string symbol = Symbol_to_Trade;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;
   double lossPerLot = numTicks * tickValue;

   double calculatedLots = 0.0;
   if(lossPerLot > 0)
   {
      calculatedLots = riskAmount / lossPerLot;
   }

   return NormalizeLotSize(calculatedLots);
}

double GetPipSize()
{
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);

   if(digits == 2 || digits == 3 || digits == 5)
      return point * 10;
   else
      return point;
}

double NormalizeLotSize(double lots)
{
   string symbol = Symbol_to_Trade;
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   double normalizedLots = MathFloor(lots / lotStep) * lotStep;

   if(normalizedLots < minLot) normalizedLots = minLot;
   if(normalizedLots > maxLot) normalizedLots = maxLot;
   if(normalizedLots > Max_Lot_Size) normalizedLots = Max_Lot_Size;

   return normalizedLots;
}

void ManagePosition()
{
   if(!PositionSelect(Symbol_to_Trade)) return;

   double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double positionSL = PositionGetDouble(POSITION_SL);
   double positionTP = PositionGetDouble(POSITION_TP);
   long positionType = PositionGetInteger(POSITION_TYPE);

   double currentPrice = (positionType == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID) :
                         SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);

   double pipSize = GetPipSize();

   // Break-Even Logic
   if(UseBreakEven && !breakEvenExecuted)
   {
      double triggerDistance = BreakEven_Trigger_Pips * pipSize;

      double currentProfit = (positionType == POSITION_TYPE_BUY) ?
                             (currentPrice - positionOpenPrice) :
                             (positionOpenPrice - currentPrice);

      if(currentProfit >= triggerDistance)
      {
         double newSL = (positionType == POSITION_TYPE_BUY) ?
                        positionOpenPrice + (BreakEven_Offset_Pips * pipSize) :
                        positionOpenPrice - (BreakEven_Offset_Pips * pipSize);

         MqlTradeRequest request = {};
         MqlTradeResult result = {};

         request.action = TRADE_ACTION_SLTP;
         request.symbol = Symbol_to_Trade;
         request.sl = newSL;
         request.tp = positionTP;

         if(OrderSend(request, result))
         {
            Print("=== BREAK-EVEN ACTIVATED ===");
            breakEvenExecuted = true;
         }
      }
   }

   // Trailing Stop Logic - FOR DAY TRADING
   if(UseTrailingStop && breakEvenExecuted)
   {
      double trailingDistance = TrailingStop_Pips * pipSize;
      double trailingStep = TrailingStep_Pips * pipSize;

      if(positionType == POSITION_TYPE_BUY)
      {
         double newSL = currentPrice - trailingDistance;

         // Only move SL if it's better than current SL and moves by at least one step
         if(newSL > positionSL + trailingStep)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_SLTP;
            request.symbol = Symbol_to_Trade;
            request.sl = newSL;
            request.tp = positionTP;

            if(OrderSend(request, result))
            {
               Print("=== TRAILING STOP UPDATED === BUY SL: ", positionSL, " -> ", newSL);
            }
         }
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         double newSL = currentPrice + trailingDistance;

         // Only move SL if it's better than current SL and moves by at least one step
         if(newSL < positionSL - trailingStep)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_SLTP;
            request.symbol = Symbol_to_Trade;
            request.sl = newSL;
            request.tp = positionTP;

            if(OrderSend(request, result))
            {
               Print("=== TRAILING STOP UPDATED === SELL SL: ", positionSL, " -> ", newSL);
            }
         }
      }
   }
}

ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
   int fillingMode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   if((fillingMode & 1) == 1)
      return ORDER_FILLING_FOK;
   else if((fillingMode & 2) == 2)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
