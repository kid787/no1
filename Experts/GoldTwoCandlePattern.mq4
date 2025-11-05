//+------------------------------------------------------------------+
//|                                      GoldTwoCandlePattern.mq4    |
//|                                                                  |
//|   ゴールド用2本ローソク足パターンEA                                 |
//|   陰線→陽線パターンでエントリー                                     |
//+------------------------------------------------------------------+
#property copyright "Gold Two Candle Pattern EA"
#property link      ""
#property version   "1.00"
#property strict

//--- 入力パラメータ
input double   RiskPercent = 2.0;           // 資金リスク率(%)
input double   RiskReward = 1.5;            // リスクリワード比率
input int      MaxPositions = 2;            // 最大同時保有ポジション数
input double   MinBodyPips = 5.0;           // 実体の最小サイズ(pips)
input double   MinLowDiffPips = 3.0;        // 2本目の安値が1本目より長い最小差(pips)
input bool     UseWinRateFilter = true;     // 勝率向上フィルター使用
input bool     UseTrailingStop = true;      // トレーリングストップ使用
input int      TrailingSMA_Period = 20;     // トレーリングストップ用SMA期間
input bool     LongOnly = true;             // ロングのみ（推奨）
input int      MagicNumber = 12345;         // マジックナンバー
input int      Slippage = 30;               // スリッページ(ポイント)

//--- グローバル変数
datetime lastBarTime = 0;                   // 最後のバー時間（1分足）
double   pointValue;                        // 1ポイントの値
double   pipValue;                          // 1pipの値

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // 通貨ペア確認
   if(Symbol() != "XAUUSD" && Symbol() != "GOLD" && Symbol() != "XAUUSD.a")
   {
      Alert("警告: このEAはゴールド(XAUUSD)用に設計されています。現在のシンボル: ", Symbol());
   }

   // タイムフレーム確認
   if(Period() != PERIOD_M1)
   {
      Alert("警告: このEAは1分足での使用を推奨します。現在: ", Period(), "分足");
   }

   // ポイント値の計算
   pointValue = Point;
   if(Digits == 3 || Digits == 5)
      pipValue = pointValue * 10;
   else
      pipValue = pointValue;

   Print("EA初期化完了 - ゴールド2本ローソク足パターンEA");
   Print("リスク率: ", RiskPercent, "%, リスクリワード: ", RiskReward);
   Print("最大ポジション数: ", MaxPositions);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA停止 - 理由: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // 新しいバーの確認（1分足）
   if(Time[0] == lastBarTime)
      return;

   lastBarTime = Time[0];

   // トレーリングストップの更新
   if(UseTrailingStop)
      UpdateTrailingStop();

   // 既存ポジションの利確チェック
   CheckProfitExit();

   // 現在のポジション数確認
   int currentPositions = CountOpenPositions();
   if(currentPositions >= MaxPositions)
      return;

   // エントリーシグナルチェック
   if(LongOnly)
   {
      if(CheckLongSignal())
      {
         OpenBuyOrder();
      }
   }
   else
   {
      if(CheckShortSignal())
      {
         OpenSellOrder();
      }
   }
}

//+------------------------------------------------------------------+
//| ロングシグナルチェック                                               |
//+------------------------------------------------------------------+
bool CheckLongSignal()
{
   // バー1: 1本前（完成したバー）
   // バー2: 2本前（完成したバー）

   double open1 = iOpen(NULL, PERIOD_M1, 1);
   double close1 = iClose(NULL, PERIOD_M1, 1);
   double high1 = iHigh(NULL, PERIOD_M1, 1);
   double low1 = iLow(NULL, PERIOD_M1, 1);

   double open2 = iOpen(NULL, PERIOD_M1, 2);
   double close2 = iClose(NULL, PERIOD_M1, 2);
   double high2 = iHigh(NULL, PERIOD_M1, 2);
   double low2 = iLow(NULL, PERIOD_M1, 2);

   // 条件1: 2本目（バー2）が陰線、1本目（バー1）が陽線
   bool isBar2Bearish = close2 < open2;
   bool isBar1Bullish = close1 > open1;

   if(!isBar2Bearish || !isBar1Bullish)
      return false;

   // 条件2: 1本目の安値（ひげ）が2本目より長い（下に突き抜けている）
   double lowDiff = (low2 - low1) / pipValue;
   if(lowDiff < MinLowDiffPips)
   {
      Print("エントリー見送り: 安値の差が小さい (", DoubleToStr(lowDiff, 2), " pips < ", MinLowDiffPips, " pips)");
      return false;
   }

   // 条件3: 実体サイズチェック（どちらかが小さすぎる場合は見送り）
   double body1 = MathAbs(close1 - open1) / pipValue;
   double body2 = MathAbs(close2 - open2) / pipValue;

   if(body1 < MinBodyPips || body2 < MinBodyPips)
   {
      Print("エントリー見送り: 実体が小さい (バー1: ", DoubleToStr(body1, 2), " pips, バー2: ", DoubleToStr(body2, 2), " pips)");
      return false;
   }

   // 条件4: 勝率向上フィルター
   if(UseWinRateFilter)
   {
      // 1本目の高値が2本目の高値より低い
      bool isHigh1Lower = high1 < high2;

      // 1本目の上ひげが短い
      double upperWick1 = (high1 - MathMax(open1, close1)) / pipValue;
      double upperWick2 = (high2 - MathMax(open2, close2)) / pipValue;
      bool isUpperWick1Short = upperWick1 < upperWick2;

      // どちらか一つでも満たせば良い
      if(!isHigh1Lower && !isUpperWick1Short)
      {
         Print("エントリー見送り: 勝率向上フィルター不合格");
         return false;
      }
   }

   // 1時間足のレジスタンスゾーンチェック
   if(!CheckResistanceZone())
   {
      Print("エントリー見送り: レジスタンスゾーン接近");
      return false;
   }

   Print("ロングシグナル検出!");
   return true;
}

//+------------------------------------------------------------------+
//| ショートシグナルチェック（逆パターン）                                |
//+------------------------------------------------------------------+
bool CheckShortSignal()
{
   // 売りは買いの逆だが、トレンド継続が弱いため推奨しない
   // 必要に応じて実装

   double open1 = iOpen(NULL, PERIOD_M1, 1);
   double close1 = iClose(NULL, PERIOD_M1, 1);
   double high1 = iHigh(NULL, PERIOD_M1, 1);
   double low1 = iLow(NULL, PERIOD_M1, 1);

   double open2 = iOpen(NULL, PERIOD_M1, 2);
   double close2 = iClose(NULL, PERIOD_M1, 2);
   double high2 = iHigh(NULL, PERIOD_M1, 2);
   double low2 = iLow(NULL, PERIOD_M1, 2);

   // 2本目が陽線、1本目が陰線
   bool isBar2Bullish = close2 > open2;
   bool isBar1Bearish = close1 < open1;

   if(!isBar2Bullish || !isBar1Bearish)
      return false;

   // 1本目の高値が2本目より高い
   double highDiff = (high1 - high2) / pipValue;
   if(highDiff < MinLowDiffPips)
      return false;

   // 実体サイズチェック
   double body1 = MathAbs(close1 - open1) / pipValue;
   double body2 = MathAbs(close2 - open2) / pipValue;

   if(body1 < MinBodyPips || body2 < MinBodyPips)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| レジスタンスゾーンチェック（1時間足）                                |
//+------------------------------------------------------------------+
bool CheckResistanceZone()
{
   // 1時間足の直近高値を取得
   double h1_high1 = iHigh(NULL, PERIOD_H1, 1);
   double h1_high2 = iHigh(NULL, PERIOD_H1, 2);
   double h1_high3 = iHigh(NULL, PERIOD_H1, 3);

   double resistanceLevel = MathMax(h1_high1, MathMax(h1_high2, h1_high3));
   double currentPrice = Ask;

   // 現在価格がレジスタンスの5pips以内なら見送り
   double distanceToResistance = (resistanceLevel - currentPrice) / pipValue;

   if(distanceToResistance < 5.0)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| 買いオーダーを開く                                                  |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
   double price = Ask;

   // ストップロス: 1本目の安値（ひげの先端）
   double stopLoss = iLow(NULL, PERIOD_M1, 1);

   // 1時間足の直近安値も確認（抵抗ゾーン直近安値）
   double h1_low1 = iLow(NULL, PERIOD_H1, 1);
   double h1_low2 = iLow(NULL, PERIOD_H1, 2);
   double supportLevel = MathMin(h1_low1, h1_low2);

   // より安全な方を選択
   stopLoss = MathMin(stopLoss, supportLevel);

   // テイクプロフィット: リスクリワード1.5
   double riskPips = (price - stopLoss) / pipValue;
   double rewardPips = riskPips * RiskReward;
   double takeProfit = price + (rewardPips * pipValue);

   // ロットサイズ計算（資金の2%）
   double lotSize = CalculateLotSize(price, stopLoss);

   // 正規化
   lotSize = NormalizeLots(lotSize);
   stopLoss = NormalizeDouble(stopLoss, Digits);
   takeProfit = NormalizeDouble(takeProfit, Digits);

   Print("買い注文準備 - 価格: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit, ", ロット: ", lotSize);

   int ticket = OrderSend(Symbol(), OP_BUY, lotSize, price, Slippage, stopLoss, takeProfit,
                          "Gold 2-Candle Long", MagicNumber, 0, clrGreen);

   if(ticket > 0)
   {
      Print("買い注文成功 - チケット: ", ticket);
   }
   else
   {
      Print("買い注文失敗 - エラー: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| 売りオーダーを開く                                                  |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
   double price = Bid;

   // ストップロス: 1本目の高値（ひげの先端）
   double stopLoss = iHigh(NULL, PERIOD_M1, 1);

   // テイクプロフィット: リスクリワード1.5
   double riskPips = (stopLoss - price) / pipValue;
   double rewardPips = riskPips * RiskReward;
   double takeProfit = price - (rewardPips * pipValue);

   // ロットサイズ計算
   double lotSize = CalculateLotSize(stopLoss, price);

   // 正規化
   lotSize = NormalizeLots(lotSize);
   stopLoss = NormalizeDouble(stopLoss, Digits);
   takeProfit = NormalizeDouble(takeProfit, Digits);

   int ticket = OrderSend(Symbol(), OP_SELL, lotSize, price, Slippage, stopLoss, takeProfit,
                          "Gold 2-Candle Short", MagicNumber, 0, clrRed);

   if(ticket > 0)
   {
      Print("売り注文成功 - チケット: ", ticket);
   }
   else
   {
      Print("売り注文失敗 - エラー: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ロットサイズ計算（資金の2%）                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double accountBalance = AccountBalance();
   double riskAmount = accountBalance * (RiskPercent / 100.0);

   double pipRisk = MathAbs(entryPrice - stopLoss) / pipValue;

   // ゴールドの1ロットの1pipの価値
   // 通常、ゴールドは1ロット = 100オンス
   // 1pip = 0.01ドル/オンス = 1ドル/ロット
   double pipValuePerLot = MarketInfo(Symbol(), MODE_TICKVALUE) * (pipValue / pointValue);

   if(pipValuePerLot == 0 || pipRisk == 0)
      return 0.01; // デフォルト最小ロット

   double lotSize = riskAmount / (pipRisk * pipValuePerLot);

   return lotSize;
}

//+------------------------------------------------------------------+
//| ロット数の正規化                                                    |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   lots = MathRound(lots / lotStep) * lotStep;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| 現在のポジション数をカウント                                        |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| トレーリングストップの更新（20SMA基準）                              |
//+------------------------------------------------------------------+
void UpdateTrailingStop()
{
   double sma = iMA(NULL, PERIOD_M1, TrailingSMA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
            continue;

         if(OrderType() == OP_BUY)
         {
            // ローソク足実体が20SMAを下抜けたらストップロスを更新
            double currentClose = iClose(NULL, PERIOD_M1, 0);
            double currentOpen = iOpen(NULL, PERIOD_M1, 0);
            double bodyBottom = MathMin(currentOpen, currentClose);

            // 実体がSMAより下にある場合
            if(bodyBottom < sma)
            {
               double newSL = NormalizeDouble(sma, Digits);

               // 新しいSLが現在のSLより有利な場合のみ更新
               if(newSL > OrderStopLoss() && newSL < OrderClosePrice())
               {
                  bool result = OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue);
                  if(result)
                     Print("トレーリングストップ更新 - チケット: ", OrderTicket(), ", 新SL: ", newSL);
               }
            }
         }
         else if(OrderType() == OP_SELL)
         {
            // 売りの場合は逆
            double currentClose = iClose(NULL, PERIOD_M1, 0);
            double currentOpen = iOpen(NULL, PERIOD_M1, 0);
            double bodyTop = MathMax(currentOpen, currentClose);

            if(bodyTop > sma)
            {
               double newSL = NormalizeDouble(sma, Digits);

               if(newSL < OrderStopLoss() && newSL > OrderClosePrice())
               {
                  bool result = OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue);
                  if(result)
                     Print("トレーリングストップ更新 - チケット: ", OrderTicket(), ", 新SL: ", newSL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 利益時の陰線実体完成での利確チェック                                 |
//+------------------------------------------------------------------+
void CheckProfitExit()
{
   // 1本前のバーが陰線かチェック
   double open1 = iOpen(NULL, PERIOD_M1, 1);
   double close1 = iClose(NULL, PERIOD_M1, 1);
   bool isBearishCandle = close1 < open1;

   if(!isBearishCandle)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
            continue;

         if(OrderType() == OP_BUY)
         {
            // 利益が出ているかチェック
            double profit = OrderProfit() + OrderSwap() + OrderCommission();

            if(profit > 0)
            {
               // 利確
               bool result = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
               if(result)
                  Print("陰線実体完成で利確 - チケット: ", OrderTicket(), ", 利益: ", profit);
            }
            else
            {
               Print("陰線検出だが損失中のため利確見送り - チケット: ", OrderTicket(), ", 損益: ", profit);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
