//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|        Economic News Filter using MT5 Calendar v1.0              |
//|        重要経済指標の前後でトレードを停止                          |
//+------------------------------------------------------------------+
#ifndef NEWS_FILTER_MQH
#define NEWS_FILTER_MQH

//+------------------------------------------------------------------+
//| News Impact Level                                                 |
//+------------------------------------------------------------------+
enum ENUM_NEWS_IMPACT
{
   NEWS_IMPACT_LOW = 0,      // 低インパクト
   NEWS_IMPACT_MEDIUM = 1,   // 中インパクト
   NEWS_IMPACT_HIGH = 2      // 高インパクト
};

//+------------------------------------------------------------------+
//| News Filter Class                                                 |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   bool              m_Enabled;
   int               m_MinutesBefore;      // 指標発表前の回避時間（分）
   int               m_MinutesAfter;       // 指標発表後の回避時間（分）
   ENUM_NEWS_IMPACT  m_MinImpact;          // フィルタする最小インパクト
   string            m_Currencies[];       // 監視する通貨リスト

   datetime          m_NextNewsTime;       // 次の重要指標の時間
   string            m_NextNewsName;       // 次の重要指標の名前
   string            m_NextNewsCurrency;   // 次の重要指標の通貨

public:
   CNewsFilter()
   {
      m_Enabled = false;
      m_MinutesBefore = 5;
      m_MinutesAfter = 5;
      m_MinImpact = NEWS_IMPACT_HIGH;
      m_NextNewsTime = 0;
      m_NextNewsName = "";
      m_NextNewsCurrency = "";
   }

   //--- 初期化
   bool Initialize(bool enabled, int minutesBefore = 5, int minutesAfter = 5,
                   ENUM_NEWS_IMPACT minImpact = NEWS_IMPACT_HIGH)
   {
      m_Enabled = enabled;
      m_MinutesBefore = minutesBefore;
      m_MinutesAfter = minutesAfter;
      m_MinImpact = minImpact;

      if(!m_Enabled)
      {
         Print("[NewsFilter] Disabled");
         return true;
      }

      PrintFormat("[NewsFilter] Initialized - Before: %d min, After: %d min, MinImpact: %s",
                  m_MinutesBefore, m_MinutesAfter,
                  m_MinImpact == NEWS_IMPACT_HIGH ? "HIGH" :
                  m_MinImpact == NEWS_IMPACT_MEDIUM ? "MEDIUM" : "LOW");

      // 初回の指標チェック
      UpdateNextNews();

      return true;
   }

   //--- シンボルから通貨を設定
   void SetCurrenciesFromSymbol(string symbol)
   {
      ArrayResize(m_Currencies, 0);

      // シンボルから通貨を抽出 (例: XAUJPY -> XAU, JPY)
      if(StringLen(symbol) >= 6)
      {
         string curr1 = StringSubstr(symbol, 0, 3);
         string curr2 = StringSubstr(symbol, 3, 3);

         ArrayResize(m_Currencies, 2);
         m_Currencies[0] = curr1;
         m_Currencies[1] = curr2;

         // USD関連は常に監視
         bool hasUSD = false;
         for(int i = 0; i < ArraySize(m_Currencies); i++)
         {
            if(m_Currencies[i] == "USD")
               hasUSD = true;
         }
         if(!hasUSD)
         {
            int size = ArraySize(m_Currencies);
            ArrayResize(m_Currencies, size + 1);
            m_Currencies[size] = "USD";
         }

         PrintFormat("[NewsFilter] Monitoring currencies: %s, %s, USD", curr1, curr2);
      }
   }

   //--- 次の重要指標を更新
   void UpdateNextNews()
   {
      if(!m_Enabled)
         return;

      datetime now = TimeCurrent();
      datetime searchEnd = now + 24 * 60 * 60;  // 24時間先まで検索

      m_NextNewsTime = 0;
      m_NextNewsName = "";
      m_NextNewsCurrency = "";

      MqlCalendarValue values[];

      // カレンダーから今後24時間のイベントを取得
      if(CalendarValueHistory(values, now, searchEnd) > 0)
      {
         datetime earliestTime = searchEnd;

         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if(!CalendarEventById(values[i].event_id, event))
               continue;

            MqlCalendarCountry country;
            if(!CalendarCountryById(event.country_id, country))
               continue;

            // インパクトレベルをチェック
            ENUM_CALENDAR_EVENT_IMPORTANCE importance = event.importance;
            if(importance == CALENDAR_IMPORTANCE_NONE)
               continue;

            // フィルター設定に基づいてチェック
            bool isRelevant = false;

            if(m_MinImpact == NEWS_IMPACT_HIGH && importance == CALENDAR_IMPORTANCE_HIGH)
               isRelevant = true;
            else if(m_MinImpact == NEWS_IMPACT_MEDIUM &&
                    (importance == CALENDAR_IMPORTANCE_HIGH || importance == CALENDAR_IMPORTANCE_MODERATE))
               isRelevant = true;
            else if(m_MinImpact == NEWS_IMPACT_LOW)
               isRelevant = true;

            if(!isRelevant)
               continue;

            // 通貨をチェック
            string eventCurrency = country.currency;
            bool currencyMatch = false;

            for(int j = 0; j < ArraySize(m_Currencies); j++)
            {
               if(eventCurrency == m_Currencies[j])
               {
                  currencyMatch = true;
                  break;
               }
            }

            // USD関連は常にチェック
            if(eventCurrency == "USD")
               currencyMatch = true;

            if(!currencyMatch)
               continue;

            // 最も近いイベントを保存
            if(values[i].time < earliestTime)
            {
               earliestTime = values[i].time;
               m_NextNewsTime = values[i].time;
               m_NextNewsName = event.name;
               m_NextNewsCurrency = eventCurrency;
            }
         }
      }

      if(m_NextNewsTime > 0)
      {
         PrintFormat("[NewsFilter] Next news: %s (%s) at %s",
                     m_NextNewsName, m_NextNewsCurrency,
                     TimeToString(m_NextNewsTime, TIME_DATE|TIME_MINUTES));
      }
   }

   //--- トレード許可をチェック
   bool IsTradeAllowed()
   {
      if(!m_Enabled)
         return true;

      if(m_NextNewsTime == 0)
      {
         // 定期的に更新
         UpdateNextNews();
         return true;
      }

      datetime now = TimeCurrent();

      // 指標発表時間の前後をチェック
      datetime avoidStart = m_NextNewsTime - m_MinutesBefore * 60;
      datetime avoidEnd = m_NextNewsTime + m_MinutesAfter * 60;

      if(now >= avoidStart && now <= avoidEnd)
      {
         PrintFormat("[NewsFilter] Trade blocked! News: %s (%s) at %s",
                     m_NextNewsName, m_NextNewsCurrency,
                     TimeToString(m_NextNewsTime, TIME_DATE|TIME_MINUTES));
         return false;
      }

      // 指標発表が過ぎたら次の指標を検索
      if(now > avoidEnd)
      {
         UpdateNextNews();
      }

      return true;
   }

   //--- ポジションをクローズすべきかチェック
   bool ShouldClosePositions()
   {
      if(!m_Enabled)
         return false;

      if(m_NextNewsTime == 0)
         return false;

      datetime now = TimeCurrent();
      datetime avoidStart = m_NextNewsTime - m_MinutesBefore * 60;

      // 指標発表の直前（1分前）にポジションをクローズ
      if(now >= avoidStart - 60 && now < avoidStart)
      {
         PrintFormat("[NewsFilter] Close positions! News in %d minutes: %s (%s)",
                     (int)((m_NextNewsTime - now) / 60),
                     m_NextNewsName, m_NextNewsCurrency);
         return true;
      }

      return false;
   }

   //--- 次の指標情報を取得
   datetime GetNextNewsTime() { return m_NextNewsTime; }
   string GetNextNewsName() { return m_NextNewsName; }
   string GetNextNewsCurrency() { return m_NextNewsCurrency; }

   //--- ステータス文字列
   string GetStatusString()
   {
      if(!m_Enabled)
         return "NewsFilter: OFF";

      if(m_NextNewsTime == 0)
         return "NewsFilter: ON (No upcoming news)";

      datetime now = TimeCurrent();
      int minutesToNews = (int)((m_NextNewsTime - now) / 60);

      return StringFormat("NewsFilter: ON | Next: %s (%s) in %d min",
                          m_NextNewsName, m_NextNewsCurrency, minutesToNews);
   }
};

#endif // NEWS_FILTER_MQH
