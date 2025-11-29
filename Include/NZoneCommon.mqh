//+------------------------------------------------------------------+
//|                                                  NZoneCommon.mqh |
//|                                          N-Zone Hunter Common    |
//|                               Common functions for N-Wave detection |
//+------------------------------------------------------------------+
#property copyright "N-Zone Hunter"
#property link      ""
#property version   "1.00"

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
   int               m_swing_strength;  // Number of bars to left/right for swing detection

   // Fibonacci levels
   double            m_min_retracement;
   double            m_max_retracement;
   double            m_extension_100;
   double            m_extension_161;

public:
   CNZoneDetector(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_H1);
   ~CNZoneDetector();

   void              SetParameters(int swing_strength, double min_ret, double max_ret);
   bool              DetectNWave(NWavePattern &pattern);
   bool              IsSwingHigh(int bar_index, int strength);
   bool              IsSwingLow(int bar_index, int strength);
   SwingPoint        FindLastSwingHigh(int start_bar, int strength);
   SwingPoint        FindLastSwingLow(int start_bar, int strength);
   double            CalculateFibRetracement(double start, double end, double level);
   double            CalculateFibExtension(double A, double B, double C, double level);
   bool              ValidateRetracement(const NWavePattern &pattern);
   void              CalculateTPZone(NWavePattern &pattern);
   bool              IsPriceInZone(double price, double zone_start, double zone_end);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CNZoneDetector::CNZoneDetector(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_H1)
{
   m_symbol = (symbol == NULL) ? _Symbol : symbol;
   m_timeframe = timeframe;
   m_swing_strength = 5;

   // Default Fibonacci levels
   m_min_retracement = 0.382;
   m_max_retracement = 0.618;
   m_extension_100 = 1.000;
   m_extension_161 = 1.618;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CNZoneDetector::~CNZoneDetector()
{
}

//+------------------------------------------------------------------+
//| Set detection parameters                                          |
//+------------------------------------------------------------------+
void CNZoneDetector::SetParameters(int swing_strength, double min_ret, double max_ret)
{
   m_swing_strength = swing_strength;
   m_min_retracement = min_ret;
   m_max_retracement = max_ret;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                     |
//+------------------------------------------------------------------+
bool CNZoneDetector::IsSwingHigh(int bar_index, int strength)
{
   if(bar_index < strength) return false;

   double high = iHigh(m_symbol, m_timeframe, bar_index);

   // Check bars to the left
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(m_symbol, m_timeframe, bar_index - i) >= high)
         return false;
   }

   // Check bars to the right
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(m_symbol, m_timeframe, bar_index + i) >= high)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                      |
//+------------------------------------------------------------------+
bool CNZoneDetector::IsSwingLow(int bar_index, int strength)
{
   if(bar_index < strength) return false;

   double low = iLow(m_symbol, m_timeframe, bar_index);

   // Check bars to the left
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(m_symbol, m_timeframe, bar_index - i) <= low)
         return false;
   }

   // Check bars to the right
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(m_symbol, m_timeframe, bar_index + i) <= low)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Find last swing high                                             |
//+------------------------------------------------------------------+
SwingPoint CNZoneDetector::FindLastSwingHigh(int start_bar, int strength)
{
   SwingPoint point;
   point.time = 0;
   point.price = 0;
   point.bar_index = -1;
   point.is_high = true;

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

//+------------------------------------------------------------------+
//| Find last swing low                                              |
//+------------------------------------------------------------------+
SwingPoint CNZoneDetector::FindLastSwingLow(int start_bar, int strength)
{
   SwingPoint point;
   point.time = 0;
   point.price = 0;
   point.bar_index = -1;
   point.is_high = false;

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

//+------------------------------------------------------------------+
//| Calculate Fibonacci retracement                                  |
//+------------------------------------------------------------------+
double CNZoneDetector::CalculateFibRetracement(double start, double end, double level)
{
   return end + (start - end) * level;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci extension                                    |
//+------------------------------------------------------------------+
double CNZoneDetector::CalculateFibExtension(double A, double B, double C, double level)
{
   double wave_ab = MathAbs(B - A);

   if(B > A)  // Bullish wave
      return C + (wave_ab * level);
   else       // Bearish wave
      return C - (wave_ab * level);
}

//+------------------------------------------------------------------+
//| Validate retracement level                                       |
//+------------------------------------------------------------------+
bool CNZoneDetector::ValidateRetracement(const NWavePattern &pattern)
{
   double retracement = pattern.retracement_percent;

   // Check if retracement is within healthy range (38.2% - 61.8%)
   if(retracement >= m_min_retracement && retracement <= m_max_retracement)
      return true;

   // Reject if retracement is too deep (> 78.6%)
   if(retracement > 0.786)
      return false;

   return false;
}

//+------------------------------------------------------------------+
//| Calculate TP Zone                                                |
//+------------------------------------------------------------------+
void CNZoneDetector::CalculateTPZone(NWavePattern &pattern)
{
   // TP1: 100% extension (N-value)
   pattern.tp1_price = CalculateFibExtension(pattern.A.price, pattern.B.price,
                                              pattern.C.price, m_extension_100);

   // TP2: 161.8% extension
   pattern.tp2_price = CalculateFibExtension(pattern.A.price, pattern.B.price,
                                              pattern.C.price, m_extension_161);

   // Set D target
   pattern.D_target.price = pattern.tp1_price;
   pattern.D_target.time = 0;
   pattern.D_target.bar_index = -1;
   pattern.D_target.is_high = !pattern.C.is_high;
}

//+------------------------------------------------------------------+
//| Check if price is in zone                                        |
//+------------------------------------------------------------------+
bool CNZoneDetector::IsPriceInZone(double price, double zone_start, double zone_end)
{
   double min_price = MathMin(zone_start, zone_end);
   double max_price = MathMax(zone_start, zone_end);

   return (price >= min_price && price <= max_price);
}

//+------------------------------------------------------------------+
//| Detect N-Wave pattern                                            |
//+------------------------------------------------------------------+
bool CNZoneDetector::DetectNWave(NWavePattern &pattern)
{
   pattern.is_valid = false;

   // Find most recent swing points
   SwingPoint last_high = FindLastSwingHigh(m_swing_strength + 1, m_swing_strength);
   SwingPoint last_low = FindLastSwingLow(m_swing_strength + 1, m_swing_strength);

   if(last_high.bar_index < 0 || last_low.bar_index < 0)
      return false;

   // Determine pattern direction based on most recent swing
   if(last_high.bar_index < last_low.bar_index)  // Most recent is high - looking for bullish pattern
   {
      // For bullish N-wave: A(low) -> B(high) -> C(low) -> D(high target)
      pattern.C = last_high;  // Actually this should be the correction high
      pattern.B = FindLastSwingLow(last_high.bar_index + 1, m_swing_strength);
      if(pattern.B.bar_index < 0) return false;

      pattern.A = FindLastSwingHigh(pattern.B.bar_index + 1, m_swing_strength);
      if(pattern.A.bar_index < 0) return false;

      pattern.is_bullish = false;  // Bearish pattern (A high -> B low -> C high -> D low target)

      // Calculate retracement
      double wave_ab = pattern.A.price - pattern.B.price;
      double wave_bc = pattern.C.price - pattern.B.price;
      pattern.retracement_percent = wave_bc / wave_ab;
   }
   else  // Most recent is low - looking for bearish continuation
   {
      // For bearish N-wave: A(high) -> B(low) -> C(high) -> D(low target)
      pattern.C = last_low;  // Correction low
      pattern.B = FindLastSwingHigh(last_low.bar_index + 1, m_swing_strength);
      if(pattern.B.bar_index < 0) return false;

      pattern.A = FindLastSwingLow(pattern.B.bar_index + 1, m_swing_strength);
      if(pattern.A.bar_index < 0) return false;

      pattern.is_bullish = true;  // Bullish pattern (A low -> B high -> C low -> D high target)

      // Calculate retracement
      double wave_ab = pattern.B.price - pattern.A.price;
      double wave_bc = pattern.B.price - pattern.C.price;
      pattern.retracement_percent = wave_bc / wave_ab;
   }

   // Validate retracement
   if(!ValidateRetracement(pattern))
      return false;

   // Calculate TP zone
   CalculateTPZone(pattern);

   pattern.is_valid = true;
   pattern.detected_time = TimeCurrent();

   return true;
}

//+------------------------------------------------------------------+
//| Class for detecting reversal price action on M1                  |
//+------------------------------------------------------------------+
class CReversalDetector
{
public:
   // Check for pin bar
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

      if(bullish_pin)
      {
         // Long lower wick, small body
         return (lower_wick > body * 2 && lower_wick > total_range * 0.6);
      }
      else
      {
         // Long upper wick, small body
         return (upper_wick > body * 2 && upper_wick > total_range * 0.6);
      }
   }

   // Check for engulfing pattern
   static bool IsEngulfing(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_engulfing)
   {
      if(bar_index < 1) return false;

      double open1 = iOpen(symbol, timeframe, bar_index);
      double close1 = iClose(symbol, timeframe, bar_index);
      double open2 = iOpen(symbol, timeframe, bar_index + 1);
      double close2 = iClose(symbol, timeframe, bar_index + 1);

      if(bullish_engulfing)
      {
         // Current bar is bullish and engulfs previous bearish bar
         return (close1 > open1 && open2 > close2 &&
                 close1 > open2 && open1 < close2);
      }
      else
      {
         // Current bar is bearish and engulfs previous bullish bar
         return (open1 > close1 && close2 > open2 &&
                 open1 > close2 && close1 < open2);
      }
   }

   // Check for mini N-wave reversal structure
   static bool IsMiniReversal(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_reversal)
   {
      if(bar_index < 3) return false;

      if(bullish_reversal)
      {
         // Look for higher lows
         double low1 = iLow(symbol, timeframe, bar_index + 2);
         double low2 = iLow(symbol, timeframe, bar_index + 1);
         double low3 = iLow(symbol, timeframe, bar_index);

         return (low2 < low1 && low3 > low2);
      }
      else
      {
         // Look for lower highs
         double high1 = iHigh(symbol, timeframe, bar_index + 2);
         double high2 = iHigh(symbol, timeframe, bar_index + 1);
         double high3 = iHigh(symbol, timeframe, bar_index);

         return (high2 > high1 && high3 < high2);
      }
   }

   // Combined reversal detection
   static bool DetectReversal(string symbol, ENUM_TIMEFRAMES timeframe, int bar_index, bool bullish_reversal)
   {
      return IsPinBar(symbol, timeframe, bar_index, bullish_reversal) ||
             IsEngulfing(symbol, timeframe, bar_index, bullish_reversal) ||
             IsMiniReversal(symbol, timeframe, bar_index, bullish_reversal);
   }
};

//+------------------------------------------------------------------+
//| Risk management class                                            |
//+------------------------------------------------------------------+
class CRiskManager
{
public:
   // Calculate lot size based on risk percentage
   static double CalculateLotSize(string symbol, double entry_price, double sl_price,
                                   double risk_percent, double account_balance)
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

      // Round to lot step
      lot_size = MathFloor(lot_size / lot_step) * lot_step;

      // Ensure within limits
      if(lot_size < min_lot) lot_size = min_lot;
      if(lot_size > max_lot) lot_size = max_lot;

      return lot_size;
   }

   // Calculate take profit based on risk:reward ratio
   static double CalculateTPByRR(double entry_price, double sl_price, double rr_ratio, bool is_buy)
   {
      double sl_distance = MathAbs(entry_price - sl_price);
      double tp_distance = sl_distance * rr_ratio;

      if(is_buy)
         return entry_price + tp_distance;
      else
         return entry_price - tp_distance;
   }
};
