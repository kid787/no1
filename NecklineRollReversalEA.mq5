//+------------------------------------------------------------------+
//|                                      NecklineRollReversalEA.mq5 |
//|               XAUUSD専用 ネックライン＋ピボットバウンスEA        |
//|              Fintokeiチャレンジプラン対応 資金管理付き          |
//+------------------------------------------------------------------+
#property copyright "Neckline Roll Reversal EA"
#property link      ""
#property version   "1.04"
#property strict

//+------------------------------------------------------------------+
//| 入力パラメータ                                                   |
//+------------------------------------------------------------------+
input group "===== 基本設定 ====="
input double   InitialBalance       = 0;         // 初期資金（0=自動検出）
input double   DailyLossLimit       = 4.9;       // 1日の最大損失率(%) ※5%未満に設定
input double   TotalLossLimit       = 9.9;       // 全体の最大損失率(%) ※10%未満に設定
input double   MaxRiskPerTrade      = 2.0;       // 1トレードあたりの最大リスク(%)
input double   MaxOpenRisk          = 3.0;       // 同時オープンポジションの最大リスク(%)
input int      MagicNumber          = 20251223;  // マジックナンバー

input group "===== 戦略選択 ====="
input bool     UseNecklineStrategy  = true;      // ネックライン戦略を使用
input bool     UsePivotBounce       = true;      // ピボットバウンス戦略を使用

input group "===== ネックライン設定（緩和版）====="
input int      LookbackBars         = 100;       // ネックライン検出のルックバック期間
input int      SwingStrength        = 3;         // スイングポイント判定の強度（前後のバー数）※緩和
input int      MinTouches           = 1;         // 重要ラインと見なす最小タッチ回数 ※緩和
input double   NecklineTolerance    = 80;        // ネックライン許容誤差（ポイント）※緩和
input double   BreakoutMinBody      = 80;        // ブレイクアウト確認の最小実体サイズ（ポイント）※緩和

input group "===== ブレイクアウト・リターンムーブ設定 ====="
input int      BreakoutConfirmBars  = 2;         // ブレイクアウト確認に必要なバー数 ※緩和
input int      MaxReturnWaitBars    = 50;        // リターンムーブ待機の最大バー数 ※延長
input double   ReturnTolerance      = 50;        // リターンムーブ許容誤差（ポイント）※緩和

input group "===== プライスアクション設定（緩和版）====="
input double   PinBarWickRatio      = 1.5;       // ピンバーのヒゲ/実体比率 ※緩和
input double   PinBarBodyMaxRatio   = 0.4;       // ピンバーの実体/全体比率上限 ※緩和
input double   EngulfingMinRatio    = 1.0;       // 包み足の最小サイズ比率 ※緩和
input bool     RequirePriceAction   = false;     // プライスアクション必須か ※緩和

input group "===== ピボットバウンス設定 ====="
input double   PivotTolerance       = 100;       // ピボットレベル許容誤差（ポイント）
input bool     UsePivotS1R1         = true;      // S1/R1でエントリー
input bool     UsePivotS2R2         = true;      // S2/R2でエントリー
input bool     UseCentralPivot      = true;      // 中央ピボットでエントリー

input group "===== リスク管理設定 ====="
input double   RiskRewardRatio      = 2.0;       // リスク・リワード比率（1:X）
input double   SLBufferPoints       = 15;        // SLバッファ（ポイント）
input bool     UseFixedSL           = true;      // 固定SLを使用 ※推奨ON
input double   FixedSLPoints        = 150;       // 固定SL幅（ポイント）※v1.04縮小
input bool     UseFixedTP           = true;      // 固定TPを使用 ※v1.04追加・推奨ON
input double   FixedTPPoints        = 300;       // 固定TP幅（ポイント）※v1.04追加 R:R=1:2
input double   MaxSLPoints          = 200;       // 最大SL幅（ポイント）※v1.04厳格化
input bool     SkipWideStopTrades   = false;     // SLが広すぎるトレードをスキップ ※OFF
input double   EntryNearNeckline    = 200;       // ネックライン近接エントリー許容範囲（ポイント）※緩和

input group "===== 建値決済設定 ====="
input bool     UseBreakeven         = false;     // 建値決済を使用 ※v1.04デフォルトOFF（TPを狙う）
input double   BreakevenTrigger     = 150;       // 建値決済発動ポイント ※v1.04遅延
input double   BreakevenProfit      = 50;        // 建値決済時の確保ポイント ※v1.04増加

input group "===== トレーリングストップ設定 ====="
input bool     UseTrailingStop      = false;     // トレーリングストップを使用 ※v1.04デフォルトOFF（TPを狙う）
input double   TrailingStart        = 250;       // トレーリング開始ポイント（含み益）※v1.04遅延
input double   TrailingStep         = 50;        // トレーリングステップ（ポイント）※v1.04拡大
input double   TrailingDistance     = 100;       // トレーリング距離（ポイント）※v1.04拡大

input group "===== タイムフレーム・フィルター設定 ====="
input ENUM_TIMEFRAMES  TradingTimeframe = PERIOD_H1;  // 取引タイムフレーム
input int      TradingStartHour     = 0;         // 取引開始時間（サーバー時間）
input int      TradingEndHour       = 24;        // 取引終了時間（サーバー時間）
input bool     TradeOnMonday        = true;      // 月曜日に取引
input bool     TradeOnFriday        = true;      // 金曜日に取引
input int      MaxTradesPerDay      = 3;         // 1日の最大トレード数

//+------------------------------------------------------------------+
//| ネックライン構造体                                               |
//+------------------------------------------------------------------+
struct SNeckline
{
   double   price;
   int      touches;
   bool     isResistance;
   bool     isBroken;
   datetime breakTime;
   int      breakBar;
   bool     waitingRetest;
};

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
double g_InitialBalance;
double g_DailyStartEquity;
datetime g_LastDailyReset;
bool g_TradingBlocked;
datetime g_LastBarTime;
SNeckline g_Necklines[];
int g_NecklineCount;
double g_DailyPivot;
double g_DailyR1, g_DailyR2, g_DailyR3;
double g_DailyS1, g_DailyS2, g_DailyS3;
double g_PreviousHigh, g_PreviousLow, g_PreviousClose;
int g_TodayTradeCount;
datetime g_LastTradeDate;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InitialBalance <= 0)
      g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   else
      g_InitialBalance = InitialBalance;

   g_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_LastDailyReset = 0;
   g_TradingBlocked = false;
   g_LastBarTime = 0;
   g_NecklineCount = 0;
   g_TodayTradeCount = 0;
   g_LastTradeDate = 0;

   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("警告: このEAはXAUUSD用に設計されています。現在のシンボル: ", _Symbol);
   }

   CalculateDailyPivot();

   Print("=== ネックライン＋ピボットバウンスEA v1.04 起動 ===");
   Print("初期資金: ", DoubleToString(g_InitialBalance, 0), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("ネックライン戦略: ", UseNecklineStrategy ? "ON" : "OFF");
   Print("ピボットバウンス戦略: ", UsePivotBounce ? "ON" : "OFF");
   Print("固定SL: ", UseFixedSL ? DoubleToString(FixedSLPoints, 0) + "pt" : "OFF");
   Print("固定TP: ", UseFixedTP ? DoubleToString(FixedTPPoints, 0) + "pt" : "OFF");
   Print("R:R比率: 1:", DoubleToString(FixedTPPoints / FixedSLPoints, 1));
   Print("デイリーピボット: ", DoubleToString(g_DailyPivot, _Digits));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== EA 停止 ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyReset();

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

   if(UseBreakeven)
      ManageBreakeven();

   if(UseTrailingStop)
      ManageTrailingStop();

   MonitorUnrealizedLoss();

   datetime currentBarTime = iTime(_Symbol, TradingTimeframe, 0);
   if(currentBarTime == g_LastBarTime)
      return;

   g_LastBarTime = currentBarTime;

   if(!IsTradeTime())
      return;

   //--- 日付が変わったらピボット再計算とトレードカウントリセット
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(g_LastTradeDate != today)
   {
      CalculateDailyPivot();
      g_TodayTradeCount = 0;
      g_LastTradeDate = today;
   }

   //--- 1日の最大トレード数チェック
   if(g_TodayTradeCount >= MaxTradesPerDay)
      return;

   //--- ネックライン戦略
   if(UseNecklineStrategy)
   {
      DetectNecklines();
      CheckBreakouts();
      CheckReturnMoveAndEntry();
   }

   //--- ピボットバウンス戦略
   if(UsePivotBounce)
   {
      CheckPivotBounceEntry();
   }
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

   double dailyLossPercent = (g_DailyStartEquity - currentEquity) / g_DailyStartEquity * 100.0;
   if(dailyLossPercent >= DailyLossLimit)
   {
      Print("!!! 1日の最大損失率到達: ", DoubleToString(dailyLossPercent, 2), "% !!!");
      return false;
   }

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

   if(dt.day_of_week == 0)
      return false;
   if(dt.day_of_week == 6)
      return false;
   if(dt.day_of_week == 1 && !TradeOnMonday)
      return false;
   if(dt.day_of_week == 5 && !TradeOnFriday)
      return false;

   if(dt.hour < TradingStartHour || dt.hour >= TradingEndHour)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| デイリーピボットの計算                                           |
//+------------------------------------------------------------------+
void CalculateDailyPivot()
{
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

   g_DailyPivot = (g_PreviousHigh + g_PreviousLow + g_PreviousClose) / 3.0;

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
//| ピボットバウンスエントリーの確認                                 |
//+------------------------------------------------------------------+
void CheckPivotBounceEntry()
{
   if(HasOpenPosition())
      return;

   if(!CheckOpenRisk())
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, TradingTimeframe, 0, 3, rates) < 3)
      return;

   double tolerance = PivotTolerance * _Point;
   double close = rates[1].close;
   double low = rates[1].low;
   double high = rates[1].high;
   double prevClose = rates[2].close;

   //--- サポートレベルでの買いシグナル
   double supportLevels[];
   int supportCount = 0;
   ArrayResize(supportLevels, 0);

   if(UseCentralPivot && close > g_DailyPivot)
   {
      ArrayResize(supportLevels, supportCount + 1);
      supportLevels[supportCount++] = g_DailyPivot;
   }
   if(UsePivotS1R1)
   {
      ArrayResize(supportLevels, supportCount + 1);
      supportLevels[supportCount++] = g_DailyS1;
   }
   if(UsePivotS2R2)
   {
      ArrayResize(supportLevels, supportCount + 1);
      supportLevels[supportCount++] = g_DailyS2;
   }

   //--- サポートでの反発チェック（買い）
   for(int i = 0; i < supportCount; i++)
   {
      double level = supportLevels[i];

      //--- 価格がサポートにタッチして反発
      bool touchedSupport = low <= level + tolerance && low >= level - tolerance;
      bool bouncedUp = close > level && close > rates[1].open;  // 陽線で反発

      if(touchedSupport && bouncedUp)
      {
         Print("ピボットサポート反発検出: Level=", DoubleToString(level, _Digits));

         double sl = CalculatePivotSL(rates, true, level);
         if(sl == 0) continue;

         double tp = CalculateTP(close, sl, true);

         if(ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Pivot_Bounce_Buy"))
         {
            g_TodayTradeCount++;
            Print("ピボットバウンス買いエントリー: Level=", DoubleToString(level, _Digits));
            return;
         }
      }
   }

   //--- レジスタンスレベルでの売りシグナル
   double resistanceLevels[];
   int resistanceCount = 0;
   ArrayResize(resistanceLevels, 0);

   if(UseCentralPivot && close < g_DailyPivot)
   {
      ArrayResize(resistanceLevels, resistanceCount + 1);
      resistanceLevels[resistanceCount++] = g_DailyPivot;
   }
   if(UsePivotS1R1)
   {
      ArrayResize(resistanceLevels, resistanceCount + 1);
      resistanceLevels[resistanceCount++] = g_DailyR1;
   }
   if(UsePivotS2R2)
   {
      ArrayResize(resistanceLevels, resistanceCount + 1);
      resistanceLevels[resistanceCount++] = g_DailyR2;
   }

   //--- レジスタンスでの反発チェック（売り）
   for(int i = 0; i < resistanceCount; i++)
   {
      double level = resistanceLevels[i];

      bool touchedResistance = high >= level - tolerance && high <= level + tolerance;
      bool bouncedDown = close < level && close < rates[1].open;  // 陰線で反発

      if(touchedResistance && bouncedDown)
      {
         Print("ピボットレジスタンス反発検出: Level=", DoubleToString(level, _Digits));

         double sl = CalculatePivotSL(rates, false, level);
         if(sl == 0) continue;

         double tp = CalculateTP(close, sl, false);

         if(ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Pivot_Bounce_Sell"))
         {
            g_TodayTradeCount++;
            Print("ピボットバウンス売りエントリー: Level=", DoubleToString(level, _Digits));
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ピボット用SL計算                                                 |
//+------------------------------------------------------------------+
double CalculatePivotSL(MqlRates &rates[], bool isBuy, double pivotLevel)
{
   double buffer = SLBufferPoints * _Point;
   double maxSL = MaxSLPoints * _Point;
   double entryPrice = rates[1].close;

   if(UseFixedSL)
   {
      double fixedSL = FixedSLPoints * _Point;
      if(isBuy)
         return entryPrice - fixedSL;
      else
         return entryPrice + fixedSL;
   }

   double sl;
   double slDistance;

   if(isBuy)
   {
      sl = rates[1].low - buffer;
      slDistance = entryPrice - sl;

      if(slDistance > maxSL)
      {
         if(SkipWideStopTrades)
            return 0;
         sl = entryPrice - maxSL;
      }
   }
   else
   {
      sl = rates[1].high + buffer;
      slDistance = sl - entryPrice;

      if(slDistance > maxSL)
      {
         if(SkipWideStopTrades)
            return 0;
         sl = entryPrice + maxSL;
      }
   }

   return sl;
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

   double swingHighs[];
   double swingLows[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);

   for(int i = SwingStrength; i < LookbackBars - SwingStrength; i++)
   {
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

   ArrayResize(g_Necklines, 0);
   g_NecklineCount = 0;

   double tolerance = NecklineTolerance * _Point;

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

      if(g_Necklines[i].isResistance)
      {
         double body = MathAbs(rates[1].close - rates[1].open);
         bool isBullishBreak = rates[1].close > necklinePrice + tolerance &&
                               rates[1].close > rates[1].open &&
                               body >= minBody;

         if(isBullishBreak)
         {
            g_Necklines[i].isBroken = true;
            g_Necklines[i].breakTime = rates[1].time;
            g_Necklines[i].breakBar = 1;
            g_Necklines[i].waitingRetest = true;
            Print("レジスタンスブレイクアウト検出: ", DoubleToString(necklinePrice, _Digits));
         }
      }
      else
      {
         double body = MathAbs(rates[1].close - rates[1].open);
         bool isBearishBreak = rates[1].close < necklinePrice - tolerance &&
                               rates[1].close < rates[1].open &&
                               body >= minBody;

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
   if(HasOpenPosition())
      return;

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

      int barsSinceBreak = iBarShift(_Symbol, TradingTimeframe, g_Necklines[i].breakTime);
      if(barsSinceBreak > MaxReturnWaitBars)
      {
         g_Necklines[i].waitingRetest = false;
         continue;
      }

      double necklinePrice = g_Necklines[i].price;

      if(g_Necklines[i].isResistance)
      {
         bool isRetesting = rates[1].low <= necklinePrice + returnTol &&
                            rates[1].close >= necklinePrice - returnTol;

         double entryDistance = MathAbs(rates[1].close - necklinePrice);
         double nearNeckline = EntryNearNeckline * _Point;

         if(isRetesting && entryDistance <= nearNeckline)
         {
            //--- プライスアクション確認（オプション）
            bool signalOK = true;
            if(RequirePriceAction)
            {
               int signal = CheckPriceActionSignal(rates, true);
               signalOK = (signal > 0);
            }

            if(signalOK)
            {
               double sl = CalculateSL(rates, true, necklinePrice);

               if(sl == 0)
               {
                  continue;
               }

               double tp = CalculateTP(rates[1].close, sl, true);

               if(ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Neckline_RR_Buy"))
               {
                  g_Necklines[i].waitingRetest = false;
                  g_TodayTradeCount++;
                  Print("ロールリバーサル買いエントリー: Price=", DoubleToString(rates[1].close, _Digits));
               }
            }
         }
      }
      else
      {
         bool isRetesting = rates[1].high >= necklinePrice - returnTol &&
                            rates[1].close <= necklinePrice + returnTol;

         double entryDistance = MathAbs(rates[1].close - necklinePrice);
         double nearNeckline = EntryNearNeckline * _Point;

         if(isRetesting && entryDistance <= nearNeckline)
         {
            bool signalOK = true;
            if(RequirePriceAction)
            {
               int signal = CheckPriceActionSignal(rates, false);
               signalOK = (signal > 0);
            }

            if(signalOK)
            {
               double sl = CalculateSL(rates, false, necklinePrice);

               if(sl == 0)
               {
                  continue;
               }

               double tp = CalculateTP(rates[1].close, sl, false);

               if(ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Neckline_RR_Sell"))
               {
                  g_Necklines[i].waitingRetest = false;
                  g_TodayTradeCount++;
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
   if(IsPinBar(rates, isBuy))
      return 1;

   if(IsEngulfingBar(rates, isBuy))
      return 2;

   if(IsTwoBarReversal(rates, isBuy))
      return 3;

   return 0;
}

//+------------------------------------------------------------------+
//| ピンバーの判定（緩和版）                                         |
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
      double wickRatio = (body > 0) ? lowerWick / body : 0;
      if(lowerWick > upperWick * PinBarWickRatio &&
         bodyRatio <= PinBarBodyMaxRatio &&
         wickRatio >= PinBarWickRatio)
      {
         return true;
      }
   }
   else
   {
      double wickRatio = (body > 0) ? upperWick / body : 0;
      if(upperWick > lowerWick * PinBarWickRatio &&
         bodyRatio <= PinBarBodyMaxRatio &&
         wickRatio >= PinBarWickRatio)
      {
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| 包み足の判定（緩和版）                                           |
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
      bool prevBearish = prevClose < prevOpen;
      bool currBullish = currClose > currOpen;
      bool engulfs = currOpen <= prevClose && currClose >= prevOpen;
      bool sizeOK = currBody >= prevBody * EngulfingMinRatio;

      if(prevBearish && currBullish && engulfs && sizeOK)
      {
         return true;
      }
   }
   else
   {
      bool prevBullish = prevClose > prevOpen;
      bool currBearish = currClose < currOpen;
      bool engulfs = currOpen >= prevClose && currClose <= prevOpen;
      bool sizeOK = currBody >= prevBody * EngulfingMinRatio;

      if(prevBullish && currBearish && engulfs && sizeOK)
      {
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
      double combinedLow = MathMin(low1, low2);
      double combinedHigh = MathMax(high1, high2);
      double lowerWick = MathMin(open2, close1) - combinedLow;
      double totalRange = combinedHigh - combinedLow;

      if(totalRange == 0)
         return false;

      bool pattern = close2 < open2 && close1 > open1 && close1 > open2;
      double wickRatio = lowerWick / totalRange;

      if(pattern && wickRatio >= 0.4)
      {
         return true;
      }
   }
   else
   {
      double combinedLow = MathMin(low1, low2);
      double combinedHigh = MathMax(high1, high2);
      double upperWick = combinedHigh - MathMax(open2, close1);
      double totalRange = combinedHigh - combinedLow;

      if(totalRange == 0)
         return false;

      bool pattern = close2 > open2 && close1 < open1 && close1 < open2;
      double wickRatio = upperWick / totalRange;

      if(pattern && wickRatio >= 0.4)
      {
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
   double maxSL = MaxSLPoints * _Point;
   double entryPrice = rates[1].close;

   if(UseFixedSL)
   {
      double fixedSL = FixedSLPoints * _Point;
      if(isBuy)
         return entryPrice - fixedSL;
      else
         return entryPrice + fixedSL;
   }

   double sl;
   double slDistance;

   if(isBuy)
   {
      double signalLow = rates[1].low;
      sl = signalLow - buffer;
      slDistance = entryPrice - sl;

      if(slDistance > maxSL)
      {
         if(SkipWideStopTrades)
         {
            return 0;
         }
         else
         {
            sl = entryPrice - maxSL;
         }
      }
   }
   else
   {
      double signalHigh = rates[1].high;
      sl = signalHigh + buffer;
      slDistance = sl - entryPrice;

      if(slDistance > maxSL)
      {
         if(SkipWideStopTrades)
         {
            return 0;
         }
         else
         {
            sl = entryPrice + maxSL;
         }
      }
   }

   return sl;
}

//+------------------------------------------------------------------+
//| TPの計算                                                         |
//+------------------------------------------------------------------+
double CalculateTP(double entryPrice, double sl, bool isBuy)
{
   double tpDistance;

   //--- 固定TPを使用する場合（v1.04追加：R:R比率を保証）
   if(UseFixedTP)
   {
      tpDistance = FixedTPPoints * _Point;
   }
   else
   {
      //--- SLに基づくR:R計算
      double slDistance = MathAbs(entryPrice - sl);
      tpDistance = slDistance * RiskRewardRatio;
   }

   double tp;
   if(isBuy)
   {
      tp = entryPrice + tpDistance;
   }
   else
   {
      tp = entryPrice - tpDistance;
   }

   return tp;
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
//| ロットサイズ計算                                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   double remainingDailyLoss = g_DailyStartEquity * (DailyLossLimit / 100.0) - (g_DailyStartEquity - currentEquity);
   double remainingTotalLoss = g_InitialBalance * (TotalLossLimit / 100.0) - (g_InitialBalance - currentEquity);

   double maxAllowedLoss = MathMin(remainingDailyLoss, remainingTotalLoss);

   double tradeRiskAmount = accountBalance * (MaxRiskPerTrade / 100.0);
   maxAllowedLoss = MathMin(maxAllowedLoss, tradeRiskAmount);

   if(maxAllowedLoss <= 0)
   {
      return 0;
   }

   double pipValue = GetPipValue();
   double pipSize = GetPipSize();
   double slPips = slPoints / pipSize;

   double lossPerLot = slPips * pipValue;

   if(lossPerLot <= 0)
   {
      return 0;
   }

   double calculatedLots = maxAllowedLoss / lossPerLot;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   calculatedLots = MathFloor(calculatedLots / lotStep) * lotStep;

   if(calculatedLots < minLot)
      calculatedLots = minLot;
   if(calculatedLots > maxLot)
      calculatedLots = maxLot;

   return calculatedLots;
}

//+------------------------------------------------------------------+
//| Pip サイズの取得                                                 |
//+------------------------------------------------------------------+
double GetPipSize()
{
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
   {
      return 0.1;
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
//| フィリングモード取得                                             |
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

         if(profit >= startPoints)
         {
            newSL = currentPrice - distancePoints;

            if(currentSL == 0 || newSL >= currentSL + stepPoints)
            {
               if(newSL > openPrice)
               {
                  ModifyPosition(ticket, newSL, currentTP);
               }
            }
         }
      }
      else
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
               }
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
      case TRADE_RETCODE_CANCEL:            return "Request canceled";
      case TRADE_RETCODE_PLACED:            return "Order placed";
      case TRADE_RETCODE_DONE:              return "Request completed";
      case TRADE_RETCODE_DONE_PARTIAL:      return "Partial completion";
      case TRADE_RETCODE_ERROR:             return "Error";
      case TRADE_RETCODE_TIMEOUT:           return "Timeout";
      case TRADE_RETCODE_INVALID:           return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:    return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE:     return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS:     return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED:    return "Trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED:     return "Market closed";
      case TRADE_RETCODE_NO_MONEY:          return "No money";
      case TRADE_RETCODE_PRICE_CHANGED:     return "Price changed";
      case TRADE_RETCODE_PRICE_OFF:         return "No quotes";
      default:                              return "Unknown";
   }
}
//+------------------------------------------------------------------+
