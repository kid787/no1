//+------------------------------------------------------------------+
//|                                MTF_Conscious_Line_Detector.mq5   |
//|                                                                  |
//|  マルチタイムフレーム水平線・ネックライン検出インジケーター       |
//|  意識されているサポート/レジスタンスとパターンのネックラインを検出|
//+------------------------------------------------------------------+
#property copyright "MTF Conscious Line Detector"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//--- 入力パラメーター
input int      InpPivotPeriod = 5;              // ピボット検出期間（左右）
input int      InpLookbackBars = 500;           // 計算対象の過去足数
input double   InpZoneWidthPips = 5.0;          // ライン判定ゾーン幅（pips）
input int      InpMinTryCount = 1;              // 最小トライ回数（表示閾値）
input bool     InpShowMonthly = true;           // 月足ラインを表示
input bool     InpShowWeekly = true;            // 週足ラインを表示
input bool     InpShowDaily = true;             // 日足ラインを表示
input bool     InpShow4H = true;                // 4時間足ラインを表示
input bool     InpShow1H = true;                // 1時間足ラインを表示
input bool     InpShow30M = true;               // 30分足ラインを表示
input bool     InpShow15M = true;               // 15分足ラインを表示
input bool     InpShow5M = true;                // 5分足ラインを表示
input bool     InpShowNecklines = true;         // ネックラインを表示
input bool     InpShowLabels = true;            // ラベルを表示
input int      InpMaxLinesPerTF = 10;           // 時間足あたりの最大ライン数

//--- グローバル変数
struct LineInfo
{
   double   price;              // ライン価格
   int      tryCount;           // トライ回数
   bool     isResistance;       // レジスタンスの場合true
   bool     polarityFlipped;    // 極性転換フラグ
   datetime lastTryTime;        // 最終トライ時刻
   datetime detectedTime;       // 検出時刻
   string   objectName;         // オブジェクト名
   string   labelName;          // ラベル名
   ENUM_TIMEFRAMES timeframe;   // 時間足
   bool     isNeckline;         // ネックラインフラグ
};

struct PatternInfo
{
   bool     detected;           // パターン検出フラグ
   double   necklinePrice;      // ネックライン価格
   datetime necklineTime;       // ネックライン時刻
   string   patternType;        // パターンタイプ（M/W/HS）
};

LineInfo g_lines[];             // 全ラインの配列
int g_lineCount = 0;            // ライン数
string g_prefix = "MTF_CL_";    // オブジェクト名プレフィックス
double g_point;                 // ポイント値
double g_zoneWidth;             // ゾーン幅（価格単位）

//--- 時間足配列
ENUM_TIMEFRAMES g_timeframes[] =
{
   PERIOD_MN1,   // 月足
   PERIOD_W1,    // 週足
   PERIOD_D1,    // 日足
   PERIOD_H4,    // 4時間足
   PERIOD_H1,    // 1時間足
   PERIOD_M30,   // 30分足
   PERIOD_M15,   // 15分足
   PERIOD_M5     // 5分足
};

bool g_showTimeframes[] =
{
   InpShowMonthly,
   InpShowWeekly,
   InpShowDaily,
   InpShow4H,
   InpShow1H,
   InpShow30M,
   InpShow15M,
   InpShow5M
};

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // ポイント値の計算
   g_point = _Point;
   if(_Digits == 3 || _Digits == 5)
      g_zoneWidth = InpZoneWidthPips * 10 * g_point;
   else
      g_zoneWidth = InpZoneWidthPips * g_point;

   // 配列初期化
   ArrayResize(g_lines, 0);
   g_lineCount = 0;

   Print("MTF Conscious Line Detector 初期化完了");
   Print("ゾーン幅: ", g_zoneWidth, " (", InpZoneWidthPips, " pips)");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター終了関数                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // 全オブジェクトを削除
   DeleteAllObjects();
   ArrayResize(g_lines, 0);
   g_lineCount = 0;

   Print("MTF Conscious Line Detector 終了");
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
   // 最初の実行または新しいバーの場合のみ更新
   static datetime lastBarTime = 0;
   datetime currentBarTime = time[rates_total - 1];

   if(lastBarTime == currentBarTime && prev_calculated > 0)
      return(rates_total);

   lastBarTime = currentBarTime;

   // 既存のラインを削除
   DeleteAllObjects();
   ArrayResize(g_lines, 0);
   g_lineCount = 0;

   // 各時間足でラインを検出
   for(int tf = 0; tf < ArraySize(g_timeframes); tf++)
   {
      if(!g_showTimeframes[tf])
         continue;

      DetectLinesForTimeframe(g_timeframes[tf], time, high, low, close, rates_total);
   }

   // ネックラインの検出
   if(InpShowNecklines)
   {
      DetectNecklinesForTimeframe(PERIOD_H4, time, high, low, close, rates_total);
      DetectNecklinesForTimeframe(PERIOD_H1, time, high, low, close, rates_total);
      DetectNecklinesForTimeframe(PERIOD_M30, time, high, low, close, rates_total);
   }

   // ラインを描画
   DrawAllLines();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| 指定時間足のラインを検出                                           |
//+------------------------------------------------------------------+
void DetectLinesForTimeframe(ENUM_TIMEFRAMES tf,
                             const datetime &time[],
                             const double &high[],
                             const double &low[],
                             const double &close[],
                             int rates_total)
{
   // MTFデータの取得
   int bars = MathMin(InpLookbackBars, iBars(_Symbol, tf));
   if(bars < InpPivotPeriod * 2 + 1)
      return;

   double htf_high[], htf_low[], htf_close[];
   datetime htf_time[];

   ArraySetAsSeries(htf_high, true);
   ArraySetAsSeries(htf_low, true);
   ArraySetAsSeries(htf_close, true);
   ArraySetAsSeries(htf_time, true);

   if(CopyHigh(_Symbol, tf, 0, bars, htf_high) <= 0)
      return;
   if(CopyLow(_Symbol, tf, 0, bars, htf_low) <= 0)
      return;
   if(CopyClose(_Symbol, tf, 0, bars, htf_close) <= 0)
      return;
   if(CopyTime(_Symbol, tf, 0, bars, htf_time) <= 0)
      return;

   // ピボットの検出
   int detectedLines = 0;

   for(int i = InpPivotPeriod; i < bars - InpPivotPeriod && detectedLines < InpMaxLinesPerTF; i++)
   {
      // ピボットハイの検出
      if(IsPivotHigh(htf_high, i, InpPivotPeriod))
      {
         double pivotPrice = htf_high[i];
         int tryCount = CalculateTryCount(htf_high, htf_low, htf_close, htf_time, i, pivotPrice, true, bars);

         if(tryCount >= InpMinTryCount)
         {
            AddLine(pivotPrice, tryCount, true, false, htf_time[i], tf, false);
            detectedLines++;
         }
      }

      // ピボットローの検出
      if(IsPivotLow(htf_low, i, InpPivotPeriod))
      {
         double pivotPrice = htf_low[i];
         int tryCount = CalculateTryCount(htf_high, htf_low, htf_close, htf_time, i, pivotPrice, false, bars);

         if(tryCount >= InpMinTryCount)
         {
            AddLine(pivotPrice, tryCount, false, false, htf_time[i], tf, false);
            detectedLines++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ピボットハイの判定                                                |
//+------------------------------------------------------------------+
bool IsPivotHigh(const double &high[], int index, int period)
{
   double centerHigh = high[index];

   // 左側の確認
   for(int i = 1; i <= period; i++)
   {
      if(high[index + i] >= centerHigh)
         return false;
   }

   // 右側の確認
   for(int i = 1; i <= period; i++)
   {
      if(high[index - i] >= centerHigh)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ピボットローの判定                                                |
//+------------------------------------------------------------------+
bool IsPivotLow(const double &low[], int index, int period)
{
   double centerLow = low[index];

   // 左側の確認
   for(int i = 1; i <= period; i++)
   {
      if(low[index + i] <= centerLow)
         return false;
   }

   // 右側の確認
   for(int i = 1; i <= period; i++)
   {
      if(low[index - i] <= centerLow)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| トライ回数の計算                                                  |
//+------------------------------------------------------------------+
int CalculateTryCount(const double &high[],
                     const double &low[],
                     const double &close[],
                     const datetime &htf_time[],
                     int pivotIndex,
                     double linePrice,
                     bool isResistance,
                     int bars)
{
   int tryCount = 1;  // 初期検出で1回
   bool polarityFlipped = false;

   // ピボット以降の価格動向を確認
   for(int i = pivotIndex - 1; i >= 0; i--)
   {
      double upperZone = linePrice + g_zoneWidth;
      double lowerZone = linePrice - g_zoneWidth;

      // ゾーンへのタッチ判定
      bool touchedZone = (high[i] >= lowerZone && low[i] <= upperZone);

      if(!touchedZone)
         continue;

      // リジェクション判定（終値がゾーン外で反転）
      if(isResistance)
      {
         // レジスタンスとして機能
         if(high[i] >= linePrice && close[i] < lowerZone)
         {
            tryCount++;
         }
         // 極性転換の確認（ブレイク後にサポートとして機能）
         else if(close[i] > upperZone && !polarityFlipped)
         {
            // ブレイク後、サポートとして機能したか確認
            for(int j = i - 1; j >= 0 && j > i - 10; j--)
            {
               if(low[j] <= upperZone && close[j] > linePrice)
               {
                  polarityFlipped = true;
                  tryCount += 3;  // 極性転換ボーナス
                  break;
               }
            }
         }
      }
      else
      {
         // サポートとして機能
         if(low[i] <= linePrice && close[i] > upperZone)
         {
            tryCount++;
         }
         // 極性転換の確認（ブレイク後にレジスタンスとして機能）
         else if(close[i] < lowerZone && !polarityFlipped)
         {
            // ブレイク後、レジスタンスとして機能したか確認
            for(int j = i - 1; j >= 0 && j > i - 10; j--)
            {
               if(high[j] >= lowerZone && close[j] < linePrice)
               {
                  polarityFlipped = true;
                  tryCount += 3;  // 極性転換ボーナス
                  break;
               }
            }
         }
      }
   }

   return tryCount;
}

//+------------------------------------------------------------------+
//| ネックライン検出（指定時間足）                                      |
//+------------------------------------------------------------------+
void DetectNecklinesForTimeframe(ENUM_TIMEFRAMES tf,
                                 const datetime &time[],
                                 const double &high[],
                                 const double &low[],
                                 const double &close[],
                                 int rates_total)
{
   // MTFデータの取得
   int bars = MathMin(InpLookbackBars, iBars(_Symbol, tf));
   if(bars < 50)
      return;

   double htf_high[], htf_low[], htf_close[];
   datetime htf_time[];

   ArraySetAsSeries(htf_high, true);
   ArraySetAsSeries(htf_low, true);
   ArraySetAsSeries(htf_close, true);
   ArraySetAsSeries(htf_time, true);

   if(CopyHigh(_Symbol, tf, 0, bars, htf_high) <= 0)
      return;
   if(CopyLow(_Symbol, tf, 0, bars, htf_low) <= 0)
      return;
   if(CopyClose(_Symbol, tf, 0, bars, htf_close) <= 0)
      return;
   if(CopyTime(_Symbol, tf, 0, bars, htf_time) <= 0)
      return;

   // Mパターン（ダブルトップ）の検出
   DetectMPattern(htf_high, htf_low, htf_close, htf_time, bars, tf);

   // Wパターン（ダブルボトム）の検出
   DetectWPattern(htf_high, htf_low, htf_close, htf_time, bars, tf);

   // ヘッドアンドショルダーの検出
   DetectHSPattern(htf_high, htf_low, htf_close, htf_time, bars, tf);
}

//+------------------------------------------------------------------+
//| Mパターン（ダブルトップ）検出                                      |
//+------------------------------------------------------------------+
void DetectMPattern(const double &high[],
                   const double &low[],
                   const double &close[],
                   const datetime &htf_time[],
                   int bars,
                   ENUM_TIMEFRAMES tf)
{
   for(int i = InpPivotPeriod * 2; i < bars - InpPivotPeriod * 2; i++)
   {
      // 2つの高値ピボットを探す
      if(!IsPivotHigh(high, i, InpPivotPeriod))
         continue;

      double firstTop = high[i];

      // 次のピボットハイを探す
      for(int j = i - InpPivotPeriod * 2; j >= InpPivotPeriod && j > i - 50; j--)
      {
         if(!IsPivotHigh(high, j, InpPivotPeriod))
            continue;

         double secondTop = high[j];

         // 高値が近い場合（ダブルトップ）
         if(MathAbs(firstTop - secondTop) / firstTop < 0.02)  // 2%以内
         {
            // 中間の安値（ネックライン）を探す
            double necklinePrice = high[i];
            for(int k = i; k > j; k--)
            {
               if(low[k] < necklinePrice)
                  necklinePrice = low[k];
            }

            // ネックラインとして追加
            AddLine(necklinePrice, 2, false, false, htf_time[i], tf, true);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Wパターン（ダブルボトム）検出                                      |
//+------------------------------------------------------------------+
void DetectWPattern(const double &high[],
                   const double &low[],
                   const double &close[],
                   const datetime &htf_time[],
                   int bars,
                   ENUM_TIMEFRAMES tf)
{
   for(int i = InpPivotPeriod * 2; i < bars - InpPivotPeriod * 2; i++)
   {
      // 2つの安値ピボットを探す
      if(!IsPivotLow(low, i, InpPivotPeriod))
         continue;

      double firstBottom = low[i];

      // 次のピボットローを探す
      for(int j = i - InpPivotPeriod * 2; j >= InpPivotPeriod && j > i - 50; j--)
      {
         if(!IsPivotLow(low, j, InpPivotPeriod))
            continue;

         double secondBottom = low[j];

         // 安値が近い場合（ダブルボトム）
         if(MathAbs(firstBottom - secondBottom) / firstBottom < 0.02)  // 2%以内
         {
            // 中間の高値（ネックライン）を探す
            double necklinePrice = low[i];
            for(int k = i; k > j; k--)
            {
               if(high[k] > necklinePrice)
                  necklinePrice = high[k];
            }

            // ネックラインとして追加
            AddLine(necklinePrice, 2, true, false, htf_time[i], tf, true);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ヘッドアンドショルダーパターン検出                                  |
//+------------------------------------------------------------------+
void DetectHSPattern(const double &high[],
                    const double &low[],
                    const double &close[],
                    const datetime &htf_time[],
                    int bars,
                    ENUM_TIMEFRAMES tf)
{
   for(int i = InpPivotPeriod * 3; i < bars - InpPivotPeriod * 3; i++)
   {
      // ヘッド（中央の高値）を探す
      if(!IsPivotHigh(high, i, InpPivotPeriod))
         continue;

      double head = high[i];

      // 左肩を探す
      double leftShoulder = 0;
      int leftShoulderIdx = -1;
      for(int j = i + InpPivotPeriod * 2; j < i + 30 && j < bars - InpPivotPeriod; j++)
      {
         if(IsPivotHigh(high, j, InpPivotPeriod) && high[j] < head * 0.98)
         {
            leftShoulder = high[j];
            leftShoulderIdx = j;
            break;
         }
      }

      if(leftShoulderIdx < 0)
         continue;

      // 右肩を探す
      double rightShoulder = 0;
      int rightShoulderIdx = -1;
      for(int j = i - InpPivotPeriod * 2; j > i - 30 && j >= InpPivotPeriod; j--)
      {
         if(IsPivotHigh(high, j, InpPivotPeriod) && high[j] < head * 0.98)
         {
            rightShoulder = high[j];
            rightShoulderIdx = j;
            break;
         }
      }

      if(rightShoulderIdx < 0)
         continue;

      // 肩の高さが近い場合
      if(MathAbs(leftShoulder - rightShoulder) / leftShoulder < 0.03)
      {
         // ネックラインを探す（左肩とヘッド間、ヘッドと右肩間の安値）
         double necklinePrice = high[i];
         for(int k = leftShoulderIdx; k > rightShoulderIdx; k--)
         {
            if(low[k] < necklinePrice)
               necklinePrice = low[k];
         }

         // ネックラインとして追加
         AddLine(necklinePrice, 3, false, false, htf_time[i], tf, true);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| ラインを配列に追加                                                |
//+------------------------------------------------------------------+
void AddLine(double price,
            int tryCount,
            bool isResistance,
            bool polarityFlipped,
            datetime detectedTime,
            ENUM_TIMEFRAMES tf,
            bool isNeckline)
{
   // 配列サイズを拡張
   int newSize = g_lineCount + 1;
   ArrayResize(g_lines, newSize);

   // ライン情報を設定
   g_lines[g_lineCount].price = price;
   g_lines[g_lineCount].tryCount = tryCount;
   g_lines[g_lineCount].isResistance = isResistance;
   g_lines[g_lineCount].polarityFlipped = polarityFlipped;
   g_lines[g_lineCount].detectedTime = detectedTime;
   g_lines[g_lineCount].timeframe = tf;
   g_lines[g_lineCount].isNeckline = isNeckline;

   // オブジェクト名を生成
   string tfStr = TimeframeToString(tf);
   string typeStr = isNeckline ? "NL" : (isResistance ? "R" : "S");
   g_lines[g_lineCount].objectName = g_prefix + tfStr + "_" + typeStr + "_" + IntegerToString(g_lineCount);
   g_lines[g_lineCount].labelName = g_prefix + "Label_" + tfStr + "_" + typeStr + "_" + IntegerToString(g_lineCount);

   g_lineCount++;
}

//+------------------------------------------------------------------+
//| 全ラインを描画                                                    |
//+------------------------------------------------------------------+
void DrawAllLines()
{
   for(int i = 0; i < g_lineCount; i++)
   {
      DrawLine(g_lines[i]);

      if(InpShowLabels)
         DrawLabel(g_lines[i]);
   }
}

//+------------------------------------------------------------------+
//| ライン描画                                                        |
//+------------------------------------------------------------------+
void DrawLine(LineInfo &line)
{
   // ライン色と太さの計算（10段階）
   color lineColor;
   int lineWidth;
   ENUM_LINE_STYLE lineStyle = STYLE_SOLID;

   if(line.isNeckline)
   {
      // ネックラインは点線で描画
      lineStyle = STYLE_DOT;
      lineColor = clrYellow;
      lineWidth = 2;
   }
   else
   {
      // トライ回数に基づく色と太さ
      int strength = MathMin(line.tryCount, 10);

      // 色の段階（10段階）
      if(strength <= 2)
         lineColor = clrLightGray;      // 弱いライン
      else if(strength <= 4)
         lineColor = clrSilver;
      else if(strength <= 6)
         lineColor = clrLightBlue;
      else if(strength <= 8)
         lineColor = clrDodgerBlue;
      else if(strength <= 10)
         lineColor = clrBlue;
      else if(strength <= 12)
         lineColor = clrMediumBlue;
      else if(strength <= 14)
         lineColor = clrNavy;
      else if(strength <= 16)
         lineColor = clrGold;           // 上位足・高強度
      else if(strength <= 18)
         lineColor = clrOrange;
      else
         lineColor = clrRed;            // 最強ライン

      // 極性転換がある場合は特別色
      if(line.polarityFlipped)
         lineColor = clrMagenta;

      // 太さ（1-5）
      lineWidth = MathMin((strength / 2) + 1, 5);
   }

   // ラインオブジェクトを作成
   if(!ObjectCreate(0, line.objectName, OBJ_HLINE, 0, 0, line.price))
   {
      Print("ライン作成エラー: ", GetLastError());
      return;
   }

   ObjectSetInteger(0, line.objectName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, line.objectName, OBJPROP_STYLE, lineStyle);
   ObjectSetInteger(0, line.objectName, OBJPROP_WIDTH, lineWidth);
   ObjectSetInteger(0, line.objectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, line.objectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, line.objectName, OBJPROP_SELECTED, false);
}

//+------------------------------------------------------------------+
//| ラベル描画                                                        |
//+------------------------------------------------------------------+
void DrawLabel(LineInfo &line)
{
   // ラベルテキストの作成
   string tfStr = TimeframeToString(line.timeframe);
   string typeStr = line.isNeckline ? "NL" : (line.isResistance ? "R" : "S");
   string labelText = tfStr + "-" + typeStr + ":" + IntegerToString(line.tryCount) + "x";

   if(line.polarityFlipped)
      labelText += " [極性転換]";

   // ラベルオブジェクトを作成
   datetime labelTime = TimeCurrent();

   if(!ObjectCreate(0, line.labelName, OBJ_TEXT, 0, labelTime, line.price))
   {
      Print("ラベル作成エラー: ", GetLastError());
      return;
   }

   ObjectSetString(0, line.labelName, OBJPROP_TEXT, labelText);
   ObjectSetInteger(0, line.labelName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, line.labelName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, line.labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, line.labelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, line.labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, line.labelName, OBJPROP_SELECTED, false);
}

//+------------------------------------------------------------------+
//| 全オブジェクトを削除                                              |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int totalObjects = ObjectsTotal(0);

   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);

      if(StringFind(objName, g_prefix) == 0)
      {
         ObjectDelete(0, objName);
      }
   }
}

//+------------------------------------------------------------------+
//| 時間足を文字列に変換                                              |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_MN1: return "MN";
      case PERIOD_W1:  return "W";
      case PERIOD_D1:  return "D";
      case PERIOD_H4:  return "H4";
      case PERIOD_H1:  return "H1";
      case PERIOD_M30: return "M30";
      case PERIOD_M15: return "M15";
      case PERIOD_M5:  return "M5";
      default:         return "UK";
   }
}

//+------------------------------------------------------------------+
