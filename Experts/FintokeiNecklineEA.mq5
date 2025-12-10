//+------------------------------------------------------------------+
//|                                           FintokeiNecklineEA.mq5 |
//|          Fintokei Challenge + Neckline Breakout Retest Strategy  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Neckline EA"
#property link      ""
#property version   "1.00"
#property description "Fintokeiチャレンジプラン対応 ネックラインブレイク戦略EA"
#property description "Wトップ/Mボトムのネックライン割れ後の戻り売り/押し目買い"

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
input int      Magic_Number         = 202514;      // マジックナンバー
input string   EA_Comment           = "FintokeiNeckline"; // EAコメント
input int      Slippage_Points      = 30;          // スリッページ許容値

//+------------------------------------------------------------------+
//| 外部パラメータ - パターン検出設定                                   |
//+------------------------------------------------------------------+
input group "=== パターン検出設定 ==="
input ENUM_TIMEFRAMES PatternTimeFrame = PERIOD_H1;   // パターン検出時間足
input int      SwingLookback        = 20;          // スイングポイント検出期間
input double   Pattern_Min_Height_Pips = 50.0;     // パターン最小高さ（Pips）※XAUUSD=$5.0
input double   DoubleTop_Tolerance_Pips = 30.0;    // ダブルトップ許容差（Pips）※XAUUSD=$3.0
input int      Min_Bars_Between_Peaks = 5;         // ピーク間の最小バー数

//+------------------------------------------------------------------+
//| 外部パラメータ - ネックライン設定                                   |
//+------------------------------------------------------------------+
input group "=== ネックライン設定 ==="
input double   NL_Break_Confirm_Pips = 10.0;       // NLブレイク確定（Pips）※XAUUSD=$1.0
input double   NL_Retest_Zone_Pips  = 30.0;        // NLリテストゾーン（Pips）※XAUUSD=$3.0
input int      Max_Bars_After_Break = 30;          // ブレイク後の最大待機バー数

//+------------------------------------------------------------------+
//| 外部パラメータ - エントリー設定                                     |
//+------------------------------------------------------------------+
input group "=== エントリー設定 ==="
input bool     Require_Rejection_Pattern = false;  // 反発パターン必須
input double   MinRiskReward        = 2.0;         // 最小リスクリワード比率
input double   SL_Buffer_Pips       = 20.0;        // SLバッファ（Pips）※XAUUSD=$2.0

//+------------------------------------------------------------------+
//| 外部パラメータ - ポジション管理                                     |
//+------------------------------------------------------------------+
input group "=== ポジション管理 ==="
input bool     BreakEven_Enable          = true;   // ブレイクイーブン有効
input double   BreakEven_Trigger_Percent = 50.0;   // トリガー（TP距離の%）
input int      BreakEven_Offset_Pips     = 20;     // オフセット（Pips）※XAUUSD=$2.0
input int      Max_Positions             = 1;      // 最大同時ポジション数

//+------------------------------------------------------------------+
//| 外部パラメータ - 時間フィルター                                     |
//+------------------------------------------------------------------+
input group "=== 時間フィルター ==="
input bool     TimeFilter_Enable    = true;        // 時間帯フィルター有効
input int      Trade_Start_Hour     = 8;           // 取引開始時刻（サーバー時間）
input int      Trade_End_Hour       = 22;          // 取引終了時刻（サーバー時間）

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
//| パターン状態の列挙型                                               |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_STATE
{
   STATE_SEARCHING,        // パターン検索中
   STATE_PATTERN_FOUND,    // パターン検出（NLブレイク待ち）
   STATE_NL_BROKEN,        // NLブレイク済み（リテスト待ち）
   STATE_RETEST_ZONE,      // リテストゾーン内
   STATE_ENTRY_READY       // エントリー準備完了
};

//+------------------------------------------------------------------+
//| パターン方向の列挙型                                               |
//+------------------------------------------------------------------+
enum ENUM_PATTERN_TYPE
{
   PATTERN_NONE,           // パターンなし
   PATTERN_DOUBLE_TOP,     // ダブルトップ（売りシグナル）
   PATTERN_DOUBLE_BOTTOM   // ダブルボトム（買いシグナル）
};

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
CTrade trade;

// パターン検出用変数
ENUM_PATTERN_STATE patternState = STATE_SEARCHING;
ENUM_PATTERN_TYPE patternType = PATTERN_NONE;

// パターンの主要レート
double highA = 0;          // 最初の高値（ダブルトップ）
double lowA = 0;           // 最初の安値（ダブルボトム）
double highC = 0;          // 2番目の高値（切り下げ）
double lowC = 0;           // 2番目の安値（切り上げ）
double neckline = 0;       // ネックライン
double highD = 0;          // リテスト高値（エントリーポイント）
double lowD = 0;           // リテスト安値（エントリーポイント）

// ブレイク検出用
datetime nlBreakTime = 0;  // NLブレイク時刻
int barsAfterBreak = 0;    // ブレイク後のバー数

// バー管理
datetime lastBarTime = 0;

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
string objPrefix = "FNE_";

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

   // Fintokeiリスク管理の初期化
   InitializeFintokeiRiskManagement();

   // パターン状態の初期化
   ResetPatternState();

   // 表示更新
   UpdateDisplay();

   Print("=== FintokeiNecklineEA 初期化完了 ===");
   Print("取引銘柄: ", Symbol_to_Trade);
   Print("パターン検出時間足: ", EnumToString(PatternTimeFrame));
   Print("初期残高: ", DoubleToString(InitialBalance, 2));
   Print("Pip値: ", DoubleToString(pipValue, 5));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // オブジェクトの削除
   ObjectsDeleteAll(0, objPrefix);
   ChartRedraw();

   Print("FintokeiNecklineEA が終了しました");
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

   // 新しいバーの確認
   datetime currentBarTime = iTime(Symbol_to_Trade, PatternTimeFrame, 0);
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

   // メインロジック：パターン状態マシン
   ProcessPatternStateMachine();

   // 表示更新
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| パターン状態マシンの処理                                          |
//+------------------------------------------------------------------+
void ProcessPatternStateMachine()
{
   switch(patternState)
   {
      case STATE_SEARCHING:
         // パターンを検索
         SearchForPattern();
         break;

      case STATE_PATTERN_FOUND:
         // NLブレイクを監視
         MonitorNecklineBreak();
         break;

      case STATE_NL_BROKEN:
         // リテストを待機
         WaitForRetest();
         break;

      case STATE_RETEST_ZONE:
         // エントリーシグナルを確認
         CheckEntrySignal();
         break;

      case STATE_ENTRY_READY:
         // エントリー実行
         ExecuteEntry();
         break;
   }
}

//+------------------------------------------------------------------+
//| パターン検索                                                      |
//+------------------------------------------------------------------+
void SearchForPattern()
{
   // スイングハイ・スイングローを検出
   double swingHighs[], swingLows[];
   int swingHighBars[], swingLowBars[];

   DetectSwingPoints(swingHighs, swingHighBars, swingLows, swingLowBars);

   // ダブルトップの検出
   if(DetectDoubleTop(swingHighs, swingHighBars, swingLows, swingLowBars))
   {
      patternType = PATTERN_DOUBLE_TOP;
      patternState = STATE_PATTERN_FOUND;
      Print("=== ダブルトップ検出 ===");
      Print("高値A: ", DoubleToString(highA, 2));
      Print("高値C: ", DoubleToString(highC, 2));
      Print("ネックライン: ", DoubleToString(neckline, 2));
      return;
   }

   // ダブルボトムの検出
   if(DetectDoubleBottom(swingHighs, swingHighBars, swingLows, swingLowBars))
   {
      patternType = PATTERN_DOUBLE_BOTTOM;
      patternState = STATE_PATTERN_FOUND;
      Print("=== ダブルボトム検出 ===");
      Print("安値A: ", DoubleToString(lowA, 2));
      Print("安値C: ", DoubleToString(lowC, 2));
      Print("ネックライン: ", DoubleToString(neckline, 2));
      return;
   }
}

//+------------------------------------------------------------------+
//| スイングポイントの検出                                            |
//+------------------------------------------------------------------+
void DetectSwingPoints(double &swingHighs[], int &swingHighBars[],
                       double &swingLows[], int &swingLowBars[])
{
   ArrayResize(swingHighs, 0);
   ArrayResize(swingHighBars, 0);
   ArrayResize(swingLows, 0);
   ArrayResize(swingLowBars, 0);

   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   int barsToCheck = SwingLookback * 5;  // 十分なバー数を確保

   if(CopyHigh(Symbol_to_Trade, PatternTimeFrame, 1, barsToCheck, highs) < barsToCheck)
      return;
   if(CopyLow(Symbol_to_Trade, PatternTimeFrame, 1, barsToCheck, lows) < barsToCheck)
      return;

   // スイングハイの検出（前後のバーより高い）
   for(int i = SwingLookback; i < barsToCheck - SwingLookback; i++)
   {
      bool isSwingHigh = true;
      for(int j = 1; j <= SwingLookback; j++)
      {
         if(highs[i] <= highs[i-j] || highs[i] <= highs[i+j])
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         int size = ArraySize(swingHighs);
         ArrayResize(swingHighs, size + 1);
         ArrayResize(swingHighBars, size + 1);
         swingHighs[size] = highs[i];
         swingHighBars[size] = i + 1;  // バーインデックス（1から開始）
      }
   }

   // スイングローの検出（前後のバーより低い）
   for(int i = SwingLookback; i < barsToCheck - SwingLookback; i++)
   {
      bool isSwingLow = true;
      for(int j = 1; j <= SwingLookback; j++)
      {
         if(lows[i] >= lows[i-j] || lows[i] >= lows[i+j])
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow)
      {
         int size = ArraySize(swingLows);
         ArrayResize(swingLows, size + 1);
         ArrayResize(swingLowBars, size + 1);
         swingLows[size] = lows[i];
         swingLowBars[size] = i + 1;
      }
   }
}

//+------------------------------------------------------------------+
//| ダブルトップの検出                                                |
//+------------------------------------------------------------------+
bool DetectDoubleTop(double &swingHighs[], int &swingHighBars[],
                     double &swingLows[], int &swingLowBars[])
{
   int highCount = ArraySize(swingHighs);
   int lowCount = ArraySize(swingLows);

   if(highCount < 2 || lowCount < 1)
      return false;

   // 直近の2つの高値と間の安値を探す
   for(int i = 0; i < highCount - 1; i++)
   {
      double peak1 = swingHighs[i];      // 直近の高値（高値C）
      int peak1Bar = swingHighBars[i];

      for(int j = i + 1; j < highCount; j++)
      {
         double peak2 = swingHighs[j];   // 前の高値（高値A）
         int peak2Bar = swingHighBars[j];

         // ピーク間の最小バー数チェック
         if(peak2Bar - peak1Bar < Min_Bars_Between_Peaks)
            continue;

         // 高値Cが高値Aより低い（切り下げ）または同程度
         double tolerance = DoubleTop_Tolerance_Pips * pipValue;
         if(peak1 > peak2 + tolerance)
            continue;

         // パターンの高さチェック
         double patternHeight = (peak2 - GetLowestLowBetween(peak1Bar, peak2Bar)) / pipValue;
         if(patternHeight < Pattern_Min_Height_Pips)
            continue;

         // 間の安値（ネックライン）を探す
         for(int k = 0; k < lowCount; k++)
         {
            int lowBar = swingLowBars[k];
            if(lowBar > peak1Bar && lowBar < peak2Bar)
            {
               // ダブルトップ検出
               highA = peak2;
               highC = peak1;
               neckline = swingLows[k];
               return true;
            }
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| ダブルボトムの検出                                                |
//+------------------------------------------------------------------+
bool DetectDoubleBottom(double &swingHighs[], int &swingHighBars[],
                        double &swingLows[], int &swingLowBars[])
{
   int highCount = ArraySize(swingHighs);
   int lowCount = ArraySize(swingLows);

   if(lowCount < 2 || highCount < 1)
      return false;

   // 直近の2つの安値と間の高値を探す
   for(int i = 0; i < lowCount - 1; i++)
   {
      double valley1 = swingLows[i];      // 直近の安値（安値C）
      int valley1Bar = swingLowBars[i];

      for(int j = i + 1; j < lowCount; j++)
      {
         double valley2 = swingLows[j];   // 前の安値（安値A）
         int valley2Bar = swingLowBars[j];

         // バレー間の最小バー数チェック
         if(valley2Bar - valley1Bar < Min_Bars_Between_Peaks)
            continue;

         // 安値Cが安値Aより高い（切り上げ）または同程度
         double tolerance = DoubleTop_Tolerance_Pips * pipValue;
         if(valley1 < valley2 - tolerance)
            continue;

         // パターンの高さチェック
         double patternHeight = (GetHighestHighBetween(valley1Bar, valley2Bar) - valley2) / pipValue;
         if(patternHeight < Pattern_Min_Height_Pips)
            continue;

         // 間の高値（ネックライン）を探す
         for(int k = 0; k < highCount; k++)
         {
            int highBar = swingHighBars[k];
            if(highBar > valley1Bar && highBar < valley2Bar)
            {
               // ダブルボトム検出
               lowA = valley2;
               lowC = valley1;
               neckline = swingHighs[k];
               return true;
            }
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| 指定バー間の最安値を取得                                          |
//+------------------------------------------------------------------+
double GetLowestLowBetween(int bar1, int bar2)
{
   double lows[];
   ArraySetAsSeries(lows, true);
   int count = bar2 - bar1 + 1;
   if(CopyLow(Symbol_to_Trade, PatternTimeFrame, bar1, count, lows) < count)
      return 0;
   return lows[ArrayMinimum(lows)];
}

//+------------------------------------------------------------------+
//| 指定バー間の最高値を取得                                          |
//+------------------------------------------------------------------+
double GetHighestHighBetween(int bar1, int bar2)
{
   double highs[];
   ArraySetAsSeries(highs, true);
   int count = bar2 - bar1 + 1;
   if(CopyHigh(Symbol_to_Trade, PatternTimeFrame, bar1, count, highs) < count)
      return 0;
   return highs[ArrayMaximum(highs)];
}

//+------------------------------------------------------------------+
//| ネックラインブレイクの監視                                        |
//+------------------------------------------------------------------+
void MonitorNecklineBreak()
{
   double close = iClose(Symbol_to_Trade, PatternTimeFrame, 1);
   double breakLevel;

   if(patternType == PATTERN_DOUBLE_TOP)
   {
      // ネックラインの下抜けを確認
      breakLevel = neckline - NL_Break_Confirm_Pips * pipValue;
      if(close < breakLevel)
      {
         patternState = STATE_NL_BROKEN;
         nlBreakTime = iTime(Symbol_to_Trade, PatternTimeFrame, 1);
         barsAfterBreak = 0;
         Print("ネックラインブレイク確認（下抜け）: ", DoubleToString(close, 2));
      }
   }
   else if(patternType == PATTERN_DOUBLE_BOTTOM)
   {
      // ネックラインの上抜けを確認
      breakLevel = neckline + NL_Break_Confirm_Pips * pipValue;
      if(close > breakLevel)
      {
         patternState = STATE_NL_BROKEN;
         nlBreakTime = iTime(Symbol_to_Trade, PatternTimeFrame, 1);
         barsAfterBreak = 0;
         Print("ネックラインブレイク確認（上抜け）: ", DoubleToString(close, 2));
      }
   }

   // パターンの無効化チェック
   CheckPatternInvalidation();
}

//+------------------------------------------------------------------+
//| リテスト待機                                                      |
//+------------------------------------------------------------------+
void WaitForRetest()
{
   barsAfterBreak++;

   // タイムアウトチェック
   if(barsAfterBreak > Max_Bars_After_Break)
   {
      Print("リテスト待機タイムアウト - パターンリセット");
      ResetPatternState();
      return;
   }

   double close = iClose(Symbol_to_Trade, PatternTimeFrame, 1);
   double high = iHigh(Symbol_to_Trade, PatternTimeFrame, 1);
   double low = iLow(Symbol_to_Trade, PatternTimeFrame, 1);

   if(patternType == PATTERN_DOUBLE_TOP)
   {
      // ネックライン付近への戻りを確認
      double retestZoneUpper = neckline + NL_Retest_Zone_Pips * pipValue;
      double retestZoneLower = neckline - NL_Retest_Zone_Pips * pipValue;

      if(high >= retestZoneLower && high <= retestZoneUpper)
      {
         patternState = STATE_RETEST_ZONE;
         highD = high;
         Print("リテストゾーン到達: High=", DoubleToString(high, 2),
               ", NL=", DoubleToString(neckline, 2));
      }
   }
   else if(patternType == PATTERN_DOUBLE_BOTTOM)
   {
      // ネックライン付近への押しを確認
      double retestZoneUpper = neckline + NL_Retest_Zone_Pips * pipValue;
      double retestZoneLower = neckline - NL_Retest_Zone_Pips * pipValue;

      if(low <= retestZoneUpper && low >= retestZoneLower)
      {
         patternState = STATE_RETEST_ZONE;
         lowD = low;
         Print("リテストゾーン到達: Low=", DoubleToString(low, 2),
               ", NL=", DoubleToString(neckline, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| エントリーシグナルの確認                                          |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   barsAfterBreak++;

   // タイムアウトチェック
   if(barsAfterBreak > Max_Bars_After_Break)
   {
      Print("エントリー待機タイムアウト - パターンリセット");
      ResetPatternState();
      return;
   }

   double close = iClose(Symbol_to_Trade, PatternTimeFrame, 1);
   double open = iOpen(Symbol_to_Trade, PatternTimeFrame, 1);
   double high = iHigh(Symbol_to_Trade, PatternTimeFrame, 1);
   double low = iLow(Symbol_to_Trade, PatternTimeFrame, 1);

   if(patternType == PATTERN_DOUBLE_TOP)
   {
      // 高値Dを更新
      if(high > highD)
         highD = high;

      // 反発パターンの確認（ベアリッシュ）
      bool rejectionPattern = false;

      if(Require_Rejection_Pattern)
      {
         rejectionPattern = IsBearishRejection(open, high, low, close);
      }
      else
      {
         // 単純に下落開始を確認
         rejectionPattern = (close < open && close < neckline);
      }

      if(rejectionPattern)
      {
         patternState = STATE_ENTRY_READY;
         Print("売りシグナル確認: 高値D=", DoubleToString(highD, 2));
      }

      // リテストゾーンを上抜けたらパターン無効
      if(close > neckline + NL_Retest_Zone_Pips * 2 * pipValue)
      {
         Print("リテストゾーン上抜け - パターン無効");
         ResetPatternState();
      }
   }
   else if(patternType == PATTERN_DOUBLE_BOTTOM)
   {
      // 安値Dを更新
      if(low < lowD)
         lowD = low;

      // 反発パターンの確認（ブリッシュ）
      bool rejectionPattern = false;

      if(Require_Rejection_Pattern)
      {
         rejectionPattern = IsBullishRejection(open, high, low, close);
      }
      else
      {
         // 単純に上昇開始を確認
         rejectionPattern = (close > open && close > neckline);
      }

      if(rejectionPattern)
      {
         patternState = STATE_ENTRY_READY;
         Print("買いシグナル確認: 安値D=", DoubleToString(lowD, 2));
      }

      // リテストゾーンを下抜けたらパターン無効
      if(close < neckline - NL_Retest_Zone_Pips * 2 * pipValue)
      {
         Print("リテストゾーン下抜け - パターン無効");
         ResetPatternState();
      }
   }
}

//+------------------------------------------------------------------+
//| ベアリッシュ反発パターンの検出                                    |
//+------------------------------------------------------------------+
bool IsBearishRejection(double open, double high, double low, double close)
{
   double bodySize = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalRange = high - low;

   if(totalRange == 0) return false;

   // ピンバー（上ヒゲが長い陰線）
   if(close < open && upperWick > bodySize * 2 && upperWick > lowerWick * 2)
      return true;

   // 包み足（前の足を確認する必要があるが、簡易版として大陰線）
   if(close < open && bodySize > totalRange * 0.6)
      return true;

   // 単純な陰線で下落開始
   if(close < open && close < neckline)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| ブリッシュ反発パターンの検出                                      |
//+------------------------------------------------------------------+
bool IsBullishRejection(double open, double high, double low, double close)
{
   double bodySize = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalRange = high - low;

   if(totalRange == 0) return false;

   // ピンバー（下ヒゲが長い陽線）
   if(close > open && lowerWick > bodySize * 2 && lowerWick > upperWick * 2)
      return true;

   // 包み足（前の足を確認する必要があるが、簡易版として大陽線）
   if(close > open && bodySize > totalRange * 0.6)
      return true;

   // 単純な陽線で上昇開始
   if(close > open && close > neckline)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| エントリー実行                                                    |
//+------------------------------------------------------------------+
void ExecuteEntry()
{
   if(patternType == PATTERN_DOUBLE_TOP)
   {
      ExecuteShortEntry();
   }
   else if(patternType == PATTERN_DOUBLE_BOTTOM)
   {
      ExecuteLongEntry();
   }

   // パターンリセット
   ResetPatternState();
}

//+------------------------------------------------------------------+
//| ショートエントリーの実行                                          |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
   double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

   // SL: 高値Dの上（またはネックラインの上）
   double sl = highD + SL_Buffer_Pips * pipValue;
   double slDistance = sl - bid;
   double slPips = slDistance / pipValue;

   // TP: ネックラインの下の安値付近（パターン高さ分）
   double patternHeight = highA - neckline;
   double tp = neckline - patternHeight;
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
      Print("=== ショートエントリー成功 ===");
      Print("Entry: ", DoubleToString(bid, digits));
      Print("SL: ", DoubleToString(sl, digits), " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", DoubleToString(tp, digits));
      Print("RR: ", DoubleToString(riskReward, 2));
   }
   else
   {
      Print("ショートエントリー失敗: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| ロングエントリーの実行                                            |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
   double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);

   // SL: 安値Dの下
   double sl = lowD - SL_Buffer_Pips * pipValue;
   double slDistance = ask - sl;
   double slPips = slDistance / pipValue;

   // TP: ネックラインの上の高値付近（パターン高さ分）
   double patternHeight = neckline - lowA;
   double tp = neckline + patternHeight;
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
      Print("=== ロングエントリー成功 ===");
      Print("Entry: ", DoubleToString(ask, digits));
      Print("SL: ", DoubleToString(sl, digits), " (", DoubleToString(slPips, 1), " pips)");
      Print("TP: ", DoubleToString(tp, digits));
      Print("RR: ", DoubleToString(riskReward, 2));
   }
   else
   {
      Print("ロングエントリー失敗: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| パターン無効化のチェック                                          |
//+------------------------------------------------------------------+
void CheckPatternInvalidation()
{
   double close = iClose(Symbol_to_Trade, PatternTimeFrame, 1);

   if(patternType == PATTERN_DOUBLE_TOP)
   {
      // 高値Aを上抜けたらパターン無効
      if(close > highA)
      {
         Print("高値A上抜け - パターン無効");
         ResetPatternState();
      }
   }
   else if(patternType == PATTERN_DOUBLE_BOTTOM)
   {
      // 安値Aを下抜けたらパターン無効
      if(close < lowA)
      {
         Print("安値A下抜け - パターン無効");
         ResetPatternState();
      }
   }
}

//+------------------------------------------------------------------+
//| パターン状態のリセット                                            |
//+------------------------------------------------------------------+
void ResetPatternState()
{
   patternState = STATE_SEARCHING;
   patternType = PATTERN_NONE;
   highA = 0;
   lowA = 0;
   highC = 0;
   lowC = 0;
   neckline = 0;
   highD = 0;
   lowD = 0;
   nlBreakTime = 0;
   barsAfterBreak = 0;
}

//+------------------------------------------------------------------+
//| ロットサイズの計算                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);

   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
   double pipValuePerLot = tickValue * (pipValue / tickSize);

   double lotSize = riskAmount / (slPips * pipValuePerLot);

   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(lotSize, MathMin(maxLot, Max_Lot_Size)));

   return lotSize;
}

//+------------------------------------------------------------------+
//| 自分のポジション数をカウント                                      |
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
//| ブレイクイーブン管理                                              |
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

      double tpDistance = MathAbs(currentTP - openPrice);
      double triggerDistance = tpDistance * (BreakEven_Trigger_Percent / 100.0);

      double beLevel = openPrice + (posType == POSITION_TYPE_BUY ? 1 : -1) * BreakEven_Offset_Pips * pipValue;

      if(posType == POSITION_TYPE_BUY)
      {
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
//| 取引時間帯のチェック                                              |
//+------------------------------------------------------------------+
bool IsTradeTimeAllowed()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;

   if(Trade_Start_Hour < Trade_End_Hour)
   {
      return (currentHour >= Trade_Start_Hour && currentHour < Trade_End_Hour);
   }
   else
   {
      return (currentHour >= Trade_Start_Hour || currentHour < Trade_End_Hour);
   }
}

//+------------------------------------------------------------------+
//| Fintokeiリスク管理の初期化                                        |
//+------------------------------------------------------------------+
void InitializeFintokeiRiskManagement()
{
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                         timeStruct.year, timeStruct.mon, timeStruct.day));

   string gvEquity = "FNE_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
   string gvTradingDays = "FNE_TradingDays";

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
//| 日次リセットのチェック（UTC 0時）                                  |
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
      if(hadTradeToday)
      {
         tradingDaysCount++;
         GlobalVariableSet("FNE_TradingDays", tradingDaysCount);
      }

      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;

      string gvEquity = "FNE_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
      GlobalVariableSet(gvEquity, DailyStartingEquity);

      hadTradeToday = false;

      Print("=== 日次リセット実行 ===");
      Print("新しい日次基準額: ", DoubleToString(DailyStartingEquity, 2));
      Print("累計取引日数: ", tradingDaysCount);
   }
}

//+------------------------------------------------------------------+
//| 新規取引のチェック（取引日数カウント用）                           |
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

   double effectiveDailyLimit = DailyLossLimitPct - SafetyBufferPct;
   double effectiveOverallLimit = OverallLossLimitPct - SafetyBufferPct;

   double overallLossLine = InitialBalance * (1.0 - effectiveOverallLimit / 100.0);
   if(currentEquity <= overallLossLine)
   {
      double lossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
      emergencyReason = StringFormat("全体損失制限に到達 (%.2f%% >= %.2f%%)",
                                     lossPercent, effectiveOverallLimit);
      return false;
   }

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
//| 緊急全決済の実行                                                  |
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

   Alert("FintokeiNecklineEA: 損失制限到達！全ポジション決済完了。新規取引停止中。");
}

//+------------------------------------------------------------------+
//| チャート表示の更新                                                |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   double overallLossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
   double dailyLossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;

   double overallLossLine = InitialBalance * (1.0 - OverallLossLimitPct / 100.0);
   double dailyLossLine = DailyStartingEquity * (1.0 - DailyLossLimitPct / 100.0);

   double overallWarningLine = InitialBalance * (1.0 - (OverallLossLimitPct - SafetyBufferPct) / 100.0);
   double dailyWarningLine = DailyStartingEquity * (1.0 - (DailyLossLimitPct - SafetyBufferPct) / 100.0);

   double overallMargin = currentEquity - overallWarningLine;
   double dailyMargin = currentEquity - dailyWarningLine;

   int yPos = PanelY;
   int yStep = 18;

   // ヘッダー
   if(isEmergencyStop)
   {
      CreateLabel("Header", "FINTOKEI NECKLINE EA - EMERGENCY STOP", PanelX, yPos, DangerColor, 11, true);
   }
   else
   {
      CreateLabel("Header", "FINTOKEI NECKLINE EA", PanelX, yPos, clrGold, 11, true);
   }
   yPos += yStep + 5;

   CreateLabel("Sep1", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   CreateLabel("Balance", StringFormat("Balance: %.0f | Equity: %.0f", currentBalance, currentEquity),
               PanelX, yPos, NormalColor, 10, false);
   yPos += yStep + 5;

   CreateLabel("Sep2", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // パターン状態
   string stateStr = "";
   color stateColor = NormalColor;
   switch(patternState)
   {
      case STATE_SEARCHING:     stateStr = "Searching..."; stateColor = clrGray; break;
      case STATE_PATTERN_FOUND: stateStr = "Pattern Found"; stateColor = clrYellow; break;
      case STATE_NL_BROKEN:     stateStr = "NL Broken - Waiting Retest"; stateColor = clrOrange; break;
      case STATE_RETEST_ZONE:   stateStr = "In Retest Zone"; stateColor = clrAqua; break;
      case STATE_ENTRY_READY:   stateStr = "ENTRY READY"; stateColor = SafeColor; break;
   }
   CreateLabel("PatternState", StringFormat("State: %s", stateStr), PanelX, yPos, stateColor, 10, false);
   yPos += yStep;

   // パターンタイプ
   string typeStr = (patternType == PATTERN_DOUBLE_TOP) ? "Double Top (SELL)" :
                    (patternType == PATTERN_DOUBLE_BOTTOM) ? "Double Bottom (BUY)" : "None";
   color typeColor = (patternType == PATTERN_DOUBLE_TOP) ? DangerColor :
                     (patternType == PATTERN_DOUBLE_BOTTOM) ? SafeColor : clrGray;
   CreateLabel("PatternType", StringFormat("Pattern: %s", typeStr), PanelX, yPos, typeColor, 10, false);
   yPos += yStep;

   // ネックライン
   if(neckline > 0)
   {
      CreateLabel("Neckline", StringFormat("Neckline: %.2f", neckline), PanelX, yPos, clrAqua, 10, false);
      yPos += yStep;
   }

   yPos += 5;
   CreateLabel("Sep3", "----------------------------------------", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 損失情報
   color overallColor = GetStatusColor(overallLossPercent, OverallLossLimitPct, SafetyBufferPct);
   CreateLabel("OverallLoss", StringFormat("Overall: %.2f%% / %.1f%%", overallLossPercent, OverallLossLimitPct),
               PanelX, yPos, overallColor, 10, false);
   yPos += yStep;

   color dailyColor = GetStatusColor(dailyLossPercent, DailyLossLimitPct, SafetyBufferPct);
   CreateLabel("DailyLoss", StringFormat("Daily: %.2f%% / %.1f%%", dailyLossPercent, DailyLossLimitPct),
               PanelX, yPos, dailyColor, 10, false);
   yPos += yStep;

   // 取引日数
   color tradingDaysColor = (tradingDaysCount >= 3) ? SafeColor : WarningColor;
   int todayCount = hadTradeToday ? 1 : 0;
   CreateLabel("TradingDays", StringFormat("Trading Days: %d (Min: 3)",
               tradingDaysCount + todayCount),
               PanelX, yPos, tradingDaysColor, 10, false);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ステータスに応じた色を取得                                        |
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
//| ラベルオブジェクトの作成/更新                                     |
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
