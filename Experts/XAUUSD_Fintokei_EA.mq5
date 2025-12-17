//+------------------------------------------------------------------+
//|                                         XAUUSD_Fintokei_EA.mq5   |
//|                           Simple Prop Trade Success EA           |
//|                           Fintokei Challenge Compliant           |
//+------------------------------------------------------------------+
#property copyright "Fintokei Challenge EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input ENUM_TIMEFRAMES TradingTimeframe = PERIOD_M5;     // Trading Timeframe
input int      SlowMAPeriod = 200;                       // Slow MA Period (SMA)
input int      FastMAPeriod = 100;                       // Fast MA Period (EMA)
input int      SupportResistanceLookback = 50;           // S/R Lookback Period
input double   SRZoneWidth = 5.0;                        // S/R Zone Width (points)
input int      MinConfluenceSignals = 2;                 // Minimum Confluence Signals

input group "=== Risk Management ==="
input double   RiskPerTrade = 1.0;                       // Risk Per Trade (%)
input double   MaxRiskPercentage = 3.0;                  // Max Open Position Risk (%)
input double   StopLossPips = 100;                       // Stop Loss (pips)
input double   TakeProfitRatio = 2.0;                    // Take Profit Ratio (Risk:Reward)

input group "=== Fintokei Challenge Settings ==="
input int      ChallengeStep = 1;                        // Challenge Step (1 or 2)
input double   InitialBalance = 10000000;                // Initial Balance (JPY)
input double   DailyLossLimit = 5.0;                     // Daily Loss Limit (%)
input double   TotalLossLimit = 10.0;                    // Total Loss Limit (%)
input double   Step1ProfitTarget = 8.0;                  // Step 1 Profit Target (%)
input double   Step2ProfitTarget = 6.0;                  // Step 2 Profit Target (%)
input int      MinTradingDays = 3;                       // Minimum Trading Days
input double   SafetyBuffer = 0.5;                       // Safety Buffer (%)

input group "=== Trading Hours ==="
input int      TradeStartHour = 9;                       // Trade Start Hour (Server Time)
input int      TradeEndHour = 22;                        // Trade End Hour (Server Time)
input bool     TradeOnMonday = true;                     // Trade on Monday
input bool     TradeOnFriday = true;                     // Trade on Friday

input group "=== Price Action Settings ==="
input double   PinBarRatio = 0.6;                        // Pin Bar Wick/Body Ratio
input double   EngulfingMinSize = 1.5;                   // Engulfing Min Size Ratio

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;

int            slowMAHandle;
int            fastMAHandle;

double         dailyStartEquity;
datetime       dailyResetTime;
double         totalLossLine;
double         dailyLossLine;
double         profitTarget;

int            tradingDaysCount;
datetime       lastTradingDay;
datetime       lastActivityTime;

bool           challengeCompleted;
bool           tradingAllowed;

string         SYMBOL = "XAUUSD";
int            MAGIC_NUMBER = 20241201;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Verify symbol
   if(Symbol() != SYMBOL)
   {
      Print("Error: This EA is designed for ", SYMBOL, " only!");
      return INIT_FAILED;
   }

   // Initialize MA handles
   slowMAHandle = iMA(SYMBOL, TradingTimeframe, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   fastMAHandle = iMA(SYMBOL, TradingTimeframe, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(slowMAHandle == INVALID_HANDLE || fastMAHandle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   // Initialize trade settings
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Initialize challenge parameters
   InitializeChallengeParameters();

   Print("EA initialized successfully for ", SYMBOL);
   Print("Challenge Step: ", ChallengeStep);
   Print("Profit Target: ", DoubleToString(profitTarget, 2), "%");
   Print("Daily Loss Limit: ", DoubleToString(DailyLossLimit, 2), "%");
   Print("Total Loss Limit: ", DoubleToString(TotalLossLimit, 2), "%");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(slowMAHandle != INVALID_HANDLE)
      IndicatorRelease(slowMAHandle);
   if(fastMAHandle != INVALID_HANDLE)
      IndicatorRelease(fastMAHandle);

   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Initialize Challenge Parameters                                   |
//+------------------------------------------------------------------+
void InitializeChallengeParameters()
{
   // Set profit target based on challenge step
   if(ChallengeStep == 1)
      profitTarget = Step1ProfitTarget;
   else
      profitTarget = Step2ProfitTarget;

   // Calculate loss lines
   totalLossLine = InitialBalance * (1.0 - TotalLossLimit / 100.0);

   // Initialize daily tracking
   dailyStartEquity = accountInfo.Equity();
   dailyResetTime = GetDailyResetTime();
   UpdateDailyLossLine();

   // Initialize trading day counter
   tradingDaysCount = 0;
   lastTradingDay = 0;
   lastActivityTime = TimeCurrent();

   // Challenge status
   challengeCompleted = false;
   tradingAllowed = true;
}

//+------------------------------------------------------------------+
//| Get UTC 0:00 reset time                                          |
//+------------------------------------------------------------------+
datetime GetDailyResetTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Update daily loss line                                            |
//+------------------------------------------------------------------+
void UpdateDailyLossLine()
{
   dailyLossLine = dailyStartEquity * (1.0 - (DailyLossLimit - SafetyBuffer) / 100.0);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if challenge is completed
   if(challengeCompleted)
   {
      Comment("Challenge Completed! All targets achieved.");
      return;
   }

   // Check daily reset
   CheckDailyReset();

   // Monitor risk limits
   if(!MonitorRiskLimits())
   {
      Comment("Trading paused due to risk limits.");
      return;
   }

   // Check profit target achievement
   if(CheckProfitTarget())
   {
      return;
   }

   // Check trading hours
   if(!IsTradingHoursAllowed())
   {
      return;
   }

   // Check 30-day activity requirement
   CheckActivityRequirement();

   // Main trading logic
   ExecuteTradingLogic();

   // Update display
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Check and handle daily reset                                      |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime currentResetTime = GetDailyResetTime();

   if(currentResetTime > dailyResetTime)
   {
      // New day started
      dailyResetTime = currentResetTime;
      dailyStartEquity = accountInfo.Equity();
      UpdateDailyLossLine();

      Print("Daily reset at: ", TimeToString(dailyResetTime));
      Print("New daily start equity: ", DoubleToString(dailyStartEquity, 2));
      Print("New daily loss line: ", DoubleToString(dailyLossLine, 2));
   }
}

//+------------------------------------------------------------------+
//| Monitor risk limits                                               |
//+------------------------------------------------------------------+
bool MonitorRiskLimits()
{
   double currentEquity = accountInfo.Equity();

   // Check total loss limit (10%)
   if(currentEquity <= totalLossLine)
   {
      Print("CRITICAL: Total loss limit reached! Closing all positions.");
      CloseAllPositions();
      tradingAllowed = false;
      return false;
   }

   // Check daily loss limit (5%)
   if(currentEquity <= dailyLossLine)
   {
      Print("WARNING: Daily loss limit approaching! Closing all positions.");
      CloseAllPositions();
      tradingAllowed = false;
      return false;
   }

   // Check if approaching limits - emergency close
   double dailyLossPercent = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   double totalLossPercent = (InitialBalance - currentEquity) / InitialBalance * 100.0;

   if(dailyLossPercent >= (DailyLossLimit - SafetyBuffer))
   {
      Print("Approaching daily loss limit: ", DoubleToString(dailyLossPercent, 2), "%");
      CloseAllPositions();
      return false;
   }

   if(totalLossPercent >= (TotalLossLimit - SafetyBuffer))
   {
      Print("Approaching total loss limit: ", DoubleToString(totalLossPercent, 2), "%");
      CloseAllPositions();
      return false;
   }

   tradingAllowed = true;
   return true;
}

//+------------------------------------------------------------------+
//| Check profit target                                               |
//+------------------------------------------------------------------+
bool CheckProfitTarget()
{
   double currentEquity = accountInfo.Equity();
   double profitPercent = (currentEquity - InitialBalance) / InitialBalance * 100.0;

   if(profitPercent >= profitTarget)
   {
      // Check if we have met minimum trading days
      if(tradingDaysCount >= MinTradingDays)
      {
         // Close all positions
         CloseAllPositions();

         // Verify no open positions
         if(CountOpenPositions() == 0)
         {
            challengeCompleted = true;
            Print("===========================================");
            Print("CHALLENGE STEP ", ChallengeStep, " COMPLETED!");
            Print("Profit achieved: ", DoubleToString(profitPercent, 2), "%");
            Print("Trading days: ", tradingDaysCount);
            Print("===========================================");
            return true;
         }
      }
      else
      {
         Print("Profit target reached but minimum trading days not met.");
         Print("Trading days: ", tradingDaysCount, "/", MinTradingDays);
         // Continue trading to meet minimum days
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if trading hours allowed                                    |
//+------------------------------------------------------------------+
bool IsTradingHoursAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Check day of week
   if(dt.day_of_week == 0) return false; // Sunday
   if(dt.day_of_week == 1 && !TradeOnMonday) return false;
   if(dt.day_of_week == 5 && !TradeOnFriday) return false;
   if(dt.day_of_week == 6) return false; // Saturday

   // Check trading hours
   if(dt.hour < TradeStartHour || dt.hour >= TradeEndHour)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check 30-day activity requirement                                 |
//+------------------------------------------------------------------+
void CheckActivityRequirement()
{
   datetime currentTime = TimeCurrent();

   // Check if 25 days have passed without activity (warning before 30 days)
   if(currentTime - lastActivityTime > 25 * 24 * 60 * 60)
   {
      Print("WARNING: 25 days without trading activity. Activity required within 5 days.");
   }
}

//+------------------------------------------------------------------+
//| Execute main trading logic                                        |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
   // Check if we already have a position
   if(CountOpenPositions() > 0)
   {
      ManageOpenPositions();
      return;
   }

   // Check risk allocation
   if(!CanOpenNewPosition())
   {
      return;
   }

   // Get MA values
   double slowMA[], fastMA[];
   ArraySetAsSeries(slowMA, true);
   ArraySetAsSeries(fastMA, true);

   if(CopyBuffer(slowMAHandle, 0, 0, 3, slowMA) < 3) return;
   if(CopyBuffer(fastMAHandle, 0, 0, 3, fastMA) < 3) return;

   // Get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(SYMBOL, TradingTimeframe, 0, SupportResistanceLookback + 5, rates) < SupportResistanceLookback + 5) return;

   double currentPrice = rates[0].close;
   double currentHigh = rates[0].high;
   double currentLow = rates[0].low;

   // Calculate confluence signals
   int buySignals = 0;
   int sellSignals = 0;

   // 1. Granville's Law - MA analysis
   int granvilleBuy = CheckGranvilleBuy(slowMA, fastMA, rates);
   int granvilleSell = CheckGranvilleSell(slowMA, fastMA, rates);
   buySignals += granvilleBuy;
   sellSignals += granvilleSell;

   // 2. Support/Resistance levels
   double supportLevel, resistanceLevel;
   FindSupportResistance(rates, supportLevel, resistanceLevel);

   if(currentLow <= supportLevel + SRZoneWidth * _Point && currentPrice > supportLevel)
      buySignals++;
   if(currentHigh >= resistanceLevel - SRZoneWidth * _Point && currentPrice < resistanceLevel)
      sellSignals++;

   // 3. Price Action patterns
   int priceActionBuy = CheckBullishPriceAction(rates);
   int priceActionSell = CheckBearishPriceAction(rates);
   buySignals += priceActionBuy;
   sellSignals += priceActionSell;

   // Entry logic - require minimum confluence
   if(buySignals >= MinConfluenceSignals && sellSignals < MinConfluenceSignals)
   {
      ExecuteBuyOrder(supportLevel);
   }
   else if(sellSignals >= MinConfluenceSignals && buySignals < MinConfluenceSignals)
   {
      ExecuteSellOrder(resistanceLevel);
   }
}

//+------------------------------------------------------------------+
//| Check Granville's Law for Buy signal                              |
//+------------------------------------------------------------------+
int CheckGranvilleBuy(double &slowMA[], double &fastMA[], MqlRates &rates[])
{
   int signals = 0;
   double currentPrice = rates[0].close;

   // Price above 200 SMA (uptrend)
   bool inUptrend = currentPrice > slowMA[0];

   // Granville Law 1: Price crosses above MA from below
   if(rates[1].close < slowMA[1] && rates[0].close > slowMA[0])
      signals++;

   // Granville Law 2: Price pulls back to MA in uptrend and bounces
   if(inUptrend && rates[1].low <= slowMA[1] * 1.001 && rates[0].close > slowMA[0])
      signals++;

   // Granville Law 3: Price pulls back toward MA but doesn't touch, then rises
   if(inUptrend && rates[2].close > rates[1].close && rates[1].close > slowMA[1] &&
      rates[1].low > slowMA[1] && rates[0].close > rates[1].close)
      signals++;

   // Fast MA (100 EMA) support
   if(rates[1].low <= fastMA[1] * 1.002 && rates[0].close > fastMA[0] && inUptrend)
      signals++;

   return MathMin(signals, 2); // Max 2 signals from Granville
}

//+------------------------------------------------------------------+
//| Check Granville's Law for Sell signal                             |
//+------------------------------------------------------------------+
int CheckGranvilleSell(double &slowMA[], double &fastMA[], MqlRates &rates[])
{
   int signals = 0;
   double currentPrice = rates[0].close;

   // Price below 200 SMA (downtrend)
   bool inDowntrend = currentPrice < slowMA[0];

   // Granville Law 5: Price crosses below MA from above
   if(rates[1].close > slowMA[1] && rates[0].close < slowMA[0])
      signals++;

   // Granville Law 6: Price pulls back to MA in downtrend and falls
   if(inDowntrend && rates[1].high >= slowMA[1] * 0.999 && rates[0].close < slowMA[0])
      signals++;

   // Granville Law 7: Price pulls back toward MA but doesn't touch, then falls
   if(inDowntrend && rates[2].close < rates[1].close && rates[1].close < slowMA[1] &&
      rates[1].high < slowMA[1] && rates[0].close < rates[1].close)
      signals++;

   // Fast MA (100 EMA) resistance
   if(rates[1].high >= fastMA[1] * 0.998 && rates[0].close < fastMA[0] && inDowntrend)
      signals++;

   return MathMin(signals, 2); // Max 2 signals from Granville
}

//+------------------------------------------------------------------+
//| Find Support and Resistance levels                                |
//+------------------------------------------------------------------+
void FindSupportResistance(MqlRates &rates[], double &support, double &resistance)
{
   support = DBL_MAX;
   resistance = 0;

   // Find swing lows (support) and swing highs (resistance)
   for(int i = 2; i < SupportResistanceLookback - 2; i++)
   {
      // Swing low
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
         rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
      {
         if(rates[i].low < support)
            support = rates[i].low;
      }

      // Swing high
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
         rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
      {
         if(rates[i].high > resistance)
            resistance = rates[i].high;
      }
   }

   // Default values if not found
   if(support == DBL_MAX) support = rates[0].low - 100 * _Point;
   if(resistance == 0) resistance = rates[0].high + 100 * _Point;
}

//+------------------------------------------------------------------+
//| Check Bullish Price Action patterns                               |
//+------------------------------------------------------------------+
int CheckBullishPriceAction(MqlRates &rates[])
{
   int signals = 0;

   // Pin Bar (Hammer)
   if(IsBullishPinBar(rates[1]))
      signals++;

   // Bullish Engulfing
   if(IsBullishEngulfing(rates[2], rates[1]))
      signals++;

   // Morning Star (simplified)
   if(IsMorningStar(rates[3], rates[2], rates[1]))
      signals++;

   return MathMin(signals, 2);
}

//+------------------------------------------------------------------+
//| Check Bearish Price Action patterns                               |
//+------------------------------------------------------------------+
int CheckBearishPriceAction(MqlRates &rates[])
{
   int signals = 0;

   // Pin Bar (Shooting Star)
   if(IsBearishPinBar(rates[1]))
      signals++;

   // Bearish Engulfing
   if(IsBearishEngulfing(rates[2], rates[1]))
      signals++;

   // Evening Star (simplified)
   if(IsEveningStar(rates[3], rates[2], rates[1]))
      signals++;

   return MathMin(signals, 2);
}

//+------------------------------------------------------------------+
//| Check for Bullish Pin Bar (Hammer)                                |
//+------------------------------------------------------------------+
bool IsBullishPinBar(MqlRates &rate)
{
   double body = MathAbs(rate.close - rate.open);
   double totalRange = rate.high - rate.low;
   double lowerWick = MathMin(rate.open, rate.close) - rate.low;
   double upperWick = rate.high - MathMax(rate.open, rate.close);

   if(totalRange == 0) return false;

   // Long lower wick, small body, small upper wick
   return (lowerWick / totalRange >= PinBarRatio &&
           body / totalRange <= (1 - PinBarRatio) &&
           upperWick < lowerWick * 0.3);
}

//+------------------------------------------------------------------+
//| Check for Bearish Pin Bar (Shooting Star)                         |
//+------------------------------------------------------------------+
bool IsBearishPinBar(MqlRates &rate)
{
   double body = MathAbs(rate.close - rate.open);
   double totalRange = rate.high - rate.low;
   double lowerWick = MathMin(rate.open, rate.close) - rate.low;
   double upperWick = rate.high - MathMax(rate.open, rate.close);

   if(totalRange == 0) return false;

   // Long upper wick, small body, small lower wick
   return (upperWick / totalRange >= PinBarRatio &&
           body / totalRange <= (1 - PinBarRatio) &&
           lowerWick < upperWick * 0.3);
}

//+------------------------------------------------------------------+
//| Check for Bullish Engulfing                                       |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(MqlRates &prev, MqlRates &curr)
{
   // Previous candle is bearish
   bool prevBearish = prev.close < prev.open;
   // Current candle is bullish
   bool currBullish = curr.close > curr.open;

   double prevBody = MathAbs(prev.close - prev.open);
   double currBody = MathAbs(curr.close - curr.open);

   // Current body engulfs previous body
   return (prevBearish && currBullish &&
           curr.close > prev.open && curr.open < prev.close &&
           currBody >= prevBody * EngulfingMinSize);
}

//+------------------------------------------------------------------+
//| Check for Bearish Engulfing                                       |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(MqlRates &prev, MqlRates &curr)
{
   // Previous candle is bullish
   bool prevBullish = prev.close > prev.open;
   // Current candle is bearish
   bool currBearish = curr.close < curr.open;

   double prevBody = MathAbs(prev.close - prev.open);
   double currBody = MathAbs(curr.close - curr.open);

   // Current body engulfs previous body
   return (prevBullish && currBearish &&
           curr.close < prev.open && curr.open > prev.close &&
           currBody >= prevBody * EngulfingMinSize);
}

//+------------------------------------------------------------------+
//| Check for Morning Star pattern                                    |
//+------------------------------------------------------------------+
bool IsMorningStar(MqlRates &first, MqlRates &middle, MqlRates &last)
{
   double firstBody = MathAbs(first.close - first.open);
   double middleBody = MathAbs(middle.close - middle.open);
   double lastBody = MathAbs(last.close - last.open);

   // First candle: bearish with large body
   bool firstBearish = first.close < first.open;
   // Middle candle: small body (doji or small)
   bool middleSmall = middleBody < firstBody * 0.3;
   // Last candle: bullish with large body
   bool lastBullish = last.close > last.open;

   return (firstBearish && middleSmall && lastBullish &&
           last.close > (first.open + first.close) / 2);
}

//+------------------------------------------------------------------+
//| Check for Evening Star pattern                                    |
//+------------------------------------------------------------------+
bool IsEveningStar(MqlRates &first, MqlRates &middle, MqlRates &last)
{
   double firstBody = MathAbs(first.close - first.open);
   double middleBody = MathAbs(middle.close - middle.open);
   double lastBody = MathAbs(last.close - last.open);

   // First candle: bullish with large body
   bool firstBullish = first.close > first.open;
   // Middle candle: small body (doji or small)
   bool middleSmall = middleBody < firstBody * 0.3;
   // Last candle: bearish with large body
   bool lastBearish = last.close < last.open;

   return (firstBullish && middleSmall && lastBearish &&
           last.close < (first.open + first.close) / 2);
}

//+------------------------------------------------------------------+
//| Can open new position based on risk                               |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
   double currentEquity = accountInfo.Equity();
   double openRisk = CalculateOpenPositionRisk();
   double newTradeRisk = RiskPerTrade;

   // Check if total risk would exceed maximum
   if(openRisk + newTradeRisk > MaxRiskPercentage)
   {
      Print("Cannot open new position. Current risk: ", DoubleToString(openRisk, 2),
            "%, Max allowed: ", DoubleToString(MaxRiskPercentage, 2), "%");
      return false;
   }

   // Check if trade would risk violating daily loss limit
   double potentialLoss = currentEquity * (RiskPerTrade / 100.0);
   if(currentEquity - potentialLoss <= dailyLossLine)
   {
      Print("Cannot open position - would risk daily loss limit");
      return false;
   }

   // Check if trade would risk violating total loss limit
   if(currentEquity - potentialLoss <= totalLossLine)
   {
      Print("Cannot open position - would risk total loss limit");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate open position risk                                      |
//+------------------------------------------------------------------+
double CalculateOpenPositionRisk()
{
   double totalRisk = 0;
   double equity = accountInfo.Equity();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
         {
            double positionRisk = MathAbs(positionInfo.Profit());
            if(positionInfo.Profit() < 0)
            {
               totalRisk += (MathAbs(positionInfo.Profit()) / equity) * 100.0;
            }
         }
      }
   }

   return totalRisk;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPoints)
{
   double equity = accountInfo.Equity();
   double riskAmount = equity * (RiskPerTrade / 100.0);

   double tickValue = SymbolInfoDouble(SYMBOL, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(SYMBOL, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / tickSize * _Point;

   if(pointValue == 0 || stopLossPoints == 0) return 0.01;

   double lotSize = riskAmount / (stopLossPoints * pointValue);

   // Normalize lot size
   double minLot = SymbolInfoDouble(SYMBOL, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(SYMBOL, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(SYMBOL, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Execute Buy Order                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double supportLevel)
{
   double ask = SymbolInfoDouble(SYMBOL, SYMBOL_ASK);
   double stopLoss = ask - StopLossPips * _Point * 10;
   double takeProfit = ask + StopLossPips * TakeProfitRatio * _Point * 10;

   // Use support level for stop loss if available
   if(supportLevel > 0 && supportLevel < ask)
   {
      stopLoss = supportLevel - 20 * _Point;
   }

   double stopLossPoints = (ask - stopLoss) / _Point;
   double lotSize = CalculateLotSize(stopLossPoints);

   if(lotSize < SymbolInfoDouble(SYMBOL, SYMBOL_VOLUME_MIN))
   {
      Print("Calculated lot size too small");
      return;
   }

   // Verify risk before execution
   double potentialLoss = lotSize * stopLossPoints * SymbolInfoDouble(SYMBOL, SYMBOL_TRADE_TICK_VALUE) /
                          SymbolInfoDouble(SYMBOL, SYMBOL_TRADE_TICK_SIZE) * _Point;

   if(accountInfo.Equity() - potentialLoss <= dailyLossLine ||
      accountInfo.Equity() - potentialLoss <= totalLossLine)
   {
      Print("Order rejected - potential loss exceeds limits");
      return;
   }

   if(trade.Buy(lotSize, SYMBOL, ask, stopLoss, takeProfit, "XAUUSD_Fintokei_Buy"))
   {
      Print("Buy order executed: Lot=", lotSize, " SL=", stopLoss, " TP=", takeProfit);
      UpdateTradingDay();
      lastActivityTime = TimeCurrent();
   }
   else
   {
      Print("Buy order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Order                                                |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double resistanceLevel)
{
   double bid = SymbolInfoDouble(SYMBOL, SYMBOL_BID);
   double stopLoss = bid + StopLossPips * _Point * 10;
   double takeProfit = bid - StopLossPips * TakeProfitRatio * _Point * 10;

   // Use resistance level for stop loss if available
   if(resistanceLevel > 0 && resistanceLevel > bid)
   {
      stopLoss = resistanceLevel + 20 * _Point;
   }

   double stopLossPoints = (stopLoss - bid) / _Point;
   double lotSize = CalculateLotSize(stopLossPoints);

   if(lotSize < SymbolInfoDouble(SYMBOL, SYMBOL_VOLUME_MIN))
   {
      Print("Calculated lot size too small");
      return;
   }

   // Verify risk before execution
   double potentialLoss = lotSize * stopLossPoints * SymbolInfoDouble(SYMBOL, SYMBOL_TRADE_TICK_VALUE) /
                          SymbolInfoDouble(SYMBOL, SYMBOL_TRADE_TICK_SIZE) * _Point;

   if(accountInfo.Equity() - potentialLoss <= dailyLossLine ||
      accountInfo.Equity() - potentialLoss <= totalLossLine)
   {
      Print("Order rejected - potential loss exceeds limits");
      return;
   }

   if(trade.Sell(lotSize, SYMBOL, bid, stopLoss, takeProfit, "XAUUSD_Fintokei_Sell"))
   {
      Print("Sell order executed: Lot=", lotSize, " SL=", stopLoss, " TP=", takeProfit);
      UpdateTradingDay();
      lastActivityTime = TimeCurrent();
   }
   else
   {
      Print("Sell order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Update trading day counter                                        |
//+------------------------------------------------------------------+
void UpdateTradingDay()
{
   datetime today = GetDailyResetTime();

   if(today > lastTradingDay)
   {
      tradingDaysCount++;
      lastTradingDay = today;
      Print("Trading day count updated: ", tradingDaysCount);
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
         {
            // Trail stop loss when in profit
            TrailStopLoss(positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trail stop loss                                                   |
//+------------------------------------------------------------------+
void TrailStopLoss(ulong ticket)
{
   if(!positionInfo.SelectByTicket(ticket)) return;

   double currentSL = positionInfo.StopLoss();
   double currentTP = positionInfo.TakeProfit();
   double openPrice = positionInfo.PriceOpen();
   double currentPrice;
   double trailDistance = StopLossPips * _Point * 10 * 0.5; // 50% of SL as trail distance

   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      currentPrice = SymbolInfoDouble(SYMBOL, SYMBOL_BID);
      double newSL = currentPrice - trailDistance;

      // Only trail if price moved enough and new SL is better than current
      if(currentPrice > openPrice + trailDistance && newSL > currentSL)
      {
         trade.PositionModify(ticket, newSL, currentTP);
      }
   }
   else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
   {
      currentPrice = SymbolInfoDouble(SYMBOL, SYMBOL_ASK);
      double newSL = currentPrice + trailDistance;

      // Only trail if price moved enough and new SL is better than current
      if(currentPrice < openPrice - trailDistance && (newSL < currentSL || currentSL == 0))
      {
         trade.PositionModify(ticket, newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
         {
            trade.PositionClose(positionInfo.Ticket());
            Print("Position closed: ", positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update display information                                        |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double currentEquity = accountInfo.Equity();
   double currentBalance = accountInfo.Balance();
   double profitPercent = (currentEquity - InitialBalance) / InitialBalance * 100.0;
   double dailyPL = currentEquity - dailyStartEquity;
   double dailyPLPercent = dailyPL / dailyStartEquity * 100.0;

   string display = "";
   display += "=== XAUUSD Fintokei Challenge EA ===\n";
   display += StringFormat("Challenge Step: %d\n", ChallengeStep);
   display += StringFormat("Initial Balance: %.2f\n", InitialBalance);
   display += StringFormat("Current Equity: %.2f\n", currentEquity);
   display += StringFormat("Current Balance: %.2f\n", currentBalance);
   display += "-----------------------------------\n";
   display += StringFormat("Profit Target: %.2f%% (%.2f%%)\n", profitTarget, profitPercent);
   display += StringFormat("Daily P/L: %.2f (%.2f%%)\n", dailyPL, dailyPLPercent);
   display += StringFormat("Daily Loss Limit: %.2f%%\n", DailyLossLimit);
   display += StringFormat("Daily Loss Line: %.2f\n", dailyLossLine);
   display += StringFormat("Total Loss Line: %.2f\n", totalLossLine);
   display += "-----------------------------------\n";
   display += StringFormat("Trading Days: %d/%d\n", tradingDaysCount, MinTradingDays);
   display += StringFormat("Open Positions: %d\n", CountOpenPositions());
   display += StringFormat("Trading Allowed: %s\n", tradingAllowed ? "Yes" : "No");
   display += StringFormat("Challenge Status: %s\n", challengeCompleted ? "COMPLETED" : "In Progress");

   Comment(display);
}

//+------------------------------------------------------------------+
