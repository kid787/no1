//+------------------------------------------------------------------+
//|                                       FintokeiGranvilleEA_V2.mq5 |
//|          Fintokei Challenge + Granville Trading Strategy EA V2  |
//|                              改善版: DD制御強化・動的リスク調整   |
//+------------------------------------------------------------------+
#property copyright "Fintokei Granville EA V2"
#property link      ""
#property version   "2.00"
#property description "Fintokeiチャレンジプラン対応 グランビル法則EA V2"
#property description "改善版: ドローダウン制御強化・動的リスク調整"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 外部パラメータ - Fintokeiリスク管理                                |
//+------------------------------------------------------------------+
input group "=== Fintokei リスク管理設定 ==="
input double   InitialBalance       = 2000000.0;   // 初期残高
input double   DailyLossLimitPct    = 5.0;         // 1日の最大損失率（%）
input double   OverallLossLimitPct  = 10.0;        // 全体の最大損失率（%）
input double   SafetyBufferPct      = 1.0;         // 安全バッファ（%）※1.0推奨

//+------------------------------------------------------------------+
//| 外部パラメータ - 取引設定                                          |
//+------------------------------------------------------------------+
input group "=== 取引設定 ==="
input string   Symbol_to_Trade      = "XAUUSD";    // 取引対象銘柄
input double   Risk_Percent         = 0.5;         // 1トレードのリスク（残高の%）※0.5推奨
input double   Max_Lot_Size         = 3.0;         // 最大ロット数
input int      Magic_Number         = 202512;      // マジックナンバー
input string   EA_Comment           = "FintokeiGranvilleV2"; // EAコメント
input int      Slippage_Points      = 30;          // スリッページ許容値

//+------------------------------------------------------------------+
//| 外部パラメータ - 動的リスク調整                                     |
//+------------------------------------------------------------------+
input group "=== 動的リスク調整 ==="
input bool     DynamicRisk_Enable        = true;   // 動的リスク調整有効
input double   DD_Risk_Reduce_Threshold  = 3.0;    // リスク縮小開始DD（%）
input double   DD_Risk_Reduce_Factor     = 0.5;    // リスク縮小係数（0.5=半分）
input double   DD_Stop_Trading_Threshold = 4.0;    // 取引停止DD（%）
input int      ConsecutiveLoss_Pause     = 3;      // 連敗後の一時停止回数
input int      Pause_Bars                = 4;      // 一時停止バー数（M30）

//+------------------------------------------------------------------+
//| 外部パラメータ - グランビル法則設定                                 |
//+------------------------------------------------------------------+
input group "=== グランビル法則設定 ==="
input int      MA_Period_Mid        = 75;          // 中期MA期間（EMA）
input int      MA_Period_Long       = 200;         // 長期MA期間（EMA）
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H4;   // MTFトレンド確認用時間足
input int      MA_Proximity_Pips    = 100;         // MA近接許容範囲（Point単位）
input double   TakeProfit_Ratio     = 2.5;         // リスクリワード比率（2.5推奨）

//+------------------------------------------------------------------+
//| 外部パラメータ - フィルター設定                                     |
//+------------------------------------------------------------------+
input group "=== フィルター設定 ==="
input int      ADX_Period           = 14;          // ADX期間
input double   ADX_Min_Level        = 25.0;        // ADX最小値（25推奨）
input double   ADX_Max_Level        = 50.0;        // ADX最大値（過熱防止）
input int      ATR_Period           = 14;          // ATR期間
input double   ATR_Min_Multiplier   = 0.6;         // ATR最小倍率
input double   ATR_Max_Multiplier   = 1.8;         // ATR最大倍率
input int      RSI_Period           = 14;          // RSI期間（ロング強化用）
input double   RSI_Oversold         = 40.0;        // RSI売られ過ぎ（ロング用）
input double   RSI_Overbought       = 60.0;        // RSI買われ過ぎ（ショート用）

//+------------------------------------------------------------------+
//| 外部パラメータ - ポジション管理                                     |
//+------------------------------------------------------------------+
input group "=== ポジション管理 ==="
input bool     BreakEven_Enable          = true;   // ブレイクイーブン有効
input double   BreakEven_Trigger_Percent = 40.0;   // トリガー（SL幅の%）※早め発動
input int      BreakEven_Offset_Pips     = 5;      // オフセット（Pips）
input bool     PartialTP_Enable          = true;   // 部分利確有効
input double   PartialTP_Close_Percent   = 50.0;   // 決済割合（%）
input double   PartialTP_Trigger_Percent = 40.0;   // トリガー（TP距離の%）※早め発動
input bool     TrailingStop_Enable       = true;   // トレーリングストップ有効
input double   TrailingStop_Trigger_Pct  = 60.0;   // トリガー（SL幅の%）
input double   TrailingStop_Distance_Pct = 30.0;   // 追従距離（SL幅の%）

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間フィルター                                     |
//+------------------------------------------------------------------+
input group "=== 時間フィルター ==="
input bool     TimeFilter_Enable    = true;        // 時間帯フィルター有効
input int      Trade_Start_Hour     = 10;          // 取引開始時刻（時）※ロンドン前
input int      Trade_Start_Minute   = 0;           // 取引開始時刻（分）
input int      Trade_End_Hour       = 3;           // 取引終了時刻（時）※NY後半まで
input int      Trade_End_Minute     = 0;           // 取引終了時刻（分）

//+------------------------------------------------------------------+
//| 外部パラメータ - 表示設定                                          |
//+------------------------------------------------------------------+
input group "=== 表示設定 ==="
input color    NormalColor          = clrWhite;    // 通常テキスト色
input color    WarningColor         = clrYellow;   // 警告色
input color    DangerColor          = clrRed;      // 危険色
input color    SafeColor            = clrLime;     // 安全色
input int      PanelX               = 10;          // パネルX位置
input int      PanelY               = 30;          // パネルY位置

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
CTrade trade;

// インジケーターハンドル
int ma75Handle, ma200Handle, mtfMA75Handle, mtfMA200Handle;
int adxHandle, atrHandle, rsiHandle;

// バー管理
datetime lastBarTime = 0;

// 部分利確フラグ
bool partialTPExecuted = false;

// Fintokeiリスク管理変数
double DailyStartingEquity = 0;
datetime lastResetDateUTC = 0;
bool isEmergencyStop = false;
string emergencyReason = "";

// 取引日数カウント
int tradingDaysCount = 0;
bool hadTradeToday = false;
int lastPositionCount = 0;

// 連敗・一時停止管理
int consecutiveLosses = 0;
int pauseBarsRemaining = 0;
bool isTradingPaused = false;
double lastTradeProfit = 0;

// オブジェクト名プレフィックス
string objPrefix = "FGE2_";

// 動的リスク
double currentRiskPercent = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // トレードオブジェクトの設定
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Slippage_Points);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // 銘柄の選択
   if(!SymbolSelect(Symbol_to_Trade, true))
   {
      Print("銘柄の選択に失敗しました: ", Symbol_to_Trade);
      return(INIT_FAILED);
   }

   // インジケーターハンドルの作成
   ma75Handle = iMA(Symbol_to_Trade, PERIOD_M30, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   ma200Handle = iMA(Symbol_to_Trade, PERIOD_M30, MA_Period_Long, 0, MODE_EMA, PRICE_CLOSE);
   mtfMA75Handle = iMA(Symbol_to_Trade, MTF_Timeframe, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   mtfMA200Handle = iMA(Symbol_to_Trade, MTF_Timeframe, MA_Period_Long, 0, MODE_EMA, PRICE_CLOSE);
   adxHandle = iADX(Symbol_to_Trade, PERIOD_M30, ADX_Period);
   atrHandle = iATR(Symbol_to_Trade, PERIOD_M30, ATR_Period);
   rsiHandle = iRSI(Symbol_to_Trade, PERIOD_M30, RSI_Period, PRICE_CLOSE);

   if(ma75Handle == INVALID_HANDLE || ma200Handle == INVALID_HANDLE ||
      mtfMA75Handle == INVALID_HANDLE || mtfMA200Handle == INVALID_HANDLE ||
      adxHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE ||
      rsiHandle == INVALID_HANDLE)
   {
      Print("インジケーターハンドルの作成に失敗しました");
      return(INIT_FAILED);
   }

   // 初期リスクを設定
   currentRiskPercent = Risk_Percent;

   // Fintokeiリスク管理の初期化
   InitializeFintokeiRiskManagement();

   // 表示更新
   UpdateDisplay();

   Print("=== FintokeiGranvilleEA V2 初期化完了 ===");
   Print("取引銘柄: ", Symbol_to_Trade);
   Print("初期残高: ", DoubleToString(InitialBalance, 2));
   Print("日次損失制限: ", DailyLossLimitPct, "% (安全バッファ: ", SafetyBufferPct, "%)");
   Print("1トレードリスク: ", Risk_Percent, "%");
   Print("RR比率: 1:", TakeProfit_Ratio);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ハンドルの解放
   if(ma75Handle != INVALID_HANDLE) IndicatorRelease(ma75Handle);
   if(ma200Handle != INVALID_HANDLE) IndicatorRelease(ma200Handle);
   if(mtfMA75Handle != INVALID_HANDLE) IndicatorRelease(mtfMA75Handle);
   if(mtfMA200Handle != INVALID_HANDLE) IndicatorRelease(mtfMA200Handle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);

   // オブジェクトの削除
   ObjectsDeleteAll(0, objPrefix);
   ChartRedraw();

   Print("FintokeiGranvilleEA V2 が終了しました");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // UTC 0時のリセットチェック
   CheckDailyReset();

   // 取引日数カウント用の新規注文チェック
   CheckNewTrade();

   // 取引結果の追跡（連敗管理用）
   TrackTradeResults();

   // Fintokei損失制限のチェック（最優先）
   if(!CheckFintokeiLimits())
   {
      ExecuteEmergencyClose();
      UpdateDisplay();
      return;
   }

   // 緊急停止中は新規エントリーをブロック
   if(isEmergencyStop)
   {
      UpdateDisplay();
      return;
   }

   // 動的リスク調整
   if(DynamicRisk_Enable)
   {
      AdjustDynamicRisk();
   }

   // 新しいバーの確認
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_M30, 0);
   if(currentBarTime == lastBarTime)
   {
      // バー内でもポジション管理と表示は更新
      if(HasPosition())
      {
         ManageOpenPosition();
      }
      UpdateDisplay();
      return;
   }
   lastBarTime = currentBarTime;

   // 一時停止カウントダウン
   if(pauseBarsRemaining > 0)
   {
      pauseBarsRemaining--;
      if(pauseBarsRemaining == 0)
      {
         isTradingPaused = false;
         Print("一時停止解除");
      }
   }

   // 既存のポジションチェック
   if(HasPosition())
   {
      ManageOpenPosition();
      UpdateDisplay();
      return;
   }

   // ポジションがない場合はフラグをリセット
   partialTPExecuted = false;

   // 一時停止中はエントリーしない
   if(isTradingPaused)
   {
      UpdateDisplay();
      return;
   }

   // DD停止チェック
   if(DynamicRisk_Enable)
   {
      double currentDD = GetCurrentDailyDrawdown();
      if(currentDD >= DD_Stop_Trading_Threshold)
      {
         UpdateDisplay();
         return;
      }
   }

   // 時間帯フィルターのチェック
   if(TimeFilter_Enable && !IsWithinTradingHours())
   {
      UpdateDisplay();
      return;
   }

   // ATRボラティリティフィルターのチェック
   if(!CheckVolatilityFilter())
   {
      UpdateDisplay();
      return;
   }

   // トレンド分析
   int trendDirection = AnalyzeTrend();

   if(trendDirection == 0)
   {
      UpdateDisplay();
      return;
   }

   // エントリーシグナルのチェック
   if(trendDirection == 1)
   {
      if(CheckBuySignal())
      {
         ExecuteBuyOrder();
      }
   }
   else if(trendDirection == -1)
   {
      if(CheckSellSignal())
      {
         ExecuteSellOrder();
      }
   }

   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| 取引結果の追跡（連敗管理用）                                       |
//+------------------------------------------------------------------+
void TrackTradeResults()
{
   static int lastDealsCount = 0;

   // 履歴から最新の取引を確認
   HistorySelect(0, TimeCurrent());
   int currentDealsCount = HistoryDealsTotal();

   if(currentDealsCount > lastDealsCount)
   {
      // 新しい決済があった
      for(int i = lastDealsCount; i < currentDealsCount; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

            if(magic == Magic_Number && entry == DEAL_ENTRY_OUT)
            {
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
               double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
               double netProfit = profit + swap + commission;

               if(netProfit < 0)
               {
                  consecutiveLosses++;
                  Print("連敗カウント: ", consecutiveLosses);

                  if(consecutiveLosses >= ConsecutiveLoss_Pause)
                  {
                     isTradingPaused = true;
                     pauseBarsRemaining = Pause_Bars;
                     Print("連敗により一時停止: ", Pause_Bars, " バー");
                  }
               }
               else
               {
                  consecutiveLosses = 0;  // 勝ちでリセット
               }

               lastTradeProfit = netProfit;
            }
         }
      }
   }

   lastDealsCount = currentDealsCount;
}

//+------------------------------------------------------------------+
//| 現在の日次ドローダウンを取得                                       |
//+------------------------------------------------------------------+
double GetCurrentDailyDrawdown()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(DailyStartingEquity <= 0) return 0;
   return ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;
}

//+------------------------------------------------------------------+
//| 動的リスク調整                                                     |
//+------------------------------------------------------------------+
void AdjustDynamicRisk()
{
   double currentDD = GetCurrentDailyDrawdown();

   if(currentDD >= DD_Risk_Reduce_Threshold)
   {
      // DDに応じてリスクを縮小
      double reduction = (currentDD - DD_Risk_Reduce_Threshold) / (DD_Stop_Trading_Threshold - DD_Risk_Reduce_Threshold);
      reduction = MathMin(reduction, 1.0);

      currentRiskPercent = Risk_Percent * (1.0 - reduction * (1.0 - DD_Risk_Reduce_Factor));
      currentRiskPercent = MathMax(currentRiskPercent, Risk_Percent * DD_Risk_Reduce_Factor);
   }
   else
   {
      currentRiskPercent = Risk_Percent;
   }
}

//+------------------------------------------------------------------+
//| オープンポジションの管理                                           |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   // 部分利確
   if(PartialTP_Enable && !partialTPExecuted)
   {
      CheckAndSetPartialTP();
   }

   // ブレイクイーブン
   if(BreakEven_Enable)
   {
      CheckAndSetBreakEven();
   }

   // トレーリングストップ
   if(TrailingStop_Enable)
   {
      CheckAndSetTrailingStop();
   }
}

//+------------------------------------------------------------------+
//| Fintokeiリスク管理の初期化                                         |
//+------------------------------------------------------------------+
void InitializeFintokeiRiskManagement()
{
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   string gvName = "FGE2_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);

   if(GlobalVariableCheck(gvName))
   {
      DailyStartingEquity = GlobalVariableGet(gvName);
      lastResetDateUTC = todayResetUTC;
   }
   else
   {
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;
      GlobalVariableSet(gvName, DailyStartingEquity);
   }

   if(GlobalVariableCheck("FGE2_TradingDays"))
   {
      tradingDaysCount = (int)GlobalVariableGet("FGE2_TradingDays");
   }

   lastPositionCount = PositionsTotal();
}

//+------------------------------------------------------------------+
//| 日次リセットのチェック（UTC 0時）                                   |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   if(todayResetUTC > lastResetDateUTC)
   {
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;

      string gvName = "FGE2_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
      GlobalVariableSet(gvName, DailyStartingEquity);

      if(hadTradeToday)
      {
         tradingDaysCount++;
         GlobalVariableSet("FGE2_TradingDays", tradingDaysCount);
      }

      hadTradeToday = false;
      consecutiveLosses = 0;  // 日次リセット時に連敗もリセット
      isTradingPaused = false;
      pauseBarsRemaining = 0;
      currentRiskPercent = Risk_Percent;

      Print("=== 日次リセット実行 ===");
      Print("新しい日次基準額: ", DoubleToString(DailyStartingEquity, 2));
   }
}

//+------------------------------------------------------------------+
//| 新規取引のチェック                                                 |
//+------------------------------------------------------------------+
void CheckNewTrade()
{
   int currentPositionCount = PositionsTotal();

   if(currentPositionCount > lastPositionCount)
   {
      if(!hadTradeToday)
      {
         hadTradeToday = true;
      }
   }

   lastPositionCount = currentPositionCount;
}

//+------------------------------------------------------------------+
//| Fintokei損失制限のチェック                                         |
//+------------------------------------------------------------------+
bool CheckFintokeiLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   double effectiveDailyLimit = DailyLossLimitPct - SafetyBufferPct;
   double effectiveOverallLimit = OverallLossLimitPct - SafetyBufferPct;

   // 全体損失チェック
   double overallLossLine = InitialBalance * (1.0 - effectiveOverallLimit / 100.0);
   if(currentEquity <= overallLossLine)
   {
      double lossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
      emergencyReason = StringFormat("全体損失制限到達 (%.2f%%)", lossPercent);
      return false;
   }

   // 日次損失チェック
   double dailyLossLine = DailyStartingEquity * (1.0 - effectiveDailyLimit / 100.0);
   if(currentEquity <= dailyLossLine)
   {
      double lossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;
      emergencyReason = StringFormat("日次損失制限到達 (%.2f%%)", lossPercent);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 緊急全決済の実行                                                   |
//+------------------------------------------------------------------+
void ExecuteEmergencyClose()
{
   Print("!!! 緊急決済開始 - ", emergencyReason);

   int totalPositions = PositionsTotal();
   int closedCount = 0;

   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(trade.PositionClose(ticket))
         {
            closedCount++;
         }
         else
         {
            for(int retry = 0; retry < 3; retry++)
            {
               Sleep(500);
               if(trade.PositionClose(ticket))
               {
                  closedCount++;
                  break;
               }
            }
         }
      }
   }

   isEmergencyStop = true;
   Print("=== 緊急決済完了: ", closedCount, " ポジション ===");
   Alert("FintokeiGranvilleEA V2: 損失制限到達！緊急停止中");
}

//+------------------------------------------------------------------+
//| ポジション保有チェック                                             |
//+------------------------------------------------------------------+
bool HasPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == Symbol_to_Trade)
      {
         if(PositionGetInteger(POSITION_MAGIC) == Magic_Number)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| トレンド分析（強化版）                                             |
//+------------------------------------------------------------------+
int AnalyzeTrend()
{
   double mtfMA75[], mtfMA200[], m30MA75[], m30MA200[];
   ArraySetAsSeries(mtfMA75, true);
   ArraySetAsSeries(mtfMA200, true);
   ArraySetAsSeries(m30MA75, true);
   ArraySetAsSeries(m30MA200, true);

   if(CopyBuffer(mtfMA75Handle, 0, 0, 25, mtfMA75) < 25) return 0;
   if(CopyBuffer(mtfMA200Handle, 0, 0, 5, mtfMA200) < 5) return 0;
   if(CopyBuffer(ma75Handle, 0, 0, 3, m30MA75) < 3) return 0;
   if(CopyBuffer(ma200Handle, 0, 0, 3, m30MA200) < 3) return 0;

   // MTFトレンド判定（H4）
   double mtfCurrent = mtfMA75[0];
   double mtfPast = mtfMA75[20];
   double mtfDiff = mtfCurrent - mtfPast;
   double threshold = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) * 10;

   bool mtfUptrend = (mtfDiff > threshold) && (mtfMA75[0] > mtfMA200[0]);
   bool mtfDowntrend = (mtfDiff < -threshold) && (mtfMA75[0] < mtfMA200[0]);

   // M30トレンド判定
   bool m30MA75Up = (m30MA75[0] > m30MA75[1]) && (m30MA75[1] > m30MA75[2]);
   bool m30MA75Down = (m30MA75[0] < m30MA75[1]) && (m30MA75[1] < m30MA75[2]);

   if(mtfUptrend && m30MA75Up) return 1;
   else if(mtfDowntrend && m30MA75Down) return -1;
   else return 0;
}

//+------------------------------------------------------------------+
//| 買いシグナルのチェック（RSIフィルター追加）                          |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
   double close[], ma75[], ma200[], adxValue[], rsiValue[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma75, true);
   ArraySetAsSeries(ma200, true);
   ArraySetAsSeries(adxValue, true);
   ArraySetAsSeries(rsiValue, true);

   if(CopyClose(Symbol_to_Trade, PERIOD_M30, 0, 5, close) < 5) return false;
   if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5) return false;
   if(CopyBuffer(ma200Handle, 0, 0, 3, ma200) < 3) return false;
   if(CopyBuffer(adxHandle, 0, 0, 2, adxValue) < 2) return false;
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiValue) < 3) return false;

   double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // 基本フィルター
   bool above200EMA = close[0] > ma200[0];
   bool strongTrend = (adxValue[0] >= ADX_Min_Level) && (adxValue[0] <= ADX_Max_Level);
   bool maTrendUp = (ma75[0] > ma75[1]) && (ma75[1] > ma75[2]);

   // RSIフィルター（ロング強化：売られ過ぎ領域からの回復）
   bool rsiFilter = (rsiValue[1] <= RSI_Oversold && rsiValue[0] > rsiValue[1]) ||
                    (rsiValue[0] > RSI_Oversold && rsiValue[0] < 60);

   // グランビルルール
   bool rule1 = maTrendUp && (close[1] <= ma75[1]) && (close[0] > ma75[0]);
   bool rule2 = maTrendUp && (close[2] > ma75[2]) && (close[1] < ma75[1]) && (close[0] > ma75[0]);

   bool wasNearMA = (close[1] > ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);
   bool bounced = (close[0] > ma75[0]) && (close[0] > close[1]);
   bool rule3 = (wasNearMA || bounced);

   return ((rule1 || rule2 || rule3) && above200EMA && strongTrend && rsiFilter);
}

//+------------------------------------------------------------------+
//| 売りシグナルのチェック（RSIフィルター追加）                          |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
   double close[], ma75[], ma200[], adxValue[], rsiValue[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma75, true);
   ArraySetAsSeries(ma200, true);
   ArraySetAsSeries(adxValue, true);
   ArraySetAsSeries(rsiValue, true);

   if(CopyClose(Symbol_to_Trade, PERIOD_M30, 0, 5, close) < 5) return false;
   if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5) return false;
   if(CopyBuffer(ma200Handle, 0, 0, 3, ma200) < 3) return false;
   if(CopyBuffer(adxHandle, 0, 0, 2, adxValue) < 2) return false;
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiValue) < 3) return false;

   double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   bool below200EMA = close[0] < ma200[0];
   bool strongTrend = (adxValue[0] >= ADX_Min_Level) && (adxValue[0] <= ADX_Max_Level);
   bool maTrendDown = (ma75[0] < ma75[1]) && (ma75[1] < ma75[2]);

   // RSIフィルター（ショート：買われ過ぎ領域からの反落）
   bool rsiFilter = (rsiValue[1] >= RSI_Overbought && rsiValue[0] < rsiValue[1]) ||
                    (rsiValue[0] < RSI_Overbought && rsiValue[0] > 40);

   bool rule5 = maTrendDown && (close[1] >= ma75[1]) && (close[0] < ma75[0]);
   bool rule6 = maTrendDown && (close[2] < ma75[2]) && (close[1] > ma75[1]) && (close[0] < ma75[0]);

   bool wasNearMA = (close[1] < ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);
   bool bounced = (close[0] < ma75[0]) && (close[0] < close[1]);
   bool rule7 = (wasNearMA || bounced);

   return ((rule5 || rule6 || rule7) && below200EMA && strongTrend && rsiFilter);
}

//+------------------------------------------------------------------+
//| 買い注文の実行                                                     |
//+------------------------------------------------------------------+
void ExecuteBuyOrder()
{
   double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   double swingLow = FindSwingLow();
   double sl = 0;

   if(swingLow > 0 && swingLow < ask)
   {
      sl = swingLow - (10 * point);
   }
   else
   {
      sl = ask * 0.985;  // 1.5%のSL
   }

   // SLが大きすぎる場合は制限
   double maxSLPercent = 0.02;  // 最大2%
   if((ask - sl) / ask > maxSLPercent)
   {
      sl = ask * (1.0 - maxSLPercent);
   }

   if(sl >= ask)
   {
      sl = ask - (ask * 0.01);
   }

   double slDistance = ask - sl;
   double tp = ask + (slDistance * TakeProfit_Ratio);

   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));

   double lotSize = CalculateLotSize(ask, sl);

   if(lotSize <= 0)
   {
      Print("ロット計算失敗");
      return;
   }

   if(trade.Buy(lotSize, Symbol_to_Trade, ask, sl, tp, EA_Comment))
   {
      Print("買い注文成功: ロット=", lotSize, ", SL=", sl, ", TP=", tp, ", リスク%=", currentRiskPercent);
   }
   else
   {
      Print("買い注文失敗: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 売り注文の実行                                                     |
//+------------------------------------------------------------------+
void ExecuteSellOrder()
{
   double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   double swingHigh = FindSwingHigh();
   double sl = 0;

   if(swingHigh > 0 && swingHigh > bid)
   {
      sl = swingHigh + (10 * point);
   }
   else
   {
      sl = bid * 1.015;  // 1.5%のSL
   }

   // SLが大きすぎる場合は制限
   double maxSLPercent = 0.02;  // 最大2%
   if((sl - bid) / bid > maxSLPercent)
   {
      sl = bid * (1.0 + maxSLPercent);
   }

   if(sl <= bid)
   {
      sl = bid + (bid * 0.01);
   }

   double slDistance = sl - bid;
   double tp = bid - (slDistance * TakeProfit_Ratio);

   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));

   double lotSize = CalculateLotSize(bid, sl);

   if(lotSize <= 0)
   {
      Print("ロット計算失敗");
      return;
   }

   if(trade.Sell(lotSize, Symbol_to_Trade, bid, sl, tp, EA_Comment))
   {
      Print("売り注文成功: ロット=", lotSize, ", SL=", sl, ", TP=", tp, ", リスク%=", currentRiskPercent);
   }
   else
   {
      Print("売り注文失敗: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| スイングローの検索                                                 |
//+------------------------------------------------------------------+
double FindSwingLow()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 15, rates) < 15) return 0;

   double swingLow = rates[0].low;
   for(int i = 1; i < 15; i++)
   {
      if(rates[i].low < swingLow)
         swingLow = rates[i].low;
   }

   return swingLow;
}

//+------------------------------------------------------------------+
//| スイングハイの検索                                                 |
//+------------------------------------------------------------------+
double FindSwingHigh()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 15, rates) < 15) return 0;

   double swingHigh = rates[0].high;
   for(int i = 1; i < 15; i++)
   {
      if(rates[i].high > swingHigh)
         swingHigh = rates[i].high;
   }

   return swingHigh;
}

//+------------------------------------------------------------------+
//| ロット数の計算（動的リスク対応）                                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * currentRiskPercent / 100.0;

   // Fintokei制限を考慮した最大リスク額
   double maxDailyRisk = DailyStartingEquity * (DailyLossLimitPct - SafetyBufferPct) / 100.0;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double usedRisk = DailyStartingEquity - currentEquity;
   double remainingRisk = maxDailyRisk - usedRisk;

   // 残りリスク額の30%を上限とする（より厳しく）
   double maxAllowedRisk = remainingRisk * 0.3;

   if(riskAmount > maxAllowedRisk && maxAllowedRisk > 0)
   {
      riskAmount = maxAllowedRisk;
      Print("リスク額をFintokei制限に合わせて調整: ", DoubleToString(riskAmount, 2));
   }

   double slDistance = MathAbs(entryPrice - stopLoss);
   if(slDistance <= 0) return 0.01;

   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);

   double lotSize = riskAmount / (slDistance / tickSize * tickValue);

   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   if(lotSize > Max_Lot_Size) lotSize = Max_Lot_Size;

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| ブレイクイーブン管理                                               |
//+------------------------------------------------------------------+
void CheckAndSetBreakEven()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != Symbol_to_Trade) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;

      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionSL = PositionGetDouble(POSITION_SL);
      double positionTP = PositionGetDouble(POSITION_TP);
      long positionType = PositionGetInteger(POSITION_TYPE);
      ulong ticket = PositionGetInteger(POSITION_TICKET);

      double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);

      double slDistance = MathAbs(positionOpenPrice - positionSL);
      if(slDistance == 0) continue;

      double triggerDistance = slDistance * BreakEven_Trigger_Percent / 100.0;
      double offsetPoints = BreakEven_Offset_Pips * point * 10;

      if(positionType == POSITION_TYPE_BUY)
      {
         double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
         double currentProfit = currentPrice - positionOpenPrice;
         double newSL = positionOpenPrice + offsetPoints;

         if(currentProfit >= triggerDistance && positionSL < positionOpenPrice)
         {
            newSL = NormalizeDouble(newSL, digits);
            if(trade.PositionModify(ticket, newSL, positionTP))
            {
               Print("ブレイクイーブン発動 [BUY]");
            }
         }
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
         double currentProfit = positionOpenPrice - currentPrice;
         double newSL = positionOpenPrice - offsetPoints;

         if(currentProfit >= triggerDistance && positionSL > positionOpenPrice)
         {
            newSL = NormalizeDouble(newSL, digits);
            if(trade.PositionModify(ticket, newSL, positionTP))
            {
               Print("ブレイクイーブン発動 [SELL]");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 部分利確管理                                                       |
//+------------------------------------------------------------------+
void CheckAndSetPartialTP()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != Symbol_to_Trade) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;

      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionTP = PositionGetDouble(POSITION_TP);
      double positionVolume = PositionGetDouble(POSITION_VOLUME);
      long positionType = PositionGetInteger(POSITION_TYPE);
      ulong ticket = PositionGetInteger(POSITION_TICKET);

      if(positionTP == 0) continue;

      double tpDistance = MathAbs(positionTP - positionOpenPrice);
      if(tpDistance == 0) continue;

      double triggerDistance = tpDistance * PartialTP_Trigger_Percent / 100.0;

      double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);
      double closeVolume = positionVolume * PartialTP_Close_Percent / 100.0;

      closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
      closeVolume = NormalizeDouble(closeVolume, 2);

      double remainVolume = positionVolume - closeVolume;
      if(closeVolume < minLot || remainVolume < minLot)
      {
         partialTPExecuted = true;
         continue;
      }

      if(positionType == POSITION_TYPE_BUY)
      {
         double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
         double currentProfit = currentPrice - positionOpenPrice;

         if(currentProfit >= triggerDistance)
         {
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
               partialTPExecuted = true;
               Print("部分利確実行 [BUY]");
            }
         }
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
         double currentProfit = positionOpenPrice - currentPrice;

         if(currentProfit >= triggerDistance)
         {
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
               partialTPExecuted = true;
               Print("部分利確実行 [SELL]");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップ管理                                           |
//+------------------------------------------------------------------+
void CheckAndSetTrailingStop()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != Symbol_to_Trade) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;

      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionSL = PositionGetDouble(POSITION_SL);
      double positionTP = PositionGetDouble(POSITION_TP);
      long positionType = PositionGetInteger(POSITION_TYPE);
      ulong ticket = PositionGetInteger(POSITION_TICKET);

      int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);

      double originalSLDistance = MathAbs(positionOpenPrice - positionSL);
      if(originalSLDistance == 0) continue;

      double triggerDistance = originalSLDistance * TrailingStop_Trigger_Pct / 100.0;
      double trailDistance = originalSLDistance * TrailingStop_Distance_Pct / 100.0;

      if(positionType == POSITION_TYPE_BUY)
      {
         double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
         double currentProfit = currentPrice - positionOpenPrice;

         if(currentProfit >= triggerDistance)
         {
            double newSL = currentPrice - trailDistance;
            newSL = NormalizeDouble(newSL, digits);

            if(newSL > positionSL)
            {
               if(trade.PositionModify(ticket, newSL, positionTP))
               {
                  Print("トレーリングストップ更新 [BUY]: ", newSL);
               }
            }
         }
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
         double currentProfit = positionOpenPrice - currentPrice;

         if(currentProfit >= triggerDistance)
         {
            double newSL = currentPrice + trailDistance;
            newSL = NormalizeDouble(newSL, digits);

            if(newSL < positionSL)
            {
               if(trade.PositionModify(ticket, newSL, positionTP))
               {
                  Print("トレーリングストップ更新 [SELL]: ", newSL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 時間帯フィルター                                                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);

   int currentTotalMinutes = currentTime.hour * 60 + currentTime.min;
   int startTotalMinutes = Trade_Start_Hour * 60 + Trade_Start_Minute;
   int endTotalMinutes = Trade_End_Hour * 60 + Trade_End_Minute;

   if(endTotalMinutes < startTotalMinutes)
   {
      return (currentTotalMinutes >= startTotalMinutes || currentTotalMinutes < endTotalMinutes);
   }
   else
   {
      return (currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes);
   }
}

//+------------------------------------------------------------------+
//| ATRボラティリティフィルター                                         |
//+------------------------------------------------------------------+
bool CheckVolatilityFilter()
{
   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(atrHandle, 0, 0, 20, atr) < 20) return false;

   double currentATR = atr[0];
   double avgATR = 0;
   for(int i = 0; i < 20; i++)
      avgATR += atr[i];
   avgATR /= 20.0;

   double atrMultiplier = currentATR / avgATR;

   if(atrMultiplier < ATR_Min_Multiplier || atrMultiplier > ATR_Max_Multiplier)
   {
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| チャート表示の更新                                                 |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   double overallLossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
   double dailyLossPercent = GetCurrentDailyDrawdown();

   double overallLossLine = InitialBalance * (1.0 - OverallLossLimitPct / 100.0);
   double dailyLossLine = DailyStartingEquity * (1.0 - DailyLossLimitPct / 100.0);

   double overallMargin = currentEquity - overallLossLine;
   double dailyMargin = currentEquity - dailyLossLine;

   int yPos = PanelY;
   int yStep = 16;

   // ヘッダー
   if(isEmergencyStop)
   {
      CreateLabel("Header", "FINTOKEI GRANVILLE V2 - 緊急停止", PanelX, yPos, DangerColor, 10, true);
   }
   else if(isTradingPaused)
   {
      CreateLabel("Header", StringFormat("FINTOKEI V2 - 一時停止(%dバー)", pauseBarsRemaining), PanelX, yPos, WarningColor, 10, true);
   }
   else
   {
      CreateLabel("Header", "FINTOKEI GRANVILLE V2", PanelX, yPos, clrGold, 10, true);
   }
   yPos += yStep + 3;

   CreateLabel("Sep1", "------------------------", PanelX, yPos, clrGray, 8, false);
   yPos += yStep - 2;

   // 口座情報
   CreateLabel("Balance", StringFormat("残高: %.0f | Equity: %.0f", currentBalance, currentEquity),
               PanelX, yPos, NormalColor, 9, false);
   yPos += yStep;

   // 全体損失
   color overallColor = GetStatusColor(overallLossPercent, OverallLossLimitPct - SafetyBufferPct);
   CreateLabel("Overall", StringFormat("全体DD: %.2f%% / %.1f%% (残: %.0f)",
               overallLossPercent, OverallLossLimitPct, overallMargin),
               PanelX, yPos, overallColor, 9, false);
   yPos += yStep;

   // 日次損失
   color dailyColor = GetStatusColor(dailyLossPercent, DailyLossLimitPct - SafetyBufferPct);
   CreateLabel("Daily", StringFormat("日次DD: %.2f%% / %.1f%% (残: %.0f)",
               dailyLossPercent, DailyLossLimitPct, dailyMargin),
               PanelX, yPos, dailyColor, 9, false);
   yPos += yStep;

   // 動的リスク表示
   if(DynamicRisk_Enable)
   {
      color riskColor = (currentRiskPercent < Risk_Percent) ? WarningColor : SafeColor;
      CreateLabel("DynRisk", StringFormat("リスク: %.2f%% (基準: %.1f%%)",
                  currentRiskPercent, Risk_Percent),
                  PanelX, yPos, riskColor, 9, false);
      yPos += yStep;
   }

   // 連敗情報
   CreateLabel("ConsLoss", StringFormat("連敗: %d / %d", consecutiveLosses, ConsecutiveLoss_Pause),
               PanelX, yPos, (consecutiveLosses >= 2) ? WarningColor : NormalColor, 9, false);
   yPos += yStep;

   // 取引日数
   int todayCount = hadTradeToday ? 1 : 0;
   color tradingDaysColor = (tradingDaysCount + todayCount >= 3) ? SafeColor : WarningColor;
   CreateLabel("TradingDays", StringFormat("取引日: %d日", tradingDaysCount + todayCount),
               PanelX, yPos, tradingDaysColor, 9, false);

   if(isEmergencyStop)
   {
      yPos += yStep + 5;
      CreateLabel("Emergency", emergencyReason, PanelX, yPos, DangerColor, 9, true);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ステータス色の取得                                                 |
//+------------------------------------------------------------------+
color GetStatusColor(double currentLoss, double limit)
{
   if(currentLoss >= limit)
      return DangerColor;
   else if(currentLoss >= limit - 1.0)
      return WarningColor;
   else
      return SafeColor;
}

//+------------------------------------------------------------------+
//| ラベルオブジェクトの作成/更新                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, bool bold)
{
   string fullName = objPrefix + name;

   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
   }

   ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, fullName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetString(0, fullName, OBJPROP_TEXT, text);
}
//+------------------------------------------------------------------+
