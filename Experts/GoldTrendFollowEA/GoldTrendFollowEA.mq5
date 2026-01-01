//+------------------------------------------------------------------+
//|                                           GoldTrendFollowEA.mq5  |
//|          XAUUSD Multi-Timeframe Trend Follow EA                  |
//|                  Fintokei Challenge Compatible                   |
//+------------------------------------------------------------------+
//| 概要:                                                             |
//| - ダウ理論とSMAを用いたマルチタイムフレーム・トレンドフォロー戦略    |
//| - v2.3: バックテスト最適化版 (10%DD以下目標)                       |
//| - ADXトレンド強度フィルター、週次損失制限追加                       |
//|   (1日5%損失制限、全体10%損失制限、週5%損失制限)                   |
//+------------------------------------------------------------------+
//| バックテスト結果 (2025年 EURJPY H1):                              |
//| - Risk 1.2%: DD 8%/10%, PF 1.55, RF 2.08 ← Fintokei最適          |
//| - Risk 1.3%: DD 9%/11%, PF 1.55, RF 2.17                         |
//| - Risk 1.4%: DD 10%/12%, PF 1.53 (境界線)                        |
//| - Long-only推奨 (ショートは勝率低下)                              |
//+------------------------------------------------------------------+
#property copyright "Gold Trend Follow EA"
#property link      ""
#property version   "2.30"
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
input group "===== 資金管理設定 (Fintokei準拠) ====="
input double   InpInitialBalance = 0;           // 初期資金 (0=自動取得)
input double   InpRiskPercent = 1.2;            // 1トレードのリスク率 (%) ※1.2%推奨 (Fintokei最適値)
input double   InpMaxDailyLoss = 5.0;           // 1日最大損失率 (%)
input double   InpMaxWeeklyLoss = 5.0;          // 週間最大損失率 (%) ※追加
input double   InpMaxTotalLoss = 10.0;          // 全体最大損失率 (%)
input double   InpMaxPositionRisk = 3.0;        // 同時ポジション最大リスク (%)
input int      InpMaxConsecutiveLosses = 3;     // 連続損失制限 (0=無制限)

input group "===== トレード設定 ====="
input double   InpMinRiskReward = 1.5;          // 最小リスクリワード比
input int      InpMaxPositions = 1;             // 最大同時ポジション数 ※1推奨
input int      InpMagicNumber = 123456;         // マジックナンバー
input string   InpSymbol = "XAUUSD";            // 取引シンボル
input int      InpSlippage = 30;                // 許容スリッページ (points)

input group "===== エントリー設定 ====="
input bool     InpEnableLongTrades = true;      // ロング（買い）を有効化 ※ON推奨 (勝率46%)
input bool     InpEnableShortTrades = false;    // ショート（売り）を有効化 ※OFF推奨 (勝率低下)
input bool     InpEnableH4Pullback = true;      // H4押し目・戻り目を有効化
input bool     InpEnableH1Pullback = true;      // H1押し目・戻り目を有効化
input bool     InpEnableD1Pullback = true;      // D1押し目・戻り目を有効化
input bool     InpEnableH4Reversal = true;      // H4トレンド転換を有効化

input group "===== トレンドフィルター ====="
input bool     InpUseADXFilter = true;          // ADXフィルターを使用 ※推奨ON
input int      InpADXPeriod = 14;               // ADX期間
input double   InpADXMinLevel = 20.0;           // ADX最小値 (これ以下はレンジ)

input group "===== 時間フィルター ====="
input bool     InpUseTimeFilter = false;        // 時間フィルターを使用
input int      InpStartHour = 8;                // 開始時間 (サーバー時間)
input int      InpEndHour = 22;                 // 終了時間 (サーバー時間)

input group "===== デバッグ設定 ====="
input bool     InpDebugMode = true;             // デバッグモード (デフォルト有効)

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

   PrintFormat("[EA] ===== Gold Trend Follow EA v2.3 Initialized =====");
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

   //--- Always log trend status on new bar (helps debugging)
   PrintFormat("[EA] %s | Trend: %s",
               TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES),
               g_TrendAnalyzer.GetTrendString());

   if(InpDebugMode)
   {
      PrintFormat("[EA] Risk Status: %s", g_RiskManager.GetStatusString());
   }

   //--- Check existing positions
   int currentPositions = CountMyPositions();
   if(currentPositions >= InpMaxPositions)
   {
      if(InpDebugMode)
         Print("[EA] Max positions reached");
      return;
   }

   //--- Update entry logic state
   g_EntryLogic.UpdateState();

   //--- Check for entry signals
   EntrySignal signal = g_EntryLogic.CheckEntrySignals();

   if(!signal.valid)
   {
      if(InpDebugMode && signal.reason != "")
         PrintFormat("[EA] No signal: %s", signal.reason);
      return;
   }

   //--- Check minimum RR
   if(!g_LotCalculator.MeetsMinimumRR(signal.entryPrice, signal.stopLoss, signal.takeProfit, InpMinRiskReward))
   {
      if(InpDebugMode)
         PrintFormat("[EA] Signal rejected: RR below minimum (%.2f)",
                     g_LotCalculator.CalculateRiskRewardRatio(signal.entryPrice, signal.stopLoss, signal.takeProfit));
      return;
   }

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

   if(InpDebugMode)
   {
      PrintFormat("[EA] Trade closed: Profit=%.2f, Total=%.2f | %s",
                  profit, totalPnL,
                  totalPnL >= 0 ? "WIN" : "LOSS");
   }
}

//+------------------------------------------------------------------+
