//+------------------------------------------------------------------+
//|                              USDJPY_RangeEnvelope_EA.mq5         |
//|         ドル円専用EA: レンジBOX×エンベロープ逆張り戦略           |
//|                     Fintokei チャレンジプラン対応                |
//+------------------------------------------------------------------+
#property copyright "USDJPY Range Envelope EA"
#property link      ""
#property version   "2.00"
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
input ENUM_TIMEFRAMES InpEntryTimeframe = PERIOD_M1;   // エントリー足（1分足）
input ENUM_TIMEFRAMES InpRangeTF1      = PERIOD_M15;   // レンジ検出足1（15分足）
input ENUM_TIMEFRAMES InpRangeTF2      = PERIOD_M5;    // レンジ検出足2（5分足）
input int      InpMagicNumber          = 20241231;     // マジックナンバー

input group "===== トレード時間設定 ====="
input int      InpTradingStartHour     = 0;            // トレード開始時刻（サーバー時間）
input int      InpTradingEndHour       = 24;           // トレード終了時刻（サーバー時間）
input bool     InpTradingOnMonday      = true;         // 月曜日にトレード
input bool     InpTradingOnTuesday     = true;         // 火曜日にトレード
input bool     InpTradingOnWednesday   = true;         // 水曜日にトレード
input bool     InpTradingOnThursday    = true;         // 木曜日にトレード
input bool     InpTradingOnFriday      = true;         // 金曜日にトレード

input group "===== レンジBOX検出設定 ====="
input bool     InpUseADXFilter         = true;         // ADXフィルターを使用
input int      InpADXPeriod            = 14;           // ADX期間
input double   InpADXThreshold         = 25.0;         // ADX閾値（これ以下でレンジ）
input bool     InpUseBBSqueezeFilter   = true;         // BBスクイーズフィルターを使用
input int      InpBBPeriod             = 20;           // ボリンジャーバンド期間
input double   InpBBDeviation          = 2.0;          // ボリンジャーバンド偏差
input double   InpBBSqueezeRatio       = 0.7;          // BBスクイーズ比率（平均の何倍以下でスクイーズ）
input bool     InpUseATRFilter         = true;         // ATRフィルターを使用
input int      InpATRPeriod            = 14;           // ATR期間
input double   InpATRRatio             = 0.8;          // ATR比率（平均の何倍以下でレンジ）

input group "===== トレンドフィルター設定 ====="
input bool     InpUseTrendFilter       = true;         // トレンドフィルターを使用
input ENUM_TIMEFRAMES InpTrendTF       = PERIOD_M15;   // トレンド判定足
input int      InpTrendEMAPeriod       = 50;           // トレンドEMA期間
input int      InpTrendEMAShift        = 0;            // EMAシフト

input group "===== エンベロープ設定（1分足）====="
input int      InpEnvelopePeriod       = 20;           // エンベロープ期間
input double   InpEnvelopeDev1         = 0.05;         // 偏差1 (%)
input double   InpEnvelopeDev2         = 0.08;         // 偏差2 (%)
input double   InpEnvelopeDev3         = 0.10;         // 偏差3 (%)
input double   InpEnvelopeDev4         = 0.12;         // 偏差4 (%)
input double   InpEnvelopeDev5         = 0.15;         // 偏差5 (%)
input double   InpEnvelopeDev6         = 0.18;         // 偏差6 (%)

input group "===== プライスアクション設定 ====="
input bool     InpUsePriceAction       = false;        // プライスアクション確認を使用
input double   InpPinBarWickRatio      = 2.0;          // ピンバーヒゲ倍率
input double   InpEngulfingMinRatio    = 1.0;          // 包み足最小倍率

input group "===== セッションフィルター設定 ====="
input bool     InpUseSessionFilter     = true;         // セッションフィルターを使用
input bool     InpTradeAsianSession    = true;         // アジアセッション（0-8時）
input bool     InpTradeLondonSession   = true;         // ロンドンセッション（8-16時）
input bool     InpTradeNYSession       = true;         // NYセッション（16-24時）

input group "===== ボリューム確認設定 ====="
input bool     InpUseVolumeFilter      = false;        // ボリュームフィルターを使用
input double   InpVolumeRatio          = 0.8;          // ボリューム比率（平均の何倍以下で低ボリューム）
input int      InpVolumePeriod         = 20;           // ボリューム平均期間

input group "===== 利確・損切り設定 ====="
input int      InpTPMode               = 1;            // TPモード（0=中心線, 1=反対側バンド）
input int      InpSLBuffer             = 2;            // SLバッファ (pips)
input bool     InpUseRangeBreakExit    = true;         // レンジブレイク時に決済
input double   InpRangeBreakATRMult    = 1.5;          // レンジブレイク判定（ATRの何倍）

input group "===== 最大保有時間設定 ====="
input bool     InpUseMaxHoldTime       = true;         // 最大保有時間を使用
input int      InpMaxHoldBars          = 60;           // 最大保有バー数（1分足基準）

input group "===== リスク管理設定 ====="
input double   InpRiskPercent          = 1.0;          // 1トレードあたりのリスク (%)
input double   InpMaxPositionLossPercent = 3.0;        // 1ポジション最大含み損 (%)
input double   InpMaxDailyLossPercent  = 5.0;          // 1日の最大損失率 (%)
input double   InpMaxTotalLossPercent  = 10.0;         // 全体の最大損失率 (%)
input double   InpMinLotSize           = 0.01;         // 最小エントリーロット

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symbolInfo;

// インジケーターハンドル
int h_adx_tf1, h_adx_tf2;           // ADX
int h_bb_tf1, h_bb_tf2;             // ボリンジャーバンド
int h_atr_tf1, h_atr_tf2;           // ATR
int h_envelopes[6];                  // エンベロープ（6段階）
int h_trend_ema;                     // トレンドEMA

// リスク管理変数
double g_initialBalance;
double g_dailyStartEquity;
datetime g_lastDayCheck;
double g_totalLossLine;
double g_dailyLossLine;

// トレード管理
int g_touchedEnvelopeBand;
datetime g_entryTime;
double g_rangeHigh;
double g_rangeLow;
double g_rangeATR;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!symbolInfo.Name(InpSymbol))
    {
        Print("エラー: シンボル ", InpSymbol, " が見つかりません");
        return INIT_FAILED;
    }

    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    if(!InitializeIndicators())
    {
        Print("エラー: インジケーターの初期化に失敗しました");
        return INIT_FAILED;
    }

    InitializeRiskManagement();

    Print("=== Range Envelope EA 初期化完了 ===");
    Print("レンジ検出TF: ", EnumToString(InpRangeTF1), " / ", EnumToString(InpRangeTF2));
    Print("エントリーTF: ", EnumToString(InpEntryTimeframe));
    Print("ADXフィルター: ", InpUseADXFilter ? "ON" : "OFF");
    Print("BBスクイーズフィルター: ", InpUseBBSqueezeFilter ? "ON" : "OFF");
    Print("ATRフィルター: ", InpUseATRFilter ? "ON" : "OFF");
    Print("トレンドフィルター: ", InpUseTrendFilter ? "ON" : "OFF", " (", EnumToString(InpTrendTF), " EMA", InpTrendEMAPeriod, ")");
    Print("プライスアクション: ", InpUsePriceAction ? "ON" : "OFF");
    Print("セッションフィルター: ", InpUseSessionFilter ? "ON" : "OFF");
    Print("ボリュームフィルター: ", InpUseVolumeFilter ? "ON" : "OFF");
    Print("レンジブレイク決済: ", InpUseRangeBreakExit ? "ON" : "OFF");
    Print("最大保有時間: ", InpUseMaxHoldTime ? "ON" : "OFF");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(h_adx_tf1 != INVALID_HANDLE) IndicatorRelease(h_adx_tf1);
    if(h_adx_tf2 != INVALID_HANDLE) IndicatorRelease(h_adx_tf2);
    if(h_bb_tf1 != INVALID_HANDLE) IndicatorRelease(h_bb_tf1);
    if(h_bb_tf2 != INVALID_HANDLE) IndicatorRelease(h_bb_tf2);
    if(h_atr_tf1 != INVALID_HANDLE) IndicatorRelease(h_atr_tf1);
    if(h_atr_tf2 != INVALID_HANDLE) IndicatorRelease(h_atr_tf2);
    if(h_trend_ema != INVALID_HANDLE) IndicatorRelease(h_trend_ema);

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
    if(!symbolInfo.RefreshRates())
        return;

    CheckDailyReset();
    CheckPositionLossLimit();

    if(!CheckRiskLimits())
    {
        CloseAllPositions("リスク制限到達");
        return;
    }

    // ポジション保有中の管理
    if(HasOpenPosition())
    {
        ManageOpenPosition();
        return;
    }

    // 新しいバーでのみエントリーチェック
    if(!IsNewBar(InpEntryTimeframe))
        return;

    // トレード時間チェック
    if(!IsTradingTime())
        return;

    // セッションフィルター
    if(InpUseSessionFilter && !IsValidSession())
        return;

    // レンジBOX検出
    if(!IsRangeMarket())
        return;

    // ボリュームフィルター
    if(InpUseVolumeFilter && !IsLowVolume())
        return;

    // エントリー条件のチェック
    CheckEntryConditions();
}

//+------------------------------------------------------------------+
//| インジケーターの初期化                                            |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    // ADX（2つの時間足）
    h_adx_tf1 = iADX(InpSymbol, InpRangeTF1, InpADXPeriod);
    h_adx_tf2 = iADX(InpSymbol, InpRangeTF2, InpADXPeriod);
    if(h_adx_tf1 == INVALID_HANDLE || h_adx_tf2 == INVALID_HANDLE)
    {
        Print("エラー: ADXの作成に失敗");
        return false;
    }

    // ボリンジャーバンド（2つの時間足）
    h_bb_tf1 = iBands(InpSymbol, InpRangeTF1, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
    h_bb_tf2 = iBands(InpSymbol, InpRangeTF2, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
    if(h_bb_tf1 == INVALID_HANDLE || h_bb_tf2 == INVALID_HANDLE)
    {
        Print("エラー: ボリンジャーバンドの作成に失敗");
        return false;
    }

    // ATR（2つの時間足）
    h_atr_tf1 = iATR(InpSymbol, InpRangeTF1, InpATRPeriod);
    h_atr_tf2 = iATR(InpSymbol, InpRangeTF2, InpATRPeriod);
    if(h_atr_tf1 == INVALID_HANDLE || h_atr_tf2 == INVALID_HANDLE)
    {
        Print("エラー: ATRの作成に失敗");
        return false;
    }

    // エンベロープ（6段階、1分足）
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

    // トレンドEMA
    h_trend_ema = iMA(InpSymbol, InpTrendTF, InpTrendEMAPeriod, InpTrendEMAShift, MODE_EMA, PRICE_CLOSE);
    if(h_trend_ema == INVALID_HANDLE)
    {
        Print("エラー: トレンドEMAの作成に失敗");
        return false;
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

    if(currentTime.day != lastTime.day)
    {
        g_dailyStartEquity = accountInfo.Equity();
        g_dailyLossLine = g_dailyStartEquity * (1.0 - InpMaxDailyLossPercent / 100.0);
        g_lastDayCheck = TimeCurrent();
        Print("日次リセット: 新しい日次損失ライン = ", g_dailyLossLine);
    }
}

//+------------------------------------------------------------------+
//| リスク制限のチェック                                              |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
    double currentEquity = accountInfo.Equity();

    if(currentEquity <= g_totalLossLine)
    {
        Print("警告: 全体損失制限（10%）に到達");
        return false;
    }

    if(currentEquity <= g_dailyLossLine)
    {
        Print("警告: 日次損失制限（5%）に到達");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| 個別ポジションの含み損チェック                                     |
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

        double positionProfit = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();

        if(positionProfit < 0 && MathAbs(positionProfit) >= maxLossAmount)
        {
            Print("警告: ポジション含み損が", InpMaxPositionLossPercent, "%に到達！");
            ClosePosition(positionInfo.Ticket(), "含み損制限");
        }
    }
}

//+------------------------------------------------------------------+
//| レンジ相場の判定                                                  |
//+------------------------------------------------------------------+
bool IsRangeMarket()
{
    bool isRange = false;
    int rangeConditionsMet = 0;
    int totalConditions = 0;

    // ADXフィルター
    if(InpUseADXFilter)
    {
        totalConditions++;
        if(CheckADXRange())
            rangeConditionsMet++;
    }

    // BBスクイーズフィルター
    if(InpUseBBSqueezeFilter)
    {
        totalConditions++;
        if(CheckBBSqueeze())
            rangeConditionsMet++;
    }

    // ATRフィルター
    if(InpUseATRFilter)
    {
        totalConditions++;
        if(CheckATRRange())
            rangeConditionsMet++;
    }

    // フィルターが1つもONでない場合は常にレンジとみなす
    if(totalConditions == 0)
        return true;

    // 少なくとも1つの条件を満たせばレンジとみなす
    // （全部満たす必要がある場合は rangeConditionsMet == totalConditions に変更）
    isRange = (rangeConditionsMet >= 1);

    if(isRange)
    {
        // レンジの範囲を記録
        UpdateRangeInfo();
    }

    return isRange;
}

//+------------------------------------------------------------------+
//| ADXによるレンジ判定                                               |
//+------------------------------------------------------------------+
bool CheckADXRange()
{
    double adx1[], adx2[];
    ArraySetAsSeries(adx1, true);
    ArraySetAsSeries(adx2, true);

    if(CopyBuffer(h_adx_tf1, 0, 0, 3, adx1) < 3) return false;
    if(CopyBuffer(h_adx_tf2, 0, 0, 3, adx2) < 3) return false;

    // 両方の時間足でADXが閾値以下
    bool tf1Range = (adx1[0] < InpADXThreshold);
    bool tf2Range = (adx2[0] < InpADXThreshold);

    return (tf1Range || tf2Range);  // どちらかでレンジ
}

//+------------------------------------------------------------------+
//| BBスクイーズによるレンジ判定                                       |
//+------------------------------------------------------------------+
bool CheckBBSqueeze()
{
    double bbUpper1[], bbLower1[], bbUpper2[], bbLower2[];
    ArraySetAsSeries(bbUpper1, true);
    ArraySetAsSeries(bbLower1, true);
    ArraySetAsSeries(bbUpper2, true);
    ArraySetAsSeries(bbLower2, true);

    if(CopyBuffer(h_bb_tf1, 1, 0, 21, bbUpper1) < 21) return false;
    if(CopyBuffer(h_bb_tf1, 2, 0, 21, bbLower1) < 21) return false;
    if(CopyBuffer(h_bb_tf2, 1, 0, 21, bbUpper2) < 21) return false;
    if(CopyBuffer(h_bb_tf2, 2, 0, 21, bbLower2) < 21) return false;

    // BB幅の計算（TF1）
    double currentWidth1 = bbUpper1[0] - bbLower1[0];
    double avgWidth1 = 0;
    for(int i = 0; i < 20; i++)
        avgWidth1 += (bbUpper1[i+1] - bbLower1[i+1]);
    avgWidth1 /= 20;

    // BB幅の計算（TF2）
    double currentWidth2 = bbUpper2[0] - bbLower2[0];
    double avgWidth2 = 0;
    for(int i = 0; i < 20; i++)
        avgWidth2 += (bbUpper2[i+1] - bbLower2[i+1]);
    avgWidth2 /= 20;

    // スクイーズ判定
    bool tf1Squeeze = (currentWidth1 < avgWidth1 * InpBBSqueezeRatio);
    bool tf2Squeeze = (currentWidth2 < avgWidth2 * InpBBSqueezeRatio);

    return (tf1Squeeze || tf2Squeeze);
}

//+------------------------------------------------------------------+
//| ATRによるレンジ判定                                               |
//+------------------------------------------------------------------+
bool CheckATRRange()
{
    double atr1[], atr2[];
    ArraySetAsSeries(atr1, true);
    ArraySetAsSeries(atr2, true);

    if(CopyBuffer(h_atr_tf1, 0, 0, 21, atr1) < 21) return false;
    if(CopyBuffer(h_atr_tf2, 0, 0, 21, atr2) < 21) return false;

    // ATR平均の計算（TF1）
    double avgATR1 = 0;
    for(int i = 1; i < 21; i++)
        avgATR1 += atr1[i];
    avgATR1 /= 20;

    // ATR平均の計算（TF2）
    double avgATR2 = 0;
    for(int i = 1; i < 21; i++)
        avgATR2 += atr2[i];
    avgATR2 /= 20;

    // レンジ判定
    bool tf1Low = (atr1[0] < avgATR1 * InpATRRatio);
    bool tf2Low = (atr2[0] < avgATR2 * InpATRRatio);

    // レンジブレイク判定用にATRを保存
    g_rangeATR = atr1[0];

    return (tf1Low || tf2Low);
}

//+------------------------------------------------------------------+
//| レンジ情報の更新                                                  |
//+------------------------------------------------------------------+
void UpdateRangeInfo()
{
    // 直近20本の高値・安値からレンジを計算
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    int copied = CopyHigh(InpSymbol, InpRangeTF1, 0, 20, highs);
    CopyLow(InpSymbol, InpRangeTF1, 0, 20, lows);

    if(copied < 20) return;

    g_rangeHigh = highs[ArrayMaximum(highs)];
    g_rangeLow = lows[ArrayMinimum(lows)];
}

//+------------------------------------------------------------------+
//| トレンド方向の取得（1=上昇, -1=下降, 0=不明）                      |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
    if(!InpUseTrendFilter)
        return 0;  // フィルターOFFの場合は方向指定なし

    double ema[];
    ArraySetAsSeries(ema, true);

    if(CopyBuffer(h_trend_ema, 0, 0, 3, ema) < 3)
        return 0;

    double currentPrice = symbolInfo.Bid();

    // EMAより上なら上昇トレンド、下なら下降トレンド
    if(currentPrice > ema[0])
        return 1;   // 上昇トレンド → 買いのみ許可
    else if(currentPrice < ema[0])
        return -1;  // 下降トレンド → 売りのみ許可

    return 0;
}

//+------------------------------------------------------------------+
//| セッション判定                                                    |
//+------------------------------------------------------------------+
bool IsValidSession()
{
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);
    int hour = currentTime.hour;

    // アジアセッション（0-8時 サーバー時間）
    if(hour >= 0 && hour < 8)
        return InpTradeAsianSession;

    // ロンドンセッション（8-16時）
    if(hour >= 8 && hour < 16)
        return InpTradeLondonSession;

    // NYセッション（16-24時）
    if(hour >= 16 && hour < 24)
        return InpTradeNYSession;

    return true;
}

//+------------------------------------------------------------------+
//| 低ボリューム判定                                                  |
//+------------------------------------------------------------------+
bool IsLowVolume()
{
    long volumes[];
    ArraySetAsSeries(volumes, true);

    if(CopyTickVolume(InpSymbol, InpEntryTimeframe, 0, InpVolumePeriod + 1, volumes) < InpVolumePeriod + 1)
        return true;  // データ取得失敗時はフィルターをパス

    // 平均ボリューム計算
    double avgVolume = 0;
    for(int i = 1; i <= InpVolumePeriod; i++)
        avgVolume += (double)volumes[i];
    avgVolume /= InpVolumePeriod;

    // 現在のボリュームが平均より低い
    return ((double)volumes[0] < avgVolume * InpVolumeRatio);
}

//+------------------------------------------------------------------+
//| トレード時間のチェック                                            |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);

    // 曜日チェック
    switch(currentTime.day_of_week)
    {
        case 0: return false;
        case 1: if(!InpTradingOnMonday) return false; break;
        case 2: if(!InpTradingOnTuesday) return false; break;
        case 3: if(!InpTradingOnWednesday) return false; break;
        case 4: if(!InpTradingOnThursday) return false; break;
        case 5: if(!InpTradingOnFriday) return false; break;
        case 6: return false;
    }

    // 時間チェック
    int currentHour = currentTime.hour;

    if(InpTradingStartHour < InpTradingEndHour)
    {
        if(currentHour < InpTradingStartHour || currentHour >= InpTradingEndHour)
            return false;
    }
    else if(InpTradingStartHour > InpTradingEndHour)
    {
        if(currentHour < InpTradingStartHour && currentHour >= InpTradingEndHour)
            return false;
    }

    return true;
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
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| エントリー条件のチェック                                          |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
    int touchedBand = 0;
    bool buySignal = false;
    bool sellSignal = false;

    // トレンド方向を取得
    int trendDirection = GetTrendDirection();

    // 下限バンドタッチ → 買いシグナル
    // トレンドフィルター: 上昇トレンド(1)または方向不明(0)の場合のみ
    if(trendDirection >= 0)
    {
        touchedBand = CheckEnvelopeLowerBandTouch();
        if(touchedBand > 0)
        {
            if(!InpUsePriceAction || CheckBuyPriceAction())
            {
                buySignal = true;
                g_touchedEnvelopeBand = touchedBand;
            }
        }
    }

    // 上限バンドタッチ → 売りシグナル
    // トレンドフィルター: 下降トレンド(-1)または方向不明(0)の場合のみ
    if(!buySignal && trendDirection <= 0)
    {
        touchedBand = CheckEnvelopeUpperBandTouch();
        if(touchedBand > 0)
        {
            if(!InpUsePriceAction || CheckSellPriceAction())
            {
                sellSignal = true;
                g_touchedEnvelopeBand = touchedBand;
            }
        }
    }

    // エントリー実行
    if(buySignal)
        ExecuteBuyEntry();
    else if(sellSignal)
        ExecuteSellEntry();
}

//+------------------------------------------------------------------+
//| エンベロープ下限バンドタッチのチェック                             |
//+------------------------------------------------------------------+
int CheckEnvelopeLowerBandTouch()
{
    double low = iLow(InpSymbol, InpEntryTimeframe, 1);

    for(int i = 5; i >= 0; i--)
    {
        double lowerBand[];
        ArraySetAsSeries(lowerBand, true);

        if(CopyBuffer(h_envelopes[i], 1, 0, 3, lowerBand) < 3)
            continue;

        if(low <= lowerBand[1])
            return i + 1;
    }

    return 0;
}

//+------------------------------------------------------------------+
//| エンベロープ上限バンドタッチのチェック                             |
//+------------------------------------------------------------------+
int CheckEnvelopeUpperBandTouch()
{
    double high = iHigh(InpSymbol, InpEntryTimeframe, 1);

    for(int i = 5; i >= 0; i--)
    {
        double upperBand[];
        ArraySetAsSeries(upperBand, true);

        if(CopyBuffer(h_envelopes[i], 0, 0, 3, upperBand) < 3)
            continue;

        if(high >= upperBand[1])
            return i + 1;
    }

    return 0;
}

//+------------------------------------------------------------------+
//| 買いプライスアクションのチェック                                   |
//+------------------------------------------------------------------+
bool CheckBuyPriceAction()
{
    if(IsBullishPinBar())
        return true;

    if(IsBullishEngulfing())
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| 売りプライスアクションのチェック                                   |
//+------------------------------------------------------------------+
bool CheckSellPriceAction()
{
    if(IsBearishPinBar())
        return true;

    if(IsBearishEngulfing())
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

    if(body < symbolInfo.Point()) body = symbolInfo.Point();

    if(lowerWick >= body * InpPinBarWickRatio && lowerWick > upperWick * 2)
        return true;

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

    if(upperWick >= body * InpPinBarWickRatio && upperWick > lowerWick * 2)
        return true;

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

    if(close1 > open1 && close2 < open2)
    {
        if(open1 < close2 && close1 > open2)
        {
            double body1 = close1 - open1;
            double body2 = open2 - close2;

            if(body1 >= body2 * InpEngulfingMinRatio)
                return true;
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

    if(close1 < open1 && close2 > open2)
    {
        if(open1 > close2 && close1 < open2)
        {
            double body1 = open1 - close1;
            double body2 = close2 - open2;

            if(body1 >= body2 * InpEngulfingMinRatio)
                return true;
        }
    }

    return false;
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
//| ロットサイズの計算                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
    if(slPips <= 0) return 0.0;

    double accountBalance = accountInfo.Balance();
    double maxLossAmount = accountBalance * (InpRiskPercent / 100.0);

    double pipSize = GetPipSize();
    double tickSize = symbolInfo.TickSize();
    double tickValue = symbolInfo.TickValue();

    double slDistance = slPips * pipSize;
    double numTicks = slDistance / tickSize;
    double lossPerLot = numTicks * tickValue;

    if(lossPerLot <= 0) return 0.0;

    double calculatedLots = maxLossAmount / lossPerLot;

    return NormalizeLotSize(calculatedLots);
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
//| 買いエントリーの実行                                              |
//+------------------------------------------------------------------+
void ExecuteBuyEntry()
{
    double entryPrice = symbolInfo.Ask();
    double pipSize = GetPipSize();

    // SL: タッチしたバンドの外側
    double lowerBand[];
    ArraySetAsSeries(lowerBand, true);
    CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 1, 0, 3, lowerBand);
    double slPrice = lowerBand[0] - (InpSLBuffer * pipSize);

    double slPips = (entryPrice - slPrice) / pipSize;

    // ロット計算
    double lots = CalculateLotSize(slPips);
    if(lots < InpMinLotSize)
    {
        Print("スキップ: ロット(", lots, ") < 最小ロット(", InpMinLotSize, ")");
        return;
    }

    // TP計算
    double tpPrice;
    if(InpTPMode == 0)
    {
        // 中心線
        double upperBand[], lowerBandTP[];
        ArraySetAsSeries(upperBand, true);
        ArraySetAsSeries(lowerBandTP, true);
        CopyBuffer(h_envelopes[0], 0, 0, 3, upperBand);
        CopyBuffer(h_envelopes[0], 1, 0, 3, lowerBandTP);
        tpPrice = (upperBand[0] + lowerBandTP[0]) / 2;
    }
    else
    {
        // 反対側バンド
        double upperBand[];
        ArraySetAsSeries(upperBand, true);
        CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 0, 0, 3, upperBand);
        tpPrice = upperBand[0];
    }

    // エントリー
    if(trade.Buy(lots, InpSymbol, entryPrice, slPrice, tpPrice,
                 StringFormat("RangeEnv Buy L%d", g_touchedEnvelopeBand)))
    {
        g_entryTime = TimeCurrent();
        Print("買いエントリー: ", lots, " @ ", entryPrice, " SL:", slPrice, " TP:", tpPrice);
    }
    else
    {
        Print("買いエントリー失敗: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| 売りエントリーの実行                                              |
//+------------------------------------------------------------------+
void ExecuteSellEntry()
{
    double entryPrice = symbolInfo.Bid();
    double pipSize = GetPipSize();

    // SL: タッチしたバンドの外側
    double upperBand[];
    ArraySetAsSeries(upperBand, true);
    CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 0, 0, 3, upperBand);
    double slPrice = upperBand[0] + (InpSLBuffer * pipSize);

    double slPips = (slPrice - entryPrice) / pipSize;

    // ロット計算
    double lots = CalculateLotSize(slPips);
    if(lots < InpMinLotSize)
    {
        Print("スキップ: ロット(", lots, ") < 最小ロット(", InpMinLotSize, ")");
        return;
    }

    // TP計算
    double tpPrice;
    if(InpTPMode == 0)
    {
        // 中心線
        double upperBandTP[], lowerBand[];
        ArraySetAsSeries(upperBandTP, true);
        ArraySetAsSeries(lowerBand, true);
        CopyBuffer(h_envelopes[0], 0, 0, 3, upperBandTP);
        CopyBuffer(h_envelopes[0], 1, 0, 3, lowerBand);
        tpPrice = (upperBandTP[0] + lowerBand[0]) / 2;
    }
    else
    {
        // 反対側バンド
        double lowerBand[];
        ArraySetAsSeries(lowerBand, true);
        CopyBuffer(h_envelopes[g_touchedEnvelopeBand - 1], 1, 0, 3, lowerBand);
        tpPrice = lowerBand[0];
    }

    // エントリー
    if(trade.Sell(lots, InpSymbol, entryPrice, slPrice, tpPrice,
                  StringFormat("RangeEnv Sell L%d", g_touchedEnvelopeBand)))
    {
        g_entryTime = TimeCurrent();
        Print("売りエントリー: ", lots, " @ ", entryPrice, " SL:", slPrice, " TP:", tpPrice);
    }
    else
    {
        Print("売りエントリー失敗: ", trade.ResultRetcode());
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

        // レンジブレイク決済
        if(InpUseRangeBreakExit && CheckRangeBreak(positionInfo.PositionType()))
        {
            ClosePosition(positionInfo.Ticket(), "レンジブレイク");
            continue;
        }

        // 最大保有時間決済
        if(InpUseMaxHoldTime && CheckMaxHoldTime())
        {
            ClosePosition(positionInfo.Ticket(), "最大保有時間");
            continue;
        }
    }
}

//+------------------------------------------------------------------+
//| レンジブレイクのチェック                                          |
//+------------------------------------------------------------------+
bool CheckRangeBreak(ENUM_POSITION_TYPE posType)
{
    double currentPrice = symbolInfo.Bid();
    double breakThreshold = g_rangeATR * InpRangeBreakATRMult;

    if(posType == POSITION_TYPE_BUY)
    {
        // 売りポジションの逆方向（下方向）へのブレイク
        if(currentPrice < g_rangeLow - breakThreshold)
            return true;
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        // 買いポジションの逆方向（上方向）へのブレイク
        if(currentPrice > g_rangeHigh + breakThreshold)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| 最大保有時間のチェック                                            |
//+------------------------------------------------------------------+
bool CheckMaxHoldTime()
{
    int barsSinceEntry = Bars(InpSymbol, InpEntryTimeframe, g_entryTime, TimeCurrent());
    return (barsSinceEntry >= InpMaxHoldBars);
}

//+------------------------------------------------------------------+
//| ポジションの決済                                                  |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
    if(trade.PositionClose(ticket))
        Print("ポジション決済: ", ticket, " 理由: ", reason);
    else
        Print("決済失敗: ", trade.ResultRetcode());
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
                ClosePosition(positionInfo.Ticket(), reason);
        }
    }
}
//+------------------------------------------------------------------+
