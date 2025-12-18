//+------------------------------------------------------------------+
//|                                                CommonDefines.mqh |
//|                                      XAUUSD Expert - 共通定義     |
//+------------------------------------------------------------------+
#ifndef COMMON_DEFINES_MQH
#define COMMON_DEFINES_MQH

//--- マジックナンバー
#define EA_MAGIC_NUMBER 20241218

//--- シグナル方向
enum ENUM_SIGNAL_DIRECTION {
   SIGNAL_NONE = 0,      // シグナルなし
   SIGNAL_BUY = 1,       // 買いシグナル
   SIGNAL_SELL = -1      // 売りシグナル
};

//--- エントリーロジックタイプ
enum ENUM_ENTRY_LOGIC {
   LOGIC_NONE = 0,
   LOGIC_GRANVILLE = 1,        // グランビルの法則
   LOGIC_HORIZONTAL_LINE = 2,  // 水平線反発
   LOGIC_NECKLINE = 4,         // ネックライン反発
   LOGIC_PRICE_ACTION = 8,     // プライスアクション
   LOGIC_MA_CONFLUENCE = 16    // MA収束
};

//--- 利確ターゲットタイプ
enum ENUM_TP_TARGET {
   TP_RECENT_HIGH_LOW = 0,     // 直近高値安値
   TP_HIGHER_TF_HL = 1,        // 上位足の直近高値安値
   TP_DAILY_PIVOT = 2,         // デイリーPIVOT
   TP_FIBONACCI = 3,           // Fibonacci
   TP_MA20_CROSS = 4           // 20SMAローソク足実体抜け
};

//--- プライスアクションパターン
enum ENUM_PRICE_ACTION {
   PA_NONE = 0,
   PA_PIN_BAR = 1,             // ピンバー
   PA_ENGULFING = 2,           // 包み足
   PA_INSIDE_BAR = 4,          // はらみ足
   PA_TWEEZER = 8,             // 毛抜き
   PA_MORNING_STAR = 16,       // 明けの明星
   PA_EVENING_STAR = 32,       // 宵の明星
   PA_HAMMER = 64,             // ハンマー
   PA_SHOOTING_STAR = 128,     // 流れ星
   PA_DOJI = 256               // 同事線
};

//--- スイングポイント構造体
struct SwingPoint {
   double   price;             // 価格
   datetime time;              // 時間
   int      barIndex;          // バーインデックス
   bool     isHigh;            // 高値かどうか
   bool     isConfirmed;       // 確定したかどうか
};

//--- エントリーシグナル構造体
struct EntrySignal {
   ENUM_SIGNAL_DIRECTION direction;    // エントリー方向
   int      logicFlags;                // 検出されたロジック（ビットフラグ）
   int      logicCount;                // 重なったロジック数
   double   entryPrice;                // エントリー価格
   double   stopLoss;                  // 損切りライン
   double   takeProfit1;               // 利確ライン1
   double   takeProfit2;               // 利確ライン2
   double   takeProfit3;               // 利確ライン3
   double   strength;                  // シグナル強度 (0.0-1.0)
   string   description;               // シグナル説明
};

//--- ポジション情報構造体
struct PositionInfo {
   ulong    ticket;                    // チケット番号
   double   openPrice;                 // オープン価格
   double   currentSL;                 // 現在のSL
   double   currentTP;                 // 現在のTP
   double   lots;                      // ロット数
   double   initialLots;               // 初期ロット数
   int      splitCount;                // 分割回数
   bool     breakEvenApplied;          // 建値決済適用済み
   datetime openTime;                  // オープン時間
   ENUM_POSITION_TYPE type;            // ポジションタイプ
};

//--- Fintokei リスク管理用構造体
struct FintokeiRiskInfo {
   double   initialBalance;            // 初期残高
   double   dailyStartEquity;          // 日次開始時の有効証拠金
   datetime dailyResetTime;            // 日次リセット時間(UTC0:00)
   double   dailyLossLimit;            // 1日の損失限度額(5%)
   double   totalLossLimit;            // 全体の損失限度額(10%)
   double   maxPositionRisk;           // 最大ポジションリスク(3%)
   double   currentDailyLoss;          // 現在の日次損失
   double   currentTotalLoss;          // 現在の全体損失
   bool     tradingAllowed;            // トレード許可フラグ
};

//--- PIVOT構造体
struct DailyPivot {
   double   pivot;                     // ピボットポイント
   double   r1, r2, r3;                // 抵抗線
   double   s1, s2, s3;                // 支持線
   datetime calcDate;                  // 計算日
};

//--- Fibonacci構造体
struct FibonacciLevels {
   double   high;                      // 高値
   double   low;                       // 安値
   double   level236;                  // 23.6%
   double   level382;                  // 38.2%
   double   level500;                  // 50.0%
   double   level618;                  // 61.8%
   double   level786;                  // 78.6%
   double   level1000;                 // 100.0%
   double   level1618;                 // 161.8%
   double   level2618;                 // 261.8%
   bool     isUptrend;                 // 上昇トレンドか
};

//--- ユーティリティ関数
//+------------------------------------------------------------------+
//| Pipサイズを取得                                                   |
//+------------------------------------------------------------------+
double GetPipSize(string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   // XAUUSD/Goldの場合は0.1が1pip
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
   {
      return 0.1;  // Gold: 0.1 = 1 pip (10 points)
   }

   // その他の通貨ペア
   if(digits == 3 || digits == 5)
   {
      return point * 10.0;
   }
   return point;
}

//+------------------------------------------------------------------+
//| 価格をPipsに変換                                                  |
//+------------------------------------------------------------------+
double PriceToPips(double priceDistance, string symbol = NULL)
{
   double pipSize = GetPipSize(symbol);
   if(pipSize == 0) return 0;
   return priceDistance / pipSize;
}

//+------------------------------------------------------------------+
//| Pipsを価格に変換                                                  |
//+------------------------------------------------------------------+
double PipsToPrice(double pips, string symbol = NULL)
{
   return pips * GetPipSize(symbol);
}

//+------------------------------------------------------------------+
//| 1ロットあたりの損失額を計算                                       |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips, string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;

   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize(symbol);

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;

   return numTicks * tickValue;
}

//+------------------------------------------------------------------+
//| ロットサイズを正規化                                              |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots, string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   lots = MathFloor(lots / lotStep) * lotStep;

   if(lots < minLot) lots = minLot;

   return lots;
}

//+------------------------------------------------------------------+
//| 時間がUTC0:00かどうかをチェック                                   |
//+------------------------------------------------------------------+
bool IsNewTradingDay(datetime currentTime, datetime &lastDayTime)
{
   MqlDateTime current, last;
   TimeToStruct(currentTime, current);
   TimeToStruct(lastDayTime, last);

   // UTC 0:00でリセット
   if(current.day != last.day || current.mon != last.mon || current.year != last.year)
   {
      lastDayTime = currentTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 価格が指定したレベル近辺にあるかチェック                          |
//+------------------------------------------------------------------+
bool IsPriceNearLevel(double price, double level, double tolerancePips)
{
   double tolerance = PipsToPrice(tolerancePips);
   return MathAbs(price - level) <= tolerance;
}

//+------------------------------------------------------------------+
//| ログ出力（デバッグ用）                                            |
//+------------------------------------------------------------------+
void LogDebug(string message, bool enabled = true)
{
   if(enabled)
   {
      Print("[XAUUSD_EA] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ", message);
   }
}

//+------------------------------------------------------------------+
//| エントリーシグナル構造体の初期化                                  |
//+------------------------------------------------------------------+
void InitEntrySignal(EntrySignal &signal)
{
   signal.direction = SIGNAL_NONE;
   signal.logicFlags = LOGIC_NONE;
   signal.logicCount = 0;
   signal.entryPrice = 0;
   signal.stopLoss = 0;
   signal.takeProfit1 = 0;
   signal.takeProfit2 = 0;
   signal.takeProfit3 = 0;
   signal.strength = 0;
   signal.description = "";
}

#endif // COMMON_DEFINES_MQH
