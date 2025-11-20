//+------------------------------------------------------------------+
//|                               XAUUSD_NoEntry_Zone_Detector.mq5 |
//|                                    XAUUSD Non-Entry Zone Detector |
//|                     Detects Harami patterns on higher timeframes |
//+------------------------------------------------------------------+
#property copyright "XAUUSD No-Entry Zone Detector"
#property link      ""
#property version   "1.01"
#property indicator_chart_window
#property indicator_plots 0

//--- Input parameters
input ENUM_TIMEFRAMES Harami_Timeframe = PERIOD_H4;           // ハラミ足を検出する上位時間足
input int             Range_Pips_Min = 20;                     // 最小レンジ幅(pips)：これ未満は低ボラティリティゾーン
input color           Zone_Color = clrDimGray;                 // 非エントリーゾーンの背景色
input int             Zone_Opacity = 50;                       // ゾーンの透明度 (0-255)
input bool            Enable_MidRange_Alert = false;           // トレンド中盤の包み足検出を有効化
input int             MidRange_Period = 20;                    // 中盤判定用の期間
input bool            Alert_Breakout = true;                   // ゾーンブレイクアウト時のアラート
input color           LowVol_Zone_Color = clrYellow;           // 低ボラティリティゾーンの色
input int             LowVol_Zone_Opacity = 80;                // 低ボラティリティゾーンの透明度

//--- Global variables
struct HaramiZone
{
   datetime time_start;
   datetime time_end;
   double   high;
   double   low;
   bool     is_low_volatility;
   int      bar_index;
   bool     high_break_alerted;
   bool     low_break_alerted;
};

HaramiZone zones[];
int zones_count = 0;
datetime last_check_time = 0;
datetime last_bar_time = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   IndicatorSetString(INDICATOR_SHORTNAME, "XAUUSD NoEntry Zone Detector");

   //--- Check if higher timeframe is valid
   if(Harami_Timeframe < Period())
   {
      Print("警告: 指定された上位時間足が現在の時間足より小さいです。現在の時間足: ", EnumToString((ENUM_TIMEFRAMES)Period()));
   }

   //--- Initial scan
   ScanHaramiPatterns();
   DrawAllZones();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete all objects created by this indicator
   DeleteAllObjects();
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
   //--- Check for new bar on current timeframe
   datetime current_bar_time = time[rates_total-1];
   bool is_new_bar = (current_bar_time != last_bar_time);

   if(is_new_bar)
   {
      last_bar_time = current_bar_time;
   }

   //--- Check for new bar on higher timeframe
   datetime current_htf_time = iTime(_Symbol, Harami_Timeframe, 0);

   if(current_htf_time != last_check_time)
   {
      last_check_time = current_htf_time;
      ScanHaramiPatterns();
      DrawAllZones();
   }

   //--- Check for breakouts only on new bar if alert is enabled
   if(Alert_Breakout && is_new_bar && rates_total > 0)
   {
      CheckBreakouts(close[rates_total-1]);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Scan for Harami patterns on higher timeframe                    |
//+------------------------------------------------------------------+
void ScanHaramiPatterns()
{
   ArrayResize(zones, 0);
   zones_count = 0;

   int bars_to_scan = 100; // Scan last 100 bars of higher timeframe

   for(int i = 1; i < bars_to_scan; i++)
   {
      // Get data for parent candle (i) and child candle (i-1)
      double parent_high = iHigh(_Symbol, Harami_Timeframe, i);
      double parent_low = iLow(_Symbol, Harami_Timeframe, i);
      double parent_open = iOpen(_Symbol, Harami_Timeframe, i);
      double parent_close = iClose(_Symbol, Harami_Timeframe, i);

      double child_high = iHigh(_Symbol, Harami_Timeframe, i-1);
      double child_low = iLow(_Symbol, Harami_Timeframe, i-1);

      // Check for Harami pattern (inside bar)
      // Parent candle must completely engulf child candle
      if(parent_high > child_high && parent_low < child_low)
      {
         // Valid Harami pattern found
         datetime zone_start = iTime(_Symbol, Harami_Timeframe, i);
         datetime zone_end = TimeCurrent(); // Extend to current time

         // Calculate range in pips
         double range_pips = (parent_high - parent_low) / _Point / 10.0;
         bool is_low_vol = (range_pips < Range_Pips_Min);

         // Add zone to array
         zones_count++;
         ArrayResize(zones, zones_count);

         zones[zones_count-1].time_start = zone_start;
         zones[zones_count-1].time_end = zone_end;
         zones[zones_count-1].high = parent_high;
         zones[zones_count-1].low = parent_low;
         zones[zones_count-1].is_low_volatility = is_low_vol;
         zones[zones_count-1].bar_index = i;
         zones[zones_count-1].high_break_alerted = false;
         zones[zones_count-1].low_break_alerted = false;

         // Check for mid-range engulfing pattern if enabled
         if(Enable_MidRange_Alert)
         {
            CheckMidRangePattern(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for mid-range engulfing patterns                          |
//+------------------------------------------------------------------+
void CheckMidRangePattern(int bar_index)
{
   // Check if an engulfing pattern occurs in mid-range
   double parent_high = iHigh(_Symbol, Harami_Timeframe, bar_index);
   double parent_low = iLow(_Symbol, Harami_Timeframe, bar_index);
   double parent_open = iOpen(_Symbol, Harami_Timeframe, bar_index);
   double parent_close = iClose(_Symbol, Harami_Timeframe, bar_index);

   double child_high = iHigh(_Symbol, Harami_Timeframe, bar_index-1);
   double child_low = iLow(_Symbol, Harami_Timeframe, bar_index-1);
   double child_open = iOpen(_Symbol, Harami_Timeframe, bar_index-1);
   double child_close = iClose(_Symbol, Harami_Timeframe, bar_index-1);

   // Check for engulfing pattern (opposite of Harami)
   bool is_bullish_engulfing = (parent_close > parent_open) &&
                                (child_close < child_open) &&
                                (parent_open < child_close) &&
                                (parent_close > child_open);

   bool is_bearish_engulfing = (parent_close < parent_open) &&
                                (child_close > child_open) &&
                                (parent_open > child_close) &&
                                (parent_close < child_open);

   if(is_bullish_engulfing || is_bearish_engulfing)
   {
      // Check if pattern is in mid-range (not at extremes)
      double highest = iHigh(_Symbol, Harami_Timeframe, iHighest(_Symbol, Harami_Timeframe, MODE_HIGH, MidRange_Period, bar_index));
      double lowest = iLow(_Symbol, Harami_Timeframe, iLowest(_Symbol, Harami_Timeframe, MODE_LOW, MidRange_Period, bar_index));

      double upper_threshold = lowest + (highest - lowest) * 0.8;
      double lower_threshold = lowest + (highest - lowest) * 0.2;

      double pattern_level = (parent_high + parent_low) / 2.0;

      // If pattern is in mid-range (between 20% and 80%)
      if(pattern_level < upper_threshold && pattern_level > lower_threshold)
      {
         // Draw warning text
         datetime pattern_time = iTime(_Symbol, Harami_Timeframe, bar_index);
         string obj_name = "MidRange_Alert_" + IntegerToString(bar_index) + "_" + TimeToString(pattern_time);

         if(ObjectFind(0, obj_name) < 0)
         {
            ObjectCreate(0, obj_name, OBJ_TEXT, 0, pattern_time, parent_high + 10 * _Point);
            ObjectSetString(0, obj_name, OBJPROP_TEXT, "MID-RANGE ALERT");
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrOrangeRed);
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_LOWER);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw all detected zones                                          |
//+------------------------------------------------------------------+
void DrawAllZones()
{
   DeleteAllObjects();

   for(int i = 0; i < zones_count; i++)
   {
      DrawZone(zones[i], i);
   }
}

//+------------------------------------------------------------------+
//| Draw a single zone                                               |
//+------------------------------------------------------------------+
void DrawZone(HaramiZone &zone, int index)
{
   string obj_name = "NoEntryZone_" + IntegerToString(index) + "_" + TimeToString(zone.time_start);

   // Create rectangle for zone
   if(ObjectFind(0, obj_name) < 0)
   {
      ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, zone.time_start, zone.high, zone.time_end, zone.low);
   }
   else
   {
      // Update end time to current
      ObjectSetInteger(0, obj_name, OBJPROP_TIME, 1, TimeCurrent());
   }

   // Set colors based on volatility
   color zone_color = zone.is_low_volatility ? LowVol_Zone_Color : Zone_Color;
   int opacity = zone.is_low_volatility ? LowVol_Zone_Opacity : Zone_Opacity;

   // Apply color with opacity
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
   ObjectSetInteger(0, obj_name, OBJPROP_BGCOLOR, zone_color);
   ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
   ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
   ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj_name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DOT);

   // Draw horizontal lines at high and low
   string line_high_name = "NoEntryZone_High_" + IntegerToString(index) + "_" + TimeToString(zone.time_start);
   string line_low_name = "NoEntryZone_Low_" + IntegerToString(index) + "_" + TimeToString(zone.time_start);

   if(ObjectFind(0, line_high_name) < 0)
   {
      ObjectCreate(0, line_high_name, OBJ_TREND, 0, zone.time_start, zone.high, zone.time_end, zone.high);
      ObjectSetInteger(0, line_high_name, OBJPROP_COLOR, zone_color);
      ObjectSetInteger(0, line_high_name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, line_high_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, line_high_name, OBJPROP_BACK, false);
      ObjectSetInteger(0, line_high_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, line_high_name, OBJPROP_RAY_RIGHT, true);
   }
   else
   {
      ObjectSetInteger(0, line_high_name, OBJPROP_TIME, 1, TimeCurrent());
   }

   if(ObjectFind(0, line_low_name) < 0)
   {
      ObjectCreate(0, line_low_name, OBJ_TREND, 0, zone.time_start, zone.low, zone.time_end, zone.low);
      ObjectSetInteger(0, line_low_name, OBJPROP_COLOR, zone_color);
      ObjectSetInteger(0, line_low_name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, line_low_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, line_low_name, OBJPROP_BACK, false);
      ObjectSetInteger(0, line_low_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, line_low_name, OBJPROP_RAY_RIGHT, true);
   }
   else
   {
      ObjectSetInteger(0, line_low_name, OBJPROP_TIME, 1, TimeCurrent());
   }

   // Add label with range info
   if(zone.is_low_volatility)
   {
      string label_name = "NoEntryZone_Label_" + IntegerToString(index) + "_" + TimeToString(zone.time_start);
      double range_pips = (zone.high - zone.low) / _Point / 10.0;

      if(ObjectFind(0, label_name) < 0)
      {
         ObjectCreate(0, label_name, OBJ_TEXT, 0, zone.time_start, zone.high);
         ObjectSetString(0, label_name, OBJPROP_TEXT, "LOW VOL: " + DoubleToString(range_pips, 1) + " pips");
         ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for zone breakouts                                         |
//+------------------------------------------------------------------+
void CheckBreakouts(double current_close)
{
   for(int i = 0; i < zones_count; i++)
   {
      // Check for breakout above zone (only alert once per zone)
      if(current_close > zones[i].high && !zones[i].high_break_alerted)
      {
         zones[i].high_break_alerted = true;
         string message = "ブレイクアウト検出: " + _Symbol + " が非エントリーゾーン上限 " +
                         DoubleToString(zones[i].high, _Digits) + " を上抜けました";
         Alert(message);
         SendNotification(message);
      }

      // Check for breakout below zone (only alert once per zone)
      if(current_close < zones[i].low && !zones[i].low_break_alerted)
      {
         zones[i].low_break_alerted = true;
         string message = "ブレイクアウト検出: " + _Symbol + " が非エントリーゾーン下限 " +
                         DoubleToString(zones[i].low, _Digits) + " を下抜けました";
         Alert(message);
         SendNotification(message);
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all objects created by this indicator                     |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int obj_total = ObjectsTotal(0, 0, -1);

   for(int i = obj_total - 1; i >= 0; i--)
   {
      string obj_name = ObjectName(0, i, 0, -1);

      if(StringFind(obj_name, "NoEntryZone_") >= 0 ||
         StringFind(obj_name, "MidRange_Alert_") >= 0)
      {
         ObjectDelete(0, obj_name);
      }
   }
}
//+------------------------------------------------------------------+
