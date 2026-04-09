//+------------------------------------------------------------------+
//|                            GoldScalp_Break.mq5                  |
//|                     Scalping Breakout + Trend                   |
//|                     Objetivo: 75%+ WR / Low Drawdown            |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"
#property strict
#property indicator_plots 0

#include <Trade\Trade.mqh>
CTrade  trade;

//==================================================================
// INPUTS - SESIONES
//==================================================================
input bool     UseAsiaSession   = true;
input bool     UseLondonSession = true;
input bool     UseNYSession    = true;
input int      GMTOffset       = 0;

//==================================================================
// INPUTS - INDICADORES (SIMPLES Y EFECTIVOS)
//==================================================================
input int      InpEMAFast      = 9;          // EMA rapida
input int      InpEMASlow     = 21;         // EMA lenta
input int      InpBB_Period   = 20;         // Bollinger period
input double   InpBB_Dev      = 2.0;         // Bollinger deviation

//==================================================================
// INPUTS - SL/TP (CONSERVADOR PARA WR ALTO)
//==================================================================
input int     InpSL_Pips     = 30;         // SL tight
input int     InpTP_Pips    = 60;         // TP 2:1.

//==================================================================
// INPUTS - LIMITE TRADES
//==================================================================
input int     MaxTradesPerDay = 10;
input int     InpCooldown     = 5;          // 5 minutos

//==================================================================
// INPUTS - TRADING
//==================================================================
input double   RiskPerTrade       = 2.0;
input double   DailyDrawdownLimit = 10.0;
input int      MagicNumber        = 2026;
input string   BaseSymbolParam    = "";
input ENUM_TIMEFRAMES MainTF      = PERIOD_M1;

input bool     UseSpreadFilter    = true;
input int      MaxSpreadPoints    = 40;

//==================================================================
// GLOBALES
//==================================================================
int hEMA_fast, hEMA_slow, hBB;
datetime lastBarTime;
string  baseSymbolUsed;

int tradesToday = 0;
datetime lastTradeTime = 0;
datetime lastResetTime = 0;

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   if(BaseSymbolParam == "")
      baseSymbolUsed = _Symbol;
   else
      baseSymbolUsed = BaseSymbolParam;

   trade.SetExpertMagicNumber(MagicNumber);

   // Indicadores simples
   hEMA_fast = iEMA(baseSymbolUsed, MainTF, InpEMAFast, PRICE_CLOSE);
   hEMA_slow = iEMA(baseSymbolUsed, MainTF, InpEMASlow, PRICE_CLOSE);
   hBB = iBands(baseSymbolUsed, MainTF, InpBB_Period, 0, InpBB_Dev, PRICE_CLOSE);

   if(hEMA_fast == INVALID_HANDLE || hEMA_slow == INVALID_HANDLE || hBB == INVALID_HANDLE)
     {
      Print("Error: No cargaron indicadores");
      return(INIT_FAILED);
     }

   Print("=== GOLDSCALP BREAK INIT ===");
   Print("EMA: ", InpEMAFast, "/", InpEMASlow);
   Print("Sessions: ", (UseAsiaSession?"Asia ":"")+(UseLondonSession?"LON ":"")+(UseNYSession?"NY":""));
   Print("SL: ", InpSL_Pips, " | TP: ", InpTP_Pips, " (2:1)");
   Print("=============================");

   return(INIT_SUCCEEDED);
}

//==================================================================
// ON TICK
//==================================================================
void OnTick()
{
   datetime curBarTime = iTime(baseSymbolUsed, MainTF, 0);
   if(curBarTime == lastBarTime) return;
   lastBarTime = curBarTime;

   // Reset daily
   datetime now = TimeCurrent();
   if(now >= lastResetTime + 24*3600)
     {
      tradesToday = 0;
      lastResetTime = now;
     }

   // Limits
   if(tradesToday >= MaxTradesPerDay) return;
   if(lastTradeTime > 0 && (now - lastTradeTime) < InpCooldown * 60) return;

   // Spread
   if(UseSpreadFilter)
     {
      int spread = (int)SymbolInfoInteger(baseSymbolUsed, SYMBOL_SPREAD);
      if(spread > MaxSpreadPoints) return;
     }

   // Session check
   if(!IsSessionActive()) return;

   // Señales
   bool buySignal, sellSignal;
   double buySL, buyTP, sellSL, sellTP;

   if(CheckSignal(buySignal, sellSignal, buySL, buyTP, sellSL, sellTP))
     {
      if(buySignal)
        {
         PlaceOrder(true, SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK), buySL, buyTP);
         OnTradeExecuted();
        }
      else if(sellSignal)
        {
         PlaceOrder(false, SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID), sellSL, sellTP);
         OnTradeExecuted();
        }
     }
}

//==================================================================
// CHECK SIGNAL (EMA CROSS + BB TOUCH)
//==================================================================
bool CheckSignal(bool &buySignal, bool &sellSignal, double &buySL, double &buyTP, double &sellSL, double &sellTP)
{
   double emaFast[], emaSlow[], bbUpper[], bbLower[];
   double close[];
   
   if(CopyBuffer(hEMA_fast, 0, 0, 10, emaFast) < 10) return false;
   if(CopyBuffer(hEMA_slow, 0, 0, 10, emaSlow) < 10) return false;
   if(CopyBuffer(hBB, 1, 0, 10, bbUpper) < 10) return false;
   if(CopyBuffer(hBB, 2, 0, 10, bbLower) < 10) return false;
   if(CopyClose(baseSymbolUsed, MainTF, 0, 1, close) < 1) return false;

   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(close, true);
   
   double point = SymbolInfoDouble(baseSymbolUsed, SYMBOL_POINT);
   double ask = SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK);
   double bid = SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID);
   double currentClose = close[0];

   // ===== BUY: EMA fast cruza arriba EMA slow + precio toca banda inferior =====
   bool emaCrossUp = (emaFast[0] > emaSlow[0]) && (emaFast[1] <= emaSlow[1]);
   bool priceAtBBLower = currentClose <= bbLower[0] * 1.001;  // Dentro de 0.1% de BB lower
   bool trendUp = emaFast[0] > emaSlow[0];  // Trend upward

   // Precio rebota de BB lower
   bool bounceLower = (bbLower[0] - bbLower[1]) > 0;  // BB lower subiendo

   bool buyCond = emaCrossUp && priceAtBBLower && trendUp;

   if(buyCond)
     {
      buySignal = true;
      buySL = ask - (InpSL_Pips * point);
      buyTP = ask + (InpTP_Pips * point);
      return true;
     }

   // ===== SELL: EMA fast cruza abajo EMA slow + precio toca banda superior =====
   bool emaCrossDown = (emaFast[0] < emaSlow[0]) && (emaFast[1] >= emaSlow[1]);
   bool priceAtBBUpper = currentClose >= bbUpper[0] * 0.999;  // Dentro de 0.1% de BB upper
   bool trendDown = emaFast[0] < emaSlow[0];

   bool sellCond = emaCrossDown && priceAtBBUpper && trendDown;

   if(sellCond)
     {
      sellSignal = true;
      sellSL = ask + (InpSL_Pips * point);
      sellTP = ask - (InpTP_Pips * point);
      return true;
     }

   return false;
}

//==================================================================
// IS SESSION ACTIVE
//==================================================================
bool IsSessionActive()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now + GMTOffset * 3600, dt);

   int hour = dt.hour;

   if(UseAsiaSession && hour >= 0 && hour < 9) return true;
   if(UseLondonSession && hour >= 8 && hour < 17) return true;
   if(UseNYSession && hour >= 13 && hour < 22) return true;

   return false;
}

//==================================================================
// PLACE ORDER
//==================================================================
void PlaceOrder(bool isBuy, double price, double sl, double tp)
{
   double lot = CalculateLotSize(sl, price, baseSymbolUsed);

   if(lot <= 0) return;

   bool result = false;

   if(isBuy)
      result = trade.Buy(lot, baseSymbolUsed, 0, sl, tp, "GSB_BUY");
   else
      result = trade.Sell(lot, baseSymbolUsed, 0, sl, tp, "GSB_SELL");

   if(result)
     {
      Print("=== ORDEN: ", isBuy ? "BUY" : "SELL", " | SL: ", sl, " TP: ", tp);
     }
}

void OnTradeExecuted()
{
   tradesToday++;
   lastTradeTime = TimeCurrent();
}

//==================================================================
// CALCULATE LOT SIZE
//==================================================================
double CalculateLotSize(double sl, double entry, string symbol)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPerTrade / 100.0);

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   double slDistance = MathAbs(entry - sl) / point;
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   double lot = riskAmount / (slDistance * tickValue);
   lot = MathFloor(lot / lotStep) * lotStep;

   lot = MathMax(minLot, MathMin(maxLot, lot));

   return NormalizeDouble(lot, 2);
}

//==================================================================
// ON DEINIT
//==================================================================
void OnDeinit(const int reason)
{
   Print("GoldScalp Break detenido");
}