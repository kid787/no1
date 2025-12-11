//+------------------------------------------------------------------+
//|                                                TradeManager.mqh  |
//|                    Trade Execution and Management Module          |
//|                     Copyright 2024, Your Company                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//--- Trade Direction
enum ENUM_TRADE_DIRECTION
{
   TRADE_BUY = 1,
   TRADE_SELL = -1,
   TRADE_NONE = 0
};

//--- Exit Reason
enum ENUM_EXIT_REASON
{
   EXIT_SL_HIT = 0,
   EXIT_TP_HIT = 1,
   EXIT_TRAILING = 2,
   EXIT_SIGNAL = 3,
   EXIT_TIME = 4,
   EXIT_EMERGENCY = 5,
   EXIT_MANUAL = 6
};

//--- Trade Manager Class
class CTradeManager
{
private:
   string            m_symbol;
   int               m_magicNumber;
   double            m_slippage;

   CTrade            m_trade;
   CPositionInfo     m_position;
   CSymbolInfo       m_symbolInfo;

   // Position tracking
   ulong             m_currentTicket;
   ENUM_TRADE_DIRECTION m_currentDirection;
   double            m_entryPrice;
   double            m_stopLoss;
   double            m_takeProfit;
   double            m_trailingStop;
   double            m_breakEvenLevel;
   bool              m_isBreakEvenSet;

   // ATR handle for dynamic SL/TP
   int               m_atrHandle;
   double            m_currentATR;

   // Statistics
   int               m_totalTrades;
   int               m_winningTrades;
   int               m_losingTrades;
   double            m_totalProfit;
   double            m_totalLoss;

   // Trade limits
   int               m_maxTradesPerDay;
   int               m_todayTrades;
   datetime          m_lastTradeDate;

   // Internal methods
   bool              UpdateATR();
   double            NormalizePrice(double price);
   bool              ValidateStopLoss(double sl, ENUM_TRADE_DIRECTION dir);

public:
                     CTradeManager();
                    ~CTradeManager();

   bool              Init(string symbol, int magicNumber, double slippage = 30, int maxTradesDay = 5);
   void              Deinit();

   // Main trading methods
   bool              OpenBuy(double lotSize, double slPrice, double tpPrice, string comment = "");
   bool              OpenSell(double lotSize, double slPrice, double tpPrice, string comment = "");
   bool              ClosePosition(ENUM_EXIT_REASON reason = EXIT_MANUAL);
   bool              CloseAllPositions();

   // Dynamic SL/TP based on ATR
   bool              OpenBuyATR(double lotSize, double atrMultiplierSL = 2.0, double atrMultiplierTP = 3.0, string comment = "");
   bool              OpenSellATR(double lotSize, double atrMultiplierSL = 2.0, double atrMultiplierTP = 3.0, string comment = "");

   // Position management
   bool              ModifyStopLoss(double newSL);
   bool              ModifyTakeProfit(double newTP);
   bool              SetBreakEven(double activationProfit);
   bool              ApplyTrailingStop(double trailDistance, double trailStep);
   void              UpdateTrailing();
   void              UpdateBreakEven();

   // ATR-based trailing
   bool              ApplyATRTrailing(double atrMultiplier = 1.5);

   // Position info
   bool              HasPosition();
   ulong             GetCurrentTicket() { return m_currentTicket; }
   ENUM_TRADE_DIRECTION GetCurrentDirection() { return m_currentDirection; }
   double            GetEntryPrice() { return m_entryPrice; }
   double            GetStopLoss() { return m_stopLoss; }
   double            GetTakeProfit() { return m_takeProfit; }
   double            GetCurrentATR() { return m_currentATR; }
   double            GetUnrealizedProfit();

   // Statistics
   int               GetTotalTrades() { return m_totalTrades; }
   int               GetWinningTrades() { return m_winningTrades; }
   int               GetLosingTrades() { return m_losingTrades; }
   double            GetWinRate() { return m_totalTrades > 0 ? (double)m_winningTrades / m_totalTrades * 100 : 0; }
   double            GetTotalProfit() { return m_totalProfit; }
   double            GetTotalLoss() { return m_totalLoss; }

   // Trade limits
   bool              CanTradeToday();
   void              ResetDailyCounter();
   int               GetTodayTrades() { return m_todayTrades; }

   // SL/TP calculation helpers
   double            CalculateSLBuy(double atrMultiplier = 2.0);
   double            CalculateSLSell(double atrMultiplier = 2.0);
   double            CalculateTPBuy(double atrMultiplier = 3.0);
   double            CalculateTPSell(double atrMultiplier = 3.0);

   // XAUUSD specific pip calculations
   double            PriceToPips(double priceDistance);
   double            PipsToPrice(double pips);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CTradeManager::CTradeManager()
{
   m_symbol = "";
   m_magicNumber = 0;
   m_slippage = 30;
   m_currentTicket = 0;
   m_currentDirection = TRADE_NONE;
   m_entryPrice = 0;
   m_stopLoss = 0;
   m_takeProfit = 0;
   m_trailingStop = 0;
   m_breakEvenLevel = 0;
   m_isBreakEvenSet = false;
   m_atrHandle = INVALID_HANDLE;
   m_currentATR = 0;
   m_totalTrades = 0;
   m_winningTrades = 0;
   m_losingTrades = 0;
   m_totalProfit = 0;
   m_totalLoss = 0;
   m_maxTradesPerDay = 5;
   m_todayTrades = 0;
   m_lastTradeDate = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CTradeManager::~CTradeManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CTradeManager::Init(string symbol, int magicNumber, double slippage = 30, int maxTradesDay = 5)
{
   m_symbol = symbol;
   m_magicNumber = magicNumber;
   m_slippage = slippage;
   m_maxTradesPerDay = maxTradesDay;

   if(!m_symbolInfo.Name(symbol))
   {
      Print("Error: Invalid symbol ", symbol);
      return false;
   }

   m_trade.SetExpertMagicNumber(magicNumber);
   m_trade.SetDeviationInPoints((ulong)slippage);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   m_trade.SetAsyncMode(false);

   // Initialize ATR
   m_atrHandle = iATR(m_symbol, PERIOD_H1, 14);
   if(m_atrHandle == INVALID_HANDLE)
   {
      Print("Error creating ATR handle");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CTradeManager::Deinit()
{
   if(m_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Update ATR Value                                                  |
//+------------------------------------------------------------------+
bool CTradeManager::UpdateATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) != 1)
      return false;

   m_currentATR = atr[0];
   return true;
}

//+------------------------------------------------------------------+
//| Normalize Price                                                   |
//+------------------------------------------------------------------+
double CTradeManager::NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| Validate Stop Loss                                                |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateStopLoss(double sl, ENUM_TRADE_DIRECTION dir)
{
   double currentPrice = dir == TRADE_BUY ?
                         SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                         SymbolInfoDouble(m_symbol, SYMBOL_BID);

   long stopLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double minDistance = stopLevel * point;

   if(dir == TRADE_BUY && sl > 0)
   {
      if(currentPrice - sl < minDistance) return false;
   }
   else if(dir == TRADE_SELL && sl > 0)
   {
      if(sl - currentPrice < minDistance) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Open Buy Position                                                 |
//+------------------------------------------------------------------+
bool CTradeManager::OpenBuy(double lotSize, double slPrice, double tpPrice, string comment = "")
{
   if(!CanTradeToday())
   {
      Print("Max trades per day reached");
      return false;
   }

   if(HasPosition())
   {
      Print("Already have a position");
      return false;
   }

   m_symbolInfo.RefreshRates();
   double ask = m_symbolInfo.Ask();

   slPrice = NormalizePrice(slPrice);
   tpPrice = NormalizePrice(tpPrice);

   if(!ValidateStopLoss(slPrice, TRADE_BUY))
   {
      Print("Invalid stop loss for BUY");
      return false;
   }

   if(m_trade.Buy(lotSize, m_symbol, ask, slPrice, tpPrice, comment))
   {
      m_currentTicket = m_trade.ResultOrder();
      m_currentDirection = TRADE_BUY;
      m_entryPrice = ask;
      m_stopLoss = slPrice;
      m_takeProfit = tpPrice;
      m_isBreakEvenSet = false;
      m_todayTrades++;
      m_totalTrades++;

      Print("BUY opened: Ticket=", m_currentTicket, " Entry=", m_entryPrice,
            " SL=", m_stopLoss, " TP=", m_takeProfit);
      return true;
   }
   else
   {
      Print("BUY failed: ", m_trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Open Sell Position                                                |
//+------------------------------------------------------------------+
bool CTradeManager::OpenSell(double lotSize, double slPrice, double tpPrice, string comment = "")
{
   if(!CanTradeToday())
   {
      Print("Max trades per day reached");
      return false;
   }

   if(HasPosition())
   {
      Print("Already have a position");
      return false;
   }

   m_symbolInfo.RefreshRates();
   double bid = m_symbolInfo.Bid();

   slPrice = NormalizePrice(slPrice);
   tpPrice = NormalizePrice(tpPrice);

   if(!ValidateStopLoss(slPrice, TRADE_SELL))
   {
      Print("Invalid stop loss for SELL");
      return false;
   }

   if(m_trade.Sell(lotSize, m_symbol, bid, slPrice, tpPrice, comment))
   {
      m_currentTicket = m_trade.ResultOrder();
      m_currentDirection = TRADE_SELL;
      m_entryPrice = bid;
      m_stopLoss = slPrice;
      m_takeProfit = tpPrice;
      m_isBreakEvenSet = false;
      m_todayTrades++;
      m_totalTrades++;

      Print("SELL opened: Ticket=", m_currentTicket, " Entry=", m_entryPrice,
            " SL=", m_stopLoss, " TP=", m_takeProfit);
      return true;
   }
   else
   {
      Print("SELL failed: ", m_trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Open Buy with ATR-based SL/TP                                     |
//+------------------------------------------------------------------+
bool CTradeManager::OpenBuyATR(double lotSize, double atrMultiplierSL = 2.0, double atrMultiplierTP = 3.0, string comment = "")
{
   UpdateATR();

   m_symbolInfo.RefreshRates();
   double ask = m_symbolInfo.Ask();

   double sl = ask - (m_currentATR * atrMultiplierSL);
   double tp = ask + (m_currentATR * atrMultiplierTP);

   return OpenBuy(lotSize, sl, tp, comment);
}

//+------------------------------------------------------------------+
//| Open Sell with ATR-based SL/TP                                    |
//+------------------------------------------------------------------+
bool CTradeManager::OpenSellATR(double lotSize, double atrMultiplierSL = 2.0, double atrMultiplierTP = 3.0, string comment = "")
{
   UpdateATR();

   m_symbolInfo.RefreshRates();
   double bid = m_symbolInfo.Bid();

   double sl = bid + (m_currentATR * atrMultiplierSL);
   double tp = bid - (m_currentATR * atrMultiplierTP);

   return OpenSell(lotSize, sl, tp, comment);
}

//+------------------------------------------------------------------+
//| Close Position                                                    |
//+------------------------------------------------------------------+
bool CTradeManager::ClosePosition(ENUM_EXIT_REASON reason = EXIT_MANUAL)
{
   if(!HasPosition()) return false;

   double profit = GetUnrealizedProfit();

   if(m_trade.PositionClose(m_currentTicket))
   {
      // Update statistics
      if(profit >= 0)
      {
         m_winningTrades++;
         m_totalProfit += profit;
      }
      else
      {
         m_losingTrades++;
         m_totalLoss += MathAbs(profit);
      }

      string reasonStr[] = {"SL_HIT", "TP_HIT", "TRAILING", "SIGNAL", "TIME", "EMERGENCY", "MANUAL"};
      Print("Position closed: Reason=", reasonStr[reason], " Profit=", profit);

      m_currentTicket = 0;
      m_currentDirection = TRADE_NONE;
      m_entryPrice = 0;
      m_stopLoss = 0;
      m_takeProfit = 0;
      m_isBreakEvenSet = false;

      return true;
   }

   Print("Close failed: ", m_trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| Close All Positions                                               |
//+------------------------------------------------------------------+
bool CTradeManager::CloseAllPositions()
{
   bool success = true;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
            PositionGetString(POSITION_SYMBOL) == m_symbol)
         {
            if(!m_trade.PositionClose(ticket))
            {
               success = false;
            }
         }
      }
   }

   if(success)
   {
      m_currentTicket = 0;
      m_currentDirection = TRADE_NONE;
   }

   return success;
}

//+------------------------------------------------------------------+
//| Modify Stop Loss                                                  |
//+------------------------------------------------------------------+
bool CTradeManager::ModifyStopLoss(double newSL)
{
   if(!HasPosition()) return false;

   if(!PositionSelectByTicket(m_currentTicket))
      return false;

   newSL = NormalizePrice(newSL);
   double tp = PositionGetDouble(POSITION_TP);

   if(m_trade.PositionModify(m_currentTicket, newSL, tp))
   {
      m_stopLoss = newSL;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Modify Take Profit                                                |
//+------------------------------------------------------------------+
bool CTradeManager::ModifyTakeProfit(double newTP)
{
   if(!HasPosition()) return false;

   if(!PositionSelectByTicket(m_currentTicket))
      return false;

   newTP = NormalizePrice(newTP);
   double sl = PositionGetDouble(POSITION_SL);

   if(m_trade.PositionModify(m_currentTicket, sl, newTP))
   {
      m_takeProfit = newTP;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Set Break Even                                                    |
//+------------------------------------------------------------------+
bool CTradeManager::SetBreakEven(double activationProfit)
{
   if(!HasPosition()) return false;
   if(m_isBreakEvenSet) return true;

   m_breakEvenLevel = activationProfit;
   return true;
}

//+------------------------------------------------------------------+
//| Update Break Even                                                 |
//+------------------------------------------------------------------+
void CTradeManager::UpdateBreakEven()
{
   if(!HasPosition()) return;
   if(m_isBreakEvenSet) return;
   if(m_breakEvenLevel <= 0) return;

   m_symbolInfo.RefreshRates();

   if(m_currentDirection == TRADE_BUY)
   {
      double currentPrice = m_symbolInfo.Bid();
      double profit = currentPrice - m_entryPrice;

      if(profit >= m_breakEvenLevel && m_stopLoss < m_entryPrice)
      {
         double newSL = m_entryPrice + (m_symbolInfo.Spread() * m_symbolInfo.Point());
         if(ModifyStopLoss(newSL))
         {
            m_isBreakEvenSet = true;
            Print("Break even set for BUY at ", newSL);
         }
      }
   }
   else if(m_currentDirection == TRADE_SELL)
   {
      double currentPrice = m_symbolInfo.Ask();
      double profit = m_entryPrice - currentPrice;

      if(profit >= m_breakEvenLevel && m_stopLoss > m_entryPrice)
      {
         double newSL = m_entryPrice - (m_symbolInfo.Spread() * m_symbolInfo.Point());
         if(ModifyStopLoss(newSL))
         {
            m_isBreakEvenSet = true;
            Print("Break even set for SELL at ", newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Trailing Stop                                               |
//+------------------------------------------------------------------+
bool CTradeManager::ApplyTrailingStop(double trailDistance, double trailStep)
{
   m_trailingStop = trailDistance;
   return true;
}

//+------------------------------------------------------------------+
//| Update Trailing Stop                                              |
//+------------------------------------------------------------------+
void CTradeManager::UpdateTrailing()
{
   if(!HasPosition()) return;
   if(m_trailingStop <= 0) return;

   m_symbolInfo.RefreshRates();

   if(m_currentDirection == TRADE_BUY)
   {
      double currentPrice = m_symbolInfo.Bid();
      double newSL = currentPrice - m_trailingStop;

      if(newSL > m_stopLoss + (m_trailingStop * 0.1)) // Trail step
      {
         ModifyStopLoss(newSL);
      }
   }
   else if(m_currentDirection == TRADE_SELL)
   {
      double currentPrice = m_symbolInfo.Ask();
      double newSL = currentPrice + m_trailingStop;

      if(newSL < m_stopLoss - (m_trailingStop * 0.1)) // Trail step
      {
         ModifyStopLoss(newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Apply ATR-based Trailing                                          |
//+------------------------------------------------------------------+
bool CTradeManager::ApplyATRTrailing(double atrMultiplier = 1.5)
{
   UpdateATR();
   return ApplyTrailingStop(m_currentATR * atrMultiplier, m_currentATR * 0.1);
}

//+------------------------------------------------------------------+
//| Check if Has Position                                             |
//+------------------------------------------------------------------+
bool CTradeManager::HasPosition()
{
   // Check by ticket
   if(m_currentTicket > 0 && PositionSelectByTicket(m_currentTicket))
   {
      return true;
   }

   // Check by magic number and symbol
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
            PositionGetString(POSITION_SYMBOL) == m_symbol)
         {
            m_currentTicket = ticket;
            m_currentDirection = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? TRADE_BUY : TRADE_SELL;
            m_entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            m_stopLoss = PositionGetDouble(POSITION_SL);
            m_takeProfit = PositionGetDouble(POSITION_TP);
            return true;
         }
      }
   }

   m_currentTicket = 0;
   m_currentDirection = TRADE_NONE;
   return false;
}

//+------------------------------------------------------------------+
//| Get Unrealized Profit                                             |
//+------------------------------------------------------------------+
double CTradeManager::GetUnrealizedProfit()
{
   if(!HasPosition()) return 0;

   if(PositionSelectByTicket(m_currentTicket))
   {
      return PositionGetDouble(POSITION_PROFIT);
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Can Trade Today                                                   |
//+------------------------------------------------------------------+
bool CTradeManager::CanTradeToday()
{
   datetime now = TimeCurrent();
   MqlDateTime dt1, dt2;
   TimeToStruct(now, dt1);
   TimeToStruct(m_lastTradeDate, dt2);

   // Reset counter on new day
   if(dt1.day != dt2.day || dt1.mon != dt2.mon || dt1.year != dt2.year)
   {
      m_todayTrades = 0;
      m_lastTradeDate = now;
   }

   return m_todayTrades < m_maxTradesPerDay;
}

//+------------------------------------------------------------------+
//| Reset Daily Counter                                               |
//+------------------------------------------------------------------+
void CTradeManager::ResetDailyCounter()
{
   m_todayTrades = 0;
   m_lastTradeDate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss for Buy                                       |
//+------------------------------------------------------------------+
double CTradeManager::CalculateSLBuy(double atrMultiplier = 2.0)
{
   UpdateATR();
   m_symbolInfo.RefreshRates();
   return m_symbolInfo.Ask() - (m_currentATR * atrMultiplier);
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss for Sell                                      |
//+------------------------------------------------------------------+
double CTradeManager::CalculateSLSell(double atrMultiplier = 2.0)
{
   UpdateATR();
   m_symbolInfo.RefreshRates();
   return m_symbolInfo.Bid() + (m_currentATR * atrMultiplier);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit for Buy                                     |
//+------------------------------------------------------------------+
double CTradeManager::CalculateTPBuy(double atrMultiplier = 3.0)
{
   UpdateATR();
   m_symbolInfo.RefreshRates();
   return m_symbolInfo.Ask() + (m_currentATR * atrMultiplier);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit for Sell                                    |
//+------------------------------------------------------------------+
double CTradeManager::CalculateTPSell(double atrMultiplier = 3.0)
{
   UpdateATR();
   m_symbolInfo.RefreshRates();
   return m_symbolInfo.Bid() - (m_currentATR * atrMultiplier);
}

//+------------------------------------------------------------------+
//| Convert Price Distance to Pips (XAUUSD specific)                  |
//| For XAUUSD: 1 pip = 0.1 (10 points if point = 0.01)               |
//+------------------------------------------------------------------+
double CTradeManager::PriceToPips(double priceDistance)
{
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   // XAUUSD pip = 10 points typically
   return priceDistance / (point * 10);
}

//+------------------------------------------------------------------+
//| Convert Pips to Price Distance                                    |
//+------------------------------------------------------------------+
double CTradeManager::PipsToPrice(double pips)
{
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   return pips * point * 10;
}
