//+------------------------------------------------------------------+
//|                                       FintokeiLotCalculator.mq5  |
//|                     Fintokei Challenge Lot Calculator Indicator  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Lot Calculator"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0
#property description "Fintokeiチャレンジプラン対応ロット計算インジケーター"
#property description "損失制限を考慮した安全なロットサイズを計算"

//+------------------------------------------------------------------+
//| 入力パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== Fintokei設定 ==="
input double   InitialBalance       = 100000.0;    // 初期残高
input double   DailyLossLimitPct    = 5.0;         // 1日の最大損失率（%）
input double   OverallLossLimitPct  = 10.0;        // 全体の最大損失率（%）
input double   SafetyBufferPct      = 0.1;         // 安全バッファ（%）

input group "=== リスク設定 ==="
input double   RiskPercent          = 1.0;         // 1トレードのリスク（%）※控えめ推奨
input int      LotDigits            = 2;           // ロット表示桁数

input group "=== ライン設定 ==="
input double   InitialSL_Pips       = 300.0;       // 初期損切り幅（Pips）
input double   InitialTP_Pips       = 600.0;       // 初期利確幅（Pips）
input int      LineWidth            = 3;           // ラインの太さ

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
string slLineName = "FLC_StopLoss";
string tpLineName = "FLC_TakeProfit";
string objPrefix = "FLC_";
double currentPrice = 0;

// Fintokei日次基準額
double DailyStartingEquity = 0;
datetime lastResetDateUTC = 0;

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // 現在価格の取得
   currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Pip サイズの計算
   double pipSize = GetPipSize();

   // 初期ライン位置の計算
   double slPrice = currentPrice - (InitialSL_Pips * pipSize);
   double tpPrice = currentPrice + (InitialTP_Pips * pipSize);

   // 損切りライン作成（マゼンタ）
   if(ObjectFind(0, slLineName) < 0)
   {
      ObjectCreate(0, slLineName, OBJ_HLINE, 0, 0, slPrice);
      ObjectSetInteger(0, slLineName, OBJPROP_COLOR, C'255,0,255');
      ObjectSetInteger(0, slLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, slLineName, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, slLineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, slLineName, OBJPROP_SELECTED, true);
      ObjectSetString(0, slLineName, OBJPROP_TEXT, "損切りライン");
   }
   else
   {
      ObjectSetInteger(0, slLineName, OBJPROP_SELECTED, true);
   }

   // 利確ライン作成（ライムグリーン）
   if(ObjectFind(0, tpLineName) < 0)
   {
      ObjectCreate(0, tpLineName, OBJ_HLINE, 0, 0, tpPrice);
      ObjectSetInteger(0, tpLineName, OBJPROP_COLOR, C'50,205,50');
      ObjectSetInteger(0, tpLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, tpLineName, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, tpLineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, tpLineName, OBJPROP_SELECTED, true);
      ObjectSetString(0, tpLineName, OBJPROP_TEXT, "利確ライン");
   }
   else
   {
      ObjectSetInteger(0, tpLineName, OBJPROP_SELECTED, true);
   }

   // Fintokei日次基準額の初期化
   InitializeDailyEquity();

   // 初期計算
   UpdateCalculations();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター終了関数                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ラインオブジェクトの削除
   ObjectDelete(0, slLineName);
   ObjectDelete(0, tpLineName);

   // ラベルオブジェクトの削除
   ObjectsDeleteAll(0, objPrefix);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| カスタムインジケーター計算関数                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // CPU負荷軽減のため、自動更新は行わない
   // ラインドラッグ時のみ更新（OnChartEvent参照）
   return(rates_total);
}

//+------------------------------------------------------------------+
//| チャートイベントハンドラ                                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // オブジェクトがドラッグされた場合
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(sparam == slLineName || sparam == tpLineName)
      {
         UpdateCalculations();
      }
   }

   // マウスクリック時にも更新（価格変動対応）
   if(id == CHARTEVENT_CLICK)
   {
      UpdateCalculations();
   }
}

//+------------------------------------------------------------------+
//| Fintokei日次基準額の初期化                                         |
//+------------------------------------------------------------------+
void InitializeDailyEquity()
{
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   string gvName = "FLC_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);

   if(GlobalVariableCheck(gvName))
   {
      DailyStartingEquity = GlobalVariableGet(gvName);
      lastResetDateUTC = todayResetUTC;
   }
   else
   {
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;
      GlobalVariableSet(gvName, DailyStartingEquity);
   }
}

//+------------------------------------------------------------------+
//| 日次リセットのチェック                                             |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   if(todayResetUTC > lastResetDateUTC)
   {
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;

      string gvName = "FLC_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
      GlobalVariableSet(gvName, DailyStartingEquity);
   }
}

//+------------------------------------------------------------------+
//| 全計算の更新                                                       |
//+------------------------------------------------------------------+
void UpdateCalculations()
{
   // 日次リセットチェック
   CheckDailyReset();

   // 現在価格の更新
   currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ライン価格の取得
   double slPrice = ObjectGetDouble(0, slLineName, OBJPROP_PRICE);
   double tpPrice = ObjectGetDouble(0, tpLineName, OBJPROP_PRICE);

   if(slPrice == 0 || tpPrice == 0)
   {
      return;
   }

   // Pips距離の計算
   double pipSize = GetPipSize();
   double slPips = MathAbs(currentPrice - slPrice) / pipSize;
   double tpPips = MathAbs(tpPrice - currentPrice) / pipSize;

   // 口座情報
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Fintokei制限の計算
   double effectiveDailyLimit = DailyLossLimitPct - SafetyBufferPct;
   double effectiveOverallLimit = OverallLossLimitPct - SafetyBufferPct;

   // 残りリスク余裕の計算
   double overallLossLine = InitialBalance * (1.0 - effectiveOverallLimit / 100.0);
   double dailyLossLine = DailyStartingEquity * (1.0 - effectiveDailyLimit / 100.0);

   double overallMargin = accountEquity - overallLossLine;
   double dailyMargin = accountEquity - dailyLossLine;
   double minMargin = MathMin(overallMargin, dailyMargin);

   // 標準リスク額の計算
   double standardRiskAmount = accountBalance * (RiskPercent / 100.0);

   // Fintokei制限を考慮した最大リスク額（残りマージンの50%を上限）
   double maxAllowedRisk = minMargin * 0.5;

   // 実際に使用するリスク額
   double actualRiskAmount = MathMin(standardRiskAmount, maxAllowedRisk);
   if(actualRiskAmount < 0) actualRiskAmount = 0;

   bool isRiskLimited = (actualRiskAmount < standardRiskAmount);

   // ロットサイズの計算
   double lossPerLot = CalculateLossPerLot(slPips);
   double calculatedLots = 0.0;
   if(lossPerLot > 0)
   {
      calculatedLots = actualRiskAmount / lossPerLot;
   }
   double normalizedLots = NormalizeLotSize(calculatedLots);

   // リスクリワード比の計算
   double rrRatio = 0.0;
   if(slPips > 0)
   {
      rrRatio = tpPips / slPips;
   }

   // 期待利益の計算
   double profitPerLot = CalculateProfitPerLot(tpPips);
   double expectedProfit = profitPerLot * normalizedLots;

   // 現在の損失率
   double overallLossPercent = ((InitialBalance - accountEquity) / InitialBalance) * 100.0;
   double dailyLossPercent = ((DailyStartingEquity - accountEquity) / DailyStartingEquity) * 100.0;

   // 表示更新
   int yPos = 30;
   int yStep = 18;

   // ヘッダー
   CreateLabel("Header", "■ FINTOKEI LOT CALCULATOR ■", 10, yPos, clrGold, 12, true);
   yPos += yStep + 5;

   CreateLabel("Sep1", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 10, yPos, clrGray, 9, false);
   yPos += yStep;

   // 推奨ロット（大きく表示）
   color lotColor = isRiskLimited ? clrOrange : clrYellow;
   CreateLabel("LotDisplay", StringFormat("推奨: %." + IntegerToString(LotDigits) + "f Lot", normalizedLots),
               10, yPos, lotColor, 24, true);
   yPos += 35;

   // リスク制限警告
   if(isRiskLimited)
   {
      CreateLabel("RiskWarning", "※ Fintokei制限によりリスク額を制限中",
                  10, yPos, clrOrange, 9, false);
      yPos += yStep;
   }

   // SL/TP情報
   CreateLabel("SLInfo", StringFormat("SL: %.1f pips | 損失: %.0f円 (%.2f%%)",
               slPips, actualRiskAmount, (actualRiskAmount/accountBalance)*100),
               10, yPos, clrWhite, 9, false);
   yPos += yStep;

   CreateLabel("TPInfo", StringFormat("TP: %.1f pips | RR 1:%.2f | 利益: %.0f円",
               tpPips, rrRatio, expectedProfit),
               10, yPos, clrLime, 9, false);
   yPos += yStep + 5;

   CreateLabel("Sep2", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 10, yPos, clrGray, 9, false);
   yPos += yStep;

   // Fintokei制限情報
   CreateLabel("FintokeiTitle", "【Fintokei制限状況】", 10, yPos, clrWhite, 10, true);
   yPos += yStep;

   color overallColor = GetStatusColor(overallLossPercent, OverallLossLimitPct);
   CreateLabel("OverallLoss", StringFormat("全体損失: %.2f%% / %.1f%% (残り: %.0f円)",
               overallLossPercent, OverallLossLimitPct, overallMargin),
               10, yPos, overallColor, 9, false);
   yPos += yStep;

   color dailyColor = GetStatusColor(dailyLossPercent, DailyLossLimitPct);
   CreateLabel("DailyLoss", StringFormat("日次損失: %.2f%% / %.1f%% (残り: %.0f円)",
               dailyLossPercent, DailyLossLimitPct, dailyMargin),
               10, yPos, dailyColor, 9, false);
   yPos += yStep;

   CreateLabel("DailyBase", StringFormat("日次基準額: %.0f (UTC0時)", DailyStartingEquity),
               10, yPos, clrSilver, 8, false);
   yPos += yStep + 5;

   CreateLabel("Sep3", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 10, yPos, clrGray, 9, false);
   yPos += yStep;

   // 口座情報
   CreateLabel("AccountInfo", StringFormat("残高: %.0f | 有効証拠金: %.0f | 価格: %s",
               accountBalance, accountEquity, DoubleToString(currentPrice, _Digits)),
               10, yPos, clrSilver, 8, false);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Pipサイズの取得                                                    |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double pipSize;
   if(digits == 3 || digits == 5)
   {
      pipSize = point * 10.0;
   }
   else
   {
      pipSize = point;
   }

   return pipSize;
}

//+------------------------------------------------------------------+
//| 1ロットあたりの損失額計算                                          |
//+------------------------------------------------------------------+
double CalculateLossPerLot(double slPips)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   double slDistance = slPips * pipSize;
   double numTicks = slDistance / tickSize;
   double lossPerLot = numTicks * tickValue;

   return lossPerLot;
}

//+------------------------------------------------------------------+
//| 1ロットあたりの利益額計算                                          |
//+------------------------------------------------------------------+
double CalculateProfitPerLot(double tpPips)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipSize = GetPipSize();

   double tpDistance = tpPips * pipSize;
   double numTicks = tpDistance / tickSize;
   double profitPerLot = numTicks * tickValue;

   return profitPerLot;
}

//+------------------------------------------------------------------+
//| ロットサイズの正規化                                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   lots = MathFloor(lots / lotStep) * lotStep;

   if(lots < minLot) lots = minLot;

   return lots;
}

//+------------------------------------------------------------------+
//| ステータス色の取得                                                 |
//+------------------------------------------------------------------+
color GetStatusColor(double currentLoss, double limit)
{
   if(currentLoss >= limit - SafetyBufferPct)
      return clrRed;
   else if(currentLoss >= limit - 1.0)
      return clrYellow;
   else
      return clrLime;
}

//+------------------------------------------------------------------+
//| ラベルオブジェクトの作成/更新                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, bool bold)
{
   string fullName = objPrefix + name;

   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
   }

   ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, fullName, OBJPROP_FONT, bold ? "Arial Black" : "Courier New");
   ObjectSetString(0, fullName, OBJPROP_TEXT, text);
}
//+------------------------------------------------------------------+
