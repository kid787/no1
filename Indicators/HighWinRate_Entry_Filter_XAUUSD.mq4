//+------------------------------------------------------------------+
//|                          HighWinRate_Entry_Filter_XAUUSD.mq4    |
//|                          High Win Rate Entry Filter - XAUUSD    |
//|                   Multi-Timeframe Analysis & Edge Filter - GOLD |
//+------------------------------------------------------------------+
#property copyright "High Win Rate Trading System - XAUUSD Edition"
#property link      ""
#property version   "1.10"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property description "XAUUSDゴールド専用高勝率エントリーフィルター"
#property description "金特有のボラティリティとトレンド特性に最適化"

//--- Input Parameters - XAUUSD Optimized Defaults
input ENUM_TIMEFRAMES King_TimeFrame = PERIOD_H4;           // 最上位足（4時間足推奨） - 金のトレンド把握
input ENUM_TIMEFRAMES Base_TimeFrame = PERIOD_H1;           // 基準足（1時間足） - エントリータイミング
input int             SMA_Period = 50;                      // 移動平均線の期間（50が金で重視される）
input int             London_Start_Hour = 8;                // ロンドン時間開始（GMT）
input int             London_End_Hour = 16;                 // ロンドン時間終了（GMT）
input bool            Enable_NY_Session = true;             // ニューヨーク時間も有効化
input int             NY_Start_Hour = 13;                   // ニューヨーク時間開始（GMT）
input int             NY_End_Hour = 21;                     // ニューヨーク時間終了（GMT）
input int             SR_Lookback_Bars = 100;               // S/Rライン検出用の遡り期間（金は長期）
input double          SR_Threshold = 0.0008;                // S/Rレベル判定の閾値（金の価格変動に合わせて大きめ）
input int             Cluster_Min_Bars = 15;                // クラスター判定の最小ローソク足数（金は揉み合いが長い）
input double          Cluster_Range_Dollars = 15.0;         // クラスター判定の価格幅（ドル単位）
input double          Entry_Zone_Dollars = 5.0;             // エントリージャッジゾーンの幅（ドル単位）
input bool            Enable_Sound_Alert = true;            // サウンドアラートを有効化
input bool            Enable_Popup_Alert = true;            // ポップアップアラートを有効化
input color           London_BG_Color = C'25,25,50';        // ロンドン時間帯の背景色
input color           NY_BG_Color = C'50,25,0';             // ニューヨーク時間帯の背景色
input color           Overlap_BG_Color = C'0,50,0';         // 重複時間帯の背景色（最重要）
input color           Order_BG_Color = C'0,40,40';          // 秩序あり時の背景色
input color           SR_Line_Color = clrGold;              // S/Rラインの色（金だから金色）
input color           Cluster_Box_Color = clrOrange;        // クラスターボックスの色
input int             Alert_Cooldown_Seconds = 600;         // アラートのクールダウン時間（10分）
input bool            Show_Daily_Pivot = true;              // 日足ピボットポイント表示
input bool            Show_Price_Labels = true;             // 価格ラベル表示

//--- Global Variables
datetime lastAlertTime = 0;
string indicatorPrefix = "HWEF_GOLD_";
double dailyHigh = 0;
double dailyLow = 0;
double dailyOpen = 0;

//--- Trend Direction Enum
enum TrendDirection {
    TREND_UP = 1,
    TREND_DOWN = -1,
    TREND_NEUTRAL = 0
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Indicator short name
    IndicatorShortName("HighWinRate Entry Filter - XAUUSD");

    //--- Initialize
    CleanupObjects();

    //--- Symbol check
    if(StringFind(Symbol(), "XAU") < 0 && StringFind(Symbol(), "GOLD") < 0)
    {
        Alert("警告: このインジケーターはXAUUSD（ゴールド）専用です。現在のシンボル: " + Symbol());
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    CleanupObjects();
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
    //--- 日次データの更新
    UpdateDailyData();

    // 1. MTF環境認識フィルター
    TrendDirection kingTrend = GetTrendDirection(King_TimeFrame, SMA_Period);
    TrendDirection baseTrend = GetTrendDirection(Base_TimeFrame, SMA_Period);

    bool isOrderPresent = (kingTrend == baseTrend && kingTrend != TREND_NEUTRAL);

    // 2. 時間帯フィルター（金はロンドン・ニューヨーク両方重要）
    bool isLondonSession = IsLondonSession();
    bool isNYSession = IsNYSession();
    bool isOverlapSession = (isLondonSession && isNYSession); // 最重要時間帯

    // 3. 背景色の設定
    DrawBackground(isOrderPresent, isLondonSession, isNYSession, isOverlapSession);

    // 4. S/Rラインの描画（金の主要レベル）
    DrawSupportResistanceLines(King_TimeFrame, SR_Lookback_Bars);

    // 5. デイリーピボットポイントの描画
    if(Show_Daily_Pivot)
    {
        DrawDailyPivots();
    }

    // 6. クラスターボックスの検出と描画
    DetectAndDrawClusters(Base_TimeFrame);

    // 7. エントリーシグナルの検出
    bool entrySignal = CheckEntryConditions(isOrderPresent, isLondonSession, isNYSession, kingTrend);

    // 8. アラート
    if(entrySignal && ShouldAlert())
    {
        string trendStr = (kingTrend == TREND_UP) ? "上昇トレンド（ロング）" : "下降トレンド（ショート）";
        string message = "【XAUUSD】高勝率エントリー機会検出！\n方向: " + trendStr + "\n現在価格: " + DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), 2);

        if(Enable_Popup_Alert)
            Alert(message);

        if(Enable_Sound_Alert)
            PlaySound("alert2.wav");

        lastAlertTime = TimeCurrent();
    }

    // 9. チャート上に情報表示
    DisplayInfo(isOrderPresent, isLondonSession, isNYSession, isOverlapSession, kingTrend, baseTrend);

    return(rates_total);
}

//+------------------------------------------------------------------+
//| デイリーデータの更新                                              |
//+------------------------------------------------------------------+
void UpdateDailyData()
{
    dailyHigh = iHigh(Symbol(), PERIOD_D1, 0);
    dailyLow = iLow(Symbol(), PERIOD_D1, 0);
    dailyOpen = iOpen(Symbol(), PERIOD_D1, 0);
}

//+------------------------------------------------------------------+
//| デイリーピボットポイントの描画                                    |
//+------------------------------------------------------------------+
void DrawDailyPivots()
{
    double prevHigh = iHigh(Symbol(), PERIOD_D1, 1);
    double prevLow = iLow(Symbol(), PERIOD_D1, 1);
    double prevClose = iClose(Symbol(), PERIOD_D1, 1);

    // ピボットポイント計算
    double pivot = (prevHigh + prevLow + prevClose) / 3;
    double r1 = 2 * pivot - prevLow;
    double r2 = pivot + (prevHigh - prevLow);
    double s1 = 2 * pivot - prevHigh;
    double s2 = pivot - (prevHigh - prevLow);

    // ピボットラインの描画
    DrawHLine(indicatorPrefix + "Pivot", pivot, clrYellow, 2, STYLE_SOLID, "Pivot");
    DrawHLine(indicatorPrefix + "R1", r1, clrRed, 1, STYLE_DASH, "R1");
    DrawHLine(indicatorPrefix + "R2", r2, clrRed, 1, STYLE_DOT, "R2");
    DrawHLine(indicatorPrefix + "S1", s1, clrLime, 1, STYLE_DASH, "S1");
    DrawHLine(indicatorPrefix + "S2", s2, clrLime, 1, STYLE_DOT, "S2");
}

//+------------------------------------------------------------------+
//| 水平線の描画ヘルパー関数                                          |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color lineColor, int width, int style, string label)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    }

    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);

    if(Show_Price_Labels)
    {
        ObjectSetString(0, name, OBJPROP_TEXT, label + " " + DoubleToString(price, 2));
    }
}

//+------------------------------------------------------------------+
//| トレンド方向の判定                                                |
//+------------------------------------------------------------------+
TrendDirection GetTrendDirection(ENUM_TIMEFRAMES timeframe, int period)
{
    // 指定された時間足のSMAを計算
    double sma_current = iMA(Symbol(), timeframe, period, 0, MODE_SMA, PRICE_CLOSE, 0);
    double sma_previous = iMA(Symbol(), timeframe, period, 0, MODE_SMA, PRICE_CLOSE, 1);
    double sma_2bars_ago = iMA(Symbol(), timeframe, period, 0, MODE_SMA, PRICE_CLOSE, 2);
    double close_current = iClose(Symbol(), timeframe, 0);

    // SMAの傾き（連続的な上昇/下降）と価格位置で判定
    bool smaRising = (sma_current > sma_previous && sma_previous > sma_2bars_ago);
    bool smaFalling = (sma_current < sma_previous && sma_previous < sma_2bars_ago);
    bool priceAboveSMA = (close_current > sma_current);
    bool priceBelowSMA = (close_current < sma_current);

    if(smaRising && priceAboveSMA)
        return TREND_UP;
    else if(smaFalling && priceBelowSMA)
        return TREND_DOWN;
    else
        return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| ロンドンセッション判定                                            |
//+------------------------------------------------------------------+
bool IsLondonSession()
{
    int currentHour = TimeHour(TimeCurrent());

    if(London_Start_Hour <= London_End_Hour)
    {
        return (currentHour >= London_Start_Hour && currentHour < London_End_Hour);
    }
    else
    {
        // 日付をまたぐ場合
        return (currentHour >= London_Start_Hour || currentHour < London_End_Hour);
    }
}

//+------------------------------------------------------------------+
//| ニューヨークセッション判定                                        |
//+------------------------------------------------------------------+
bool IsNYSession()
{
    if(!Enable_NY_Session) return false;

    int currentHour = TimeHour(TimeCurrent());

    if(NY_Start_Hour <= NY_End_Hour)
    {
        return (currentHour >= NY_Start_Hour && currentHour < NY_End_Hour);
    }
    else
    {
        return (currentHour >= NY_Start_Hour || currentHour < NY_End_Hour);
    }
}

//+------------------------------------------------------------------+
//| 背景色の描画                                                      |
//+------------------------------------------------------------------+
void DrawBackground(bool isOrder, bool isLondon, bool isNY, bool isOverlap)
{
    string bgName = indicatorPrefix + "Background";

    // 背景色の決定（優先順位: 重複 > 秩序 > セッション）
    color bgColor = clrNONE;

    if(isOverlap && isOrder)
    {
        // 重複時間 + 秩序あり = 最高の条件
        bgColor = Overlap_BG_Color;
    }
    else if(isOverlap)
    {
        // 重複時間のみ
        bgColor = Overlap_BG_Color;
    }
    else if(isOrder && (isLondon || isNY))
    {
        // 秩序あり + セッション中
        bgColor = Order_BG_Color;
    }
    else if(isLondon)
    {
        bgColor = London_BG_Color;
    }
    else if(isNY)
    {
        bgColor = NY_BG_Color;
    }

    // 背景矩形の描画
    if(bgColor != clrNONE)
    {
        datetime startTime = iTime(Symbol(), Period(), 0);
        datetime endTime = startTime + Period() * 60;
        double highPrice = iHigh(Symbol(), Period(), 0) + 50;
        double lowPrice = iLow(Symbol(), Period(), 0) - 50;

        if(ObjectFind(0, bgName) < 0)
        {
            ObjectCreate(0, bgName, OBJ_RECTANGLE, 0, startTime, highPrice, endTime, lowPrice);
            ObjectSetInteger(0, bgName, OBJPROP_FILL, true);
            ObjectSetInteger(0, bgName, OBJPROP_BACK, true);
            ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
        }

        ObjectSetInteger(0, bgName, OBJPROP_TIME, 0, startTime);
        ObjectSetDouble(0, bgName, OBJPROP_PRICE, 0, highPrice);
        ObjectSetInteger(0, bgName, OBJPROP_TIME, 1, endTime);
        ObjectSetDouble(0, bgName, OBJPROP_PRICE, 1, lowPrice);
        ObjectSetInteger(0, bgName, OBJPROP_COLOR, bgColor);
    }
}

//+------------------------------------------------------------------+
//| サポート/レジスタンスラインの描画                                 |
//+------------------------------------------------------------------+
void DrawSupportResistanceLines(ENUM_TIMEFRAMES timeframe, int lookback)
{
    double highLevels[];
    double lowLevels[];

    ArrayResize(highLevels, 0);
    ArrayResize(lowLevels, 0);

    // 主要な高値・安値を検出
    for(int i = 2; i < lookback; i++)
    {
        double high_current = iHigh(Symbol(), timeframe, i);
        double high_prev = iHigh(Symbol(), timeframe, i+1);
        double high_next = iHigh(Symbol(), timeframe, i-1);
        double high_prev2 = iHigh(Symbol(), timeframe, i+2);
        double high_next2 = iHigh(Symbol(), timeframe, i-2);

        double low_current = iLow(Symbol(), timeframe, i);
        double low_prev = iLow(Symbol(), timeframe, i+1);
        double low_next = iLow(Symbol(), timeframe, i-1);
        double low_prev2 = iLow(Symbol(), timeframe, i+2);
        double low_next2 = iLow(Symbol(), timeframe, i-2);

        // スイングハイの検出（より厳密な条件）
        if(high_current > high_prev && high_current > high_next &&
           high_current > high_prev2 && high_current > high_next2)
        {
            int size = ArraySize(highLevels);
            ArrayResize(highLevels, size + 1);
            highLevels[size] = high_current;
        }

        // スイングローの検出（より厳密な条件）
        if(low_current < low_prev && low_current < low_next &&
           low_current < low_prev2 && low_current < low_next2)
        {
            int size = ArraySize(lowLevels);
            ArrayResize(lowLevels, size + 1);
            lowLevels[size] = low_current;
        }
    }

    // 重複を除去してラインを描画
    DrawUniqueLines(highLevels, "Resistance", SR_Line_Color);
    DrawUniqueLines(lowLevels, "Support", SR_Line_Color);
}

//+------------------------------------------------------------------+
//| ユニークなラインの描画                                            |
//+------------------------------------------------------------------+
void DrawUniqueLines(double &levels[], string prefix, color lineColor)
{
    int levelCount = ArraySize(levels);
    if(levelCount == 0) return;

    // ソート
    ArraySort(levels);

    // 類似レベルを統合
    double uniqueLevels[];
    ArrayResize(uniqueLevels, 0);

    for(int i = 0; i < levelCount; i++)
    {
        bool isUnique = true;

        for(int j = 0; j < ArraySize(uniqueLevels); j++)
        {
            if(MathAbs(levels[i] - uniqueLevels[j]) / levels[i] < SR_Threshold)
            {
                isUnique = false;
                break;
            }
        }

        if(isUnique)
        {
            int size = ArraySize(uniqueLevels);
            ArrayResize(uniqueLevels, size + 1);
            uniqueLevels[size] = levels[i];
        }
    }

    // ラインを描画（最大7本まで - 金は重要レベルが多い）
    int maxLines = MathMin(ArraySize(uniqueLevels), 7);

    for(int i = 0; i < maxLines; i++)
    {
        string lineName = indicatorPrefix + prefix + "_" + IntegerToString(i);

        if(ObjectFind(0, lineName) < 0)
        {
            ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, uniqueLevels[i]);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
        }
        else
        {
            ObjectSetDouble(0, lineName, OBJPROP_PRICE, 0, uniqueLevels[i]);
        }

        // 価格ラベル
        if(Show_Price_Labels)
        {
            ObjectSetString(0, lineName, OBJPROP_TEXT, prefix + " $" + DoubleToString(uniqueLevels[i], 2));
        }
    }
}

//+------------------------------------------------------------------+
//| クラスターの検出と描画                                            |
//+------------------------------------------------------------------+
void DetectAndDrawClusters(ENUM_TIMEFRAMES timeframe)
{
    int barsToCheck = 150; // 金は長期的なクラスターを見る
    double clusterRangePrice = Cluster_Range_Dollars;

    for(int i = Cluster_Min_Bars; i < barsToCheck; i++)
    {
        double maxPrice = iHigh(Symbol(), timeframe, i);
        double minPrice = iLow(Symbol(), timeframe, i);

        // 範囲内の価格変動を確認
        int barsInCluster = 0;
        datetime startTime = iTime(Symbol(), timeframe, i);
        datetime endTime = startTime;

        for(int j = i; j >= 0; j--)
        {
            double high = iHigh(Symbol(), timeframe, j);
            double low = iLow(Symbol(), timeframe, j);

            if(high <= maxPrice + clusterRangePrice && low >= minPrice - clusterRangePrice)
            {
                barsInCluster++;
                endTime = iTime(Symbol(), timeframe, j);

                if(high > maxPrice) maxPrice = high;
                if(low < minPrice) minPrice = low;
            }
            else
            {
                break;
            }
        }

        // クラスターボックスの描画
        if(barsInCluster >= Cluster_Min_Bars)
        {
            string boxName = indicatorPrefix + "Cluster_" + TimeToString(startTime);

            if(ObjectFind(0, boxName) < 0)
            {
                ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, startTime, maxPrice, endTime, minPrice);
                ObjectSetInteger(0, boxName, OBJPROP_COLOR, Cluster_Box_Color);
                ObjectSetInteger(0, boxName, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, boxName, OBJPROP_FILL, false);
                ObjectSetInteger(0, boxName, OBJPROP_BACK, true);

                // ラベル追加
                string labelName = boxName + "_Label";
                double midPrice = (maxPrice + minPrice) / 2;
                ObjectCreate(0, labelName, OBJ_TEXT, 0, startTime, midPrice);
                ObjectSetString(0, labelName, OBJPROP_TEXT, "クラスター $" + DoubleToString(minPrice, 2) + "-" + DoubleToString(maxPrice, 2));
                ObjectSetInteger(0, labelName, OBJPROP_COLOR, Cluster_Box_Color);
                ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
            }

            i -= barsInCluster; // 検出済みのクラスターをスキップ
        }
    }
}

//+------------------------------------------------------------------+
//| エントリー条件のチェック                                          |
//+------------------------------------------------------------------+
bool CheckEntryConditions(bool isOrder, bool isLondon, bool isNY, TrendDirection trend)
{
    // 基本条件: 秩序あり + セッション中 + トレンド方向が明確
    if(!isOrder || trend == TREND_NEUTRAL)
        return false;

    if(!isLondon && !isNY)
        return false;

    // 価格がSMAに近い位置にあるか確認（守の状況）
    double sma_base = iMA(Symbol(), Base_TimeFrame, SMA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
    double close_current = iClose(Symbol(), Period(), 0);
    double distance = MathAbs(close_current - sma_base);

    // SMAから Entry_Zone_Dollars ドル以内に価格がある場合（ジャッジゾーン）
    if(distance < Entry_Zone_Dollars)
    {
        // 短期足での反転シグナルを確認
        double close_prev = iClose(Symbol(), Period(), 1);
        double open_prev = iOpen(Symbol(), Period(), 1);

        if(trend == TREND_UP)
        {
            // 上昇トレンドでの押し目買い
            // 価格がSMAの下から上に戻ってきた
            if(close_current > sma_base && close_prev < sma_base)
            {
                return true;
            }
            // または強い陽線の出現
            if(close_prev > open_prev && (close_prev - open_prev) > 2.0) // 2ドル以上の陽線
            {
                return true;
            }
        }
        else if(trend == TREND_DOWN)
        {
            // 下降トレンドでの戻り売り
            // 価格がSMAの上から下に戻ってきた
            if(close_current < sma_base && close_prev > sma_base)
            {
                return true;
            }
            // または強い陰線の出現
            if(close_prev < open_prev && (open_prev - close_prev) > 2.0) // 2ドル以上の陰線
            {
                return true;
            }
        }
    }

    // ピボットレベル付近でのリバウンド
    if(Show_Daily_Pivot)
    {
        double prevHigh = iHigh(Symbol(), PERIOD_D1, 1);
        double prevLow = iLow(Symbol(), PERIOD_D1, 1);
        double prevClose = iClose(Symbol(), PERIOD_D1, 1);
        double pivot = (prevHigh + prevLow + prevClose) / 3;

        // ピボットから3ドル以内
        if(MathAbs(close_current - pivot) < 3.0)
        {
            if(trend == TREND_UP && close_current > pivot)
                return true;
            if(trend == TREND_DOWN && close_current < pivot)
                return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| アラート可否の判定                                                |
//+------------------------------------------------------------------+
bool ShouldAlert()
{
    return (TimeCurrent() - lastAlertTime > Alert_Cooldown_Seconds);
}

//+------------------------------------------------------------------+
//| 情報表示                                                          |
//+------------------------------------------------------------------+
void DisplayInfo(bool isOrder, bool isLondon, bool isNY, bool isOverlap, TrendDirection kingTrend, TrendDirection baseTrend)
{
    string labelName = indicatorPrefix + "Info";

    if(ObjectFind(0, labelName) < 0)
    {
        ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrGold);
        ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
    }

    string trendKingStr = TrendToString(kingTrend);
    string trendBaseStr = TrendToString(baseTrend);
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double dailyRange = dailyHigh - dailyLow;

    string info = "【XAUUSD専用 高勝率エントリーフィルター】\n";
    info += "━━━━━━━━━━━━━━━━━━━━━━\n";
    info += "現在価格: $" + DoubleToString(currentPrice, 2) + "\n";
    info += "日足レンジ: $" + DoubleToString(dailyRange, 2) + " (" + DoubleToString(dailyLow, 2) + " - " + DoubleToString(dailyHigh, 2) + ")\n";
    info += "━━━━━━━━━━━━━━━━━━━━━━\n";
    info += "上位足トレンド (" + EnumToString(King_TimeFrame) + "): " + trendKingStr + "\n";
    info += "基準足トレンド (" + EnumToString(Base_TimeFrame) + "): " + trendBaseStr + "\n";
    info += "秩序: " + (isOrder ? "✓ あり（Order）" : "✗ なし") + "\n";
    info += "━━━━━━━━━━━━━━━━━━━━━━\n";

    string session = "";
    if(isOverlap)
        session = "✪ ロンドン・NY重複（最重要）";
    else if(isLondon)
        session = "● ロンドンセッション";
    else if(isNY)
        session = "● ニューヨークセッション";
    else
        session = "○ 低ボラティリティ時間";

    info += "時間帯: " + session + "\n";
    info += "━━━━━━━━━━━━━━━━━━━━━━\n";

    if(isOverlap && isOrder)
    {
        info += "状態: ★★★★★ 最高のエントリー環境 ★★★★★";
    }
    else if(isOrder && (isLondon || isNY))
    {
        info += "状態: ★★★★ 優良なエントリー環境";
    }
    else if(isOrder)
    {
        info += "状態: ★★★ 良好（ボラティリティ待ち）";
    }
    else if(isLondon || isNY)
    {
        info += "状態: ★★ 待機（トレンド確認待ち）";
    }
    else
    {
        info += "状態: ★ 待機推奨";
    }

    ObjectSetString(0, labelName, OBJPROP_TEXT, info);
}

//+------------------------------------------------------------------+
//| トレンドを文字列に変換                                            |
//+------------------------------------------------------------------+
string TrendToString(TrendDirection trend)
{
    switch(trend)
    {
        case TREND_UP: return "強い上昇 ↑↑";
        case TREND_DOWN: return "強い下降 ↓↓";
        case TREND_NEUTRAL: return "中立・レンジ ⇄";
        default: return "不明";
    }
}

//+------------------------------------------------------------------+
//| オブジェクトのクリーンアップ                                      |
//+------------------------------------------------------------------+
void CleanupObjects()
{
    int total = ObjectsTotal(0);

    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);

        if(StringFind(name, indicatorPrefix) == 0)
        {
            ObjectDelete(0, name);
        }
    }
}
//+------------------------------------------------------------------+
