//+------------------------------------------------------------------+
//|                                                   GoldLongEA.mq5 |
//|                                  ゴールド（XAUUSD）ロング専用EA |
//|                 2本のローソク足パターン戦略 + レジスタンスゾーン |
//+------------------------------------------------------------------+
#property copyright "Gold Long Strategy EA v2.0"
#property version   "2.00"
#property description "2本のローソク足パターンを使用した押し目買い戦略"
#property description "対象：XAUUSD（ゴールド）ロングのみ"
#property description "エントリー：15分足 & 1時間足 / 利確：レジスタンスゾーン"

#include <Trade\Trade.mqh>

//--- Input Parameters
//--- 基本設定
input group "=== 基本設定 ==="
input double   LotSize = 0.01;                    // ロットサイズ
input int      MagicNumber = 234567;              // マジックナンバー
input string   TradeComment = "GoldLongEA_v2";    // コメント

//--- エントリー条件
input group "=== エントリー条件（ゴールド用） ==="
input double   MinWickDifference_Points = 80.0;   // 安値の最小差（ポイント）※100pt=1ドル
input double   MinBodySize_Points = 30.0;         // 最小実体サイズ（ポイント）
input bool     UseHighFilter = true;              // 勝率フィルター使用
input double   MaxUpperWick_Points = 50.0;        // 2本目の最大上ひげ（ポイント）

//--- 決済条件
input group "=== 決済条件 ==="
input double   StopLoss_Points = 350.0;              // 損切り（ポイント）※35ドル
input bool     UseResistanceZone = true;             // レジスタンスゾーン利確の使用
input int      ResistanceZoneLookback = 100;        // レジスタンス検出用の過去足数（H1）
input double   ResistanceZoneRange_Points = 50.0;   // レジスタンスゾーン判定範囲（±50pt）
input int      MinResistanceTouches = 3;            // レジスタンス判定の最小タッチ回数
input double   ResistanceExitRange_Points = 20.0;   // レジスタンス到達判定範囲（±20pt）
input bool     UseConditionalTP = true;             // 条件付き利確の使用（補助）

//--- トレード設定
input group "=== トレード設定 ==="
input int      MaxPositions = 1;                     // 最大ポジション数
input ENUM_TIMEFRAMES EntryTimeframe1 = PERIOD_M15;  // エントリー時間足1（15分足）
input ENUM_TIMEFRAMES EntryTimeframe2 = PERIOD_H1;   // エントリー時間足2（1時間足）
input bool     RequireBothTimeframes = true;         // 両方の時間足でシグナル必要
input int      Slippage = 50;                        // スリッページ（ポイント）

//--- Global Variables
CTrade trade;
datetime lastBarTime_M15 = 0;
datetime lastBarTime_H1 = 0;

//--- レジスタンスゾーン情報
struct ResistanceLevel
{
   double price;        // レジスタンス価格
   int touches;         // タッチ回数
};

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
   Print("ゴールドロング専用EA v2.0 初期化完了");
   Print("シンボル: ", symbol);
   Print("ロットサイズ: ", LotSize);
   Print("エントリー時間足: ", EnumToString(EntryTimeframe1), " & ", EnumToString(EntryTimeframe2));
   Print("両時間足シグナル必須: ", RequireBothTimeframes ? "はい" : "いいえ");
   Print("レジスタンスゾーン利確: ", UseResistanceZone ? "有効" : "無効");
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
   //--- 新しいバーのチェック（どちらかの時間足で新しいバーができたら）
   bool newBar_M15 = IsNewBar(EntryTimeframe1, lastBarTime_M15);
   bool newBar_H1 = IsNewBar(EntryTimeframe2, lastBarTime_H1);

   if(!newBar_M15 && !newBar_H1)
      return;  // 新しいバーがなければ何もしない

   //--- 既存ポジションの確認と管理
   if(CountPositions() > 0)
   {
      // レジスタンスゾーン利確チェック（最優先）
      if(UseResistanceZone)
         CheckResistanceZoneTakeProfit();

      // 条件付き利確チェック（補助）
      if(UseConditionalTP)
         CheckConditionalTakeProfit();
   }
   else
   {
      //--- 新規エントリーチェック
      if(CheckLongEntry())
      {
         OpenLongPosition();
      }
   }
}

//+------------------------------------------------------------------+
//| 新しいバーの検出（時間足別）                                      |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe, datetime &lastTime)
{
   datetime currentBarTime = iTime(_Symbol, timeframe, 0);

   if(currentBarTime != lastTime)
   {
      lastTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ロングエントリー条件チェック（複数時間足対応）                    |
//+------------------------------------------------------------------+
bool CheckLongEntry()
{
   bool signal_tf1 = CheckLongEntryOnTimeframe(EntryTimeframe1);
   bool signal_tf2 = CheckLongEntryOnTimeframe(EntryTimeframe2);

   if(RequireBothTimeframes)
   {
      // 両方の時間足でシグナルが必要
      if(signal_tf1 && signal_tf2)
      {
         Print("========================================");
         Print("★ エントリーシグナル確定！★");
         Print("両時間足でシグナル検出: ", EnumToString(EntryTimeframe1), " & ", EnumToString(EntryTimeframe2));
         Print("========================================");
         return true;
      }
   }
   else
   {
      // どちらかの時間足でシグナルがあればOK
      if(signal_tf1 || signal_tf2)
      {
         string tf = signal_tf1 ? EnumToString(EntryTimeframe1) : EnumToString(EntryTimeframe2);
         Print("========================================");
         Print("★ エントリーシグナル検出！★");
         Print("時間足: ", tf);
         Print("========================================");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| 指定時間足でのロングエントリー条件チェック                        |
//+------------------------------------------------------------------+
bool CheckLongEntryOnTimeframe(ENUM_TIMEFRAMES timeframe)
{
   //--- ローソク足データ取得（完成したバーのみ使用）
   double open1  = iOpen(_Symbol, timeframe, 1);   // 2本目（最新の完成バー）始値
   double high1  = iHigh(_Symbol, timeframe, 1);   // 2本目高値
   double low1   = iLow(_Symbol, timeframe, 1);    // 2本目安値
   double close1 = iClose(_Symbol, timeframe, 1);  // 2本目終値

   double open2  = iOpen(_Symbol, timeframe, 2);   // 1本目始値
   double high2  = iHigh(_Symbol, timeframe, 2);   // 1本目高値
   double low2   = iLow(_Symbol, timeframe, 2);    // 1本目安値
   double close2 = iClose(_Symbol, timeframe, 2);  // 1本目終値

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
      return false;

   //--- 3. 安値（Low）の比較：2本目の安値が1本目より明確に下
   double wickDifference = (low2 - low1) / _Point;  // 正の値 = 2本目が下

   if(wickDifference < MinWickDifference_Points)
      return false;

   //--- 4. 勝率フィルター（オプション）
   if(UseHighFilter)
   {
      // 4-1. 2本目の高値が1本目より低い
      if(high1 >= high2)
         return false;

      // 4-2. 2本目の上ひげが短い
      double upperWick1 = (high1 - close1) / _Point;  // 2本目の上ひげ

      if(upperWick1 > MaxUpperWick_Points)
         return false;
   }

   //--- すべての条件を満たした
   return true;
}

//+------------------------------------------------------------------+
//| ロングポジションを開く                                            |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- 損切り価格の計算：エントリー時間足の2本目の安値から35ドル（350ポイント）下
   // 優先的にM15の安値を使用（より精密）
   double entryLow = iLow(_Symbol, EntryTimeframe1, 1);
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
      Print("損切り価格: ", stopLoss, " (", EnumToString(EntryTimeframe1), " 安値 ", entryLow, " から ", StopLoss_Points/100, " ドル下)");
      Print("ロットサイズ: ", LotSize);

      // レジスタンスゾーンを表示
      if(UseResistanceZone)
      {
         double resistance = FindNearestResistanceZone();
         if(resistance > 0)
         {
            Print("目標レジスタンスゾーン: ", resistance, " (現在価格から +",
                  NormalizeDouble((resistance - entryPrice) / _Point, 0), " ポイント)");
         }
      }
   }
   else
   {
      Print("エラー: オーダー送信失敗 - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| レジスタンスゾーンでの利確チェック                                |
//+------------------------------------------------------------------+
void CheckResistanceZoneTakeProfit()
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

   //--- レジスタンスゾーンを検出
   double resistance = FindNearestResistanceZone();
   if(resistance <= 0)
      return;  // レジスタンスが見つからない

   //--- 現在価格を取得
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- レジスタンスゾーンに到達したかチェック
   double distanceToResistance = MathAbs(currentPrice - resistance) / _Point;

   if(distanceToResistance <= ResistanceExitRange_Points)
   {
      //--- レジスタンスゾーンに到達したので決済
      bool result = trade.PositionClose(ticket);

      if(result)
      {
         Print("========================================");
         Print("★ レジスタンスゾーン利確実行 ★");
         Print("利益: ", profit, " ドル");
         Print("レジスタンス価格: ", resistance);
         Print("決済価格: ", currentPrice);
         Print("到達距離: ", distanceToResistance, " ポイント");
         Print("========================================");
      }
      else
      {
         Print("エラー: 決済失敗 - ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| 最も近いレジスタンスゾーンを検出                                  |
//+------------------------------------------------------------------+
double FindNearestResistanceZone()
{
   //--- 現在価格を取得
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- レジスタンスレベルを格納する配列
   ResistanceLevel levels[];
   ArrayResize(levels, 0);

   //--- 1時間足の過去の高値を分析
   for(int i = 1; i <= ResistanceZoneLookback; i++)
   {
      double high = iHigh(_Symbol, PERIOD_H1, i);
      if(high == 0)
         continue;

      //--- 現在価格より上のレベルのみ対象
      if(high <= currentPrice)
         continue;

      //--- 既存のレジスタンスレベルと比較
      bool foundSimilar = false;
      for(int j = 0; j < ArraySize(levels); j++)
      {
         double priceDiff = MathAbs(high - levels[j].price) / _Point;

         if(priceDiff <= ResistanceZoneRange_Points)
         {
            //--- 同じゾーン内なので、タッチ回数を増やす
            levels[j].touches++;
            foundSimilar = true;
            break;
         }
      }

      //--- 新しいレジスタンスレベル
      if(!foundSimilar)
      {
         int newSize = ArraySize(levels) + 1;
         ArrayResize(levels, newSize);
         levels[newSize - 1].price = high;
         levels[newSize - 1].touches = 1;
      }
   }

   //--- 最小タッチ回数以上のレジスタンスレベルを抽出
   double nearestResistance = 0;
   double minDistance = 999999;

   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(levels[i].touches >= MinResistanceTouches)
      {
         double distance = levels[i].price - currentPrice;

         if(distance > 0 && distance < minDistance)
         {
            minDistance = distance;
            nearestResistance = levels[i].price;
         }
      }
   }

   return nearestResistance;
}

//+------------------------------------------------------------------+
//| 条件付き利確のチェック（補助）                                    |
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

   //--- エントリー時間足の最新の完成バーが陰線かチェック
   double open1  = iOpen(_Symbol, EntryTimeframe1, 1);
   double close1 = iClose(_Symbol, EntryTimeframe1, 1);

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
         Print("理由: 利益状態で陰線の実体が完成 (", EnumToString(EntryTimeframe1), ")");
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
