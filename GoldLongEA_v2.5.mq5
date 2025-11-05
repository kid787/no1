//+------------------------------------------------------------------+
//|                                              GoldLongEA_v2.5.mq5 |
//|                                  ゴールド（XAUUSD）ロング専用EA |
//|           2本のローソク足パターン + レジスタンス + トレーリング |
//+------------------------------------------------------------------+
#property copyright "Gold Long Strategy EA v2.5"
#property version   "2.50"
#property description "2本のローソク足パターンを使用した押し目買い戦略"
#property description "対象：XAUUSD（ゴールド）ロングのみ"
#property description "新機能：トレーリングストップ、時間帯フィルター、視覚化"

#include <Trade\Trade.mqh>

//--- Input Parameters
//--- 基本設定
input group "=== 基本設定 ==="
input double   LotSize = 0.01;                    // ロットサイズ
input int      MagicNumber = 234567;              // マジックナンバー
input string   TradeComment = "GoldLongEA_v2.5";  // コメント

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

//--- トレーリングストップ
input group "=== トレーリングストップ ==="
input bool     UseTrailingStop = true;              // トレーリングストップ使用
input double   TrailingStop_Points = 200.0;         // トレーリングストップ（ポイント）※20ドル
input double   TrailingStep_Points = 50.0;          // トレーリングステップ（ポイント）※5ドル
input double   TrailingStart_Points = 300.0;        // トレーリング開始利益（ポイント）※30ドル

//--- トレード設定
input group "=== トレード設定 ==="
input int      MaxPositions = 1;                     // 最大ポジション数
input ENUM_TIMEFRAMES EntryTimeframe1 = PERIOD_M15;  // エントリー時間足1（15分足）
input ENUM_TIMEFRAMES EntryTimeframe2 = PERIOD_H1;   // エントリー時間足2（1時間足）
input bool     RequireBothTimeframes = true;         // 両方の時間足でシグナル必要
input int      Slippage = 50;                        // スリッページ（ポイント）

//--- 時間帯フィルター
input group "=== 時間帯フィルター ==="
input bool     UseTimeFilter = false;                // 時間帯フィルター使用
input int      StartHour = 0;                        // 取引開始時刻（時）
input int      EndHour = 23;                         // 取引終了時刻（時）
input bool     AvoidWeekend = true;                  // 週末取引を避ける

//--- 表示設定
input group "=== 表示設定 ==="
input bool     ShowResistanceLines = true;           // レジスタンスラインを表示
input bool     ShowInfoPanel = true;                 // 情報パネルを表示
input color    ResistanceColor = clrRed;             // レジスタンスライン色
input int      LineWidth = 2;                        // ライン幅

//--- Global Variables
CTrade trade;
datetime lastBarTime_M15 = 0;
datetime lastBarTime_H1 = 0;

//--- 統計情報
int totalTrades = 0;
int winTrades = 0;
int lossTrades = 0;
double totalProfit = 0;

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

   //--- 既存のオブジェクトを削除
   DeleteAllObjects();

   Print("========================================");
   Print("ゴールドロング専用EA v2.5 初期化完了");
   Print("シンボル: ", symbol);
   Print("ロットサイズ: ", LotSize);
   Print("エントリー時間足: ", EnumToString(EntryTimeframe1), " & ", EnumToString(EntryTimeframe2));
   Print("両時間足シグナル必須: ", RequireBothTimeframes ? "はい" : "いいえ");
   Print("レジスタンスゾーン利確: ", UseResistanceZone ? "有効" : "無効");
   Print("トレーリングストップ: ", UseTrailingStop ? "有効" : "無効");
   Print("時間帯フィルター: ", UseTimeFilter ? "有効" : "無効");
   Print("損切り: ", StopLoss_Points, " ポイント (", StopLoss_Points/100, " ドル)");
   Print("========================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- オブジェクトを削除
   DeleteAllObjects();

   Print("========================================");
   Print("EA停止: ", reason);
   Print("総トレード数: ", totalTrades);
   Print("勝ちトレード: ", winTrades);
   Print("負けトレード: ", lossTrades);
   Print("勝率: ", totalTrades > 0 ? (winTrades * 100.0 / totalTrades) : 0, "%");
   Print("総利益: ", totalProfit, " ドル");
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 新しいバーのチェック（どちらかの時間足で新しいバーができたら）
   bool newBar_M15 = IsNewBar(EntryTimeframe1, lastBarTime_M15);
   bool newBar_H1 = IsNewBar(EntryTimeframe2, lastBarTime_H1);

   //--- レジスタンスゾーンを視覚化
   if(ShowResistanceLines && newBar_H1)
      DrawResistanceZones();

   //--- 情報パネルを表示
   if(ShowInfoPanel)
      UpdateInfoPanel();

   //--- 既存ポジションの管理（毎ティック）
   if(CountPositions() > 0)
   {
      //--- トレーリングストップ
      if(UseTrailingStop)
         ManageTrailingStop();

      //--- 新しいバーでのみ利確チェック
      if(newBar_M15 || newBar_H1)
      {
         // レジスタンスゾーン利確チェック（最優先）
         if(UseResistanceZone)
            CheckResistanceZoneTakeProfit();

         // 条件付き利確チェック（補助）
         if(UseConditionalTP)
            CheckConditionalTakeProfit();
      }
   }
   else
   {
      //--- 新規エントリーチェック（新しいバーでのみ）
      if(newBar_M15 || newBar_H1)
      {
         if(IsTimeAllowed() && CheckLongEntry())
         {
            OpenLongPosition();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 時間帯フィルターチェック                                          |
//+------------------------------------------------------------------+
bool IsTimeAllowed()
{
   if(!UseTimeFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   //--- 週末チェック
   if(AvoidWeekend && (dt.day_of_week == 0 || dt.day_of_week == 6))
      return false;

   //--- 時間帯チェック
   if(StartHour <= EndHour)
   {
      // 通常の時間帯（例：9-17時）
      if(dt.hour >= StartHour && dt.hour < EndHour)
         return true;
   }
   else
   {
      // 日をまたぐ時間帯（例：22-6時）
      if(dt.hour >= StartHour || dt.hour < EndHour)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| トレーリングストップ管理                                          |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!PositionSelect(_Symbol))
      return;

   //--- ポジション情報取得
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long posMagic = PositionGetInteger(POSITION_MAGIC);

   if(posMagic != MagicNumber)
      return;

   double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- 現在の利益をポイントで計算
   double profitPoints = (currentPrice - positionOpenPrice) / _Point;

   //--- トレーリング開始利益に達していない場合は何もしない
   if(profitPoints < TrailingStart_Points)
      return;

   //--- 新しいストップロス価格を計算
   double newSL = currentPrice - (TrailingStop_Points * _Point);

   //--- 価格を正規化
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   newSL = NormalizeDouble(newSL, digits);

   //--- 新しいSLが現在のSLより高い場合のみ更新
   if(newSL > currentSL + (TrailingStep_Points * _Point))
   {
      bool result = trade.PositionModify(ticket, newSL, 0);

      if(result)
      {
         Print("トレーリングストップ更新: SL = ", newSL, " (利益: ", NormalizeDouble(profitPoints/100, 1), " ドル)");
      }
   }
}

//+------------------------------------------------------------------+
//| レジスタンスゾーンを視覚化                                        |
//+------------------------------------------------------------------+
void DrawResistanceZones()
{
   //--- 既存のレジスタンスラインを削除
   for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(name, "Resistance_") == 0)
         ObjectDelete(0, name);
   }

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
            levels[j].touches++;
            // 平均価格を更新
            levels[j].price = (levels[j].price * (levels[j].touches - 1) + high) / levels[j].touches;
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

   //--- 最小タッチ回数以上のレジスタンスゾーンを描画
   int drawnLines = 0;
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(levels[i].touches >= MinResistanceTouches)
      {
         string objName = "Resistance_" + IntegerToString(drawnLines);

         if(ObjectCreate(0, objName, OBJ_HLINE, 0, 0, levels[i].price))
         {
            ObjectSetInteger(0, objName, OBJPROP_COLOR, ResistanceColor);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, LineWidth);
            ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, objName, OBJPROP_BACK, true);
            ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);

            string tooltip = "レジスタンス (" + IntegerToString(levels[i].touches) + "回タッチ)";
            ObjectSetString(0, objName, OBJPROP_TOOLTIP, tooltip);
         }

         drawnLines++;
      }
   }
}

//+------------------------------------------------------------------+
//| 情報パネルを更新                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
   string panelName = "InfoPanel";
   int x = 10;
   int y = 20;
   color textColor = clrWhite;
   int fontSize = 9;

   //--- パネルテキストを作成
   string info = "";
   info += "========== Gold Long EA v2.5 ==========\n";
   info += "総トレード: " + IntegerToString(totalTrades) + "\n";
   info += "勝ち: " + IntegerToString(winTrades) + " / 負け: " + IntegerToString(lossTrades) + "\n";

   if(totalTrades > 0)
      info += "勝率: " + DoubleToString(winTrades * 100.0 / totalTrades, 1) + "%\n";
   else
      info += "勝率: 0.0%\n";

   info += "総利益: " + DoubleToString(totalProfit, 2) + " USD\n";
   info += "--------------------------------------\n";

   //--- ポジション情報
   if(PositionSelect(_Symbol))
   {
      double profit = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double profitPoints = (currentPrice - openPrice) / _Point;

      info += "ポジション: オープン中\n";
      info += "利益: " + DoubleToString(profit, 2) + " USD\n";
      info += "    (" + DoubleToString(profitPoints/100, 1) + " ドル相当)\n";

      //--- レジスタンスまでの距離
      if(UseResistanceZone)
      {
         double resistance = FindNearestResistanceZone();
         if(resistance > 0)
         {
            double distancePoints = (resistance - currentPrice) / _Point;
            info += "レジスタンスまで: " + DoubleToString(distancePoints/100, 1) + " ドル\n";
         }
      }
   }
   else
   {
      info += "ポジション: なし\n";
      info += "シグナル待機中...\n";
   }

   //--- ラベルを作成または更新
   if(ObjectFind(0, panelName) < 0)
   {
      ObjectCreate(0, panelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, panelName, OBJPROP_COLOR, textColor);
      ObjectSetInteger(0, panelName, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, panelName, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);
   }

   ObjectSetString(0, panelName, OBJPROP_TEXT, info);
}

//+------------------------------------------------------------------+
//| すべてのオブジェクトを削除                                        |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   //--- レジスタンスライン削除
   for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(name, "Resistance_") == 0)
         ObjectDelete(0, name);
   }

   //--- 情報パネル削除
   ObjectDelete(0, "InfoPanel");
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
   double open1  = iOpen(_Symbol, timeframe, 1);
   double high1  = iHigh(_Symbol, timeframe, 1);
   double low1   = iLow(_Symbol, timeframe, 1);
   double close1 = iClose(_Symbol, timeframe, 1);

   double open2  = iOpen(_Symbol, timeframe, 2);
   double high2  = iHigh(_Symbol, timeframe, 2);
   double low2   = iLow(_Symbol, timeframe, 2);
   double close2 = iClose(_Symbol, timeframe, 2);

   if(open1 == 0 || open2 == 0)
      return false;

   bool isCandle1Bearish = (close2 < open2);
   bool isCandle2Bullish = (close1 > open1);

   if(!isCandle1Bearish || !isCandle2Bullish)
      return false;

   double body1 = MathAbs(close1 - open1) / _Point;
   double body2 = MathAbs(close2 - open2) / _Point;

   if(body1 < MinBodySize_Points || body2 < MinBodySize_Points)
      return false;

   double wickDifference = (low2 - low1) / _Point;

   if(wickDifference < MinWickDifference_Points)
      return false;

   if(UseHighFilter)
   {
      if(high1 >= high2)
         return false;

      double upperWick1 = (high1 - close1) / _Point;

      if(upperWick1 > MaxUpperWick_Points)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ロングポジションを開く                                            |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double entryLow = iLow(_Symbol, EntryTimeframe1, 1);
   double stopLoss = entryLow - (StopLoss_Points * _Point);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);

   bool result = trade.Buy(LotSize, _Symbol, entryPrice, stopLoss, 0, TradeComment);

   if(result)
   {
      Print("★ ロングポジション開始 ★");
      Print("エントリー価格: ", entryPrice);
      Print("損切り価格: ", stopLoss, " (", EnumToString(EntryTimeframe1), " 安値 ", entryLow, " から ", StopLoss_Points/100, " ドル下)");
      Print("ロットサイズ: ", LotSize);

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
   if(!PositionSelect(_Symbol))
      return;

   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long posMagic = PositionGetInteger(POSITION_MAGIC);

   if(posMagic != MagicNumber)
      return;

   double profit = PositionGetDouble(POSITION_PROFIT);
   if(profit <= 0)
      return;

   double resistance = FindNearestResistanceZone();
   if(resistance <= 0)
      return;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double distanceToResistance = MathAbs(currentPrice - resistance) / _Point;

   if(distanceToResistance <= ResistanceExitRange_Points)
   {
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

         //--- 統計更新
         totalTrades++;
         if(profit > 0)
            winTrades++;
         else
            lossTrades++;
         totalProfit += profit;
      }
   }
}

//+------------------------------------------------------------------+
//| 最も近いレジスタンスゾーンを検出                                  |
//+------------------------------------------------------------------+
double FindNearestResistanceZone()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ResistanceLevel levels[];
   ArrayResize(levels, 0);

   for(int i = 1; i <= ResistanceZoneLookback; i++)
   {
      double high = iHigh(_Symbol, PERIOD_H1, i);
      if(high == 0)
         continue;

      if(high <= currentPrice)
         continue;

      bool foundSimilar = false;
      for(int j = 0; j < ArraySize(levels); j++)
      {
         double priceDiff = MathAbs(high - levels[j].price) / _Point;

         if(priceDiff <= ResistanceZoneRange_Points)
         {
            levels[j].touches++;
            foundSimilar = true;
            break;
         }
      }

      if(!foundSimilar)
      {
         int newSize = ArraySize(levels) + 1;
         ArrayResize(levels, newSize);
         levels[newSize - 1].price = high;
         levels[newSize - 1].touches = 1;
      }
   }

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
   if(!PositionSelect(_Symbol))
      return;

   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long posMagic = PositionGetInteger(POSITION_MAGIC);

   if(posMagic != MagicNumber)
      return;

   double profit = PositionGetDouble(POSITION_PROFIT);
   if(profit <= 0)
      return;

   double open1  = iOpen(_Symbol, EntryTimeframe1, 1);
   double close1 = iClose(_Symbol, EntryTimeframe1, 1);

   bool isBearishBar = (close1 < open1);

   if(isBearishBar)
   {
      bool result = trade.PositionClose(ticket);

      if(result)
      {
         Print("========================================");
         Print("★ 条件付き利確実行 ★");
         Print("利益: ", profit, " ドル");
         Print("理由: 利益状態で陰線の実体が完成 (", EnumToString(EntryTimeframe1), ")");
         Print("========================================");

         //--- 統計更新
         totalTrades++;
         if(profit > 0)
            winTrades++;
         else
            lossTrades++;
         totalProfit += profit;
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
