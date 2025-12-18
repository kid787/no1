//+------------------------------------------------------------------+
//|                                               HorizontalLine.mqh |
//|                       XAUUSD Expert - 水平線・ネックライン検出     |
//+------------------------------------------------------------------+
#ifndef HORIZONTAL_LINE_MQH
#define HORIZONTAL_LINE_MQH

#include "CommonDefines.mqh"

//--- 水平線タイプ
enum ENUM_LINE_TYPE {
   LINE_NONE = 0,
   LINE_SUPPORT = 1,         // サポートライン
   LINE_RESISTANCE = 2,      // レジスタンスライン
   LINE_NECKLINE = 3,        // ネックライン
   LINE_SWING_HIGH = 4,      // スイングハイ
   LINE_SWING_LOW = 5        // スイングロー
};

//--- 水平線構造体
struct HorizontalLevel {
   double         price;           // 価格
   ENUM_LINE_TYPE type;            // 種類
   int            touchCount;      // タッチ回数
   datetime       firstTouch;      // 最初のタッチ時間
   datetime       lastTouch;       // 最後のタッチ時間
   double         strength;        // 強度 (0.0-1.0)
   bool           isBroken;        // ブレイク済みか
};

//+------------------------------------------------------------------+
//| 水平線検出クラス                                                  |
//+------------------------------------------------------------------+
class CHorizontalLine
{
private:
   // 設定
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int            m_lookbackBars;       // 検索バー数
   int            m_swingStrength;      // スイングポイント強度（左右のバー数）
   double         m_mergeTolerance;     // レベル統合の許容範囲（pips）
   double         m_touchTolerance;     // タッチ判定の許容範囲（pips）
   int            m_maxLevels;          // 最大レベル数

   // 検出されたレベル
   HorizontalLevel m_levels[];
   int            m_levelCount;

   // スイングポイント
   SwingPoint     m_swingHighs[];
   SwingPoint     m_swingLows[];

   // ログ
   bool           m_enableLog;

   // 内部メソッド
   void           DetectSwingPoints();
   void           FindSupportResistance();
   void           DetectNecklines();
   void           MergeLevels();
   void           CalculateLevelStrength();
   bool           AddLevel(double price, ENUM_LINE_TYPE type);
   int            FindNearestLevel(double price, ENUM_LINE_TYPE type);

public:
                  CHorizontalLine();
                 ~CHorizontalLine();

   // 初期化
   bool           Initialize(string symbol = NULL,
                             ENUM_TIMEFRAMES timeframe = PERIOD_M5,
                             int lookback = 200,
                             int swingStr = 3,
                             double mergeTol = 5.0,
                             double touchTol = 3.0);

   // 更新
   void           Update();

   // レベル検出
   bool           IsPriceNearSupport(double price, double &supportPrice);
   bool           IsPriceNearResistance(double price, double &resistancePrice);
   bool           IsPriceNearNeckline(double price, double &necklinePrice);

   // シグナル
   ENUM_SIGNAL_DIRECTION GetBounceSignal(double price);
   double         GetNearestSupportBelow(double price);
   double         GetNearestResistanceAbove(double price);

   // レベル情報取得
   int            GetLevelCount() { return m_levelCount; }
   bool           GetLevel(int index, HorizontalLevel &level);
   double         GetStrongestSupport(double belowPrice);
   double         GetStrongestResistance(double abovePrice);

   // スイングポイント取得
   bool           GetRecentSwingHigh(SwingPoint &point, int maxBarsBack = 50);
   bool           GetRecentSwingLow(SwingPoint &point, int maxBarsBack = 50);

   // 設定
   void           EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CHorizontalLine::CHorizontalLine()
{
   m_symbol = "";
   m_timeframe = PERIOD_M5;
   m_lookbackBars = 200;
   m_swingStrength = 3;
   m_mergeTolerance = 5.0;
   m_touchTolerance = 3.0;
   m_maxLevels = 20;
   m_levelCount = 0;
   m_enableLog = true;
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CHorizontalLine::~CHorizontalLine()
{
   ArrayFree(m_levels);
   ArrayFree(m_swingHighs);
   ArrayFree(m_swingLows);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CHorizontalLine::Initialize(string symbol,
                                  ENUM_TIMEFRAMES timeframe,
                                  int lookback,
                                  int swingStr,
                                  double mergeTol,
                                  double touchTol)
{
   m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   m_timeframe = timeframe;
   m_lookbackBars = lookback;
   m_swingStrength = swingStr;
   m_mergeTolerance = mergeTol;
   m_touchTolerance = touchTol;

   ArrayResize(m_levels, 0);
   m_levelCount = 0;

   Update();

   if(m_enableLog)
   {
      LogDebug(StringFormat("HorizontalLine initialized: Symbol=%s, TF=%d, Lookback=%d, SwingStr=%d",
               m_symbol, m_timeframe, m_lookbackBars, m_swingStrength));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 更新                                                              |
//+------------------------------------------------------------------+
void CHorizontalLine::Update()
{
   // レベルをクリア
   ArrayResize(m_levels, 0);
   m_levelCount = 0;

   // スイングポイントを検出
   DetectSwingPoints();

   // サポート・レジスタンスを検出
   FindSupportResistance();

   // ネックラインを検出
   DetectNecklines();

   // 近いレベルを統合
   MergeLevels();

   // レベル強度を計算
   CalculateLevelStrength();
}

//+------------------------------------------------------------------+
//| スイングポイントを検出                                            |
//+------------------------------------------------------------------+
void CHorizontalLine::DetectSwingPoints()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackBars, rates);
   if(copied < m_lookbackBars) return;

   ArrayResize(m_swingHighs, 0);
   ArrayResize(m_swingLows, 0);

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
         SwingPoint point;
         point.price = rates[i].high;
         point.time = rates[i].time;
         point.barIndex = i;
         point.isHigh = true;
         point.isConfirmed = true;

         int size = ArraySize(m_swingHighs);
         ArrayResize(m_swingHighs, size + 1);
         m_swingHighs[size] = point;
      }

      if(isSwingLow)
      {
         SwingPoint point;
         point.price = rates[i].low;
         point.time = rates[i].time;
         point.barIndex = i;
         point.isHigh = false;
         point.isConfirmed = true;

         int size = ArraySize(m_swingLows);
         ArrayResize(m_swingLows, size + 1);
         m_swingLows[size] = point;
      }
   }
}

//+------------------------------------------------------------------+
//| サポート・レジスタンスを検出                                      |
//+------------------------------------------------------------------+
void CHorizontalLine::FindSupportResistance()
{
   // スイングローからサポートを作成
   for(int i = 0; i < ArraySize(m_swingLows); i++)
   {
      AddLevel(m_swingLows[i].price, LINE_SUPPORT);
   }

   // スイングハイからレジスタンスを作成
   for(int i = 0; i < ArraySize(m_swingHighs); i++)
   {
      AddLevel(m_swingHighs[i].price, LINE_RESISTANCE);
   }
}

//+------------------------------------------------------------------+
//| ネックラインを検出                                                |
//+------------------------------------------------------------------+
void CHorizontalLine::DetectNecklines()
{
   // ダブルトップ/ダブルボトムのネックライン検出
   // 2つの近いスイングハイの間のローがネックライン（ダブルトップ）
   // 2つの近いスイングローの間のハイがネックライン（ダブルボトム）

   double tolerance = PipsToPrice(m_mergeTolerance * 2, m_symbol);

   // ダブルトップのネックライン
   for(int i = 0; i < ArraySize(m_swingHighs) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(m_swingHighs); j++)
      {
         // 2つのスイングハイが近い価格にあるか
         if(MathAbs(m_swingHighs[i].price - m_swingHighs[j].price) < tolerance)
         {
            // その間にあるスイングローを探す
            for(int k = 0; k < ArraySize(m_swingLows); k++)
            {
               if(m_swingLows[k].barIndex > m_swingHighs[i].barIndex &&
                  m_swingLows[k].barIndex < m_swingHighs[j].barIndex)
               {
                  AddLevel(m_swingLows[k].price, LINE_NECKLINE);
               }
            }
         }
      }
   }

   // ダブルボトムのネックライン
   for(int i = 0; i < ArraySize(m_swingLows) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(m_swingLows); j++)
      {
         // 2つのスイングローが近い価格にあるか
         if(MathAbs(m_swingLows[i].price - m_swingLows[j].price) < tolerance)
         {
            // その間にあるスイングハイを探す
            for(int k = 0; k < ArraySize(m_swingHighs); k++)
            {
               if(m_swingHighs[k].barIndex > m_swingLows[i].barIndex &&
                  m_swingHighs[k].barIndex < m_swingLows[j].barIndex)
               {
                  AddLevel(m_swingHighs[k].price, LINE_NECKLINE);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| レベルを追加                                                      |
//+------------------------------------------------------------------+
bool CHorizontalLine::AddLevel(double price, ENUM_LINE_TYPE type)
{
   if(m_levelCount >= m_maxLevels)
      return false;

   // 既存の近いレベルがあるか確認
   int nearIndex = FindNearestLevel(price, type);
   if(nearIndex >= 0)
   {
      // タッチ回数を増やす
      m_levels[nearIndex].touchCount++;
      m_levels[nearIndex].lastTouch = TimeCurrent();
      return true;
   }

   // 新規追加
   ArrayResize(m_levels, m_levelCount + 1);

   m_levels[m_levelCount].price = price;
   m_levels[m_levelCount].type = type;
   m_levels[m_levelCount].touchCount = 1;
   m_levels[m_levelCount].firstTouch = TimeCurrent();
   m_levels[m_levelCount].lastTouch = TimeCurrent();
   m_levels[m_levelCount].strength = 0.5;
   m_levels[m_levelCount].isBroken = false;

   m_levelCount++;
   return true;
}

//+------------------------------------------------------------------+
//| 最も近いレベルを検索                                              |
//+------------------------------------------------------------------+
int CHorizontalLine::FindNearestLevel(double price, ENUM_LINE_TYPE type)
{
   double tolerance = PipsToPrice(m_mergeTolerance, m_symbol);

   for(int i = 0; i < m_levelCount; i++)
   {
      if(m_levels[i].type == type || type == LINE_NONE)
      {
         if(MathAbs(m_levels[i].price - price) < tolerance)
         {
            return i;
         }
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| 近いレベルを統合                                                  |
//+------------------------------------------------------------------+
void CHorizontalLine::MergeLevels()
{
   if(m_levelCount < 2) return;

   double tolerance = PipsToPrice(m_mergeTolerance, m_symbol);

   // シンプルなマージ：近いレベルを結合
   for(int i = 0; i < m_levelCount; i++)
   {
      for(int j = i + 1; j < m_levelCount; j++)
      {
         if(MathAbs(m_levels[i].price - m_levels[j].price) < tolerance)
         {
            // jのタッチ回数をiに加算
            m_levels[i].touchCount += m_levels[j].touchCount;

            // 価格は平均値
            m_levels[i].price = (m_levels[i].price + m_levels[j].price) / 2;

            // jを削除
            for(int k = j; k < m_levelCount - 1; k++)
            {
               m_levels[k] = m_levels[k + 1];
            }
            m_levelCount--;
            ArrayResize(m_levels, m_levelCount);
            j--;  // インデックス調整
         }
      }
   }
}

//+------------------------------------------------------------------+
//| レベル強度を計算                                                  |
//+------------------------------------------------------------------+
void CHorizontalLine::CalculateLevelStrength()
{
   for(int i = 0; i < m_levelCount; i++)
   {
      // タッチ回数に基づいて強度を計算
      double touchStrength = MathMin(1.0, m_levels[i].touchCount / 5.0);

      // 最近のタッチほど強い
      double recency = 1.0;
      int barsSinceTouch = iBarShift(m_symbol, m_timeframe, m_levels[i].lastTouch);
      if(barsSinceTouch > 0)
      {
         recency = MathMax(0.3, 1.0 - (barsSinceTouch / (double)m_lookbackBars));
      }

      m_levels[i].strength = touchStrength * 0.7 + recency * 0.3;
   }
}

//+------------------------------------------------------------------+
//| 価格がサポート付近にあるか                                        |
//+------------------------------------------------------------------+
bool CHorizontalLine::IsPriceNearSupport(double price, double &supportPrice)
{
   double tolerance = PipsToPrice(m_touchTolerance, m_symbol);

   for(int i = 0; i < m_levelCount; i++)
   {
      if(m_levels[i].type == LINE_SUPPORT || m_levels[i].type == LINE_NECKLINE)
      {
         if(MathAbs(price - m_levels[i].price) < tolerance && price >= m_levels[i].price)
         {
            supportPrice = m_levels[i].price;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 価格がレジスタンス付近にあるか                                    |
//+------------------------------------------------------------------+
bool CHorizontalLine::IsPriceNearResistance(double price, double &resistancePrice)
{
   double tolerance = PipsToPrice(m_touchTolerance, m_symbol);

   for(int i = 0; i < m_levelCount; i++)
   {
      if(m_levels[i].type == LINE_RESISTANCE || m_levels[i].type == LINE_NECKLINE)
      {
         if(MathAbs(price - m_levels[i].price) < tolerance && price <= m_levels[i].price)
         {
            resistancePrice = m_levels[i].price;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 価格がネックライン付近にあるか                                    |
//+------------------------------------------------------------------+
bool CHorizontalLine::IsPriceNearNeckline(double price, double &necklinePrice)
{
   double tolerance = PipsToPrice(m_touchTolerance, m_symbol);

   for(int i = 0; i < m_levelCount; i++)
   {
      if(m_levels[i].type == LINE_NECKLINE)
      {
         if(MathAbs(price - m_levels[i].price) < tolerance)
         {
            necklinePrice = m_levels[i].price;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| バウンスシグナルを取得                                            |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIRECTION CHorizontalLine::GetBounceSignal(double price)
{
   double levelPrice;

   // サポートからの反発 → 買いシグナル
   if(IsPriceNearSupport(price, levelPrice))
   {
      return SIGNAL_BUY;
   }

   // レジスタンスからの反落 → 売りシグナル
   if(IsPriceNearResistance(price, levelPrice))
   {
      return SIGNAL_SELL;
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 指定価格より下の最も近いサポート                                  |
//+------------------------------------------------------------------+
double CHorizontalLine::GetNearestSupportBelow(double price)
{
   double nearest = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < m_levelCount; i++)
   {
      if((m_levels[i].type == LINE_SUPPORT || m_levels[i].type == LINE_NECKLINE) &&
         m_levels[i].price < price)
      {
         double distance = price - m_levels[i].price;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = m_levels[i].price;
         }
      }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| 指定価格より上の最も近いレジスタンス                              |
//+------------------------------------------------------------------+
double CHorizontalLine::GetNearestResistanceAbove(double price)
{
   double nearest = 0;
   double minDistance = DBL_MAX;

   for(int i = 0; i < m_levelCount; i++)
   {
      if((m_levels[i].type == LINE_RESISTANCE || m_levels[i].type == LINE_NECKLINE) &&
         m_levels[i].price > price)
      {
         double distance = m_levels[i].price - price;
         if(distance < minDistance)
         {
            minDistance = distance;
            nearest = m_levels[i].price;
         }
      }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| レベル情報を取得                                                  |
//+------------------------------------------------------------------+
bool CHorizontalLine::GetLevel(int index, HorizontalLevel &level)
{
   if(index < 0 || index >= m_levelCount)
      return false;

   level = m_levels[index];
   return true;
}

//+------------------------------------------------------------------+
//| 最も強いサポートを取得                                            |
//+------------------------------------------------------------------+
double CHorizontalLine::GetStrongestSupport(double belowPrice)
{
   double strongest = 0;
   double maxStrength = 0;

   for(int i = 0; i < m_levelCount; i++)
   {
      if((m_levels[i].type == LINE_SUPPORT || m_levels[i].type == LINE_NECKLINE) &&
         m_levels[i].price < belowPrice &&
         m_levels[i].strength > maxStrength)
      {
         maxStrength = m_levels[i].strength;
         strongest = m_levels[i].price;
      }
   }
   return strongest;
}

//+------------------------------------------------------------------+
//| 最も強いレジスタンスを取得                                        |
//+------------------------------------------------------------------+
double CHorizontalLine::GetStrongestResistance(double abovePrice)
{
   double strongest = 0;
   double maxStrength = 0;

   for(int i = 0; i < m_levelCount; i++)
   {
      if((m_levels[i].type == LINE_RESISTANCE || m_levels[i].type == LINE_NECKLINE) &&
         m_levels[i].price > abovePrice &&
         m_levels[i].strength > maxStrength)
      {
         maxStrength = m_levels[i].strength;
         strongest = m_levels[i].price;
      }
   }
   return strongest;
}

//+------------------------------------------------------------------+
//| 直近のスイングハイを取得                                          |
//+------------------------------------------------------------------+
bool CHorizontalLine::GetRecentSwingHigh(SwingPoint &point, int maxBarsBack)
{
   for(int i = 0; i < ArraySize(m_swingHighs); i++)
   {
      if(m_swingHighs[i].barIndex <= maxBarsBack)
      {
         point = m_swingHighs[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 直近のスイングローを取得                                          |
//+------------------------------------------------------------------+
bool CHorizontalLine::GetRecentSwingLow(SwingPoint &point, int maxBarsBack)
{
   for(int i = 0; i < ArraySize(m_swingLows); i++)
   {
      if(m_swingLows[i].barIndex <= maxBarsBack)
      {
         point = m_swingLows[i];
         return true;
      }
   }
   return false;
}

#endif // HORIZONTAL_LINE_MQH
