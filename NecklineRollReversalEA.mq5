//+------------------------------------------------------------------+
//|                                      NecklineRollReversalEA.mq5 |
//|               XAUUSD専用 ネックラインロールリバーサルEA         |
//|              Fintokeiチャレンジプラン対応 資金管理付き          |
//+------------------------------------------------------------------+
#property copyright "Neckline Roll Reversal EA"
#property link      ""
#property version   "1.01"
#property strict

//+------------------------------------------------------------------+
//| 入力パラメータ                                                   |
//+------------------------------------------------------------------+
input group "===== 基本設定 ====="
input double   InitialBalance       = 0;         // 初期資金（0=自動検出）
input double   DailyLossLimit       = 4.9;       // 1日の最大損失率(%) ※5%未満に設定
input double   TotalLossLimit       = 9.9;       // 全体の最大損失率(%) ※10%未満に設定
input double   MaxRiskPerTrade      = 3.0;       // 1トレードあたりの最大リスク(%)
input double   MaxOpenRisk          = 3.0;       // 同時オープンポジションの最大リスク(%)
input int      MagicNumber          = 20251222;  // マジックナンバー

input group "===== ネックライン設定 ====="
input int      LookbackBars         = 100;       // ネックライン検出のルックバック期間
input int      SwingStrength        = 5;         // スイングポイント判定の強度（前後のバー数）
input int      MinTouches           = 2;         // 重要ラインと見なす最小タッチ回数
input double   NecklineTolerance    = 50;        // ネックライン許容誤差（ポイント）
input double   BreakoutMinBody      = 100;       // ブレイクアウト確認の最小実体サイズ（ポイント）

input group "===== ブレイクアウト・リターンムーブ設定 ====="
input int      BreakoutConfirmBars  = 3;         // ブレイクアウト確認に必要なバー数
input int      MaxReturnWaitBars    = 20;        // リターンムーブ待機の最大バー数
input double   ReturnTolerance      = 30;        // リターンムーブ許容誤差（ポイント）

input group "===== プライスアクション設定 ====="
input double   PinBarWickRatio      = 2.0;       // ピンバーのヒゲ/実体比率
input double   PinBarBodyMaxRatio   = 0.33;      // ピンバーの実体/全体比率上限
input double   EngulfingMinRatio    = 1.1;       // 包み足の最小サイズ比率

input group "===== リスク管理設定 ====="
input double   RiskRewardRatio      = 2.0;       // リスク・リワード比率（1:X）
input double   SLBufferPoints       = 15;        // SLバッファ（ポイント）
input bool     UseFixedSL           = false;     // 固定SLを使用
input double   FixedSLPoints        = 500;       // 固定SL幅（ポイント）

input group "===== デイリーピボット設定 ====="
input bool     UsePivotTP           = false;     // ピボットでの利確を使用
input bool     UsePivotAsTarget     = false;     // ピボットを目標価格として使用

input group "===== 建値決済設定 ====="
input bool     UseBreakeven         = true;      // 建値決済を使用
input double   BreakevenTrigger     = 50;        // 建値決済発動ポイント
input double   BreakevenProfit      = 25;        // 建値決済時の確保ポイント

input group "===== トレーリングストップ設定 ====="
input bool     UseTrailingStop      = true;      // トレーリングストップを使用
input double   TrailingStart        = 80;        // トレーリング開始ポイント（含み益）
input double   TrailingStep         = 30;        // トレーリングステップ（ポイント）
input double   TrailingDistance     = 50;        // トレーリング距離（ポイント）

input group "===== タイムフレーム・フィルター設定 ====="
input ENUM_TIMEFRAMES  TradingTimeframe = PERIOD_H1;  // 取引タイムフレーム
input int      TradingStartHour     = 0;         // 取引開始時間（サーバー時間）
input int      TradingEndHour       = 24;        // 取引終了時間（サーバー時間）
input bool     TradeOnMonday        = true;      // 月曜日に取引
input bool     TradeOnFriday        = true;      // 金曜日に取引

//+------------------------------------------------------------------+
//| ネックライン構造体                                               |
//+------------------------------------------------------------------+
struct SNeckline
{
   double   price;           // ネックライン価格
   int      touches;         // タッチ回数
   bool     isResistance;    // レジスタンスかサポートか
   bool     isBroken;        // ブレイクされたか
   datetime breakTime;       // ブレイク時刻
   int      breakBar;        // ブレイクしたバーのインデックス
   bool     waitingRetest;   // リテスト待ち状態
};

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
double g_InitialBalance;           // 初期資金
double g_DailyStartEquity;         // 1日の開始時有効証拠金
datetime g_LastDailyReset;         // 最後の日次リセット時刻
bool g_TradingBlocked;             // 取引禁止フラグ
datetime g_LastBarTime;            // 最後のバー時刻
SNeckline g_Necklines[];           // 検出されたネックライン
int g_NecklineCount;               // ネックライン数
double g_DailyPivot;               // デイリーピボット
double g_DailyR1, g_DailyR2, g_DailyR3;  // レジスタンスレベル
double g_DailyS1, g_DailyS2, g_DailyS3;  // サポートレベル
double g_PreviousHigh, g_PreviousLow, g_PreviousClose;  // 前日の高値・安値・終値

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 初期資金の設定
   if(InitialBalance <= 0)
      g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   else
      g_InitialBalance = InitialBalance;

   //--- 日次開始証拠金の初期化
   g_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_LastDailyReset = 0;
   g_TradingBlocked = false;
   g_LastBarTime = 0;
   g_NecklineCount = 0;

   //--- シンボル確認
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("警告: このEAはXAUUSD用に設計されています。現在のシンボル: ", _Symbol);
   }

   //--- デイリーピボットの初期計算
   CalculateDailyPivot();

   Print("=== ネックラインロールリバーサルEA 起動 ===");
   Print("初期資金: ", DoubleToString(g_InitialBalance, 0), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("1日最大損失: ", DoubleToString(DailyLossLimit, 1), "%");
   Print("全体最大損失: ", DoubleToString(TotalLossLimit, 1), "%");
   Print("タイムフレーム: ", EnumToString(TradingTimeframe));
   Print("デイリーピボット: ", DoubleToString(g_DailyPivot, _Digits));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== ネックラインロールリバーサルEA 停止 ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 日次リセットの確認
   CheckDailyReset();

   //--- 損失管理の確認
   if(!CheckRiskLimits())
   {
      if(!g_TradingBlocked)
      {
         CloseAllPositions("損失制限到達");
         g_TradingBlocked = true;
         Print("!!! 取引停止: 損失制限に達しました !!!");
      }
      return;
   }

   //--- 建値決済の確認
   if(UseBreakeven)
      ManageBreakeven();

   //--- トレーリングストップの確認
   if(UseTrailingStop)
      ManageTrailingStop();

   //--- ピボットでの利確確認
   if(UsePivotTP)
      CheckPivotTP();

   //--- 含み損監視
   MonitorUnrealizedLoss();

   //--- 新しいバーの確認
   datetime currentBarTime = iTime(_Symbol, TradingTimeframe, 0);
   if(currentBarTime == g_LastBarTime)
      return;  // 同じバー内では処理しない

   g_LastBarTime = currentBarTime;

   //--- 取引時間のフィルタリング
   if(!IsTradeTime())
      return;

   //--- 日付が変わったらピボット再計算
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   static int lastDay = -1;
   if(dt.day != lastDay)
   {
      CalculateDailyPivot();
      lastDay = dt.day;
   }

   //--- ネックラインの検出と更新
   DetectNecklines();

   //--- ブレイクアウトの確認
   CheckBreakouts();

   //--- リターンムーブとエントリーシグナルの確認
   CheckReturnMoveAndEntry();
}

//+------------------------------------------------------------------+
//| 日次リセットの確認                                               |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime serverTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);

   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

   if(g_LastDailyReset < todayStart)
   {
      g_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_LastDailyReset = todayStart;
      g_TradingBlocked = false;

      Print("=== 日次リセット ===");
      Print("本日開始時有効証拠金: ", DoubleToString(g_DailyStartEquity, 2));
   }
}

//+------------------------------------------------------------------+
//| リスク制限の確認                                                 |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 1日の最大損失率チェック
   double dailyLossPercent = (g_DailyStartEquity - currentEquity) / g_DailyStartEquity * 100.0;
   if(dailyLossPercent >= DailyLossLimit)
   {
      Print("!!! 1日の最大損失率到達: ", DoubleToString(dailyLossPercent, 2), "% !!!");
      return false;
   }

   //--- 全体の最大損失率チェック
   double totalLossPercent = (g_InitialBalance - currentEquity) / g_InitialBalance * 100.0;
   if(totalLossPercent >= TotalLossLimit)
   {
      Print("!!! 全体の最大損失率到達: ", DoubleToString(totalLossPercent, 2), "% !!!");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 取引時間の確認                                                   |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   //--- 曜日フィルター
   if(dt.day_of_week == 0)  // 日曜日
      return false;
   if(dt.day_of_week == 6)  // 土曜日
      return false;
   if(dt.day_of_week == 1 && !TradeOnMonday)
      return false;
   if(dt.day_of_week == 5 && !TradeOnFriday)
      return false;

   //--- 時間フィルター
   if(dt.hour < TradingStartHour || dt.hour >= TradingEndHour)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| デイリーピボットの計算                                           |
//+------------------------------------------------------------------+
void CalculateDailyPivot()
{
   //--- 前日のOHLCを取得
   MqlRates dailyRates[];
   ArraySetAsSeries(dailyRates, true);

   if(CopyRates(_Symbol, PERIOD_D1, 1, 1, dailyRates) < 1)
   {
      Print("デイリーレート取得エラー");
      return;
   }

   g_PreviousHigh = dailyRates[0].high;
   g_PreviousLow = dailyRates[0].low;
   g_PreviousClose = dailyRates[0].close;

   //--- ピボットポイント計算
   g_DailyPivot = (g_PreviousHigh + g_PreviousLow + g_PreviousClose) / 3.0;

   //--- サポート・レジスタンスレベル
   g_DailyR1 = 2.0 * g_DailyPivot - g_PreviousLow;
   g_DailyS1 = 2.0 * g_DailyPivot - g_PreviousHigh;
   g_DailyR2 = g_DailyPivot + (g_PreviousHigh - g_PreviousLow);
   g_DailyS2 = g_DailyPivot - (g_PreviousHigh - g_PreviousLow);
   g_DailyR3 = g_PreviousHigh + 2.0 * (g_DailyPivot - g_PreviousLow);
   g_DailyS3 = g_PreviousLow - 2.0 * (g_PreviousHigh - g_DailyPivot);

   Print("=== デイリーピボット更新 ===");
   Print("Pivot: ", DoubleToString(g_DailyPivot, _Digits));
   Print("R1: ", DoubleToString(g_DailyR1, _Digits), " R2: ", DoubleToString(g_DailyR2, _Digits));
   Print("S1: ", DoubleToString(g_DailyS1, _Digits), " S2: ", DoubleToString(g_DailyS2, _Digits));
}

//+------------------------------------------------------------------+
//| ネックラインの検出                                               |
//+------------------------------------------------------------------+
void DetectNecklines()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, TradingTimeframe, 0, LookbackBars, rates) < LookbackBars)
      return;

   //--- スイングハイ・スイングローの検出
   double swingHighs[];
   double swingLows[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);

   for(int i = SwingStrength; i < LookbackBars - SwingStrength; i++)
   {
      //--- スイングハイの判定
      bool isSwingHigh = true;
      for(int j = 1; j <= SwingStrength; j++)
      {
         if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         int size = ArraySize(swingHighs);
         ArrayResize(swingHighs, size + 1);
         swingHighs[size] = rates[i].high;
      }

      //--- スイングローの判定
      bool isSwingLow = true;
      for(int j = 1; j <= SwingStrength; j++)
      {
         if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow)
      {
         int size = ArraySize(swingLows);
         ArrayResize(swingLows, size + 1);
         swingLows[size] = rates[i].low;
      }
   }

   //--- 重要なレベルの特定（複数タッチ）
   ArrayResize(g_Necklines, 0);
   g_NecklineCount = 0;

   double tolerance = NecklineTolerance * _Point;

   //--- レジスタンスレベルの検出
   for(int i = 0; i < ArraySize(swingHighs); i++)
   {
      int touches = 1;
      double avgPrice = swingHighs[i];

      for(int j = i + 1; j < ArraySize(swingHighs); j++)
      {
         if(MathAbs(swingHighs[i] - swingHighs[j]) <= tolerance)
         {
            touches++;
            avgPrice = (avgPrice * (touches - 1) + swingHighs[j]) / touches;
         }
      }

      if(touches >= MinTouches)
      {
         //--- 既存のネックラインと重複チェック
         bool exists = false;
         for(int k = 0; k < g_NecklineCount; k++)
         {
            if(MathAbs(g_Necklines[k].price - avgPrice) <= tolerance)
            {
               exists = true;
               break;
            }
         }

         if(!exists)
         {
            ArrayResize(g_Necklines, g_NecklineCount + 1);
            g_Necklines[g_NecklineCount].price = avgPrice;
            g_Necklines[g_NecklineCount].touches = touches;
            g_Necklines[g_NecklineCount].isResistance = true;
            g_Necklines[g_NecklineCount].isBroken = false;
            g_Necklines[g_NecklineCount].waitingRetest = false;
            g_NecklineCount++;
         }
      }
   }

   //--- サポートレベルの検出
   for(int i = 0; i < ArraySize(swingLows); i++)
   {
      int touches = 1;
      double avgPrice = swingLows[i];

      for(int j = i + 1; j < ArraySize(swingLows); j++)
      {
         if(MathAbs(swingLows[i] - swingLows[j]) <= tolerance)
         {
            touches++;
            avgPrice = (avgPrice * (touches - 1) + swingLows[j]) / touches;
         }
      }

      if(touches >= MinTouches)
      {
         bool exists = false;
         for(int k = 0; k < g_NecklineCount; k++)
         {
            if(MathAbs(g_Necklines[k].price - avgPrice) <= tolerance)
            {
               exists = true;
               break;
            }
         }

         if(!exists)
         {
            ArrayResize(g_Necklines, g_NecklineCount + 1);
            g_Necklines[g_NecklineCount].price = avgPrice;
            g_Necklines[g_NecklineCount].touches = touches;
            g_Necklines[g_NecklineCount].isResistance = false;
            g_Necklines[g_NecklineCount].isBroken = false;
            g_Necklines[g_NecklineCount].waitingRetest = false;
            g_NecklineCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ブレイクアウトの確認                                             |
//+------------------------------------------------------------------+
void CheckBreakouts()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, TradingTimeframe, 0, BreakoutConfirmBars + 1, rates) < BreakoutConfirmBars + 1)
      return;

   double tolerance = NecklineTolerance * _Point;
   double minBody = BreakoutMinBody * _Point;

   for(int i = 0; i < g_NecklineCount; i++)
   {
      if(g_Necklines[i].isBroken)
         continue;

      double necklinePrice = g_Necklines[i].price;

      //--- レジスタンスのブレイクアウト確認（上抜け）
      if(g_Necklines[i].isResistance)
      {
         //--- 直近バーの実体終値がラインより上で確定
         double body = MathAbs(rates[1].close - rates[1].open);
         bool isBullishBreak = rates[1].close > necklinePrice + tolerance &&
                               rates[1].close > rates[1].open &&  // 陽線
                               body >= minBody;                    // 大きな実体

         if(isBullishBreak)
         {
            g_Necklines[i].isBroken = true;
            g_Necklines[i].breakTime = rates[1].time;
            g_Necklines[i].breakBar = 1;
            g_Necklines[i].waitingRetest = true;
            Print("レジスタンスブレイクアウト検出: ", DoubleToString(necklinePrice, _Digits));
         }
      }
      //--- サポートのブレイクアウト確認（下抜け）
      else
      {
         double body = MathAbs(rates[1].close - rates[1].open);
         bool isBearishBreak = rates[1].close < necklinePrice - tolerance &&
                               rates[1].close < rates[1].open &&  // 陰線
                               body >= minBody;                    // 大きな実体

         if(isBearishBreak)
         {
            g_Necklines[i].isBroken = true;
            g_Necklines[i].breakTime = rates[1].time;
            g_Necklines[i].breakBar = 1;
            g_Necklines[i].waitingRetest = true;
            Print("サポートブレイクアウト検出: ", DoubleToString(necklinePrice, _Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| リターンムーブとエントリーシグナルの確認                         |
//+------------------------------------------------------------------+
void CheckReturnMoveAndEntry()
{
   //--- 既にポジションがある場合はスキップ
   if(HasOpenPosition())
      return;

   //--- オープンリスクの確認
   if(!CheckOpenRisk())
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, TradingTimeframe, 0, 5, rates) < 5)
      return;

   double returnTol = ReturnTolerance * _Point;

   for(int i = 0; i < g_NecklineCount; i++)
   {
      if(!g_Necklines[i].isBroken || !g_Necklines[i].waitingRetest)
         continue;

      //--- リターンムーブ待機期間のチェック
      int barsSinceBreak = iBarShift(_Symbol, TradingTimeframe, g_Necklines[i].breakTime);
      if(barsSinceBreak > MaxReturnWaitBars)
      {
         g_Necklines[i].waitingRetest = false;  // 待機期限切れ
         continue;
      }

      double necklinePrice = g_Necklines[i].price;

      //--- 元レジスタンス→サポートへの転換（買いエントリー）
      if(g_Necklines[i].isResistance)
      {
         //--- 価格がネックラインまで戻ってきたか
         bool isRetesting = rates[1].low <= necklinePrice + returnTol &&
                            rates[1].close >= necklinePrice - returnTol;

         if(isRetesting)
         {
            //--- プライスアクションシグナルの確認
            int signal = CheckPriceActionSignal(rates, true);  // 買いシグナル

            if(signal > 0)
            {
               double sl = CalculateSL(rates, true, necklinePrice);
               double tp = CalculateTP(rates[1].close, sl, true);

               if(ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Neckline_RR_Buy"))
               {
                  g_Necklines[i].waitingRetest = false;
                  Print("ロールリバーサル買いエントリー: Price=", DoubleToString(rates[1].close, _Digits));
               }
            }
         }
      }
      //--- 元サポート→レジスタンスへの転換（売りエントリー）
      else
      {
         bool isRetesting = rates[1].high >= necklinePrice - returnTol &&
                            rates[1].close <= necklinePrice + returnTol;

         if(isRetesting)
         {
            int signal = CheckPriceActionSignal(rates, false);  // 売りシグナル

            if(signal > 0)
            {
               double sl = CalculateSL(rates, false, necklinePrice);
               double tp = CalculateTP(rates[1].close, sl, false);

               if(ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Neckline_RR_Sell"))
               {
                  g_Necklines[i].waitingRetest = false;
                  Print("ロールリバーサル売りエントリー: Price=", DoubleToString(rates[1].close, _Digits));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| プライスアクションシグナルの確認                                 |
//+------------------------------------------------------------------+
int CheckPriceActionSignal(MqlRates &rates[], bool isBuy)
{
   //--- ピンバーの確認
   if(IsPinBar(rates, isBuy))
      return 1;

   //--- 包み足の確認
   if(IsEngulfingBar(rates, isBuy))
      return 2;

   //--- ツーバーリバーサルの確認
   if(IsTwoBarReversal(rates, isBuy))
      return 3;

   return 0;
}

//+------------------------------------------------------------------+
//| ピンバーの判定                                                   |
//+------------------------------------------------------------------+
bool IsPinBar(MqlRates &rates[], bool isBuy)
{
   double open = rates[1].open;
   double high = rates[1].high;
   double low = rates[1].low;
   double close = rates[1].close;

   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalRange = high - low;

   if(totalRange == 0)
      return false;

   double bodyRatio = body / totalRange;

   if(isBuy)
   {
      //--- 買いピンバー（ハンマー）: 下ヒゲが長い
      double wickRatio = (body > 0) ? lowerWick / body : 0;
      if(lowerWick > upperWick * PinBarWickRatio &&
         bodyRatio <= PinBarBodyMaxRatio &&
         wickRatio >= PinBarWickRatio)
      {
         Print("買いピンバー検出");
         return true;
      }
   }
   else
   {
      //--- 売りピンバー（シューティングスター）: 上ヒゲが長い
      double wickRatio = (body > 0) ? upperWick / body : 0;
      if(upperWick > lowerWick * PinBarWickRatio &&
         bodyRatio <= PinBarBodyMaxRatio &&
         wickRatio >= PinBarWickRatio)
      {
         Print("売りピンバー検出");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| 包み足の判定                                                     |
//+------------------------------------------------------------------+
bool IsEngulfingBar(MqlRates &rates[], bool isBuy)
{
   double currOpen = rates[1].open;
   double currClose = rates[1].close;
   double currBody = MathAbs(currClose - currOpen);

   double prevOpen = rates[2].open;
   double prevClose = rates[2].close;
   double prevBody = MathAbs(prevClose - prevOpen);

   if(prevBody == 0)
      return false;

   if(isBuy)
   {
      //--- 買い包み足: 陽線が前の陰線を完全に包む
      bool prevBearish = prevClose < prevOpen;
      bool currBullish = currClose > currOpen;
      bool engulfs = currOpen <= prevClose && currClose >= prevOpen;
      bool sizeOK = currBody >= prevBody * EngulfingMinRatio;

      if(prevBearish && currBullish && engulfs && sizeOK)
      {
         Print("買い包み足検出");
         return true;
      }
   }
   else
   {
      //--- 売り包み足: 陰線が前の陽線を完全に包む
      bool prevBullish = prevClose > prevOpen;
      bool currBearish = currClose < currOpen;
      bool engulfs = currOpen >= prevClose && currClose <= prevOpen;
      bool sizeOK = currBody >= prevBody * EngulfingMinRatio;

      if(prevBullish && currBearish && engulfs && sizeOK)
      {
         Print("売り包み足検出");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| ツーバーリバーサルの判定                                         |
//+------------------------------------------------------------------+
bool IsTwoBarReversal(MqlRates &rates[], bool isBuy)
{
   double high1 = rates[1].high;
   double low1 = rates[1].low;
   double close1 = rates[1].close;
   double open1 = rates[1].open;

   double high2 = rates[2].high;
   double low2 = rates[2].low;
   double close2 = rates[2].close;
   double open2 = rates[2].open;

   if(isBuy)
   {
      //--- 2本合わせて下ヒゲが長い形状
      double combinedLow = MathMin(low1, low2);
      double combinedHigh = MathMax(high1, high2);
      double combinedBody = MathAbs(close1 - open2);
      double lowerWick = MathMin(open2, close1) - combinedLow;
      double totalRange = combinedHigh - combinedLow;

      if(totalRange == 0)
         return false;

      //--- 1本目が陰線、2本目が陽線で反転
      bool pattern = close2 < open2 && close1 > open1 && close1 > open2;
      double wickRatio = lowerWick / totalRange;

      if(pattern && wickRatio >= 0.5)
      {
         Print("買いツーバーリバーサル検出");
         return true;
      }
   }
   else
   {
      double combinedLow = MathMin(low1, low2);
      double combinedHigh = MathMax(high1, high2);
      double combinedBody = MathAbs(close1 - open2);
      double upperWick = combinedHigh - MathMax(open2, close1);
      double totalRange = combinedHigh - combinedLow;

      if(totalRange == 0)
         return false;

      //--- 1本目が陽線、2本目が陰線で反転
      bool pattern = close2 > open2 && close1 < open1 && close1 < open2;
      double wickRatio = upperWick / totalRange;

      if(pattern && wickRatio >= 0.5)
      {
         Print("売りツーバーリバーサル検出");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| SLの計算                                                         |
//+------------------------------------------------------------------+
double CalculateSL(MqlRates &rates[], bool isBuy, double necklinePrice)
{
   double buffer = SLBufferPoints * _Point;

   if(UseFixedSL)
   {
      double fixedSL = FixedSLPoints * _Point;
      if(isBuy)
         return rates[1].close - fixedSL;
      else
         return rates[1].close + fixedSL;
   }

   if(isBuy)
   {
      //--- シグナル足の安値またはネックラインの下
      double signalLow = rates[1].low;
      double sl = MathMin(signalLow, necklinePrice) - buffer;
      return sl;
   }
   else
   {
      //--- シグナル足の高値またはネックラインの上
      double signalHigh = rates[1].high;
      double sl = MathMax(signalHigh, necklinePrice) + buffer;
      return sl;
   }
}

//+------------------------------------------------------------------+
//| TPの計算                                                         |
//+------------------------------------------------------------------+
double CalculateTP(double entryPrice, double sl, bool isBuy)
{
   double slDistance = MathAbs(entryPrice - sl);
   double tpDistance = slDistance * RiskRewardRatio;

   double tp;
   if(isBuy)
   {
      tp = entryPrice + tpDistance;

      //--- ピボットを目標として使用
      if(UsePivotAsTarget)
      {
         //--- 次のピボットレベルを探す
         double nearestPivot = FindNearestPivotLevel(entryPrice, true);
         if(nearestPivot > entryPrice && nearestPivot < tp)
         {
            //--- ピボットがTP以前にある場合、ピボットをTPとして使用
            tp = nearestPivot;
         }
      }
   }
   else
   {
      tp = entryPrice - tpDistance;

      if(UsePivotAsTarget)
      {
         double nearestPivot = FindNearestPivotLevel(entryPrice, false);
         if(nearestPivot < entryPrice && nearestPivot > tp)
         {
            tp = nearestPivot;
         }
      }
   }

   return tp;
}

//+------------------------------------------------------------------+
//| 最寄りのピボットレベルを検索                                     |
//+------------------------------------------------------------------+
double FindNearestPivotLevel(double price, bool above)
{
   double levels[];
   ArrayResize(levels, 7);
   levels[0] = g_DailyPivot;
   levels[1] = g_DailyR1;
   levels[2] = g_DailyR2;
   levels[3] = g_DailyR3;
   levels[4] = g_DailyS1;
   levels[5] = g_DailyS2;
   levels[6] = g_DailyS3;

   double nearest = 0;
   double minDist = DBL_MAX;

   for(int i = 0; i < 7; i++)
   {
      if(above && levels[i] > price)
      {
         double dist = levels[i] - price;
         if(dist < minDist)
         {
            minDist = dist;
            nearest = levels[i];
         }
      }
      else if(!above && levels[i] < price)
      {
         double dist = price - levels[i];
         if(dist < minDist)
         {
            minDist = dist;
            nearest = levels[i];
         }
      }
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| オープンリスクの確認                                             |
//+------------------------------------------------------------------+
bool CheckOpenRisk()
{
   double totalRisk = 0;
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double positionRisk = CalculatePositionRisk(ticket);
      totalRisk += positionRisk;
   }

   double riskPercent = (totalRisk / accountBalance) * 100.0;

   if(riskPercent >= MaxOpenRisk)
   {
      Print("オープンリスク制限到達: ", DoubleToString(riskPercent, 2), "%");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ポジションリスクの計算                                           |
//+------------------------------------------------------------------+
double CalculatePositionRisk(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   if(sl == 0)
      return 0;

   double pipValue = GetPipValue();
   double pipSize = GetPipSize();
   double slPips = MathAbs(openPrice - sl) / pipSize;

   return slPips * pipValue * volume;
}

//+------------------------------------------------------------------+
//| 既存ポジションの確認                                             |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ロットサイズ計算（リスクベース）                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 残りの許容損失を計算
   double remainingDailyLoss = g_DailyStartEquity * (DailyLossLimit / 100.0) - (g_DailyStartEquity - currentEquity);
   double remainingTotalLoss = g_InitialBalance * (TotalLossLimit / 100.0) - (g_InitialBalance - currentEquity);

   //--- より厳しい方を採用
   double maxAllowedLoss = MathMin(remainingDailyLoss, remainingTotalLoss);

   //--- トレードリスク制限を適用
   double tradeRiskAmount = accountBalance * (MaxRiskPerTrade / 100.0);
   maxAllowedLoss = MathMin(maxAllowedLoss, tradeRiskAmount);

   if(maxAllowedLoss <= 0)
   {
      Print("ロット計算エラー: 許容損失が0以下");
      return 0;
   }

   //--- Pip価値とサイズの取得
   double pipValue = GetPipValue();
   double pipSize = GetPipSize();
   double slPips = slPoints / pipSize;

   //--- SL pipsでの損失額（1ロットあたり）
   double lossPerLot = slPips * pipValue;

   if(lossPerLot <= 0)
   {
      Print("ロット計算エラー: lossPerLot=", lossPerLot);
      return 0;
   }

   double calculatedLots = maxAllowedLoss / lossPerLot;

   //--- ロットサイズの正規化
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   calculatedLots = MathFloor(calculatedLots / lotStep) * lotStep;

   if(calculatedLots < minLot)
      calculatedLots = minLot;
   if(calculatedLots > maxLot)
      calculatedLots = maxLot;

   Print("ロット計算: 許容損失=", DoubleToString(maxAllowedLoss, 0),
         " SL Points=", DoubleToString(slPoints, 1),
         " ロット=", DoubleToString(calculatedLots, 2));

   return calculatedLots;
}

//+------------------------------------------------------------------+
//| Pip サイズの取得                                                 |
//+------------------------------------------------------------------+
double GetPipSize()
{
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
   {
      return 0.1;  // 金の場合は0.1ドル = 1 pip
   }
   else if(StringFind(_Symbol, "JPY") >= 0)
   {
      return 0.01;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(digits == 3 || digits == 5)
      return point * 10.0;

   return point;
}

//+------------------------------------------------------------------+
//| 1pipあたりの価値を取得                                           |
//+------------------------------------------------------------------+
double GetPipValue()
{
   string symbol = _Symbol;
   string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   double pipSize = GetPipSize();
   double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if((StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) && accountCurrency == "JPY")
   {
      double usdJpyRate = GetUSDJPYRate();
      double pipValueUSD = pipSize * contractSize;
      return pipValueUSD * usdJpyRate;
   }

   if(StringFind(symbol, "JPY") >= 0 && accountCurrency == "JPY")
   {
      return pipSize * contractSize;
   }

   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double ticksPerPip = pipSize / tickSize;
   double pipValue = ticksPerPip * tickValue;

   if(accountCurrency == "JPY" && pipValue < 100)
   {
      double usdJpyRate = GetUSDJPYRate();
      pipValue = pipValue * usdJpyRate;
   }

   return pipValue;
}

//+------------------------------------------------------------------+
//| USDJPYレートを取得                                               |
//+------------------------------------------------------------------+
double GetUSDJPYRate()
{
   double rate = 0;

   if(SymbolInfoDouble("USDJPY", SYMBOL_BID) > 0)
      rate = SymbolInfoDouble("USDJPY", SYMBOL_BID);
   else if(SymbolInfoDouble("USDJPY.raw", SYMBOL_BID) > 0)
      rate = SymbolInfoDouble("USDJPY.raw", SYMBOL_BID);
   else if(SymbolInfoDouble("USDJPYm", SYMBOL_BID) > 0)
      rate = SymbolInfoDouble("USDJPYm", SYMBOL_BID);
   else
      rate = 155.0;

   return rate;
}

//+------------------------------------------------------------------+
//| サポートされるフィリングモードを取得                             |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| トレード実行                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE orderType, double sl, double tp, string comment)
{
   double price;
   if(orderType == ORDER_TYPE_BUY)
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- SL幅（ポイント）からロット計算
   double slPoints = MathAbs(price - sl) / _Point;
   double lots = CalculateLotSize(slPoints * _Point);

   if(lots <= 0)
   {
      Print("ロットサイズ計算エラー: 許容損失不足");
      return false;
   }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 30;
   request.magic = MagicNumber;
   request.comment = comment;
   request.type_filling = GetFillingMode();

   if(!OrderSend(request, result))
   {
      Print("注文エラー: ", result.retcode, " - ", GetRetcodeDescription(result.retcode));
      return false;
   }

   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("注文成功: ", comment,
            " Lots=", DoubleToString(lots, 2),
            " Price=", DoubleToString(price, _Digits),
            " SL=", DoubleToString(sl, _Digits),
            " TP=", DoubleToString(tp, _Digits));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 建値決済の管理                                                   |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   double triggerPoints = BreakevenTrigger * _Point;
   double profitPoints = BreakevenProfit * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPrice;
      double newSL;

      if(posType == POSITION_TYPE_BUY)
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = currentPrice - openPrice;

         if(profit >= triggerPoints)
         {
            newSL = openPrice + profitPoints;
            if(currentSL < newSL)
            {
               ModifyPosition(ticket, newSL, currentTP);
               Print("建値決済設定: Ticket=", ticket, " 新SL=", DoubleToString(newSL, _Digits));
            }
         }
      }
      else
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = openPrice - currentPrice;

         if(profit >= triggerPoints)
         {
            newSL = openPrice - profitPoints;
            if(currentSL > newSL || currentSL == 0)
            {
               ModifyPosition(ticket, newSL, currentTP);
               Print("建値決済設定: Ticket=", ticket, " 新SL=", DoubleToString(newSL, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップの管理                                       |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double startPoints = TrailingStart * _Point;
   double stepPoints = TrailingStep * _Point;
   double distancePoints = TrailingDistance * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPrice;
      double newSL;
      double profit;

      if(posType == POSITION_TYPE_BUY)
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         profit = currentPrice - openPrice;

         //--- トレーリング開始条件を満たしているか
         if(profit >= startPoints)
         {
            //--- 新しいSL = 現在価格 - トレーリング距離
            newSL = currentPrice - distancePoints;

            //--- 現在のSLよりステップ以上高い場合のみ更新
            if(currentSL == 0 || newSL >= currentSL + stepPoints)
            {
               //--- エントリー価格より上にSLを設定
               if(newSL > openPrice)
               {
                  ModifyPosition(ticket, newSL, currentTP);
                  Print("トレーリングストップ更新(BUY): Ticket=", ticket,
                        " 新SL=", DoubleToString(newSL, _Digits),
                        " 含み益=", DoubleToString(profit / _Point, 0), "pts");
               }
            }
         }
      }
      else  // SELL
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         profit = openPrice - currentPrice;

         if(profit >= startPoints)
         {
            newSL = currentPrice + distancePoints;

            if(currentSL == 0 || newSL <= currentSL - stepPoints)
            {
               if(newSL < openPrice)
               {
                  ModifyPosition(ticket, newSL, currentTP);
                  Print("トレーリングストップ更新(SELL): Ticket=", ticket,
                        " 新SL=", DoubleToString(newSL, _Digits),
                        " 含み益=", DoubleToString(profit / _Point, 0), "pts");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ピボットでの利確確認                                             |
//+------------------------------------------------------------------+
void CheckPivotTP()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPrice;
      double tolerance = 10 * _Point;  // ピボット到達判定の許容誤差

      if(posType == POSITION_TYPE_BUY)
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         //--- 価格がピボットレベルに到達したか確認
         if((currentPrice >= g_DailyPivot - tolerance && openPrice < g_DailyPivot) ||
            (currentPrice >= g_DailyR1 - tolerance && openPrice < g_DailyR1) ||
            (currentPrice >= g_DailyR2 - tolerance && openPrice < g_DailyR2))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit > 0)
            {
               ClosePosition(ticket);
               Print("ピボット到達決済(BUY): Ticket=", ticket);
            }
         }
      }
      else
      {
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         if((currentPrice <= g_DailyPivot + tolerance && openPrice > g_DailyPivot) ||
            (currentPrice <= g_DailyS1 + tolerance && openPrice > g_DailyS1) ||
            (currentPrice <= g_DailyS2 + tolerance && openPrice > g_DailyS2))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit > 0)
            {
               ClosePosition(ticket);
               Print("ピボット到達決済(SELL): Ticket=", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 含み損のリアルタイム監視                                         |
//+------------------------------------------------------------------+
void MonitorUnrealizedLoss()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPercent = (g_DailyStartEquity - currentEquity) / g_DailyStartEquity * 100.0;
   double warningThreshold = DailyLossLimit * 0.9;

   if(dailyLossPercent >= warningThreshold && dailyLossPercent < DailyLossLimit)
   {
      Print("警告: 日次損失率が警戒レベルに到達: ", DoubleToString(dailyLossPercent, 2), "%");
      CloseWorstPosition();
   }
}

//+------------------------------------------------------------------+
//| ポジション修正                                                   |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = sl;
   request.tp = tp;

   if(!OrderSend(request, result))
   {
      Print("ポジション修正エラー: ", result.retcode);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ポジション決済                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.deviation = 30;
   request.magic = MagicNumber;
   request.position = ticket;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   if(posType == POSITION_TYPE_BUY)
   {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
   }
   else
   {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
   }

   request.type_filling = GetFillingMode();

   if(!OrderSend(request, result))
   {
      Print("決済エラー: Ticket=", ticket, " Error=", result.retcode);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 全ポジション決済                                                 |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("全ポジション決済開始: ", reason);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ClosePosition(ticket);
   }
}

//+------------------------------------------------------------------+
//| 最も損失が大きいポジションを決済                                 |
//+------------------------------------------------------------------+
void CloseWorstPosition()
{
   double worstProfit = 0;
   ulong worstTicket = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(profit < worstProfit)
      {
         worstProfit = profit;
         worstTicket = ticket;
      }
   }

   if(worstTicket > 0)
   {
      Print("最大損失ポジション決済: Ticket=", worstTicket, " Loss=", DoubleToString(worstProfit, 2));
      ClosePosition(worstTicket);
   }
}

//+------------------------------------------------------------------+
//| リターンコードの説明                                             |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:           return "Requote";
      case TRADE_RETCODE_REJECT:            return "Request rejected";
      case TRADE_RETCODE_CANCEL:            return "Request canceled by trader";
      case TRADE_RETCODE_PLACED:            return "Order placed";
      case TRADE_RETCODE_DONE:              return "Request completed";
      case TRADE_RETCODE_DONE_PARTIAL:      return "Only part of the request was completed";
      case TRADE_RETCODE_ERROR:             return "Request processing error";
      case TRADE_RETCODE_TIMEOUT:           return "Request canceled by timeout";
      case TRADE_RETCODE_INVALID:           return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:    return "Invalid volume in the request";
      case TRADE_RETCODE_INVALID_PRICE:     return "Invalid price in the request";
      case TRADE_RETCODE_INVALID_STOPS:     return "Invalid stops in the request";
      case TRADE_RETCODE_TRADE_DISABLED:    return "Trade is disabled";
      case TRADE_RETCODE_MARKET_CLOSED:     return "Market is closed";
      case TRADE_RETCODE_NO_MONEY:          return "There is not enough money to complete the request";
      case TRADE_RETCODE_PRICE_CHANGED:     return "Prices changed";
      case TRADE_RETCODE_PRICE_OFF:         return "There are no quotes to process the request";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid order expiration date in the request";
      case TRADE_RETCODE_ORDER_CHANGED:     return "Order state changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too frequent requests";
      default:                              return "Unknown error";
   }
}
//+------------------------------------------------------------------+
