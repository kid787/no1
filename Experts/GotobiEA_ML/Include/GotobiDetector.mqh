//+------------------------------------------------------------------+
//|                                              GotobiDetector.mqh |
//|                                      Gotobi Day Detection Logic |
//|                              5,10,15,20,25,30日 + 月末判定       |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML"
#property version   "1.00"

//+------------------------------------------------------------------+
//| 日本の祝日データ構造                                              |
//+------------------------------------------------------------------+
struct JapanHoliday
{
   int month;
   int day;
   string name;
};

//+------------------------------------------------------------------+
//| ゴトー日判定クラス                                                |
//+------------------------------------------------------------------+
class CGotobiDetector
{
private:
   // 日本の祝日配列（2024-2025年対応）
   JapanHoliday m_holidays[];
   int          m_holidayCount;

   // 初期化済みフラグ
   bool         m_initialized;

   // 祝日データ初期化
   void InitHolidays();

public:
   CGotobiDetector();
   ~CGotobiDetector();

   // ゴトー日判定
   bool IsGotobiDay(datetime dt);

   // 実際のゴトー日取引日を取得（前倒し考慮）
   datetime GetActualGotobiTradingDate(datetime gotobiDate);

   // 今日がゴトー日の取引日かどうか
   bool IsTodayGotobiTradingDay();

   // 次のゴトー日取引日を取得
   datetime GetNextGotobiTradingDate();

   // 月末日を取得
   int GetLastDayOfMonth(int year, int month);

   // 週末判定
   bool IsWeekend(datetime dt);

   // 祝日判定
   bool IsJapanHoliday(datetime dt);

   // 営業日判定
   bool IsBusinessDay(datetime dt);

   // 金曜日のゴトー日判定（高勝率パターン）
   bool IsFridayGotobiDay(datetime dt);

   // 月曜日判定（流動性低下リスク）
   bool IsMonday(datetime dt);

   // ログ出力
   void LogGotobiInfo(datetime dt);
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CGotobiDetector::CGotobiDetector()
{
   m_initialized = false;
   m_holidayCount = 0;
   InitHolidays();
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CGotobiDetector::~CGotobiDetector()
{
   ArrayFree(m_holidays);
}

//+------------------------------------------------------------------+
//| 日本の祝日データ初期化                                            |
//+------------------------------------------------------------------+
void CGotobiDetector::InitHolidays()
{
   // 2024-2025年の主要な日本の祝日
   // 実際の運用では外部ファイルからの読み込みが望ましい

   JapanHoliday holidays[] = {
      // 2024年
      {1, 1, "元日"},
      {1, 8, "成人の日"},
      {2, 11, "建国記念の日"},
      {2, 12, "振替休日"},
      {2, 23, "天皇誕生日"},
      {3, 20, "春分の日"},
      {4, 29, "昭和の日"},
      {5, 3, "憲法記念日"},
      {5, 4, "みどりの日"},
      {5, 5, "こどもの日"},
      {5, 6, "振替休日"},
      {7, 15, "海の日"},
      {8, 11, "山の日"},
      {8, 12, "振替休日"},
      {9, 16, "敬老の日"},
      {9, 22, "秋分の日"},
      {9, 23, "振替休日"},
      {10, 14, "スポーツの日"},
      {11, 3, "文化の日"},
      {11, 4, "振替休日"},
      {11, 23, "勤労感謝の日"},
      // 2025年
      {1, 1, "元日"},
      {1, 13, "成人の日"},
      {2, 11, "建国記念の日"},
      {2, 23, "天皇誕生日"},
      {2, 24, "振替休日"},
      {3, 20, "春分の日"},
      {4, 29, "昭和の日"},
      {5, 3, "憲法記念日"},
      {5, 4, "みどりの日"},
      {5, 5, "こどもの日"},
      {5, 6, "振替休日"},
      {7, 21, "海の日"},
      {8, 11, "山の日"},
      {9, 15, "敬老の日"},
      {9, 23, "秋分の日"},
      {10, 13, "スポーツの日"},
      {11, 3, "文化の日"},
      {11, 23, "勤労感謝の日"},
      {11, 24, "振替休日"}
   };

   m_holidayCount = ArraySize(holidays);
   ArrayResize(m_holidays, m_holidayCount);

   for(int i = 0; i < m_holidayCount; i++)
   {
      m_holidays[i] = holidays[i];
   }

   m_initialized = true;
}

//+------------------------------------------------------------------+
//| 月末日を取得                                                      |
//+------------------------------------------------------------------+
int CGotobiDetector::GetLastDayOfMonth(int year, int month)
{
   int daysInMonth[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

   // 閏年判定
   if(month == 2)
   {
      if((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0))
         return 29;
   }

   return daysInMonth[month - 1];
}

//+------------------------------------------------------------------+
//| ゴトー日判定（5,10,15,20,25,30日 + 月末）                         |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsGotobiDay(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   int day = mdt.day;
   int month = mdt.mon;
   int year = mdt.year;

   // 5の倍数日（5, 10, 15, 20, 25, 30）
   if(day == 5 || day == 10 || day == 15 || day == 20 || day == 25 || day == 30)
      return true;

   // 月末日
   if(day == GetLastDayOfMonth(year, month))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 週末判定                                                          |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsWeekend(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   return (mdt.day_of_week == 0 || mdt.day_of_week == 6);
}

//+------------------------------------------------------------------+
//| 祝日判定                                                          |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsJapanHoliday(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   for(int i = 0; i < m_holidayCount; i++)
   {
      if(m_holidays[i].month == mdt.mon && m_holidays[i].day == mdt.day)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 営業日判定                                                        |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsBusinessDay(datetime dt)
{
   return !IsWeekend(dt) && !IsJapanHoliday(dt);
}

//+------------------------------------------------------------------+
//| 実際のゴトー日取引日を取得（前倒し考慮）                          |
//+------------------------------------------------------------------+
datetime CGotobiDetector::GetActualGotobiTradingDate(datetime gotobiDate)
{
   datetime checkDate = gotobiDate;

   // 土日祝日の場合は前倒し
   while(!IsBusinessDay(checkDate))
   {
      checkDate -= 86400; // 1日前
   }

   return checkDate;
}

//+------------------------------------------------------------------+
//| 今日がゴトー日の取引日かどうか                                    |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsTodayGotobiTradingDay()
{
   datetime today = TimeCurrent();
   MqlDateTime mdt;
   TimeToStruct(today, mdt);

   // 日本時間に変換（サーバー時間がGMT+0の場合、+9時間）
   // MT5のサーバー時間設定により調整が必要
   // 注：実際のブローカーのサーバー時間を確認して調整

   // 今日の日付のみを取得
   datetime todayDate = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                  mdt.year, mdt.mon, mdt.day));

   // 今月のゴトー日をチェック
   int gotobiDays[] = {5, 10, 15, 20, 25, 30};
   int lastDay = GetLastDayOfMonth(mdt.year, mdt.mon);

   // 5の倍数日チェック
   for(int i = 0; i < ArraySize(gotobiDays); i++)
   {
      if(gotobiDays[i] <= lastDay)
      {
         datetime gotobiDate = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                         mdt.year, mdt.mon, gotobiDays[i]));
         datetime actualTradingDate = GetActualGotobiTradingDate(gotobiDate);

         if(todayDate == actualTradingDate)
            return true;
      }
   }

   // 月末日チェック
   datetime lastDayDate = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                    mdt.year, mdt.mon, lastDay));
   datetime actualLastDayTrading = GetActualGotobiTradingDate(lastDayDate);

   if(todayDate == actualLastDayTrading)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 次のゴトー日取引日を取得                                          |
//+------------------------------------------------------------------+
datetime CGotobiDetector::GetNextGotobiTradingDate()
{
   datetime today = TimeCurrent();
   MqlDateTime mdt;
   TimeToStruct(today, mdt);

   int year = mdt.year;
   int month = mdt.mon;
   int day = mdt.day;

   // 最大60日先まで検索
   for(int offset = 1; offset <= 60; offset++)
   {
      datetime checkDate = today + (offset * 86400);
      MqlDateTime checkMdt;
      TimeToStruct(checkDate, checkMdt);

      // その日がゴトー日かチェック
      if(IsGotobiDay(checkDate))
      {
         datetime actualTradingDate = GetActualGotobiTradingDate(checkDate);
         MqlDateTime actualMdt;
         TimeToStruct(actualTradingDate, actualMdt);

         // 今日より後の日付なら返す
         if(actualMdt.day > day || actualMdt.mon > month || actualMdt.year > year)
         {
            return actualTradingDate;
         }
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| 金曜日のゴトー日判定（高勝率パターン）                            |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsFridayGotobiDay(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   return (mdt.day_of_week == 5 && IsTodayGotobiTradingDay());
}

//+------------------------------------------------------------------+
//| 月曜日判定（流動性低下リスク）                                    |
//+------------------------------------------------------------------+
bool CGotobiDetector::IsMonday(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   return (mdt.day_of_week == 1);
}

//+------------------------------------------------------------------+
//| ゴトー日情報ログ出力                                              |
//+------------------------------------------------------------------+
void CGotobiDetector::LogGotobiInfo(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);

   Print("=== ゴトー日判定情報 ===");
   Print("日付: ", TimeToString(dt, TIME_DATE));
   Print("曜日: ", mdt.day_of_week);
   Print("ゴトー日: ", IsGotobiDay(dt) ? "はい" : "いいえ");
   Print("営業日: ", IsBusinessDay(dt) ? "はい" : "いいえ");
   Print("今日は取引日: ", IsTodayGotobiTradingDay() ? "はい" : "いいえ");
   Print("金曜ゴトー日: ", IsFridayGotobiDay(dt) ? "はい" : "いいえ");
   Print("月曜日: ", IsMonday(dt) ? "はい" : "いいえ");
   Print("========================");
}

//+------------------------------------------------------------------+
