//+------------------------------------------------------------------+
//|                                      XAUUSD_Fintokei_EA_v2.mq5   |
//|                      Simple Prop Trade Success EA - Version 2    |
//|                         Fintokei Challenge Compliant             |
//+------------------------------------------------------------------+
#property copyright "Fintokei Challenge EA v2"
#property link      ""
#property version   "2.00"
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
input int      FastMAPeriod = 20;                         // Fast MA Period (M5)

input group "=== Price Action Settings ==="
input double   PinBarWickRatio = 0.66;                    // Pin Bar Wick Ratio (min 0.66)
input double   PinBarBodyMaxRatio = 0.33;                 // Pin Bar Body Max Ratio
input double   EngulfingMinRatio = 1.2;                   // Engulfing Min Size Ratio
input bool     WaitForConfirmation = true;                // Wait for Confirmation Candle
input int      SRLookbackPeriod = 20;                     // S/R Lookback Period
input double   SRTouchDistance = 50;                      // S/R Touch Distance (points)

input group "=== Risk Management (CRITICAL) ==="
input double   RiskPerTrade = 0.5;                        // Risk Per Trade (%)
input double   MaxDailyRisk = 2.0;                        // Max Daily Risk (%)
input double   StopLossPoints = 500;                      // Stop Loss (points)
input double   TakeProfitRatio = 2.0;                     // Take Profit Ratio (R:R)
input double   MaxSpread = 50;                            // Max Spread (points)

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
input int      LondonOpenHour = 8;                        // London Open Hour
input int      LondonCloseHour = 17;                      // London Close Hour
input int      NYOpenHour = 13;                           // NY Open Hour
input int      NYCloseHour = 22;                          // NY Close Hour
input bool     TradeAsianSession = false;                 // Trade Asian Session

input group "=== Daily Trading Settings ==="
input int      MaxTradesPerDay = 3;                       // Max Trades Per Day
input int      MaxOpenPositions = 1;                      // Max Open Positions
input bool     OneTradePerSignal = true;                  // One Trade Per Signal Type

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symbolInfo;

// Indicator handles
int            trendMAHandle;
int            fastMAHandle;
int            atrHandle;

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
double         todayPnL;

// Flags
bool           challengeCompleted;
bool           tradingAllowed;
bool           totalLossReached;
bool           dailyLossReached;

// Signal tracking
datetime       lastBuySignalTime;
datetime       lastSellSignalTime;
int            lastSignalType; // 0=none, 1=buy, 2=sell

// Constants
string         SYMBOL = "XAUUSD";
int            MAGIC_NUMBER = 20241202;

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
   fastMAHandle = iMA(SYMBOL, EntryTimeframe, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(SYMBOL, EntryTimeframe, 14);

   if(trendMAHandle == INVALID_HANDLE || fastMAHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
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

   // Reset daily counters
   ResetDailyCounters();

   Print("===========================================");
   Print("XAUUSD Fintokei EA v2 Initialized");
   Print("Challenge Step: ", ChallengeStep);
   Print("Initial Balance: ", DoubleToString(actualInitialBalance, 2));
   Print("Profit Target: ", DoubleToString(profitTarget, 2), "%");
   Print("Daily Loss Limit: ", DoubleToString(DailyLossLimit, 2), "%");
   Print("Total Loss Limit: ", DoubleToString(TotalLossLimit, 2), "%");
   Print("Risk Per Trade: ", DoubleToString(RiskPerTrade, 2), "%");
   Print("===========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(trendMAHandle != INVALID_HANDLE) IndicatorRelease(trendMAHandle);
   if(fastMAHandle != INVALID_HANDLE) IndicatorRelease(fastMAHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);

   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Initialize Challenge Parameters                                   |
//+------------------------------------------------------------------+
void InitializeChallengeParameters()
{
   // Set profit target based on challenge step
   profitTarget = (ChallengeStep == 1) ? Step1ProfitTarget : Step2ProfitTarget;

   // Set actual initial balance
   if(InitialBalance <= 0)
      actualInitialBalance = accountInfo.Balance();
   else
      actualInitialBalance = InitialBalance;

   // Calculate loss lines with safety buffer
   totalLossLine = actualInitialBalance * (1.0 - (TotalLossLimit - SafetyBuffer) / 100.0);

   // Initialize daily tracking
   dailyStartEquity = accountInfo.Equity();
   dailyResetTime = GetTodayStartTime();
   UpdateDailyLossLine();

   // Initialize counters
   tradingDaysCount = 0;
   lastTradingDay = 0;

   // Challenge status
   challengeCompleted = false;
   tradingAllowed = true;
   totalLossReached = false;
   dailyLossReached = false;

   // Signal tracking
   lastBuySignalTime = 0;
   lastSellSignalTime = 0;
   lastSignalType = 0;

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
      todayPnL = 0;
      lastTradeDate = today;
      lastSignalType = 0;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update symbol info
   symbolInfo.RefreshRates();

   // Check daily reset
   CheckDailyReset();

   // Reset daily counters
   ResetDailyCounters();

   // Monitor positions and risk
   MonitorOpenPositions();

   // Check risk limits (includes unrealized P&L)
   if(!CheckRiskLimits())
   {
      UpdateDisplay();
      return;
   }

   // Check if challenge completed
   if(challengeCompleted && !ContinueAfterTarget)
   {
      UpdateDisplay();
      return;
   }

   // Check profit target
   CheckProfitTarget();

   // Check trading conditions
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

   // Update display
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
      // New day started
      dailyResetTime = today;
      dailyStartEquity = accountInfo.Equity();
      UpdateDailyLossLine();

      // Reset flags
      dailyLossReached = false;
      if(!totalLossReached) tradingAllowed = true;

      Print("=== Daily Reset ===");
      Print("Date: ", TimeToString(today, TIME_DATE));
      Print("Starting Equity: ", DoubleToString(dailyStartEquity, 2));
      Print("Daily Loss Line: ", DoubleToString(dailyLossLine, 2));
   }
}

//+------------------------------------------------------------------+
//| Check risk limits including unrealized P&L                        |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double currentEquity = accountInfo.Equity();
   double unrealizedPnL = GetUnrealizedPnL();

   // Calculate actual equity with all positions
   double effectiveEquity = currentEquity;

   // Check total loss limit (10% from initial)
   double totalLossPercent = (actualInitialBalance - effectiveEquity) / actualInitialBalance * 100.0;

   if(totalLossPercent >= (TotalLossLimit - SafetyBuffer))
   {
      if(!totalLossReached)
      {
         Print("!!! TOTAL LOSS LIMIT APPROACHING !!!");
         Print("Loss: ", DoubleToString(totalLossPercent, 2), "% | Limit: ", DoubleToString(TotalLossLimit, 2), "%");
         totalLossReached = true;
      }
      CloseAllPositions("Total loss limit");
      tradingAllowed = false;
      return false;
   }

   // Check daily loss limit (5% from daily start)
   double dailyLossPercent = (dailyStartEquity - effectiveEquity) / dailyStartEquity * 100.0;

   if(dailyLossPercent >= (DailyLossLimit - SafetyBuffer))
   {
      if(!dailyLossReached)
      {
         Print("!!! DAILY LOSS LIMIT APPROACHING !!!");
         Print("Daily Loss: ", DoubleToString(dailyLossPercent, 2), "% | Limit: ", DoubleToString(DailyLossLimit, 2), "%");
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
//| Get unrealized P&L                                                |
//+------------------------------------------------------------------+
double GetUnrealizedPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == SYMBOL && positionInfo.Magic() == MAGIC_NUMBER)
         {
            pnl += positionInfo.Profit() + positionInfo.Swap();
         }
      }
   }
   return pnl;
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
         Print("===========================================");
         Print("!!! CHALLENGE TARGET REACHED !!!");
         Print("Profit: ", DoubleToString(profitPercent, 2), "%");
         Print("Trading Days: ", tradingDaysCount);
         Print("===========================================");

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
   // Check if trading is allowed
   if(!tradingAllowed) return false;

   // Check spread
   double currentSpread = symbolInfo.Spread();
   if(currentSpread > MaxSpread)
   {
      return false;
   }

   // Check trading hours
   if(!IsTradingHours()) return false;

   // Check max trades per day
   if(todayTradeCount >= MaxTradesPerDay) return false;

   // Check max open positions
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

   // No trading on weekends
   if(dow == 0 || dow == 6) return false;

   // London session
   bool inLondon = (hour >= LondonOpenHour && hour < LondonCloseHour);

   // NY session
   bool inNY = (hour >= NYOpenHour && hour < NYCloseHour);

   // Asian session (optional)
   bool inAsian = TradeAsianSession && (hour >= 0 && hour < 8);

   return inLondon || inNY || inAsian;
}

//+------------------------------------------------------------------+
//| Execute main trading logic                                        |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
   // Get trend direction from H1
   int trendDirection = GetTrendDirection();
   if(trendDirection == 0) return; // No clear trend

   // Get price action signals
   int priceActionSignal = GetPriceActionSignal();
   if(priceActionSignal == 0) return; // No signal

   // Check if signal aligns with trend
   bool validBuySetup = (trendDirection == 1 && priceActionSignal == 1);
   bool validSellSetup = (trendDirection == -1 && priceActionSignal == -1);

   // Check S/R confluence
   double supportLevel = 0, resistanceLevel = 0;
   FindSupportResistance(supportLevel, resistanceLevel);

   double currentPrice = symbolInfo.Ask();
   bool nearSupport = (currentPrice - supportLevel) < SRTouchDistance * _Point;
   bool nearResistance = (resistanceLevel - currentPrice) < SRTouchDistance * _Point;

   // Execute trades with confluence
   if(validBuySetup && nearSupport)
   {
      if(!OneTradePerSignal || lastSignalType != 1)
      {
         ExecuteBuyTrade(supportLevel);
         lastSignalType = 1;
      }
   }
   else if(validSellSetup && nearResistance)
   {
      if(!OneTradePerSignal || lastSignalType != 2)
      {
         ExecuteSellTrade(resistanceLevel);
         lastSignalType = 2;
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

   if(CopyBuffer(trendMAHandle, 0, 0, 3, trendMA) < 3) return 0;

   MqlRates h1Rates[];
   ArraySetAsSeries(h1Rates, true);
   if(CopyRates(SYMBOL, TrendTimeframe, 0, 3, h1Rates) < 3) return 0;

   double currentPrice = h1Rates[0].close;

   // Check trend direction
   bool priceAboveMA = currentPrice > trendMA[0];
   bool maRising = trendMA[0] > trendMA[1] && trendMA[1] > trendMA[2];
   bool maFalling = trendMA[0] < trendMA[1] && trendMA[1] < trendMA[2];

   if(priceAboveMA && maRising) return 1;  // Uptrend
   if(!priceAboveMA && maFalling) return -1; // Downtrend

   return 0; // No clear trend
}

//+------------------------------------------------------------------+
//| Get price action signal from M5 timeframe                         |
//+------------------------------------------------------------------+
int GetPriceActionSignal()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int barsNeeded = WaitForConfirmation ? 4 : 3;
   if(CopyRates(SYMBOL, EntryTimeframe, 0, barsNeeded + 1, rates) < barsNeeded + 1) return 0;

   // Check for Pin Bar (on bar 1 or 2 depending on confirmation)
   int checkBar = WaitForConfirmation ? 2 : 1;

   // Bullish Pin Bar
   if(IsBullishPinBar(rates[checkBar]))
   {
      if(!WaitForConfirmation || IsBullishConfirmation(rates[1], rates[checkBar]))
      {
         return 1;
      }
   }

   // Bearish Pin Bar
   if(IsBearishPinBar(rates[checkBar]))
   {
      if(!WaitForConfirmation || IsBearishConfirmation(rates[1], rates[checkBar]))
      {
         return -1;
      }
   }

   // Check for Engulfing Pattern
   int engulfBar1 = WaitForConfirmation ? 3 : 2;
   int engulfBar2 = WaitForConfirmation ? 2 : 1;

   // Bullish Engulfing
   if(IsBullishEngulfing(rates[engulfBar1], rates[engulfBar2]))
   {
      if(!WaitForConfirmation || IsBullishConfirmation(rates[1], rates[engulfBar2]))
      {
         return 1;
      }
   }

   // Bearish Engulfing
   if(IsBearishEngulfing(rates[engulfBar1], rates[engulfBar2]))
   {
      if(!WaitForConfirmation || IsBearishConfirmation(rates[1], rates[engulfBar2]))
      {
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Check for Bullish Pin Bar                                         |
//+------------------------------------------------------------------+
bool IsBullishPinBar(MqlRates &rate)
{
   double totalRange = rate.high - rate.low;
   if(totalRange == 0) return false;

   double body = MathAbs(rate.close - rate.open);
   double lowerWick = MathMin(rate.open, rate.close) - rate.low;
   double upperWick = rate.high - MathMax(rate.open, rate.close);

   // Pin bar rules:
   // 1. Lower wick >= 66% of total range
   // 2. Body <= 33% of total range
   // 3. Upper wick is small (< 30% of lower wick)

   double wickRatio = lowerWick / totalRange;
   double bodyRatio = body / totalRange;

   return (wickRatio >= PinBarWickRatio &&
           bodyRatio <= PinBarBodyMaxRatio &&
           upperWick < lowerWick * 0.3);
}

//+------------------------------------------------------------------+
//| Check for Bearish Pin Bar                                         |
//+------------------------------------------------------------------+
bool IsBearishPinBar(MqlRates &rate)
{
   double totalRange = rate.high - rate.low;
   if(totalRange == 0) return false;

   double body = MathAbs(rate.close - rate.open);
   double lowerWick = MathMin(rate.open, rate.close) - rate.low;
   double upperWick = rate.high - MathMax(rate.open, rate.close);

   // Pin bar rules for bearish:
   // 1. Upper wick >= 66% of total range
   // 2. Body <= 33% of total range
   // 3. Lower wick is small (< 30% of upper wick)

   double wickRatio = upperWick / totalRange;
   double bodyRatio = body / totalRange;

   return (wickRatio >= PinBarWickRatio &&
           bodyRatio <= PinBarBodyMaxRatio &&
           lowerWick < upperWick * 0.3);
}

//+------------------------------------------------------------------+
//| Check for Bullish Engulfing                                       |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(MqlRates &prev, MqlRates &curr)
{
   // Previous candle must be bearish
   if(prev.close >= prev.open) return false;

   // Current candle must be bullish
   if(curr.close <= curr.open) return false;

   double prevBody = MathAbs(prev.close - prev.open);
   double currBody = MathAbs(curr.close - curr.open);

   // Current body must engulf previous body
   bool engulfs = (curr.close > prev.open && curr.open < prev.close);

   // Current body should be significantly larger
   bool sizeOK = (currBody >= prevBody * EngulfingMinRatio);

   return engulfs && sizeOK;
}

//+------------------------------------------------------------------+
//| Check for Bearish Engulfing                                       |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(MqlRates &prev, MqlRates &curr)
{
   // Previous candle must be bullish
   if(prev.close <= prev.open) return false;

   // Current candle must be bearish
   if(curr.close >= curr.open) return false;

   double prevBody = MathAbs(prev.close - prev.open);
   double currBody = MathAbs(curr.close - curr.open);

   // Current body must engulf previous body
   bool engulfs = (curr.open > prev.close && curr.close < prev.open);

   // Current body should be significantly larger
   bool sizeOK = (currBody >= prevBody * EngulfingMinRatio);

   return engulfs && sizeOK;
}

//+------------------------------------------------------------------+
//| Check for Bullish Confirmation                                    |
//+------------------------------------------------------------------+
bool IsBullishConfirmation(MqlRates &confirm, MqlRates &signal)
{
   // Confirmation candle should be bullish and close above signal high
   return (confirm.close > confirm.open && confirm.close > signal.high);
}

//+------------------------------------------------------------------+
//| Check for Bearish Confirmation                                    |
//+------------------------------------------------------------------+
bool IsBearishConfirmation(MqlRates &confirm, MqlRates &signal)
{
   // Confirmation candle should be bearish and close below signal low
   return (confirm.close < confirm.open && confirm.close < signal.low);
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

   // Find swing points
   for(int i = 2; i < SRLookbackPeriod; i++)
   {
      // Swing Low (Support)
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
         rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
      {
         if(rates[i].low < lowestLow)
            lowestLow = rates[i].low;
      }

      // Swing High (Resistance)
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
         rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
      {
         if(rates[i].high > highestHigh)
            highestHigh = rates[i].high;
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

   // Get tick value
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();

   if(tickValue == 0 || tickSize == 0) return symbolInfo.LotsMin();

   // Calculate point value per lot
   double pointValue = tickValue / tickSize * _Point;

   // Calculate lot size
   double lotSize = riskAmount / (slPoints * pointValue);

   // Normalize lot size
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   // Additional safety check - limit max lot based on daily risk
   double maxLotByDailyRisk = (accountEquity * MaxDailyRisk / 100.0) / (slPoints * pointValue);
   lotSize = MathMin(lotSize, maxLotByDailyRisk);

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Execute Buy Trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(double supportLevel)
{
   // Pre-trade risk check
   if(!PreTradeRiskCheck()) return;

   double ask = symbolInfo.Ask();
   double slPrice, tpPrice;

   // Calculate SL based on support or fixed points
   if(supportLevel > 0 && (ask - supportLevel) < StopLossPoints * _Point * 2)
   {
      slPrice = supportLevel - 20 * _Point;
   }
   else
   {
      slPrice = ask - StopLossPoints * _Point;
   }

   double slPoints = (ask - slPrice) / _Point;
   tpPrice = ask + slPoints * _Point * TakeProfitRatio;

   // Calculate lot size
   double lotSize = CalculateLotSize(slPoints);
   if(lotSize < symbolInfo.LotsMin())
   {
      Print("Lot size too small: ", lotSize);
      return;
   }

   // Final risk verification
   if(!VerifyTradeRisk(lotSize, slPoints)) return;

   // Execute trade
   if(trade.Buy(lotSize, SYMBOL, ask, slPrice, tpPrice, "XAUUSD_v2_Buy"))
   {
      Print("BUY executed: Lot=", lotSize, " Entry=", ask, " SL=", slPrice, " TP=", tpPrice);
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
void ExecuteSellTrade(double resistanceLevel)
{
   // Pre-trade risk check
   if(!PreTradeRiskCheck()) return;

   double bid = symbolInfo.Bid();
   double slPrice, tpPrice;

   // Calculate SL based on resistance or fixed points
   if(resistanceLevel > 0 && (resistanceLevel - bid) < StopLossPoints * _Point * 2)
   {
      slPrice = resistanceLevel + 20 * _Point;
   }
   else
   {
      slPrice = bid + StopLossPoints * _Point;
   }

   double slPoints = (slPrice - bid) / _Point;
   tpPrice = bid - slPoints * _Point * TakeProfitRatio;

   // Calculate lot size
   double lotSize = CalculateLotSize(slPoints);
   if(lotSize < symbolInfo.LotsMin())
   {
      Print("Lot size too small: ", lotSize);
      return;
   }

   // Final risk verification
   if(!VerifyTradeRisk(lotSize, slPoints)) return;

   // Execute trade
   if(trade.Sell(lotSize, SYMBOL, bid, slPrice, tpPrice, "XAUUSD_v2_Sell"))
   {
      Print("SELL executed: Lot=", lotSize, " Entry=", bid, " SL=", slPrice, " TP=", tpPrice);
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

   // Check daily loss limit
   double dailyLossPercent = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   if(dailyLossPercent >= (DailyLossLimit - SafetyBuffer - RiskPerTrade))
   {
      Print("Cannot trade - Daily loss limit too close: ", DoubleToString(dailyLossPercent, 2), "%");
      return false;
   }

   // Check total loss limit
   double totalLossPercent = (actualInitialBalance - currentEquity) / actualInitialBalance * 100.0;
   if(totalLossPercent >= (TotalLossLimit - SafetyBuffer - RiskPerTrade))
   {
      Print("Cannot trade - Total loss limit too close: ", DoubleToString(totalLossPercent, 2), "%");
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

   // Check if potential loss would breach daily limit
   if((dailyStartEquity - currentEquity + potentialLoss) / dailyStartEquity * 100.0 >= (DailyLossLimit - SafetyBuffer))
   {
      Print("Trade rejected - Would breach daily loss limit");
      return false;
   }

   // Check if potential loss would breach total limit
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
            // Check if position is at risk of breaching limits
            double unrealizedLoss = -positionInfo.Profit(); // Negative if in loss
            if(unrealizedLoss > 0)
            {
               double currentEquity = accountInfo.Equity();
               double dailyLossWithPosition = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
               double totalLossWithPosition = (actualInitialBalance - currentEquity) / actualInitialBalance * 100.0;

               // Emergency close if approaching limits
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
            if(trade.PositionClose(positionInfo.Ticket()))
            {
               Print("Position closed (", reason, "): ", positionInfo.Ticket());
            }
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
   double totalLossPercent = (actualInitialBalance - currentEquity) / actualInitialBalance * 100.0;

   string status = challengeCompleted ? "COMPLETED" : (tradingAllowed ? "Active" : "PAUSED");
   string trendStr = "";
   int trend = GetTrendDirection();
   if(trend == 1) trendStr = "UP";
   else if(trend == -1) trendStr = "DOWN";
   else trendStr = "RANGING";

   string display = "";
   display += "╔══════════════════════════════════════╗\n";
   display += "║   XAUUSD Fintokei EA v2              ║\n";
   display += "╠══════════════════════════════════════╣\n";
   display += StringFormat("║ Status: %-29s║\n", status);
   display += StringFormat("║ H1 Trend: %-27s║\n", trendStr);
   display += "╠══════════════════════════════════════╣\n";
   display += StringFormat("║ Initial: %'15.0f JPY      ║\n", actualInitialBalance);
   display += StringFormat("║ Equity:  %'15.0f JPY      ║\n", currentEquity);
   display += StringFormat("║ Balance: %'15.0f JPY      ║\n", currentBalance);
   display += "╠══════════════════════════════════════╣\n";
   display += StringFormat("║ Profit Target: %5.1f%% (Now: %+6.2f%%) ║\n", profitTarget, profitPercent);
   display += StringFormat("║ Daily P&L:     %+10.0f (%+5.2f%%)  ║\n", dailyPnL, dailyPnLPercent);
   display += "╠══════════════════════════════════════╣\n";
   display += StringFormat("║ Daily Loss:  %5.2f%% / %5.1f%% limit  ║\n", MathMax(0, -dailyPnLPercent), DailyLossLimit);
   display += StringFormat("║ Total Loss:  %5.2f%% / %5.1f%% limit  ║\n", MathMax(0, totalLossPercent), TotalLossLimit);
   display += "╠══════════════════════════════════════╣\n";
   display += StringFormat("║ Trading Days: %d/%d                    ║\n", tradingDaysCount, MinTradingDays);
   display += StringFormat("║ Today Trades: %d/%d                    ║\n", todayTradeCount, MaxTradesPerDay);
   display += StringFormat("║ Open Positions: %d/%d                  ║\n", CountOpenPositions(), MaxOpenPositions);
   display += "╚══════════════════════════════════════╝\n";

   Comment(display);
}

//+------------------------------------------------------------------+
