//+------------------------------------------------------------------+
//|                                             FintokeiScalpEA.mq5 |
//|          Fintokei Challenge + Multi-Strategy Scalping EA        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Scalp EA"
#property link      ""
#property version   "1.00"
#property description "Fintokeiチャレンジプラン対応 マルチ戦略スキャルピングEA"
#property description "H1環境認識 + M5エントリー（BB/トレンドライン/ネックライン）"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 外部パラメータ - Fintokeiリスク管理                                |
//+------------------------------------------------------------------+
input group "=== Fintokei リスク管理設定 ==="
input double   InitialBalance       = 100000.0;    // 初期残高
input double   DailyLossLimitPct    = 5.0;         // 1日の最大損失率（%）
input double   OverallLossLimitPct  = 10.0;        // 全体の最大損失率（%）
input double   SafetyBufferPct      = 1.0;         // 安全バッファ（%）

//+------------------------------------------------------------------+
//| 外部パラメータ - 取引設定                                          |
//+------------------------------------------------------------------+
input group "=== 取引設定 ==="
input string   Symbol_to_Trade      = "XAUUSD";    // 取引対象銘柄
input double   Risk_Percent         = 0.3;         // 1トレードのリスク（残高の%）
input double   Max_Lot_Size         = 5.0;         // 最大ロット数
input int      Magic_Number         = 202516;      // マジックナンバー
input string   EA_Comment           = "FintokeiScalp"; // EAコメント
input int      Slippage_Points      = 30;          // スリッページ許容値

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間足設定                                        |
//+------------------------------------------------------------------+
input group "=== 時間足設定 ==="
input ENUM_TIMEFRAMES TF_Environment  = PERIOD_H1;    // 環境認識時間足
input ENUM_TIMEFRAMES TF_Entry        = PERIOD_M5;    // エントリー時間足
input int      H1_Lookback_Bars       = 24;           // H1レンジ検出期間

//+------------------------------------------------------------------+
//| 外部パラメータ - 戦略選択                                          |
//+------------------------------------------------------------------+
input group "=== 戦略選択 ==="
input bool     Strategy_TrendlineBB   = true;         // 案4: トレンドライン+BB反発
input bool     Strategy_BB_SR         = false;        // 案1: BB+H1サポレジ平均回帰
input bool     Strategy_BB_Squeeze    = false;        // 案2: BBスクイーズブレイク
input bool     Strategy_NecklineBB    = false;        // 案3: ネックライン+BB確認
input bool     Strategy_EMA_Cross     = false;        // 案5: EMAクロス+RSI（高勝率）
input bool     Strategy_MACD_RSI      = false;        // 案6: MACD+RSIモメンタム

//+------------------------------------------------------------------+
//| 外部パラメータ - ボリンジャーバンド設定                              |
//+------------------------------------------------------------------+
input group "=== ボリンジャーバンド設定 ==="
input int      BB_Period              = 20;           // BB期間
input double   BB_Deviation           = 2.0;          // BB偏差
input double   BB_Squeeze_Threshold   = 0.5;          // BBスクイーズ閾値（%）

//+------------------------------------------------------------------+
//| 外部パラメータ - RSI設定                                           |
//+------------------------------------------------------------------+
input group "=== RSI設定 ==="
input bool     Use_RSI_Filter         = true;         // RSIフィルター有効
input int      RSI_Period             = 14;           // RSI期間
input double   RSI_Overbought         = 70.0;         // RSI買われ過ぎ
input double   RSI_Oversold           = 30.0;         // RSI売られ過ぎ

//+------------------------------------------------------------------+
//| 外部パラメータ - EMA設定（案5用）                                   |
//+------------------------------------------------------------------+
input group "=== EMA設定（案5用）==="
input int      EMA_Fast_Period        = 9;            // 短期EMA期間
input int      EMA_Slow_Period        = 21;           // 長期EMA期間

//+------------------------------------------------------------------+
//| 外部パラメータ - MACD設定（案6用）                                  |
//+------------------------------------------------------------------+
input group "=== MACD設定（案6用）==="
input int      MACD_Fast              = 12;           // MACD短期EMA
input int      MACD_Slow              = 26;           // MACD長期EMA
input int      MACD_Signal            = 9;            // MACDシグナル期間
input int      RSI_Fast_Period        = 7;            // RSI高速期間（案6用）

//+------------------------------------------------------------------+
//| 外部パラメータ - トレンドライン設定                                  |
//+------------------------------------------------------------------+
input group "=== トレンドライン設定 ==="
input int      TL_Lookback_Bars       = 50;           // トレンドライン検出期間
input int      TL_Min_Touches         = 2;            // 最小タッチ回数
input double   TL_Proximity_Pips      = 30.0;         // トレンドライン近接判定（Pips）

//+------------------------------------------------------------------+
//| 外部パラメータ - エントリー設定                                     |
//+------------------------------------------------------------------+
input group "=== エントリー設定 ==="
input double   SL_Pips                = 30.0;         // ストップロス（Pips）
input double   TP_Pips                = 45.0;         // テイクプロフィット（Pips）
input double   Min_RR_Ratio           = 1.5;          // 最小リスクリワード比

//+------------------------------------------------------------------+
//| 外部パラメータ - ポジション管理                                     |
//+------------------------------------------------------------------+
input group "=== ポジション管理 ==="
input bool     BreakEven_Enable       = false;        // ブレイクイーブン有効
input double   BreakEven_Trigger_Pct  = 50.0;         // トリガー（TP距離の%）
input int      BreakEven_Offset_Pips  = 5;            // オフセット（Pips）
input int      Max_Positions          = 1;            // 最大同時ポジション数
input int      Max_Trades_Per_Day     = 5;            // 1日の最大トレード数

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間フィルター                                     |
//+------------------------------------------------------------------+
input group "=== 時間フィルター ==="
input bool     TimeFilter_Enable      = true;         // 時間帯フィルター有効
input int      Trade_Start_Hour       = 9;            // 取引開始時刻
input int      Trade_End_Hour         = 21;           // 取引終了時刻

//+------------------------------------------------------------------+
//| 外部パラメータ - 表示設定                                          |
//+------------------------------------------------------------------+
input group "=== 表示設定 ==="
input bool     Show_Lines             = true;         // ライン表示
input color    TrendLine_Color        = clrYellow;    // トレンドライン色
input color    SR_Color               = clrAqua;      // サポレジ色
input int      PanelX                 = 10;           // パネルX位置
input int      PanelY                 = 30;           // パネルY位置

//+------------------------------------------------------------------+
//| シグナルタイプの列挙型                                             |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL
};

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleBB;
int            handleRSI;
int            handleATR;
int            handleEMAFast;
int            handleEMASlow;
int            handleMACD;
int            handleRSIFast;

// H1環境情報
double         g_h1RangeHigh;
double         g_h1RangeLow;
double         g_h1RangeMiddle;
bool           g_h1RangeValid;

// トレンドライン
double         g_trendLineUpper;      // 上降トレンドライン（レジスタンス）
double         g_trendLineLower;      // 下降トレンドライン（サポート）
bool           g_trendLineUpperValid;
bool           g_trendLineLowerValid;

// Fintokeiリスク管理
double         g_dailyStartBalance;
double         g_dailyPnL;
datetime       g_lastDayCheck;
bool           g_tradingAllowed;
int            g_todayTradeCount;

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
      g_pipPoint = 0.1;
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
   handleBB = iBands(Symbol_to_Trade, TF_Entry, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   handleRSI = iRSI(Symbol_to_Trade, TF_Entry, RSI_Period, PRICE_CLOSE);
   handleATR = iATR(Symbol_to_Trade, TF_Entry, 14);
   handleEMAFast = iMA(Symbol_to_Trade, TF_Entry, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMASlow = iMA(Symbol_to_Trade, TF_Entry, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleMACD = iMACD(Symbol_to_Trade, TF_Entry, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   handleRSIFast = iRSI(Symbol_to_Trade, TF_Entry, RSI_Fast_Period, PRICE_CLOSE);

   if(handleBB == INVALID_HANDLE || handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE ||
      handleEMAFast == INVALID_HANDLE || handleEMASlow == INVALID_HANDLE ||
      handleMACD == INVALID_HANDLE || handleRSIFast == INVALID_HANDLE)
   {
      Print("インジケーターハンドルの作成に失敗しました");
      return INIT_FAILED;
   }

   // 初期化
   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyPnL = 0;
   g_lastDayCheck = 0;
   g_tradingAllowed = true;
   g_todayTradeCount = 0;

   Print("FintokeiScalpEA 初期化完了 - Pip値: ", g_pipPoint);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleBB != INVALID_HANDLE) IndicatorRelease(handleBB);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleEMAFast != INVALID_HANDLE) IndicatorRelease(handleEMAFast);
   if(handleEMASlow != INVALID_HANDLE) IndicatorRelease(handleEMASlow);
   if(handleMACD != INVALID_HANDLE) IndicatorRelease(handleMACD);
   if(handleRSIFast != INVALID_HANDLE) IndicatorRelease(handleRSIFast);

   ObjectsDeleteAll(0, "Scalp_");
   Print("FintokeiScalpEA 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // 日付変更チェック
   CheckNewDay();

   // Fintokeiリスク管理
   if(!CheckFintokeiRisk())
   {
      g_tradingAllowed = false;
   }

   // パネル更新
   UpdatePanel();

   // ブレイクイーブン管理
   if(BreakEven_Enable)
      ManageBreakEven();

   // 新しいバーでのみ処理（エントリー時間足）
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(Symbol_to_Trade, TF_Entry, 0);
   if(lastBarTime == currentBarTime)
      return;
   lastBarTime = currentBarTime;

   // 取引許可チェック
   if(!g_tradingAllowed)
      return;

   // 時間フィルター
   if(TimeFilter_Enable && !IsWithinTradingHours())
      return;

   // 1日の最大トレード数チェック
   if(g_todayTradeCount >= Max_Trades_Per_Day)
      return;

   // 最大ポジション数チェック
   if(CountPositions() >= Max_Positions)
      return;

   // H1環境分析
   AnalyzeH1Environment();

   // トレンドライン検出
   if(Strategy_TrendlineBB)
      DetectTrendLines();

   // シグナル検出と実行
   ENUM_SIGNAL_TYPE signal = SIGNAL_NONE;

   // 案4: トレンドライン+BB反発（推奨）
   if(Strategy_TrendlineBB && signal == SIGNAL_NONE)
      signal = CheckTrendlineBBSignal();

   // 案1: BB+H1サポレジ平均回帰
   if(Strategy_BB_SR && signal == SIGNAL_NONE)
      signal = CheckBBSRSignal();

   // 案2: BBスクイーズブレイク
   if(Strategy_BB_Squeeze && signal == SIGNAL_NONE)
      signal = CheckBBSqueezeSignal();

   // 案3: ネックライン+BB確認
   if(Strategy_NecklineBB && signal == SIGNAL_NONE)
      signal = CheckNecklineBBSignal();

   // 案5: EMAクロス+RSI（高勝率）
   if(Strategy_EMA_Cross && signal == SIGNAL_NONE)
      signal = CheckEMACrossSignal();

   // 案6: MACD+RSIモメンタム
   if(Strategy_MACD_RSI && signal == SIGNAL_NONE)
      signal = CheckMACDRSISignal();

   // トレード実行
   if(signal != SIGNAL_NONE)
      ExecuteTrade(signal);
}

//+------------------------------------------------------------------+
//| H1環境分析                                                         |
//+------------------------------------------------------------------+
void AnalyzeH1Environment()
{
   g_h1RangeValid = false;

   int highestBar = iHighest(Symbol_to_Trade, TF_Environment, MODE_HIGH, H1_Lookback_Bars, 1);
   int lowestBar = iLowest(Symbol_to_Trade, TF_Environment, MODE_LOW, H1_Lookback_Bars, 1);

   if(highestBar < 0 || lowestBar < 0)
      return;

   g_h1RangeHigh = iHigh(Symbol_to_Trade, TF_Environment, highestBar);
   g_h1RangeLow = iLow(Symbol_to_Trade, TF_Environment, lowestBar);
   g_h1RangeMiddle = (g_h1RangeHigh + g_h1RangeLow) / 2.0;

   double rangeWidth = (g_h1RangeHigh - g_h1RangeLow) / g_pipPoint;
   if(rangeWidth >= 50.0) // 最小50pips
      g_h1RangeValid = true;
}

//+------------------------------------------------------------------+
//| トレンドライン検出                                                  |
//+------------------------------------------------------------------+
void DetectTrendLines()
{
   g_trendLineUpperValid = false;
   g_trendLineLowerValid = false;

   double highs[], lows[];
   ArrayResize(highs, TL_Lookback_Bars);
   ArrayResize(lows, TL_Lookback_Bars);

   // スイングハイ/ローを取得
   int swingHighs[10], swingLows[10];
   int shCount = 0, slCount = 0;

   for(int i = 2; i < TL_Lookback_Bars - 2 && (shCount < 10 || slCount < 10); i++)
   {
      double h = iHigh(Symbol_to_Trade, TF_Environment, i);
      double h1 = iHigh(Symbol_to_Trade, TF_Environment, i-1);
      double h2 = iHigh(Symbol_to_Trade, TF_Environment, i-2);
      double h3 = iHigh(Symbol_to_Trade, TF_Environment, i+1);
      double h4 = iHigh(Symbol_to_Trade, TF_Environment, i+2);

      // スイングハイ
      if(shCount < 10 && h > h1 && h > h2 && h > h3 && h > h4)
      {
         swingHighs[shCount++] = i;
      }

      double l = iLow(Symbol_to_Trade, TF_Environment, i);
      double l1 = iLow(Symbol_to_Trade, TF_Environment, i-1);
      double l2 = iLow(Symbol_to_Trade, TF_Environment, i-2);
      double l3 = iLow(Symbol_to_Trade, TF_Environment, i+1);
      double l4 = iLow(Symbol_to_Trade, TF_Environment, i+2);

      // スイングロー
      if(slCount < 10 && l < l1 && l < l2 && l < l3 && l < l4)
      {
         swingLows[slCount++] = i;
      }
   }

   // 下降トレンドライン（スイングハイを結ぶ）- レジスタンス
   if(shCount >= 2)
   {
      double price1 = iHigh(Symbol_to_Trade, TF_Environment, swingHighs[0]);
      double price2 = iHigh(Symbol_to_Trade, TF_Environment, swingHighs[1]);
      int bar1 = swingHighs[0];
      int bar2 = swingHighs[1];

      if(bar2 > bar1 && price2 < price1) // 下降トレンド
      {
         double slope = (price2 - price1) / (bar2 - bar1);
         g_trendLineUpper = price1 + slope * (-bar1); // 現在のバー(0)での値
         g_trendLineUpperValid = true;
      }
   }

   // 上昇トレンドライン（スイングローを結ぶ）- サポート
   if(slCount >= 2)
   {
      double price1 = iLow(Symbol_to_Trade, TF_Environment, swingLows[0]);
      double price2 = iLow(Symbol_to_Trade, TF_Environment, swingLows[1]);
      int bar1 = swingLows[0];
      int bar2 = swingLows[1];

      if(bar2 > bar1 && price2 > price1) // 上昇トレンド
      {
         double slope = (price2 - price1) / (bar2 - bar1);
         g_trendLineLower = price1 + slope * (-bar1);
         g_trendLineLowerValid = true;
      }
   }

   // ライン描画
   if(Show_Lines)
      DrawTrendLines();
}

//+------------------------------------------------------------------+
//| 案4: トレンドライン+BB反発シグナル                                  |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckTrendlineBBSignal()
{
   double bbUpper[], bbMiddle[], bbLower[], rsi[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleBB, 1, 0, 3, bbUpper) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 0, 0, 3, bbMiddle) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 2, 0, 3, bbLower) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleRSI, 0, 0, 3, rsi) < 3) return SIGNAL_NONE;

   double close1 = iClose(Symbol_to_Trade, TF_Entry, 1);
   double low1 = iLow(Symbol_to_Trade, TF_Entry, 1);
   double high1 = iHigh(Symbol_to_Trade, TF_Entry, 1);
   double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   // ロングシグナル: 上昇トレンドライン付近 + BB下限 + RSI売られ過ぎ
   if(g_trendLineLowerValid)
   {
      double distanceToTL = currentPrice - g_trendLineLower;
      double distancePips = distanceToTL / g_pipPoint;

      if(distancePips >= 0 && distancePips <= TL_Proximity_Pips)
      {
         // BB下限付近
         if(low1 <= bbLower[1] || close1 <= bbLower[1] * 1.001)
         {
            // RSIフィルター
            if(!Use_RSI_Filter || rsi[1] <= RSI_Oversold)
            {
               return SIGNAL_BUY;
            }
         }
      }
   }

   // ショートシグナル: 下降トレンドライン付近 + BB上限 + RSI買われ過ぎ
   if(g_trendLineUpperValid)
   {
      double distanceToTL = g_trendLineUpper - currentPrice;
      double distancePips = distanceToTL / g_pipPoint;

      if(distancePips >= 0 && distancePips <= TL_Proximity_Pips)
      {
         // BB上限付近
         if(high1 >= bbUpper[1] || close1 >= bbUpper[1] * 0.999)
         {
            // RSIフィルター
            if(!Use_RSI_Filter || rsi[1] >= RSI_Overbought)
            {
               return SIGNAL_SELL;
            }
         }
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 案1: BB+H1サポレジ平均回帰シグナル                                  |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckBBSRSignal()
{
   if(!g_h1RangeValid) return SIGNAL_NONE;

   double bbUpper[], bbMiddle[], bbLower[], rsi[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleBB, 1, 0, 3, bbUpper) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 0, 0, 3, bbMiddle) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 2, 0, 3, bbLower) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleRSI, 0, 0, 3, rsi) < 3) return SIGNAL_NONE;

   double close1 = iClose(Symbol_to_Trade, TF_Entry, 1);
   double low1 = iLow(Symbol_to_Trade, TF_Entry, 1);
   double high1 = iHigh(Symbol_to_Trade, TF_Entry, 1);
   double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   double h1LowZone = g_h1RangeLow + 50 * g_pipPoint;  // H1サポート付近
   double h1HighZone = g_h1RangeHigh - 50 * g_pipPoint; // H1レジスタンス付近

   // ロングシグナル: H1サポート付近 + BB下限タッチ + RSI売られ過ぎ
   if(currentPrice <= h1LowZone)
   {
      if(low1 <= bbLower[1])
      {
         if(!Use_RSI_Filter || rsi[1] <= RSI_Oversold)
         {
            return SIGNAL_BUY;
         }
      }
   }

   // ショートシグナル: H1レジスタンス付近 + BB上限タッチ + RSI買われ過ぎ
   if(currentPrice >= h1HighZone)
   {
      if(high1 >= bbUpper[1])
      {
         if(!Use_RSI_Filter || rsi[1] >= RSI_Overbought)
         {
            return SIGNAL_SELL;
         }
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 案2: BBスクイーズブレイクシグナル                                   |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckBBSqueezeSignal()
{
   double bbUpper[], bbMiddle[], bbLower[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);

   if(CopyBuffer(handleBB, 1, 0, 10, bbUpper) < 10) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 0, 0, 10, bbMiddle) < 10) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 2, 0, 10, bbLower) < 10) return SIGNAL_NONE;

   // 過去のBB幅を計算
   double avgWidth = 0;
   for(int i = 3; i < 10; i++)
   {
      avgWidth += (bbUpper[i] - bbLower[i]);
   }
   avgWidth /= 7;

   // 現在のBB幅
   double currentWidth = bbUpper[1] - bbLower[1];
   double previousWidth = bbUpper[2] - bbLower[2];

   // スクイーズ状態からの拡大を検出
   double squeezeRatio = previousWidth / avgWidth * 100;
   double expansionRatio = currentWidth / previousWidth;

   if(squeezeRatio < BB_Squeeze_Threshold * 100 && expansionRatio > 1.5)
   {
      double close1 = iClose(Symbol_to_Trade, TF_Entry, 1);
      double open1 = iOpen(Symbol_to_Trade, TF_Entry, 1);

      // ブレイク方向を判定
      if(close1 > bbUpper[1] && close1 > open1)
      {
         return SIGNAL_BUY;
      }
      else if(close1 < bbLower[1] && close1 < open1)
      {
         return SIGNAL_SELL;
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 案3: ネックライン+BB確認シグナル                                    |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckNecklineBBSignal()
{
   // ダブルトップ/ボトムのネックライン検出
   double neckline = 0;
   bool isDoubleTop = false;
   bool isDoubleBottom = false;

   // スイングポイントからネックラインを検出
   double swingHigh1 = 0, swingHigh2 = 0;
   double swingLow1 = 0, swingLow2 = 0;
   double necklineLow = 0, necklineHigh = 0;

   for(int i = 5; i < 50; i++)
   {
      double h = iHigh(Symbol_to_Trade, TF_Environment, i);
      double h1 = iHigh(Symbol_to_Trade, TF_Environment, i-1);
      double h2 = iHigh(Symbol_to_Trade, TF_Environment, i-2);
      double h3 = iHigh(Symbol_to_Trade, TF_Environment, i+1);
      double h4 = iHigh(Symbol_to_Trade, TF_Environment, i+2);

      if(h > h1 && h > h2 && h > h3 && h > h4)
      {
         if(swingHigh1 == 0) swingHigh1 = h;
         else if(swingHigh2 == 0)
         {
            swingHigh2 = h;
            // ダブルトップ判定
            if(MathAbs(swingHigh1 - swingHigh2) / g_pipPoint < 30)
            {
               isDoubleTop = true;
               // ネックラインは間の安値
               int lowBar = iLowest(Symbol_to_Trade, TF_Environment, MODE_LOW, i, 1);
               necklineLow = iLow(Symbol_to_Trade, TF_Environment, lowBar);
            }
            break;
         }
      }
   }

   for(int i = 5; i < 50; i++)
   {
      double l = iLow(Symbol_to_Trade, TF_Environment, i);
      double l1 = iLow(Symbol_to_Trade, TF_Environment, i-1);
      double l2 = iLow(Symbol_to_Trade, TF_Environment, i-2);
      double l3 = iLow(Symbol_to_Trade, TF_Environment, i+1);
      double l4 = iLow(Symbol_to_Trade, TF_Environment, i+2);

      if(l < l1 && l < l2 && l < l3 && l < l4)
      {
         if(swingLow1 == 0) swingLow1 = l;
         else if(swingLow2 == 0)
         {
            swingLow2 = l;
            // ダブルボトム判定
            if(MathAbs(swingLow1 - swingLow2) / g_pipPoint < 30)
            {
               isDoubleBottom = true;
               // ネックラインは間の高値
               int highBar = iHighest(Symbol_to_Trade, TF_Environment, MODE_HIGH, i, 1);
               necklineHigh = iHigh(Symbol_to_Trade, TF_Environment, highBar);
            }
            break;
         }
      }
   }

   double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
   double bbUpper[], bbMiddle[], bbLower[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);

   if(CopyBuffer(handleBB, 1, 0, 3, bbUpper) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 0, 0, 3, bbMiddle) < 3) return SIGNAL_NONE;
   if(CopyBuffer(handleBB, 2, 0, 3, bbLower) < 3) return SIGNAL_NONE;

   // ダブルボトム + ネックライン上でサポート + BB確認
   if(isDoubleBottom && necklineHigh > 0)
   {
      double distToNL = MathAbs(currentPrice - necklineHigh) / g_pipPoint;
      if(distToNL < 20 && currentPrice >= necklineHigh)
      {
         double low1 = iLow(Symbol_to_Trade, TF_Entry, 1);
         if(low1 <= bbLower[1] * 1.002)
         {
            return SIGNAL_BUY;
         }
      }
   }

   // ダブルトップ + ネックライン下でレジスタンス + BB確認
   if(isDoubleTop && necklineLow > 0)
   {
      double distToNL = MathAbs(currentPrice - necklineLow) / g_pipPoint;
      if(distToNL < 20 && currentPrice <= necklineLow)
      {
         double high1 = iHigh(Symbol_to_Trade, TF_Entry, 1);
         if(high1 >= bbUpper[1] * 0.998)
         {
            return SIGNAL_SELL;
         }
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 案5: EMAクロス+RSIシグナル（高勝率戦略）                            |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckEMACrossSignal()
{
   double emaFast[], emaSlow[], rsi[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleEMAFast, 0, 0, 5, emaFast) < 5) return SIGNAL_NONE;
   if(CopyBuffer(handleEMASlow, 0, 0, 5, emaSlow) < 5) return SIGNAL_NONE;
   if(CopyBuffer(handleRSI, 0, 0, 5, rsi) < 5) return SIGNAL_NONE;

   // EMAクロスオーバー検出
   bool goldenCross = (emaFast[2] <= emaSlow[2]) && (emaFast[1] > emaSlow[1]);  // 買いクロス
   bool deadCross = (emaFast[2] >= emaSlow[2]) && (emaFast[1] < emaSlow[1]);    // 売りクロス

   // 価格がEMAより上/下にあることを確認
   double close1 = iClose(Symbol_to_Trade, TF_Entry, 1);

   // ロングシグナル: ゴールデンクロス + RSI中立～売られ過ぎからの回復
   if(goldenCross)
   {
      // RSIが50以下から上昇中、または売られ過ぎからの回復
      if(rsi[1] < 60 && rsi[1] > rsi[2])
      {
         // 価格がEMAの上にある
         if(close1 > emaFast[1])
         {
            return SIGNAL_BUY;
         }
      }
   }

   // ショートシグナル: デッドクロス + RSI中立～買われ過ぎからの下落
   if(deadCross)
   {
      // RSIが50以上から下落中、または買われ過ぎからの下落
      if(rsi[1] > 40 && rsi[1] < rsi[2])
      {
         // 価格がEMAの下にある
         if(close1 < emaFast[1])
         {
            return SIGNAL_SELL;
         }
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 案6: MACD+RSIモメンタムシグナル                                     |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckMACDRSISignal()
{
   double macdMain[], macdSignal[], rsiFast[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(rsiFast, true);

   if(CopyBuffer(handleMACD, 0, 0, 5, macdMain) < 5) return SIGNAL_NONE;
   if(CopyBuffer(handleMACD, 1, 0, 5, macdSignal) < 5) return SIGNAL_NONE;
   if(CopyBuffer(handleRSIFast, 0, 0, 5, rsiFast) < 5) return SIGNAL_NONE;

   // MACDクロスオーバー検出
   bool macdBullCross = (macdMain[2] <= macdSignal[2]) && (macdMain[1] > macdSignal[1]);
   bool macdBearCross = (macdMain[2] >= macdSignal[2]) && (macdMain[1] < macdSignal[1]);

   // MACDヒストグラムの方向
   double histogram1 = macdMain[1] - macdSignal[1];
   double histogram2 = macdMain[2] - macdSignal[2];
   bool histogramIncreasing = histogram1 > histogram2;
   bool histogramDecreasing = histogram1 < histogram2;

   // ロングシグナル: MACDブルクロス or ヒストグラム増加 + RSI売られ過ぎからの回復
   if(macdBullCross || (histogram1 > 0 && histogramIncreasing))
   {
      // RSIが売られ過ぎから回復中（30-50の範囲で上昇）
      if(rsiFast[1] > 30 && rsiFast[1] < 55 && rsiFast[1] > rsiFast[2])
      {
         return SIGNAL_BUY;
      }
   }

   // ショートシグナル: MACDベアクロス or ヒストグラム減少 + RSI買われ過ぎから下落
   if(macdBearCross || (histogram1 < 0 && histogramDecreasing))
   {
      // RSIが買われ過ぎから下落中（50-70の範囲で下降）
      if(rsiFast[1] < 70 && rsiFast[1] > 45 && rsiFast[1] < rsiFast[2])
      {
         return SIGNAL_SELL;
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| トレード実行                                                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_SIGNAL_TYPE signal)
{
   double entryPrice, sl, tp, lotSize;
   double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   if(signal == SIGNAL_BUY)
   {
      entryPrice = ask;
      sl = entryPrice - SL_Pips * g_pipPoint;
      tp = entryPrice + TP_Pips * g_pipPoint;
   }
   else if(signal == SIGNAL_SELL)
   {
      entryPrice = bid;
      sl = entryPrice + SL_Pips * g_pipPoint;
      tp = entryPrice - TP_Pips * g_pipPoint;
   }
   else
   {
      return;
   }

   // リスクリワード比チェック
   double slDistance = MathAbs(entryPrice - sl);
   double tpDistance = MathAbs(tp - entryPrice);
   if(tpDistance / slDistance < Min_RR_Ratio)
   {
      tp = signal == SIGNAL_BUY ?
           entryPrice + slDistance * Min_RR_Ratio :
           entryPrice - slDistance * Min_RR_Ratio;
   }

   // ロットサイズ計算
   lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("ロットサイズ計算エラー");
      return;
   }

   // 注文発注
   string comment = EA_Comment;
   bool result = false;

   if(signal == SIGNAL_BUY)
   {
      result = trade.Buy(lotSize, Symbol_to_Trade, entryPrice, sl, tp, comment);
   }
   else
   {
      result = trade.Sell(lotSize, Symbol_to_Trade, entryPrice, sl, tp, comment);
   }

   if(result)
   {
      g_todayTradeCount++;
      Print("注文成功: ", comment, " Lot=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
   }
   else
   {
      Print("注文失敗: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ロットサイズ計算                                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0 || tickValue <= 0)
      return 0;

   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);

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

   double overallLoss = InitialBalance - equity;
   double overallLossPct = (overallLoss / InitialBalance) * 100.0;
   double overallLimit = OverallLossLimitPct - SafetyBufferPct;

   if(overallLossPct >= overallLimit)
   {
      Print("警告: 全体の最大損失率に達しました - ", DoubleToString(overallLossPct, 2), "%");
      return false;
   }

   g_dailyPnL = equity - g_dailyStartBalance;
   double dailyLossPct = (-g_dailyPnL / g_dailyStartBalance) * 100.0;
   double dailyLimit = DailyLossLimitPct - SafetyBufferPct;

   if(g_dailyPnL < 0 && dailyLossPct >= dailyLimit)
   {
      Print("警告: 日次の最大損失率に達しました - ", DoubleToString(dailyLossPct, 2), "%");
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
      g_todayTradeCount = 0;
      Print("新しい日: 日次リセット");
   }
}

//+------------------------------------------------------------------+
//| 取引時間内かチェック                                                |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= Trade_Start_Hour && dt.hour < Trade_End_Hour);
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
//| トレンドライン描画                                                  |
//+------------------------------------------------------------------+
void DrawTrendLines()
{
   datetime time0 = iTime(Symbol_to_Trade, TF_Environment, 0);
   datetime time50 = iTime(Symbol_to_Trade, TF_Environment, TL_Lookback_Bars);

   if(g_trendLineLowerValid)
   {
      ObjectDelete(0, "Scalp_TL_Support");
      ObjectCreate(0, "Scalp_TL_Support", OBJ_HLINE, 0, time0, g_trendLineLower);
      ObjectSetInteger(0, "Scalp_TL_Support", OBJPROP_COLOR, TrendLine_Color);
      ObjectSetInteger(0, "Scalp_TL_Support", OBJPROP_STYLE, STYLE_DASH);
   }

   if(g_trendLineUpperValid)
   {
      ObjectDelete(0, "Scalp_TL_Resist");
      ObjectCreate(0, "Scalp_TL_Resist", OBJ_HLINE, 0, time0, g_trendLineUpper);
      ObjectSetInteger(0, "Scalp_TL_Resist", OBJPROP_COLOR, TrendLine_Color);
      ObjectSetInteger(0, "Scalp_TL_Resist", OBJPROP_STYLE, STYLE_DASH);
   }

   // H1サポレジ
   if(g_h1RangeValid)
   {
      ObjectDelete(0, "Scalp_H1_High");
      ObjectCreate(0, "Scalp_H1_High", OBJ_HLINE, 0, time0, g_h1RangeHigh);
      ObjectSetInteger(0, "Scalp_H1_High", OBJPROP_COLOR, SR_Color);

      ObjectDelete(0, "Scalp_H1_Low");
      ObjectCreate(0, "Scalp_H1_Low", OBJ_HLINE, 0, time0, g_h1RangeLow);
      ObjectSetInteger(0, "Scalp_H1_Low", OBJPROP_COLOR, SR_Color);
   }
}

//+------------------------------------------------------------------+
//| パネル更新                                                         |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   int y = PanelY;
   int lineHeight = 16;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   CreateLabel("Panel_Title", "=== Fintokei Scalp EA ===", PanelX, y, clrWhite);
   y += lineHeight;

   CreateLabel("Panel_Balance", "残高: " + DoubleToString(balance, 0), PanelX, y, clrWhite);
   y += lineHeight;

   // 有効な戦略
   string activeStrat = "";
   if(Strategy_TrendlineBB) activeStrat += "TL+BB ";
   if(Strategy_BB_SR) activeStrat += "BB+SR ";
   if(Strategy_BB_Squeeze) activeStrat += "Squeeze ";
   if(Strategy_NecklineBB) activeStrat += "NL+BB ";
   if(Strategy_EMA_Cross) activeStrat += "EMA ";
   if(Strategy_MACD_RSI) activeStrat += "MACD ";
   CreateLabel("Panel_Strategy", "戦略: " + activeStrat, PanelX, y, clrYellow);
   y += lineHeight;

   CreateLabel("Panel_Trades", "本日: " + IntegerToString(g_todayTradeCount) + "/" + IntegerToString(Max_Trades_Per_Day),
               PanelX, y, clrWhite);
   y += lineHeight;

   string status = g_tradingAllowed ? "取引許可" : "取引停止";
   color statusColor = g_tradingAllowed ? clrLime : clrRed;
   CreateLabel("Panel_Status", status, PanelX, y, statusColor);
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
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}
//+------------------------------------------------------------------+
