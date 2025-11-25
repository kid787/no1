//+------------------------------------------------------------------+
//|                                          LargeCandleDetector.mq5 |
//|                                  大陽線・大陰線検出インジケーター |
//+------------------------------------------------------------------+
#property copyright   "LargeCandleDetector"
#property link        ""
#property version     "1.00"
#property description "大陽線・大陰線を検出し、サインとアラートを表示するインジケーター"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- プロット設定
#property indicator_label1  "Bullish Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrBlue
#property indicator_width1  2

#property indicator_label2  "Bearish Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//+------------------------------------------------------------------+
//| 入力パラメータ                                                      |
//+------------------------------------------------------------------+
input int    LookbackPeriod    = 20;      // 過去比較本数
input double SizeMultiplier    = 1.5;     // サイズ倍率
input bool   AlertsEnabled     = true;    // アラートを有効にする
input color  DrawBullishSign   = clrBlue; // 陽線サイン色
input color  DrawBearishSign   = clrRed;  // 陰線サイン色

//+------------------------------------------------------------------+
//| インジケーターバッファ                                              |
//+------------------------------------------------------------------+
double BullishSignalBuffer[];
double BearishSignalBuffer[];

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
datetime lastAlertTime = 0;

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- インジケーターバッファのマッピング
   SetIndexBuffer(0, BullishSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BearishSignalBuffer, INDICATOR_DATA);

   //--- 矢印コードの設定（233 = 上向き三角形, 234 = 下向き三角形）
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   //--- 色の設定
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, DrawBullishSign);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, DrawBearishSign);

   //--- 空の値の設定
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   //--- インジケーター名の設定
   IndicatorSetString(INDICATOR_SHORTNAME, "LargeCandleDetector(" +
                      IntegerToString(LookbackPeriod) + "," +
                      DoubleToString(SizeMultiplier, 1) + ")");

   //--- バッファの初期化
   ArraySetAsSeries(BullishSignalBuffer, true);
   ArraySetAsSeries(BearishSignalBuffer, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター計算関数                                      |
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
   //--- 配列の方向を設定
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   //--- 十分なデータがあるかチェック
   if(rates_total < LookbackPeriod + 1)
      return(0);

   //--- 計算開始位置の決定
   int start;
   if(prev_calculated == 0)
   {
      //--- 初回計算時は全てのバッファをクリア
      ArrayInitialize(BullishSignalBuffer, 0.0);
      ArrayInitialize(BearishSignalBuffer, 0.0);
      start = rates_total - LookbackPeriod - 1;
   }
   else
   {
      //--- リペイント防止：確定した足のみ計算（最新2本のみ再計算）
      start = 1;
   }

   //--- メインループ
   for(int i = start; i >= 1; i--)
   {
      //--- バッファの初期化
      BullishSignalBuffer[i] = 0.0;
      BearishSignalBuffer[i] = 0.0;

      //--- 平均実体サイズの計算
      double avgBodySize = CalculateAverageBodySize(i, open, close);

      //--- 平均が0の場合はスキップ
      if(avgBodySize <= 0)
         continue;

      //--- 現在の足の実体サイズを計算
      double currentBodySize = MathAbs(close[i] - open[i]);

      //--- 閾値の計算
      double threshold = avgBodySize * SizeMultiplier;

      //--- 大陽線の検出
      if(close[i] > open[i] && currentBodySize >= threshold)
      {
         BullishSignalBuffer[i] = low[i] - (high[i] - low[i]) * 0.1;

         //--- アラート（確定足のみ、重複防止）
         if(AlertsEnabled && i == 1 && time[i] != lastAlertTime)
         {
            SendAlert("大陽線検出", time[i], close[i]);
            lastAlertTime = time[i];
         }
      }
      //--- 大陰線の検出
      else if(close[i] < open[i] && currentBodySize >= threshold)
      {
         BearishSignalBuffer[i] = high[i] + (high[i] - low[i]) * 0.1;

         //--- アラート（確定足のみ、重複防止）
         if(AlertsEnabled && i == 1 && time[i] != lastAlertTime)
         {
            SendAlert("大陰線検出", time[i], close[i]);
            lastAlertTime = time[i];
         }
      }
   }

   //--- 次回の OnCalculate のために返す
   return(rates_total);
}

//+------------------------------------------------------------------+
//| 平均実体サイズの計算                                               |
//+------------------------------------------------------------------+
double CalculateAverageBodySize(int currentBar,
                                const double &open[],
                                const double &close[])
{
   double sum = 0.0;
   int count = 0;

   //--- 過去のLookbackPeriod本の確定足の実体サイズを集計
   for(int j = currentBar + 1; j <= currentBar + LookbackPeriod; j++)
   {
      double bodySize = MathAbs(close[j] - open[j]);
      sum += bodySize;
      count++;
   }

   //--- 平均を計算
   if(count > 0)
      return sum / count;
   else
      return 0.0;
}

//+------------------------------------------------------------------+
//| アラート送信                                                       |
//+------------------------------------------------------------------+
void SendAlert(string signalType, datetime signalTime, double price)
{
   string symbol = Symbol();
   string timeframe = EnumToString(Period());
   string message = signalType + " | " + symbol + " " + timeframe +
                    " | 時刻: " + TimeToString(signalTime, TIME_DATE|TIME_MINUTES) +
                    " | 価格: " + DoubleToString(price, _Digits);

   //--- ポップアップアラート
   Alert(message);

   //--- プッシュ通知（モバイル端末への通知、有効な場合）
   SendNotification(message);

   //--- ログ出力
   Print(message);
}
//+------------------------------------------------------------------+
