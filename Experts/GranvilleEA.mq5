//+------------------------------------------------------------------+
//|                                                   GranvilleEA.mq5 |
//|                              Copyright 2025, Granville EA System |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Granville EA System"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

// 入力パラメータ
input string   Symbol_to_Trade = "XAUUSD";        // 取引対象銘柄
input double   Risk_Percent = 2.0;                 // リスク（口座残高の％）
input double   Max_Lot_Size = 10.0;                // 最大ロット数
input int      MA_Period_Mid = 75;                 // H1中期MA期間 (EMA)
input int      MA_Period_Long = 200;               // H1長期MA期間 (EMA)
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H4;   // MTFトレンド確認用時間足
input int      MA_Proximity_Pips = 100;            // MA近接と見なす許容範囲 (Point単位)
input double   TakeProfit_Ratio = 2.0;             // リスクリワード比率
input int      EMA_Short_Period = 20;              // 短期EMA（反発/反落確認用）
input int      Magic_Number = 123456;              // マジックナンバー
input string   EA_Comment = "Granville EA";        // EAコメント
input int      Slippage_Points = 30;               // スリッページ許容値

// グローバル変数
CTrade trade;
int ma75Handle, ma200Handle, mtfMA75Handle, emaShortHandle;
datetime lastBarTime = 0;

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

   // MAハンドルの作成
   ma75Handle = iMA(Symbol_to_Trade, PERIOD_H1, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   ma200Handle = iMA(Symbol_to_Trade, PERIOD_H1, MA_Period_Long, 0, MODE_EMA, PRICE_CLOSE);
   mtfMA75Handle = iMA(Symbol_to_Trade, MTF_Timeframe, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
   emaShortHandle = iMA(Symbol_to_Trade, PERIOD_H1, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(ma75Handle == INVALID_HANDLE || ma200Handle == INVALID_HANDLE ||
      mtfMA75Handle == INVALID_HANDLE || emaShortHandle == INVALID_HANDLE)
   {
      Print("MAハンドルの作成に失敗しました");
      return(INIT_FAILED);
   }

   Print("Granville EA が正常に初期化されました");
   Print("取引銘柄: ", Symbol_to_Trade);
   Print("リスク設定: ", Risk_Percent, "%");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ハンドルの解放
   if(ma75Handle != INVALID_HANDLE) IndicatorRelease(ma75Handle);
   if(ma200Handle != INVALID_HANDLE) IndicatorRelease(ma200Handle);
   if(mtfMA75Handle != INVALID_HANDLE) IndicatorRelease(mtfMA75Handle);
   if(emaShortHandle != INVALID_HANDLE) IndicatorRelease(emaShortHandle);

   Print("Granville EA が終了しました");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 新しいバーの確認
   datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_H1, 0);
   if(currentBarTime == lastBarTime)
      return;

   lastBarTime = currentBarTime;

   // 既存のポジションチェック
   if(PositionSelect(Symbol_to_Trade))
   {
      return; // 既にポジションがある場合は新規エントリーしない
   }

   // トレンド分析
   int trendDirection = AnalyzeTrend();

   if(trendDirection == 0)
   {
      // レンジ相場の場合は取引しない
      return;
   }

   // エントリーシグナルのチェック
   if(trendDirection == 1) // 上昇トレンド
   {
      if(CheckBuySignal())
      {
         ExecuteBuyOrder();
      }
   }
   else if(trendDirection == -1) // 下降トレンド
   {
      if(CheckSellSignal())
      {
         ExecuteSellOrder();
      }
   }
}

//+------------------------------------------------------------------+
//| トレンド分析                                                       |
//+------------------------------------------------------------------+
int AnalyzeTrend()
{
   double mtfMA[], h1MA75[], h1MA200[];
   ArraySetAsSeries(mtfMA, true);
   ArraySetAsSeries(h1MA75, true);
   ArraySetAsSeries(h1MA200, true);

   // MTF MA75のコピー
   if(CopyBuffer(mtfMA75Handle, 0, 0, 25, mtfMA) < 25)
      return 0;

   // H1 MAのコピー
   if(CopyBuffer(ma75Handle, 0, 0, 3, h1MA75) < 3)
      return 0;
   if(CopyBuffer(ma200Handle, 0, 0, 3, h1MA200) < 3)
      return 0;

   // MTFトレンドの判定
   double mtfCurrent = mtfMA[0];
   double mtfPast = mtfMA[20];
   double mtfDiff = mtfCurrent - mtfPast;
   double threshold = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) * 10;

   bool mtfUptrend = mtfDiff > threshold;
   bool mtfDowntrend = mtfDiff < -threshold;

   // H1トレンドの判定
   bool h1MA75Up = (h1MA75[0] > h1MA75[1]) && (h1MA75[1] > h1MA75[2]);
   bool h1MA75Down = (h1MA75[0] < h1MA75[1]) && (h1MA75[1] < h1MA75[2]);

   // トレンド方向の決定
   if(mtfUptrend && h1MA75Up)
      return 1;  // 上昇トレンド
   else if(mtfDowntrend && h1MA75Down)
      return -1; // 下降トレンド
   else
      return 0;  // レンジまたは不明確
}

//+------------------------------------------------------------------+
//| 買いシグナルのチェック（グランビル Rule 3）                           |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
   double close[], ma75[], emaShort[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma75, true);
   ArraySetAsSeries(emaShort, true);

   // 価格とMAデータの取得
   if(CopyClose(Symbol_to_Trade, PERIOD_H1, 0, 5, close) < 5)
      return false;
   if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5)
      return false;
   if(CopyBuffer(emaShortHandle, 0, 0, 3, emaShort) < 3)
      return false;

   double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // Rule 3: 押し目形成の確認
   // 1. 前足がMA75に接近していた
   bool wasNearMA = (close[1] > ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);

   // 2. 現在足がMA75から反発
   bool bounced = (close[0] > ma75[0]) && (close[0] > close[1]);

   // 3. 短期EMAが上向きに転じた（追加フィルター）
   bool emaUp = emaShort[0] > emaShort[1];

   // 4. 価格がMA75の上にある
   bool aboveMA = close[0] > ma75[0];

   // 5. ダウ理論チェック（オプション）: 安値の切り上げ
   bool higherLow = true;
   if(close[2] != 0)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 5, rates) == 5)
      {
         double recentLow = rates[0].low;
         for(int i = 1; i < 5; i++)
         {
            if(rates[i].low < recentLow)
            {
               higherLow = false;
               break;
            }
         }
      }
   }

   return (wasNearMA && bounced && emaUp && aboveMA);
}

//+------------------------------------------------------------------+
//| 売りシグナルのチェック（グランビル Rule 7）                           |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
   double close[], ma75[], emaShort[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma75, true);
   ArraySetAsSeries(emaShort, true);

   // 価格とMAデータの取得
   if(CopyClose(Symbol_to_Trade, PERIOD_H1, 0, 5, close) < 5)
      return false;
   if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5)
      return false;
   if(CopyBuffer(emaShortHandle, 0, 0, 3, emaShort) < 3)
      return false;

   double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // Rule 7: 戻り形成の確認
   // 1. 前足がMA75に接近していた
   bool wasNearMA = (close[1] < ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);

   // 2. 現在足がMA75から反落
   bool bounced = (close[0] < ma75[0]) && (close[0] < close[1]);

   // 3. 短期EMAが下向きに転じた（追加フィルター）
   bool emaDown = emaShort[0] < emaShort[1];

   // 4. 価格がMA75の下にある
   bool belowMA = close[0] < ma75[0];

   // 5. ダウ理論チェック（オプション）: 高値の切り下げ
   bool lowerHigh = true;
   if(close[2] != 0)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 5, rates) == 5)
      {
         double recentHigh = rates[0].high;
         for(int i = 1; i < 5; i++)
         {
            if(rates[i].high > recentHigh)
            {
               lowerHigh = false;
               break;
            }
         }
      }
   }

   return (wasNearMA && bounced && emaDown && belowMA);
}

//+------------------------------------------------------------------+
//| 買い注文の実行                                                     |
//+------------------------------------------------------------------+
void ExecuteBuyOrder()
{
   double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // スイングローの検索
   double swingLow = FindSwingLow();

   // ストップロスの計算
   double sl = 0;
   if(swingLow > 0 && swingLow < ask)
   {
      sl = swingLow - (10 * point); // スイングローより少し下
   }
   else
   {
      // スイングローが見つからない場合は、エントリー価格から2%下を使用
      sl = ask * 0.98;
   }

   // SLが現在価格より上にならないように制限
   if(sl >= ask)
   {
      sl = ask - (ask * 0.01); // 最低1%のSL
   }

   // テイクプロフィットの計算
   double slDistance = ask - sl;
   double tp = ask + (slDistance * TakeProfit_Ratio);

   // 正規化
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));

   // ロット数の計算
   double lotSize = CalculateLotSize(ask, sl);

   if(lotSize <= 0)
   {
      Print("エラー: ロット数の計算に失敗しました");
      return;
   }

   // 注文実行
   if(trade.Buy(lotSize, Symbol_to_Trade, ask, sl, tp, EA_Comment))
   {
      Print("買い注文が成功しました: ロット=", lotSize, ", Price=", ask, ", SL=", sl, ", TP=", tp);
   }
   else
   {
      Print("買い注文が失敗しました: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 売り注文の実行                                                     |
//+------------------------------------------------------------------+
void ExecuteSellOrder()
{
   double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // スイングハイの検索
   double swingHigh = FindSwingHigh();

   // ストップロスの計算
   double sl = 0;
   if(swingHigh > 0 && swingHigh > bid)
   {
      sl = swingHigh + (10 * point); // スイングハイより少し上
   }
   else
   {
      // スイングハイが見つからない場合は、エントリー価格から2%上を使用
      sl = bid * 1.02;
   }

   // SLが現在価格より下にならないように制限
   if(sl <= bid)
   {
      sl = bid + (bid * 0.01); // 最低1%のSL
   }

   // テイクプロフィットの計算
   double slDistance = sl - bid;
   double tp = bid - (slDistance * TakeProfit_Ratio);

   // 正規化
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS));

   // ロット数の計算
   double lotSize = CalculateLotSize(bid, sl);

   if(lotSize <= 0)
   {
      Print("エラー: ロット数の計算に失敗しました");
      return;
   }

   // 注文実行
   if(trade.Sell(lotSize, Symbol_to_Trade, bid, sl, tp, EA_Comment))
   {
      Print("売り注文が成功しました: ロット=", lotSize, ", Price=", bid, ", SL=", sl, ", TP=", tp);
   }
   else
   {
      Print("売り注文が失敗しました: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| スイングローの検索                                                 |
//+------------------------------------------------------------------+
double FindSwingLow()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 20, rates) < 20)
      return 0;

   double swingLow = rates[0].low;
   for(int i = 1; i < 20; i++)
   {
      if(rates[i].low < swingLow)
         swingLow = rates[i].low;
   }

   return swingLow;
}

//+------------------------------------------------------------------+
//| スイングハイの検索                                                 |
//+------------------------------------------------------------------+
double FindSwingHigh()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 20, rates) < 20)
      return 0;

   double swingHigh = rates[0].high;
   for(int i = 1; i < 20; i++)
   {
      if(rates[i].high > swingHigh)
         swingHigh = rates[i].high;
   }

   return swingHigh;
}

//+------------------------------------------------------------------+
//| ロット数の計算（口座残高の％ベース）                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   // 口座残高の取得
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // リスク額の計算
   double riskAmount = accountBalance * Risk_Percent / 100.0;

   // SL距離の計算（価格単位）
   double slDistance = MathAbs(entryPrice - stopLoss);

   if(slDistance <= 0)
   {
      Print("エラー: SL距離が無効です");
      return 0.01; // 最小ロット
   }

   // ティック価値の取得
   double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

   // ロット数の計算
   // ロット数 = リスク額 / (SL距離 / tickSize × tickValue)
   double lotSize = riskAmount / (slDistance / tickSize * tickValue);

   // ロット数の正規化
   double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

   // ステップに合わせて丸める
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   // 最小・最大ロットの制限
   if(lotSize < minLot)
      lotSize = minLot;
   if(lotSize > maxLot)
      lotSize = maxLot;
   if(lotSize > Max_Lot_Size)
      lotSize = Max_Lot_Size;

   // 正規化
   lotSize = NormalizeDouble(lotSize, 2);

   Print("ロット計算: 残高=", accountBalance, ", リスク額=", riskAmount,
         ", SL距離=", slDistance, ", ロット=", lotSize);

   return lotSize;
}
//+------------------------------------------------------------------+
