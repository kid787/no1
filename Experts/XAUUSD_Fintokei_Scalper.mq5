//+------------------------------------------------------------------+
//|                                      XAUUSD_Fintokei_Scalper.mq5 |
//|                          XAUUSD Scalping EA for Fintokei         |
//|                          5分足スキャルピング/デイトレード専用      |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Fintokei Scalper"
#property link      ""
#property version   "2.10"
#property description "XAUUSD専用 - Fintokeiチャレンジルール完全対応"
#property description "v2.1: RR比・ATR・トレーリングストップ追加"

#include "..\\Include\\FintokeiRiskManager.mqh"
#include "..\\Include\\TechnicalSignals.mqh"
#include "..\\Include\\TradeManager.mqh"

//--- Input Parameters
input group "=== 基本設定 ==="
input int                  MagicNumber = 789012;           // マジックナンバー
input ENUM_TIMEFRAMES      Timeframe = PERIOD_M5;          // 時間足（5分足推奨）

input group "=== Fintokei リスク管理 ==="
input double               MaxDailyLossPercent = 4.9;      // 1日の最大損失率 (%)
input double               MaxTotalLossPercent = 9.9;      // 全体の最大損失率 (%)
input double               MaxPositionRiskPercent = 3.0;   // ポジション最大リスク (%)

input group "=== ロット計算 ==="
input double               RiskPercentPerTrade = 2.0;      // 1トレードあたりのリスク (%)
input double               MinLotSize = 0.01;              // 最小ロットサイズ
input double               MaxLotSize = 10.0;              // 最大ロットサイズ

input group "=== エントリー条件 ==="
input bool                 UseGranville = true;            // グランビルの法則を使用
input bool                 UsePriceAction = true;          // プライスアクションを使用
input bool                 UseHorizontalLevels = true;     // 水平線レベルを使用
input bool                 UsePivotLevels = true;          // ピボットレベルを使用
input int                  MinSignalsRequired = 2;         // 必要な最小シグナル数（v2.1: 3→2に戻す）

input group "=== 時間帯フィルター ==="
input bool                 UseTimeFilter = true;           // 時間帯フィルターを使用
input int                  TradingStartHour = 5;           // 取引開始時刻（v2.1: 8→5に変更）
input int                  TradingEndHour = 18;            // 取引終了時刻（v2.1: 22→18に変更）
input bool                 AvoidMondayTrading = false;     // 月曜日の取引を避ける
input bool                 AvoidFridayTrading = true;      // 金曜日の取引を避ける（デフォルトON）

input group "=== トレード制限 ==="
input int                  MaxTradesPerDay = 10;           // 1日の最大トレード数（v2.1: 5→10に変更）
input int                  MaxConsecutiveLosses = 3;       // 連続負けでストップ
input int                  PauseAfterLoss_Minutes = 60;    // 負けトレード後の休止時間（分）

input group "=== v2.1: 新規リスク管理 ==="
input double               MinRiskRewardRatio = 1.5;       // 最小RR比（1:1.5未満は拒否）
input double               MaxSingleLossPercent = 2.0;     // 1トレード最大損失（%）
input bool                 UseATRFilter = true;            // ATRボラティリティフィルター
input double               MinATR = 3.0;                   // 最小ATR（これ未満は取引しない）
input double               MaxATR = 15.0;                  // 最大ATR（これ超えは取引しない）

input group "=== エグジット設定 ==="
input double               BreakevenTriggerPips = 80.0;    // 建値移動トリガー (v2.1: 100→80に変更)
input double               BreakevenOffsetPips = 10.0;     // 建値からのオフセット (pips)
input double               SLBufferPercent = 5.0;          // 損切りライン余裕 (5%)

input double               PartialClose1_Pips = 150.0;     // 第1利確レベル (v2.1: 200→150に変更)
input double               PartialClose1_Percent = 50.0;   // 第1利確割合 (v2.1: 30→50%に変更)
input double               PartialClose2_Pips = 300.0;     // 第2利確レベル (v2.1: 400→300に変更)
input double               PartialClose2_Percent = 30.0;   // 第2利確割合 (30%)
input double               PartialClose3_Pips = 500.0;     // 第3利確レベル (v2.1: 600→500に変更)
input double               PartialClose3_Percent = 20.0;   // 第3利確割合 (v2.1: 40→20%に変更)

input group "=== v2.1: トレーリングストップ ==="
input bool                 UseTrailingStop = true;         // トレーリングストップ使用
input double               TrailingStartPips = 200.0;      // トレーリング開始（20ドル利益から）
input double               TrailingStepPips = 50.0;        // トレーリングステップ（5ドル）

input group "=== その他設定 ==="
input bool                 ShowDebugInfo = true;           // デバッグ情報表示
input int                  MaxPositions = 1;               // 最大同時ポジション数

//--- Global Objects
CFintokeiRiskManager *g_RiskManager;
CTechnicalSignals    *g_TechSignals;
CTradeManager        *g_TradeManager;

//--- Global Variables
datetime g_LastBarTime = 0;
bool g_Initialized = false;

// トレード制限用変数
int g_TradesToday = 0;
datetime g_LastTradeDate = 0;
int g_ConsecutiveLosses = 0;
datetime g_LastLossTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // シンボルチェック
   if(_Symbol != "XAUUSD" && _Symbol != "XAUUSD.a" && _Symbol != "XAUUSDm")
   {
      Alert("警告: このEAはXAUUSD専用です。現在のシンボル: ", _Symbol);
      Print("注意: XAUUSD以外のシンボルで動作していますが、動作保証はありません。");
   }

   // 時間足チェック
   if(_Period != Timeframe)
   {
      Alert("警告: 推奨時間足は", EnumToString(Timeframe), "です。現在:", EnumToString(_Period));
   }

   // オブジェクトの初期化
   g_RiskManager = new CFintokeiRiskManager(MaxDailyLossPercent, MaxTotalLossPercent, MaxPositionRiskPercent);
   g_TechSignals = new CTechnicalSignals(_Symbol, Timeframe);
   g_TradeManager = new CTradeManager(_Symbol, MagicNumber);

   // 設定の適用
   g_TradeManager.SetBreakevenSettings(BreakevenTriggerPips, BreakevenOffsetPips);
   g_TradeManager.SetPartialClose(0, PartialClose1_Pips, PartialClose1_Percent / 100.0);
   g_TradeManager.SetPartialClose(1, PartialClose2_Pips, PartialClose2_Percent / 100.0);
   g_TradeManager.SetPartialClose(2, PartialClose3_Pips, PartialClose3_Percent / 100.0);
   g_TradeManager.SetSLBuffer(SLBufferPercent);

   // v2.1: 新機能の設定
   g_TradeManager.SetRiskRewardRatio(MinRiskRewardRatio);
   g_TradeManager.SetMaxLossPercent(MaxSingleLossPercent);
   g_TradeManager.SetTrailingStop(UseTrailingStop, TrailingStartPips, TrailingStepPips);

   g_Initialized = true;

   Print("========================================");
   Print("XAUUSD Fintokei Scalper 初期化完了");
   Print("シンボル: ", _Symbol);
   Print("時間足: ", EnumToString(Timeframe));
   Print("マジックナンバー: ", MagicNumber);
   Print("========================================");

   // リスク情報の表示
   g_RiskManager.PrintRiskInfo();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_RiskManager != NULL) delete g_RiskManager;
   if(g_TechSignals != NULL) delete g_TechSignals;
   if(g_TradeManager != NULL) delete g_TradeManager;

   Print("XAUUSD Fintokei Scalper 終了: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_Initialized) return;

   // 新しいバーのチェック
   datetime currentBarTime = iTime(_Symbol, Timeframe, 0);
   bool isNewBar = (currentBarTime != g_LastBarTime);

   if(isNewBar)
   {
      g_LastBarTime = currentBarTime;

      // リスク管理チェック
      if(!g_RiskManager.CanTrade())
      {
         Print("リスク制限により取引停止中");
         if(ShowDebugInfo)
            g_RiskManager.PrintRiskInfo();

         // 既存ポジションを全てクローズ
         g_TradeManager.CloseAllPositions();
         return;
      }

      // エントリーロジック
      CheckForEntry();
   }

   // ポジション管理（毎ティック）
   g_TradeManager.ManageAllPositions();
}

//+------------------------------------------------------------------+
//| エントリーチェック                                                |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // 最大ポジション数チェック
   if(g_TradeManager.GetPositionCount() >= MaxPositions)
      return;

   // === 新規追加: 時間帯・曜日・トレード制限チェック ===

   // 1日の切り替わりチェック
   MqlDateTime currentDT;
   TimeToStruct(TimeCurrent(), currentDT);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", currentDT.year, currentDT.mon, currentDT.day));

   if(currentDate != g_LastTradeDate)
   {
      g_TradesToday = 0;
      g_LastTradeDate = currentDate;
   }

   // 1日の最大トレード数チェック
   if(g_TradesToday >= MaxTradesPerDay)
   {
      if(ShowDebugInfo) Print("本日の最大トレード数に達しました: ", g_TradesToday, "/", MaxTradesPerDay);
      return;
   }

   // 時間帯フィルター
   if(UseTimeFilter)
   {
      int currentHour = currentDT.hour;
      if(currentHour < TradingStartHour || currentHour >= TradingEndHour)
      {
         if(ShowDebugInfo) Print("取引時間外: ", currentHour, "時 (", TradingStartHour, "-", TradingEndHour, "時のみ)");
         return;
      }
   }

   // 曜日フィルター
   if(AvoidMondayTrading && currentDT.day_of_week == 1)
   {
      if(ShowDebugInfo) Print("月曜日の取引はスキップ");
      return;
   }

   if(AvoidFridayTrading && currentDT.day_of_week == 5)
   {
      if(ShowDebugInfo) Print("金曜日の取引はスキップ");
      return;
   }

   // 連続負けトレード後の休止
   if(g_ConsecutiveLosses >= MaxConsecutiveLosses)
   {
      Print("連続負けトレードにより取引停止中: ", g_ConsecutiveLosses, "回");
      return;
   }

   // 負けトレード後の休止時間チェック
   if(g_LastLossTime > 0 && PauseAfterLoss_Minutes > 0)
   {
      datetime pauseUntil = g_LastLossTime + PauseAfterLoss_Minutes * 60;
      if(TimeCurrent() < pauseUntil)
      {
         if(ShowDebugInfo)
            Print("負けトレード後の休止中。再開時刻: ", TimeToString(pauseUntil));
         return;
      }
   }

   // === ここまで新規追加 ===

   // v2.1: ATRボラティリティフィルター
   if(UseATRFilter)
   {
      if(!g_TechSignals.CheckVolatility(MaxATR, MinATR))
      {
         double currentATR = g_TechSignals.GetATR(0);
         if(ShowDebugInfo)
            Print("ATRフィルター: ボラティリティ範囲外 ATR=", DoubleToString(currentATR, 2),
                  " (", MinATR, "-", MaxATR, ")");
         return;
      }
   }

   // シグナルの収集
   int buySignals = 0;
   int sellSignals = 0;

   // 1. グランビルの法則
   if(UseGranville)
   {
      ENUM_GRANVILLE_SIGNAL granvSignal = g_TechSignals.CheckGranvilleSignal();

      if(granvSignal == GRANV_BUY_1 || granvSignal == GRANV_BUY_2 || granvSignal == GRANV_BUY_3)
      {
         buySignals++;
         if(ShowDebugInfo) Print("グランビル買いシグナル: ", EnumToString(granvSignal));
      }
      else if(granvSignal == GRANV_SELL_1 || granvSignal == GRANV_SELL_2 || granvSignal == GRANV_SELL_3)
      {
         sellSignals++;
         if(ShowDebugInfo) Print("グランビル売りシグナル: ", EnumToString(granvSignal));
      }
   }

   // 2. プライスアクション
   if(UsePriceAction)
   {
      ENUM_PRICE_ACTION paSignal = g_TechSignals.DetectPriceAction(1);

      if(paSignal == PA_BULLISH_ENGULFING || paSignal == PA_BULLISH_PIN_BAR || paSignal == PA_BULLISH_DOJI)
      {
         buySignals++;
         if(ShowDebugInfo) Print("強気プライスアクション: ", EnumToString(paSignal));
      }
      else if(paSignal == PA_BEARISH_ENGULFING || paSignal == PA_BEARISH_PIN_BAR || paSignal == PA_BEARISH_DOJI)
      {
         sellSignals++;
         if(ShowDebugInfo) Print("弱気プライスアクション: ", EnumToString(paSignal));
      }
   }

   // 3. 水平線レベル
   if(UseHorizontalLevels)
   {
      double supportLevel = 0, resistanceLevel = 0;
      bool nearSupport = g_TechSignals.IsNearHorizontalLevel(true, supportLevel);
      bool nearResistance = g_TechSignals.IsNearHorizontalLevel(false, resistanceLevel);

      if(nearSupport)
      {
         buySignals++;
         if(ShowDebugInfo) Print("サポートレベル接近: ", supportLevel);
      }

      if(nearResistance)
      {
         sellSignals++;
         if(ShowDebugInfo) Print("レジスタンスレベル接近: ", resistanceLevel);
      }
   }

   // 4. ピボットレベル
   if(UsePivotLevels)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double nearestPivot = 0;

      if(g_TechSignals.IsNearPivotLevel(currentPrice, nearestPivot))
      {
         // ピボット付近では両方向の可能性があるため、他のシグナルと組み合わせる
         if(buySignals > sellSignals)
         {
            buySignals++;
            if(ShowDebugInfo) Print("ピボットサポート: ", nearestPivot);
         }
         else if(sellSignals > buySignals)
         {
            sellSignals++;
            if(ShowDebugInfo) Print("ピボットレジスタンス: ", nearestPivot);
         }
      }
   }

   // エントリー判断
   bool shouldBuy = (buySignals >= MinSignalsRequired && buySignals > sellSignals);
   bool shouldSell = (sellSignals >= MinSignalsRequired && sellSignals > buySignals);

   if(ShowDebugInfo)
   {
      Print("シグナル集計 - 買い:", buySignals, " 売り:", sellSignals,
            " (必要:", MinSignalsRequired, ")");
   }

   // エントリー実行
   if(shouldBuy)
   {
      ExecuteBuyEntry();
   }
   else if(shouldSell)
   {
      ExecuteSellEntry();
   }
}

//+------------------------------------------------------------------+
//| 買いエントリー実行                                                |
//+------------------------------------------------------------------+
void ExecuteBuyEntry()
{
   Print("=== 買いエントリー条件成立 ===");

   // 損切りレベルの決定（直近安値 + 余裕）
   double swingLow = 0;
   if(!g_TechSignals.GetSwingHighLow(false, swingLow))
   {
      Print("スイング安値が見つかりません。エントリー中止。");
      return;
   }

   double slPrice = g_TradeManager.CalculateSLPrice(true, swingLow);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slPips = MathAbs(currentPrice - slPrice) / g_TradeManager.GetPipSize();

   // ロット計算
   double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                     SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) *
                     g_TradeManager.GetPipSize();

   double maxLot = g_RiskManager.CalculateMaxLot(slPips, pipValue);

   if(maxLot < MinLotSize)
   {
      Print("計算されたロットが最小値未満です。エントリー中止。");
      return;
   }

   if(maxLot > MaxLotSize)
      maxLot = MaxLotSize;

   maxLot = g_TradeManager.NormalizeLot(maxLot);

   // 利確レベルの決定
   double tp1, tp2, tp3;
   g_TradeManager.CalculateTPPrices(true, currentPrice,
                                    PartialClose1_Pips, PartialClose2_Pips, PartialClose3_Pips,
                                    tp1, tp2, tp3);

   // v2.1: リスクリワード比チェック
   if(!g_TradeManager.CheckRiskReward(currentPrice, slPrice, tp3))
   {
      Print("買いエントリー中止: RR比が不十分");
      return;
   }

   // v2.1: 最大損失チェック
   if(!g_TradeManager.CheckMaxLoss(maxLot, slPips))
   {
      Print("買いエントリー中止: 1トレード最大損失超過");
      return;
   }

   // エントリー
   string comment = StringFormat("Buy SL:%.1f TP1:%.1f TP2:%.1f TP3:%.1f",
                                 slPips, PartialClose1_Pips, PartialClose2_Pips, PartialClose3_Pips);

   if(g_TradeManager.OpenBuyPosition(maxLot, slPrice, tp3, comment))
   {
      Print("買いエントリー成功: Lot=", maxLot, " SL=", slPrice, " (", slPips, " pips)");
      Print("TP1=", tp1, " TP2=", tp2, " TP3=", tp3);
      g_TradesToday++;  // トレードカウント増加
   }
}

//+------------------------------------------------------------------+
//| 売りエントリー実行                                                |
//+------------------------------------------------------------------+
void ExecuteSellEntry()
{
   Print("=== 売りエントリー条件成立 ===");

   // 損切りレベルの決定（直近高値 + 余裕）
   double swingHigh = 0;
   if(!g_TechSignals.GetSwingHighLow(true, swingHigh))
   {
      Print("スイング高値が見つかりません。エントリー中止。");
      return;
   }

   double slPrice = g_TradeManager.CalculateSLPrice(false, swingHigh);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPips = MathAbs(slPrice - currentPrice) / g_TradeManager.GetPipSize();

   // ロット計算
   double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                     SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) *
                     g_TradeManager.GetPipSize();

   double maxLot = g_RiskManager.CalculateMaxLot(slPips, pipValue);

   if(maxLot < MinLotSize)
   {
      Print("計算されたロットが最小値未満です。エントリー中止。");
      return;
   }

   if(maxLot > MaxLotSize)
      maxLot = MaxLotSize;

   maxLot = g_TradeManager.NormalizeLot(maxLot);

   // 利確レベルの決定
   double tp1, tp2, tp3;
   g_TradeManager.CalculateTPPrices(false, currentPrice,
                                    PartialClose1_Pips, PartialClose2_Pips, PartialClose3_Pips,
                                    tp1, tp2, tp3);

   // v2.1: リスクリワード比チェック
   if(!g_TradeManager.CheckRiskReward(currentPrice, slPrice, tp3))
   {
      Print("売りエントリー中止: RR比が不十分");
      return;
   }

   // v2.1: 最大損失チェック
   if(!g_TradeManager.CheckMaxLoss(maxLot, slPips))
   {
      Print("売りエントリー中止: 1トレード最大損失超過");
      return;
   }

   // エントリー
   string comment = StringFormat("Sell SL:%.1f TP1:%.1f TP2:%.1f TP3:%.1f",
                                 slPips, PartialClose1_Pips, PartialClose2_Pips, PartialClose3_Pips);

   if(g_TradeManager.OpenSellPosition(maxLot, slPrice, tp3, comment))
   {
      Print("売りエントリー成功: Lot=", maxLot, " SL=", slPrice, " (", slPips, " pips)");
      Print("TP1=", tp1, " TP2=", tp2, " TP3=", tp3);
      g_TradesToday++;  // トレードカウント増加
   }
}

//+------------------------------------------------------------------+
//| OnTimer function                                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 定期的にリスク情報を表示
   if(ShowDebugInfo)
   {
      g_RiskManager.PrintRiskInfo();
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction function - 取引イベント監視                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // ポジションが決済された場合
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // 履歴から取引を取得
      if(HistoryDealSelect(trans.deal))
      {
         long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

         // 自分のEAの取引かチェック
         if(dealMagic != MagicNumber)
            return;

         // 決済（Exit）の場合のみ
         long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(dealEntry == DEAL_ENTRY_OUT)
         {
            double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            double dealSwap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            double dealCommission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
            double totalProfit = dealProfit + dealSwap + dealCommission;

            // 負けトレードの場合
            if(totalProfit < 0)
            {
               g_ConsecutiveLosses++;
               g_LastLossTime = TimeCurrent();

               Print("=== 負けトレード検出 ===");
               Print("損益: ", totalProfit, " 円");
               Print("連続負け: ", g_ConsecutiveLosses, " / ", MaxConsecutiveLosses);

               if(g_ConsecutiveLosses >= MaxConsecutiveLosses)
               {
                  Print("警告: 連続負けが上限に達しました。取引を一時停止します。");
                  Alert("連続負け", g_ConsecutiveLosses, "回により取引停止");
               }
            }
            // 勝ちトレードの場合
            else if(totalProfit > 0)
            {
               g_ConsecutiveLosses = 0;  // 連続負けをリセット
               Print("=== 勝ちトレード ===");
               Print("利益: ", totalProfit, " 円");
               Print("連続負けカウントをリセット");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
