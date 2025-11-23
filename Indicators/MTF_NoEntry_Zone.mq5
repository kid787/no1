//+------------------------------------------------------------------+
//|                                           MTF_NoEntry_Zone.mq5   |
//|                        XAUUSDデイトレード用 上位足ノーエントリーゾーン可視化インジケーター |
//|                                    MTF No-Entry Zone Visualizer  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Input Parameters
// 機能A: 上位足の強力な抵抗帯ゾーン設定
input group "=== HTF Resistance/Support Zones ==="
input ENUM_TIMEFRAMES HTF1_Timeframe = PERIOD_H1;      // 上位足1の時間軸
input ENUM_TIMEFRAMES HTF2_Timeframe = PERIOD_H4;      // 上位足2の時間軸
input int HTF_Lookback_Bars = 100;                     // 遡るバー数
input double HTF_Zone_Pips = 5.0;                      // ゾーンの幅 (Pips)
input color HTF_Resistance_Color = clrDarkRed;         // レジスタンスゾーン色
input color HTF_Support_Color = clrDarkGreen;          // サポートゾーン色
input int HTF_Zone_Transparency = 220;                 // ゾーン透明度 (0-255)

// 機能B: レンジ相場の中央ゾーン設定
input group "=== Range Center Zone ==="
input ENUM_TIMEFRAMES Range_Timeframe = PERIOD_H4;     // レンジ計算用時間軸
input double Range_Center_Percentage = 0.4;            // 中央ゾーンの割合 (0.4=40%)
input color Range_Center_Color = clrYellow;            // レンジ中央ゾーン色
input int Range_Zone_Transparency = 230;               // ゾーン透明度 (0-255)

// 機能C: 構造崩壊ライン設定
input group "=== Neckline/Structural Break Line ==="
input ENUM_TIMEFRAMES Neckline_Timeframe = PERIOD_H4;  // ネックライン計算用時間軸
input color Neckline_Color = clrBlue;                  // ネックライン色
input color Neckline_Alert_Color = clrOrange;          // 接近時の警告色
input double Neckline_Alert_Pips = 10.0;               // 警告距離 (Pips)
input int Neckline_Width = 2;                          // ライン幅
input ENUM_LINE_STYLE Neckline_Style = STYLE_DASH;     // ラインスタイル

// 一般設定
input group "=== General Settings ==="
input bool Show_HTF_Zones = true;                      // 上位足ゾーンを表示
input bool Show_Range_Zone = true;                     // レンジ中央ゾーンを表示
input bool Show_Neckline = true;                       // ネックラインを表示
input int Max_Zones_Display = 5;                       // 最大表示ゾーン数

//--- グローバル変数
struct ZoneData
{
    double upper;
    double lower;
    bool isResistance;
    ENUM_TIMEFRAMES timeframe;
    string objectName;
};

struct RangeData
{
    double rangeHigh;
    double rangeLow;
    double centerUpper;
    double centerLower;
    string objectName;
};

struct NecklineData
{
    double price;
    bool isBullish;
    string objectName;
};

ZoneData htfZones[];
RangeData currentRange;
NecklineData currentNeckline;

double point_value;
double pip_value;
string indicator_prefix = "MTF_NoEntry_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // ポイント値とPips値を計算
    point_value = _Point;

    // XAUUSD (Gold)の場合、1 Pip = 0.1 ポイント（5桁業者）
    if(_Digits == 3 || _Digits == 5)
        pip_value = point_value * 10;
    else
        pip_value = point_value;

    // 指標名の設定
    IndicatorSetString(INDICATOR_SHORTNAME, "MTF No-Entry Zone Visualizer");

    // 既存のオブジェクトをクリア
    DeleteAllObjects();

    // 初回の計算とゾーン描画
    UpdateAllZones();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // すべてのオブジェクトを削除
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
    // 新しいバーが形成されたときにゾーンを更新
    static datetime lastBarTime = 0;
    if(time[rates_total - 1] != lastBarTime)
    {
        lastBarTime = time[rates_total - 1];
        UpdateAllZones();
    }

    // 価格がネックラインに接近しているかチェック
    if(Show_Neckline)
        UpdateNecklineColor();

    return(rates_total);
}

//+------------------------------------------------------------------+
//| すべてのゾーンとラインを更新                                        |
//+------------------------------------------------------------------+
void UpdateAllZones()
{
    // 既存のゾーンオブジェクトを削除
    DeleteAllObjects();

    // 機能A: 上位足の抵抗帯/サポートゾーンを計算・描画
    if(Show_HTF_Zones)
    {
        CalculateAndDrawHTFZones(HTF1_Timeframe, 1);
        CalculateAndDrawHTFZones(HTF2_Timeframe, 2);
    }

    // 機能B: レンジ中央ゾーンを計算・描画
    if(Show_Range_Zone)
    {
        CalculateAndDrawRangeZone();
    }

    // 機能C: ネックラインを計算・描画
    if(Show_Neckline)
    {
        CalculateAndDrawNeckline();
    }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 機能A: 上位足の抵抗帯/サポートゾーンを計算・描画                      |
//+------------------------------------------------------------------+
void CalculateAndDrawHTFZones(ENUM_TIMEFRAMES tf, int htf_number)
{
    // 上位足のデータを取得
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    int copied = CopyRates(_Symbol, tf, 0, HTF_Lookback_Bars, rates);
    if(copied <= 0)
    {
        Print("Failed to copy rates for timeframe ", EnumToString(tf));
        return;
    }

    // スイングハイとスイングローを検出
    double swingHighs[];
    double swingLows[];
    ArrayResize(swingHighs, 0);
    ArrayResize(swingLows, 0);

    // スイングポイントを検出（前後2本のバーと比較）
    for(int i = 2; i < copied - 2; i++)
    {
        // スイングハイの検出
        if(rates[i].high > rates[i-1].high &&
           rates[i].high > rates[i-2].high &&
           rates[i].high > rates[i+1].high &&
           rates[i].high > rates[i+2].high)
        {
            int size = ArraySize(swingHighs);
            ArrayResize(swingHighs, size + 1);
            swingHighs[size] = rates[i].high;
        }

        // スイングローの検出
        if(rates[i].low < rates[i-1].low &&
           rates[i].low < rates[i-2].low &&
           rates[i].low < rates[i+1].low &&
           rates[i].low < rates[i+2].low)
        {
            int size = ArraySize(swingLows);
            ArrayResize(swingLows, size + 1);
            swingLows[size] = rates[i].low;
        }
    }

    // 最も重要な（頻繁に意識される）価格帯を特定
    // 価格クラスタリング：近い価格帯をグループ化
    double zone_width = HTF_Zone_Pips * pip_value;

    // レジスタンスゾーンを作成
    if(ArraySize(swingHighs) > 0)
    {
        ArraySort(swingHighs);
        double clusters[];
        ClusterPrices(swingHighs, zone_width * 2, clusters);

        // 最も重要な上位N個のゾーンを描画
        int zones_to_draw = MathMin(ArraySize(clusters), Max_Zones_Display / 2);
        for(int i = 0; i < zones_to_draw; i++)
        {
            DrawZone(clusters[ArraySize(clusters) - 1 - i], zone_width, true, tf, htf_number, i);
        }
    }

    // サポートゾーンを作成
    if(ArraySize(swingLows) > 0)
    {
        ArraySort(swingLows);
        double clusters[];
        ClusterPrices(swingLows, zone_width * 2, clusters);

        // 最も重要な上位N個のゾーンを描画
        int zones_to_draw = MathMin(ArraySize(clusters), Max_Zones_Display / 2);
        for(int i = 0; i < zones_to_draw; i++)
        {
            DrawZone(clusters[i], zone_width, false, tf, htf_number, i);
        }
    }
}

//+------------------------------------------------------------------+
//| 価格クラスタリング関数                                             |
//+------------------------------------------------------------------+
void ClusterPrices(const double &prices[], double threshold, double &clusters[])
{
    ArrayResize(clusters, 0);

    if(ArraySize(prices) == 0)
        return;

    // 価格をグループ化
    for(int i = 0; i < ArraySize(prices); i++)
    {
        bool found_cluster = false;

        // 既存のクラスタに追加できるかチェック
        for(int j = 0; j < ArraySize(clusters); j++)
        {
            if(MathAbs(prices[i] - clusters[j]) <= threshold)
            {
                // クラスタの平均を更新
                clusters[j] = (clusters[j] + prices[i]) / 2;
                found_cluster = true;
                break;
            }
        }

        // 新しいクラスタを作成
        if(!found_cluster)
        {
            int size = ArraySize(clusters);
            ArrayResize(clusters, size + 1);
            clusters[size] = prices[i];
        }
    }
}

//+------------------------------------------------------------------+
//| ゾーンを描画                                                      |
//+------------------------------------------------------------------+
void DrawZone(double center_price, double width, bool is_resistance,
              ENUM_TIMEFRAMES tf, int htf_number, int zone_index)
{
    string obj_name = indicator_prefix + "Zone_" + EnumToString(tf) + "_" +
                      (is_resistance ? "R" : "S") + "_" + IntegerToString(zone_index);

    double upper = center_price + width / 2;
    double lower = center_price - width / 2;

    // 矩形オブジェクトを作成
    datetime time_start = iTime(_Symbol, PERIOD_CURRENT, 100);
    datetime time_end = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT) * 200;

    ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, time_start, upper, time_end, lower);

    // 色と透明度を設定
    color zone_color = is_resistance ? HTF_Resistance_Color : HTF_Support_Color;
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
    ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);

    // 透明度を設定（色にアルファチャンネルを追加）
    int alpha = HTF_Zone_Transparency;
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, ColorWithAlpha(zone_color, alpha));

    // 時間軸の移動に対応
    ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);
}

//+------------------------------------------------------------------+
//| 機能B: レンジ中央ゾーンを計算・描画                                  |
//+------------------------------------------------------------------+
void CalculateAndDrawRangeZone()
{
    // 上位足のデータを取得
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    int lookback = 50; // レンジ検出用のルックバック期間
    int copied = CopyRates(_Symbol, Range_Timeframe, 0, lookback, rates);
    if(copied <= 0)
        return;

    // 直近の主要なスイングハイとスイングローを検出
    double range_high = rates[0].high;
    double range_low = rates[0].low;

    for(int i = 0; i < copied; i++)
    {
        if(rates[i].high > range_high)
            range_high = rates[i].high;
        if(rates[i].low < range_low)
            range_low = rates[i].low;
    }

    // レンジ幅を計算
    double range_width = range_high - range_low;

    // レンジが極端に小さい場合はスキップ
    if(range_width < 100 * point_value)
        return;

    // 中央ゾーンを計算
    double center = (range_high + range_low) / 2;
    double center_zone_half = (range_width * Range_Center_Percentage) / 2;

    currentRange.rangeHigh = range_high;
    currentRange.rangeLow = range_low;
    currentRange.centerUpper = center + center_zone_half;
    currentRange.centerLower = center - center_zone_half;

    // 中央ゾーンを描画
    string obj_name = indicator_prefix + "RangeCenter";
    currentRange.objectName = obj_name;

    datetime time_start = iTime(_Symbol, PERIOD_CURRENT, 100);
    datetime time_end = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT) * 200;

    ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, time_start, currentRange.centerUpper,
                 time_end, currentRange.centerLower);

    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, Range_Center_Color);
    ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);

    int alpha = Range_Zone_Transparency;
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, ColorWithAlpha(Range_Center_Color, alpha));
}

//+------------------------------------------------------------------+
//| 機能C: ネックラインを計算・描画                                     |
//+------------------------------------------------------------------+
void CalculateAndDrawNeckline()
{
    // 上位足のデータを取得
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    int lookback = 30;
    int copied = CopyRates(_Symbol, Neckline_Timeframe, 0, lookback, rates);
    if(copied <= 0)
        return;

    // トレンドを判定（簡易的に直近の高値・安値の推移で判断）
    bool is_bullish = rates[0].close > rates[lookback/2].close;

    // 押し安値（上昇トレンド）または戻り高値（下降トレンド）を検出
    double neckline_price = 0;

    if(is_bullish)
    {
        // 上昇トレンド：最も新しい押し安値を検出
        neckline_price = rates[0].low;
        for(int i = 1; i < lookback; i++)
        {
            if(rates[i].low < neckline_price && i > 2)
            {
                // スイングローかチェック
                if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
                {
                    neckline_price = rates[i].low;
                    break;
                }
            }
        }
    }
    else
    {
        // 下降トレンド：最も新しい戻り高値を検出
        neckline_price = rates[0].high;
        for(int i = 1; i < lookback; i++)
        {
            if(rates[i].high > neckline_price && i > 2)
            {
                // スイングハイかチェック
                if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
                {
                    neckline_price = rates[i].high;
                    break;
                }
            }
        }
    }

    currentNeckline.price = neckline_price;
    currentNeckline.isBullish = is_bullish;

    // ネックラインを描画
    string obj_name = indicator_prefix + "Neckline";
    currentNeckline.objectName = obj_name;

    datetime time_start = iTime(_Symbol, PERIOD_CURRENT, 100);
    datetime time_end = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT) * 200;

    ObjectCreate(0, obj_name, OBJ_TREND, 0, time_start, neckline_price, time_end, neckline_price);

    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, Neckline_Color);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, Neckline_Style);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, Neckline_Width);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);
}

//+------------------------------------------------------------------+
//| ネックラインの色を更新（価格接近時）                                 |
//+------------------------------------------------------------------+
void UpdateNecklineColor()
{
    if(currentNeckline.price == 0)
        return;

    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double distance = MathAbs(current_price - currentNeckline.price);
    double alert_distance = Neckline_Alert_Pips * pip_value;

    color line_color = (distance <= alert_distance) ? Neckline_Alert_Color : Neckline_Color;

    if(ObjectFind(0, currentNeckline.objectName) >= 0)
    {
        ObjectSetInteger(0, currentNeckline.objectName, OBJPROP_COLOR, line_color);
    }
}

//+------------------------------------------------------------------+
//| すべてのインジケーターオブジェクトを削除                              |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        string obj_name = ObjectName(0, i, 0, -1);
        if(StringFind(obj_name, indicator_prefix) >= 0)
        {
            ObjectDelete(0, obj_name);
        }
    }
}

//+------------------------------------------------------------------+
//| 透明度付きの色を作成                                               |
//+------------------------------------------------------------------+
color ColorWithAlpha(color base_color, int alpha)
{
    // MQL5では色の透明度は直接サポートされていないため、
    // RGBコンポーネントを使用して半透明効果を近似
    // 注: この関数は基本色を返すのみ（MT5の制限により完全な透明度制御は不可）
    return base_color;
}

//+------------------------------------------------------------------+
