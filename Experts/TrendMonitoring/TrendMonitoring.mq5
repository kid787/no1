//+------------------------------------------------------------------+
//|                                              TrendMonitoring.mq5 |
//|                        Market Regime Detection Sample EA         |
//|                     Demonstrates MarketRegime.mqh Usage          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

#include "MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Input Parameters - Moving Averages                                |
//+------------------------------------------------------------------+
input group "=== Moving Average Settings ==="
input int      InpMAShortPeriod     = 20;       // 短期MA期間
input int      InpMAMediumPeriod    = 50;       // 中期MA期間
input int      InpMALongPeriod      = 200;      // 長期MA期間
input int      InpMASlopePeriod     = 5;        // MA傾き計算期間
input double   InpMASlopeThreshold  = 0.0001;   // MA傾き閾値

//+------------------------------------------------------------------+
//| Input Parameters - ADX                                            |
//+------------------------------------------------------------------+
input group "=== ADX Settings ==="
input int      InpADXPeriod         = 14;       // ADX期間
input double   InpADXTrendThreshold = 25.0;     // トレンド判定閾値
input double   InpADXTrendlessThreshold = 20.0; // トレンドレス判定閾値

//+------------------------------------------------------------------+
//| Input Parameters - Bollinger Bands                                |
//+------------------------------------------------------------------+
input group "=== Bollinger Bands Settings ==="
input int      InpBBPeriod          = 20;       // BB期間
input double   InpBBDeviation       = 2.0;      // BB偏差
input double   InpBBExpansionRatio  = 1.5;      // エクスパンション判定比率
input double   InpBBSqueezeRatio    = 0.5;      // スクイーズ判定比率

//+------------------------------------------------------------------+
//| Input Parameters - RSI                                            |
//+------------------------------------------------------------------+
input group "=== RSI Settings ==="
input int      InpRSIPeriod         = 14;       // RSI期間
input double   InpRSIUpper          = 70.0;     // RSI上限
input double   InpRSILower          = 30.0;     // RSI下限
input double   InpRSICenterRange    = 10.0;     // RSI中心帯範囲

//+------------------------------------------------------------------+
//| Input Parameters - ATR                                            |
//+------------------------------------------------------------------+
input group "=== ATR Settings ==="
input int      InpATRPeriod         = 14;       // ATR期間
input int      InpATRLookback       = 20;       // ATR比較期間
input double   InpATRLowThreshold   = 0.7;      // 低ATR判定比率

//+------------------------------------------------------------------+
//| Input Parameters - Ichimoku                                       |
//+------------------------------------------------------------------+
input group "=== Ichimoku Settings ==="
input int      InpIchiTenkan        = 9;        // 転換線期間
input int      InpIchiKijun         = 26;       // 基準線期間
input int      InpIchiSenkou        = 52;       // 先行スパン期間

//+------------------------------------------------------------------+
//| Input Parameters - Swing Analysis                                 |
//+------------------------------------------------------------------+
input group "=== Swing Analysis Settings ==="
input int      InpSwingLookback     = 20;       // スイングH/L検出期間
input int      InpSwingStrength     = 3;        // スイング強度

//+------------------------------------------------------------------+
//| Input Parameters - Display                                        |
//+------------------------------------------------------------------+
input group "=== Display Settings ==="
input bool     InpShowPanel         = true;     // パネル表示
input bool     InpShowAlerts        = true;     // レジーム変更アラート
input color    InpTrendUpColor      = clrLime;  // 上昇トレンド色
input color    InpTrendDownColor    = clrRed;   // 下降トレンド色
input color    InpRangeColor        = clrYellow;// レンジ色
input color    InpTrendlessColor    = clrGray;  // トレンドレス色

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CMarketRegime  g_regime;
ENUM_MARKET_REGIME g_last_regime;
bool           g_first_run = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set up parameters
   SMarketRegimeParams params;
   InitDefaultParams(params);

   // Moving Averages
   params.ma_short_period = InpMAShortPeriod;
   params.ma_medium_period = InpMAMediumPeriod;
   params.ma_long_period = InpMALongPeriod;
   params.ma_slope_period = InpMASlopePeriod;
   params.ma_slope_threshold = InpMASlopeThreshold;

   // ADX
   params.adx_period = InpADXPeriod;
   params.adx_trend_threshold = InpADXTrendThreshold;
   params.adx_trendless_threshold = InpADXTrendlessThreshold;

   // Bollinger Bands
   params.bb_period = InpBBPeriod;
   params.bb_deviation = InpBBDeviation;
   params.bb_expansion_ratio = InpBBExpansionRatio;
   params.bb_squeeze_ratio = InpBBSqueezeRatio;

   // RSI
   params.rsi_period = InpRSIPeriod;
   params.rsi_upper = InpRSIUpper;
   params.rsi_lower = InpRSILower;
   params.rsi_center_range = InpRSICenterRange;

   // ATR
   params.atr_period = InpATRPeriod;
   params.atr_lookback = InpATRLookback;
   params.atr_low_threshold = InpATRLowThreshold;

   // Ichimoku
   params.ichi_tenkan = InpIchiTenkan;
   params.ichi_kijun = InpIchiKijun;
   params.ichi_senkou = InpIchiSenkou;

   // Swing Analysis
   params.swing_lookback = InpSwingLookback;
   params.swing_strength = InpSwingStrength;

   // Initialize the market regime detector
   if(!g_regime.Init(_Symbol, params))
   {
      Print("Failed to initialize Market Regime detector");
      return INIT_FAILED;
   }

   g_last_regime = REGIME_TRENDLESS;

   // Create info panel
   if(InpShowPanel)
      CreatePanel();

   Print("Trend Monitoring EA initialized successfully");
   Print("Analyzing ", _Symbol, " using D1 (Daily) timeframe data");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_regime.Deinit();

   // Remove panel objects
   ObjectsDeleteAll(0, "MR_");

   Print("Trend Monitoring EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Analyze market regime (automatically cached per D1 bar)
   ENUM_MARKET_REGIME current_regime = g_regime.Analyze(false);

   // Check for regime change
   if(current_regime != g_last_regime || g_first_run)
   {
      OnRegimeChange(g_last_regime, current_regime);
      g_last_regime = current_regime;
      g_first_run = false;
   }

   // Update panel
   if(InpShowPanel)
      UpdatePanel();

   // Execute trading logic based on regime
   ExecuteTradingLogic(current_regime);
}

//+------------------------------------------------------------------+
//| Handle Regime Change                                              |
//+------------------------------------------------------------------+
void OnRegimeChange(ENUM_MARKET_REGIME old_regime, ENUM_MARKET_REGIME new_regime)
{
   string old_str = GetRegimeDisplayName(old_regime);
   string new_str = GetRegimeDisplayName(new_regime);

   string message = StringFormat("Market Regime Changed: %s -> %s\n%s",
                                  old_str, new_str,
                                  g_regime.GetRegimeDescription());

   Print(message);

   if(InpShowAlerts && !g_first_run)
   {
      Alert(message);
   }

   // Log detailed analysis
   SMarketAnalysisResult result;
   g_regime.GetAnalysisResult(result);
   Print(StringFormat("Scores - Trend: %d, Range: %d, Trendless: %d",
                       result.trend_score, result.range_score, result.trendless_score));
   Print(StringFormat("ADX: %.2f, RSI: %.2f, ATR: %.5f",
                       result.adx_value, result.rsi_value, result.atr_value));
}

//+------------------------------------------------------------------+
//| Execute Trading Logic Based on Regime                             |
//+------------------------------------------------------------------+
void ExecuteTradingLogic(ENUM_MARKET_REGIME regime)
{
   // This is where you implement your trading strategy
   // Different strategies for different market conditions

   switch(regime)
   {
      case REGIME_TREND_UP:
         // Implement trend-following buy strategy
         // Example: Look for pullbacks to MA, breakout entries
         TrendFollowingStrategy(true);
         break;

      case REGIME_TREND_DOWN:
         // Implement trend-following sell strategy
         TrendFollowingStrategy(false);
         break;

      case REGIME_RANGE:
         // Implement mean-reversion strategy
         // Example: Buy at support, sell at resistance
         RangeTradingStrategy();
         break;

      case REGIME_TRENDLESS:
         // Reduce or avoid trading
         // Example: Tighten stops, reduce position sizes
         TrendlessStrategy();
         break;
   }
}

//+------------------------------------------------------------------+
//| Trend Following Strategy Placeholder                              |
//+------------------------------------------------------------------+
void TrendFollowingStrategy(bool is_bullish)
{
   // Implement your trend following logic here
   // Examples:
   // - Enter on MA pullbacks
   // - Use ATR for stop loss placement
   // - Trail stops using MA or swing points

   // This is a placeholder - implement your actual strategy
   static datetime last_log = 0;
   datetime current = TimeCurrent();

   if(current - last_log > 3600)  // Log once per hour
   {
      string direction = is_bullish ? "BULLISH" : "BEARISH";
      Comment("Strategy: Trend Following (", direction, ")\n",
              "Looking for trend continuation setups...");
      last_log = current;
   }
}

//+------------------------------------------------------------------+
//| Range Trading Strategy Placeholder                                |
//+------------------------------------------------------------------+
void RangeTradingStrategy()
{
   // Implement your range trading logic here
   // Examples:
   // - Buy at support levels
   // - Sell at resistance levels
   // - Use oscillators for entry timing

   static datetime last_log = 0;
   datetime current = TimeCurrent();

   if(current - last_log > 3600)
   {
      Comment("Strategy: Range Trading\n",
              "Looking for mean reversion setups...");
      last_log = current;
   }
}

//+------------------------------------------------------------------+
//| Trendless Strategy Placeholder                                    |
//+------------------------------------------------------------------+
void TrendlessStrategy()
{
   // Implement your trendless market logic here
   // Examples:
   // - Reduce position sizes
   // - Widen stops or avoid new entries
   // - Wait for clearer signals

   static datetime last_log = 0;
   datetime current = TimeCurrent();

   if(current - last_log > 3600)
   {
      Comment("Strategy: Trendless/Waiting\n",
              "Market conditions unclear - reducing exposure...");
      last_log = current;
   }
}

//+------------------------------------------------------------------+
//| Create Info Panel                                                 |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = 10;
   int y = 30;
   int width = 300;
   int height = 250;

   // Background
   ObjectCreate(0, "MR_Background", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "MR_Background", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "MR_Background", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "MR_Background", OBJPROP_XSIZE, width);
   ObjectSetInteger(0, "MR_Background", OBJPROP_YSIZE, height);
   ObjectSetInteger(0, "MR_Background", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "MR_Background", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "MR_Background", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "MR_Background", OBJPROP_CORNER, CORNER_LEFT_UPPER);

   // Title
   CreateLabel("MR_Title", x + 10, y + 5, "Trend Monitoring - Market Regime", clrWhite, 12);

   // Regime display
   CreateLabel("MR_Regime", x + 10, y + 30, "Regime: ---", clrWhite, 10);
   CreateLabel("MR_Description", x + 10, y + 50, "", clrGray, 8);

   // Scores
   CreateLabel("MR_TrendScore", x + 10, y + 80, "Trend Score: 0", clrWhite, 9);
   CreateLabel("MR_RangeScore", x + 10, y + 100, "Range Score: 0", clrWhite, 9);
   CreateLabel("MR_TrendlessScore", x + 10, y + 120, "Trendless Score: 0", clrWhite, 9);

   // Indicators
   CreateLabel("MR_ADX", x + 10, y + 150, "ADX: ---", clrWhite, 9);
   CreateLabel("MR_RSI", x + 10, y + 170, "RSI: ---", clrWhite, 9);
   CreateLabel("MR_ATR", x + 10, y + 190, "ATR: ---", clrWhite, 9);

   // Conditions
   CreateLabel("MR_Conditions", x + 10, y + 220, "Analyzing...", clrGray, 8);
}

//+------------------------------------------------------------------+
//| Create Label Helper                                               |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int font_size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Update Info Panel                                                 |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   SMarketAnalysisResult result;
   g_regime.GetAnalysisResult(result);
   ENUM_MARKET_REGIME regime = result.regime;

   // Get regime color
   color regime_color;
   switch(regime)
   {
      case REGIME_TREND_UP:   regime_color = InpTrendUpColor;   break;
      case REGIME_TREND_DOWN: regime_color = InpTrendDownColor; break;
      case REGIME_RANGE:      regime_color = InpRangeColor;     break;
      default:                regime_color = InpTrendlessColor; break;
   }

   // Update regime
   ObjectSetString(0, "MR_Regime", OBJPROP_TEXT, "Regime: " + GetRegimeDisplayName(regime));
   ObjectSetInteger(0, "MR_Regime", OBJPROP_COLOR, regime_color);

   // Update description
   ObjectSetString(0, "MR_Description", OBJPROP_TEXT, result.regime_description);

   // Update scores
   ObjectSetString(0, "MR_TrendScore", OBJPROP_TEXT,
                    StringFormat("Trend Score: %d", result.trend_score));
   ObjectSetInteger(0, "MR_TrendScore", OBJPROP_COLOR,
                    result.trend_score >= 60 ? clrLime : clrWhite);

   ObjectSetString(0, "MR_RangeScore", OBJPROP_TEXT,
                    StringFormat("Range Score: %d", result.range_score));
   ObjectSetInteger(0, "MR_RangeScore", OBJPROP_COLOR,
                    result.range_score >= 50 ? clrYellow : clrWhite);

   ObjectSetString(0, "MR_TrendlessScore", OBJPROP_TEXT,
                    StringFormat("Trendless Score: %d", result.trendless_score));
   ObjectSetInteger(0, "MR_TrendlessScore", OBJPROP_COLOR,
                    result.trendless_score >= 50 ? clrGray : clrWhite);

   // Update indicators
   ObjectSetString(0, "MR_ADX", OBJPROP_TEXT,
                    StringFormat("ADX: %.2f %s",
                                  result.adx_value,
                                  result.is_adx_trending ? "(Trending)" : ""));

   ObjectSetString(0, "MR_RSI", OBJPROP_TEXT,
                    StringFormat("RSI: %.2f %s",
                                  result.rsi_value,
                                  result.is_rsi_near_center ? "(Center)" : ""));

   ObjectSetString(0, "MR_ATR", OBJPROP_TEXT,
                    StringFormat("ATR: %.5f %s",
                                  result.atr_value,
                                  result.is_atr_low ? "(Low)" : ""));

   // Update conditions summary
   string conditions = "";
   if(result.is_perfect_order_bullish) conditions += "PO(Up) ";
   if(result.is_perfect_order_bearish) conditions += "PO(Down) ";
   if(result.is_bb_expanding) conditions += "BBExp ";
   if(result.is_bb_squeezing) conditions += "BBSqz ";
   if(result.is_band_walk_upper) conditions += "BW(Up) ";
   if(result.is_band_walk_lower) conditions += "BW(Down) ";
   if(result.is_in_ichimoku_cloud) conditions += "Cloud ";

   if(conditions == "") conditions = "No strong signals";
   ObjectSetString(0, "MR_Conditions", OBJPROP_TEXT, conditions);
}

//+------------------------------------------------------------------+
//| Get Regime Display Name                                           |
//+------------------------------------------------------------------+
string GetRegimeDisplayName(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_TREND_UP:   return "TREND UP";
      case REGIME_TREND_DOWN: return "TREND DOWN";
      case REGIME_RANGE:      return "RANGE";
      case REGIME_TRENDLESS:  return "TRENDLESS";
      default:                return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Timer function (optional - for periodic updates)                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Can be used for periodic regime checks independent of ticks
   // Enable with EventSetTimer(3600) in OnInit for hourly updates
}
//+------------------------------------------------------------------+
