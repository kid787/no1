//+------------------------------------------------------------------+
//|                              USDJPY_EnvelopePriceAction_EA.mq5   |
//|         ドル円専用EA: エンベロープ×プライスアクション戦略        |
//|                     Fintokei チャレンジプラン対応                |
//+------------------------------------------------------------------+
#property copyright "USDJPY Envelope Price Action EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| 入力パラメータ                                                    |
//+------------------------------------------------------------------+
input group "===== 基本設定 ====="
input string   InpSymbol               = "USDJPY";     // 通貨ペア
input ENUM_TIMEFRAMES InpEntryTimeframe = PERIOD_M1;   // エントリー足
input ENUM_TIMEFRAMES InpFilterTimeframe = PERIOD_H1;  // 上位足フィルター
input int      InpMagicNumber          = 20241230;     // マジックナンバー

input group "===== エンベロープ設定 ====="
input int      InpEnvelopePeriod       = 20;           // エンベロープ期間
input double   InpEnvelopeDev1         = 0.15;         // 偏差1 (%)
input double   InpEnvelopeDev2         = 0.20;         // 偏差2 (%)
input double   InpEnvelopeDev3         = 0.25;         // 偏差3 (%)
input double   InpEnvelopeDev4         = 0.30;         // 偏差4 (%)
input double   InpEnvelopeDev5         = 0.35;         // 偏差5 (%)
input double   InpEnvelopeDev6         = 0.40;         // 偏差6 (%)

input group "===== 上位足フィルター設定 ====="
input int      InpEMAPeriod            = 200;          // 上位足EMA期間
input double   InpVolatilityThreshold  = 0.5;          // ボラティリティ閾値 (ATR%)

input group "===== プライスアクション設定 ====="
input double   InpPinBarWickRatio      = 3.0;          // ピンバーヒゲ倍率（実体の何倍か）
input double   InpEngulfingMinRatio    = 1.0;          // 包み足最小倍率

input group "===== リスク管理設定 ====="
input double   InpRiskPercent          = 3.0;          // 1トレードあたりのリスク (%)
input double   InpMaxPositionLossPercent = 3.0;        // 1ポジション最大含み損 (%) ★重要
input double   InpMaxDailyLossPercent  = 5.0;          // 1日の最大損失率 (%)
input double   InpMaxTotalLossPercent  = 10.0;         // 全体の最大損失率 (%)
input double   InpLotReduction1        = 5.0;          // ロット削減開始 損失率1 (%)
input double   InpLotReduction2        = 7.0;          // ロット削減開始 損失率2 (%)
input double   InpLotReductionFactor   = 0.5;          // ロット削減率 (50%)
input int      InpSLBuffer             = 3;            // SLバッファ (pips)

input group "===== 利確設定 ====="
input bool     InpUsePartialClose      = true;         // 分割決済を使用
input double   InpPartialCloseRatio    = 0.5;          // 分割決済割合 (50%)

input group "===== RSI設定 ====="
input int      InpRSIPeriod            = 14;           // RSI期間
input int      InpRSIOverbought        = 70;           // RSI買われすぎ
input int      InpRSIOversold          = 30;           // RSI売られすぎ

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symbolInfo;

// インジケーターハンドル
int h_ema200_h1;           // 1時間足200EMA
int h_envelopes[6];        // エンベロープ（6段階）
int h_atr_h1;              // 1時間足ATR
int h_rsi;                 // RSI

// リスク管理変数
double g_initialBalance;    // 初期残高
double g_dailyStartEquity;  // 当日開始時の有効証拠金
datetime g_lastDayCheck;    // 最後の日付チェック
double g_totalLossLine;     // 全体損失失格ライン
double g_dailyLossLine;     // 日次損失失格ライン

// トレード管理
bool g_hasPosition;
int g_lastEntryBar;
int g_touchedEnvelopeBand;  // タッチしたエンベロープバンドのレベル（1-6）
datetime g_lastBandTouchTime;
double g_entryEnvelopeLevel; // エントリー時のエンベロープレベル

// ネックラインブレイク用
double g_doubleBottomNeckline;
double g_doubleTopNeckline;
datetime g_lastSwingLow1Time;
datetime g_lastSwingLow2Time;
double g_lastSwingLow1Price;
double g_lastSwingLow2Price;
datetime g_lastSwingHigh1Time;
datetime g_lastSwingHigh2Time;
double g_lastSwingHigh1Price;
double g_lastSwingHigh2Price;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // シンボル情報初期化
    if(!symbolInfo.Name(InpSymbol))
    {
        Print("エラー: シンボル ", InpSymbol, " が見つかりません");
        return INIT_FAILED;
    }

    // トレード設定
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // インジケーターの初期化
    if(!InitializeIndicators())
    {
        Print("エラー: インジケーターの初期化に失敗しました");
        return INIT_FAILED;
    }

    // リスク管理の初期化
    InitializeRiskManagement();

    Print("EA初期化完了: ", InpSymbol);
    Print("初期残高: ", g_initialBalance);
    Print("全体損失失格ライン: ", g_totalLossLine);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // インジケーターハンドルの解放
    if(h_ema200_h1 != INVALID_HANDLE) IndicatorRelease(h_ema200_h1);
    if(h_atr_h1 != INVALID_HANDLE) IndicatorRelease(h_atr_h1);
    if(h_rsi != INVALID_HANDLE) IndicatorRelease(h_rsi);

    for(int i = 0; i < 6; i++)
    {
        if(h_envelopes[i] != INVALID_HANDLE) IndicatorRelease(h_envelopes[i]);
    }

    Print("EA終了: 理由コード = ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // シンボル情報の更新
    if(!symbolInfo.RefreshRates())
        return;

    // 日次リセットのチェック
    CheckDailyReset();

    // 【最優先】個別ポジションの含み損チェック（3%ルール）
    CheckPositionLossLimit();

    // リスク管理チェック（5%/10%ルール）
    if(!CheckRiskLimits())
    {
        // リスク制限に達した場合、すべてのポジションを決済
        CloseAllPositions("リスク制限到達");
        return;
    }

    // ポジション保有中の場合
    if(HasOpenPosition())
    {
        ManageOpenPosition();
        return;
    }

    // 新しいバーでのみエントリーチェック
    if(!IsNewBar(InpEntryTimeframe))
        return;

    // エントリー条件のチェック
    CheckEntryConditions();
}

//+------------------------------------------------------------------+
//| インジケーターの初期化                                            |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    // 1時間足200EMA
    h_ema200_h1 = iMA(InpSymbol, InpFilterTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(h_ema200_h1 == INVALID_HANDLE)
    {
        Print("エラー: 200EMAの作成に失敗");
        return false;
    }

    // 1時間足ATR
    h_atr_h1 = iATR(InpSymbol, InpFilterTimeframe, 14);
    if(h_atr_h1 == INVALID_HANDLE)
    {
        Print("エラー: ATRの作成に失敗");
        return false;
    }

    // RSI
    h_rsi = iRSI(InpSymbol, InpEntryTimeframe, InpRSIPeriod, PRICE_CLOSE);
    if(h_rsi == INVALID_HANDLE)
    {
        Print("エラー: RSIの作成に失敗");
        return false;
    }

    // エンベロープ（6段階）
    double deviations[6] = {InpEnvelopeDev1, InpEnvelopeDev2, InpEnvelopeDev3,
                           InpEnvelopeDev4, InpEnvelopeDev5, InpEnvelopeDev6};

    for(int i = 0; i < 6; i++)
    {
        h_envelopes[i] = iEnvelopes(InpSymbol, InpEntryTimeframe, InpEnvelopePeriod,
                                     0, MODE_SMA, PRICE_CLOSE, deviations[i]);
        if(h_envelopes[i] == INVALID_HANDLE)
        {
            Print("エラー: エンベロープ", i+1, "の作成に失敗");
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| リスク管理の初期化                                                |
//+------------------------------------------------------------------+
void InitializeRiskManagement()
{
    g_initialBalance = accountInfo.Balance();
    g_dailyStartEquity = accountInfo.Equity();
    g_lastDayCheck = TimeCurrent();

    // 失格ラインの計算
    g_totalLossLine = g_initialBalance * (1.0 - InpMaxTotalLossPercent / 100.0);
    g_dailyLossLine = g_dailyStartEquity * (1.0 - InpMaxDailyLossPercent / 100.0);
}

//+------------------------------------------------------------------+
//| 日次リセットのチェック                                            |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    MqlDateTime currentTime, lastTime;
    TimeToStruct(TimeCurrent(), currentTime);
    TimeToStruct(g_lastDayCheck, lastTime);

    // UTC 0時（日本時間9時）でリセット
    if(currentTime.day != lastTime.day)
    {
        g_dailyStartEquity = accountInfo.Equity();
        g_dailyLossLine = g_dailyStartEquity * (1.0 - InpMaxDailyLossPercent / 100.0);
        g_lastDayCheck = TimeCurrent();

        Print("日次リセット: 新しい有効証拠金 = ", g_dailyStartEquity);
        Print("新しい日次損失ライン = ", g_dailyLossLine);
    }
}

//+------------------------------------------------------------------+
//| リスク制限のチェック                                              |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
    double currentEquity = accountInfo.Equity();

    // 全体損失制限（10%ルール）
    if(currentEquity <= g_totalLossLine)
    {
        Print("警告: 全体損失制限（10%）に到達。有効証拠金: ", currentEquity, " 失格ライン: ", g_totalLossLine);
        return false;
    }

    // 日次損失制限（5%ルール）
    if(currentEquity <= g_dailyLossLine)
    {
        Print("警告: 日次損失制限（5%）に到達。有効証拠金: ", currentEquity, " 失格ライン: ", g_dailyLossLine);
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| 個別ポジションの含み損チェック（3%ルール）                         |
//+------------------------------------------------------------------+
void CheckPositionLossLimit()
{
    double maxLossAmount = g_initialBalance * (InpMaxPositionLossPercent / 100.0);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!positionInfo.SelectByIndex(i))
            continue;

        if(positionInfo.Symbol() != InpSymbol || positionInfo.Magic() != InpMagicNumber)
            continue;

        // 現在の含み損益を取得
        double positionProfit = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();

        // 含み損が最大許容額を超えた場合
        if(positionProfit < 0 && MathAbs(positionProfit) >= maxLossAmount)
        {
            Print("警告: ポジション含み損が", InpMaxPositionLossPercent, "%に到達！");
            Print("含み損: ", positionProfit, " 許容額: -", maxLossAmount);
            ClosePosition(positionInfo.Ticket(), "1ポジション3%含み損制限");
        }
    }
}

//+------------------------------------------------------------------+
//| 現在の損失率に基づくロット調整係数の計算                           |
//+------------------------------------------------------------------+
double GetLotAdjustmentFactor()
{
    double currentEquity = accountInfo.Equity();
    double lossPercent = (g_initialBalance - currentEquity) / g_initialBalance * 100.0;

    if(lossPercent >= InpLotReduction2)
    {
        // 7%以上の損失：25%のロット
        return InpLotReductionFactor * InpLotReductionFactor;
    }
    else if(lossPercent >= InpLotReduction1)
    {
        // 5%以上の損失：50%のロット
        return InpLotReductionFactor;
    }

    return 1.0;  // 通常のロット
}

//+------------------------------------------------------------------+
//| ロットサイズの計算                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
    if(slPips <= 0) return 0.0;

    double accountBalance = accountInfo.Balance();
    double riskPercent = InpRiskPercent;

    // 損失率に基づくロット調整
    double adjustmentFactor = GetLotAdjustmentFactor();
    riskPercent *= adjustmentFactor;

    // 最大リスク金額
    double maxLossAmount = accountBalance * (riskPercent / 100.0);

    // 1ロットあたりの損失額を計算
    double lossPerLot = CalculateLossPerLot(slPips);

    if(lossPerLot <= 0) return 0.0;

    double calculatedLots = maxLossAmount / lossPerLot;

    // ロットサイズの正規化
    return NormalizeLotSize(calculatedLots);
}

//+------------------------------------------------------------------+
//| 1ロットあたりの損失額を計算                                        |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips)
{
    double point = symbolInfo.Point();
    double tickSize = symbolInfo.TickSize();
    double tickValue = symbolInfo.TickValue();
    double pipSize = GetPipSize();

    // SL距離を価格に変換
    double slDistance = slPips * pipSize;

    // ティック数を計算
    double numTicks = slDistance / tickSize;

    // 1ロットあたりの損失額
    return numTicks * tickValue;
}

//+------------------------------------------------------------------+
//| ロットサイズの正規化                                              |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
    double minLot = symbolInfo.LotsMin();
    double maxLot = symbolInfo.LotsMax();
    double lotStep = symbolInfo.LotsStep();

    if(lots < minLot) lots = minLot;
    if(lots > maxLot) lots = maxLot;

    lots = MathFloor(lots / lotStep) * lotStep;

    if(lots < minLot) lots = minLot;

    return lots;
}

//+------------------------------------------------------------------+
//| Pip サイズの取得                                                  |
//+------------------------------------------------------------------+
double GetPipSize()
{
    int digits = (int)symbolInfo.Digits();
    double point = symbolInfo.Point();

    if(digits == 3 || digits == 5)
        return point * 10.0;
    else
        return point;
}

//+------------------------------------------------------------------+
//| 新しいバーのチェック                                              |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(InpSymbol, timeframe, 0);

    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| ポジション保有チェック                                            |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == InpSymbol && positionInfo.Magic() == InpMagicNumber)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| エントリー条件のチェック                                          |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
    // 上位足トレンド方向の取得
    int trendDirection = GetTrendDirection();
    if(trendDirection == 0) return;  // トレンドが不明確な場合はスキップ

    // ボラティリティチェック
    if(!CheckVolatility()) return;

    // エンベロープバンドタッチのチェック
    int touchedBand = 0;
    bool buySignal = false;
    bool sellSignal = false;

    if(trendDirection > 0)  // 買い目線
    {
        touchedBand = CheckEnvelopeLowerBandTouch();
        if(touchedBand > 0)
        {
            // プライスアクションのチェック
            if(CheckBuyPriceAction())
            {
                buySignal = true;
                g_touchedEnvelopeBand = touchedBand;
            }
        }
    }
    else if(trendDirection < 0)  // 売り目線
    {
        touchedBand = CheckEnvelopeUpperBandTouch();
        if(touchedBand > 0)
        {
            // プライスアクションのチェック
            if(CheckSellPriceAction())
            {
                sellSignal = true;
                g_touchedEnvelopeBand = touchedBand;
            }
        }
    }

    // エントリー実行
    if(buySignal)
    {
        ExecuteBuyEntry();
    }
    else if(sellSignal)
    {
        ExecuteSellEntry();
    }
}

//+------------------------------------------------------------------+
//| トレンド方向の取得                                                |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
    double ema200[];
    ArraySetAsSeries(ema200, true);

    if(CopyBuffer(h_ema200_h1, 0, 0, 3, ema200) < 3)
        return 0;

    double currentPrice = symbolInfo.Bid();

    // 価格とEMAの位置関係
    if(currentPrice > ema200[0])
        return 1;   // 買い目線
    else if(currentPrice < ema200[0])
        return -1;  // 売り目線

    return 0;
}

//+------------------------------------------------------------------+
//| ボラティリティチェック                                            |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
    double atr[];
    ArraySetAsSeries(atr, true);

    if(CopyBuffer(h_atr_h1, 0, 0, 20, atr) < 20)
        return false;

    double currentATR = atr[0];

    // ATRの平均を計算
    double avgATR = 0;
    for(int i = 0; i < 20; i++)
        avgATR += atr[i];
    avgATR /= 20;

    // 現在のATRが平均に対して異常に高い場合は逆張りを避ける
    double atrRatio = currentATR / avgATR;

    if(atrRatio > (1.0 + InpVolatilityThreshold))
    {
        // ボラティリティが高すぎる（強いトレンド発生中）
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| エンベロープ下限バンドタッチのチェック                             |
//+------------------------------------------------------------------+
int CheckEnvelopeLowerBandTouch()
{
    double low = iLow(InpSymbol, InpEntryTimeframe, 1);  // 確定した前のバー

    // 最も外側のバンドからチェック（レベル6から1へ）
    for(int i = 5; i >= 0; i--)
    {
        double lowerBand[];
        ArraySetAsSeries(lowerBand, true);

        if(CopyBuffer(h_envelopes[i], 1, 0, 3, lowerBand) < 3)
            continue;

        if(low <= lowerBand[1])
        {
            g_lastBandTouchTime = TimeCurrent();
            return i + 1;  // 1-6のレベルを返す
        }
    }

    return 0;
}

//+------------------------------------------------------------------+
//| エンベロープ上限バンドタッチのチェック                             |
//+------------------------------------------------------------------+
int CheckEnvelopeUpperBandTouch()
{
    double high = iHigh(InpSymbol, InpEntryTimeframe, 1);  // 確定した前のバー

    // 最も外側のバンドからチェック（レベル6から1へ）
    for(int i = 5; i >= 0; i--)
    {
        double upperBand[];
        ArraySetAsSeries(upperBand, true);

        if(CopyBuffer(h_envelopes[i], 0, 0, 3, upperBand) < 3)
            continue;

        if(high >= upperBand[1])
        {
            g_lastBandTouchTime = TimeCurrent();
            return i + 1;  // 1-6のレベルを返す
        }
    }

    return 0;
}

//+------------------------------------------------------------------+
//| 買いプライスアクションのチェック                                   |
//+------------------------------------------------------------------+
bool CheckBuyPriceAction()
{
    // ピンバーチェック
    if(IsBullishPinBar())
        return true;

    // 包み足チェック
    if(IsBullishEngulfing())
        return true;

    // ネックラインブレイクチェック
    if(IsDoubleBottomNecklineBreak())
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| 売りプライスアクションのチェック                                   |
//+------------------------------------------------------------------+
bool CheckSellPriceAction()
{
    // ピンバーチェック
    if(IsBearishPinBar())
        return true;

    // 包み足チェック
    if(IsBearishEngulfing())
        return true;

    // ネックラインブレイクチェック
    if(IsDoubleTopNecklineBreak())
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| 強気ピンバーのチェック                                            |
//+------------------------------------------------------------------+
bool IsBullishPinBar()
{
    double open = iOpen(InpSymbol, InpEntryTimeframe, 1);
    double high = iHigh(InpSymbol, InpEntryTimeframe, 1);
    double low = iLow(InpSymbol, InpEntryTimeframe, 1);
    double close = iClose(InpSymbol, InpEntryTimeframe, 1);

    double body = MathAbs(close - open);
    double lowerWick = MathMin(open, close) - low;
    double upperWick = high - MathMax(open, close);

    if(body < symbolInfo.Point()) body = symbolInfo.Point();  // ゼロ除算防止

    // 下ヒゲが実体の3倍以上、かつ上ヒゲが下ヒゲより短い
    if(lowerWick >= body * InpPinBarWickRatio && lowerWick > upperWick * 2)
    {
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| 弱気ピンバーのチェック                                            |
//+------------------------------------------------------------------+
bool IsBearishPinBar()
{
    double open = iOpen(InpSymbol, InpEntryTimeframe, 1);
    double high = iHigh(InpSymbol, InpEntryTimeframe, 1);
    double low = iLow(InpSymbol, InpEntryTimeframe, 1);
    double close = iClose(InpSymbol, InpEntryTimeframe, 1);

    double body = MathAbs(close - open);
    double lowerWick = MathMin(open, close) - low;
    double upperWick = high - MathMax(open, close);

    if(body < symbolInfo.Point()) body = symbolInfo.Point();

    // 上ヒゲが実体の3倍以上、かつ下ヒゲが上ヒゲより短い
    if(upperWick >= body * InpPinBarWickRatio && upperWick > lowerWick * 2)
    {
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| 強気包み足のチェック                                              |
//+------------------------------------------------------------------+
bool IsBullishEngulfing()
{
    double open1 = iOpen(InpSymbol, InpEntryTimeframe, 1);
    double close1 = iClose(InpSymbol, InpEntryTimeframe, 1);
    double open2 = iOpen(InpSymbol, InpEntryTimeframe, 2);
    double close2 = iClose(InpSymbol, InpEntryTimeframe, 2);

    // 現在のバー（1）が陽線で、前のバー（2）が陰線
    if(close1 > open1 && close2 < open2)
    {
        // 現在のバーの実体が前のバーの実体を完全に包み込む
        if(open1 < close2 && close1 > open2)
        {
            double body1 = close1 - open1;
            double body2 = open2 - close2;

            // 現在の実体が前の実体より大きい
            if(body1 >= body2 * InpEngulfingMinRatio)
            {
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| 弱気包み足のチェック                                              |
//+------------------------------------------------------------------+
bool IsBearishEngulfing()
{
    double open1 = iOpen(InpSymbol, InpEntryTimeframe, 1);
    double close1 = iClose(InpSymbol, InpEntryTimeframe, 1);
    double open2 = iOpen(InpSymbol, InpEntryTimeframe, 2);
    double close2 = iClose(InpSymbol, InpEntryTimeframe, 2);

    // 現在のバー（1）が陰線で、前のバー（2）が陽線
    if(close1 < open1 && close2 > open2)
    {
        // 現在のバーの実体が前のバーの実体を完全に包み込む
        if(open1 > close2 && close1 < open2)
        {
            double body1 = open1 - close1;
            double body2 = close2 - open2;

            // 現在の実体が前の実体より大きい
            if(body1 >= body2 * InpEngulfingMinRatio)
            {
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| ダブルボトムネックラインブレイクのチェック                         |
//+------------------------------------------------------------------+
bool IsDoubleBottomNecklineBreak()
{
    // 直近20本のバーからスイングローを検出
    double lows[], highs[];
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(highs, true);

    int barsToCheck = 20;

    // スイングローの検出（左右3本より安い安値）
    double swingLows[10];
    int swingLowBars[10];
    int swingLowCount = 0;

    for(int i = 3; i < barsToCheck - 3 && swingLowCount < 10; i++)
    {
        double low = iLow(InpSymbol, InpEntryTimeframe, i);
        bool isSwingLow = true;

        for(int j = 1; j <= 3; j++)
        {
            if(iLow(InpSymbol, InpEntryTimeframe, i - j) < low ||
               iLow(InpSymbol, InpEntryTimeframe, i + j) < low)
            {
                isSwingLow = false;
                break;
            }
        }

        if(isSwingLow)
        {
            swingLows[swingLowCount] = low;
            swingLowBars[swingLowCount] = i;
            swingLowCount++;
        }
    }

    // 2つ以上のスイングローが必要
    if(swingLowCount < 2) return false;

    // ダブルボトムパターンの検出（2つの安値がほぼ同じレベル）
    double pipSize = GetPipSize();
    double tolerance = 5 * pipSize;  // 5pipsの許容誤差

    for(int i = 0; i < swingLowCount - 1; i++)
    {
        if(MathAbs(swingLows[i] - swingLows[i + 1]) <= tolerance)
        {
            // ダブルボトムを検出
            // ネックラインは2つの安値の間の最高値
            double neckline = 0;
            for(int j = swingLowBars[i]; j <= swingLowBars[i + 1]; j++)
            {
                double high = iHigh(InpSymbol, InpEntryTimeframe, j);
                if(high > neckline) neckline = high;
            }

            // 直近のバーがネックラインを上抜け
            double close1 = iClose(InpSymbol, InpEntryTimeframe, 1);
            double open1 = iOpen(InpSymbol, InpEntryTimeframe, 1);

            if(close1 > neckline && close1 > open1)  // 陽線でブレイク
            {
                g_doubleBottomNeckline = neckline;
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| ダブルトップネックラインブレイクのチェック                         |
//+------------------------------------------------------------------+
bool IsDoubleTopNecklineBreak()
{
    int barsToCheck = 20;

    // スイングハイの検出
    double swingHighs[10];
    int swingHighBars[10];
    int swingHighCount = 0;

    for(int i = 3; i < barsToCheck - 3 && swingHighCount < 10; i++)
    {
        double high = iHigh(InpSymbol, InpEntryTimeframe, i);
        bool isSwingHigh = true;

        for(int j = 1; j <= 3; j++)
        {
            if(iHigh(InpSymbol, InpEntryTimeframe, i - j) > high ||
               iHigh(InpSymbol, InpEntryTimeframe, i + j) > high)
            {
                isSwingHigh = false;
                break;
            }
        }

        if(isSwingHigh)
        {
            swingHighs[swingHighCount] = high;
            swingHighBars[swingHighCount] = i;
            swingHighCount++;
        }
    }

    if(swingHighCount < 2) return false;

    double pipSize = GetPipSize();
    double tolerance = 5 * pipSize;

    for(int i = 0; i < swingHighCount - 1; i++)
    {
        if(MathAbs(swingHighs[i] - swingHighs[i + 1]) <= tolerance)
        {
            // ダブルトップを検出
            double neckline = DBL_MAX;
            for(int j = swingHighBars[i]; j <= swingHighBars[i + 1]; j++)
            {
                double low = iLow(InpSymbol, InpEntryTimeframe, j);
                if(low < neckline) neckline = low;
            }

            double close1 = iClose(InpSymbol, InpEntryTimeframe, 1);
            double open1 = iOpen(InpSymbol, InpEntryTimeframe, 1);

            if(close1 < neckline && close1 < open1)  // 陰線でブレイク
            {
                g_doubleTopNeckline = neckline;
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| 買いエントリーの実行                                              |
//+------------------------------------------------------------------+
void ExecuteBuyEntry()
{
    // SL計算（エントリーバーの安値 - バッファ）
    double entryPrice = symbolInfo.Ask();
    double slPrice = iLow(InpSymbol, InpEntryTimeframe, 1) - (InpSLBuffer * GetPipSize());

    // エンベロープの外側バンドをSLの代替として使用（より広い方）
    double lowerBand[];
    ArraySetAsSeries(lowerBand, true);
    if(CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 1, 0, 3, lowerBand) >= 3)
    {
        double envSL = lowerBand[0] - (InpSLBuffer * GetPipSize());
        if(envSL < slPrice)
            slPrice = envSL;
    }

    // SL距離（pips）
    double slPips = (entryPrice - slPrice) / GetPipSize();

    // ロットサイズ計算
    double lots = CalculateLotSize(slPips);
    if(lots <= 0)
    {
        Print("エラー: ロットサイズが0以下です");
        return;
    }

    // リスクチェック（エントリー前）
    double potentialLoss = CalculateLossPerLot(slPips) * lots;
    double currentEquity = accountInfo.Equity();

    if(currentEquity - potentialLoss < g_dailyLossLine ||
       currentEquity - potentialLoss < g_totalLossLine)
    {
        Print("警告: このトレードは損失制限を超える可能性があります。エントリーをスキップ");
        return;
    }

    // TP計算（第1目標：中心線）
    double centerLine[];
    ArraySetAsSeries(centerLine, true);
    CopyBuffer(h_envelopes[0], 0, 0, 3, centerLine);  // 中心線を取得

    // iEnvelopesのバッファ0は上限、バッファ1は下限
    // 中心線は計算する必要がある
    double upperBand[], lowerBandTP[];
    ArraySetAsSeries(upperBand, true);
    ArraySetAsSeries(lowerBandTP, true);
    CopyBuffer(h_envelopes[0], 0, 0, 3, upperBand);
    CopyBuffer(h_envelopes[0], 1, 0, 3, lowerBandTP);

    double tpPrice = (upperBand[0] + lowerBandTP[0]) / 2;  // 中心線

    // 外側のバンド（0.35%または0.4%）で反発した場合はTPを伸ばす
    if(g_touchedEnvelopeBand >= 5)  // 0.35%以上
    {
        // 反対側のバンドまでTPを伸ばす
        CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 0, 0, 3, upperBand);
        tpPrice = upperBand[0];
    }

    // エントリー記録
    g_entryEnvelopeLevel = (double)g_touchedEnvelopeBand;

    // オーダー送信
    if(trade.Buy(lots, InpSymbol, entryPrice, slPrice, tpPrice,
                 StringFormat("Envelope Buy L%d", g_touchedEnvelopeBand)))
    {
        Print("買いエントリー成功: ", lots, " ロット @ ", entryPrice);
        Print("SL: ", slPrice, " TP: ", tpPrice);
        Print("エンベロープレベル: ", g_touchedEnvelopeBand);
    }
    else
    {
        Print("買いエントリー失敗: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| 売りエントリーの実行                                              |
//+------------------------------------------------------------------+
void ExecuteSellEntry()
{
    double entryPrice = symbolInfo.Bid();
    double slPrice = iHigh(InpSymbol, InpEntryTimeframe, 1) + (InpSLBuffer * GetPipSize());

    // エンベロープの外側バンドをSLの代替として使用
    double upperBand[];
    ArraySetAsSeries(upperBand, true);
    if(CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 0, 0, 3, upperBand) >= 3)
    {
        double envSL = upperBand[0] + (InpSLBuffer * GetPipSize());
        if(envSL > slPrice)
            slPrice = envSL;
    }

    double slPips = (slPrice - entryPrice) / GetPipSize();

    double lots = CalculateLotSize(slPips);
    if(lots <= 0)
    {
        Print("エラー: ロットサイズが0以下です");
        return;
    }

    double potentialLoss = CalculateLossPerLot(slPips) * lots;
    double currentEquity = accountInfo.Equity();

    if(currentEquity - potentialLoss < g_dailyLossLine ||
       currentEquity - potentialLoss < g_totalLossLine)
    {
        Print("警告: このトレードは損失制限を超える可能性があります。エントリーをスキップ");
        return;
    }

    // TP計算
    double lowerBand[], upperBandTP[];
    ArraySetAsSeries(lowerBand, true);
    ArraySetAsSeries(upperBandTP, true);
    CopyBuffer(h_envelopes[0], 0, 0, 3, upperBandTP);
    CopyBuffer(h_envelopes[0], 1, 0, 3, lowerBand);

    double tpPrice = (upperBandTP[0] + lowerBand[0]) / 2;

    if(g_touchedEnvelopeBand >= 5)
    {
        CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 1, 0, 3, lowerBand);
        tpPrice = lowerBand[0];
    }

    g_entryEnvelopeLevel = (double)g_touchedEnvelopeBand;

    if(trade.Sell(lots, InpSymbol, entryPrice, slPrice, tpPrice,
                  StringFormat("Envelope Sell L%d", g_touchedEnvelopeBand)))
    {
        Print("売りエントリー成功: ", lots, " ロット @ ", entryPrice);
        Print("SL: ", slPrice, " TP: ", tpPrice);
        Print("エンベロープレベル: ", g_touchedEnvelopeBand);
    }
    else
    {
        Print("売りエントリー失敗: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| オープンポジションの管理                                          |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!positionInfo.SelectByIndex(i))
            continue;

        if(positionInfo.Symbol() != InpSymbol || positionInfo.Magic() != InpMagicNumber)
            continue;

        // RSIダイバージェンスのチェック
        if(CheckRSIDivergence(positionInfo.PositionType()))
        {
            ClosePosition(positionInfo.Ticket(), "RSIダイバージェンス");
            continue;
        }

        // 分割決済のチェック
        if(InpUsePartialClose)
        {
            CheckPartialClose(positionInfo.Ticket(), positionInfo.PositionType());
        }

        // トレーリングストップ（オプション）
        // ManageTrailingStop(positionInfo.Ticket(), positionInfo.PositionType());
    }
}

//+------------------------------------------------------------------+
//| RSIダイバージェンスのチェック                                      |
//+------------------------------------------------------------------+
bool CheckRSIDivergence(ENUM_POSITION_TYPE posType)
{
    double rsi[];
    ArraySetAsSeries(rsi, true);

    if(CopyBuffer(h_rsi, 0, 0, 20, rsi) < 20)
        return false;

    // 価格の高値/安値
    double priceHigh1 = 0, priceHigh2 = 0;
    double priceLow1 = 0, priceLow2 = 0;
    int highBar1 = 0, highBar2 = 0;
    int lowBar1 = 0, lowBar2 = 0;

    // スイングポイントを検出
    for(int i = 2; i < 18; i++)
    {
        double high = iHigh(InpSymbol, InpEntryTimeframe, i);
        double low = iLow(InpSymbol, InpEntryTimeframe, i);

        // スイングハイ
        if(high > iHigh(InpSymbol, InpEntryTimeframe, i-1) &&
           high > iHigh(InpSymbol, InpEntryTimeframe, i+1))
        {
            if(priceHigh1 == 0)
            {
                priceHigh1 = high;
                highBar1 = i;
            }
            else if(priceHigh2 == 0)
            {
                priceHigh2 = high;
                highBar2 = i;
                break;
            }
        }
    }

    for(int i = 2; i < 18; i++)
    {
        double low = iLow(InpSymbol, InpEntryTimeframe, i);

        // スイングロー
        if(low < iLow(InpSymbol, InpEntryTimeframe, i-1) &&
           low < iLow(InpSymbol, InpEntryTimeframe, i+1))
        {
            if(priceLow1 == 0)
            {
                priceLow1 = low;
                lowBar1 = i;
            }
            else if(priceLow2 == 0)
            {
                priceLow2 = low;
                lowBar2 = i;
                break;
            }
        }
    }

    // 買いポジションの場合：弱気ダイバージェンス（価格高値更新、RSI高値切り下げ）
    if(posType == POSITION_TYPE_BUY)
    {
        if(priceHigh1 > 0 && priceHigh2 > 0)
        {
            if(priceHigh1 > priceHigh2 && rsi[highBar1] < rsi[highBar2])
            {
                Print("弱気ダイバージェンス検出");
                return true;
            }
        }
    }
    // 売りポジションの場合：強気ダイバージェンス（価格安値更新、RSI安値切り上げ）
    else if(posType == POSITION_TYPE_SELL)
    {
        if(priceLow1 > 0 && priceLow2 > 0)
        {
            if(priceLow1 < priceLow2 && rsi[lowBar1] > rsi[lowBar2])
            {
                Print("強気ダイバージェンス検出");
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| 分割決済のチェック                                                |
//+------------------------------------------------------------------+
void CheckPartialClose(ulong ticket, ENUM_POSITION_TYPE posType)
{
    if(!positionInfo.SelectByTicket(ticket))
        return;

    double openPrice = positionInfo.PriceOpen();
    double currentPrice = posType == POSITION_TYPE_BUY ? symbolInfo.Bid() : symbolInfo.Ask();
    double volume = positionInfo.Volume();

    // 中心線を取得
    double upperBand[], lowerBand[];
    ArraySetAsSeries(upperBand, true);
    ArraySetAsSeries(lowerBand, true);
    CopyBuffer(h_envelopes[0], 0, 0, 3, upperBand);
    CopyBuffer(h_envelopes[0], 1, 0, 3, lowerBand);
    double centerLine = (upperBand[0] + lowerBand[0]) / 2;

    // 第1目標（中心線）到達で部分決済
    if(posType == POSITION_TYPE_BUY && currentPrice >= centerLine && openPrice < centerLine)
    {
        double closeVolume = NormalizeLotSize(volume * InpPartialCloseRatio);
        if(closeVolume >= symbolInfo.LotsMin())
        {
            trade.PositionClosePartial(ticket, closeVolume);
            Print("部分決済実行（買い）: ", closeVolume, " ロット @ 中心線到達");
        }
    }
    else if(posType == POSITION_TYPE_SELL && currentPrice <= centerLine && openPrice > centerLine)
    {
        double closeVolume = NormalizeLotSize(volume * InpPartialCloseRatio);
        if(closeVolume >= symbolInfo.LotsMin())
        {
            trade.PositionClosePartial(ticket, closeVolume);
            Print("部分決済実行（売り）: ", closeVolume, " ロット @ 中心線到達");
        }
    }
}

//+------------------------------------------------------------------+
//| ポジションの決済                                                  |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
    if(trade.PositionClose(ticket))
    {
        Print("ポジション決済: チケット ", ticket, " 理由: ", reason);
    }
    else
    {
        Print("ポジション決済失敗: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| すべてのポジションを決済                                          |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == InpSymbol && positionInfo.Magic() == InpMagicNumber)
            {
                ClosePosition(positionInfo.Ticket(), reason);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| OnTimer イベントハンドラー                                        |
//+------------------------------------------------------------------+
void OnTimer()
{
    // リスク管理のリアルタイム監視
    if(!CheckRiskLimits())
    {
        CloseAllPositions("リスク制限到達（タイマー）");
    }
}

//+------------------------------------------------------------------+
