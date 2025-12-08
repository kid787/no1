//+------------------------------------------------------------------+
//|                                         FintokeiGranvilleEA.mq5  |
//|          Fintokei Challenge + Granville Trading Strategy EA      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Granville EA"
#property link      ""
#property version   "1.00"
#property description "Fintokeiチャレンジプラン対応 グランビル法則EA"
#property description "XAUUSD専用・厳格なリスク管理機能付き"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 外部パラメータ - Fintokeiリスク管理                                |
//+------------------------------------------------------------------+
input group "=== Fintokei リスク管理設定 ==="
input double   InitialBalance       = 100000.0;    // 初期残高
input double   DailyLossLimitPct    = 5.0;         // 1日の最大損失率（%）
input double   OverallLossLimitPct  = 10.0;        // 全体の最大損失率（%）
input double   SafetyBufferPct      = 1.0;         // 安全バッファ（%）※1.0推奨

//+------------------------------------------------------------------+
//| 外部パラメータ - 取引設定                                          |
//+------------------------------------------------------------------+
input group "=== 取引設定 ==="
input string   Symbol_to_Trade      = "XAUUSD";    // 取引対象銘柄
input double   Risk_Percent         = 0.5;         // 1トレードのリスク（残高の%）※0.5推奨
input double   Max_Lot_Size         = 5.0;         // 最大ロット数
input int      Magic_Number         = 202512;      // マジックナンバー
input string   EA_Comment           = "FintokeiGranville"; // EAコメント
input int      Slippage_Points      = 30;          // スリッページ許容値

//+------------------------------------------------------------------+
//| 外部パラメータ - グランビル法則設定                                 |
//+------------------------------------------------------------------+
input group "=== グランビル法則設定 ==="
input int      MA_Period_Mid        = 75;          // 中期MA期間（EMA）
input int      MA_Period_Long       = 200;         // 長期MA期間（EMA）
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H4;   // MTFトレンド確認用時間足
input int      MA_Proximity_Pips    = 100;         // MA近接許容範囲（Point単位）
input double   TakeProfit_Ratio     = 2.0;         // リスクリワード比率

//+------------------------------------------------------------------+
//| 外部パラメータ - フィルター設定                                     |
//+------------------------------------------------------------------+
input group "=== フィルター設定 ==="
input int      ADX_Period           = 14;          // ADX期間
input double   ADX_Min_Level        = 20.0;        // ADX最小値
input int      ATR_Period           = 14;          // ATR期間
input double   ATR_Min_Multiplier   = 0.5;         // ATR最小倍率
input double   ATR_Max_Multiplier   = 2.0;         // ATR最大倍率

//+------------------------------------------------------------------+
//| 外部パラメータ - ポジション管理                                     |
//+------------------------------------------------------------------+
input group "=== ポジション管理 ==="
input bool     BreakEven_Enable          = true;   // ブレイクイーブン有効
input double   BreakEven_Trigger_Percent = 50.0;   // トリガー（SL幅の%）
input int      BreakEven_Offset_Pips     = 10;     // オフセット（Pips）
input bool     PartialTP_Enable          = true;   // 部分利確有効
input double   PartialTP_Close_Percent   = 50.0;   // 決済割合（%）
input double   PartialTP_Trigger_Percent = 50.0;   // トリガー（TP距離の%）

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間フィルター                                     |
//+------------------------------------------------------------------+
input group "=== 時間フィルター ==="
input bool     TimeFilter_Enable    = true;        // 時間帯フィルター有効
input int      Trade_Start_Hour     = 12;          // 取引開始時刻（時）
input int      Trade_Start_Minute   = 0;           // 取引開始時刻（分）
input int      Trade_End_Hour       = 5;           // 取引終了時刻（時）
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
int ma75Handle, ma200Handle, mtfMA75Handle, emaShortHandle, adxHandle, atrHandle;

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

// オブジェクト名プレフィックス
string objPrefix = "FGE_";

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
   emaShortHandle = iMA(Symbol_to_Trade, PERIOD_M30, 20, 0, MODE_EMA, PRICE_CLOSE);
   adxHandle = iADX(Symbol_to_Trade, PERIOD_M30, ADX_Period);
   atrHandle = iATR(Symbol_to_Trade, PERIOD_M30, ATR_Period);

   if(ma75Handle == INVALID_HANDLE || ma200Handle == INVALID_HANDLE ||
      mtfMA75Handle == INVALID_HANDLE || emaShortHandle == INVALID_HANDLE ||
      adxHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("インジケーターハンドルの作成に失敗しました");
      return(INIT_FAILED);
   }

   // Fintokeiリスク管理の初期化
   InitializeFintokeiRiskManagement();

   // 表示更新
   UpdateDisplay();

   Print("=== FintokeiGranvilleEA 初期化完了 ===");
   Print("取引銘柄: ", Symbol_to_Trade);
   Print("初期残高: ", DoubleToString(InitialBalance, 2));
   Print("日次損失制限: ", DailyLossLimitPct, "%");
   Print("全体損失制限: ", OverallLossLimitPct, "%");
   Print("1トレードリスク: ", Risk_Percent, "%");

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
   if(emaShortHandle != INVALID_HANDLE) IndicatorRelease(emaShortHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);

   // オブジェクトの削除
   ObjectsDeleteAll(0, objPrefix);
   ChartRedraw();

   Print("FintokeiGranvilleEA が終了しました");
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

   // Fintokei損失制限のチェック（最優先）
   if(!CheckFintokeiLimits())
   {
      // 損失ラインに到達した場合、緊急決済を実行
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

   // 新しいバーの確認
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_M30, 0);
   if(currentBarTime == lastBarTime)
   {
      // バー内でも表示は更新
      UpdateDisplay();
      return;
   }
   lastBarTime = currentBarTime;

   // 既存のポジションチェック
   if(HasPosition())
   {
      // 部分利確機能
      if(PartialTP_Enable && !partialTPExecuted)
      {
         CheckAndSetPartialTP();
      }

      // ブレイクイーブン機能
      if(BreakEven_Enable)
      {
         CheckAndSetBreakEven();
      }

      UpdateDisplay();
      return;
   }

   // ポジションがない場合はフラグをリセット
   partialTPExecuted = false;

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
//| Fintokeiリスク管理の初期化                                         |
//+------------------------------------------------------------------+
void InitializeFintokeiRiskManagement()
{
   // 現在のUTC時間を取得
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   // 今日のUTC 0時を計算
   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   // グローバル変数から日次基準額を読み込み
   string gvName = "FGE_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);

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

   // 取引日数の読み込み
   if(GlobalVariableCheck("FGE_TradingDays"))
   {
      tradingDaysCount = (int)GlobalVariableGet("FGE_TradingDays");
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

      string gvName = "FGE_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
      GlobalVariableSet(gvName, DailyStartingEquity);

      if(hadTradeToday)
      {
         tradingDaysCount++;
         GlobalVariableSet("FGE_TradingDays", tradingDaysCount);
      }

      hadTradeToday = false;

      Print("=== 日次リセット実行 ===");
      Print("新しい日次基準額: ", DoubleToString(DailyStartingEquity, 2));
      Print("累計取引日数: ", tradingDaysCount);
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
         Print("本日の取引を検出");
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
            // リトライ
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
   Alert("FintokeiGranvilleEA: 損失制限到達！緊急停止中");
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
//| トレンド分析                                                       |
//+------------------------------------------------------------------+
int AnalyzeTrend()
{
   double mtfMA[], h1MA75[], h1MA200[];
   ArraySetAsSeries(mtfMA, true);
   ArraySetAsSeries(h1MA75, true);
   ArraySetAsSeries(h1MA200, true);

   if(CopyBuffer(mtfMA75Handle, 0, 0, 25, mtfMA) < 25) return 0;
   if(CopyBuffer(ma75Handle, 0, 0, 3, h1MA75) < 3) return 0;
   if(CopyBuffer(ma200Handle, 0, 0, 3, h1MA200) < 3) return 0;

   double mtfCurrent = mtfMA[0];
   double mtfPast = mtfMA[20];
   double mtfDiff = mtfCurrent - mtfPast;
   double threshold = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) * 10;

   bool mtfUptrend = mtfDiff > threshold;
   bool mtfDowntrend = mtfDiff < -threshold;

   bool h1MA75Up = (h1MA75[0] > h1MA75[1]) && (h1MA75[1] > h1MA75[2]);
   bool h1MA75Down = (h1MA75[0] < h1MA75[1]) && (h1MA75[1] < h1MA75[2]);

   if(mtfUptrend && h1MA75Up) return 1;
   else if(mtfDowntrend && h1MA75Down) return -1;
   else return 0;
}

//+------------------------------------------------------------------+
//| 買いシグナルのチェック                                             |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
   double close[], ma75[], ma200[], adxValue[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma75, true);
   ArraySetAsSeries(ma200, true);
   ArraySetAsSeries(adxValue, true);

   if(CopyClose(Symbol_to_Trade, PERIOD_M30, 0, 5, close) < 5) return false;
   if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5) return false;
   if(CopyBuffer(ma200Handle, 0, 0, 3, ma200) < 3) return false;
   if(CopyBuffer(adxHandle, 0, 0, 2, adxValue) < 2) return false;

   double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   bool above200EMA = close[0] > ma200[0];
   bool strongTrend = adxValue[0] >= ADX_Min_Level;
   bool maTrendUp = (ma75[0] > ma75[1]) && (ma75[1] > ma75[2]);

   bool rule1 = maTrendUp && (close[1] <= ma75[1]) && (close[0] > ma75[0]);
   bool rule2 = maTrendUp && (close[2] > ma75[2]) && (close[1] < ma75[1]) && (close[0] > ma75[0]);

   bool wasNearMA = (close[1] > ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);
   bool bounced = (close[0] > ma75[0]) && (close[0] > close[1]);
   bool rule3 = (wasNearMA || bounced);

   return ((rule1 || rule2 || rule3) && above200EMA && strongTrend);
}

//+------------------------------------------------------------------+
//| 売りシグナルのチェック                                             |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
   double close[], ma75[], ma200[], adxValue[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma75, true);
   ArraySetAsSeries(ma200, true);
   ArraySetAsSeries(adxValue, true);

   if(CopyClose(Symbol_to_Trade, PERIOD_M30, 0, 5, close) < 5) return false;
   if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5) return false;
   if(CopyBuffer(ma200Handle, 0, 0, 3, ma200) < 3) return false;
   if(CopyBuffer(adxHandle, 0, 0, 2, adxValue) < 2) return false;

   double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   bool below200EMA = close[0] < ma200[0];
   bool strongTrend = adxValue[0] >= ADX_Min_Level;
   bool maTrendDown = (ma75[0] < ma75[1]) && (ma75[1] < ma75[2]);

   bool rule5 = maTrendDown && (close[1] >= ma75[1]) && (close[0] < ma75[0]);
   bool rule6 = maTrendDown && (close[2] < ma75[2]) && (close[1] > ma75[1]) && (close[0] < ma75[0]);

   bool wasNearMA = (close[1] < ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);
   bool bounced = (close[0] < ma75[0]) && (close[0] < close[1]);
   bool rule7 = (wasNearMA || bounced);

   return ((rule5 || rule6 || rule7) && below200EMA && strongTrend);
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
      sl = ask * 0.98;
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
      Print("買い注文成功: ロット=", lotSize, ", SL=", sl, ", TP=", tp);
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
      sl = bid * 1.02;
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
      Print("売り注文成功: ロット=", lotSize, ", SL=", sl, ", TP=", tp);
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

   if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 20, rates) < 20) return 0;

   double swingLow = rates[0].low;
   for(int i = 1; i < 20; i++)
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

   if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 20, rates) < 20) return 0;

   double swingHigh = rates[0].high;
   for(int i = 1; i < 20; i++)
   {
      if(rates[i].high > swingHigh)
         swingHigh = rates[i].high;
   }

   return swingHigh;
}

//+------------------------------------------------------------------+
//| ロット数の計算（Fintokei対応・控えめ設定）                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * Risk_Percent / 100.0;

   // Fintokei制限を考慮した最大リスク額
   double maxDailyRisk = DailyStartingEquity * (DailyLossLimitPct - SafetyBufferPct) / 100.0;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double usedRisk = DailyStartingEquity - currentEquity;
   double remainingRisk = maxDailyRisk - usedRisk;

   // 残りリスク額の50%を上限とする（余裕を持たせる）
   double maxAllowedRisk = remainingRisk * 0.5;

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
               Print("ブレイクイーブン発動 [BUY]: 新SL=", newSL);
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
               Print("ブレイクイーブン発動 [SELL]: 新SL=", newSL);
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
               Print("部分利確実行 [BUY]: ", closeVolume, " ロット");
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
               Print("部分利確実行 [SELL]: ", closeVolume, " ロット");
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
   double dailyLossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;

   double overallLossLine = InitialBalance * (1.0 - OverallLossLimitPct / 100.0);
   double dailyLossLine = DailyStartingEquity * (1.0 - DailyLossLimitPct / 100.0);

   double overallMargin = currentEquity - overallLossLine;
   double dailyMargin = currentEquity - dailyLossLine;

   int yPos = PanelY;
   int yStep = 18;

   // ヘッダー
   if(isEmergencyStop)
   {
      CreateLabel("Header", "■ FINTOKEI GRANVILLE EA - 緊急停止中 ■", PanelX, yPos, DangerColor, 11, true);
   }
   else
   {
      CreateLabel("Header", "■ FINTOKEI GRANVILLE EA ■", PanelX, yPos, clrGold, 11, true);
   }
   yPos += yStep + 5;

   CreateLabel("Sep1", "━━━━━━━━━━━━━━━━━━━━━━━━━━", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 口座情報
   CreateLabel("Balance", StringFormat("残高: %.0f | 有効証拠金: %.0f", currentBalance, currentEquity),
               PanelX, yPos, NormalColor, 9, false);
   yPos += yStep;

   // 全体損失
   color overallColor = GetStatusColor(overallLossPercent, OverallLossLimitPct);
   CreateLabel("Overall", StringFormat("全体損失: %.2f%% / %.1f%% (残り: %.0f)",
               overallLossPercent, OverallLossLimitPct, overallMargin),
               PanelX, yPos, overallColor, 9, false);
   yPos += yStep;

   // 日次損失
   color dailyColor = GetStatusColor(dailyLossPercent, DailyLossLimitPct);
   CreateLabel("Daily", StringFormat("日次損失: %.2f%% / %.1f%% (残り: %.0f)",
               dailyLossPercent, DailyLossLimitPct, dailyMargin),
               PanelX, yPos, dailyColor, 9, false);
   yPos += yStep;

   // 取引日数
   int todayCount = hadTradeToday ? 1 : 0;
   color tradingDaysColor = (tradingDaysCount + todayCount >= 3) ? SafeColor : WarningColor;
   CreateLabel("TradingDays", StringFormat("取引日数: %d日 (最低3日必要)",
               tradingDaysCount + todayCount),
               PanelX, yPos, tradingDaysColor, 9, false);
   yPos += yStep;

   // 緊急停止メッセージ
   if(isEmergencyStop)
   {
      yPos += 5;
      CreateLabel("Emergency", "!! " + emergencyReason + " !!", PanelX, yPos, DangerColor, 10, true);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ステータス色の取得                                                 |
//+------------------------------------------------------------------+
color GetStatusColor(double currentLoss, double limit)
{
   if(currentLoss >= limit - SafetyBufferPct)
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
