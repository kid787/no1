//+------------------------------------------------------------------+
//|                                                  NZoneHunter.mq5 |
//|                                          N-Zone Hunter Indicator |
//|                    Detects N-Wave patterns and TP zones on H1    |
//+------------------------------------------------------------------+
#property copyright "N-Zone Hunter"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Structure to hold swing points                                   |
//+------------------------------------------------------------------+
struct SwingPoint
{
   datetime time;
   double   price;
   int      bar_index;
   bool     is_high;  // true for high, false for low
};

//+------------------------------------------------------------------+
//| Structure to hold N-Wave pattern                                 |
//+------------------------------------------------------------------+
struct NWavePattern
{
   SwingPoint A;
   SwingPoint B;
   SwingPoint C;
   SwingPoint D_target;
   double     retracement_percent;
   double     tp1_price;  // 100% extension (N-value)
   double     tp2_price;  // 161.8% extension
   bool       is_bullish;
   bool       is_valid;
   datetime   detected_time;
};

//+------------------------------------------------------------------+
//| Class for N-Wave detection and zone calculation                  |
//+------------------------------------------------------------------+
class CNZoneDetector
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_swing_strength;

   double            m_min_retracement;
   double            m_max_retracement;
   double            m_extension_100;
   double            m_extension_161;

public:
   CNZoneDetector(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
   {
      m_symbol = (symbol == NULL) ? _Symbol : symbol;
      m_timeframe = timeframe;
      m_swing_strength = 5;
      m_min_retracement = 0.382;
      m_max_retracement = 0.618;
      m_extension_100 = 1.000;
      m_extension_161 = 1.618;
   }

   ~CNZoneDetector() {}

   void SetParameters(int swing_strength, double min_ret, double max_ret)
   {
      m_swing_strength = swing_strength;
      m_min_retracement = min_ret;
      m_max_retracement = max_ret;
   }

   bool IsSwingHigh(int bar_index, int strength)
   {
      if(bar_index < strength) return false;
      double high = iHigh(m_symbol, m_timeframe, bar_index);
      for(int i = 1; i <= strength; i++)
      {
         if(iHigh(m_symbol, m_timeframe, bar_index - i) >= high) return false;
         if(iHigh(m_symbol, m_timeframe, bar_index + i) >= high) return false;
      }
      return true;
   }

   bool IsSwingLow(int bar_index, int strength)
   {
      if(bar_index < strength) return false;
      double low = iLow(m_symbol, m_timeframe, bar_index);
      for(int i = 1; i <= strength; i++)
      {
         if(iLow(m_symbol, m_timeframe, bar_index - i) <= low) return false;
         if(iLow(m_symbol, m_timeframe, bar_index + i) <= low) return false;
      }
      return true;
   }

   SwingPoint FindLastSwingHigh(int start_bar, int strength)
   {
      SwingPoint point;
      point.time = 0; point.price = 0; point.bar_index = -1; point.is_high = true;
      int bars_count = iBars(m_symbol, m_timeframe);
      for(int i = start_bar; i < bars_count - strength; i++)
      {
         if(IsSwingHigh(i, strength))
         {
            point.time = iTime(m_symbol, m_timeframe, i);
            point.price = iHigh(m_symbol, m_timeframe, i);
            point.bar_index = i;
            break;
         }
      }
      return point;
   }

   SwingPoint FindLastSwingLow(int start_bar, int strength)
   {
      SwingPoint point;
      point.time = 0; point.price = 0; point.bar_index = -1; point.is_high = false;
      int bars_count = iBars(m_symbol, m_timeframe);
      for(int i = start_bar; i < bars_count - strength; i++)
      {
         if(IsSwingLow(i, strength))
         {
            point.time = iTime(m_symbol, m_timeframe, i);
            point.price = iLow(m_symbol, m_timeframe, i);
            point.bar_index = i;
            break;
         }
      }
      return point;
   }

   double CalculateFibExtension(double A, double B, double C, double level)
   {
      double wave_ab = MathAbs(B - A);
      if(B > A) return C + (wave_ab * level);
      else return C - (wave_ab * level);
   }

   bool ValidateRetracement(const NWavePattern &pattern)
   {
      double retracement = pattern.retracement_percent;
      if(retracement >= m_min_retracement && retracement <= m_max_retracement) return true;
      if(retracement > 0.786) return false;
      return false;
   }

   void CalculateTPZone(NWavePattern &pattern)
   {
      pattern.tp1_price = CalculateFibExtension(pattern.A.price, pattern.B.price, pattern.C.price, m_extension_100);
      pattern.tp2_price = CalculateFibExtension(pattern.A.price, pattern.B.price, pattern.C.price, m_extension_161);
      pattern.D_target.price = pattern.tp1_price;
      pattern.D_target.time = 0;
      pattern.D_target.bar_index = -1;
      pattern.D_target.is_high = !pattern.C.is_high;
   }

   bool IsPriceInZone(double price, double zone_start, double zone_end)
   {
      double min_price = MathMin(zone_start, zone_end);
      double max_price = MathMax(zone_start, zone_end);
      return (price >= min_price && price <= max_price);
   }

   bool DetectNWave(NWavePattern &pattern)
   {
      pattern.is_valid = false;
      SwingPoint last_high = FindLastSwingHigh(m_swing_strength + 1, m_swing_strength);
      SwingPoint last_low = FindLastSwingLow(m_swing_strength + 1, m_swing_strength);

      if(last_high.bar_index < 0 || last_low.bar_index < 0) return false;

      if(last_high.bar_index < last_low.bar_index)
      {
         pattern.C = last_high;
         pattern.B = FindLastSwingLow(last_high.bar_index + 1, m_swing_strength);
         if(pattern.B.bar_index < 0) return false;
         pattern.A = FindLastSwingHigh(pattern.B.bar_index + 1, m_swing_strength);
         if(pattern.A.bar_index < 0) return false;
         pattern.is_bullish = false;
         double wave_ab = pattern.A.price - pattern.B.price;
         double wave_bc = pattern.C.price - pattern.B.price;
         pattern.retracement_percent = wave_bc / wave_ab;
      }
      else
      {
         pattern.C = last_low;
         pattern.B = FindLastSwingHigh(last_low.bar_index + 1, m_swing_strength);
         if(pattern.B.bar_index < 0) return false;
         pattern.A = FindLastSwingLow(pattern.B.bar_index + 1, m_swing_strength);
         if(pattern.A.bar_index < 0) return false;
         pattern.is_bullish = true;
         double wave_ab = pattern.B.price - pattern.A.price;
         double wave_bc = pattern.B.price - pattern.C.price;
         pattern.retracement_percent = wave_bc / wave_ab;
      }

      if(!ValidateRetracement(pattern)) return false;
      CalculateTPZone(pattern);
      pattern.is_valid = true;
      pattern.detected_time = TimeCurrent();
      return true;
   }
};

//--- Input parameters
input int      InpSwingStrength = 5;           // Swing detection strength
input double   InpMinRetracement = 0.382;      // Minimum retracement (38.2%)
input double   InpMaxRetracement = 0.618;      // Maximum retracement (61.8%)
input bool     InpShowLabels = true;           // Show ABC labels
input color    InpBullishColor = clrLime;      // Bullish pattern color
input color    InpBearishColor = clrRed;       // Bearish pattern color
input color    InpZoneColor = clrYellow;       // TP Zone color
input int      InpZoneTransparency = 80;       // Zone transparency (0-100)

//--- Global variables
CNZoneDetector* g_detector;
NWavePattern g_current_pattern;
datetime g_last_detection_time = 0;
string g_prefix = "NZone_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create detector instance
   g_detector = new CNZoneDetector(_Symbol, PERIOD_H1);
   g_detector.SetParameters(InpSwingStrength, InpMinRetracement, InpMaxRetracement);

   // Set indicator short name
   IndicatorSetString(INDICATOR_SHORTNAME, "N-Zone Hunter");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete all objects created by indicator
   DeleteAllObjects();

   // Delete detector
   if(g_detector != NULL)
      delete g_detector;
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
   // Detect N-Wave pattern
   if(g_detector.DetectNWave(g_current_pattern))
   {
      // Check if this is a new pattern
      if(g_current_pattern.detected_time != g_last_detection_time)
      {
         g_last_detection_time = g_current_pattern.detected_time;

         // Delete old objects
         DeleteAllObjects();

         // Draw new pattern
         DrawPattern(g_current_pattern);
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw N-Wave pattern on chart                                     |
//+------------------------------------------------------------------+
void DrawPattern(const NWavePattern &pattern)
{
   if(!pattern.is_valid) return;

   color line_color = pattern.is_bullish ? InpBullishColor : InpBearishColor;

   // Draw A->B line
   DrawLine(g_prefix + "AB", pattern.A.time, pattern.A.price,
            pattern.B.time, pattern.B.price, line_color, 2);

   // Draw B->C line
   DrawLine(g_prefix + "BC", pattern.B.time, pattern.B.price,
            pattern.C.time, pattern.C.price, line_color, 2);

   // Draw C->D projection line (dotted)
   datetime d_time = pattern.C.time + (pattern.C.time - pattern.A.time);
   DrawLine(g_prefix + "CD", pattern.C.time, pattern.C.price,
            d_time, pattern.D_target.price, line_color, 1, STYLE_DOT);

   // Draw TP Zone
   DrawZone(pattern);

   // Draw labels
   if(InpShowLabels)
   {
      DrawLabel(g_prefix + "A", pattern.A.time, pattern.A.price, "A", line_color);
      DrawLabel(g_prefix + "B", pattern.B.time, pattern.B.price, "B", line_color);
      DrawLabel(g_prefix + "C", pattern.C.time, pattern.C.price, "C", line_color);

      // Draw info text
      string info = StringFormat("%s N-Wave | Ret: %.1f%% | TP1: %.2f | TP2: %.2f",
                                 pattern.is_bullish ? "Bullish" : "Bearish",
                                 pattern.retracement_percent * 100,
                                 pattern.tp1_price,
                                 pattern.tp2_price);

      DrawText(g_prefix + "Info", pattern.C.time, pattern.C.price, info, line_color);
   }
}

//+------------------------------------------------------------------+
//| Draw TP Zone (rectangle)                                         |
//+------------------------------------------------------------------+
void DrawZone(const NWavePattern &pattern)
{
   datetime start_time = pattern.C.time;
   datetime end_time = start_time + PeriodSeconds(PERIOD_H1) * 50; // Extend 50 bars

   string name = g_prefix + "Zone";

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, start_time, pattern.tp1_price, end_time, pattern.tp2_price))
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, start_time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, pattern.tp1_price);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, end_time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, pattern.tp2_price);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, InpZoneColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   // Set transparency
   color zone_color = InpZoneColor;
   long alpha = (100 - InpZoneTransparency) * 255 / 100;
   ObjectSetInteger(0, name, OBJPROP_COLOR, (zone_color & 0x00FFFFFF) | (alpha << 24));

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Draw trend line                                                  |
//+------------------------------------------------------------------+
void DrawLine(string name, datetime time1, double price1, datetime time2, double price2,
              color clr, int width, ENUM_LINE_STYLE style = STYLE_SOLID)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2))
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Draw text label                                                  |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime time, double price, string text, color clr)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, time, price))
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   }

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Draw text                                                        |
//+------------------------------------------------------------------+
void DrawText(string name, datetime time, double price, string text, color clr)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, time, price))
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   }

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete all objects created by indicator                          |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);

      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }

   ChartRedraw();
}
