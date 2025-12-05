//+------------------------------------------------------------------+
//|                                      GranvilleEA_M5_DayTrade.mq5 |
//|                           Granville's Law M5 Day Trading System  |
//|                           Optimized for 50-100 trades per year   |
//+------------------------------------------------------------------+
#property copyright "Granville Gold Trading System"
#property link      ""
#property version   "3.00"
#property description "XAU/USD M5 Day Trading EA"
#property description "Target: 2-8 hour holding time, PF 1.5+"
#property description "50-100 trades per year with trailing stop"

//+------------------------------------------------------------------+
//| Input Parameters - DAY TRADING OPTIMIZED                         |
//+------------------------------------------------------------------+
// Basic Settings
input string   Symbol_to_Trade = "XAUUSD";
input double   Risk_Percent = 2.0;
input double   Max_Lot_Size = 10.0;

// Moving Average Settings
input int      MA_Fast = 8;                        // 5→8 for M5
input int      MA_Mid = 21;                        // 13→21 for M5
input int      MA_Slow = 50;                       // 21→50 for M5
input int      MA_Filter = 100;                    // 50→100 for M5
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H1;   // M15→H1
input int      MTF_MA_Period = 50;

// Day Trading Settings
input double   TakeProfit_Pips = 60.0;             // 20→60 (day trading)
input double   StopLoss_Pips = 30.0;               // 10→30 (day trading)
input double   MinRR_Ratio = 2.0;

// Trailing Stop - NEW
input bool     UseTrailingStop = true;
input double   TrailingStop_Pips = 40.0;           // Trail at 40 pips
input double   TrailingStep_Pips = 10.0;           // Step 10 pips

// Filters - BALANCED
input int      ADX_Period = 14;
input double   ADX_Min_Level = 15.0;               // 18→15 (moderate)
input int      RSI_Period = 14;
input double   RSI_OverboughtLevel = 70.0;
input double   RSI_OversoldLevel = 30.0;
input int      MinSignalCount = 1;                 // 2→1 (more trades)

// EMA Distance Filter
input bool     UseEMADistanceFilter = true;
input double   MaxEMADistance_Pips = 50.0;         // 30→50 for M5

// Risk Management
input bool     UseBreakEven = true;
input double   BreakEven_Trigger_Pips = 15.0;      // 8→15 for day trade
input int      BreakEven_Offset_Pips = 5;

// Prop Trading
input bool     DailyLossLimit_Enable = true;
input double   DailyLossLimit_Percent = 4.0;

// Time Filter - EXTENDED
input bool     TimeFilter_Enable = true;
input int      Trade_Start_Hour = 8;               // London pre-open
input int      Trade_End_Hour = 21;                // 17→21 (NY session included)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int handleEMA_Fast, handleEMA_Mid, handleEMA_Slow, handleEMA_Filter;
int handleEMA_MTF, handleADX, handleRSI;

double bufferEMA_Fast[], bufferEMA_Mid[], bufferEMA_Slow[], bufferEMA_Filter[];
double bufferEMA_MTF[], bufferADX[], bufferRSI[];

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
   Print("Granville M5 Day Trading EA v3.00");
   Print("========================================");
   Print("Symbol: ", Symbol_to_Trade);
   Print("Timeframe: M5 Day Trading");
   Print("TP: ", TakeProfit_Pips, " pips | SL: ", StopLoss_Pips, " pips");
   Print("R:R: ", (TakeProfit_Pips/StopLoss_Pips));
   Print("Trailing Stop: ", (UseTrailingStop ? "Enabled" : "Disabled"));
   Print("Trading Hours: ", Trade_Start_Hour, ":00 - ", Trade_End_Hour, ":00");
   Print("========================================");

   ArraySetAsSeries(bufferEMA_Fast, true);
   ArraySetAsSeries(bufferEMA_Mid, true);
   ArraySetAsSeries(bufferEMA_Slow, true);
   ArraySetAsSeries(bufferEMA_Filter, true);
   ArraySetAsSeries(bufferEMA_MTF, true);
   ArraySetAsSeries(bufferADX, true);
   ArraySetAsSeries(bufferRSI, true);

   handleEMA_Fast = iMA(Symbol_to_Trade, PERIOD_M5, MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Mid = iMA(Symbol_to_Trade, PERIOD_M5, MA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(Symbol_to_Trade, PERIOD_M5, MA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Filter = iMA(Symbol_to_Trade, PERIOD_M5, MA_Filter, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_MTF = iMA(Symbol_to_Trade, MTF_Timeframe, MTF_MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleADX = iADX(Symbol_to_Trade, PERIOD_M5, ADX_Period);
   handleRSI = iRSI(Symbol_to_Trade, PERIOD_M5, RSI_Period, PRICE_CLOSE);

   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Mid == INVALID_HANDLE ||
      handleEMA_Slow == INVALID_HANDLE || handleEMA_Filter == INVALID_HANDLE ||
      handleEMA_MTF == INVALID_HANDLE || handleADX == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastResetDate = TimeCurrent();

   Print("Initialization successful!");
   return(INIT_SUCCEEDED);
}

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

   int signal = CheckDayTradeSignal(mtfTrend);

   if(signal != 0)
   {
      ExecuteTrade(signal);
   }
}

//+------------------------------------------------------------------+
//| Check day trading signals - BALANCED APPROACH                    |
//+------------------------------------------------------------------+
int CheckDayTradeSignal(int mtfTrend)
{
   double close0 = iClose(Symbol_to_Trade, PERIOD_M5, 0);
   double close1 = iClose(Symbol_to_Trade, PERIOD_M5, 1);
   double open0 = iOpen(Symbol_to_Trade, PERIOD_M5, 0);
   double high0 = iHigh(Symbol_to_Trade, PERIOD_M5, 0);
   double low0 = iLow(Symbol_to_Trade, PERIOD_M5, 0);

   double emaFast0 = bufferEMA_Fast[0];
   double emaFast1 = bufferEMA_Fast[1];
   double emaMid0 = bufferEMA_Mid[0];
   double emaMid1 = bufferEMA_Mid[1];
   double emaSlow0 = bufferEMA_Slow[0];
   double emaFilter0 = bufferEMA_Filter[0];

   double adx = bufferADX[0];
   double rsi = bufferRSI[0];
   double pipSize = GetPipSize();

   // ADX filter
   if(adx < ADX_Min_Level) return 0;

   // === BUY SIGNALS ===
   if(mtfTrend == 1 && close0 > emaFilter0)
   {
      int signalCount = 0;
      string signals = "BUY: ";

      // Signal 1: Fast EMA crosses above Mid EMA
      if(emaFast1 <= emaMid1 && emaFast0 > emaMid0)
      {
         signalCount++;
         signals += "[Cross] ";
      }

      // Signal 2: Price bounces from Mid EMA
      if(close1 <= emaMid1 && close0 > emaMid0 && low0 <= emaMid0)
      {
         signalCount++;
         signals += "[Bounce] ";
      }

      // Signal 3: RSI oversold reversal
      if(rsi < RSI_OversoldLevel)
      {
         signalCount++;
         signals += "[RSI] ";
      }

      // Signal 4: Strong bullish candle
      double candleBody = close0 - open0;
      double candleRange = high0 - low0;
      if(candleBody > 0 && candleBody > candleRange * 0.6)
      {
         signalCount++;
         signals += "[Candle] ";
      }

      // Signal 5: Triple EMA alignment
      if(emaFast0 > emaMid0 && emaMid0 > emaSlow0 && emaSlow0 > emaFilter0)
      {
         signalCount++;
         signals += "[EMA] ";
      }

      // EMA Distance Filter
      if(UseEMADistanceFilter)
      {
         double distance = MathAbs(close0 - emaMid0);
         if(distance > MaxEMADistance_Pips * pipSize) return 0;
      }

      if(signalCount >= MinSignalCount)
      {
         Print(signals, "Count: ", signalCount);
         return 1;
      }
   }

   // === SELL SIGNALS ===
   if(mtfTrend == -1 && close0 < emaFilter0)
   {
      int signalCount = 0;
      string signals = "SELL: ";

      // Signal 1: Fast EMA crosses below Mid EMA
      if(emaFast1 >= emaMid1 && emaFast0 < emaMid0)
      {
         signalCount++;
         signals += "[Cross] ";
      }

      // Signal 2: Price bounces from Mid EMA
      if(close1 >= emaMid1 && close0 < emaMid0 && high0 >= emaMid0)
      {
         signalCount++;
         signals += "[Bounce] ";
      }

      // Signal 3: RSI overbought reversal
      if(rsi > RSI_OverboughtLevel)
      {
         signalCount++;
         signals += "[RSI] ";
      }

      // Signal 4: Strong bearish candle
      double candleBody = open0 - close0;
      double candleRange = high0 - low0;
      if(candleBody > 0 && candleBody > candleRange * 0.6)
      {
         signalCount++;
         signals += "[Candle] ";
      }

      // Signal 5: Triple EMA alignment
      if(emaFast0 < emaMid0 && emaMid0 < emaSlow0 && emaSlow0 < emaFilter0)
      {
         signalCount++;
         signals += "[EMA] ";
      }

      // EMA Distance Filter
      if(UseEMADistanceFilter)
      {
         double distance = MathAbs(close0 - emaMid0);
         if(distance > MaxEMADistance_Pips * pipSize) return 0;
      }

      if(signalCount >= MinSignalCount)
      {
         Print(signals, "Count: ", signalCount);
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
   request.magic = 300000;
   request.comment = "Granville M5";
   request.type_filling = GetFillingMode(Symbol_to_Trade);

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
      {
         currentTicket = result.order;
         Print("=== DAY TRADE OPENED ===");
         Print("Type: ", (signal > 0 ? "BUY" : "SELL"));
         Print("Price: ", price, " | SL: ", sl, " (", StopLoss_Pips, " pips)");
         Print("TP: ", tp, " (", TakeProfit_Pips, " pips)");
         Print("Lot: ", lotSize, " | R:R: ", (TakeProfit_Pips/StopLoss_Pips));
      }
   }
}

//+------------------------------------------------------------------+
//| Manage position with trailing stop                               |
//+------------------------------------------------------------------+
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

   // Trailing Stop
   if(UseTrailingStop)
   {
      double currentProfit = (positionType == POSITION_TYPE_BUY) ?
                             (currentPrice - positionOpenPrice) :
                             (positionOpenPrice - currentPrice);

      double trailDistance = TrailingStop_Pips * pipSize;

      if(currentProfit >= trailDistance)
      {
         double newSL = 0;

         if(positionType == POSITION_TYPE_BUY)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > positionSL + (TrailingStep_Pips * pipSize))
            {
               ModifySL(newSL, positionTP);
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(newSL < positionSL - (TrailingStep_Pips * pipSize) || positionSL == 0)
            {
               ModifySL(newSL, positionTP);
            }
         }
      }
   }

   // Break Even
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

         ModifySL(newSL, positionTP);
         breakEvenExecuted = true;
         Print("=== BREAK-EVEN ACTIVATED ===");
      }
   }
}

void ModifySL(double newSL, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_SLTP;
   request.symbol = Symbol_to_Trade;
   request.sl = newSL;
   request.tp = tp;

   OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Helper functions                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_M5, 0);
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
   }

   if(DailyLossLimit_Enable && !dailyLimitReached)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double lossPercent = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;

      if(lossPercent >= DailyLossLimit_Percent)
      {
         dailyLimitReached = true;
         Print("!!! DAILY LOSS LIMIT: ", lossPercent, "% !!!");
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
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;
   double lossPerLot = numTicks * tickValue;

   double calculatedLots = (lossPerLot > 0) ? (riskAmount / lossPerLot) : 0;

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
   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   double normalizedLots = MathFloor(lots / lotStep) * lotStep;

   if(normalizedLots < minLot) normalizedLots = minLot;
   if(normalizedLots > maxLot) normalizedLots = maxLot;
   if(normalizedLots > Max_Lot_Size) normalizedLots = Max_Lot_Size;

   return normalizedLots;
}

ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
   int fillingMode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   if((fillingMode & 1) == 1) return ORDER_FILLING_FOK;
   else if((fillingMode & 2) == 2) return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
