//+------------------------------------------------------------------+
//|                                                LotCalculator.mq5 |
//|                                  MT5 Lot Size Calculator Utility |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "MT5 Lot Calculator"
#property link      ""
#property version   "2.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Input parameters
input double   RiskPercent      = 2.0;    // リスク許容度 (%)
input int      LotDigits        = 2;      // 表示桁数
input double   InitialSL_Pips   = 30.0;   // 初期損切り幅 (Pips)
input double   InitialTP_Pips   = 90.0;   // 初期利確幅 (Pips)
input int      LineWidth        = 2;      // ラインの太さ (1-5)

//--- Object names
string slLineName = "LC_StopLoss";
string tpLineName = "LC_TakeProfit";

//--- Global variables
double currentPrice = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== LotCalculator OnInit START ===");

   //--- Get current price
   currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("Current Price: ", currentPrice);

   //--- Calculate pip size
   double pipSize = GetPipSize();
   Print("Pip Size: ", pipSize);

   //--- Calculate initial line positions
   double slPrice = currentPrice - (InitialSL_Pips * pipSize);
   double tpPrice = currentPrice + (InitialTP_Pips * pipSize);
   Print("Initial SL Price: ", slPrice, " TP Price: ", tpPrice);

   //--- Create Stop Loss line (Red)
   if(ObjectFind(0, slLineName) < 0)
   {
      bool created = ObjectCreate(0, slLineName, OBJ_HLINE, 0, 0, slPrice);
      Print("SL Line Create Result: ", created, " at price: ", slPrice);
      if(created)
      {
         ObjectSetInteger(0, slLineName, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, slLineName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, slLineName, OBJPROP_WIDTH, LineWidth);
         ObjectSetInteger(0, slLineName, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, slLineName, OBJPROP_SELECTED, false);
         ObjectSetString(0, slLineName, OBJPROP_TEXT, "損切りライン");
         Print("SL Line configured successfully");
      }
      else
      {
         Print("ERROR: Failed to create SL Line! Error code: ", GetLastError());
      }
   }
   else
   {
      Print("SL Line already exists");
   }

   //--- Create Take Profit line (Green)
   if(ObjectFind(0, tpLineName) < 0)
   {
      bool created = ObjectCreate(0, tpLineName, OBJ_HLINE, 0, 0, tpPrice);
      Print("TP Line Create Result: ", created, " at price: ", tpPrice);
      if(created)
      {
         ObjectSetInteger(0, tpLineName, OBJPROP_COLOR, clrLime);
         ObjectSetInteger(0, tpLineName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, tpLineName, OBJPROP_WIDTH, LineWidth);
         ObjectSetInteger(0, tpLineName, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, tpLineName, OBJPROP_SELECTED, false);
         ObjectSetString(0, tpLineName, OBJPROP_TEXT, "利確ライン");
         Print("TP Line configured successfully");
      }
      else
      {
         Print("ERROR: Failed to create TP Line! Error code: ", GetLastError());
      }
   }
   else
   {
      Print("TP Line already exists");
   }

   //--- Initial calculation
   UpdateCalculations();

   Print("=== LotCalculator OnInit END ===");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete line objects
   ObjectDelete(0, slLineName);
   ObjectDelete(0, tpLineName);

   //--- Delete label objects
   ObjectDelete(0, "LC_LotDisplay");
   ObjectDelete(0, "LC_Info1");
   ObjectDelete(0, "LC_Info2");
   ObjectDelete(0, "LC_Info3");

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Update calculations on every tick
   UpdateCalculations();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   //--- Check if object was modified (dragged)
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(sparam == slLineName || sparam == tpLineName)
      {
         UpdateCalculations();
      }
   }
}

//+------------------------------------------------------------------+
//| Update all calculations and displays                             |
//+------------------------------------------------------------------+
void UpdateCalculations()
{
   //--- Update current price
   currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Get line prices
   double slPrice = ObjectGetDouble(0, slLineName, OBJPROP_PRICE);
   double tpPrice = ObjectGetDouble(0, tpLineName, OBJPROP_PRICE);

   //--- Check if lines exist and have valid prices
   if(slPrice == 0 || tpPrice == 0)
   {
      Print("Error: Line prices are zero. SL=", slPrice, " TP=", tpPrice);
      return;
   }

   //--- Calculate distances in pips
   double pipSize = GetPipSize();
   double slPips = MathAbs(currentPrice - slPrice) / pipSize;
   double tpPips = MathAbs(tpPrice - currentPrice) / pipSize;

   //--- Calculate lot size based on SL
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLossAmount = accountBalance * (RiskPercent / 100.0);
   double lossPerLot = CalculateLossPerLot(slPips);

   double calculatedLots = 0.0;
   if(lossPerLot > 0)
   {
      calculatedLots = maxLossAmount / lossPerLot;
   }
   double normalizedLots = NormalizeLotSize(calculatedLots);

   //--- Calculate risk-reward ratio
   double rrRatio = 0.0;
   if(slPips > 0)
   {
      rrRatio = tpPips / slPips;
   }

   //--- Calculate expected profit
   double profitPerLot = CalculateProfitPerLot(tpPips);
   double expectedProfit = profitPerLot * normalizedLots;

   //--- Debug output (comment out after testing)
   static int debugCounter = 0;
   if(debugCounter % 100 == 0)  // Print every 100 ticks to avoid spam
   {
      Print("=== LOT CALCULATOR DEBUG ===");
      Print("CurrentPrice=", currentPrice, " SL=", slPrice, " TP=", tpPrice);
      Print("SLPips=", slPips, " TPPips=", tpPips);
      Print("Balance=", accountBalance, " MaxLoss=", maxLossAmount);
      Print("LossPerLot=", lossPerLot, " CalcLots=", calculatedLots);
      Print("NormalizedLots=", normalizedLots, " RR=", rrRatio);
      Print("===========================");
   }
   debugCounter++;

   //--- Create or update display labels at lower left corner
   int yPos = 30;  // Starting Y position from bottom
   int yStep = 15; // Line spacing

   // Main lot size display (large font)
   string lotLabel = "LC_LotDisplay";
   if(ObjectFind(0, lotLabel) < 0)
      ObjectCreate(0, lotLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, lotLabel, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, lotLabel, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, lotLabel, OBJPROP_YDISTANCE, yPos);
   ObjectSetInteger(0, lotLabel, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, lotLabel, OBJPROP_FONTSIZE, 24);
   ObjectSetString(0, lotLabel, OBJPROP_FONT, "Arial Black");
   ObjectSetString(0, lotLabel, OBJPROP_TEXT, StringFormat("推奨: %." + IntegerToString(LotDigits) + "f Lot", normalizedLots));
   yPos += 35;

   // Supporting information (smaller font)
   string info1 = "LC_Info1";
   if(ObjectFind(0, info1) < 0)
      ObjectCreate(0, info1, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, info1, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, info1, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, info1, OBJPROP_YDISTANCE, yPos);
   ObjectSetInteger(0, info1, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, info1, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, info1, OBJPROP_FONT, "Courier New");
   ObjectSetString(0, info1, OBJPROP_TEXT, StringFormat("SL: %.1f pips | 損失: %.0f円 (%.1f%%)", slPips, maxLossAmount, RiskPercent));
   yPos += yStep;

   string info2 = "LC_Info2";
   if(ObjectFind(0, info2) < 0)
      ObjectCreate(0, info2, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, info2, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, info2, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, info2, OBJPROP_YDISTANCE, yPos);
   ObjectSetInteger(0, info2, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, info2, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, info2, OBJPROP_FONT, "Courier New");
   ObjectSetString(0, info2, OBJPROP_TEXT, StringFormat("TP: %.1f pips | RR 1:%.2f | 利益: %.0f円", tpPips, rrRatio, expectedProfit));
   yPos += yStep;

   string info3 = "LC_Info3";
   if(ObjectFind(0, info3) < 0)
      ObjectCreate(0, info3, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, info3, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, info3, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, info3, OBJPROP_YDISTANCE, yPos);
   ObjectSetInteger(0, info3, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, info3, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, info3, OBJPROP_FONT, "Courier New");
   ObjectSetString(0, info3, OBJPROP_TEXT, StringFormat("残高: %.0f円 | 価格: %s", accountBalance, DoubleToString(currentPrice, _Digits)));
}

//+------------------------------------------------------------------+
//| Get pip size for current symbol                                  |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double pipSize;
   if(digits == 3 || digits == 5)
   {
      // 5-digit or 3-digit broker
      pipSize = point * 10.0;
   }
   else
   {
      // 4-digit or 2-digit broker
      pipSize = point;
   }

   return pipSize;
}

//+------------------------------------------------------------------+
//| Calculate loss per 1 lot for given SL distance in pips          |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips)
{
   string symbol = _Symbol;

   //--- Get symbol properties
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   //--- Convert SL pips to price distance
   double slDistance = slPips * pipSize;

   //--- Calculate number of ticks in SL distance
   double numTicks = slDistance / tickSize;

   //--- Calculate loss per 1 lot in account currency
   double lossPerLot = numTicks * tickValue;

   return lossPerLot;
}

//+------------------------------------------------------------------+
//| Calculate profit per 1 lot for given TP distance in pips        |
//+------------------------------------------------------------------+
double CalculateProfitPerLot(double tpPips)
{
   string symbol = _Symbol;

   //--- Get symbol properties
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   //--- Convert TP pips to price distance
   double tpDistance = tpPips * pipSize;

   //--- Calculate number of ticks in TP distance
   double numTicks = tpDistance / tickSize;

   //--- Calculate profit per 1 lot in account currency
   double profitPerLot = numTicks * tickValue;

   return profitPerLot;
}

//+------------------------------------------------------------------+
//| Normalize lot size according to broker constraints              |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
   string symbol = _Symbol;

   //--- Get broker constraints
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   //--- Ensure lot is within min/max range
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   //--- Normalize to lot step
   lots = MathFloor(lots / lotStep) * lotStep;

   //--- Ensure it's still above minimum after rounding
   if(lots < minLot)
      lots = minLot;

   return lots;
}
//+------------------------------------------------------------------+
