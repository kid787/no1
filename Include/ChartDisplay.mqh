//+------------------------------------------------------------------+
//|                                                 ChartDisplay.mqh |
//|                    Chart Information Display Module               |
//|                     Copyright 2024, Your Company                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"

#include "DowTheory.mqh"
#include "RiskManager.mqh"

//--- Chart Display Class
class CChartDisplay
{
private:
   string            m_prefix;          // Object name prefix
   int               m_xOffset;         // X position
   int               m_yOffset;         // Y position
   int               m_lineHeight;      // Line height
   color             m_textColor;       // Default text color
   color             m_positiveColor;   // Positive value color
   color             m_negativeColor;   // Negative value color
   color             m_warningColor;    // Warning color
   color             m_criticalColor;   // Critical color
   string            m_fontName;        // Font name
   int               m_fontSize;        // Font size

   // Internal methods
   void              CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 0);
   void              UpdateLabel(string name, string text, color clr);
   void              DeleteLabel(string name);

public:
                     CChartDisplay();
                    ~CChartDisplay();

   void              Init(string prefix = "XAUUSD_DOW_", int xOffset = 20, int yOffset = 50);
   void              Deinit();

   // Display updates
   void              UpdateRiskDisplay(CRiskManager &risk);
   void              UpdateTrendDisplay(ENUM_DOW_TREND trend, ENUM_DOW_TREND htfTrend);
   void              UpdatePositionDisplay(string direction, double entry, double sl, double tp, double profit);
   void              UpdateSignalDisplay(string signal, int strength);
   void              UpdateSessionDisplay(string session, bool isActive);
   void              UpdateStatsDisplay(int trades, double winRate, double totalPL);
   void              UpdateEmergencyDisplay(bool isEmergency, string reason);
   void              UpdateTradingDaysDisplay(int days);

   // Full panel update
   void              CreatePanel();
   void              UpdateAll(CRiskManager &risk, CDowTheory &dow, CDowTheory &dowHTF,
                              string posDir, double entry, double sl, double tp, double profit,
                              string signal, int strength, string session, bool sessionActive,
                              int trades, double winRate, double totalPL);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CChartDisplay::CChartDisplay()
{
   m_prefix = "XAUUSD_DOW_";
   m_xOffset = 20;
   m_yOffset = 50;
   m_lineHeight = 18;
   m_textColor = clrWhite;
   m_positiveColor = clrLime;
   m_negativeColor = clrRed;
   m_warningColor = clrOrange;
   m_criticalColor = clrMagenta;
   m_fontName = "Arial";
   m_fontSize = 9;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CChartDisplay::~CChartDisplay()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
void CChartDisplay::Init(string prefix = "XAUUSD_DOW_", int xOffset = 20, int yOffset = 50)
{
   m_prefix = prefix;
   m_xOffset = xOffset;
   m_yOffset = yOffset;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CChartDisplay::Deinit()
{
   ObjectsDeleteAll(0, m_prefix);
}

//+------------------------------------------------------------------+
//| Create Label Object                                               |
//+------------------------------------------------------------------+
void CChartDisplay::CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 0)
{
   string objName = m_prefix + name;

   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, objName, OBJPROP_FONT, m_fontName);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize > 0 ? fontSize : m_fontSize);
   }

   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Update Label Object                                               |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateLabel(string name, string text, color clr)
{
   string objName = m_prefix + name;

   if(ObjectFind(0, objName) >= 0)
   {
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   }
}

//+------------------------------------------------------------------+
//| Delete Label Object                                               |
//+------------------------------------------------------------------+
void CChartDisplay::DeleteLabel(string name)
{
   string objName = m_prefix + name;
   ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
//| Create Panel                                                      |
//+------------------------------------------------------------------+
void CChartDisplay::CreatePanel()
{
   int y = m_yOffset;
   int x = m_xOffset;

   // Header
   CreateLabel("Header", x, y, "=== XAUUSD Dow Theory EA ===", clrGold, 11);
   y += m_lineHeight + 5;

   // Separator
   CreateLabel("Sep1", x, y, "--------------------------------", clrDarkGray);
   y += m_lineHeight;

   // Risk Section
   CreateLabel("RiskHeader", x, y, "[Risk Management - Fintokei]", clrCyan);
   y += m_lineHeight;

   CreateLabel("DailyDD", x, y, "Daily DD: 0.00%", m_textColor);
   y += m_lineHeight;

   CreateLabel("OverallDD", x, y, "Overall DD: 0.00%", m_textColor);
   y += m_lineHeight;

   CreateLabel("DailyLine", x, y, "Daily Line: 0.00", m_textColor);
   y += m_lineHeight;

   CreateLabel("OverallLine", x, y, "Overall Line: 0.00", m_textColor);
   y += m_lineHeight;

   CreateLabel("RiskState", x, y, "Risk State: NORMAL", m_positiveColor);
   y += m_lineHeight;

   CreateLabel("TradingDays", x, y, "Trading Days: 0/3", m_textColor);
   y += m_lineHeight + 5;

   // Separator
   CreateLabel("Sep2", x, y, "--------------------------------", clrDarkGray);
   y += m_lineHeight;

   // Trend Section
   CreateLabel("TrendHeader", x, y, "[Dow Theory Analysis]", clrCyan);
   y += m_lineHeight;

   CreateLabel("HTFTrend", x, y, "HTF Trend (H4): RANGE", m_textColor);
   y += m_lineHeight;

   CreateLabel("CurrentTrend", x, y, "Current Trend (H1): RANGE", m_textColor);
   y += m_lineHeight;

   CreateLabel("Signal", x, y, "Signal: NONE", m_textColor);
   y += m_lineHeight;

   CreateLabel("Strength", x, y, "Strength: 0/5", m_textColor);
   y += m_lineHeight + 5;

   // Separator
   CreateLabel("Sep3", x, y, "--------------------------------", clrDarkGray);
   y += m_lineHeight;

   // Position Section
   CreateLabel("PosHeader", x, y, "[Position Info]", clrCyan);
   y += m_lineHeight;

   CreateLabel("PosDir", x, y, "Direction: NONE", m_textColor);
   y += m_lineHeight;

   CreateLabel("PosEntry", x, y, "Entry: 0.00", m_textColor);
   y += m_lineHeight;

   CreateLabel("PosSL", x, y, "Stop Loss: 0.00", m_textColor);
   y += m_lineHeight;

   CreateLabel("PosTP", x, y, "Take Profit: 0.00", m_textColor);
   y += m_lineHeight;

   CreateLabel("PosProfit", x, y, "Profit: 0.00", m_textColor);
   y += m_lineHeight + 5;

   // Separator
   CreateLabel("Sep4", x, y, "--------------------------------", clrDarkGray);
   y += m_lineHeight;

   // Session Section
   CreateLabel("SessionHeader", x, y, "[Session Info]", clrCyan);
   y += m_lineHeight;

   CreateLabel("Session", x, y, "Current Session: ---", m_textColor);
   y += m_lineHeight;

   CreateLabel("SessionStatus", x, y, "Active: NO", m_textColor);
   y += m_lineHeight + 5;

   // Separator
   CreateLabel("Sep5", x, y, "--------------------------------", clrDarkGray);
   y += m_lineHeight;

   // Stats Section
   CreateLabel("StatsHeader", x, y, "[Statistics]", clrCyan);
   y += m_lineHeight;

   CreateLabel("TotalTrades", x, y, "Total Trades: 0", m_textColor);
   y += m_lineHeight;

   CreateLabel("WinRate", x, y, "Win Rate: 0.0%", m_textColor);
   y += m_lineHeight;

   CreateLabel("TotalPL", x, y, "Total P/L: 0.00", m_textColor);
   y += m_lineHeight;

   // Emergency notice (hidden by default)
   CreateLabel("Emergency", x, y + 20, "", clrRed, 12);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Risk Display                                               |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateRiskDisplay(CRiskManager &risk)
{
   double dailyDD = risk.GetCurrentDailyDrawdownPct();
   double overallDD = risk.GetCurrentOverallDrawdownPct();
   double dailyLine = risk.GetSafetyDailyLine();
   double overallLine = risk.GetSafetyOverallLine();
   ENUM_RISK_STATE state = risk.GetRiskState();

   // Daily DD
   color ddColor = dailyDD < 3.0 ? m_positiveColor : (dailyDD < 4.0 ? m_warningColor : m_criticalColor);
   UpdateLabel("DailyDD", StringFormat("Daily DD: %.2f%%", dailyDD), ddColor);

   // Overall DD
   color odColor = overallDD < 6.0 ? m_positiveColor : (overallDD < 8.0 ? m_warningColor : m_criticalColor);
   UpdateLabel("OverallDD", StringFormat("Overall DD: %.2f%%", overallDD), odColor);

   // Lines
   UpdateLabel("DailyLine", StringFormat("Daily Line: %.2f", dailyLine), m_textColor);
   UpdateLabel("OverallLine", StringFormat("Overall Line: %.2f", overallLine), m_textColor);

   // Risk State
   string stateStr;
   color stateColor;
   switch(state)
   {
      case RISK_NORMAL:
         stateStr = "NORMAL";
         stateColor = m_positiveColor;
         break;
      case RISK_WARNING:
         stateStr = "WARNING";
         stateColor = m_warningColor;
         break;
      case RISK_CRITICAL:
         stateStr = "CRITICAL";
         stateColor = m_criticalColor;
         break;
      case RISK_EMERGENCY:
         stateStr = "EMERGENCY STOP";
         stateColor = clrRed;
         break;
   }
   UpdateLabel("RiskState", StringFormat("Risk State: %s", stateStr), stateColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Trend Display                                              |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateTrendDisplay(ENUM_DOW_TREND trend, ENUM_DOW_TREND htfTrend)
{
   // HTF Trend
   string htfStr;
   color htfColor;
   switch(htfTrend)
   {
      case DOW_TREND_UP:
         htfStr = "UPTREND";
         htfColor = m_positiveColor;
         break;
      case DOW_TREND_DOWN:
         htfStr = "DOWNTREND";
         htfColor = m_negativeColor;
         break;
      default:
         htfStr = "RANGE";
         htfColor = m_textColor;
   }
   UpdateLabel("HTFTrend", StringFormat("HTF Trend (H4): %s", htfStr), htfColor);

   // Current Trend
   string trendStr;
   color trendColor;
   switch(trend)
   {
      case DOW_TREND_UP:
         trendStr = "UPTREND";
         trendColor = m_positiveColor;
         break;
      case DOW_TREND_DOWN:
         trendStr = "DOWNTREND";
         trendColor = m_negativeColor;
         break;
      default:
         trendStr = "RANGE";
         trendColor = m_textColor;
   }
   UpdateLabel("CurrentTrend", StringFormat("Current Trend (H1): %s", trendStr), trendColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Position Display                                           |
//+------------------------------------------------------------------+
void CChartDisplay::UpdatePositionDisplay(string direction, double entry, double sl, double tp, double profit)
{
   color dirColor = direction == "BUY" ? m_positiveColor : (direction == "SELL" ? m_negativeColor : m_textColor);
   UpdateLabel("PosDir", StringFormat("Direction: %s", direction), dirColor);

   UpdateLabel("PosEntry", StringFormat("Entry: %.2f", entry), m_textColor);
   UpdateLabel("PosSL", StringFormat("Stop Loss: %.2f", sl), m_negativeColor);
   UpdateLabel("PosTP", StringFormat("Take Profit: %.2f", tp), m_positiveColor);

   color profitColor = profit >= 0 ? m_positiveColor : m_negativeColor;
   UpdateLabel("PosProfit", StringFormat("Profit: %.2f", profit), profitColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Signal Display                                             |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateSignalDisplay(string signal, int strength)
{
   color sigColor;
   if(signal == "BUY")
      sigColor = m_positiveColor;
   else if(signal == "SELL")
      sigColor = m_negativeColor;
   else
      sigColor = m_textColor;

   UpdateLabel("Signal", StringFormat("Signal: %s", signal), sigColor);
   UpdateLabel("Strength", StringFormat("Strength: %d/5", strength), strength >= 3 ? m_positiveColor : m_textColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Session Display                                            |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateSessionDisplay(string session, bool isActive)
{
   UpdateLabel("Session", StringFormat("Current Session: %s", session), m_textColor);

   color activeColor = isActive ? m_positiveColor : m_negativeColor;
   UpdateLabel("SessionStatus", StringFormat("Active: %s", isActive ? "YES" : "NO"), activeColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Stats Display                                              |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateStatsDisplay(int trades, double winRate, double totalPL)
{
   UpdateLabel("TotalTrades", StringFormat("Total Trades: %d", trades), m_textColor);
   UpdateLabel("WinRate", StringFormat("Win Rate: %.1f%%", winRate), winRate >= 50 ? m_positiveColor : m_warningColor);

   color plColor = totalPL >= 0 ? m_positiveColor : m_negativeColor;
   UpdateLabel("TotalPL", StringFormat("Total P/L: %.2f", totalPL), plColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Emergency Display                                          |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateEmergencyDisplay(bool isEmergency, string reason)
{
   if(isEmergency)
   {
      UpdateLabel("Emergency", "!!! EMERGENCY STOP: " + reason + " !!!", clrRed);
   }
   else
   {
      UpdateLabel("Emergency", "", m_textColor);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Trading Days Display                                       |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateTradingDaysDisplay(int days)
{
   color dayColor = days >= 3 ? m_positiveColor : m_warningColor;
   UpdateLabel("TradingDays", StringFormat("Trading Days: %d/3", days), dayColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update All Displays                                               |
//+------------------------------------------------------------------+
void CChartDisplay::UpdateAll(CRiskManager &risk, CDowTheory &dow, CDowTheory &dowHTF,
                              string posDir, double entry, double sl, double tp, double profit,
                              string signal, int strength, string session, bool sessionActive,
                              int trades, double winRate, double totalPL)
{
   UpdateRiskDisplay(risk);
   UpdateTrendDisplay(dow.GetCurrentTrend(), dowHTF.GetCurrentTrend());
   UpdatePositionDisplay(posDir, entry, sl, tp, profit);
   UpdateSignalDisplay(signal, strength);
   UpdateSessionDisplay(session, sessionActive);
   UpdateStatsDisplay(trades, winRate, totalPL);
   UpdateTradingDaysDisplay(risk.GetTradingDays());
   UpdateEmergencyDisplay(risk.IsEmergencyStop(), risk.GetLastError());
}
