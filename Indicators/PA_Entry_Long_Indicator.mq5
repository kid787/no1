//+------------------------------------------------------------------+
//|                                      PA_Entry_Long_Indicator.mq5 |
//|                                  Copyright 2025, Price Action FX |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Price Action FX"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- plot arrows
#property indicator_label1  "PA Entry Long"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input double Zone_High = 1.1000;                    // 抵抗帯の上限価格
input double Zone_Low = 1.0950;                     // 抵抗帯の下限価格
input int Lookback_Period_Decline = 10;             // 下落評価期間（ローソク足本数）
input double Momentum_Threshold = 0.0010;           // 上昇判断基準（実体の大きさ、pips）
input int Angle_Period = 5;                         // 角度計算期間（ローソク足本数）
input int Small_Body_Period = 3;                    // 小さな実体の評価期間
input double Small_Body_Ratio = 0.3;                // 小さな実体と判断する比率（平均に対する）
input double Vertical_Angle_Threshold = 60.0;      // 垂直と判断する角度（度）
input double Gentle_Angle_Threshold = 45.0;        // 緩やかと判断する角度（度）
input double Upper_Wick_Ratio = 0.3;               // ヒゲが少ないと判断する比率
input int Strong_Candle_Lookback = 2;              // 強い陽線の確認期間

//--- indicator buffers
double ArrowBuffer[];

//--- global variables
datetime lastSignalTime = 0;  // 重複シグナル防止用

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0, ArrowBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // 上向き矢印のコード
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

   //--- set index label
   PlotIndexSetString(0, PLOT_LABEL, "PA Entry Long");

   //--- initialization done
   IndicatorSetString(INDICATOR_SHORTNAME, "PA Entry Long Signal");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- check for minimum bars
   if(rates_total < Lookback_Period_Decline + Angle_Period + 10)
      return(0);

   //--- set array as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ArrowBuffer, true);

   //--- starting index for calculations
   int start = 1;
   if(prev_calculated > 1)
      start = rates_total - prev_calculated;

   //--- main loop
   for(int i = start; i < rates_total - Lookback_Period_Decline - 10; i++)
   {
      ArrowBuffer[i] = 0.0;  // デフォルトはシグナルなし

      //--- フェーズ1: 抵抗帯内での値動きの確認
      if(!CheckPhase1_InResistanceZone(close, i))
         continue;

      //--- フェーズ2: 下落の勢いの衰えの確認
      if(!CheckPhase2_DeclineMomentumWeakening(open, high, low, close, i))
         continue;

      //--- フェーズ3: 強い反発の確認
      if(!CheckPhase3_StrongReversal(open, high, low, close, i))
         continue;

      //--- 全てのフェーズを満たした場合、シグナルを表示
      if(time[i] != lastSignalTime)  // 重複防止
      {
         ArrowBuffer[i] = low[i] - (10 * _Point);  // 矢印を安値の少し下に表示
         lastSignalTime = time[i];

         //--- ストップロスラインを描画
         DrawStopLossLine(time[i], FindRecentLow(low, i, Lookback_Period_Decline));
      }
   }

   //--- return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| フェーズ1: 抵抗帯内での値動きの確認                                  |
//+------------------------------------------------------------------+
bool CheckPhase1_InResistanceZone(const double &close[], int index)
{
   double currentClose = close[index];

   // 終値が抵抗帯の範囲内にあるかチェック
   if(currentClose >= Zone_Low && currentClose <= Zone_High)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| フェーズ2: 下落の勢いの衰えの確認                                    |
//+------------------------------------------------------------------+
bool CheckPhase2_DeclineMomentumWeakening(const double &open[], const double &high[],
                                          const double &low[], const double &close[], int index)
{
   //--- パターン1: じわじわ下落/横ばいパターン
   if(CheckGradualDeclineOrSideways(open, high, low, close, index))
      return true;

   //--- パターン2: ソーサー（お椀型）パターン
   if(CheckSaucerPattern(low, index))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| じわじわ下落/横ばいパターンのチェック                                  |
//+------------------------------------------------------------------+
bool CheckGradualDeclineOrSideways(const double &open[], const double &high[],
                                   const double &low[], const double &close[], int index)
{
   //--- 安値更新を確認
   bool isNewLow = false;
   double recentLow = low[index];

   for(int i = index + 1; i < index + Lookback_Period_Decline; i++)
   {
      if(recentLow < low[i])
      {
         isNewLow = true;
         break;
      }
   }

   if(!isNewLow)
      return false;

   //--- 値動きの角度をチェック
   double angle = CalculateAngle(close, index, Angle_Period);
   if(MathAbs(angle) < Gentle_Angle_Threshold)  // 45度より緩やか
      return true;

   //--- 横ばい（価格停滞）パターンのチェック
   if(CheckSidewaysPattern(open, close, index))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 横ばいパターンのチェック                                             |
//+------------------------------------------------------------------+
bool CheckSidewaysPattern(const double &open[], const double &close[], int index)
{
   //--- 平均実体サイズを計算
   double avgBody = CalculateAverageBodySize(open, close, index + Small_Body_Period, 20);

   //--- 直近X本のローソク足の実体が非常に小さいかチェック
   int smallBodyCount = 0;
   for(int i = index; i < index + Small_Body_Period; i++)
   {
      double bodySize = MathAbs(close[i] - open[i]);
      if(bodySize < avgBody * Small_Body_Ratio)
         smallBodyCount++;
   }

   // 大半が小さな実体の場合、横ばいと判断
   if(smallBodyCount >= Small_Body_Period - 1)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| ソーサー（お椀型）パターンのチェック                                   |
//+------------------------------------------------------------------+
bool CheckSaucerPattern(const double &low[], int index)
{
   //--- 安値の切り上げを確認（最低3本）
   if(index + 4 >= ArraySize(low))
      return false;

   // 安値が切り上がっているかチェック
   if(low[index] > low[index + 1] && low[index + 1] <= low[index + 2] &&
      low[index + 2] <= low[index + 3])
   {
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| フェーズ3: 強い反発の確認                                            |
//+------------------------------------------------------------------+
bool CheckPhase3_StrongReversal(const double &open[], const double &high[],
                                const double &low[], const double &close[], int index)
{
   //--- 条件1: 大陽線の確定
   if(!CheckLargeBullishCandle(open, close, index))
      return false;

   //--- 条件2: 垂直に近い角度
   if(!CheckVerticalAngle(close, index))
      return false;

   //--- 条件3: ヒゲの少なさ
   if(!CheckMinimalWick(open, high, close, index))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| 大陽線のチェック                                                    |
//+------------------------------------------------------------------+
bool CheckLargeBullishCandle(const double &open[], const double &close[], int index)
{
   //--- 直近1～2本の陽線をチェック
   for(int i = index; i < index + Strong_Candle_Lookback; i++)
   {
      double bodySize = close[i] - open[i];

      // 陽線であり、かつ閾値を超える大きさか
      if(bodySize > Momentum_Threshold)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 垂直に近い角度のチェック                                             |
//+------------------------------------------------------------------+
bool CheckVerticalAngle(const double &close[], int index)
{
   double angle = CalculateAngle(close, index, 3);  // 直近2-3本で角度計算

   // 垂直に近い角度（60度以上）か
   if(angle > Vertical_Angle_Threshold)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| ヒゲの少なさのチェック                                               |
//+------------------------------------------------------------------+
bool CheckMinimalWick(const double &open[], const double &high[],
                      const double &close[], int index)
{
   //--- 直近2本のローソク足をチェック
   for(int i = index; i < index + 2; i++)
   {
      double bodySize = MathAbs(close[i] - open[i]);
      double upperWick = high[i] - MathMax(open[i], close[i]);

      // 上ヒゲが実体に対して小さいか
      if(bodySize > 0 && upperWick / bodySize > Upper_Wick_Ratio)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 角度計算（度数法）                                                   |
//+------------------------------------------------------------------+
double CalculateAngle(const double &close[], int index, int period)
{
   if(index + period >= ArraySize(close))
      return 0.0;

   double priceChange = close[index] - close[index + period - 1];
   double timeChange = period;  // ローソク足の本数

   // アークタンジェントを使用して角度を計算（ラジアンから度数法へ）
   double angleRad = MathArctan(priceChange / (timeChange * _Point));
   double angleDeg = angleRad * 180.0 / M_PI;

   return angleDeg;
}

//+------------------------------------------------------------------+
//| 平均実体サイズ計算                                                   |
//+------------------------------------------------------------------+
double CalculateAverageBodySize(const double &open[], const double &close[],
                                int start, int period)
{
   if(start + period >= ArraySize(open))
      return 0.0;

   double sum = 0.0;
   for(int i = start; i < start + period; i++)
   {
      sum += MathAbs(close[i] - open[i]);
   }

   return sum / period;
}

//+------------------------------------------------------------------+
//| 直近の安値を検索                                                    |
//+------------------------------------------------------------------+
double FindRecentLow(const double &low[], int index, int period)
{
   double minLow = low[index];

   for(int i = index; i < index + period && i < ArraySize(low); i++)
   {
      if(low[i] < minLow)
         minLow = low[i];
   }

   return minLow;
}

//+------------------------------------------------------------------+
//| ストップロスラインの描画                                             |
//+------------------------------------------------------------------+
void DrawStopLossLine(datetime signalTime, double stopLossPrice)
{
   string lineName = "SL_Line_" + TimeToString(signalTime);

   //--- 既存のラインを削除
   if(ObjectFind(0, lineName) >= 0)
      ObjectDelete(0, lineName);

   //--- 水平線を作成
   ObjectCreate(0, lineName, OBJ_HLINE, 0, signalTime, stopLossPrice);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
   ObjectSetString(0, lineName, OBJPROP_TEXT, "Stop Loss");
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- delete all objects created by indicator
   ObjectsDeleteAll(0, "SL_Line_");
}
//+------------------------------------------------------------------+
