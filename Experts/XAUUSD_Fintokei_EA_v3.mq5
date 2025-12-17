//+------------------------------------------------------------------+
//|                                      XAUUSD_Fintokei_EA_v3.mq5   |
//|                      Simple Prop Trade Success EA - Version 3    |
//|                         Fintokei Challenge Compliant             |
//+------------------------------------------------------------------+
#property copyright "Fintokei Challenge EA v3"
#property link      ""
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Multi-Timeframe Settings ==="
input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_M5;        // Entry Timeframe (M5)
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H1;        // Trend Timeframe (H1)
input int      TrendMAPeriod = 50;                        // Trend MA Period (H1)

input group "=== Price Action Settings ==="
input double   PinBarWickRatio = 0.60;                    // Pin Bar Wick Ratio (relaxed)
input double   PinBarBodyMaxRatio = 0.40;                 // Pin Bar Body Max Ratio
input double   EngulfingMinRatio = 1.0;                   // Engulfing Min Size Ratio
input bool     RequireSRConfluence = false;               // Require S/R Confluence
input int      SRLookbackPeriod = 30;                     // S/R Lookback Period
input double   SRTouchDistance = 300;                     // S/R Touch Distance (points)

input group "=== Risk Management (CRITICAL) ==="
input double   RiskPerTrade = 0.5;                        // Risk Per Trade (%)
input double   MaxDailyRisk = 2.0;                        // Max Daily Risk (%)
input double   StopLossPoints = 300;                      // Stop Loss (points) - reduced
input double   TakeProfitRatio = 2.0;                     // Take Profit Ratio (R:R)
input double   MaxSpread = 80;                            // Max Spread (points)

input group "=== Fintokei Challenge Settings ==="
input int      ChallengeStep = 1;                         // Challenge Step (1 or 2)
input double   InitialBalance = 0;                        // Initial Balance (0=Auto)
input double   DailyLossLimit = 5.0;                      // Daily Loss Limit (%)
input double   TotalLossLimit = 10.0;                     // Total Loss Limit (%)
input double   Step1ProfitTarget = 8.0;                   // Step 1 Profit Target (%)
input double   Step2ProfitTarget = 6.0;                   // Step 2 Profit Target (%)
input int      MinTradingDays = 3;                        // Minimum Trading Days
input double   SafetyBuffer = 1.0;                        // Safety Buffer (%)
input bool     ContinueAfterTarget = true;                // Continue Trading After Target

input group "=== Trading Hours (Server Time) ==="
input int      SessionStartHour = 8;                      // Session Start Hour
input int      SessionEndHour = 22;                       // Session End Hour
input bool     TradeOnFriday = true;                      // Trade on Friday

input group "=== Daily Trading Settings ==="
input int      MaxTradesPerDay = 5;                       // Max Trades Per Day
input int      MaxOpenPositions = 1;                      // Max Open Positions

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symbolInfo;

// Indicator handles
int            trendMAHandle;

// Challenge tracking
double         actualInitialBalance;
double         dailyStartEquity;
datetime       dailyResetTime;
double         totalLossLine;
double         dailyLossLine;
double         profitTarget;

// Trading state
int            tradingDaysCount;
datetime       lastTradingDay;
int            todayTradeCount;
datetime       lastTradeDate;

// Flags
bool           challengeCompleted;
bool           tradingAllowed;
bool           totalLossReached;
bool           dailyLossReached;

// Constants
string         SYMBOL = "XAUUSD";
int            MAGIC_NUMBER = 20241203;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize symbol info
   if(!symbolInfo.Name(SYMBOL))
   {
      Print("Error: Failed to initialize symbol info for ", SYMBOL);
      return INIT_FAILED;
   }

   // Verify symbol
   if(Symbol() != SYMBOL)
   {
      Print("Error: This EA is designed for ", SYMBOL, " only! Current: ", Symbol());
      return INIT_FAILED;
   }

   // Initialize indicator handles
   trendMAHandle = iMA(SYMBOL, TrendTimeframe, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(trendMAHandle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicator handle!");
      return INIT_FAILED;
   }

   // Initialize trade settings
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Initialize challenge parameters
   InitializeChallengeParameters();

   // Reset daily counters
   ResetDailyCounters();

   Print("===========================================");
   Print("XAUUSD Fintokei EA v3 Initialized");
   Print("Challenge Step: ", ChallengeStep);
   Print("Initial Balance: ", DoubleToString(actualInitialBalance, 2));
   Print("Profit Target: ", DoubleToString(profitTarget, 2), "%");
   Print("Risk Per Trade: ", DoubleToString(RiskPerTrade, 2), "%");
   Print("Stop Loss: ", StopLossPoints, " points");
   Print("===========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(trendMAHandle != INVALID_HANDLE) IndicatorRelease(trendMAHandle);
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Initialize Challenge Parameters                                   |
//+------------------------------------------------------------------+
void InitializeChallengeParameters()
{
   profitTarget = (ChallengeStep == 1) ? Step1ProfitTarget : Step2ProfitTarget;

   if(InitialBalance <= 0)
      actualInitialBalance = accountInfo.Balance();
   else
      actualInitialBalance = InitialBalance;

   totalLossLine = actualInitialBalance * (1.0 - (TotalLossLimit - SafetyBuffer) / 100.0);

   dailyStartEquity = accountInfo.Equity();
   dailyResetTime = GetTodayStartTime();
   UpdateDailyLossLine();

   tradingDaysCount = 0;
   lastTradingDay = 0;

   challengeCompleted = false;
   tradingAllowed = true;
   totalLossReached = false;
   dailyLossReached = false;

   Print("Total Loss Line: ", DoubleToString(totalLossLine, 2));
   Print("Daily Loss Line: ", DoubleToString(dailyLossLine, 2));
}

//+------------------------------------------------------------------+
//| Get today's start time (00:00)                                    |
//+------------------------------------------------------------------+
datetime GetTodayStartTime()
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
//| Reset daily counters                                              |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   datetime today = GetTodayStartTime();
   if(today != lastTradeDate)
   {
      todayTradeCount = 0;
      lastTradeDate = today;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   symbolInfo.RefreshRates();

   CheckDailyReset();
   ResetDailyCounters();
   MonitorOpenPositions();

   if(!CheckRiskLimits())
   {
      UpdateDisplay();
      return;
   }

   if(challengeCompleted && !ContinueAfterTarget)
   {
      UpdateDisplay();
      return;
   }

   CheckProfitTarget();

   if(!IsTradingAllowed())
   {
      UpdateDisplay();
      return;
   }

   // Execute trading logic on new bar only
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(SYMBOL, EntryTimeframe, 0);

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      ExecuteTradingLogic();
   }

   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Check and handle daily reset                                      |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime today = GetTodayStartTime();

   if(today > dailyResetTime)
   {
      dailyResetTime = today;
      dailyStartEquity = accountInfo.Equity();
      UpdateDailyLossLine();

      dailyLossReached = false;
      if(!totalLossReached) tradingAllowed = true;

      Print("=== Daily Reset === Date: ", TimeToString(today, TIME_DATE),
            " Equity: ", DoubleToString(dailyStartEquity, 2));
   }
}

//+------------------------------------------------------------------+
//| Check risk limits                                                 |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double currentEquity = accountInfo.Equity();

   double totalLossPercent = (actualInitialBalance - currentEquity) / actualInitialBalance * 100.0;
   if(totalLossPercent >= (TotalLossLimit - SafetyBuffer))
   {
      if(!totalLossReached)
      {
         Print("!!! TOTAL LOSS LIMIT: ", DoubleToString(totalLossPercent, 2), "%");
         totalLossReached = true;
      }
      CloseAllPositions("Total loss limit");
      tradingAllowed = false;
      return false;
   }

   double dailyLossPercent = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   if(dailyLossPercent >= (DailyLossLimit - SafetyBuffer))
   {
      if(!dailyLossReached)
      {
         Print("!!! DAILY LOSS LIMIT: ", DoubleToString(dailyLossPercent, 2), "%");
         dailyLossReached = true;
      }
      CloseAllPositions("Daily loss limit");
      tradingAllowed = false;
      return false;
   }

   tradingAllowed = true;
   return true;
}

//+------------------------------------------------------------------+
//| Check profit target                                               |
//+------------------------------------------------------------------+
void CheckProfitTarget()
{
   double currentEquity = accountInfo.Equity();
   double profitPercent = (currentEquity - actualInitialBalance) / actualInitialBalance * 100.0;

   if(profitPercent >= profitTarget && tradingDaysCount >= MinTradingDays)
   {
      if(!challengeCompleted)
      {
         Print("=== CHALLENGE TARGET REACHED === Profit: ", DoubleToString(profitPercent, 2), "%");
         if(!ContinueAfterTarget)
         {
            CloseAllPositions("Target reached");
            challengeCompleted = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                       |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   if(!tradingAllowed) return false;

   double currentSpread = symbolInfo.Spread();
   if(currentSpread > MaxSpread) return false;

   if(!IsTradingHours()) return false;

   if(todayTradeCount >= MaxTradesPerDay) return false;

   if(CountOpenPositions() >= MaxOpenPositions) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                     |
//+------------------------------------------------------------------+
bool IsTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   int dow = dt.day_of_week;

   if(dow == 0 || dow == 6) return false;
   if(dow == 5 && !TradeOnFriday) return false;

   return (hour >= SessionStartHour && hour < SessionEndHour);
}

//+------------------------------------------------------------------+
//| Execute main trading logic                                        |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
   // Get trend direction from H1
   int trendDirection = GetTrendDirection();

   // Get price action signals from M5
   int priceActionSignal = GetPriceActionSignal();
   if(priceActionSignal == 0) return;

   // Check S/R confluence if required
   bool srConfirmed = true;
   double supportLevel = 0, resistanceLevel = 0;

   if(RequireSRConfluence)
   {
      FindSupportResistance(supportLevel, resistanceLevel);
      double currentPrice = symbolInfo.Bid();
      bool nearSupport = (currentPrice - supportLevel) < SRTouchDistance * _Point;
      bool nearResistance = (resistanceLevel - currentPrice) < SRTouchDistance * _Point;

      if(priceActionSignal == 1 && !nearSupport) srConfirmed = false;
      if(priceActionSignal == -1 && !nearResistance) srConfirmed = false;
   }

   if(!srConfirmed) return;

   // Execute trades
   // Option 1: Trade with trend (safer)
   // Option 2: Trade price action only (more trades)

   bool tradeWithTrend = (trendDirection != 0);

   if(priceActionSignal == 1)  // Buy signal
   {
      if(!tradeWithTrend || trendDirection >= 0)  // Uptrend or no trend
      {
         ExecuteBuyTrade();
      }
   }
   else if(priceActionSignal == -1)  // Sell signal
   {
      if(!tradeWithTrend || trendDirection <= 0)  // Downtrend or no trend
      {
         ExecuteSellTrade();
      }
   }
}

//+------------------------------------------------------------------+
//| Get trend direction from H1 timeframe                             |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double trendMA[];
   ArraySetAsSeries(trendMA, true);

   if(CopyBuffer(trendMAHandle, 0, 0, 2, trendMA) < 2) return 0;

   MqlRates h1Rates[];
   ArraySetAsSeries(h1Rates, true);
   if(CopyRates(SYMBOL, TrendTimeframe, 0, 1, h1Rates) < 1) return 0;

   double currentPrice = h1Rates[0].close;

   if(currentPrice > trendMA[0]) return 1;   // Above MA - bullish bias
   if(currentPrice < trendMA[0]) return -1;  // Below MA - bearish bias

   return 0;
}

//+------------------------------------------------------------------+
//| Get price action signal from M5 timeframe                         |
//+------------------------------------------------------------------+
int GetPriceActionSignal()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(SYMBOL, EntryTimeframe, 0, 5, rates) < 5) return 0;

   // Check completed bar (bar 1)
   // Bullish signals
   if(IsBullishPinBar(rates[1])) return 1;
   if(IsBullishEngulfing(rates[2], rates[1])) return 1;

   // Bearish signals
   if(IsBearishPinBar(rates[1])) return -1;
   if(IsBearishEngulfing(rates[2], rates[1])) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Check for Bullish Pin Bar                                         |
//+------------------------------------------------------------------+
bool IsBullishPinBar(MqlRates &rate)
{
   double totalRange = rate.high - rate.low;
   if(totalRange < 10 * _Point) return false;  // Minimum size filter

   double body = MathAbs(rate.close - rate.open);
   double lowerWick = MathMin(rate.open, rate.close) - rate.low;
   double upperWick = rate.high - MathMax(rate.open, rate.close);

   double wickRatio = lowerWick / totalRange;
   double bodyRatio = body / totalRange;

   bool isPinBar = (wickRatio >= PinBarWickRatio &&
                    bodyRatio <= PinBarBodyMaxRatio &&
                    upperWick < lowerWick * 0.5);

   if(isPinBar)
   {
      Print("Bullish Pin Bar detected at ", TimeToString(rate.time));
   }

   return isPinBar;
}

//+------------------------------------------------------------------+
//| Check for Bearish Pin Bar                                         |
//+------------------------------------------------------------------+
bool IsBearishPinBar(MqlRates &rate)
{
   double totalRange = rate.high - rate.low;
   if(totalRange < 10 * _Point) return false;

   double body = MathAbs(rate.close - rate.open);
   double lowerWick = MathMin(rate.open, rate.close) - rate.low;
   double upperWick = rate.high - MathMax(rate.open, rate.close);

   double wickRatio = upperWick / totalRange;
   double bodyRatio = body / totalRange;

   bool isPinBar = (wickRatio >= PinBarWickRatio &&
                    bodyRatio <= PinBarBodyMaxRatio &&
                    lowerWick < upperWick * 0.5);

   if(isPinBar)
   {
      Print("Bearish Pin Bar detected at ", TimeToString(rate.time));
   }

   return isPinBar;
}

//+------------------------------------------------------------------+
//| Check for Bullish Engulfing                                       |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(MqlRates &prev, MqlRates &curr)
{
   if(prev.close >= prev.open) return false;  // Prev must be bearish
   if(curr.close <= curr.open) return false;  // Curr must be bullish

   double prevBody = MathAbs(prev.close - prev.open);
   double currBody = MathAbs(curr.close - curr.open);

   if(prevBody < 5 * _Point) return false;  // Filter tiny candles

   bool engulfs = (curr.close > prev.open && curr.open <= prev.close);
   bool sizeOK = (currBody >= prevBody * EngulfingMinRatio);

   bool isEngulfing = engulfs && sizeOK;

   if(isEngulfing)
   {
      Print("Bullish Engulfing detected at ", TimeToString(curr.time));
   }

   return isEngulfing;
}

//+------------------------------------------------------------------+
//| Check for Bearish Engulfing                                       |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(MqlRates &prev, MqlRates &curr)
{
   if(prev.close <= prev.open) return false;  // Prev must be bullish
   if(curr.close >= curr.open) return false;  // Curr must be bearish

   double prevBody = MathAbs(prev.close - prev.open);
   double currBody = MathAbs(curr.close - curr.open);

   if(prevBody < 5 * _Point) return false;

   bool engulfs = (curr.open >= prev.close && curr.close < prev.open);
   bool sizeOK = (currBody >= prevBody * EngulfingMinRatio);

   bool isEngulfing = engulfs && sizeOK;

   if(isEngulfing)
   {
      Print("Bearish Engulfing detected at ", TimeToString(curr.time));
   }

   return isEngulfing;
}

//+------------------------------------------------------------------+
//| Find Support and Resistance levels                                |
//+------------------------------------------------------------------+
void FindSupportResistance(double &support, double &resistance)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(SYMBOL, EntryTimeframe, 0, SRLookbackPeriod + 5, rates) < SRLookbackPeriod + 5)
   {
      support = 0;
      resistance = 0;
      return;
   }

   double lowestLow = DBL_MAX;
   double highestHigh = 0;

   for(int i = 2; i < SRLookbackPeriod; i++)
   {
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
      {
         if(rates[i].low < lowestLow) lowestLow = rates[i].low;
      }

      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
      {
         if(rates[i].high > highestHigh) highestHigh = rates[i].high;
      }
   }

   support = (lowestLow != DBL_MAX) ? lowestLow : rates[SRLookbackPeriod-1].low;
   resistance = (highestHigh != 0) ? highestHigh : rates[SRLookbackPeriod-1].high;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   if(slPoints <= 0) return symbolInfo.LotsMin();

   double accountEquity = accountInfo.Equity();
   double riskAmount = accountEquity * (RiskPerTrade / 100.0);

   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();

   if(tickValue == 0 || tickSize == 0) return symbolInfo.LotsMin();

   double pointValue = tickValue / tickSize * _Point;
   double lotSize = riskAmount / (slPoints * pointValue);

   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   // Daily risk limit
   double maxLotByDailyRisk = (accountEquity * MaxDailyRisk / 100.0) / (slPoints * pointValue);
   lotSize = MathMin(lotSize, maxLotByDailyRisk);

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Execute Buy Trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade()
{
   if(!PreTradeRiskCheck()) return;

   double ask = symbolInfo.Ask();
   double bid = symbolInfo.Bid();

   // Fixed stop loss in points
   double slPrice = NormalizeDouble(ask - StopLossPoints * _Point, symbolInfo.Digits());
   double slPoints = StopLossPoints;
   double tpPrice = NormalizeDouble(ask + slPoints * _Point * TakeProfitRatio, symbolInfo.Digits());

   // Validate SL/TP
   double minStopLevel = symbolInfo.StopsLevel() * _Point;
   if(minStopLevel == 0) minStopLevel = 50 * _Point;

   if((ask - slPrice) < minStopLevel)
   {
      slPrice = NormalizeDouble(ask - minStopLevel - 10 * _Point, symbolInfo.Digits());
   }
   if((tpPrice - ask) < minStopLevel)
   {
      tpPrice = NormalizeDouble(ask + minStopLevel + 10 * _Point, symbolInfo.Digits());
   }

   // Final validation: SL must be below ask, TP must be above ask
   if(slPrice >= ask || tpPrice <= ask)
   {
      Print("Invalid BUY stops: Ask=", ask, " SL=", slPrice, " TP=", tpPrice);
      return;
   }

   double lotSize = CalculateLotSize(slPoints);
   if(lotSize < symbolInfo.LotsMin())
   {
      Print("Lot size too small: ", lotSize);
      return;
   }

   if(!VerifyTradeRisk(lotSize, slPoints)) return;

   if(trade.Buy(lotSize, SYMBOL, ask, slPrice, tpPrice, "XAUUSD_v3_Buy"))
   {
      Print("BUY: Lot=", lotSize, " Entry=", ask, " SL=", slPrice, " TP=", tpPrice);
      UpdateTradingDay();
      todayTradeCount++;
   }
   else
   {
      Print("BUY failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Trade                                                |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
{
   if(!PreTradeRiskCheck()) return;

   double ask = symbolInfo.Ask();
   double bid = symbolInfo.Bid();

   // Fixed stop loss in points
   double slPrice = NormalizeDouble(bid + StopLossPoints * _Point, symbolInfo.Digits());
   double slPoints = StopLossPoints;
   double tpPrice = NormalizeDouble(bid - slPoints * _Point * TakeProfitRatio, symbolInfo.Digits());

   // Validate SL/TP
   double minStopLevel = symbolInfo.StopsLevel() * _Point;
   if(minStopLevel == 0) minStopLevel = 50 * _Point;

   if((slPrice - bid) < minStopLevel)
   {
      slPrice = NormalizeDouble(bid + minStopLevel + 10 * _Point, symbolInfo.Digits());
   }
   if((bid - tpPrice) < minStopLevel)
   {
      tpPrice = NormalizeDouble(bid - minStopLevel - 10 * _Point, symbolInfo.Digits());
   }

   // Final validation: SL must be above bid, TP must be below bid
   if(slPrice <= bid || tpPrice >= bid)
   {
      Print("Invalid SELL stops: Bid=", bid, " SL=", slPrice, " TP=", tpPrice);
      return;
   }

   double lotSize = CalculateLotSize(slPoints);
   if(lotSize < symbolInfo.LotsMin())
   {
      Print("Lot size too small: ", lotSize);
      return;
   }

   if(!VerifyTradeRisk(lotSize, slPoints)) return;

   if(trade.Sell(lotSize, SYMBOL, bid, slPrice, tpPrice, "XAUUSD_v3_Sell"))
   {
      Print("SELL: Lot=", lotSize, " Entry=", bid, " SL=", slPrice, " TP=", tpPrice);
      UpdateTradingDay();
      todayTradeCount++;
   }
   else
   {
      Print("SELL failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Pre-trade risk check                                              |
//+------------------------------------------------------------------+
bool PreTradeRiskCheck()
{
   double currentEquity = accountInfo.Equity();

   double dailyLossPercent = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   if(dailyLossPercent >= (DailyLossLimit - SafetyBuffer - RiskPerTrade))
   {
      Print("Skip trade - Daily loss limit close: ", DoubleToString(dailyLossPercent, 2), "%");
      return false;
   }

   double totalLossPercent = (actualInitialBalance - currentEquity) / actualInitialBalance * 100.0;
   if(totalLossPercent >= (TotalLossLimit - SafetyBuffer - RiskPerTrade))
   {
      Print("Skip trade - Total loss limit close: ", DoubleToString(totalLossPercent, 2), "%");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Verify trade risk before execution                                |
//+------------------------------------------------------------------+
bool VerifyTradeRisk(double lotSize, double slPoints)
{
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();
   double pointValue = tickValue / tickSize * _Point;

   double potentialLoss = lotSize * slPoints * pointValue;
   double currentEquity = accountInfo.Equity();

   if((dailyStartEquity - currentEquity + potentialLoss) / dailyStartEquity * 100.0 >= (DailyLossLimit - SafetyBuffer))
   {
      Print("Trade rejected - Would breach daily loss limit");
      return false;
   }

   if((actualInitialBalance - currentEquity + potentialLoss) / actualInitialBalance * 100.0 >= (TotalLossLimit - SafetyBuffer))
   {
      Print("Trade rejected - Would breach total loss limit");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Update trading day counter                                        |
//+------------------------------------------------------------------+
void UpdateTradingDay()
{
   datetime today = GetTodayStartTime();
   if(today > lastTradingDay)
   {
      tradingDaysCount++;
      lastTradingDay = today;
      Print("Trading day count: ", tradingDaysCount);
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
//| Monitor open positions                                            |
//+------------------------------------------------------------------+
void MonitorOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
         {
            double currentEquity = accountInfo.Equity();
            double dailyLossWithPosition = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
            double totalLossWithPosition = (actualInitialBalance - currentEquity) / actualInitialBalance * 100.0;

            if(dailyLossWithPosition >= (DailyLossLimit - SafetyBuffer * 0.5) ||
               totalLossWithPosition >= (TotalLossLimit - SafetyBuffer * 0.5))
            {
               Print("Emergency close - Approaching loss limit");
               trade.PositionClose(positionInfo.Ticket());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
         {
            trade.PositionClose(positionInfo.Ticket());
            Print("Closed (", reason, "): ", positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update display                                                    |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double currentEquity = accountInfo.Equity();
   double currentBalance = accountInfo.Balance();
   double profitPercent = (currentEquity - actualInitialBalance) / actualInitialBalance * 100.0;
   double dailyPnL = currentEquity - dailyStartEquity;
   double dailyPnLPercent = dailyPnL / dailyStartEquity * 100.0;

   string status = challengeCompleted ? "COMPLETED" : (tradingAllowed ? "Active" : "PAUSED");

   string display = "";
   display += "=== XAUUSD Fintokei EA v3 ===\n";
   display += StringFormat("Status: %s | Step: %d\n", status, ChallengeStep);
   display += StringFormat("Initial: %'.0f | Equity: %'.0f\n", actualInitialBalance, currentEquity);
   display += "-----------------------------\n";
   display += StringFormat("Profit: %+.2f%% / %.1f%% target\n", profitPercent, profitTarget);
   display += StringFormat("Daily: %+.2f%% / -%.1f%% limit\n", dailyPnLPercent, DailyLossLimit);
   display += "-----------------------------\n";
   display += StringFormat("Days: %d/%d | Trades: %d/%d\n", tradingDaysCount, MinTradingDays, todayTradeCount, MaxTradesPerDay);
   display += StringFormat("Open: %d/%d | Spread: %.0f\n", CountOpenPositions(), MaxOpenPositions, symbolInfo.Spread());

   Comment(display);
}

//+------------------------------------------------------------------+
