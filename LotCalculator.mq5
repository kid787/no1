//+------------------------------------------------------------------+
//|                                                LotCalculator.mq5 |
//|                                  MT5 Lot Size Calculator Utility |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "MT5 Lot Calculator"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Input parameters
input double   RiskPercent      = 2.0;    // リスク許容度 (%)
input double   SL_Pips_Input    = 30.0;   // 損切り幅 (Pips)
input int      LotDigits        = 2;      // 表示桁数

//--- Global variables
string labelName = "LotCalculatorLabel";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create label object for displaying results
   if(ObjectFind(0, labelName) < 0)
   {
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Courier New");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete label object
   ObjectDelete(0, labelName);
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
   //--- Calculate lot size
   CalculateAndDisplayLotSize();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate and display lot size                                   |
//+------------------------------------------------------------------+
void CalculateAndDisplayLotSize()
{
   //--- Get account balance
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- Step A: Calculate maximum allowable loss (in JPY)
   double maxLossAmount = accountBalance * (RiskPercent / 100.0);

   //--- Step B: Calculate loss per 1 lot for specified SL distance
   double lossPerLot = CalculateLossPerLot(SL_Pips_Input);

   //--- Step C: Calculate appropriate lot size
   double calculatedLots = 0.0;
   if(lossPerLot > 0)
   {
      calculatedLots = maxLossAmount / lossPerLot;
   }

   //--- Step D: Normalize lot size according to broker constraints
   double normalizedLots = NormalizeLotSize(calculatedLots);

   //--- Prepare display text
   string displayText = "";
   displayText += "[ロット計算結果]\n";
   displayText += StringFormat("許容リスク: %.1f%% (最大損失: %.2f JPY)\n", RiskPercent, maxLossAmount);
   displayText += StringFormat("SL幅: %.1f Pips\n", SL_Pips_Input);
   displayText += StringFormat("推奨ロット数: %." + IntegerToString(LotDigits) + "f Lot\n", normalizedLots);
   displayText += "───────────────────\n";
   displayText += StringFormat("口座残高: %.2f JPY\n", accountBalance);
   displayText += StringFormat("1ロットあたり損失: %.2f JPY", lossPerLot);

   //--- Update label
   ObjectSetString(0, labelName, OBJPROP_TEXT, displayText);
   ChartRedraw();
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
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   //--- Calculate point value (digits adjustment for JPY pairs)
   // For most brokers, 1 pip = 10 points for JPY pairs (e.g., 0.01 for XXX/JPY)
   // For non-JPY pairs, 1 pip = 10 points (e.g., 0.0001 for EUR/USD)
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

   //--- Convert SL pips to price distance
   double slDistance = slPips * pipSize;

   //--- Calculate number of ticks in SL distance
   double numTicks = slDistance / tickSize;

   //--- Calculate loss per 1 lot in account currency
   // tickValue is the profit/loss in account currency for 1 tick movement per 1 lot
   double lossPerLot = numTicks * tickValue;

   return(lossPerLot);
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

   return(lots);
}
//+------------------------------------------------------------------+
