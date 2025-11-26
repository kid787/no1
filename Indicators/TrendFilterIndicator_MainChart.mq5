//+------------------------------------------------------------------+
//|                               TrendFilterIndicator_MainChart.mq5 |
//|                軽量トレンドフィルターインジケーター（メインチャート版）        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   4

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

// Long Signal Arrow (ロングシグナル矢印)
#property indicator_label3  "Long Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLimeGreen
#property indicator_width3  3

// Short Signal Arrow (ショートシグナル矢印)
#property indicator_label4  "Short Signal"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  3

//--- 入力パラメータ
input int    FastEMA_Period   = 5;      // 短期EMA期間
input int    SlowEMA_Period   = 15;     // 長期EMA期間
input int    ATR_Period       = 14;     // ATR期間
input double ATR_Multiplier   = 0.5;    // ATR乗数
input bool   ShowSignalArrows = true;   // シグナル矢印を表示

//--- インジケーターバッファ
double EMA_Fast_Buffer[];      // EMA Fast値
double EMA_Slow_Buffer[];      // EMA Slow値
double Long_Signal_Buffer[];   // ロングシグナル
double Short_Signal_Buffer[];  // ショートシグナル
double Trend_State[];          // トレンド状態（内部計算用）
double Prev_Trend_State[];     // 前のバーのトレンド状態
double ATR_Buffer[];           // ATR値（内部計算用）

//--- ハンドル
int handle_EMA_Fast;
int handle_EMA_Slow;
int handle_ATR;

//--- ゾーン定義用定数
#define ZONE_NO_TRADE  0  // レンジ相場
#define ZONE_LONG      1  // 上昇トレンド
#define ZONE_SHORT    -1  // 下降トレンド

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- インジケーターバッファのマッピング
   SetIndexBuffer(0, EMA_Fast_Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, EMA_Slow_Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, Long_Signal_Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, Short_Signal_Buffer, INDICATOR_DATA);
   SetIndexBuffer(4, Trend_State, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, Prev_Trend_State, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, ATR_Buffer, INDICATOR_CALCULATIONS);

   //--- 矢印の設定
   PlotIndexSetInteger(2, PLOT_ARROW, 233);  // 上向き矢印
   PlotIndexSetInteger(3, PLOT_ARROW, 234);  // 下向き矢印

   //--- プロットの設定
   PlotIndexSetString(0, PLOT_LABEL, "EMA " + IntegerToString(FastEMA_Period));
   PlotIndexSetString(1, PLOT_LABEL, "EMA " + IntegerToString(SlowEMA_Period));
   PlotIndexSetString(2, PLOT_LABEL, "Long Signal");
   PlotIndexSetString(3, PLOT_LABEL, "Short Signal");

   //--- 矢印の表示/非表示
   if(!ShowSignalArrows)
   {
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   //--- バッファの初期化
   ArrayInitialize(Long_Signal_Buffer, EMPTY_VALUE);
   ArrayInitialize(Short_Signal_Buffer, EMPTY_VALUE);

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
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, max_period + 1);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, max_period + 1);

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
   int start_pos = prev_calculated > 0 ? prev_calculated - 1 : max_period;

   //--- EMAとATRのデータをコピー
   double ema_fast_data[], ema_slow_data[], atr_data[];

   if(CopyBuffer(handle_EMA_Fast, 0, 0, rates_total, ema_fast_data) <= 0)
   {
      Print("EMA Fast データのコピーに失敗しました");
      return(prev_calculated);
   }

   if(CopyBuffer(handle_EMA_Slow, 0, 0, rates_total, ema_slow_data) <= 0)
   {
      Print("EMA Slow データのコピーに失敗しました");
      return(prev_calculated);
   }

   if(CopyBuffer(handle_ATR, 0, 0, rates_total, atr_data) <= 0)
   {
      Print("ATR データのコピーに失敗しました");
      return(prev_calculated);
   }

   //--- 各バーの計算
   for(int i = start_pos; i < rates_total; i++)
   {
      //--- EMAバッファに値を設定
      EMA_Fast_Buffer[i] = ema_fast_data[i];
      EMA_Slow_Buffer[i] = ema_slow_data[i];

      //--- ATR値の取得
      double atr_value = atr_data[i];
      ATR_Buffer[i] = atr_value;

      //--- 乖離度とATR基準距離の計算
      double ema_fast = ema_fast_data[i];
      double ema_slow = ema_slow_data[i];
      double ema_diff = MathAbs(ema_fast - ema_slow);
      double distance = atr_value * ATR_Multiplier;

      //--- 前のバーのトレンド状態を保存
      if(i > 0)
         Prev_Trend_State[i] = Trend_State[i - 1];
      else
         Prev_Trend_State[i] = ZONE_NO_TRADE;

      //--- ゾーン判定
      if(ema_diff < distance)
      {
         // レンジ相場（トレード禁止ゾーン）
         Trend_State[i] = ZONE_NO_TRADE;
      }
      else if(ema_fast > ema_slow)
      {
         // 上昇トレンド（ロングのみ）
         Trend_State[i] = ZONE_LONG;
      }
      else
      {
         // 下降トレンド（ショートのみ）
         Trend_State[i] = ZONE_SHORT;
      }

      //--- シグナル矢印の設定（トレンド状態が変化した時）
      Long_Signal_Buffer[i] = EMPTY_VALUE;
      Short_Signal_Buffer[i] = EMPTY_VALUE;

      if(ShowSignalArrows && i > max_period)
      {
         // レンジからロングトレンドへの変化
         if(Trend_State[i] == ZONE_LONG && Prev_Trend_State[i] != ZONE_LONG)
         {
            Long_Signal_Buffer[i] = low[i] - atr_value * 0.5;
         }
         // レンジからショートトレンドへの変化
         else if(Trend_State[i] == ZONE_SHORT && Prev_Trend_State[i] != ZONE_SHORT)
         {
            Short_Signal_Buffer[i] = high[i] + atr_value * 0.5;
         }
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
