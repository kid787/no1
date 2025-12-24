//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                        Risk Management (VaR, Correlation, DD)   |
//|                              Fintokei資金管理ルール完全対応       |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML"
#property version   "1.00"

//+------------------------------------------------------------------+
//| 定数定義                                                          |
//+------------------------------------------------------------------+
#define VAR_HISTORY_SIZE       100  // VaR計算用価格変動履歴
#define CORRELATION_PERIOD     50   // 相関計算期間

//+------------------------------------------------------------------+
//| Fintokei設定構造体                                                |
//+------------------------------------------------------------------+
struct FintokeiSettings
{
   double initialBalance;         // 初期資金
   double dailyLossLimitPct;      // 日次最大損失率（5%）
   double totalLossLimitPct;      // 全体最大損失率（10%）
   double maxConcurrentRiskPct;   // 同時ポジションリスク上限（3%）
   double maxDrawdownReduction;   // DD時のロット削減率
   double ddThresholdPct;         // DD閾値（6%）
};

//+------------------------------------------------------------------+
//| 日次リセット情報構造体                                            |
//+------------------------------------------------------------------+
struct DailyResetInfo
{
   datetime resetTime;            // リセット時刻（UTC 0時 = JST 9時）
   double   equityAtReset;        // リセット時の有効証拠金
   double   dailyLossLimit;       // 当日の損失限度額
   double   dailyPnL;             // 当日の損益
};

//+------------------------------------------------------------------+
//| リスク管理クラス                                                  |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   // Fintokei設定
   FintokeiSettings m_fintokei;

   // 日次リセット情報
   DailyResetInfo   m_dailyInfo;

   // VaR計算用
   double           m_priceChanges[];
   int              m_priceChangeCount;
   double           m_var99;           // 99%信頼区間VaR

   // 相関計算用
   string           m_correlationSymbol;
   double           m_correlation;
   double           m_correlationThreshold;

   // ドローダウン管理
   double           m_peakEquity;
   double           m_currentDD;
   double           m_maxDD;
   bool             m_isLotReduced;

   // シンボル情報
   string           m_symbol;
   double           m_pipSize;

   // 初期化済みフラグ
   bool             m_initialized;

   // 内部メソッド
   void             UpdatePriceChanges();
   double           CalculateHistoricalVaR(double confidenceLevel);
   void             QuickSort(double &arr[], int left, int right);
   double           CalculateCorrelation(string symbol1, string symbol2, int period);
   void             CheckDailyReset();
   double           GetCurrentEquity();
   double           GetAccountBalance();
   double           GetUnrealizedPnL();

public:
   CRiskManager();
   ~CRiskManager();

   // 初期化
   bool Initialize(string symbol, double initialBalance);

   // Fintokei設定
   void SetFintokeiSettings(double dailyLossPct, double totalLossPct,
                            double concurrentRiskPct, double ddThreshold);

   // === Fintokeiルール監視 ===

   // 日次損失チェック（5%ルール）
   bool IsDailyLossLimitOK();
   double GetDailyLossRemaining();
   double GetDailyLossPct();

   // 全体損失チェック（10%ルール）
   bool IsTotalLossLimitOK();
   double GetTotalLossRemaining();
   double GetTotalLossPct();

   // 同時ポジションリスクチェック（3%ルール）
   bool IsConcurrentRiskOK(double additionalRisk);
   double GetCurrentConcurrentRisk();

   // エントリー可能かどうかの総合チェック
   bool CanOpenPosition(double riskAmount);

   // 強制決済が必要かチェック
   bool ShouldForceClose();

   // === VaRリスク管理 ===

   // VaR更新
   void UpdateVaR();

   // VaR取得（金額）
   double GetVaR99();

   // VaRベースの最大ロット計算
   double GetMaxLotByVaR(double maxLossAmount);

   // === コリレーション分析 ===

   // 相関係数更新
   void UpdateCorrelation(string correlationSymbol = "EURUSD");

   // 相関係数取得
   double GetCorrelation();

   // 相関リスクチェック（0.8超で警告）
   bool IsCorrelationRiskHigh();

   // === ドローダウン管理 ===

   // DD更新
   void UpdateDrawdown();

   // 現在のDD率取得
   double GetCurrentDrawdownPct();

   // 最大DD取得
   double GetMaxDrawdownPct();

   // DD時のロット削減が必要か
   bool IsLotReductionActive();

   // ロット削減率取得（通常1.0、DD時0.5）
   double GetLotReductionFactor();

   // === 安全なロット計算 ===

   // 全リスク条件を考慮した最大ロット
   double GetSafeLotSize(double slPips, double riskPercent);

   // === ログ出力 ===
   void LogRiskStatus();
   void LogFintokeiStatus();
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
{
   m_priceChangeCount = 0;
   m_var99 = 0;
   m_correlationSymbol = "EURUSD";
   m_correlation = 0;
   m_correlationThreshold = 0.8;
   m_peakEquity = 0;
   m_currentDD = 0;
   m_maxDD = 0;
   m_isLotReduced = false;
   m_symbol = "";
   m_pipSize = 0;
   m_initialized = false;

   // Fintokeiデフォルト設定
   m_fintokei.initialBalance = 0;
   m_fintokei.dailyLossLimitPct = 5.0;
   m_fintokei.totalLossLimitPct = 10.0;
   m_fintokei.maxConcurrentRiskPct = 3.0;
   m_fintokei.maxDrawdownReduction = 0.5;
   m_fintokei.ddThresholdPct = 6.0;

   // 日次リセット初期化
   m_dailyInfo.resetTime = 0;
   m_dailyInfo.equityAtReset = 0;
   m_dailyInfo.dailyLossLimit = 0;
   m_dailyInfo.dailyPnL = 0;
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
   ArrayFree(m_priceChanges);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CRiskManager::Initialize(string symbol, double initialBalance)
{
   m_symbol = symbol;

   // pip サイズ計算
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   m_pipSize = (digits == 3 || digits == 5) ? point * 10.0 : point;

   // Fintokei初期資金設定
   m_fintokei.initialBalance = initialBalance > 0 ? initialBalance : AccountInfoDouble(ACCOUNT_BALANCE);

   // 価格変動履歴初期化
   ArrayResize(m_priceChanges, VAR_HISTORY_SIZE);
   ArrayFill(m_priceChanges, 0, VAR_HISTORY_SIZE, 0);

   // 初期VaR計算
   UpdatePriceChanges();

   // 初期相関計算
   UpdateCorrelation();

   // 日次リセット情報初期化
   CheckDailyReset();

   // ピークエクイティ初期化
   m_peakEquity = GetCurrentEquity();

   m_initialized = true;

   Print("RiskManager: 初期化完了 初期資金=", DoubleToString(m_fintokei.initialBalance, 0));

   return true;
}

//+------------------------------------------------------------------+
//| Fintokei設定                                                      |
//+------------------------------------------------------------------+
void CRiskManager::SetFintokeiSettings(double dailyLossPct, double totalLossPct,
                                       double concurrentRiskPct, double ddThreshold)
{
   m_fintokei.dailyLossLimitPct = dailyLossPct;
   m_fintokei.totalLossLimitPct = totalLossPct;
   m_fintokei.maxConcurrentRiskPct = concurrentRiskPct;
   m_fintokei.ddThresholdPct = ddThreshold;

   Print("RiskManager: Fintokei設定更新 日次=", dailyLossPct, "% 全体=", totalLossPct, "%");
}

//+------------------------------------------------------------------+
//| 現在の有効証拠金取得                                              |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

//+------------------------------------------------------------------+
//| 口座残高取得                                                      |
//+------------------------------------------------------------------+
double CRiskManager::GetAccountBalance()
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
//| 未実現損益取得                                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetUnrealizedPnL()
{
   double totalPnL = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         totalPnL += PositionGetDouble(POSITION_PROFIT);
         totalPnL += PositionGetDouble(POSITION_SWAP);
      }
   }

   return totalPnL;
}

//+------------------------------------------------------------------+
//| 日次リセットチェック（UTC 0時 = JST 9時）                         |
//+------------------------------------------------------------------+
void CRiskManager::CheckDailyReset()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime mdt;
   TimeToStruct(currentTime, mdt);

   // 今日のUTC 0時を計算
   datetime todayReset = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                   mdt.year, mdt.mon, mdt.day));

   // リセット時刻を過ぎていて、まだ更新していない場合
   if(currentTime >= todayReset && m_dailyInfo.resetTime < todayReset)
   {
      m_dailyInfo.resetTime = todayReset;
      m_dailyInfo.equityAtReset = GetCurrentEquity();
      m_dailyInfo.dailyLossLimit = m_dailyInfo.equityAtReset * (m_fintokei.dailyLossLimitPct / 100.0);
      m_dailyInfo.dailyPnL = 0;

      Print("RiskManager: 日次リセット実行 基準エクイティ=", DoubleToString(m_dailyInfo.equityAtReset, 0),
            " 日次損失限度=", DoubleToString(m_dailyInfo.dailyLossLimit, 0));
   }

   // 初回初期化
   if(m_dailyInfo.resetTime == 0)
   {
      m_dailyInfo.resetTime = todayReset;
      m_dailyInfo.equityAtReset = GetCurrentEquity();
      m_dailyInfo.dailyLossLimit = m_dailyInfo.equityAtReset * (m_fintokei.dailyLossLimitPct / 100.0);
   }
}

//+------------------------------------------------------------------+
//| 日次損失チェック（5%ルール）                                      |
//+------------------------------------------------------------------+
bool CRiskManager::IsDailyLossLimitOK()
{
   CheckDailyReset();

   double currentEquity = GetCurrentEquity();
   double lossFromReset = m_dailyInfo.equityAtReset - currentEquity;

   // 失格ライン = リセット時エクイティ × 95%
   double disqualifyLine = m_dailyInfo.equityAtReset * (1.0 - m_fintokei.dailyLossLimitPct / 100.0);

   // 現在のエクイティが失格ラインを下回っていないかチェック
   return (currentEquity > disqualifyLine);
}

//+------------------------------------------------------------------+
//| 日次残り損失許容額取得                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetDailyLossRemaining()
{
   CheckDailyReset();

   double currentEquity = GetCurrentEquity();
   double disqualifyLine = m_dailyInfo.equityAtReset * (1.0 - m_fintokei.dailyLossLimitPct / 100.0);

   return MathMax(0, currentEquity - disqualifyLine);
}

//+------------------------------------------------------------------+
//| 日次損失率取得                                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetDailyLossPct()
{
   CheckDailyReset();

   double currentEquity = GetCurrentEquity();
   double lossFromReset = m_dailyInfo.equityAtReset - currentEquity;

   if(m_dailyInfo.equityAtReset <= 0)
      return 0;

   return (lossFromReset / m_dailyInfo.equityAtReset) * 100.0;
}

//+------------------------------------------------------------------+
//| 全体損失チェック（10%ルール）                                     |
//+------------------------------------------------------------------+
bool CRiskManager::IsTotalLossLimitOK()
{
   double currentEquity = GetCurrentEquity();

   // 失格ライン = 初期資金 × 90%
   double disqualifyLine = m_fintokei.initialBalance * (1.0 - m_fintokei.totalLossLimitPct / 100.0);

   return (currentEquity > disqualifyLine);
}

//+------------------------------------------------------------------+
//| 全体残り損失許容額取得                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetTotalLossRemaining()
{
   double currentEquity = GetCurrentEquity();
   double disqualifyLine = m_fintokei.initialBalance * (1.0 - m_fintokei.totalLossLimitPct / 100.0);

   return MathMax(0, currentEquity - disqualifyLine);
}

//+------------------------------------------------------------------+
//| 全体損失率取得                                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetTotalLossPct()
{
   double currentEquity = GetCurrentEquity();
   double lossFromInitial = m_fintokei.initialBalance - currentEquity;

   if(m_fintokei.initialBalance <= 0)
      return 0;

   return (lossFromInitial / m_fintokei.initialBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| 同時ポジションリスクチェック（3%ルール）                          |
//+------------------------------------------------------------------+
bool CRiskManager::IsConcurrentRiskOK(double additionalRisk)
{
   double currentRisk = GetCurrentConcurrentRisk();
   double totalRisk = currentRisk + additionalRisk;

   double maxRiskAmount = m_fintokei.initialBalance * (m_fintokei.maxConcurrentRiskPct / 100.0);

   return (totalRisk <= maxRiskAmount);
}

//+------------------------------------------------------------------+
//| 現在の同時ポジションリスク取得                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentConcurrentRisk()
{
   double totalRisk = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         double posProfit = PositionGetDouble(POSITION_PROFIT);
         if(posProfit < 0)
         {
            totalRisk += MathAbs(posProfit);
         }

         // SLまでの潜在的損失も計算
         double sl = PositionGetDouble(POSITION_SL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double lots = PositionGetDouble(POSITION_VOLUME);

         if(sl > 0)
         {
            double slDistance = MathAbs(openPrice - sl);
            double tickSize = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_TICK_SIZE);
            double tickValue = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_TICK_VALUE);
            double potentialLoss = (slDistance / tickSize) * tickValue * lots;
            totalRisk = MathMax(totalRisk, potentialLoss);
         }
      }
   }

   return totalRisk;
}

//+------------------------------------------------------------------+
//| エントリー可能かの総合チェック                                    |
//+------------------------------------------------------------------+
bool CRiskManager::CanOpenPosition(double riskAmount)
{
   // 日次損失チェック
   if(!IsDailyLossLimitOK())
   {
      Print("RiskManager: 日次損失限度に達しています");
      return false;
   }

   // 全体損失チェック
   if(!IsTotalLossLimitOK())
   {
      Print("RiskManager: 全体損失限度に達しています");
      return false;
   }

   // 同時リスクチェック
   if(!IsConcurrentRiskOK(riskAmount))
   {
      Print("RiskManager: 同時ポジションリスク限度に達しています");
      return false;
   }

   // 相関リスクチェック
   if(IsCorrelationRiskHigh())
   {
      Print("RiskManager: 相関リスクが高いためエントリー停止");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 強制決済が必要かチェック                                          |
//+------------------------------------------------------------------+
bool CRiskManager::ShouldForceClose()
{
   double currentEquity = GetCurrentEquity();

   // 日次失格ラインの95%（安全マージン）
   double dailyWarningLine = m_dailyInfo.equityAtReset * (1.0 - m_fintokei.dailyLossLimitPct / 100.0 * 0.95);

   // 全体失格ラインの95%
   double totalWarningLine = m_fintokei.initialBalance * (1.0 - m_fintokei.totalLossLimitPct / 100.0 * 0.95);

   if(currentEquity <= dailyWarningLine)
   {
      Print("RiskManager: 日次損失限度の警告ライン到達 強制決済推奨");
      return true;
   }

   if(currentEquity <= totalWarningLine)
   {
      Print("RiskManager: 全体損失限度の警告ライン到達 強制決済推奨");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 価格変動履歴更新                                                  |
//+------------------------------------------------------------------+
void CRiskManager::UpdatePriceChanges()
{
   double close[];
   ArraySetAsSeries(close, true);

   if(CopyClose(m_symbol, PERIOD_D1, 0, VAR_HISTORY_SIZE + 1, close) < VAR_HISTORY_SIZE + 1)
      return;

   m_priceChangeCount = 0;

   for(int i = 0; i < VAR_HISTORY_SIZE; i++)
   {
      if(close[i + 1] != 0)
      {
         m_priceChanges[i] = (close[i] - close[i + 1]) / close[i + 1] * 100.0;
         m_priceChangeCount++;
      }
   }

   // VaR計算
   m_var99 = CalculateHistoricalVaR(0.99);
}

//+------------------------------------------------------------------+
//| ヒストリカルVaR計算                                               |
//+------------------------------------------------------------------+
double CRiskManager::CalculateHistoricalVaR(double confidenceLevel)
{
   if(m_priceChangeCount < 10)
      return 0;

   // 価格変動をコピーしてソート
   double sortedChanges[];
   ArrayResize(sortedChanges, m_priceChangeCount);

   for(int i = 0; i < m_priceChangeCount; i++)
   {
      sortedChanges[i] = m_priceChanges[i];
   }

   // クイックソート
   QuickSort(sortedChanges, 0, m_priceChangeCount - 1);

   // パーセンタイル計算（99%信頼区間 = 1%パーセンタイル）
   int index = (int)MathFloor((1.0 - confidenceLevel) * m_priceChangeCount);
   index = MathMax(0, MathMin(index, m_priceChangeCount - 1));

   // 結果を保存してから配列を解放
   double result = MathAbs(sortedChanges[index]);

   ArrayFree(sortedChanges);

   return result;
}

//+------------------------------------------------------------------+
//| クイックソート                                                    |
//+------------------------------------------------------------------+
void CRiskManager::QuickSort(double &arr[], int left, int right)
{
   if(left >= right)
      return;

   double pivot = arr[(left + right) / 2];
   int i = left;
   int j = right;

   while(i <= j)
   {
      while(arr[i] < pivot) i++;
      while(arr[j] > pivot) j--;

      if(i <= j)
      {
         double temp = arr[i];
         arr[i] = arr[j];
         arr[j] = temp;
         i++;
         j--;
      }
   }

   if(left < j) QuickSort(arr, left, j);
   if(i < right) QuickSort(arr, i, right);
}

//+------------------------------------------------------------------+
//| VaR更新                                                           |
//+------------------------------------------------------------------+
void CRiskManager::UpdateVaR()
{
   UpdatePriceChanges();
}

//+------------------------------------------------------------------+
//| VaR取得（%）                                                      |
//+------------------------------------------------------------------+
double CRiskManager::GetVaR99()
{
   return m_var99;
}

//+------------------------------------------------------------------+
//| VaRベースの最大ロット計算                                         |
//+------------------------------------------------------------------+
double CRiskManager::GetMaxLotByVaR(double maxLossAmount)
{
   if(m_var99 <= 0)
      return 0;

   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   // 1ロットあたりの予想最大損失
   double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double expectedLossPerLot = currentPrice * contractSize * (m_var99 / 100.0);

   if(expectedLossPerLot <= 0)
      return 0;

   double maxLots = maxLossAmount / expectedLossPerLot;

   // ブローカー制約で正規化
   double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

   maxLots = MathFloor(maxLots / lotStep) * lotStep;
   maxLots = MathMax(minLot, MathMin(maxLots, maxLot));

   return maxLots;
}

//+------------------------------------------------------------------+
//| 相関係数更新                                                      |
//+------------------------------------------------------------------+
void CRiskManager::UpdateCorrelation(string correlationSymbol)
{
   m_correlationSymbol = correlationSymbol;
   m_correlation = CalculateCorrelation(m_symbol, correlationSymbol, CORRELATION_PERIOD);
}

//+------------------------------------------------------------------+
//| 相関係数計算                                                      |
//+------------------------------------------------------------------+
double CRiskManager::CalculateCorrelation(string symbol1, string symbol2, int period)
{
   double close1[], close2[];
   ArraySetAsSeries(close1, true);
   ArraySetAsSeries(close2, true);

   if(CopyClose(symbol1, PERIOD_D1, 0, period, close1) < period)
      return 0;
   if(CopyClose(symbol2, PERIOD_D1, 0, period, close2) < period)
      return 0;

   // 変化率計算
   double changes1[], changes2[];
   ArrayResize(changes1, period - 1);
   ArrayResize(changes2, period - 1);

   for(int i = 0; i < period - 1; i++)
   {
      changes1[i] = (close1[i] - close1[i + 1]) / close1[i + 1];
      changes2[i] = (close2[i] - close2[i + 1]) / close2[i + 1];
   }

   // 平均計算
   double mean1 = 0, mean2 = 0;
   for(int i = 0; i < period - 1; i++)
   {
      mean1 += changes1[i];
      mean2 += changes2[i];
   }
   mean1 /= (period - 1);
   mean2 /= (period - 1);

   // 共分散と標準偏差計算
   double covariance = 0;
   double variance1 = 0, variance2 = 0;

   for(int i = 0; i < period - 1; i++)
   {
      double diff1 = changes1[i] - mean1;
      double diff2 = changes2[i] - mean2;
      covariance += diff1 * diff2;
      variance1 += diff1 * diff1;
      variance2 += diff2 * diff2;
   }

   double stdDev1 = MathSqrt(variance1);
   double stdDev2 = MathSqrt(variance2);

   if(stdDev1 == 0 || stdDev2 == 0)
      return 0;

   double correlation = covariance / (stdDev1 * stdDev2);

   ArrayFree(changes1);
   ArrayFree(changes2);

   return correlation;
}

//+------------------------------------------------------------------+
//| 相関係数取得                                                      |
//+------------------------------------------------------------------+
double CRiskManager::GetCorrelation()
{
   return m_correlation;
}

//+------------------------------------------------------------------+
//| 相関リスクチェック                                                |
//+------------------------------------------------------------------+
bool CRiskManager::IsCorrelationRiskHigh()
{
   return (MathAbs(m_correlation) > m_correlationThreshold);
}

//+------------------------------------------------------------------+
//| ドローダウン更新                                                  |
//+------------------------------------------------------------------+
void CRiskManager::UpdateDrawdown()
{
   double currentEquity = GetCurrentEquity();

   // ピーク更新
   if(currentEquity > m_peakEquity)
   {
      m_peakEquity = currentEquity;
      m_isLotReduced = false; // DD回復でロット削減解除
   }

   // DD計算
   if(m_peakEquity > 0)
   {
      m_currentDD = ((m_peakEquity - currentEquity) / m_peakEquity) * 100.0;
   }

   // 最大DD更新
   if(m_currentDD > m_maxDD)
   {
      m_maxDD = m_currentDD;
   }

   // DD閾値チェック
   if(m_currentDD >= m_fintokei.ddThresholdPct)
   {
      m_isLotReduced = true;
   }
}

//+------------------------------------------------------------------+
//| 現在のDD率取得                                                    |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentDrawdownPct()
{
   return m_currentDD;
}

//+------------------------------------------------------------------+
//| 最大DD取得                                                        |
//+------------------------------------------------------------------+
double CRiskManager::GetMaxDrawdownPct()
{
   return m_maxDD;
}

//+------------------------------------------------------------------+
//| ロット削減アクティブか                                            |
//+------------------------------------------------------------------+
bool CRiskManager::IsLotReductionActive()
{
   return m_isLotReduced;
}

//+------------------------------------------------------------------+
//| ロット削減率取得                                                  |
//+------------------------------------------------------------------+
double CRiskManager::GetLotReductionFactor()
{
   if(m_isLotReduced)
      return m_fintokei.maxDrawdownReduction;
   return 1.0;
}

//+------------------------------------------------------------------+
//| 安全なロットサイズ計算                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetSafeLotSize(double slPips, double riskPercent)
{
   // 基本リスク額計算
   double balance = GetAccountBalance();
   double baseRiskAmount = balance * (riskPercent / 100.0);

   // Fintokei制約でリスク額を制限
   double dailyRemaining = GetDailyLossRemaining();
   double totalRemaining = GetTotalLossRemaining();
   double concurrentLimit = m_fintokei.initialBalance * (m_fintokei.maxConcurrentRiskPct / 100.0) - GetCurrentConcurrentRisk();

   double maxRiskAmount = MathMin(baseRiskAmount, dailyRemaining);
   maxRiskAmount = MathMin(maxRiskAmount, totalRemaining);
   maxRiskAmount = MathMin(maxRiskAmount, concurrentLimit);

   // VaR制約
   double varMaxLots = GetMaxLotByVaR(maxRiskAmount);

   // SLベースのロット計算
   double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double slDistance = slPips * m_pipSize;
   double numTicks = slDistance / tickSize;
   double lossPerLot = numTicks * tickValue;

   double slBasedLots = 0;
   if(lossPerLot > 0)
   {
      slBasedLots = maxRiskAmount / lossPerLot;
   }

   // 最小値を採用
   double finalLots = MathMin(slBasedLots, varMaxLots);

   // DD時のロット削減
   finalLots *= GetLotReductionFactor();

   // ブローカー制約で正規化
   double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

   finalLots = MathFloor(finalLots / lotStep) * lotStep;
   finalLots = MathMax(minLot, MathMin(finalLots, maxLot));

   return finalLots;
}

//+------------------------------------------------------------------+
//| リスクステータスログ出力                                          |
//+------------------------------------------------------------------+
void CRiskManager::LogRiskStatus()
{
   Print("=== リスク管理ステータス ===");
   Print("VaR(99%): ", DoubleToString(m_var99, 3), "%");
   Print("相関係数(", m_correlationSymbol, "): ", DoubleToString(m_correlation, 3));
   Print("相関リスク: ", IsCorrelationRiskHigh() ? "HIGH" : "OK");
   Print("現在DD: ", DoubleToString(m_currentDD, 2), "%");
   Print("最大DD: ", DoubleToString(m_maxDD, 2), "%");
   Print("ロット削減: ", m_isLotReduced ? "有効(50%)" : "無効");
   Print("============================");
}

//+------------------------------------------------------------------+
//| Fintokeiステータスログ出力                                        |
//+------------------------------------------------------------------+
void CRiskManager::LogFintokeiStatus()
{
   Print("=== Fintokei資金管理 ===");
   Print("初期資金: ", DoubleToString(m_fintokei.initialBalance, 0));
   Print("現在エクイティ: ", DoubleToString(GetCurrentEquity(), 0));
   Print("--- 日次損失(5%ルール) ---");
   Print("  基準エクイティ: ", DoubleToString(m_dailyInfo.equityAtReset, 0));
   Print("  日次損失率: ", DoubleToString(GetDailyLossPct(), 2), "%");
   Print("  残り許容額: ", DoubleToString(GetDailyLossRemaining(), 0));
   Print("  ステータス: ", IsDailyLossLimitOK() ? "OK" : "LIMIT");
   Print("--- 全体損失(10%ルール) ---");
   Print("  全体損失率: ", DoubleToString(GetTotalLossPct(), 2), "%");
   Print("  残り許容額: ", DoubleToString(GetTotalLossRemaining(), 0));
   Print("  ステータス: ", IsTotalLossLimitOK() ? "OK" : "LIMIT");
   Print("--- 同時リスク(3%ルール) ---");
   Print("  現在リスク: ", DoubleToString(GetCurrentConcurrentRisk(), 0));
   Print("==========================");
}

//+------------------------------------------------------------------+
