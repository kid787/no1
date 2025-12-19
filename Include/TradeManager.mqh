//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|                          Trade Entry and Exit Management         |
//+------------------------------------------------------------------+
#property copyright "Trade Manager Module"
#property version   "1.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Trade Manager Class                                              |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade   m_Trade;
   string   m_Symbol;
   int      m_MagicNumber;
   double   m_BreakevenTriggerPips;     // 建値移動のトリガー（pips）
   double   m_BreakevenOffsetPips;      // 建値からのオフセット（pips）
   double   m_PartialClosePips[];       // 分割決済のpips配列
   double   m_PartialClosePercent[];    // 分割決済のパーセント配列
   double   m_SLBufferPercent;          // 損切りラインの余裕（%）

   // v2.1: 新規追加
   double   m_MinRiskRewardRatio;       // 最小リスクリワード比
   double   m_MaxLossPercent;           // 1トレードあたりの最大損失率（%）
   bool     m_UseTrailingStop;          // トレーリングストップ使用
   double   m_TrailingStartPips;        // トレーリング開始pips
   double   m_TrailingStepPips;         // トレーリングステップpips

public:
   //--- コンストラクタ
   CTradeManager(string symbol = NULL, int magicNumber = 123456)
   {
      m_Symbol = (symbol == NULL) ? _Symbol : symbol;
      m_MagicNumber = magicNumber;
      m_Trade.SetExpertMagicNumber(m_MagicNumber);

      // デフォルト設定
      m_BreakevenTriggerPips = 150.0;   // 15ドル（XAUUSDでは1pip=0.1ドル）
      m_BreakevenOffsetPips = 10.0;     // 1ドル

      // 分割決済の設定
      ArrayResize(m_PartialClosePips, 3);
      ArrayResize(m_PartialClosePercent, 3);

      m_PartialClosePips[0] = 200.0;    // 20ドルで30%決済
      m_PartialClosePercent[0] = 0.3;

      m_PartialClosePips[1] = 400.0;    // 40ドルで30%決済
      m_PartialClosePercent[1] = 0.3;

      m_PartialClosePips[2] = 600.0;    // 60ドルで残り決済
      m_PartialClosePercent[2] = 0.4;

      m_SLBufferPercent = 3.0;          // 損切りラインに3%の余裕

      // v2.1: 新規パラメータの初期値
      m_MinRiskRewardRatio = 1.5;       // 最小RR比 1:1.5
      m_MaxLossPercent = 2.0;           // 1トレード最大2%損失
      m_UseTrailingStop = true;         // トレーリングストップ有効
      m_TrailingStartPips = 200.0;      // 20ドルから開始
      m_TrailingStepPips = 50.0;        // 5ドルステップ
   }

   //--- 設定
   void SetBreakevenSettings(double triggerPips, double offsetPips)
   {
      m_BreakevenTriggerPips = triggerPips;
      m_BreakevenOffsetPips = offsetPips;
   }

   void SetPartialClose(int index, double pips, double percent)
   {
      if(index >= 0 && index < ArraySize(m_PartialClosePips))
      {
         m_PartialClosePips[index] = pips;
         m_PartialClosePercent[index] = percent;
      }
   }

   void SetSLBuffer(double percent)
   {
      m_SLBufferPercent = percent;
   }

   //--- v2.1: 新規設定メソッド
   void SetRiskRewardRatio(double minRR)
   {
      m_MinRiskRewardRatio = minRR;
   }

   void SetMaxLossPercent(double maxLoss)
   {
      m_MaxLossPercent = maxLoss;
   }

   void SetTrailingStop(bool use, double startPips, double stepPips)
   {
      m_UseTrailingStop = use;
      m_TrailingStartPips = startPips;
      m_TrailingStepPips = stepPips;
   }

   //--- ピップサイズの取得
   double GetPipSize()
   {
      int digits = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);

      if(digits == 3 || digits == 5)
         return point * 10.0;
      else
         return point;
   }

   //--- エントリー
   bool OpenBuyPosition(double lots, double slPrice, double tpPrice, string comment = "")
   {
      double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      if(m_Trade.Buy(lots, m_Symbol, ask, slPrice, tpPrice, comment))
      {
         Print("買いポジションオープン成功: Lot=", lots, " SL=", slPrice, " TP=", tpPrice);
         return true;
      }
      else
      {
         Print("買いポジションオープン失敗: ", m_Trade.ResultRetcodeDescription());
         return false;
      }
   }

   bool OpenSellPosition(double lots, double slPrice, double tpPrice, string comment = "")
   {
      double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);

      if(m_Trade.Sell(lots, m_Symbol, bid, slPrice, tpPrice, comment))
      {
         Print("売りポジションオープン成功: Lot=", lots, " SL=", slPrice, " TP=", tpPrice);
         return true;
      }
      else
      {
         Print("売りポジションオープン失敗: ", m_Trade.ResultRetcodeDescription());
         return false;
      }
   }

   //--- 損切り価格の計算（ダウ理論 + 余裕）
   double CalculateSLPrice(bool isBuy, double swingPrice)
   {
      double buffer = swingPrice * (m_SLBufferPercent / 100.0);

      if(isBuy)
         return swingPrice - buffer;  // 買いの場合、直近安値より下
      else
         return swingPrice + buffer;  // 売りの場合、直近高値より上
   }

   //--- 利確価格の計算（複数ターゲット）
   void CalculateTPPrices(bool isBuy, double entryPrice, double tp1, double tp2, double tp3,
                          double &outTP1, double &outTP2, double &outTP3)
   {
      double pipSize = GetPipSize();

      if(isBuy)
      {
         outTP1 = entryPrice + (tp1 * pipSize);
         outTP2 = entryPrice + (tp2 * pipSize);
         outTP3 = entryPrice + (tp3 * pipSize);
      }
      else
      {
         outTP1 = entryPrice - (tp1 * pipSize);
         outTP2 = entryPrice - (tp2 * pipSize);
         outTP3 = entryPrice - (tp3 * pipSize);
      }
   }

   //--- 建値移動
   bool MoveToBreakeven(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return false;

      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionSL = PositionGetDouble(POSITION_SL);
      int positionType = (int)PositionGetInteger(POSITION_TYPE);

      double currentPrice = (positionType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(m_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      double pipSize = GetPipSize();
      double triggerDistance = m_BreakevenTriggerPips * pipSize;
      double bePrice = positionOpenPrice + (m_BreakevenOffsetPips * pipSize) *
                       ((positionType == POSITION_TYPE_BUY) ? 1 : -1);

      // トリガー距離に達しているかチェック
      bool shouldMove = false;
      if(positionType == POSITION_TYPE_BUY)
      {
         shouldMove = (currentPrice >= positionOpenPrice + triggerDistance) &&
                      (positionSL < positionOpenPrice);
      }
      else
      {
         shouldMove = (currentPrice <= positionOpenPrice - triggerDistance) &&
                      (positionSL > positionOpenPrice || positionSL == 0);
      }

      if(shouldMove)
      {
         double positionTP = PositionGetDouble(POSITION_TP);
         if(m_Trade.PositionModify(ticket, bePrice, positionTP))
         {
            Print("建値移動成功: Ticket=", ticket, " 新SL=", bePrice);
            return true;
         }
         else
         {
            Print("建値移動失敗: ", m_Trade.ResultRetcodeDescription());
            return false;
         }
      }

      return false;
   }

   //--- 分割決済
   bool PartialClose(ulong ticket, int targetLevel)
   {
      if(!PositionSelectByTicket(ticket))
         return false;

      if(targetLevel < 0 || targetLevel >= ArraySize(m_PartialClosePips))
         return false;

      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionVolume = PositionGetDouble(POSITION_VOLUME);
      int positionType = (int)PositionGetInteger(POSITION_TYPE);

      double currentPrice = (positionType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(m_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      double pipSize = GetPipSize();
      double targetDistance = m_PartialClosePips[targetLevel] * pipSize;

      // ターゲット価格に達しているかチェック
      bool targetReached = false;
      if(positionType == POSITION_TYPE_BUY)
         targetReached = (currentPrice >= positionOpenPrice + targetDistance);
      else
         targetReached = (currentPrice <= positionOpenPrice - targetDistance);

      if(targetReached)
      {
         double closeVolume = positionVolume * m_PartialClosePercent[targetLevel];
         closeVolume = NormalizeLot(closeVolume);

         if(closeVolume >= SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MIN))
         {
            if(m_Trade.PositionClosePartial(ticket, closeVolume))
            {
               Print("分割決済成功: Ticket=", ticket, " Level=", targetLevel,
                     " Volume=", closeVolume, " 残り=", positionVolume - closeVolume);
               return true;
            }
            else
            {
               Print("分割決済失敗: ", m_Trade.ResultRetcodeDescription());
            }
         }
      }

      return false;
   }

   //--- ロット正規化
   double NormalizeLot(double lots)
   {
      double minLot = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_STEP);

      if(lots < minLot)
         return 0.0;

      if(lots > maxLot)
         lots = maxLot;

      lots = MathFloor(lots / lotStep) * lotStep;

      if(lots < minLot)
         return 0.0;

      return lots;
   }

   //--- 全ポジション管理
   void ManageAllPositions()
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) != m_Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_MagicNumber) continue;

            // 建値移動チェック
         MoveToBreakeven(ticket);

         // v2.1: トレーリングストップチェック
         if(m_UseTrailingStop)
            TrailingStop(ticket);

         // 分割決済チェック
         for(int level = 0; level < ArraySize(m_PartialClosePips); level++)
         {
            PartialClose(ticket, level);
         }
      }
   }

   //--- 現在のポジション数を取得
   int GetPositionCount()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) == m_Symbol &&
            PositionGetInteger(POSITION_MAGIC) == m_MagicNumber)
         {
            count++;
         }
      }
      return count;
   }

   //--- 現在のポジション方向を取得（なければ-1）
   int GetPositionType()
   {
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) == m_Symbol &&
            PositionGetInteger(POSITION_MAGIC) == m_MagicNumber)
         {
            return (int)PositionGetInteger(POSITION_TYPE);
         }
      }
      return -1;
   }

   //--- すべてのポジションをクローズ
   void CloseAllPositions()
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) != m_Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_MagicNumber) continue;

            m_Trade.PositionClose(ticket);
      }
   }

   //+------------------------------------------------------------------+
   //| v2.1: リスクリワード比をチェック                                  |
   //+------------------------------------------------------------------+
   bool CheckRiskReward(double entryPrice, double slPrice, double tpPrice)
   {
      // v2.2: MinRiskRewardRatio = 0の場合はチェックをスキップ
      if(m_MinRiskRewardRatio <= 0)
         return true;

      double slDistance = MathAbs(entryPrice - slPrice);
      double tpDistance = MathAbs(tpPrice - entryPrice);

      if(slDistance <= 0) return false;

      double rrRatio = tpDistance / slDistance;

      if(rrRatio < m_MinRiskRewardRatio)
      {
         Print("RR比が不十分: ", DoubleToString(rrRatio, 2),
               " < ", DoubleToString(m_MinRiskRewardRatio, 2));
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| v2.1: 最大損失額チェック                                          |
   //+------------------------------------------------------------------+
   bool CheckMaxLoss(double lots, double slPips)
   {
      double pipValue = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                        SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_SIZE) *
                        GetPipSize();

      double potentialLoss = lots * slPips * pipValue;
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double lossPercent = (potentialLoss / accountBalance) * 100.0;

      if(lossPercent > m_MaxLossPercent)
      {
         Print("1トレードの損失が大きすぎ: ", DoubleToString(lossPercent, 2),
               "% > ", DoubleToString(m_MaxLossPercent, 2), "%");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| v2.1: トレーリングストップ                                        |
   //+------------------------------------------------------------------+
   bool TrailingStop(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return false;

      double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double positionSL = PositionGetDouble(POSITION_SL);
      double positionTP = PositionGetDouble(POSITION_TP);
      int positionType = (int)PositionGetInteger(POSITION_TYPE);

      double currentPrice = (positionType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(m_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(m_Symbol, SYMBOL_ASK);

      double pipSize = GetPipSize();
      double startDistance = m_TrailingStartPips * pipSize;
      double stepDistance = m_TrailingStepPips * pipSize;

      bool shouldUpdate = false;
      double newSL = positionSL;

      if(positionType == POSITION_TYPE_BUY)
      {
         // 買いポジション
         double profit = currentPrice - positionOpenPrice;

         // トレーリング開始条件
         if(profit >= startDistance)
         {
            // 現在価格からステップ分戻した位置
            double trailingSL = currentPrice - stepDistance;

            // 現在のSLより有利な位置なら更新
            if(trailingSL > positionSL || positionSL == 0)
            {
               newSL = trailingSL;
               shouldUpdate = true;
            }
         }
      }
      else
      {
         // 売りポジション
         double profit = positionOpenPrice - currentPrice;

         // トレーリング開始条件
         if(profit >= startDistance)
         {
            // 現在価格からステップ分上げた位置
            double trailingSL = currentPrice + stepDistance;

            // 現在のSLより有利な位置なら更新
            if(trailingSL < positionSL || positionSL == 0)
            {
               newSL = trailingSL;
               shouldUpdate = true;
            }
         }
      }

      if(shouldUpdate)
      {
         if(m_Trade.PositionModify(ticket, newSL, positionTP))
         {
            Print("トレーリングストップ更新: Ticket=", ticket,
                  " 新SL=", newSL);
            return true;
         }
      }

      return false;
   }
};
