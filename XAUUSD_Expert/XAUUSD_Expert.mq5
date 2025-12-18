//+------------------------------------------------------------------+
//|                                               XAUUSD_Expert.mq5  |
//|                              XAUUSD専用EA - Fintokeiチャレンジ対応   |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Expert EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| 共通定義                                                          |
//+------------------------------------------------------------------+
#define EA_MAGIC_NUMBER 20241218

enum ENUM_SIGNAL_DIRECTION {
   SIGNAL_NONE = 0,
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1
};

enum ENUM_ENTRY_LOGIC {
   LOGIC_NONE = 0,
   LOGIC_GRANVILLE = 1,
   LOGIC_HORIZONTAL_LINE = 2,
   LOGIC_NECKLINE = 4,
   LOGIC_PRICE_ACTION = 8,
   LOGIC_MA_CONFLUENCE = 16
};

enum ENUM_DOW_TREND {
   DOW_TREND_UP = 1,
   DOW_TREND_DOWN = -1,
   DOW_TREND_RANGE = 0
};

enum ENUM_GRANVILLE_PATTERN {
   GRANVILLE_NONE = 0,
   GRANVILLE_BUY_1 = 1,
   GRANVILLE_BUY_2 = 2,
   GRANVILLE_BUY_3 = 3,
   GRANVILLE_BUY_4 = 4,
   GRANVILLE_SELL_1 = 5,
   GRANVILLE_SELL_2 = 6,
   GRANVILLE_SELL_3 = 7,
   GRANVILLE_SELL_4 = 8
};

enum ENUM_PRICE_ACTION {
   PA_NONE = 0,
   PA_PIN_BAR = 1,
   PA_ENGULFING = 2,
   PA_INSIDE_BAR = 4,
   PA_TWEEZER = 8,
   PA_HAMMER = 64,
   PA_SHOOTING_STAR = 128
};

enum ENUM_LINE_TYPE {
   LINE_NONE = 0,
   LINE_SUPPORT = 1,
   LINE_RESISTANCE = 2,
   LINE_NECKLINE = 3
};

struct EntrySignal {
   ENUM_SIGNAL_DIRECTION direction;
   int      logicFlags;
   int      logicCount;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   takeProfit3;
   double   strength;
   string   description;
};

struct SwingPoint {
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
};

struct HorizontalLevel {
   double         price;
   ENUM_LINE_TYPE type;
   int            touchCount;
   double         strength;
};

struct DailyPivot {
   double   pivot;
   double   r1, r2, r3;
   double   s1, s2, s3;
};

struct FibonacciLevels {
   double   high;
   double   low;
   double   level236;
   double   level382;
   double   level500;
   double   level618;
   double   level786;
   double   level1618;
   bool     isUptrend;
};

struct PositionInfo {
   ulong    ticket;
   double   openPrice;
   double   currentSL;
   double   currentTP;
   double   lots;
   bool     breakEvenApplied;
   int      splitCount;
   ENUM_POSITION_TYPE type;
};

struct PartialTPSetting {
   double   triggerPercent;
   double   closePercent;
   bool     moveToBreakEven;
};

//+------------------------------------------------------------------+
//| ユーティリティ関数                                                |
//+------------------------------------------------------------------+
double GetPipSizeUtil(string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
      return 0.1;
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

double PriceToPipsUtil(double priceDistance, string symbol = NULL)
{
   double pipSize = GetPipSizeUtil(symbol);
   if(pipSize == 0) return 0;
   return priceDistance / pipSize;
}

double PipsToPriceUtil(double pips, string symbol = NULL)
{
   return pips * GetPipSizeUtil(symbol);
}

double CalculateLossPerLotUtil(double slPips, string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSizeUtil(symbol);
   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;
   return numTicks * tickValue;
}

double NormalizeLotSizeUtil(double lots, string symbol = NULL)
{
   if(symbol == NULL) symbol = _Symbol;
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   return lots;
}

void LogDebugUtil(string message, bool enabled = true)
{
   if(enabled)
      Print("[XAUUSD_EA] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ", message);
}

void InitEntrySignalUtil(EntrySignal &signal)
{
   signal.direction = SIGNAL_NONE;
   signal.logicFlags = LOGIC_NONE;
   signal.logicCount = 0;
   signal.entryPrice = 0;
   signal.stopLoss = 0;
   signal.takeProfit1 = 0;
   signal.takeProfit2 = 0;
   signal.takeProfit3 = 0;
   signal.strength = 0;
   signal.description = "";
}

//+------------------------------------------------------------------+
//| 入力パラメータ                                                    |
//+------------------------------------------------------------------+
input group "=== 基本設定 ==="
input double   InpInitialBalance    = 0;
input int      InpMinLogicCount     = 2;

input group "=== リスク管理（Fintokei対応） ==="
input double   InpDailyLossLimit    = 5.0;
input double   InpTotalLossLimit    = 10.0;
input double   InpMaxPositionRisk   = 3.0;
input double   InpDefaultRisk       = 2.0;
input double   InpSafetyMargin      = 0.5;

input group "=== グランビル設定 ==="
input int      InpSMA200Period      = 200;
input int      InpEMA100Period      = 100;
input int      InpSMA20Period       = 20;
input double   InpMATouchPips       = 15.0;

input group "=== 水平線設定 ==="
input int      InpHLLookback        = 200;
input int      InpSwingStrength     = 3;
input double   InpHLMergePips       = 8.0;
input double   InpHLTouchPips       = 5.0;

input group "=== プライスアクション設定 ==="
input double   InpPinBarRatio       = 2.0;
input double   InpMinCandlePips     = 8.0;

input group "=== 損切り設定 ==="
input double   InpSLMarginPercent   = 3.0;
input double   InpMinSLPips         = 30.0;
input double   InpMaxSLPips         = 100.0;

input group "=== 利確設定 ==="
input double   InpMinRR             = 1.5;
input bool     InpUsePivotTP        = true;
input bool     InpUseFibTP          = true;
input bool     InpUseSwingTP        = true;

input group "=== ポジション管理 ==="
input double   InpBreakEvenPips     = 30.0;
input double   InpBreakEvenProfit   = 5.0;
input bool     InpEnablePartialTP   = true;
input bool     InpEnableSMAExit     = true;

input group "=== 取引時間 ==="
input int      InpStartHour         = 8;
input int      InpEndHour           = 21;

input group "=== デバッグ ==="
input bool     InpEnableLog         = true;

//+------------------------------------------------------------------+
//| リスクマネージャークラス                                          |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   double   m_dailyLossPercent;
   double   m_totalLossPercent;
   double   m_maxPositionRiskPercent;
   double   m_defaultRiskPercent;
   double   m_initialBalance;
   double   m_dailyStartEquity;
   datetime m_lastDayResetTime;
   bool     m_tradingEnabled;
   bool     m_emergencyStop;
   double   m_safetyMargin;
   bool     m_enableLog;

   void     UpdateDailyReset()
   {
      datetime currentTime = TimeCurrent();
      MqlDateTime current, last;
      TimeToStruct(currentTime, current);
      TimeToStruct(m_lastDayResetTime, last);
      if(current.day != last.day || current.mon != last.mon || current.year != last.year)
         OnNewDay();
   }

public:
   CRiskManager()
   {
      m_dailyLossPercent = 5.0;
      m_totalLossPercent = 10.0;
      m_maxPositionRiskPercent = 3.0;
      m_defaultRiskPercent = 2.0;
      m_safetyMargin = 0.5;
      m_initialBalance = 0;
      m_dailyStartEquity = 0;
      m_lastDayResetTime = 0;
      m_tradingEnabled = true;
      m_emergencyStop = false;
      m_enableLog = true;
   }

   bool Initialize(double initialBalance, double dailyLoss, double totalLoss,
                   double maxPosRisk, double defaultRisk, double safetyMargin)
   {
      m_dailyLossPercent = dailyLoss;
      m_totalLossPercent = totalLoss;
      m_maxPositionRiskPercent = maxPosRisk;
      m_defaultRiskPercent = defaultRisk;
      m_safetyMargin = safetyMargin;
      m_initialBalance = (initialBalance > 0) ? initialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lastDayResetTime = TimeCurrent();
      m_tradingEnabled = true;
      m_emergencyStop = false;
      return true;
   }

   void OnNewDay()
   {
      m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lastDayResetTime = TimeCurrent();
      if(m_emergencyStop && GetCurrentTotalLossPercent() < (m_totalLossPercent - m_safetyMargin))
      {
         m_emergencyStop = false;
         m_tradingEnabled = true;
      }
   }

   double GetCurrentDailyLossPercent()
   {
      UpdateDailyReset();
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyLoss = m_dailyStartEquity - currentEquity;
      if(m_dailyStartEquity <= 0) return 0;
      return (dailyLoss / m_dailyStartEquity) * 100.0;
   }

   double GetCurrentTotalLossPercent()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double totalLoss = m_initialBalance - currentEquity;
      if(m_initialBalance <= 0) return 0;
      return (totalLoss / m_initialBalance) * 100.0;
   }

   bool IsTradingAllowed()
   {
      UpdateDailyReset();
      if(m_emergencyStop) return false;
      if(GetCurrentDailyLossPercent() >= (m_dailyLossPercent - m_safetyMargin))
      {
         m_tradingEnabled = false;
         return false;
      }
      if(GetCurrentTotalLossPercent() >= (m_totalLossPercent - m_safetyMargin))
      {
         m_tradingEnabled = false;
         m_emergencyStop = true;
         return false;
      }
      m_tradingEnabled = true;
      return true;
   }

   bool CanOpenPosition(double lotSize, double slPips)
   {
      if(m_emergencyStop) return false;
      UpdateDailyReset();
      double additionalRisk = CalculateLossPerLotUtil(slPips) * lotSize;
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyLossLimit = m_dailyStartEquity * (m_dailyLossPercent - m_safetyMargin) / 100.0;
      double currentDailyLoss = m_dailyStartEquity - currentEquity;
      if(currentDailyLoss + additionalRisk >= dailyLossLimit) return false;
      double totalLossLimit = m_initialBalance * (m_totalLossPercent - m_safetyMargin) / 100.0;
      double currentTotalLoss = m_initialBalance - currentEquity;
      if(currentTotalLoss + additionalRisk >= totalLossLimit) return false;
      return true;
   }

   double CalculateOptimalLot(double slPips, double riskPercent = 0)
   {
      if(slPips <= 0) return 0;
      if(riskPercent <= 0) riskPercent = m_defaultRiskPercent;
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double maxLossAmount = accountBalance * (riskPercent / 100.0);
      double lossPerLot = CalculateLossPerLotUtil(slPips);
      if(lossPerLot <= 0) return 0;
      double calculatedLots = maxLossAmount / lossPerLot;
      return NormalizeLotSizeUtil(calculatedLots);
   }

   double CalculateMaxAllowableLot(double slPips)
   {
      if(slPips <= 0) return 0;
      UpdateDailyReset();
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyLossLimit = m_dailyStartEquity * (m_dailyLossPercent - m_safetyMargin) / 100.0;
      double remainingDailyRisk = MathMax(0, dailyLossLimit - (m_dailyStartEquity - currentEquity));
      double totalLossLimit = m_initialBalance * (m_totalLossPercent - m_safetyMargin) / 100.0;
      double remainingTotalRisk = MathMax(0, totalLossLimit - (m_initialBalance - currentEquity));
      double maxRiskAmount = MathMin(remainingDailyRisk, remainingTotalRisk);
      if(maxRiskAmount <= 0) return 0;
      double lossPerLot = CalculateLossPerLotUtil(slPips);
      if(lossPerLot <= 0) return 0;
      return NormalizeLotSizeUtil(maxRiskAmount / lossPerLot);
   }

   void OnTick()
   {
      UpdateDailyReset();
      double dailyLoss = GetCurrentDailyLossPercent();
      double totalLoss = GetCurrentTotalLossPercent();
      if(dailyLoss >= (m_dailyLossPercent - m_safetyMargin) ||
         totalLoss >= (m_totalLossPercent - m_safetyMargin))
      {
         CTrade trade;
         trade.SetExpertMagicNumber(EA_MAGIC_NUMBER);
         int total = PositionsTotal();
         for(int i = total - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
               if(PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
                  trade.PositionClose(ticket);
            }
         }
         m_tradingEnabled = false;
         if(totalLoss >= (m_totalLossPercent - m_safetyMargin))
            m_emergencyStop = true;
      }
   }

   void EnableLog(bool enable) { m_enableLog = enable; }
   void PrintRiskStatus()
   {
      if(!m_enableLog) return;
      LogDebugUtil(StringFormat("Risk: Daily=%.2f%%, Total=%.2f%%, Trading=%s",
                   GetCurrentDailyLossPercent(), GetCurrentTotalLossPercent(),
                   m_tradingEnabled ? "Yes" : "No"));
   }
};

//+------------------------------------------------------------------+
//| グランビルロジッククラス                                          |
//+------------------------------------------------------------------+
class CGranvilleLogic
{
private:
   int      m_handleSMA200;
   int      m_handleEMA100;
   int      m_handleSMA20;
   double   m_sma200[];
   double   m_ema100[];
   double   m_sma20[];
   double   m_maTouchTolerance;
   double   m_maSlopeThreshold;
   int      m_maSlopeBars;
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   bool     m_enableLog;

   bool UpdateMAValues(int bars = 10)
   {
      if(CopyBuffer(m_handleSMA200, 0, 0, bars, m_sma200) != bars) return false;
      if(CopyBuffer(m_handleEMA100, 0, 0, bars, m_ema100) != bars) return false;
      if(CopyBuffer(m_handleSMA20, 0, 0, bars, m_sma20) != bars) return false;
      return true;
   }

   double GetMASlope(double &maArray[], int bars)
   {
      if(ArraySize(maArray) < bars) return 0;
      double sum = 0;
      for(int i = 0; i < bars - 1; i++)
         sum += maArray[i] - maArray[i + 1];
      return PriceToPipsUtil(sum / (bars - 1), m_symbol);
   }

public:
   CGranvilleLogic()
   {
      m_handleSMA200 = INVALID_HANDLE;
      m_handleEMA100 = INVALID_HANDLE;
      m_handleSMA20 = INVALID_HANDLE;
      m_maTouchTolerance = 10.0;
      m_maSlopeThreshold = 0.5;
      m_maSlopeBars = 5;
      m_enableLog = true;
      ArraySetAsSeries(m_sma200, true);
      ArraySetAsSeries(m_ema100, true);
      ArraySetAsSeries(m_sma20, true);
   }

   ~CGranvilleLogic()
   {
      if(m_handleSMA200 != INVALID_HANDLE) IndicatorRelease(m_handleSMA200);
      if(m_handleEMA100 != INVALID_HANDLE) IndicatorRelease(m_handleEMA100);
      if(m_handleSMA20 != INVALID_HANDLE) IndicatorRelease(m_handleSMA20);
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int sma200, int ema100, int sma20, double touchTolerance)
   {
      m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
      m_timeframe = timeframe;
      m_maTouchTolerance = touchTolerance;
      m_handleSMA200 = iMA(m_symbol, m_timeframe, sma200, 0, MODE_SMA, PRICE_CLOSE);
      m_handleEMA100 = iMA(m_symbol, m_timeframe, ema100, 0, MODE_EMA, PRICE_CLOSE);
      m_handleSMA20 = iMA(m_symbol, m_timeframe, sma20, 0, MODE_SMA, PRICE_CLOSE);
      return (m_handleSMA200 != INVALID_HANDLE && m_handleEMA100 != INVALID_HANDLE && m_handleSMA20 != INVALID_HANDLE);
   }

   ENUM_SIGNAL_DIRECTION GetSignalDirection()
   {
      if(!UpdateMAValues(20)) return SIGNAL_NONE;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_timeframe, 0, 5, rates) < 5) return SIGNAL_NONE;

      double sma200Slope = GetMASlope(m_sma200, m_maSlopeBars);
      double ema100Slope = GetMASlope(m_ema100, m_maSlopeBars);
      double tolerance = PipsToPriceUtil(m_maTouchTolerance, m_symbol);

      // 買い: MA上昇中、価格がMAに接近して反発
      if(sma200Slope > m_maSlopeThreshold)
      {
         if(MathAbs(rates[1].low - m_sma200[1]) < tolerance || MathAbs(rates[2].low - m_sma200[2]) < tolerance)
         {
            if(bid > rates[1].close && rates[1].close > rates[1].low)
               return SIGNAL_BUY;
         }
      }
      if(ema100Slope > m_maSlopeThreshold)
      {
         if(MathAbs(rates[1].low - m_ema100[1]) < tolerance || MathAbs(rates[2].low - m_ema100[2]) < tolerance)
         {
            if(bid > rates[1].close && rates[1].close > rates[1].low)
               return SIGNAL_BUY;
         }
      }

      // 売り: MA下降中、価格がMAに接近して反落
      if(sma200Slope < -m_maSlopeThreshold)
      {
         if(MathAbs(rates[1].high - m_sma200[1]) < tolerance || MathAbs(rates[2].high - m_sma200[2]) < tolerance)
         {
            if(bid < rates[1].close && rates[1].close < rates[1].high)
               return SIGNAL_SELL;
         }
      }
      if(ema100Slope < -m_maSlopeThreshold)
      {
         if(MathAbs(rates[1].high - m_ema100[1]) < tolerance || MathAbs(rates[2].high - m_ema100[2]) < tolerance)
         {
            if(bid < rates[1].close && rates[1].close < rates[1].high)
               return SIGNAL_SELL;
         }
      }

      return SIGNAL_NONE;
   }

   double GetSignalStrength()
   {
      if(GetSignalDirection() != SIGNAL_NONE) return 0.8;
      return 0.0;
   }

   bool IsPriceNearLongMA()
   {
      if(!UpdateMAValues(1)) return false;
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double tolerance = PipsToPriceUtil(m_maTouchTolerance, m_symbol);
      return (MathAbs(price - m_sma200[0]) <= tolerance || MathAbs(price - m_ema100[0]) <= tolerance);
   }

   double GetSMA20(int shift = 0)
   {
      if(!UpdateMAValues(shift + 1)) return 0;
      if(shift >= ArraySize(m_sma20)) return 0;
      return m_sma20[shift];
   }

   void EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| 水平線検出クラス                                                  |
//+------------------------------------------------------------------+
class CHorizontalLine
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_lookbackBars;
   int      m_swingStrength;
   double   m_mergeTolerance;
   double   m_touchTolerance;
   HorizontalLevel m_levels[];
   int      m_levelCount;
   SwingPoint m_swingHighs[];
   SwingPoint m_swingLows[];
   bool     m_enableLog;

   void DetectSwingPoints()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackBars, rates);
      if(copied < m_lookbackBars) return;
      ArrayResize(m_swingHighs, 0);
      ArrayResize(m_swingLows, 0);

      for(int i = m_swingStrength; i < copied - m_swingStrength; i++)
      {
         bool isSwingHigh = true;
         bool isSwingLow = true;
         for(int j = 1; j <= m_swingStrength; j++)
         {
            if(rates[i].high <= rates[i - j].high || rates[i].high <= rates[i + j].high)
               isSwingHigh = false;
            if(rates[i].low >= rates[i - j].low || rates[i].low >= rates[i + j].low)
               isSwingLow = false;
         }
         if(isSwingHigh)
         {
            int size = ArraySize(m_swingHighs);
            ArrayResize(m_swingHighs, size + 1);
            m_swingHighs[size].price = rates[i].high;
            m_swingHighs[size].time = rates[i].time;
            m_swingHighs[size].barIndex = i;
            m_swingHighs[size].isHigh = true;
         }
         if(isSwingLow)
         {
            int size = ArraySize(m_swingLows);
            ArrayResize(m_swingLows, size + 1);
            m_swingLows[size].price = rates[i].low;
            m_swingLows[size].time = rates[i].time;
            m_swingLows[size].barIndex = i;
            m_swingLows[size].isHigh = false;
         }
      }
   }

public:
   CHorizontalLine()
   {
      m_lookbackBars = 200;
      m_swingStrength = 3;
      m_mergeTolerance = 5.0;
      m_touchTolerance = 3.0;
      m_levelCount = 0;
      m_enableLog = true;
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int lookback, int swingStr, double mergeTol, double touchTol)
   {
      m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
      m_timeframe = timeframe;
      m_lookbackBars = lookback;
      m_swingStrength = swingStr;
      m_mergeTolerance = mergeTol;
      m_touchTolerance = touchTol;
      Update();
      return true;
   }

   void Update()
   {
      ArrayResize(m_levels, 0);
      m_levelCount = 0;
      DetectSwingPoints();

      double tolerance = PipsToPriceUtil(m_mergeTolerance, m_symbol);

      // サポートレベル（スイングロー）
      for(int i = 0; i < ArraySize(m_swingLows); i++)
      {
         bool found = false;
         for(int j = 0; j < m_levelCount; j++)
         {
            if(m_levels[j].type == LINE_SUPPORT && MathAbs(m_levels[j].price - m_swingLows[i].price) < tolerance)
            {
               m_levels[j].touchCount++;
               found = true;
               break;
            }
         }
         if(!found && m_levelCount < 20)
         {
            ArrayResize(m_levels, m_levelCount + 1);
            m_levels[m_levelCount].price = m_swingLows[i].price;
            m_levels[m_levelCount].type = LINE_SUPPORT;
            m_levels[m_levelCount].touchCount = 1;
            m_levels[m_levelCount].strength = 0.5;
            m_levelCount++;
         }
      }

      // レジスタンスレベル（スイングハイ）
      for(int i = 0; i < ArraySize(m_swingHighs); i++)
      {
         bool found = false;
         for(int j = 0; j < m_levelCount; j++)
         {
            if(m_levels[j].type == LINE_RESISTANCE && MathAbs(m_levels[j].price - m_swingHighs[i].price) < tolerance)
            {
               m_levels[j].touchCount++;
               found = true;
               break;
            }
         }
         if(!found && m_levelCount < 20)
         {
            ArrayResize(m_levels, m_levelCount + 1);
            m_levels[m_levelCount].price = m_swingHighs[i].price;
            m_levels[m_levelCount].type = LINE_RESISTANCE;
            m_levels[m_levelCount].touchCount = 1;
            m_levels[m_levelCount].strength = 0.5;
            m_levelCount++;
         }
      }
   }

   ENUM_SIGNAL_DIRECTION GetBounceSignal(double price)
   {
      double tolerance = PipsToPriceUtil(m_touchTolerance, m_symbol);
      for(int i = 0; i < m_levelCount; i++)
      {
         if(m_levels[i].type == LINE_SUPPORT && MathAbs(price - m_levels[i].price) < tolerance && price >= m_levels[i].price)
            return SIGNAL_BUY;
         if(m_levels[i].type == LINE_RESISTANCE && MathAbs(price - m_levels[i].price) < tolerance && price <= m_levels[i].price)
            return SIGNAL_SELL;
      }
      return SIGNAL_NONE;
   }

   double GetNearestSupportBelow(double price)
   {
      double nearest = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < m_levelCount; i++)
      {
         if(m_levels[i].type == LINE_SUPPORT && m_levels[i].price < price)
         {
            double distance = price - m_levels[i].price;
            if(distance < minDistance)
            {
               minDistance = distance;
               nearest = m_levels[i].price;
            }
         }
      }
      return nearest;
   }

   double GetNearestResistanceAbove(double price)
   {
      double nearest = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < m_levelCount; i++)
      {
         if(m_levels[i].type == LINE_RESISTANCE && m_levels[i].price > price)
         {
            double distance = m_levels[i].price - price;
            if(distance < minDistance)
            {
               minDistance = distance;
               nearest = m_levels[i].price;
            }
         }
      }
      return nearest;
   }

   void EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| プライスアクションクラス                                          |
//+------------------------------------------------------------------+
class CPriceAction
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   double   m_pinBarRatio;
   double   m_minCandleSize;
   bool     m_enableLog;

   double GetCandleBody(const MqlRates &rate) { return MathAbs(rate.close - rate.open); }
   double GetUpperWick(const MqlRates &rate) { return rate.high - MathMax(rate.open, rate.close); }
   double GetLowerWick(const MqlRates &rate) { return MathMin(rate.open, rate.close) - rate.low; }
   double GetCandleRange(const MqlRates &rate) { return rate.high - rate.low; }
   bool IsBullishCandle(const MqlRates &rate) { return rate.close > rate.open; }
   bool IsBearishCandle(const MqlRates &rate) { return rate.close < rate.open; }

public:
   CPriceAction()
   {
      m_pinBarRatio = 2.0;
      m_minCandleSize = 5.0;
      m_enableLog = true;
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe, double pinBarRatio, double engulfRatio, double dojiRatio, double minCandleSize)
   {
      m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
      m_timeframe = timeframe;
      m_pinBarRatio = pinBarRatio;
      m_minCandleSize = minCandleSize;
      return true;
   }

   ENUM_SIGNAL_DIRECTION GetSignalDirection()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_timeframe, 0, 5, rates) < 5) return SIGNAL_NONE;

      // ピンバーチェック
      double body = GetCandleBody(rates[1]);
      double range = GetCandleRange(rates[1]);
      double upperWick = GetUpperWick(rates[1]);
      double lowerWick = GetLowerWick(rates[1]);

      if(PriceToPipsUtil(range, m_symbol) >= m_minCandleSize)
      {
         if(body <= range * 0.3)
         {
            // 買いピンバー
            if(lowerWick > body * m_pinBarRatio && lowerWick > upperWick * 2)
               return SIGNAL_BUY;
            // 売りピンバー
            if(upperWick > body * m_pinBarRatio && upperWick > lowerWick * 2)
               return SIGNAL_SELL;
         }
      }

      // 包み足チェック
      double currentBody = GetCandleBody(rates[1]);
      double previousBody = GetCandleBody(rates[2]);
      if(PriceToPipsUtil(currentBody, m_symbol) >= m_minCandleSize && currentBody > previousBody)
      {
         // 買いの包み足
         if(IsBearishCandle(rates[2]) && IsBullishCandle(rates[1]))
         {
            if(rates[1].open <= rates[2].close && rates[1].close >= rates[2].open)
               return SIGNAL_BUY;
         }
         // 売りの包み足
         if(IsBullishCandle(rates[2]) && IsBearishCandle(rates[1]))
         {
            if(rates[1].open >= rates[2].close && rates[1].close <= rates[2].open)
               return SIGNAL_SELL;
         }
      }

      // ハンマー
      if(PriceToPipsUtil(range, m_symbol) >= m_minCandleSize)
      {
         if(lowerWick >= body * 2.0 && upperWick < body * 0.3 && body > 0)
            return SIGNAL_BUY;
         // 流れ星
         if(upperWick >= body * 2.0 && lowerWick < body * 0.3 && body > 0)
            return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   double GetSignalStrength()
   {
      if(GetSignalDirection() != SIGNAL_NONE) return 0.8;
      return 0.0;
   }

   void EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| ダウ理論クラス                                                    |
//+------------------------------------------------------------------+
class CDowTheory
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   ENUM_TIMEFRAMES m_higherTimeframe;
   int      m_swingStrength;
   int      m_lookbackBars;
   double   m_slMarginPercent;
   SwingPoint m_swingHighs[];
   SwingPoint m_swingLows[];
   SwingPoint m_htfSwingHighs[];
   SwingPoint m_htfSwingLows[];
   bool     m_enableLog;

   void DetectSwingPoints(ENUM_TIMEFRAMES tf, SwingPoint &highs[], SwingPoint &lows[])
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, tf, 0, m_lookbackBars, rates);
      if(copied < m_lookbackBars) return;
      ArrayResize(highs, 0);
      ArrayResize(lows, 0);

      for(int i = m_swingStrength; i < copied - m_swingStrength; i++)
      {
         bool isSwingHigh = true;
         bool isSwingLow = true;
         for(int j = 1; j <= m_swingStrength; j++)
         {
            if(rates[i].high <= rates[i - j].high || rates[i].high <= rates[i + j].high)
               isSwingHigh = false;
            if(rates[i].low >= rates[i - j].low || rates[i].low >= rates[i + j].low)
               isSwingLow = false;
         }
         if(isSwingHigh)
         {
            int size = ArraySize(highs);
            ArrayResize(highs, size + 1);
            highs[size].price = rates[i].high;
            highs[size].barIndex = i;
            highs[size].isHigh = true;
         }
         if(isSwingLow)
         {
            int size = ArraySize(lows);
            ArrayResize(lows, size + 1);
            lows[size].price = rates[i].low;
            lows[size].barIndex = i;
            lows[size].isHigh = false;
         }
      }
   }

public:
   CDowTheory()
   {
      m_swingStrength = 3;
      m_lookbackBars = 100;
      m_slMarginPercent = 3.0;
      m_enableLog = true;
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe, ENUM_TIMEFRAMES higherTF, int swingStr, int lookback, double slMargin)
   {
      m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
      m_timeframe = timeframe;
      m_higherTimeframe = higherTF;
      m_swingStrength = swingStr;
      m_lookbackBars = lookback;
      m_slMarginPercent = slMargin;
      Update();
      return true;
   }

   void Update()
   {
      DetectSwingPoints(m_timeframe, m_swingHighs, m_swingLows);
      DetectSwingPoints(m_higherTimeframe, m_htfSwingHighs, m_htfSwingLows);
   }

   ENUM_DOW_TREND GetTrend()
   {
      int highCount = ArraySize(m_swingHighs);
      int lowCount = ArraySize(m_swingLows);
      if(highCount < 2 || lowCount < 2) return DOW_TREND_RANGE;
      bool higherHighs = m_swingHighs[0].price > m_swingHighs[1].price;
      bool higherLows = m_swingLows[0].price > m_swingLows[1].price;
      bool lowerHighs = m_swingHighs[0].price < m_swingHighs[1].price;
      bool lowerLows = m_swingLows[0].price < m_swingLows[1].price;
      if(higherHighs && higherLows) return DOW_TREND_UP;
      if(lowerHighs && lowerLows) return DOW_TREND_DOWN;
      return DOW_TREND_RANGE;
   }

   double CalculateBuySL(double entryPrice)
   {
      if(ArraySize(m_swingLows) < 1) return entryPrice - PipsToPriceUtil(50.0, m_symbol);
      double swingLow = m_swingLows[0].price;
      double margin = swingLow * (m_slMarginPercent / 100.0);
      double sl = swingLow - margin;
      if(sl >= entryPrice) sl = entryPrice - PipsToPriceUtil(30.0, m_symbol);
      return sl;
   }

   double CalculateSellSL(double entryPrice)
   {
      if(ArraySize(m_swingHighs) < 1) return entryPrice + PipsToPriceUtil(50.0, m_symbol);
      double swingHigh = m_swingHighs[0].price;
      double margin = swingHigh * (m_slMarginPercent / 100.0);
      double sl = swingHigh + margin;
      if(sl <= entryPrice) sl = entryPrice + PipsToPriceUtil(30.0, m_symbol);
      return sl;
   }

   double GetNextResistance(double currentPrice)
   {
      double nearest = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < ArraySize(m_swingHighs); i++)
      {
         if(m_swingHighs[i].price > currentPrice)
         {
            double distance = m_swingHighs[i].price - currentPrice;
            if(distance < minDistance)
            {
               minDistance = distance;
               nearest = m_swingHighs[i].price;
            }
         }
      }
      return nearest;
   }

   double GetNextSupport(double currentPrice)
   {
      double nearest = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < ArraySize(m_swingLows); i++)
      {
         if(m_swingLows[i].price < currentPrice)
         {
            double distance = currentPrice - m_swingLows[i].price;
            if(distance < minDistance)
            {
               minDistance = distance;
               nearest = m_swingLows[i].price;
            }
         }
      }
      return nearest;
   }

   double GetHTFResistance(double currentPrice)
   {
      double nearest = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < ArraySize(m_htfSwingHighs); i++)
      {
         if(m_htfSwingHighs[i].price > currentPrice)
         {
            double distance = m_htfSwingHighs[i].price - currentPrice;
            if(distance < minDistance)
            {
               minDistance = distance;
               nearest = m_htfSwingHighs[i].price;
            }
         }
      }
      return nearest;
   }

   double GetHTFSupport(double currentPrice)
   {
      double nearest = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < ArraySize(m_htfSwingLows); i++)
      {
         if(m_htfSwingLows[i].price < currentPrice)
         {
            double distance = currentPrice - m_htfSwingLows[i].price;
            if(distance < minDistance)
            {
               minDistance = distance;
               nearest = m_htfSwingLows[i].price;
            }
         }
      }
      return nearest;
   }

   void EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| PIVOT・Fibonacciクラス                                            |
//+------------------------------------------------------------------+
class CPivotFibonacci
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   DailyPivot m_dailyPivot;
   FibonacciLevels m_fibLevels;
   int      m_fibLookback;
   bool     m_enableLog;

   void CalculatePivot()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, PERIOD_D1, 0, 2, rates) < 2) return;
      double high = rates[1].high;
      double low = rates[1].low;
      double close = rates[1].close;
      m_dailyPivot.pivot = (high + low + close) / 3.0;
      m_dailyPivot.r1 = 2.0 * m_dailyPivot.pivot - low;
      m_dailyPivot.r2 = m_dailyPivot.pivot + (high - low);
      m_dailyPivot.r3 = high + 2.0 * (m_dailyPivot.pivot - low);
      m_dailyPivot.s1 = 2.0 * m_dailyPivot.pivot - high;
      m_dailyPivot.s2 = m_dailyPivot.pivot - (high - low);
      m_dailyPivot.s3 = low - 2.0 * (high - m_dailyPivot.pivot);
   }

   void CalculateFibonacci()
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_timeframe, 0, m_fibLookback, rates) < m_fibLookback) return;
      double highestHigh = rates[0].high;
      double lowestLow = rates[0].low;
      int highIndex = 0, lowIndex = 0;
      for(int i = 0; i < m_fibLookback; i++)
      {
         if(rates[i].high > highestHigh) { highestHigh = rates[i].high; highIndex = i; }
         if(rates[i].low < lowestLow) { lowestLow = rates[i].low; lowIndex = i; }
      }
      m_fibLevels.high = highestHigh;
      m_fibLevels.low = lowestLow;
      m_fibLevels.isUptrend = (highIndex < lowIndex);
      double range = highestHigh - lowestLow;
      if(m_fibLevels.isUptrend)
      {
         m_fibLevels.level236 = highestHigh - range * 0.236;
         m_fibLevels.level382 = highestHigh - range * 0.382;
         m_fibLevels.level500 = highestHigh - range * 0.500;
         m_fibLevels.level618 = highestHigh - range * 0.618;
         m_fibLevels.level786 = highestHigh - range * 0.786;
         m_fibLevels.level1618 = highestHigh + range * 0.618;
      }
      else
      {
         m_fibLevels.level236 = lowestLow + range * 0.236;
         m_fibLevels.level382 = lowestLow + range * 0.382;
         m_fibLevels.level500 = lowestLow + range * 0.500;
         m_fibLevels.level618 = lowestLow + range * 0.618;
         m_fibLevels.level786 = lowestLow + range * 0.786;
         m_fibLevels.level1618 = lowestLow - range * 0.618;
      }
   }

public:
   CPivotFibonacci()
   {
      m_fibLookback = 100;
      m_enableLog = true;
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe, int fibLookback)
   {
      m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
      m_timeframe = timeframe;
      m_fibLookback = fibLookback;
      Update();
      return true;
   }

   void Update()
   {
      CalculatePivot();
      CalculateFibonacci();
   }

   double GetNearestPivotTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction)
   {
      double levels[] = {m_dailyPivot.pivot, m_dailyPivot.r1, m_dailyPivot.r2, m_dailyPivot.r3,
                        m_dailyPivot.s1, m_dailyPivot.s2, m_dailyPivot.s3};
      double nearestTP = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < ArraySize(levels); i++)
      {
         if(direction == SIGNAL_BUY && levels[i] > entryPrice)
         {
            double distance = levels[i] - entryPrice;
            if(distance < minDistance) { minDistance = distance; nearestTP = levels[i]; }
         }
         else if(direction == SIGNAL_SELL && levels[i] < entryPrice)
         {
            double distance = entryPrice - levels[i];
            if(distance < minDistance) { minDistance = distance; nearestTP = levels[i]; }
         }
      }
      return nearestTP;
   }

   double GetNearestFibTP(double entryPrice, ENUM_SIGNAL_DIRECTION direction)
   {
      double levels[] = {m_fibLevels.level236, m_fibLevels.level382, m_fibLevels.level500,
                        m_fibLevels.level618, m_fibLevels.level786, m_fibLevels.level1618};
      double nearestTP = 0;
      double minDistance = DBL_MAX;
      for(int i = 0; i < ArraySize(levels); i++)
      {
         if(direction == SIGNAL_BUY && levels[i] > entryPrice)
         {
            double distance = levels[i] - entryPrice;
            if(distance < minDistance) { minDistance = distance; nearestTP = levels[i]; }
         }
         else if(direction == SIGNAL_SELL && levels[i] < entryPrice)
         {
            double distance = entryPrice - levels[i];
            if(distance < minDistance) { minDistance = distance; nearestTP = levels[i]; }
         }
      }
      return nearestTP;
   }

   void EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| ポジション管理クラス                                              |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   string   m_symbol;
   ulong    m_magicNumber;
   double   m_breakEvenTriggerPips;
   double   m_breakEvenProfitPips;
   bool     m_enableBreakEven;
   bool     m_enablePartialTP;
   bool     m_enableSMAExit;
   PartialTPSetting m_partialSettings[];
   int      m_partialCount;
   PositionInfo m_positions[];
   int      m_positionCount;
   int      m_handleSMA20;
   double   m_sma20[];
   CTrade   m_trade;
   bool     m_enableLog;

   bool UpdatePositionList()
   {
      ArrayResize(m_positions, 0);
      m_positionCount = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            {
               ArrayResize(m_positions, m_positionCount + 1);
               m_positions[m_positionCount].ticket = ticket;
               m_positions[m_positionCount].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               m_positions[m_positionCount].currentSL = PositionGetDouble(POSITION_SL);
               m_positions[m_positionCount].currentTP = PositionGetDouble(POSITION_TP);
               m_positions[m_positionCount].lots = PositionGetDouble(POSITION_VOLUME);
               m_positions[m_positionCount].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               m_positions[m_positionCount].splitCount = 0;
               double openPrice = m_positions[m_positionCount].openPrice;
               double sl = m_positions[m_positionCount].currentSL;
               ENUM_POSITION_TYPE type = m_positions[m_positionCount].type;
               m_positions[m_positionCount].breakEvenApplied =
                  (type == POSITION_TYPE_BUY && sl >= openPrice - PipsToPriceUtil(1, m_symbol)) ||
                  (type == POSITION_TYPE_SELL && sl > 0 && sl <= openPrice + PipsToPriceUtil(1, m_symbol));
               m_positionCount++;
            }
         }
      }
      return true;
   }

   double GetPositionProfitPips(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return 0;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                           SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double priceDiff = (type == POSITION_TYPE_BUY) ? currentPrice - openPrice : openPrice - currentPrice;
      return PriceToPipsUtil(priceDiff, m_symbol);
   }

public:
   CPositionManager()
   {
      m_magicNumber = EA_MAGIC_NUMBER;
      m_breakEvenTriggerPips = 30.0;
      m_breakEvenProfitPips = 5.0;
      m_enableBreakEven = true;
      m_enablePartialTP = true;
      m_enableSMAExit = true;
      m_partialCount = 0;
      m_positionCount = 0;
      m_handleSMA20 = INVALID_HANDLE;
      m_enableLog = true;
      ArraySetAsSeries(m_sma20, true);
   }

   ~CPositionManager()
   {
      if(m_handleSMA20 != INVALID_HANDLE) IndicatorRelease(m_handleSMA20);
   }

   bool Initialize(string symbol, ulong magic, double beTriggerPips, double beProfitPips)
   {
      m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
      m_magicNumber = magic;
      m_breakEvenTriggerPips = beTriggerPips;
      m_breakEvenProfitPips = beProfitPips;
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(30);
      m_handleSMA20 = iMA(m_symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);

      // デフォルト分割利確設定
      ArrayResize(m_partialSettings, 3);
      m_partialSettings[0].triggerPercent = 30.0;
      m_partialSettings[0].closePercent = 30.0;
      m_partialSettings[0].moveToBreakEven = true;
      m_partialSettings[1].triggerPercent = 60.0;
      m_partialSettings[1].closePercent = 30.0;
      m_partialSettings[1].moveToBreakEven = false;
      m_partialSettings[2].triggerPercent = 100.0;
      m_partialSettings[2].closePercent = 40.0;
      m_partialSettings[2].moveToBreakEven = false;
      m_partialCount = 3;

      UpdatePositionList();
      return true;
   }

   void OnTick()
   {
      UpdatePositionList();
      if(m_positionCount == 0) return;
      if(m_enableBreakEven) CheckBreakEven();
      if(m_enablePartialTP) CheckPartialTP();
      if(m_enableSMAExit) CheckSMAExit();
   }

   void CheckBreakEven()
   {
      for(int i = 0; i < m_positionCount; i++)
      {
         if(m_positions[i].breakEvenApplied) continue;
         double profitPips = GetPositionProfitPips(m_positions[i].ticket);
         if(profitPips < m_breakEvenTriggerPips) continue;

         double newSL;
         if(m_positions[i].type == POSITION_TYPE_BUY)
         {
            newSL = m_positions[i].openPrice + PipsToPriceUtil(m_breakEvenProfitPips, m_symbol);
            if(m_positions[i].currentSL < newSL || m_positions[i].currentSL == 0)
            {
               if(m_trade.PositionModify(m_positions[i].ticket, newSL, m_positions[i].currentTP))
                  m_positions[i].breakEvenApplied = true;
            }
         }
         else
         {
            newSL = m_positions[i].openPrice - PipsToPriceUtil(m_breakEvenProfitPips, m_symbol);
            if(m_positions[i].currentSL > newSL || m_positions[i].currentSL == 0)
            {
               if(m_trade.PositionModify(m_positions[i].ticket, newSL, m_positions[i].currentTP))
                  m_positions[i].breakEvenApplied = true;
            }
         }
      }
   }

   void CheckPartialTP()
   {
      for(int i = 0; i < m_positionCount; i++)
      {
         if(m_positions[i].currentTP == 0) continue;
         double totalDistance = MathAbs(m_positions[i].currentTP - m_positions[i].openPrice);
         double currentPrice = (m_positions[i].type == POSITION_TYPE_BUY) ?
                              SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                              SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double currentDistance = (m_positions[i].type == POSITION_TYPE_BUY) ?
                                 currentPrice - m_positions[i].openPrice :
                                 m_positions[i].openPrice - currentPrice;
         if(currentDistance <= 0) continue;
         double progressPercent = (currentDistance / totalDistance) * 100.0;

         for(int j = m_positions[i].splitCount; j < m_partialCount; j++)
         {
            if(progressPercent >= m_partialSettings[j].triggerPercent)
            {
               double closeLotsPercent = m_partialSettings[j].closePercent / 100.0;
               double closeLots = NormalizeLotSizeUtil(m_positions[i].lots * closeLotsPercent, m_symbol);
               double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
               double remainLots = m_positions[i].lots - closeLots;
               if(remainLots < minLot) closeLots = m_positions[i].lots;
               if(closeLots >= minLot)
               {
                  if(m_trade.PositionClosePartial(m_positions[i].ticket, closeLots))
                  {
                     m_positions[i].splitCount = j + 1;
                     if(m_partialSettings[j].moveToBreakEven && !m_positions[i].breakEvenApplied)
                     {
                        double beSL = m_positions[i].openPrice;
                        if(m_positions[i].type == POSITION_TYPE_BUY)
                           beSL += PipsToPriceUtil(m_breakEvenProfitPips, m_symbol);
                        else
                           beSL -= PipsToPriceUtil(m_breakEvenProfitPips, m_symbol);
                        if(m_trade.PositionModify(m_positions[i].ticket, beSL, m_positions[i].currentTP))
                           m_positions[i].breakEvenApplied = true;
                     }
                  }
               }
               break;
            }
         }
      }
   }

   void CheckSMAExit()
   {
      if(m_handleSMA20 == INVALID_HANDLE) return;
      if(CopyBuffer(m_handleSMA20, 0, 0, 3, m_sma20) < 3) return;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, PERIOD_M5, 0, 3, rates) < 3) return;

      for(int i = 0; i < m_positionCount; i++)
      {
         if(!m_positions[i].breakEvenApplied) continue;
         if(m_positions[i].type == POSITION_TYPE_BUY)
         {
            if(rates[2].close > m_sma20[2] && rates[1].close < m_sma20[1])
               m_trade.PositionClose(m_positions[i].ticket);
         }
         else
         {
            if(rates[2].close < m_sma20[2] && rates[1].close > m_sma20[1])
               m_trade.PositionClose(m_positions[i].ticket);
         }
      }
   }

   bool OpenPosition(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment)
   {
      double price = (type == ORDER_TYPE_BUY) ?
                    SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                    SymbolInfoDouble(m_symbol, SYMBOL_BID);
      bool result = m_trade.PositionOpen(m_symbol, type, lots, price, sl, tp, comment);
      if(result) UpdatePositionList();
      return result;
   }

   bool HasOpenPosition()
   {
      UpdatePositionList();
      return m_positionCount > 0;
   }

   void EnablePartialTP(bool enable) { m_enablePartialTP = enable; }
   void EnableSMAExit(bool enable) { m_enableSMAExit = enable; }
   void EnableLog(bool enable) { m_enableLog = enable; }
};

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
CRiskManager      *g_riskManager;
CGranvilleLogic   *g_granville;
CHorizontalLine   *g_horizontalLine;
CPriceAction      *g_priceAction;
CDowTheory        *g_dowTheory;
CPivotFibonacci   *g_pivotFibo;
CPositionManager  *g_positionManager;

datetime          g_lastBarTime = 0;
bool              g_initialized = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("This EA is designed for XAUUSD/Gold only!");
      return INIT_FAILED;
   }

   g_riskManager = new CRiskManager();
   g_granville = new CGranvilleLogic();
   g_horizontalLine = new CHorizontalLine();
   g_priceAction = new CPriceAction();
   g_dowTheory = new CDowTheory();
   g_pivotFibo = new CPivotFibonacci();
   g_positionManager = new CPositionManager();

   if(!g_riskManager.Initialize(InpInitialBalance, InpDailyLossLimit, InpTotalLossLimit,
                                 InpMaxPositionRisk, InpDefaultRisk, InpSafetyMargin))
   {
      Print("Failed to initialize RiskManager");
      return INIT_FAILED;
   }
   g_riskManager.EnableLog(InpEnableLog);

   if(!g_granville.Initialize(_Symbol, PERIOD_M5, InpSMA200Period, InpEMA100Period, InpSMA20Period, InpMATouchPips))
   {
      Print("Failed to initialize GranvilleLogic");
      return INIT_FAILED;
   }
   g_granville.EnableLog(InpEnableLog);

   if(!g_horizontalLine.Initialize(_Symbol, PERIOD_M5, InpHLLookback, InpSwingStrength, InpHLMergePips, InpHLTouchPips))
   {
      Print("Failed to initialize HorizontalLine");
      return INIT_FAILED;
   }
   g_horizontalLine.EnableLog(InpEnableLog);

   if(!g_priceAction.Initialize(_Symbol, PERIOD_M5, InpPinBarRatio, 1.0, 0.1, InpMinCandlePips))
   {
      Print("Failed to initialize PriceAction");
      return INIT_FAILED;
   }
   g_priceAction.EnableLog(InpEnableLog);

   if(!g_dowTheory.Initialize(_Symbol, PERIOD_M5, PERIOD_H1, InpSwingStrength, InpHLLookback, InpSLMarginPercent))
   {
      Print("Failed to initialize DowTheory");
      return INIT_FAILED;
   }
   g_dowTheory.EnableLog(InpEnableLog);

   if(!g_pivotFibo.Initialize(_Symbol, PERIOD_M5, InpHLLookback))
   {
      Print("Failed to initialize PivotFibonacci");
      return INIT_FAILED;
   }
   g_pivotFibo.EnableLog(InpEnableLog);

   if(!g_positionManager.Initialize(_Symbol, EA_MAGIC_NUMBER, InpBreakEvenPips, InpBreakEvenProfit))
   {
      Print("Failed to initialize PositionManager");
      return INIT_FAILED;
   }
   g_positionManager.EnableLog(InpEnableLog);
   g_positionManager.EnablePartialTP(InpEnablePartialTP);
   g_positionManager.EnableSMAExit(InpEnableSMAExit);

   g_initialized = true;
   Print("XAUUSD Expert EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_riskManager != NULL) { delete g_riskManager; g_riskManager = NULL; }
   if(g_granville != NULL) { delete g_granville; g_granville = NULL; }
   if(g_horizontalLine != NULL) { delete g_horizontalLine; g_horizontalLine = NULL; }
   if(g_priceAction != NULL) { delete g_priceAction; g_priceAction = NULL; }
   if(g_dowTheory != NULL) { delete g_dowTheory; g_dowTheory = NULL; }
   if(g_pivotFibo != NULL) { delete g_pivotFibo; g_pivotFibo = NULL; }
   if(g_positionManager != NULL) { delete g_positionManager; g_positionManager = NULL; }
   Print("XAUUSD Expert EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;

   g_riskManager.OnTick();
   g_positionManager.OnTick();

   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   if(!IsTradingTime()) return;
   if(!g_riskManager.IsTradingAllowed())
   {
      if(InpEnableLog) LogDebugUtil("Trading not allowed by RiskManager");
      return;
   }

   UpdateAnalysis();

   if(g_positionManager.HasOpenPosition()) return;

   EntrySignal signal;
   if(CheckEntrySignal(signal))
      ExecuteEntry(signal);
}

//+------------------------------------------------------------------+
//| 取引時間チェック                                                  |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
   return true;
}

//+------------------------------------------------------------------+
//| 分析データを更新                                                  |
//+------------------------------------------------------------------+
void UpdateAnalysis()
{
   g_horizontalLine.Update();
   g_dowTheory.Update();
   g_pivotFibo.Update();
}

//+------------------------------------------------------------------+
//| エントリーシグナルをチェック                                      |
//+------------------------------------------------------------------+
bool CheckEntrySignal(EntrySignal &signal)
{
   InitEntrySignalUtil(signal);

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int logicCount = 0;
   int logicFlags = 0;
   string description = "";

   ENUM_SIGNAL_DIRECTION granvilleDir = g_granville.GetSignalDirection();
   if(granvilleDir != SIGNAL_NONE)
   {
      logicCount++;
      logicFlags |= LOGIC_GRANVILLE;
      description += "Granville ";
      signal.direction = granvilleDir;
   }

   ENUM_SIGNAL_DIRECTION hlDir = g_horizontalLine.GetBounceSignal(currentPrice);
   if(hlDir != SIGNAL_NONE)
   {
      if(signal.direction == SIGNAL_NONE || signal.direction == hlDir)
      {
         logicCount++;
         logicFlags |= LOGIC_HORIZONTAL_LINE;
         description += "HorizontalLine ";
         signal.direction = hlDir;
      }
   }

   ENUM_SIGNAL_DIRECTION paDir = g_priceAction.GetSignalDirection();
   if(paDir != SIGNAL_NONE)
   {
      if(signal.direction == SIGNAL_NONE || signal.direction == paDir)
      {
         logicCount++;
         logicFlags |= LOGIC_PRICE_ACTION;
         description += "PriceAction ";
         signal.direction = paDir;
      }
   }

   ENUM_DOW_TREND dowTrend = g_dowTheory.GetTrend();
   bool trendConfirmed = false;
   if(signal.direction == SIGNAL_BUY && dowTrend == DOW_TREND_UP) trendConfirmed = true;
   if(signal.direction == SIGNAL_SELL && dowTrend == DOW_TREND_DOWN) trendConfirmed = true;

   bool nearLongMA = g_granville.IsPriceNearLongMA();
   if(nearLongMA)
   {
      logicFlags |= LOGIC_MA_CONFLUENCE;
      description += "MAConfluence ";
   }

   if(logicCount < InpMinLogicCount) return false;
   if(signal.direction == SIGNAL_NONE) return false;

   signal.entryPrice = (signal.direction == SIGNAL_BUY) ?
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                       SymbolInfoDouble(_Symbol, SYMBOL_BID);

   signal.stopLoss = CalculateStopLoss(signal.direction, signal.entryPrice);
   if(signal.stopLoss == 0)
   {
      if(InpEnableLog) LogDebugUtil("Failed to calculate stop loss");
      return false;
   }

   double slPips = MathAbs(PriceToPipsUtil(signal.entryPrice - signal.stopLoss, _Symbol));
   if(slPips < InpMinSLPips)
   {
      if(signal.direction == SIGNAL_BUY)
         signal.stopLoss = signal.entryPrice - PipsToPriceUtil(InpMinSLPips, _Symbol);
      else
         signal.stopLoss = signal.entryPrice + PipsToPriceUtil(InpMinSLPips, _Symbol);
      slPips = InpMinSLPips;
   }

   if(slPips > InpMaxSLPips)
   {
      if(InpEnableLog) LogDebugUtil(StringFormat("SL too large: %.1f pips", slPips));
      return false;
   }

   CalculateTakeProfits(signal);

   double tp1Pips = MathAbs(PriceToPipsUtil(signal.takeProfit1 - signal.entryPrice, _Symbol));
   double rrRatio = tp1Pips / slPips;
   if(rrRatio < InpMinRR)
   {
      if(InpEnableLog) LogDebugUtil(StringFormat("RR ratio too low: %.2f", rrRatio));
      return false;
   }

   signal.logicFlags = logicFlags;
   signal.logicCount = logicCount;
   signal.description = description;
   signal.strength = g_priceAction.GetSignalStrength() * 0.4 +
                    g_granville.GetSignalStrength() * 0.4 +
                    (trendConfirmed ? 0.2 : 0);

   if(InpEnableLog)
   {
      LogDebugUtil(StringFormat("Entry signal: %s, LogicCount=%d, %s, RR=%.2f",
               (signal.direction == SIGNAL_BUY) ? "BUY" : "SELL",
               logicCount, description, rrRatio));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 損切りラインを計算                                                |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_SIGNAL_DIRECTION direction, double entryPrice)
{
   double sl = 0;
   if(direction == SIGNAL_BUY)
   {
      sl = g_dowTheory.CalculateBuySL(entryPrice);
      double support = g_horizontalLine.GetNearestSupportBelow(entryPrice);
      if(support > 0 && support < sl)
      {
         double margin = support * (InpSLMarginPercent / 100.0);
         sl = support - margin;
      }
   }
   else
   {
      sl = g_dowTheory.CalculateSellSL(entryPrice);
      double resistance = g_horizontalLine.GetNearestResistanceAbove(entryPrice);
      if(resistance > 0 && resistance > sl)
      {
         double margin = resistance * (InpSLMarginPercent / 100.0);
         sl = resistance + margin;
      }
   }
   return sl;
}

//+------------------------------------------------------------------+
//| 利確ラインを計算                                                  |
//+------------------------------------------------------------------+
void CalculateTakeProfits(EntrySignal &signal)
{
   double tp1 = 0, tp2 = 0, tp3 = 0;
   double entryPrice = signal.entryPrice;
   ENUM_SIGNAL_DIRECTION dir = signal.direction;

   if(InpUseSwingTP)
   {
      if(dir == SIGNAL_BUY) tp1 = g_dowTheory.GetNextResistance(entryPrice);
      else tp1 = g_dowTheory.GetNextSupport(entryPrice);
   }

   if(InpUsePivotTP)
   {
      double pivotTP = g_pivotFibo.GetNearestPivotTP(entryPrice, dir);
      if(pivotTP > 0)
      {
         if(tp1 == 0 || (dir == SIGNAL_BUY && pivotTP < tp1) || (dir == SIGNAL_SELL && pivotTP > tp1))
            tp2 = pivotTP;
         else tp2 = tp1;
         if(tp1 == 0) tp1 = pivotTP;
      }
   }

   if(InpUseFibTP)
   {
      double fibTP = g_pivotFibo.GetNearestFibTP(entryPrice, dir);
      if(fibTP > 0)
      {
         tp3 = fibTP;
         if(tp1 == 0) tp1 = fibTP;
         if(tp2 == 0) tp2 = fibTP;
      }
   }

   if(dir == SIGNAL_BUY)
   {
      double htfRes = g_dowTheory.GetHTFResistance(entryPrice);
      if(htfRes > 0 && (tp2 == 0 || htfRes > tp2)) tp2 = htfRes;
   }
   else
   {
      double htfSup = g_dowTheory.GetHTFSupport(entryPrice);
      if(htfSup > 0 && (tp2 == 0 || htfSup < tp2)) tp2 = htfSup;
   }

   double slDistance = MathAbs(entryPrice - signal.stopLoss);
   if(tp1 == 0)
   {
      if(dir == SIGNAL_BUY) tp1 = entryPrice + slDistance * InpMinRR;
      else tp1 = entryPrice - slDistance * InpMinRR;
   }
   if(tp2 == 0)
   {
      if(dir == SIGNAL_BUY) tp2 = entryPrice + slDistance * 2.0;
      else tp2 = entryPrice - slDistance * 2.0;
   }
   if(tp3 == 0)
   {
      if(dir == SIGNAL_BUY) tp3 = entryPrice + slDistance * 3.0;
      else tp3 = entryPrice - slDistance * 3.0;
   }

   signal.takeProfit1 = tp1;
   signal.takeProfit2 = tp2;
   signal.takeProfit3 = tp3;
}

//+------------------------------------------------------------------+
//| エントリーを実行                                                  |
//+------------------------------------------------------------------+
void ExecuteEntry(EntrySignal &signal)
{
   double slPips = MathAbs(PriceToPipsUtil(signal.entryPrice - signal.stopLoss, _Symbol));
   double lots = g_riskManager.CalculateOptimalLot(slPips, InpDefaultRisk);
   double maxLots = g_riskManager.CalculateMaxAllowableLot(slPips);
   if(lots > maxLots) lots = maxLots;
   if(lots <= 0)
   {
      if(InpEnableLog) LogDebugUtil("Lot size is 0");
      return;
   }
   if(!g_riskManager.CanOpenPosition(lots, slPips))
   {
      if(InpEnableLog) LogDebugUtil("RiskManager rejected position");
      return;
   }

   ENUM_ORDER_TYPE orderType = (signal.direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string comment = StringFormat("XAUEA_%d_%s", signal.logicCount, signal.description);
   double tp = InpEnablePartialTP ? signal.takeProfit2 : signal.takeProfit1;

   if(g_positionManager.OpenPosition(orderType, lots, signal.stopLoss, tp, comment))
   {
      if(InpEnableLog)
      {
         LogDebugUtil(StringFormat("Opened: %s, %.2f lots, Entry=%.2f, SL=%.2f, TP=%.2f",
                  (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
                  lots, signal.entryPrice, signal.stopLoss, tp));
         g_riskManager.PrintRiskStatus();
      }
   }
}
//+------------------------------------------------------------------+
