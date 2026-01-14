//+------------------------------------------------------------------+
//|                                              TrendMonitoring.mq5 |
//|                    Multi-Symbol Market Regime Detection EA       |
//|                     Based on D1 (Daily) Chart Analysis           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "2.00"
#property strict

#include "MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define MAX_SYMBOLS 17   // 監視シンボル最大数

//+------------------------------------------------------------------+
//| Input Parameters - Moving Averages                                |
//+------------------------------------------------------------------+
input group "=== Moving Average Settings ==="
input int      InpMAShortPeriod     = 20;       // 短期MA期間
input int      InpMAMediumPeriod    = 50;       // 中期MA期間
input int      InpMALongPeriod      = 200;      // 長期MA期間

//+------------------------------------------------------------------+
//| Input Parameters - ADX                                            |
//+------------------------------------------------------------------+
input group "=== ADX Settings ==="
input int      InpADXPeriod         = 14;       // ADX期間
input double   InpADXTrendThreshold = 25.0;     // トレンド判定閾値

//+------------------------------------------------------------------+
//| Input Parameters - Display                                        |
//+------------------------------------------------------------------+
input group "=== Display Settings ==="
input bool     InpShowAlerts        = true;     // レジーム変更アラート
input int      InpPanelX            = 10;       // パネルX位置
input int      InpPanelY            = 30;       // パネルY位置
input color    InpTrendUpColor      = clrLime;  // 上昇トレンド色
input color    InpTrendDownColor    = clrRed;   // 下降トレンド色
input color    InpRangeColor        = clrYellow;// レンジ色
input color    InpTrendlessColor    = clrGray;  // トレンドレス色
input color    InpBackgroundColor   = C'20,20,30'; // 背景色
input color    InpHeaderColor       = C'40,40,60'; // ヘッダー色

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
string g_symbols[MAX_SYMBOLS];                    // 監視シンボル配列
CMarketRegime g_regimes[MAX_SYMBOLS];             // 各シンボルのRegime検出器
ENUM_MARKET_REGIME g_last_regimes[MAX_SYMBOLS];   // 前回のRegime
int g_symbol_count = 0;                           // 有効なシンボル数
bool g_first_run = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // シンボルリスト初期化
   InitSymbolList();

   // パラメータ設定
   SMarketRegimeParams params;
   InitDefaultParams(params);
   params.ma_short_period = InpMAShortPeriod;
   params.ma_medium_period = InpMAMediumPeriod;
   params.ma_long_period = InpMALongPeriod;
   params.adx_period = InpADXPeriod;
   params.adx_trend_threshold = InpADXTrendThreshold;

   // 各シンボルのRegime検出器を初期化
   for(int i = 0; i < g_symbol_count; i++)
   {
      g_last_regimes[i] = REGIME_TRENDLESS;
      if(!g_regimes[i].Init(g_symbols[i], params))
      {
         Print("Failed to initialize regime detector for ", g_symbols[i]);
      }
   }

   // パネル作成
   CreateMultiSymbolPanel();

   Print("=== Trend Monitoring EA v2.0 ===");
   Print("Monitoring ", g_symbol_count, " symbols on D1 timeframe");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Regime検出器の解放
   for(int i = 0; i < g_symbol_count; i++)
   {
      g_regimes[i].Deinit();
   }

   // パネル削除
   ObjectsDeleteAll(0, "TM_");
   Comment("");

   Print("Trend Monitoring EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // 全シンボルの分析を実行
   for(int i = 0; i < g_symbol_count; i++)
   {
      ENUM_MARKET_REGIME current = g_regimes[i].Analyze(false);

      // Regime変更検出
      if(current != g_last_regimes[i] || g_first_run)
      {
         if(!g_first_run && InpShowAlerts)
         {
            string msg = StringFormat("%s: %s -> %s",
               g_symbols[i],
               GetRegimeShortName(g_last_regimes[i]),
               GetRegimeShortName(current));
            Alert(msg);
         }
         g_last_regimes[i] = current;
      }
   }

   g_first_run = false;

   // パネル更新
   UpdateMultiSymbolPanel();
}

//+------------------------------------------------------------------+
//| Initialize Symbol List                                            |
//+------------------------------------------------------------------+
void InitSymbolList()
{
   g_symbol_count = 0;

   // メジャー通貨ペア (USD関連)
   AddSymbolIfExists("EURUSD");
   AddSymbolIfExists("GBPUSD");
   AddSymbolIfExists("AUDUSD");
   AddSymbolIfExists("USDJPY");
   AddSymbolIfExists("USDCAD");

   // クロス円
   AddSymbolIfExists("EURJPY");
   AddSymbolIfExists("GBPJPY");
   AddSymbolIfExists("AUDJPY");
   AddSymbolIfExists("CADJPY");

   // 欧州クロス
   AddSymbolIfExists("EURGBP");
   AddSymbolIfExists("EURAUD");
   AddSymbolIfExists("EURCAD");

   // その他のクロス
   AddSymbolIfExists("GBPAUD");
   AddSymbolIfExists("GBPCAD");
   AddSymbolIfExists("AUDCAD");

   // ゴールド
   AddSymbolIfExists("XAUUSD");
   AddSymbolIfExists("XAUJPY");

   Print("Initialized ", g_symbol_count, " symbols for monitoring");
}

//+------------------------------------------------------------------+
//| Add Symbol if Exists in Market Watch                              |
//+------------------------------------------------------------------+
void AddSymbolIfExists(string symbol)
{
   if(g_symbol_count >= MAX_SYMBOLS) return;

   // シンボルが存在するか確認
   if(SymbolSelect(symbol, true))
   {
      g_symbols[g_symbol_count] = symbol;
      g_symbol_count++;
      Print("Added symbol: ", symbol);
   }
   else
   {
      Print("Symbol not available: ", symbol);
   }
}

//+------------------------------------------------------------------+
//| Create Multi-Symbol Panel                                         |
//+------------------------------------------------------------------+
void CreateMultiSymbolPanel()
{
   int x = InpPanelX;
   int y = InpPanelY;
   int row_height = 20;
   int panel_width = 750;
   int header_height = 25;
   int panel_height = header_height + (g_symbol_count + 1) * row_height + 10;

   // メイン背景
   CreateRectangle("TM_BG", x, y, panel_width, panel_height, InpBackgroundColor);

   // タイトルバー
   CreateRectangle("TM_Header", x, y, panel_width, header_height, InpHeaderColor);
   CreateLabel("TM_Title", x + 10, y + 5, "Multi-Symbol Trend Monitor (D1)", clrWhite, 11);
   CreateLabel("TM_Time", x + panel_width - 200, y + 5, "", clrSilver, 9);

   // カラムヘッダー
   int header_y = y + header_height + 5;
   CreateLabel("TM_H_Symbol", x + 10, header_y, "Symbol", clrSilver, 9);
   CreateLabel("TM_H_Regime", x + 100, header_y, "Regime", clrSilver, 9);
   CreateLabel("TM_H_TScore", x + 200, header_y, "Trend", clrSilver, 9);
   CreateLabel("TM_H_RScore", x + 260, header_y, "Range", clrSilver, 9);
   CreateLabel("TM_H_ADX", x + 320, header_y, "ADX", clrSilver, 9);
   CreateLabel("TM_H_RSI", x + 380, header_y, "RSI", clrSilver, 9);
   CreateLabel("TM_H_Signals", x + 440, header_y, "Signals", clrSilver, 9);

   // 各シンボル行
   for(int i = 0; i < g_symbol_count; i++)
   {
      int row_y = header_y + (i + 1) * row_height;
      string prefix = "TM_R" + IntegerToString(i) + "_";

      // 行背景（交互色）
      color row_bg = (i % 2 == 0) ? InpBackgroundColor : C'25,25,35';
      CreateRectangle(prefix + "BG", x + 5, row_y - 2, panel_width - 10, row_height, row_bg);

      // シンボル名
      CreateLabel(prefix + "Symbol", x + 10, row_y, g_symbols[i], clrWhite, 9);

      // Regime
      CreateLabel(prefix + "Regime", x + 100, row_y, "---", clrGray, 9);

      // スコア
      CreateLabel(prefix + "TScore", x + 200, row_y, "0", clrGray, 9);
      CreateLabel(prefix + "RScore", x + 260, row_y, "0", clrGray, 9);

      // インジケーター値
      CreateLabel(prefix + "ADX", x + 320, row_y, "0.0", clrGray, 9);
      CreateLabel(prefix + "RSI", x + 380, row_y, "0.0", clrGray, 9);

      // シグナル
      CreateLabel(prefix + "Signals", x + 440, row_y, "", clrGray, 8);
   }

   // 凡例
   int legend_y = y + panel_height + 5;
   CreateLabel("TM_Legend", x + 10, legend_y, "Legend:", clrSilver, 8);
   CreateLabel("TM_Leg1", x + 60, legend_y, "UP", InpTrendUpColor, 8);
   CreateLabel("TM_Leg2", x + 90, legend_y, "DOWN", InpTrendDownColor, 8);
   CreateLabel("TM_Leg3", x + 140, legend_y, "RANGE", InpRangeColor, 8);
   CreateLabel("TM_Leg4", x + 200, legend_y, "TRENDLESS", InpTrendlessColor, 8);
}

//+------------------------------------------------------------------+
//| Update Multi-Symbol Panel                                         |
//+------------------------------------------------------------------+
void UpdateMultiSymbolPanel()
{
   // 時刻更新
   ObjectSetString(0, "TM_Time", OBJPROP_TEXT,
      "Updated: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));

   // 各シンボルの情報更新
   for(int i = 0; i < g_symbol_count; i++)
   {
      string prefix = "TM_R" + IntegerToString(i) + "_";

      SMarketAnalysisResult result;
      g_regimes[i].GetAnalysisResult(result);

      // Regime表示
      string regime_str = GetRegimeShortName(result.regime);
      color regime_color = GetRegimeColor(result.regime);

      ObjectSetString(0, prefix + "Regime", OBJPROP_TEXT, regime_str);
      ObjectSetInteger(0, prefix + "Regime", OBJPROP_COLOR, regime_color);

      // スコア表示
      ObjectSetString(0, prefix + "TScore", OBJPROP_TEXT, IntegerToString(result.trend_score));
      ObjectSetInteger(0, prefix + "TScore", OBJPROP_COLOR,
         result.trend_score >= 60 ? InpTrendUpColor : clrGray);

      ObjectSetString(0, prefix + "RScore", OBJPROP_TEXT, IntegerToString(result.range_score));
      ObjectSetInteger(0, prefix + "RScore", OBJPROP_COLOR,
         result.range_score >= 50 ? InpRangeColor : clrGray);

      // ADX
      ObjectSetString(0, prefix + "ADX", OBJPROP_TEXT, DoubleToString(result.adx_value, 1));
      ObjectSetInteger(0, prefix + "ADX", OBJPROP_COLOR,
         result.is_adx_trending ? InpTrendUpColor : clrGray);

      // RSI
      ObjectSetString(0, prefix + "RSI", OBJPROP_TEXT, DoubleToString(result.rsi_value, 1));
      color rsi_color = clrGray;
      if(result.rsi_value >= 70) rsi_color = InpTrendUpColor;
      else if(result.rsi_value <= 30) rsi_color = InpTrendDownColor;
      else if(result.is_rsi_near_center) rsi_color = InpRangeColor;
      ObjectSetInteger(0, prefix + "RSI", OBJPROP_COLOR, rsi_color);

      // シグナル
      string signals = BuildSignalString(result);
      ObjectSetString(0, prefix + "Signals", OBJPROP_TEXT, signals);
   }
}

//+------------------------------------------------------------------+
//| Build Signal String                                               |
//+------------------------------------------------------------------+
string BuildSignalString(SMarketAnalysisResult &result)
{
   string signals = "";

   // トレンドシグナル
   if(result.is_perfect_order_bullish) signals += "PO+ ";
   if(result.is_perfect_order_bearish) signals += "PO- ";
   if(result.is_bb_expanding) signals += "BBEx ";
   if(result.is_band_walk_upper) signals += "BW+ ";
   if(result.is_band_walk_lower) signals += "BW- ";

   // レンジシグナル
   if(result.is_bb_squeezing) signals += "BBSq ";
   if(result.is_ma_horizontal) signals += "MAH ";

   // 雲
   if(result.is_in_ichimoku_cloud) signals += "Cloud ";

   // ダウ理論
   if(result.is_higher_highs && result.is_higher_lows) signals += "HH/HL ";
   if(result.is_lower_highs && result.is_lower_lows) signals += "LH/LL ";

   if(signals == "") signals = "-";

   return signals;
}

//+------------------------------------------------------------------+
//| Get Regime Short Name                                             |
//+------------------------------------------------------------------+
string GetRegimeShortName(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_TREND_UP:   return "UP";
      case REGIME_TREND_DOWN: return "DOWN";
      case REGIME_RANGE:      return "RANGE";
      case REGIME_TRENDLESS:  return "FLAT";
      default:                return "---";
   }
}

//+------------------------------------------------------------------+
//| Get Regime Color                                                  |
//+------------------------------------------------------------------+
color GetRegimeColor(ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_TREND_UP:   return InpTrendUpColor;
      case REGIME_TREND_DOWN: return InpTrendDownColor;
      case REGIME_RANGE:      return InpRangeColor;
      case REGIME_TRENDLESS:  return InpTrendlessColor;
      default:                return clrGray;
   }
}

//+------------------------------------------------------------------+
//| Create Rectangle Helper                                           |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color bg_color)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
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
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
}
//+------------------------------------------------------------------+
