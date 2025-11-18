//+------------------------------------------------------------------+
//|                                    HighWinRate_Entry_Filter.mq4 |
//|                                      High Win Rate Entry Filter |
//|                           Multi-Timeframe Analysis & Edge Filter |
//+------------------------------------------------------------------+
#property copyright "High Win Rate Trading System"
#property link      ""
#property version   "1.00"
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

    if(ObjectFind(0, labelName) < 0)
    {
        ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
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

    ObjectSetString(0, labelName, OBJPROP_TEXT, info);
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
