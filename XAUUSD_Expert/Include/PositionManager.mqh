//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|                   XAUUSD Expert - ポジション管理（建値決済・分割利確） |
//+------------------------------------------------------------------+
#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH

#include "CommonDefines.mqh"
#include <Trade/Trade.mqh>

//--- 分割利確設定構造体
struct PartialTPSetting {
   double         triggerPercent;      // 利益トリガー（TP距離の%）
   double         closePercent;        // クローズするロットの%
   bool           moveToBreakEven;     // 建値に移動するか
};

//+------------------------------------------------------------------+
//| ポジション管理クラス                                              |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   // 設定
   string         m_symbol;
   ulong          m_magicNumber;

   // 建値決済設定
   double         m_breakEvenTriggerPips;   // 建値移動トリガー（pips）
   double         m_breakEvenProfitPips;    // 建値移動後の利益確保（pips）
   bool           m_enableBreakEven;

   // 分割利確設定
   PartialTPSetting m_partialSettings[];
   int            m_partialCount;
   bool           m_enablePartialTP;

   // トレーリングストップ設定
   double         m_trailingStartPips;      // トレーリング開始（pips）
   double         m_trailingStepPips;       // トレーリングステップ（pips）
   bool           m_enableTrailing;

   // 20SMA利確用
   int            m_handleSMA20;
   double         m_sma20[];
   bool           m_enableSMAExit;

   // ポジション追跡
   PositionInfo   m_positions[];
   int            m_positionCount;

   // トレード
   CTrade         m_trade;

   // ログ
   bool           m_enableLog;

   // 内部メソッド
   bool           UpdatePositionList();
   int            FindPositionIndex(ulong ticket);
   bool           ModifyStopLoss(ulong ticket, double newSL);
   bool           ClosePartial(ulong ticket, double lots);
   double         GetPositionProfit(ulong ticket);
   double         GetPositionProfitPips(ulong ticket);

public:
                  CPositionManager();
                 ~CPositionManager();

   // 初期化
   bool           Initialize(string symbol = NULL,
                             ulong magic = EA_MAGIC_NUMBER,
                             double beTrigerPips = 30.0,
                             double beProfitPips = 5.0,
                             double trailStart = 50.0,
                             double trailStep = 20.0);

   // 分割利確設定
   void           AddPartialTPSetting(double triggerPercent, double closePercent, bool moveToBreakEven);
   void           ClearPartialTPSettings();

   // 機能有効/無効
   void           EnableBreakEven(bool enable) { m_enableBreakEven = enable; }
   void           EnablePartialTP(bool enable) { m_enablePartialTP = enable; }
   void           EnableTrailing(bool enable) { m_enableTrailing = enable; }
   void           EnableSMAExit(bool enable) { m_enableSMAExit = enable; }

   // OnTick処理
   void           OnTick();

   // 建値決済チェック
   void           CheckBreakEven();

   // 分割利確チェック
   void           CheckPartialTP();

   // トレーリングストップチェック
   void           CheckTrailingStop();

   // 20SMA抜け利確チェック
   void           CheckSMAExit();

   // ポジション操作
   bool           OpenPosition(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment = "");
   bool           ClosePosition(ulong ticket);
   bool           CloseAllPositions();
   bool           ModifyPosition(ulong ticket, double sl, double tp);

   // ポジション情報取得
   int            GetPositionCount();
   bool           HasOpenPosition();
   double         GetTotalProfit();
   double         GetTotalLots();
   bool           GetPositionInfo(int index, PositionInfo &info);

   // 設定
   void           EnableLog(bool enable) { m_enableLog = enable; }
   void           SetBreakEvenPips(double trigger, double profit) { m_breakEvenTriggerPips = trigger; m_breakEvenProfitPips = profit; }
   void           SetTrailingPips(double start, double step) { m_trailingStartPips = start; m_trailingStepPips = step; }
};

//+------------------------------------------------------------------+
//| コンストラクタ                                                    |
//+------------------------------------------------------------------+
CPositionManager::CPositionManager()
{
   m_symbol = "";
   m_magicNumber = EA_MAGIC_NUMBER;

   m_breakEvenTriggerPips = 30.0;
   m_breakEvenProfitPips = 5.0;
   m_enableBreakEven = true;

   m_partialCount = 0;
   m_enablePartialTP = true;

   m_trailingStartPips = 50.0;
   m_trailingStepPips = 20.0;
   m_enableTrailing = false;

   m_handleSMA20 = INVALID_HANDLE;
   m_enableSMAExit = true;

   m_positionCount = 0;
   m_enableLog = true;

   ArraySetAsSeries(m_sma20, true);
}

//+------------------------------------------------------------------+
//| デストラクタ                                                      |
//+------------------------------------------------------------------+
CPositionManager::~CPositionManager()
{
   if(m_handleSMA20 != INVALID_HANDLE)
      IndicatorRelease(m_handleSMA20);

   ArrayFree(m_positions);
   ArrayFree(m_partialSettings);
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
bool CPositionManager::Initialize(string symbol,
                                   ulong magic,
                                   double beTrigerPips,
                                   double beProfitPips,
                                   double trailStart,
                                   double trailStep)
{
   m_symbol = (symbol == NULL || symbol == "") ? _Symbol : symbol;
   m_magicNumber = magic;
   m_breakEvenTriggerPips = beTrigerPips;
   m_breakEvenProfitPips = beProfitPips;
   m_trailingStartPips = trailStart;
   m_trailingStepPips = trailStep;

   m_trade.SetExpertMagicNumber(m_magicNumber);
   m_trade.SetDeviationInPoints(30);  // スリッページ許容

   // 20SMAのインジケータ作成
   m_handleSMA20 = iMA(m_symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);
   if(m_handleSMA20 == INVALID_HANDLE)
   {
      if(m_enableLog) LogDebug("Failed to create SMA20 indicator");
   }

   // デフォルトの分割利確設定
   ClearPartialTPSettings();
   AddPartialTPSetting(30.0, 30.0, true);   // 30%到達で30%決済、建値移動
   AddPartialTPSetting(60.0, 30.0, false);  // 60%到達でさらに30%決済
   AddPartialTPSetting(100.0, 40.0, false); // 100%到達で残り40%決済

   UpdatePositionList();

   if(m_enableLog)
   {
      LogDebug(StringFormat("PositionManager initialized: Symbol=%s, Magic=%d, BE=%.1f/%.1f pips",
               m_symbol, m_magicNumber, m_breakEvenTriggerPips, m_breakEvenProfitPips));
   }

   return true;
}

//+------------------------------------------------------------------+
//| 分割利確設定を追加                                                |
//+------------------------------------------------------------------+
void CPositionManager::AddPartialTPSetting(double triggerPercent, double closePercent, bool moveToBreakEven)
{
   ArrayResize(m_partialSettings, m_partialCount + 1);
   m_partialSettings[m_partialCount].triggerPercent = triggerPercent;
   m_partialSettings[m_partialCount].closePercent = closePercent;
   m_partialSettings[m_partialCount].moveToBreakEven = moveToBreakEven;
   m_partialCount++;
}

//+------------------------------------------------------------------+
//| 分割利確設定をクリア                                              |
//+------------------------------------------------------------------+
void CPositionManager::ClearPartialTPSettings()
{
   ArrayResize(m_partialSettings, 0);
   m_partialCount = 0;
}

//+------------------------------------------------------------------+
//| ポジションリストを更新                                            |
//+------------------------------------------------------------------+
bool CPositionManager::UpdatePositionList()
{
   ArrayResize(m_positions, 0);
   m_positionCount = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
         {
            ArrayResize(m_positions, m_positionCount + 1);

            m_positions[m_positionCount].ticket = ticket;
            m_positions[m_positionCount].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            m_positions[m_positionCount].currentSL = PositionGetDouble(POSITION_SL);
            m_positions[m_positionCount].currentTP = PositionGetDouble(POSITION_TP);
            m_positions[m_positionCount].lots = PositionGetDouble(POSITION_VOLUME);
            m_positions[m_positionCount].openTime = (datetime)PositionGetInteger(POSITION_TIME);
            m_positions[m_positionCount].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            // 初期ロットと分割回数は追跡が必要（コメントから復元するか、別途管理）
            m_positions[m_positionCount].initialLots = m_positions[m_positionCount].lots;
            m_positions[m_positionCount].splitCount = 0;
            m_positions[m_positionCount].breakEvenApplied = (m_positions[m_positionCount].currentSL >= m_positions[m_positionCount].openPrice - PipsToPrice(1, m_symbol) &&
                                                              m_positions[m_positionCount].type == POSITION_TYPE_BUY) ||
                                                             (m_positions[m_positionCount].currentSL <= m_positions[m_positionCount].openPrice + PipsToPrice(1, m_symbol) &&
                                                              m_positions[m_positionCount].type == POSITION_TYPE_SELL);

            m_positionCount++;
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| ポジションインデックスを検索                                      |
//+------------------------------------------------------------------+
int CPositionManager::FindPositionIndex(ulong ticket)
{
   for(int i = 0; i < m_positionCount; i++)
   {
      if(m_positions[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| OnTick処理                                                        |
//+------------------------------------------------------------------+
void CPositionManager::OnTick()
{
   UpdatePositionList();

   if(m_positionCount == 0)
      return;

   // 建値決済チェック
   if(m_enableBreakEven)
      CheckBreakEven();

   // 分割利確チェック
   if(m_enablePartialTP)
      CheckPartialTP();

   // トレーリングストップチェック
   if(m_enableTrailing)
      CheckTrailingStop();

   // 20SMA抜け利確チェック
   if(m_enableSMAExit)
      CheckSMAExit();
}

//+------------------------------------------------------------------+
//| 建値決済チェック                                                  |
//+------------------------------------------------------------------+
void CPositionManager::CheckBreakEven()
{
   for(int i = 0; i < m_positionCount; i++)
   {
      PositionInfo &pos = m_positions[i];

      // 既に建値適用済みならスキップ
      if(pos.breakEvenApplied)
         continue;

      double profitPips = GetPositionProfitPips(pos.ticket);
      if(profitPips < m_breakEvenTriggerPips)
         continue;

      double newSL;
      if(pos.type == POSITION_TYPE_BUY)
      {
         newSL = pos.openPrice + PipsToPrice(m_breakEvenProfitPips, m_symbol);
         // 現在のSLより有利な場合のみ変更
         if(pos.currentSL < newSL || pos.currentSL == 0)
         {
            if(ModifyStopLoss(pos.ticket, newSL))
            {
               pos.breakEvenApplied = true;
               if(m_enableLog) LogDebug(StringFormat("Break-even applied: Ticket=%d, NewSL=%.5f", pos.ticket, newSL));
            }
         }
      }
      else // SELL
      {
         newSL = pos.openPrice - PipsToPrice(m_breakEvenProfitPips, m_symbol);
         // 現在のSLより有利な場合のみ変更
         if(pos.currentSL > newSL || pos.currentSL == 0)
         {
            if(ModifyStopLoss(pos.ticket, newSL))
            {
               pos.breakEvenApplied = true;
               if(m_enableLog) LogDebug(StringFormat("Break-even applied: Ticket=%d, NewSL=%.5f", pos.ticket, newSL));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 分割利確チェック                                                  |
//+------------------------------------------------------------------+
void CPositionManager::CheckPartialTP()
{
   for(int i = 0; i < m_positionCount; i++)
   {
      PositionInfo &pos = m_positions[i];

      if(pos.currentTP == 0)
         continue;

      double totalDistance = MathAbs(pos.currentTP - pos.openPrice);
      double currentPrice = (pos.type == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                           SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double currentDistance = (pos.type == POSITION_TYPE_BUY) ?
                              currentPrice - pos.openPrice :
                              pos.openPrice - currentPrice;

      if(currentDistance <= 0)
         continue;

      double progressPercent = (currentDistance / totalDistance) * 100.0;

      // 分割設定に基づいてチェック
      for(int j = pos.splitCount; j < m_partialCount; j++)
      {
         if(progressPercent >= m_partialSettings[j].triggerPercent)
         {
            double closeLotsPercent = m_partialSettings[j].closePercent / 100.0;
            double closeLots = NormalizeLotSize(pos.lots * closeLotsPercent, m_symbol);

            // 残りロットが最小ロット以上か確認
            double remainLots = pos.lots - closeLots;
            double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

            if(remainLots < minLot)
            {
               // 全部クローズ
               closeLots = pos.lots;
            }

            if(closeLots >= minLot)
            {
               if(ClosePartial(pos.ticket, closeLots))
               {
                  if(m_enableLog)
                  {
                     LogDebug(StringFormat("Partial TP: Ticket=%d, Closed=%.2f lots (%.1f%%), Progress=%.1f%%",
                              pos.ticket, closeLots, m_partialSettings[j].closePercent, progressPercent));
                  }

                  pos.splitCount = j + 1;

                  // 建値移動フラグがあれば実行
                  if(m_partialSettings[j].moveToBreakEven && !pos.breakEvenApplied)
                  {
                     double beSL = pos.openPrice;
                     if(pos.type == POSITION_TYPE_BUY)
                        beSL += PipsToPrice(m_breakEvenProfitPips, m_symbol);
                     else
                        beSL -= PipsToPrice(m_breakEvenProfitPips, m_symbol);

                     if(ModifyStopLoss(pos.ticket, beSL))
                     {
                        pos.breakEvenApplied = true;
                        if(m_enableLog) LogDebug(StringFormat("Break-even after partial: Ticket=%d", pos.ticket));
                     }
                  }
               }
            }
            break;  // 一度に1つの分割のみ実行
         }
      }
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップチェック                                      |
//+------------------------------------------------------------------+
void CPositionManager::CheckTrailingStop()
{
   for(int i = 0; i < m_positionCount; i++)
   {
      PositionInfo &pos = m_positions[i];

      double profitPips = GetPositionProfitPips(pos.ticket);
      if(profitPips < m_trailingStartPips)
         continue;

      double currentPrice = (pos.type == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                           SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      double newSL;
      if(pos.type == POSITION_TYPE_BUY)
      {
         newSL = currentPrice - PipsToPrice(m_trailingStepPips, m_symbol);
         if(newSL > pos.currentSL)
         {
            if(ModifyStopLoss(pos.ticket, newSL))
            {
               if(m_enableLog) LogDebug(StringFormat("Trailing stop updated: Ticket=%d, NewSL=%.5f", pos.ticket, newSL));
            }
         }
      }
      else // SELL
      {
         newSL = currentPrice + PipsToPrice(m_trailingStepPips, m_symbol);
         if(newSL < pos.currentSL || pos.currentSL == 0)
         {
            if(ModifyStopLoss(pos.ticket, newSL))
            {
               if(m_enableLog) LogDebug(StringFormat("Trailing stop updated: Ticket=%d, NewSL=%.5f", pos.ticket, newSL));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 20SMA抜け利確チェック                                             |
//+------------------------------------------------------------------+
void CPositionManager::CheckSMAExit()
{
   if(m_handleSMA20 == INVALID_HANDLE)
      return;

   if(CopyBuffer(m_handleSMA20, 0, 0, 3, m_sma20) < 3)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, PERIOD_M5, 0, 3, rates) < 3)
      return;

   for(int i = 0; i < m_positionCount; i++)
   {
      PositionInfo &pos = m_positions[i];

      // 建値が適用されている（含み益状態）でのみチェック
      if(!pos.breakEvenApplied)
         continue;

      // 買いポジション: 実体が20SMAを下抜け
      if(pos.type == POSITION_TYPE_BUY)
      {
         // 前バーの実体が20SMAより上、現バーの実体が20SMAより下
         if(rates[2].close > m_sma20[2] && rates[1].close < m_sma20[1])
         {
            if(m_enableLog) LogDebug(StringFormat("SMA20 exit signal (BUY): Ticket=%d", pos.ticket));
            ClosePosition(pos.ticket);
         }
      }
      // 売りポジション: 実体が20SMAを上抜け
      else
      {
         if(rates[2].close < m_sma20[2] && rates[1].close > m_sma20[1])
         {
            if(m_enableLog) LogDebug(StringFormat("SMA20 exit signal (SELL): Ticket=%d", pos.ticket));
            ClosePosition(pos.ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| SLを変更                                                          |
//+------------------------------------------------------------------+
bool CPositionManager::ModifyStopLoss(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   double currentTP = PositionGetDouble(POSITION_TP);

   return m_trade.PositionModify(ticket, newSL, currentTP);
}

//+------------------------------------------------------------------+
//| 部分決済                                                          |
//+------------------------------------------------------------------+
bool CPositionManager::ClosePartial(ulong ticket, double lots)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   double currentLots = PositionGetDouble(POSITION_VOLUME);
   if(lots > currentLots)
      lots = currentLots;

   return m_trade.PositionClosePartial(ticket, lots);
}

//+------------------------------------------------------------------+
//| ポジション利益（金額）を取得                                      |
//+------------------------------------------------------------------+
double CPositionManager::GetPositionProfit(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;

   return PositionGetDouble(POSITION_PROFIT);
}

//+------------------------------------------------------------------+
//| ポジション利益（pips）を取得                                      |
//+------------------------------------------------------------------+
double CPositionManager::GetPositionProfitPips(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double currentPrice = (type == POSITION_TYPE_BUY) ?
                        SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                        SymbolInfoDouble(m_symbol, SYMBOL_ASK);

   double priceDiff = (type == POSITION_TYPE_BUY) ?
                     currentPrice - openPrice :
                     openPrice - currentPrice;

   return PriceToPips(priceDiff, m_symbol);
}

//+------------------------------------------------------------------+
//| ポジションをオープン                                              |
//+------------------------------------------------------------------+
bool CPositionManager::OpenPosition(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment)
{
   double price = (type == ORDER_TYPE_BUY) ?
                 SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                 SymbolInfoDouble(m_symbol, SYMBOL_BID);

   bool result = m_trade.PositionOpen(m_symbol, type, lots, price, sl, tp, comment);

   if(result)
   {
      UpdatePositionList();
      if(m_enableLog)
      {
         LogDebug(StringFormat("Position opened: Type=%s, Lots=%.2f, Price=%.5f, SL=%.5f, TP=%.5f",
                  (type == ORDER_TYPE_BUY) ? "BUY" : "SELL", lots, price, sl, tp));
      }
   }
   else
   {
      if(m_enableLog)
      {
         LogDebug(StringFormat("Failed to open position: Error=%d, %s",
                  m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
      }
   }

   return result;
}

//+------------------------------------------------------------------+
//| ポジションをクローズ                                              |
//+------------------------------------------------------------------+
bool CPositionManager::ClosePosition(ulong ticket)
{
   bool result = m_trade.PositionClose(ticket);

   if(result)
   {
      UpdatePositionList();
      if(m_enableLog) LogDebug(StringFormat("Position closed: Ticket=%d", ticket));
   }

   return result;
}

//+------------------------------------------------------------------+
//| 全ポジションをクローズ                                            |
//+------------------------------------------------------------------+
bool CPositionManager::CloseAllPositions()
{
   UpdatePositionList();

   bool allClosed = true;
   for(int i = m_positionCount - 1; i >= 0; i--)
   {
      if(!ClosePosition(m_positions[i].ticket))
         allClosed = false;
   }

   return allClosed;
}

//+------------------------------------------------------------------+
//| ポジションを変更                                                  |
//+------------------------------------------------------------------+
bool CPositionManager::ModifyPosition(ulong ticket, double sl, double tp)
{
   bool result = m_trade.PositionModify(ticket, sl, tp);

   if(result)
   {
      UpdatePositionList();
   }

   return result;
}

//+------------------------------------------------------------------+
//| ポジション数を取得                                                |
//+------------------------------------------------------------------+
int CPositionManager::GetPositionCount()
{
   UpdatePositionList();
   return m_positionCount;
}

//+------------------------------------------------------------------+
//| オープンポジションがあるか                                        |
//+------------------------------------------------------------------+
bool CPositionManager::HasOpenPosition()
{
   return GetPositionCount() > 0;
}

//+------------------------------------------------------------------+
//| 合計利益を取得                                                    |
//+------------------------------------------------------------------+
double CPositionManager::GetTotalProfit()
{
   UpdatePositionList();

   double total = 0;
   for(int i = 0; i < m_positionCount; i++)
   {
      total += GetPositionProfit(m_positions[i].ticket);
   }

   return total;
}

//+------------------------------------------------------------------+
//| 合計ロットを取得                                                  |
//+------------------------------------------------------------------+
double CPositionManager::GetTotalLots()
{
   UpdatePositionList();

   double total = 0;
   for(int i = 0; i < m_positionCount; i++)
   {
      total += m_positions[i].lots;
   }

   return total;
}

//+------------------------------------------------------------------+
//| ポジション情報を取得                                              |
//+------------------------------------------------------------------+
bool CPositionManager::GetPositionInfo(int index, PositionInfo &info)
{
   if(index < 0 || index >= m_positionCount)
      return false;

   info = m_positions[index];
   return true;
}

#endif // POSITION_MANAGER_MQH
