//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                          XAUUSD Expert - Fintokei対応資金管理     |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include "CommonDefines.mqh"

//+------------------------------------------------------------------+
//| Fintokei対応リスクマネージャークラス                               |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   // Fintokeiルール設定
   double         m_dailyLossPercent;       // 日次損失限度率(5%)
   double         m_totalLossPercent;       // 全体損失限度率(10%)
   double         m_maxPositionRiskPercent; // 最大ポジションリスク率(3%)
   double         m_defaultRiskPercent;     // デフォルトリスク率(2%)

   // 口座情報
   double         m_initialBalance;         // 初期残高
   double         m_dailyStartEquity;       // 日次開始時有効証拠金
   datetime       m_lastDayResetTime;       // 最後のリセット時間

   // リスク状態
   bool           m_tradingEnabled;         // トレード許可フラグ
   bool           m_emergencyStop;          // 緊急停止フラグ
   double         m_safetyMargin;           // 安全マージン(%)

   // ログ設定
   bool           m_enableLog;

   // 内部メソッド
   void           UpdateDailyReset();
   double         GetTotalUnrealizedPnL();
   bool           CheckDailyLossLimit(double additionalRisk = 0);
   bool           CheckTotalLossLimit(double additionalRisk = 0);

public:
                  CRiskManager();
                 ~CRiskManager();

   // 初期化
   bool           Initialize(double initialBalance = 0,
                             double dailyLoss = 5.0,
                             double totalLoss = 10.0,
                             double maxPosRisk = 3.0,
                             double defaultRisk = 2.0,
                             double safetyMargin = 0.5);

   // リスクチェック
   bool           CanOpenPosition(double lotSize, double slPips);
   bool           IsTradingAllowed();
   void           CheckAndCloseIfNeeded();

   // ロット計算
   double         CalculateOptimalLot(double slPips, double riskPercent = 0);
   double         CalculateMaxAllowableLot(double slPips);

   // リスク情報取得
   double         GetCurrentDailyLossPercent();
   double         GetCurrentTotalLossPercent();
   double         GetRemainingDailyRisk();
   double         GetRemainingTotalRisk();
   double         GetDailyStartEquity() { return m_dailyStartEquity; }
   double         GetInitialBalance() { return m_initialBalance; }

   // 状態取得
   bool           IsEmergencyStop() { return m_emergencyStop; }
   void           ResetEmergencyStop() { m_emergencyStop = false; }

   // 更新
   void           OnTick();
   void           OnNewDay();

   // ログ
   void           EnableLog(bool enable) { m_enableLog = enable; }
   void           PrintRiskStatus();
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
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

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CRiskManager::Initialize(double initialBalance,
                               double dailyLoss,
                               double totalLoss,
                               double maxPosRisk,
                               double defaultRisk,
                               double safetyMargin)
{
   m_dailyLossPercent = dailyLoss;
   m_totalLossPercent = totalLoss;
   m_maxPositionRiskPercent = maxPosRisk;
   m_defaultRiskPercent = defaultRisk;
   m_safetyMargin = safetyMargin;

   // 初期残高の設定
   if(initialBalance > 0)
   {
      m_initialBalance = initialBalance;
   }
   else
   {
      m_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   // 日次開始時有効証拠金の初期設定
   m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_lastDayResetTime = TimeCurrent();

   m_tradingEnabled = true;
   m_emergencyStop = false;

   if(m_enableLog)
   {
      LogDebug(StringFormat("RiskManager initialized: InitBalance=%.2f, DailyStartEquity=%.2f, DailyLoss=%.1f%%, TotalLoss=%.1f%%",
               m_initialBalance, m_dailyStartEquity, m_dailyLossPercent, m_totalLossPercent));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 日次リセットの更新（UTC 0:00）                                    |
//+------------------------------------------------------------------+
void CRiskManager::UpdateDailyReset()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime current, last;
   TimeToStruct(currentTime, current);
   TimeToStruct(m_lastDayResetTime, last);

   // UTC 0:00（MT5サーバー時間で判定）
   // 注意: MT5サーバー時間がUTCと異なる場合は調整が必要
   if(current.day != last.day || current.mon != last.mon || current.year != last.year)
   {
      OnNewDay();
   }
}

//+------------------------------------------------------------------+
//| 新しい日の処理                                                    |
//+------------------------------------------------------------------+
void CRiskManager::OnNewDay()
{
   m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   m_lastDayResetTime = TimeCurrent();

   // 緊急停止が日次損失によるものであれば解除を検討
   // （全体損失による場合は解除しない）
   if(m_emergencyStop && !CheckTotalLossLimit())
   {
      // 全体損失限度は超えていないが緊急停止中 → 日次損失による停止だった可能性
      // → 新日になったのでリセット
      m_emergencyStop = false;
      m_tradingEnabled = true;
   }

   if(m_enableLog)
   {
      LogDebug(StringFormat("New trading day started: DailyStartEquity=%.2f", m_dailyStartEquity));
   }
}

//+------------------------------------------------------------------+
//| 未実現損益の合計を取得                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetTotalUnrealizedPnL()
{
   double totalPnL = 0;
   int totalPositions = PositionsTotal();

   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
            {
               totalPnL += PositionGetDouble(POSITION_PROFIT);
               totalPnL += PositionGetDouble(POSITION_SWAP);
            }
         }
      }
   }

   return totalPnL;
}

//+------------------------------------------------------------------+
//| 日次損失限度のチェック                                            |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDailyLossLimit(double additionalRisk)
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossLimit = m_dailyStartEquity * (m_dailyLossPercent - m_safetyMargin) / 100.0;
   double currentLoss = m_dailyStartEquity - currentEquity;

   // 追加リスクを考慮
   double projectedLoss = currentLoss + additionalRisk;

   return projectedLoss < dailyLossLimit;
}

//+------------------------------------------------------------------+
//| 全体損失限度のチェック                                            |
//+------------------------------------------------------------------+
bool CRiskManager::CheckTotalLossLimit(double additionalRisk)
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalLossLimit = m_initialBalance * (m_totalLossPercent - m_safetyMargin) / 100.0;
   double currentLoss = m_initialBalance - currentEquity;

   // 追加リスクを考慮
   double projectedLoss = currentLoss + additionalRisk;

   return projectedLoss < totalLossLimit;
}

//+------------------------------------------------------------------+
//| ポジションをオープンできるかチェック                              |
//+------------------------------------------------------------------+
bool CRiskManager::CanOpenPosition(double lotSize, double slPips)
{
   // 緊急停止中はトレード不可
   if(m_emergencyStop)
   {
      if(m_enableLog) LogDebug("Cannot open position: Emergency stop is active");
      return false;
   }

   // 日次リセットの確認
   UpdateDailyReset();

   // 追加リスクの計算
   double additionalRisk = CalculateLossPerLot(slPips) * lotSize;

   // 日次損失限度のチェック
   if(!CheckDailyLossLimit(additionalRisk))
   {
      if(m_enableLog) LogDebug("Cannot open position: Daily loss limit would be exceeded");
      return false;
   }

   // 全体損失限度のチェック
   if(!CheckTotalLossLimit(additionalRisk))
   {
      if(m_enableLog) LogDebug("Cannot open position: Total loss limit would be exceeded");
      return false;
   }

   // 現在のオープンポジションリスクのチェック
   double currentPositionRisk = 0;
   int totalPositions = PositionsTotal();

   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
         {
            double posLots = PositionGetDouble(POSITION_VOLUME);
            double posSL = PositionGetDouble(POSITION_SL);
            double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);

            if(posSL > 0)
            {
               double slDistance = MathAbs(posOpen - posSL);
               double slPipsPos = PriceToPips(slDistance);
               currentPositionRisk += CalculateLossPerLot(slPipsPos) * posLots;
            }
         }
      }
   }

   // 合計リスクのチェック（最大ポジションリスク）
   double maxPositionRiskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * m_maxPositionRiskPercent / 100.0;
   if(currentPositionRisk + additionalRisk > maxPositionRiskAmount)
   {
      if(m_enableLog) LogDebug(StringFormat("Cannot open position: Max position risk would be exceeded (Current: %.2f, Additional: %.2f, Max: %.2f)",
                                            currentPositionRisk, additionalRisk, maxPositionRiskAmount));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| トレードが許可されているかチェック                                |
//+------------------------------------------------------------------+
bool CRiskManager::IsTradingAllowed()
{
   UpdateDailyReset();

   if(m_emergencyStop)
      return false;

   // リアルタイムで損失限度をチェック
   if(!CheckDailyLossLimit(0))
   {
      m_tradingEnabled = false;
      return false;
   }

   if(!CheckTotalLossLimit(0))
   {
      m_tradingEnabled = false;
      m_emergencyStop = true;  // 全体損失は緊急停止
      return false;
   }

   m_tradingEnabled = true;
   return true;
}

//+------------------------------------------------------------------+
//| 必要に応じてポジションをクローズ                                  |
//+------------------------------------------------------------------+
void CRiskManager::CheckAndCloseIfNeeded()
{
   UpdateDailyReset();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 日次損失限度（安全マージン込み）
   double dailyLossLimitStrict = m_dailyStartEquity * (m_dailyLossPercent - m_safetyMargin) / 100.0;
   double currentDailyLoss = m_dailyStartEquity - currentEquity;

   // 全体損失限度（安全マージン込み）
   double totalLossLimitStrict = m_initialBalance * (m_totalLossPercent - m_safetyMargin) / 100.0;
   double currentTotalLoss = m_initialBalance - currentEquity;

   bool needClose = false;
   string reason = "";

   if(currentDailyLoss >= dailyLossLimitStrict)
   {
      needClose = true;
      reason = StringFormat("Daily loss limit reached: %.2f%% (Limit: %.2f%%)",
                           GetCurrentDailyLossPercent(), m_dailyLossPercent - m_safetyMargin);
   }

   if(currentTotalLoss >= totalLossLimitStrict)
   {
      needClose = true;
      m_emergencyStop = true;
      reason = StringFormat("Total loss limit reached: %.2f%% (Limit: %.2f%%)",
                           GetCurrentTotalLossPercent(), m_totalLossPercent - m_safetyMargin);
   }

   if(needClose)
   {
      if(m_enableLog) LogDebug("EMERGENCY CLOSE: " + reason);

      // 全ポジションをクローズ
      CTrade trade;
      trade.SetExpertMagicNumber(EA_MAGIC_NUMBER);

      int totalPositions = PositionsTotal();
      for(int i = totalPositions - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
            {
               if(!trade.PositionClose(ticket))
               {
                  if(m_enableLog) LogDebug(StringFormat("Failed to close position %d: %d", ticket, GetLastError()));
               }
            }
         }
      }

      m_tradingEnabled = false;
   }
}

//+------------------------------------------------------------------+
//| 最適なロットサイズを計算                                          |
//+------------------------------------------------------------------+
double CRiskManager::CalculateOptimalLot(double slPips, double riskPercent)
{
   if(slPips <= 0)
      return 0;

   if(riskPercent <= 0)
      riskPercent = m_defaultRiskPercent;

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLossAmount = accountBalance * (riskPercent / 100.0);
   double lossPerLot = CalculateLossPerLot(slPips);

   if(lossPerLot <= 0)
      return 0;

   double calculatedLots = maxLossAmount / lossPerLot;

   return NormalizeLotSize(calculatedLots);
}

//+------------------------------------------------------------------+
//| 許容される最大ロットサイズを計算                                  |
//+------------------------------------------------------------------+
double CRiskManager::CalculateMaxAllowableLot(double slPips)
{
   if(slPips <= 0)
      return 0;

   // 残りの日次リスク
   double remainingDailyRisk = GetRemainingDailyRisk();

   // 残りの全体リスク
   double remainingTotalRisk = GetRemainingTotalRisk();

   // 最大ポジションリスク残り
   double currentPositionRisk = 0;
   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
         {
            double posLots = PositionGetDouble(POSITION_VOLUME);
            double posSL = PositionGetDouble(POSITION_SL);
            double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            if(posSL > 0)
            {
               double slDistance = MathAbs(posOpen - posSL);
               double slPipsPos = PriceToPips(slDistance);
               currentPositionRisk += CalculateLossPerLot(slPipsPos) * posLots;
            }
         }
      }
   }

   double maxPositionRiskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * m_maxPositionRiskPercent / 100.0;
   double remainingPositionRisk = maxPositionRiskAmount - currentPositionRisk;

   // 最も制限の厳しいリスクを選択
   double maxRiskAmount = MathMin(remainingDailyRisk, MathMin(remainingTotalRisk, remainingPositionRisk));

   if(maxRiskAmount <= 0)
      return 0;

   double lossPerLot = CalculateLossPerLot(slPips);
   if(lossPerLot <= 0)
      return 0;

   double maxLots = maxRiskAmount / lossPerLot;

   return NormalizeLotSize(maxLots);
}

//+------------------------------------------------------------------+
//| 現在の日次損失率を取得                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentDailyLossPercent()
{
   UpdateDailyReset();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = m_dailyStartEquity - currentEquity;

   if(m_dailyStartEquity <= 0)
      return 0;

   return (dailyLoss / m_dailyStartEquity) * 100.0;
}

//+------------------------------------------------------------------+
//| 現在の全体損失率を取得                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentTotalLossPercent()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalLoss = m_initialBalance - currentEquity;

   if(m_initialBalance <= 0)
      return 0;

   return (totalLoss / m_initialBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| 残りの日次リスク（金額）を取得                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetRemainingDailyRisk()
{
   UpdateDailyReset();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossLimit = m_dailyStartEquity * (m_dailyLossPercent - m_safetyMargin) / 100.0;
   double currentDailyLoss = m_dailyStartEquity - currentEquity;

   return MathMax(0, dailyLossLimit - currentDailyLoss);
}

//+------------------------------------------------------------------+
//| 残りの全体リスク（金額）を取得                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetRemainingTotalRisk()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalLossLimit = m_initialBalance * (m_totalLossPercent - m_safetyMargin) / 100.0;
   double currentTotalLoss = m_initialBalance - currentEquity;

   return MathMax(0, totalLossLimit - currentTotalLoss);
}

//+------------------------------------------------------------------+
//| OnTick処理                                                        |
//+------------------------------------------------------------------+
void CRiskManager::OnTick()
{
   UpdateDailyReset();
   CheckAndCloseIfNeeded();
}

//+------------------------------------------------------------------+
//| リスク状態を出力                                                  |
//+------------------------------------------------------------------+
void CRiskManager::PrintRiskStatus()
{
   if(!m_enableLog) return;

   LogDebug("===== Risk Status =====");
   LogDebug(StringFormat("Initial Balance: %.2f", m_initialBalance));
   LogDebug(StringFormat("Daily Start Equity: %.2f", m_dailyStartEquity));
   LogDebug(StringFormat("Current Equity: %.2f", AccountInfoDouble(ACCOUNT_EQUITY)));
   LogDebug(StringFormat("Daily Loss: %.2f%% / %.2f%%", GetCurrentDailyLossPercent(), m_dailyLossPercent));
   LogDebug(StringFormat("Total Loss: %.2f%% / %.2f%%", GetCurrentTotalLossPercent(), m_totalLossPercent));
   LogDebug(StringFormat("Remaining Daily Risk: %.2f", GetRemainingDailyRisk()));
   LogDebug(StringFormat("Remaining Total Risk: %.2f", GetRemainingTotalRisk()));
   LogDebug(StringFormat("Trading Allowed: %s", m_tradingEnabled ? "Yes" : "No"));
   LogDebug(StringFormat("Emergency Stop: %s", m_emergencyStop ? "Yes" : "No"));
   LogDebug("=======================");
}

#endif // RISK_MANAGER_MQH
