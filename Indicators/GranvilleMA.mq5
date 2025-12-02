//+------------------------------------------------------------------+
//|                                                  GranvilleMA.mq5 |
//|                                    Copyright 2025, MT5 Indicator |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MT5 Indicator"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   5

// インジケータープロット設定
#property indicator_label1  "EMA 75"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "EMA 200"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "Buy Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrBlue
#property indicator_width3  3

#property indicator_label4  "Sell Signal"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  3

#property indicator_label5  "Heikin-Ashi"
#property indicator_type5   DRAW_COLOR_CANDLES
#property indicator_color5  clrLimeGreen, clrRed
#property indicator_width5  1

// 入力パラメータ
input int      MA_PERIOD_MID = 75;              // 中期MA期間
input int      MA_PERIOD_LONG = 200;            // 長期MA期間
input ENUM_MA_METHOD MA_METHOD = MODE_EMA;      // MA計算方法
input ENUM_TIMEFRAMES MTF_TREND_PERIOD = PERIOD_H4; // MTFトレンド期間
input bool     HEIKIN_ASHI_ENABLED = true;      // 平均足表示
input int      MA_PROXIMITY_PIPS = 50;          // MA近接判定（Pips）
input color    TextColor = clrWhite;            // テキストカラー
input int      TextSize = 10;                   // テキストサイズ

// インジケーターバッファ
double MA75Buffer[];
double MA200Buffer[];
double BuySignalBuffer[];
double SellSignalBuffer[];
double HAOpenBuffer[];
double HAHighBuffer[];
double HALowBuffer[];
double HACloseBuffer[];
double HAColorBuffer[];

// グローバル変数
int ma75Handle, ma200Handle, mtfMA75Handle;
string labelName = "MTF_Trend_Label";

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   // インジケーターバッファのマッピング
   SetIndexBuffer(0, MA75Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, MA200Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, SellSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, HAOpenBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, HAHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, HALowBuffer, INDICATOR_DATA);
   SetIndexBuffer(7, HACloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(8, HAColorBuffer, INDICATOR_COLOR_INDEX);

   // シグナル矢印の設定
   PlotIndexSetInteger(2, PLOT_ARROW, 233); // 上向き矢印
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   PlotIndexSetInteger(3, PLOT_ARROW, 234); // 下向き矢印
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);

   // 平均足の透明度設定
   if(HEIKIN_ASHI_ENABLED)
   {
      PlotIndexSetInteger(4, PLOT_DRAW_BEGIN, 1);
      PlotIndexSetInteger(4, PLOT_LINE_COLOR, 0, clrLimeGreen);
      PlotIndexSetInteger(4, PLOT_LINE_COLOR, 1, clrRed);
   }
   else
   {
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   // MAハンドルの作成
   ma75Handle = iMA(_Symbol, PERIOD_CURRENT, MA_PERIOD_MID, 0, MA_METHOD, PRICE_CLOSE);
   ma200Handle = iMA(_Symbol, PERIOD_CURRENT, MA_PERIOD_LONG, 0, MA_METHOD, PRICE_CLOSE);
   mtfMA75Handle = iMA(_Symbol, MTF_TREND_PERIOD, MA_PERIOD_MID, 0, MA_METHOD, PRICE_CLOSE);

   if(ma75Handle == INVALID_HANDLE || ma200Handle == INVALID_HANDLE || mtfMA75Handle == INVALID_HANDLE)
   {
      Print("MAハンドルの作成に失敗しました");
      return(INIT_FAILED);
   }

   // インジケーター名の設定
   IndicatorSetString(INDICATOR_SHORTNAME, "Granville MA System");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   // ラベルの作成
   CreateLabel();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター終了関数                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ハンドルの解放
   if(ma75Handle != INVALID_HANDLE) IndicatorRelease(ma75Handle);
   if(ma200Handle != INVALID_HANDLE) IndicatorRelease(ma200Handle);
   if(mtfMA75Handle != INVALID_HANDLE) IndicatorRelease(mtfMA75Handle);

   // ラベルの削除
   ObjectDelete(0, labelName);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| カスタムインジケーター計算関数                                        |
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
   if(rates_total < MA_PERIOD_LONG)
      return(0);

   int start = prev_calculated > 0 ? prev_calculated - 1 : 0;

   // MAデータの取得
   if(CopyBuffer(ma75Handle, 0, 0, rates_total, MA75Buffer) <= 0)
      return(0);
   if(CopyBuffer(ma200Handle, 0, 0, rates_total, MA200Buffer) <= 0)
      return(0);

   // MTFトレンドの更新
   UpdateMTFTrendLabel();

   // 配列を時系列に設定
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(MA75Buffer, true);

   // 計算ループ
   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      int idx = rates_total - 1 - i;

      // シグナルバッファの初期化
      BuySignalBuffer[idx] = 0.0;
      SellSignalBuffer[idx] = 0.0;

      // グランビルシグナルの検出
      if(i >= 2)
      {
         DetectGranvilleSignal(i, idx, close, MA75Buffer);
      }

      // 平均足の計算
      if(HEIKIN_ASHI_ENABLED)
      {
         CalculateHeikinAshi(i, idx, rates_total, open, high, low, close);
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| MTFトレンドラベルの作成                                             |
//+------------------------------------------------------------------+
void CreateLabel()
{
   if(ObjectFind(0, labelName) < 0)
   {
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, TextColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, TextSize);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
   }
}

//+------------------------------------------------------------------+
//| MTFトレンド方向の更新                                               |
//+------------------------------------------------------------------+
void UpdateMTFTrendLabel()
{
   double mtfMA[];
   ArraySetAsSeries(mtfMA, true);

   if(CopyBuffer(mtfMA75Handle, 0, 0, 25, mtfMA) < 25)
      return;

   // 現在のMA値と20本前のMA値を比較
   double currentMA = mtfMA[0];
   double pastMA = mtfMA[20];
   double diff = currentMA - pastMA;
   double threshold = _Point * 10; // 閾値（横ばい判定用）

   string trendText;
   color trendColor;

   if(diff > threshold)
   {
      trendText = "H4トレンド: ⬆️上昇 (BUY優先)";
      trendColor = clrLimeGreen;
   }
   else if(diff < -threshold)
   {
      trendText = "H4トレンド: ⬇️下落 (SELL優先)";
      trendColor = clrRed;
   }
   else
   {
      trendText = "H4トレンド: レンジ (トレード非推奨)";
      trendColor = clrYellow;
   }

   ObjectSetString(0, labelName, OBJPROP_TEXT, trendText);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, trendColor);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| グランビルシグナルの検出                                             |
//+------------------------------------------------------------------+
void DetectGranvilleSignal(int i, int idx, const double &close[], const double &ma[])
{
   double proximityPoints = MA_PROXIMITY_PIPS * _Point * 10;

   // 現在と過去2本のデータ
   double close0 = close[i];
   double close1 = close[i-1];
   double close2 = close[i-2];
   double ma0 = ma[i];
   double ma1 = ma[i-1];
   double ma2 = ma[i-2];

   // MAの傾き確認
   bool maTrendUp = (ma0 > ma1) && (ma1 > ma2);
   bool maTrendDown = (ma0 < ma1) && (ma1 < ma2);

   // Rule 3: 上昇トレンド中の押し目買い
   if(maTrendUp)
   {
      // 前足がMAに接近していて、現在足がMAから反発
      bool wasNearMA = (MathAbs(close1 - ma1) <= proximityPoints) && (close1 > ma1);
      bool bounced = (close0 > ma0) && (close0 > close1);

      if(wasNearMA && bounced)
      {
         BuySignalBuffer[idx] = close[i] - (proximityPoints * 0.5);
      }
   }

   // Rule 7: 下降トレンド中の戻り売り
   if(maTrendDown)
   {
      // 前足がMAに接近していて、現在足がMAから反落
      bool wasNearMA = (MathAbs(close1 - ma1) <= proximityPoints) && (close1 < ma1);
      bool bounced = (close0 < ma0) && (close0 < close1);

      if(wasNearMA && bounced)
      {
         SellSignalBuffer[idx] = close[i] + (proximityPoints * 0.5);
      }
   }
}

//+------------------------------------------------------------------+
//| 平均足の計算                                                        |
//+------------------------------------------------------------------+
void CalculateHeikinAshi(int i, int idx, int rates_total, const double &open[], const double &high[],
                         const double &low[], const double &close[])
{
   double haOpen, haHigh, haLow, haClose;

   // 平均足の終値
   haClose = (open[i] + high[i] + low[i] + close[i]) / 4.0;

   // 平均足の始値
   if(i == 0)
   {
      haOpen = (open[i] + close[i]) / 2.0;
   }
   else
   {
      int prevIdx = rates_total - i;
      haOpen = (HAOpenBuffer[prevIdx] + HACloseBuffer[prevIdx]) / 2.0;
   }

   // 平均足の高値と安値
   haHigh = MathMax(high[i], MathMax(haOpen, haClose));
   haLow = MathMin(low[i], MathMin(haOpen, haClose));

   // バッファへの格納
   HAOpenBuffer[idx] = haOpen;
   HAHighBuffer[idx] = haHigh;
   HALowBuffer[idx] = haLow;
   HACloseBuffer[idx] = haClose;

   // カラーの設定（陽線:0、陰線:1）
   HAColorBuffer[idx] = (haClose >= haOpen) ? 0 : 1;
}
//+------------------------------------------------------------------+
