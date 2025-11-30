//+------------------------------------------------------------------+
//|                                               NZoneHunterEA.mq5  |
//|                                          N-Zone Hunter Expert    |
//|                    Trades reversals at N-Wave TP zones on M1     |
//+------------------------------------------------------------------+
#property copyright "N-Zone Hunter"
#property link      ""
#property version   "1.00"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Structures and Classes                                            |
//+------------------------------------------------------------------+
struct SwingPoint
{
   datetime time;
   double   price;
   int      bar_index;
   bool     is_high;
};

struct NWavePattern
{
   SwingPoint A;
   SwingPoint B;
   SwingPoint C;
   SwingPoint D_target;
   double     retracement_percent;
   double     tp1_price;
   double     tp2_price;
   bool       is_bullish;
   bool       is_valid;
   datetime   detected_time;
};

class CNZoneDetector
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int m_swing_strength;
   double m_min_retracement;
   double m_max_retracement;
   double m_extension_100;
   double m_extension_161;

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

class CReversalDetector
{
public:
   static bool IsPinBar(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_pin)
   {
      double open = iOpen(symbol, timeframe, bar_index);
      double close = iClose(symbol, timeframe, bar_index);
      double high = iHigh(symbol, timeframe, bar_index);
      double low = iLow(symbol, timeframe, bar_index);
      double body = MathAbs(close - open);
      double upper_wick = high - MathMax(open, close);
      double lower_wick = MathMin(open, close) - low;
      double total_range = high - low;
      if(total_range == 0) return false;
      if(bullish_pin) return (lower_wick > body * 2 && lower_wick > total_range * 0.6);
      else return (upper_wick > body * 2 && upper_wick > total_range * 0.6);
   }

   static bool IsEngulfing(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_engulfing)
   {
      if(bar_index < 1) return false;
      double open1 = iOpen(symbol, timeframe, bar_index);
      double close1 = iClose(symbol, timeframe, bar_index);
      double open2 = iOpen(symbol, timeframe, bar_index + 1);
      double close2 = iClose(symbol, timeframe, bar_index + 1);
      if(bullish_engulfing)
         return (close1 > open1 && open2 > close2 && close1 > open2 && open1 < close2);
      else
         return (open1 > close1 && close2 > open2 && open1 > close2 && close1 < open2);
   }

   static bool IsMiniReversal(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_reversal)
   {
      if(bar_index < 3) return false;
      if(bullish_reversal)
      {
         double low1 = iLow(symbol, timeframe, bar_index + 2);
         double low2 = iLow(symbol, timeframe, bar_index + 1);
         double low3 = iLow(symbol, timeframe, bar_index);
         return (low2 < low1 && low3 > low2);
      }
      else
      {
         double high1 = iHigh(symbol, timeframe, bar_index + 2);
         double high2 = iHigh(symbol, timeframe, bar_index + 1);
         double high3 = iHigh(symbol, timeframe, bar_index);
         return (high2 > high1 && high3 < high2);
      }
   }

   static bool DetectReversal(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_reversal)
   {
      return IsPinBar(symbol, timeframe, bar_index, bullish_reversal) ||
             IsEngulfing(symbol, timeframe, bar_index, bullish_reversal) ||
             IsMiniReversal(symbol, timeframe, bar_index, bullish_reversal);
   }
};

class CRiskManager
{
public:
   static double CalculateLotSize(string symbol, double entry_price, double sl_price, double risk_percent, double account_balance)
   {
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double risk_amount = account_balance * risk_percent / 100.0;
      double sl_distance = MathAbs(entry_price - sl_price);
      if(sl_distance == 0) return min_lot;
      double lot_size = risk_amount / (sl_distance / tick_size * tick_value);
      lot_size = MathFloor(lot_size / lot_step) * lot_step;
      if(lot_size < min_lot) lot_size = min_lot;
      if(lot_size > max_lot) lot_size = max_lot;
      return lot_size;
   }

   static double CalculateTPByRR(double entry_price, double sl_price, double rr_ratio, bool is_buy)
   {
      double sl_distance = MathAbs(entry_price - sl_price);
      double tp_distance = sl_distance * rr_ratio;
      if(is_buy) return entry_price + tp_distance;
      else return entry_price - tp_distance;
   }
};

//--- Input parameters
// H1 Analysis parameters
input group "===== H1 N-Wave Detection ====="
input int      InpSwingStrength = 5;           // Swing detection strength
input double   InpMinRetracement = 0.382;      // Minimum retracement (38.2%)
input double   InpMaxRetracement = 0.618;      // Maximum retracement (61.8%)

// M1 Entry parameters
input group "===== M1 Entry Settings ====="
input bool     InpUsePinBar = true;            // Use Pin Bar signals
input bool     InpUseEngulfing = true;         // Use Engulfing signals
input bool     InpUseMiniReversal = true;      // Use Mini N-Wave reversal

// Risk management
input group "===== Risk Management ====="
input double   InpRiskPercent = 1.0;           // Risk per trade (%)
input double   InpRiskReward = 2.0;            // Risk:Reward ratio
input int      InpStopLossOffset = 5;          // SL offset from reversal point (points)
input bool     InpUsePointC_TP = false;        // Use point C as TP target

// Trading controls
input group "===== Trading Controls ====="
input bool     InpTradeOnlyInZone = true;      // Trade only when price in TP zone
input int      InpMagicNumber = 20241129;      // Magic number
input string   InpTradeComment = "NZone";      // Trade comment
input bool     InpShowVisuals = true;          // Show visual objects on chart

//--- Global variables
CTrade g_trade;
CNZoneDetector* g_h1_detector;
NWavePattern g_current_pattern;
datetime g_last_pattern_time = 0;
datetime g_last_trade_time = 0;
bool g_pattern_active = false;
bool g_in_zone = false;
string g_prefix = "NZEA_";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(10);

   // Create H1 detector
   g_h1_detector = new CNZoneDetector(_Symbol, PERIOD_H1);
   g_h1_detector.SetParameters(InpSwingStrength, InpMinRetracement, InpMaxRetracement);

   // Validate symbol
   if(_Symbol != "XAUUSD" && StringFind(_Symbol, "GOLD") < 0 && StringFind(_Symbol, "XAU") < 0)
   {
      Print("Warning: This EA is designed for XAUUSD (Gold). Current symbol: ", _Symbol);
   }

   Print("N-Zone Hunter EA initialized successfully");
   Print("Symbol: ", _Symbol);
   Print("H1 Analysis | M1 Execution");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete visual objects
   if(InpShowVisuals)
      DeleteAllObjects();

   // Delete detector
   if(g_h1_detector != NULL)
      delete g_h1_detector;

   Print("N-Zone Hunter EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new M1 bar
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, PERIOD_M1, 0);

   if(current_bar_time == last_bar_time)
      return;

   last_bar_time = current_bar_time;

   // Step 1: Detect N-Wave pattern on H1
   DetectH1Pattern();

   // Step 2: Check if price is in TP zone
   CheckZoneEntry();

   // Step 3: If in zone, look for M1 reversal and enter trade
   if(g_in_zone && g_pattern_active)
   {
      CheckM1Reversal();
   }

   // Step 4: Update visuals
   if(InpShowVisuals && g_pattern_active)
   {
      UpdateVisuals();
   }
}

//+------------------------------------------------------------------+
//| Detect N-Wave pattern on H1                                      |
//+------------------------------------------------------------------+
void DetectH1Pattern()
{
   NWavePattern new_pattern;

   if(g_h1_detector.DetectNWave(new_pattern))
   {
      // Check if this is a new pattern
      if(new_pattern.detected_time != g_last_pattern_time)
      {
         g_current_pattern = new_pattern;
         g_last_pattern_time = new_pattern.detected_time;
         g_pattern_active = true;
         g_in_zone = false;

         Print("New N-Wave pattern detected!");
         Print("Direction: ", g_current_pattern.is_bullish ? "Bullish" : "Bearish");
         Print("Retracement: ", DoubleToString(g_current_pattern.retracement_percent * 100, 1), "%");
         Print("TP1 (100%): ", DoubleToString(g_current_pattern.tp1_price, _Digits));
         Print("TP2 (161.8%): ", DoubleToString(g_current_pattern.tp2_price, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| Check if price has entered TP zone                               |
//+------------------------------------------------------------------+
void CheckZoneEntry()
{
   if(!g_pattern_active) return;

   double current_price = (iClose(_Symbol, PERIOD_M1, 0) + iOpen(_Symbol, PERIOD_M1, 0)) / 2.0;
   bool was_in_zone = g_in_zone;

   g_in_zone = g_h1_detector.IsPriceInZone(current_price,
                                            g_current_pattern.tp1_price,
                                            g_current_pattern.tp2_price);

   // Log zone entry
   if(g_in_zone && !was_in_zone)
   {
      Print("Price entered TP Zone! Current price: ", DoubleToString(current_price, _Digits));
      Print("Zone range: ", DoubleToString(g_current_pattern.tp1_price, _Digits),
            " - ", DoubleToString(g_current_pattern.tp2_price, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Check for M1 reversal and enter trade                            |
//+------------------------------------------------------------------+
void CheckM1Reversal()
{
   // Check if we already have an open position
   if(PositionSelect(_Symbol))
   {
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return;  // Already in trade
   }

   // Prevent multiple trades on same pattern
   datetime current_time = TimeCurrent();
   if(current_time - g_last_trade_time < PeriodSeconds(PERIOD_M1) * 5)
      return;

   // Determine expected reversal direction
   // If bullish pattern (expecting price to go up to TP zone), we look for bearish reversal to sell
   // If bearish pattern (expecting price to go down to TP zone), we look for bullish reversal to buy
   bool looking_for_bullish_reversal = !g_current_pattern.is_bullish;

   // Check M1 bar 1 (last closed bar) for reversal patterns
   bool reversal_detected = false;

   if(InpUsePinBar && CReversalDetector::IsPinBar(_Symbol, PERIOD_M1, 1, looking_for_bullish_reversal))
   {
      reversal_detected = true;
      Print("Pin Bar detected on M1");
   }

   if(!reversal_detected && InpUseEngulfing &&
      CReversalDetector::IsEngulfing(_Symbol, PERIOD_M1, 1, looking_for_bullish_reversal))
   {
      reversal_detected = true;
      Print("Engulfing pattern detected on M1");
   }

   if(!reversal_detected && InpUseMiniReversal &&
      CReversalDetector::IsMiniReversal(_Symbol, PERIOD_M1, 1, looking_for_bullish_reversal))
   {
      reversal_detected = true;
      Print("Mini reversal structure detected on M1");
   }

   if(reversal_detected)
   {
      ExecuteTrade(looking_for_bullish_reversal);
   }
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                        |
//+------------------------------------------------------------------+
void ExecuteTrade(bool is_buy)
{
   double entry_price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                        SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate Stop Loss
   double sl_price;
   if(is_buy)
   {
      // For buy: SL below recent low or zone boundary
      double recent_low = iLow(_Symbol, PERIOD_M1, 1);
      double zone_boundary = MathMin(g_current_pattern.tp1_price, g_current_pattern.tp2_price);
      sl_price = MathMin(recent_low, zone_boundary) - InpStopLossOffset * _Point;
   }
   else
   {
      // For sell: SL above recent high or zone boundary
      double recent_high = iHigh(_Symbol, PERIOD_M1, 1);
      double zone_boundary = MathMax(g_current_pattern.tp1_price, g_current_pattern.tp2_price);
      sl_price = MathMax(recent_high, zone_boundary) + InpStopLossOffset * _Point;
   }

   // Calculate Take Profit
   double tp_price;
   if(InpUsePointC_TP)
   {
      // Use point C as target (50% retracement back towards C)
      double distance_to_c = MathAbs(entry_price - g_current_pattern.C.price);
      tp_price = is_buy ? entry_price + distance_to_c * 0.5 :
                 entry_price - distance_to_c * 0.5;
   }
   else
   {
      // Use Risk:Reward ratio
      tp_price = CRiskManager::CalculateTPByRR(entry_price, sl_price, InpRiskReward, is_buy);
   }

   // Calculate lot size based on risk
   double lot_size = CRiskManager::CalculateLotSize(_Symbol, entry_price, sl_price,
                     InpRiskPercent, AccountInfoDouble(ACCOUNT_BALANCE));

   // Validate lot size
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lot_size < min_lot)
   {
      Print("Calculated lot size ", lot_size, " is below minimum ", min_lot);
      lot_size = min_lot;
   }
   if(lot_size > max_lot)
   {
      Print("Calculated lot size ", lot_size, " is above maximum ", max_lot);
      lot_size = max_lot;
   }

   // Validate SL and TP distances
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_distance = stops_level * _Point;

   if(MathAbs(entry_price - sl_price) < min_distance)
   {
      Print("SL too close to entry price. Required: ", min_distance);
      return;
   }

   if(MathAbs(entry_price - tp_price) < min_distance)
   {
      Print("TP too close to entry price. Required: ", min_distance);
      return;
   }

   // Execute trade
   Print("=== Executing Trade ===");
   Print("Direction: ", is_buy ? "BUY" : "SELL");
   Print("Entry: ", DoubleToString(entry_price, _Digits));
   Print("SL: ", DoubleToString(sl_price, _Digits));
   Print("TP: ", DoubleToString(tp_price, _Digits));
   Print("Lot Size: ", DoubleToString(lot_size, 2));
   Print("Risk: ", DoubleToString(InpRiskPercent, 2), "%");
   Print("R:R: 1:", DoubleToString(InpRiskReward, 2));

   bool result;
   if(is_buy)
   {
      result = g_trade.Buy(lot_size, _Symbol, entry_price, sl_price, tp_price, InpTradeComment);
   }
   else
   {
      result = g_trade.Sell(lot_size, _Symbol, entry_price, sl_price, tp_price, InpTradeComment);
   }

   if(result)
   {
      Print("Trade executed successfully! Ticket: ", g_trade.ResultOrder());
      g_last_trade_time = TimeCurrent();

      // Mark pattern as used
      g_pattern_active = false;
   }
   else
   {
      Print("Trade execution failed! Error: ", GetLastError());
      Print("Result code: ", g_trade.ResultRetcode());
      Print("Result comment: ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Update visual objects on chart                                   |
//+------------------------------------------------------------------+
void UpdateVisuals()
{
   if(!g_pattern_active) return;

   color line_color = g_current_pattern.is_bullish ? clrLime : clrRed;

   // Draw A->B->C lines
   DrawLine(g_prefix + "AB", g_current_pattern.A.time, g_current_pattern.A.price,
            g_current_pattern.B.time, g_current_pattern.B.price, line_color, 2);

   DrawLine(g_prefix + "BC", g_current_pattern.B.time, g_current_pattern.B.price,
            g_current_pattern.C.time, g_current_pattern.C.price, line_color, 2);

   // Draw TP zone
   DrawZone();

   // Draw labels
   DrawLabel(g_prefix + "A", g_current_pattern.A.time, g_current_pattern.A.price, "A", line_color);
   DrawLabel(g_prefix + "B", g_current_pattern.B.time, g_current_pattern.B.price, "B", line_color);
   DrawLabel(g_prefix + "C", g_current_pattern.C.time, g_current_pattern.C.price, "C", line_color);

   // Draw status info
   string status = "Pattern: " + (string)(g_current_pattern.is_bullish ? "Bullish" : "Bearish");
   status += " | In Zone: " + (string)(g_in_zone ? "YES" : "NO");
   status += " | TP1: " + DoubleToString(g_current_pattern.tp1_price, _Digits);
   status += " | TP2: " + DoubleToString(g_current_pattern.tp2_price, _Digits);

   Comment(status);
}

//+------------------------------------------------------------------+
//| Draw TP Zone on M1 chart                                         |
//+------------------------------------------------------------------+
void DrawZone()
{
   datetime start_time = g_current_pattern.C.time;
   datetime end_time = TimeCurrent() + PeriodSeconds(PERIOD_M1) * 100;

   string name = g_prefix + "Zone";

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, start_time, g_current_pattern.tp1_price,
                    end_time, g_current_pattern.tp2_price))
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, start_time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, g_current_pattern.tp1_price);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, end_time);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, g_current_pattern.tp2_price);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // Set transparency
   long alpha = 50 * 255 / 100;
   ObjectSetInteger(0, name, OBJPROP_COLOR, (clrYellow & 0x00FFFFFF) | (alpha << 24));
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
}

//+------------------------------------------------------------------+
//| Delete all objects created by EA                                 |
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
