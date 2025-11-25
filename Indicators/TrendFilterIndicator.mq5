//+------------------------------------------------------------------+
//|                                        TrendFilterIndicator.mq5 |
//|                                  軽量トレンドフィルターインジケーター |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   3

// EMA Fast Line (短期EMA)
#property indicator_label1  "EMA Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// EMA Slow Line (長期EMA)
#property indicator_label2  "EMA Slow"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Background Color (背景色 - ヒストグラム)
#property indicator_label3  "Trend Zone"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  clrGray,clrLimeGreen,clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  5

//--- 入力パラメータ
input int    FastEMA_Period   = 5;      // 短期EMA期間
input int    SlowEMA_Period   = 15;     // 長期EMA期間
input int    ATR_Period       = 14;     // ATR期間
input double ATR_Multiplier   = 0.5;    // ATR乗数

//--- インジケーターバッファ
double EMA_Fast_Buffer[];      // EMA Fast値
double EMA_Slow_Buffer[];      // EMA Slow値
double Trend_Histogram[];      // トレンド背景用ヒストグラム
double Trend_Color_Buffer[];   // トレンドカラーインデックス
double ATR_Buffer[];           // ATR値（内部計算用）

//--- ハンドル
int handle_EMA_Fast;
int handle_EMA_Slow;
int handle_ATR;

//--- ゾーン定義用定数
#define ZONE_NO_TRADE  0  // レンジ相場（灰色）
#define ZONE_LONG      1  // 上昇トレンド（緑色）
#define ZONE_SHORT     2  // 下降トレンド（赤色）

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- インジケーターバッファのマッピング
   SetIndexBuffer(0, EMA_Fast_Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, EMA_Slow_Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, Trend_Histogram, INDICATOR_DATA);
   SetIndexBuffer(3, Trend_Color_Buffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, ATR_Buffer, INDICATOR_CALCULATIONS);

   //--- 配列を時系列として設定
   ArraySetAsSeries(EMA_Fast_Buffer, true);
   ArraySetAsSeries(EMA_Slow_Buffer, true);
   ArraySetAsSeries(Trend_Histogram, true);
   ArraySetAsSeries(Trend_Color_Buffer, true);
   ArraySetAsSeries(ATR_Buffer, true);

   //--- プロットの設定
   PlotIndexSetString(0, PLOT_LABEL, "EMA " + IntegerToString(FastEMA_Period));
   PlotIndexSetString(1, PLOT_LABEL, "EMA " + IntegerToString(SlowEMA_Period));
   PlotIndexSetString(2, PLOT_LABEL, "Trend Zone");

   //--- EMAハンドルの作成
   handle_EMA_Fast = iMA(_Symbol, _Period, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_EMA_Slow = iMA(_Symbol, _Period, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_ATR = iATR(_Symbol, _Period, ATR_Period);

   //--- ハンドル作成チェック
   if(handle_EMA_Fast == INVALID_HANDLE || handle_EMA_Slow == INVALID_HANDLE || handle_ATR == INVALID_HANDLE)
   {
      Print("インジケーターハンドルの作成に失敗しました");
      return(INIT_FAILED);
   }

   //--- 描画開始位置の設定
   int max_period = MathMax(FastEMA_Period, MathMax(SlowEMA_Period, ATR_Period));
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, max_period);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, max_period);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, max_period);

   //--- インジケーター名の設定
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("Trend Filter (EMA %d/%d, ATR %d×%.1f)",
      FastEMA_Period, SlowEMA_Period, ATR_Period, ATR_Multiplier));

   //--- 小数点桁数の設定
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター反復関数                                          |
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
   //--- 十分なバーがあるか確認
   int max_period = MathMax(FastEMA_Period, MathMax(SlowEMA_Period, ATR_Period));
   if(rates_total < max_period)
      return(0);

   //--- 計算開始位置の決定
   int start_pos = prev_calculated - 1;
   if(start_pos < max_period)
      start_pos = max_period;

   //--- コピーするバー数の計算
   int to_copy = rates_total - start_pos + 1;
   if(to_copy <= 0)
      return(rates_total);

   //--- EMAとATRのデータをコピー
   double ema_fast_data[], ema_slow_data[], atr_data[];
   ArraySetAsSeries(ema_fast_data, true);
   ArraySetAsSeries(ema_slow_data, true);
   ArraySetAsSeries(atr_data, true);

   if(CopyBuffer(handle_EMA_Fast, 0, 0, to_copy, ema_fast_data) <= 0)
   {
      Print("EMA Fast データのコピーに失敗しました");
      return(prev_calculated);
   }

   if(CopyBuffer(handle_EMA_Slow, 0, 0, to_copy, ema_slow_data) <= 0)
   {
      Print("EMA Slow データのコピーに失敗しました");
      return(prev_calculated);
   }

   if(CopyBuffer(handle_ATR, 0, 0, to_copy, atr_data) <= 0)
   {
      Print("ATR データのコピーに失敗しました");
      return(prev_calculated);
   }

   //--- 各バーの計算
   for(int i = 0; i < to_copy; i++)
   {
      int buffer_index = rates_total - start_pos + i - 1;

      //--- EMAバッファに値を設定
      EMA_Fast_Buffer[buffer_index] = ema_fast_data[i];
      EMA_Slow_Buffer[buffer_index] = ema_slow_data[i];

      //--- ATR値の取得
      double atr_value = atr_data[i];
      ATR_Buffer[buffer_index] = atr_value;

      //--- 乖離度とATR基準距離の計算
      double ema_diff = MathAbs(ema_fast_data[i] - ema_slow_data[i]);
      double distance = atr_value * ATR_Multiplier;

      //--- ヒストグラムの高さを設定（チャート範囲をカバーするため大きな値）
      // 現在の価格を基準に、チャート全体をカバーする高さを設定
      double histogram_height = close[rates_total - buffer_index - 1];

      //--- ゾーン判定
      if(ema_diff < distance)
      {
         // レンジ相場（トレード禁止ゾーン）
         Trend_Histogram[buffer_index] = histogram_height;
         Trend_Color_Buffer[buffer_index] = ZONE_NO_TRADE;
      }
      else if(ema_fast_data[i] > ema_slow_data[i])
      {
         // 上昇トレンド（ロングのみ）
         Trend_Histogram[buffer_index] = histogram_height;
         Trend_Color_Buffer[buffer_index] = ZONE_LONG;
      }
      else
      {
         // 下降トレンド（ショートのみ）
         Trend_Histogram[buffer_index] = histogram_height;
         Trend_Color_Buffer[buffer_index] = ZONE_SHORT;
      }
   }

   //--- 次の呼び出しのために計算済みバー数を返す
   return(rates_total);
}

//+------------------------------------------------------------------+
//| インジケーター終了関数                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- ハンドルの解放
   if(handle_EMA_Fast != INVALID_HANDLE)
      IndicatorRelease(handle_EMA_Fast);
   if(handle_EMA_Slow != INVALID_HANDLE)
      IndicatorRelease(handle_EMA_Slow);
   if(handle_ATR != INVALID_HANDLE)
      IndicatorRelease(handle_ATR);
}
//+------------------------------------------------------------------+
