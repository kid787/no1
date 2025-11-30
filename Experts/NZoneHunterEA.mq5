//+------------------------------------------------------------------+
//|                                               NZoneHunterEA.mq5  |
//|                                          N-Zone Hunter Expert    |
//|                    Trades reversals at N-Wave TP zones on M1     |
//+------------------------------------------------------------------+
#property copyright "N-Zone Hunter"
#property link      ""
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <NZoneCommon.mqh>

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
