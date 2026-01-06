//+------------------------------------------------------------------+
//|                                                MarketRegime.mqh |
//|                        Market Condition Recognition Logic        |
//|                     Based on D1 (Daily) Chart Analysis           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                        |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
   MARKET_REGIME_TREND_UP,      // 上昇トレンド
   MARKET_REGIME_TREND_DOWN,    // 下降トレンド
   MARKET_REGIME_RANGE,         // レンジ（ボックス）相場
   MARKET_REGIME_TRENDLESS      // ノントレンド（トレンドレス）
};

//+------------------------------------------------------------------+
//| Market Regime Detection Parameters Structure                     |
//+------------------------------------------------------------------+
struct MarketRegimeParams
{
   // Moving Average Parameters
   int      ma_short_period;          // 短期MA期間（デフォルト: 20）
   int      ma_medium_period;         // 中期MA期間（デフォルト: 50）
   int      ma_long_period;           // 長期MA期間（デフォルト: 200）
   int      ma_slope_period;          // MA傾き計算期間
   double   ma_slope_threshold;       // MA傾き閾値（ポイント）

   // ADX Parameters
   int      adx_period;               // ADX期間（デフォルト: 14）
   double   adx_trend_threshold;      // トレンド判定閾値（デフォルト: 25）
   double   adx_trendless_threshold;  // トレンドレス判定閾値（デフォルト: 20）

   // Bollinger Bands Parameters
   int      bb_period;                // BB期間（デフォルト: 20）
   double   bb_deviation;             // BB偏差（デフォルト: 2.0）
   double   bb_expansion_ratio;       // エクスパンション判定比率
   double   bb_squeeze_ratio;         // スクイーズ判定比率

   // RSI Parameters
   int      rsi_period;               // RSI期間（デフォルト: 14）
   double   rsi_upper;                // RSI上限（デフォルト: 70）
   double   rsi_lower;                // RSI下限（デフォルト: 30）
   double   rsi_center_range;         // RSI中心帯範囲（デフォルト: 10）

   // ATR Parameters
   int      atr_period;               // ATR期間（デフォルト: 14）
   int      atr_lookback;             // ATR比較期間
   double   atr_low_threshold;        // 低ATR判定比率

   // Ichimoku Parameters
   int      ichi_tenkan;              // 転換線期間（デフォルト: 9）
   int      ichi_kijun;               // 基準線期間（デフォルト: 26）
   int      ichi_senkou;              // 先行スパン期間（デフォルト: 52）

   // Swing High/Low Parameters
   int      swing_lookback;           // スイングH/L検出期間
   int      swing_strength;           // スイング強度（バー数）

   // General Parameters
   int      bars_to_analyze;          // 分析に使用するバー数

   // Default Constructor
   MarketRegimeParams()
   {
      ma_short_period = 20;
      ma_medium_period = 50;
      ma_long_period = 200;
      ma_slope_period = 5;
      ma_slope_threshold = 0.0001;

      adx_period = 14;
      adx_trend_threshold = 25.0;
      adx_trendless_threshold = 20.0;

      bb_period = 20;
      bb_deviation = 2.0;
      bb_expansion_ratio = 1.5;
      bb_squeeze_ratio = 0.5;

      rsi_period = 14;
      rsi_upper = 70.0;
      rsi_lower = 30.0;
      rsi_center_range = 10.0;

      atr_period = 14;
      atr_lookback = 20;
      atr_low_threshold = 0.7;

      ichi_tenkan = 9;
      ichi_kijun = 26;
      ichi_senkou = 52;

      swing_lookback = 20;
      swing_strength = 3;

      bars_to_analyze = 100;
   }
};

//+------------------------------------------------------------------+
//| Market Analysis Results Structure                                 |
//+------------------------------------------------------------------+
struct MarketAnalysisResult
{
   // Trend Indicators
   bool     is_perfect_order_bullish;    // 強気パーフェクトオーダー
   bool     is_perfect_order_bearish;    // 弱気パーフェクトオーダー
   bool     is_ma_sloping_up;            // MA上向き傾斜
   bool     is_ma_sloping_down;          // MA下向き傾斜
   bool     is_bb_expanding;             // BBエクスパンション
   bool     is_band_walk_upper;          // 上部バンドウォーク
   bool     is_band_walk_lower;          // 下部バンドウォーク
   bool     is_adx_trending;             // ADXトレンド状態
   bool     is_adx_rising;               // ADX上昇中
   bool     is_higher_highs;             // 高値更新
   bool     is_higher_lows;              // 安値切り上げ
   bool     is_lower_highs;              // 高値切り下げ
   bool     is_lower_lows;               // 安値更新

   // Range Indicators
   bool     is_bb_squeezing;             // BBスクイーズ
   bool     is_bb_horizontal;            // BB水平
   bool     is_rsi_ranging;              // RSIレンジ内
   bool     is_rsi_near_center;          // RSI中心付近
   bool     is_ma_horizontal;            // MA水平
   bool     is_price_crossing_ma;        // 価格がMAを頻繁に交差

   // Trendless Indicators
   bool     is_adx_very_low;             // ADX非常に低い
   bool     is_in_ichimoku_cloud;        // 一目雲内
   bool     is_atr_declining;            // ATR減少
   bool     is_atr_low;                  // ATR低水準

   // Raw Values
   double   adx_value;                   // ADX現在値
   double   rsi_value;                   // RSI現在値
   double   atr_value;                   // ATR現在値
   double   atr_average;                 // ATR平均値
   double   bb_width;                    // BBバンド幅
   double   bb_width_average;            // BBバンド幅平均

   // Scores (0-100)
   int      trend_score;                 // トレンドスコア
   int      range_score;                 // レンジスコア
   int      trendless_score;             // トレンドレススコア

   // Final Regime
   ENUM_MARKET_REGIME regime;            // 判定結果
   string   regime_description;          // 判定説明

   MarketAnalysisResult()
   {
      is_perfect_order_bullish = false;
      is_perfect_order_bearish = false;
      is_ma_sloping_up = false;
      is_ma_sloping_down = false;
      is_bb_expanding = false;
      is_band_walk_upper = false;
      is_band_walk_lower = false;
      is_adx_trending = false;
      is_adx_rising = false;
      is_higher_highs = false;
      is_higher_lows = false;
      is_lower_highs = false;
      is_lower_lows = false;

      is_bb_squeezing = false;
      is_bb_horizontal = false;
      is_rsi_ranging = false;
      is_rsi_near_center = false;
      is_ma_horizontal = false;
      is_price_crossing_ma = false;

      is_adx_very_low = false;
      is_in_ichimoku_cloud = false;
      is_atr_declining = false;
      is_atr_low = false;

      adx_value = 0;
      rsi_value = 0;
      atr_value = 0;
      atr_average = 0;
      bb_width = 0;
      bb_width_average = 0;

      trend_score = 0;
      range_score = 0;
      trendless_score = 0;

      regime = MARKET_REGIME_TRENDLESS;
      regime_description = "";
   }
};

//+------------------------------------------------------------------+
//| CMarketRegime Class - Market Condition Recognition               |
//+------------------------------------------------------------------+
class CMarketRegime
{
private:
   string               m_symbol;           // シンボル
   ENUM_TIMEFRAMES      m_timeframe;        // タイムフレーム（D1固定）
   MarketRegimeParams   m_params;           // パラメータ
   MarketAnalysisResult m_result;           // 分析結果

   // Indicator Handles
   int      m_ma_short_handle;
   int      m_ma_medium_handle;
   int      m_ma_long_handle;
   int      m_adx_handle;
   int      m_bb_handle;
   int      m_rsi_handle;
   int      m_atr_handle;
   int      m_ichimoku_handle;

   // Cache for optimization
   datetime m_last_calc_time;              // 最終計算時刻
   bool     m_is_initialized;              // 初期化フラグ

   // Private Methods
   bool     CreateIndicators();
   void     ReleaseIndicators();
   bool     AnalyzeTrendConditions();
   bool     AnalyzeRangeConditions();
   bool     AnalyzeTrendlessConditions();
   bool     AnalyzePriceAction();
   void     CalculateScores();
   ENUM_MARKET_REGIME DetermineRegime();

   // Helper Methods
   double   GetMASlope(int ma_handle, int period);
   bool     IsBandWalk(bool upper);
   int      CountMACrossings(int lookback);
   bool     FindSwingHighLow(double &swing_high, double &swing_low, int lookback);
   double   CalculateBBWidth(int shift);
   double   GetAverageBBWidth(int lookback);
   double   GetAverageATR(int lookback);

public:
   // Constructor / Destructor
                     CMarketRegime();
                    ~CMarketRegime();

   // Initialization
   bool              Init(string symbol, MarketRegimeParams &params);
   bool              Init(string symbol);  // Use default params
   void              Deinit();

   // Main Analysis Function
   ENUM_MARKET_REGIME Analyze(bool force_update = false);

   // Getters
   ENUM_MARKET_REGIME GetCurrentRegime() const { return m_result.regime; }
   MarketAnalysisResult GetAnalysisResult() const { return m_result; }
   string            GetRegimeString() const;
   string            GetRegimeDescription() const { return m_result.regime_description; }

   // Score Getters
   int               GetTrendScore() const { return m_result.trend_score; }
   int               GetRangeScore() const { return m_result.range_score; }
   int               GetTrendlessScore() const { return m_result.trendless_score; }

   // Individual Indicator Checks
   bool              IsTrending() const { return m_result.is_adx_trending; }
   bool              IsRanging() const { return m_result.is_bb_squeezing && m_result.is_rsi_ranging; }
   bool              IsTrendless() const { return m_result.is_adx_very_low; }

   // Update Parameters
   void              SetParams(MarketRegimeParams &params) { m_params = params; }
   MarketRegimeParams GetParams() const { return m_params; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CMarketRegime::CMarketRegime()
{
   m_symbol = "";
   m_timeframe = PERIOD_D1;  // 日足固定
   m_is_initialized = false;
   m_last_calc_time = 0;

   m_ma_short_handle = INVALID_HANDLE;
   m_ma_medium_handle = INVALID_HANDLE;
   m_ma_long_handle = INVALID_HANDLE;
   m_adx_handle = INVALID_HANDLE;
   m_bb_handle = INVALID_HANDLE;
   m_rsi_handle = INVALID_HANDLE;
   m_atr_handle = INVALID_HANDLE;
   m_ichimoku_handle = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CMarketRegime::~CMarketRegime()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize with custom parameters                                 |
//+------------------------------------------------------------------+
bool CMarketRegime::Init(string symbol, MarketRegimeParams &params)
{
   if(m_is_initialized)
      Deinit();

   m_symbol = symbol;
   m_params = params;
   m_timeframe = PERIOD_D1;  // 常に日足を使用

   if(!CreateIndicators())
   {
      Print("CMarketRegime: Failed to create indicators");
      return false;
   }

   m_is_initialized = true;
   return true;
}

//+------------------------------------------------------------------+
//| Initialize with default parameters                                |
//+------------------------------------------------------------------+
bool CMarketRegime::Init(string symbol)
{
   MarketRegimeParams default_params;
   return Init(symbol, default_params);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CMarketRegime::Deinit()
{
   ReleaseIndicators();
   m_is_initialized = false;
}

//+------------------------------------------------------------------+
//| Create all indicator handles                                      |
//+------------------------------------------------------------------+
bool CMarketRegime::CreateIndicators()
{
   // Moving Averages (EMA)
   m_ma_short_handle = iMA(m_symbol, m_timeframe, m_params.ma_short_period, 0, MODE_EMA, PRICE_CLOSE);
   if(m_ma_short_handle == INVALID_HANDLE)
   {
      Print("Failed to create short MA indicator");
      return false;
   }

   m_ma_medium_handle = iMA(m_symbol, m_timeframe, m_params.ma_medium_period, 0, MODE_EMA, PRICE_CLOSE);
   if(m_ma_medium_handle == INVALID_HANDLE)
   {
      Print("Failed to create medium MA indicator");
      return false;
   }

   m_ma_long_handle = iMA(m_symbol, m_timeframe, m_params.ma_long_period, 0, MODE_SMA, PRICE_CLOSE);
   if(m_ma_long_handle == INVALID_HANDLE)
   {
      Print("Failed to create long MA indicator");
      return false;
   }

   // ADX
   m_adx_handle = iADX(m_symbol, m_timeframe, m_params.adx_period);
   if(m_adx_handle == INVALID_HANDLE)
   {
      Print("Failed to create ADX indicator");
      return false;
   }

   // Bollinger Bands
   m_bb_handle = iBands(m_symbol, m_timeframe, m_params.bb_period, 0, m_params.bb_deviation, PRICE_CLOSE);
   if(m_bb_handle == INVALID_HANDLE)
   {
      Print("Failed to create Bollinger Bands indicator");
      return false;
   }

   // RSI
   m_rsi_handle = iRSI(m_symbol, m_timeframe, m_params.rsi_period, PRICE_CLOSE);
   if(m_rsi_handle == INVALID_HANDLE)
   {
      Print("Failed to create RSI indicator");
      return false;
   }

   // ATR
   m_atr_handle = iATR(m_symbol, m_timeframe, m_params.atr_period);
   if(m_atr_handle == INVALID_HANDLE)
   {
      Print("Failed to create ATR indicator");
      return false;
   }

   // Ichimoku
   m_ichimoku_handle = iIchimoku(m_symbol, m_timeframe, m_params.ichi_tenkan, m_params.ichi_kijun, m_params.ichi_senkou);
   if(m_ichimoku_handle == INVALID_HANDLE)
   {
      Print("Failed to create Ichimoku indicator");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Release all indicator handles                                     |
//+------------------------------------------------------------------+
void CMarketRegime::ReleaseIndicators()
{
   if(m_ma_short_handle != INVALID_HANDLE)  { IndicatorRelease(m_ma_short_handle);  m_ma_short_handle = INVALID_HANDLE; }
   if(m_ma_medium_handle != INVALID_HANDLE) { IndicatorRelease(m_ma_medium_handle); m_ma_medium_handle = INVALID_HANDLE; }
   if(m_ma_long_handle != INVALID_HANDLE)   { IndicatorRelease(m_ma_long_handle);   m_ma_long_handle = INVALID_HANDLE; }
   if(m_adx_handle != INVALID_HANDLE)       { IndicatorRelease(m_adx_handle);       m_adx_handle = INVALID_HANDLE; }
   if(m_bb_handle != INVALID_HANDLE)        { IndicatorRelease(m_bb_handle);        m_bb_handle = INVALID_HANDLE; }
   if(m_rsi_handle != INVALID_HANDLE)       { IndicatorRelease(m_rsi_handle);       m_rsi_handle = INVALID_HANDLE; }
   if(m_atr_handle != INVALID_HANDLE)       { IndicatorRelease(m_atr_handle);       m_atr_handle = INVALID_HANDLE; }
   if(m_ichimoku_handle != INVALID_HANDLE)  { IndicatorRelease(m_ichimoku_handle);  m_ichimoku_handle = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Main Analysis Function                                            |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CMarketRegime::Analyze(bool force_update)
{
   if(!m_is_initialized)
   {
      Print("CMarketRegime: Not initialized");
      return MARKET_REGIME_TRENDLESS;
   }

   // 新しい日足が確定したかチェック（計算負荷軽減）
   datetime current_bar_time = iTime(m_symbol, m_timeframe, 0);
   if(!force_update && current_bar_time == m_last_calc_time)
   {
      return m_result.regime;  // キャッシュされた結果を返す
   }

   // Reset result
   MarketAnalysisResult new_result;
   m_result = new_result;

   // Analyze all conditions
   if(!AnalyzeTrendConditions())
   {
      Print("CMarketRegime: Failed to analyze trend conditions");
   }

   if(!AnalyzeRangeConditions())
   {
      Print("CMarketRegime: Failed to analyze range conditions");
   }

   if(!AnalyzeTrendlessConditions())
   {
      Print("CMarketRegime: Failed to analyze trendless conditions");
   }

   if(!AnalyzePriceAction())
   {
      Print("CMarketRegime: Failed to analyze price action");
   }

   // Calculate scores and determine regime
   CalculateScores();
   m_result.regime = DetermineRegime();

   // Update cache time
   m_last_calc_time = current_bar_time;

   return m_result.regime;
}

//+------------------------------------------------------------------+
//| Analyze Trend Conditions                                          |
//+------------------------------------------------------------------+
bool CMarketRegime::AnalyzeTrendConditions()
{
   double ma_short[], ma_medium[], ma_long[];
   double adx_main[], adx_plus[], adx_minus[];
   double bb_upper[], bb_middle[], bb_lower[];

   ArraySetAsSeries(ma_short, true);
   ArraySetAsSeries(ma_medium, true);
   ArraySetAsSeries(ma_long, true);
   ArraySetAsSeries(adx_main, true);
   ArraySetAsSeries(adx_plus, true);
   ArraySetAsSeries(adx_minus, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_lower, true);

   int bars_needed = m_params.bars_to_analyze;

   // Get MA values
   if(CopyBuffer(m_ma_short_handle, 0, 0, bars_needed, ma_short) <= 0) return false;
   if(CopyBuffer(m_ma_medium_handle, 0, 0, bars_needed, ma_medium) <= 0) return false;
   if(CopyBuffer(m_ma_long_handle, 0, 0, bars_needed, ma_long) <= 0) return false;

   // Get ADX values
   if(CopyBuffer(m_adx_handle, 0, 0, bars_needed, adx_main) <= 0) return false;
   if(CopyBuffer(m_adx_handle, 1, 0, bars_needed, adx_plus) <= 0) return false;
   if(CopyBuffer(m_adx_handle, 2, 0, bars_needed, adx_minus) <= 0) return false;

   // Get BB values
   if(CopyBuffer(m_bb_handle, 0, 0, bars_needed, bb_middle) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 1, 0, bars_needed, bb_upper) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 2, 0, bars_needed, bb_lower) <= 0) return false;

   // === Perfect Order Check ===
   // Bullish: Short > Medium > Long
   m_result.is_perfect_order_bullish = (ma_short[0] > ma_medium[0]) && (ma_medium[0] > ma_long[0]);
   // Bearish: Short < Medium < Long
   m_result.is_perfect_order_bearish = (ma_short[0] < ma_medium[0]) && (ma_medium[0] < ma_long[0]);

   // === MA Slope Check ===
   double short_slope = GetMASlope(m_ma_short_handle, m_params.ma_slope_period);
   double medium_slope = GetMASlope(m_ma_medium_handle, m_params.ma_slope_period);

   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double slope_threshold = m_params.ma_slope_threshold / point;

   m_result.is_ma_sloping_up = (short_slope > slope_threshold) && (medium_slope > 0);
   m_result.is_ma_sloping_down = (short_slope < -slope_threshold) && (medium_slope < 0);

   // === ADX Check ===
   m_result.adx_value = adx_main[0];
   m_result.is_adx_trending = adx_main[0] >= m_params.adx_trend_threshold;
   m_result.is_adx_rising = (adx_main[0] > adx_main[1]) && (adx_main[1] > adx_main[2]);

   // === Bollinger Band Expansion Check ===
   m_result.bb_width = bb_upper[0] - bb_lower[0];
   m_result.bb_width_average = GetAverageBBWidth(m_params.atr_lookback);

   m_result.is_bb_expanding = m_result.bb_width > (m_result.bb_width_average * m_params.bb_expansion_ratio);

   // === Band Walk Check ===
   m_result.is_band_walk_upper = IsBandWalk(true);
   m_result.is_band_walk_lower = IsBandWalk(false);

   return true;
}

//+------------------------------------------------------------------+
//| Analyze Range Conditions                                          |
//+------------------------------------------------------------------+
bool CMarketRegime::AnalyzeRangeConditions()
{
   double rsi[];
   double bb_upper[], bb_middle[], bb_lower[];

   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_lower, true);

   int bars_needed = m_params.bars_to_analyze;

   // Get RSI values
   if(CopyBuffer(m_rsi_handle, 0, 0, bars_needed, rsi) <= 0) return false;

   // Get BB values
   if(CopyBuffer(m_bb_handle, 0, 0, bars_needed, bb_middle) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 1, 0, bars_needed, bb_upper) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 2, 0, bars_needed, bb_lower) <= 0) return false;

   // === RSI Check ===
   m_result.rsi_value = rsi[0];
   m_result.is_rsi_ranging = (rsi[0] >= m_params.rsi_lower) && (rsi[0] <= m_params.rsi_upper);
   m_result.is_rsi_near_center = MathAbs(rsi[0] - 50.0) <= m_params.rsi_center_range;

   // === BB Squeeze Check ===
   m_result.is_bb_squeezing = m_result.bb_width < (m_result.bb_width_average * m_params.bb_squeeze_ratio);

   // === BB Horizontal Check ===
   // Check if middle band is relatively flat
   double bb_middle_slope = 0;
   if(bars_needed >= m_params.ma_slope_period + 1)
   {
      bb_middle_slope = (bb_middle[0] - bb_middle[m_params.ma_slope_period]) / m_params.ma_slope_period;
   }
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_result.is_bb_horizontal = MathAbs(bb_middle_slope) < (m_params.ma_slope_threshold / point * 0.5);

   // === MA Horizontal Check ===
   double ma_slope = GetMASlope(m_ma_medium_handle, m_params.ma_slope_period);
   m_result.is_ma_horizontal = MathAbs(ma_slope) < (m_params.ma_slope_threshold / point * 0.3);

   // === Price Crossing MA Check ===
   int crossings = CountMACrossings(m_params.swing_lookback);
   m_result.is_price_crossing_ma = (crossings >= 4);  // 頻繁な交差

   return true;
}

//+------------------------------------------------------------------+
//| Analyze Trendless Conditions                                      |
//+------------------------------------------------------------------+
bool CMarketRegime::AnalyzeTrendlessConditions()
{
   double adx_main[];
   double atr[];
   double senkou_a[], senkou_b[];

   ArraySetAsSeries(adx_main, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(senkou_a, true);
   ArraySetAsSeries(senkou_b, true);

   int bars_needed = m_params.bars_to_analyze;

   // Get ADX values
   if(CopyBuffer(m_adx_handle, 0, 0, bars_needed, adx_main) <= 0) return false;

   // Get ATR values
   if(CopyBuffer(m_atr_handle, 0, 0, bars_needed, atr) <= 0) return false;

   // Get Ichimoku Senkou Span values (雲)
   if(CopyBuffer(m_ichimoku_handle, 2, 0, bars_needed, senkou_a) <= 0) return false;
   if(CopyBuffer(m_ichimoku_handle, 3, 0, bars_needed, senkou_b) <= 0) return false;

   // === ADX Very Low Check ===
   m_result.is_adx_very_low = adx_main[0] < m_params.adx_trendless_threshold;

   // === ATR Check ===
   m_result.atr_value = atr[0];
   m_result.atr_average = GetAverageATR(m_params.atr_lookback);

   m_result.is_atr_low = atr[0] < (m_result.atr_average * m_params.atr_low_threshold);
   m_result.is_atr_declining = (atr[0] < atr[1]) && (atr[1] < atr[2]) && (atr[2] < atr[3]);

   // === Ichimoku Cloud Check ===
   double close = iClose(m_symbol, m_timeframe, 0);
   double cloud_top = MathMax(senkou_a[0], senkou_b[0]);
   double cloud_bottom = MathMin(senkou_a[0], senkou_b[0]);

   m_result.is_in_ichimoku_cloud = (close >= cloud_bottom) && (close <= cloud_top);

   return true;
}

//+------------------------------------------------------------------+
//| Analyze Price Action (Swing High/Low)                             |
//+------------------------------------------------------------------+
bool CMarketRegime::AnalyzePriceAction()
{
   double high[], low[], close[];

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int bars_needed = m_params.bars_to_analyze;

   if(CopyHigh(m_symbol, m_timeframe, 0, bars_needed, high) <= 0) return false;
   if(CopyLow(m_symbol, m_timeframe, 0, bars_needed, low) <= 0) return false;
   if(CopyClose(m_symbol, m_timeframe, 0, bars_needed, close) <= 0) return false;

   // Find recent swing points
   int strength = m_params.swing_strength;
   int lookback = m_params.swing_lookback;

   double swing_highs[4] = {0, 0, 0, 0};
   double swing_lows[4] = {0, 0, 0, 0};
   int sh_count = 0, sl_count = 0;

   for(int i = strength; i < lookback - strength && (sh_count < 4 || sl_count < 4); i++)
   {
      // Check for swing high
      if(sh_count < 4)
      {
         bool is_swing_high = true;
         for(int j = 1; j <= strength; j++)
         {
            if(high[i] <= high[i-j] || high[i] <= high[i+j])
            {
               is_swing_high = false;
               break;
            }
         }
         if(is_swing_high)
         {
            swing_highs[sh_count++] = high[i];
         }
      }

      // Check for swing low
      if(sl_count < 4)
      {
         bool is_swing_low = true;
         for(int j = 1; j <= strength; j++)
         {
            if(low[i] >= low[i-j] || low[i] >= low[i+j])
            {
               is_swing_low = false;
               break;
            }
         }
         if(is_swing_low)
         {
            swing_lows[sl_count++] = low[i];
         }
      }
   }

   // Analyze swing patterns (most recent swings first in array)
   if(sh_count >= 2 && sl_count >= 2)
   {
      // Higher Highs: 最新の高値 > 前回の高値
      m_result.is_higher_highs = swing_highs[0] > swing_highs[1];
      // Higher Lows: 最新の安値 > 前回の安値
      m_result.is_higher_lows = swing_lows[0] > swing_lows[1];
      // Lower Highs: 最新の高値 < 前回の高値
      m_result.is_lower_highs = swing_highs[0] < swing_highs[1];
      // Lower Lows: 最新の安値 < 前回の安値
      m_result.is_lower_lows = swing_lows[0] < swing_lows[1];
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate Scores for Each Regime                                  |
//+------------------------------------------------------------------+
void CMarketRegime::CalculateScores()
{
   // === Trend Score (0-100) ===
   int trend_score = 0;

   // Perfect Order: +20 points
   if(m_result.is_perfect_order_bullish || m_result.is_perfect_order_bearish)
      trend_score += 20;

   // MA Slope: +15 points
   if(m_result.is_ma_sloping_up || m_result.is_ma_sloping_down)
      trend_score += 15;

   // ADX Trending: +20 points
   if(m_result.is_adx_trending)
      trend_score += 20;

   // ADX Rising: +10 points
   if(m_result.is_adx_rising)
      trend_score += 10;

   // BB Expansion: +15 points
   if(m_result.is_bb_expanding)
      trend_score += 15;

   // Band Walk: +10 points
   if(m_result.is_band_walk_upper || m_result.is_band_walk_lower)
      trend_score += 10;

   // Price Action (Dow Theory): +10 points
   if((m_result.is_higher_highs && m_result.is_higher_lows) ||
      (m_result.is_lower_highs && m_result.is_lower_lows))
      trend_score += 10;

   m_result.trend_score = MathMin(trend_score, 100);

   // === Range Score (0-100) ===
   int range_score = 0;

   // BB Squeeze: +25 points
   if(m_result.is_bb_squeezing)
      range_score += 25;

   // BB Horizontal: +15 points
   if(m_result.is_bb_horizontal)
      range_score += 15;

   // RSI Ranging: +15 points
   if(m_result.is_rsi_ranging)
      range_score += 15;

   // RSI Near Center: +15 points
   if(m_result.is_rsi_near_center)
      range_score += 15;

   // MA Horizontal: +15 points
   if(m_result.is_ma_horizontal)
      range_score += 15;

   // Price Crossing MA: +15 points
   if(m_result.is_price_crossing_ma)
      range_score += 15;

   m_result.range_score = MathMin(range_score, 100);

   // === Trendless Score (0-100) ===
   int trendless_score = 0;

   // ADX Very Low: +30 points
   if(m_result.is_adx_very_low)
      trendless_score += 30;

   // In Ichimoku Cloud: +25 points
   if(m_result.is_in_ichimoku_cloud)
      trendless_score += 25;

   // ATR Low: +20 points
   if(m_result.is_atr_low)
      trendless_score += 20;

   // ATR Declining: +15 points
   if(m_result.is_atr_declining)
      trendless_score += 15;

   // No clear price action pattern: +10 points
   if(!m_result.is_higher_highs && !m_result.is_lower_lows)
      trendless_score += 10;

   m_result.trendless_score = MathMin(trendless_score, 100);
}

//+------------------------------------------------------------------+
//| Determine Final Market Regime                                     |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CMarketRegime::DetermineRegime()
{
   ENUM_MARKET_REGIME regime = MARKET_REGIME_TRENDLESS;
   string description = "";

   // === Decision Logic ===
   // 複数指標の一致を重視（ダマシ回避）

   // Trend判定: スコア60以上かつ複数条件一致
   bool trend_confirmed = (m_result.trend_score >= 60) &&
                          (m_result.is_adx_trending || m_result.is_adx_rising) &&
                          (m_result.is_perfect_order_bullish || m_result.is_perfect_order_bearish ||
                           m_result.is_ma_sloping_up || m_result.is_ma_sloping_down);

   if(trend_confirmed)
   {
      // 方向判定
      bool bullish = m_result.is_perfect_order_bullish ||
                     m_result.is_ma_sloping_up ||
                     m_result.is_band_walk_upper ||
                     (m_result.is_higher_highs && m_result.is_higher_lows);

      bool bearish = m_result.is_perfect_order_bearish ||
                     m_result.is_ma_sloping_down ||
                     m_result.is_band_walk_lower ||
                     (m_result.is_lower_highs && m_result.is_lower_lows);

      if(bullish && !bearish)
      {
         regime = MARKET_REGIME_TREND_UP;
         description = "上昇トレンド: ";
         if(m_result.is_perfect_order_bullish) description += "パーフェクトオーダー ";
         if(m_result.is_bb_expanding) description += "BBエクスパンション ";
         if(m_result.is_adx_trending) description += StringFormat("ADX=%.1f ", m_result.adx_value);
      }
      else if(bearish && !bullish)
      {
         regime = MARKET_REGIME_TREND_DOWN;
         description = "下降トレンド: ";
         if(m_result.is_perfect_order_bearish) description += "パーフェクトオーダー ";
         if(m_result.is_bb_expanding) description += "BBエクスパンション ";
         if(m_result.is_adx_trending) description += StringFormat("ADX=%.1f ", m_result.adx_value);
      }
   }

   // Range判定: レンジスコアが高くトレンドスコアが低い
   if(regime == MARKET_REGIME_TRENDLESS && m_result.range_score >= 50 && m_result.trend_score < 40)
   {
      regime = MARKET_REGIME_RANGE;
      description = "レンジ相場: ";
      if(m_result.is_bb_squeezing) description += "BBスクイーズ ";
      if(m_result.is_rsi_near_center) description += StringFormat("RSI=%.1f ", m_result.rsi_value);
      if(m_result.is_price_crossing_ma) description += "MA交差頻発 ";
   }

   // Trendless判定: デフォルトまたは明確なトレンドレス条件
   if(regime == MARKET_REGIME_TRENDLESS)
   {
      description = "トレンドレス: ";
      if(m_result.is_adx_very_low) description += StringFormat("ADX=%.1f(低) ", m_result.adx_value);
      if(m_result.is_in_ichimoku_cloud) description += "雲内 ";
      if(m_result.is_atr_low) description += "低ボラティリティ ";
   }

   m_result.regime_description = description;

   return regime;
}

//+------------------------------------------------------------------+
//| Helper: Get MA Slope                                              |
//+------------------------------------------------------------------+
double CMarketRegime::GetMASlope(int ma_handle, int period)
{
   double ma_values[];
   ArraySetAsSeries(ma_values, true);

   if(CopyBuffer(ma_handle, 0, 0, period + 1, ma_values) <= 0)
      return 0;

   return (ma_values[0] - ma_values[period]) / period;
}

//+------------------------------------------------------------------+
//| Helper: Check for Band Walk                                       |
//+------------------------------------------------------------------+
bool CMarketRegime::IsBandWalk(bool upper)
{
   double close[], bb_upper[], bb_lower[], bb_middle[];

   ArraySetAsSeries(close, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_middle, true);

   int lookback = 5;  // 直近5本のバーをチェック

   if(CopyClose(m_symbol, m_timeframe, 0, lookback, close) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 0, 0, lookback, bb_middle) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 1, 0, lookback, bb_upper) <= 0) return false;
   if(CopyBuffer(m_bb_handle, 2, 0, lookback, bb_lower) <= 0) return false;

   int count = 0;
   for(int i = 0; i < lookback; i++)
   {
      if(upper)
      {
         // 価格がミドルバンドより上にあり、アッパーバンドに近い
         double upper_zone = bb_middle[i] + (bb_upper[i] - bb_middle[i]) * 0.5;
         if(close[i] > upper_zone)
            count++;
      }
      else
      {
         // 価格がミドルバンドより下にあり、ローワーバンドに近い
         double lower_zone = bb_middle[i] - (bb_middle[i] - bb_lower[i]) * 0.5;
         if(close[i] < lower_zone)
            count++;
      }
   }

   return count >= 4;  // 5本中4本以上がバンドウォーク状態
}

//+------------------------------------------------------------------+
//| Helper: Count MA Crossings                                        |
//+------------------------------------------------------------------+
int CMarketRegime::CountMACrossings(int lookback)
{
   double close[], ma[];

   ArraySetAsSeries(close, true);
   ArraySetAsSeries(ma, true);

   if(CopyClose(m_symbol, m_timeframe, 0, lookback, close) <= 0) return 0;
   if(CopyBuffer(m_ma_medium_handle, 0, 0, lookback, ma) <= 0) return 0;

   int crossings = 0;
   bool was_above = close[lookback - 1] > ma[lookback - 1];

   for(int i = lookback - 2; i >= 0; i--)
   {
      bool is_above = close[i] > ma[i];
      if(is_above != was_above)
      {
         crossings++;
         was_above = is_above;
      }
   }

   return crossings;
}

//+------------------------------------------------------------------+
//| Helper: Calculate BB Width at Shift                               |
//+------------------------------------------------------------------+
double CMarketRegime::CalculateBBWidth(int shift)
{
   double bb_upper[], bb_lower[];

   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);

   if(CopyBuffer(m_bb_handle, 1, shift, 1, bb_upper) <= 0) return 0;
   if(CopyBuffer(m_bb_handle, 2, shift, 1, bb_lower) <= 0) return 0;

   return bb_upper[0] - bb_lower[0];
}

//+------------------------------------------------------------------+
//| Helper: Get Average BB Width                                      |
//+------------------------------------------------------------------+
double CMarketRegime::GetAverageBBWidth(int lookback)
{
   double total = 0;
   int count = 0;

   for(int i = 1; i <= lookback; i++)
   {
      double width = CalculateBBWidth(i);
      if(width > 0)
      {
         total += width;
         count++;
      }
   }

   return count > 0 ? total / count : 0;
}

//+------------------------------------------------------------------+
//| Helper: Get Average ATR                                           |
//+------------------------------------------------------------------+
double CMarketRegime::GetAverageATR(int lookback)
{
   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(m_atr_handle, 0, 1, lookback, atr) <= 0)
      return 0;

   double total = 0;
   for(int i = 0; i < lookback; i++)
      total += atr[i];

   return total / lookback;
}

//+------------------------------------------------------------------+
//| Get Regime as String                                              |
//+------------------------------------------------------------------+
string CMarketRegime::GetRegimeString() const
{
   switch(m_result.regime)
   {
      case MARKET_REGIME_TREND_UP:   return "TREND_UP";
      case MARKET_REGIME_TREND_DOWN: return "TREND_DOWN";
      case MARKET_REGIME_RANGE:      return "RANGE";
      case MARKET_REGIME_TRENDLESS:  return "TRENDLESS";
      default:                        return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Utility Function: Get Market Regime (Standalone)                  |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME GetMarketRegime(string symbol, MarketRegimeParams &params)
{
   static CMarketRegime regime_detector;
   static bool is_init = false;
   static string last_symbol = "";

   if(!is_init || symbol != last_symbol)
   {
      regime_detector.Init(symbol, params);
      is_init = true;
      last_symbol = symbol;
   }

   return regime_detector.Analyze();
}

//+------------------------------------------------------------------+
//| Utility Function: Get Market Regime with Default Params           |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME GetMarketRegime(string symbol)
{
   MarketRegimeParams default_params;
   return GetMarketRegime(symbol, default_params);
}
//+------------------------------------------------------------------+
