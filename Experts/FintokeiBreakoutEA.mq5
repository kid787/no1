//+------------------------------------------------------------------+
//|                                          FintokeiBreakoutEA.mq5  |
//|          Fintokei Challenge + Authentic Breakout Strategy EA     |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Breakout EA"
#property link      ""
#property version   "1.00"
#property description "Fintokeiチャレンジプラン対応 本物のブレイクアウト戦略EA"
#property description "ブロック形成を確認し、ダマシを排除する高精度ブレイクアウト"

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
input int      Magic_Number         = 202513;      // マジックナンバー
input string   EA_Comment           = "FintokeiBreakout"; // EAコメント
input int      Slippage_Points      = 30;          // スリッページ許容値

//+------------------------------------------------------------------+
//| 外部パラメータ - ブレイクアウト設定                                  |
//+------------------------------------------------------------------+
input group "=== ブレイクアウト設定 ==="
input ENUM_TIMEFRAMES EntryTimeFrame    = PERIOD_M5;   // エントリー時間足
input ENUM_TIMEFRAMES ConfirmTimeFrame  = PERIOD_H1;   // トレンド確認時間足
input int      SR_Lookback_Bars     = 50;          // S/Rライン検出期間（本数）
input double   SR_Touch_Pips        = 5.0;         // S/Rライン近接判定（Pips）
input double   Breakout_Confirm_Pips = 2.0;        // ブレイク確定判定（Pips）

//+------------------------------------------------------------------+
//| 外部パラメータ - ブロック（小競り合い）設定                          |
//+------------------------------------------------------------------+
input group "=== ブロック（小競り合い）設定 ==="
input int      BlockCandleCount     = 8;           // ブロック最大ローソク足本数
input int      BlockCandleMin       = 4;           // ブロック最小ローソク足本数
input double   MaxBlockPips         = 10.0;        // ブロック最大幅（Pips）
input double   MinBlockPips         = 3.0;         // ブロック最小幅（Pips）

//+------------------------------------------------------------------+
//| 外部パラメータ - トレンド確認設定                                    |
//+------------------------------------------------------------------+
input group "=== トレンド確認設定（上位足）==="
input int      FastMA_Period        = 20;          // 短期MA期間
input int      SlowMA_Period        = 50;          // 長期MA期間
input int      MA_Slope_Bars        = 3;           // MA傾き判定期間

//+------------------------------------------------------------------+
//| 外部パラメータ - リスクリワード設定                                  |
//+------------------------------------------------------------------+
input group "=== リスクリワード設定 ==="
input double   TakeProfitPips       = 20.0;        // 目標利確幅（Pips）
input double   MinRiskReward        = 1.5;         // 最小リスクリワード比率
input double   SL_Buffer_Pips       = 2.0;         // SLバッファ（Pips）

//+------------------------------------------------------------------+
//| 外部パラメータ - ダマシ排除設定                                      |
//+------------------------------------------------------------------+
input group "=== ダマシ排除設定 ==="
input bool     FakeBreakout_Filter  = true;        // ダマシフィルター有効
input int      Momentum_Check_Bars  = 3;           // 勢い確認本数
input double   Max_Momentum_Pips    = 15.0;        // 最大許容勢い（Pips）

//+------------------------------------------------------------------+
//| 外部パラメータ - ポジション管理                                     |
//+------------------------------------------------------------------+
input group "=== ポジション管理 ==="
input bool     BreakEven_Enable          = true;   // ブレイクイーブン有効
input double   BreakEven_Trigger_Percent = 50.0;   // トリガー（TP距離の%）
input int      BreakEven_Offset_Pips     = 5;      // オフセット（Pips）
input int      Max_Positions             = 1;      // 最大同時ポジション数

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間フィルター                                     |
//+------------------------------------------------------------------+
input group "=== 時間フィルター ==="
input bool     TimeFilter_Enable    = true;        // 時間帯フィルター有効
input int      Trade_Start_Hour     = 10;          // 取引開始時刻（サーバー時間）
input int      Trade_End_Hour       = 23;          // 取引終了時刻（サーバー時間）

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
int fastMAHandle, slowMAHandle;

// バー管理
datetime lastBarTime = 0;

// S/Rライン
double currentResistance = 0;
double currentSupport = 0;

// ブロック情報
double blockHigh = 0;
double blockLow = 0;
bool blockDetected = false;
int blockType = 0;  // 1=ロング用（レジスタンス下）, -1=ショート用（サポート上）

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
string objPrefix = "FBE_";

// Pips変換用
double pipValue = 0;

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

   // Pip値の計算
   int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      pipValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) * 10;
   else
      pipValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // XAUUSDの場合の特別処理
   if(StringFind(Symbol_to_Trade, "XAU") >= 0 || StringFind(Symbol_to_Trade, "GOLD") >= 0)
   {
      pipValue = 0.1;  // 金は0.1ドル = 1 pip
   }

   // インジケーターハンドルの作成（上位足用）
   fastMAHandle = iMA(Symbol_to_Trade, ConfirmTimeFrame, FastMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   slowMAHandle = iMA(Symbol_to_Trade, ConfirmTimeFrame, SlowMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE)
   {
      Print("インジケーターハンドルの作成に失敗しました");
      return(INIT_FAILED);
   }

   // Fintokeiリスク管理の初期化
   InitializeFintokeiRiskManagement();

   // 表示更新
   UpdateDisplay();

   Print("=== FintokeiBreakoutEA 初期化完了 ===");
   Print("取引銘柄: ", Symbol_to_Trade);
   Print("エントリー時間足: ", EnumToString(EntryTimeFrame));
   Print("トレンド確認時間足: ", EnumToString(ConfirmTimeFrame));
   Print("初期残高: ", DoubleToString(InitialBalance, 2));
   Print("日次損失制限: ", DailyLossLimitPct, "%");
   Print("全体損失制限: ", OverallLossLimitPct, "%");
   Print("1トレードリスク: ", Risk_Percent, "%");
   Print("Pip値: ", DoubleToString(pipValue, 5));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ハンドルの解放
   if(fastMAHandle != INVALID_HANDLE) IndicatorRelease(fastMAHandle);
   if(slowMAHandle != INVALID_HANDLE) IndicatorRelease(slowMAHandle);

   // オブジェクトの削除
   ObjectsDeleteAll(0, objPrefix);
   ChartRedraw();

   Print("FintokeiBreakoutEA が終了しました");
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

   // ブレイクイーブン管理
   if(BreakEven_Enable)
   {
      ManageBreakEven();
   }

   // 新しいバーの確認（エントリー時間足）
   datetime currentBarTime = iTime(Symbol_to_Trade, EntryTimeFrame, 0);
   if(currentBarTime == lastBarTime)
   {
      UpdateDisplay();
      return;
   }
   lastBarTime = currentBarTime;

   // 時間フィルター
   if(TimeFilter_Enable && !IsTradeTimeAllowed())
   {
      UpdateDisplay();
      return;
   }

   // 最大ポジション数チェック
   if(CountMyPositions() >= Max_Positions)
   {
      UpdateDisplay();
      return;
   }

   // トレードシグナルのチェック
   CheckTradeSignal();

   // 表示更新
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| トレードシグナルのチェック                                         |
//+------------------------------------------------------------------+
void CheckTradeSignal()
{
   // 1. 上位足のトレンド確認
   int trendDirection = GetTrendDirection();

   // 2. S/Rラインの検出
   DetectSRLines();

   // 3. ブロック（小競り合い）の検出
   DetectBlock();

   if(!blockDetected)
      return;

   // 4. ブレイクアウトの確認とエントリー
   double currentClose = iClose(Symbol_to_Trade, EntryTimeFrame, 1);  // 確定足
   double currentHigh = iHigh(Symbol_to_Trade, EntryTimeFrame, 1);
   double currentLow = iLow(Symbol_to_Trade, EntryTimeFrame, 1);

   // ロングエントリー条件
   if(blockType == 1 && trendDirection >= 0)  // 上昇トレンドまたはレンジ
   {
      // レジスタンスラインのブレイク確認
      double breakoutLevel = currentResistance + Breakout_Confirm_Pips * pipValue;

      if(currentClose > breakoutLevel)
      {
         // ダマシフィルター
         if(FakeBreakout_Filter && IsFakeBreakout(true))
         {
            Print("ダマシブレイク検出 - ロングエントリー見送り");
            return;
         }

         // エントリー実行
         ExecuteLongEntry();
      }
   }

   // ショートエントリー条件
   if(blockType == -1 && trendDirection <= 0)  // 下降トレンドまたはレンジ
   {
      // サポートラインのブレイク確認
      double breakoutLevel = currentSupport - Breakout_Confirm_Pips * pipValue;

      if(currentClose < breakoutLevel)
      {
         // ダマシフィルター
         if(FakeBreakout_Filter && IsFakeBreakout(false))
         {
            Print("ダマシブレイク検出 - ショートエントリー見送り");
            return;
         }

         // エントリー実行
         ExecuteShortEntry();
      }
   }
}

//+------------------------------------------------------------------+
//| 上位足のトレンド方向を取得                                         |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(fastMAHandle, 0, 0, MA_Slope_Bars + 1, fastMA) < MA_Slope_Bars + 1)
      return 0;
   if(CopyBuffer(slowMAHandle, 0, 0, MA_Slope_Bars + 1, slowMA) < MA_Slope_Bars + 1)
      return 0;

   // MA位置の確認
   bool fastAboveSlow = fastMA[0] > slowMA[0];

   // MA傾きの確認
   bool fastRising = fastMA[0] > fastMA[MA_Slope_Bars];
   bool slowRising = slowMA[0] > slowMA[MA_Slope_Bars];
   bool fastFalling = fastMA[0] < fastMA[MA_Slope_Bars];
   bool slowFalling = slowMA[0] < slowMA[MA_Slope_Bars];

   // 上昇トレンド: 短期MA > 長期MA かつ 両方上向き
   if(fastAboveSlow && fastRising && slowRising)
      return 1;

   // 下降トレンド: 短期MA < 長期MA かつ 両方下向き
   if(!fastAboveSlow && fastFalling && slowFalling)
      return -1;

   // レンジ
   return 0;
}

//+------------------------------------------------------------------+
//| S/Rラインの検出                                                   |
//+------------------------------------------------------------------+
void DetectSRLines()
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   // エントリー時間足のデータを取得
   if(CopyHigh(Symbol_to_Trade, EntryTimeFrame, 1, SR_Lookback_Bars, highs) < SR_Lookback_Bars)
      return;
   if(CopyLow(Symbol_to_Trade, EntryTimeFrame, 1, SR_Lookback_Bars, lows) < SR_Lookback_Bars)
      return;

   // 最高値と最安値を見つける（最も意識されるライン）
   int highestIndex = ArrayMaximum(highs, 0, SR_Lookback_Bars);
   int lowestIndex = ArrayMinimum(lows, 0, SR_Lookback_Bars);

   currentResistance = highs[highestIndex];
   currentSupport = lows[lowestIndex];

   // より精度の高いS/R検出: 複数回タッチされた価格帯を探す
   currentResistance = FindStrongerResistance(highs, currentResistance);
   currentSupport = FindStrongerSupport(lows, currentSupport);
}

//+------------------------------------------------------------------+
//| より強いレジスタンスを検出                                         |
//+------------------------------------------------------------------+
double FindStrongerResistance(double &highs[], double initialResistance)
{
   double tolerance = SR_Touch_Pips * pipValue;
   int touchCount = 0;
   double sumLevel = 0;

   for(int i = 0; i < ArraySize(highs); i++)
   {
      if(MathAbs(highs[i] - initialResistance) <= tolerance)
      {
         touchCount++;
         sumLevel += highs[i];
      }
   }

   // 2回以上タッチされていればその平均を使用
   if(touchCount >= 2)
      return sumLevel / touchCount;

   return initialResistance;
}

//+------------------------------------------------------------------+
//| より強いサポートを検出                                             |
//+------------------------------------------------------------------+
double FindStrongerSupport(double &lows[], double initialSupport)
{
   double tolerance = SR_Touch_Pips * pipValue;
   int touchCount = 0;
   double sumLevel = 0;

   for(int i = 0; i < ArraySize(lows); i++)
   {
      if(MathAbs(lows[i] - initialSupport) <= tolerance)
      {
         touchCount++;
         sumLevel += lows[i];
      }
   }

   // 2回以上タッチされていればその平均を使用
   if(touchCount >= 2)
      return sumLevel / touchCount;

   return initialSupport;
}

//+------------------------------------------------------------------+
//| ブロック（小競り合い）の検出                                        |
//+------------------------------------------------------------------+
void DetectBlock()
{
   blockDetected = false;
   blockType = 0;

   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   // 直近のローソク足データを取得
   if(CopyHigh(Symbol_to_Trade, EntryTimeFrame, 1, BlockCandleCount, highs) < BlockCandleCount)
      return;
   if(CopyLow(Symbol_to_Trade, EntryTimeFrame, 1, BlockCandleCount, lows) < BlockCandleCount)
      return;
   if(CopyClose(Symbol_to_Trade, EntryTimeFrame, 1, BlockCandleCount, closes) < BlockCandleCount)
      return;

   // 様々なブロックサイズで検出を試みる
   for(int blockSize = BlockCandleMin; blockSize <= BlockCandleCount; blockSize++)
   {
      // ブロックの高値・安値を計算
      double bHigh = highs[ArrayMaximum(highs, 0, blockSize)];
      double bLow = lows[ArrayMinimum(lows, 0, blockSize)];
      double blockRange = (bHigh - bLow) / pipValue;

      // ブロック幅のチェック
      if(blockRange < MinBlockPips || blockRange > MaxBlockPips)
         continue;

      // レジスタンス付近のブロック（ロング用）
      double distanceToResistance = (currentResistance - bHigh) / pipValue;
      if(distanceToResistance >= 0 && distanceToResistance <= SR_Touch_Pips)
      {
         blockHigh = bHigh;
         blockLow = bLow;
         blockDetected = true;
         blockType = 1;  // ロング用
         Print("ブロック検出（ロング用）: High=", DoubleToString(blockHigh, 2),
               ", Low=", DoubleToString(blockLow, 2),
               ", Range=", DoubleToString(blockRange, 1), " pips",
               ", Resistance=", DoubleToString(currentResistance, 2));
         return;
      }

      // サポート付近のブロック（ショート用）
      double distanceToSupport = (bLow - currentSupport) / pipValue;
      if(distanceToSupport >= 0 && distanceToSupport <= SR_Touch_Pips)
      {
         blockHigh = bHigh;
         blockLow = bLow;
         blockDetected = true;
         blockType = -1;  // ショート用
         Print("ブロック検出（ショート用）: High=", DoubleToString(blockHigh, 2),
               ", Low=", DoubleToString(blockLow, 2),
               ", Range=", DoubleToString(blockRange, 1), " pips",
               ", Support=", DoubleToString(currentSupport, 2));
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| ダマシブレイクの判定                                               |
//+------------------------------------------------------------------+
bool IsFakeBreakout(bool isLong)
{
   double closes[];
   ArraySetAsSeries(closes, true);

   if(CopyClose(Symbol_to_Trade, EntryTimeFrame, 1, Momentum_Check_Bars + 1, closes) < Momentum_Check_Bars + 1)
      return false;

   // 直近の勢いを計算
   double totalMove = 0;
   for(int i = 0; i < Momentum_Check_Bars; i++)
   {
      if(isLong)
         totalMove += (closes[i] - closes[i + 1]);
      else
         totalMove += (closes[i + 1] - closes[i]);
   }

   double momentumPips = MathAbs(totalMove) / pipValue;

   // 急激な動きはダマシの可能性が高い
   if(momentumPips > Max_Momentum_Pips)
   {
      Print("急激な勢い検出: ", DoubleToString(momentumPips, 1), " pips > ", DoubleToString(Max_Momentum_Pips, 1));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| ロングエントリーの実行                                             |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   // 現在価格の取得
   double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);

   // SLの設定（ブロック安値の下）
   double sl = blockLow - SL_Buffer_Pips * pipValue;
   double slDistance = ask - sl;
   double slPips = slDistance / pipValue;

   // TPの設定
   double tp = ask + TakeProfitPips * pipValue;
   double tpDistance = tp - ask;

   // リスクリワード比率のチェック
   double riskReward = tpDistance / slDistance;
   if(riskReward < MinRiskReward)
   {
      Print("リスクリワード比率不足: ", DoubleToString(riskReward, 2), " < ", DoubleToString(MinRiskReward, 2));
      return;
   }

   // ロットサイズの計算
   double lotSize = CalculateLotSize(slPips);
   if(lotSize <= 0)
   {
      Print("ロットサイズ計算エラー");
      return;
   }

   // 価格の正規化
   int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
   ask = NormalizeDouble(ask, digits);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // 注文実行
   if(trade.Buy(lotSize, Symbol_to_Trade, ask, sl, tp, EA_Comment))
   {
      Print("ロングエントリー成功: Lot=", DoubleToString(lotSize, 2),
            ", Entry=", DoubleToString(ask, digits),
            ", SL=", DoubleToString(sl, digits),
            ", TP=", DoubleToString(tp, digits),
            ", RR=", DoubleToString(riskReward, 2));
   }
   else
   {
      Print("ロングエントリー失敗: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| ショートエントリーの実行                                           |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
   // 現在価格の取得
   double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   // SLの設定（ブロック高値の上）
   double sl = blockHigh + SL_Buffer_Pips * pipValue;
   double slDistance = sl - bid;
   double slPips = slDistance / pipValue;

   // TPの設定
   double tp = bid - TakeProfitPips * pipValue;
   double tpDistance = bid - tp;

   // リスクリワード比率のチェック
   double riskReward = tpDistance / slDistance;
   if(riskReward < MinRiskReward)
   {
      Print("リスクリワード比率不足: ", DoubleToString(riskReward, 2), " < ", DoubleToString(MinRiskReward, 2));
      return;
   }

   // ロットサイズの計算
   double lotSize = CalculateLotSize(slPips);
   if(lotSize <= 0)
   {
      Print("ロットサイズ計算エラー");
      return;
   }

   // 価格の正規化
   int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
   bid = NormalizeDouble(bid, digits);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // 注文実行
   if(trade.Sell(lotSize, Symbol_to_Trade, bid, sl, tp, EA_Comment))
   {
      Print("ショートエントリー成功: Lot=", DoubleToString(lotSize, 2),
            ", Entry=", DoubleToString(bid, digits),
            ", SL=", DoubleToString(sl, digits),
            ", TP=", DoubleToString(tp, digits),
            ", RR=", DoubleToString(riskReward, 2));
   }
   else
   {
      Print("ショートエントリー失敗: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| ロットサイズの計算                                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   // 1ロットあたりの1pipの価値を取得
   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
   double pipValuePerLot = tickValue * (pipValue / tickSize);

   // ロットサイズの計算
   double lotSize = riskAmount / (slPips * pipValuePerLot);

   // ロットサイズの正規化
   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(lotSize, MathMin(maxLot, Max_Lot_Size)));

   return lotSize;
}

//+------------------------------------------------------------------+
//| 自分のポジション数をカウント                                       |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
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
//| ブレイクイーブン管理                                               |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol_to_Trade ||
         PositionGetInteger(POSITION_MAGIC) != Magic_Number)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);

      double currentPrice = (posType == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID) :
                           SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);

      // TP距離の計算
      double tpDistance = MathAbs(currentTP - openPrice);
      double triggerDistance = tpDistance * (BreakEven_Trigger_Percent / 100.0);

      // ブレイクイーブンレベル
      double beLevel = openPrice + (posType == POSITION_TYPE_BUY ? 1 : -1) * BreakEven_Offset_Pips * pipValue;

      if(posType == POSITION_TYPE_BUY)
      {
         // ロングポジション
         if(currentPrice >= openPrice + triggerDistance && currentSL < openPrice)
         {
            int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
            beLevel = NormalizeDouble(beLevel, digits);

            if(trade.PositionModify(ticket, beLevel, currentTP))
            {
               Print("ブレイクイーブン設定: Ticket=", ticket, ", NewSL=", beLevel);
            }
         }
      }
      else
      {
         // ショートポジション
         if(currentPrice <= openPrice - triggerDistance && currentSL > openPrice)
         {
            int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
            beLevel = NormalizeDouble(beLevel, digits);

            if(trade.PositionModify(ticket, beLevel, currentTP))
            {
               Print("ブレイクイーブン設定: Ticket=", ticket, ", NewSL=", beLevel);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 取引時間帯のチェック                                               |
//+------------------------------------------------------------------+
bool IsTradeTimeAllowed()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;

   if(Trade_Start_Hour < Trade_End_Hour)
   {
      // 通常の時間帯（例：10時～23時）
      return (currentHour >= Trade_Start_Hour && currentHour < Trade_End_Hour);
   }
   else
   {
      // 日をまたぐ時間帯（例：22時～5時）
      return (currentHour >= Trade_Start_Hour || currentHour < Trade_End_Hour);
   }
}

//+------------------------------------------------------------------+
//| Fintokeiリスク管理の初期化                                        |
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

   // グローバル変数名
   string gvEquity = "FBE_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
   string gvTradingDays = "FBE_TradingDays";

   // 日次基準額の復元または初期化
   if(GlobalVariableCheck(gvEquity))
   {
      DailyStartingEquity = GlobalVariableGet(gvEquity);
      Print("日次基準額を復元: ", DoubleToString(DailyStartingEquity, 2));
   }
   else
   {
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(gvEquity, DailyStartingEquity);
      Print("日次基準額を新規設定: ", DoubleToString(DailyStartingEquity, 2));
   }

   lastResetDateUTC = todayResetUTC;

   // 取引日数の復元または初期化
   if(GlobalVariableCheck(gvTradingDays))
   {
      tradingDaysCount = (int)GlobalVariableGet(gvTradingDays);
   }
   else
   {
      tradingDaysCount = 0;
      GlobalVariableSet(gvTradingDays, 0);
   }

   lastPositionCount = PositionsTotal();
   Print("取引日数: ", tradingDaysCount);
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
      // 前日の取引があった場合、取引日数をカウント
      if(hadTradeToday)
      {
         tradingDaysCount++;
         GlobalVariableSet("FBE_TradingDays", tradingDaysCount);
      }

      // 新しい日の基準額を設定
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;

      string gvEquity = "FBE_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
      GlobalVariableSet(gvEquity, DailyStartingEquity);

      hadTradeToday = false;

      Print("=== 日次リセット実行 ===");
      Print("新しい日次基準額: ", DoubleToString(DailyStartingEquity, 2));
      Print("累計取引日数: ", tradingDaysCount);
   }
}

//+------------------------------------------------------------------+
//| 新規取引のチェック（取引日数カウント用）                             |
//+------------------------------------------------------------------+
void CheckNewTrade()
{
   int currentPositionCount = PositionsTotal();

   if(currentPositionCount > lastPositionCount)
   {
      if(!hadTradeToday)
      {
         hadTradeToday = true;
         Print("本日の取引を検出。取引日としてカウントされます。");
      }
   }

   lastPositionCount = currentPositionCount;
}

//+------------------------------------------------------------------+
//| Fintokei損失制限のチェック                                        |
//+------------------------------------------------------------------+
bool CheckFintokeiLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 安全バッファを考慮した実効損失制限
   double effectiveDailyLimit = DailyLossLimitPct - SafetyBufferPct;
   double effectiveOverallLimit = OverallLossLimitPct - SafetyBufferPct;

   // 全体の損失率チェック
   double overallLossLine = InitialBalance * (1.0 - effectiveOverallLimit / 100.0);
   if(currentEquity <= overallLossLine)
   {
      double lossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
      emergencyReason = StringFormat("全体損失制限に到達 (%.2f%% >= %.2f%%)",
                                     lossPercent, effectiveOverallLimit);
      return false;
   }

   // 日次の損失率チェック
   double dailyLossLine = DailyStartingEquity * (1.0 - effectiveDailyLimit / 100.0);
   if(currentEquity <= dailyLossLine)
   {
      double lossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;
      emergencyReason = StringFormat("日次損失制限に到達 (%.2f%% >= %.2f%%)",
                                     lossPercent, effectiveDailyLimit);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 緊急全決済の実行                                                   |
//+------------------------------------------------------------------+
void ExecuteEmergencyClose()
{
   Print("!!! 緊急決済を開始します !!!");
   Print("理由: ", emergencyReason);

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
            Print("ポジション決済成功: Ticket=", ticket);
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

   Print("=== 緊急決済完了 ===");
   Print("決済成功: ", closedCount, " ポジション");
   Print(">>> 新規取引を停止しました <<<");

   Alert("FintokeiBreakoutEA: 損失制限到達！全ポジション決済完了。新規取引停止中。");
}

//+------------------------------------------------------------------+
//| チャート表示の更新                                                 |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // 損失率の計算
   double overallLossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
   double dailyLossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;

   // 失格ラインの計算
   double overallLossLine = InitialBalance * (1.0 - OverallLossLimitPct / 100.0);
   double dailyLossLine = DailyStartingEquity * (1.0 - DailyLossLimitPct / 100.0);

   // 安全バッファ適用後のライン
   double overallWarningLine = InitialBalance * (1.0 - (OverallLossLimitPct - SafetyBufferPct) / 100.0);
   double dailyWarningLine = DailyStartingEquity * (1.0 - (DailyLossLimitPct - SafetyBufferPct) / 100.0);

   // 残りマージン
   double overallMargin = currentEquity - overallWarningLine;
   double dailyMargin = currentEquity - dailyWarningLine;

   int yPos = PanelY;
   int yStep = 18;

   // ヘッダー
   if(isEmergencyStop)
   {
      CreateLabel("Header", "FINTOKEI BREAKOUT EA - EMERGENCY STOP", PanelX, yPos, DangerColor, 11, true);
   }
   else
   {
      CreateLabel("Header", "FINTOKEI BREAKOUT EA", PanelX, yPos, clrGold, 11, true);
   }
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep1", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 口座情報
   CreateLabel("Balance", StringFormat("Balance: %.0f | Equity: %.0f", currentBalance, currentEquity),
               PanelX, yPos, NormalColor, 10, false);
   yPos += yStep;

   CreateLabel("InitBal", StringFormat("Initial: %.0f", InitialBalance),
               PanelX, yPos, clrSilver, 9, false);
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep2", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 全体損失
   color overallColor = GetStatusColor(overallLossPercent, OverallLossLimitPct, SafetyBufferPct);
   CreateLabel("OverallTitle", "[Overall Loss]", PanelX, yPos, clrWhite, 10, true);
   yPos += yStep;

   CreateLabel("OverallLoss", StringFormat("Current: %.2f%% / Limit: %.1f%%",
               overallLossPercent, OverallLossLimitPct), PanelX + 10, yPos, overallColor, 10, false);
   yPos += yStep;

   CreateLabel("OverallLine", StringFormat("Fail Line: %.0f | Margin: %.0f",
               overallLossLine, overallMargin), PanelX + 10, yPos, clrSilver, 9, false);
   yPos += yStep + 5;

   // 日次損失
   color dailyColor = GetStatusColor(dailyLossPercent, DailyLossLimitPct, SafetyBufferPct);
   CreateLabel("DailyTitle", "[Daily Loss]", PanelX, yPos, clrWhite, 10, true);
   yPos += yStep;

   CreateLabel("DailyLoss", StringFormat("Current: %.2f%% / Limit: %.1f%%",
               dailyLossPercent, DailyLossLimitPct), PanelX + 10, yPos, dailyColor, 10, false);
   yPos += yStep;

   CreateLabel("DailyBase", StringFormat("Base: %.0f (UTC0)", DailyStartingEquity),
               PanelX + 10, yPos, clrSilver, 9, false);
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep3", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // S/Rライン情報
   CreateLabel("SRTitle", "[S/R Lines]", PanelX, yPos, clrWhite, 10, true);
   yPos += yStep;

   CreateLabel("Resistance", StringFormat("Resistance: %.2f", currentResistance),
               PanelX + 10, yPos, clrAqua, 9, false);
   yPos += yStep;

   CreateLabel("Support", StringFormat("Support: %.2f", currentSupport),
               PanelX + 10, yPos, clrOrange, 9, false);
   yPos += yStep;

   // ブロック情報
   if(blockDetected)
   {
      string blockTypeStr = (blockType == 1) ? "LONG Setup" : "SHORT Setup";
      CreateLabel("Block", StringFormat("Block: %s (%.1f pips)",
                  blockTypeStr, (blockHigh - blockLow) / pipValue),
                  PanelX + 10, yPos, clrYellow, 9, false);
   }
   else
   {
      CreateLabel("Block", "Block: Not Detected", PanelX + 10, yPos, clrGray, 9, false);
   }
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep4", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // トレンド情報
   int trend = GetTrendDirection();
   string trendStr = (trend == 1) ? "UP" : (trend == -1) ? "DOWN" : "RANGE";
   color trendColor = (trend == 1) ? SafeColor : (trend == -1) ? DangerColor : WarningColor;
   CreateLabel("Trend", StringFormat("Trend (%s): %s", EnumToString(ConfirmTimeFrame), trendStr),
               PanelX, yPos, trendColor, 10, false);
   yPos += yStep;

   // 取引日数
   color tradingDaysColor = (tradingDaysCount >= 3) ? SafeColor : WarningColor;
   int todayCount = hadTradeToday ? 1 : 0;
   CreateLabel("TradingDays", StringFormat("Trading Days: %d (Min: 3) %s",
               tradingDaysCount + todayCount,
               (tradingDaysCount + todayCount >= 3) ? "OK" : ""),
               PanelX, yPos, tradingDaysColor, 10, false);
   yPos += yStep + 5;

   // 緊急停止時の追加メッセージ
   if(isEmergencyStop)
   {
      CreateLabel("Sep5", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
      yPos += yStep;

      CreateLabel("EmergencyMsg1", "!! EMERGENCY STOP !!", PanelX, yPos, DangerColor, 12, true);
      yPos += yStep;

      CreateLabel("EmergencyMsg2", emergencyReason, PanelX, yPos, DangerColor, 9, false);
      yPos += yStep;

      CreateLabel("EmergencyMsg3", "All positions closed. Trading halted.", PanelX, yPos, WarningColor, 9, false);
   }

   // 現在時刻（UTC）
   yPos += yStep + 5;
   datetime utcTime = TimeGMT();
   CreateLabel("UTCTime", StringFormat("UTC: %s", TimeToString(utcTime, TIME_DATE | TIME_MINUTES)),
               PanelX, yPos, clrGray, 8, false);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ステータスに応じた色を取得                                         |
//+------------------------------------------------------------------+
color GetStatusColor(double currentLoss, double limit, double buffer)
{
   if(currentLoss >= limit - buffer)
      return DangerColor;
   else if(currentLoss >= limit - buffer - 1.0)
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
