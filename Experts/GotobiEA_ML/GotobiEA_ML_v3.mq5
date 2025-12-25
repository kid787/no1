//+------------------------------------------------------------------+
//|                                              GotobiEA_ML_v3.mq5 |
//|                      Gotobi Day EA with Machine Learning v3.0   |
//|                              仲値直前エントリー最適化版          |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML v3"
#property link      ""
#property version   "3.00"
#property description "ゴトー日手法 v3.0 - 仲値直前エントリー最適化"
#property description "Fintokei資金管理ルール完全対応"
#property description "エントリー時間を仲値に近づけて勝率向上"

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
input int      InpMagicNumber      = 20241226;    // マジックナンバー
input string   InpComment          = "GotobiV3";  // 注文コメント

//--- サーバー時間設定
input group "=== サーバー時間設定 ==="
input int      InpServerGMTOffset  = 3;           // サーバーGMTオフセット（TitanFX=3）
input bool     InpUseSummerTime    = false;       // サマータイム考慮

//--- Fintokei資金管理設定
input group "=== Fintokei資金管理 ==="
input double   InpInitialBalance   = 2000000;     // 初期資金（円）
input double   InpDailyMaxLossPct  = 4.5;         // 日次最大損失率（%）
input double   InpTotalMaxLossPct  = 9.0;         // 全体最大損失率（%）
input double   InpMaxConcurrentRisk = 3.0;        // 同時ポジションリスク上限（%）
input double   InpDDThreshold      = 6.0;         // ドローダウン閾値（%）

//--- リスク管理設定（高ロット戦略）
input group "=== リスク管理（高ロット戦略） ==="
input double   InpRiskPercent      = 2.5;         // 1トレードリスク（%）※高め
input double   InpMinSLPips        = 8.0;         // 最小SL幅（pips）※小さめ
input double   InpMaxSLPips        = 25.0;        // 最大SL幅（pips）※小さめ
input double   InpATRMultiplierSL  = 0.7;         // SL ATR乗数（小さめ=高ロット）
input double   InpATRMultiplierTP  = 1.05;        // TP ATR乗数（RR 1.5:1）

//--- エントリー設定（仲値直前）
input group "=== エントリー設定（仲値直前） ==="
input bool     InpUseMLOptimization = false;      // ML最適化を使用
input int      InpFixedEntryHour   = 8;           // エントリー時刻（時）JST ※8時台
input int      InpFixedEntryMinute = 0;           // エントリー時刻（分）JST
input int      InpEntryWindowMin   = 45;          // エントリー許容時間幅（分）※8:00-8:45
input bool     InpLogDecision      = true;        // 判断をログ出力

//--- 決済設定
input group "=== 決済設定 ==="
input bool     InpUseTimeExit      = true;        // 時間決済を使用 ※仲値で決済
input int      InpNakaneHour       = 9;           // 仲値時刻（時）JST
input int      InpNakaneMinute     = 50;          // 仲値決済時刻（分）JST ※9:50
input int      InpMaxHoldingHours  = 4;           // 最大保有時間（時間）

//--- トレーリングストップ設定
input group "=== トレーリングストップ ==="
input bool     InpUseTrailingStop  = true;        // トレーリングストップ使用
input double   InpTrailingStartPips = 10.0;       // トレーリング開始（pips）
input double   InpTrailingStepPips = 5.0;         // トレーリングステップ（pips）

//--- スプレッド設定
input group "=== スプレッド設定 ==="
input double   InpMaxSpreadPips    = 2.5;         // 最大許容スプレッド（pips）※厳しめ
input double   InpMaxSpreadMultiplier = 1.8;      // 最大スプレッド倍率
input bool     InpAvoidMondayMorning = true;      // 月曜早朝を回避

//--- 金曜ゴトー日設定
input group "=== 金曜ゴトー日設定 ==="
input bool     InpFridayBoost      = true;        // 金曜ゴトー日リスク増加
input double   InpFridayRiskMult   = 1.3;         // 金曜日リスク乗数

//--- フィルター設定
input group "=== フィルター設定 ==="
input bool     InpUseTrendFilter   = true;        // トレンドフィルター使用
input int      InpTrendMAPeriod    = 20;          // トレンド判定MA期間

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

//--- サーバー時間オフセット（秒）
int     g_serverTimeOffset = 0;

//--- ポジション情報
ulong   g_currentTicket = 0;
datetime g_entryTime = 0;
double  g_entryPrice = 0;
double  g_entrySL = 0;
double  g_entryTP = 0;
double  g_trailingStopPrice = 0;
ENUM_POSITION_TYPE g_positionType;

//--- トレンドフィルター用
int     g_trendMAHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==============================================");
   Print("GotobiEA_ML v3.0 初期化開始");
   Print("==============================================");

   //--- シンボルチェック
   if(InpSymbol != _Symbol)
   {
      Print("警告: 設定シンボル(", InpSymbol, ")と適用シンボル(", _Symbol, ")が異なります");
   }

   //--- サーバー時間オフセット計算
   int gmtOffset = InpServerGMTOffset;
   if(InpUseSummerTime)
      gmtOffset += 1;

   g_serverTimeOffset = (9 - gmtOffset) * 3600;

   Print("サーバーGMTオフセット: GMT+", gmtOffset);
   Print("JST変換オフセット: ", g_serverTimeOffset / 3600, "時間");

   //--- トレードオブジェクト初期化
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.SetAsyncMode(false);

   //--- トレンドフィルター用MA初期化
   if(InpUseTrendFilter)
   {
      g_trendMAHandle = iMA(_Symbol, PERIOD_H1, InpTrendMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      if(g_trendMAHandle == INVALID_HANDLE)
      {
         Print("トレンドMA初期化失敗");
         return INIT_FAILED;
      }
   }

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
   Print("GotobiEA_ML v3.0 初期化完了");
   LogCurrentSettings();
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 現在の設定をログ出力                                              |
//+------------------------------------------------------------------+
void LogCurrentSettings()
{
   Print("--- v3.0 主要設定 ---");
   Print("リスク%: ", InpRiskPercent, " (高ロット戦略)");
   Print("SL ATR乗数: ", InpATRMultiplierSL, " (小さめ)");
   Print("TP ATR乗数: ", InpATRMultiplierTP, " (RR 1.5:1)");
   Print("エントリー時刻(JST): ", InpFixedEntryHour, ":", InpFixedEntryMinute, " - ",
         InpFixedEntryHour, ":", InpFixedEntryMinute + InpEntryWindowMin);
   Print("仲値決済: ", InpUseTimeExit ? "ON (9:50)" : "OFF");
   Print("トレーリングストップ: ", InpUseTrailingStop ? "ON" : "OFF");
   Print("トレンドフィルター: ", InpUseTrendFilter ? "ON" : "OFF");
   Print("金曜ブースト: ", InpFridayBoost ? "ON" : "OFF");
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_trendMAHandle != INVALID_HANDLE)
      IndicatorRelease(g_trendMAHandle);

   Print("GotobiEA_ML v3.0 終了 理由コード: ", reason);
}

//+------------------------------------------------------------------+
//| モジュール初期化                                                  |
//+------------------------------------------------------------------+
bool InitializeModules()
{
   string symbol = (_Symbol != "" ? _Symbol : InpSymbol);

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
//| サーバー時間をJSTに変換                                           |
//+------------------------------------------------------------------+
datetime ServerTimeToJST(datetime serverTime)
{
   return serverTime + g_serverTimeOffset;
}

//+------------------------------------------------------------------+
//| JSTの時間と分を取得                                               |
//+------------------------------------------------------------------+
void GetJSTTime(int &hour, int &minute)
{
   datetime jstTime = ServerTimeToJST(TimeCurrent());
   MqlDateTime mdt;
   TimeToStruct(jstTime, mdt);
   hour = mdt.hour;
   minute = mdt.min;
}

//+------------------------------------------------------------------+
//| 日次状態チェック                                                  |
//+------------------------------------------------------------------+
void CheckDailyState()
{
   datetime currentTime = TimeCurrent();
   datetime jstTime = ServerTimeToJST(currentTime);
   MqlDateTime mdt;
   TimeToStruct(jstTime, mdt);

   //--- JST基準で日付変更チェック
   datetime todayDate = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                  mdt.year, mdt.mon, mdt.day));

   if(todayDate != g_lastTradeDate)
   {
      g_lastTradeDate = todayDate;
      g_hasEnteredToday = false;
      g_hasExitedToday = false;
      g_trailingStopPrice = 0;

      Print("日付変更検出(JST) リセット実行 ", TimeToString(jstTime, TIME_DATE));
   }

   //--- ゴトー日チェック（JST基準）
   g_isGotobiTradingDay = g_gotobiDetector.IsTodayGotobiTradingDay();

   if(g_isGotobiTradingDay && !g_hasEnteredToday)
   {
      Print("本日はゴトー日取引日です (JST: ", TimeToString(jstTime, TIME_DATE), ")");
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
            g_entryTime = (datetime)PositionGetInteger(POSITION_TIME);
            g_positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            Print("既存ポジション検出 チケット: ", ticket);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| トレンドフィルター（上昇トレンドのみロング）                       |
//+------------------------------------------------------------------+
bool IsTrendFavorable()
{
   if(!InpUseTrendFilter)
      return true;

   if(g_trendMAHandle == INVALID_HANDLE)
      return true;

   double ma[];
   ArraySetAsSeries(ma, true);

   if(CopyBuffer(g_trendMAHandle, 0, 0, 3, ma) < 3)
      return true;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 価格がMAより上なら上昇トレンド
   bool isUptrend = (currentPrice > ma[0]);

   // MAが上向きか
   bool isMARising = (ma[0] > ma[1] && ma[1] > ma[2]);

   if(InpLogDecision)
   {
      Print("トレンドフィルター: 価格=", DoubleToString(currentPrice, 3),
            " MA=", DoubleToString(ma[0], 3),
            " 上昇トレンド=", isUptrend ? "Yes" : "No",
            " MA上向き=", isMARising ? "Yes" : "No");
   }

   // 価格がMAより上、またはMA上向きならOK
   return (isUptrend || isMARising);
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

      //--- トレーリングストップ処理
      if(InpUseTrailingStop)
         ProcessTrailingStop();
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

   //--- VaR更新（1時間ごと）
   static datetime lastUpdateTime = 0;
   datetime currentTime = TimeCurrent();

   if(currentTime - lastUpdateTime >= 3600)
   {
      g_riskManager.UpdateVaR();
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
   int jstHour, jstMinute;
   GetJSTTime(jstHour, jstMinute);

   //--- エントリー時間帯チェック（8:00-8:45 JST）
   int entryStartMin = InpFixedEntryHour * 60 + InpFixedEntryMinute;
   int entryEndMin = entryStartMin + InpEntryWindowMin;
   int currentMin = jstHour * 60 + jstMinute;

   bool isEntryTime = (currentMin >= entryStartMin && currentMin < entryEndMin);

   //--- ロングエントリー処理
   if(isEntryTime && !g_hasEnteredToday && !g_isInPosition)
   {
      ProcessLongEntry(jstHour, jstMinute);
   }

   //--- 仲値時間決済処理（9:50 JST）
   if(InpUseTimeExit && g_isInPosition)
   {
      int nakaneMin = InpNakaneHour * 60 + InpNakaneMinute;
      if(currentMin >= nakaneMin && currentMin <= nakaneMin + 5)
      {
         ProcessTimeExit();
      }
   }

   //--- 最大保有時間チェック
   if(g_isInPosition && InpMaxHoldingHours > 0)
   {
      datetime holdingTime = TimeCurrent() - g_entryTime;
      if(holdingTime >= InpMaxHoldingHours * 3600)
      {
         Print("最大保有時間超過 決済実行");
         ClosePosition(g_currentTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| ロングエントリー処理                                              |
//+------------------------------------------------------------------+
void ProcessLongEntry(int jstHour, int jstMinute)
{
   //--- 取引条件チェック
   if(!CheckEntryConditions())
      return;

   //--- トレンドフィルター
   if(!IsTrendFavorable())
   {
      if(InpLogDecision)
         Print("エントリースキップ: トレンド不適合");
      return;
   }

   //--- 判断ログ
   if(InpLogDecision)
   {
      Print("=== エントリー判断 (JST ", jstHour, ":", jstMinute, ") ===");
   }

   //--- エントリー実行
   ExecuteLongEntry();
}

//+------------------------------------------------------------------+
//| エントリー条件チェック                                            |
//+------------------------------------------------------------------+
bool CheckEntryConditions()
{
   //--- スプレッドチェック（絶対値）
   double currentSpread = g_adaptiveParams.GetCurrentSpread();
   if(currentSpread > InpMaxSpreadPips)
   {
      if(InpLogDecision)
         Print("取引条件NG: スプレッド過大 ", DoubleToString(currentSpread, 1), " > ", InpMaxSpreadPips);
      return false;
   }

   //--- 月曜早朝チェック
   if(InpAvoidMondayMorning && g_adaptiveParams.IsMondayEarlyMorning())
   {
      if(InpLogDecision)
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
      if(InpLogDecision)
      {
         Print("取引条件NG: Fintokeiリスク制限");
         g_riskManager.LogFintokeiStatus();
      }
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
      g_trailingStopPrice = slPrice;
      g_positionType = POSITION_TYPE_BUY;

      int jstH, jstM;
      GetJSTTime(jstH, jstM);

      Print("=== ロングエントリー成功 (v3) ===");
      Print("JST時刻: ", jstH, ":", jstM);
      Print("チケット: ", g_currentTicket);
      Print("価格: ", DoubleToString(ask, _Digits));
      Print("SL: ", DoubleToString(slPrice, _Digits), " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", DoubleToString(tpPrice, _Digits), " (", DoubleToString(tpPips, 1), " pips)");
      Print("RR比: 1:", DoubleToString(tpPips/slPips, 2));
      Print("ロット: ", DoubleToString(lots, 2));
      Print("金曜ゴトー日: ", isFridayGotobi ? "Yes" : "No");
      Print("=================================");
   }
   else
   {
      Print("注文失敗: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップ処理                                          |
//+------------------------------------------------------------------+
void ProcessTrailingStop()
{
   if(!g_isInPosition || g_currentTicket == 0)
      return;

   if(!PositionSelectByTicket(g_currentTicket))
      return;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pipSize = g_lotCalculator.GetSymbolPipSize();

   // 利益pips計算
   double profitPips = (currentPrice - g_entryPrice) / pipSize;

   // トレーリング開始条件
   if(profitPips < InpTrailingStartPips)
      return;

   // 新しいSL計算
   double newSL = currentPrice - (InpTrailingStepPips * pipSize);

   // 現在のSLより高い場合のみ更新
   if(newSL > g_trailingStopPrice + (InpTrailingStepPips * pipSize * 0.5))
   {
      if(g_trade.PositionModify(g_currentTicket, newSL, g_entryTP))
      {
         g_trailingStopPrice = newSL;
         g_entrySL = newSL;

         Print("トレーリングストップ更新: ", DoubleToString(newSL, _Digits),
               " (利益: ", DoubleToString(profitPips, 1), " pips)");
      }
   }
}

//+------------------------------------------------------------------+
//| 時間決済処理                                                      |
//+------------------------------------------------------------------+
void ProcessTimeExit()
{
   if(!g_isInPosition || g_currentTicket == 0)
      return;

   // 利益が出ている場合のみ時間決済
   if(!PositionSelectByTicket(g_currentTicket))
      return;

   double profit = PositionGetDouble(POSITION_PROFIT);

   // 含み益の場合は仲値で決済
   if(profit > 0)
   {
      Print("仲値時刻到達 利益確定決済 (含み益: ", DoubleToString(profit, 0), "円)");
      ClosePosition(g_currentTicket);
   }
   else
   {
      // 含み損の場合はTP/SLに任せる
      Print("仲値時刻 含み損のため継続保有 (含み損: ", DoubleToString(profit, 0), "円)");
   }
}

//+------------------------------------------------------------------+
//| ポジション決済                                                    |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
   {
      g_isInPosition = false;
      g_currentTicket = 0;
      return;
   }

   double profit = PositionGetDouble(POSITION_PROFIT);
   double lots = PositionGetDouble(POSITION_VOLUME);

   if(g_trade.PositionClose(ticket))
   {
      double pips = 0;
      double pipSize = g_lotCalculator.GetSymbolPipSize();

      if(g_positionType == POSITION_TYPE_BUY)
         pips = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - g_entryPrice) / pipSize;
      else
         pips = (g_entryPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / pipSize;

      //--- MLトレード記録
      if(InpUseMLOptimization)
      {
         int maState = g_mlOptimizer.GetCurrentMAState(_Symbol);
         MqlDateTime mdt;
         TimeToStruct(g_entryTime, mdt);
         bool isFridayGotobi = g_gotobiDetector.IsFridayGotobiDay(g_entryTime);

         g_mlOptimizer.RecordTrade(g_entryTime, TimeCurrent(), profit, pips,
                                   maState, mdt.day_of_week, isFridayGotobi);
      }

      Print("=== ポジション決済 (v3) ===");
      Print("損益: ", DoubleToString(profit, 0), " 円");
      Print("pips: ", DoubleToString(pips, 1));
      Print("===========================");

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
//| ポジション監視                                                    |
//+------------------------------------------------------------------+
void MonitorPosition()
{
   if(!PositionSelectByTicket(g_currentTicket))
   {
      //--- ポジションがなくなった（TP/SLヒット）
      Print("ポジションクローズ検出（TP/SLヒット）");

      //--- 履歴から損益取得してML記録
      if(InpUseMLOptimization)
      {
         RecordClosedTrade();
      }

      g_isInPosition = false;
      g_currentTicket = 0;
      g_hasExitedToday = true;
      return;
   }
}

//+------------------------------------------------------------------+
//| クローズしたトレードを記録                                        |
//+------------------------------------------------------------------+
void RecordClosedTrade()
{
   HistorySelect(g_entryTime, TimeCurrent());
   int deals = HistoryDealsTotal();

   for(int i = deals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == InpMagicNumber &&
         HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         double pipSize = g_lotCalculator.GetSymbolPipSize();

         double pips = 0;
         if(g_positionType == POSITION_TYPE_BUY)
            pips = (closePrice - g_entryPrice) / pipSize;
         else
            pips = (g_entryPrice - closePrice) / pipSize;

         int maState = g_mlOptimizer.GetCurrentMAState(_Symbol);
         MqlDateTime mdt;
         TimeToStruct(g_entryTime, mdt);
         bool isFridayGotobi = g_gotobiDetector.IsFridayGotobiDay(g_entryTime);

         g_mlOptimizer.RecordTrade(g_entryTime, TimeCurrent(), profit, pips,
                                   maState, mdt.day_of_week, isFridayGotobi);

         Print("ML記録: 損益=", DoubleToString(profit, 0), " pips=", DoubleToString(pips, 1));
         break;
      }
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
   double profit = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   double winTrades = TesterStatistics(STAT_PROFIT_TRADES);
   double winRate = trades > 0 ? (winTrades / trades * 100) : 0;
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);

   //--- カスタム最適化基準
   // PF × 勝率 × シャープレシオ / (DD + 1)
   double criterion = 0;
   if(drawdown > 0 && trades > 0)
   {
      criterion = profitFactor * (winRate / 50) * MathMax(sharpeRatio, 0.1) / (drawdown + 1);
   }

   Print("=== バックテスト結果 (v3) ===");
   Print("利益: ", DoubleToString(profit, 0));
   Print("取引数: ", trades);
   Print("勝率: ", DoubleToString(winRate, 1), "%");
   Print("PF: ", DoubleToString(profitFactor, 2));
   Print("DD: ", DoubleToString(drawdown, 2), "%");
   Print("シャープレシオ: ", DoubleToString(sharpeRatio, 2));
   Print("基準値: ", DoubleToString(criterion, 2));
   Print("=============================");

   return criterion;
}

//+------------------------------------------------------------------+
