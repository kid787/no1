//+------------------------------------------------------------------+
//|                                                  PriceAction.mqh |
//|                       XAUUSD Expert - プライスアクション検出       |
//+------------------------------------------------------------------+
#ifndef PRICE_ACTION_MQH
#define PRICE_ACTION_MQH

#include "CommonDefines.mqh"

//--- プライスアクション検出結果構造体
struct PriceActionResult {
   ENUM_PRICE_ACTION pattern;        // 検出されたパターン
   ENUM_SIGNAL_DIRECTION direction;  // シグナル方向
   double         strength;          // シグナル強度 (0.0-1.0)
   int            barIndex;          // パターンが検出されたバー
   string         description;       // パターン説明
};

//+------------------------------------------------------------------+
//| プライスアクション検出クラス                                      |
//+------------------------------------------------------------------+
class CPriceAction
{
private:
   // 設定
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   // パターン検出パラメータ
   double         m_pinBarRatio;        // ピンバーのヒゲ/実体比率
   double         m_engulfingMinRatio;  // 包み足の最小比率
   double         m_dojiBodyRatio;      // 同事線の最大実体比率
   double         m_minCandleSize;      // 最小ローソク足サイズ（pips）

   // ログ
   bool           m_enableLog;

   // 内部メソッド
   double         GetCandleBody(const MqlRates &rate);
   double         GetUpperWick(const MqlRates &rate);
   double         GetLowerWick(const MqlRates &rate);
   double         GetCandleRange(const MqlRates &rate);
   bool           IsBullishCandle(const MqlRates &rate);
   bool           IsBearishCandle(const MqlRates &rate);

public:
                  CPriceAction();
                 ~CPriceAction();

   // 初期化
   bool           Initialize(string symbol = NULL,
                             ENUM_TIMEFRAMES timeframe = PERIOD_M5,
                             double pinBarRatio = 2.0,
                             double engulfingRatio = 1.0,
                             double dojiRatio = 0.1,
                             double minCandleSize = 5.0);

   // 個別パターン検出
   bool           IsPinBar(const MqlRates &rates[], int index, ENUM_SIGNAL_DIRECTION &direction);
   bool           IsEngulfing(const MqlRates &rates[], int index, ENUM_SIGNAL_DIRECTION &direction);
   bool           IsInsideBar(const MqlRates &rates[], int index);
   bool           IsTweezer(const MqlRates &rates[], int index, ENUM_SIGNAL_DIRECTION &direction);
   bool           IsMorningStar(const MqlRates &rates[], int index);
   bool           IsEveningStar(const MqlRates &rates[], int index);
   bool           IsHammer(const MqlRates &rates[], int index);
   bool           IsShootingStar(const MqlRates &rates[], int index);
   bool           IsDoji(const MqlRates &rate);

   // 総合検出
   int            DetectPatterns(PriceActionResult &results[], int maxResults = 5);
   ENUM_SIGNAL_DIRECTION GetSignalDirection();
   double         GetSignalStrength();

   // 最新のパターン取得
   bool           GetLatestPattern(PriceActionResult &result);

   // 設定
   void           EnableLog(bool enable) { m_enableLog = enable; }
   void           SetPinBarRatio(double ratio) { m_pinBarRatio = ratio; }
   void           SetMinCandleSize(double pips) { m_minCandleSize = pips; }
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CPriceAction::CPriceAction()
{
   m_symbol = "";
   m_timeframe = PERIOD_M5;
   m_pinBarRatio = 2.0;
   m_engulfingMinRatio = 1.0;
   m_dojiBodyRatio = 0.1;
   m_minCandleSize = 5.0;
   m_enableLog = true;
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CPriceAction::~CPriceAction()
{
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CPriceAction::Initialize(string symbol,
                               ENUM_TIMEFRAMES timeframe,
                               double pinBarRatio,
                               double engulfingRatio,
                               double dojiRatio,
                               double minCandleSize)
{
   m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   m_timeframe = timeframe;
   m_pinBarRatio = pinBarRatio;
   m_engulfingMinRatio = engulfingRatio;
   m_dojiBodyRatio = dojiRatio;
   m_minCandleSize = minCandleSize;

   if(m_enableLog)
   {
      LogDebug(StringFormat("PriceAction initialized: Symbol=%s, TF=%d, PinBarRatio=%.1f",
               m_symbol, m_timeframe, m_pinBarRatio));
   }

   return true;
}

//+------------------------------------------------------------------+
//| ローソク足の実体を取得                                            |
//+------------------------------------------------------------------+
double CPriceAction::GetCandleBody(const MqlRates &rate)
{
   return MathAbs(rate.close - rate.open);
}

//+------------------------------------------------------------------+
//| 上ヒゲを取得                                                      |
//+------------------------------------------------------------------+
double CPriceAction::GetUpperWick(const MqlRates &rate)
{
   return rate.high - MathMax(rate.open, rate.close);
}

//+------------------------------------------------------------------+
//| 下ヒゲを取得                                                      |
//+------------------------------------------------------------------+
double CPriceAction::GetLowerWick(const MqlRates &rate)
{
   return MathMin(rate.open, rate.close) - rate.low;
}

//+------------------------------------------------------------------+
//| ローソク足のレンジを取得                                          |
//+------------------------------------------------------------------+
double CPriceAction::GetCandleRange(const MqlRates &rate)
{
   return rate.high - rate.low;
}

//+------------------------------------------------------------------+
//| 陽線かどうか                                                      |
//+------------------------------------------------------------------+
bool CPriceAction::IsBullishCandle(const MqlRates &rate)
{
   return rate.close > rate.open;
}

//+------------------------------------------------------------------+
//| 陰線かどうか                                                      |
//+------------------------------------------------------------------+
bool CPriceAction::IsBearishCandle(const MqlRates &rate)
{
   return rate.close < rate.open;
}

//+------------------------------------------------------------------+
//| ピンバー検出                                                      |
//+------------------------------------------------------------------+
bool CPriceAction::IsPinBar(const MqlRates &rates[], int index, ENUM_SIGNAL_DIRECTION &direction)
{
   if(index < 0 || index >= ArraySize(rates))
      return false;

   const MqlRates &candle = rates[index];

   double body = GetCandleBody(candle);
   double range = GetCandleRange(candle);
   double upperWick = GetUpperWick(candle);
   double lowerWick = GetLowerWick(candle);

   // 最小サイズチェック
   if(PriceToPips(range, m_symbol) < m_minCandleSize)
      return false;

   // 実体が小さい必要がある
   if(body > range * 0.3)
      return false;

   // 買いピンバー（下ヒゲが長い）
   if(lowerWick > body * m_pinBarRatio && lowerWick > upperWick * 2)
   {
      direction = SIGNAL_BUY;
      if(m_enableLog) LogDebug(StringFormat("Bullish Pin Bar detected at index %d", index));
      return true;
   }

   // 売りピンバー（上ヒゲが長い）
   if(upperWick > body * m_pinBarRatio && upperWick > lowerWick * 2)
   {
      direction = SIGNAL_SELL;
      if(m_enableLog) LogDebug(StringFormat("Bearish Pin Bar detected at index %d", index));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 包み足検出                                                        |
//+------------------------------------------------------------------+
bool CPriceAction::IsEngulfing(const MqlRates &rates[], int index, ENUM_SIGNAL_DIRECTION &direction)
{
   if(index < 1 || index >= ArraySize(rates))
      return false;

   const MqlRates &current = rates[index];
   const MqlRates &previous = rates[index + 1];

   double currentBody = GetCandleBody(current);
   double previousBody = GetCandleBody(previous);

   // 最小サイズチェック
   if(PriceToPips(currentBody, m_symbol) < m_minCandleSize)
      return false;

   // 包み足の条件：現在の実体が前の実体を完全に包む
   if(currentBody < previousBody * m_engulfingMinRatio)
      return false;

   // 買いの包み足（陰線の後の陽線）
   if(IsBearishCandle(previous) && IsBullishCandle(current))
   {
      if(current.open <= previous.close && current.close >= previous.open)
      {
         direction = SIGNAL_BUY;
         if(m_enableLog) LogDebug(StringFormat("Bullish Engulfing detected at index %d", index));
         return true;
      }
   }

   // 売りの包み足（陽線の後の陰線）
   if(IsBullishCandle(previous) && IsBearishCandle(current))
   {
      if(current.open >= previous.close && current.close <= previous.open)
      {
         direction = SIGNAL_SELL;
         if(m_enableLog) LogDebug(StringFormat("Bearish Engulfing detected at index %d", index));
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| はらみ足検出                                                      |
//+------------------------------------------------------------------+
bool CPriceAction::IsInsideBar(const MqlRates &rates[], int index)
{
   if(index < 1 || index >= ArraySize(rates))
      return false;

   const MqlRates &current = rates[index];
   const MqlRates &previous = rates[index + 1];

   // 現在の足が前の足の中に完全に収まっている
   bool isInside = (current.high < previous.high && current.low > previous.low);

   if(isInside && m_enableLog)
   {
      LogDebug(StringFormat("Inside Bar detected at index %d", index));
   }

   return isInside;
}

//+------------------------------------------------------------------+
//| 毛抜き検出                                                        |
//+------------------------------------------------------------------+
bool CPriceAction::IsTweezer(const MqlRates &rates[], int index, ENUM_SIGNAL_DIRECTION &direction)
{
   if(index < 1 || index >= ArraySize(rates))
      return false;

   const MqlRates &current = rates[index];
   const MqlRates &previous = rates[index + 1];

   double tolerance = PipsToPrice(1.0, m_symbol);  // 1 pip許容

   // 毛抜き底（安値が同じ）
   if(MathAbs(current.low - previous.low) < tolerance)
   {
      if(IsBearishCandle(previous) && IsBullishCandle(current))
      {
         direction = SIGNAL_BUY;
         if(m_enableLog) LogDebug(StringFormat("Tweezer Bottom detected at index %d", index));
         return true;
      }
   }

   // 毛抜き天井（高値が同じ）
   if(MathAbs(current.high - previous.high) < tolerance)
   {
      if(IsBullishCandle(previous) && IsBearishCandle(current))
      {
         direction = SIGNAL_SELL;
         if(m_enableLog) LogDebug(StringFormat("Tweezer Top detected at index %d", index));
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| 明けの明星検出                                                    |
//+------------------------------------------------------------------+
bool CPriceAction::IsMorningStar(const MqlRates &rates[], int index)
{
   if(index < 2 || index >= ArraySize(rates))
      return false;

   const MqlRates &first = rates[index + 2];   // 最初の足（大陰線）
   const MqlRates &second = rates[index + 1];  // 2番目の足（小さい足、ギャップダウン）
   const MqlRates &third = rates[index];       // 3番目の足（大陽線）

   double firstBody = GetCandleBody(first);
   double secondBody = GetCandleBody(second);
   double thirdBody = GetCandleBody(third);

   // 条件チェック
   if(!IsBearishCandle(first)) return false;   // 最初は大陰線
   if(!IsBullishCandle(third)) return false;   // 3番目は大陽線
   if(secondBody > firstBody * 0.3) return false;  // 2番目は小さい
   if(thirdBody < firstBody * 0.5) return false;   // 3番目は十分大きい

   // ギャップの確認（完全なギャップは稀なので緩い条件）
   if(second.high > first.low) return false;

   if(m_enableLog) LogDebug(StringFormat("Morning Star detected at index %d", index));
   return true;
}

//+------------------------------------------------------------------+
//| 宵の明星検出                                                      |
//+------------------------------------------------------------------+
bool CPriceAction::IsEveningStar(const MqlRates &rates[], int index)
{
   if(index < 2 || index >= ArraySize(rates))
      return false;

   const MqlRates &first = rates[index + 2];   // 最初の足（大陽線）
   const MqlRates &second = rates[index + 1];  // 2番目の足（小さい足、ギャップアップ）
   const MqlRates &third = rates[index];       // 3番目の足（大陰線）

   double firstBody = GetCandleBody(first);
   double secondBody = GetCandleBody(second);
   double thirdBody = GetCandleBody(third);

   // 条件チェック
   if(!IsBullishCandle(first)) return false;   // 最初は大陽線
   if(!IsBearishCandle(third)) return false;   // 3番目は大陰線
   if(secondBody > firstBody * 0.3) return false;  // 2番目は小さい
   if(thirdBody < firstBody * 0.5) return false;   // 3番目は十分大きい

   // ギャップの確認
   if(second.low < first.high) return false;

   if(m_enableLog) LogDebug(StringFormat("Evening Star detected at index %d", index));
   return true;
}

//+------------------------------------------------------------------+
//| ハンマー検出                                                      |
//+------------------------------------------------------------------+
bool CPriceAction::IsHammer(const MqlRates &rates[], int index)
{
   if(index < 0 || index >= ArraySize(rates))
      return false;

   const MqlRates &candle = rates[index];

   double body = GetCandleBody(candle);
   double range = GetCandleRange(candle);
   double lowerWick = GetLowerWick(candle);
   double upperWick = GetUpperWick(candle);

   // 最小サイズチェック
   if(PriceToPips(range, m_symbol) < m_minCandleSize)
      return false;

   // ハンマーの条件
   // - 下ヒゲが実体の2倍以上
   // - 上ヒゲはほとんどない
   // - 実体は上部にある
   bool isHammer = (lowerWick >= body * 2.0) &&
                   (upperWick < body * 0.3) &&
                   (body > 0);

   if(isHammer && m_enableLog)
   {
      LogDebug(StringFormat("Hammer detected at index %d", index));
   }

   return isHammer;
}

//+------------------------------------------------------------------+
//| 流れ星検出                                                        |
//+------------------------------------------------------------------+
bool CPriceAction::IsShootingStar(const MqlRates &rates[], int index)
{
   if(index < 0 || index >= ArraySize(rates))
      return false;

   const MqlRates &candle = rates[index];

   double body = GetCandleBody(candle);
   double range = GetCandleRange(candle);
   double lowerWick = GetLowerWick(candle);
   double upperWick = GetUpperWick(candle);

   // 最小サイズチェック
   if(PriceToPips(range, m_symbol) < m_minCandleSize)
      return false;

   // 流れ星の条件
   // - 上ヒゲが実体の2倍以上
   // - 下ヒゲはほとんどない
   // - 実体は下部にある
   bool isShootingStar = (upperWick >= body * 2.0) &&
                          (lowerWick < body * 0.3) &&
                          (body > 0);

   if(isShootingStar && m_enableLog)
   {
      LogDebug(StringFormat("Shooting Star detected at index %d", index));
   }

   return isShootingStar;
}

//+------------------------------------------------------------------+
//| 同事線検出                                                        |
//+------------------------------------------------------------------+
bool CPriceAction::IsDoji(const MqlRates &rate)
{
   double body = GetCandleBody(rate);
   double range = GetCandleRange(rate);

   if(range == 0) return false;

   bool isDoji = (body / range) < m_dojiBodyRatio;

   return isDoji;
}

//+------------------------------------------------------------------+
//| 複数パターン検出                                                  |
//+------------------------------------------------------------------+
int CPriceAction::DetectPatterns(PriceActionResult &results[], int maxResults)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(m_symbol, m_timeframe, 0, 10, rates);
   if(copied < 10) return 0;

   ArrayResize(results, 0);
   int count = 0;

   ENUM_SIGNAL_DIRECTION direction;

   // インデックス1（確定した最新の足）でパターンを検出
   // ピンバー
   if(count < maxResults && IsPinBar(rates, 1, direction))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_PIN_BAR;
      results[count].direction = direction;
      results[count].strength = 0.8;
      results[count].barIndex = 1;
      results[count].description = (direction == SIGNAL_BUY) ? "Bullish Pin Bar" : "Bearish Pin Bar";
      count++;
   }

   // 包み足
   if(count < maxResults && IsEngulfing(rates, 1, direction))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_ENGULFING;
      results[count].direction = direction;
      results[count].strength = 0.85;
      results[count].barIndex = 1;
      results[count].description = (direction == SIGNAL_BUY) ? "Bullish Engulfing" : "Bearish Engulfing";
      count++;
   }

   // はらみ足
   if(count < maxResults && IsInsideBar(rates, 1))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_INSIDE_BAR;
      results[count].direction = SIGNAL_NONE;  // ブレイク方向待ち
      results[count].strength = 0.5;
      results[count].barIndex = 1;
      results[count].description = "Inside Bar";
      count++;
   }

   // 毛抜き
   if(count < maxResults && IsTweezer(rates, 1, direction))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_TWEEZER;
      results[count].direction = direction;
      results[count].strength = 0.75;
      results[count].barIndex = 1;
      results[count].description = (direction == SIGNAL_BUY) ? "Tweezer Bottom" : "Tweezer Top";
      count++;
   }

   // ハンマー
   if(count < maxResults && IsHammer(rates, 1))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_HAMMER;
      results[count].direction = SIGNAL_BUY;
      results[count].strength = 0.7;
      results[count].barIndex = 1;
      results[count].description = "Hammer";
      count++;
   }

   // 流れ星
   if(count < maxResults && IsShootingStar(rates, 1))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_SHOOTING_STAR;
      results[count].direction = SIGNAL_SELL;
      results[count].strength = 0.7;
      results[count].barIndex = 1;
      results[count].description = "Shooting Star";
      count++;
   }

   // 明けの明星
   if(count < maxResults && IsMorningStar(rates, 1))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_MORNING_STAR;
      results[count].direction = SIGNAL_BUY;
      results[count].strength = 0.9;
      results[count].barIndex = 1;
      results[count].description = "Morning Star";
      count++;
   }

   // 宵の明星
   if(count < maxResults && IsEveningStar(rates, 1))
   {
      ArrayResize(results, count + 1);
      results[count].pattern = PA_EVENING_STAR;
      results[count].direction = SIGNAL_SELL;
      results[count].strength = 0.9;
      results[count].barIndex = 1;
      results[count].description = "Evening Star";
      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| シグナル方向を取得                                                |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIRECTION CPriceAction::GetSignalDirection()
{
   PriceActionResult results[];
   int count = DetectPatterns(results, 5);

   if(count == 0) return SIGNAL_NONE;

   // 最も強いシグナルを返す
   double maxStrength = 0;
   ENUM_SIGNAL_DIRECTION direction = SIGNAL_NONE;

   for(int i = 0; i < count; i++)
   {
      if(results[i].strength > maxStrength && results[i].direction != SIGNAL_NONE)
      {
         maxStrength = results[i].strength;
         direction = results[i].direction;
      }
   }

   return direction;
}

//+------------------------------------------------------------------+
//| シグナル強度を取得                                                |
//+------------------------------------------------------------------+
double CPriceAction::GetSignalStrength()
{
   PriceActionResult results[];
   int count = DetectPatterns(results, 5);

   if(count == 0) return 0;

   double maxStrength = 0;
   for(int i = 0; i < count; i++)
   {
      if(results[i].strength > maxStrength)
      {
         maxStrength = results[i].strength;
      }
   }

   return maxStrength;
}

//+------------------------------------------------------------------+
//| 最新のパターンを取得                                              |
//+------------------------------------------------------------------+
bool CPriceAction::GetLatestPattern(PriceActionResult &result)
{
   PriceActionResult results[];
   int count = DetectPatterns(results, 1);

   if(count > 0)
   {
      result = results[0];
      return true;
   }

   return false;
}

#endif // PRICE_ACTION_MQH
