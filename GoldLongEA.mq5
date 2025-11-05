//+------------------------------------------------------------------+
//|                                                   GoldLongEA.mq5 |
//|                                  ゴールド（XAUUSD）ロング専用EA |
//|                                   2本のローソク足パターン戦略    |
//+------------------------------------------------------------------+
#property copyright "Gold Long Strategy EA"
#property version   "1.00"
#property description "2本のローソク足パターンを使用した押し目買い戦略"
#property description "対象：XAUUSD（ゴールド）ロングのみ"

#include <Trade\Trade.mqh>

//--- Input Parameters
//--- 基本設定
input group "=== 基本設定 ==="
input double   LotSize = 0.01;                    // ロットサイズ
input int      MagicNumber = 234567;              // マジックナンバー
input string   TradeComment = "GoldLongEA";       // コメント

//--- エントリー条件
input group "=== エントリー条件（ゴールド用） ==="
input double   MinWickDifference_Points = 80.0;   // 安値の最小差（ポイント）※100pt=1ドル
input double   MinBodySize_Points = 30.0;         // 最小実体サイズ（ポイント）
input bool     UseHighFilter = true;              // 勝率フィルター使用
input double   MaxUpperWick_Points = 50.0;        // 2本目の最大上ひげ（ポイント）

//--- 決済条件
input group "=== 決済条件 ==="
input double   StopLoss_Points = 350.0;           // 損切り（ポイント）※35ドル
input bool     UseConditionalTP = true;           // 条件付き利確の使用

//--- トレード設定
input group "=== トレード設定 ==="
input int      MaxPositions = 1;                  // 最大ポジション数
input int      Slippage = 50;                     // スリッページ（ポイント）

//--- Global Variables
CTrade trade;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- EAの基本設定
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   //--- シンボルチェック
   string symbol = _Symbol;
   if(StringFind(symbol, "XAU") < 0 && StringFind(symbol, "GOLD") < 0)
   {
      Print("警告: このEAはゴールド（XAUUSD）専用です。現在のシンボル: ", symbol);
   }

   Print("========================================");
   Print("ゴールドロング専用EA 初期化完了");
   Print("シンボル: ", symbol);
   Print("ロットサイズ: ", LotSize);
   Print("損切り: ", StopLoss_Points, " ポイント (", StopLoss_Points/100, " ドル)");
   Print("========================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA停止: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 新しいバーのチェック
   if(!IsNewBar())
      return;

   //--- 既存ポジションの確認と管理
   if(UseConditionalTP)
      CheckConditionalTakeProfit();

   //--- 新規エントリーチェック
   if(CountPositions() < MaxPositions)
   {
      if(CheckLongEntry())
      {
         OpenLongPosition();
      }
   }
}

//+------------------------------------------------------------------+
//| 新しいバーの検出                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ロングエントリー条件チェック                                      |
//+------------------------------------------------------------------+
bool CheckLongEntry()
{
   //--- ローソク足データ取得（完成したバーのみ使用）
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);   // 2本目（最新の完成バー）始値
   double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);   // 2本目高値
   double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);    // 2本目安値
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);  // 2本目終値

   double open2  = iOpen(_Symbol, PERIOD_CURRENT, 2);   // 1本目始値
   double high2  = iHigh(_Symbol, PERIOD_CURRENT, 2);   // 1本目高値
   double low2   = iLow(_Symbol, PERIOD_CURRENT, 2);    // 1本目安値
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);  // 1本目終値

   //--- データ取得エラーチェック
   if(open1 == 0 || open2 == 0)
      return false;

   //--- 1. ローソク足パターンチェック：1本目=陰線、2本目=陽線
   bool isCandle1Bearish = (close2 < open2);  // 1本目が陰線
   bool isCandle2Bullish = (close1 > open1);  // 2本目が陽線

   if(!isCandle1Bearish || !isCandle2Bullish)
      return false;

   //--- 2. 実体サイズのチェック
   double body1 = MathAbs(close1 - open1) / _Point;  // 2本目の実体
   double body2 = MathAbs(close2 - open2) / _Point;  // 1本目の実体

   if(body1 < MinBodySize_Points || body2 < MinBodySize_Points)
   {
      Print("エントリー見送り: 実体サイズ不足 (1本目:", body2, "pt, 2本目:", body1, "pt)");
      return false;
   }

   //--- 3. 安値（Low）の比較：2本目の安値が1本目より明確に下
   double wickDifference = (low2 - low1) / _Point;  // 正の値 = 2本目が下

   if(wickDifference < MinWickDifference_Points)
   {
      Print("エントリー見送り: 安値の差が不足 (差:", wickDifference, "pt, 必要:", MinWickDifference_Points, "pt)");
      return false;
   }

   //--- 4. 勝率フィルター（オプション）
   if(UseHighFilter)
   {
      // 4-1. 2本目の高値が1本目より低い
      if(high1 >= high2)
      {
         Print("エントリー見送り: 2本目の高値が1本目以上");
         return false;
      }

      // 4-2. 2本目の上ひげが短い
      double upperWick1 = (high1 - close1) / _Point;  // 2本目の上ひげ

      if(upperWick1 > MaxUpperWick_Points)
      {
         Print("エントリー見送り: 2本目の上ひげが長すぎる (", upperWick1, "pt)");
         return false;
      }
   }

   //--- すべての条件を満たした
   Print("========================================");
   Print("ロングエントリーシグナル検出！");
   Print("1本目 - 始値:", open2, " 終値:", close2, " 安値:", low2, " (陰線)");
   Print("2本目 - 始値:", open1, " 終値:", close1, " 安値:", low1, " (陽線)");
   Print("安値の差: ", wickDifference, " ポイント");
   Print("========================================");

   return true;
}

//+------------------------------------------------------------------+
//| ロングポジションを開く                                            |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- 損切り価格の計算：2本目の安値から35ドル（350ポイント）下
   double entryLow = iLow(_Symbol, PERIOD_CURRENT, 1);  // 2本目の安値
   double stopLoss = entryLow - (StopLoss_Points * _Point);

   //--- 価格の正規化
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);

   //--- オーダー送信
   bool result = trade.Buy(LotSize, _Symbol, entryPrice, stopLoss, 0, TradeComment);

   if(result)
   {
      Print("★ ロングポジション開始 ★");
      Print("エントリー価格: ", entryPrice);
      Print("損切り価格: ", stopLoss, " (2本目安値 ", entryLow, " から ", StopLoss_Points/100, " ドル下)");
      Print("ロットサイズ: ", LotSize);
   }
   else
   {
      Print("エラー: オーダー送信失敗 - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 条件付き利確のチェック                                            |
//+------------------------------------------------------------------+
void CheckConditionalTakeProfit()
{
   //--- ポジションがなければ何もしない
   if(!PositionSelect(_Symbol))
      return;

   //--- ポジション情報取得
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long posMagic = PositionGetInteger(POSITION_MAGIC);

   //--- マジックナンバーチェック
   if(posMagic != MagicNumber)
      return;

   //--- 利益状態かチェック
   double profit = PositionGetDouble(POSITION_PROFIT);

   if(profit <= 0)
      return;  // 利益が出ていない場合は何もしない

   //--- 最新の完成バーが陰線かチェック
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool isBearishBar = (close1 < open1);  // 陰線

   if(isBearishBar)
   {
      //--- 条件を満たしたので決済
      bool result = trade.PositionClose(ticket);

      if(result)
      {
         Print("========================================");
         Print("★ 条件付き利確実行 ★");
         Print("利益: ", profit, " ドル");
         Print("理由: 利益状態で陰線の実体が完成");
         Print("========================================");
      }
      else
      {
         Print("エラー: 決済失敗 - ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| 現在のポジション数をカウント                                      |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
