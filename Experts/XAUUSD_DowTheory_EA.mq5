//+------------------------------------------------------------------+
//|                                         XAUUSD_DowTheory_EA.mq5 |
//|       Dow Theory + SMC Based XAUUSD Scalping/Day Trading EA      |
//|             Fintokei Challenge Plan Risk Management              |
//|                     Copyright 2024, Your Company                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property description "XAUUSD専用 ダウ理論ベース EA"
#property description "Fintokeiチャレンジプラン対応リスク管理"
#property description "スキャルピング/デイトレード用"

//--- Include modules
#include "../Include/DowTheory.mqh"
#include "../Include/RiskManager.mqh"
#include "../Include/SmartMoneyConcepts.mqh"
#include "../Include/TradeManager.mqh"
#include "../Include/ChartDisplay.mqh"
#include "../Include/ZigZagBreakout.mqh"
#include "../Include/DailyPivot.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//--- Fintokei Risk Management Parameters
input group "=== Fintokei Risk Management ==="
input double   InpInitialBalance     = 2000000.0;   // 初期残高 (JPY) - 200万円
input int      InpUTCDayResetHour    = 0;           // 日次リセットUTC時間 (0-23)
input double   InpDailyLossLimitPct  = 5.0;         // 1日の最大損失率 (%)
input double   InpOverallLossLimitPct = 10.0;       // 全体の最大損失率 (%)
input double   InpSafetyBufferPct    = 0.1;         // 安全バッファ (%)
input double   InpRiskPerTradePct    = 1.0;         // 1トレードあたりリスク (%)

//--- Trading Parameters
input group "=== Trading Parameters ==="
input int      InpMagicNumber        = 202412;      // マジックナンバー
input double   InpSlippage           = 30;          // スリッページ (points)
input int      InpMaxTradesPerDay    = 5;           // 1日の最大取引数
input double   InpATRMultiplierSL    = 2.0;         // ATR倍率 (SL用)
input double   InpATRMultiplierTP    = 3.0;         // ATR倍率 (TP用)

//--- Dow Theory Parameters
input group "=== Dow Theory Settings ==="
input ENUM_TIMEFRAMES InpHTFPeriod   = PERIOD_H4;   // 上位時間足 (トレンド判定)
input ENUM_TIMEFRAMES InpBasePeriod  = PERIOD_H1;   // 基準時間足 (エントリー)
input ENUM_TIMEFRAMES InpEntryPeriod = PERIOD_M15;  // エントリー時間足
input int      InpLookbackBars       = 100;         // ルックバック本数

//--- SMC Parameters
input group "=== Smart Money Concepts ==="
input bool     InpUseSMC             = true;        // SMC分析を使用
input bool     InpUseOrderBlocks     = true;        // オーダーブロックを使用
input bool     InpUseFVG             = true;        // FVGを使用

//--- Session Filter Parameters
input group "=== Session Filter ==="
input bool     InpUseSessionFilter   = true;        // セッションフィルターを使用
input int      InpLondonStartHour    = 8;           // ロンドンセッション開始 (GMT)
input int      InpLondonEndHour      = 17;          // ロンドンセッション終了 (GMT)
input int      InpNYStartHour        = 13;          // NYセッション開始 (GMT)
input int      InpNYEndHour          = 22;          // NYセッション終了 (GMT)
input bool     InpTradeOverlapOnly   = true;        // オーバーラップ時間のみ取引

//--- Trading Hours Filter (NEW)
input group "=== Trading Hours Filter ==="
input bool     InpUseTimeFilter      = true;        // 取引時間フィルターを使用
input int      InpTradeStartHour     = 12;          // 取引開始時間 (GMT, 0-23)
input int      InpTradeEndHour       = 16;          // 取引終了時間 (GMT, 0-23)

//--- Indicator Parameters
input group "=== Technical Indicators ==="
input int      InpEMAPeriodFast      = 9;           // EMA期間 (高速)
input int      InpEMAPeriodSlow      = 21;          // EMA期間 (低速)
input int      InpRSIPeriod          = 14;          // RSI期間
input int      InpRSIOverbought      = 70;          // RSI買われすぎ
input int      InpRSIOversold        = 30;          // RSI売られすぎ
input int      InpATRPeriod          = 14;          // ATR期間
input double   InpATRFilterMultiplier = 0.5;        // ATRボラティリティフィルター

//--- Trailing Stop Parameters
input group "=== Trailing Stop ==="
input bool     InpUseTrailing        = true;        // トレーリングストップを使用
input double   InpTrailingATRMult    = 1.5;         // トレーリングATR倍率
input bool     InpUseBreakEven       = true;        // ブレイクイーブンを使用
input double   InpBreakEvenATRMult   = 1.0;         // ブレイクイーブンATR倍率

//--- ZigZag Breakout Filter Parameters
input group "=== ZigZag Breakout Filter ==="
input bool     InpUseZigZag          = true;        // ZigZagフィルターを使用
input bool     InpZigZagStandalone   = true;        // B案: ZigZag単体エントリーを許可
input bool     InpZigZagDowReplace   = true;        // C案: ダウ理論をZigZagベースに置換
input int      InpZigZagDepth        = 12;          // ZigZag Depth
input int      InpZigZagDeviation    = 5;           // ZigZag Deviation
input int      InpZigZagBackstep     = 3;           // ZigZag Backstep

//--- Daily Pivot Take Profit Parameters (D案)
input group "=== Daily Pivot Take Profit (D案) ==="
input bool     InpUsePivotTP         = true;        // D案: PIVOTベース利確を使用
input double   InpPivotMaxRatio      = 1.5;         // PIVOT最大距離倍率 (ATR TP比)
input double   InpPivotMinRatio      = 0.3;         // PIVOT最小距離倍率 (近すぎる場合ATR TP)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// Module instances
CDowTheory        g_dowHTF;           // Higher timeframe Dow Theory
CDowTheory        g_dowBase;          // Base timeframe Dow Theory
CDowTheory        g_dowEntry;         // Entry timeframe Dow Theory
CRiskManager      g_riskMgr;          // Risk Manager
CSmartMoneyConcepts g_smcBase;        // SMC for base timeframe
CSmartMoneyConcepts g_smcEntry;       // SMC for entry timeframe
CTradeManager     g_tradeMgr;         // Trade Manager
CChartDisplay     g_display;          // Chart Display
CZigZagBreakout   g_zigzag;           // ZigZag Breakout Filter
CDailyPivot       g_pivot;            // Daily Pivot for TP (D案)

// Indicator handles
int g_emaFastHandle;
int g_emaSlowHandle;
int g_rsiHandle;
int g_atrHandle;

// State variables
datetime g_lastBarTime = 0;
bool g_isNewBar = false;
string g_currentSignal = "NONE";
int g_signalStrength = 0;
string g_currentSession = "---";
bool g_sessionActive = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(StringFind(Symbol(), "XAUUSD") < 0 && StringFind(Symbol(), "GOLD") < 0)
   {
      Print("Warning: This EA is designed for XAUUSD/GOLD. Current symbol: ", Symbol());
      // Continue anyway for testing purposes
   }

   // Initialize Risk Manager
   if(!g_riskMgr.Init(InpInitialBalance, InpUTCDayResetHour, InpDailyLossLimitPct,
                      InpOverallLossLimitPct, InpSafetyBufferPct, InpRiskPerTradePct))
   {
      Print("Error: Failed to initialize Risk Manager");
      return INIT_FAILED;
   }

   // Initialize Dow Theory modules
   if(!g_dowHTF.Init(Symbol(), InpHTFPeriod, InpLookbackBars))
   {
      Print("Error: Failed to initialize HTF Dow Theory");
      return INIT_FAILED;
   }

   if(!g_dowBase.Init(Symbol(), InpBasePeriod, InpLookbackBars))
   {
      Print("Error: Failed to initialize Base Dow Theory");
      return INIT_FAILED;
   }

   if(!g_dowEntry.Init(Symbol(), InpEntryPeriod, InpLookbackBars))
   {
      Print("Error: Failed to initialize Entry Dow Theory");
      return INIT_FAILED;
   }

   // Initialize SMC modules
   if(InpUseSMC)
   {
      if(!g_smcBase.Init(Symbol(), InpBasePeriod, InpLookbackBars))
      {
         Print("Error: Failed to initialize Base SMC");
         return INIT_FAILED;
      }

      if(!g_smcEntry.Init(Symbol(), InpEntryPeriod, InpLookbackBars))
      {
         Print("Error: Failed to initialize Entry SMC");
         return INIT_FAILED;
      }
   }

   // Initialize ZigZag Breakout Filter
   if(InpUseZigZag)
   {
      if(!g_zigzag.Init(Symbol(), InpBasePeriod, InpZigZagDepth, InpZigZagDeviation, InpZigZagBackstep))
      {
         Print("Warning: Failed to initialize ZigZag filter - continuing without it");
         // Continue without ZigZag - not critical
      }
   }

   // Initialize Daily Pivot (D案)
   if(InpUsePivotTP)
   {
      if(!g_pivot.Init(Symbol()))
      {
         Print("Warning: Failed to initialize Daily Pivot - using ATR-based TP only");
         // Continue without Pivot - not critical
      }
   }

   // Initialize Trade Manager
   if(!g_tradeMgr.Init(Symbol(), InpMagicNumber, InpSlippage, InpMaxTradesPerDay))
   {
      Print("Error: Failed to initialize Trade Manager");
      return INIT_FAILED;
   }

   // Initialize indicators
   g_emaFastHandle = iMA(Symbol(), InpBasePeriod, InpEMAPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(Symbol(), InpBasePeriod, InpEMAPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_rsiHandle = iRSI(Symbol(), InpBasePeriod, InpRSIPeriod, PRICE_CLOSE);
   g_atrHandle = iATR(Symbol(), InpBasePeriod, InpATRPeriod);

   if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicator handles");
      return INIT_FAILED;
   }

   // Initialize Chart Display
   g_display.Init("XAUUSD_DOW_", 20, 50);
   g_display.CreatePanel();

   Print("=== XAUUSD Dow Theory EA Initialized ===");
   Print("Initial Balance: ", InpInitialBalance, " JPY");
   Print("Daily Loss Limit: ", InpDailyLossLimitPct, "%");
   Print("Overall Loss Limit: ", InpOverallLossLimitPct, "%");
   Print("Risk Per Trade: ", InpRiskPerTradePct, "%");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Deinitialize modules
   g_dowHTF.Deinit();
   g_dowBase.Deinit();
   g_dowEntry.Deinit();
   g_riskMgr.Deinit();
   g_smcBase.Deinit();
   g_smcEntry.Deinit();
   g_zigzag.Deinit();
   g_tradeMgr.Deinit();
   g_display.Deinit();

   // Release indicator handles
   if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);

   Print("=== XAUUSD Dow Theory EA Deinitialized ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //=== Step 1: Risk Check (Every Tick) ===
   if(!g_riskMgr.CheckRisk())
   {
      // Emergency stop triggered
      g_display.UpdateEmergencyDisplay(true, g_riskMgr.GetLastError());
      return;
   }

   // Check if trading is allowed
   if(!g_riskMgr.CanTrade())
   {
      UpdateDisplayInfo();
      return;
   }

   //=== Step 2: Position Management ===
   if(g_tradeMgr.HasPosition())
   {
      ManagePosition();
      UpdateDisplayInfo();
      return;
   }

   //=== Step 3: Check for New Bar (Entry only on new bar) ===
   g_isNewBar = IsNewBar();
   if(!g_isNewBar)
   {
      UpdateDisplayInfo();
      return;
   }

   //=== Step 4: Session Filter ===
   if(InpUseSessionFilter && !IsValidSession())
   {
      g_currentSignal = "NONE (Session)";
      g_signalStrength = 0;
      UpdateDisplayInfo();
      return;
   }

   //=== Step 5: Update Analysis Modules ===
   UpdateAnalysis();

   //=== Step 6: Generate Entry Signal ===
   ENUM_TRADE_DIRECTION signal = GenerateEntrySignal();

   //=== Step 7: Execute Trade if Signal is Valid ===
   if(signal != TRADE_NONE && g_signalStrength >= 3)
   {
      ExecuteTrade(signal);
   }

   //=== Step 8: Update Display ===
   UpdateDisplayInfo();
}

//+------------------------------------------------------------------+
//| Check for New Bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol(), InpEntryPeriod, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check Valid Trading Session                                       |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   datetime gmtTime = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   int hour = dt.hour;

   bool inLondon = (hour >= InpLondonStartHour && hour < InpLondonEndHour);
   bool inNY = (hour >= InpNYStartHour && hour < InpNYEndHour);
   bool inOverlap = inLondon && inNY;

   // Update session info
   if(inOverlap)
   {
      g_currentSession = "London-NY Overlap";
      g_sessionActive = true;
   }
   else if(inLondon)
   {
      g_currentSession = "London";
      g_sessionActive = !InpTradeOverlapOnly;
   }
   else if(inNY)
   {
      g_currentSession = "New York";
      g_sessionActive = !InpTradeOverlapOnly;
   }
   else
   {
      g_currentSession = "Asian/Off";
      g_sessionActive = false;
   }

   // Session filter check
   bool sessionOK = InpTradeOverlapOnly ? inOverlap : (inLondon || inNY);

   // Trading hours filter (NEW)
   if(InpUseTimeFilter)
   {
      bool inTradingHours;
      if(InpTradeStartHour < InpTradeEndHour)
      {
         // 通常の時間帯 (例: 12:00 - 16:00)
         inTradingHours = (hour >= InpTradeStartHour && hour < InpTradeEndHour);
      }
      else
      {
         // 日をまたぐ時間帯 (例: 22:00 - 04:00)
         inTradingHours = (hour >= InpTradeStartHour || hour < InpTradeEndHour);
      }

      // Update session display with time filter info
      if(!inTradingHours)
      {
         g_currentSession = StringFormat("%s (時間外: %02d:00-%02d:00)",
                                          g_currentSession, InpTradeStartHour, InpTradeEndHour);
         g_sessionActive = false;
      }

      return sessionOK && inTradingHours;
   }

   return sessionOK;
}

//+------------------------------------------------------------------+
//| Update Analysis Modules                                           |
//+------------------------------------------------------------------+
void UpdateAnalysis()
{
   // Update Dow Theory analysis
   g_dowHTF.Update();
   g_dowBase.Update();
   g_dowEntry.Update();

   // Update SMC analysis
   if(InpUseSMC)
   {
      g_smcBase.Update();
      g_smcEntry.Update();
   }

   // Update ZigZag analysis
   if(InpUseZigZag)
   {
      g_zigzag.Update();
   }

   // Update Daily Pivot (D案)
   if(InpUsePivotTP)
   {
      g_pivot.Update();
   }
}

//+------------------------------------------------------------------+
//| Generate Entry Signal (Method 8 from prompt)                      |
//| Combines multiple technical factors                               |
//+------------------------------------------------------------------+
ENUM_TRADE_DIRECTION GenerateEntrySignal()
{
   g_signalStrength = 0;
   g_currentSignal = "NONE";

   int buyScore = 0;
   int sellScore = 0;

   //=== C案: ZigZagベースのトレンド検出 ===
   ENUM_DOW_TREND htfTrend;
   ENUM_DOW_TREND baseTrend;
   ENUM_DOW_TREND entryTrend;

   if(InpUseZigZag && InpZigZagDowReplace)
   {
      // ZigZagベースのトレンド検出
      int zigzagTrend = g_zigzag.GetZigZagDowTrend();

      // ZigZagトレンドをダウ理論トレンドに変換
      if(zigzagTrend > 0)
      {
         htfTrend = DOW_TREND_UP;
         baseTrend = DOW_TREND_UP;
         entryTrend = DOW_TREND_UP;
      }
      else if(zigzagTrend < 0)
      {
         htfTrend = DOW_TREND_DOWN;
         baseTrend = DOW_TREND_DOWN;
         entryTrend = DOW_TREND_DOWN;
      }
      else
      {
         htfTrend = DOW_TREND_RANGE;
         baseTrend = DOW_TREND_RANGE;
         entryTrend = DOW_TREND_RANGE;
      }

      // ZigZag HH/HL検出でスコア加算
      if(g_zigzag.IsZigZagUptrend())
         buyScore += 2;  // HH+HL確認で+2
      if(g_zigzag.IsZigZagDowntrend())
         sellScore += 2; // LH+LL確認で+2
   }
   else
   {
      // 従来のダウ理論トレンド検出
      htfTrend = g_dowHTF.GetCurrentTrend();
      baseTrend = g_dowBase.GetCurrentTrend();
      entryTrend = g_dowEntry.GetCurrentTrend();
   }

   //=== Factor 1: Dow Theory Trend (HTF) ===
   if(htfTrend == DOW_TREND_UP) buyScore++;
   else if(htfTrend == DOW_TREND_DOWN) sellScore++;

   //=== Factor 2: Dow Theory Trend (Base) ===
   if(baseTrend == DOW_TREND_UP) buyScore++;
   else if(baseTrend == DOW_TREND_DOWN) sellScore++;

   //=== Factor 3: MTF Alignment (Method 5) ===
   // All timeframes should align for strong signal
   if(htfTrend == DOW_TREND_UP && baseTrend == DOW_TREND_UP && entryTrend == DOW_TREND_UP)
      buyScore++;
   else if(htfTrend == DOW_TREND_DOWN && baseTrend == DOW_TREND_DOWN && entryTrend == DOW_TREND_DOWN)
      sellScore++;

   //=== Factor 4: MA Granville Confirmation (Method 6) ===
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   CopyBuffer(g_emaFastHandle, 0, 0, 3, emaFast);
   CopyBuffer(g_emaSlowHandle, 0, 0, 3, emaSlow);

   double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   // EMA alignment
   if(emaFast[0] > emaSlow[0] && currentPrice > emaFast[0])
      buyScore++;
   else if(emaFast[0] < emaSlow[0] && currentPrice < emaFast[0])
      sellScore++;

   // Price near EMA (Granville rebound)
   double deviation = MathAbs(currentPrice - emaSlow[0]) / emaSlow[0] * 100;
   if(deviation < 0.3) // Price close to MA
   {
      if(emaFast[0] > emaSlow[0] && currentPrice >= emaSlow[0])
         buyScore++; // Potential bounce up
      else if(emaFast[0] < emaSlow[0] && currentPrice <= emaSlow[0])
         sellScore++; // Potential bounce down
   }

   //=== Factor 5: RSI Filter ===
   double rsi[];
   ArraySetAsSeries(rsi, true);
   CopyBuffer(g_rsiHandle, 0, 0, 2, rsi);

   // RSI divergence/confirmation
   if(rsi[0] > 50 && rsi[0] < InpRSIOverbought)
      buyScore++;
   else if(rsi[0] < 50 && rsi[0] > InpRSIOversold)
      sellScore++;

   //=== Factor 6: SMC Confirmation ===
   if(InpUseSMC)
   {
      // Order Block proximity
      if(InpUseOrderBlocks)
      {
         OrderBlock ob;
         if(g_smcEntry.GetNearestBullishOB(currentPrice, ob))
         {
            // Check if price is near bullish OB
            if(currentPrice - ob.highPrice < ob.highPrice * 0.002) // Within 0.2%
               buyScore++;
         }
         if(g_smcEntry.GetNearestBearishOB(currentPrice, ob))
         {
            if(ob.lowPrice - currentPrice < ob.lowPrice * 0.002)
               sellScore++;
         }
      }

      // FVG proximity
      if(InpUseFVG)
      {
         FairValueGap fvg;
         if(g_smcEntry.GetNearestBullishFVG(currentPrice, fvg))
         {
            if(currentPrice - fvg.highPrice < fvg.highPrice * 0.002)
               buyScore++;
         }
         if(g_smcEntry.GetNearestBearishFVG(currentPrice, fvg))
         {
            if(fvg.lowPrice - currentPrice < fvg.lowPrice * 0.002)
               sellScore++;
         }
      }

      // BOS confirmation
      if(g_smcEntry.HasRecentBullishBOS(10))
         buyScore++;
      if(g_smcEntry.HasRecentBearishBOS(10))
         sellScore++;
   }

   //=== Factor 7: Trend Continuation Check (Method 3) ===
   if(g_dowBase.ConfirmTrendContinuity())
   {
      if(baseTrend == DOW_TREND_UP)
         buyScore++;
      else if(baseTrend == DOW_TREND_DOWN)
         sellScore++;
   }

   //=== Factor 8: Trend Reversal Check (Method 4) ===
   // Only add score if reversal is confirmed in our favor
   if(g_dowBase.CheckTrendReversalConfirmed())
   {
      if(baseTrend == DOW_TREND_DOWN) // Was down, now reversing up
         buyScore++;
      else if(baseTrend == DOW_TREND_UP) // Was up, now reversing down
         sellScore++;
   }

   //=== Factor 9: ATR Volatility Filter ===
   double atr[];
   ArraySetAsSeries(atr, true);
   CopyBuffer(g_atrHandle, 0, 0, 20, atr);

   double avgATR = 0;
   for(int i = 0; i < 20; i++) avgATR += atr[i];
   avgATR /= 20;

   // Trade only when volatility is normal (not too low or too high)
   if(atr[0] > avgATR * InpATRFilterMultiplier && atr[0] < avgATR * 2.0)
   {
      // Volatility is good for trading
      if(buyScore > sellScore) buyScore++;
      else if(sellScore > buyScore) sellScore++;
   }

   //=== Factor 10: ZigZag Breakout Filter ===
   bool zigzagBullishBreakout = false;
   bool zigzagBearishBreakout = false;

   if(InpUseZigZag)
   {
      // ZigZag confirms buy signal
      if(g_zigzag.ConfirmBuySignal())
         buyScore++;

      // ZigZag confirms sell signal
      if(g_zigzag.ConfirmSellSignal())
         sellScore++;

      // Strong breakout confirmation
      zigzagBullishBreakout = g_zigzag.IsBullishBreakout();
      zigzagBearishBreakout = g_zigzag.IsBearishBreakout();

      if(zigzagBullishBreakout && htfTrend == DOW_TREND_UP)
         buyScore += 2;  // 強いブレイクアウトは+2
      if(zigzagBearishBreakout && htfTrend == DOW_TREND_DOWN)
         sellScore += 2;  // 強いブレイクアウトは+2
   }

   //=== Determine Signal ===
   int maxScore = MathMax(buyScore, sellScore);
   g_signalStrength = maxScore;

   // Base score threshold
   int scoreThreshold = 3;

   //=== B案: ZigZag単体エントリー ===
   // ZigZagブレイクアウト単体でもエントリー可能
   if(InpUseZigZag && InpZigZagStandalone)
   {
      // ZigZag上方ブレイクアウト + 上位足が上昇トレンド
      if(zigzagBullishBreakout && htfTrend == DOW_TREND_UP)
      {
         g_currentSignal = "BUY (ZZ)";
         return TRADE_BUY;
      }

      // ZigZag下方ブレイクアウト + 上位足が下降トレンド
      if(zigzagBearishBreakout && htfTrend == DOW_TREND_DOWN)
      {
         g_currentSignal = "SELL (ZZ)";
         return TRADE_SELL;
      }
   }

   //=== 通常のスコアベースシグナル ===
   if(buyScore >= scoreThreshold && buyScore > sellScore)
   {
      g_currentSignal = "BUY";
      return TRADE_BUY;
   }
   else if(sellScore >= scoreThreshold && sellScore > buyScore)
   {
      g_currentSignal = "SELL";
      return TRADE_SELL;
   }

   g_currentSignal = "NONE";
   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_TRADE_DIRECTION direction)
{
   // Calculate ATR for dynamic SL/TP
   double atr[];
   ArraySetAsSeries(atr, true);
   CopyBuffer(g_atrHandle, 0, 0, 1, atr);

   double currentATR = atr[0];

   // Calculate lot size based on risk
   double stopLossPips = g_tradeMgr.PriceToPips(currentATR * InpATRMultiplierSL);
   double lotSize = g_riskMgr.CalculateLotSize(Symbol(), stopLossPips);

   // Get stop loss and take profit prices
   double sl, tp;
   double currentPrice = SymbolInfoDouble(Symbol(), direction == TRADE_BUY ? SYMBOL_ASK : SYMBOL_BID);

   if(direction == TRADE_BUY)
   {
      // For buy: try to use Dow Theory push low as SL if available
      double pushLow, returnHigh;
      if(g_dowBase.IdentifyKeyPivotPoints(pushLow, returnHigh) && pushLow > 0)
      {
         sl = pushLow - (currentATR * 0.2); // Slightly below push low
      }
      else
      {
         sl = currentPrice - (currentATR * InpATRMultiplierSL);
      }

      // Base TP from ATR
      double atrTP = currentPrice + (currentATR * InpATRMultiplierTP);
      tp = atrTP;

      // D案: Daily Pivot TP
      if(InpUsePivotTP)
      {
         double pivotTP = g_pivot.GetNearestResistance(currentPrice);
         if(pivotTP > 0)
         {
            double atrDistance = atrTP - currentPrice;
            double pivotDistance = pivotTP - currentPrice;

            // PIVOTが適切な距離にある場合のみ使用
            if(pivotDistance > atrDistance * InpPivotMinRatio &&
               pivotDistance < atrDistance * InpPivotMaxRatio)
            {
               tp = pivotTP;
               Print("D案: BUY TP set to Pivot R=", pivotTP, " (ATR TP=", atrTP, ")");
            }
            else
            {
               Print("D案: Pivot R=", pivotTP, " out of range, using ATR TP=", atrTP);
            }
         }
      }

      // Check for nearby resistance for TP (SMC)
      OrderBlock ob;
      if(InpUseSMC && g_smcBase.GetNearestBearishOB(currentPrice, ob))
      {
         if(ob.lowPrice < tp && ob.lowPrice > currentPrice)
         {
            tp = ob.lowPrice - (currentATR * 0.1); // Set TP before resistance
         }
      }

      string comment = StringFormat("DOW_BUY_S%d", g_signalStrength);
      if(g_tradeMgr.OpenBuy(lotSize, sl, tp, comment))
      {
         g_riskMgr.RecordTrade(); // Record trading day

         // Apply trailing and break even
         if(InpUseTrailing)
            g_tradeMgr.ApplyATRTrailing(InpTrailingATRMult);
         if(InpUseBreakEven)
            g_tradeMgr.SetBreakEven(currentATR * InpBreakEvenATRMult);

         Print("BUY Trade Opened: Lot=", lotSize, " SL=", sl, " TP=", tp, " Strength=", g_signalStrength);
      }
   }
   else if(direction == TRADE_SELL)
   {
      // For sell: try to use Dow Theory return high as SL if available
      double pushLow, returnHigh;
      if(g_dowBase.IdentifyKeyPivotPoints(pushLow, returnHigh) && returnHigh > 0)
      {
         sl = returnHigh + (currentATR * 0.2); // Slightly above return high
      }
      else
      {
         sl = currentPrice + (currentATR * InpATRMultiplierSL);
      }

      // Base TP from ATR
      double atrTP = currentPrice - (currentATR * InpATRMultiplierTP);
      tp = atrTP;

      // D案: Daily Pivot TP
      if(InpUsePivotTP)
      {
         double pivotTP = g_pivot.GetNearestSupport(currentPrice);
         if(pivotTP > 0)
         {
            double atrDistance = currentPrice - atrTP;
            double pivotDistance = currentPrice - pivotTP;

            // PIVOTが適切な距離にある場合のみ使用
            if(pivotDistance > atrDistance * InpPivotMinRatio &&
               pivotDistance < atrDistance * InpPivotMaxRatio)
            {
               tp = pivotTP;
               Print("D案: SELL TP set to Pivot S=", pivotTP, " (ATR TP=", atrTP, ")");
            }
            else
            {
               Print("D案: Pivot S=", pivotTP, " out of range, using ATR TP=", atrTP);
            }
         }
      }

      // Check for nearby support for TP (SMC)
      OrderBlock ob;
      if(InpUseSMC && g_smcBase.GetNearestBullishOB(currentPrice, ob))
      {
         if(ob.highPrice > tp && ob.highPrice < currentPrice)
         {
            tp = ob.highPrice + (currentATR * 0.1); // Set TP before support
         }
      }

      string comment = StringFormat("DOW_SELL_S%d", g_signalStrength);
      if(g_tradeMgr.OpenSell(lotSize, sl, tp, comment))
      {
         g_riskMgr.RecordTrade(); // Record trading day

         // Apply trailing and break even
         if(InpUseTrailing)
            g_tradeMgr.ApplyATRTrailing(InpTrailingATRMult);
         if(InpUseBreakEven)
            g_tradeMgr.SetBreakEven(currentATR * InpBreakEvenATRMult);

         Print("SELL Trade Opened: Lot=", lotSize, " SL=", sl, " TP=", tp, " Strength=", g_signalStrength);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Existing Position (Method 9 from prompt)                   |
//+------------------------------------------------------------------+
void ManagePosition()
{
   // Update trailing stop
   if(InpUseTrailing)
      g_tradeMgr.UpdateTrailing();

   // Update break even
   if(InpUseBreakEven)
      g_tradeMgr.UpdateBreakEven();

   // Check for exit signals
   ENUM_TRADE_DIRECTION currentDir = g_tradeMgr.GetCurrentDirection();

   // Check Dow Theory for exit
   ENUM_DOW_TREND baseTrend = g_dowBase.GetCurrentTrend();
   bool trendContinues = g_dowBase.ConfirmTrendContinuity();
   bool trendReversed = g_dowBase.CheckTrendReversalConfirmed();

   // Exit conditions
   if(currentDir == TRADE_BUY)
   {
      // Exit buy if trend reverses to down
      if(trendReversed && baseTrend == DOW_TREND_DOWN)
      {
         g_tradeMgr.ClosePosition(EXIT_SIGNAL);
         Print("BUY closed: Dow Theory trend reversal detected");
         return;
      }

      // Exit if trend continuity breaks
      if(!trendContinues && baseTrend == DOW_TREND_UP)
      {
         double profit = g_tradeMgr.GetUnrealizedProfit();
         if(profit > 0) // Only exit if profitable
         {
            g_tradeMgr.ClosePosition(EXIT_SIGNAL);
            Print("BUY closed: Trend continuity broken with profit");
            return;
         }
      }
   }
   else if(currentDir == TRADE_SELL)
   {
      // Exit sell if trend reverses to up
      if(trendReversed && baseTrend == DOW_TREND_UP)
      {
         g_tradeMgr.ClosePosition(EXIT_SIGNAL);
         Print("SELL closed: Dow Theory trend reversal detected");
         return;
      }

      // Exit if trend continuity breaks
      if(!trendContinues && baseTrend == DOW_TREND_DOWN)
      {
         double profit = g_tradeMgr.GetUnrealizedProfit();
         if(profit > 0)
         {
            g_tradeMgr.ClosePosition(EXIT_SIGNAL);
            Print("SELL closed: Trend continuity broken with profit");
            return;
         }
      }
   }

   // Check RSI for exit
   double rsi[];
   ArraySetAsSeries(rsi, true);
   CopyBuffer(g_rsiHandle, 0, 0, 1, rsi);

   if(currentDir == TRADE_BUY && rsi[0] > InpRSIOverbought)
   {
      double profit = g_tradeMgr.GetUnrealizedProfit();
      if(profit > 0)
      {
         g_tradeMgr.ClosePosition(EXIT_SIGNAL);
         Print("BUY closed: RSI overbought");
      }
   }
   else if(currentDir == TRADE_SELL && rsi[0] < InpRSIOversold)
   {
      double profit = g_tradeMgr.GetUnrealizedProfit();
      if(profit > 0)
      {
         g_tradeMgr.ClosePosition(EXIT_SIGNAL);
         Print("SELL closed: RSI oversold");
      }
   }
}

//+------------------------------------------------------------------+
//| Update Display Information                                        |
//+------------------------------------------------------------------+
void UpdateDisplayInfo()
{
   // Get position info
   string posDir = "NONE";
   double entry = 0, sl = 0, tp = 0, profit = 0;

   if(g_tradeMgr.HasPosition())
   {
      posDir = g_tradeMgr.GetCurrentDirection() == TRADE_BUY ? "BUY" : "SELL";
      entry = g_tradeMgr.GetEntryPrice();
      sl = g_tradeMgr.GetStopLoss();
      tp = g_tradeMgr.GetTakeProfit();
      profit = g_tradeMgr.GetUnrealizedProfit();
   }

   // Update all displays
   g_display.UpdateAll(
      g_riskMgr,
      g_dowBase,
      g_dowHTF,
      posDir,
      entry,
      sl,
      tp,
      profit,
      g_currentSignal,
      g_signalStrength,
      g_currentSession,
      g_sessionActive,
      g_tradeMgr.GetTotalTrades(),
      g_tradeMgr.GetWinRate(),
      g_tradeMgr.GetTotalProfit() - g_tradeMgr.GetTotalLoss()
   );
}

//+------------------------------------------------------------------+
//| TesterInit function - MT5 Optimizer Parameter Ranges              |
//| ストラテジーテスターで「最適化」を選択時に使用されます              |
//+------------------------------------------------------------------+
void OnTesterInit()
{
   // パラメータ最適化範囲の設定
   // 形式: ParameterSetRange("パラメータ名", 有効, 現在値, 開始値, ステップ, 終了値)

   //--- リスク管理パラメータ
   // 1トレードあたりリスク: 0.2% - 0.5% (ステップ 0.1%)
   ParameterSetRange("InpRiskPerTradePct", true, 0.3, 0.2, 0.1, 0.5);

   //--- ATRパラメータ（重要）
   // ATR倍率(SL用): 1.0 - 2.0 (ステップ 0.2)
   ParameterSetRange("InpATRMultiplierSL", true, 1.2, 1.0, 0.2, 2.0);

   // ATR倍率(TP用): 4.0 - 8.0 (ステップ 1.0)
   ParameterSetRange("InpATRMultiplierTP", true, 6.0, 4.0, 1.0, 8.0);

   //--- 取引制限パラメータ
   // 1日の最大取引数: 3 - 7 (ステップ 1)
   ParameterSetRange("InpMaxTradesPerDay", true, 5, 3, 1, 7);

   //--- 取引時間パラメータ
   // 取引開始時間: 10 - 14 (ステップ 1)
   ParameterSetRange("InpTradeStartHour", true, 12, 10, 1, 14);

   // 取引終了時間: 15 - 18 (ステップ 1)
   ParameterSetRange("InpTradeEndHour", true, 16, 15, 1, 18);

   //--- インジケーターパラメータ
   // EMA高速期間: 5 - 15 (ステップ 2)
   ParameterSetRange("InpEMAPeriodFast", true, 9, 5, 2, 15);

   // EMA低速期間: 15 - 30 (ステップ 5)
   ParameterSetRange("InpEMAPeriodSlow", true, 21, 15, 5, 30);

   // RSI期間: 10 - 20 (ステップ 2)
   ParameterSetRange("InpRSIPeriod", true, 14, 10, 2, 20);

   //--- トレーリングストップパラメータ
   // トレーリングATR倍率: 1.0 - 2.5 (ステップ 0.5)
   ParameterSetRange("InpTrailingATRMult", true, 1.5, 1.0, 0.5, 2.5);

   // ブレイクイーブンATR倍率: 0.5 - 1.5 (ステップ 0.5)
   ParameterSetRange("InpBreakEvenATRMult", true, 1.0, 0.5, 0.5, 1.5);

   //--- ZigZagパラメータ（オプション）
   // ZigZag Depth: 8 - 20 (ステップ 4)
   ParameterSetRange("InpZigZagDepth", false, 12, 8, 4, 20);

   // ZigZag Deviation: 3 - 7 (ステップ 2)
   ParameterSetRange("InpZigZagDeviation", false, 5, 3, 2, 7);

   // ZigZag Backstep: 2 - 4 (ステップ 1)
   ParameterSetRange("InpZigZagBackstep", false, 3, 2, 1, 4);

   //--- D案: Daily Pivotパラメータ
   // PIVOT最大距離倍率: 1.0 - 2.0 (ステップ 0.5)
   ParameterSetRange("InpPivotMaxRatio", true, 1.5, 1.0, 0.5, 2.0);

   // PIVOT最小距離倍率: 0.2 - 0.5 (ステップ 0.1)
   ParameterSetRange("InpPivotMinRatio", true, 0.3, 0.2, 0.1, 0.5);

   //--- 固定パラメータ（最適化しない）
   ParameterSetRange("InpInitialBalance", false, 2000000.0, 0, 0, 0);
   ParameterSetRange("InpDailyLossLimitPct", false, 5.0, 0, 0, 0);
   ParameterSetRange("InpOverallLossLimitPct", false, 10.0, 0, 0, 0);
   ParameterSetRange("InpSafetyBufferPct", false, 0.1, 0, 0, 0);
   ParameterSetRange("InpMagicNumber", false, 202412, 0, 0, 0);
   ParameterSetRange("InpUseSessionFilter", false, 1, 0, 0, 0);
   ParameterSetRange("InpTradeOverlapOnly", false, 1, 0, 0, 0);
   ParameterSetRange("InpUseSMC", false, 1, 0, 0, 0);
   ParameterSetRange("InpUseOrderBlocks", false, 1, 0, 0, 0);
   ParameterSetRange("InpUseFVG", false, 1, 0, 0, 0);
   ParameterSetRange("InpUseZigZag", false, 1, 0, 0, 0);
   ParameterSetRange("InpZigZagStandalone", false, 1, 0, 0, 0);
   ParameterSetRange("InpZigZagDowReplace", false, 1, 0, 0, 0);
   ParameterSetRange("InpUsePivotTP", false, 1, 0, 0, 0);

   Print("=== Optimizer Parameters Initialized ===");
}

//+------------------------------------------------------------------+
//| TesterDeinit function                                             |
//+------------------------------------------------------------------+
void OnTesterDeinit()
{
   Print("=== Optimization Complete ===");
}

//+------------------------------------------------------------------+
//| TesterPass function - Called after each optimization pass         |
//+------------------------------------------------------------------+
void OnTesterPass()
{
   // 各最適化パスの結果処理（必要に応じて）
}

//+------------------------------------------------------------------+
//| Tester function - Custom optimization criterion                   |
//| Fintokei対応カスタム最適化基準                                    |
//+------------------------------------------------------------------+
double OnTester()
{
   // カスタム最適化基準
   double winRate = g_tradeMgr.GetWinRate();
   double profitFactor = g_tradeMgr.GetTotalLoss() > 0 ?
                         g_tradeMgr.GetTotalProfit() / g_tradeMgr.GetTotalLoss() : 0;
   int totalTrades = g_tradeMgr.GetTotalTrades();
   double totalPL = g_tradeMgr.GetTotalProfit() - g_tradeMgr.GetTotalLoss();

   // Fintokei対応スコア計算:
   // 1. プロフィットファクター (PF > 1.0 を優先)
   // 2. 勝率 (高いほど良い)
   // 3. 取引数 (十分な取引数が必要)
   // 4. 総損益 (黒字を優先)

   double score = 0;
   if(totalTrades >= 50) // 最低50取引で信頼性確保
   {
      // PFボーナス (1.0以上で大きなボーナス)
      double pfBonus = profitFactor >= 1.0 ? profitFactor * 100 : profitFactor * 10;

      // 勝率ボーナス (70%以上で追加ボーナス)
      double wrBonus = winRate >= 70 ? winRate * 1.5 : winRate;

      // 利益ボーナス (黒字なら追加)
      double plBonus = totalPL > 0 ? MathSqrt(totalPL) : 0;

      // 取引数補正 (多すぎず少なすぎず)
      double tradeBonus = MathSqrt(totalTrades);

      score = pfBonus * wrBonus * tradeBonus + plBonus;
   }

   return score;
}
