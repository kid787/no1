//+------------------------------------------------------------------+
//|                                          FintokeiRiskManager.mqh |
//|                          Fintokei Challenge Rule Compliance      |
//+------------------------------------------------------------------+
#property copyright "Fintokei Risk Manager"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Fintokei Risk Management Class                                   |
//+------------------------------------------------------------------+
class CFintokeiRiskManager
{
private:
   double   m_InitialBalance;           // 初期資金
   double   m_DailyStartEquity;         // 1日の開始時有効証拠金
   datetime m_LastDayCheck;             // 最後に日付をチェックした時刻
   double   m_MaxDailyLossPercent;      // 1日の最大損失率（デフォルト5%）
   double   m_MaxTotalLossPercent;      // 全体の最大損失率（デフォルト10%）
   double   m_MaxPositionRiskPercent;   // ポジションあたりの最大リスク（デフォルト3%）

   string   m_DataFileName;             // データ保存用ファイル名

public:
   //--- コンストラクタ
   CFintokeiRiskManager(double maxDailyLoss = 4.9, double maxTotalLoss = 9.9, double maxPosRisk = 3.0)
   {
      m_MaxDailyLossPercent = maxDailyLoss;
      m_MaxTotalLossPercent = maxTotalLoss;
      m_MaxPositionRiskPercent = maxPosRisk;
      m_DataFileName = "FintokeiData_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";

      Initialize();
   }

   //--- 初期化
   void Initialize()
   {
      // ファイルから過去のデータを読み込む
      if(!LoadData())
      {
         // 新規の場合、現在の残高を初期資金とする
         m_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         m_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_LastDayCheck = TimeCurrent();
         SaveData();
      }

      // 日付が変わっているかチェック
      CheckNewDay();
   }

   //--- 新しい日のチェック（UTC 0時 = 日本時間9時）
   void CheckNewDay()
   {
      datetime currentTime = TimeCurrent();
      MqlDateTime currentDT, lastDT;

      TimeToStruct(currentTime, currentDT);
      TimeToStruct(m_LastDayCheck, lastDT);

      // UTC日付が変わったかチェック
      if(currentDT.day != lastDT.day || currentDT.mon != lastDT.mon || currentDT.year != lastDT.year)
      {
         // 新しい日の開始
         m_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_LastDayCheck = currentTime;
         SaveData();

         Print("=== 新しい取引日開始 ===");
         Print("開始有効証拠金: ", m_DailyStartEquity);
         Print("1日の最大損失許容額: ", m_DailyStartEquity * m_MaxDailyLossPercent / 100.0);
      }
   }

   //--- データの保存
   void SaveData()
   {
      int fileHandle = FileOpen(m_DataFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(fileHandle != INVALID_HANDLE)
      {
         FileWriteString(fileHandle, DoubleToString(m_InitialBalance, 2) + "\n");
         FileWriteString(fileHandle, DoubleToString(m_DailyStartEquity, 2) + "\n");
         FileWriteString(fileHandle, IntegerToString(m_LastDayCheck) + "\n");
         FileClose(fileHandle);
      }
   }

   //--- データの読み込み
   bool LoadData()
   {
      int fileHandle = FileOpen(m_DataFileName, FILE_READ|FILE_TXT|FILE_COMMON);
      if(fileHandle == INVALID_HANDLE)
         return false;

      string line;
      line = FileReadString(fileHandle);
      m_InitialBalance = StringToDouble(line);

      line = FileReadString(fileHandle);
      m_DailyStartEquity = StringToDouble(line);

      line = FileReadString(fileHandle);
      m_LastDayCheck = (datetime)StringToInteger(line);

      FileClose(fileHandle);
      return true;
   }

   //--- 1日の損失チェック（5%ルール）
   bool CheckDailyLoss()
   {
      CheckNewDay();

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyLoss = m_DailyStartEquity - currentEquity;
      double dailyLossPercent = (dailyLoss / m_DailyStartEquity) * 100.0;

      if(dailyLossPercent >= m_MaxDailyLossPercent)
      {
         Print("警告: 1日の損失が", m_MaxDailyLossPercent, "%に達しました！");
         Print("開始証拠金: ", m_DailyStartEquity, " 現在証拠金: ", currentEquity);
         Print("損失: ", dailyLoss, " (", dailyLossPercent, "%)");
         return false;
      }

      return true;
   }

   //--- 全体の損失チェック（10%ルール）
   bool CheckTotalLoss()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double totalLoss = m_InitialBalance - currentEquity;
      double totalLossPercent = (totalLoss / m_InitialBalance) * 100.0;

      if(totalLossPercent >= m_MaxTotalLossPercent)
      {
         Print("警告: 全体の損失が", m_MaxTotalLossPercent, "%に達しました！");
         Print("初期資金: ", m_InitialBalance, " 現在証拠金: ", currentEquity);
         Print("損失: ", totalLoss, " (", totalLossPercent, "%)");
         return false;
      }

      return true;
   }

   //--- トレード可能かチェック（両方のルールを確認）
   bool CanTrade()
   {
      return CheckDailyLoss() && CheckTotalLoss();
   }

   //--- 現在の証拠金状態を取得
   double GetCurrentEquity()
   {
      return AccountInfoDouble(ACCOUNT_EQUITY);
   }

   //--- 1日の開始証拠金を取得
   double GetDailyStartEquity()
   {
      return m_DailyStartEquity;
   }

   //--- 初期資金を取得
   double GetInitialBalance()
   {
      return m_InitialBalance;
   }

   //--- 1日の残り損失許容額を取得
   double GetDailyRemainingLoss()
   {
      CheckNewDay();

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double maxLossAmount = m_DailyStartEquity * m_MaxDailyLossPercent / 100.0;
      double currentLoss = m_DailyStartEquity - currentEquity;
      double remainingLoss = maxLossAmount - currentLoss;

      return MathMax(0, remainingLoss);
   }

   //--- 全体の残り損失許容額を取得
   double GetTotalRemainingLoss()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double maxLossAmount = m_InitialBalance * m_MaxTotalLossPercent / 100.0;
      double currentLoss = m_InitialBalance - currentEquity;
      double remainingLoss = maxLossAmount - currentLoss;

      return MathMax(0, remainingLoss);
   }

   //--- 最大ロット数を計算（2つの制限の厳しい方を採用）
   double CalculateMaxLot(double slPips, double pipValue)
   {
      if(slPips <= 0 || pipValue <= 0)
         return 0.0;

      // 1日の制限に基づく最大ロット
      double dailyRemainingLoss = GetDailyRemainingLoss();
      double maxLotDaily = dailyRemainingLoss / (slPips * pipValue);

      // 全体の制限に基づく最大ロット
      double totalRemainingLoss = GetTotalRemainingLoss();
      double maxLotTotal = totalRemainingLoss / (slPips * pipValue);

      // ポジションリスク制限に基づく最大ロット
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double maxPositionRisk = currentEquity * m_MaxPositionRiskPercent / 100.0;
      double maxLotPosition = maxPositionRisk / (slPips * pipValue);

      // 最も厳しい制限を採用
      double maxLot = MathMin(maxLotDaily, MathMin(maxLotTotal, maxLotPosition));

      // ブローカーの制限に正規化
      maxLot = NormalizeLotSize(maxLot);

      return maxLot;
   }

   //--- ロットサイズの正規化
   double NormalizeLotSize(double lots)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      if(lots < minLot)
         return 0.0;  // 最小ロット未満の場合は取引しない

      if(lots > maxLot)
         lots = maxLot;

      lots = MathFloor(lots / lotStep) * lotStep;

      if(lots < minLot)
         return 0.0;

      return lots;
   }

   //--- リスク情報の表示
   void PrintRiskInfo()
   {
      CheckNewDay();

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      // 1日の損失情報
      double dailyLoss = m_DailyStartEquity - currentEquity;
      double dailyLossPercent = (dailyLoss / m_DailyStartEquity) * 100.0;
      double dailyRemaining = GetDailyRemainingLoss();

      // 全体の損失情報
      double totalLoss = m_InitialBalance - currentEquity;
      double totalLossPercent = (totalLoss / m_InitialBalance) * 100.0;
      double totalRemaining = GetTotalRemainingLoss();

      Print("=== Fintokei リスク状況 ===");
      Print("初期資金: ", m_InitialBalance);
      Print("本日開始証拠金: ", m_DailyStartEquity);
      Print("現在証拠金: ", currentEquity);
      Print("---");
      Print("1日の損失: ", dailyLoss, " (", DoubleToString(dailyLossPercent, 2), "% / ", m_MaxDailyLossPercent, "%)");
      Print("1日の残り損失許容額: ", dailyRemaining);
      Print("---");
      Print("全体の損失: ", totalLoss, " (", DoubleToString(totalLossPercent, 2), "% / ", m_MaxTotalLossPercent, "%)");
      Print("全体の残り損失許容額: ", totalRemaining);
      Print("========================");
   }
};
