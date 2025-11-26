//+------------------------------------------------------------------+
//|                              TrendFilterIndicator_SubWindow.mq5 |
//|                     軽量トレンドフィルターインジケーター（サブウィンドウ版） |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "1.10"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   2

// EMA Trend Histogram (トレンド状態ヒストグラム)
#property indicator_label1  "Trend State"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrGray,clrLimeGreen,clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

// Zero Line (ゼロライン)
#property indicator_label2  "Zero Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDarkGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- 入力パラメータ
input int    FastEMA_Period   = 5;      // 短期EMA期間
input int    SlowEMA_Period   = 15;     // 長期EMA期間
input int    ATR_Period       = 14;     // ATR期間
input double ATR_Multiplier   = 0.5;    // ATR乗数

//--- インジケーターバッファ
double Trend_Buffer[];         // トレンド状態値（+1, 0, -1）
double Trend_Color_Buffer[];   // トレンドカラーインデックス
double Zero_Buffer[];          // ゼロライン
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
   SetIndexBuffer(0, Trend_Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, Trend_Color_Buffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, Zero_Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, ATR_Buffer, INDICATOR_CALCULATIONS);

   //--- プロットの設定
   PlotIndexSetString(0, PLOT_LABEL, "Trend State");
   PlotIndexSetString(1, PLOT_LABEL, "Zero");

   //--- ゼロラインの初期化
   ArrayInitialize(Zero_Buffer, 0.0);

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
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, 0);

   //--- インジケーター名の設定
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("Trend Filter (EMA %d/%d, ATR %d×%.1f)",
      FastEMA_Period, SlowEMA_Period, ATR_Period, ATR_Multiplier));

   //--- 小数点桁数の設定
   IndicatorSetInteger(INDICATOR_DIGITS, 0);

   //--- レベルの設定
   IndicatorSetInteger(INDICATOR_LEVELS, 3);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 1.0);   // Long Zone
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, 0.0);   // Zero Line
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, -1.0);  // Short Zone
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrLimeGreen);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrDarkGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 2, clrRed);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_SOLID);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 2, STYLE_DOT);

   //--- ウィンドウの最小・最大値を設定
   IndicatorSetDouble(INDICATOR_MINIMUM, -1.5);
   IndicatorSetDouble(INDICATOR_MAXIMUM, 1.5);

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

   //--- コピーするバー数の計算
   int to_copy = rates_total - start_pos;
   if(to_copy <= 0)
      return(rates_total);

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
      //--- ゼロラインの設定
      Zero_Buffer[i] = 0.0;

      //--- EMAとATR値の取得
      double ema_fast = ema_fast_data[i];
      double ema_slow = ema_slow_data[i];
      double atr_value = atr_data[i];

      //--- ATRバッファに保存
      ATR_Buffer[i] = atr_value;

      //--- 乖離度とATR基準距離の計算
      double ema_diff = MathAbs(ema_fast - ema_slow);
      double distance = atr_value * ATR_Multiplier;

      //--- ゾーン判定
      if(ema_diff < distance)
      {
         // レンジ相場（トレード禁止ゾーン）
         Trend_Buffer[i] = 0.0;
         Trend_Color_Buffer[i] = ZONE_NO_TRADE;
      }
      else if(ema_fast > ema_slow)
      {
         // 上昇トレンド（ロングのみ）
         Trend_Buffer[i] = 1.0;
         Trend_Color_Buffer[i] = ZONE_LONG;
      }
      else
      {
         // 下降トレンド（ショートのみ）
         Trend_Buffer[i] = -1.0;
         Trend_Color_Buffer[i] = ZONE_SHORT;
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
