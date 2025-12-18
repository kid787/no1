//+------------------------------------------------------------------+
//|                                               GranvilleLogic.mqh |
//|                            XAUUSD Expert - グランビルの法則       |
//+------------------------------------------------------------------+
#ifndef GRANVILLE_LOGIC_MQH
#define GRANVILLE_LOGIC_MQH

#include "CommonDefines.mqh"

//--- グランビルのパターンタイプ
enum ENUM_GRANVILLE_PATTERN {
   GRANVILLE_NONE = 0,
   // 買いシグナル
   GRANVILLE_BUY_1 = 1,   // MA下降→横ばい/上昇、価格がMAを下から上抜け
   GRANVILLE_BUY_2 = 2,   // MA上昇中、価格がMA下抜け後再度上抜け
   GRANVILLE_BUY_3 = 3,   // MA上昇中、価格がMAに接近し反発（押し目買い）★重要
   GRANVILLE_BUY_4 = 4,   // MA下降中、価格がMAから大きく乖離して下落（逆張り）
   // 売りシグナル
   GRANVILLE_SELL_1 = 5,  // MA上昇→横ばい/下降、価格がMAを上から下抜け
   GRANVILLE_SELL_2 = 6,  // MA下降中、価格がMA上抜け後再度下抜け
   GRANVILLE_SELL_3 = 7,  // MA下降中、価格がMAに接近し反落（戻り売り）★重要
   GRANVILLE_SELL_4 = 8   // MA上昇中、価格がMAから大きく乖離して上昇（逆張り）
};

//+------------------------------------------------------------------+
//| グランビルの法則クラス                                            |
//+------------------------------------------------------------------+
class CGranvilleLogic
{
private:
   // MA設定
   int            m_sma200Period;      // 長期SMA期間
   int            m_ema100Period;      // 中期EMA期間
   int            m_sma20Period;       // 短期SMA期間（利確用）

   // MAハンドル
   int            m_handleSMA200;
   int            m_handleEMA100;
   int            m_handleSMA20;

   // MA値バッファ
   double         m_sma200[];
   double         m_ema100[];
   double         m_sma20[];

   // 設定パラメータ
   double         m_maTouchTolerance;  // MA接近の許容範囲（pips）
   double         m_maDeviationPips;   // 乖離と判断する距離（pips）
   int            m_maSlopeBars;       // MA傾きを判定するバー数
   double         m_maSlopeThreshold;  // MA傾き閾値（pips/bar）

   // シンボル・タイムフレーム
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   // ログ設定
   bool           m_enableLog;

   // 内部メソッド
   bool           UpdateMAValues(int bars = 10);
   double         GetMASlope(double &maArray[], int bars);
   bool           IsPriceNearMA(double price, double maValue);
   bool           IsPriceAboveMA(double price, double maValue);
   bool           IsPriceBelowMA(double price, double maValue);

public:
                  CGranvilleLogic();
                 ~CGranvilleLogic();

   // 初期化
   bool           Initialize(string symbol = NULL,
                             ENUM_TIMEFRAMES timeframe = PERIOD_M5,
                             int sma200 = 200,
                             int ema100 = 100,
                             int sma20 = 20,
                             double touchTolerance = 10.0,
                             double deviationPips = 50.0);

   // シグナル検出
   ENUM_GRANVILLE_PATTERN DetectPattern();
   ENUM_SIGNAL_DIRECTION GetSignalDirection();
   double         GetSignalStrength();
   string         GetPatternDescription(ENUM_GRANVILLE_PATTERN pattern);

   // MA値取得
   double         GetSMA200(int shift = 0);
   double         GetEMA100(int shift = 0);
   double         GetSMA20(int shift = 0);

   // MA状態取得
   bool           IsSMA200Rising();
   bool           IsSMA200Falling();
   bool           IsEMA100Rising();
   bool           IsEMA100Falling();
   bool           IsMAConverging();       // MA収束中か
   bool           IsPriceNearLongMA();    // 価格が長期MAに近いか

   // トレンド判定
   int            GetTrendDirection();    // 1: 上昇, -1: 下降, 0: レンジ

   // 設定
   void           EnableLog(bool enable) { m_enableLog = enable; }
   void           SetTouchTolerance(double pips) { m_maTouchTolerance = pips; }
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CGranvilleLogic::CGranvilleLogic()
{
   m_sma200Period = 200;
   m_ema100Period = 100;
   m_sma20Period = 20;

   m_handleSMA200 = INVALID_HANDLE;
   m_handleEMA100 = INVALID_HANDLE;
   m_handleSMA20 = INVALID_HANDLE;

   m_maTouchTolerance = 10.0;
   m_maDeviationPips = 50.0;
   m_maSlopeBars = 5;
   m_maSlopeThreshold = 0.5;

   m_symbol = "";
   m_timeframe = PERIOD_M5;
   m_enableLog = true;

   ArraySetAsSeries(m_sma200, true);
   ArraySetAsSeries(m_ema100, true);
   ArraySetAsSeries(m_sma20, true);
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CGranvilleLogic::~CGranvilleLogic()
{
   if(m_handleSMA200 != INVALID_HANDLE) IndicatorRelease(m_handleSMA200);
   if(m_handleEMA100 != INVALID_HANDLE) IndicatorRelease(m_handleEMA100);
   if(m_handleSMA20 != INVALID_HANDLE) IndicatorRelease(m_handleSMA20);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CGranvilleLogic::Initialize(string symbol,
                                  ENUM_TIMEFRAMES timeframe,
                                  int sma200,
                                  int ema100,
                                  int sma20,
                                  double touchTolerance,
                                  double deviationPips)
{
   m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   m_timeframe = timeframe;
   m_sma200Period = sma200;
   m_ema100Period = ema100;
   m_sma20Period = sma20;
   m_maTouchTolerance = touchTolerance;
   m_maDeviationPips = deviationPips;

   // MAインジケータの作成
   m_handleSMA200 = iMA(m_symbol, m_timeframe, m_sma200Period, 0, MODE_SMA, PRICE_CLOSE);
   m_handleEMA100 = iMA(m_symbol, m_timeframe, m_ema100Period, 0, MODE_EMA, PRICE_CLOSE);
   m_handleSMA20 = iMA(m_symbol, m_timeframe, m_sma20Period, 0, MODE_SMA, PRICE_CLOSE);

   if(m_handleSMA200 == INVALID_HANDLE || m_handleEMA100 == INVALID_HANDLE || m_handleSMA20 == INVALID_HANDLE)
   {
      if(m_enableLog) LogDebug("Failed to create MA indicators");
      return false;
   }

   if(m_enableLog)
   {
      LogDebug(StringFormat("GranvilleLogic initialized: Symbol=%s, TF=%d, SMA200=%d, EMA100=%d, SMA20=%d",
               m_symbol, m_timeframe, m_sma200Period, m_ema100Period, m_sma20Period));
   }

   return true;
}

//+------------------------------------------------------------------+
//| MA値を更新                                                        |
//+------------------------------------------------------------------+
bool CGranvilleLogic::UpdateMAValues(int bars)
{
   if(CopyBuffer(m_handleSMA200, 0, 0, bars, m_sma200) != bars) return false;
   if(CopyBuffer(m_handleEMA100, 0, 0, bars, m_ema100) != bars) return false;
   if(CopyBuffer(m_handleSMA20, 0, 0, bars, m_sma20) != bars) return false;
   return true;
}

//+------------------------------------------------------------------+
//| MAの傾きを計算                                                    |
//+------------------------------------------------------------------+
double CGranvilleLogic::GetMASlope(double &maArray[], int bars)
{
   if(ArraySize(maArray) < bars) return 0;

   double sum = 0;
   for(int i = 0; i < bars - 1; i++)
   {
      sum += maArray[i] - maArray[i + 1];
   }

   return PriceToPips(sum / (bars - 1), m_symbol);
}

//+------------------------------------------------------------------+
//| 価格がMAに近いか                                                  |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsPriceNearMA(double price, double maValue)
{
   double distancePips = MathAbs(PriceToPips(price - maValue, m_symbol));
   return distancePips <= m_maTouchTolerance;
}

//+------------------------------------------------------------------+
//| 価格がMAより上か                                                  |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsPriceAboveMA(double price, double maValue)
{
   return price > maValue;
}

//+------------------------------------------------------------------+
//| 価格がMAより下か                                                  |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsPriceBelowMA(double price, double maValue)
{
   return price < maValue;
}

//+------------------------------------------------------------------+
//| グランビルパターンを検出                                          |
//+------------------------------------------------------------------+
ENUM_GRANVILLE_PATTERN CGranvilleLogic::DetectPattern()
{
   if(!UpdateMAValues(20))
      return GRANVILLE_NONE;

   // 現在の価格
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double price = (bid + ask) / 2;

   // 前バーのデータ
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, m_timeframe, 0, 5, rates) < 5)
      return GRANVILLE_NONE;

   double close1 = rates[1].close;  // 1本前の終値
   double close2 = rates[2].close;  // 2本前の終値

   // MA値
   double sma200_0 = m_sma200[0];
   double sma200_1 = m_sma200[1];
   double ema100_0 = m_ema100[0];
   double ema100_1 = m_ema100[1];

   // MAの傾き
   double sma200Slope = GetMASlope(m_sma200, m_maSlopeBars);
   double ema100Slope = GetMASlope(m_ema100, m_maSlopeBars);

   // ★グランビル買い3: MA上昇中、価格がMAに接近し反発（押し目買い）- 最重要
   // 200SMAまたは100EMAに引き付けて買い
   if(sma200Slope > m_maSlopeThreshold)  // SMA200上昇中
   {
      // 価格がSMA200に接近して反発
      if(IsPriceNearMA(rates[1].low, sma200_1) ||
         IsPriceNearMA(rates[2].low, m_sma200[2]))
      {
         // 現在の足で反発の兆候（下ヒゲ、または陽線）
         if(price > close1 && close1 > rates[1].low)
         {
            if(m_enableLog) LogDebug("Granville BUY3 detected: Pullback to SMA200 with bounce");
            return GRANVILLE_BUY_3;
         }
      }
   }

   if(ema100Slope > m_maSlopeThreshold)  // EMA100上昇中
   {
      // 価格がEMA100に接近して反発
      if(IsPriceNearMA(rates[1].low, ema100_1) ||
         IsPriceNearMA(rates[2].low, m_ema100[2]))
      {
         if(price > close1 && close1 > rates[1].low)
         {
            if(m_enableLog) LogDebug("Granville BUY3 detected: Pullback to EMA100 with bounce");
            return GRANVILLE_BUY_3;
         }
      }
   }

   // ★グランビル売り3: MA下降中、価格がMAに接近し反落（戻り売り）- 最重要
   if(sma200Slope < -m_maSlopeThreshold)  // SMA200下降中
   {
      // 価格がSMA200に接近して反落
      if(IsPriceNearMA(rates[1].high, sma200_1) ||
         IsPriceNearMA(rates[2].high, m_sma200[2]))
      {
         // 現在の足で反落の兆候（上ヒゲ、または陰線）
         if(price < close1 && close1 < rates[1].high)
         {
            if(m_enableLog) LogDebug("Granville SELL3 detected: Rally to SMA200 with rejection");
            return GRANVILLE_SELL_3;
         }
      }
   }

   if(ema100Slope < -m_maSlopeThreshold)  // EMA100下降中
   {
      // 価格がEMA100に接近して反落
      if(IsPriceNearMA(rates[1].high, ema100_1) ||
         IsPriceNearMA(rates[2].high, m_ema100[2]))
      {
         if(price < close1 && close1 < rates[1].high)
         {
            if(m_enableLog) LogDebug("Granville SELL3 detected: Rally to EMA100 with rejection");
            return GRANVILLE_SELL_3;
         }
      }
   }

   // グランビル買い1: MA下降→上昇転換、価格がMAを上抜け
   if(sma200Slope > 0 && m_sma200[5] > m_sma200[3])  // 傾きが負から正へ
   {
      if(close2 < m_sma200[2] && close1 > sma200_1)  // MAを上抜け
      {
         if(m_enableLog) LogDebug("Granville BUY1 detected: MA turning up with price crossover");
         return GRANVILLE_BUY_1;
      }
   }

   // グランビル売り1: MA上昇→下降転換、価格がMAを下抜け
   if(sma200Slope < 0 && m_sma200[5] < m_sma200[3])  // 傾きが正から負へ
   {
      if(close2 > m_sma200[2] && close1 < sma200_1)  // MAを下抜け
      {
         if(m_enableLog) LogDebug("Granville SELL1 detected: MA turning down with price crossover");
         return GRANVILLE_SELL_1;
      }
   }

   // グランビル買い2: MA上昇中、価格がMA下抜け後再上抜け
   if(sma200Slope > m_maSlopeThreshold)
   {
      if(m_sma200[3] < rates[3].close &&  // 3本前はMA上
         m_sma200[2] > rates[2].close &&  // 2本前はMA下（一時的に下抜け）
         sma200_1 < close1)               // 1本前で再上抜け
      {
         if(m_enableLog) LogDebug("Granville BUY2 detected: Retest and recross above rising MA");
         return GRANVILLE_BUY_2;
      }
   }

   // グランビル売り2: MA下降中、価格がMA上抜け後再下抜け
   if(sma200Slope < -m_maSlopeThreshold)
   {
      if(m_sma200[3] > rates[3].close &&  // 3本前はMA下
         m_sma200[2] < rates[2].close &&  // 2本前はMA上（一時的に上抜け）
         sma200_1 > close1)               // 1本前で再下抜け
      {
         if(m_enableLog) LogDebug("Granville SELL2 detected: Retest and recross below falling MA");
         return GRANVILLE_SELL_2;
      }
   }

   return GRANVILLE_NONE;
}

//+------------------------------------------------------------------+
//| シグナル方向を取得                                                |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIRECTION CGranvilleLogic::GetSignalDirection()
{
   ENUM_GRANVILLE_PATTERN pattern = DetectPattern();

   switch(pattern)
   {
      case GRANVILLE_BUY_1:
      case GRANVILLE_BUY_2:
      case GRANVILLE_BUY_3:
      case GRANVILLE_BUY_4:
         return SIGNAL_BUY;

      case GRANVILLE_SELL_1:
      case GRANVILLE_SELL_2:
      case GRANVILLE_SELL_3:
      case GRANVILLE_SELL_4:
         return SIGNAL_SELL;

      default:
         return SIGNAL_NONE;
   }
}

//+------------------------------------------------------------------+
//| シグナル強度を取得                                                |
//+------------------------------------------------------------------+
double CGranvilleLogic::GetSignalStrength()
{
   ENUM_GRANVILLE_PATTERN pattern = DetectPattern();

   // パターン3（押し目・戻り）が最も信頼性が高い
   switch(pattern)
   {
      case GRANVILLE_BUY_3:
      case GRANVILLE_SELL_3:
         return 0.9;  // 押し目・戻りは高信頼度

      case GRANVILLE_BUY_1:
      case GRANVILLE_SELL_1:
         return 0.7;  // 転換点は中程度

      case GRANVILLE_BUY_2:
      case GRANVILLE_SELL_2:
         return 0.6;  // 再クロスは中程度

      case GRANVILLE_BUY_4:
      case GRANVILLE_SELL_4:
         return 0.4;  // 逆張りは低信頼度

      default:
         return 0.0;
   }
}

//+------------------------------------------------------------------+
//| パターン説明を取得                                                |
//+------------------------------------------------------------------+
string CGranvilleLogic::GetPatternDescription(ENUM_GRANVILLE_PATTERN pattern)
{
   switch(pattern)
   {
      case GRANVILLE_BUY_1:  return "Granville Buy1: MA turning up crossover";
      case GRANVILLE_BUY_2:  return "Granville Buy2: Retest and recross above MA";
      case GRANVILLE_BUY_3:  return "Granville Buy3: Pullback bounce off rising MA";
      case GRANVILLE_BUY_4:  return "Granville Buy4: Oversold bounce (counter-trend)";
      case GRANVILLE_SELL_1: return "Granville Sell1: MA turning down crossover";
      case GRANVILLE_SELL_2: return "Granville Sell2: Retest and recross below MA";
      case GRANVILLE_SELL_3: return "Granville Sell3: Rally rejection at falling MA";
      case GRANVILLE_SELL_4: return "Granville Sell4: Overbought reversal (counter-trend)";
      default:               return "No pattern";
   }
}

//+------------------------------------------------------------------+
//| MA値取得                                                          |
//+------------------------------------------------------------------+
double CGranvilleLogic::GetSMA200(int shift)
{
   if(!UpdateMAValues(shift + 1)) return 0;
   if(shift >= ArraySize(m_sma200)) return 0;
   return m_sma200[shift];
}

double CGranvilleLogic::GetEMA100(int shift)
{
   if(!UpdateMAValues(shift + 1)) return 0;
   if(shift >= ArraySize(m_ema100)) return 0;
   return m_ema100[shift];
}

double CGranvilleLogic::GetSMA20(int shift)
{
   if(!UpdateMAValues(shift + 1)) return 0;
   if(shift >= ArraySize(m_sma20)) return 0;
   return m_sma20[shift];
}

//+------------------------------------------------------------------+
//| SMA200上昇中か                                                    |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsSMA200Rising()
{
   if(!UpdateMAValues(m_maSlopeBars)) return false;
   return GetMASlope(m_sma200, m_maSlopeBars) > m_maSlopeThreshold;
}

//+------------------------------------------------------------------+
//| SMA200下降中か                                                    |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsSMA200Falling()
{
   if(!UpdateMAValues(m_maSlopeBars)) return false;
   return GetMASlope(m_sma200, m_maSlopeBars) < -m_maSlopeThreshold;
}

//+------------------------------------------------------------------+
//| EMA100上昇中か                                                    |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsEMA100Rising()
{
   if(!UpdateMAValues(m_maSlopeBars)) return false;
   return GetMASlope(m_ema100, m_maSlopeBars) > m_maSlopeThreshold;
}

//+------------------------------------------------------------------+
//| EMA100下降中か                                                    |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsEMA100Falling()
{
   if(!UpdateMAValues(m_maSlopeBars)) return false;
   return GetMASlope(m_ema100, m_maSlopeBars) < -m_maSlopeThreshold;
}

//+------------------------------------------------------------------+
//| MA収束中か                                                        |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsMAConverging()
{
   if(!UpdateMAValues(10)) return false;

   double distanceCurrent = MathAbs(m_sma200[0] - m_ema100[0]);
   double distancePast = MathAbs(m_sma200[5] - m_ema100[5]);

   return distanceCurrent < distancePast;
}

//+------------------------------------------------------------------+
//| 価格が長期MAに近いか                                              |
//+------------------------------------------------------------------+
bool CGranvilleLogic::IsPriceNearLongMA()
{
   if(!UpdateMAValues(1)) return false;

   double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   return IsPriceNearMA(price, m_sma200[0]) || IsPriceNearMA(price, m_ema100[0]);
}

//+------------------------------------------------------------------+
//| トレンド方向を取得                                                |
//+------------------------------------------------------------------+
int CGranvilleLogic::GetTrendDirection()
{
   if(!UpdateMAValues(10)) return 0;

   double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // 価格が両MAより上 & 両MA上昇中 = 上昇トレンド
   if(price > m_sma200[0] && price > m_ema100[0])
   {
      if(IsSMA200Rising() && IsEMA100Rising())
         return 1;
   }

   // 価格が両MAより下 & 両MA下降中 = 下降トレンド
   if(price < m_sma200[0] && price < m_ema100[0])
   {
      if(IsSMA200Falling() && IsEMA100Falling())
         return -1;
   }

   return 0;  // レンジまたは不明
}

#endif // GRANVILLE_LOGIC_MQH
