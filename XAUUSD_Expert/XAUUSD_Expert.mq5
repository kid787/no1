//+------------------------------------------------------------------+
//|                                               XAUUSD_Expert.mq5  |
//|                              XAUUSD専用EA - Fintokeiチャレンジ対応   |
//|                                                                  |
//|  機能:                                                            |
//|  - グランビルの法則（200SMA/100EMA）                               |
//|  - 水平線・ネックライン反発                                        |
//|  - ローソク足プライスアクション                                    |
//|  - 2つ以上のロジック重複でエントリー                               |
//|  - Fintokei対応資金管理（5%/10%ルール）                            |
//|  - 建値決済・分割利確                                              |
//|  - ダウ理論に基づく損切り                                          |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Expert EA"
#property link      ""
#property version   "1.00"
#property strict

//--- インクルード
#include "Include/CommonDefines.mqh"
#include "Include/RiskManager.mqh"
#include "Include/GranvilleLogic.mqh"
#include "Include/HorizontalLine.mqh"
#include "Include/PriceAction.mqh"
#include "Include/DowTheory.mqh"
#include "Include/PivotFibonacci.mqh"
#include "Include/PositionManager.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| 入力パラメータ                                                    |
//+------------------------------------------------------------------+
input group "=== 基本設定 ==="
input double   InpInitialBalance    = 0;          // 初期残高（0=自動）
input int      InpMinLogicCount     = 2;          // 最小エントリーロジック数

input group "=== リスク管理（Fintokei対応） ==="
input double   InpDailyLossLimit    = 5.0;        // 日次損失限度（%）
input double   InpTotalLossLimit    = 10.0;       // 全体損失限度（%）
input double   InpMaxPositionRisk   = 3.0;        // 最大ポジションリスク（%）
input double   InpDefaultRisk       = 2.0;        // デフォルトリスク（%）
input double   InpSafetyMargin      = 0.5;        // 安全マージン（%）

input group "=== グランビル設定 ==="
input int      InpSMA200Period      = 200;        // 長期SMA期間
input int      InpEMA100Period      = 100;        // 中期EMA期間
input int      InpSMA20Period       = 20;         // 短期SMA期間
input double   InpMATouchPips       = 15.0;       // MA接近許容範囲（pips）

input group "=== 水平線設定 ==="
input int      InpHLLookback        = 200;        // 検索バー数
input int      InpSwingStrength     = 3;          // スイングポイント強度
input double   InpHLMergePips       = 8.0;        // レベル統合許容（pips）
input double   InpHLTouchPips       = 5.0;        // タッチ判定許容（pips）

input group "=== プライスアクション設定 ==="
input double   InpPinBarRatio       = 2.0;        // ピンバーヒゲ比率
input double   InpMinCandlePips     = 8.0;        // 最小ローソク足サイズ（pips）

input group "=== 損切り設定 ==="
input double   InpSLMarginPercent   = 3.0;        // 損切り余裕マージン（%）
input double   InpMinSLPips         = 30.0;       // 最小損切り幅（pips）
input double   InpMaxSLPips         = 100.0;      // 最大損切り幅（pips）

input group "=== 利確設定 ==="
input double   InpMinRR             = 1.5;        // 最小リスクリワード比
input bool     InpUsePivotTP        = true;       // PIVOT利確を使用
input bool     InpUseFibTP          = true;       // Fibonacci利確を使用
input bool     InpUseSwingTP        = true;       // スイングポイント利確を使用

input group "=== ポジション管理 ==="
input double   InpBreakEvenPips     = 30.0;       // 建値移動トリガー（pips）
input double   InpBreakEvenProfit   = 5.0;        // 建値移動後利益確保（pips）
input bool     InpEnablePartialTP   = true;       // 分割利確を有効化
input bool     InpEnableSMAExit     = true;       // 20SMA抜け利確を有効化

input group "=== 取引時間 ==="
input int      InpStartHour         = 8;          // 取引開始時間（時）
input int      InpEndHour           = 21;         // 取引終了時間（時）
input bool     InpAvoidNews         = true;       // 重要指標時間を回避

input group "=== デバッグ ==="
input bool     InpEnableLog         = true;       // ログ出力を有効化

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
// モジュールインスタンス
CRiskManager      *g_riskManager;
CGranvilleLogic   *g_granville;
CHorizontalLine   *g_horizontalLine;
CPriceAction      *g_priceAction;
CDowTheory        *g_dowTheory;
CPivotFibonacci   *g_pivotFibo;
CPositionManager  *g_positionManager;

// 状態管理
datetime          g_lastBarTime = 0;
bool              g_initialized = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // XAUUSD専用チェック
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("This EA is designed for XAUUSD/Gold only!");
      return INIT_FAILED;
   }

   // モジュールの初期化
   g_riskManager = new CRiskManager();
   g_granville = new CGranvilleLogic();
   g_horizontalLine = new CHorizontalLine();
   g_priceAction = new CPriceAction();
   g_dowTheory = new CDowTheory();
   g_pivotFibo = new CPivotFibonacci();
   g_positionManager = new CPositionManager();

   // リスクマネージャー初期化
   if(!g_riskManager.Initialize(InpInitialBalance,
                                 InpDailyLossLimit,
                                 InpTotalLossLimit,
                                 InpMaxPositionRisk,
                                 InpDefaultRisk,
                                 InpSafetyMargin))
   {
      Print("Failed to initialize RiskManager");
      return INIT_FAILED;
   }
   g_riskManager.EnableLog(InpEnableLog);

   // グランビルロジック初期化
   if(!g_granville.Initialize(_Symbol, PERIOD_M5,
                               InpSMA200Period,
                               InpEMA100Period,
                               InpSMA20Period,
                               InpMATouchPips))
   {
      Print("Failed to initialize GranvilleLogic");
      return INIT_FAILED;
   }
   g_granville.EnableLog(InpEnableLog);

   // 水平線検出初期化
   if(!g_horizontalLine.Initialize(_Symbol, PERIOD_M5,
                                    InpHLLookback,
                                    InpSwingStrength,
                                    InpHLMergePips,
                                    InpHLTouchPips))
   {
      Print("Failed to initialize HorizontalLine");
      return INIT_FAILED;
   }
   g_horizontalLine.EnableLog(InpEnableLog);

   // プライスアクション初期化
   if(!g_priceAction.Initialize(_Symbol, PERIOD_M5,
                                 InpPinBarRatio,
                                 1.0,  // engulfing ratio
                                 0.1,  // doji ratio
                                 InpMinCandlePips))
   {
      Print("Failed to initialize PriceAction");
      return INIT_FAILED;
   }
   g_priceAction.EnableLog(InpEnableLog);

   // ダウ理論初期化
   if(!g_dowTheory.Initialize(_Symbol, PERIOD_M5, PERIOD_H1,
                               InpSwingStrength,
                               InpHLLookback,
                               InpSLMarginPercent))
   {
      Print("Failed to initialize DowTheory");
      return INIT_FAILED;
   }
   g_dowTheory.EnableLog(InpEnableLog);

   // PIVOT・Fibonacci初期化
   if(!g_pivotFibo.Initialize(_Symbol, PERIOD_M5, InpHLLookback))
   {
      Print("Failed to initialize PivotFibonacci");
      return INIT_FAILED;
   }
   g_pivotFibo.EnableLog(InpEnableLog);

   // ポジション管理初期化
   if(!g_positionManager.Initialize(_Symbol, EA_MAGIC_NUMBER,
                                     InpBreakEvenPips,
                                     InpBreakEvenProfit))
   {
      Print("Failed to initialize PositionManager");
      return INIT_FAILED;
   }
   g_positionManager.EnableLog(InpEnableLog);
   g_positionManager.EnablePartialTP(InpEnablePartialTP);
   g_positionManager.EnableSMAExit(InpEnableSMAExit);

   g_initialized = true;
   Print("XAUUSD Expert EA initialized successfully");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // モジュールの解放
   if(g_riskManager != NULL) { delete g_riskManager; g_riskManager = NULL; }
   if(g_granville != NULL) { delete g_granville; g_granville = NULL; }
   if(g_horizontalLine != NULL) { delete g_horizontalLine; g_horizontalLine = NULL; }
   if(g_priceAction != NULL) { delete g_priceAction; g_priceAction = NULL; }
   if(g_dowTheory != NULL) { delete g_dowTheory; g_dowTheory = NULL; }
   if(g_pivotFibo != NULL) { delete g_pivotFibo; g_pivotFibo = NULL; }
   if(g_positionManager != NULL) { delete g_positionManager; g_positionManager = NULL; }

   Print("XAUUSD Expert EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized)
      return;

   // リスク管理の監視（毎ティック）
   g_riskManager.OnTick();

   // ポジション管理の監視（毎ティック）
   g_positionManager.OnTick();

   // 新しいバーでのみ処理
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime == g_lastBarTime)
      return;

   g_lastBarTime = currentBarTime;

   // 取引時間チェック
   if(!IsTradingTime())
      return;

   // トレード許可チェック
   if(!g_riskManager.IsTradingAllowed())
   {
      if(InpEnableLog) LogDebug("Trading not allowed by RiskManager");
      return;
   }

   // データ更新
   UpdateAnalysis();

   // 既にポジションがある場合は新規エントリーしない
   if(g_positionManager.HasOpenPosition())
      return;

   // エントリーシグナルをチェック
   EntrySignal signal;
   if(CheckEntrySignal(signal))
   {
      ExecuteEntry(signal);
   }
}

//+------------------------------------------------------------------+
//| 取引時間チェック                                                  |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // 週末チェック
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;

   // 取引時間チェック
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| 分析データを更新                                                  |
//+------------------------------------------------------------------+
void UpdateAnalysis()
{
   g_horizontalLine.Update();
   g_dowTheory.Update();
   g_pivotFibo.Update();
}

//+------------------------------------------------------------------+
//| エントリーシグナルをチェック                                      |
//+------------------------------------------------------------------+
bool CheckEntrySignal(EntrySignal &signal)
{
   InitEntrySignal(signal);

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int logicCount = 0;
   int logicFlags = 0;
   string description = "";

   // === ロジック1: グランビルの法則 ===
   ENUM_SIGNAL_DIRECTION granvilleDir = g_granville.GetSignalDirection();
   if(granvilleDir != SIGNAL_NONE)
   {
      logicCount++;
      logicFlags |= LOGIC_GRANVILLE;
      description += "Granville ";
      signal.direction = granvilleDir;
   }

   // === ロジック2: 水平線・ネックライン反発 ===
   ENUM_SIGNAL_DIRECTION hlDir = g_horizontalLine.GetBounceSignal(currentPrice);
   if(hlDir != SIGNAL_NONE)
   {
      if(signal.direction == SIGNAL_NONE || signal.direction == hlDir)
      {
         logicCount++;
         logicFlags |= LOGIC_HORIZONTAL_LINE;
         description += "HorizontalLine ";
         signal.direction = hlDir;
      }
   }

   // === ロジック3: プライスアクション ===
   ENUM_SIGNAL_DIRECTION paDir = g_priceAction.GetSignalDirection();
   if(paDir != SIGNAL_NONE)
   {
      if(signal.direction == SIGNAL_NONE || signal.direction == paDir)
      {
         logicCount++;
         logicFlags |= LOGIC_PRICE_ACTION;
         description += "PriceAction ";
         signal.direction = paDir;
      }
   }

   // === ロジック4: トレンド方向確認（ダウ理論） ===
   ENUM_DOW_TREND dowTrend = g_dowTheory.GetTrend();
   bool trendConfirmed = false;
   if(signal.direction == SIGNAL_BUY && dowTrend == DOW_TREND_UP)
      trendConfirmed = true;
   if(signal.direction == SIGNAL_SELL && dowTrend == DOW_TREND_DOWN)
      trendConfirmed = true;

   // === ロジック5: 長期MAに引き付けているか ===
   bool nearLongMA = g_granville.IsPriceNearLongMA();
   if(nearLongMA)
   {
      logicFlags |= LOGIC_MA_CONFLUENCE;
      description += "MAConfluence ";
   }

   // 最小ロジック数チェック
   if(logicCount < InpMinLogicCount)
   {
      return false;
   }

   // シグナル方向が確定していない場合
   if(signal.direction == SIGNAL_NONE)
   {
      return false;
   }

   // トレンドと逆行しているシグナルは除外（オプション）
   // if(!trendConfirmed && dowTrend != DOW_TREND_RANGE)
   // {
   //    return false;
   // }

   // エントリー価格を設定
   signal.entryPrice = (signal.direction == SIGNAL_BUY) ?
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                       SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 損切りラインを計算
   signal.stopLoss = CalculateStopLoss(signal.direction, signal.entryPrice);
   if(signal.stopLoss == 0)
   {
      if(InpEnableLog) LogDebug("Failed to calculate stop loss");
      return false;
   }

   // 損切り幅のチェック
   double slPips = MathAbs(PriceToPips(signal.entryPrice - signal.stopLoss, _Symbol));
   if(slPips < InpMinSLPips)
   {
      // エントリーポイントを調整してロットを高くする
      if(signal.direction == SIGNAL_BUY)
         signal.stopLoss = signal.entryPrice - PipsToPrice(InpMinSLPips, _Symbol);
      else
         signal.stopLoss = signal.entryPrice + PipsToPrice(InpMinSLPips, _Symbol);

      slPips = InpMinSLPips;
   }

   if(slPips > InpMaxSLPips)
   {
      if(InpEnableLog) LogDebug(StringFormat("SL too large: %.1f pips (max: %.1f)", slPips, InpMaxSLPips));
      return false;
   }

   // 利確ラインを計算
   CalculateTakeProfits(signal);

   // 最小リスクリワード比チェック
   double tp1Pips = MathAbs(PriceToPips(signal.takeProfit1 - signal.entryPrice, _Symbol));
   double rrRatio = tp1Pips / slPips;
   if(rrRatio < InpMinRR)
   {
      if(InpEnableLog) LogDebug(StringFormat("RR ratio too low: %.2f (min: %.2f)", rrRatio, InpMinRR));
      return false;
   }

   signal.logicFlags = logicFlags;
   signal.logicCount = logicCount;
   signal.description = description;
   signal.strength = g_priceAction.GetSignalStrength() * 0.4 +
                    g_granville.GetSignalStrength() * 0.4 +
                    (trendConfirmed ? 0.2 : 0);

   if(InpEnableLog)
   {
      LogDebug(StringFormat("Entry signal detected: %s, LogicCount=%d, Logics=%s, RR=%.2f",
               (signal.direction == SIGNAL_BUY) ? "BUY" : "SELL",
               logicCount, description, rrRatio));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 損切りラインを計算                                                |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_SIGNAL_DIRECTION direction, double entryPrice)
{
   double sl = 0;

   if(direction == SIGNAL_BUY)
   {
      // ダウ理論に基づく直近安値＋マージン
      sl = g_dowTheory.CalculateBuySL(entryPrice);

      // 水平線のサポートも考慮
      double support = g_horizontalLine.GetNearestSupportBelow(entryPrice);
      if(support > 0 && support < sl)
      {
         // より近いサポートの少し下に設定
         double margin = support * (InpSLMarginPercent / 100.0);
         sl = support - margin;
      }
   }
   else // SELL
   {
      sl = g_dowTheory.CalculateSellSL(entryPrice);

      // 水平線のレジスタンスも考慮
      double resistance = g_horizontalLine.GetNearestResistanceAbove(entryPrice);
      if(resistance > 0 && resistance > sl)
      {
         double margin = resistance * (InpSLMarginPercent / 100.0);
         sl = resistance + margin;
      }
   }

   return sl;
}

//+------------------------------------------------------------------+
//| 利確ラインを計算                                                  |
//+------------------------------------------------------------------+
void CalculateTakeProfits(EntrySignal &signal)
{
   double tp1 = 0, tp2 = 0, tp3 = 0;
   double entryPrice = signal.entryPrice;
   ENUM_SIGNAL_DIRECTION dir = signal.direction;

   // === TP1: 直近スイングポイント ===
   if(InpUseSwingTP)
   {
      if(dir == SIGNAL_BUY)
         tp1 = g_dowTheory.GetNextResistance(entryPrice);
      else
         tp1 = g_dowTheory.GetNextSupport(entryPrice);
   }

   // === TP2: PIVOT ===
   if(InpUsePivotTP)
   {
      double pivotTP = g_pivotFibo.GetNearestPivotTP(entryPrice, dir);
      if(pivotTP > 0)
      {
         if(tp1 == 0 || (dir == SIGNAL_BUY && pivotTP < tp1) || (dir == SIGNAL_SELL && pivotTP > tp1))
            tp2 = pivotTP;
         else
            tp2 = tp1;
         if(tp1 == 0) tp1 = pivotTP;
      }
   }

   // === TP3: Fibonacci ===
   if(InpUseFibTP)
   {
      double fibTP = g_pivotFibo.GetNearestFibTP(entryPrice, dir);
      if(fibTP > 0)
      {
         tp3 = fibTP;
         if(tp1 == 0) tp1 = fibTP;
         if(tp2 == 0) tp2 = fibTP;
      }
   }

   // === 上位足のスイングポイント ===
   if(dir == SIGNAL_BUY)
   {
      double htfRes = g_dowTheory.GetHTFResistance(entryPrice);
      if(htfRes > 0 && (tp2 == 0 || htfRes > tp2))
         tp2 = htfRes;
   }
   else
   {
      double htfSup = g_dowTheory.GetHTFSupport(entryPrice);
      if(htfSup > 0 && (tp2 == 0 || htfSup < tp2))
         tp2 = htfSup;
   }

   // フォールバック：SL距離のRR倍
   double slDistance = MathAbs(entryPrice - signal.stopLoss);
   if(tp1 == 0)
   {
      if(dir == SIGNAL_BUY)
         tp1 = entryPrice + slDistance * InpMinRR;
      else
         tp1 = entryPrice - slDistance * InpMinRR;
   }
   if(tp2 == 0)
   {
      if(dir == SIGNAL_BUY)
         tp2 = entryPrice + slDistance * 2.0;
      else
         tp2 = entryPrice - slDistance * 2.0;
   }
   if(tp3 == 0)
   {
      if(dir == SIGNAL_BUY)
         tp3 = entryPrice + slDistance * 3.0;
      else
         tp3 = entryPrice - slDistance * 3.0;
   }

   signal.takeProfit1 = tp1;
   signal.takeProfit2 = tp2;
   signal.takeProfit3 = tp3;
}

//+------------------------------------------------------------------+
//| エントリーを実行                                                  |
//+------------------------------------------------------------------+
void ExecuteEntry(EntrySignal &signal)
{
   // ロットサイズを計算
   double slPips = MathAbs(PriceToPips(signal.entryPrice - signal.stopLoss, _Symbol));
   double lots = g_riskManager.CalculateOptimalLot(slPips, InpDefaultRisk);

   // 最大許容ロットをチェック
   double maxLots = g_riskManager.CalculateMaxAllowableLot(slPips);
   if(lots > maxLots)
      lots = maxLots;

   if(lots <= 0)
   {
      if(InpEnableLog) LogDebug("Calculated lot size is 0 or negative");
      return;
   }

   // リスクチェック
   if(!g_riskManager.CanOpenPosition(lots, slPips))
   {
      if(InpEnableLog) LogDebug("RiskManager rejected the position");
      return;
   }

   // オーダータイプ
   ENUM_ORDER_TYPE orderType = (signal.direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   // コメント作成
   string comment = StringFormat("XAUEA_%d_%s", signal.logicCount, signal.description);

   // TP1を使用（分割利確の場合は最終TPを設定）
   double tp = signal.takeProfit1;
   if(InpEnablePartialTP)
   {
      // 分割利確有効時は遠いTPを設定
      tp = signal.takeProfit2;
   }

   // ポジションをオープン
   if(g_positionManager.OpenPosition(orderType, lots, signal.stopLoss, tp, comment))
   {
      if(InpEnableLog)
      {
         LogDebug(StringFormat("Position opened: %s, Lots=%.2f, Entry=%.5f, SL=%.5f, TP=%.5f, SLPips=%.1f",
                  (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
                  lots, signal.entryPrice, signal.stopLoss, tp, slPips));
         g_riskManager.PrintRiskStatus();
      }
   }
}

//+------------------------------------------------------------------+
//| チャートイベント処理                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // 必要に応じてチャートイベントを処理
}

//+------------------------------------------------------------------+
//| タイマー処理                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 必要に応じてタイマー処理を追加
}
//+------------------------------------------------------------------+
