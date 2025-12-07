//+------------------------------------------------------------------+
//| GranvilleEA_ProfitOptimizer_v2.3_FIXED.mq5 |
//| v2.0 + Max SL control only (Minimal improvement) |
//| Copyright 2025, Granville EA System |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Granville EA System Profit Optimizer"
#property link ""
#property version "2.30"

#include <Trade\Trade.mqh>

// Input Parameters - 基本設定
input string Symbol_to_Trade = "XAUUSD"; // 取引通貨ペア
input double Risk_Percent = 2.0; // 1ポジションあたりのリスク (%)
input double Max_Lot_Size = 10.0; // 最大ロットサイズ

// Input Parameters - 移動平均
input int MA_Period_Mid = 75; // 中期MA期間 (EMA)
input int MA_Period_Long = 200; // 長期MA期間 (EMA)
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H4; // MTFトレンド確認時間足
input int MA_Proximity_Pips = 100; // MA接近許容値 (Points)

// Input Parameters - テクニカル指標
input int EMA_Short_Period = 20; // 短期EMA期間
input int ADX_Period = 14; // ADX期間
input double ADX_Min_Level = 20.0; // ADX最小レベル
input int ATR_Period = 14; // ATR期間
input double ATR_Min_Multiplier = 0.5; // ATR最小倍率
input double ATR_Max_Multiplier = 2.0; // ATR最大倍率

// Input Parameters - 利確・損切り
input double Max_SL_Pips = 200.0; // 最大損切り幅 (Pips) ★v2.3新規追加
input double TakeProfit_Ratio = 2.0; // リスクリワード比率
input bool BreakEven_Enable = true; // ブレークイーブン有効化
input double BreakEven_Trigger_Percent = 50.0; // トリガー (SL幅の%)
input int BreakEven_Offset_Pips = 10; // オフセット (Pips)
input bool PartialTP_Enable = true; // 部分利確有効化
input double PartialTP_Close_Percent = 50.0; // 決済割合 (%)
input double PartialTP_Trigger_Percent = 50.0; // トリガー (TP距離の%)

// Input Parameters - ピラミッディング（増し玉）
input bool Pyramiding_Enable = true; // 増し玉機能有効化
input int Max_Positions = 3; // 最大ポジション数
input double Pyramiding_Min_Profit_Percent = 50.0; // 増し玉に必要な最小利益 (リスクの%)
input double Pyramiding_Min_Distance_Pips = 50.0; // 最小追加距離 (Pips)

// Input Parameters - リスク管理
input bool DailyLossLimit_Enable = true; // 日次損失制限有効化
input double DailyLossLimit_Percent = 4.0; // 日次損失制限 (%)

// Input Parameters - 時間フィルター
input bool TimeFilter_Enable = true; // 時間フィルター有効化
input int Trade_Start_Hour = 12; // 取引開始時刻
input int Trade_Start_Minute = 0; // 取引開始分
input int Trade_End_Hour = 5; // 取引終了時刻
input int Trade_End_Minute = 0; // 取引終了分

// Input Parameters - その他
input int Magic_Number = 123456; // マジックナンバー
input string EA_Comment = "Granville EA PO v2.3"; // EAコメント
input int Slippage_Points = 30; // スリッページ許容値

// グローバル変数
CTrade trade;
int ma75Handle, ma200Handle, mtfMA75Handle, emaShortHandle, adxHandle, atrHandle;
datetime lastBarTime = 0;
bool partialTPExecuted[];

// 日次損失制限変数
double dailyStartBalance = 0;
datetime lastResetDate = 0;
bool dailyTradingAllowed = true;

//+------------------------------------------------------------------+
//| Expert initialization function |
//+------------------------------------------------------------------+
int OnInit()
{
    // Trade object settings
    trade.SetExpertMagicNumber(Magic_Number);
    trade.SetDeviationInPoints(Slippage_Points);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    // Select trading symbol
    if(!SymbolSelect(Symbol_to_Trade, true))
    {
        Print("シンボル選択失敗: ", Symbol_to_Trade);
        return(INIT_FAILED);
    }

    // Create MA handles
    ma75Handle = iMA(Symbol_to_Trade, PERIOD_M30, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
    ma200Handle = iMA(Symbol_to_Trade, PERIOD_M30, MA_Period_Long, 0, MODE_EMA, PRICE_CLOSE);
    mtfMA75Handle = iMA(Symbol_to_Trade, MTF_Timeframe, MA_Period_Mid, 0, MODE_EMA, PRICE_CLOSE);
    emaShortHandle = iMA(Symbol_to_Trade, PERIOD_M30, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE);
    adxHandle = iADX(Symbol_to_Trade, PERIOD_M30, ADX_Period);
    atrHandle = iATR(Symbol_to_Trade, PERIOD_M30, ATR_Period);

    if(ma75Handle == INVALID_HANDLE || ma200Handle == INVALID_HANDLE ||
       mtfMA75Handle == INVALID_HANDLE || emaShortHandle == INVALID_HANDLE ||
       adxHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
    {
        Print("インジケーターハンドル作成失敗");
        return(INIT_FAILED);
    }

    // Initialize partial TP array
    ArrayResize(partialTPExecuted, Max_Positions);
    ArrayInitialize(partialTPExecuted, false);

    // Initialize daily loss limit
    dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);
    lastResetDate = StringToTime(StringFormat("%04d.%02d.%02d",
                                               currentTime.year, currentTime.mon, currentTime.day));
    dailyTradingAllowed = true;

    Print("========================================");
    Print("Granville EA Profit Optimizer v2.3 初期化成功");
    Print("取引シンボル: ", Symbol_to_Trade);
    Print("リスク設定: ", Risk_Percent, "% (1ポジションあたり)");
    Print("最大ポジション数: ", Max_Positions);
    Print("最大損切り幅: ", Max_SL_Pips, " pips ★NEW");
    Print("増し玉機能: ", Pyramiding_Enable ? "有効" : "無効");
    Print("日次損失制限: ", DailyLossLimit_Percent, "% (開始残高: $", dailyStartBalance, ")");
    Print("========================================");

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release handles
    if(ma75Handle != INVALID_HANDLE) IndicatorRelease(ma75Handle);
    if(ma200Handle != INVALID_HANDLE) IndicatorRelease(ma200Handle);
    if(mtfMA75Handle != INVALID_HANDLE) IndicatorRelease(mtfMA75Handle);
    if(emaShortHandle != INVALID_HANDLE) IndicatorRelease(emaShortHandle);
    if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
    if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);

    Print("Granville EA Profit Optimizer v2.3 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    datetime currentBarTime = iTime(Symbol_to_Trade, PERIOD_M30, 0);
    if(currentBarTime == lastBarTime)
        return;

    lastBarTime = currentBarTime;

    // Check daily loss limit
    if(DailyLossLimit_Enable)
    {
        CheckDailyLossLimit();
    }

    // Get current positions count
    int currentPositions = CountPositions();

    // Manage existing positions
    if(currentPositions > 0)
    {
        ManagePositions();
    }

    // Block new entries if daily loss limit reached
    if(DailyLossLimit_Enable && !dailyTradingAllowed)
    {
        return;
    }

    // Check time filter
    if(TimeFilter_Enable && !IsWithinTradingHours())
    {
        return;
    }

    // Check volatility filter
    if(!CheckVolatilityFilter())
    {
        return;
    }

    // Trend analysis
    int trendDirection = AnalyzeTrend();

    if(trendDirection == 0)
    {
        // No clear trend
        return;
    }

    // Check if we can open new positions
    if(currentPositions >= Max_Positions)
    {
        return; // Maximum positions reached
    }

    // Check entry signals
    if(trendDirection == 1) // Uptrend
    {
        if(CheckBuySignal())
        {
            // If we have existing positions, check pyramiding conditions
            if(currentPositions > 0)
            {
                if(Pyramiding_Enable && CanAddPosition(POSITION_TYPE_BUY))
                {
                    ExecuteBuyOrder(currentPositions);
                }
            }
            else
            {
                // First position
                ExecuteBuyOrder(0);
            }
        }
    }
    else if(trendDirection == -1) // Downtrend
    {
        if(CheckSellSignal())
        {
            // If we have existing positions, check pyramiding conditions
            if(currentPositions > 0)
            {
                if(Pyramiding_Enable && CanAddPosition(POSITION_TYPE_SELL))
                {
                    ExecuteSellOrder(currentPositions);
                }
            }
            else
            {
                // First position
                ExecuteSellOrder(0);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Count positions for this symbol and magic number |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol_to_Trade &&
               PositionGetInteger(POSITION_MAGIC) == Magic_Number)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check if we can add a pyramiding position |
//+------------------------------------------------------------------+
bool CanAddPosition(ENUM_POSITION_TYPE posType)
{
    double totalProfit = 0;
    double totalRisk = 0;
    double minEntryPrice = 0;
    double maxEntryPrice = 0;
    bool firstPosition = true;

    // Calculate total profit and risk from existing positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol_to_Trade &&
               PositionGetInteger(POSITION_MAGIC) == Magic_Number)
            {
                long type = PositionGetInteger(POSITION_TYPE);
                if(type != posType)
                {
                    return false; // Opposite direction position exists
                }

                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentProfit = PositionGetDouble(POSITION_PROFIT);
                double sl = PositionGetDouble(POSITION_SL);

                // Track entry prices
                if(firstPosition)
                {
                    minEntryPrice = openPrice;
                    maxEntryPrice = openPrice;
                    firstPosition = false;
                }
                else
                {
                    if(openPrice < minEntryPrice) minEntryPrice = openPrice;
                    if(openPrice > maxEntryPrice) maxEntryPrice = openPrice;
                }

                totalProfit += currentProfit;

                // Calculate risk for this position
                double slDistance = MathAbs(openPrice - sl);
                double volume = PositionGetDouble(POSITION_VOLUME);
                double positionRisk = CalculateLossPerLot(slDistance / GetPipSize()) * volume;
                totalRisk += positionRisk;
            }
        }
    }

    // Check if total profit is sufficient (compared to total risk)
    if(totalRisk > 0)
    {
        double profitToRiskPercent = (totalProfit / totalRisk) * 100.0;
        if(profitToRiskPercent < Pyramiding_Min_Profit_Percent)
        {
            return false; // Not enough profit
        }
    }

    // Check minimum distance from last entry
    double currentPrice = (posType == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK) :
                          SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);

    double lastEntryPrice = (posType == POSITION_TYPE_BUY) ? maxEntryPrice : minEntryPrice;
    double distancePips = MathAbs(currentPrice - lastEntryPrice) / GetPipSize();

    if(distancePips < Pyramiding_Min_Distance_Pips)
    {
        return false; // Too close to last entry
    }

    return true;
}

//+------------------------------------------------------------------+
//| Manage existing positions |
//+------------------------------------------------------------------+
void ManagePositions()
{
    int posIndex = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol_to_Trade &&
               PositionGetInteger(POSITION_MAGIC) == Magic_Number)
            {
                // Partial take-profit
                if(PartialTP_Enable && posIndex < ArraySize(partialTPExecuted) &&
                   !partialTPExecuted[posIndex])
                {
                    if(CheckAndSetPartialTP(ticket, posIndex))
                    {
                        partialTPExecuted[posIndex] = true;
                    }
                }

                // Break-even
                if(BreakEven_Enable)
                {
                    CheckAndSetBreakEven(ticket);
                }

                posIndex++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trend Analysis |
//+------------------------------------------------------------------+
int AnalyzeTrend()
{
    double mtfMA[], h1MA75[], h1MA200[];
    ArraySetAsSeries(mtfMA, true);
    ArraySetAsSeries(h1MA75, true);
    ArraySetAsSeries(h1MA200, true);

    // Copy MTF MA75
    if(CopyBuffer(mtfMA75Handle, 0, 0, 25, mtfMA) < 25)
        return 0;

    // Copy H1 MAs
    if(CopyBuffer(ma75Handle, 0, 0, 3, h1MA75) < 3)
        return 0;
    if(CopyBuffer(ma200Handle, 0, 0, 3, h1MA200) < 3)
        return 0;

    // Determine MTF trend
    double mtfCurrent = mtfMA[0];
    double mtfPast = mtfMA[20];
    double mtfDiff = mtfCurrent - mtfPast;
    double threshold = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT) * 10;

    bool mtfUptrend = mtfDiff > threshold;
    bool mtfDowntrend = mtfDiff < -threshold;

    // Determine H1 trend
    bool h1MA75Up = (h1MA75[0] > h1MA75[1]) && (h1MA75[1] > h1MA75[2]);
    bool h1MA75Down = (h1MA75[0] < h1MA75[1]) && (h1MA75[1] < h1MA75[2]);

    // Decide trend direction
    if(mtfUptrend && h1MA75Up)
        return 1; // Uptrend
    else if(mtfDowntrend && h1MA75Down)
        return -1; // Downtrend
    else
        return 0; // Unclear
}

//+------------------------------------------------------------------+
//| Buy Signal Check (Granville Rule 3) |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
    double close[], ma75[], ma200[], adxValue[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(ma75, true);
    ArraySetAsSeries(ma200, true);
    ArraySetAsSeries(adxValue, true);

    // Get price and MA data
    if(CopyClose(Symbol_to_Trade, PERIOD_M30, 0, 5, close) < 5)
        return false;
    if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5)
        return false;
    if(CopyBuffer(ma200Handle, 0, 0, 3, ma200) < 3)
        return false;

    // Get ADX data
    if(CopyBuffer(adxHandle, 0, 0, 2, adxValue) < 2)
        return false;

    double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

    // Common filters
    bool above200EMA = close[0] > ma200[0];
    bool strongTrend = adxValue[0] >= ADX_Min_Level;
    bool maTrendUp = (ma75[0] > ma75[1]) && (ma75[1] > ma75[2]);

    // Rule 1: MA breakout
    bool rule1 = maTrendUp && (close[1] <= ma75[1]) && (close[0] > ma75[0]);

    // Rule 2: MA reversal recovery
    bool rule2 = maTrendUp && (close[2] > ma75[2]) && (close[1] < ma75[1]) && (close[0] > ma75[0]);

    // Rule 3: Pullback buy
    bool wasNearMA = (close[1] > ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);
    bool bounced = (close[0] > ma75[0]) && (close[0] > close[1]);
    bool rule3 = (wasNearMA || bounced);

    return ((rule1 || rule2 || rule3) && above200EMA && strongTrend);
}

//+------------------------------------------------------------------+
//| Sell Signal Check (Granville Rule 7) |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
    double close[], ma75[], ma200[], adxValue[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(ma75, true);
    ArraySetAsSeries(ma200, true);
    ArraySetAsSeries(adxValue, true);

    // Get price and MA data
    if(CopyClose(Symbol_to_Trade, PERIOD_M30, 0, 5, close) < 5)
        return false;
    if(CopyBuffer(ma75Handle, 0, 0, 5, ma75) < 5)
        return false;
    if(CopyBuffer(ma200Handle, 0, 0, 3, ma200) < 3)
        return false;

    // Get ADX data
    if(CopyBuffer(adxHandle, 0, 0, 2, adxValue) < 2)
        return false;

    double proximityPoints = MA_Proximity_Pips * SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

    // Common filters
    bool below200EMA = close[0] < ma200[0];
    bool strongTrend = adxValue[0] >= ADX_Min_Level;
    bool maTrendDown = (ma75[0] < ma75[1]) && (ma75[1] < ma75[2]);

    // Rule 5: MA breakout
    bool rule5 = maTrendDown && (close[1] >= ma75[1]) && (close[0] < ma75[0]);

    // Rule 6: MA reversal recovery
    bool rule6 = maTrendDown && (close[2] < ma75[2]) && (close[1] > ma75[1]) && (close[0] < ma75[0]);

    // Rule 7: Pullback sell
    bool wasNearMA = (close[1] < ma75[1]) && (MathAbs(close[1] - ma75[1]) <= proximityPoints);
    bool bounced = (close[0] < ma75[0]) && (close[0] < close[1]);
    bool rule7 = (wasNearMA || bounced);

    return ((rule5 || rule6 || rule7) && below200EMA && strongTrend);
}

//+------------------------------------------------------------------+
//| Execute Buy Order |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(int positionIndex)
{
    double ask = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
    double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

    // Find swing low
    double swingLow = FindSwingLow();

    // Calculate stop loss
    double sl = 0;
    if(swingLow > 0 && swingLow < ask)
    {
        sl = swingLow - (10 * point);
    }
    else
    {
        sl = ask * 0.98;
    }

    if(sl >= ask)
    {
        sl = ask - (ask * 0.01);
    }

    // ★v2.3新規追加: 損切り幅の制限
    double slDistance = ask - sl;
    double slPips = slDistance / GetPipSize();

    if(slPips > Max_SL_Pips)
    {
        sl = ask - (Max_SL_Pips * GetPipSize());
        Print("⚠️ 損切りを制限: ", DoubleToString(slPips, 1), " → ", Max_SL_Pips, " pips");
        slDistance = ask - sl;
        slPips = Max_SL_Pips;
    }

    // Calculate take profit
    double tp = ask + (slDistance * TakeProfit_Ratio);

    // Normalize
    int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);

    // Calculate lot size using LotCalculator method
    double lotSize = CalculateLotSizeEnhanced(ask, sl);

    if(lotSize <= 0)
    {
        Print("エラー: ロット計算失敗");
        return;
    }

    // Execute order
    string comment = EA_Comment + (positionIndex > 0 ? " #" + IntegerToString(positionIndex + 1) : "");
    if(trade.Buy(lotSize, Symbol_to_Trade, ask, sl, tp, comment))
    {
        Print("========================================");
        Print("買い注文成功", (positionIndex > 0 ? " [増し玉 #" + IntegerToString(positionIndex + 1) + "]" : ""));
        Print("ロット: ", lotSize);
        Print("価格: ", ask);
        Print("損切り: ", sl, " (", DoubleToString((ask - sl) / GetPipSize(), 1), " pips)");
        Print("利確: ", tp, " (", DoubleToString((tp - ask) / GetPipSize(), 1), " pips)");
        Print("リスク: ", Risk_Percent, "%");
        Print("========================================");
    }
    else
    {
        Print("買い注文失敗: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Execute Sell Order |
//+------------------------------------------------------------------+
void ExecuteSellOrder(int positionIndex)
{
    double bid = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
    double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

    // Find swing high
    double swingHigh = FindSwingHigh();

    // Calculate stop loss
    double sl = 0;
    if(swingHigh > 0 && swingHigh > bid)
    {
        sl = swingHigh + (10 * point);
    }
    else
    {
        sl = bid * 1.02;
    }

    if(sl <= bid)
    {
        sl = bid + (bid * 0.01);
    }

    // ★v2.3新規追加: 損切り幅の制限
    double slDistance = sl - bid;
    double slPips = slDistance / GetPipSize();

    if(slPips > Max_SL_Pips)
    {
        sl = bid + (Max_SL_Pips * GetPipSize());
        Print("⚠️ 損切りを制限: ", DoubleToString(slPips, 1), " → ", Max_SL_Pips, " pips");
        slDistance = sl - bid;
        slPips = Max_SL_Pips;
    }

    // Calculate take profit
    double tp = bid - (slDistance * TakeProfit_Ratio);

    // Normalize
    int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);

    // Calculate lot size using LotCalculator method
    double lotSize = CalculateLotSizeEnhanced(bid, sl);

    if(lotSize <= 0)
    {
        Print("エラー: ロット計算失敗");
        return;
    }

    // Execute order
    string comment = EA_Comment + (positionIndex > 0 ? " #" + IntegerToString(positionIndex + 1) : "");
    if(trade.Sell(lotSize, Symbol_to_Trade, bid, sl, tp, comment))
    {
        Print("========================================");
        Print("売り注文成功", (positionIndex > 0 ? " [増し玉 #" + IntegerToString(positionIndex + 1) + "]" : ""));
        Print("ロット: ", lotSize);
        Print("価格: ", bid);
        Print("損切り: ", sl, " (", DoubleToString((sl - bid) / GetPipSize(), 1), " pips)");
        Print("利確: ", tp, " (", DoubleToString((bid - tp) / GetPipSize(), 1), " pips)");
        Print("リスク: ", Risk_Percent, "%");
        Print("========================================");
    }
    else
    {
        Print("売り注文失敗: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Find Swing Low |
//+------------------------------------------------------------------+
double FindSwingLow()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 20, rates) < 20)
        return 0;

    double swingLow = rates[0].low;
    for(int i = 1; i < 20; i++)
    {
        if(rates[i].low < swingLow)
            swingLow = rates[i].low;
    }

    return swingLow;
}

//+------------------------------------------------------------------+
//| Find Swing High |
//+------------------------------------------------------------------+
double FindSwingHigh()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    if(CopyRates(Symbol_to_Trade, PERIOD_H1, 0, 20, rates) < 20)
        return 0;

    double swingHigh = rates[0].high;
    for(int i = 1; i < 20; i++)
    {
        if(rates[i].high > swingHigh)
            swingHigh = rates[i].high;
    }

    return swingHigh;
}

//+------------------------------------------------------------------+
//| Get pip size (from LotCalculator.mq5) |
//+------------------------------------------------------------------+
double GetPipSize()
{
    int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);

    double pipSize;
    if(digits == 3 || digits == 5)
    {
        pipSize = point * 10.0;
    }
    else
    {
        pipSize = point;
    }

    return pipSize;
}

//+------------------------------------------------------------------+
//| Calculate loss per 1 lot (from LotCalculator.mq5) |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips)
{
    // Get symbol properties
    double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
    double pipSize = GetPipSize();

    // Convert SL pips to price distance
    double slDistance = slPips * pipSize;

    // Calculate number of ticks in SL distance
    double numTicks = slDistance / tickSize;

    // Calculate loss per 1 lot in account currency
    double lossPerLot = numTicks * tickValue;

    return lossPerLot;
}

//+------------------------------------------------------------------+
//| Calculate profit per 1 lot (from LotCalculator.mq5) |
//+------------------------------------------------------------------+
double CalculateProfitPerLot(double tpPips)
{
    // Get symbol properties
    double tickSize = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_TRADE_TICK_VALUE);
    double pipSize = GetPipSize();

    // Convert TP pips to price distance
    double tpDistance = tpPips * pipSize;

    // Calculate number of ticks in TP distance
    double numTicks = tpDistance / tickSize;

    // Calculate profit per 1 lot in account currency
    double profitPerLot = numTicks * tickValue;

    return profitPerLot;
}

//+------------------------------------------------------------------+
//| Enhanced lot size calculation (from LotCalculator.mq5) |
//+------------------------------------------------------------------+
double CalculateLotSizeEnhanced(double entryPrice, double stopLoss)
{
    // Get account balance
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    // Calculate risk amount
    double riskAmount = accountBalance * Risk_Percent / 100.0;

    // Calculate SL distance in pips
    double slDistance = MathAbs(entryPrice - stopLoss);
    double slPips = slDistance / GetPipSize();

    if(slPips <= 0)
    {
        Print("エラー: 無効なSL距離");
        return 0.01;
    }

    // Calculate loss per lot
    double lossPerLot = CalculateLossPerLot(slPips);

    if(lossPerLot <= 0)
    {
        Print("エラー: 無効なロット計算");
        return 0.01;
    }

    // Calculate lot size
    double lotSize = riskAmount / lossPerLot;

    // Normalize lot size
    lotSize = NormalizeLotSize(lotSize);

    // Apply maximum limit
    if(lotSize > Max_Lot_Size)
        lotSize = Max_Lot_Size;

    Print("ロット計算詳細: 残高=", accountBalance, ", リスク=", riskAmount,
          ", SL=", DoubleToString(slPips, 1), " pips, ロット=", lotSize);

    return lotSize;
}

//+------------------------------------------------------------------+
//| Normalize lot size (from LotCalculator.mq5) |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
    // Get broker constraints
    double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);

    // Ensure lot is within min/max range
    if(lots < minLot)
        lots = minLot;
    if(lots > maxLot)
        lots = maxLot;

    // Normalize to lot step
    lots = MathFloor(lots / lotStep) * lotStep;

    // Ensure it's still above minimum after rounding
    if(lots < minLot)
        lots = minLot;

    return lots;
}

//+------------------------------------------------------------------+
//| Break-Even Management |
//+------------------------------------------------------------------+
void CheckAndSetBreakEven(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return;

    double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double positionSL = PositionGetDouble(POSITION_SL);
    double positionTP = PositionGetDouble(POSITION_TP);
    long positionType = PositionGetInteger(POSITION_TYPE);

    double point = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol_to_Trade, SYMBOL_DIGITS);

    double slDistance = MathAbs(positionOpenPrice - positionSL);
    if(slDistance == 0) return;

    double triggerDistance = slDistance * BreakEven_Trigger_Percent / 100.0;
    double offsetPoints = BreakEven_Offset_Pips * point * 10;

    if(positionType == POSITION_TYPE_BUY)
    {
        double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
        double currentProfit = currentPrice - positionOpenPrice;
        double newSL = positionOpenPrice + offsetPoints;

        if(currentProfit >= triggerDistance && positionSL < positionOpenPrice)
        {
            newSL = NormalizeDouble(newSL, digits);
            if(trade.PositionModify(ticket, newSL, positionTP))
            {
                Print("✅ ブレークイーブン発動 [買い]: チケット=", ticket,
                      ", 新SL=", newSL);
            }
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
        double currentProfit = positionOpenPrice - currentPrice;
        double newSL = positionOpenPrice - offsetPoints;

        if(currentProfit >= triggerDistance && positionSL > positionOpenPrice)
        {
            newSL = NormalizeDouble(newSL, digits);
            if(trade.PositionModify(ticket, newSL, positionTP))
            {
                Print("✅ ブレークイーブン発動 [売り]: チケット=", ticket,
                      ", 新SL=", newSL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Partial Take-Profit Management |
//+------------------------------------------------------------------+
bool CheckAndSetPartialTP(ulong ticket, int posIndex)
{
    if(!PositionSelectByTicket(ticket))
        return false;

    double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double positionTP = PositionGetDouble(POSITION_TP);
    double positionVolume = PositionGetDouble(POSITION_VOLUME);
    long positionType = PositionGetInteger(POSITION_TYPE);

    if(positionTP == 0) return false;

    double tpDistance = MathAbs(positionTP - positionOpenPrice);
    if(tpDistance == 0) return false;

    double triggerDistance = tpDistance * PartialTP_Trigger_Percent / 100.0;

    // Calculate close volume
    double minLot = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_VOLUME_STEP);
    double closeVolume = positionVolume * PartialTP_Close_Percent / 100.0;

    closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
    closeVolume = NormalizeDouble(closeVolume, 2);

    double remainVolume = positionVolume - closeVolume;
    if(closeVolume < minLot || remainVolume < minLot)
    {
        return true; // Mark as executed (impossible to split)
    }

    if(positionType == POSITION_TYPE_BUY)
    {
        double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_BID);
        double currentProfit = currentPrice - positionOpenPrice;

        if(currentProfit >= triggerDistance)
        {
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
                Print("✅ 部分利確実行 [買い]: チケット=", ticket,
                      ", 決済ロット=", closeVolume);
                return true;
            }
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        double currentPrice = SymbolInfoDouble(Symbol_to_Trade, SYMBOL_ASK);
        double currentProfit = positionOpenPrice - currentPrice;

        if(currentProfit >= triggerDistance)
        {
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
                Print("✅ 部分利確実行 [売り]: チケット=", ticket,
                      ", 決済ロット=", closeVolume);
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Time Filter |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);

    int currentHour = currentTime.hour;
    int currentMinute = currentTime.min;

    int currentTotalMinutes = currentHour * 60 + currentMinute;
    int startTotalMinutes = Trade_Start_Hour * 60 + Trade_Start_Minute;
    int endTotalMinutes = Trade_End_Hour * 60 + Trade_End_Minute;

    if(endTotalMinutes < startTotalMinutes)
    {
        return (currentTotalMinutes >= startTotalMinutes || currentTotalMinutes < endTotalMinutes);
    }
    else
    {
        return (currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes);
    }
}

//+------------------------------------------------------------------+
//| Daily Loss Limit |
//+------------------------------------------------------------------+
void CheckDailyLossLimit()
{
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);

    datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d",
                                                      currentTime.year, currentTime.mon, currentTime.day));

    if(currentDate != lastResetDate)
    {
        dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        lastResetDate = currentDate;
        dailyTradingAllowed = true;

        // Reset partial TP flags
        ArrayInitialize(partialTPExecuted, false);

        Print("📅 新しい取引日: ", TimeToString(currentDate, TIME_DATE),
              " - 開始残高: $", DoubleToString(dailyStartBalance, 2));
    }

    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyPnL = currentBalance - dailyStartBalance;
    double dailyPnLPercent = (dailyPnL / dailyStartBalance) * 100.0;

    if(dailyPnLPercent <= -DailyLossLimit_Percent && dailyTradingAllowed)
    {
        dailyTradingAllowed = false;
        Print("🚫 日次損失制限到達: ", DoubleToString(dailyPnLPercent, 2),
              "% - 本日の新規取引停止");
    }
}

//+------------------------------------------------------------------+
//| ATR Volatility Filter |
//+------------------------------------------------------------------+
bool CheckVolatilityFilter()
{
    double atr[];
    ArraySetAsSeries(atr, true);

    if(CopyBuffer(atrHandle, 0, 0, 20, atr) < 20)
    {
        Print("⚠️ ATRデータ取得失敗");
        return false;
    }

    double currentATR = atr[0];
    double avgATR = 0;
    for(int i = 0; i < 20; i++)
        avgATR += atr[i];
    avgATR /= 20.0;

    double atrMultiplier = currentATR / avgATR;

    if(atrMultiplier < ATR_Min_Multiplier)
    {
        return false;
    }

    if(atrMultiplier > ATR_Max_Multiplier)
    {
        return false;
    }

    return true;
}
//+------------------------------------------------------------------+
