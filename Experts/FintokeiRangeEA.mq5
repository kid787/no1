//+------------------------------------------------------------------+
//|                                              FintokeiRangeEA.mq5 |
//|          Fintokei Challenge + Range Trading Strategy             |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Range EA"
#property link      ""
#property version   "1.00"
#property description "Fintokeiチャレンジプラン対応 レンジトレード戦略EA"
#property description "レンジブレイクアウト + カウンター（逆張り）の2モード"

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
input double   Risk_Percent         = 0.5;         // 1トレードのリスク（残高の%）
input double   Max_Lot_Size         = 5.0;         // 最大ロット数
input int      Magic_Number         = 202515;      // マジックナンバー
input string   EA_Comment           = "FintokeiRange"; // EAコメント
input int      Slippage_Points      = 30;          // スリッページ許容値

//+------------------------------------------------------------------+
//| 外部パラメータ - レンジ検出設定                                     |
//+------------------------------------------------------------------+
input group "=== レンジ検出設定 ==="
input ENUM_TIMEFRAMES Range_Timeframe   = PERIOD_H1;   // レンジ検出時間足
input ENUM_TIMEFRAMES Higher_Timeframe  = PERIOD_H4;   // 上位足（トレンド確認）
input int      Lookback_Bars            = 48;          // レンジ検出期間（バー数）
input double   Min_Range_Pips           = 80.0;        // 最小レンジ幅（Pips）※XAUUSD=$8.0
input double   Max_Range_Pips           = 300.0;       // 最大レンジ幅（Pips）※XAUUSD=$30.0
input double   Range_Squeeze_Pct        = 30.0;        // 子レンジ判定（親の%以下で回避）

//+------------------------------------------------------------------+
//| 外部パラメータ - ブレイクアウト設定                                  |
//+------------------------------------------------------------------+
input group "=== ブレイクアウト設定 ==="
input bool     Enable_Breakout          = true;        // ブレイクアウトロジック有効
input double   Breakout_Confirm_Pips    = 15.0;        // ブレイク確定距離（Pips）※XAUUSD=$1.5
input bool     Require_HTF_Alignment    = true;        // 上位足トレンド一致必須
input double   Breakout_SL_Buffer_Pips  = 20.0;        // ブレイクSLバッファ（Pips）
input double   Breakout_RR_Ratio        = 2.0;         // ブレイクアウト リスクリワード

//+------------------------------------------------------------------+
//| 外部パラメータ - カウンター設定                                     |
//+------------------------------------------------------------------+
input group "=== カウンター（逆張り）設定 ==="
input bool     Enable_Counter           = true;        // カウンターロジック有効
input double   Boundary_Buffer_Pips     = 30.0;        // 境界近接ゾーン（Pips）※XAUUSD=$3.0
input bool     Require_Rejection        = true;        // 反発パターン必須
input double   Counter_SL_Buffer_Pips   = 15.0;        // カウンターSLバッファ（Pips）
input bool     Counter_TP_to_Opposite   = true;        // TPを反対側境界に設定
input double   Counter_RR_Ratio         = 1.5;         // カウンター リスクリワード（TPが中央の場合）

//+------------------------------------------------------------------+
//| 外部パラメータ - RSIフィルター                                      |
//+------------------------------------------------------------------+
input group "=== RSIフィルター ==="
input bool     Use_RSI_Filter           = true;        // RSIフィルター有効
input int      RSI_Period               = 14;          // RSI期間
input double   RSI_Overbought           = 70.0;        // RSI買われ過ぎ
input double   RSI_Oversold             = 30.0;        // RSI売られ過ぎ

//+------------------------------------------------------------------+
//| 外部パラメータ - 移動平均トレンドフィルター                          |
//+------------------------------------------------------------------+
input group "=== トレンドフィルター ==="
input int      MA_Fast_Period           = 20;          // 短期MA期間
input int      MA_Slow_Period           = 50;          // 長期MA期間
input ENUM_MA_METHOD MA_Method          = MODE_EMA;    // MA種類

//+------------------------------------------------------------------+
//| 外部パラメータ - ポジション管理                                     |
//+------------------------------------------------------------------+
input group "=== ポジション管理 ==="
input bool     BreakEven_Enable         = true;        // ブレイクイーブン有効
input double   BreakEven_Trigger_Pct    = 50.0;        // トリガー（TP距離の%）
input int      BreakEven_Offset_Pips    = 10;          // オフセット（Pips）
input int      Max_Positions            = 1;           // 最大同時ポジション数

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間フィルター                                     |
//+------------------------------------------------------------------+
input group "=== 時間フィルター ==="
input bool     TimeFilter_Enable        = true;        // 時間帯フィルター有効
input int      Trade_Start_Hour         = 8;           // 取引開始時刻（サーバー時間）
input int      Trade_End_Hour           = 22;          // 取引終了時刻（サーバー時間）
input bool     Session_Filter_Enable    = false;       // セッションフィルター有効
input int      Asian_End_Hour           = 8;           // アジアセッション終了時刻
input int      London_Start_Hour        = 9;           // ロンドンセッション開始時刻

//+------------------------------------------------------------------+
//| 外部パラメータ - 表示設定                                          |
//+------------------------------------------------------------------+
input group "=== 表示設定 ==="
input bool     Show_Range_Lines         = true;        // レンジラインを表示
input color    Range_High_Color         = clrRed;      // レンジ上限色
input color    Range_Low_Color          = clrBlue;     // レンジ下限色
input color    NormalColor              = clrWhite;    // 通常テキスト色
input color    WarningColor             = clrYellow;   // 警告色
input color    DangerColor              = clrRed;      // 危険色
input color    SafeColor                = clrLime;     // 安全色
input int      PanelX                   = 10;          // パネルX位置
input int      PanelY                   = 30;          // パネルY位置

//+------------------------------------------------------------------+
//| トレードタイプの列挙型                                             |
//+------------------------------------------------------------------+
enum ENUM_TRADE_TYPE
{
   TRADE_NONE,              // トレードなし
   TRADE_BREAKOUT_LONG,     // ブレイクアウト買い
   TRADE_BREAKOUT_SHORT,    // ブレイクアウト売り
   TRADE_COUNTER_LONG,      // カウンター買い
   TRADE_COUNTER_SHORT      // カウンター売り
};

//+------------------------------------------------------------------+
//| トレンド方向の列挙型                                               |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_UP,                // 上昇トレンド
   TREND_DOWN,              // 下降トレンド
   TREND_NEUTRAL            // 中立（レンジ）
};

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleRSI;
int            handleMAFast;
int            handleMASlow;
int            handleMAFastHTF;
int            handleMASlowHTF;

// レンジ情報
double         g_rangeHigh;           // レンジ上限
double         g_rangeLow;            // レンジ下限
double         g_rangeMiddle;         // レンジ中央
double         g_rangeWidth;          // レンジ幅
bool           g_rangeValid;          // 有効なレンジ
bool           g_childRangeDetected;  // 子レンジ検出

// Fintokeiリスク管理
double         g_dailyStartBalance;   // 当日開始時の残高
double         g_dailyPnL;            // 当日の損益
datetime       g_lastDayCheck;        // 最後の日付チェック
bool           g_tradingAllowed;      // 取引許可フラグ

// Pip計算用
double         g_pipValue;
double         g_pipPoint;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Pip値の計算
   int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
   {
      g_pipPoint = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) * 10;
      g_pipValue = 10.0;
   }
   else if(digits == 2) // XAUUSD
   {
      g_pipPoint = 0.1;  // XAUUSD: 1 pip = $0.10
      g_pipValue = 1.0;
   }
   else
   {
      g_pipPoint = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
      g_pipValue = 1.0;
   }

   // トレード設定
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Slippage_Points);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // インジケーターハンドル作成
   handleRSI = iRSI(Symbol_to_Trade, Range_Timeframe, RSI_Period, PRICE_CLOSE);
   handleMAFast = iMA(Symbol_to_Trade, Range_Timeframe, MA_Fast_Period, 0, MA_Method, PRICE_CLOSE);
   handleMASlow = iMA(Symbol_to_Trade, Range_Timeframe, MA_Slow_Period, 0, MA_Method, PRICE_CLOSE);
   handleMAFastHTF = iMA(Symbol_to_Trade, Higher_Timeframe, MA_Fast_Period, 0, MA_Method, PRICE_CLOSE);
   handleMASlowHTF = iMA(Symbol_to_Trade, Higher_Timeframe, MA_Slow_Period, 0, MA_Method, PRICE_CLOSE);

   if(handleRSI == INVALID_HANDLE || handleMAFast == INVALID_HANDLE ||
      handleMASlow == INVALID_HANDLE || handleMAFastHTF == INVALID_HANDLE ||
      handleMASlowHTF == INVALID_HANDLE)
   {
      Print("インジケーターハンドルの作成に失敗しました");
      return INIT_FAILED;
   }

   // Fintokeiリスク管理の初期化
   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyPnL = 0;
   g_lastDayCheck = 0;
   g_tradingAllowed = true;

   // レンジ情報の初期化
   g_rangeValid = false;
   g_rangeHigh = 0;
   g_rangeLow = 0;

   Print("FintokeiRangeEA 初期化完了 - Pip値: ", g_pipPoint);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // インジケーターハンドル解放
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleMAFast != INVALID_HANDLE) IndicatorRelease(handleMAFast);
   if(handleMASlow != INVALID_HANDLE) IndicatorRelease(handleMASlow);
   if(handleMAFastHTF != INVALID_HANDLE) IndicatorRelease(handleMAFastHTF);
   if(handleMASlowHTF != INVALID_HANDLE) IndicatorRelease(handleMASlowHTF);

   // レンジライン削除
   ObjectDelete(0, "RangeHigh");
   ObjectDelete(0, "RangeLow");
   ObjectDelete(0, "RangeMiddle");

   // パネル削除
   ObjectsDeleteAll(0, "Panel_");

   Print("FintokeiRangeEA 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // 日付変更チェック
   CheckNewDay();

   // Fintokeiリスク管理チェック
   if(!CheckFintokeiRisk())
   {
      g_tradingAllowed = false;
   }

   // パネル更新
   UpdatePanel();

   // ブレイクイーブン管理
   if(BreakEven_Enable)
      ManageBreakEven();

   // 新しいバーでのみ処理
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(Symbol_to_Trade, Range_Timeframe, 0);

   if(lastBarTime == currentBarTime)
      return;
   lastBarTime = currentBarTime;

   // レンジの特定
   IdentifyRange();

   // レンジライン描画
   if(Show_Range_Lines)
      DrawRangeLines();

   // 取引許可チェック
   if(!g_tradingAllowed)
      return;

   // 時間フィルター
   if(TimeFilter_Enable && !IsWithinTradingHours())
      return;

   // 有効なレンジがない場合はスキップ
   if(!g_rangeValid)
      return;

   // 子レンジ検出時はスキップ
   if(g_childRangeDetected)
      return;

   // 最大ポジション数チェック
   if(CountPositions() >= Max_Positions)
      return;

   // トレードシグナルの検出
   ENUM_TRADE_TYPE signal = DetectTradeSignal();

   // シグナルに基づいてトレード実行
   if(signal != TRADE_NONE)
      ExecuteTrade(signal);
}

//+------------------------------------------------------------------+
//| レンジの特定                                                       |
//+------------------------------------------------------------------+
void IdentifyRange()
{
   g_rangeValid = false;
   g_childRangeDetected = false;

   // 過去Lookback_Bars内の最高値/最安値を取得
   int highestBar = iHighest(Symbol_to_Trade, Range_Timeframe, MODE_HIGH, Lookback_Bars, 1);
   int lowestBar = iLowest(Symbol_to_Trade, Range_Timeframe, MODE_LOW, Lookback_Bars, 1);

   if(highestBar < 0 || lowestBar < 0)
      return;

   g_rangeHigh = iHigh(Symbol_to_Trade, Range_Timeframe, highestBar);
   g_rangeLow = iLow(Symbol_to_Trade, Range_Timeframe, lowestBar);
   g_rangeMiddle = (g_rangeHigh + g_rangeLow) / 2.0;
   g_rangeWidth = (g_rangeHigh - g_rangeLow) / g_pipPoint;

   // レンジ幅の検証
   if(g_rangeWidth < Min_Range_Pips)
   {
      // レンジが狭すぎる
      return;
   }

   if(g_rangeWidth > Max_Range_Pips)
   {
      // レンジが広すぎる（トレンド相場の可能性）
      return;
   }

   // 子レンジの検出（直近のボラティリティ縮小）
   int recentBars = 10;
   int recentHighBar = iHighest(Symbol_to_Trade, Range_Timeframe, MODE_HIGH, recentBars, 1);
   int recentLowBar = iLowest(Symbol_to_Trade, Range_Timeframe, MODE_LOW, recentBars, 1);

   if(recentHighBar >= 0 && recentLowBar >= 0)
   {
      double recentHigh = iHigh(Symbol_to_Trade, Range_Timeframe, recentHighBar);
      double recentLow = iLow(Symbol_to_Trade, Range_Timeframe, recentLowBar);
      double recentWidth = (recentHigh - recentLow) / g_pipPoint;

      double squeezePct = (recentWidth / g_rangeWidth) * 100.0;
      if(squeezePct < Range_Squeeze_Pct)
      {
         g_childRangeDetected = true;
      }
   }

   g_rangeValid = true;
}

//+------------------------------------------------------------------+
//| トレードシグナルの検出                                              |
//+------------------------------------------------------------------+
ENUM_TRADE_TYPE DetectTradeSignal()
{
   double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
   double closePrice = iClose(Symbol_to_Trade, Range_Timeframe, 1);

   // レンジ中央付近は取引回避（30%ゾーン）
   double centerZone = g_rangeWidth * 0.15 * g_pipPoint; // 中央から±15%
   if(MathAbs(currentPrice - g_rangeMiddle) < centerZone)
      return TRADE_NONE;

   // 上位足トレンド方向の取得
   ENUM_TREND_DIRECTION htfTrend = GetHigherTFTrend();
   ENUM_TREND_DIRECTION currentTrend = GetCurrentTrend();

   // ブレイクアウトロジック
   if(Enable_Breakout)
   {
      // 上方ブレイクアウト
      double breakoutUpLevel = g_rangeHigh + Breakout_Confirm_Pips * g_pipPoint;
      if(closePrice > breakoutUpLevel)
      {
         // 上位足トレンド確認
         if(!Require_HTF_Alignment || htfTrend == TREND_UP || htfTrend == TREND_NEUTRAL)
         {
            return TRADE_BREAKOUT_LONG;
         }
      }

      // 下方ブレイクアウト
      double breakoutDownLevel = g_rangeLow - Breakout_Confirm_Pips * g_pipPoint;
      if(closePrice < breakoutDownLevel)
      {
         // 上位足トレンド確認
         if(!Require_HTF_Alignment || htfTrend == TREND_DOWN || htfTrend == TREND_NEUTRAL)
         {
            return TRADE_BREAKOUT_SHORT;
         }
      }
   }

   // カウンターロジック
   if(Enable_Counter)
   {
      // レンジ上限付近での売り
      double upperZone = g_rangeHigh - Boundary_Buffer_Pips * g_pipPoint;
      if(currentPrice >= upperZone && currentPrice <= g_rangeHigh + Boundary_Buffer_Pips * g_pipPoint)
      {
         // 上位足トレンド確認（下降または中立）
         if(htfTrend == TREND_DOWN || htfTrend == TREND_NEUTRAL)
         {
            // RSIフィルター
            if(!Use_RSI_Filter || IsRSIOverbought())
            {
               // 反発パターン確認
               if(!Require_Rejection || DetectRejectionPattern(false))
               {
                  return TRADE_COUNTER_SHORT;
               }
            }
         }
      }

      // レンジ下限付近での買い
      double lowerZone = g_rangeLow + Boundary_Buffer_Pips * g_pipPoint;
      if(currentPrice <= lowerZone && currentPrice >= g_rangeLow - Boundary_Buffer_Pips * g_pipPoint)
      {
         // 上位足トレンド確認（上昇または中立）
         if(htfTrend == TREND_UP || htfTrend == TREND_NEUTRAL)
         {
            // RSIフィルター
            if(!Use_RSI_Filter || IsRSIOversold())
            {
               // 反発パターン確認
               if(!Require_Rejection || DetectRejectionPattern(true))
               {
                  return TRADE_COUNTER_LONG;
               }
            }
         }
      }
   }

   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| トレード実行                                                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_TRADE_TYPE tradeType)
{
   double entryPrice, sl, tp, lotSize;
   double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   switch(tradeType)
   {
      case TRADE_BREAKOUT_LONG:
         entryPrice = ask;
         sl = g_rangeHigh - Breakout_SL_Buffer_Pips * g_pipPoint;
         tp = entryPrice + (entryPrice - sl) * Breakout_RR_Ratio;
         break;

      case TRADE_BREAKOUT_SHORT:
         entryPrice = bid;
         sl = g_rangeLow + Breakout_SL_Buffer_Pips * g_pipPoint;
         tp = entryPrice - (sl - entryPrice) * Breakout_RR_Ratio;
         break;

      case TRADE_COUNTER_LONG:
         entryPrice = ask;
         sl = g_rangeLow - Counter_SL_Buffer_Pips * g_pipPoint;
         if(Counter_TP_to_Opposite)
            tp = g_rangeHigh;
         else
            tp = entryPrice + (entryPrice - sl) * Counter_RR_Ratio;
         break;

      case TRADE_COUNTER_SHORT:
         entryPrice = bid;
         sl = g_rangeHigh + Counter_SL_Buffer_Pips * g_pipPoint;
         if(Counter_TP_to_Opposite)
            tp = g_rangeLow;
         else
            tp = entryPrice - (sl - entryPrice) * Counter_RR_Ratio;
         break;

      default:
         return;
   }

   // リスクリワード比のチェック
   double slDistance = MathAbs(entryPrice - sl);
   double tpDistance = MathAbs(tp - entryPrice);
   double rrRatio = tpDistance / slDistance;

   if(rrRatio < 1.0)
   {
      Print("リスクリワード比が不十分: ", DoubleToString(rrRatio, 2));
      return;
   }

   // ロットサイズ計算
   lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("ロットサイズ計算エラー");
      return;
   }

   // 注文発注
   string comment = EA_Comment + "_" + EnumToString(tradeType);
   bool result = false;

   if(tradeType == TRADE_BREAKOUT_LONG || tradeType == TRADE_COUNTER_LONG)
   {
      result = trade.Buy(lotSize, Symbol_to_Trade, entryPrice, sl, tp, comment);
   }
   else
   {
      result = trade.Sell(lotSize, Symbol_to_Trade, entryPrice, sl, tp, comment);
   }

   if(result)
   {
      Print("注文成功: ", comment, " Lot=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
   }
   else
   {
      Print("注文失敗: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| 上位足トレンド方向の取得                                            |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetHigherTFTrend()
{
   double maFast[], maSlow[];
   ArraySetAsSeries(maFast, true);
   ArraySetAsSeries(maSlow, true);

   if(CopyBuffer(handleMAFastHTF, 0, 0, 3, maFast) < 3) return TREND_NEUTRAL;
   if(CopyBuffer(handleMASlowHTF, 0, 0, 3, maSlow) < 3) return TREND_NEUTRAL;

   // MA位置関係でトレンド判定
   if(maFast[0] > maSlow[0] && maFast[1] > maSlow[1])
      return TREND_UP;
   else if(maFast[0] < maSlow[0] && maFast[1] < maSlow[1])
      return TREND_DOWN;

   return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| 現在のトレンド方向の取得                                            |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetCurrentTrend()
{
   double maFast[], maSlow[];
   ArraySetAsSeries(maFast, true);
   ArraySetAsSeries(maSlow, true);

   if(CopyBuffer(handleMAFast, 0, 0, 3, maFast) < 3) return TREND_NEUTRAL;
   if(CopyBuffer(handleMASlow, 0, 0, 3, maSlow) < 3) return TREND_NEUTRAL;

   if(maFast[0] > maSlow[0] && maFast[1] > maSlow[1])
      return TREND_UP;
   else if(maFast[0] < maSlow[0] && maFast[1] < maSlow[1])
      return TREND_DOWN;

   return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| RSI買われ過ぎ判定                                                  |
//+------------------------------------------------------------------+
bool IsRSIOverbought()
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleRSI, 0, 0, 3, rsi) < 3) return false;

   return (rsi[1] >= RSI_Overbought);
}

//+------------------------------------------------------------------+
//| RSI売られ過ぎ判定                                                  |
//+------------------------------------------------------------------+
bool IsRSIOversold()
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleRSI, 0, 0, 3, rsi) < 3) return false;

   return (rsi[1] <= RSI_Oversold);
}

//+------------------------------------------------------------------+
//| 反発パターン検出                                                   |
//+------------------------------------------------------------------+
bool DetectRejectionPattern(bool isBullish)
{
   double open1 = iOpen(Symbol_to_Trade, Range_Timeframe, 1);
   double high1 = iHigh(Symbol_to_Trade, Range_Timeframe, 1);
   double low1 = iLow(Symbol_to_Trade, Range_Timeframe, 1);
   double close1 = iClose(Symbol_to_Trade, Range_Timeframe, 1);

   double open2 = iOpen(Symbol_to_Trade, Range_Timeframe, 2);
   double high2 = iHigh(Symbol_to_Trade, Range_Timeframe, 2);
   double low2 = iLow(Symbol_to_Trade, Range_Timeframe, 2);
   double close2 = iClose(Symbol_to_Trade, Range_Timeframe, 2);

   double bodySize1 = MathAbs(close1 - open1);
   double range1 = high1 - low1;

   if(range1 <= 0) return false;

   if(isBullish)
   {
      // ピンバー（下ヒゲが長い）
      double lowerWick = MathMin(open1, close1) - low1;
      if(lowerWick > range1 * 0.6 && bodySize1 < range1 * 0.3)
         return true;

      // 強気包み足
      if(close2 < open2 && close1 > open1)
      {
         if(close1 > open2 && open1 < close2)
            return true;
      }

      // 下ヒゲの長い陽線
      if(close1 > open1 && lowerWick > bodySize1)
         return true;
   }
   else
   {
      // ピンバー（上ヒゲが長い）
      double upperWick = high1 - MathMax(open1, close1);
      if(upperWick > range1 * 0.6 && bodySize1 < range1 * 0.3)
         return true;

      // 弱気包み足
      if(close2 > open2 && close1 < open1)
      {
         if(close1 < open2 && open1 > close2)
            return true;
      }

      // 上ヒゲの長い陰線
      if(close1 < open1 && upperWick > bodySize1)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| ロットサイズ計算                                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   // XAUUSD用のポイント値計算
   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0 || tickValue <= 0)
      return 0;

   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);

   // ロットサイズの正規化
   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(lotSize, MathMin(maxLot, Max_Lot_Size)));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Fintokeiリスク管理チェック                                         |
//+------------------------------------------------------------------+
bool CheckFintokeiRisk()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 全体の最大損失率チェック
   double overallLoss = InitialBalance - equity;
   double overallLossPct = (overallLoss / InitialBalance) * 100.0;
   double overallLimit = OverallLossLimitPct - SafetyBufferPct;

   if(overallLossPct >= overallLimit)
   {
      Print("警告: 全体の最大損失率に近づいています - ", DoubleToString(overallLossPct, 2), "%");
      return false;
   }

   // 日次の最大損失率チェック
   g_dailyPnL = equity - g_dailyStartBalance;
   double dailyLossPct = (-g_dailyPnL / g_dailyStartBalance) * 100.0;
   double dailyLimit = DailyLossLimitPct - SafetyBufferPct;

   if(g_dailyPnL < 0 && dailyLossPct >= dailyLimit)
   {
      Print("警告: 日次の最大損失率に近づいています - ", DoubleToString(dailyLossPct, 2), "%");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 新しい日のチェック                                                  |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." +
                                  IntegerToString(dt.mon) + "." +
                                  IntegerToString(dt.day));

   if(g_lastDayCheck != today)
   {
      g_lastDayCheck = today;
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyPnL = 0;
      g_tradingAllowed = true;
      Print("新しい日: 日次残高リセット - ", DoubleToString(g_dailyStartBalance, 2));
   }
}

//+------------------------------------------------------------------+
//| 取引時間内かチェック                                                |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // 基本の時間フィルター
   if(dt.hour < Trade_Start_Hour || dt.hour >= Trade_End_Hour)
      return false;

   // セッションフィルター（有効な場合）
   if(Session_Filter_Enable)
   {
      // アジアセッション中はブレイクアウトを避ける
      // ロンドン/NYセッションでブレイクアウトを狙う
      if(dt.hour < Asian_End_Hour)
      {
         // アジアセッション中 - カウンターのみ許可
         // （この制限は DetectTradeSignal で別途処理可能）
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| ポジション数のカウント                                              |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol_to_Trade &&
            PositionGetInteger(POSITION_MAGIC) == Magic_Number)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| ブレイクイーブン管理                                                |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol_to_Trade)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

      if(tp == 0) continue;

      double tpDistance = MathAbs(tp - openPrice);
      double triggerDistance = tpDistance * (BreakEven_Trigger_Pct / 100.0);
      double beLevel = openPrice + BreakEven_Offset_Pips * g_pipPoint *
                       (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(currentPrice >= openPrice + triggerDistance && currentSL < beLevel)
         {
            trade.PositionModify(PositionGetTicket(i), beLevel, tp);
         }
      }
      else
      {
         if(currentPrice <= openPrice - triggerDistance && (currentSL > beLevel || currentSL == 0))
         {
            trade.PositionModify(PositionGetTicket(i), beLevel, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| レンジライン描画                                                   |
//+------------------------------------------------------------------+
void DrawRangeLines()
{
   if(!g_rangeValid) return;

   datetime startTime = iTime(Symbol_to_Trade, Range_Timeframe, Lookback_Bars);
   datetime endTime = TimeCurrent() + PeriodSeconds(Range_Timeframe) * 10;

   // レンジ上限
   ObjectDelete(0, "RangeHigh");
   ObjectCreate(0, "RangeHigh", OBJ_RECTANGLE, 0, startTime, g_rangeHigh,
                endTime, g_rangeHigh - Boundary_Buffer_Pips * g_pipPoint);
   ObjectSetInteger(0, "RangeHigh", OBJPROP_COLOR, Range_High_Color);
   ObjectSetInteger(0, "RangeHigh", OBJPROP_FILL, true);
   ObjectSetInteger(0, "RangeHigh", OBJPROP_BACK, true);

   // レンジ下限
   ObjectDelete(0, "RangeLow");
   ObjectCreate(0, "RangeLow", OBJ_RECTANGLE, 0, startTime, g_rangeLow,
                endTime, g_rangeLow + Boundary_Buffer_Pips * g_pipPoint);
   ObjectSetInteger(0, "RangeLow", OBJPROP_COLOR, Range_Low_Color);
   ObjectSetInteger(0, "RangeLow", OBJPROP_FILL, true);
   ObjectSetInteger(0, "RangeLow", OBJPROP_BACK, true);

   // レンジ中央
   ObjectDelete(0, "RangeMiddle");
   ObjectCreate(0, "RangeMiddle", OBJ_HLINE, 0, 0, g_rangeMiddle);
   ObjectSetInteger(0, "RangeMiddle", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "RangeMiddle", OBJPROP_STYLE, STYLE_DOT);
}

//+------------------------------------------------------------------+
//| パネル更新                                                         |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   int y = PanelY;
   int lineHeight = 18;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double overallLoss = InitialBalance - equity;
   double overallLossPct = (overallLoss / InitialBalance) * 100.0;
   double dailyLossPct = g_dailyPnL < 0 ? (-g_dailyPnL / g_dailyStartBalance) * 100.0 : 0;

   // タイトル
   CreateLabel("Panel_Title", "=== Fintokei Range EA ===", PanelX, y, NormalColor);
   y += lineHeight;

   // 残高情報
   CreateLabel("Panel_Balance", "残高: " + DoubleToString(balance, 0) + " / Equity: " + DoubleToString(equity, 0),
               PanelX, y, NormalColor);
   y += lineHeight;

   // 日次損益
   color dailyColor = g_dailyPnL >= 0 ? SafeColor : (dailyLossPct > 3.0 ? DangerColor : WarningColor);
   CreateLabel("Panel_Daily", "日次P/L: " + DoubleToString(g_dailyPnL, 0) + " (" + DoubleToString(dailyLossPct, 2) + "%)",
               PanelX, y, dailyColor);
   y += lineHeight;

   // 全体損益
   color overallColor = overallLoss <= 0 ? SafeColor : (overallLossPct > 7.0 ? DangerColor : WarningColor);
   CreateLabel("Panel_Overall", "全体DD: " + DoubleToString(overallLossPct, 2) + "%",
               PanelX, y, overallColor);
   y += lineHeight;

   // レンジ情報
   y += lineHeight / 2;
   CreateLabel("Panel_RangeSep", "--- レンジ情報 ---", PanelX, y, NormalColor);
   y += lineHeight;

   string rangeStatus = g_rangeValid ? "有効" : "無効";
   color rangeColor = g_rangeValid ? SafeColor : WarningColor;
   if(g_childRangeDetected)
   {
      rangeStatus = "子レンジ検出";
      rangeColor = WarningColor;
   }
   CreateLabel("Panel_RangeStatus", "レンジ: " + rangeStatus, PanelX, y, rangeColor);
   y += lineHeight;

   if(g_rangeValid)
   {
      CreateLabel("Panel_RangeHigh", "上限: " + DoubleToString(g_rangeHigh, 2), PanelX, y, Range_High_Color);
      y += lineHeight;
      CreateLabel("Panel_RangeLow", "下限: " + DoubleToString(g_rangeLow, 2), PanelX, y, Range_Low_Color);
      y += lineHeight;
      CreateLabel("Panel_RangeWidth", "幅: " + DoubleToString(g_rangeWidth, 1) + " pips", PanelX, y, NormalColor);
      y += lineHeight;
   }

   // トレンド情報
   y += lineHeight / 2;
   CreateLabel("Panel_TrendSep", "--- トレンド情報 ---", PanelX, y, NormalColor);
   y += lineHeight;

   ENUM_TREND_DIRECTION htfTrend = GetHigherTFTrend();
   string htfTrendStr = htfTrend == TREND_UP ? "上昇" : (htfTrend == TREND_DOWN ? "下降" : "中立");
   color htfColor = htfTrend == TREND_UP ? SafeColor : (htfTrend == TREND_DOWN ? DangerColor : WarningColor);
   CreateLabel("Panel_HTFTrend", "上位足: " + htfTrendStr, PanelX, y, htfColor);
   y += lineHeight;

   // 取引状態
   y += lineHeight / 2;
   CreateLabel("Panel_TradeSep", "--- 取引状態 ---", PanelX, y, NormalColor);
   y += lineHeight;

   string tradingStatus = g_tradingAllowed ? "取引許可" : "取引停止";
   color tradingColor = g_tradingAllowed ? SafeColor : DangerColor;
   CreateLabel("Panel_Trading", tradingStatus, PanelX, y, tradingColor);
   y += lineHeight;

   CreateLabel("Panel_Positions", "ポジション: " + IntegerToString(CountPositions()) + "/" + IntegerToString(Max_Positions),
               PanelX, y, NormalColor);
}

//+------------------------------------------------------------------+
//| ラベル作成                                                         |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   }

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}
//+------------------------------------------------------------------+
