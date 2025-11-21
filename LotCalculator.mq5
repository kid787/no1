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
   //--- Get current price
   currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Calculate pip size
   double pipSize = GetPipSize();

   //--- Calculate initial line positions
   double slPrice = currentPrice - (InitialSL_Pips * pipSize);
   double tpPrice = currentPrice + (InitialTP_Pips * pipSize);

   //--- Create Stop Loss line (Red)
   if(ObjectFind(0, slLineName) < 0)
   {
      ObjectCreate(0, slLineName, OBJ_HLINE, 0, 0, slPrice);
      ObjectSetInteger(0, slLineName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, slLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, slLineName, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, slLineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, slLineName, OBJPROP_SELECTED, false);
      ObjectSetString(0, slLineName, OBJPROP_TEXT, "損切りライン");
   }

   //--- Create Take Profit line (Green)
   if(ObjectFind(0, tpLineName) < 0)
   {
      ObjectCreate(0, tpLineName, OBJ_HLINE, 0, 0, tpPrice);
      ObjectSetInteger(0, tpLineName, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, tpLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, tpLineName, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, tpLineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, tpLineName, OBJPROP_SELECTED, false);
      ObjectSetString(0, tpLineName, OBJPROP_TEXT, "利確ライン");
   }

   //--- Create info label
   if(ObjectFind(0, infoLabelName) < 0)
   {
      ObjectCreate(0, infoLabelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, infoLabelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, infoLabelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, infoLabelName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, infoLabelName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, infoLabelName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, infoLabelName, OBJPROP_FONT, "Courier New");
   }

   //--- Create TP label
   if(ObjectFind(0, tpLabelName) < 0)
   {
      ObjectCreate(0, tpLabelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, tpLabelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, tpLabelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, tpLabelName, OBJPROP_YDISTANCE, 200);
      ObjectSetInteger(0, tpLabelName, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, tpLabelName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, tpLabelName, OBJPROP_FONT, "Courier New");
   }

   //--- Initial calculation
   UpdateCalculations();

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
   //--- Update current price
   currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Update calculations periodically
   static datetime lastUpdate = 0;
   datetime currentTime = TimeCurrent();
   if(currentTime - lastUpdate >= 1)  // Update every second
   {
      UpdateCalculations();
      lastUpdate = currentTime;
   }

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

   ObjectSetString(0, infoLabelName, OBJPROP_TEXT, displayText);

   //--- Update TP label
   string tpText = "";
   tpText += "[利確ライン情報]\n";
   tpText += "───────────────────\n";
   tpText += StringFormat("利確価格: %s\n", DoubleToString(tpPrice, _Digits));
   tpText += StringFormat("利確幅: %.1f Pips\n", tpPips);
   tpText += StringFormat("リスクリワード: 1:%.2f\n", rrRatio);
   tpText += StringFormat("想定利益: %.2f JPY", expectedProfit);

   ObjectSetString(0, tpLabelName, OBJPROP_TEXT, tpText);

   ChartRedraw();
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
