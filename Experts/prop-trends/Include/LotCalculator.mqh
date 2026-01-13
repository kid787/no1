//+------------------------------------------------------------------+
//|                                                LotCalculator.mqh |
//|                   Lot Size Calculator with Risk Management       |
//+------------------------------------------------------------------+
#ifndef LOT_CALCULATOR_MQH
#define LOT_CALCULATOR_MQH

#include "RiskManager.mqh"

//+------------------------------------------------------------------+
//| Lot Size Calculator Class                                        |
//| - リスクベースのロットサイズ計算                                   |
//| - Fintokeiルール準拠                                              |
//| - エントリーポイントをSLに近づけて高ロット化                         |
//+------------------------------------------------------------------+
class CLotCalculator
{
private:
   string            m_Symbol;
   CRiskManager*     m_RiskManager;

   double            m_DefaultRiskPercent;   // デフォルトリスク率
   int               m_LotDigits;            // ロット表示桁数

public:
   //--- Constructor
   CLotCalculator()
   {
      m_Symbol = "";
      m_RiskManager = NULL;
      m_DefaultRiskPercent = 2.0;
      m_LotDigits = 2;
   }

   //--- Initialize
   bool Initialize(string symbol, CRiskManager* riskManager, double riskPercent = 2.0)
   {
      m_Symbol = symbol;
      m_RiskManager = riskManager;
      m_DefaultRiskPercent = riskPercent;

      Print("[LotCalculator] Initialized with risk: ", m_DefaultRiskPercent, "%");
      return true;
   }

   //--- Get pip size for symbol
   double GetPipSize()
   {
      int digits = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);

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

   //--- Calculate loss per lot for given SL distance in pips
   double CalculateLossPerLot(double slPips)
   {
      double tickSize = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double pipSize = GetPipSize();

      double slDistance = slPips * pipSize;
      double numTicks = slDistance / tickSize;
      double lossPerLot = numTicks * tickValue;

      return lossPerLot;
   }

   //--- Calculate lot size based on SL distance and risk
   double CalculateLotSize(double entryPrice, double stopLoss, double customRiskPercent = 0)
   {
      double riskPercent = customRiskPercent > 0 ? customRiskPercent : m_DefaultRiskPercent;

      // Calculate SL distance in pips
      double pipSize = GetPipSize();
      double slDistance = MathAbs(entryPrice - stopLoss);
      double slPips = slDistance / pipSize;

      if(slPips <= 0)
      {
         Print("[LotCalculator] Invalid SL distance");
         return 0;
      }

      // Get max risk amount from risk manager
      double maxRiskAmount = m_RiskManager.GetMaxRiskAmount();
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Calculate risk amount based on percentage
      double targetRiskAmount = accountBalance * (riskPercent / 100.0);

      // Use the smaller of target risk and max allowed risk
      double actualRiskAmount = MathMin(targetRiskAmount, maxRiskAmount);

      if(actualRiskAmount <= 0)
      {
         Print("[LotCalculator] No risk capacity available");
         return 0;
      }

      // Calculate lots
      double lossPerLot = CalculateLossPerLot(slPips);
      if(lossPerLot <= 0)
      {
         Print("[LotCalculator] Invalid loss per lot calculation");
         return 0;
      }

      double calculatedLots = actualRiskAmount / lossPerLot;

      // Apply lot reduction multiplier from risk manager
      double reductionMultiplier = m_RiskManager.GetLotReductionMultiplier();
      calculatedLots *= reductionMultiplier;

      // Normalize lot size
      double normalizedLots = NormalizeLotSize(calculatedLots);

      PrintFormat("[LotCalculator] Entry=%.5f, SL=%.5f, SLPips=%.1f, Risk=%.2f%%, MaxRisk=%.2f, Lots=%.2f",
                  entryPrice, stopLoss, slPips, riskPercent, actualRiskAmount, normalizedLots);

      return normalizedLots;
   }

   //--- Calculate optimal entry price to maximize lot size
   //--- エントリーポイントをSLに近づけて高ロット化
   double CalculateOptimalEntry(double currentPrice, double stopLoss, bool isBuy, double targetLots = 0)
   {
      if(targetLots <= 0)
         return currentPrice;

      double pipSize = GetPipSize();
      double maxRiskAmount = m_RiskManager.GetMaxRiskAmount();

      // Calculate required SL distance for target lots
      double lossPerLot = 1.0;  // Will calculate iteratively
      double targetSlPips = maxRiskAmount / (targetLots * CalculateLossPerLot(1.0));

      double optimalEntry;
      if(isBuy)
      {
         // For buy: entry should be closer to SL (lower)
         optimalEntry = stopLoss + (targetSlPips * pipSize);

         // Cannot enter below current price for buy
         if(optimalEntry < currentPrice)
            optimalEntry = currentPrice;
      }
      else
      {
         // For sell: entry should be closer to SL (higher)
         optimalEntry = stopLoss - (targetSlPips * pipSize);

         // Cannot enter above current price for sell
         if(optimalEntry > currentPrice)
            optimalEntry = currentPrice;
      }

      return optimalEntry;
   }

   //--- Normalize lot size according to broker constraints
   double NormalizeLotSize(double lots)
   {
      double minLot = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_STEP);

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

   //--- Calculate profit per lot for given TP distance
   double CalculateProfitPerLot(double tpPips)
   {
      double tickSize = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double pipSize = GetPipSize();

      double tpDistance = tpPips * pipSize;
      double numTicks = tpDistance / tickSize;
      double profitPerLot = numTicks * tickValue;

      return profitPerLot;
   }

   //--- Calculate expected profit for a trade
   double CalculateExpectedProfit(double entryPrice, double takeProfit, double lots)
   {
      double pipSize = GetPipSize();
      double tpDistance = MathAbs(takeProfit - entryPrice);
      double tpPips = tpDistance / pipSize;

      double profitPerLot = CalculateProfitPerLot(tpPips);
      return profitPerLot * lots;
   }

   //--- Calculate expected loss for a trade
   double CalculateExpectedLoss(double entryPrice, double stopLoss, double lots)
   {
      double pipSize = GetPipSize();
      double slDistance = MathAbs(entryPrice - stopLoss);
      double slPips = slDistance / pipSize;

      double lossPerLot = CalculateLossPerLot(slPips);
      return lossPerLot * lots;
   }

   //--- Calculate risk-reward ratio
   double CalculateRiskRewardRatio(double entryPrice, double stopLoss, double takeProfit)
   {
      double slDistance = MathAbs(entryPrice - stopLoss);
      double tpDistance = MathAbs(takeProfit - entryPrice);

      if(slDistance <= 0)
         return 0;

      return tpDistance / slDistance;
   }

   //--- Check if trade meets minimum RR requirement
   bool MeetsMinimumRR(double entryPrice, double stopLoss, double takeProfit, double minRR = 1.5)
   {
      double rr = CalculateRiskRewardRatio(entryPrice, stopLoss, takeProfit);
      return rr >= minRR;
   }

   //--- Get trade summary string
   string GetTradeSummary(double entryPrice, double stopLoss, double takeProfit, double lots)
   {
      double pipSize = GetPipSize();
      double slPips = MathAbs(entryPrice - stopLoss) / pipSize;
      double tpPips = MathAbs(takeProfit - entryPrice) / pipSize;
      double rr = CalculateRiskRewardRatio(entryPrice, stopLoss, takeProfit);
      double expectedLoss = CalculateExpectedLoss(entryPrice, stopLoss, lots);
      double expectedProfit = CalculateExpectedProfit(entryPrice, takeProfit, lots);

      return StringFormat(
         "Lots=%.2f | SL=%.1f pips (%.0f) | TP=%.1f pips (+%.0f) | RR=1:%.2f",
         lots, slPips, -expectedLoss, tpPips, expectedProfit, rr
      );
   }

   //--- Setters
   void SetDefaultRiskPercent(double percent) { m_DefaultRiskPercent = percent; }

   //--- Getters
   double GetDefaultRiskPercent() { return m_DefaultRiskPercent; }
};

#endif // LOT_CALCULATOR_MQH
