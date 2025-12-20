//+------------------------------------------------------------------+
//|                                       XAUUSD_Fintokei_EA_v2.mq5 |
//|                        XAUUSD専用 Fintokeiチャレンジ対応EA v2    |
//|                        改善版：リスク管理強化・RR比改善          |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Fintokei EA v2"
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
input double   InitialBalance     = 0;        // 初期資金（0=自動取得）
input int      MagicNumber        = 123456;   // マジックナンバー
input string   TradeSymbol        = "XAUUSD"; // 取引通貨ペア
input ENUM_TIMEFRAMES MainTF      = PERIOD_M5;// メイン時間足

input group "===== Fintokei リスク管理（強化版） ====="
input double   DailyMaxLossPercent   = 4.0;   // 1日の最大損失率(%) ※余裕を持たせて4%
input double   TotalMaxLossPercent   = 8.0;   // 全体の最大損失率(%) ※余裕を持たせて8%
input double   MaxRiskPerTrade       = 1.5;   // 1トレードの最大リスク(%) ※縮小
input double   DefaultRiskPercent    = 1.0;   // デフォルトリスク(%) ※縮小
input double   DDWarningPercent      = 6.0;   // ドローダウン警告レベル(%)
input double   DDStopPercent         = 8.0;   // ドローダウン停止レベル(%)

input group "===== 移動平均線設定 ====="
input int      SMA_Period         = 200;      // 長期SMA期間
input int      EMA_Period         = 100;      // 中期EMA期間
input int      FastEMA_Period     = 20;       // 短期EMA期間（利確用）
input int      TrendEMA_Period    = 50;       // トレンド判定EMA期間

input group "===== グランビル設定 ====="
input double   GranvillePullbackPips = 30;    // MAへの引き付け距離(pips) ※縮小
input double   GranvilleTouchPips    = 15;    // MAタッチ判定距離(pips) ※縮小

input group "===== プライスアクション設定 ====="
input double   PinBarRatio        = 0.65;     // ピンバーの芯/実体比率 ※厳格化
input double   EngulfingMinRatio  = 1.3;      // 包み足の最小比率 ※厳格化

input group "===== 水平線設定 ====="
input int      SRLookback         = 100;      // S/R検出のルックバック期間 ※拡大
input double   SRZonePips         = 15;       // S/Rゾーン幅(pips) ※縮小
input int      SRTouchCount       = 3;        // S/R確認に必要なタッチ数 ※増加

input group "===== 損切り設定（改善版） ====="
input double   SLBufferPercent    = 0.2;      // 損切りバッファ(%) ※縮小
input int      SwingLookback      = 10;       // スイング高値/安値ルックバック ※縮小
input double   MaxSLPips          = 150;      // 最大損切り幅(pips) ※制限追加
input double   ATRMultiplier      = 1.5;      // ATRベースSL倍率

input group "===== 利確設定（改善版） ====="
input bool     UsePartialTP       = true;     // 分割利確を使用
input double   TP1_Percent        = 50;       // 第1利確のポジション比率(%)
input double   TP1_RR             = 1.5;      // 第1利確のRR比率 ※改善
input double   TP2_RR             = 3.0;      // 第2利確のRR比率 ※改善
input double   MinRRRatio         = 1.5;      // 最小RR比（これ以下はエントリーしない）

input group "===== 建値決済設定 ====="
input bool     UseBreakeven       = true;     // 建値決済を使用
input double   BreakevenTriggerRR = 0.8;      // 建値移動のトリガーRR ※早期化
input double   BreakevenPlusPips  = 3;        // 建値+αのpips

input group "===== トレーリングストップ設定 ====="
input bool     UseTrailingStop    = true;     // トレーリングストップを使用
input double   TrailingStartRR    = 1.5;      // トレーリング開始RR
input double   TrailingStepPips   = 20;       // トレーリングステップ(pips)

input group "===== PIVOT設定 ====="
input bool     UseDailyPivot      = true;     // デイリーPIVOTを使用
input bool     UseWeeklyPivot     = false;    // ウィークリーPIVOTを使用

input group "===== Fibonacci設定 ====="
input bool     UseFibonacci       = true;     // Fibonacciを使用
input double   FibLevel1          = 0.382;    // Fibレベル1
input double   FibLevel2          = 0.5;      // Fibレベル2
input double   FibLevel3          = 0.618;    // Fibレベル3

input group "===== エントリー条件（厳格化） ====="
input int      MinConfluenceCount = 3;        // 最小コンフルエンス数 ※増加
input int      MaxSpreadPips      = 25;       // 最大スプレッド(pips) ※縮小
input bool     TradeOnlyNewBar    = true;     // 新しいバーでのみエントリー
input bool     UseTrendFilter     = true;     // トレンドフィルターを使用
input int      MaxDailyTrades     = 3;        // 1日の最大取引数

input group "===== 取引時間設定 ====="
input int      TradeStartHour     = 8;        // 取引開始時間(UTC) ※絞り込み
input int      TradeEndHour       = 20;       // 取引終了時間(UTC) ※絞り込み
input bool     AvoidNewsTime      = true;     // ニュース時間を避ける

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   accInfo;
CSymbolInfo    symInfo;

// インジケータハンドル
int handleSMA200;
int handleEMA100;
int handleEMA50;
int handleEMA20;
int handleATR;

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
int g_totalSignals;

// PIVOT値
double g_pivotPoint;
double g_resistance1, g_resistance2, g_resistance3;
double g_support1, g_support2, g_support3;

// Fibonacci値
double g_fibHigh, g_fibLow;
double g_fib382, g_fib500, g_fib618;

// S/Rレベル
double g_resistanceLevels[];
double g_supportLevels[];

// トレンド状態
int g_trendDirection; // 1=上昇, -1=下降, 0=レンジ

//+------------------------------------------------------------------+
//| エントリーシグナル構造体                                          |
//+------------------------------------------------------------------+
struct EntrySignal
{
   bool isValid;
   int direction;        // 1=Buy, -1=Sell
   double entryPrice;
   double stopLoss;
   double takeProfit1;
   double takeProfit2;
   int confluenceCount;
   string confluenceList;
   double rrRatio;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // シンボル確認
   if(StringFind(Symbol(), "XAUUSD") < 0 && StringFind(Symbol(), "GOLD") < 0)
   {
      Print("警告: このEAはXAUUSD専用です。現在のシンボル: ", Symbol());
   }

   // シンボル情報初期化
   if(!symInfo.Name(Symbol()))
   {
      Print("エラー: シンボル情報の取得に失敗しました");
      return INIT_FAILED;
   }

   // トレード設定
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // インジケータ初期化
   handleSMA200 = iMA(Symbol(), MainTF, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   handleEMA100 = iMA(Symbol(), MainTF, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA50  = iMA(Symbol(), MainTF, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA20  = iMA(Symbol(), MainTF, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleATR    = iATR(Symbol(), MainTF, 14);

   if(handleSMA200 == INVALID_HANDLE || handleEMA100 == INVALID_HANDLE ||
      handleEMA50 == INVALID_HANDLE || handleEMA20 == INVALID_HANDLE ||
      handleATR == INVALID_HANDLE)
   {
      Print("エラー: インジケータの初期化に失敗しました");
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

   // 配列初期化
   ArrayResize(g_resistanceLevels, 0);
   ArrayResize(g_supportLevels, 0);

   // 日次チェック
   CheckDailyReset();

   Print("========================================");
   Print("XAUUSD Fintokei EA v2.0 初期化完了");
   Print("========================================");
   Print("初期資金: ", g_initialBalance);
   Print("1日最大損失: ", DailyMaxLossPercent, "%");
   Print("全体最大損失: ", TotalMaxLossPercent, "%");
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
   // インジケータハンドル解放
   if(handleSMA200 != INVALID_HANDLE) IndicatorRelease(handleSMA200);
   if(handleEMA100 != INVALID_HANDLE) IndicatorRelease(handleEMA100);
   if(handleEMA50 != INVALID_HANDLE)  IndicatorRelease(handleEMA50);
   if(handleEMA20 != INVALID_HANDLE)  IndicatorRelease(handleEMA20);
   if(handleATR != INVALID_HANDLE)    IndicatorRelease(handleATR);

   Print("XAUUSD Fintokei EA v2.0 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // シンボル情報更新
   symInfo.Refresh();
   symInfo.RefreshRates();

   // 日次リセットチェック（UTC 0時）
   CheckDailyReset();

   // ハイウォーターマーク更新
   UpdateHighWaterMark();

   // リスク管理チェック（強化版）
   if(!CheckRiskManagementEnhanced())
   {
      if(!g_tradingAllowed)
      {
         CloseAllPositions("リスク制限超過");
      }
      return;
   }

   // 既存ポジション管理
   ManageOpenPositions();

   // 新しいバーでのみエントリー判定
   if(TradeOnlyNewBar && !IsNewBar())
      return;

   // 取引時間チェック
   if(!IsTradeTime())
      return;

   // スプレッドチェック
   if(!CheckSpread())
      return;

   // 1日の最大取引数チェック
   if(g_dailyTradeCount >= MaxDailyTrades)
   {
      return;
   }

   // 既にポジションがある場合は新規エントリーしない
   if(HasOpenPosition())
      return;

   // トレンド判定
   DetermineTrend();

   // PIVOTポイント計算
   CalculatePivotPoints();

   // S/Rレベル検出
   DetectSupportResistance();

   // Fibonacciレベル計算
   CalculateFibonacciLevels();

   // エントリーシグナル取得
   EntrySignal signal = GetEntrySignal();

   // シグナルが有効でRR比が十分な場合のみエントリー
   if(signal.isValid && signal.confluenceCount >= MinConfluenceCount && signal.rrRatio >= MinRRRatio)
   {
      ExecuteEntry(signal);
   }
}

//+------------------------------------------------------------------+
//| 日次リセットチェック（UTC 0時）                                   |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime);

   MqlDateTime lastCheck;
   TimeToStruct(g_lastDayCheck, lastCheck);

   // 日付が変わった場合（UTC 0時）
   if(currentTime.day != lastCheck.day || g_lastDayCheck == 0)
   {
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_lastDayCheck = TimeGMT();
      g_tradingAllowed = true;
      g_ddWarningIssued = false;
      g_dailyTradeCount = 0;

      Print("========================================");
      Print("日次リセット: ", TimeToString(TimeGMT(), TIME_DATE));
      Print("開始時有効証拠金: ", g_dailyStartEquity);
      Print("========================================");
   }
}

//+------------------------------------------------------------------+
//| ハイウォーターマーク更新                                          |
//+------------------------------------------------------------------+
void UpdateHighWaterMark()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > g_highWaterMark)
   {
      g_highWaterMark = currentEquity;
   }
}

//+------------------------------------------------------------------+
//| リスク管理チェック（強化版）                                      |
//+------------------------------------------------------------------+
bool CheckRiskManagementEnhanced()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 1. 1日の損失チェック（より厳格に4%）
   double dailyLossLimit = g_dailyStartEquity * (1.0 - DailyMaxLossPercent / 100.0);
   double dailyLossPercent = ((g_dailyStartEquity - currentEquity) / g_dailyStartEquity) * 100.0;

   if(currentEquity <= dailyLossLimit)
   {
      if(g_tradingAllowed)
      {
         Print("========================================");
         Print("警告: 1日の損失制限(", DailyMaxLossPercent, "%)に達しました！");
         Print("開始時証拠金: ", g_dailyStartEquity);
         Print("現在の証拠金: ", currentEquity);
         Print("取引を停止します。");
         Print("========================================");
      }
      g_tradingAllowed = false;
      return false;
   }

   // 2. 全体の損失チェック（より厳格に8%）
   double totalLossLimit = g_initialBalance * (1.0 - TotalMaxLossPercent / 100.0);
   double totalLossPercent = ((g_initialBalance - currentEquity) / g_initialBalance) * 100.0;

   if(currentEquity <= totalLossLimit)
   {
      if(g_tradingAllowed)
      {
         Print("========================================");
         Print("警告: 全体の損失制限(", TotalMaxLossPercent, "%)に達しました！");
         Print("初期資金: ", g_initialBalance);
         Print("現在の証拠金: ", currentEquity);
         Print("取引を停止します。");
         Print("========================================");
      }
      g_tradingAllowed = false;
      return false;
   }

   // 3. ドローダウン監視
   double ddPercent = ((g_highWaterMark - currentEquity) / g_highWaterMark) * 100.0;

   // 警告レベル
   if(ddPercent >= DDWarningPercent && !g_ddWarningIssued)
   {
      Print("警告: ドローダウンが", DDWarningPercent, "%に達しました。現在: ", ddPercent, "%");
      g_ddWarningIssued = true;
   }

   // 停止レベル
   if(ddPercent >= DDStopPercent)
   {
      if(g_tradingAllowed)
      {
         Print("========================================");
         Print("警告: ドローダウンが", DDStopPercent, "%に達しました！");
         Print("ハイウォーターマーク: ", g_highWaterMark);
         Print("現在の証拠金: ", currentEquity);
         Print("取引を停止します。");
         Print("========================================");
      }
      g_tradingAllowed = false;
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| トレンド判定                                                      |
//+------------------------------------------------------------------+
void DetermineTrend()
{
   double ema50[], ema100[], sma200[];
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema100, true);
   ArraySetAsSeries(sma200, true);

   if(CopyBuffer(handleEMA50, 0, 0, 3, ema50) < 3) return;
   if(CopyBuffer(handleEMA100, 0, 0, 3, ema100) < 3) return;
   if(CopyBuffer(handleSMA200, 0, 0, 3, sma200) < 3) return;

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(Symbol(), MainTF, 0, 3, close) < 3) return;

   // トレンド判定: EMA50 > EMA100 > SMA200 = 上昇トレンド
   if(ema50[0] > ema100[0] && ema100[0] > sma200[0] && close[0] > ema50[0])
   {
      g_trendDirection = 1;  // 上昇トレンド
   }
   else if(ema50[0] < ema100[0] && ema100[0] < sma200[0] && close[0] < ema50[0])
   {
      g_trendDirection = -1; // 下降トレンド
   }
   else
   {
      g_trendDirection = 0;  // レンジ
   }
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
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime);

   // ニュース時間回避（UTC 12:30-14:30 米国重要指標）
   if(AvoidNewsTime)
   {
      if(currentTime.hour >= 12 && currentTime.hour <= 14)
      {
         if(currentTime.day_of_week >= 1 && currentTime.day_of_week <= 5)
         {
            return false;
         }
      }
   }

   if(TradeStartHour <= TradeEndHour)
   {
      return (currentTime.hour >= TradeStartHour && currentTime.hour < TradeEndHour);
   }
   else
   {
      return (currentTime.hour >= TradeStartHour || currentTime.hour < TradeEndHour);
   }
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
         {
            return true;
         }
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
            Print("ポジション決済: ", reason, " チケット: ", posInfo.Ticket());
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

   double prevHigh = high[0];
   double prevLow = low[0];
   double prevClose = close[0];

   g_pivotPoint = (prevHigh + prevLow + prevClose) / 3.0;

   g_resistance1 = 2.0 * g_pivotPoint - prevLow;
   g_support1 = 2.0 * g_pivotPoint - prevHigh;

   g_resistance2 = g_pivotPoint + (prevHigh - prevLow);
   g_support2 = g_pivotPoint - (prevHigh - prevLow);

   g_resistance3 = prevHigh + 2.0 * (g_pivotPoint - prevLow);
   g_support3 = prevLow - 2.0 * (prevHigh - g_pivotPoint);
}

//+------------------------------------------------------------------+
//| サポート・レジスタンス検出（改善版）                              |
//+------------------------------------------------------------------+
void DetectSupportResistance()
{
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int copied = CopyHigh(Symbol(), MainTF, 0, SRLookback, high);
   if(copied < SRLookback) return;
   copied = CopyLow(Symbol(), MainTF, 0, SRLookback, low);
   if(copied < SRLookback) return;
   copied = CopyClose(Symbol(), MainTF, 0, SRLookback, close);
   if(copied < SRLookback) return;

   ArrayResize(g_resistanceLevels, 0);
   ArrayResize(g_supportLevels, 0);

   double pipSize = GetPipSize();
   double zoneSize = SRZonePips * pipSize;

   // フラクタル（スイング高値/安値）検出 - より厳格に
   for(int i = 3; i < SRLookback - 3; i++)
   {
      // スイング高値（3本先まで確認）
      if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i-3] &&
         high[i] > high[i+1] && high[i] > high[i+2] && high[i] > high[i+3])
      {
         // タッチ回数をカウント
         int touchCount = CountTouches(high, close, high[i], zoneSize, SRLookback);
         if(touchCount >= SRTouchCount)
         {
            AddLevel(g_resistanceLevels, high[i], zoneSize);
         }
      }

      // スイング安値（3本先まで確認）
      if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i-3] &&
         low[i] < low[i+1] && low[i] < low[i+2] && low[i] < low[i+3])
      {
         int touchCount = CountTouches(low, close, low[i], zoneSize, SRLookback);
         if(touchCount >= SRTouchCount)
         {
            AddLevel(g_supportLevels, low[i], zoneSize);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| タッチ回数カウント                                                |
//+------------------------------------------------------------------+
int CountTouches(double &prices[], double &close[], double level, double zone, int lookback)
{
   int count = 0;
   for(int i = 0; i < lookback; i++)
   {
      if(MathAbs(prices[i] - level) < zone)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| レベル追加（重複チェック付き）                                    |
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

   g_fib382 = g_fibHigh - range * FibLevel1;
   g_fib500 = g_fibHigh - range * FibLevel2;
   g_fib618 = g_fibHigh - range * FibLevel3;
}

//+------------------------------------------------------------------+
//| エントリーシグナル取得（改善版）                                  |
//+------------------------------------------------------------------+
EntrySignal GetEntrySignal()
{
   EntrySignal signal;
   signal.isValid = false;
   signal.direction = 0;
   signal.confluenceCount = 0;
   signal.confluenceList = "";
   signal.rrRatio = 0;

   // トレンドフィルター
   if(UseTrendFilter && g_trendDirection == 0)
   {
      return signal; // レンジ相場ではエントリーしない
   }

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

   double currentPrice = close[0];
   double pipSize = GetPipSize();

   // コンフルエンス判定
   int buyConfluence = 0;
   int sellConfluence = 0;
   string buyList = "";
   string sellList = "";

   double pullbackDistance = GranvillePullbackPips * pipSize;
   double touchDistance = GranvilleTouchPips * pipSize;

   //--- 1. トレンド方向確認（必須条件） ---
   if(UseTrendFilter)
   {
      if(g_trendDirection == 1)
      {
         buyConfluence++;
         buyList += "上昇トレンド ";
      }
      else if(g_trendDirection == -1)
      {
         sellConfluence++;
         sellList += "下降トレンド ";
      }
   }

   //--- 2. グランビルの法則チェック ---
   // 200SMAへの引き付け（買い）- より厳格な条件
   if(currentPrice > sma200[0] && (currentPrice - sma200[0]) < pullbackDistance)
   {
      if(close[1] > close[2] && low[1] <= sma200[1] + touchDistance && close[1] > sma200[1])
      {
         buyConfluence++;
         buyList += "グランビル200SMA ";
      }
   }

   // 100EMAへの引き付け（買い）
   if(currentPrice > ema100[0] && (currentPrice - ema100[0]) < pullbackDistance)
   {
      if(close[1] > close[2] && low[1] <= ema100[1] + touchDistance && close[1] > ema100[1])
      {
         buyConfluence++;
         buyList += "グランビル100EMA ";
      }
   }

   // 200SMAへの引き付け（売り）
   if(currentPrice < sma200[0] && (sma200[0] - currentPrice) < pullbackDistance)
   {
      if(close[1] < close[2] && high[1] >= sma200[1] - touchDistance && close[1] < sma200[1])
      {
         sellConfluence++;
         sellList += "グランビル200SMA ";
      }
   }

   // 100EMAへの引き付け（売り）
   if(currentPrice < ema100[0] && (ema100[0] - currentPrice) < pullbackDistance)
   {
      if(close[1] < close[2] && high[1] >= ema100[1] - touchDistance && close[1] < ema100[1])
      {
         sellConfluence++;
         sellList += "グランビル100EMA ";
      }
   }

   //--- 3. プライスアクションチェック（厳格化） ---
   if(IsBullishPinBar(open[1], high[1], low[1], close[1]))
   {
      // ピンバーが重要なレベル付近であることを確認
      if(IsNearSupportLevel(low[1]))
      {
         buyConfluence++;
         buyList += "ピンバー ";
      }
   }
   if(IsBearishPinBar(open[1], high[1], low[1], close[1]))
   {
      if(IsNearResistanceLevel(high[1]))
      {
         sellConfluence++;
         sellList += "ピンバー ";
      }
   }

   // 包み足（Engulfing）
   if(IsBullishEngulfing(open[1], close[1], open[2], close[2]))
   {
      if(IsNearSupportLevel(low[1]))
      {
         buyConfluence++;
         buyList += "包み足 ";
      }
   }
   if(IsBearishEngulfing(open[1], close[1], open[2], close[2]))
   {
      if(IsNearResistanceLevel(high[1]))
      {
         sellConfluence++;
         sellList += "包み足 ";
      }
   }

   //--- 4. S/Rレベルチェック ---
   double srZone = SRZonePips * pipSize;

   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(MathAbs(low[1] - g_supportLevels[i]) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "サポート反発 ";
         break;
      }
   }

   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(MathAbs(high[1] - g_resistanceLevels[i]) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "レジスタンス反発 ";
         break;
      }
   }

   //--- 5. PIVOTチェック ---
   if(UseDailyPivot)
   {
      if(MathAbs(low[1] - g_support1) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "PIVOT S1 ";
      }
      if(MathAbs(low[1] - g_pivotPoint) < srZone && close[1] > open[1] && g_trendDirection >= 0)
      {
         buyConfluence++;
         buyList += "PIVOT PP ";
      }

      if(MathAbs(high[1] - g_resistance1) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "PIVOT R1 ";
      }
      if(MathAbs(high[1] - g_pivotPoint) < srZone && close[1] < open[1] && g_trendDirection <= 0)
      {
         sellConfluence++;
         sellList += "PIVOT PP ";
      }
   }

   //--- 6. Fibonacciチェック ---
   if(UseFibonacci)
   {
      if(MathAbs(low[1] - g_fib618) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib61.8 ";
      }
      if(MathAbs(low[1] - g_fib500) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib50.0 ";
      }
   }

   //--- シグナル決定 ---
   // トレンド方向と一致するシグナルのみ採用
   if(buyConfluence >= MinConfluenceCount &&
      (!UseTrendFilter || g_trendDirection >= 0) &&
      buyConfluence > sellConfluence)
   {
      signal.isValid = true;
      signal.direction = 1;
      signal.confluenceCount = buyConfluence;
      signal.confluenceList = buyList;
      signal.entryPrice = symInfo.Ask();
      signal.stopLoss = CalculateStopLossImproved(1, atr[0]);
      CalculateTakeProfits(signal);
      signal.rrRatio = CalculateRRRatio(signal);
   }
   else if(sellConfluence >= MinConfluenceCount &&
           (!UseTrendFilter || g_trendDirection <= 0) &&
           sellConfluence > buyConfluence)
   {
      signal.isValid = true;
      signal.direction = -1;
      signal.confluenceCount = sellConfluence;
      signal.confluenceList = sellList;
      signal.entryPrice = symInfo.Bid();
      signal.stopLoss = CalculateStopLossImproved(-1, atr[0]);
      CalculateTakeProfits(signal);
      signal.rrRatio = CalculateRRRatio(signal);
   }

   return signal;
}

//+------------------------------------------------------------------+
//| サポートレベル付近判定                                            |
//+------------------------------------------------------------------+
bool IsNearSupportLevel(double price)
{
   double pipSize = GetPipSize();
   double zone = SRZonePips * pipSize;

   // S/Rレベルチェック
   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(MathAbs(price - g_supportLevels[i]) < zone)
         return true;
   }

   // PIVOTチェック
   if(UseDailyPivot)
   {
      if(MathAbs(price - g_support1) < zone ||
         MathAbs(price - g_support2) < zone ||
         MathAbs(price - g_pivotPoint) < zone)
         return true;
   }

   // Fibチェック
   if(UseFibonacci)
   {
      if(MathAbs(price - g_fib382) < zone ||
         MathAbs(price - g_fib500) < zone ||
         MathAbs(price - g_fib618) < zone)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| レジスタンスレベル付近判定                                        |
//+------------------------------------------------------------------+
bool IsNearResistanceLevel(double price)
{
   double pipSize = GetPipSize();
   double zone = SRZonePips * pipSize;

   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(MathAbs(price - g_resistanceLevels[i]) < zone)
         return true;
   }

   if(UseDailyPivot)
   {
      if(MathAbs(price - g_resistance1) < zone ||
         MathAbs(price - g_resistance2) < zone ||
         MathAbs(price - g_pivotPoint) < zone)
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
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalRange = high - low;

   if(totalRange == 0 || body == 0) return false;

   // より厳格な条件：下ヒゲが実体の2.5倍以上
   return (lowerWick >= body * PinBarRatio * 2.5 &&
           upperWick < lowerWick * 0.3 &&
           close >= open &&
           body < totalRange * 0.3);
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
           lowerWick < upperWick * 0.3 &&
           close <= open &&
           body < totalRange * 0.3);
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
//| 損切りライン計算（改善版：ATRベース）                            |
//+------------------------------------------------------------------+
double CalculateStopLossImproved(int direction, double atrValue)
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

   if(direction == 1)  // 買い
   {
      double swingLow = low[ArrayMinimum(low, 0, SwingLookback)];
      double buffer = swingLow * (SLBufferPercent / 100.0);
      sl = swingLow - buffer;

      // ATRベースのSLと比較して小さい方を採用
      double entryPrice = symInfo.Ask();
      double swingSL = entryPrice - sl;

      if(swingSL > maxSL)
      {
         sl = entryPrice - maxSL;
      }
      if(swingSL > atrSL)
      {
         sl = MathMax(sl, entryPrice - atrSL);
      }
   }
   else  // 売り
   {
      double swingHigh = high[ArrayMaximum(high, 0, SwingLookback)];
      double buffer = swingHigh * (SLBufferPercent / 100.0);
      sl = swingHigh + buffer;

      double entryPrice = symInfo.Bid();
      double swingSL = sl - entryPrice;

      if(swingSL > maxSL)
      {
         sl = entryPrice + maxSL;
      }
      if(swingSL > atrSL)
      {
         sl = MathMin(sl, entryPrice + atrSL);
      }
   }

   return NormalizeDouble(sl, symInfo.Digits());
}

//+------------------------------------------------------------------+
//| 利確ライン計算                                                    |
//+------------------------------------------------------------------+
void CalculateTakeProfits(EntrySignal &signal)
{
   double riskDistance = MathAbs(signal.entryPrice - signal.stopLoss);

   if(signal.direction == 1)  // 買い
   {
      signal.takeProfit1 = signal.entryPrice + riskDistance * TP1_RR;
      signal.takeProfit2 = signal.entryPrice + riskDistance * TP2_RR;

      // レジスタンスレベルで調整
      double nearestResistance = GetNearestResistance(signal.entryPrice);
      if(nearestResistance > signal.entryPrice && nearestResistance < signal.takeProfit2)
      {
         // TP1は手前のレジスタンス、TP2はその先
         if(nearestResistance > signal.takeProfit1)
         {
            signal.takeProfit2 = nearestResistance;
         }
      }
   }
   else  // 売り
   {
      signal.takeProfit1 = signal.entryPrice - riskDistance * TP1_RR;
      signal.takeProfit2 = signal.entryPrice - riskDistance * TP2_RR;

      double nearestSupport = GetNearestSupport(signal.entryPrice);
      if(nearestSupport < signal.entryPrice && nearestSupport > signal.takeProfit2)
      {
         if(nearestSupport < signal.takeProfit1)
         {
            signal.takeProfit2 = nearestSupport;
         }
      }
   }

   signal.takeProfit1 = NormalizeDouble(signal.takeProfit1, symInfo.Digits());
   signal.takeProfit2 = NormalizeDouble(signal.takeProfit2, symInfo.Digits());
}

//+------------------------------------------------------------------+
//| 最寄りのレジスタンス取得                                          |
//+------------------------------------------------------------------+
double GetNearestResistance(double currentPrice)
{
   double nearest = 0;
   double minDistance = DBL_MAX;

   // S/Rレベル
   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(g_resistanceLevels[i] > currentPrice)
      {
         double distance = g_resistanceLevels[i] - currentPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = g_resistanceLevels[i];
         }
      }
   }

   // PIVOTレベル
   if(UseDailyPivot)
   {
      if(g_resistance1 > currentPrice && (g_resistance1 - currentPrice) < minDistance)
      {
         nearest = g_resistance1;
      }
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| 最寄りのサポート取得                                              |
//+------------------------------------------------------------------+
double GetNearestSupport(double currentPrice)
{
   double nearest = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(g_supportLevels[i] < currentPrice)
      {
         double distance = currentPrice - g_supportLevels[i];
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = g_supportLevels[i];
         }
      }
   }

   if(UseDailyPivot)
   {
      if(g_support1 < currentPrice && (currentPrice - g_support1) < minDistance)
      {
         nearest = g_support1;
      }
   }

   return nearest;
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
   // RR比チェック
   if(signal.rrRatio < MinRRRatio)
   {
      Print("RR比が不十分: ", signal.rrRatio, " < ", MinRRRatio);
      return;
   }

   // ロットサイズ計算
   double lots = CalculateLotSize(signal.entryPrice, signal.stopLoss);

   if(lots <= 0)
   {
      Print("エラー: ロットサイズが不正です");
      return;
   }

   // リスクチェック
   if(!ValidateRisk(lots, signal.entryPrice, signal.stopLoss))
   {
      Print("リスク制限によりエントリー見送り");
      return;
   }

   bool result = false;

   if(signal.direction == 1)  // 買い
   {
      if(UsePartialTP)
      {
         double lot1 = NormalizeLotSize(lots * (TP1_Percent / 100.0));
         double lot2 = NormalizeLotSize(lots - lot1);

         if(lot1 > 0)
            result = trade.Buy(lot1, Symbol(), 0, signal.stopLoss, signal.takeProfit1, "XAUUSD_v2_TP1");
         if(lot2 > 0)
            result = trade.Buy(lot2, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_v2_TP2") || result;
      }
      else
      {
         result = trade.Buy(lots, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_v2");
      }
   }
   else  // 売り
   {
      if(UsePartialTP)
      {
         double lot1 = NormalizeLotSize(lots * (TP1_Percent / 100.0));
         double lot2 = NormalizeLotSize(lots - lot1);

         if(lot1 > 0)
            result = trade.Sell(lot1, Symbol(), 0, signal.stopLoss, signal.takeProfit1, "XAUUSD_v2_TP1");
         if(lot2 > 0)
            result = trade.Sell(lot2, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_v2_TP2") || result;
      }
      else
      {
         result = trade.Sell(lots, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_v2");
      }
   }

   if(result)
   {
      g_dailyTradeCount++;
      Print("========================================");
      Print("エントリー成功: ", (signal.direction == 1 ? "BUY" : "SELL"));
      Print("コンフルエンス: ", signal.confluenceCount, " - ", signal.confluenceList);
      Print("RR比: ", signal.rrRatio);
      Print("SL: ", signal.stopLoss, " TP1: ", signal.takeProfit1, " TP2: ", signal.takeProfit2);
      Print("本日の取引数: ", g_dailyTradeCount, "/", MaxDailyTrades);
      Print("========================================");
   }
   else
   {
      Print("エントリー失敗: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| ロットサイズ計算                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (DefaultRiskPercent / 100.0);

   // 最大リスク制限
   double maxRiskAmount = accountBalance * (MaxRiskPerTrade / 100.0);
   if(riskAmount > maxRiskAmount)
      riskAmount = maxRiskAmount;

   // 1日の残りリスク制限チェック
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossLimit = g_dailyStartEquity * (DailyMaxLossPercent / 100.0);
   double usedDailyLoss = g_dailyStartEquity - currentEquity;
   double remainingDailyRisk = dailyLossLimit - usedDailyLoss;

   if(riskAmount > remainingDailyRisk * 0.5)  // 50%の余裕を持つ
      riskAmount = remainingDailyRisk * 0.5;

   if(riskAmount <= 0)
      return 0;

   // SL距離をpipsに変換
   double slDistance = MathAbs(entryPrice - stopLoss);
   double pipSize = GetPipSize();
   double slPips = slDistance / pipSize;

   // 1ロットあたりの損失計算
   double lossPerLot = CalculateLossPerLot(slPips);

   if(lossPerLot <= 0)
      return 0;

   double lots = riskAmount / lossPerLot;

   return NormalizeLotSize(lots);
}

//+------------------------------------------------------------------+
//| 1ロットあたりの損失計算                                          |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips)
{
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;

   return numTicks * tickValue;
}

//+------------------------------------------------------------------+
//| ロットサイズ正規化                                                |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   lots = MathFloor(lots / lotStep) * lotStep;

   if(lots < minLot)
      lots = minLot;

   return lots;
}

//+------------------------------------------------------------------+
//| Pipサイズ取得                                                    |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(digits == 2)
      return point * 10.0;
   else if(digits == 3)
      return point * 10.0;
   else
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

   // 1トレードのリスクチェック
   double riskPercent = (potentialLoss / accountBalance) * 100.0;
   if(riskPercent > MaxRiskPerTrade)
   {
      Print("リスク超過: ", riskPercent, "% > ", MaxRiskPerTrade, "%");
      return false;
   }

   // 1日の損失チェック
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double projectedEquity = currentEquity - potentialLoss;
   double dailyLossLimit = g_dailyStartEquity * (1.0 - DailyMaxLossPercent / 100.0);

   if(projectedEquity < dailyLossLimit)
   {
      Print("1日損失制限に抵触の可能性");
      return false;
   }

   // 全体の損失チェック
   double totalLossLimit = g_initialBalance * (1.0 - TotalMaxLossPercent / 100.0);
   if(projectedEquity < totalLossLimit)
   {
      Print("全体損失制限に抵触の可能性");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| オープンポジション管理                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != MagicNumber)
         continue;

      // 建値決済チェック
      if(UseBreakeven)
      {
         CheckBreakeven(posInfo);
      }

      // トレーリングストップ
      if(UseTrailingStop)
      {
         CheckTrailingStop(posInfo);
      }

      // 20EMA実体抜けチェック
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
      if(currentSL >= openPrice)
         return;

      double triggerDistance = MathAbs(openPrice - pos.StopLoss()) * BreakevenTriggerRR;
      if(currentPrice >= openPrice + triggerDistance)
      {
         double newSL = openPrice + (BreakevenPlusPips * pipSize);
         newSL = NormalizeDouble(newSL, symInfo.Digits());

         if(newSL > currentSL)
         {
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
            Print("建値決済設定: チケット ", pos.Ticket(), " 新SL: ", newSL);
         }
      }
   }
   else
   {
      if(currentSL <= openPrice && currentSL > 0)
         return;

      double triggerDistance = MathAbs(pos.StopLoss() - openPrice) * BreakevenTriggerRR;
      if(currentPrice <= openPrice - triggerDistance)
      {
         double newSL = openPrice - (BreakevenPlusPips * pipSize);
         newSL = NormalizeDouble(newSL, symInfo.Digits());

         if(newSL < currentSL || currentSL == 0)
         {
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
            Print("建値決済設定: チケット ", pos.Ticket(), " 新SL: ", newSL);
         }
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
   double trailingStartDistance = initialRisk * TrailingStartRR;

   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      if(currentPrice >= openPrice + trailingStartDistance)
      {
         double newSL = currentPrice - trailingStep;
         newSL = NormalizeDouble(newSL, symInfo.Digits());

         if(newSL > currentSL)
         {
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
            Print("トレーリングストップ更新: チケット ", pos.Ticket(), " 新SL: ", newSL);
         }
      }
   }
   else
   {
      if(currentPrice <= openPrice - trailingStartDistance)
      {
         double newSL = currentPrice + trailingStep;
         newSL = NormalizeDouble(newSL, symInfo.Digits());

         if(newSL < currentSL || currentSL == 0)
         {
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
            Print("トレーリングストップ更新: チケット ", pos.Ticket(), " 新SL: ", newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 20EMA実体抜けチェック                                            |
//+------------------------------------------------------------------+
void CheckEMAExit(CPositionInfo &pos)
{
   double ema20[];
   ArraySetAsSeries(ema20, true);

   if(CopyBuffer(handleEMA20, 0, 0, 2, ema20) < 2)
      return;

   double close[], open[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);

   if(CopyClose(Symbol(), MainTF, 0, 2, close) < 2) return;
   if(CopyOpen(Symbol(), MainTF, 0, 2, open) < 2) return;

   // 含み益が出ている場合のみチェック
   if(pos.Profit() <= 0)
      return;

   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      if(close[1] < ema20[1] && open[1] > ema20[1])
      {
         double currentPrice = symInfo.Bid();
         if(currentPrice < ema20[0])
         {
            trade.PositionClose(pos.Ticket());
            Print("20EMA下抜けにより決済: チケット ", pos.Ticket());
         }
      }
   }
   else
   {
      if(close[1] > ema20[1] && open[1] < ema20[1])
      {
         double currentPrice = symInfo.Ask();
         if(currentPrice > ema20[0])
         {
            trade.PositionClose(pos.Ticket());
            Print("20EMA上抜けにより決済: チケット ", pos.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
