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
string infoLabelName = "LC_InfoLabel";
string tpLabelName = "LC_TPLabel";

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

   //--- Create info label
   if(ObjectFind(0, infoLabelName) < 0)
   {
      bool created = ObjectCreate(0, infoLabelName, OBJ_LABEL, 0, 0, 0);
      Print("Info Label Create Result: ", created);
      if(created)
      {
         ObjectSetInteger(0, infoLabelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, infoLabelName, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, infoLabelName, OBJPROP_YDISTANCE, 30);
         ObjectSetInteger(0, infoLabelName, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, infoLabelName, OBJPROP_FONTSIZE, 10);
         ObjectSetString(0, infoLabelName, OBJPROP_FONT, "Courier New");
         Print("Info Label configured successfully");
      }
      else
      {
         Print("ERROR: Failed to create Info Label! Error code: ", GetLastError());
      }
   }
   else
   {
      Print("Info Label already exists");
   }

   //--- Create TP label
   if(ObjectFind(0, tpLabelName) < 0)
   {
      bool created = ObjectCreate(0, tpLabelName, OBJ_LABEL, 0, 0, 0);
      Print("TP Label Create Result: ", created);
      if(created)
      {
         ObjectSetInteger(0, tpLabelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, tpLabelName, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, tpLabelName, OBJPROP_YDISTANCE, 200);
         ObjectSetInteger(0, tpLabelName, OBJPROP_COLOR, clrLime);
         ObjectSetInteger(0, tpLabelName, OBJPROP_FONTSIZE, 10);
         ObjectSetString(0, tpLabelName, OBJPROP_FONT, "Courier New");
         Print("TP Label configured successfully");
      }
      else
      {
         Print("ERROR: Failed to create TP Label! Error code: ", GetLastError());
      }
   }
   else
   {
      Print("TP Label already exists");
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
   //--- Delete all objects
   ObjectDelete(0, slLineName);
   ObjectDelete(0, tpLineName);
   ObjectDelete(0, infoLabelName);
   ObjectDelete(0, tpLabelName);
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

   //--- Update info label
   string displayText = "";
   displayText += "[ロット計算結果]\n";
   displayText += "───────────────────\n";
   displayText += StringFormat("現在価格: %s\n", DoubleToString(currentPrice, _Digits));
   displayText += StringFormat("口座残高: %.2f JPY\n", accountBalance);
   displayText += "\n";
   displayText += StringFormat("損切り価格: %s\n", DoubleToString(slPrice, _Digits));
   displayText += StringFormat("損切り幅: %.1f Pips\n", slPips);
   displayText += StringFormat("許容損失: %.2f JPY (%.1f%%)\n", maxLossAmount, RiskPercent);
   displayText += "\n";
   displayText += StringFormat("推奨ロット: %." + IntegerToString(LotDigits) + "f Lot\n", normalizedLots);
   displayText += StringFormat("最大損失額: %.2f JPY", maxLossAmount);

   bool infoSet = ObjectSetString(0, infoLabelName, OBJPROP_TEXT, displayText);
   if(debugCounter % 100 == 0)
   {
      Print("Info Label Text Set Result: ", infoSet);
      if(!infoSet) Print("ERROR: Failed to set info label text! Error: ", GetLastError());
   }

   //--- Update TP label
   string tpText = "";
   tpText += "[利確ライン情報]\n";
   tpText += "───────────────────\n";
   tpText += StringFormat("利確価格: %s\n", DoubleToString(tpPrice, _Digits));
   tpText += StringFormat("利確幅: %.1f Pips\n", tpPips);
   tpText += StringFormat("リスクリワード: 1:%.2f\n", rrRatio);
   tpText += StringFormat("想定利益: %.2f JPY", expectedProfit);

   bool tpSet = ObjectSetString(0, tpLabelName, OBJPROP_TEXT, tpText);
   if(debugCounter % 100 == 0)
   {
      Print("TP Label Text Set Result: ", tpSet);
      if(!tpSet) Print("ERROR: Failed to set TP label text! Error: ", GetLastError());
   }

   //--- Force chart redraw
   ChartRedraw(0);
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
