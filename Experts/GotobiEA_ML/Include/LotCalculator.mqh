//+------------------------------------------------------------------+
//|                                                LotCalculator.mqh |
//|                                  Lot Size Calculator for Gotobi |
//|                              高ロット戦略（SL近接エントリー対応） |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML"
#property version   "1.00"

//+------------------------------------------------------------------+
//| ロットサイズ計算クラス                                            |
//+------------------------------------------------------------------+
class CLotCalculator
{
private:
   // シンボル情報
   string      m_symbol;
   double      m_pipSize;
   double      m_point;
   int         m_digits;
   double      m_tickSize;
   double      m_tickValue;
   double      m_contractSize;

   // ブローカー制約
   double      m_minLot;
   double      m_maxLot;
   double      m_lotStep;

   // 初期化済みフラグ
   bool        m_initialized;

   // 内部メソッド
   double      GetPipSize();
   void        UpdateSymbolInfo();

public:
   CLotCalculator();
   ~CLotCalculator();

   // 初期化
   bool Initialize(string symbol);

   // === ロット計算メソッド ===

   // リスク%とSL pipsからロット計算
   double CalculateLotByRisk(double riskPercent, double slPips, double balance = 0);

   // 最大損失額とSL pipsからロット計算
   double CalculateLotByAmount(double maxLossAmount, double slPips);

   // SL価格からロット計算（エントリー価格とSL価格を指定）
   double CalculateLotByPrice(double entryPrice, double slPrice, double maxLossAmount);

   // === 損益計算メソッド ===

   // 1ロットあたりの損失額計算（SL pips指定）
   double CalculateLossPerLot(double slPips);

   // 1ロットあたりの利益額計算（TP pips指定）
   double CalculateProfitPerLot(double tpPips);

   // 指定ロットでの期待損失額
   double CalculateExpectedLoss(double lots, double slPips);

   // 指定ロットでの期待利益額
   double CalculateExpectedProfit(double lots, double tpPips);

   // === 高ロット戦略サポート ===

   // エントリーを損切りラインに近づけた場合の最適ロット計算
   // (Fintokei 5%ルール遵守)
   double CalculateOptimalHighLot(double entryPrice, double slPrice,
                                  double accountBalance, double maxRiskPct);

   // SL幅を最小化した場合のロット（アグレッシブ戦略）
   double CalculateAggressiveLot(double minSlPips, double accountBalance, double maxRiskPct);

   // === ユーティリティ ===

   // ロットサイズの正規化
   double NormalizeLotSize(double lots);

   // ロットが有効かチェック
   bool IsValidLot(double lots);

   // pip値の取得
   double GetPipValue(double lots = 1.0);

   // 情報取得
   double GetMinLot() { return m_minLot; }
   double GetMaxLot() { return m_maxLot; }
   double GetLotStep() { return m_lotStep; }
   double GetSymbolPipSize() { return m_pipSize; }

   // ログ出力
   void LogLotCalculation(double riskPct, double slPips, double calculatedLot);
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CLotCalculator::CLotCalculator()
{
   m_symbol = "";
   m_pipSize = 0;
   m_point = 0;
   m_digits = 0;
   m_tickSize = 0;
   m_tickValue = 0;
   m_contractSize = 0;
   m_minLot = 0;
   m_maxLot = 0;
   m_lotStep = 0;
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CLotCalculator::~CLotCalculator()
{
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CLotCalculator::Initialize(string symbol)
{
   m_symbol = symbol;
   UpdateSymbolInfo();

   if(m_tickSize <= 0 || m_tickValue <= 0)
   {
      Print("LotCalculator: シンボル情報取得失敗 ", symbol);
      return false;
   }

   m_initialized = true;

   Print("LotCalculator: 初期化完了 ", symbol,
         " MinLot=", m_minLot,
         " MaxLot=", m_maxLot,
         " PipSize=", m_pipSize);

   return true;
}

//+------------------------------------------------------------------+
//| シンボル情報更新                                                  |
//+------------------------------------------------------------------+
void CLotCalculator::UpdateSymbolInfo()
{
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_pipSize = GetPipSize();
   m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   m_tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   m_contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   m_minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   m_maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   m_lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
}

//+------------------------------------------------------------------+
//| pip サイズ取得                                                    |
//+------------------------------------------------------------------+
double CLotCalculator::GetPipSize()
{
   if(m_digits == 3 || m_digits == 5)
      return m_point * 10.0;
   else
      return m_point;
}

//+------------------------------------------------------------------+
//| 1ロットあたりの損失額計算                                         |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateLossPerLot(double slPips)
{
   if(!m_initialized)
      return 0;

   // SL pipsを価格距離に変換
   double slDistance = slPips * m_pipSize;

   // ティック数を計算
   double numTicks = slDistance / m_tickSize;

   // 1ロットあたりの損失額
   double lossPerLot = numTicks * m_tickValue;

   return lossPerLot;
}

//+------------------------------------------------------------------+
//| 1ロットあたりの利益額計算                                         |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateProfitPerLot(double tpPips)
{
   if(!m_initialized)
      return 0;

   double tpDistance = tpPips * m_pipSize;
   double numTicks = tpDistance / m_tickSize;
   double profitPerLot = numTicks * m_tickValue;

   return profitPerLot;
}

//+------------------------------------------------------------------+
//| リスク%とSL pipsからロット計算                                    |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateLotByRisk(double riskPercent, double slPips, double balance)
{
   if(!m_initialized || slPips <= 0)
      return m_minLot;

   // 残高取得
   if(balance <= 0)
      balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // 最大損失額計算
   double maxLossAmount = balance * (riskPercent / 100.0);

   return CalculateLotByAmount(maxLossAmount, slPips);
}

//+------------------------------------------------------------------+
//| 最大損失額とSL pipsからロット計算                                 |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateLotByAmount(double maxLossAmount, double slPips)
{
   if(!m_initialized || slPips <= 0 || maxLossAmount <= 0)
      return m_minLot;

   double lossPerLot = CalculateLossPerLot(slPips);

   if(lossPerLot <= 0)
      return m_minLot;

   double calculatedLots = maxLossAmount / lossPerLot;

   return NormalizeLotSize(calculatedLots);
}

//+------------------------------------------------------------------+
//| SL価格からロット計算                                              |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateLotByPrice(double entryPrice, double slPrice, double maxLossAmount)
{
   if(!m_initialized || maxLossAmount <= 0)
      return m_minLot;

   // SL幅をpipsで計算
   double slDistance = MathAbs(entryPrice - slPrice);
   double slPips = slDistance / m_pipSize;

   if(slPips <= 0)
      return m_minLot;

   return CalculateLotByAmount(maxLossAmount, slPips);
}

//+------------------------------------------------------------------+
//| 期待損失額計算                                                    |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateExpectedLoss(double lots, double slPips)
{
   return CalculateLossPerLot(slPips) * lots;
}

//+------------------------------------------------------------------+
//| 期待利益額計算                                                    |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateExpectedProfit(double lots, double tpPips)
{
   return CalculateProfitPerLot(tpPips) * lots;
}

//+------------------------------------------------------------------+
//| 高ロット最適化計算                                                |
//| エントリーを損切りラインに近づけることで高ロットを実現            |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateOptimalHighLot(double entryPrice, double slPrice,
                                               double accountBalance, double maxRiskPct)
{
   if(!m_initialized)
      return m_minLot;

   // SL幅計算（価格差）
   double slDistance = MathAbs(entryPrice - slPrice);
   double slPips = slDistance / m_pipSize;

   // 最大リスク額（Fintokei 5%ルール対応）
   double maxRiskAmount = accountBalance * (maxRiskPct / 100.0);

   // ロット計算
   double optimalLot = CalculateLotByAmount(maxRiskAmount, slPips);

   Print("LotCalculator: 高ロット計算 SL=", DoubleToString(slPips, 1), "pips",
         " リスク=", DoubleToString(maxRiskPct, 1), "%",
         " ロット=", DoubleToString(optimalLot, 2));

   return optimalLot;
}

//+------------------------------------------------------------------+
//| アグレッシブロット計算（最小SL幅）                                |
//+------------------------------------------------------------------+
double CLotCalculator::CalculateAggressiveLot(double minSlPips, double accountBalance, double maxRiskPct)
{
   if(!m_initialized)
      return m_minLot;

   // 最小SL幅での最大ロット
   double maxRiskAmount = accountBalance * (maxRiskPct / 100.0);
   double aggressiveLot = CalculateLotByAmount(maxRiskAmount, minSlPips);

   Print("LotCalculator: アグレッシブ計算 最小SL=", DoubleToString(minSlPips, 1), "pips",
         " ロット=", DoubleToString(aggressiveLot, 2));

   return aggressiveLot;
}

//+------------------------------------------------------------------+
//| ロットサイズ正規化                                                |
//+------------------------------------------------------------------+
double CLotCalculator::NormalizeLotSize(double lots)
{
   // 最小値チェック
   if(lots < m_minLot)
      lots = m_minLot;

   // 最大値チェック
   if(lots > m_maxLot)
      lots = m_maxLot;

   // ロットステップに正規化（切り捨て）
   lots = MathFloor(lots / m_lotStep) * m_lotStep;

   // 最小値を下回らないよう再チェック
   if(lots < m_minLot)
      lots = m_minLot;

   return lots;
}

//+------------------------------------------------------------------+
//| ロット有効性チェック                                              |
//+------------------------------------------------------------------+
bool CLotCalculator::IsValidLot(double lots)
{
   if(lots < m_minLot)
      return false;
   if(lots > m_maxLot)
      return false;

   // ロットステップに合っているか
   double remainder = MathMod(lots, m_lotStep);
   if(remainder > m_lotStep / 2)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| pip値取得                                                         |
//+------------------------------------------------------------------+
double CLotCalculator::GetPipValue(double lots)
{
   if(!m_initialized)
      return 0;

   double pipDistance = m_pipSize;
   double numTicks = pipDistance / m_tickSize;

   return numTicks * m_tickValue * lots;
}

//+------------------------------------------------------------------+
//| ログ出力                                                          |
//+------------------------------------------------------------------+
void CLotCalculator::LogLotCalculation(double riskPct, double slPips, double calculatedLot)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (riskPct / 100.0);
   double expectedLoss = CalculateExpectedLoss(calculatedLot, slPips);

   Print("=== ロット計算詳細 ===");
   Print("残高: ", DoubleToString(balance, 0));
   Print("リスク%: ", DoubleToString(riskPct, 1), "%");
   Print("リスク額: ", DoubleToString(riskAmount, 0));
   Print("SL幅: ", DoubleToString(slPips, 1), " pips");
   Print("1ロット損失: ", DoubleToString(CalculateLossPerLot(slPips), 0));
   Print("計算ロット: ", DoubleToString(calculatedLot, 2));
   Print("予想損失: ", DoubleToString(expectedLoss, 0));
   Print("1pip価値: ", DoubleToString(GetPipValue(calculatedLot), 0));
   Print("======================");
}

//+------------------------------------------------------------------+
