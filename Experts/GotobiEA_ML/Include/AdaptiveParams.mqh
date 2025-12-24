//+------------------------------------------------------------------+
//|                                               AdaptiveParams.mqh |
//|                         Adaptive Parameters (ATR SL/TP, Spread) |
//|                              動的SL/TP、スプレッド監視            |
//+------------------------------------------------------------------+
#property copyright "Gotobi EA ML"
#property version   "1.00"

//+------------------------------------------------------------------+
//| 定数定義                                                          |
//+------------------------------------------------------------------+
#define SPREAD_HISTORY_SIZE    100  // スプレッド履歴サイズ

//+------------------------------------------------------------------+
//| 適応的パラメータクラス                                            |
//+------------------------------------------------------------------+
class CAdaptiveParams
{
private:
   // ATRハンドル
   int         m_atrHandle;
   int         m_atrPeriod;

   // スプレッド履歴
   double      m_spreadHistory[];
   int         m_spreadHistoryIndex;
   int         m_spreadHistoryCount;
   double      m_avgSpread;
   double      m_maxSpreadMultiplier;

   // シンボル情報
   string      m_symbol;
   double      m_pipSize;
   double      m_point;
   int         m_digits;

   // SL/TP乗数
   double      m_slAtrMultiplier;
   double      m_tpAtrMultiplier;

   // 最小・最大値
   double      m_minSlPips;
   double      m_maxSlPips;
   double      m_minTpPips;
   double      m_maxTpPips;

   // 初期化済みフラグ
   bool        m_initialized;

   // 内部メソッド
   void        UpdateSpreadHistory(double spread);
   double      CalculateAverageSpread();
   double      GetPipSize();

public:
   CAdaptiveParams();
   ~CAdaptiveParams();

   // 初期化
   bool Initialize(string symbol, int atrPeriod = 14,
                   double slMultiplier = 1.5, double tpMultiplier = 2.0);

   // ATR取得
   double GetATR(int shift = 0);

   // 動的SL/TP計算（pips単位）
   double GetDynamicSL();
   double GetDynamicTP();

   // 動的SL/TP計算（価格単位）
   double GetDynamicSLPrice(double entryPrice, bool isBuy);
   double GetDynamicTPPrice(double entryPrice, bool isBuy);

   // スプレッド監視
   void   UpdateSpread();
   double GetCurrentSpread();
   double GetAverageSpread();
   bool   IsSpreadAcceptable();
   double GetSpreadRatio();

   // 月曜早朝チェック
   bool   IsMondayEarlyMorning();

   // 重要指標時間チェック（日本時間ベース）
   bool   IsHighImpactNewsTime();

   // 取引可能条件チェック
   bool   IsTradeConditionOK();

   // パラメータ設定
   void   SetSlAtrMultiplier(double mult) { m_slAtrMultiplier = mult; }
   void   SetTpAtrMultiplier(double mult) { m_tpAtrMultiplier = mult; }
   void   SetMaxSpreadMultiplier(double mult) { m_maxSpreadMultiplier = mult; }
   void   SetSlLimits(double minPips, double maxPips) { m_minSlPips = minPips; m_maxSlPips = maxPips; }
   void   SetTpLimits(double minPips, double maxPips) { m_minTpPips = minPips; m_maxTpPips = maxPips; }

   // ログ出力
   void   LogAdaptiveParams();
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CAdaptiveParams::CAdaptiveParams()
{
   m_atrHandle = INVALID_HANDLE;
   m_atrPeriod = 14;
   m_spreadHistoryIndex = 0;
   m_spreadHistoryCount = 0;
   m_avgSpread = 0;
   m_maxSpreadMultiplier = 1.5;
   m_symbol = "";
   m_pipSize = 0;
   m_point = 0;
   m_digits = 0;
   m_slAtrMultiplier = 1.5;
   m_tpAtrMultiplier = 2.0;
   m_minSlPips = 10;
   m_maxSlPips = 100;
   m_minTpPips = 15;
   m_maxTpPips = 150;
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CAdaptiveParams::~CAdaptiveParams()
{
   if(m_atrHandle != INVALID_HANDLE)
      IndicatorRelease(m_atrHandle);

   ArrayFree(m_spreadHistory);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CAdaptiveParams::Initialize(string symbol, int atrPeriod,
                                 double slMultiplier, double tpMultiplier)
{
   m_symbol = symbol;
   m_atrPeriod = atrPeriod;
   m_slAtrMultiplier = slMultiplier;
   m_tpAtrMultiplier = tpMultiplier;

   // シンボル情報取得
   m_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   m_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   m_pipSize = GetPipSize();

   // ATRハンドル作成（H1を使用）
   m_atrHandle = iATR(symbol, PERIOD_H1, atrPeriod);
   if(m_atrHandle == INVALID_HANDLE)
   {
      Print("AdaptiveParams: ATRインジケーター作成失敗");
      return false;
   }

   // スプレッド履歴初期化
   ArrayResize(m_spreadHistory, SPREAD_HISTORY_SIZE);
   ArrayFill(m_spreadHistory, 0, SPREAD_HISTORY_SIZE, 0);

   // 初期スプレッド取得
   for(int i = 0; i < 10; i++)
   {
      UpdateSpread();
   }

   m_initialized = true;

   Print("AdaptiveParams: 初期化完了 Symbol=", symbol, " ATRPeriod=", atrPeriod);

   return true;
}

//+------------------------------------------------------------------+
//| pip サイズ取得                                                    |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetPipSize()
{
   if(m_digits == 3 || m_digits == 5)
      return m_point * 10.0;
   else
      return m_point;
}

//+------------------------------------------------------------------+
//| ATR取得                                                           |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetATR(int shift)
{
   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(m_atrHandle, 0, shift, 1, atr) < 1)
      return 0;

   return atr[0];
}

//+------------------------------------------------------------------+
//| 動的SL計算（pips単位）                                            |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetDynamicSL()
{
   double atr = GetATR();

   if(atr == 0)
      return m_minSlPips;

   // ATRをpipsに変換
   double atrPips = atr / m_pipSize;

   // SL = ATR × 乗数
   double slPips = atrPips * m_slAtrMultiplier;

   // 範囲制限
   slPips = MathMax(slPips, m_minSlPips);
   slPips = MathMin(slPips, m_maxSlPips);

   return NormalizeDouble(slPips, 1);
}

//+------------------------------------------------------------------+
//| 動的TP計算（pips単位）                                            |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetDynamicTP()
{
   double atr = GetATR();

   if(atr == 0)
      return m_minTpPips;

   // ATRをpipsに変換
   double atrPips = atr / m_pipSize;

   // TP = ATR × 乗数
   double tpPips = atrPips * m_tpAtrMultiplier;

   // 範囲制限
   tpPips = MathMax(tpPips, m_minTpPips);
   tpPips = MathMin(tpPips, m_maxTpPips);

   return NormalizeDouble(tpPips, 1);
}

//+------------------------------------------------------------------+
//| 動的SL価格計算                                                    |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetDynamicSLPrice(double entryPrice, bool isBuy)
{
   double slPips = GetDynamicSL();
   double slDistance = slPips * m_pipSize;

   if(isBuy)
      return NormalizeDouble(entryPrice - slDistance, m_digits);
   else
      return NormalizeDouble(entryPrice + slDistance, m_digits);
}

//+------------------------------------------------------------------+
//| 動的TP価格計算                                                    |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetDynamicTPPrice(double entryPrice, bool isBuy)
{
   double tpPips = GetDynamicTP();
   double tpDistance = tpPips * m_pipSize;

   if(isBuy)
      return NormalizeDouble(entryPrice + tpDistance, m_digits);
   else
      return NormalizeDouble(entryPrice - tpDistance, m_digits);
}

//+------------------------------------------------------------------+
//| スプレッド履歴更新                                                |
//+------------------------------------------------------------------+
void CAdaptiveParams::UpdateSpreadHistory(double spread)
{
   m_spreadHistory[m_spreadHistoryIndex] = spread;
   m_spreadHistoryIndex = (m_spreadHistoryIndex + 1) % SPREAD_HISTORY_SIZE;

   if(m_spreadHistoryCount < SPREAD_HISTORY_SIZE)
      m_spreadHistoryCount++;

   m_avgSpread = CalculateAverageSpread();
}

//+------------------------------------------------------------------+
//| 平均スプレッド計算                                                |
//+------------------------------------------------------------------+
double CAdaptiveParams::CalculateAverageSpread()
{
   if(m_spreadHistoryCount == 0)
      return 0;

   double sum = 0;
   for(int i = 0; i < m_spreadHistoryCount; i++)
   {
      sum += m_spreadHistory[i];
   }

   return sum / m_spreadHistoryCount;
}

//+------------------------------------------------------------------+
//| スプレッド更新                                                    |
//+------------------------------------------------------------------+
void CAdaptiveParams::UpdateSpread()
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   double spreadPips = (ask - bid) / m_pipSize;

   UpdateSpreadHistory(spreadPips);
}

//+------------------------------------------------------------------+
//| 現在のスプレッド取得（pips）                                      |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetCurrentSpread()
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

   return (ask - bid) / m_pipSize;
}

//+------------------------------------------------------------------+
//| 平均スプレッド取得                                                |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetAverageSpread()
{
   return m_avgSpread;
}

//+------------------------------------------------------------------+
//| スプレッド許容判定                                                |
//+------------------------------------------------------------------+
bool CAdaptiveParams::IsSpreadAcceptable()
{
   if(m_avgSpread <= 0)
      return true; // データ不足時は許可

   double currentSpread = GetCurrentSpread();
   double ratio = currentSpread / m_avgSpread;

   // 平均の1.5倍以下なら許可
   return (ratio <= m_maxSpreadMultiplier);
}

//+------------------------------------------------------------------+
//| スプレッド比率取得                                                |
//+------------------------------------------------------------------+
double CAdaptiveParams::GetSpreadRatio()
{
   if(m_avgSpread <= 0)
      return 1.0;

   return GetCurrentSpread() / m_avgSpread;
}

//+------------------------------------------------------------------+
//| 月曜早朝チェック                                                  |
//+------------------------------------------------------------------+
bool CAdaptiveParams::IsMondayEarlyMorning()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);

   // 月曜日かつ6-7時（サーバー時間、日本時間に調整必要）
   if(mdt.day_of_week == 1 && mdt.hour >= 6 && mdt.hour < 8)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| 重要指標時間チェック                                              |
//+------------------------------------------------------------------+
bool CAdaptiveParams::IsHighImpactNewsTime()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);

   // 日本時間ベースの重要指標時間帯（サーバー時間調整が必要）
   // 雇用統計: 毎月第一金曜 21:30-22:30 JST (12:30-13:30 UTC)
   // FOMC: 不定期 03:00-04:00 JST (18:00-19:00 UTC前日)

   // 簡易実装：金曜日の21-23時（JST）は指標の可能性が高い
   if(mdt.day_of_week == 5)
   {
      // UTC時間で12-14時は避ける（JST 21-23時相当）
      if(mdt.hour >= 12 && mdt.hour <= 14)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 取引可能条件チェック                                              |
//+------------------------------------------------------------------+
bool CAdaptiveParams::IsTradeConditionOK()
{
   // スプレッドチェック
   if(!IsSpreadAcceptable())
   {
      Print("AdaptiveParams: スプレッド拡大中 現在=", DoubleToString(GetCurrentSpread(), 1),
            " 平均=", DoubleToString(m_avgSpread, 1),
            " 比率=", DoubleToString(GetSpreadRatio(), 2));
      return false;
   }

   // 月曜早朝チェック
   if(IsMondayEarlyMorning())
   {
      Print("AdaptiveParams: 月曜早朝のため取引回避");
      return false;
   }

   // 重要指標時間チェック
   if(IsHighImpactNewsTime())
   {
      Print("AdaptiveParams: 重要指標時間帯のため取引回避");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ログ出力                                                          |
//+------------------------------------------------------------------+
void CAdaptiveParams::LogAdaptiveParams()
{
   Print("=== 適応的パラメータ ===");
   Print("ATR(", m_atrPeriod, "): ", DoubleToString(GetATR(), 5));
   Print("動的SL: ", DoubleToString(GetDynamicSL(), 1), " pips");
   Print("動的TP: ", DoubleToString(GetDynamicTP(), 1), " pips");
   Print("現在スプレッド: ", DoubleToString(GetCurrentSpread(), 1), " pips");
   Print("平均スプレッド: ", DoubleToString(m_avgSpread, 1), " pips");
   Print("スプレッド比率: ", DoubleToString(GetSpreadRatio(), 2));
   Print("スプレッド許容: ", IsSpreadAcceptable() ? "OK" : "NG");
   Print("月曜早朝: ", IsMondayEarlyMorning() ? "Yes" : "No");
   Print("指標時間: ", IsHighImpactNewsTime() ? "Yes" : "No");
   Print("取引可能: ", IsTradeConditionOK() ? "OK" : "NG");
   Print("========================");
}

//+------------------------------------------------------------------+
