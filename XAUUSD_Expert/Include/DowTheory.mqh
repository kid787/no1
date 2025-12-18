//+------------------------------------------------------------------+
//|                                                    DowTheory.mqh |
//|                       XAUUSD Expert - ダウ理論・損切り管理         |
//+------------------------------------------------------------------+
#ifndef DOW_THEORY_MQH
#define DOW_THEORY_MQH

#include "CommonDefines.mqh"

//--- トレンド状態
enum ENUM_DOW_TREND {
   DOW_TREND_UP = 1,         // 上昇トレンド
   DOW_TREND_DOWN = -1,      // 下降トレンド
   DOW_TREND_RANGE = 0       // レンジ
};

//--- スイングポイント情報構造体
struct DowSwingPoint {
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
   bool     isConfirmed;
   bool     isBroken;
};

//+------------------------------------------------------------------+
//| ダウ理論クラス                                                    |
//+------------------------------------------------------------------+
class CDowTheory
{
private:
   // 設定
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   ENUM_TIMEFRAMES m_higherTimeframe;  // 上位足
   int            m_swingStrength;      // スイングポイント強度
   int            m_lookbackBars;       // 検索バー数
   double         m_slMarginPercent;    // 損切り余裕マージン(%)

   // スイングポイントデータ
   DowSwingPoint  m_swingHighs[];
   DowSwingPoint  m_swingLows[];
   int            m_highCount;
   int            m_lowCount;

   // 上位足スイングポイント
   DowSwingPoint  m_htfSwingHighs[];
   DowSwingPoint  m_htfSwingLows[];

   // ログ
   bool           m_enableLog;

   // 内部メソッド
   void           DetectSwingPoints(ENUM_TIMEFRAMES tf, DowSwingPoint &highs[], DowSwingPoint &lows[]);
   bool           IsHigherHigh(const DowSwingPoint &current, const DowSwingPoint &previous);
   bool           IsHigherLow(const DowSwingPoint &current, const DowSwingPoint &previous);
   bool           IsLowerHigh(const DowSwingPoint &current, const DowSwingPoint &previous);
   bool           IsLowerLow(const DowSwingPoint &current, const DowSwingPoint &previous);

public:
                  CDowTheory();
                 ~CDowTheory();

   // 初期化
   bool           Initialize(string symbol = NULL,
                             ENUM_TIMEFRAMES timeframe = PERIOD_M5,
                             ENUM_TIMEFRAMES higherTF = PERIOD_H1,
                             int swingStr = 3,
                             int lookback = 100,
                             double slMargin = 3.0);

   // 更新
   void           Update();

   // トレンド判定
   ENUM_DOW_TREND GetTrend();
   ENUM_DOW_TREND GetHigherTFTrend();
   bool           IsTrendAligned();  // 上位足とトレンドが一致しているか

   // 損切りライン計算
   double         CalculateBuySL(double entryPrice);     // 買いの損切りライン
   double         CalculateSellSL(double entryPrice);    // 売りの損切りライン
   double         GetLastSwingLow(int count = 1);        // 直近N個目のスイングロー
   double         GetLastSwingHigh(int count = 1);       // 直近N個目のスイングハイ

   // 上位足の損切りライン
   double         GetHTFLastSwingLow(int count = 1);
   double         GetHTFLastSwingHigh(int count = 1);

   // スイングポイント取得
   bool           GetSwingHigh(int index, DowSwingPoint &point);
   bool           GetSwingLow(int index, DowSwingPoint &point);
   int            GetSwingHighCount() { return m_highCount; }
   int            GetSwingLowCount() { return m_lowCount; }

   // 利確ターゲット
   double         GetNextResistance(double currentPrice);  // 次のレジスタンス
   double         GetNextSupport(double currentPrice);     // 次のサポート
   double         GetHTFResistance(double currentPrice);   // 上位足のレジスタンス
   double         GetHTFSupport(double currentPrice);      // 上位足のサポート

   // 設定
   void           EnableLog(bool enable) { m_enableLog = enable; }
   void           SetSLMargin(double percent) { m_slMarginPercent = percent; }
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CDowTheory::CDowTheory()
{
   m_symbol = "";
   m_timeframe = PERIOD_M5;
   m_higherTimeframe = PERIOD_H1;
   m_swingStrength = 3;
   m_lookbackBars = 100;
   m_slMarginPercent = 3.0;
   m_highCount = 0;
   m_lowCount = 0;
   m_enableLog = true;
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CDowTheory::~CDowTheory()
{
   ArrayFree(m_swingHighs);
   ArrayFree(m_swingLows);
   ArrayFree(m_htfSwingHighs);
   ArrayFree(m_htfSwingLows);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CDowTheory::Initialize(string symbol,
                             ENUM_TIMEFRAMES timeframe,
                             ENUM_TIMEFRAMES higherTF,
                             int swingStr,
                             int lookback,
                             double slMargin)
{
   m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   m_timeframe = timeframe;
   m_higherTimeframe = higherTF;
   m_swingStrength = swingStr;
   m_lookbackBars = lookback;
   m_slMarginPercent = slMargin;

   Update();

   if(m_enableLog)
   {
      LogDebug(StringFormat("DowTheory initialized: Symbol=%s, TF=%d, HTF=%d, SwingStr=%d, SLMargin=%.1f%%",
               m_symbol, m_timeframe, m_higherTimeframe, m_swingStrength, m_slMarginPercent));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 更新                                                              |
//+------------------------------------------------------------------+
void CDowTheory::Update()
{
   // 現在のタイムフレームのスイングポイントを検出
   DetectSwingPoints(m_timeframe, m_swingHighs, m_swingLows);
   m_highCount = ArraySize(m_swingHighs);
   m_lowCount = ArraySize(m_swingLows);

   // 上位足のスイングポイントを検出
   DetectSwingPoints(m_higherTimeframe, m_htfSwingHighs, m_htfSwingLows);
}

//+------------------------------------------------------------------+
//| スイングポイントを検出                                            |
//+------------------------------------------------------------------+
void CDowTheory::DetectSwingPoints(ENUM_TIMEFRAMES tf, DowSwingPoint &highs[], DowSwingPoint &lows[])
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(m_symbol, tf, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return;

   ArrayResize(highs, 0);
   ArrayResize(lows, 0);

   for(int i = m_swingStrength; i < copied - m_swingStrength; i++)
   {
      bool isSwingHigh = true;
      bool isSwingLow = true;

      // スイングハイの判定
      for(int j = 1; j <= m_swingStrength; j++)
      {
         if(rates[i].high <= rates[i - j].high || rates[i].high <= rates[i + j].high)
         {
            isSwingHigh = false;
            break;
         }
      }

      // スイングローの判定
      for(int j = 1; j <= m_swingStrength; j++)
      {
         if(rates[i].low >= rates[i - j].low || rates[i].low >= rates[i + j].low)
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         DowSwingPoint point;
         point.price = rates[i].high;
         point.time = rates[i].time;
         point.barIndex = i;
         point.isHigh = true;
         point.isConfirmed = (i > m_swingStrength);
         point.isBroken = false;

         int size = ArraySize(highs);
         ArrayResize(highs, size + 1);
         highs[size] = point;
      }

      if(isSwingLow)
      {
         DowSwingPoint point;
         point.price = rates[i].low;
         point.time = rates[i].time;
         point.barIndex = i;
         point.isHigh = false;
         point.isConfirmed = (i > m_swingStrength);
         point.isBroken = false;

         int size = ArraySize(lows);
         ArrayResize(lows, size + 1);
         lows[size] = point;
      }
   }
}

//+------------------------------------------------------------------+
//| 高値更新判定                                                      |
//+------------------------------------------------------------------+
bool CDowTheory::IsHigherHigh(const DowSwingPoint &current, const DowSwingPoint &previous)
{
   return current.price > previous.price;
}

//+------------------------------------------------------------------+
//| 安値切り上げ判定                                                  |
//+------------------------------------------------------------------+
bool CDowTheory::IsHigherLow(const DowSwingPoint &current, const DowSwingPoint &previous)
{
   return current.price > previous.price;
}

//+------------------------------------------------------------------+
//| 高値切り下げ判定                                                  |
//+------------------------------------------------------------------+
bool CDowTheory::IsLowerHigh(const DowSwingPoint &current, const DowSwingPoint &previous)
{
   return current.price < previous.price;
}

//+------------------------------------------------------------------+
//| 安値更新判定                                                      |
//+------------------------------------------------------------------+
bool CDowTheory::IsLowerLow(const DowSwingPoint &current, const DowSwingPoint &previous)
{
   return current.price < previous.price;
}

//+------------------------------------------------------------------+
//| トレンド判定                                                      |
//+------------------------------------------------------------------+
ENUM_DOW_TREND CDowTheory::GetTrend()
{
   if(m_highCount < 2 || m_lowCount < 2)
      return DOW_TREND_RANGE;

   // 直近のスイングポイントを比較
   bool higherHighs = IsHigherHigh(m_swingHighs[0], m_swingHighs[1]);
   bool higherLows = IsHigherLow(m_swingLows[0], m_swingLows[1]);
   bool lowerHighs = IsLowerHigh(m_swingHighs[0], m_swingHighs[1]);
   bool lowerLows = IsLowerLow(m_swingLows[0], m_swingLows[1]);

   // 上昇トレンド: 高値更新 & 安値切り上げ
   if(higherHighs && higherLows)
   {
      return DOW_TREND_UP;
   }

   // 下降トレンド: 高値切り下げ & 安値更新
   if(lowerHighs && lowerLows)
   {
      return DOW_TREND_DOWN;
   }

   return DOW_TREND_RANGE;
}

//+------------------------------------------------------------------+
//| 上位足のトレンド判定                                              |
//+------------------------------------------------------------------+
ENUM_DOW_TREND CDowTheory::GetHigherTFTrend()
{
   int htfHighCount = ArraySize(m_htfSwingHighs);
   int htfLowCount = ArraySize(m_htfSwingLows);

   if(htfHighCount < 2 || htfLowCount < 2)
      return DOW_TREND_RANGE;

   bool higherHighs = IsHigherHigh(m_htfSwingHighs[0], m_htfSwingHighs[1]);
   bool higherLows = IsHigherLow(m_htfSwingLows[0], m_htfSwingLows[1]);
   bool lowerHighs = IsLowerHigh(m_htfSwingHighs[0], m_htfSwingHighs[1]);
   bool lowerLows = IsLowerLow(m_htfSwingLows[0], m_htfSwingLows[1]);

   if(higherHighs && higherLows) return DOW_TREND_UP;
   if(lowerHighs && lowerLows) return DOW_TREND_DOWN;

   return DOW_TREND_RANGE;
}

//+------------------------------------------------------------------+
//| トレンドが上位足と一致しているか                                  |
//+------------------------------------------------------------------+
bool CDowTheory::IsTrendAligned()
{
   ENUM_DOW_TREND currentTrend = GetTrend();
   ENUM_DOW_TREND htfTrend = GetHigherTFTrend();

   // 両方が同じトレンド方向の場合true
   return (currentTrend == htfTrend && currentTrend != DOW_TREND_RANGE);
}

//+------------------------------------------------------------------+
//| 買いの損切りラインを計算                                          |
//+------------------------------------------------------------------+
double CDowTheory::CalculateBuySL(double entryPrice)
{
   // 直近のスイングローを取得
   double swingLow = GetLastSwingLow(1);

   if(swingLow == 0)
   {
      // スイングローが見つからない場合、デフォルトの距離を使用
      return entryPrice - PipsToPrice(50.0, m_symbol);
   }

   // マージンを追加（騙し・試しを考慮）
   double margin = swingLow * (m_slMarginPercent / 100.0);
   double slPrice = swingLow - margin;

   // エントリー価格より上にならないようにチェック
   if(slPrice >= entryPrice)
   {
      slPrice = entryPrice - PipsToPrice(30.0, m_symbol);
   }

   if(m_enableLog)
   {
      LogDebug(StringFormat("Buy SL calculated: SwingLow=%.5f, Margin=%.5f, SL=%.5f",
               swingLow, margin, slPrice));
   }

   return slPrice;
}

//+------------------------------------------------------------------+
//| 売りの損切りラインを計算                                          |
//+------------------------------------------------------------------+
double CDowTheory::CalculateSellSL(double entryPrice)
{
   // 直近のスイングハイを取得
   double swingHigh = GetLastSwingHigh(1);

   if(swingHigh == 0)
   {
      // スイングハイが見つからない場合、デフォルトの距離を使用
      return entryPrice + PipsToPrice(50.0, m_symbol);
   }

   // マージンを追加（騙し・試しを考慮）
   double margin = swingHigh * (m_slMarginPercent / 100.0);
   double slPrice = swingHigh + margin;

   // エントリー価格より下にならないようにチェック
   if(slPrice <= entryPrice)
   {
      slPrice = entryPrice + PipsToPrice(30.0, m_symbol);
   }

   if(m_enableLog)
   {
      LogDebug(StringFormat("Sell SL calculated: SwingHigh=%.5f, Margin=%.5f, SL=%.5f",
               swingHigh, margin, slPrice));
   }

   return slPrice;
}

//+------------------------------------------------------------------+
//| 直近のスイングローを取得                                          |
//+------------------------------------------------------------------+
double CDowTheory::GetLastSwingLow(int count)
{
   if(count < 1 || count > m_lowCount)
      return 0;

   return m_swingLows[count - 1].price;
}

//+------------------------------------------------------------------+
//| 直近のスイングハイを取得                                          |
//+------------------------------------------------------------------+
double CDowTheory::GetLastSwingHigh(int count)
{
   if(count < 1 || count > m_highCount)
      return 0;

   return m_swingHighs[count - 1].price;
}

//+------------------------------------------------------------------+
//| 上位足のスイングローを取得                                        |
//+------------------------------------------------------------------+
double CDowTheory::GetHTFLastSwingLow(int count)
{
   int htfLowCount = ArraySize(m_htfSwingLows);
   if(count < 1 || count > htfLowCount)
      return 0;

   return m_htfSwingLows[count - 1].price;
}

//+------------------------------------------------------------------+
//| 上位足のスイングハイを取得                                        |
//+------------------------------------------------------------------+
double CDowTheory::GetHTFLastSwingHigh(int count)
{
   int htfHighCount = ArraySize(m_htfSwingHighs);
   if(count < 1 || count > htfHighCount)
      return 0;

   return m_htfSwingHighs[count - 1].price;
}

//+------------------------------------------------------------------+
//| スイングハイを取得                                                |
//+------------------------------------------------------------------+
bool CDowTheory::GetSwingHigh(int index, DowSwingPoint &point)
{
   if(index < 0 || index >= m_highCount)
      return false;

   point = m_swingHighs[index];
   return true;
}

//+------------------------------------------------------------------+
//| スイングローを取得                                                |
//+------------------------------------------------------------------+
bool CDowTheory::GetSwingLow(int index, DowSwingPoint &point)
{
   if(index < 0 || index >= m_lowCount)
      return false;

   point = m_swingLows[index];
   return true;
}

//+------------------------------------------------------------------+
//| 次のレジスタンスを取得                                            |
//+------------------------------------------------------------------+
double CDowTheory::GetNextResistance(double currentPrice)
{
   double nearest = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < m_highCount; i++)
   {
      if(m_swingHighs[i].price > currentPrice)
      {
         double distance = m_swingHighs[i].price - currentPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = m_swingHighs[i].price;
         }
      }
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| 次のサポートを取得                                                |
//+------------------------------------------------------------------+
double CDowTheory::GetNextSupport(double currentPrice)
{
   double nearest = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < m_lowCount; i++)
   {
      if(m_swingLows[i].price < currentPrice)
      {
         double distance = currentPrice - m_swingLows[i].price;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = m_swingLows[i].price;
         }
      }
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| 上位足のレジスタンスを取得                                        |
//+------------------------------------------------------------------+
double CDowTheory::GetHTFResistance(double currentPrice)
{
   double nearest = 0;
   double minDistance = DBL_MAX;
   int htfHighCount = ArraySize(m_htfSwingHighs);

   for(int i = 0; i < htfHighCount; i++)
   {
      if(m_htfSwingHighs[i].price > currentPrice)
      {
         double distance = m_htfSwingHighs[i].price - currentPrice;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = m_htfSwingHighs[i].price;
         }
      }
   }

   return nearest;
}

//+------------------------------------------------------------------+
//| 上位足のサポートを取得                                            |
//+------------------------------------------------------------------+
double CDowTheory::GetHTFSupport(double currentPrice)
{
   double nearest = 0;
   double minDistance = DBL_MAX;
   int htfLowCount = ArraySize(m_htfSwingLows);

   for(int i = 0; i < htfLowCount; i++)
   {
      if(m_htfSwingLows[i].price < currentPrice)
      {
         double distance = currentPrice - m_htfSwingLows[i].price;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = m_htfSwingLows[i].price;
         }
      }
   }

   return nearest;
}

#endif // DOW_THEORY_MQH
