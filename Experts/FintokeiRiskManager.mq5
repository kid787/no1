//+------------------------------------------------------------------+
//|                                          FintokeiRiskManager.mq5 |
//|                Fintokei Challenge Plan Risk Management EA        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Fintokei Risk Manager"
#property link      ""
#property version   "1.00"
#property description "Fintokeiチャレンジプラン専用リスク管理EA"
#property description "有効証拠金(Equity)をリアルタイム監視し、損失ラインで強制決済"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 外部パラメータ                                                     |
//+------------------------------------------------------------------+
input group "=== 基本設定 ==="
input double   InitialBalance       = 100000.0;    // 初期残高
input int      UTCDayResetHour      = 0;           // 日次リセット時刻（UTC）※0固定
input double   DailyLossLimitPct    = 5.0;         // 1日の最大損失率（%）
input double   OverallLossLimitPct  = 10.0;        // 全体の最大損失率（%）
input double   SafetyBufferPct      = 0.1;         // 安全バッファ（%）

input group "=== 表示設定 ==="
input color    PanelBgColor         = C'32,32,32'; // パネル背景色
input color    NormalColor          = clrWhite;    // 通常テキスト色
input color    WarningColor         = clrYellow;   // 警告色
input color    DangerColor          = clrRed;      // 危険色
input color    SafeColor            = clrLime;     // 安全色
input int      PanelX               = 10;          // パネルX位置
input int      PanelY               = 30;          // パネルY位置

//+------------------------------------------------------------------+
//| グローバル変数                                                     |
//+------------------------------------------------------------------+
CTrade trade;

// 日次基準額（UTC 0時の有効証拠金）
double DailyStartingEquity = 0;

// 最後にリセットした日付（UTC）
datetime lastResetDateUTC = 0;

// 緊急停止フラグ
bool isEmergencyStop = false;

// 緊急停止の理由
string emergencyReason = "";

// 取引日数カウント用
int tradingDaysCount = 0;
datetime lastTradingDate = 0;
bool hadTradeToday = false;

// オブジェクト名プレフィックス
string objPrefix = "FRM_";

// 前回のポジション数（新規注文検出用）
int lastPositionCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // トレードオブジェクトの設定
   trade.SetExpertMagicNumber(0);  // 全てのポジションを対象
   trade.SetDeviationInPoints(50); // スリッページ許容
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // 日次基準額の初期化
   InitializeDailyEquity();

   // 取引日数カウントの初期化
   InitializeTradingDays();

   // 初期表示
   UpdateDisplay();

   Print("=== FintokeiRiskManager 初期化完了 ===");
   Print("初期残高: ", DoubleToString(InitialBalance, 2));
   Print("日次損失制限: ", DailyLossLimitPct, "%");
   Print("全体損失制限: ", OverallLossLimitPct, "%");
   Print("安全バッファ: ", SafetyBufferPct, "%");
   Print("日次基準額: ", DoubleToString(DailyStartingEquity, 2));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // オブジェクトの削除
   ObjectsDeleteAll(0, objPrefix);
   ChartRedraw();
   Print("FintokeiRiskManager が終了しました");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // UTC 0時のリセットチェック
   CheckDailyReset();

   // 緊急停止中は新規エントリーをブロック（ただし監視は継続）
   if(isEmergencyStop)
   {
      // 何もしない（表示のみ更新）
      UpdateDisplay();
      return;
   }

   // 取引日数カウント用の新規注文チェック
   CheckNewTrade();

   // 損失監視
   if(!CheckLossLimits())
   {
      // 損失ラインに到達した場合、緊急決済を実行
      ExecuteEmergencyClose();
   }

   // 表示更新
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| 日次基準額の初期化                                                 |
//+------------------------------------------------------------------+
void InitializeDailyEquity()
{
   // 現在のUTC時間を取得
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   // 今日のUTC 0時を計算
   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   // グローバル変数から日次基準額を読み込み（EA再起動時対応）
   string gvName = "FRM_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);

   if(GlobalVariableCheck(gvName))
   {
      DailyStartingEquity = GlobalVariableGet(gvName);
      lastResetDateUTC = todayResetUTC;
      Print("日次基準額をグローバル変数から復元: ", DoubleToString(DailyStartingEquity, 2));
   }
   else
   {
      // 初回起動時：現在のEquityを基準とする
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;
      GlobalVariableSet(gvName, DailyStartingEquity);
      Print("日次基準額を新規設定: ", DoubleToString(DailyStartingEquity, 2));
   }
}

//+------------------------------------------------------------------+
//| 日次リセットのチェック（UTC 0時）                                   |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   // 現在のUTC時間を取得
   datetime currentTimeUTC = TimeGMT();
   MqlDateTime timeStruct;
   TimeToStruct(currentTimeUTC, timeStruct);

   // 今日のUTC 0時を計算
   datetime todayResetUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                          timeStruct.year, timeStruct.mon, timeStruct.day));

   // 日付が変わったかチェック
   if(todayResetUTC > lastResetDateUTC)
   {
      // 新しい日のEquityを基準値として設定
      DailyStartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastResetDateUTC = todayResetUTC;

      // グローバル変数に保存
      string gvName = "FRM_DailyEquity_" + TimeToString(todayResetUTC, TIME_DATE);
      GlobalVariableSet(gvName, DailyStartingEquity);

      // 前日の取引があった場合、取引日数をカウント
      if(hadTradeToday)
      {
         tradingDaysCount++;
         string gvTradingDays = "FRM_TradingDays";
         GlobalVariableSet(gvTradingDays, tradingDaysCount);
      }

      // 今日の取引フラグをリセット
      hadTradeToday = false;

      Print("=== 日次リセット実行 ===");
      Print("新しい日次基準額: ", DoubleToString(DailyStartingEquity, 2));
      Print("UTC時刻: ", TimeToString(currentTimeUTC, TIME_DATE | TIME_MINUTES));
      Print("累計取引日数: ", tradingDaysCount);
   }
}

//+------------------------------------------------------------------+
//| 取引日数カウントの初期化                                           |
//+------------------------------------------------------------------+
void InitializeTradingDays()
{
   string gvTradingDays = "FRM_TradingDays";

   if(GlobalVariableCheck(gvTradingDays))
   {
      tradingDaysCount = (int)GlobalVariableGet(gvTradingDays);
   }
   else
   {
      tradingDaysCount = 0;
      GlobalVariableSet(gvTradingDays, 0);
   }

   // 現在のポジション数を記録
   lastPositionCount = PositionsTotal();

   Print("取引日数カウント初期化: ", tradingDaysCount);
}

//+------------------------------------------------------------------+
//| 新規取引のチェック（取引日数カウント用）                             |
//+------------------------------------------------------------------+
void CheckNewTrade()
{
   int currentPositionCount = PositionsTotal();

   // ポジション数が増えた場合、新規注文があったと判断
   if(currentPositionCount > lastPositionCount)
   {
      if(!hadTradeToday)
      {
         hadTradeToday = true;
         Print("本日の取引を検出しました。取引日としてカウントされます。");
      }
   }

   lastPositionCount = currentPositionCount;
}

//+------------------------------------------------------------------+
//| 損失制限のチェック                                                 |
//+------------------------------------------------------------------+
bool CheckLossLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 安全バッファを考慮した実効損失制限
   double effectiveDailyLimit = DailyLossLimitPct - SafetyBufferPct;
   double effectiveOverallLimit = OverallLossLimitPct - SafetyBufferPct;

   // === 全体の損失率チェック ===
   // 失格ライン: InitialBalance * (1 - OverallLossLimitPct / 100)
   double overallLossLine = InitialBalance * (1.0 - effectiveOverallLimit / 100.0);

   if(currentEquity <= overallLossLine)
   {
      double lossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
      emergencyReason = StringFormat("全体損失制限に到達 (%.2f%% >= %.2f%%)",
                                      lossPercent, effectiveOverallLimit);
      return false;
   }

   // === 日次の損失率チェック ===
   // 失格ライン: DailyStartingEquity * (1 - DailyLossLimitPct / 100)
   double dailyLossLine = DailyStartingEquity * (1.0 - effectiveDailyLimit / 100.0);

   if(currentEquity <= dailyLossLine)
   {
      double lossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;
      emergencyReason = StringFormat("日次損失制限に到達 (%.2f%% >= %.2f%%)",
                                      lossPercent, effectiveDailyLimit);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 緊急全決済の実行                                                   |
//+------------------------------------------------------------------+
void ExecuteEmergencyClose()
{
   Print("!!! 緊急決済を開始します !!!");
   Print("理由: ", emergencyReason);

   // 全てのオープンポジションを決済
   int totalPositions = PositionsTotal();
   int closedCount = 0;
   int failedCount = 0;

   // 後ろから順に決済（インデックスのずれを防ぐ）
   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);

         // 決済を試行
         if(trade.PositionClose(ticket))
         {
            closedCount++;
            Print("ポジション決済成功: Ticket=", ticket, ", Symbol=", symbol, ", Volume=", volume);
         }
         else
         {
            failedCount++;
            Print("ポジション決済失敗: Ticket=", ticket, ", Error=", trade.ResultRetcodeDescription());

            // リトライ（最大3回）
            for(int retry = 0; retry < 3; retry++)
            {
               Sleep(500);  // 500ms待機
               if(trade.PositionClose(ticket))
               {
                  closedCount++;
                  failedCount--;
                  Print("リトライ成功: Ticket=", ticket);
                  break;
               }
            }
         }
      }
   }

   // 緊急停止状態に移行
   isEmergencyStop = true;

   Print("=== 緊急決済完了 ===");
   Print("決済成功: ", closedCount, " ポジション");
   Print("決済失敗: ", failedCount, " ポジション");
   Print(">>> 新規取引を停止しました <<<");

   // アラート
   Alert("FintokeiRiskManager: 損失制限到達！全ポジション決済完了。新規取引停止中。");
}

//+------------------------------------------------------------------+
//| チャート表示の更新                                                 |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // 損失率の計算
   double overallLossPercent = ((InitialBalance - currentEquity) / InitialBalance) * 100.0;
   double dailyLossPercent = ((DailyStartingEquity - currentEquity) / DailyStartingEquity) * 100.0;

   // 失格ラインの計算
   double overallLossLine = InitialBalance * (1.0 - OverallLossLimitPct / 100.0);
   double dailyLossLine = DailyStartingEquity * (1.0 - DailyLossLimitPct / 100.0);

   // 安全バッファ適用後のライン
   double overallWarningLine = InitialBalance * (1.0 - (OverallLossLimitPct - SafetyBufferPct) / 100.0);
   double dailyWarningLine = DailyStartingEquity * (1.0 - (DailyLossLimitPct - SafetyBufferPct) / 100.0);

   // 残りマージン
   double overallMargin = currentEquity - overallWarningLine;
   double dailyMargin = currentEquity - dailyWarningLine;

   int yPos = PanelY;
   int yStep = 18;

   // ヘッダー
   if(isEmergencyStop)
   {
      CreateLabel("Header", "■ FINTOKEI RISK MANAGER - 緊急停止中 ■", PanelX, yPos, DangerColor, 12, true);
   }
   else
   {
      CreateLabel("Header", "■ FINTOKEI RISK MANAGER ■", PanelX, yPos, clrGold, 12, true);
   }
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep1", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 口座情報
   CreateLabel("Balance", StringFormat("残高: %.0f | 有効証拠金: %.0f", currentBalance, currentEquity),
               PanelX, yPos, NormalColor, 10, false);
   yPos += yStep;

   CreateLabel("InitBal", StringFormat("初期残高: %.0f", InitialBalance),
               PanelX, yPos, clrSilver, 9, false);
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep2", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 全体損失
   color overallColor = GetStatusColor(overallLossPercent, OverallLossLimitPct, SafetyBufferPct);
   CreateLabel("OverallTitle", "【全体損失】", PanelX, yPos, clrWhite, 10, true);
   yPos += yStep;

   CreateLabel("OverallLoss", StringFormat("現在: %.2f%% / 制限: %.1f%%",
               overallLossPercent, OverallLossLimitPct), PanelX + 10, yPos, overallColor, 10, false);
   yPos += yStep;

   CreateLabel("OverallLine", StringFormat("失格ライン: %.0f | 残り: %.0f",
               overallLossLine, overallMargin), PanelX + 10, yPos, clrSilver, 9, false);
   yPos += yStep + 5;

   // 日次損失
   color dailyColor = GetStatusColor(dailyLossPercent, DailyLossLimitPct, SafetyBufferPct);
   CreateLabel("DailyTitle", "【日次損失】", PanelX, yPos, clrWhite, 10, true);
   yPos += yStep;

   CreateLabel("DailyLoss", StringFormat("現在: %.2f%% / 制限: %.1f%%",
               dailyLossPercent, DailyLossLimitPct), PanelX + 10, yPos, dailyColor, 10, false);
   yPos += yStep;

   CreateLabel("DailyBase", StringFormat("基準額: %.0f (UTC0時)", DailyStartingEquity),
               PanelX + 10, yPos, clrSilver, 9, false);
   yPos += yStep;

   CreateLabel("DailyLine", StringFormat("失格ライン: %.0f | 残り: %.0f",
               dailyLossLine, dailyMargin), PanelX + 10, yPos, clrSilver, 9, false);
   yPos += yStep + 5;

   // 区切り線
   CreateLabel("Sep3", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", PanelX, yPos, clrGray, 9, false);
   yPos += yStep;

   // 取引日数
   color tradingDaysColor = (tradingDaysCount >= 3) ? SafeColor : WarningColor;
   int todayCount = hadTradeToday ? 1 : 0;
   CreateLabel("TradingDays", StringFormat("取引日数: %d日 (最低3日必要) %s",
               tradingDaysCount + todayCount,
               (tradingDaysCount + todayCount >= 3) ? "✓" : ""),
               PanelX, yPos, tradingDaysColor, 10, false);
   yPos += yStep + 5;

   // 緊急停止時の追加メッセージ
   if(isEmergencyStop)
   {
      CreateLabel("Sep4", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", PanelX, yPos, clrGray, 9, false);
      yPos += yStep;

      CreateLabel("EmergencyMsg1", "!! 緊急停止 !!", PanelX, yPos, DangerColor, 12, true);
      yPos += yStep;

      CreateLabel("EmergencyMsg2", emergencyReason, PanelX, yPos, DangerColor, 9, false);
      yPos += yStep;

      CreateLabel("EmergencyMsg3", "全ポジション決済済み・新規取引停止中", PanelX, yPos, WarningColor, 9, false);
   }

   // 現在時刻（UTC）
   yPos += yStep + 5;
   datetime utcTime = TimeGMT();
   CreateLabel("UTCTime", StringFormat("UTC: %s", TimeToString(utcTime, TIME_DATE | TIME_MINUTES)),
               PanelX, yPos, clrGray, 8, false);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ステータスに応じた色を取得                                         |
//+------------------------------------------------------------------+
color GetStatusColor(double currentLoss, double limit, double buffer)
{
   if(currentLoss >= limit - buffer)
      return DangerColor;
   else if(currentLoss >= limit - buffer - 1.0)  // 制限の1%手前で警告
      return WarningColor;
   else
      return SafeColor;
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
   ObjectSetString(0, fullName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetString(0, fullName, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| 取引日数カウントのリセット（チャレンジ開始時用）                      |
//+------------------------------------------------------------------+
void ResetTradingDaysCount()
{
   tradingDaysCount = 0;
   hadTradeToday = false;
   GlobalVariableSet("FRM_TradingDays", 0);
   Print("取引日数カウントをリセットしました");
}

//+------------------------------------------------------------------+
//| 緊急停止状態の解除（手動復帰用）                                    |
//+------------------------------------------------------------------+
void ResetEmergencyStop()
{
   if(isEmergencyStop)
   {
      isEmergencyStop = false;
      emergencyReason = "";
      Print("緊急停止状態を解除しました");
   }
}
//+------------------------------------------------------------------+
