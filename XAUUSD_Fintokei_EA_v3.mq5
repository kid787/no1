//+------------------------------------------------------------------+
//|                                       XAUUSD_Fintokei_EA_v3.mq5 |
//|                        XAUUSD専用 Fintokeiチャレンジ対応EA v3    |
//|                        MTF分析・RR比改善・勝率向上版              |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Fintokei EA v3"
#property link      ""
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| 入力パラメータ                                                    |
//+------------------------------------------------------------------+
input group "===== 基本設定 ====="
input double   InitialBalance     = 0;        // 初期資金（0=自動取得）
input int      MagicNumber        = 123456;   // マジックナンバー
input ENUM_TIMEFRAMES MainTF      = PERIOD_M5;// メイン時間足

input group "===== Fintokei リスク管理 ====="
input double   DailyMaxLossPercent   = 3.5;   // 1日の最大損失率(%)
input double   TotalMaxLossPercent   = 7.0;   // 全体の最大損失率(%)
input double   MaxRiskPerTrade       = 1.0;   // 1トレードの最大リスク(%)
input double   DefaultRiskPercent    = 0.75;  // デフォルトリスク(%)
input double   DDWarningPercent      = 5.0;   // ドローダウン警告レベル(%)
input double   DDStopPercent         = 7.0;   // ドローダウン停止レベル(%)

input group "===== マルチタイムフレーム設定 ====="
input ENUM_TIMEFRAMES HTF1         = PERIOD_H1; // 上位足1（トレンド確認）
input ENUM_TIMEFRAMES HTF2         = PERIOD_H4; // 上位足2（大局トレンド）
input bool     RequireHTFAlignment = true;      // 上位足トレンド一致を要求

input group "===== 移動平均線設定 ====="
input int      SMA_Period         = 200;      // 長期SMA期間
input int      EMA_Period         = 100;      // 中期EMA期間
input int      FastEMA_Period     = 20;       // 短期EMA期間
input int      TrendEMA_Period    = 50;       // トレンド判定EMA期間

input group "===== RSI設定 ====="
input int      RSI_Period         = 14;       // RSI期間
input int      RSI_OversoldLevel  = 35;       // RSI売られすぎレベル
input int      RSI_OverboughtLevel= 65;       // RSI買われすぎレベル
input bool     UseRSIFilter       = true;     // RSIフィルターを使用

input group "===== グランビル設定 ====="
input double   GranvillePullbackPips = 25;    // MAへの引き付け距離(pips)
input double   GranvilleTouchPips    = 12;    // MAタッチ判定距離(pips)

input group "===== プライスアクション設定 ====="
input double   PinBarRatio        = 0.7;      // ピンバーの厳格比率
input double   EngulfingMinRatio  = 1.5;      // 包み足の最小比率

input group "===== 水平線設定 ====="
input int      SRLookback         = 120;      // S/R検出のルックバック期間
input double   SRZonePips         = 12;       // S/Rゾーン幅(pips)
input int      SRTouchCount       = 3;        // S/R確認に必要なタッチ数

input group "===== 損切り設定（厳格化） ====="
input double   SLBufferPercent    = 0.15;     // 損切りバッファ(%)
input int      SwingLookback      = 8;        // スイングルックバック
input double   MaxSLPips          = 100;      // 最大損切り幅(pips)
input double   ATRMultiplier      = 1.2;      // ATRベースSL倍率

input group "===== 利確設定（RR改善） ====="
input bool     UsePartialTP       = true;     // 分割利確を使用
input double   TP1_Percent        = 60;       // 第1利確のポジション比率(%)
input double   TP1_RR             = 2.0;      // 第1利確のRR比率
input double   TP2_RR             = 4.0;      // 第2利確のRR比率
input double   MinRRRatio         = 2.0;      // 最小RR比

input group "===== 建値決済設定 ====="
input bool     UseBreakeven       = true;     // 建値決済を使用
input double   BreakevenTriggerRR = 1.0;      // 建値移動のトリガーRR
input double   BreakevenPlusPips  = 5;        // 建値+αのpips

input group "===== トレーリングストップ設定 ====="
input bool     UseTrailingStop    = true;     // トレーリングストップを使用
input double   TrailingStartRR    = 2.0;      // トレーリング開始RR
input double   TrailingStepPips   = 15;       // トレーリングステップ(pips)

input group "===== PIVOT設定 ====="
input bool     UseDailyPivot      = true;     // デイリーPIVOTを使用

input group "===== Fibonacci設定 ====="
input bool     UseFibonacci       = true;     // Fibonacciを使用
input double   FibLevel1          = 0.5;      // Fibレベル1
input double   FibLevel2          = 0.618;    // Fibレベル2
input double   FibLevel3          = 0.786;    // Fibレベル3

input group "===== エントリー条件（厳格化） ====="
input int      MinConfluenceCount = 4;        // 最小コンフルエンス数
input int      MaxSpreadPips      = 20;       // 最大スプレッド(pips)
input bool     TradeOnlyNewBar    = true;     // 新しいバーでのみエントリー
input bool     UseTrendFilter     = true;     // トレンドフィルターを使用
input int      MaxDailyTrades     = 2;        // 1日の最大取引数

input group "===== 取引時間設定 ====="
input int      TradeStartHour     = 9;        // 取引開始時間(UTC)
input int      TradeEndHour       = 18;       // 取引終了時間(UTC)
input bool     AvoidNewsTime      = true;     // ニュース時間を避ける
input bool     AvoidFridayPM      = true;     // 金曜午後を避ける

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

// インジケータハンドル - メイン足
int handleSMA200, handleEMA100, handleEMA50, handleEMA20, handleATR, handleRSI;
// インジケータハンドル - H1
int handleEMA50_H1, handleEMA100_H1, handleRSI_H1;
// インジケータハンドル - H4
int handleEMA50_H4, handleEMA100_H4;

// 資金管理用
double g_initialBalance;
double g_dailyStartEquity;
double g_highWaterMark;
datetime g_lastDayCheck;
bool g_tradingAllowed;
bool g_ddWarningIssued;
int g_dailyTradeCount;

// トレード管理用
datetime g_lastBarTime;

// PIVOT値
double g_pivotPoint;
double g_resistance1, g_resistance2, g_resistance3;
double g_support1, g_support2, g_support3;

// Fibonacci値
double g_fibHigh, g_fibLow;
double g_fib500, g_fib618, g_fib786;

// S/Rレベル
double g_resistanceLevels[];
double g_supportLevels[];

// トレンド状態
int g_trendM5;   // M5トレンド
int g_trendH1;   // H1トレンド
int g_trendH4;   // H4トレンド

//+------------------------------------------------------------------+
//| エントリーシグナル構造体                                          |
//+------------------------------------------------------------------+
struct EntrySignal
{
   bool isValid;
   int direction;
   double entryPrice;
   double stopLoss;
   double takeProfit1;
   double takeProfit2;
   int confluenceCount;
   string confluenceList;
   double rrRatio;
   int signalStrength;  // シグナル強度 1-5
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // シンボル確認
   if(StringFind(Symbol(), "XAUUSD") < 0 && StringFind(Symbol(), "GOLD") < 0)
   {
      Print("警告: このEAはXAUUSD専用です");
   }

   if(!symInfo.Name(Symbol()))
   {
      Print("エラー: シンボル情報の取得に失敗");
      return INIT_FAILED;
   }

   // トレード設定
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // メイン足インジケータ
   handleSMA200 = iMA(Symbol(), MainTF, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   handleEMA100 = iMA(Symbol(), MainTF, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA50  = iMA(Symbol(), MainTF, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA20  = iMA(Symbol(), MainTF, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleATR    = iATR(Symbol(), MainTF, 14);
   handleRSI    = iRSI(Symbol(), MainTF, RSI_Period, PRICE_CLOSE);

   // H1インジケータ
   handleEMA50_H1  = iMA(Symbol(), HTF1, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA100_H1 = iMA(Symbol(), HTF1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI_H1    = iRSI(Symbol(), HTF1, RSI_Period, PRICE_CLOSE);

   // H4インジケータ
   handleEMA50_H4  = iMA(Symbol(), HTF2, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA100_H4 = iMA(Symbol(), HTF2, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   // ハンドル確認
   if(handleSMA200 == INVALID_HANDLE || handleEMA100 == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE || handleEMA50_H1 == INVALID_HANDLE)
   {
      Print("エラー: インジケータの初期化に失敗");
      return INIT_FAILED;
   }

   // 資金管理初期化
   g_initialBalance = (InitialBalance > 0) ? InitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_highWaterMark = g_initialBalance;
   g_lastDayCheck = 0;
   g_tradingAllowed = true;
   g_ddWarningIssued = false;
   g_dailyTradeCount = 0;

   ArrayResize(g_resistanceLevels, 0);
   ArrayResize(g_supportLevels, 0);

   CheckDailyReset();

   Print("========================================");
   Print("XAUUSD Fintokei EA v3.0 初期化完了");
   Print("MTF分析: M5 + H1 + H4");
   Print("初期資金: ", g_initialBalance);
   Print("1トレードリスク: ", DefaultRiskPercent, "%");
   Print("最小RR比: ", MinRRRatio);
   Print("========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleSMA200 != INVALID_HANDLE) IndicatorRelease(handleSMA200);
   if(handleEMA100 != INVALID_HANDLE) IndicatorRelease(handleEMA100);
   if(handleEMA50 != INVALID_HANDLE)  IndicatorRelease(handleEMA50);
   if(handleEMA20 != INVALID_HANDLE)  IndicatorRelease(handleEMA20);
   if(handleATR != INVALID_HANDLE)    IndicatorRelease(handleATR);
   if(handleRSI != INVALID_HANDLE)    IndicatorRelease(handleRSI);
   if(handleEMA50_H1 != INVALID_HANDLE)  IndicatorRelease(handleEMA50_H1);
   if(handleEMA100_H1 != INVALID_HANDLE) IndicatorRelease(handleEMA100_H1);
   if(handleRSI_H1 != INVALID_HANDLE)    IndicatorRelease(handleRSI_H1);
   if(handleEMA50_H4 != INVALID_HANDLE)  IndicatorRelease(handleEMA50_H4);
   if(handleEMA100_H4 != INVALID_HANDLE) IndicatorRelease(handleEMA100_H4);

   Print("XAUUSD Fintokei EA v3.0 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   symInfo.Refresh();
   symInfo.RefreshRates();

   CheckDailyReset();
   UpdateHighWaterMark();

   if(!CheckRiskManagement())
   {
      if(!g_tradingAllowed)
         CloseAllPositions("リスク制限超過");
      return;
   }

   ManageOpenPositions();

   if(TradeOnlyNewBar && !IsNewBar())
      return;

   if(!IsTradeTime())
      return;

   if(!CheckSpread())
      return;

   if(g_dailyTradeCount >= MaxDailyTrades)
      return;

   if(HasOpenPosition())
      return;

   // MTFトレンド分析
   AnalyzeMTFTrends();

   // 上位足トレンド一致チェック
   if(RequireHTFAlignment && !IsHTFAligned())
      return;

   CalculatePivotPoints();
   DetectSupportResistance();
   CalculateFibonacciLevels();

   EntrySignal signal = GetEntrySignal();

   if(signal.isValid && signal.confluenceCount >= MinConfluenceCount &&
      signal.rrRatio >= MinRRRatio && signal.signalStrength >= 3)
   {
      ExecuteEntry(signal);
   }
}

//+------------------------------------------------------------------+
//| MTFトレンド分析                                                   |
//+------------------------------------------------------------------+
void AnalyzeMTFTrends()
{
   // M5トレンド
   g_trendM5 = GetTrendDirection(handleEMA50, handleEMA100, handleSMA200, MainTF);

   // H1トレンド
   g_trendH1 = GetTrendDirectionHTF(handleEMA50_H1, handleEMA100_H1, HTF1);

   // H4トレンド
   g_trendH4 = GetTrendDirectionHTF(handleEMA50_H4, handleEMA100_H4, HTF2);
}

//+------------------------------------------------------------------+
//| トレンド方向取得（メイン足）                                      |
//+------------------------------------------------------------------+
int GetTrendDirection(int hEMA50, int hEMA100, int hSMA200, ENUM_TIMEFRAMES tf)
{
   double ema50[], ema100[], sma200[];
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema100, true);
   ArraySetAsSeries(sma200, true);

   if(CopyBuffer(hEMA50, 0, 0, 3, ema50) < 3) return 0;
   if(CopyBuffer(hEMA100, 0, 0, 3, ema100) < 3) return 0;
   if(CopyBuffer(hSMA200, 0, 0, 3, sma200) < 3) return 0;

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(Symbol(), tf, 0, 3, close) < 3) return 0;

   // 強い上昇トレンド
   if(ema50[0] > ema100[0] && ema100[0] > sma200[0] && close[0] > ema50[0])
      return 1;

   // 強い下降トレンド
   if(ema50[0] < ema100[0] && ema100[0] < sma200[0] && close[0] < ema50[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| トレンド方向取得（上位足）                                        |
//+------------------------------------------------------------------+
int GetTrendDirectionHTF(int hEMA50, int hEMA100, ENUM_TIMEFRAMES tf)
{
   double ema50[], ema100[];
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema100, true);

   if(CopyBuffer(hEMA50, 0, 0, 3, ema50) < 3) return 0;
   if(CopyBuffer(hEMA100, 0, 0, 3, ema100) < 3) return 0;

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(Symbol(), tf, 0, 3, close) < 3) return 0;

   // EMA50 > EMA100 かつ価格がEMA50より上 = 上昇
   if(ema50[0] > ema100[0] && close[0] > ema50[0])
      return 1;

   // EMA50 < EMA100 かつ価格がEMA50より下 = 下降
   if(ema50[0] < ema100[0] && close[0] < ema50[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| 上位足トレンド一致チェック                                        |
//+------------------------------------------------------------------+
bool IsHTFAligned()
{
   // H1とH4のトレンドが同じ方向
   if(g_trendH1 != 0 && g_trendH1 == g_trendH4)
      return true;

   // H4のみで判断（H1がレンジの場合）
   if(g_trendH4 != 0)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 日次リセットチェック                                              |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime);

   MqlDateTime lastCheck;
   TimeToStruct(g_lastDayCheck, lastCheck);

   if(currentTime.day != lastCheck.day || g_lastDayCheck == 0)
   {
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_lastDayCheck = TimeGMT();
      g_tradingAllowed = true;
      g_ddWarningIssued = false;
      g_dailyTradeCount = 0;

      Print("日次リセット: 開始時証拠金 = ", g_dailyStartEquity);
   }
}

//+------------------------------------------------------------------+
//| ハイウォーターマーク更新                                          |
//+------------------------------------------------------------------+
void UpdateHighWaterMark()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > g_highWaterMark)
      g_highWaterMark = currentEquity;
}

//+------------------------------------------------------------------+
//| リスク管理チェック                                                |
//+------------------------------------------------------------------+
bool CheckRiskManagement()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 日次損失チェック
   double dailyLossLimit = g_dailyStartEquity * (1.0 - DailyMaxLossPercent / 100.0);
   if(currentEquity <= dailyLossLimit)
   {
      if(g_tradingAllowed)
         Print("警告: 日次損失制限に達しました");
      g_tradingAllowed = false;
      return false;
   }

   // 全体損失チェック
   double totalLossLimit = g_initialBalance * (1.0 - TotalMaxLossPercent / 100.0);
   if(currentEquity <= totalLossLimit)
   {
      if(g_tradingAllowed)
         Print("警告: 全体損失制限に達しました");
      g_tradingAllowed = false;
      return false;
   }

   // ドローダウン監視
   double ddPercent = ((g_highWaterMark - currentEquity) / g_highWaterMark) * 100.0;

   if(ddPercent >= DDWarningPercent && !g_ddWarningIssued)
   {
      Print("警告: DD ", ddPercent, "%");
      g_ddWarningIssued = true;
   }

   if(ddPercent >= DDStopPercent)
   {
      if(g_tradingAllowed)
         Print("警告: DD停止レベル到達");
      g_tradingAllowed = false;
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 新しいバー判定                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol(), MainTF, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 取引時間チェック                                                  |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
   MqlDateTime ct;
   TimeToStruct(TimeGMT(), ct);

   // 金曜午後回避
   if(AvoidFridayPM && ct.day_of_week == 5 && ct.hour >= 14)
      return false;

   // ニュース時間回避
   if(AvoidNewsTime && ct.hour >= 12 && ct.hour <= 14)
      return false;

   // 取引時間チェック
   if(TradeStartHour <= TradeEndHour)
      return (ct.hour >= TradeStartHour && ct.hour < TradeEndHour);
   else
      return (ct.hour >= TradeStartHour || ct.hour < TradeEndHour);
}

//+------------------------------------------------------------------+
//| スプレッドチェック                                                |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   double spreadPips = symInfo.Spread() * symInfo.Point() / GetPipSize();
   return (spreadPips <= MaxSpreadPips);
}

//+------------------------------------------------------------------+
//| オープンポジション確認                                            |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == Symbol() && posInfo.Magic() == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 全ポジション決済                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == Symbol() && posInfo.Magic() == MagicNumber)
         {
            trade.PositionClose(posInfo.Ticket());
            Print("決済: ", reason);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PIVOTポイント計算                                                 |
//+------------------------------------------------------------------+
void CalculatePivotPoints()
{
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(CopyHigh(Symbol(), PERIOD_D1, 1, 1, high) < 1) return;
   if(CopyLow(Symbol(), PERIOD_D1, 1, 1, low) < 1) return;
   if(CopyClose(Symbol(), PERIOD_D1, 1, 1, close) < 1) return;

   g_pivotPoint = (high[0] + low[0] + close[0]) / 3.0;
   g_resistance1 = 2.0 * g_pivotPoint - low[0];
   g_support1 = 2.0 * g_pivotPoint - high[0];
   g_resistance2 = g_pivotPoint + (high[0] - low[0]);
   g_support2 = g_pivotPoint - (high[0] - low[0]);
}

//+------------------------------------------------------------------+
//| サポート・レジスタンス検出                                        |
//+------------------------------------------------------------------+
void DetectSupportResistance()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyHigh(Symbol(), MainTF, 0, SRLookback, high) < SRLookback) return;
   if(CopyLow(Symbol(), MainTF, 0, SRLookback, low) < SRLookback) return;

   ArrayResize(g_resistanceLevels, 0);
   ArrayResize(g_supportLevels, 0);

   double pipSize = GetPipSize();
   double zoneSize = SRZonePips * pipSize;

   // フラクタル検出（より厳格）
   for(int i = 4; i < SRLookback - 4; i++)
   {
      // スイング高値
      if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i-3] && high[i] > high[i-4] &&
         high[i] > high[i+1] && high[i] > high[i+2] && high[i] > high[i+3] && high[i] > high[i+4])
      {
         int touchCount = CountTouches(high, high[i], zoneSize, SRLookback);
         if(touchCount >= SRTouchCount)
            AddLevel(g_resistanceLevels, high[i], zoneSize);
      }

      // スイング安値
      if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i-3] && low[i] < low[i-4] &&
         low[i] < low[i+1] && low[i] < low[i+2] && low[i] < low[i+3] && low[i] < low[i+4])
      {
         int touchCount = CountTouches(low, low[i], zoneSize, SRLookback);
         if(touchCount >= SRTouchCount)
            AddLevel(g_supportLevels, low[i], zoneSize);
      }
   }
}

//+------------------------------------------------------------------+
//| タッチ回数カウント                                                |
//+------------------------------------------------------------------+
int CountTouches(double &prices[], double level, double zone, int lookback)
{
   int count = 0;
   for(int i = 0; i < lookback; i++)
   {
      if(MathAbs(prices[i] - level) < zone)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| レベル追加                                                        |
//+------------------------------------------------------------------+
void AddLevel(double &levels[], double price, double zone)
{
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(MathAbs(levels[i] - price) < zone)
         return;
   }

   int size = ArraySize(levels);
   ArrayResize(levels, size + 1);
   levels[size] = price;
}

//+------------------------------------------------------------------+
//| Fibonacciレベル計算                                              |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels()
{
   if(!UseFibonacci) return;

   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int lookback = 100;
   if(CopyHigh(Symbol(), MainTF, 0, lookback, high) < lookback) return;
   if(CopyLow(Symbol(), MainTF, 0, lookback, low) < lookback) return;

   g_fibHigh = high[ArrayMaximum(high, 0, lookback)];
   g_fibLow = low[ArrayMinimum(low, 0, lookback)];

   double range = g_fibHigh - g_fibLow;

   g_fib500 = g_fibHigh - range * FibLevel1;
   g_fib618 = g_fibHigh - range * FibLevel2;
   g_fib786 = g_fibHigh - range * FibLevel3;
}

//+------------------------------------------------------------------+
//| RSI値取得                                                        |
//+------------------------------------------------------------------+
double GetRSI(int handle, int shift = 0)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(handle, 0, shift, 3, rsi) < 3)
      return 50.0;
   return rsi[0];
}

//+------------------------------------------------------------------+
//| エントリーシグナル取得                                            |
//+------------------------------------------------------------------+
EntrySignal GetEntrySignal()
{
   EntrySignal signal;
   signal.isValid = false;
   signal.direction = 0;
   signal.confluenceCount = 0;
   signal.confluenceList = "";
   signal.rrRatio = 0;
   signal.signalStrength = 0;

   // MA値取得
   double sma200[], ema100[], ema50[], ema20[];
   ArraySetAsSeries(sma200, true);
   ArraySetAsSeries(ema100, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema20, true);

   if(CopyBuffer(handleSMA200, 0, 0, 5, sma200) < 5) return signal;
   if(CopyBuffer(handleEMA100, 0, 0, 5, ema100) < 5) return signal;
   if(CopyBuffer(handleEMA50, 0, 0, 5, ema50) < 5) return signal;
   if(CopyBuffer(handleEMA20, 0, 0, 5, ema20) < 5) return signal;

   // 価格データ取得
   double close[], open[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyClose(Symbol(), MainTF, 0, 5, close) < 5) return signal;
   if(CopyOpen(Symbol(), MainTF, 0, 5, open) < 5) return signal;
   if(CopyHigh(Symbol(), MainTF, 0, 5, high) < 5) return signal;
   if(CopyLow(Symbol(), MainTF, 0, 5, low) < 5) return signal;

   // ATR取得
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 3, atr) < 3) return signal;

   // RSI取得
   double rsiM5 = GetRSI(handleRSI);
   double rsiH1 = GetRSI(handleRSI_H1);

   double currentPrice = close[0];
   double pipSize = GetPipSize();
   double pullbackDistance = GranvillePullbackPips * pipSize;
   double touchDistance = GranvilleTouchPips * pipSize;

   int buyConfluence = 0, sellConfluence = 0;
   string buyList = "", sellList = "";
   int buyStrength = 0, sellStrength = 0;

   //--- 1. MTFトレンド確認（必須・高スコア）---
   if(g_trendH4 == 1)
   {
      buyConfluence += 2;
      buyStrength += 2;
      buyList += "H4上昇 ";
   }
   else if(g_trendH4 == -1)
   {
      sellConfluence += 2;
      sellStrength += 2;
      sellList += "H4下降 ";
   }

   if(g_trendH1 == 1)
   {
      buyConfluence++;
      buyStrength++;
      buyList += "H1上昇 ";
   }
   else if(g_trendH1 == -1)
   {
      sellConfluence++;
      sellStrength++;
      sellList += "H1下降 ";
   }

   //--- 2. RSIフィルター ---
   if(UseRSIFilter)
   {
      // 買い: RSI < 売られすぎ && H1 RSIも低め
      if(rsiM5 < RSI_OversoldLevel && rsiH1 < 50)
      {
         buyConfluence++;
         buyStrength++;
         buyList += "RSI売られすぎ ";
      }
      // 売り: RSI > 買われすぎ && H1 RSIも高め
      if(rsiM5 > RSI_OverboughtLevel && rsiH1 > 50)
      {
         sellConfluence++;
         sellStrength++;
         sellList += "RSI買われすぎ ";
      }
   }

   //--- 3. グランビルの法則 ---
   // 200SMAへの引き付け（買い）
   if(currentPrice > sma200[0] && (currentPrice - sma200[0]) < pullbackDistance)
   {
      if(close[1] > close[2] && low[1] <= sma200[1] + touchDistance && close[1] > sma200[1])
      {
         buyConfluence++;
         buyStrength++;
         buyList += "グランビル200SMA ";
      }
   }

   // 100EMAへの引き付け（買い）
   if(currentPrice > ema100[0] && (currentPrice - ema100[0]) < pullbackDistance)
   {
      if(close[1] > close[2] && low[1] <= ema100[1] + touchDistance && close[1] > ema100[1])
      {
         buyConfluence++;
         buyStrength++;
         buyList += "グランビル100EMA ";
      }
   }

   // 200SMAへの引き付け（売り）
   if(currentPrice < sma200[0] && (sma200[0] - currentPrice) < pullbackDistance)
   {
      if(close[1] < close[2] && high[1] >= sma200[1] - touchDistance && close[1] < sma200[1])
      {
         sellConfluence++;
         sellStrength++;
         sellList += "グランビル200SMA ";
      }
   }

   // 100EMAへの引き付け（売り）
   if(currentPrice < ema100[0] && (ema100[0] - currentPrice) < pullbackDistance)
   {
      if(close[1] < close[2] && high[1] >= ema100[1] - touchDistance && close[1] < ema100[1])
      {
         sellConfluence++;
         sellStrength++;
         sellList += "グランビル100EMA ";
      }
   }

   //--- 4. プライスアクション ---
   double srZone = SRZonePips * pipSize;

   if(IsBullishPinBar(open[1], high[1], low[1], close[1]) && IsNearSupport(low[1], srZone))
   {
      buyConfluence++;
      buyStrength++;
      buyList += "ピンバー ";
   }
   if(IsBearishPinBar(open[1], high[1], low[1], close[1]) && IsNearResistance(high[1], srZone))
   {
      sellConfluence++;
      sellStrength++;
      sellList += "ピンバー ";
   }

   if(IsBullishEngulfing(open[1], close[1], open[2], close[2]) && IsNearSupport(low[1], srZone))
   {
      buyConfluence++;
      buyStrength++;
      buyList += "包み足 ";
   }
   if(IsBearishEngulfing(open[1], close[1], open[2], close[2]) && IsNearResistance(high[1], srZone))
   {
      sellConfluence++;
      sellStrength++;
      sellList += "包み足 ";
   }

   //--- 5. S/Rレベル ---
   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(MathAbs(low[1] - g_supportLevels[i]) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "SR反発 ";
         break;
      }
   }

   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(MathAbs(high[1] - g_resistanceLevels[i]) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "SR反発 ";
         break;
      }
   }

   //--- 6. PIVOTチェック ---
   if(UseDailyPivot)
   {
      if(MathAbs(low[1] - g_support1) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "PIVOT S1 ";
      }
      if(MathAbs(low[1] - g_pivotPoint) < srZone && close[1] > open[1] && g_trendH1 >= 0)
      {
         buyConfluence++;
         buyList += "PIVOT PP ";
      }
      if(MathAbs(high[1] - g_resistance1) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "PIVOT R1 ";
      }
      if(MathAbs(high[1] - g_pivotPoint) < srZone && close[1] < open[1] && g_trendH1 <= 0)
      {
         sellConfluence++;
         sellList += "PIVOT PP ";
      }
   }

   //--- 7. Fibonacci ---
   if(UseFibonacci)
   {
      if(MathAbs(low[1] - g_fib618) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib61.8 ";
      }
      if(MathAbs(low[1] - g_fib786) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib78.6 ";
      }
   }

   //--- シグナル決定 ---
   // トレンド方向に一致するシグナルのみ
   if(buyConfluence >= MinConfluenceCount && g_trendH4 >= 0 && buyConfluence > sellConfluence)
   {
      signal.isValid = true;
      signal.direction = 1;
      signal.confluenceCount = buyConfluence;
      signal.confluenceList = buyList;
      signal.signalStrength = buyStrength;
      signal.entryPrice = symInfo.Ask();
      signal.stopLoss = CalculateStopLoss(1, atr[0]);
      CalculateTakeProfits(signal);
      signal.rrRatio = CalculateRRRatio(signal);
   }
   else if(sellConfluence >= MinConfluenceCount && g_trendH4 <= 0 && sellConfluence > buyConfluence)
   {
      signal.isValid = true;
      signal.direction = -1;
      signal.confluenceCount = sellConfluence;
      signal.confluenceList = sellList;
      signal.signalStrength = sellStrength;
      signal.entryPrice = symInfo.Bid();
      signal.stopLoss = CalculateStopLoss(-1, atr[0]);
      CalculateTakeProfits(signal);
      signal.rrRatio = CalculateRRRatio(signal);
   }

   return signal;
}

//+------------------------------------------------------------------+
//| サポート付近判定                                                  |
//+------------------------------------------------------------------+
bool IsNearSupport(double price, double zone)
{
   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(MathAbs(price - g_supportLevels[i]) < zone)
         return true;
   }
   if(UseDailyPivot)
   {
      if(MathAbs(price - g_support1) < zone || MathAbs(price - g_pivotPoint) < zone)
         return true;
   }
   if(UseFibonacci)
   {
      if(MathAbs(price - g_fib618) < zone || MathAbs(price - g_fib786) < zone)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| レジスタンス付近判定                                              |
//+------------------------------------------------------------------+
bool IsNearResistance(double price, double zone)
{
   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(MathAbs(price - g_resistanceLevels[i]) < zone)
         return true;
   }
   if(UseDailyPivot)
   {
      if(MathAbs(price - g_resistance1) < zone || MathAbs(price - g_pivotPoint) < zone)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 強気ピンバー判定                                                  |
//+------------------------------------------------------------------+
bool IsBullishPinBar(double open, double high, double low, double close)
{
   double body = MathAbs(close - open);
   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);
   double totalRange = high - low;

   if(totalRange == 0 || body == 0) return false;

   return (lowerWick >= body * PinBarRatio * 2.5 &&
           upperWick < lowerWick * 0.25 &&
           close >= open &&
           body < totalRange * 0.25);
}

//+------------------------------------------------------------------+
//| 弱気ピンバー判定                                                  |
//+------------------------------------------------------------------+
bool IsBearishPinBar(double open, double high, double low, double close)
{
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalRange = high - low;

   if(totalRange == 0 || body == 0) return false;

   return (upperWick >= body * PinBarRatio * 2.5 &&
           lowerWick < upperWick * 0.25 &&
           close <= open &&
           body < totalRange * 0.25);
}

//+------------------------------------------------------------------+
//| 強気包み足判定                                                    |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(double open1, double close1, double open2, double close2)
{
   if(close2 >= open2) return false;
   if(close1 <= open1) return false;

   double prevBody = MathAbs(close2 - open2);
   double currBody = MathAbs(close1 - open1);

   return (currBody >= prevBody * EngulfingMinRatio &&
           close1 > open2 && open1 < close2);
}

//+------------------------------------------------------------------+
//| 弱気包み足判定                                                    |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(double open1, double close1, double open2, double close2)
{
   if(close2 <= open2) return false;
   if(close1 >= open1) return false;

   double prevBody = MathAbs(close2 - open2);
   double currBody = MathAbs(close1 - open1);

   return (currBody >= prevBody * EngulfingMinRatio &&
           close1 < open2 && open1 > close2);
}

//+------------------------------------------------------------------+
//| 損切りライン計算                                                  |
//+------------------------------------------------------------------+
double CalculateStopLoss(int direction, double atrValue)
{
   double low[], high[];
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(high, true);

   if(CopyLow(Symbol(), MainTF, 0, SwingLookback, low) < SwingLookback) return 0;
   if(CopyHigh(Symbol(), MainTF, 0, SwingLookback, high) < SwingLookback) return 0;

   double sl = 0;
   double pipSize = GetPipSize();
   double maxSL = MaxSLPips * pipSize;
   double atrSL = atrValue * ATRMultiplier;

   if(direction == 1)
   {
      double swingLow = low[ArrayMinimum(low, 0, SwingLookback)];
      double buffer = swingLow * (SLBufferPercent / 100.0);
      sl = swingLow - buffer;

      double entryPrice = symInfo.Ask();
      double swingDist = entryPrice - sl;

      // 最小の損切りを採用
      if(swingDist > maxSL)
         sl = entryPrice - maxSL;
      if(swingDist > atrSL)
         sl = MathMax(sl, entryPrice - atrSL);
   }
   else
   {
      double swingHigh = high[ArrayMaximum(high, 0, SwingLookback)];
      double buffer = swingHigh * (SLBufferPercent / 100.0);
      sl = swingHigh + buffer;

      double entryPrice = symInfo.Bid();
      double swingDist = sl - entryPrice;

      if(swingDist > maxSL)
         sl = entryPrice + maxSL;
      if(swingDist > atrSL)
         sl = MathMin(sl, entryPrice + atrSL);
   }

   return NormalizeDouble(sl, symInfo.Digits());
}

//+------------------------------------------------------------------+
//| 利確ライン計算                                                    |
//+------------------------------------------------------------------+
void CalculateTakeProfits(EntrySignal &signal)
{
   double riskDistance = MathAbs(signal.entryPrice - signal.stopLoss);

   if(signal.direction == 1)
   {
      signal.takeProfit1 = signal.entryPrice + riskDistance * TP1_RR;
      signal.takeProfit2 = signal.entryPrice + riskDistance * TP2_RR;
   }
   else
   {
      signal.takeProfit1 = signal.entryPrice - riskDistance * TP1_RR;
      signal.takeProfit2 = signal.entryPrice - riskDistance * TP2_RR;
   }

   signal.takeProfit1 = NormalizeDouble(signal.takeProfit1, symInfo.Digits());
   signal.takeProfit2 = NormalizeDouble(signal.takeProfit2, symInfo.Digits());
}

//+------------------------------------------------------------------+
//| RR比計算                                                          |
//+------------------------------------------------------------------+
double CalculateRRRatio(EntrySignal &signal)
{
   double risk = MathAbs(signal.entryPrice - signal.stopLoss);
   double reward = MathAbs(signal.takeProfit1 - signal.entryPrice);
   if(risk == 0) return 0;
   return reward / risk;
}

//+------------------------------------------------------------------+
//| エントリー実行                                                    |
//+------------------------------------------------------------------+
void ExecuteEntry(EntrySignal &signal)
{
   if(signal.rrRatio < MinRRRatio)
   {
      Print("RR比不足: ", signal.rrRatio);
      return;
   }

   double lots = CalculateLotSize(signal.entryPrice, signal.stopLoss);
   if(lots <= 0) return;

   if(!ValidateRisk(lots, signal.entryPrice, signal.stopLoss))
      return;

   bool result = false;

   if(signal.direction == 1)
   {
      if(UsePartialTP)
      {
         double lot1 = NormalizeLotSize(lots * (TP1_Percent / 100.0));
         double lot2 = NormalizeLotSize(lots - lot1);
         if(lot1 > 0) result = trade.Buy(lot1, Symbol(), 0, signal.stopLoss, signal.takeProfit1, "v3_TP1");
         if(lot2 > 0) result = trade.Buy(lot2, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "v3_TP2") || result;
      }
      else
         result = trade.Buy(lots, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "v3");
   }
   else
   {
      if(UsePartialTP)
      {
         double lot1 = NormalizeLotSize(lots * (TP1_Percent / 100.0));
         double lot2 = NormalizeLotSize(lots - lot1);
         if(lot1 > 0) result = trade.Sell(lot1, Symbol(), 0, signal.stopLoss, signal.takeProfit1, "v3_TP1");
         if(lot2 > 0) result = trade.Sell(lot2, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "v3_TP2") || result;
      }
      else
         result = trade.Sell(lots, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "v3");
   }

   if(result)
   {
      g_dailyTradeCount++;
      Print("========================================");
      Print("ENTRY: ", (signal.direction == 1 ? "BUY" : "SELL"));
      Print("Confluence: ", signal.confluenceCount, " Strength: ", signal.signalStrength);
      Print("RR: ", signal.rrRatio, " ", signal.confluenceList);
      Print("Trend H4:", g_trendH4, " H1:", g_trendH1);
      Print("========================================");
   }
}

//+------------------------------------------------------------------+
//| ロットサイズ計算                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (DefaultRiskPercent / 100.0);

   double maxRiskAmount = accountBalance * (MaxRiskPerTrade / 100.0);
   if(riskAmount > maxRiskAmount)
      riskAmount = maxRiskAmount;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossLimit = g_dailyStartEquity * (DailyMaxLossPercent / 100.0);
   double usedDailyLoss = g_dailyStartEquity - currentEquity;
   double remainingDailyRisk = dailyLossLimit - usedDailyLoss;

   if(riskAmount > remainingDailyRisk * 0.4)
      riskAmount = remainingDailyRisk * 0.4;

   if(riskAmount <= 0)
      return 0;

   double slDistance = MathAbs(entryPrice - stopLoss);
   double pipSize = GetPipSize();
   double slPips = slDistance / pipSize;

   double lossPerLot = CalculateLossPerLot(slPips);
   if(lossPerLot <= 0)
      return 0;

   return NormalizeLotSize(riskAmount / lossPerLot);
}

//+------------------------------------------------------------------+
//| 1ロットあたりの損失計算                                          |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips)
{
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   return (slPips * pipSize / tickSize) * tickValue;
}

//+------------------------------------------------------------------+
//| ロットサイズ正規化                                                |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;

   return lots;
}

//+------------------------------------------------------------------+
//| Pipサイズ取得                                                    |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(digits == 2 || digits == 3)
      return point * 10.0;
   return point;
}

//+------------------------------------------------------------------+
//| リスク検証                                                        |
//+------------------------------------------------------------------+
bool ValidateRisk(double lots, double entryPrice, double stopLoss)
{
   double slDistance = MathAbs(entryPrice - stopLoss);
   double pipSize = GetPipSize();
   double slPips = slDistance / pipSize;

   double potentialLoss = CalculateLossPerLot(slPips) * lots;
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   double riskPercent = (potentialLoss / accountBalance) * 100.0;
   if(riskPercent > MaxRiskPerTrade)
      return false;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double projectedEquity = currentEquity - potentialLoss;
   double dailyLossLimit = g_dailyStartEquity * (1.0 - DailyMaxLossPercent / 100.0);

   if(projectedEquity < dailyLossLimit)
      return false;

   double totalLossLimit = g_initialBalance * (1.0 - TotalMaxLossPercent / 100.0);
   if(projectedEquity < totalLossLimit)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| オープンポジション管理                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != MagicNumber) continue;

      if(UseBreakeven) CheckBreakeven(posInfo);
      if(UseTrailingStop) CheckTrailingStop(posInfo);
      CheckEMAExit(posInfo);
   }
}

//+------------------------------------------------------------------+
//| 建値決済チェック                                                  |
//+------------------------------------------------------------------+
void CheckBreakeven(CPositionInfo &pos)
{
   double openPrice = pos.PriceOpen();
   double currentSL = pos.StopLoss();
   double currentPrice = (pos.PositionType() == POSITION_TYPE_BUY) ? symInfo.Bid() : symInfo.Ask();
   double pipSize = GetPipSize();

   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      if(currentSL >= openPrice) return;

      double triggerDist = MathAbs(openPrice - pos.StopLoss()) * BreakevenTriggerRR;
      if(currentPrice >= openPrice + triggerDist)
      {
         double newSL = openPrice + (BreakevenPlusPips * pipSize);
         newSL = NormalizeDouble(newSL, symInfo.Digits());
         if(newSL > currentSL)
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
      }
   }
   else
   {
      if(currentSL <= openPrice && currentSL > 0) return;

      double triggerDist = MathAbs(pos.StopLoss() - openPrice) * BreakevenTriggerRR;
      if(currentPrice <= openPrice - triggerDist)
      {
         double newSL = openPrice - (BreakevenPlusPips * pipSize);
         newSL = NormalizeDouble(newSL, symInfo.Digits());
         if(newSL < currentSL || currentSL == 0)
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップチェック                                      |
//+------------------------------------------------------------------+
void CheckTrailingStop(CPositionInfo &pos)
{
   double openPrice = pos.PriceOpen();
   double currentSL = pos.StopLoss();
   double currentPrice = (pos.PositionType() == POSITION_TYPE_BUY) ? symInfo.Bid() : symInfo.Ask();
   double pipSize = GetPipSize();
   double trailingStep = TrailingStepPips * pipSize;

   double initialRisk = MathAbs(openPrice - currentSL);
   double trailingStartDist = initialRisk * TrailingStartRR;

   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      if(currentPrice >= openPrice + trailingStartDist)
      {
         double newSL = currentPrice - trailingStep;
         newSL = NormalizeDouble(newSL, symInfo.Digits());
         if(newSL > currentSL)
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
      }
   }
   else
   {
      if(currentPrice <= openPrice - trailingStartDist)
      {
         double newSL = currentPrice + trailingStep;
         newSL = NormalizeDouble(newSL, symInfo.Digits());
         if(newSL < currentSL || currentSL == 0)
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| EMA実体抜けチェック                                              |
//+------------------------------------------------------------------+
void CheckEMAExit(CPositionInfo &pos)
{
   double ema20[];
   ArraySetAsSeries(ema20, true);
   if(CopyBuffer(handleEMA20, 0, 0, 2, ema20) < 2) return;

   double close[], open[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   if(CopyClose(Symbol(), MainTF, 0, 2, close) < 2) return;
   if(CopyOpen(Symbol(), MainTF, 0, 2, open) < 2) return;

   if(pos.Profit() <= 0) return;

   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      if(close[1] < ema20[1] && open[1] > ema20[1])
      {
         if(symInfo.Bid() < ema20[0])
         {
            trade.PositionClose(pos.Ticket());
            Print("EMA20下抜け決済");
         }
      }
   }
   else
   {
      if(close[1] > ema20[1] && open[1] < ema20[1])
      {
         if(symInfo.Ask() > ema20[0])
         {
            trade.PositionClose(pos.Ticket());
            Print("EMA20上抜け決済");
         }
      }
   }
}
//+------------------------------------------------------------------+
