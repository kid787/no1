//+------------------------------------------------------------------+
//|                                                 GranvilleMA.mq5  |
//|                              Granville's Law Signal Indicator    |
//|                                      With MTF Trend & Filters    |
//+------------------------------------------------------------------+
#property copyright "Granville Gold Trading System"
#property link      ""
#property version   "1.00"
#property description "Displays Granville's Law signals with multi-timeframe analysis"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   6

//+------------------------------------------------------------------+
//| Input Parameters (Must match EA settings)                        |
//+------------------------------------------------------------------+
input int      MA_Period_Mid = 75;                 // Mid-term EMA period
input int      MA_Period_Long = 200;               // Long-term EMA period
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H4;   // MTF trend confirmation timeframe
input int      MA_Proximity_Pips = 100;            // MA proximity threshold (pips)

input int      ADX_Period = 14;                    // ADX period
input double   ADX_Min_Level = 20.0;               // Minimum ADX level

input int      ATR_Period = 14;                    // ATR period
input double   ATR_Min_Multiplier = 0.5;           // Minimum ATR multiplier
input double   ATR_Max_Multiplier = 2.0;           // Maximum ATR multiplier

input bool     TimeFilter_Enable = true;           // Enable time filter
input int      Trade_Start_Hour = 12;              // Trading start hour
input int      Trade_End_Hour = 5;                 // Trading end hour

input bool     Show_Heiken_Ashi = true;            // Show Heiken Ashi candles

//+------------------------------------------------------------------+
//| Indicator buffers                                                 |
//+------------------------------------------------------------------+
double EMA_Mid_Buffer[];
double EMA_Long_Buffer[];
double BuySignal_Buffer[];
double SellSignal_Buffer[];
double HA_Open[];
double HA_High[];
double HA_Low[];
double HA_Close[];

//+------------------------------------------------------------------+
//| Indicator handles                                                 |
//+------------------------------------------------------------------+
int handleEMA_Mid;
int handleEMA_Long;
int handleEMA_MTF;
int handleADX;
int handleATR;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set indicator buffers
   SetIndexBuffer(0, EMA_Mid_Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, EMA_Long_Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, BuySignal_Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, SellSignal_Buffer, INDICATOR_DATA);
   SetIndexBuffer(4, HA_Open, INDICATOR_DATA);
   SetIndexBuffer(5, HA_High, INDICATOR_DATA);
   SetIndexBuffer(6, HA_Low, INDICATOR_DATA);
   SetIndexBuffer(7, HA_Close, INDICATOR_DATA);

   // Set plot properties for EMA Mid
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrDodgerBlue);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetString(0, PLOT_LABEL, "EMA 75");

   // Set plot properties for EMA Long
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrCrimson);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);
   PlotIndexSetString(1, PLOT_LABEL, "EMA 200");

   // Set plot properties for Buy Signal
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(2, PLOT_ARROW, 233); // Up arrow
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, clrLime);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 3);
   PlotIndexSetString(2, PLOT_LABEL, "Buy Signal");

   // Set plot properties for Sell Signal
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(3, PLOT_ARROW, 234); // Down arrow
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, 3);
   PlotIndexSetString(3, PLOT_LABEL, "Sell Signal");

   // Set plot properties for Heiken Ashi
   if(Show_Heiken_Ashi)
   {
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES);
      PlotIndexSetInteger(4, PLOT_LINE_COLOR, 0, clrLimeGreen);  // Bullish
      PlotIndexSetInteger(4, PLOT_LINE_COLOR, 1, clrOrangeRed);  // Bearish
      PlotIndexSetString(4, PLOT_LABEL, "Heiken Ashi");
   }
   else
   {
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);

   // Set arrays as series
   ArraySetAsSeries(EMA_Mid_Buffer, true);
   ArraySetAsSeries(EMA_Long_Buffer, true);
   ArraySetAsSeries(BuySignal_Buffer, true);
   ArraySetAsSeries(SellSignal_Buffer, true);
   ArraySetAsSeries(HA_Open, true);
   ArraySetAsSeries(HA_High, true);
   ArraySetAsSeries(HA_Low, true);
   ArraySetAsSeries(HA_Close, true);

   // Initialize empty values
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0);

   // Create indicator handles
   handleEMA_Mid = iMA(_Symbol, PERIOD_CURRENT, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Long = iMA(_Symbol, PERIOD_CURRENT, MA_Period_Long, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_MTF = iMA(_Symbol, MTF_Timeframe, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   handleADX = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   handleATR = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   if(handleEMA_Mid == INVALID_HANDLE || handleEMA_Long == INVALID_HANDLE ||
      handleEMA_MTF == INVALID_HANDLE || handleADX == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }

   Print("Granville Indicator initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleEMA_Mid != INVALID_HANDLE) IndicatorRelease(handleEMA_Mid);
   if(handleEMA_Long != INVALID_HANDLE) IndicatorRelease(handleEMA_Long);
   if(handleEMA_MTF != INVALID_HANDLE) IndicatorRelease(handleEMA_MTF);
   if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);

   // Remove chart objects
   ObjectsDeleteAll(0, "GranvilleLabel_");
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
   if(rates_total < MA_Period_Long) return 0;

   int limit = rates_total - prev_calculated;
   if(limit > 1)
   {
      limit = rates_total - MA_Period_Long - 1;
      ArrayInitialize(BuySignal_Buffer, 0);
      ArrayInitialize(SellSignal_Buffer, 0);
   }

   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   // Copy EMA data
   double ema_mid[];
   double ema_long[];
   double ema_mtf[];
   double adx[];
   double atr[];

   ArraySetAsSeries(ema_mid, true);
   ArraySetAsSeries(ema_long, true);
   ArraySetAsSeries(ema_mtf, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(handleEMA_Mid, 0, 0, rates_total, ema_mid) <= 0) return 0;
   if(CopyBuffer(handleEMA_Long, 0, 0, rates_total, ema_long) <= 0) return 0;
   if(CopyBuffer(handleEMA_MTF, 0, 0, 30, ema_mtf) <= 0) return 0;
   if(CopyBuffer(handleADX, 0, 0, rates_total, adx) <= 0) return 0;
   if(CopyBuffer(handleATR, 0, 0, rates_total, atr) <= 0) return 0;

   // Calculate Heiken Ashi
   if(Show_Heiken_Ashi)
   {
      CalculateHeikenAshi(rates_total, prev_calculated, open, high, low, close);
   }

   // Process each bar
   for(int i = limit; i >= 0; i--)
   {
      // Copy EMA values to buffers
      EMA_Mid_Buffer[i] = ema_mid[i];
      EMA_Long_Buffer[i] = ema_long[i];

      // Don't check signals for the current forming bar (i=0)
      if(i == 0) continue;

      // Check for signals
      int signal = CheckGranvilleSignal(i, close, ema_mid, ema_long, ema_mtf, adx, atr);

      if(signal == 1) // Buy signal
      {
         BuySignal_Buffer[i] = low[i] - (100 * _Point);
         SellSignal_Buffer[i] = 0;
      }
      else if(signal == -1) // Sell signal
      {
         SellSignal_Buffer[i] = high[i] + (100 * _Point);
         BuySignal_Buffer[i] = 0;
      }
      else
      {
         BuySignal_Buffer[i] = 0;
         SellSignal_Buffer[i] = 0;
      }
   }

   // Update status labels (only on newest bar)
   if(prev_calculated != rates_total)
   {
      UpdateStatusLabels(ema_mtf, adx, atr);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate Heiken Ashi candles                                    |
//+------------------------------------------------------------------+
void CalculateHeikenAshi(int rates_total, int prev_calculated,
                         const double &open[], const double &high[],
                         const double &low[], const double &close[])
{
   int limit = rates_total - prev_calculated;
   if(limit > 1) limit = rates_total - 2;

   for(int i = limit; i >= 0; i--)
   {
      // HA Close = (O + H + L + C) / 4
      HA_Close[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;

      // HA Open = (HA Open prev + HA Close prev) / 2
      if(i == rates_total - 1)
         HA_Open[i] = (open[i] + close[i]) / 2.0;
      else
         HA_Open[i] = (HA_Open[i + 1] + HA_Close[i + 1]) / 2.0;

      // HA High = Max(H, HA Open, HA Close)
      HA_High[i] = MathMax(high[i], MathMax(HA_Open[i], HA_Close[i]));

      // HA Low = Min(L, HA Open, HA Close)
      HA_Low[i] = MathMin(low[i], MathMin(HA_Open[i], HA_Close[i]));
   }
}

//+------------------------------------------------------------------+
//| Check Granville signal (same logic as EA)                        |
//+------------------------------------------------------------------+
int CheckGranvilleSignal(int shift, const double &close[], const double &ema_mid[],
                         const double &ema_long[], const double &ema_mtf[],
                         const double &adx[], const double &atr[])
{
   // Check time filter
   if(TimeFilter_Enable && !CheckTimeFilter()) return 0;

   // Check ATR filter
   if(!CheckATRFilter(shift, atr)) return 0;

   // Get MTF trend
   int mtfTrend = GetMTFTrend(ema_mtf);
   if(mtfTrend == 0) return 0;

   // Check local trend
   if(shift + 3 >= ArraySize(ema_mid)) return 0;

   bool localUptrend = (ema_mid[shift] > ema_mid[shift + 1]) &&
                       (ema_mid[shift + 1] > ema_mid[shift + 2]) &&
                       (ema_mid[shift + 2] > ema_mid[shift + 3]);

   bool localDowntrend = (ema_mid[shift] < ema_mid[shift + 1]) &&
                         (ema_mid[shift + 1] < ema_mid[shift + 2]) &&
                         (ema_mid[shift + 2] < ema_mid[shift + 3]);

   // Check ADX
   if(adx[shift] < ADX_Min_Level) return 0;

   // Check 200 EMA filter
   bool above200 = close[shift] > ema_long[shift];
   bool below200 = close[shift] < ema_long[shift];

   // MA proximity
   double point = _Point;
   double proximityThreshold = MA_Proximity_Pips * 10 * point;
   double distanceToMA = MathAbs(close[shift] - ema_mid[shift]);
   bool nearMA = distanceToMA <= proximityThreshold;

   double distancePrev = MathAbs(close[shift + 1] - ema_mid[shift + 1]);
   bool touchedMA = distancePrev <= proximityThreshold;

   // BUY SIGNALS
   if(mtfTrend == 1 && localUptrend && above200)
   {
      // Rule 1: Cross above
      if(close[shift + 1] <= ema_mid[shift + 1] && close[shift] > ema_mid[shift])
         return 1;

      // Rule 2: False break recovery
      if(shift + 2 < ArraySize(close))
      {
         if(close[shift + 2] < ema_mid[shift + 2] &&
            close[shift + 1] < ema_mid[shift + 1] &&
            close[shift] > ema_mid[shift])
            return 1;
      }

      // Rule 3: Pullback
      if(touchedMA && close[shift] > ema_mid[shift])
         return 1;

      if(nearMA && close[shift] > close[shift + 1])
         return 1;
   }

   // SELL SIGNALS
   if(mtfTrend == -1 && localDowntrend && below200)
   {
      // Rule 5: Cross below
      if(close[shift + 1] >= ema_mid[shift + 1] && close[shift] < ema_mid[shift])
         return -1;

      // Rule 6: False break recovery
      if(shift + 2 < ArraySize(close))
      {
         if(close[shift + 2] > ema_mid[shift + 2] &&
            close[shift + 1] > ema_mid[shift + 1] &&
            close[shift] < ema_mid[shift])
            return -1;
      }

      // Rule 7: Rally
      if(touchedMA && close[shift] < ema_mid[shift])
         return -1;

      if(nearMA && close[shift] < close[shift + 1])
         return -1;
   }

   return 0;
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
//| Check ATR filter                                                 |
//+------------------------------------------------------------------+
bool CheckATRFilter(int shift, const double &atr[])
{
   if(shift + 20 >= ArraySize(atr)) return false;

   double currentATR = atr[shift];
   double sumATR = 0;

   for(int i = shift; i < shift + 20; i++)
   {
      sumATR += atr[i];
   }
   double avgATR = sumATR / 20.0;

   if(avgATR == 0) return false;

   double atrRatio = currentATR / avgATR;

   return (atrRatio >= ATR_Min_Multiplier && atrRatio <= ATR_Max_Multiplier);
}

//+------------------------------------------------------------------+
//| Get MTF trend                                                    |
//+------------------------------------------------------------------+
int GetMTFTrend(const double &ema_mtf[])
{
   if(ArraySize(ema_mtf) < 21) return 0;

   double currentEMA = ema_mtf[0];
   double pastEMA = ema_mtf[20];

   double point = _Point;
   double threshold = 10 * 10 * point;

   double diff = currentEMA - pastEMA;

   if(diff > threshold)
      return 1;
   else if(diff < -threshold)
      return -1;
   else
      return 0;
}

//+------------------------------------------------------------------+
//| Update status labels on chart                                    |
//+------------------------------------------------------------------+
void UpdateStatusLabels(const double &ema_mtf[], const double &adx[], const double &atr[])
{
   int mtfTrend = GetMTFTrend(ema_mtf);
   bool atrOK = CheckATRFilter(0, atr);
   bool adxOK = (adx[0] >= ADX_Min_Level);
   bool timeOK = !TimeFilter_Enable || CheckTimeFilter();

   // Calculate ATR ratio
   double currentATR = atr[0];
   double sumATR = 0;
   for(int i = 0; i < 20 && i < ArraySize(atr); i++)
   {
      sumATR += atr[i];
   }
   double avgATR = sumATR / 20.0;
   double atrRatio = (avgATR > 0) ? currentATR / avgATR : 0;

   // Label 1: MTF Trend
   string trendText = "H4トレンド: ";
   color trendColor = clrGray;

   if(mtfTrend == 1)
   {
      trendText += "⬆️上昇 (BUY優先)";
      trendColor = clrLime;
   }
   else if(mtfTrend == -1)
   {
      trendText += "⬇️下降 (SELL優先)";
      trendColor = clrRed;
   }
   else
   {
      trendText += "➡️レンジ";
      trendColor = clrYellow;
   }

   CreateLabel("GranvilleLabel_Trend", trendText, 10, 20, trendColor, 10);

   // Label 2: Filter Status
   string statusText = "";
   color statusColor = clrGray;

   if(adxOK && atrOK && timeOK)
   {
      statusText = "🟢 取引可能";
      statusColor = clrLime;
   }
   else
   {
      statusText = "🔴 フィルター待機";
      statusColor = clrRed;
   }

   statusText += "\nADX: " + DoubleToString(adx[0], 1) + (adxOK ? " ✅" : " ❌");
   statusText += "\nATR倍率: " + DoubleToString(atrRatio, 2) + (atrOK ? " ✅" : " ❌");
   statusText += "\n時間帯: " + (timeOK ? "✅" : "❌");

   CreateLabel("GranvilleLabel_Status", statusText, 10, 45, statusColor, 9);
}

//+------------------------------------------------------------------+
//| Create or update label                                           |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
}
//+------------------------------------------------------------------+
