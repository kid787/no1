//+------------------------------------------------------------------+
//|                                               prop-trends.mq5    |
//|          XAUJPY/XAUUSD Multi-Timeframe Trend Follow EA           |
//|                  Fintokei Challenge Compatible                   |
//+------------------------------------------------------------------+
//| 概要:                                                             |
//| - ダウ理論とSMAを用いたマルチタイムフレーム・トレンドフォロー戦略    |
//| - D1レジームフィルター搭載 (トレンド/レンジ自動判定)               |
//| - 自動戦術切り替え機能 (D1トレンドに応じてLong/Short自動選択)      |
//| - 分割決済対応 (2段階利確でリスク管理)                             |
//+------------------------------------------------------------------+
//| 推奨設定 (XAUJPY 2025年最適化済み):                               |
//| - D1 ADX閾値: 25 | D1トレンド閾値: 1000                           |
//| - 最大ドローダウン: 4% (Fintokei 10%制限に対し6%の安全マージン)    |
//| - プロフィットファクター: 1.52 | シャープレシオ: 2.24              |
//+------------------------------------------------------------------+
#property copyright "prop-trends"
#property link      ""
#property version   "3.0"
#property strict

//--- Include files
#include "Include/RiskManager.mqh"
#include "Include/TrendAnalysis.mqh"
#include "Include/EntryLogic.mqh"
#include "Include/LotCalculator.mqh"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//| 【資金管理設定】                                                   |
//| Fintokeiチャレンジの厳格なリスク管理ルールに準拠した設定            |
//| ※DD10%で即失格のため、0.9%リスクで安全マージンを確保               |
//+------------------------------------------------------------------+
input group "===== 資金管理設定 (Fintokei準拠) ====="
input double   InpInitialBalance = 0;           // 初期資金:バックテスト用の開始資金。0で口座残高を自動取得。ライブでは0推奨
input double   InpRiskPercent = 0.9;            // 1トレードリスク率(%):1回の損切りで失う最大資金の割合。0.9%でDD10%未満を維持
input double   InpMaxDailyLoss = 5.0;           // 1日最大損失率(%):この値に達すると当日のトレード停止。Fintokei5%ルール対応
input double   InpMaxWeeklyLoss = 5.0;          // 週間最大損失率(%):週単位の損失上限。連敗時の追加安全装置として機能
input double   InpMaxTotalLoss = 10.0;          // 全体最大損失率(%):累計損失上限。Fintokeiは10%で即失格のため厳守必須
input double   InpMaxPositionRisk = 3.0;        // 同時ポジション最大リスク(%):複数ポジション保有時の合計リスク上限
input int      InpMaxConsecutiveLosses = 3;     // 連続損失制限:この回数連敗するとトレード一時停止。0で無制限。3回推奨

//+------------------------------------------------------------------+
//| 【トレード設定】                                                   |
//| 基本的なトレード実行に関する設定                                    |
//+------------------------------------------------------------------+
input group "===== トレード設定 ====="
input double   InpMinRiskReward = 1.5;          // 最小リスクリワード比:利益目標÷損失リスク。1.5以上でエントリー許可。低いと回数増加
input int      InpMaxPositions = 1;             // 最大同時ポジション数:同時に保有できるポジション数。1でリスク分散、複数で積極運用
input int      InpMagicNumber = 123456;         // マジックナンバー:このEA専用の識別番号。他EAと区別するため変更可能
input string   InpSymbol = "";                  // 取引シンボル:空欄でチャートの銘柄を自動使用。手動指定も可能(例:XAUJPY)
input int      InpSlippage = 30;                // 許容スリッページ(points):注文時の価格ずれ許容範囲。30が標準、急変時は拡大

//+------------------------------------------------------------------+
//| 【エントリー設定】                                                  |
//| トレード方向とエントリーパターンの有効化設定                         |
//| ※自動戦術モードではD1トレンドに応じて自動切り替え                   |
//+------------------------------------------------------------------+
input group "===== エントリー設定 ====="
input bool     InpEnableLongTrades = true;      // ロング(買い)有効:ONでロングエントリー許可。ゴールドは長期上昇傾向のためON推奨
input bool     InpEnableShortTrades = false;    // ショート(売り)有効:ONでショートエントリー許可。勝率低下リスクがあるためOFF推奨
input bool     InpEnableH4Pullback = true;      // H4押し目/戻り目:4時間足トレンド中の調整を狙う。メイン手法のためON推奨
input bool     InpEnableH1Pullback = true;      // H1押し目/戻り目:1時間足の短期調整を狙う。取引機会を増やすためON推奨
input bool     InpEnableD1Pullback = true;      // D1押し目/戻り目:日足レベルの大きな調整を狙う。高勝率パターンのためON推奨
input bool     InpEnableH4Reversal = true;      // H4トレンド転換:4時間足でトレンド初期を狙う。早期エントリーでRR向上

//+------------------------------------------------------------------+
//| 【分割決済設定】                                                   |
//| 2段階利確でリスク管理を強化                                        |
//| TP1到達時に50%決済→残りはブレイクイーブンで安全確保                 |
//+------------------------------------------------------------------+
input group "===== 分割決済設定 ====="
input bool     InpEnablePartialTP = true;       // 分割決済有効:ONで2段階利確。TP1で半分決済しSLを建値に移動。リスク軽減効果大
input ENUM_TIMEFRAMES InpTP1Timeframe = PERIOD_H1;   // TP1時間足:第1利確目標の基準時間足。H1の直近高値/安値を目標に設定
input int      InpTP1ClosePercent = 50;         // TP1決済割合(%):TP1到達時に決済する割合。50%で半分を確実に利確
input ENUM_TIMEFRAMES InpTP2Timeframe = PERIOD_H4;   // TP2時間足:最終利確目標の基準時間足。H4の直近高値/安値でRR判定にも使用

//+------------------------------------------------------------------+
//| 【トレンドフィルター】                                             |
//| ADX(Average Directional Index)でトレンド強度を測定                 |
//| レンジ相場でのエントリーを回避し、勝率を向上                        |
//+------------------------------------------------------------------+
input group "===== トレンドフィルター ====="
input bool     InpUseADXFilter = true;          // ADXフィルター有効:ONでADXによるトレンド判定。レンジ相場を回避し勝率向上
input int      InpADXPeriod = 14;               // ADX期間:ADX計算に使用するローソク足本数。14が標準。短いと敏感、長いと鈍感
input double   InpADXMinLevel = 20.0;           // ADX最小値:この値以下はレンジ相場と判定しエントリー禁止。20が一般的な基準

//+------------------------------------------------------------------+
//| 【D1レジームフィルター】                                           |
//| 日足のトレンド状況を自動判定し、相場環境に応じたトレードを実行       |
//| ※D1 ADXとSMA20からの乖離でトレンド/レンジを判定                    |
//+------------------------------------------------------------------+
input group "===== D1レジームフィルター ====="
enum ENUM_REGIME_MODE
{
   REGIME_AUTO = 0,        // 自動判定:D1のADXとSMA20乖離で相場環境を自動判定。推奨設定
   REGIME_TREND_UP = 1,    // 強制:上昇トレンド:手動で上昇相場と設定。ロングのみ許可される
   REGIME_TREND_DOWN = 2,  // 強制:下降トレンド:手動で下降相場と設定。ショートのみ許可される
   REGIME_NO_TRADE = 3     // 強制:トレード停止:EAを一時停止。重要指標前などに使用
};
input ENUM_REGIME_MODE InpRegimeMode = REGIME_AUTO;  // D1レジームモード:日足の相場環境判定方法。自動判定が推奨
input double   InpD1ADXThreshold = 25.0;        // D1 ADX閾値:日足ADXがこの値以上でトレンド相場と判定。25はXAUJPY最適化値
input int      InpD1TrendThreshold = 1000;      // D1トレンド閾値(points):SMA20からの乖離幅。1000ptsでトレンド方向確定。XAUJPY最適化値

//+------------------------------------------------------------------+
//| 【自動戦術切り替え】                                               |
//| D1トレンドに応じてLong/Shortを自動切り替え                         |
//| 上昇トレンド→Longのみ、下降トレンド→Shortのみ、レンジ→停止         |
//+------------------------------------------------------------------+
input group "===== 自動戦術切り替え ====="
enum ENUM_TACTIC_MODE
{
   TACTIC_MANUAL = 0,          // 手動:エントリー設定をそのまま使用。自動切り替えなし
   TACTIC_AUTO_DIRECTION = 1,  // 自動:方向切替:D1トレンドに連動してLong/Shortを自動選択。推奨
   TACTIC_AUTO_FULL = 2        // 自動:方向+リスク:方向切替に加えトレンド強度でリスク率も調整
};
input ENUM_TACTIC_MODE InpTacticMode = TACTIC_AUTO_DIRECTION;  // 戦術モード:D1トレンドに応じた自動切り替え設定。方向切替推奨
input double   InpTrendUpRisk = 1.1;            // 上昇トレンド時リスク(%):AUTO_FULL時の上昇相場でのリスク率。強気設定可能
input double   InpTrendDownRisk = 1.0;          // 下降トレンド時リスク(%):AUTO_FULL時の下降相場でのリスク率。やや控えめ推奨
input double   InpRangeRisk = 0.0;              // レンジ時リスク(%):レンジ相場でのリスク率。0でトレード完全停止。安全重視

//+------------------------------------------------------------------+
//| 【時間フィルター】                                                 |
//| 特定の時間帯のみトレードを許可する設定                              |
//| ※デフォルトOFF: 24時間稼働                                        |
//+------------------------------------------------------------------+
input group "===== 時間フィルター ====="
input bool     InpUseTimeFilter = false;        // 時間フィルター有効:ONで指定時間帯のみトレード。OFFで24時間稼働
input int      InpStartHour = 8;                // 開始時間:トレード開始時刻(サーバー時間0-23)。東京時間開始なら8推奨
input int      InpEndHour = 22;                 // 終了時間:トレード終了時刻(サーバー時間0-23)。NY終了前の22推奨

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         g_Trade;
CRiskManager   g_RiskManager;
CTrendAnalyzer g_TrendAnalyzer;
CEntryLogic    g_EntryLogic;
CLotCalculator g_LotCalculator;

string         g_Symbol;
datetime       g_LastBarTime;
bool           g_IsInitialized;

//--- 分割決済用: TP1目標価格を保存 (ポジションチケット, TP1価格)
struct PartialTPInfo
{
   ulong  ticket;
   double tp1Price;
   double tp2Price;
   bool   tp1Hit;       // TP1で部分決済済みフラグ
   double originalLots; // 元のロットサイズ
};
PartialTPInfo g_PartialTPList[];  // 動的配列

//--- 自動戦術切り替え用: 動的に変更される値
bool   g_DynamicEnableLong;       // 現在のロング許可状態
bool   g_DynamicEnableShort;      // 現在のショート許可状態
double g_DynamicRiskPercent;      // 現在のリスク率
string g_CurrentTacticName;       // 現在の戦術名 (ログ用)

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_IsInitialized = false;

   //--- Set symbol
   g_Symbol = InpSymbol;
   if(g_Symbol == "" || g_Symbol == "0")
      g_Symbol = _Symbol;

   //--- Verify symbol
   if(!SymbolSelect(g_Symbol, true))
   {
      PrintFormat("[EA] Error: Symbol %s not found", g_Symbol);
      return INIT_FAILED;
   }

   //--- Initialize Trade
   g_Trade.SetExpertMagicNumber(InpMagicNumber);
   g_Trade.SetDeviationInPoints(InpSlippage);
   g_Trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Initialize Risk Manager
   if(!g_RiskManager.Initialize(InpInitialBalance))
   {
      Print("[EA] Error: Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   g_RiskManager.SetMaxDailyLossPercent(InpMaxDailyLoss);
   g_RiskManager.SetMaxWeeklyLossPercent(InpMaxWeeklyLoss);
   g_RiskManager.SetMaxTotalLossPercent(InpMaxTotalLoss);
   g_RiskManager.SetMaxPositionRiskPercent(InpMaxPositionRisk);
   g_RiskManager.SetMaxConsecutiveLosses(InpMaxConsecutiveLosses);

   //--- Initialize Trend Analyzer
   if(!g_TrendAnalyzer.Initialize(g_Symbol, InpUseADXFilter, InpADXPeriod, InpADXMinLevel))
   {
      Print("[EA] Error: Failed to initialize Trend Analyzer");
      return INIT_FAILED;
   }
   g_TrendAnalyzer.SetD1TrendThreshold(InpD1TrendThreshold);

   //--- Initialize Entry Logic
   if(!g_EntryLogic.Initialize(g_Symbol, &g_TrendAnalyzer, &g_RiskManager))
   {
      Print("[EA] Error: Failed to initialize Entry Logic");
      return INIT_FAILED;
   }
   g_EntryLogic.SetTradeDirections(InpEnableLongTrades, InpEnableShortTrades);

   //--- Initialize Lot Calculator
   if(!g_LotCalculator.Initialize(g_Symbol, &g_RiskManager, InpRiskPercent))
   {
      Print("[EA] Error: Failed to initialize Lot Calculator");
      return INIT_FAILED;
   }

   g_LastBarTime = 0;
   g_IsInitialized = true;

   //--- 動的変数を初期化 (初期値は入力パラメータから)
   g_DynamicEnableLong = InpEnableLongTrades;
   g_DynamicEnableShort = InpEnableShortTrades;
   g_DynamicRiskPercent = InpRiskPercent;
   g_CurrentTacticName = "初期化中";

   PrintFormat("[EA] ===== prop-trends v3.0 Initialized =====");
   PrintFormat("[EA] Symbol: %s", g_Symbol);
   PrintFormat("[EA] Risk: %.2f%% | MaxDaily: %.2f%% | MaxWeekly: %.2f%% | MaxTotal: %.2f%%",
               InpRiskPercent, InpMaxDailyLoss, InpMaxWeeklyLoss, InpMaxTotalLoss);
   PrintFormat("[EA] Min RR: %.2f | Max Positions: %d | Max Consec Loss: %d",
               InpMinRiskReward, InpMaxPositions, InpMaxConsecutiveLosses);
   PrintFormat("[EA] Long: %s | Short: %s | ADX Filter: %s (Min: %.1f)",
               InpEnableLongTrades ? "ON" : "OFF",
               InpEnableShortTrades ? "ON" : "OFF",
               InpUseADXFilter ? "ON" : "OFF",
               InpADXMinLevel);
   if(InpEnablePartialTP)
   {
      PrintFormat("[EA] Partial TP: ON | TP1=%s (%d%%) | TP2=%s",
                  EnumToString(InpTP1Timeframe), InpTP1ClosePercent,
                  EnumToString(InpTP2Timeframe));
   }
   PrintFormat("[EA] D1 Regime: %s | D1 ADX: %.1f | D1 Trend: %d pts",
               EnumToString(InpRegimeMode), InpD1ADXThreshold, InpD1TrendThreshold);
   PrintFormat("[EA] Tactic Mode: %s", EnumToString(InpTacticMode));
   if(InpTacticMode != TACTIC_MANUAL)
   {
      PrintFormat("[EA] Tactic Risk: TrendUp=%.2f%% | TrendDown=%.2f%% | Range=%.2f%%",
                  InpTrendUpRisk, InpTrendDownRisk, InpRangeRisk);
   }
   PrintFormat("[EA] ==================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_TrendAnalyzer.Deinitialize();
   Print("[EA] Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_IsInitialized)
      return;

   //--- Update daily equity at UTC midnight
   g_RiskManager.UpdateDailyEquity();

   //--- Check for emergency close
   if(g_RiskManager.ShouldClosePositions())
   {
      CloseAllPositions("Risk limit reached");
      return;
   }

   //--- ★分割決済チェック (毎ティック実行)★
   if(InpEnablePartialTP)
   {
      CheckPartialTakeProfit();
   }

   //--- Only process on new bar (H1)
   datetime currentBarTime = iTime(g_Symbol, PERIOD_H1, 0);
   if(currentBarTime == g_LastBarTime)
      return;
   g_LastBarTime = currentBarTime;

   //--- Time filter
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

   //--- Update trend analysis
   g_TrendAnalyzer.Update();

   //--- ★自動戦術切り替え★ (トレンド更新後、エントリー判定前に実行)
   ApplyTactic();

   //--- ★D1レジームフィルター★
   if(!CheckD1Regime())
      return;

   //--- Check existing positions
   int currentPositions = CountMyPositions();
   if(currentPositions >= InpMaxPositions)
      return;

   //--- Update entry logic state
   g_EntryLogic.UpdateState();

   //--- Check for entry signals
   EntrySignal signal = g_EntryLogic.CheckEntrySignals();

   if(!signal.valid)
      return;

   //--- ★分割決済用: TP1/TP2を計算★
   if(InpEnablePartialTP)
   {
      signal.takeProfit1 = g_EntryLogic.CalculateTPByTimeframe(signal.direction, InpTP1Timeframe, signal.entryPrice);
      signal.takeProfit2 = g_EntryLogic.CalculateTPByTimeframe(signal.direction, InpTP2Timeframe, signal.entryPrice);

      // TP2が有効ならTPとして設定
      if(signal.takeProfit2 > 0)
         signal.takeProfit = signal.takeProfit2;
   }

   //--- Check minimum RR
   if(!g_LotCalculator.MeetsMinimumRR(signal.entryPrice, signal.stopLoss, signal.takeProfit, InpMinRiskReward))
      return;

   //--- Calculate lot size
   double lots = g_LotCalculator.CalculateLotSize(signal.entryPrice, signal.stopLoss);
   if(lots <= 0)
   {
      Print("[EA] Invalid lot size calculated");
      return;
   }

   //--- Execute trade
   ExecuteTrade(signal, lots);
}

//+------------------------------------------------------------------+
//| Execute trade based on signal                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(EntrySignal &signal, double lots)
{
   string comment = StringFormat("%s|%s",
                                 g_EntryLogic.GetPatternName(signal.pattern),
                                 signal.direction == TREND_UP ? "BUY" : "SELL");

   bool result = false;

   if(signal.direction == TREND_UP)
   {
      result = g_Trade.Buy(lots, g_Symbol, 0, signal.stopLoss, signal.takeProfit, comment);
   }
   else if(signal.direction == TREND_DOWN)
   {
      result = g_Trade.Sell(lots, g_Symbol, 0, signal.stopLoss, signal.takeProfit, comment);
   }

   if(result)
   {
      PrintFormat("[EA] ===== Trade Executed =====");
      PrintFormat("[EA] Pattern: %s", g_EntryLogic.GetPatternName(signal.pattern));
      PrintFormat("[EA] Direction: %s", signal.direction == TREND_UP ? "BUY" : "SELL");
      PrintFormat("[EA] %s", g_LotCalculator.GetTradeSummary(signal.entryPrice, signal.stopLoss, signal.takeProfit, lots));
      PrintFormat("[EA] Reason: %s", signal.reason);

      //--- ★分割決済: ポジション登録★
      if(InpEnablePartialTP && signal.takeProfit1 > 0)
      {
         ulong ticket = g_Trade.ResultDeal();
         if(ticket > 0)
         {
            RegisterPartialTP(ticket, signal.takeProfit1, signal.takeProfit2, lots);
            PrintFormat("[EA] Partial TP registered: TP1=%.5f | TP2=%.5f",
                        signal.takeProfit1, signal.takeProfit2);
         }
      }

      PrintFormat("[EA] =============================");
   }
   else
   {
      PrintFormat("[EA] Trade failed! Error: %d - %s",
                  g_Trade.ResultRetcode(),
                  g_Trade.ResultRetcodeDescription());
   }

   return result;
}

//+------------------------------------------------------------------+
//| Count positions with our magic number                             |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            count++;
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   PrintFormat("[EA] CLOSING ALL POSITIONS: %s", reason);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            g_Trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpStartHour < InpEndHour)
   {
      return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   }
   else
   {
      // Handles overnight sessions
      return (dt.hour >= InpStartHour || dt.hour < InpEndHour);
   }
}

//+------------------------------------------------------------------+
//| Get position profit by ticket                                     |
//+------------------------------------------------------------------+
double GetPositionProfit(ulong ticket)
{
   if(PositionSelectByTicket(ticket))
   {
      return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Manage existing positions (trailing, breakeven, etc.)            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != g_Symbol ||
            PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
            continue;

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double bid = SymbolInfoDouble(g_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(g_Symbol, SYMBOL_ASK);
         double point = SymbolInfoDouble(g_Symbol, SYMBOL_POINT);

         // Check if we need to exit due to losing edge
         // (e.g., higher TF trend changed against us)
         bool shouldClose = false;
         ENUM_TREND_DIRECTION h4Trend = g_TrendAnalyzer.GetTrendH4();

         if(posType == POSITION_TYPE_BUY && h4Trend == TREND_DOWN)
         {
            // Our buy position is against the H4 trend now
            // Close if we're in profit
            double profit = GetPositionProfit(ticket);
            if(profit > 0)
            {
               shouldClose = true;
               PrintFormat("[EA] Closing BUY: H4 trend reversed to DOWN");
            }
         }
         else if(posType == POSITION_TYPE_SELL && h4Trend == TREND_UP)
         {
            double profit = GetPositionProfit(ticket);
            if(profit > 0)
            {
               shouldClose = true;
               PrintFormat("[EA] Closing SELL: H4 trend reversed to UP");
            }
         }

         if(shouldClose)
         {
            g_Trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Timer function (optional - for periodic checks)                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Can be used for periodic risk checks
   g_RiskManager.UpdateDailyEquity();

   if(g_RiskManager.ShouldClosePositions())
   {
      CloseAllPositions("Timer: Risk limit approaching");
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Can be used for manual controls or visualization
}

//+------------------------------------------------------------------+
//| Trade transaction handler - track consecutive losses              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Only process deal additions (trade closures)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   // Check if this is our deal
   if(trans.symbol != g_Symbol)
      return;

   // Get deal info
   ulong dealTicket = trans.deal;
   if(dealTicket == 0)
      return;

   // Select the deal
   if(!HistoryDealSelect(dealTicket))
      return;

   // Check magic number
   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(magic != InpMagicNumber)
      return;

   // Check if this is a closing deal (OUT or IN_OUT)
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
      return;

   // Get profit
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double totalPnL = profit + commission + swap;

   // Record trade result
   g_RiskManager.RecordTradeResult(totalPnL);

   PrintFormat("[EA] Trade closed: Profit=%.2f, Total=%.2f | %s",
               profit, totalPnL,
               totalPnL >= 0 ? "WIN" : "LOSS");
}

//+------------------------------------------------------------------+
//| 分割決済: ポジション登録                                          |
//+------------------------------------------------------------------+
void RegisterPartialTP(ulong ticket, double tp1, double tp2, double lots)
{
   int size = ArraySize(g_PartialTPList);
   ArrayResize(g_PartialTPList, size + 1);

   g_PartialTPList[size].ticket = ticket;
   g_PartialTPList[size].tp1Price = tp1;
   g_PartialTPList[size].tp2Price = tp2;
   g_PartialTPList[size].tp1Hit = false;
   g_PartialTPList[size].originalLots = lots;
}

//+------------------------------------------------------------------+
//| 分割決済: TP1到達チェック & 部分決済                               |
//+------------------------------------------------------------------+
void CheckPartialTakeProfit()
{
   double bid = SymbolInfoDouble(g_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_Symbol, SYMBOL_ASK);

   for(int i = ArraySize(g_PartialTPList) - 1; i >= 0; i--)
   {
      // ポジションが存在するか確認
      if(!PositionSelectByTicket(g_PartialTPList[i].ticket))
      {
         // ポジションが閉じられた → リストから削除
         RemovePartialTPEntry(i);
         continue;
      }

      // 既にTP1で部分決済済みならスキップ
      if(g_PartialTPList[i].tp1Hit)
         continue;

      // TP1価格が有効か確認
      if(g_PartialTPList[i].tp1Price <= 0)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentLots = PositionGetDouble(POSITION_VOLUME);
      bool tp1Reached = false;

      if(posType == POSITION_TYPE_BUY)
      {
         // BUY: bidがTP1以上なら到達
         tp1Reached = (bid >= g_PartialTPList[i].tp1Price);
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         // SELL: askがTP1以下なら到達
         tp1Reached = (ask <= g_PartialTPList[i].tp1Price);
      }

      if(tp1Reached)
      {
         // 部分決済を実行
         double closePercent = InpTP1ClosePercent / 100.0;
         double closeLots = NormalizeVolume(currentLots * closePercent);

         if(closeLots > 0 && closeLots < currentLots)
         {
            bool closeResult = g_Trade.PositionClosePartial(g_PartialTPList[i].ticket, closeLots);

            if(closeResult)
            {
               g_PartialTPList[i].tp1Hit = true;
               PrintFormat("[EA] ★TP1 Partial Close★ Ticket=%I64u | Closed %.2f lots (%.0f%%) at %.5f",
                           g_PartialTPList[i].ticket, closeLots, InpTP1ClosePercent * 1.0,
                           posType == POSITION_TYPE_BUY ? bid : ask);

               // 残りポジションのSLをエントリー価格に移動（ブレイクイーブン）
               MoveStopToBreakeven(g_PartialTPList[i].ticket);
            }
            else
            {
               PrintFormat("[EA] Partial close failed! Error: %d", GetLastError());
            }
         }
         else if(closeLots >= currentLots)
         {
            // 全決済になる場合
            g_PartialTPList[i].tp1Hit = true;
            PrintFormat("[EA] TP1: Lots too small for partial close, skipping");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ロットサイズを正規化                                               |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
   double minLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| 分割決済エントリーを削除                                           |
//+------------------------------------------------------------------+
void RemovePartialTPEntry(int index)
{
   int size = ArraySize(g_PartialTPList);
   if(index < 0 || index >= size)
      return;

   // 最後の要素と入れ替えて削除
   if(index < size - 1)
   {
      g_PartialTPList[index] = g_PartialTPList[size - 1];
   }
   ArrayResize(g_PartialTPList, size - 1);
}

//+------------------------------------------------------------------+
//| TP1後: SLをブレイクイーブンに移動                                  |
//+------------------------------------------------------------------+
void MoveStopToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double point = SymbolInfoDouble(g_Symbol, SYMBOL_POINT);
   double newSL = 0;

   if(posType == POSITION_TYPE_BUY)
   {
      // BUY: SLをエントリー価格+少しのバッファに
      newSL = openPrice + 10 * point;
      if(newSL <= currentSL)
         return;  // 既にブレイクイーブン以上
   }
   else
   {
      // SELL: SLをエントリー価格-少しのバッファに
      newSL = openPrice - 10 * point;
      if(newSL >= currentSL && currentSL > 0)
         return;  // 既にブレイクイーブン以下
   }

   if(g_Trade.PositionModify(ticket, newSL, currentTP))
   {
      PrintFormat("[EA] SL moved to breakeven: %.5f → %.5f", currentSL, newSL);
   }
}

//+------------------------------------------------------------------+
//| D1レジームチェック: トレード許可判定                               |
//+------------------------------------------------------------------+
bool CheckD1Regime()
{
   // ★自動戦術モードの場合は、ApplyTactic()で既に設定済み★
   // ここでは動的変数を使用してチェック

   // 手動モード: 強制設定
   switch(InpRegimeMode)
   {
      case REGIME_TREND_UP:
         // 上昇トレンドモード: ロングのみ許可
         return g_DynamicEnableLong;

      case REGIME_TREND_DOWN:
         // 下降トレンドモード: ショートのみ許可
         return g_DynamicEnableShort;

      case REGIME_NO_TRADE:
         // トレード停止モード
         return false;

      case REGIME_AUTO:
      default:
         // 自動判定モード: D1 ADX + SMAで判定
         break;
   }

   // ★自動判定ロジック★
   // D1 ADXが閾値以上 かつ D1トレンドが明確 → トレード許可
   bool isTrending = g_TrendAnalyzer.IsD1TrendingMarket(InpD1ADXThreshold);

   if(!isTrending)
   {
      // レンジ相場 → トレード禁止 (ただしRange Riskが設定されていれば許可)
      if(InpTacticMode != TACTIC_MANUAL && InpRangeRisk > 0)
         return true;  // ApplyTacticでリスク調整済み
      return false;
   }

   // トレンド方向とトレード方向の整合性チェック
   ENUM_TREND_DIRECTION d1Direction = g_TrendAnalyzer.GetD1TrendDirection();

   if(d1Direction == TREND_UP && !g_DynamicEnableLong)
   {
      // D1上昇だがロング禁止 → トレード不可
      return false;
   }

   if(d1Direction == TREND_DOWN && !g_DynamicEnableShort)
   {
      // D1下降だがショート禁止 → トレード不可
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 自動戦術切り替え: D1レジームに基づいて戦術を適用                    |
//+------------------------------------------------------------------+
void ApplyTactic()
{
   // 手動モードの場合は何もしない
   if(InpTacticMode == TACTIC_MANUAL)
   {
      g_DynamicEnableLong = InpEnableLongTrades;
      g_DynamicEnableShort = InpEnableShortTrades;
      g_DynamicRiskPercent = InpRiskPercent;
      g_CurrentTacticName = "手動設定";
      return;
   }

   // D1 ADXとトレンド方向を取得
   double d1ADX = g_TrendAnalyzer.GetADX_D1();
   bool isTrending = g_TrendAnalyzer.IsD1TrendingMarket(InpD1ADXThreshold);
   ENUM_TREND_DIRECTION d1Direction = g_TrendAnalyzer.GetD1TrendDirection();

   // 前回の状態を保存 (変更検出用)
   bool prevEnableLong = g_DynamicEnableLong;
   bool prevEnableShort = g_DynamicEnableShort;
   double prevRisk = g_DynamicRiskPercent;
   string prevTactic = g_CurrentTacticName;

   //--- 戦術決定ロジック ---

   if(!isTrending)
   {
      // ★レンジ相場★
      g_CurrentTacticName = "レンジ相場";

      if(InpRangeRisk <= 0)
      {
         // レンジ時はトレード停止
         g_DynamicEnableLong = false;
         g_DynamicEnableShort = false;
         g_DynamicRiskPercent = 0;
         g_CurrentTacticName = "レンジ相場 (停止)";
      }
      else
      {
         // レンジでもトレードする場合 (両方向許可、低リスク)
         g_DynamicEnableLong = true;
         g_DynamicEnableShort = true;
         g_DynamicRiskPercent = InpRangeRisk;
         g_CurrentTacticName = StringFormat("レンジ相場 (Risk: %.2f%%)", InpRangeRisk);
      }
   }
   else if(d1Direction == TREND_UP)
   {
      // ★上昇トレンド★
      g_DynamicEnableLong = true;
      g_DynamicEnableShort = false;  // 上昇時はショート禁止

      if(InpTacticMode == TACTIC_AUTO_FULL)
      {
         g_DynamicRiskPercent = InpTrendUpRisk;
         g_CurrentTacticName = StringFormat("上昇トレンド (Risk: %.2f%%)", InpTrendUpRisk);
      }
      else
      {
         g_DynamicRiskPercent = InpRiskPercent;
         g_CurrentTacticName = "上昇トレンド (Long Only)";
      }
   }
   else if(d1Direction == TREND_DOWN)
   {
      // ★下降トレンド★
      g_DynamicEnableLong = false;  // 下降時はロング禁止
      g_DynamicEnableShort = true;

      if(InpTacticMode == TACTIC_AUTO_FULL)
      {
         g_DynamicRiskPercent = InpTrendDownRisk;
         g_CurrentTacticName = StringFormat("下降トレンド (Risk: %.2f%%)", InpTrendDownRisk);
      }
      else
      {
         g_DynamicRiskPercent = InpRiskPercent;
         g_CurrentTacticName = "下降トレンド (Short Only)";
      }
   }
   else
   {
      // ★ニュートラル (SMA付近)★
      // 保守的にトレード停止
      g_DynamicEnableLong = false;
      g_DynamicEnableShort = false;
      g_DynamicRiskPercent = 0;
      g_CurrentTacticName = "ニュートラル (停止)";
   }

   //--- 設定をコンポーネントに反映 ---
   g_EntryLogic.SetTradeDirections(g_DynamicEnableLong, g_DynamicEnableShort);
   g_LotCalculator.SetDefaultRiskPercent(g_DynamicRiskPercent);

   //--- 戦術変更をログ出力 ---
   if(g_CurrentTacticName != prevTactic ||
      g_DynamicEnableLong != prevEnableLong ||
      g_DynamicEnableShort != prevEnableShort ||
      MathAbs(g_DynamicRiskPercent - prevRisk) > 0.001)
   {
      PrintFormat("[EA] ★戦術変更★ %s → %s", prevTactic, g_CurrentTacticName);
      PrintFormat("[EA]   D1 ADX: %.1f | Direction: %s",
                  d1ADX,
                  d1Direction == TREND_UP ? "UP" :
                  d1Direction == TREND_DOWN ? "DOWN" : "NEUTRAL");
      PrintFormat("[EA]   Long: %s | Short: %s | Risk: %.2f%%",
                  g_DynamicEnableLong ? "ON" : "OFF",
                  g_DynamicEnableShort ? "ON" : "OFF",
                  g_DynamicRiskPercent);
   }
}

//+------------------------------------------------------------------+
