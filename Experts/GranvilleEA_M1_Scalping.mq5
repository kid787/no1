//+------------------------------------------------------------------+
//|                                      GranvilleEA_M1_Scalping.mq5 |
//|                           Granville's Law M1 Scalping System     |
//|                              High-frequency trading version      |
//+------------------------------------------------------------------+
#property copyright "Granville Gold Trading System"
#property link      ""
#property version   "2.00"
#property description "XAU/USD M1 Scalping EA based on Granville's Laws"
#property description "High-frequency trading with 2% risk management"
#property description "Target: 100x more trades than M30 version"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// Basic Settings
input string   Symbol_to_Trade = "XAUUSD";
input double   Risk_Percent = 2.0;                 // Risk (% of account balance)
input double   Max_Lot_Size = 10.0;                // Maximum lot size

// Moving Average Settings (Optimized for M1)
input int      MA_Fast = 5;                        // Fast EMA (M1 scalping)
input int      MA_Mid = 13;                        // Mid EMA (M1 scalping)
input int      MA_Slow = 21;                       // Slow EMA (M1 scalping)
input int      MA_Filter = 50;                     // Filter EMA (trend)
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_M15;  // MTF trend confirmation
input int      MTF_MA_Period = 50;                 // MTF EMA period

// Scalping Settings
input double   TakeProfit_Pips = 15.0;             // TP in pips (scalping)
input double   StopLoss_Pips = 10.0;               // SL in pips (scalping)
input double   MinRR_Ratio = 1.3;                  // Minimum Risk:Reward

// Filters
input int      ADX_Period = 14;
input double   ADX_Min_Level = 12.0;               // Lowered for M1
input int      RSI_Period = 14;
input double   RSI_OverboughtLevel = 70.0;
input double   RSI_OversoldLevel = 30.0;

// Risk Management
input bool     UseBreakEven = true;
input double   BreakEven_Trigger_Pips = 5.0;       // BE at 5 pips profit
input int      BreakEven_Offset_Pips = 2;

// Prop Trading
input bool     DailyLossLimit_Enable = true;
input double   DailyLossLimit_Percent = 4.0;

// Time Filter
input bool     TimeFilter_Enable = true;
input int      Trade_Start_Hour = 8;               // London open
input int      Trade_End_Hour = 22;                // NY close

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
// Indicator handles
int handleEMA_Fast, handleEMA_Mid, handleEMA_Slow, handleEMA_Filter;
int handleEMA_MTF;
int handleADX, handleRSI;

// Buffers
double bufferEMA_Fast[], bufferEMA_Mid[], bufferEMA_Slow[], bufferEMA_Filter[];
double bufferEMA_MTF[];
double bufferADX[], bufferRSI[];

// Bar tracking
datetime lastBarTime = 0;

// Daily loss tracking
datetime lastResetDate = 0;
double dailyStartBalance = 0;
bool dailyLimitReached = false;

// Position tracking
bool breakEvenExecuted = false;
ulong currentTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Granville M1 Scalping EA - Initializing");
   Print("========================================");
   Print("Symbol: ", Symbol_to_Trade);
   Print("Timeframe: M1 Scalping");
   Print("MTF Timeframe: ", EnumToString(MTF_Timeframe));
   Print("Risk: ", Risk_Percent, "%");
   Print("TP: ", TakeProfit_Pips, " pips | SL: ", StopLoss_Pips, " pips");
   Print("R:R Ratio: ", (TakeProfit_Pips / StopLoss_Pips));
   Print("========================================");

   // Set arrays as series
   ArraySetAsSeries(bufferEMA_Fast, true);
   ArraySetAsSeries(bufferEMA_Mid, true);
   ArraySetAsSeries(bufferEMA_Slow, true);
   ArraySetAsSeries(bufferEMA_Filter, true);
   ArraySetAsSeries(bufferEMA_MTF, true);
   ArraySetAsSeries(bufferADX, true);
   ArraySetAsSeries(bufferRSI, true);

   // Create indicator handles
   handleEMA_Fast = iMA(Symbol_to_Trade, PERIOD_M1, MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Mid = iMA(Symbol_to_Trade, PERIOD_M1, MA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(Symbol_to_Trade, PERIOD_M1, MA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Filter = iMA(Symbol_to_Trade, PERIOD_M1, MA_Filter, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_MTF = iMA(Symbol_to_Trade, MTF_Timeframe, MTF_MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleADX = iADX(Symbol_to_Trade, PERIOD_M1, ADX_Period);
   handleRSI = iRSI(Symbol_to_Trade, PERIOD_M1, RSI_Period, PRICE_CLOSE);

   // Check handles
   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Mid == INVALID_HANDLE ||
      handleEMA_Slow == INVALID_HANDLE || handleEMA_Filter == INVALID_HANDLE ||
      handleEMA_MTF == INVALID_HANDLE || handleADX == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }

   // Initialize daily loss tracking
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastResetDate = TimeCurrent();

   // Check filling mode
   ENUM_ORDER_TYPE_FILLING fillingMode = GetFillingMode(Symbol_to_Trade);
   string fillingModeStr = "";
   if(fillingMode == ORDER_FILLING_FOK) fillingModeStr = "FOK";
   else if(fillingMode == ORDER_FILLING_IOC) fillingModeStr = "IOC";
   else if(fillingMode == ORDER_FILLING_RETURN) fillingModeStr = "RETURN";
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

   Print("Granville M1 Scalping EA deinitialized. Reason: ", reason);
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

   // 3. Manage existing positions
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

   // 4. Check daily limit
   if(dailyLimitReached) return;

   // 5. Check time filter
   if(TimeFilter_Enable && !CheckTimeFilter()) return;

   // 6. Copy indicator data
   if(!CopyIndicatorData()) return;

   // 7. Get MTF trend
   int mtfTrend = GetMTFTrend();
   if(mtfTrend == 0) return; // No clear trend

   // 8. Check for scalping signals
   int signal = CheckScalpingSignal(mtfTrend);

   // 9. Execute trade
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
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_M1, 0);
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

   if(currentTime.day != lastResetTime.day || currentTime.mon != lastResetTime.mon ||
      currentTime.year != lastResetTime.year)
   {
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyLimitReached = false;
      lastResetDate = TimeCurrent();
      Print("Daily loss limit reset. Start balance: ", dailyStartBalance);
   }

   if(DailyLossLimit_Enable && !dailyLimitReached)
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double lossPercent = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;

      if(lossPercent >= DailyLossLimit_Percent)
      {
         dailyLimitReached = true;
         Print("!!! DAILY LOSS LIMIT REACHED !!!");
         Print("Loss: ", lossPercent, "% | Limit: ", DailyLossLimit_Percent, "%");
      }
   }
}

//+------------------------------------------------------------------+
//| Copy indicator data                                              |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Check time filter                                                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get MTF trend                                                    |
//+------------------------------------------------------------------+
int GetMTFTrend()
{
   double currentEMA = bufferEMA_MTF[0];
   double pastEMA = bufferEMA_MTF[2];
   double close = iClose(Symbol_to_Trade, MTF_Timeframe, 0);

   // Simpler MTF trend for scalping
   if(close > currentEMA && currentEMA > pastEMA)
      return 1;  // Uptrend
   else if(close < currentEMA && currentEMA < pastEMA)
      return -1; // Downtrend
   else
      return 0;  // No clear trend
}

//+------------------------------------------------------------------+
//| Check scalping signals (Multiple strategies)                     |
//+------------------------------------------------------------------+
int CheckScalpingSignal(int mtfTrend)
{
   double close0 = iClose(Symbol_to_Trade, PERIOD_M1, 0);
   double close1 = iClose(Symbol_to_Trade, PERIOD_M1, 1);

   double emaFast0 = bufferEMA_Fast[0];
   double emaFast1 = bufferEMA_Fast[1];
   double emaMid0 = bufferEMA_Mid[0];
   double emaMid1 = bufferEMA_Mid[1];
   double emaSlow0 = bufferEMA_Slow[0];
   double emaFilter0 = bufferEMA_Filter[0];

   double adx = bufferADX[0];
   double rsi = bufferRSI[0];

   // ADX filter (relaxed for M1)
   if(adx < ADX_Min_Level) return 0;

   // === BUY SIGNALS ===
   if(mtfTrend == 1 && close0 > emaFilter0)
   {
      // Signal 1: Fast EMA crosses above Mid EMA
      if(emaFast1 <= emaMid1 && emaFast0 > emaMid0 && emaMid0 > emaSlow0)
      {
         Print("BUY Signal 1: Fast EMA cross above Mid EMA");
         return 1;
      }

      // Signal 2: Price bounces from Mid EMA
      if(close1 <= emaMid1 && close0 > emaMid0 && emaFast0 > emaMid0)
      {
         Print("BUY Signal 2: Price bounce from Mid EMA");
         return 1;
      }

      // Signal 3: RSI oversold + price above Slow EMA
      if(rsi < RSI_OversoldLevel && close0 > emaSlow0 && emaFast0 > emaMid0)
      {
         Print("BUY Signal 3: RSI oversold + bullish structure");
         return 1;
      }

      // Signal 4: Triple EMA alignment (strong trend)
      if(emaFast0 > emaMid0 && emaMid0 > emaSlow0 &&
         emaFast1 <= emaMid1 && close0 > emaFast0)
      {
         Print("BUY Signal 4: Triple EMA alignment");
         return 1;
      }
   }

   // === SELL SIGNALS ===
   if(mtfTrend == -1 && close0 < emaFilter0)
   {
      // Signal 1: Fast EMA crosses below Mid EMA
      if(emaFast1 >= emaMid1 && emaFast0 < emaMid0 && emaMid0 < emaSlow0)
      {
         Print("SELL Signal 1: Fast EMA cross below Mid EMA");
         return -1;
      }

      // Signal 2: Price bounces from Mid EMA
      if(close1 >= emaMid1 && close0 < emaMid0 && emaFast0 < emaMid0)
      {
         Print("SELL Signal 2: Price bounce from Mid EMA");
         return -1;
      }

      // Signal 3: RSI overbought + price below Slow EMA
      if(rsi > RSI_OverboughtLevel && close0 < emaSlow0 && emaFast0 < emaMid0)
      {
         Print("SELL Signal 3: RSI overbought + bearish structure");
         return -1;
      }

      // Signal 4: Triple EMA alignment (strong trend)
      if(emaFast0 < emaMid0 && emaMid0 < emaSlow0 &&
         emaFast1 >= emaMid1 && close0 < emaFast0)
      {
         Print("SELL Signal 4: Triple EMA alignment");
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Execute trade with improved lot calculation                      |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   double price = (signal > 0) ? SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK) :
                                  SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
   double pipSize = GetPipSize();

   // Calculate SL/TP based on pips
   double slDistance = StopLoss_Pips * pipSize;
   double tpDistance = TakeProfit_Pips * pipSize;

   double sl = (signal > 0) ? price - slDistance : price + slDistance;
   double tp = (signal > 0) ? price + tpDistance : price - tpDistance;

   // Calculate lot size using improved method (2% risk)
   double lotSize = CalculateLotSize_v2(StopLoss_Pips);

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
   request.magic = 234567;
   request.comment = "Granville M1";
   request.type_filling = GetFillingMode(Symbol_to_Trade);

   // Send order
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
      {
         currentTicket = result.order;
         Print("=== TRADE OPENED ===");
         Print("Type: ", (signal > 0 ? "BUY" : "SELL"));
         Print("Price: ", price, " | SL: ", sl, " | TP: ", tp);
         Print("Lot: ", lotSize, " | Risk: ", Risk_Percent, "%");
         Print("Expected Profit: ", (tpDistance / point / 10), " pips");
      }
      else
      {
         Print("Order failed: ", result.retcode, " - ", GetErrorDescription(result.retcode));
      }
   }
   else
   {
      Print("OrderSend error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size v2 (from LotCalculator logic)                 |
//+------------------------------------------------------------------+
double CalculateLotSize_v2(double slPips)
{
   string symbol = Symbol_to_Trade;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   // Get symbol properties
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   // Convert SL pips to price distance
   double slDistance = slPips * pipSize;

   // Calculate number of ticks in SL distance
   double numTicks = slDistance / tickSize;

   // Calculate loss per 1 lot
   double lossPerLot = numTicks * tickValue;

   // Calculate lot size
   double calculatedLots = 0.0;
   if(lossPerLot > 0)
   {
      calculatedLots = riskAmount / lossPerLot;
   }

   // Normalize lot size
   double normalizedLots = NormalizeLotSize(calculatedLots);

   return normalizedLots;
}

//+------------------------------------------------------------------+
//| Get pip size                                                      |
//+------------------------------------------------------------------+
double GetPipSize()
{
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);

   // For 5-digit brokers (like XAUUSD): 1 pip = 10 points
   // For 3-digit brokers: 1 pip = 1 point
   if(digits == 5 || digits == 3)
      return point * 10;
   else
      return point;
}

//+------------------------------------------------------------------+
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
   string symbol = Symbol_to_Trade;
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   // Round to lot step
   double normalizedLots = MathFloor(lots / lotStep) * lotStep;

   // Apply limits
   if(normalizedLots < minLot) normalizedLots = minLot;
   if(normalizedLots > maxLot) normalizedLots = maxLot;
   if(normalizedLots > Max_Lot_Size) normalizedLots = Max_Lot_Size;

   return normalizedLots;
}

//+------------------------------------------------------------------+
//| Manage existing position                                         |
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

   // Break Even
   if(UseBreakEven && !breakEvenExecuted)
   {
      double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
      double pipSize = GetPipSize();
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
            Print("New SL: ", newSL);
            breakEvenExecuted = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get supported filling mode                                       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
   int fillingMode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   if((fillingMode & 1) == 1) // FOK
      return ORDER_FILLING_FOK;
   else if((fillingMode & 2) == 2) // IOC
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Get error description                                            |
//+------------------------------------------------------------------+
string GetErrorDescription(uint retcode)
{
   switch(retcode)
   {
      case 10004: return "Requote";
      case 10006: return "Request rejected";
      case 10007: return "Request canceled";
      case 10008: return "Order placed";
      case 10009: return "Request completed";
      case 10010: return "Only part executed";
      case 10011: return "Request processing error";
      case 10012: return "Request canceled by timeout";
      case 10013: return "Invalid request";
      case 10014: return "Invalid volume";
      case 10015: return "Invalid price";
      case 10016: return "Invalid stops";
      case 10017: return "Trade disabled";
      case 10018: return "Market closed";
      case 10019: return "Not enough money";
      case 10020: return "Prices changed";
      case 10021: return "No quotes";
      case 10022: return "Invalid expiration";
      case 10023: return "Order state changed";
      case 10024: return "Too many requests";
      case 10025: return "No changes";
      case 10026: return "Autotrading disabled by server";
      case 10027: return "Autotrading disabled by client";
      case 10028: return "Request locked";
      case 10029: return "Order or position frozen";
      case 10030: return "Invalid fill";
      case 10031: return "No connection";
      case 10032: return "Only real allowed";
      case 10033: return "Limit orders allowed";
      case 10034: return "Limit volume exceeded";
      case 10035: return "Invalid order type";
      case 10036: return "Position with specified ID not found";
      default: return "Unknown error";
   }
}
//+------------------------------------------------------------------+
