//+------------------------------------------------------------------+
//|                                    HighWinRate_Entry_Filter.mq4 |
//|                                      High Win Rate Entry Filter |
//|                           Multi-Timeframe Analysis & Edge Filter |
//+------------------------------------------------------------------+
#property copyright "High Win Rate Trading System"
#property link      ""
#property version   "1.02"
#property strict
#property indicator_chart_window
#property indicator_buffers 0

//--- Input Parameters
input ENUM_TIMEFRAMES King_TimeFrame = PERIOD_D1;           // 最上位足（日足/4時間足）- 相場の支配者
input ENUM_TIMEFRAMES Base_TimeFrame = PERIOD_H1;           // 基準足（1時間足）- 戦略を立てる波
input int             SMA_Period = 21;                      // 移動平均線の期間 - 相場の流れ
input int             London_Start_Hour = 8;                // ロンドン時間開始（GMT）
input int             London_End_Hour = 16;                 // ロンドン時間終了（GMT）
input int             SR_Lookback_Bars = 50;                // S/Rライン検出用の遡り期間
input double          SR_Threshold = 0.0002;                // S/Rレベル判定の閾値（価格の%）
input int             Cluster_Min_Bars = 10;                // クラスター判定の最小ローソク足数
input double          Cluster_Range_Pips = 30;              // クラスター判定の価格幅（pips）
input bool            Enable_Sound_Alert = true;            // サウンドアラートを有効化
input bool            Enable_Popup_Alert = true;            // ポップアップアラートを有効化
input color           London_BG_Color = C'25,25,50';        // ロンドン時間帯の背景色
input color           Order_BG_Color = C'0,50,0';           // 秩序あり時の背景色
input color           SR_Line_Color = clrYellow;            // S/Rラインの色
input color           Cluster_Box_Color = clrDodgerBlue;    // クラスターボックスの色
input int             Alert_Cooldown_Seconds = 300;         // アラートのクールダウン時間（秒）
input bool            Enable_Double_Pattern = true;         // ダブルトップ/ボトム検出を有効化
input int             Double_Pattern_Lookback = 50;         // ダブルパターン検出範囲（バー数）
input double          Double_Pattern_Tolerance_Pips = 20.0; // 価格許容範囲（pips）
input double          Double_Pattern_Min_Retrace_Percent = 30.0; // 中間戻しの最小値（%）

//--- Global Variables
datetime lastAlertTime = 0;
string indicatorPrefix = "HWEF_";
int kingSMA_Handle;
int baseSMA_Handle;

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
    IndicatorShortName("HighWinRate Entry Filter");

    //--- Initialize
    CleanupObjects();

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
    //--- Main calculation logic

    // 1. MTF環境認識フィルター
    TrendDirection kingTrend = GetTrendDirection(King_TimeFrame, SMA_Period);
    TrendDirection baseTrend = GetTrendDirection(Base_TimeFrame, SMA_Period);

    bool isOrderPresent = (kingTrend == baseTrend && kingTrend != TREND_NEUTRAL);

    // 2. 時間帯フィルター
    bool isLondonSession = IsLondonSession();

    // 3. 背景色の設定
    DrawBackground(isOrderPresent, isLondonSession);

    // 4. S/Rラインの描画
    DrawSupportResistanceLines(King_TimeFrame, SR_Lookback_Bars);

    // 5. クラスターボックスの検出と描画
    DetectAndDrawClusters(Base_TimeFrame);

    // 5.5. ダブルトップ/ボトムの検出と描画
    if(Enable_Double_Pattern)
    {
        DetectDoublePatterns(Base_TimeFrame);
    }

    // 6. エントリーシグナルの検出
    bool entrySignal = CheckEntryConditions(isOrderPresent, isLondonSession, kingTrend);

    // 7. アラート
    if(entrySignal && ShouldAlert())
    {
        string trendStr = (kingTrend == TREND_UP) ? "上昇トレンド" : "下降トレンド";
        string message = "高勝率エントリー機会検出！方向: " + trendStr;

        if(Enable_Popup_Alert)
            Alert(message);

        if(Enable_Sound_Alert)
            PlaySound("alert.wav");

        lastAlertTime = TimeCurrent();
    }

    // 8. チャート上に情報表示
    DisplayInfo(isOrderPresent, isLondonSession, kingTrend, baseTrend);

    return(rates_total);
}

//+------------------------------------------------------------------+
//| トレンド方向の判定                                                |
//+------------------------------------------------------------------+
TrendDirection GetTrendDirection(ENUM_TIMEFRAMES timeframe, int period)
{
    // 指定された時間足のSMAを計算
    double sma_current = iMA(Symbol(), timeframe, period, 0, MODE_SMA, PRICE_CLOSE, 0);
    double sma_previous = iMA(Symbol(), timeframe, period, 0, MODE_SMA, PRICE_CLOSE, 1);
    double close_current = iClose(Symbol(), timeframe, 0);

    // SMAの傾きと価格位置で判定
    bool smaRising = (sma_current > sma_previous);
    bool priceAboveSMA = (close_current > sma_current);

    if(smaRising && priceAboveSMA)
        return TREND_UP;
    else if(!smaRising && !priceAboveSMA)
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
//| 背景色の描画                                                      |
//+------------------------------------------------------------------+
void DrawBackground(bool isOrder, bool isLondon)
{
    string bgName = indicatorPrefix + "Background";

    // 背景色の決定
    color bgColor = clrNONE;

    if(isOrder && isLondon)
    {
        // 秩序あり + ロンドン時間 = 最高の条件
        bgColor = Order_BG_Color;
    }
    else if(isLondon)
    {
        bgColor = London_BG_Color;
    }

    // 背景矩形の描画
    if(bgColor != clrNONE)
    {
        datetime startTime = iTime(Symbol(), Period(), 0);
        datetime endTime = startTime + Period() * 60;
        double highPrice = iHigh(Symbol(), Period(), 0) + 100 * Point;
        double lowPrice = iLow(Symbol(), Period(), 0) - 100 * Point;

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

        double low_current = iLow(Symbol(), timeframe, i);
        double low_prev = iLow(Symbol(), timeframe, i+1);
        double low_next = iLow(Symbol(), timeframe, i-1);

        // スイングハイの検出
        if(high_current > high_prev && high_current > high_next)
        {
            int size = ArraySize(highLevels);
            ArrayResize(highLevels, size + 1);
            highLevels[size] = high_current;
        }

        // スイングローの検出
        if(low_current < low_prev && low_current < low_next)
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

    // ラインを描画（最大5本まで）
    int maxLines = MathMin(ArraySize(uniqueLevels), 5);

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
    }
}

//+------------------------------------------------------------------+
//| クラスターの検出と描画                                            |
//+------------------------------------------------------------------+
void DetectAndDrawClusters(ENUM_TIMEFRAMES timeframe)
{
    int barsToCheck = 100;
    double clusterRangePrice = Cluster_Range_Pips * Point * 10; // pipsを価格に変換

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
            }

            i -= barsInCluster; // 検出済みのクラスターをスキップ
        }
    }
}

//+------------------------------------------------------------------+
//| エントリー条件のチェック                                          |
//+------------------------------------------------------------------+
bool CheckEntryConditions(bool isOrder, bool isLondon, TrendDirection trend)
{
    // 基本条件: 秩序あり + ロンドン時間 + トレンド方向が明確
    if(!isOrder || !isLondon || trend == TREND_NEUTRAL)
        return false;

    // 価格がSMAに近い位置にあるか確認（守の状況）
    double sma_base = iMA(Symbol(), Base_TimeFrame, SMA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
    double close_current = iClose(Symbol(), Period(), 0);
    double distance = MathAbs(close_current - sma_base) / close_current;

    // SMAから0.5%以内に価格がある場合（ジャッジゾーン）
    if(distance < 0.005)
    {
        // 短期足での反転シグナルを確認
        if(trend == TREND_UP)
        {
            // 上昇トレンドでの押し目買い
            if(close_current < sma_base && iClose(Symbol(), Period(), 1) < iOpen(Symbol(), Period(), 1))
            {
                return true;
            }
        }
        else if(trend == TREND_DOWN)
        {
            // 下降トレンドでの戻り売り
            if(close_current > sma_base && iClose(Symbol(), Period(), 1) > iOpen(Symbol(), Period(), 1))
            {
                return true;
            }
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
void DisplayInfo(bool isOrder, bool isLondon, TrendDirection kingTrend, TrendDirection baseTrend)
{
    string labelName = indicatorPrefix + "Info";

    if(ObjectFind(labelName) < 0)
    {
        ObjectCreate(labelName, OBJ_LABEL, 0, 0, 0);
        ObjectSet(labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSet(labelName, OBJPROP_XDISTANCE, 10);
        ObjectSet(labelName, OBJPROP_YDISTANCE, 30);
    }

    string trendKingStr = TrendToString(kingTrend);
    string trendBaseStr = TrendToString(baseTrend);

    string info = "【高勝率エントリーフィルター】\n";
    info += "上位足トレンド (" + EnumToString(King_TimeFrame) + "): " + trendKingStr + "\n";
    info += "基準足トレンド (" + EnumToString(Base_TimeFrame) + "): " + trendBaseStr + "\n";
    info += "秩序: " + (isOrder ? "あり（Order）" : "なし") + "\n";
    info += "ロンドン時間: " + (isLondon ? "YES" : "NO") + "\n";

    if(isOrder && isLondon)
    {
        info += "状態: ★★★ 最高のエントリー環境 ★★★";
    }
    else if(isOrder)
    {
        info += "状態: ★★ 良好（ボラティリティ待ち）";
    }
    else
    {
        info += "状態: ★ 待機";
    }

    ObjectSetText(labelName, info, 10, "MS Gothic", clrWhite);
}

//+------------------------------------------------------------------+
//| トレンドを文字列に変換                                            |
//+------------------------------------------------------------------+
string TrendToString(TrendDirection trend)
{
    switch(trend)
    {
        case TREND_UP: return "上昇 ↑";
        case TREND_DOWN: return "下降 ↓";
        case TREND_NEUTRAL: return "中立 →";
        default: return "不明";
    }
}

//+------------------------------------------------------------------+
//| ダブルトップ/ボトムのパターン検出                                 |
//+------------------------------------------------------------------+
void DetectDoublePatterns(ENUM_TIMEFRAMES timeframe)
{
    if(Double_Pattern_Lookback < 10) return;

    // 既存のダブルパターンオブジェクトをクリア
    int total = ObjectsTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(i);
        if(StringFind(name, indicatorPrefix + "DT_") == 0 || StringFind(name, indicatorPrefix + "DB_") == 0)
        {
            ObjectDelete(name);
        }
    }

    // pipsを価格に変換
    double tolerancePrice = Double_Pattern_Tolerance_Pips * Point * 10;

    // スイング高値・安値を検出
    double swingHighs[];
    int swingHighBars[];
    double swingLows[];
    int swingLowBars[];

    ArrayResize(swingHighs, 0);
    ArrayResize(swingHighBars, 0);
    ArrayResize(swingLows, 0);
    ArrayResize(swingLowBars, 0);

    // スイングポイントを検出（3バーの比較）
    for(int i = 3; i < Double_Pattern_Lookback; i++)
    {
        double high0 = iHigh(Symbol(), timeframe, i);
        double high1 = iHigh(Symbol(), timeframe, i-1);
        double high2 = iHigh(Symbol(), timeframe, i+1);

        double low0 = iLow(Symbol(), timeframe, i);
        double low1 = iLow(Symbol(), timeframe, i-1);
        double low2 = iLow(Symbol(), timeframe, i+1);

        // スイング高値（ローカルピーク）
        if(high0 > high1 && high0 > high2)
        {
            int size = ArraySize(swingHighs);
            ArrayResize(swingHighs, size + 1);
            ArrayResize(swingHighBars, size + 1);
            swingHighs[size] = high0;
            swingHighBars[size] = i;
        }

        // スイング安値（ローカルボトム）
        if(low0 < low1 && low0 < low2)
        {
            int size = ArraySize(swingLows);
            ArrayResize(swingLows, size + 1);
            ArrayResize(swingLowBars, size + 1);
            swingLows[size] = low0;
            swingLowBars[size] = i;
        }
    }

    // ダブルトップの検出
    int highCount = ArraySize(swingHighs);
    for(int i = 0; i < highCount - 1; i++)
    {
        for(int j = i + 1; j < highCount; j++)
        {
            double high1 = swingHighs[i];
            double high2 = swingHighs[j];
            int bar1 = swingHighBars[i];
            int bar2 = swingHighBars[j];

            // 価格が近似しているか
            double priceDiff = MathAbs(high1 - high2);
            if(priceDiff <= tolerancePrice)
            {
                // 中間に十分な戻しがあるか確認
                double minBetween = high1;
                for(int k = bar1 - 1; k > bar2; k--)
                {
                    double low = iLow(Symbol(), timeframe, k);
                    if(low < minBetween)
                        minBetween = low;
                }

                double retrace = ((MathMin(high1, high2) - minBetween) / MathMin(high1, high2)) * 100.0;

                if(retrace >= Double_Pattern_Min_Retrace_Percent)
                {
                    // ダブルトップ検出！
                    DrawDoubleTop(timeframe, bar1, high1, bar2, high2, minBetween);
                    break; // 1つ見つかれば十分
                }
            }
        }
    }

    // ダブルボトムの検出
    int lowCount = ArraySize(swingLows);
    for(int i = 0; i < lowCount - 1; i++)
    {
        for(int j = i + 1; j < lowCount; j++)
        {
            double low1 = swingLows[i];
            double low2 = swingLows[j];
            int bar1 = swingLowBars[i];
            int bar2 = swingLowBars[j];

            // 価格が近似しているか
            double priceDiff = MathAbs(low1 - low2);
            if(priceDiff <= tolerancePrice)
            {
                // 中間に十分な戻しがあるか確認
                double maxBetween = low1;
                for(int k = bar1 - 1; k > bar2; k--)
                {
                    double high = iHigh(Symbol(), timeframe, k);
                    if(high > maxBetween)
                        maxBetween = high;
                }

                double retrace = ((maxBetween - MathMax(low1, low2)) / MathMax(low1, low2)) * 100.0;

                if(retrace >= Double_Pattern_Min_Retrace_Percent)
                {
                    // ダブルボトム検出！
                    DrawDoubleBottom(timeframe, bar1, low1, bar2, low2, maxBetween);
                    break; // 1つ見つかれば十分
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ダブルトップの描画                                                |
//+------------------------------------------------------------------+
void DrawDoubleTop(ENUM_TIMEFRAMES timeframe, int bar1, double price1, int bar2, double price2, double middlePrice)
{
    datetime time1 = iTime(Symbol(), timeframe, bar1);
    datetime time2 = iTime(Symbol(), timeframe, bar2);

    // 第1の高値マーカー
    string arrow1Name = indicatorPrefix + "DT_Arrow1";
    if(ObjectFind(arrow1Name) < 0)
    {
        ObjectCreate(arrow1Name, OBJ_ARROW, 0, time1, price1);
        ObjectSet(arrow1Name, OBJPROP_ARROWCODE, 234); // 下向き三角
        ObjectSet(arrow1Name, OBJPROP_COLOR, clrRed);
        ObjectSet(arrow1Name, OBJPROP_WIDTH, 3);
    }

    // 第2の高値マーカー
    string arrow2Name = indicatorPrefix + "DT_Arrow2";
    if(ObjectFind(arrow2Name) < 0)
    {
        ObjectCreate(arrow2Name, OBJ_ARROW, 0, time2, price2);
        ObjectSet(arrow2Name, OBJPROP_ARROWCODE, 234);
        ObjectSet(arrow2Name, OBJPROP_COLOR, clrRed);
        ObjectSet(arrow2Name, OBJPROP_WIDTH, 3);
    }

    // ネックライン（高値を結ぶ線）
    string lineName = indicatorPrefix + "DT_Line";
    if(ObjectFind(lineName) < 0)
    {
        ObjectCreate(lineName, OBJ_TREND, 0, time1, price1, time2, price2);
        ObjectSet(lineName, OBJPROP_COLOR, clrRed);
        ObjectSet(lineName, OBJPROP_WIDTH, 2);
        ObjectSet(lineName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSet(lineName, OBJPROP_RAY, false);
    }

    // テキストラベル
    string labelName = indicatorPrefix + "DT_Label";
    datetime midTime = (time1 + time2) / 2;
    double labelPrice = MathMax(price1, price2) + (10.0 * Point);

    if(ObjectFind(labelName) < 0)
    {
        ObjectCreate(labelName, OBJ_TEXT, 0, midTime, labelPrice);
        ObjectSetText(labelName, "Double Top ▼", 10, "MS Gothic", clrRed);
    }
}

//+------------------------------------------------------------------+
//| ダブルボトムの描画                                                |
//+------------------------------------------------------------------+
void DrawDoubleBottom(ENUM_TIMEFRAMES timeframe, int bar1, double price1, int bar2, double price2, double middlePrice)
{
    datetime time1 = iTime(Symbol(), timeframe, bar1);
    datetime time2 = iTime(Symbol(), timeframe, bar2);

    // 第1の安値マーカー
    string arrow1Name = indicatorPrefix + "DB_Arrow1";
    if(ObjectFind(arrow1Name) < 0)
    {
        ObjectCreate(arrow1Name, OBJ_ARROW, 0, time1, price1);
        ObjectSet(arrow1Name, OBJPROP_ARROWCODE, 233); // 上向き三角
        ObjectSet(arrow1Name, OBJPROP_COLOR, clrDodgerBlue);
        ObjectSet(arrow1Name, OBJPROP_WIDTH, 3);
    }

    // 第2の安値マーカー
    string arrow2Name = indicatorPrefix + "DB_Arrow2";
    if(ObjectFind(arrow2Name) < 0)
    {
        ObjectCreate(arrow2Name, OBJ_ARROW, 0, time2, price2);
        ObjectSet(arrow2Name, OBJPROP_ARROWCODE, 233);
        ObjectSet(arrow2Name, OBJPROP_COLOR, clrDodgerBlue);
        ObjectSet(arrow2Name, OBJPROP_WIDTH, 3);
    }

    // ネックライン（安値を結ぶ線）
    string lineName = indicatorPrefix + "DB_Line";
    if(ObjectFind(lineName) < 0)
    {
        ObjectCreate(lineName, OBJ_TREND, 0, time1, price1, time2, price2);
        ObjectSet(lineName, OBJPROP_COLOR, clrDodgerBlue);
        ObjectSet(lineName, OBJPROP_WIDTH, 2);
        ObjectSet(lineName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSet(lineName, OBJPROP_RAY, false);
    }

    // テキストラベル
    string labelName = indicatorPrefix + "DB_Label";
    datetime midTime = (time1 + time2) / 2;
    double labelPrice = MathMin(price1, price2) - (10.0 * Point);

    if(ObjectFind(labelName) < 0)
    {
        ObjectCreate(labelName, OBJ_TEXT, 0, midTime, labelPrice);
        ObjectSetText(labelName, "Double Bottom ▲", 10, "MS Gothic", clrDodgerBlue);
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
