//+------------------------------------------------------------------+
//|                                            TechnicalSignals.mqh |
//|                          Technical Analysis Signal Detection     |
//+------------------------------------------------------------------+
#property copyright "Technical Signals Module"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Price Action Patterns                                            |
//+------------------------------------------------------------------+
enum ENUM_PRICE_ACTION
{
   PA_NONE = 0,
   PA_BULLISH_ENGULFING = 1,      // 強気のつつみ足
   PA_BEARISH_ENGULFING = 2,      // 弱気のつつみ足
   PA_BULLISH_PIN_BAR = 3,        // 強気のピンバー
   PA_BEARISH_PIN_BAR = 4,        // 弱気のピンバー
   PA_INSIDE_BAR = 5,             // インサイドバー
   PA_BULLISH_DOJI = 6,           // 強気の同時線
   PA_BEARISH_DOJI = 7            // 弱気の同時線
};

//+------------------------------------------------------------------+
//| Granville's Law Signals                                          |
//+------------------------------------------------------------------+
enum ENUM_GRANVILLE_SIGNAL
{
   GRANV_NONE = 0,
   GRANV_BUY_1 = 1,    // 買い1: MAが下降から上昇に転じ、価格がMAを上抜け
   GRANV_BUY_2 = 2,    // 買い2: MA上昇中、価格がMAを一時的に下回るが反発
   GRANV_BUY_3 = 3,    // 買い3: MA上昇中、価格がMAの上にあり、MA近くまで下降後反発
   GRANV_BUY_4 = 4,    // 買い4: MA下降中、価格がMAから大きく乖離して下落
   GRANV_SELL_1 = -1,  // 売り1: MAが上昇から下降に転じ、価格がMAを下抜け
   GRANV_SELL_2 = -2,  // 売り2: MA下降中、価格がMAを一時的に上回るが反落
   GRANV_SELL_3 = -3,  // 売り3: MA下降中、価格がMAの下にあり、MA近くまで上昇後反落
   GRANV_SELL_4 = -4   // 売り4: MA上昇中、価格がMAから大きく乖離して上昇
};

//+------------------------------------------------------------------+
//| Technical Signals Class                                          |
//+------------------------------------------------------------------+
class CTechnicalSignals
{
private:
   string   m_Symbol;
   ENUM_TIMEFRAMES m_Timeframe;

   // MA handles
   int      m_Handle_SMA200;
   int      m_Handle_EMA100;
   int      m_Handle_SMA20;
   int      m_Handle_ATR;         // v2.1: ATR追加

   // Buffers
   double   m_SMA200[];
   double   m_EMA100[];
   double   m_SMA20[];
   double   m_ATR[];              // v2.1: ATRバッファ

public:
   //--- コンストラクタ
   CTechnicalSignals(string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_M5)
   {
      m_Symbol = (symbol == NULL) ? _Symbol : symbol;
      m_Timeframe = timeframe;

      // インジケーターハンドルの作成
      m_Handle_SMA200 = iMA(m_Symbol, m_Timeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
      m_Handle_EMA100 = iMA(m_Symbol, m_Timeframe, 100, 0, MODE_EMA, PRICE_CLOSE);
      m_Handle_SMA20 = iMA(m_Symbol, m_Timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
      m_Handle_ATR = iATR(m_Symbol, m_Timeframe, 14);  // v2.1: ATR(14)追加

      ArraySetAsSeries(m_SMA200, true);
      ArraySetAsSeries(m_EMA100, true);
      ArraySetAsSeries(m_SMA20, true);
      ArraySetAsSeries(m_ATR, true);  // v2.1
   }

   //--- デストラクタ
   ~CTechnicalSignals()
   {
      if(m_Handle_SMA200 != INVALID_HANDLE) IndicatorRelease(m_Handle_SMA200);
      if(m_Handle_EMA100 != INVALID_HANDLE) IndicatorRelease(m_Handle_EMA100);
      if(m_Handle_SMA20 != INVALID_HANDLE) IndicatorRelease(m_Handle_SMA20);
      if(m_Handle_ATR != INVALID_HANDLE) IndicatorRelease(m_Handle_ATR);  // v2.1
   }

   //--- MAデータの更新
   bool UpdateIndicators()
   {
      if(CopyBuffer(m_Handle_SMA200, 0, 0, 10, m_SMA200) <= 0) return false;
      if(CopyBuffer(m_Handle_EMA100, 0, 0, 10, m_EMA100) <= 0) return false;
      if(CopyBuffer(m_Handle_SMA20, 0, 0, 10, m_SMA20) <= 0) return false;
      if(CopyBuffer(m_Handle_ATR, 0, 0, 10, m_ATR) <= 0) return false;  // v2.1

      return true;
   }

   //--- MA値の取得
   double GetSMA200(int shift = 0) { return m_SMA200[shift]; }
   double GetEMA100(int shift = 0) { return m_EMA100[shift]; }
   double GetSMA20(int shift = 0) { return m_SMA20[shift]; }

   //--- グランビルの法則チェック（200SMA使用）
   ENUM_GRANVILLE_SIGNAL CheckGranvilleSignal()
   {
      if(!UpdateIndicators()) return GRANV_NONE;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_Symbol, m_Timeframe, 0, 10, rates) <= 0)
         return GRANV_NONE;

      double currentPrice = rates[0].close;
      double prevPrice = rates[1].close;

      double ma0 = m_SMA200[0];
      double ma1 = m_SMA200[1];
      double ma2 = m_SMA200[2];

      // MAの傾き
      bool maRising = (ma0 > ma1) && (ma1 > ma2);
      bool maFalling = (ma0 < ma1) && (ma1 < ma2);
      bool maTurningUp = (ma0 > ma1) && (ma1 <= ma2);
      bool maTurningDown = (ma0 < ma1) && (ma1 >= ma2);

      // 価格とMAの位置関係
      bool priceAboveMA = currentPrice > ma0;
      bool priceBelowMA = currentPrice < ma0;
      bool priceCrossedAbove = (prevPrice <= ma1) && (currentPrice > ma0);
      bool priceCrossedBelow = (prevPrice >= ma1) && (currentPrice < ma0);

      // 乖離率の計算
      double divergence = MathAbs((currentPrice - ma0) / ma0) * 100.0;

      // 買い1: MAが下降から上昇に転じ、価格がMAを上抜け
      if(maTurningUp && priceCrossedAbove)
         return GRANV_BUY_1;

      // 買い2: MA上昇中、価格がMAを一時的に下回るが反発
      if(maRising && priceCrossedAbove && prevPrice < ma1)
         return GRANV_BUY_2;

      // 買い3: MA上昇中、価格がMAの上にあり、MA近くまで下降後反発
      if(maRising && priceAboveMA && divergence < 0.5 && rates[1].low < ma1 && currentPrice > prevPrice)
         return GRANV_BUY_3;

      // 買い4: MA下降中、価格がMAから大きく乖離して下落（逆張り）
      if(maFalling && priceBelowMA && divergence > 2.0)
         return GRANV_BUY_4;

      // 売り1: MAが上昇から下降に転じ、価格がMAを下抜け
      if(maTurningDown && priceCrossedBelow)
         return GRANV_SELL_1;

      // 売り2: MA下降中、価格がMAを一時的に上回るが反落
      if(maFalling && priceCrossedBelow && prevPrice > ma1)
         return GRANV_SELL_2;

      // 売り3: MA下降中、価格がMAの下にあり、MA近くまで上昇後反落
      if(maFalling && priceBelowMA && divergence < 0.5 && rates[1].high > ma1 && currentPrice < prevPrice)
         return GRANV_SELL_3;

      // 売り4: MA上昇中、価格がMAから大きく乖離して上昇（逆張り）
      if(maRising && priceAboveMA && divergence > 2.0)
         return GRANV_SELL_4;

      return GRANV_NONE;
   }

   //--- EMA100を使った引き付けシグナル
   bool CheckEMAPullback(bool isBuy)
   {
      if(!UpdateIndicators()) return false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_Symbol, m_Timeframe, 0, 5, rates) <= 0)
         return false;

      double currentPrice = rates[0].close;
      double ema = m_EMA100[0];

      // EMAへの引き付け判定（EMAから±1%以内）
      double pullbackThreshold = 0.01;
      double distance = MathAbs((currentPrice - ema) / ema);

      if(distance > pullbackThreshold)
         return false;

      if(isBuy)
      {
         // 買いの場合：EMAの上で反発
         return (currentPrice > ema) && (rates[1].low <= ema);
      }
      else
      {
         // 売りの場合：EMAの下で反落
         return (currentPrice < ema) && (rates[1].high >= ema);
      }
   }

   //--- プライスアクション検出
   ENUM_PRICE_ACTION DetectPriceAction(int shift = 1)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_Symbol, m_Timeframe, 0, shift + 3, rates) < shift + 3)
         return PA_NONE;

      double open1 = rates[shift].open;
      double close1 = rates[shift].close;
      double high1 = rates[shift].high;
      double low1 = rates[shift].low;
      double body1 = MathAbs(close1 - open1);
      double range1 = high1 - low1;

      double open2 = rates[shift+1].open;
      double close2 = rates[shift+1].close;
      double high2 = rates[shift+1].high;
      double low2 = rates[shift+1].low;
      double body2 = MathAbs(close2 - open2);

      // つつみ足パターン
      // 強気のつつみ足
      if(close2 < open2 && close1 > open1 &&
         close1 > open2 && open1 < close2 && body1 > body2 * 1.2)
         return PA_BULLISH_ENGULFING;

      // 弱気のつつみ足
      if(close2 > open2 && close1 < open1 &&
         close1 < open2 && open1 > close2 && body1 > body2 * 1.2)
         return PA_BEARISH_ENGULFING;

      // ピンバー
      double upperWick = high1 - MathMax(open1, close1);
      double lowerWick = MathMin(open1, close1) - low1;

      // 強気のピンバー（下ヒゲが長い）
      if(lowerWick > body1 * 2.0 && lowerWick > upperWick * 2.0)
         return PA_BULLISH_PIN_BAR;

      // 弱気のピンバー（上ヒゲが長い）
      if(upperWick > body1 * 2.0 && upperWick > lowerWick * 2.0)
         return PA_BEARISH_PIN_BAR;

      // インサイドバー
      if(high1 < high2 && low1 > low2)
         return PA_INSIDE_BAR;

      // 同時線（Doji）- 実体が非常に小さい
      if(body1 < range1 * 0.1)
      {
         // 前のローソク足の傾向で判断
         if(close2 < open2) // 前が下降
            return PA_BULLISH_DOJI;
         else if(close2 > open2) // 前が上昇
            return PA_BEARISH_DOJI;
      }

      return PA_NONE;
   }

   //--- 水平線（サポート/レジスタンス）の検出
   bool IsNearHorizontalLevel(bool isSupport, double &levelPrice)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int bars = 100;
      if(CopyRates(m_Symbol, m_Timeframe, 0, bars, rates) < bars)
         return false;

      double currentPrice = rates[0].close;
      double threshold = currentPrice * 0.003; // 0.3%の範囲

      // 直近100本のローソク足から高値・安値を探す
      for(int i = 5; i < bars - 5; i++)
      {
         if(isSupport)
         {
            // サポートライン：直近の安値
            bool isSwingLow = true;
            for(int j = i - 5; j <= i + 5; j++)
            {
               if(j != i && rates[j].low < rates[i].low)
               {
                  isSwingLow = false;
                  break;
               }
            }

            if(isSwingLow && MathAbs(currentPrice - rates[i].low) < threshold)
            {
               levelPrice = rates[i].low;
               return true;
            }
         }
         else
         {
            // レジスタンスライン：直近の高値
            bool isSwingHigh = true;
            for(int j = i - 5; j <= i + 5; j++)
            {
               if(j != i && rates[j].high > rates[i].high)
               {
                  isSwingHigh = false;
                  break;
               }
            }

            if(isSwingHigh && MathAbs(currentPrice - rates[i].high) < threshold)
            {
               levelPrice = rates[i].high;
               return true;
            }
         }
      }

      return false;
   }

   //--- デイリーピボットの計算
   void CalculateDailyPivot(double &pivot, double &r1, double &r2, double &s1, double &s2)
   {
      MqlRates dailyRates[];
      ArraySetAsSeries(dailyRates, true);

      if(CopyRates(m_Symbol, PERIOD_D1, 0, 2, dailyRates) < 2)
      {
         pivot = r1 = r2 = s1 = s2 = 0;
         return;
      }

      double high = dailyRates[1].high;
      double low = dailyRates[1].low;
      double close = dailyRates[1].close;

      pivot = (high + low + close) / 3.0;
      r1 = 2 * pivot - low;
      r2 = pivot + (high - low);
      s1 = 2 * pivot - high;
      s2 = pivot - (high - low);
   }

   //--- ピボット近接チェック
   bool IsNearPivotLevel(double price, double &nearestPivot)
   {
      double pivot, r1, r2, s1, s2;
      CalculateDailyPivot(pivot, r1, r2, s1, s2);

      double threshold = price * 0.002; // 0.2%の範囲
      double pivots[] = {pivot, r1, r2, s1, s2};

      for(int i = 0; i < ArraySize(pivots); i++)
      {
         if(MathAbs(price - pivots[i]) < threshold)
         {
            nearestPivot = pivots[i];
            return true;
         }
      }

      return false;
   }

   //--- 20SMA実体抜けチェック
   bool CheckSMABodyBreak(bool isBuy)
   {
      if(!UpdateIndicators()) return false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_Symbol, m_Timeframe, 0, 3, rates) <= 0)
         return false;

      double sma20 = m_SMA20[0];
      double currentClose = rates[0].close;
      double currentOpen = rates[0].open;
      double prevClose = rates[1].close;

      if(isBuy)
      {
         // 買い：実体がSMAを上抜け
         return (currentClose > sma20 && currentOpen > sma20 && prevClose <= sma20);
      }
      else
      {
         // 売り：実体がSMAを下抜け
         return (currentClose < sma20 && currentOpen < sma20 && prevClose >= sma20);
      }
   }

   //--- ダウ理論に基づく直近高値・安値の取得
   bool GetSwingHighLow(bool isHigh, double &price)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int bars = 50;

      if(CopyRates(m_Symbol, m_Timeframe, 0, bars, rates) < bars)
         return false;

      // スイングハイ/ローを探す（前後5本のローソク足と比較）
      for(int i = 5; i < bars - 5; i++)
      {
         if(isHigh)
         {
            bool isSwingHigh = true;
            for(int j = i - 5; j <= i + 5; j++)
            {
               if(j != i && rates[j].high >= rates[i].high)
               {
                  isSwingHigh = false;
                  break;
               }
            }

            if(isSwingHigh)
            {
               price = rates[i].high;
               return true;
            }
         }
         else
         {
            bool isSwingLow = true;
            for(int j = i - 5; j <= i + 5; j++)
            {
               if(j != i && rates[j].low <= rates[i].low)
               {
                  isSwingLow = false;
                  break;
               }
            }

            if(isSwingLow)
            {
               price = rates[i].low;
               return true;
            }
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| v2.1: ATR値を取得                                                |
   //+------------------------------------------------------------------+
   double GetATR(int shift = 0)
   {
      if(!UpdateIndicators()) return 0.0;
      return m_ATR[shift];
   }

   //+------------------------------------------------------------------+
   //| v2.1: ボラティリティチェック                                      |
   //+------------------------------------------------------------------+
   bool CheckVolatility(double maxATR = 0, double minATR = 0)
   {
      double currentATR = GetATR(0);
      if(currentATR <= 0) return false;

      // 最大ATRチェック（高ボラティリティ回避）
      if(maxATR > 0 && currentATR > maxATR)
      {
         return false;  // ATRが大きすぎる = ボラティリティ高すぎ
      }

      // 最小ATRチェック（低ボラティリティ回避）
      if(minATR > 0 && currentATR < minATR)
      {
         return false;  // ATRが小さすぎる = ボラティリティ低すぎ
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| v2.1: 適正なボラティリティ範囲かチェック                          |
   //+------------------------------------------------------------------+
   bool IsVolatilityNormal()
   {
      double currentATR = GetATR(0);
      if(currentATR <= 0) return false;

      // XAUUSDの通常範囲: ATR 3.0〜15.0ドル程度
      // 3.0未満=動きが少なすぎ、15.0超=乱高下
      double minNormalATR = 3.0;
      double maxNormalATR = 15.0;

      return CheckVolatility(maxNormalATR, minNormalATR);
   }
};
