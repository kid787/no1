//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                    Fintokei Challenge Plan Risk Management        |
//|                     Copyright 2024, Your Company                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- Risk State Enumeration
enum ENUM_RISK_STATE
{
   RISK_NORMAL = 0,         // Normal trading allowed
   RISK_WARNING = 1,        // Approaching limits
   RISK_CRITICAL = 2,       // Very close to limits
   RISK_EMERGENCY = 3       // Limits breached - stop trading
};

//--- Risk Manager Class for Fintokei Challenge Plan
class CRiskManager
{
private:
   // Parameters
   double            m_initialBalance;       // 初期残高
   int               m_utcDayResetHour;      // UTC日次リセット時間
   double            m_dailyLossLimitPct;    // 1日の最大損失率 (5%)
   double            m_overallLossLimitPct;  // 全体の最大損失率 (10%)
   double            m_safetyBufferPct;      // 安全バッファ率
   double            m_riskPerTradePct;      // 1トレードあたりリスク率

   // Daily tracking
   double            m_dailyStartingEquity;  // 日次開始時の有効証拠金
   datetime          m_lastResetTime;        // 最後のリセット時間
   int               m_lastResetDay;         // 最後のリセット日

   // Risk levels
   double            m_overallLossLine;      // 全体損失ライン
   double            m_dailyLossLine;        // 日次損失ライン
   double            m_safetyOverallLine;    // 安全バッファ付き全体ライン
   double            m_safetyDailyLine;      // 安全バッファ付き日次ライン

   // Trading day counter
   int               m_tradingDays;          // 取引日数カウント
   datetime          m_lastTradeDate;        // 最後の取引日

   // State
   ENUM_RISK_STATE   m_riskState;
   bool              m_emergencyStop;
   string            m_lastError;

   CTrade            m_trade;

   // Internal methods
   void              UpdateDailyReset();
   void              CalculateRiskLevels();
   bool              CloseAllPositions();

public:
                     CRiskManager();
                    ~CRiskManager();

   bool              Init(double initialBalance,
                         int utcResetHour = 0,
                         double dailyLossLimit = 5.0,
                         double overallLossLimit = 10.0,
                         double safetyBuffer = 0.1,
                         double riskPerTrade = 1.0);

   void              Deinit();

   // Main risk check method - call on every tick
   bool              CheckRisk();

   // Position sizing based on risk
   double            CalculateLotSize(string symbol, double stopLossPips);
   double            CalculateLotSizeByATR(string symbol, double atrValue, double atrMultiplier = 2.0);

   // Getters
   ENUM_RISK_STATE   GetRiskState() { return m_riskState; }
   bool              IsEmergencyStop() { return m_emergencyStop; }
   bool              CanTrade();
   double            GetCurrentEquity() { return AccountInfoDouble(ACCOUNT_EQUITY); }
   double            GetDailyStartingEquity() { return m_dailyStartingEquity; }
   double            GetOverallLossLine() { return m_overallLossLine; }
   double            GetDailyLossLine() { return m_dailyLossLine; }
   double            GetSafetyOverallLine() { return m_safetyOverallLine; }
   double            GetSafetyDailyLine() { return m_safetyDailyLine; }
   int               GetTradingDays() { return m_tradingDays; }
   string            GetLastError() { return m_lastError; }

   // Daily/Overall drawdown percentages
   double            GetCurrentDailyDrawdownPct();
   double            GetCurrentOverallDrawdownPct();

   // For display
   double            GetRemainingDailyRisk();
   double            GetRemainingOverallRisk();

   // Trading day management
   void              RecordTrade();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
{
   m_initialBalance = 0;
   m_utcDayResetHour = 0;
   m_dailyLossLimitPct = 5.0;
   m_overallLossLimitPct = 10.0;
   m_safetyBufferPct = 0.1;
   m_riskPerTradePct = 1.0;

   m_dailyStartingEquity = 0;
   m_lastResetTime = 0;
   m_lastResetDay = -1;

   m_overallLossLine = 0;
   m_dailyLossLine = 0;
   m_safetyOverallLine = 0;
   m_safetyDailyLine = 0;

   m_tradingDays = 0;
   m_lastTradeDate = 0;

   m_riskState = RISK_NORMAL;
   m_emergencyStop = false;
   m_lastError = "";
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Risk Manager                                           |
//+------------------------------------------------------------------+
bool CRiskManager::Init(double initialBalance,
                        int utcResetHour = 0,
                        double dailyLossLimit = 5.0,
                        double overallLossLimit = 10.0,
                        double safetyBuffer = 0.1,
                        double riskPerTrade = 1.0)
{
   m_initialBalance = initialBalance;
   m_utcDayResetHour = utcResetHour;
   m_dailyLossLimitPct = dailyLossLimit;
   m_overallLossLimitPct = overallLossLimit;
   m_safetyBufferPct = safetyBuffer;
   m_riskPerTradePct = riskPerTrade;

   // Initialize daily starting equity
   m_dailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_lastResetTime = TimeGMT();

   // Calculate initial risk levels
   CalculateRiskLevels();

   // Reset trading day counter
   m_tradingDays = 0;
   m_lastTradeDate = 0;

   m_emergencyStop = false;
   m_riskState = RISK_NORMAL;

   Print("RiskManager initialized: Initial Balance=", m_initialBalance,
         ", Daily Limit=", m_dailyLossLimitPct, "%",
         ", Overall Limit=", m_overallLossLimitPct, "%");

   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CRiskManager::Deinit()
{
   // Nothing to clean up
}

//+------------------------------------------------------------------+
//| Calculate Risk Levels                                             |
//+------------------------------------------------------------------+
void CRiskManager::CalculateRiskLevels()
{
   // 全体の失格判定ライン = 初期資金 × (1 - 全体損失率%)
   m_overallLossLine = m_initialBalance * (1.0 - m_overallLossLimitPct / 100.0);

   // 日次の失格判定ライン = 日次開始時の有効証拠金 × (1 - 日次損失率%)
   m_dailyLossLine = m_dailyStartingEquity * (1.0 - m_dailyLossLimitPct / 100.0);

   // 安全バッファ付きライン（強制決済トリガー）
   double bufferAmount = m_initialBalance * (m_safetyBufferPct / 100.0);
   m_safetyOverallLine = m_overallLossLine + bufferAmount;
   m_safetyDailyLine = m_dailyLossLine + bufferAmount;
}

//+------------------------------------------------------------------+
//| Update Daily Reset at UTC 0:00                                    |
//+------------------------------------------------------------------+
void CRiskManager::UpdateDailyReset()
{
   datetime gmtTime = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);

   // Check if we've crossed the reset hour
   if(dt.hour == m_utcDayResetHour && dt.day != m_lastResetDay)
   {
      // Reset daily starting equity
      m_dailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lastResetTime = gmtTime;
      m_lastResetDay = dt.day;

      // Recalculate risk levels
      CalculateRiskLevels();

      Print("Daily reset at UTC ", m_utcDayResetHour, ":00 - New daily starting equity: ", m_dailyStartingEquity);
   }
}

//+------------------------------------------------------------------+
//| Check Risk - Main method, call on every tick                      |
//+------------------------------------------------------------------+
bool CRiskManager::CheckRisk()
{
   // Update daily reset
   UpdateDailyReset();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Calculate current drawdown percentages
   double overallDD = GetCurrentOverallDrawdownPct();
   double dailyDD = GetCurrentDailyDrawdownPct();

   // Recovery check: If was in emergency but equity recovered, allow trading again
   if(m_emergencyStop)
   {
      // Check if equity has recovered above BOTH safety lines
      if(currentEquity > m_safetyOverallLine && currentEquity > m_safetyDailyLine)
      {
         m_emergencyStop = false;
         m_riskState = RISK_WARNING;  // Start with warning state after recovery
         m_lastError = "";
         Print("RECOVERY: Equity recovered above safety lines. Trading resumed. Equity=", currentEquity);
      }
      else
      {
         return false; // Still in emergency stop
      }
   }

   // Check against safety lines (with buffer)
   // 全体損失チェック
   if(currentEquity <= m_safetyOverallLine)
   {
      m_lastError = StringFormat("EMERGENCY: Overall loss limit reached! Equity=%.2f, Line=%.2f (%.2f%%)",
                                  currentEquity, m_safetyOverallLine, overallDD);
      Print(m_lastError);
      m_riskState = RISK_EMERGENCY;
      m_emergencyStop = true;
      CloseAllPositions();
      return false;
   }

   // 日次損失チェック
   if(currentEquity <= m_safetyDailyLine)
   {
      m_lastError = StringFormat("EMERGENCY: Daily loss limit reached! Equity=%.2f, Line=%.2f (%.2f%%)",
                                  currentEquity, m_safetyDailyLine, dailyDD);
      Print(m_lastError);
      m_riskState = RISK_EMERGENCY;
      m_emergencyStop = true;
      CloseAllPositions();
      return false;
   }

   // Warning levels
   double warningThreshold = 80.0;  // 80% of limit
   double criticalThreshold = 95.0; // 95% of limit

   double overallUsage = (overallDD / m_overallLossLimitPct) * 100.0;
   double dailyUsage = (dailyDD / m_dailyLossLimitPct) * 100.0;
   double maxUsage = MathMax(overallUsage, dailyUsage);

   if(maxUsage >= criticalThreshold)
   {
      m_riskState = RISK_CRITICAL;
   }
   else if(maxUsage >= warningThreshold)
   {
      m_riskState = RISK_WARNING;
   }
   else
   {
      m_riskState = RISK_NORMAL;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Close All Positions - Emergency action                            |
//+------------------------------------------------------------------+
bool CRiskManager::CloseAllPositions()
{
   Print("EMERGENCY: Closing all positions!");

   bool success = true;
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(!m_trade.PositionClose(ticket))
         {
            Print("Failed to close position ", ticket, ": ", GetLastError());
            success = false;
         }
         else
         {
            Print("Closed position ", ticket);
         }
      }
   }

   // Also close any pending orders
   int orderTotal = OrdersTotal();
   for(int i = orderTotal - 1; i >= 0; i--)
   {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket > 0)
      {
         if(!m_trade.OrderDelete(orderTicket))
         {
            Print("Failed to delete order ", orderTicket, ": ", GetLastError());
            success = false;
         }
      }
   }

   return success;
}

//+------------------------------------------------------------------+
//| Can Trade - Check if trading is allowed                          |
//+------------------------------------------------------------------+
bool CRiskManager::CanTrade()
{
   if(m_emergencyStop)
      return false;

   if(m_riskState == RISK_EMERGENCY)
      return false;

   // Allow trading in warning/critical states but with reduced risk
   return true;
}

//+------------------------------------------------------------------+
//| Get Current Daily Drawdown Percentage                            |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentDailyDrawdownPct()
{
   if(m_dailyStartingEquity <= 0) return 0;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = m_dailyStartingEquity - currentEquity;

   if(drawdown <= 0) return 0;

   return (drawdown / m_dailyStartingEquity) * 100.0;
}

//+------------------------------------------------------------------+
//| Get Current Overall Drawdown Percentage                          |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentOverallDrawdownPct()
{
   if(m_initialBalance <= 0) return 0;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = m_initialBalance - currentEquity;

   if(drawdown <= 0) return 0;

   return (drawdown / m_initialBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| Get Remaining Daily Risk (in currency)                           |
//+------------------------------------------------------------------+
double CRiskManager::GetRemainingDailyRisk()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   return currentEquity - m_safetyDailyLine;
}

//+------------------------------------------------------------------+
//| Get Remaining Overall Risk (in currency)                         |
//+------------------------------------------------------------------+
double CRiskManager::GetRemainingOverallRisk()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   return currentEquity - m_safetyOverallLine;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Stop Loss in Pips                    |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSize(string symbol, double stopLossPips)
{
   if(stopLossPips <= 0) return 0.01;

   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (m_riskPerTradePct / 100.0);

   // Adjust risk in warning/critical states
   if(m_riskState == RISK_WARNING)
      riskAmount *= 0.5;
   else if(m_riskState == RISK_CRITICAL)
      riskAmount *= 0.25;

   // Get symbol info
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(tickValue <= 0 || point <= 0) return minLot;

   // For XAUUSD, 1 pip = 0.1 (10 points if point = 0.01)
   double pipValue = (tickValue / tickSize) * point * 10; // Value per pip per lot

   // Calculate lot size
   double lotSize = riskAmount / (stopLossPips * pipValue);

   // Round to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   // Apply min/max limits
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on ATR                                   |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSizeByATR(string symbol, double atrValue, double atrMultiplier = 2.0)
{
   if(atrValue <= 0) return 0.01;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0) return 0.01;

   // Convert ATR to pips (for XAUUSD, 1 pip = 0.1)
   double stopLossPips = (atrValue * atrMultiplier) / (point * 10);

   return CalculateLotSize(symbol, stopLossPips);
}

//+------------------------------------------------------------------+
//| Record Trade - For trading day counter                            |
//+------------------------------------------------------------------+
void CRiskManager::RecordTrade()
{
   datetime now = TimeCurrent();
   MqlDateTime dt1, dt2;
   TimeToStruct(now, dt1);
   TimeToStruct(m_lastTradeDate, dt2);

   // Check if this is a new trading day
   if(dt1.day != dt2.day || dt1.mon != dt2.mon || dt1.year != dt2.year)
   {
      m_tradingDays++;
      m_lastTradeDate = now;
      Print("Trading day recorded. Total trading days: ", m_tradingDays);
   }
}
