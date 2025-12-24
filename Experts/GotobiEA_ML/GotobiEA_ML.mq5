//+------------------------------------------------------------------+
//|                                                  GotobiEA_ML.mq5 |
//|                      Gotobi Day EA with Machine Learning        |
//|                              Fintokei Challenge Plan Compatible |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML"
#property link      ""
#property version   "1.00"
#property description "ゴトー日手法 + 機械学習エントリー最適化EA"
#property description "Fintokei資金管理ルール完全対応"

//--- Include files
#include "Include/GotobiDetector.mqh"
#include "Include/MLOptimizer.mqh"
#include "Include/AdaptiveParams.mqh"
#include "Include/RiskManager.mqh"
#include "Include/LotCalculator.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//--- 基本設定
input group "=== 基本設定 ==="
input string   InpSymbol           = "USDJPY";    // 取引シンボル
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;  // タイムフレーム
input int      InpMagicNumber      = 20241224;    // マジックナンバー
input string   InpComment          = "GotobiML";  // 注文コメント

//--- Fintokei資金管理設定
input group "=== Fintokei資金管理 ==="
input double   InpInitialBalance   = 2000000;     // 初期資金（円）
input double   InpDailyMaxLossPct  = 4.5;         // 日次最大損失率（%）※安全マージン
input double   InpTotalMaxLossPct  = 9.0;         // 全体最大損失率（%）※安全マージン
input double   InpMaxConcurrentRisk = 3.0;        // 同時ポジションリスク上限（%）
input double   InpDDThreshold      = 6.0;         // ドローダウン閾値（%）

//--- リスク管理設定
input group "=== リスク管理 ==="
input double   InpRiskPercent      = 2.0;         // 1トレードリスク（%）
input double   InpMinSLPips        = 5.0;         // 最小SL幅（pips）
input double   InpMaxSLPips        = 50.0;        // 最大SL幅（pips）
input double   InpATRMultiplierSL  = 1.0;         // SL ATR乗数
input double   InpATRMultiplierTP  = 1.5;         // TP ATR乗数

//--- 機械学習設定
input group "=== 機械学習設定 ==="
input bool     InpUseMLOptimization = true;       // ML最適化を使用
input int      InpDefaultSlot      = 24;          // デフォルトスロット（6:00 JST）
input bool     InpLogMLDecision    = true;        // ML判断をログ出力

//--- 取引時間設定（日本時間）
input group "=== 取引時間設定（JST） ==="
input int      InpEntryStartHour   = 0;           // エントリー開始時刻
input int      InpEntryEndHour     = 9;           // エントリー終了時刻
input int      InpNakaneHour       = 9;           // 仲値時刻（時）
input int      InpNakaneMinute     = 55;          // 仲値時刻（分）
input int      InpExitStartHour    = 9;           // 決済開始時刻（時）
input int      InpExitStartMinute  = 50;          // 決済開始時刻（分）
input bool     InpAllowShortAfter  = true;        // 仲値後ショート許可

//--- スプレッド設定
input group "=== スプレッド設定 ==="
input double   InpMaxSpreadMultiplier = 1.5;      // 最大スプレッド倍率
input bool     InpAvoidMondayMorning = true;      // 月曜早朝を回避

//--- 相関設定
input group "=== 相関設定 ==="
input string   InpCorrelationSymbol = "EURUSD";   // 相関監視シンボル
input double   InpCorrelationThreshold = 0.8;     // 相関係数閾値

//--- 金曜ゴトー日設定
input group "=== 金曜ゴトー日設定 ==="
input bool     InpFridayBoost      = true;        // 金曜ゴトー日リスク増加
input double   InpFridayRiskMult   = 1.3;         // 金曜日リスク乗数

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
//--- モジュールインスタンス
CGotobiDetector  g_gotobiDetector;
CMLOptimizer     g_mlOptimizer;
CAdaptiveParams  g_adaptiveParams;
CRiskManager     g_riskManager;
CLotCalculator   g_lotCalculator;
CTrade           g_trade;

//--- 状態管理
bool    g_isInitialized = false;
bool    g_isGotobiTradingDay = false;
bool    g_hasEnteredToday = false;
bool    g_hasExitedToday = false;
bool    g_isInPosition = false;
datetime g_lastTradeDate = 0;

//--- サーバー時間オフセット（JST = UTC+9）
int     g_serverTimeOffset = 0;  // サーバー時間からJSTへのオフセット（秒）

//--- ポジション情報
ulong   g_currentTicket = 0;
datetime g_entryTime = 0;
double  g_entryPrice = 0;
double  g_entrySL = 0;
double  g_entryTP = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==============================================");
   Print("GotobiEA_ML 初期化開始");
   Print("==============================================");

   //--- シンボルチェック
   if(InpSymbol != _Symbol)
   {
      Print("警告: 設定シンボル(", InpSymbol, ")と適用シンボル(", _Symbol, ")が異なります");
   }

   //--- サーバー時間オフセット計算（要調整）
   // 多くのブローカーはGMT+2 or GMT+3（サマータイム）
   // JST = GMT+9 なので、オフセットは 6-7時間
   g_serverTimeOffset = 6 * 3600;  // デフォルト6時間（GMT+3ブローカー想定）

   //--- トレードオブジェクト初期化
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.SetAsyncMode(false);

   //--- モジュール初期化
   if(!InitializeModules())
   {
      Print("モジュール初期化失敗");
      return INIT_FAILED;
   }

   //--- タイマー設定（1分ごと）
   EventSetTimer(60);

   //--- 初期状態チェック
   CheckDailyState();
   CheckExistingPositions();

   g_isInitialized = true;

   Print("==============================================");
   Print("GotobiEA_ML 初期化完了");
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   Print("GotobiEA_ML 終了 理由コード: ", reason);
}

//+------------------------------------------------------------------+
//| モジュール初期化                                                  |
//+------------------------------------------------------------------+
bool InitializeModules()
{
   string symbol = (_Symbol != "" ? _Symbol : InpSymbol);

   //--- ゴトー日判定初期化
   // コンストラクタで自動初期化

   //--- 機械学習初期化
   if(!g_mlOptimizer.Initialize(symbol))
   {
      Print("MLOptimizer 初期化失敗");
      return false;
   }

   //--- 適応的パラメータ初期化
   if(!g_adaptiveParams.Initialize(symbol, 14, InpATRMultiplierSL, InpATRMultiplierTP))
   {
      Print("AdaptiveParams 初期化失敗");
      return false;
   }
   g_adaptiveParams.SetMaxSpreadMultiplier(InpMaxSpreadMultiplier);
   g_adaptiveParams.SetSlLimits(InpMinSLPips, InpMaxSLPips);

   //--- リスク管理初期化
   if(!g_riskManager.Initialize(symbol, InpInitialBalance))
   {
      Print("RiskManager 初期化失敗");
      return false;
   }
   g_riskManager.SetFintokeiSettings(InpDailyMaxLossPct, InpTotalMaxLossPct,
                                     InpMaxConcurrentRisk, InpDDThreshold);

   //--- ロット計算初期化
   if(!g_lotCalculator.Initialize(symbol))
   {
      Print("LotCalculator 初期化失敗");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 日次状態チェック                                                  |
//+------------------------------------------------------------------+
void CheckDailyState()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime mdt;
   TimeToStruct(currentTime, mdt);

   //--- 日付変更チェック
   datetime todayDate = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                  mdt.year, mdt.mon, mdt.day));

   if(todayDate != g_lastTradeDate)
   {
      g_lastTradeDate = todayDate;
      g_hasEnteredToday = false;
      g_hasExitedToday = false;

      Print("日付変更検出 リセット実行");
   }

   //--- ゴトー日チェック
   g_isGotobiTradingDay = g_gotobiDetector.IsTodayGotobiTradingDay();

   if(g_isGotobiTradingDay)
   {
      Print("本日はゴトー日取引日です");
      g_gotobiDetector.LogGotobiInfo(currentTime);
   }
}

//+------------------------------------------------------------------+
//| 既存ポジションチェック                                            |
//+------------------------------------------------------------------+
void CheckExistingPositions()
{
   g_isInPosition = false;
   g_currentTicket = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            g_isInPosition = true;
            g_currentTicket = ticket;
            g_entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            g_entrySL = PositionGetDouble(POSITION_SL);
            g_entryTP = PositionGetDouble(POSITION_TP);

            Print("既存ポジション検出 チケット: ", ticket);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_isInitialized)
      return;

   //--- スプレッド更新
   g_adaptiveParams.UpdateSpread();

   //--- ドローダウン更新
   g_riskManager.UpdateDrawdown();

   //--- ポジション監視
   if(g_isInPosition)
   {
      MonitorPosition();
   }

   //--- 強制決済チェック
   if(g_riskManager.ShouldForceClose() && g_isInPosition)
   {
      Print("リスク限度到達 強制決済実行");
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_isInitialized)
      return;

   //--- 日次状態チェック
   CheckDailyState();

   //--- ゴトー日でない場合はスキップ
   if(!g_isGotobiTradingDay)
      return;

   //--- VaR・相関更新（1時間ごと）
   static datetime lastUpdateTime = 0;
   datetime currentTime = TimeCurrent();

   if(currentTime - lastUpdateTime >= 3600)
   {
      g_riskManager.UpdateVaR();
      g_riskManager.UpdateCorrelation(InpCorrelationSymbol);
      lastUpdateTime = currentTime;
   }

   //--- 時間ベースの処理
   ProcessTimeBasedLogic();
}

//+------------------------------------------------------------------+
//| 時間ベースロジック処理                                            |
//+------------------------------------------------------------------+
void ProcessTimeBasedLogic()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime mdt;
   TimeToStruct(currentTime, mdt);

   //--- サーバー時間をJSTに変換
   datetime jstTime = currentTime + g_serverTimeOffset;
   MqlDateTime jstMdt;
   TimeToStruct(jstTime, jstMdt);

   int jstHour = jstMdt.hour;
   int jstMinute = jstMdt.min;

   //--- エントリー時間帯チェック
   bool isEntryTime = (jstHour >= InpEntryStartHour && jstHour < InpEntryEndHour);

   //--- 決済時間帯チェック
   bool isExitTime = (jstHour == InpExitStartHour && jstMinute >= InpExitStartMinute) ||
                     (jstHour == InpNakaneHour && jstMinute <= InpNakaneMinute);

   //--- 仲値後ショート時間帯チェック
   bool isShortTime = InpAllowShortAfter &&
                      (jstHour == InpNakaneHour && jstMinute > InpNakaneMinute) ||
                      (jstHour == 10 && jstMinute <= 30);

   //--- エントリー処理
   if(isEntryTime && !g_hasEnteredToday && !g_isInPosition)
   {
      ProcessEntry(jstHour, jstMinute);
   }

   //--- 決済処理
   if(isExitTime && g_isInPosition && !g_hasExitedToday)
   {
      ProcessExit();
   }

   //--- 仲値後ショート処理
   if(isShortTime && !g_isInPosition && g_hasExitedToday)
   {
      ProcessShortEntry();
   }
}

//+------------------------------------------------------------------+
//| エントリー処理                                                    |
//+------------------------------------------------------------------+
void ProcessEntry(int jstHour, int jstMinute)
{
   //--- 現在のスロット計算
   int currentSlot = jstHour * 4 + jstMinute / 15;

   //--- ML最適スロット取得
   int optimalSlot = InpUseMLOptimization ? g_mlOptimizer.GetOptimalSlotIndex() : InpDefaultSlot;

   //--- 最適スロットでない場合はスキップ
   if(currentSlot != optimalSlot)
      return;

   //--- 取引条件チェック
   if(!CheckEntryConditions())
      return;

   //--- ML判断ログ
   if(InpLogMLDecision)
   {
      g_mlOptimizer.LogMLDecision();
   }

   //--- エントリー実行
   ExecuteLongEntry();
}

//+------------------------------------------------------------------+
//| エントリー条件チェック                                            |
//+------------------------------------------------------------------+
bool CheckEntryConditions()
{
   //--- 適応的パラメータチェック
   if(!g_adaptiveParams.IsTradeConditionOK())
   {
      Print("取引条件NG: 適応的パラメータ");
      return false;
   }

   //--- 月曜早朝チェック
   if(InpAvoidMondayMorning && g_adaptiveParams.IsMondayEarlyMorning())
   {
      Print("取引条件NG: 月曜早朝");
      return false;
   }

   //--- 動的SL計算
   double slPips = g_adaptiveParams.GetDynamicSL();
   double riskAmount = g_lotCalculator.CalculateLotByRisk(InpRiskPercent, slPips) *
                       g_lotCalculator.CalculateLossPerLot(slPips);

   //--- Fintokeiリスクチェック
   if(!g_riskManager.CanOpenPosition(riskAmount))
   {
      Print("取引条件NG: Fintokeiリスク制限");
      g_riskManager.LogFintokeiStatus();
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ロングエントリー実行                                              |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   //--- 現在価格取得
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- 動的SL/TP計算
   double slPips = g_adaptiveParams.GetDynamicSL();
   double tpPips = g_adaptiveParams.GetDynamicTP();

   double slPrice = g_adaptiveParams.GetDynamicSLPrice(ask, true);
   double tpPrice = g_adaptiveParams.GetDynamicTPPrice(ask, true);

   //--- リスク%計算（金曜ゴトー日ブースト対応）
   double riskPct = InpRiskPercent;
   bool isFridayGotobi = g_gotobiDetector.IsFridayGotobiDay(TimeCurrent());

   if(InpFridayBoost && isFridayGotobi)
   {
      riskPct *= InpFridayRiskMult;
      Print("金曜ゴトー日 リスク増加: ", DoubleToString(riskPct, 1), "%");
   }

   //--- 安全なロットサイズ計算
   double lots = g_riskManager.GetSafeLotSize(slPips, riskPct);

   //--- ロット有効性チェック
   if(!g_lotCalculator.IsValidLot(lots))
   {
      Print("無効なロットサイズ: ", lots);
      return;
   }

   //--- ログ出力
   g_lotCalculator.LogLotCalculation(riskPct, slPips, lots);
   g_adaptiveParams.LogAdaptiveParams();

   //--- 注文実行
   if(g_trade.Buy(lots, _Symbol, ask, slPrice, tpPrice, InpComment))
   {
      g_currentTicket = g_trade.ResultOrder();
      g_isInPosition = true;
      g_hasEnteredToday = true;
      g_entryTime = TimeCurrent();
      g_entryPrice = ask;
      g_entrySL = slPrice;
      g_entryTP = tpPrice;

      Print("=== ロングエントリー成功 ===");
      Print("チケット: ", g_currentTicket);
      Print("価格: ", DoubleToString(ask, _Digits));
      Print("SL: ", DoubleToString(slPrice, _Digits), " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", DoubleToString(tpPrice, _Digits), " (", DoubleToString(tpPips, 1), " pips)");
      Print("ロット: ", DoubleToString(lots, 2));
      Print("金曜ゴトー日: ", isFridayGotobi ? "Yes" : "No");
      Print("===========================");
   }
   else
   {
      Print("注文失敗: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 決済処理                                                          |
//+------------------------------------------------------------------+
void ProcessExit()
{
   if(!g_isInPosition || g_currentTicket == 0)
      return;

   //--- ポジション情報取得
   if(!PositionSelectByTicket(g_currentTicket))
   {
      g_isInPosition = false;
      g_currentTicket = 0;
      return;
   }

   //--- 決済実行
   double lots = PositionGetDouble(POSITION_VOLUME);

   if(g_trade.PositionClose(g_currentTicket))
   {
      double profit = PositionGetDouble(POSITION_PROFIT);
      double pips = 0;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         pips = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - g_entryPrice) /
                g_lotCalculator.GetSymbolPipSize();
      }

      //--- MLトレード記録
      int maState = g_mlOptimizer.GetCurrentMAState(_Symbol);
      MqlDateTime mdt;
      TimeToStruct(g_entryTime, mdt);
      bool isFridayGotobi = g_gotobiDetector.IsFridayGotobiDay(g_entryTime);

      g_mlOptimizer.RecordTrade(g_entryTime, TimeCurrent(), profit, pips,
                                maState, mdt.day_of_week, isFridayGotobi);

      Print("=== ポジション決済 ===");
      Print("損益: ", DoubleToString(profit, 0));
      Print("pips: ", DoubleToString(pips, 1));
      Print("======================");

      g_isInPosition = false;
      g_currentTicket = 0;
      g_hasExitedToday = true;
   }
   else
   {
      Print("決済失敗: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 仲値後ショートエントリー                                          |
//+------------------------------------------------------------------+
void ProcessShortEntry()
{
   //--- 条件チェック
   if(!CheckEntryConditions())
      return;

   //--- 現在価格取得
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- 動的SL/TP計算（ショート用）
   double slPips = g_adaptiveParams.GetDynamicSL();
   double tpPips = g_adaptiveParams.GetDynamicTP() * 0.7;  // ショートは控えめ

   double slPrice = g_adaptiveParams.GetDynamicSLPrice(bid, false);
   double tpPrice = g_adaptiveParams.GetDynamicTPPrice(bid, false);

   //--- ロットサイズ計算（リスク控えめ）
   double lots = g_riskManager.GetSafeLotSize(slPips, InpRiskPercent * 0.7);

   if(!g_lotCalculator.IsValidLot(lots))
      return;

   //--- 注文実行
   if(g_trade.Sell(lots, _Symbol, bid, slPrice, tpPrice, InpComment + "_Short"))
   {
      g_currentTicket = g_trade.ResultOrder();
      g_isInPosition = true;
      g_entryTime = TimeCurrent();
      g_entryPrice = bid;
      g_entrySL = slPrice;
      g_entryTP = tpPrice;

      Print("=== ショートエントリー成功 ===");
      Print("チケット: ", g_currentTicket);
      Print("価格: ", DoubleToString(bid, _Digits));
      Print("ロット: ", DoubleToString(lots, 2));
      Print("==============================");
   }
}

//+------------------------------------------------------------------+
//| ポジション監視                                                    |
//+------------------------------------------------------------------+
void MonitorPosition()
{
   if(!PositionSelectByTicket(g_currentTicket))
   {
      //--- ポジションがなくなった（TP/SLヒット）
      g_isInPosition = false;
      g_currentTicket = 0;

      Print("ポジションクローズ検出（TP/SLヒット）");

      //--- 履歴から損益取得してML記録
      HistorySelectByPosition(g_currentTicket);
      int deals = HistoryDealsTotal();
      if(deals > 0)
      {
         ulong dealTicket = HistoryDealGetTicket(deals - 1);
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);

         double pips = (closePrice - g_entryPrice) / g_lotCalculator.GetSymbolPipSize();

         int maState = g_mlOptimizer.GetCurrentMAState(_Symbol);
         MqlDateTime mdt;
         TimeToStruct(g_entryTime, mdt);
         bool isFridayGotobi = g_gotobiDetector.IsFridayGotobiDay(g_entryTime);

         g_mlOptimizer.RecordTrade(g_entryTime, TimeCurrent(), profit, pips,
                                   maState, mdt.day_of_week, isFridayGotobi);
      }

      return;
   }

   //--- 含み損チェック（Fintokei対応）
   double unrealizedPnL = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   if(g_riskManager.ShouldForceClose())
   {
      Print("含み損警告ライン到達");
   }
}

//+------------------------------------------------------------------+
//| 全ポジション決済                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            g_trade.PositionClose(ticket);
         }
      }
   }

   g_isInPosition = false;
   g_currentTicket = 0;
}

//+------------------------------------------------------------------+
//| Tester function                                                   |
//+------------------------------------------------------------------+
double OnTester()
{
   //--- バックテスト結果計算
   double profit = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double winRate = TesterStatistics(STAT_PROFIT_TRADES) /
                    MathMax(1, TesterStatistics(STAT_TRADES)) * 100;

   //--- カスタム最適化基準
   // 利益 / ドローダウン × 勝率重み
   double criterion = 0;
   if(drawdown > 0)
   {
      criterion = (profit / drawdown) * (winRate / 50);
   }

   Print("=== バックテスト結果 ===");
   Print("利益: ", DoubleToString(profit, 0));
   Print("DD: ", DoubleToString(drawdown, 2), "%");
   Print("勝率: ", DoubleToString(winRate, 1), "%");
   Print("基準値: ", DoubleToString(criterion, 2));
   Print("========================");

   return criterion;
}

//+------------------------------------------------------------------+
