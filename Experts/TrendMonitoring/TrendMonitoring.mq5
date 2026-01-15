//+------------------------------------------------------------------+
//|                                              TrendMonitoring.mq5 |
//|                    Multi-Symbol Market Regime Detection EA       |
//|                     Based on D1 (Daily) Chart Analysis           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "3.10"
#property strict

#include "MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define MAX_SYMBOLS 20   // 監視シンボル最大数

//+------------------------------------------------------------------+
//| Input Parameters - Symbols (カンマ区切りで入力)                    |
//+------------------------------------------------------------------+
input group "=== Symbol Settings (カンマ区切り) ==="
input string InpSymbols = "EURUSD,GBPUSD,AUDUSD,USDJPY,USDCAD,EURJPY,GBPJPY,AUDJPY,CADJPY,EURGBP,EURAUD,EURCAD,GBPAUD,GBPCAD,AUDCAD,XAUUSD,XAUJPY"; // 監視シンボル
input string InpSymbolSuffix = "";  // シンボル接尾辞 (例: m, .pro, など)

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
input color    InpTrendColor        = clrLime;  // トレンド色（蛍光緑）
input color    InpRangeColor        = clrRed;   // レンジ色（赤）
input color    InpTrendlessColor    = clrDimGray; // トレンドレス色（グレー）
input color    InpBackgroundColor   = clrBlack; // 背景色

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
string g_symbols[MAX_SYMBOLS];                    // 監視シンボル配列
string g_display_names[MAX_SYMBOLS];              // 表示用シンボル名
CMarketRegime g_regimes[MAX_SYMBOLS];             // 各シンボルのRegime検出器
ENUM_MARKET_REGIME g_last_regimes[MAX_SYMBOLS];   // 前回のRegime
int g_symbol_count = 0;                           // 有効なシンボル数
bool g_first_run = true;
int g_chart_width = 0;
int g_chart_height = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // チャートサイズ取得
   g_chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   // チャート設定（フルスクリーン用 - ローソク足非表示）
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(0, CHART_SHOW_OHLC, false);
   ChartSetInteger(0, CHART_SHOW_BID_LINE, false);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, false);
   ChartSetInteger(0, CHART_SHOW_LAST_LINE, false);
   ChartSetInteger(0, CHART_SHOW_PRICE_SCALE, false);
   ChartSetInteger(0, CHART_SHOW_DATE_SCALE, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, InpBackgroundColor);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_FOREGROUND, false);

   // ローソク足を背景色と同じにして非表示
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, InpBackgroundColor);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, InpBackgroundColor);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, InpBackgroundColor);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, InpBackgroundColor);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, InpBackgroundColor);

   // シンボルリスト初期化（ユーザー入力から）
   InitSymbolListFromInput();

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
   CreateFullScreenPanel();

   Print("=== Trend Monitoring EA v3.0 (Custom Symbols) ===");
   Print("Monitoring ", g_symbol_count, " symbols on D1 timeframe");
   Print("Symbol suffix: '", InpSymbolSuffix, "'");

   // チャートイベント有効化
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);

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
               g_display_names[i],
               GetRegimeShortName(g_last_regimes[i]),
               GetRegimeShortName(current));
            Alert(msg);
         }
         g_last_regimes[i] = current;
      }
   }

   g_first_run = false;

   // パネル更新
   UpdateFullScreenPanel();
}

//+------------------------------------------------------------------+
//| Chart Event Handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      // チャートサイズ変更時にパネル再描画
      int new_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int new_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

      if(new_width != g_chart_width || new_height != g_chart_height)
      {
         g_chart_width = new_width;
         g_chart_height = new_height;
         ObjectsDeleteAll(0, "TM_");
         CreateFullScreenPanel();
         UpdateFullScreenPanel();
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize Symbol List from User Input                            |
//+------------------------------------------------------------------+
void InitSymbolListFromInput()
{
   g_symbol_count = 0;

   // カンマ区切りの文字列を分割
   string symbols_input = InpSymbols;
   string symbol_array[];

   // 空白を除去
   StringReplace(symbols_input, " ", "");

   // カンマで分割
   int count = StringSplit(symbols_input, ',', symbol_array);

   for(int i = 0; i < count && g_symbol_count < MAX_SYMBOLS; i++)
   {
      string base_symbol = symbol_array[i];
      if(StringLen(base_symbol) == 0) continue;

      // 接尾辞を追加してシンボル名を構築
      string full_symbol = base_symbol + InpSymbolSuffix;

      // シンボルが存在するか確認
      if(AddSymbolIfExists(full_symbol, base_symbol))
      {
         Print("Added: ", full_symbol, " (display: ", base_symbol, ")");
      }
      else
      {
         // 接尾辞なしで再試行
         if(StringLen(InpSymbolSuffix) > 0 && AddSymbolIfExists(base_symbol, base_symbol))
         {
            Print("Added (no suffix): ", base_symbol);
         }
         else
         {
            Print("Symbol not found: ", full_symbol, " or ", base_symbol);
         }
      }
   }

   Print("Total symbols initialized: ", g_symbol_count);
}

//+------------------------------------------------------------------+
//| Add Symbol if Exists in Market Watch                              |
//+------------------------------------------------------------------+
bool AddSymbolIfExists(string symbol, string display_name)
{
   if(g_symbol_count >= MAX_SYMBOLS) return false;

   // シンボルを気配値に追加試行
   if(SymbolSelect(symbol, true))
   {
      // シンボルが有効かチェック（価格が取得できるか）
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(bid > 0)
      {
         g_symbols[g_symbol_count] = symbol;
         g_display_names[g_symbol_count] = display_name;
         g_symbol_count++;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Create Full Screen Panel                                          |
//+------------------------------------------------------------------+
void CreateFullScreenPanel()
{
   int margin = 20;
   int title_height = 60;
   int legend_height = 50;
   int available_height = g_chart_height - title_height - legend_height - margin * 2;
   int row_height = available_height / (g_symbol_count + 1);
   if(row_height < 25) row_height = 25;
   if(row_height > 45) row_height = 45;

   int col_width = (g_chart_width - margin * 2) / 6;

   // 背景
   CreateRectangle("TM_BG", 0, 0, g_chart_width, g_chart_height, InpBackgroundColor);

   // タイトル
   int title_font = 22;
   CreateLabelEx("TM_Title", g_chart_width / 2, margin,
      "MULTI-SYMBOL TREND MONITOR (D1)", clrWhite, title_font, true, true);

   // 更新時刻
   CreateLabelEx("TM_Time", g_chart_width / 2, margin + 32,
      "", clrSilver, 11, false, true);

   // ヘッダー行
   int header_y = title_height + margin;
   int header_font = 12;
   CreateLabelEx("TM_H1", margin + col_width * 0 + col_width/2, header_y, "SYMBOL", clrSilver, header_font, true, true);
   CreateLabelEx("TM_H2", margin + col_width * 1 + col_width/2, header_y, "STATUS", clrSilver, header_font, true, true);
   CreateLabelEx("TM_H3", margin + col_width * 2 + col_width/2, header_y, "TREND", clrSilver, header_font, true, true);
   CreateLabelEx("TM_H4", margin + col_width * 3 + col_width/2, header_y, "ADX", clrSilver, header_font, true, true);
   CreateLabelEx("TM_H5", margin + col_width * 4 + col_width/2, header_y, "RSI", clrSilver, header_font, true, true);
   CreateLabelEx("TM_H6", margin + col_width * 5 + col_width/2, header_y, "SIGNALS", clrSilver, header_font, true, true);

   // 区切り線
   CreateHLine("TM_Line1", header_y + 22, clrDimGray);

   // 各シンボル行
   int data_font = 14;
   int start_y = header_y + 30;

   for(int i = 0; i < g_symbol_count; i++)
   {
      int row_y = start_y + i * row_height;
      string prefix = "TM_R" + IntegerToString(i) + "_";

      // 行背景（交互）
      if(i % 2 == 1)
      {
         CreateRectangle(prefix + "BG", margin, row_y - 5, g_chart_width - margin * 2, row_height, C'20,20,20');
      }

      // シンボル（表示名を使用）
      CreateLabelEx(prefix + "Symbol", margin + col_width * 0 + col_width/2, row_y,
         g_display_names[i], clrWhite, data_font, true, true);

      // ステータス
      CreateLabelEx(prefix + "Status", margin + col_width * 1 + col_width/2, row_y,
         "---", clrGray, data_font + 2, false, true);

      // トレンドスコア
      CreateLabelEx(prefix + "TScore", margin + col_width * 2 + col_width/2, row_y,
         "0", clrGray, data_font, false, true);

      // ADX
      CreateLabelEx(prefix + "ADX", margin + col_width * 3 + col_width/2, row_y,
         "0.0", clrGray, data_font, false, true);

      // RSI
      CreateLabelEx(prefix + "RSI", margin + col_width * 4 + col_width/2, row_y,
         "0.0", clrGray, data_font, false, true);

      // シグナル
      CreateLabelEx(prefix + "Signals", margin + col_width * 5 + col_width/2, row_y,
         "-", clrGray, data_font - 2, false, true);
   }

   // 凡例
   int legend_y = g_chart_height - legend_height + 10;
   int legend_font = 12;

   CreateLabelEx("TM_Leg0", g_chart_width / 2 - 280, legend_y, "Legend:", clrWhite, legend_font, false, false);
   CreateLabelEx("TM_Leg1", g_chart_width / 2 - 180, legend_y, "TREND", InpTrendColor, legend_font, true, false);
   CreateLabelEx("TM_Leg2", g_chart_width / 2 - 60, legend_y, "RANGE", InpRangeColor, legend_font, true, false);
   CreateLabelEx("TM_Leg3", g_chart_width / 2 + 60, legend_y, "FLAT", InpTrendlessColor, legend_font, false, false);

   CreateLabelEx("TM_Leg4", g_chart_width / 2, legend_y + 22,
      "Symbols: " + IntegerToString(g_symbol_count) + " | Suffix: '" + InpSymbolSuffix + "'", clrDimGray, 9, false, true);
}

//+------------------------------------------------------------------+
//| Update Full Screen Panel                                          |
//+------------------------------------------------------------------+
void UpdateFullScreenPanel()
{
   // 時刻更新
   ObjectSetString(0, "TM_Time", OBJPROP_TEXT,
      "Last Update: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));

   // 各シンボルの情報更新
   for(int i = 0; i < g_symbol_count; i++)
   {
      string prefix = "TM_R" + IntegerToString(i) + "_";

      // データ準備チェック
      if(!g_regimes[i].IsReady())
      {
         // ローディング表示
         ObjectSetString(0, prefix + "Status", OBJPROP_TEXT, "Loading...");
         ObjectSetInteger(0, prefix + "Status", OBJPROP_COLOR, clrDarkGray);
         ObjectSetString(0, prefix + "Status", OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, prefix + "Symbol", OBJPROP_COLOR, clrDarkGray);
         ObjectSetString(0, prefix + "TScore", OBJPROP_TEXT, "-");
         ObjectSetString(0, prefix + "ADX", OBJPROP_TEXT, "-");
         ObjectSetString(0, prefix + "RSI", OBJPROP_TEXT, "-");
         ObjectSetString(0, prefix + "Signals", OBJPROP_TEXT, "-");
         continue;
      }

      SMarketAnalysisResult result;
      g_regimes[i].GetAnalysisResult(result);

      // ステータス（色と太字を変更）
      string status_str = "";
      color status_color = InpTrendlessColor;
      bool is_bold = false;

      switch(result.regime)
      {
         case REGIME_TREND_UP:
            status_str = "▲ TREND UP";
            status_color = InpTrendColor;
            is_bold = true;
            break;
         case REGIME_TREND_DOWN:
            status_str = "▼ TREND DOWN";
            status_color = InpTrendColor;
            is_bold = true;
            break;
         case REGIME_RANGE:
            status_str = "◆ RANGE";
            status_color = InpRangeColor;
            is_bold = true;
            break;
         case REGIME_TRENDLESS:
            status_str = "― FLAT";
            status_color = InpTrendlessColor;
            is_bold = false;
            break;
      }

      ObjectSetString(0, prefix + "Status", OBJPROP_TEXT, status_str);
      ObjectSetInteger(0, prefix + "Status", OBJPROP_COLOR, status_color);
      ObjectSetString(0, prefix + "Status", OBJPROP_FONT, is_bold ? "Arial Bold" : "Arial");

      // シンボル名の色も連動
      ObjectSetInteger(0, prefix + "Symbol", OBJPROP_COLOR, status_color);
      ObjectSetString(0, prefix + "Symbol", OBJPROP_FONT, is_bold ? "Arial Bold" : "Arial");

      // トレンドスコア
      string tscore_str = IntegerToString(result.trend_score);
      ObjectSetString(0, prefix + "TScore", OBJPROP_TEXT, tscore_str);
      ObjectSetInteger(0, prefix + "TScore", OBJPROP_COLOR, status_color);
      ObjectSetString(0, prefix + "TScore", OBJPROP_FONT, is_bold ? "Arial Bold" : "Arial");

      // ADX
      string adx_str = DoubleToString(result.adx_value, 1);
      ObjectSetString(0, prefix + "ADX", OBJPROP_TEXT, adx_str);
      ObjectSetInteger(0, prefix + "ADX", OBJPROP_COLOR, status_color);
      ObjectSetString(0, prefix + "ADX", OBJPROP_FONT, is_bold ? "Arial Bold" : "Arial");

      // RSI
      string rsi_str = DoubleToString(result.rsi_value, 1);
      ObjectSetString(0, prefix + "RSI", OBJPROP_TEXT, rsi_str);
      ObjectSetInteger(0, prefix + "RSI", OBJPROP_COLOR, status_color);
      ObjectSetString(0, prefix + "RSI", OBJPROP_FONT, is_bold ? "Arial Bold" : "Arial");

      // シグナル
      string signals = BuildSignalString(result);
      ObjectSetString(0, prefix + "Signals", OBJPROP_TEXT, signals);
      ObjectSetInteger(0, prefix + "Signals", OBJPROP_COLOR, status_color);
      ObjectSetString(0, prefix + "Signals", OBJPROP_FONT, is_bold ? "Arial Bold" : "Arial");
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Build Signal String                                               |
//+------------------------------------------------------------------+
string BuildSignalString(SMarketAnalysisResult &result)
{
   string signals = "";

   if(result.is_perfect_order_bullish) signals += "PO+ ";
   if(result.is_perfect_order_bearish) signals += "PO- ";
   if(result.is_bb_expanding) signals += "BBEx ";
   if(result.is_band_walk_upper) signals += "BW+ ";
   if(result.is_band_walk_lower) signals += "BW- ";
   if(result.is_bb_squeezing) signals += "BBSq ";
   if(result.is_in_ichimoku_cloud) signals += "Cloud ";
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
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Create Horizontal Line Helper                                     |
//+------------------------------------------------------------------+
void CreateHLine(string name, int y, color line_color)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, g_chart_width - 40);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 1);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, line_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Create Label Extended Helper                                      |
//+------------------------------------------------------------------+
void CreateLabelEx(string name, int x, int y, string text, color clr, int font_size, bool bold, bool center)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, center ? ANCHOR_CENTER : ANCHOR_LEFT);
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
}
//+------------------------------------------------------------------+
