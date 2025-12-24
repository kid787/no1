//+------------------------------------------------------------------+
//|                                                  MLOptimizer.mqh |
//|                            Machine Learning Entry Time Optimizer |
//|                          0:00〜9:00の15分単位スロット最適化       |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML"
#property version   "1.00"

//+------------------------------------------------------------------+
//| 定数定義                                                          |
//+------------------------------------------------------------------+
#define ML_SLOT_COUNT         36   // 0:00〜9:00の15分スロット数
#define ML_HISTORY_DAYS       30   // 過去30日間のデータ保持
#define ML_CSV_FILENAME       "GotobiML_TradeHistory.csv"

//+------------------------------------------------------------------+
//| トレード履歴構造体                                                |
//+------------------------------------------------------------------+
struct TradeRecord
{
   datetime entryTime;      // エントリー時間
   datetime exitTime;       // 決済時間
   int      slotIndex;      // スロットインデックス（0-35）
   double   profit;         // 損益
   double   pips;           // 獲得pips
   bool     isWin;          // 勝ち負け
   int      maState;        // MA状態（-1:下降、0:レンジ、1:上昇）
   int      dayOfWeek;      // 曜日
   bool     isFridayGotobi; // 金曜ゴトー日フラグ
};

//+------------------------------------------------------------------+
//| スロット統計構造体                                                |
//+------------------------------------------------------------------+
struct SlotStats
{
   int      slotIndex;      // スロットインデックス
   int      tradeCount;     // 取引回数
   int      winCount;       // 勝ち回数
   double   totalProfit;    // 累計損益
   double   winRate;        // 勝率
   double   avgProfit;      // 平均損益
   double   expectancy;     // 期待値
   double   maxDrawdown;    // 最大ドローダウン
   double   weight;         // 重み（トレンドフィルター後）
};

//+------------------------------------------------------------------+
//| 機械学習最適化クラス                                              |
//+------------------------------------------------------------------+
class CMLOptimizer
{
private:
   // トレード履歴
   TradeRecord  m_history[];
   int          m_historyCount;

   // スロット統計
   SlotStats    m_slotStats[];

   // 最適スロット
   int          m_optimalSlotIndex;
   datetime     m_optimalEntryTime;

   // 移動平均ハンドル
   int          m_ma25Handle;
   int          m_ma75Handle;

   // CSVファイルパス
   string       m_csvPath;

   // 初期化済みフラグ
   bool         m_initialized;

   // 内部メソッド
   void         InitSlotStats();
   bool         LoadHistoryFromCSV();
   bool         SaveHistoryToCSV();
   void         CalculateSlotStatistics();
   double       CalculateExpectancy(SlotStats &slot);
   int          GetSlotIndexFromTime(datetime dt);
   datetime     GetTimeFromSlotIndex(int index);
   void         ApplyTrendWeights();
   void         ApplyDayOfWeekWeights();

public:
   CMLOptimizer();
   ~CMLOptimizer();

   // 初期化
   bool Initialize(string symbol);

   // トレード記録
   bool RecordTrade(datetime entryTime, datetime exitTime, double profit, double pips, int maState, int dayOfWeek, bool isFridayGotobi);

   // 最適スロット取得
   int  GetOptimalSlotIndex();
   datetime GetOptimalEntryTime(datetime tradingDate);

   // 統計取得
   double GetSlotExpectancy(int slotIndex);
   double GetSlotWinRate(int slotIndex);
   int    GetSlotTradeCount(int slotIndex);

   // 現在のMAトレンド状態取得
   int GetCurrentMAState(string symbol);

   // ログ出力
   void LogMLDecision();
   void LogSlotStatistics();

   // バックテスト対応
   bool IsOptimizationMode();
   void SetTestMode(bool isTest);

   // データクリア
   void ClearHistory();
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CMLOptimizer::CMLOptimizer()
{
   m_historyCount = 0;
   m_optimalSlotIndex = 24; // デフォルト: 6:00 JST
   m_initialized = false;
   m_ma25Handle = INVALID_HANDLE;
   m_ma75Handle = INVALID_HANDLE;
   m_csvPath = "";
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CMLOptimizer::~CMLOptimizer()
{
   // 履歴を保存
   if(m_initialized && m_historyCount > 0)
   {
      SaveHistoryToCSV();
   }

   // ハンドル解放
   if(m_ma25Handle != INVALID_HANDLE)
      IndicatorRelease(m_ma25Handle);
   if(m_ma75Handle != INVALID_HANDLE)
      IndicatorRelease(m_ma75Handle);

   ArrayFree(m_history);
   ArrayFree(m_slotStats);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CMLOptimizer::Initialize(string symbol)
{
   // スロット統計初期化
   InitSlotStats();

   // 移動平均ハンドル作成
   m_ma25Handle = iMA(symbol, PERIOD_D1, 25, 0, MODE_SMA, PRICE_CLOSE);
   m_ma75Handle = iMA(symbol, PERIOD_D1, 75, 0, MODE_SMA, PRICE_CLOSE);

   if(m_ma25Handle == INVALID_HANDLE || m_ma75Handle == INVALID_HANDLE)
   {
      Print("MLOptimizer: MAインジケーター作成失敗");
      return false;
   }

   // CSVから履歴読み込み
   m_csvPath = ML_CSV_FILENAME;
   LoadHistoryFromCSV();

   // 統計計算
   if(m_historyCount > 0)
   {
      CalculateSlotStatistics();
   }

   m_initialized = true;

   Print("MLOptimizer: 初期化完了 履歴レコード数=", m_historyCount);

   return true;
}

//+------------------------------------------------------------------+
//| スロット統計初期化                                                |
//+------------------------------------------------------------------+
void CMLOptimizer::InitSlotStats()
{
   ArrayResize(m_slotStats, ML_SLOT_COUNT);

   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      m_slotStats[i].slotIndex = i;
      m_slotStats[i].tradeCount = 0;
      m_slotStats[i].winCount = 0;
      m_slotStats[i].totalProfit = 0;
      m_slotStats[i].winRate = 0;
      m_slotStats[i].avgProfit = 0;
      m_slotStats[i].expectancy = 0;
      m_slotStats[i].maxDrawdown = 0;
      m_slotStats[i].weight = 1.0;
   }
}

//+------------------------------------------------------------------+
//| スロットインデックスから時刻を取得                                |
//+------------------------------------------------------------------+
datetime CMLOptimizer::GetTimeFromSlotIndex(int index)
{
   // 0:00〜9:00を15分刻みで36スロット
   int hours = index / 4;
   int minutes = (index % 4) * 15;

   MqlDateTime mdt;
   TimeCurrent();
   TimeToStruct(TimeCurrent(), mdt);

   mdt.hour = hours;
   mdt.min = minutes;
   mdt.sec = 0;

   return StructToTime(mdt);
}

//+------------------------------------------------------------------+
//| 時刻からスロットインデックスを取得                                |
//+------------------------------------------------------------------+
int CMLOptimizer::GetSlotIndexFromTime(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   int hour = mdt.hour;
   int minute = mdt.min;

   // 日本時間0:00〜9:00の範囲チェック
   if(hour >= 9)
      return ML_SLOT_COUNT - 1; // 最後のスロット

   int slotIndex = (hour * 4) + (minute / 15);

   return MathMin(MathMax(slotIndex, 0), ML_SLOT_COUNT - 1);
}

//+------------------------------------------------------------------+
//| トレード記録                                                      |
//+------------------------------------------------------------------+
bool CMLOptimizer::RecordTrade(datetime entryTime, datetime exitTime,
                               double profit, double pips,
                               int maState, int dayOfWeek, bool isFridayGotobi)
{
   // 古いデータを削除（30日以上前）
   datetime cutoffTime = TimeCurrent() - (ML_HISTORY_DAYS * 86400);

   int validCount = 0;
   for(int i = 0; i < m_historyCount; i++)
   {
      if(m_history[i].entryTime >= cutoffTime)
      {
         if(validCount != i)
            m_history[validCount] = m_history[i];
         validCount++;
      }
   }

   m_historyCount = validCount;
   ArrayResize(m_history, m_historyCount + 1);

   // 新しいレコード追加
   TradeRecord record;
   record.entryTime = entryTime;
   record.exitTime = exitTime;
   record.slotIndex = GetSlotIndexFromTime(entryTime);
   record.profit = profit;
   record.pips = pips;
   record.isWin = (profit > 0);
   record.maState = maState;
   record.dayOfWeek = dayOfWeek;
   record.isFridayGotobi = isFridayGotobi;

   m_history[m_historyCount] = record;
   m_historyCount++;

   // 統計再計算
   CalculateSlotStatistics();

   // CSVに保存
   SaveHistoryToCSV();

   Print("MLOptimizer: トレード記録 スロット=", record.slotIndex,
         " 損益=", DoubleToString(profit, 2),
         " 勝敗=", record.isWin ? "勝ち" : "負け");

   return true;
}

//+------------------------------------------------------------------+
//| スロット統計計算                                                  |
//+------------------------------------------------------------------+
void CMLOptimizer::CalculateSlotStatistics()
{
   // 統計リセット
   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      m_slotStats[i].tradeCount = 0;
      m_slotStats[i].winCount = 0;
      m_slotStats[i].totalProfit = 0;
      m_slotStats[i].maxDrawdown = 0;
   }

   // 各スロットの統計計算
   for(int i = 0; i < m_historyCount; i++)
   {
      int slotIdx = m_history[i].slotIndex;

      m_slotStats[slotIdx].tradeCount++;
      if(m_history[i].isWin)
         m_slotStats[slotIdx].winCount++;
      m_slotStats[slotIdx].totalProfit += m_history[i].profit;

      // ドローダウン計算
      if(m_history[i].profit < 0)
      {
         double dd = MathAbs(m_history[i].profit);
         if(dd > m_slotStats[slotIdx].maxDrawdown)
            m_slotStats[slotIdx].maxDrawdown = dd;
      }
   }

   // 勝率・平均損益・期待値計算
   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      if(m_slotStats[i].tradeCount > 0)
      {
         m_slotStats[i].winRate = (double)m_slotStats[i].winCount / m_slotStats[i].tradeCount * 100;
         m_slotStats[i].avgProfit = m_slotStats[i].totalProfit / m_slotStats[i].tradeCount;
         m_slotStats[i].expectancy = CalculateExpectancy(m_slotStats[i]);
      }
   }

   // トレンドフィルターと曜日の重み付け適用
   ApplyTrendWeights();
   ApplyDayOfWeekWeights();

   // 最適スロット更新
   double maxWeightedExpectancy = -999999;
   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      double weightedExp = m_slotStats[i].expectancy * m_slotStats[i].weight;
      if(weightedExp > maxWeightedExpectancy && m_slotStats[i].tradeCount >= 3)
      {
         maxWeightedExpectancy = weightedExp;
         m_optimalSlotIndex = i;
      }
   }

   Print("MLOptimizer: 最適スロット更新 スロット=", m_optimalSlotIndex,
         " 期待値=", DoubleToString(maxWeightedExpectancy, 2));
}

//+------------------------------------------------------------------+
//| 期待値計算                                                        |
//+------------------------------------------------------------------+
double CMLOptimizer::CalculateExpectancy(SlotStats &slot)
{
   if(slot.tradeCount == 0)
      return 0;

   // 期待値 = (勝率 × 平均利益) - ((1-勝率) × 平均損失)
   double winRate = slot.winRate / 100;
   double avgWin = 0;
   double avgLoss = 0;
   int winCount = 0;
   int lossCount = 0;

   // 履歴から平均勝ち/負け計算
   for(int i = 0; i < m_historyCount; i++)
   {
      if(m_history[i].slotIndex == slot.slotIndex)
      {
         if(m_history[i].isWin)
         {
            avgWin += m_history[i].profit;
            winCount++;
         }
         else
         {
            avgLoss += MathAbs(m_history[i].profit);
            lossCount++;
         }
      }
   }

   if(winCount > 0)
      avgWin /= winCount;
   if(lossCount > 0)
      avgLoss /= lossCount;

   double expectancy = (winRate * avgWin) - ((1 - winRate) * avgLoss);

   return expectancy;
}

//+------------------------------------------------------------------+
//| トレンドフィルター重み付け                                        |
//+------------------------------------------------------------------+
void CMLOptimizer::ApplyTrendWeights()
{
   // MA25 > MA75 なら上昇トレンド（ロング有利）
   double ma25[], ma75[];
   ArraySetAsSeries(ma25, true);
   ArraySetAsSeries(ma75, true);

   if(CopyBuffer(m_ma25Handle, 0, 0, 3, ma25) < 3)
      return;
   if(CopyBuffer(m_ma75Handle, 0, 0, 3, ma75) < 3)
      return;

   int trendState = 0;
   if(ma25[0] > ma75[0])
      trendState = 1;  // 上昇トレンド
   else if(ma25[0] < ma75[0])
      trendState = -1; // 下降トレンド

   // スロットごとのトレンド順張りスコアで重み付け
   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      double trendScore = 0;
      int count = 0;

      for(int j = 0; j < m_historyCount; j++)
      {
         if(m_history[j].slotIndex == i)
         {
            // MAトレンドに沿った取引の成績
            if(m_history[j].maState == trendState && m_history[j].isWin)
            {
               trendScore += 1.0;
            }
            else if(m_history[j].maState != trendState && !m_history[j].isWin)
            {
               trendScore += 0.5; // 逆張り負けは参考データ
            }
            count++;
         }
      }

      if(count > 0)
      {
         // 重み付け（0.5〜1.5の範囲）
         m_slotStats[i].weight = 0.5 + (trendScore / count);
      }
   }
}

//+------------------------------------------------------------------+
//| 曜日別重み付け                                                    |
//+------------------------------------------------------------------+
void CMLOptimizer::ApplyDayOfWeekWeights()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   int currentDayOfWeek = mdt.day_of_week;

   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      // 月曜日（流動性低下リスク）
      if(currentDayOfWeek == 1)
      {
         // 早朝スロット（6-7時 = スロット24-28）の重みを下げる
         if(i >= 24 && i <= 28)
         {
            m_slotStats[i].weight *= 0.7;
         }
      }

      // 金曜ゴトー日の履歴から重み付け
      int fridayWins = 0;
      int fridayCount = 0;

      for(int j = 0; j < m_historyCount; j++)
      {
         if(m_history[j].slotIndex == i && m_history[j].isFridayGotobi)
         {
            fridayCount++;
            if(m_history[j].isWin)
               fridayWins++;
         }
      }

      // 金曜ゴトー日の勝率が高い場合、重みを上げる
      if(fridayCount >= 3 && currentDayOfWeek == 5)
      {
         double fridayWinRate = (double)fridayWins / fridayCount;
         if(fridayWinRate > 0.7)
         {
            m_slotStats[i].weight *= 1.3; // 30%重みアップ
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 最適スロットインデックス取得                                      |
//+------------------------------------------------------------------+
int CMLOptimizer::GetOptimalSlotIndex()
{
   return m_optimalSlotIndex;
}

//+------------------------------------------------------------------+
//| 最適エントリー時間取得                                            |
//+------------------------------------------------------------------+
datetime CMLOptimizer::GetOptimalEntryTime(datetime tradingDate)
{
   MqlDateTime mdt;
   TimeToStruct(tradingDate, mdt);

   int hours = m_optimalSlotIndex / 4;
   int minutes = (m_optimalSlotIndex % 4) * 15;

   mdt.hour = hours;
   mdt.min = minutes;
   mdt.sec = 0;

   return StructToTime(mdt);
}

//+------------------------------------------------------------------+
//| スロット期待値取得                                                |
//+------------------------------------------------------------------+
double CMLOptimizer::GetSlotExpectancy(int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= ML_SLOT_COUNT)
      return 0;

   return m_slotStats[slotIndex].expectancy;
}

//+------------------------------------------------------------------+
//| スロット勝率取得                                                  |
//+------------------------------------------------------------------+
double CMLOptimizer::GetSlotWinRate(int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= ML_SLOT_COUNT)
      return 0;

   return m_slotStats[slotIndex].winRate;
}

//+------------------------------------------------------------------+
//| スロット取引回数取得                                              |
//+------------------------------------------------------------------+
int CMLOptimizer::GetSlotTradeCount(int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= ML_SLOT_COUNT)
      return 0;

   return m_slotStats[slotIndex].tradeCount;
}

//+------------------------------------------------------------------+
//| 現在のMAトレンド状態取得                                          |
//+------------------------------------------------------------------+
int CMLOptimizer::GetCurrentMAState(string symbol)
{
   double ma25[], ma75[];
   ArraySetAsSeries(ma25, true);
   ArraySetAsSeries(ma75, true);

   if(CopyBuffer(m_ma25Handle, 0, 0, 3, ma25) < 3)
      return 0;
   if(CopyBuffer(m_ma75Handle, 0, 0, 3, ma75) < 3)
      return 0;

   if(ma25[0] > ma75[0])
      return 1;  // 上昇トレンド
   else if(ma25[0] < ma75[0])
      return -1; // 下降トレンド
   else
      return 0;  // レンジ
}

//+------------------------------------------------------------------+
//| CSV読み込み                                                       |
//+------------------------------------------------------------------+
bool CMLOptimizer::LoadHistoryFromCSV()
{
   int fileHandle = FileOpen(m_csvPath, FILE_READ | FILE_CSV | FILE_COMMON, ',');

   if(fileHandle == INVALID_HANDLE)
   {
      Print("MLOptimizer: 履歴ファイルなし（新規作成予定）");
      return false;
   }

   // ヘッダースキップ
   if(!FileIsEnding(fileHandle))
   {
      FileReadString(fileHandle); // entryTime
      FileReadString(fileHandle); // exitTime
      FileReadString(fileHandle); // slotIndex
      FileReadString(fileHandle); // profit
      FileReadString(fileHandle); // pips
      FileReadString(fileHandle); // isWin
      FileReadString(fileHandle); // maState
      FileReadString(fileHandle); // dayOfWeek
      FileReadString(fileHandle); // isFridayGotobi
   }

   // 30日前のカットオフ
   datetime cutoffTime = TimeCurrent() - (ML_HISTORY_DAYS * 86400);

   m_historyCount = 0;
   ArrayResize(m_history, 100);

   while(!FileIsEnding(fileHandle))
   {
      TradeRecord record;

      string entryTimeStr = FileReadString(fileHandle);
      if(StringLen(entryTimeStr) == 0)
         break;

      record.entryTime = StringToTime(entryTimeStr);
      record.exitTime = StringToTime(FileReadString(fileHandle));
      record.slotIndex = (int)StringToInteger(FileReadString(fileHandle));
      record.profit = StringToDouble(FileReadString(fileHandle));
      record.pips = StringToDouble(FileReadString(fileHandle));
      record.isWin = (FileReadString(fileHandle) == "1");
      record.maState = (int)StringToInteger(FileReadString(fileHandle));
      record.dayOfWeek = (int)StringToInteger(FileReadString(fileHandle));
      record.isFridayGotobi = (FileReadString(fileHandle) == "1");

      // 30日以内のデータのみ保持
      if(record.entryTime >= cutoffTime)
      {
         if(m_historyCount >= ArraySize(m_history))
            ArrayResize(m_history, m_historyCount + 50);

         m_history[m_historyCount] = record;
         m_historyCount++;
      }
   }

   FileClose(fileHandle);

   Print("MLOptimizer: CSV読み込み完了 レコード数=", m_historyCount);

   return true;
}

//+------------------------------------------------------------------+
//| CSV保存                                                           |
//+------------------------------------------------------------------+
bool CMLOptimizer::SaveHistoryToCSV()
{
   int fileHandle = FileOpen(m_csvPath, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');

   if(fileHandle == INVALID_HANDLE)
   {
      Print("MLOptimizer: CSVファイル書き込み失敗");
      return false;
   }

   // ヘッダー
   FileWrite(fileHandle, "entryTime", "exitTime", "slotIndex", "profit",
             "pips", "isWin", "maState", "dayOfWeek", "isFridayGotobi");

   // データ
   for(int i = 0; i < m_historyCount; i++)
   {
      FileWrite(fileHandle,
                TimeToString(m_history[i].entryTime, TIME_DATE | TIME_MINUTES),
                TimeToString(m_history[i].exitTime, TIME_DATE | TIME_MINUTES),
                IntegerToString(m_history[i].slotIndex),
                DoubleToString(m_history[i].profit, 2),
                DoubleToString(m_history[i].pips, 1),
                m_history[i].isWin ? "1" : "0",
                IntegerToString(m_history[i].maState),
                IntegerToString(m_history[i].dayOfWeek),
                m_history[i].isFridayGotobi ? "1" : "0");
   }

   FileClose(fileHandle);

   return true;
}

//+------------------------------------------------------------------+
//| ML判断ログ出力                                                    |
//+------------------------------------------------------------------+
void CMLOptimizer::LogMLDecision()
{
   Print("=== ML最適化判断 ===");
   Print("履歴データ数: ", m_historyCount);
   Print("最適スロット: ", m_optimalSlotIndex, " (", (m_optimalSlotIndex / 4), ":", (m_optimalSlotIndex % 4) * 15, ")");
   Print("最適スロット期待値: ", DoubleToString(m_slotStats[m_optimalSlotIndex].expectancy, 2));
   Print("最適スロット勝率: ", DoubleToString(m_slotStats[m_optimalSlotIndex].winRate, 1), "%");
   Print("最適スロット取引回数: ", m_slotStats[m_optimalSlotIndex].tradeCount);
   Print("最適スロット重み: ", DoubleToString(m_slotStats[m_optimalSlotIndex].weight, 3));
   Print("現在MAトレンド: ", GetCurrentMAState("USDJPY"));
   Print("====================");
}

//+------------------------------------------------------------------+
//| スロット統計ログ出力                                              |
//+------------------------------------------------------------------+
void CMLOptimizer::LogSlotStatistics()
{
   Print("=== スロット統計 ===");
   for(int i = 0; i < ML_SLOT_COUNT; i++)
   {
      if(m_slotStats[i].tradeCount > 0)
      {
         Print(StringFormat("スロット%02d (%02d:%02d) - 取引:%d 勝率:%.1f%% 期待値:%.2f 重み:%.3f",
                            i, i / 4, (i % 4) * 15,
                            m_slotStats[i].tradeCount,
                            m_slotStats[i].winRate,
                            m_slotStats[i].expectancy,
                            m_slotStats[i].weight));
      }
   }
   Print("====================");
}

//+------------------------------------------------------------------+
//| 最適化モード判定                                                  |
//+------------------------------------------------------------------+
bool CMLOptimizer::IsOptimizationMode()
{
   return (bool)MQLInfoInteger(MQL_OPTIMIZATION);
}

//+------------------------------------------------------------------+
//| テストモード設定                                                  |
//+------------------------------------------------------------------+
void CMLOptimizer::SetTestMode(bool isTest)
{
   // テストモード時は実データを読み込まない
   if(isTest)
   {
      m_historyCount = 0;
      ArrayResize(m_history, 0);
   }
}

//+------------------------------------------------------------------+
//| 履歴クリア                                                        |
//+------------------------------------------------------------------+
void CMLOptimizer::ClearHistory()
{
   m_historyCount = 0;
   ArrayResize(m_history, 0);
   InitSlotStats();
   FileDelete(m_csvPath, FILE_COMMON);
   Print("MLOptimizer: 履歴クリア完了");
}

//+------------------------------------------------------------------+
