//+------------------------------------------------------------------+
//|                                               GotobiNakaneEA.mq5 |
//|                           ゴトー日仲値トレード＋月末アノマリーEA |
//|                      Fintokeiチャレンジプラン対応 資金管理付き   |
//+------------------------------------------------------------------+
#property copyright "Gotobi Nakane Trading EA"
#property link      ""
#property version   "1.01"
#property strict

//+------------------------------------------------------------------+
//| 入力パラメータ                                                   |
//+------------------------------------------------------------------+
input group "===== 基本設定 ====="
input double   InitialBalance       = 0;         // 初期資金（0=自動検出）
input double   DailyLossLimit       = 4.9;       // 1日の最大損失率(%) ※5%未満に設定
input double   TotalLossLimit       = 9.9;       // 全体の最大損失率(%) ※10%未満に設定
input double   MaxRiskPerTrade      = 2.0;       // 1トレードあたりの最大リスク(%)
input int      MagicNumber          = 20251222;  // マジックナンバー

input group "===== ロジック1: 仲値ロング ====="
input bool     UseLogic1            = true;      // ロジック1を使用
input int      Logic1_EntryHour     = 3;         // エントリー時間（時）※日本時間
input int      Logic1_EntryMinute   = 55;        // エントリー時間（分）
input int      Logic1_ExitHour      = 9;         // 決済時間（時）
input int      Logic1_ExitMinute    = 55;        // 決済時間（分）
input double   Logic1_SL_Pips       = 30;        // 損切り幅（Pips）
input double   Logic1_TP_Pips       = 60;        // 利確幅（Pips）

input group "===== ロジック2: 仲値ショート ====="
input bool     UseLogic2            = true;      // ロジック2を使用
input int      Logic2_EntryHour     = 9;         // エントリー時間（時）
input int      Logic2_EntryMinute   = 55;        // エントリー時間（分）
input int      Logic2_ExitHour      = 10;        // 決済時間（時）
input int      Logic2_ExitMinute    = 25;        // 決済時間（分）
input double   Logic2_SL_Pips       = 20;        // 損切り幅（Pips）
input double   Logic2_TP_Pips       = 30;        // 利確幅（Pips）

input group "===== ロジック3-A: 月末アノマリーSELL ====="
input bool     UseLogic3A           = true;      // ロジック3-Aを使用
input int      Logic3A_EntryHour    = 9;         // エントリー時間（時）
input int      Logic3A_EntryMinute  = 55;        // エントリー時間（分）
input int      Logic3A_ExitHour     = 15;        // 決済時間（時）
input int      Logic3A_ExitMinute   = 0;         // 決済時間（分）
input double   Logic3A_SL_Pips      = 40;        // 損切り幅（Pips）
input double   Logic3A_TP_Pips      = 80;        // 利確幅（Pips）

input group "===== ロジック3-B: 月末アノマリーBUY ====="
input bool     UseLogic3B           = true;      // ロジック3-Bを使用
input int      Logic3B_EntryHour    = 16;        // エントリー時間（時）
input int      Logic3B_EntryMinute  = 0;         // エントリー時間（分）
input int      Logic3B_ExitHour     = 23;        // 決済時間（時）
input int      Logic3B_ExitMinute   = 0;         // 決済時間（分）
input double   Logic3B_SL_Pips      = 50;        // 損切り幅（Pips）
input double   Logic3B_TP_Pips      = 100;       // 利確幅（Pips）

input group "===== タイムゾーン設定 ====="
input int      ServerGMTOffset      = 2;         // サーバーのGMTオフセット（冬時間）
input int      JapanGMTOffset       = 9;         // 日本のGMTオフセット

input group "===== フィルター設定 ====="
input bool     FridayGotobiOnly     = false;     // 金曜日のゴトー日のみ取引
input bool     SkipHolidayGotobi    = true;      // 土日がゴトー日の場合は前日金曜に取引

//+------------------------------------------------------------------+
//| グローバル変数                                                   |
//+------------------------------------------------------------------+
double g_InitialBalance;           // 初期資金
double g_DailyStartEquity;         // 1日の開始時有効証拠金（UTC 0時基準）
datetime g_LastDailyReset;         // 最後の日次リセット時刻
bool g_Logic1Executed;             // ロジック1実行済みフラグ
bool g_Logic2Executed;             // ロジック2実行済みフラグ
bool g_Logic3AExecuted;            // ロジック3-A実行済みフラグ
bool g_Logic3BExecuted;            // ロジック3-B実行済みフラグ
bool g_TradingBlocked;             // 取引禁止フラグ

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 初期資金の設定
   if(InitialBalance <= 0)
      g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   else
      g_InitialBalance = InitialBalance;

   //--- 日次開始証拠金の初期化
   g_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_LastDailyReset = 0;

   //--- フラグの初期化
   g_Logic1Executed = false;
   g_Logic2Executed = false;
   g_Logic3AExecuted = false;
   g_Logic3BExecuted = false;
   g_TradingBlocked = false;

   //--- シンボル情報の確認
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      Print("Error: Symbol ", _Symbol, " is not available for trading");
      return(INIT_FAILED);
   }

   Print("=== ゴトー日仲値トレードEA 起動 ===");
   Print("初期資金: ", DoubleToString(g_InitialBalance, 0), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("1日最大損失: ", DoubleToString(DailyLossLimit, 1), "%");
   Print("全体最大損失: ", DoubleToString(TotalLossLimit, 1), "%");
   Print("対象シンボル: ", _Symbol);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== ゴトー日仲値トレードEA 停止 ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 日次リセットの確認（UTC 0時 = 日本時間9時）
   CheckDailyReset();

   //--- 損失管理の確認
   if(!CheckRiskLimits())
   {
      //--- 損失制限に達した場合は全ポジション決済して取引停止
      if(!g_TradingBlocked)
      {
         CloseAllPositions("損失制限到達");
         g_TradingBlocked = true;
         Print("!!! 取引停止: 損失制限に達しました !!!");
      }
      return;
   }

   //--- 現在時刻を日本時間に変換
   datetime serverTime = TimeCurrent();
   datetime japanTime = ConvertToJapanTime(serverTime);

   MqlDateTime dt;
   TimeToStruct(japanTime, dt);

   //--- ゴトー日・月末の判定
   bool isGotobi = IsGotobiDay(japanTime);
   bool isMonthEnd = IsMonthEndDay(japanTime);

   //--- 金曜日ゴトー日のみフィルター
   if(FridayGotobiOnly && isGotobi && dt.day_of_week != 5)
      isGotobi = false;

   //--- 時刻チェック用の変数
   int currentMinuteOfDay = dt.hour * 60 + dt.min;

   //--- ロジック1: 仲値ロング（ゴトー日）
   if(UseLogic1 && isGotobi && !g_Logic1Executed)
   {
      int entryMinute = Logic1_EntryHour * 60 + Logic1_EntryMinute;
      int exitMinute = Logic1_ExitHour * 60 + Logic1_ExitMinute;

      //--- エントリー判定
      if(currentMinuteOfDay == entryMinute)
      {
         if(ExecuteTrade(ORDER_TYPE_BUY, Logic1_SL_Pips, Logic1_TP_Pips, "Logic1_Nakane_Long"))
         {
            g_Logic1Executed = true;
            Print("ロジック1: 仲値ロングエントリー完了");
         }
      }
      //--- 時間決済判定
      if(currentMinuteOfDay >= exitMinute)
      {
         ClosePositionsByComment("Logic1_Nakane_Long");
         g_Logic1Executed = true; // エントリーしていなくても時間過ぎたらフラグ立てる
      }
   }

   //--- ロジック2: 仲値ショート（ゴトー日）
   if(UseLogic2 && isGotobi && !g_Logic2Executed)
   {
      int entryMinute = Logic2_EntryHour * 60 + Logic2_EntryMinute;
      int exitMinute = Logic2_ExitHour * 60 + Logic2_ExitMinute;

      if(currentMinuteOfDay == entryMinute)
      {
         if(ExecuteTrade(ORDER_TYPE_SELL, Logic2_SL_Pips, Logic2_TP_Pips, "Logic2_Nakane_Short"))
         {
            g_Logic2Executed = true;
            Print("ロジック2: 仲値ショートエントリー完了");
         }
      }
      if(currentMinuteOfDay >= exitMinute)
      {
         ClosePositionsByComment("Logic2_Nakane_Short");
         g_Logic2Executed = true;
      }
   }

   //--- ロジック3-A: 月末アノマリーSELL
   if(UseLogic3A && isMonthEnd && !g_Logic3AExecuted)
   {
      int entryMinute = Logic3A_EntryHour * 60 + Logic3A_EntryMinute;
      int exitMinute = Logic3A_ExitHour * 60 + Logic3A_ExitMinute;

      if(currentMinuteOfDay == entryMinute)
      {
         if(ExecuteTrade(ORDER_TYPE_SELL, Logic3A_SL_Pips, Logic3A_TP_Pips, "Logic3A_MonthEnd_Sell"))
         {
            g_Logic3AExecuted = true;
            Print("ロジック3-A: 月末アノマリーSELLエントリー完了");
         }
      }
      if(currentMinuteOfDay >= exitMinute)
      {
         ClosePositionsByComment("Logic3A_MonthEnd_Sell");
         g_Logic3AExecuted = true;
      }
   }

   //--- ロジック3-B: 月末アノマリーBUY
   if(UseLogic3B && isMonthEnd && !g_Logic3BExecuted)
   {
      int entryMinute = Logic3B_EntryHour * 60 + Logic3B_EntryMinute;
      int exitMinute = Logic3B_ExitHour * 60 + Logic3B_ExitMinute;

      if(currentMinuteOfDay == entryMinute)
      {
         if(ExecuteTrade(ORDER_TYPE_BUY, Logic3B_SL_Pips, Logic3B_TP_Pips, "Logic3B_MonthEnd_Buy"))
         {
            g_Logic3BExecuted = true;
            Print("ロジック3-B: 月末アノマリーBUYエントリー完了");
         }
      }
      if(currentMinuteOfDay >= exitMinute)
      {
         ClosePositionsByComment("Logic3B_MonthEnd_Buy");
         g_Logic3BExecuted = true;
      }
   }

   //--- リアルタイム損失監視（含み損チェック）
   MonitorUnrealizedLoss();
}

//+------------------------------------------------------------------+
//| 日次リセットの確認                                               |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime serverTime = TimeCurrent();
   datetime utcTime = serverTime - ServerGMTOffset * 3600;

   MqlDateTime dt;
   TimeToStruct(utcTime, dt);

   //--- UTC 0時を過ぎたらリセット
   datetime todayUTC0 = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

   if(g_LastDailyReset < todayUTC0)
   {
      g_DailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_LastDailyReset = todayUTC0;

      //--- フラグのリセット
      g_Logic1Executed = false;
      g_Logic2Executed = false;
      g_Logic3AExecuted = false;
      g_Logic3BExecuted = false;
      g_TradingBlocked = false;

      Print("=== 日次リセット ===");
      Print("本日開始時有効証拠金: ", DoubleToString(g_DailyStartEquity, 2));
   }
}

//+------------------------------------------------------------------+
//| リスク制限の確認                                                 |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 1日の最大損失率チェック
   double dailyLossPercent = (g_DailyStartEquity - currentEquity) / g_DailyStartEquity * 100.0;
   if(dailyLossPercent >= DailyLossLimit)
   {
      Print("!!! 1日の最大損失率到達: ", DoubleToString(dailyLossPercent, 2), "% !!!");
      return false;
   }

   //--- 全体の最大損失率チェック
   double totalLossPercent = (g_InitialBalance - currentEquity) / g_InitialBalance * 100.0;
   if(totalLossPercent >= TotalLossLimit)
   {
      Print("!!! 全体の最大損失率到達: ", DoubleToString(totalLossPercent, 2), "% !!!");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 含み損のリアルタイム監視                                         |
//+------------------------------------------------------------------+
void MonitorUnrealizedLoss()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 日次損失の90%に達したら警告＆ポジション縮小
   double dailyLossPercent = (g_DailyStartEquity - currentEquity) / g_DailyStartEquity * 100.0;
   double warningThreshold = DailyLossLimit * 0.9;

   if(dailyLossPercent >= warningThreshold && dailyLossPercent < DailyLossLimit)
   {
      Print("警告: 日次損失率が警戒レベルに到達: ", DoubleToString(dailyLossPercent, 2), "%");
      //--- 最も損失が大きいポジションを決済
      CloseWorstPosition();
   }
}

//+------------------------------------------------------------------+
//| サーバー時間を日本時間に変換                                     |
//+------------------------------------------------------------------+
datetime ConvertToJapanTime(datetime serverTime)
{
   //--- サーバー時間からUTCを求め、日本時間に変換
   int diffHours = JapanGMTOffset - ServerGMTOffset;
   return serverTime + diffHours * 3600;
}

//+------------------------------------------------------------------+
//| ゴトー日判定                                                     |
//+------------------------------------------------------------------+
bool IsGotobiDay(datetime japanTime)
{
   MqlDateTime dt;
   TimeToStruct(japanTime, dt);

   int day = dt.day;
   int dayOfWeek = dt.day_of_week;

   //--- 土日は取引しない
   if(dayOfWeek == 0 || dayOfWeek == 6)
      return false;

   //--- 5の倍数の日（5, 10, 15, 20, 25, 30日）
   bool is5thMultiple = (day == 5 || day == 10 || day == 15 || day == 20 || day == 25 || day == 30);

   if(is5thMultiple)
      return true;

   //--- 土日がゴトー日の場合、前営業日（金曜日）に取引
   if(SkipHolidayGotobi && dayOfWeek == 5) // 金曜日
   {
      //--- 翌日（土曜）がゴトー日かチェック
      int tomorrow = day + 1;
      if(tomorrow == 5 || tomorrow == 10 || tomorrow == 15 || tomorrow == 20 || tomorrow == 25 || tomorrow == 30)
         return true;

      //--- 翌々日（日曜）がゴトー日かチェック
      int dayAfter = day + 2;
      if(dayAfter == 5 || dayAfter == 10 || dayAfter == 15 || dayAfter == 20 || dayAfter == 25 || dayAfter == 30)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 月末日判定                                                       |
//+------------------------------------------------------------------+
bool IsMonthEndDay(datetime japanTime)
{
   MqlDateTime dt;
   TimeToStruct(japanTime, dt);

   int dayOfWeek = dt.day_of_week;

   //--- 土日は取引しない
   if(dayOfWeek == 0 || dayOfWeek == 6)
      return false;

   //--- 月の最終営業日かチェック
   int lastDayOfMonth = GetLastDayOfMonth(dt.year, dt.mon);

   //--- 最終日が土日の場合は前営業日
   MqlDateTime lastDayDt;
   datetime lastDayTime = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, lastDayOfMonth));
   TimeToStruct(lastDayTime, lastDayDt);

   int lastDayWeekday = lastDayDt.day_of_week;
   int actualLastBusinessDay = lastDayOfMonth;

   if(lastDayWeekday == 0) // 日曜
      actualLastBusinessDay = lastDayOfMonth - 2;
   else if(lastDayWeekday == 6) // 土曜
      actualLastBusinessDay = lastDayOfMonth - 1;

   //--- 月末当日
   if(dt.day == actualLastBusinessDay)
      return true;

   //--- 月末前日も含める（ロンドンフィックス対応）
   if(dt.day == actualLastBusinessDay - 1 && dayOfWeek != 5) // 金曜除く
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 月の最終日を取得                                                 |
//+------------------------------------------------------------------+
int GetLastDayOfMonth(int year, int month)
{
   int daysInMonth[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

   //--- うるう年チェック
   if(month == 2)
   {
      if((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0))
         return 29;
   }

   return daysInMonth[month - 1];
}

//+------------------------------------------------------------------+
//| ロットサイズ計算（リスクベース）                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 残りの許容損失を計算
   double remainingDailyLoss = g_DailyStartEquity * (DailyLossLimit / 100.0) - (g_DailyStartEquity - currentEquity);
   double remainingTotalLoss = g_InitialBalance * (TotalLossLimit / 100.0) - (g_InitialBalance - currentEquity);

   //--- より厳しい方を採用
   double maxAllowedLoss = MathMin(remainingDailyLoss, remainingTotalLoss);

   //--- さらにトレードリスク制限を適用
   double tradeRiskAmount = accountBalance * (MaxRiskPerTrade / 100.0);
   maxAllowedLoss = MathMin(maxAllowedLoss, tradeRiskAmount);

   //--- 負の値チェック
   if(maxAllowedLoss <= 0)
      return 0;

   //--- pip値計算
   double pipSize = GetPipSize();
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;
   double lossPerLot = numTicks * tickValue;

   if(lossPerLot <= 0)
      return 0;

   double calculatedLots = maxAllowedLoss / lossPerLot;

   //--- ロットサイズの正規化
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   calculatedLots = MathFloor(calculatedLots / lotStep) * lotStep;

   if(calculatedLots < minLot)
      calculatedLots = minLot;
   if(calculatedLots > maxLot)
      calculatedLots = maxLot;

   return calculatedLots;
}

//+------------------------------------------------------------------+
//| サポートされるフィリングモードを取得                             |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   //--- シンボルがサポートするフィリングモードを取得
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   //--- ORDER_FILLING_FOK をサポートしているか
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   //--- ORDER_FILLING_IOC をサポートしているか
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   //--- どちらもサポートしていない場合は RETURN（部分約定許可）
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Pip サイズの取得                                                 |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //--- XAUUSD や JPY ペアなど、桁数に応じてpipサイズを調整
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
   {
      // 金の場合は0.1ドル = 1 pip として扱う
      return 0.1;
   }
   else if(digits == 3 || digits == 5)
   {
      return point * 10.0;
   }
   else
   {
      return point;
   }
}

//+------------------------------------------------------------------+
//| トレード実行                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_ORDER_TYPE orderType, double slPips, double tpPips, string comment)
{
   //--- ロットサイズ計算
   double lots = CalculateLotSize(slPips);

   if(lots <= 0)
   {
      Print("ロットサイズ計算エラー: 許容損失不足");
      return false;
   }

   //--- 価格取得
   double price, sl, tp;
   double pipSize = GetPipSize();

   if(orderType == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = price - slPips * pipSize;
      tp = price + tpPips * pipSize;
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = price + slPips * pipSize;
      tp = price - tpPips * pipSize;
   }

   //--- 注文リクエストの準備
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 30;
   request.magic = MagicNumber;
   request.comment = comment;
   request.type_filling = GetFillingMode();  // ブローカー対応フィリングモードを自動検出

   //--- 注文送信
   if(!OrderSend(request, result))
   {
      Print("注文エラー: ", result.retcode, " - ", GetRetcodeDescription(result.retcode));
      return false;
   }

   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("注文成功: ", comment, " Lots=", DoubleToString(lots, 2),
            " Price=", DoubleToString(price, _Digits),
            " SL=", DoubleToString(sl, _Digits),
            " TP=", DoubleToString(tp, _Digits));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| コメントによるポジション決済                                     |
//+------------------------------------------------------------------+
void ClosePositionsByComment(string comment)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      string posComment = PositionGetString(POSITION_COMMENT);
      if(StringFind(posComment, comment) >= 0)
      {
         ClosePosition(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| 全ポジション決済                                                 |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("全ポジション決済開始: ", reason);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ClosePosition(ticket);
   }
}

//+------------------------------------------------------------------+
//| 最も損失が大きいポジションを決済                                 |
//+------------------------------------------------------------------+
void CloseWorstPosition()
{
   double worstProfit = 0;
   ulong worstTicket = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(profit < worstProfit)
      {
         worstProfit = profit;
         worstTicket = ticket;
      }
   }

   if(worstTicket > 0)
   {
      Print("最大損失ポジション決済: Ticket=", worstTicket, " Loss=", DoubleToString(worstProfit, 2));
      ClosePosition(worstTicket);
   }
}

//+------------------------------------------------------------------+
//| ポジション決済                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.deviation = 30;
   request.magic = MagicNumber;
   request.position = ticket;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   if(posType == POSITION_TYPE_BUY)
   {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
   }
   else
   {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
   }

   request.type_filling = GetFillingMode();  // ブローカー対応フィリングモードを自動検出

   if(!OrderSend(request, result))
   {
      Print("決済エラー: Ticket=", ticket, " Error=", result.retcode);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| リターンコードの説明                                             |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:           return "Requote";
      case TRADE_RETCODE_REJECT:            return "Request rejected";
      case TRADE_RETCODE_CANCEL:            return "Request canceled by trader";
      case TRADE_RETCODE_PLACED:            return "Order placed";
      case TRADE_RETCODE_DONE:              return "Request completed";
      case TRADE_RETCODE_DONE_PARTIAL:      return "Only part of the request was completed";
      case TRADE_RETCODE_ERROR:             return "Request processing error";
      case TRADE_RETCODE_TIMEOUT:           return "Request canceled by timeout";
      case TRADE_RETCODE_INVALID:           return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:    return "Invalid volume in the request";
      case TRADE_RETCODE_INVALID_PRICE:     return "Invalid price in the request";
      case TRADE_RETCODE_INVALID_STOPS:     return "Invalid stops in the request";
      case TRADE_RETCODE_TRADE_DISABLED:    return "Trade is disabled";
      case TRADE_RETCODE_MARKET_CLOSED:     return "Market is closed";
      case TRADE_RETCODE_NO_MONEY:          return "There is not enough money to complete the request";
      case TRADE_RETCODE_PRICE_CHANGED:     return "Prices changed";
      case TRADE_RETCODE_PRICE_OFF:         return "There are no quotes to process the request";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid order expiration date in the request";
      case TRADE_RETCODE_ORDER_CHANGED:     return "Order state changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too frequent requests";
      default:                              return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| OnTimer - 定期処理（オプション）                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- 定期的なリスクチェック
   CheckRiskLimits();
}
//+------------------------------------------------------------------+
