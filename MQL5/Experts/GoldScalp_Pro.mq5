//+------------------------------------------------------------------+
//|                            GoldScalp_Pro.mq5                    |
//|                     Scalping Aggresivo M1 - Sessions Filter      |
//|                     Objetivo: 75%+ Win Rate / Max 10 trades   |
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
input bool     UseAsiaSession   = true;      // 00:00 - 09:00 GMT
input bool     UseLondonSession = true;     // 08:00 - 17:00 GMT
input bool     UseNYSession    = true;     // 13:00 - 22:00 GMT
input int      GMTOffset       = 0;        // Tu GMT offset

//==================================================================
// INPUTS - SEÑALES (ESTRICTAS PARA 75%+ WR)
//==================================================================
input int      InpRSI_Period  = 7;         // RSI rapido
input double   InpRSI_Buy   = 25.0;       // Muy sobrevendido
input double   InpRSI_Sell  = 75.0;       // Muy sobrecomprado
input int      InpRSI_Lookbk = 3;

input int      InpMACD_Fast  = 5;          // MACD rapido
input int      InpMACD_Slow  = 12;
input int      InpMACD_Sig   = 4;

//==================================================================
// INPUTS - SL/TP (AGRESIVO)
//==================================================================
input int     InpSL_Pips    = 50;        // SL muy tight
input int     InpTP_Pips   = 100;       // TP 2:1 (conservador)
//input int     InpTP_Pips   = 50;        // TP 1:1 (agresivo)

//==================================================================
// INPUTS - LIMITE TRADES
//==================================================================
input int     MaxTradesPerDay = 10;
input int     InpCooldown     = 3;         // Minutos entre trades

//==================================================================
// INPUTS - TRADING
//==================================================================
input double   RiskPerTrade       = 2.0;       // 2% por trade (agresivo)
input double   DailyDrawdownLimit = 10.0;
input int      MagicNumber        = 2026;
input string   BaseSymbolParam    = "";
input ENUM_TIMEFRAMES MainTF      = PERIOD_M1;

input bool     UseSpreadFilter    = true;
input int      MaxSpreadPoints    = 40;

//==================================================================
// GLOBALES
//==================================================================
int hRSI, hMACD;
datetime lastBarTime;
string  baseSymbolUsed;

int tradesToday = 0;
datetime lastTradeTime = 0;

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
   
   // Indicadores
   hRSI  = iRSI(baseSymbolUsed, MainTF, InpRSI_Period, PRICE_CLOSE);
   hMACD = iMACD(baseSymbolUsed, MainTF, InpMACD_Fast, InpMACD_Slow, InpMACD_Sig, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hMACD == INVALID_HANDLE)
     {
      Print("Error: No se cargaron indicadores");
      return(INIT_FAILED);
     }
   
   Print("=== GOLDSCALP PRO INIT ===");
   Print("Symbol: ", baseSymbolUsed);
   Print("Sessions: ", (UseAsiaSession?"Asia ":"")+(UseLondonSession?"LON ":"")+(UseNYSession?"NY":""));
   Print("Max trades: ", MaxTradesPerDay, "/dia");
   Print("SL: ", InpSL_Pips, " | TP: ", InpTP_Pips);
   Print("========================");
   
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
   
   // Reset daily by time (midnight)
   MqlDateTime dt, dtLast;
   TimeToStruct(TimeCurrent(), dt);
   TimeToStruct(lastTradeTime, dtLast);
   
   if(dt.day_of_month != dtLast.day_of_month)
     {
      tradesToday = 0;
     }
   
   // Check limits
   if(tradesToday >= MaxTradesPerDay)
     {
      // Print("Max trades today reached");
      return;
     }
   
   // Cooldown
   if(lastTradeTime > 0 && (now - lastTradeTime) < InpCooldown * 60)
     {
      return;
     }
   
   // Spread
   if(UseSpreadFilter)
     {
      int spread = (int)SymbolInfoInteger(baseSymbolUsed, SYMBOL_SPREAD);
      if(spread > MaxSpreadPoints)
         return;
     }
   
   // Check session
   if(!IsSessionActive())
     {
      return;
     }
   
   //Señales
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
// CHECK SIGNAL (ESTRICTO PARA 75%+ WR)
//==================================================================
bool CheckSignal(bool &buySignal, bool &sellSignal, double &buySL, double &buyTP, double &sellSL, double &sellTP)
{
   double rsi[], macd[], macdSig[];
   
   if(CopyBuffer(hRSI, 0, 0, 20, rsi) < 20) return false;
   if(CopyBuffer(hMACD, 0, 0, 20, macd) < 20) return false;
   if(CopyBuffer(hMACD, 1, 0, 20, macdSig) < 20) return false;

   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(macdSig, true);

   double point = SymbolInfoDouble(baseSymbolUsed, SYMBOL_POINT);
   double ask = SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK);
   double bid = SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID);
   
   // ===== SEÑAL BUY (RSI sobrevendido + MACD cruzando) =====
   bool rsiOS = false;
   for(int i = 0; i < InpRSI_Lookbk; i++)
     {
      if(rsi[i] <= InpRSI_Buy) rsiOS = true;
     }
   
   // MACD cruzando hacia arriba (momentum bullish)
   bool macdCross = (macd[0] > macdSig[0]) && (macd[1] <= macdSig[1]);
   
   // MACD debajo de cero (preparan reversal)
   bool macdNegativo = macd[0] < 0;
   
   // RSI subiendo (momentum positivo)
   bool rsiRising = rsi[0] > rsi[1];
   
   bool buyCond = rsiOS && macdCross && macdNegativo && rsiRising;
   
   if(buyCond)
     {
      buySignal = true;
      buySL = ask - (InpSL_Pips * point);
      buyTP = bid + (InpTP_Pips * point);
      return true;
     }
   
   // ===== SEÑAL SELL (RSI sobrecomprado + MACD cruzando) =====
   bool rsiOB = false;
   for(int i = 0; i < InpRSI_Lookbk; i++)
     {
      if(rsi[i] >= InpRSI_Sell) rsiOB = true;
     }
   
   // MACD cruzando hacia abajo
   macdCross = (macd[0] < macdSig[0]) && (macd[1] >= macdSig[1]);
   
   // MACD encima de cero
   bool macdPositivo = macd[0] > 0;
   
   // RSI bajando
   bool rsiFalling = rsi[0] < rsi[1];
   
   bool sellCond = rsiOB && macdCross && macdPositivo && rsiFalling;
   
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
   
   // Asia: 00:00 - 09:00
   if(UseAsiaSession && hour >= 0 && hour < 9)
      return true;
   
   // London: 08:00 - 17:00
   if(UseLondonSession && hour >= 8 && hour < 17)
      return true;
   
   // NY: 13:00 - 22:00
   if(UseNYSession && hour >= 13 && hour < 22)
      return true;
   
   return false;
}

//==================================================================
// PLACE ORDER
//==================================================================
void PlaceOrder(bool isBuy, double price, double sl, double tp)
{
   double lot = CalculateLotSize(sl, price, baseSymbolUsed);
   
   if(lot <= 0)
     {
      Print("Error: No se calculo lot size");
      return;
     }
   
   if(isBuy && sl >= price) { Print("SL error"); return; }
   if(!isBuy && sl <= price) { Print("SL error"); return; }
   
   bool result = false;
   
   if(isBuy)
      result = trade.Buy(lot, baseSymbolUsed, 0, sl, tp, "GSP_BUY");
   else
      result = trade.Sell(lot, baseSymbolUsed, 0, sl, tp, "GSP_SELL");
   
   if(result)
     {
      Print("=== ORDEN: ", isBuy ? "BUY" : "SELL", " | SL: ", sl, " TP: ", tp);
     }
   else
     {
      Print("ERROR: ", trade.ResultRetcodeDescription());
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
   Print("GoldScalp Pro detenido");
}