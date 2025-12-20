//+------------------------------------------------------------------+
//|                                          XAUUSD_Fintokei_EA.mq5 |
//|                        XAUUSD専用 Fintokeiチャレンジ対応EA      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Fintokei EA"
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
input double   InitialBalance     = 0;        // 初期資金（0=自動取得）
input int      MagicNumber        = 123456;   // マジックナンバー
input string   TradeSymbol        = "XAUUSD"; // 取引通貨ペア
input ENUM_TIMEFRAMES MainTF      = PERIOD_M5;// メイン時間足

input group "===== Fintokei リスク管理 ====="
input double   DailyMaxLossPercent   = 4.9;   // 1日の最大損失率(%)
input double   TotalMaxLossPercent   = 9.9;   // 全体の最大損失率(%)
input double   MaxRiskPerTrade       = 3.0;   // 1トレードの最大リスク(%)
input double   DefaultRiskPercent    = 2.0;   // デフォルトリスク(%)

input group "===== 移動平均線設定 ====="
input int      SMA_Period         = 200;      // 長期SMA期間
input int      EMA_Period         = 100;      // 中期EMA期間
input int      FastEMA_Period     = 20;       // 短期EMA期間（利確用）
input ENUM_MA_METHOD MA_Method    = MODE_SMA; // SMA計算方法

input group "===== グランビル設定 ====="
input double   GranvillePullbackPips = 50;    // MAへの引き付け距離(pips)
input double   GranvilleTouchPips    = 30;    // MAタッチ判定距離(pips)

input group "===== プライスアクション設定 ====="
input double   PinBarRatio        = 0.6;      // ピンバーの芯/実体比率
input double   EngulfingMinRatio  = 1.2;      // 包み足の最小比率

input group "===== 水平線設定 ====="
input int      SRLookback         = 50;       // S/R検出のルックバック期間
input double   SRZonePips         = 20;       // S/Rゾーン幅(pips)
input int      SRTouchCount       = 2;        // S/R確認に必要なタッチ数

input group "===== 損切り設定 ====="
input double   SLBufferPercent    = 0.3;      // 損切りバッファ(%)
input int      SwingLookback      = 20;       // スイング高値/安値ルックバック

input group "===== 利確設定 ====="
input bool     UsePartialTP       = true;     // 分割利確を使用
input double   TP1_Percent        = 50;       // 第1利確のポジション比率(%)
input double   TP1_RR             = 1.0;      // 第1利確のRR比率
input double   TP2_RR             = 2.0;      // 第2利確のRR比率

input group "===== 建値決済設定 ====="
input bool     UseBreakeven       = true;     // 建値決済を使用
input double   BreakevenTriggerRR = 1.0;      // 建値移動のトリガーRR
input double   BreakevenPlusPips  = 5;        // 建値+αのpips

input group "===== PIVOT設定 ====="
input bool     UseDailyPivot      = true;     // デイリーPIVOTを使用
input bool     UseWeeklyPivot     = false;    // ウィークリーPIVOTを使用

input group "===== Fibonacci設定 ====="
input bool     UseFibonacci       = true;     // Fibonacciを使用
input double   FibLevel1          = 0.382;    // Fibレベル1
input double   FibLevel2          = 0.5;      // Fibレベル2
input double   FibLevel3          = 0.618;    // Fibレベル3

input group "===== エントリー条件 ====="
input int      MinConfluenceCount = 2;        // 最小コンフルエンス数
input int      MaxSpreadPips      = 30;       // 最大スプレッド(pips)
input bool     TradeOnlyNewBar    = true;     // 新しいバーでのみエントリー

input group "===== 取引時間設定 ====="
input int      TradeStartHour     = 0;        // 取引開始時間(UTC)
input int      TradeEndHour       = 24;       // 取引終了時間(UTC)
input bool     AvoidNewsTime      = false;    // ニュース時間を避ける

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
int handleEMA20;
int handleATR;

// 資金管理用
double g_initialBalance;
double g_dailyStartEquity;
datetime g_lastDayCheck;
bool g_tradingAllowed;

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
   handleEMA20  = iMA(Symbol(), MainTF, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleATR    = iATR(Symbol(), MainTF, 14);

   if(handleSMA200 == INVALID_HANDLE || handleEMA100 == INVALID_HANDLE ||
      handleEMA20 == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("エラー: インジケータの初期化に失敗しました");
      return INIT_FAILED;
   }

   // 資金管理初期化
   g_initialBalance = (InitialBalance > 0) ? InitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_lastDayCheck = 0;
   g_tradingAllowed = true;

   // 配列初期化
   ArrayResize(g_resistanceLevels, 0);
   ArrayResize(g_supportLevels, 0);

   // 日次チェック
   CheckDailyReset();

   Print("XAUUSD Fintokei EA 初期化完了");
   Print("初期資金: ", g_initialBalance);
   Print("1日最大損失: ", DailyMaxLossPercent, "%");
   Print("全体最大損失: ", TotalMaxLossPercent, "%");

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
   if(handleEMA20 != INVALID_HANDLE)  IndicatorRelease(handleEMA20);
   if(handleATR != INVALID_HANDLE)    IndicatorRelease(handleATR);

   Print("XAUUSD Fintokei EA 終了");
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

   // リスク管理チェック
   if(!CheckRiskManagement())
   {
      // リスク超過時は全ポジション決済
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

   // 既にポジションがある場合は新規エントリーしない
   if(HasOpenPosition())
      return;

   // PIVOTポイント計算
   CalculatePivotPoints();

   // S/Rレベル検出
   DetectSupportResistance();

   // Fibonacciレベル計算
   CalculateFibonacciLevels();

   // エントリーシグナル取得
   EntrySignal signal = GetEntrySignal();

   // シグナルが有効な場合はエントリー
   if(signal.isValid && signal.confluenceCount >= MinConfluenceCount)
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

      Print("日次リセット: 開始時有効証拠金 = ", g_dailyStartEquity);
   }
}

//+------------------------------------------------------------------+
//| リスク管理チェック                                                |
//+------------------------------------------------------------------+
bool CheckRiskManagement()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 1日の損失チェック（5%ルール → 4.9%で制限）
   double dailyLossLimit = g_dailyStartEquity * (1.0 - DailyMaxLossPercent / 100.0);
   if(currentEquity <= dailyLossLimit)
   {
      if(g_tradingAllowed)
      {
         Print("警告: 1日の損失制限に達しました。取引を停止します。");
         Print("開始時証拠金: ", g_dailyStartEquity, " 現在: ", currentEquity, " 制限: ", dailyLossLimit);
      }
      g_tradingAllowed = false;
      return false;
   }

   // 全体の損失チェック（10%ルール → 9.9%で制限）
   double totalLossLimit = g_initialBalance * (1.0 - TotalMaxLossPercent / 100.0);
   if(currentEquity <= totalLossLimit)
   {
      if(g_tradingAllowed)
      {
         Print("警告: 全体の損失制限に達しました。取引を停止します。");
         Print("初期資金: ", g_initialBalance, " 現在: ", currentEquity, " 制限: ", totalLossLimit);
      }
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
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime);

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
   // 日足データ取得
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

   // PIVOT計算
   g_pivotPoint = (prevHigh + prevLow + prevClose) / 3.0;

   g_resistance1 = 2.0 * g_pivotPoint - prevLow;
   g_support1 = 2.0 * g_pivotPoint - prevHigh;

   g_resistance2 = g_pivotPoint + (prevHigh - prevLow);
   g_support2 = g_pivotPoint - (prevHigh - prevLow);

   g_resistance3 = prevHigh + 2.0 * (g_pivotPoint - prevLow);
   g_support3 = prevLow - 2.0 * (prevHigh - g_pivotPoint);
}

//+------------------------------------------------------------------+
//| サポート・レジスタンス検出                                        |
//+------------------------------------------------------------------+
void DetectSupportResistance()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int copied = CopyHigh(Symbol(), MainTF, 0, SRLookback, high);
   if(copied < SRLookback) return;
   copied = CopyLow(Symbol(), MainTF, 0, SRLookback, low);
   if(copied < SRLookback) return;

   ArrayResize(g_resistanceLevels, 0);
   ArrayResize(g_supportLevels, 0);

   double pipSize = GetPipSize();
   double zoneSize = SRZonePips * pipSize;

   // フラクタル（スイング高値/安値）検出
   for(int i = 2; i < SRLookback - 2; i++)
   {
      // スイング高値
      if(high[i] > high[i-1] && high[i] > high[i-2] &&
         high[i] > high[i+1] && high[i] > high[i+2])
      {
         AddLevel(g_resistanceLevels, high[i], zoneSize);
      }

      // スイング安値
      if(low[i] < low[i-1] && low[i] < low[i-2] &&
         low[i] < low[i+1] && low[i] < low[i+2])
      {
         AddLevel(g_supportLevels, low[i], zoneSize);
      }
   }
}

//+------------------------------------------------------------------+
//| レベル追加（重複チェック付き）                                    |
//+------------------------------------------------------------------+
void AddLevel(double &levels[], double price, double zone)
{
   // 既存レベルとの重複チェック
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

   // 直近のスイングハイ/ロー検出
   g_fibHigh = high[ArrayMaximum(high, 0, lookback)];
   g_fibLow = low[ArrayMinimum(low, 0, lookback)];

   double range = g_fibHigh - g_fibLow;

   // 上昇トレンドの場合（リトレースメント）
   g_fib382 = g_fibHigh - range * FibLevel1;
   g_fib500 = g_fibHigh - range * FibLevel2;
   g_fib618 = g_fibHigh - range * FibLevel3;
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

   // MA値取得
   double sma200[], ema100[], ema20[];
   ArraySetAsSeries(sma200, true);
   ArraySetAsSeries(ema100, true);
   ArraySetAsSeries(ema20, true);

   if(CopyBuffer(handleSMA200, 0, 0, 3, sma200) < 3) return signal;
   if(CopyBuffer(handleEMA100, 0, 0, 3, ema100) < 3) return signal;
   if(CopyBuffer(handleEMA20, 0, 0, 3, ema20) < 3) return signal;

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

   double currentPrice = close[0];
   double pipSize = GetPipSize();

   // コンフルエンス判定
   int buyConfluence = 0;
   int sellConfluence = 0;
   string buyList = "";
   string sellList = "";

   //--- 1. グランビルの法則チェック ---
   // 買いシグナル: 価格が200SMAまたは100EMAに引き付けられて反発
   double pullbackDistance = GranvillePullbackPips * pipSize;
   double touchDistance = GranvilleTouchPips * pipSize;

   // 200SMAへの引き付け（買い）
   if(currentPrice > sma200[0] && (currentPrice - sma200[0]) < pullbackDistance)
   {
      if(close[1] < close[0] && low[1] <= sma200[1] + touchDistance)
      {
         buyConfluence++;
         buyList += "グランビル200SMA ";
      }
   }

   // 100EMAへの引き付け（買い）
   if(currentPrice > ema100[0] && (currentPrice - ema100[0]) < pullbackDistance)
   {
      if(close[1] < close[0] && low[1] <= ema100[1] + touchDistance)
      {
         buyConfluence++;
         buyList += "グランビル100EMA ";
      }
   }

   // 200SMAへの引き付け（売り）
   if(currentPrice < sma200[0] && (sma200[0] - currentPrice) < pullbackDistance)
   {
      if(close[1] > close[0] && high[1] >= sma200[1] - touchDistance)
      {
         sellConfluence++;
         sellList += "グランビル200SMA ";
      }
   }

   // 100EMAへの引き付け（売り）
   if(currentPrice < ema100[0] && (ema100[0] - currentPrice) < pullbackDistance)
   {
      if(close[1] > close[0] && high[1] >= ema100[1] - touchDistance)
      {
         sellConfluence++;
         sellList += "グランビル100EMA ";
      }
   }

   //--- 2. プライスアクションチェック ---
   // ピンバー
   if(IsBullishPinBar(open[1], high[1], low[1], close[1]))
   {
      buyConfluence++;
      buyList += "ピンバー ";
   }
   if(IsBearishPinBar(open[1], high[1], low[1], close[1]))
   {
      sellConfluence++;
      sellList += "ピンバー ";
   }

   // 包み足（Engulfing）
   if(IsBullishEngulfing(open[1], close[1], open[2], close[2]))
   {
      buyConfluence++;
      buyList += "包み足 ";
   }
   if(IsBearishEngulfing(open[1], close[1], open[2], close[2]))
   {
      sellConfluence++;
      sellList += "包み足 ";
   }

   //--- 3. S/Rレベルチェック ---
   double srZone = SRZonePips * pipSize;

   // サポートからの反発
   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(MathAbs(low[1] - g_supportLevels[i]) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "サポート反発 ";
         break;
      }
   }

   // レジスタンスからの反発
   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(MathAbs(high[1] - g_resistanceLevels[i]) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "レジスタンス反発 ";
         break;
      }
   }

   //--- 4. PIVOTチェック ---
   if(UseDailyPivot)
   {
      // サポートPIVOTからの反発
      if(MathAbs(low[1] - g_support1) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "PIVOT S1 ";
      }
      if(MathAbs(low[1] - g_support2) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "PIVOT S2 ";
      }

      // レジスタンスPIVOTからの反発
      if(MathAbs(high[1] - g_resistance1) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "PIVOT R1 ";
      }
      if(MathAbs(high[1] - g_resistance2) < srZone && close[1] < open[1])
      {
         sellConfluence++;
         sellList += "PIVOT R2 ";
      }
   }

   //--- 5. Fibonacciチェック ---
   if(UseFibonacci)
   {
      if(MathAbs(low[1] - g_fib382) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib38.2 ";
      }
      if(MathAbs(low[1] - g_fib500) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib50.0 ";
      }
      if(MathAbs(low[1] - g_fib618) < srZone && close[1] > open[1])
      {
         buyConfluence++;
         buyList += "Fib61.8 ";
      }
   }

   //--- シグナル決定 ---
   if(buyConfluence >= MinConfluenceCount && buyConfluence > sellConfluence)
   {
      signal.isValid = true;
      signal.direction = 1;
      signal.confluenceCount = buyConfluence;
      signal.confluenceList = buyList;
      signal.entryPrice = symInfo.Ask();
      signal.stopLoss = CalculateStopLoss(1);
      CalculateTakeProfits(signal);
   }
   else if(sellConfluence >= MinConfluenceCount && sellConfluence > buyConfluence)
   {
      signal.isValid = true;
      signal.direction = -1;
      signal.confluenceCount = sellConfluence;
      signal.confluenceList = sellList;
      signal.entryPrice = symInfo.Bid();
      signal.stopLoss = CalculateStopLoss(-1);
      CalculateTakeProfits(signal);
   }

   return signal;
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

   if(totalRange == 0) return false;

   // 下ヒゲが実体の2倍以上で、上ヒゲが短い
   return (lowerWick >= body * PinBarRatio * 2 &&
           upperWick < lowerWick * 0.5 &&
           close >= open);
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

   if(totalRange == 0) return false;

   // 上ヒゲが実体の2倍以上で、下ヒゲが短い
   return (upperWick >= body * PinBarRatio * 2 &&
           lowerWick < upperWick * 0.5 &&
           close <= open);
}

//+------------------------------------------------------------------+
//| 強気包み足判定                                                    |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(double open1, double close1, double open2, double close2)
{
   // 前のローソク足が陰線で、現在のローソク足が陽線
   if(close2 >= open2) return false;  // 前が陰線でない
   if(close1 <= open1) return false;  // 現在が陽線でない

   double prevBody = MathAbs(close2 - open2);
   double currBody = MathAbs(close1 - open1);

   // 現在の実体が前の実体を包み込む
   return (currBody >= prevBody * EngulfingMinRatio &&
           close1 > open2 && open1 < close2);
}

//+------------------------------------------------------------------+
//| 弱気包み足判定                                                    |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(double open1, double close1, double open2, double close2)
{
   // 前のローソク足が陽線で、現在のローソク足が陰線
   if(close2 <= open2) return false;  // 前が陽線でない
   if(close1 >= open1) return false;  // 現在が陰線でない

   double prevBody = MathAbs(close2 - open2);
   double currBody = MathAbs(close1 - open1);

   // 現在の実体が前の実体を包み込む
   return (currBody >= prevBody * EngulfingMinRatio &&
           close1 < open2 && open1 > close2);
}

//+------------------------------------------------------------------+
//| 損切りライン計算（ダウ理論考慮）                                  |
//+------------------------------------------------------------------+
double CalculateStopLoss(int direction)
{
   double low[], high[];
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(high, true);

   if(CopyLow(Symbol(), MainTF, 0, SwingLookback, low) < SwingLookback) return 0;
   if(CopyHigh(Symbol(), MainTF, 0, SwingLookback, high) < SwingLookback) return 0;

   double sl = 0;
   double pipSize = GetPipSize();

   if(direction == 1)  // 買いの場合
   {
      // 直近スイングローを探す
      double swingLow = low[ArrayMinimum(low, 0, SwingLookback)];
      // バッファを追加（騙しや試しを考慮）
      double buffer = swingLow * (SLBufferPercent / 100.0);
      sl = swingLow - buffer;
   }
   else  // 売りの場合
   {
      // 直近スイングハイを探す
      double swingHigh = high[ArrayMaximum(high, 0, SwingLookback)];
      // バッファを追加
      double buffer = swingHigh * (SLBufferPercent / 100.0);
      sl = swingHigh + buffer;
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

      // 直近高値との比較
      double recentHigh = GetRecentSwingHigh();
      if(recentHigh > signal.entryPrice && recentHigh < signal.takeProfit2)
      {
         signal.takeProfit2 = recentHigh;
      }

      // PIVOTレベルとの比較
      if(UseDailyPivot)
      {
         if(g_resistance1 > signal.entryPrice && g_resistance1 < signal.takeProfit2)
            signal.takeProfit2 = g_resistance1;
      }
   }
   else  // 売り
   {
      signal.takeProfit1 = signal.entryPrice - riskDistance * TP1_RR;
      signal.takeProfit2 = signal.entryPrice - riskDistance * TP2_RR;

      // 直近安値との比較
      double recentLow = GetRecentSwingLow();
      if(recentLow < signal.entryPrice && recentLow > signal.takeProfit2)
      {
         signal.takeProfit2 = recentLow;
      }

      // PIVOTレベルとの比較
      if(UseDailyPivot)
      {
         if(g_support1 < signal.entryPrice && g_support1 > signal.takeProfit2)
            signal.takeProfit2 = g_support1;
      }
   }

   signal.takeProfit1 = NormalizeDouble(signal.takeProfit1, symInfo.Digits());
   signal.takeProfit2 = NormalizeDouble(signal.takeProfit2, symInfo.Digits());
}

//+------------------------------------------------------------------+
//| 直近スイングハイ取得                                              |
//+------------------------------------------------------------------+
double GetRecentSwingHigh()
{
   double high[];
   ArraySetAsSeries(high, true);

   if(CopyHigh(Symbol(), PERIOD_H1, 0, 24, high) < 24)
      return 0;

   return high[ArrayMaximum(high, 0, 24)];
}

//+------------------------------------------------------------------+
//| 直近スイングロー取得                                              |
//+------------------------------------------------------------------+
double GetRecentSwingLow()
{
   double low[];
   ArraySetAsSeries(low, true);

   if(CopyLow(Symbol(), PERIOD_H1, 0, 24, low) < 24)
      return 0;

   return low[ArrayMinimum(low, 0, 24)];
}

//+------------------------------------------------------------------+
//| エントリー実行                                                    |
//+------------------------------------------------------------------+
void ExecuteEntry(EntrySignal &signal)
{
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
         // 分割エントリー
         double lot1 = NormalizeLotSize(lots * (TP1_Percent / 100.0));
         double lot2 = NormalizeLotSize(lots - lot1);

         if(lot1 > 0)
            result = trade.Buy(lot1, Symbol(), 0, signal.stopLoss, signal.takeProfit1, "XAUUSD_EA_TP1");
         if(lot2 > 0)
            result = trade.Buy(lot2, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_EA_TP2") || result;
      }
      else
      {
         result = trade.Buy(lots, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_EA");
      }
   }
   else  // 売り
   {
      if(UsePartialTP)
      {
         double lot1 = NormalizeLotSize(lots * (TP1_Percent / 100.0));
         double lot2 = NormalizeLotSize(lots - lot1);

         if(lot1 > 0)
            result = trade.Sell(lot1, Symbol(), 0, signal.stopLoss, signal.takeProfit1, "XAUUSD_EA_TP1");
         if(lot2 > 0)
            result = trade.Sell(lot2, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_EA_TP2") || result;
      }
      else
      {
         result = trade.Sell(lots, Symbol(), 0, signal.stopLoss, signal.takeProfit2, "XAUUSD_EA");
      }
   }

   if(result)
   {
      Print("エントリー成功: ", (signal.direction == 1 ? "BUY" : "SELL"));
      Print("コンフルエンス: ", signal.confluenceCount, " - ", signal.confluenceList);
      Print("SL: ", signal.stopLoss, " TP1: ", signal.takeProfit1, " TP2: ", signal.takeProfit2);
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

   if(riskAmount > remainingDailyRisk * 0.9)  // 90%の余裕を持つ
      riskAmount = remainingDailyRisk * 0.9;

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

   // XAUUSDは通常2桁または3桁
   if(digits == 2)
      return point * 10.0;  // 0.1
   else if(digits == 3)
      return point * 10.0;  // 0.01
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
      Print("1日損失制限に抵触の可能性: 予想有効証拠金 ", projectedEquity, " < 制限 ", dailyLossLimit);
      return false;
   }

   // 全体の損失チェック
   double totalLossLimit = g_initialBalance * (1.0 - TotalMaxLossPercent / 100.0);
   if(projectedEquity < totalLossLimit)
   {
      Print("全体損失制限に抵触の可能性: 予想有効証拠金 ", projectedEquity, " < 制限 ", totalLossLimit);
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

      // 20SMA実体抜けチェック（利確判断）
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

   // 既に建値以上にSLが移動されている場合はスキップ
   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      if(currentSL >= openPrice)
         return;

      // トリガー条件チェック
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
   else  // SELL
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
//| 20SMA実体抜けチェック                                            |
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
      // 実体が20SMAを下抜け
      if(close[1] < ema20[1] && open[1] > ema20[1])
      {
         // 直近バーで確定したので決済検討
         double currentPrice = symInfo.Bid();
         if(currentPrice < ema20[0])
         {
            trade.PositionClose(pos.Ticket());
            Print("20SMA下抜けにより決済: チケット ", pos.Ticket());
         }
      }
   }
   else  // SELL
   {
      // 実体が20SMAを上抜け
      if(close[1] > ema20[1] && open[1] < ema20[1])
      {
         double currentPrice = symInfo.Ask();
         if(currentPrice > ema20[0])
         {
            trade.PositionClose(pos.Ticket());
            Print("20SMA上抜けにより決済: チケット ", pos.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 情報表示                                                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // チャート情報更新用
}

//+------------------------------------------------------------------+
