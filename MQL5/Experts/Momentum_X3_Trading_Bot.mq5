//+------------------------------------------------------------------+
//|                                    Momentum_X3_Trading_Bot.mq5  |
//|                     Bot de trading XAU/USD basado en momentum    |
//|                     Combina señales momentum + sistema trading   |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"
#property strict
#property indicator_plots 0

#include <Trade\Trade.mqh>
CTrade  trade;

//==================================================================
// INPUTS - INDICADORES MOMENTUM
//==================================================================
input int      InpRSI_Len    = 14;
input double   InpBuyRSI_Lvl = 35.0;
input double   InpSellRSI_Lvl= 65.0;
input int      InpRSI_Lookbk = 6;

input int      InpADX_Len    = 14;
input int      InpADX_Slope  = 3;

input int      InpMACD_Fast  = 12;
input int      InpMACD_Slow  = 26;
input int      InpMACD_Sig   = 9;
input int      InpNorm_Len   = 100;
input double   InpMACD_Depth = 20.0;

input int      InpCooldown     = 8;

//==================================================================
// INPUTS - TRADING
//==================================================================
input double   RiskPerTrade       = 1.0;         // % riesgo por trade
input double   DailyDrawdownLimit = 5.0;         // Límite pérdida diaria (%)
input int      MagicNumber        = 2026;        // Magic Number
input string   BaseSymbolParam    = "";          // Símbolo (vacío = usar chart)
input ENUM_TIMEFRAMES MainTF      = PERIOD_M1;   // Timeframe principal
input ENUM_TIMEFRAMES HigherTF    = PERIOD_M5;   // Timeframe superior

input bool     UseSpreadFilter    = true;
input int      MaxSpreadPoints    = 50;          // Spread máximo para oro
input bool     CheckMarketHours   = false;       // Sin check de horas
input int      GMTOffset          = 0;

input bool     UseTrailingStop    = true;
input double   TrailStopPips      = 15.0;
input bool     UsePartialExit     = true;
input double   PartialExitRatio   = 0.5;

//==================================================================
// INPUTS - ML (LSTM)
//==================================================================
input bool     UseMLSignal        = false;       // Usar filtro LSTM
input double   ML_Threshold       = 0.55;        // Threshold del LSTM (0.0-1.0)

//==================================================================
// GLOBALES
//==================================================================
int hRSI, hADX, hMACD;
datetime lastBarTime;
string  baseSymbolUsed;

double  CurrentDailyLoss = 0.0;
datetime LastTradeDay;

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   // Configurar símbolo
   if(BaseSymbolParam == "")
      baseSymbolUsed = _Symbol;
   else
      baseSymbolUsed = BaseSymbolParam;
   
   LastTradeDay = TimeCurrent();
   CurrentDailyLoss = 0.0;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Inicializar indicadores
   hRSI  = iRSI(baseSymbolUsed, MainTF, InpRSI_Len, PRICE_CLOSE);
   hADX  = iADX(baseSymbolUsed, MainTF, InpADX_Len);
   hMACD = iMACD(baseSymbolUsed, MainTF, InpMACD_Fast, InpMACD_Slow, InpMACD_Sig, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hMACD == INVALID_HANDLE)
     {
      Print("Error: No se pudieron cargar los indicadores");
      return(INIT_FAILED);
     }
   
   Print("=== MOMENTUM TRADING BOT INIT ===");
   Print("Symbol: ", baseSymbolUsed);
   Print("Timeframe: ", EnumToString(MainTF));
   Print("Risk: ", RiskPerTrade, "%");
   Print("==================================");
   
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
   
   // Reset daily loss si nuevo día
   ResetDailyLossIfNewDay();
   
   // Check daily drawdown
   if(!CheckDailyDrawdown(DailyDrawdownLimit, CurrentDailyLoss))
     {
      Print("Daily drawdown limit reached");
      return;
     }
   
   // Verificar spread
   if(UseSpreadFilter)
     {
      int currentSpread = (int)SymbolInfoInteger(baseSymbolUsed, SYMBOL_SPREAD);
      if(currentSpread > MaxSpreadPoints)
        {
         Print("Spread too high: ", currentSpread);
         return;
        }
     }
   
   // Verificar mercado abierto
   if(CheckMarketHours && !IsMarketOpen())
     {
      Print("Mercado cerrado");
      return;
     }
   
   // Evaluar señal
   bool buySignal, sellSignal;
   double buySL, buyTP, sellSL, sellTP;
   
   if(CheckMomentumSignal(buySignal, sellSignal, buySL, buyTP, sellSL, sellTP))
     {
      // Verificar ML Signal si está habilitado
      if(UseMLSignal)
        {
         double mlProb = ReadMLSignal("signal.csv");
         Print("ML Probability: ", mlProb);
         if(mlProb < ML_Threshold)
           {
            Print("ML Signal below threshold - trade skipped");
            return;
           }
        }
      
      // Ejecutar BUY
      if(buySignal)
        {
         PlaceOrder(true, SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK), buySL, buyTP);
        }
      // Ejecutar SELL
      else if(sellSignal)
        {
         PlaceOrder(false, SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID), sellSL, sellTP);
        }
     }
   
   // Gestionar posiciones abiertas
   ManageOpenPositions();
}

//==================================================================
// CHECK MOMENTUM SIGNAL
//==================================================================
bool CheckMomentumSignal(bool &buySignal, bool &sellSignal, double &buySL, double &buyTP, double &sellSL, double &sellTP)
{
   static int bSinceBuy = 10;
   static int bSinceSell = 10;
   
   bSinceBuy++;
   bSinceSell++;
   
   double rsi[], adx[], diPlus[], diMinus[], mLine[], mSig[];
   
   if(CopyBuffer(hRSI, 0, 0, InpNorm_Len, rsi) < InpNorm_Len) return false;
   if(CopyBuffer(hADX, 0, 0, InpNorm_Len, adx) < InpNorm_Len) return false;
   if(CopyBuffer(hADX, 1, 0, InpNorm_Len, diPlus) < InpNorm_Len) return false;
   if(CopyBuffer(hADX, 2, 0, InpNorm_Len, diMinus) < InpNorm_Len) return false;
   if(CopyBuffer(hMACD, 0, 0, InpNorm_Len, mLine) < InpNorm_Len) return false;
   if(CopyBuffer(hMACD, 1, 0, InpNorm_Len, mSig) < InpNorm_Len) return false;

   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(diPlus, true);
   ArraySetAsSeries(diMinus, true);
   ArraySetAsSeries(mLine, true);
   ArraySetAsSeries(mSig, true);

   double point = SymbolInfoDouble(baseSymbolUsed, SYMBOL_POINT);
   double ask = SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK);
   double bid = SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID);
   
   // Normalización MACD
   double peak = 0.0000001;
   for(int i = 0; i < InpNorm_Len; i++)
     {
      double h = mLine[i] - mSig[i];
      double v = MathMax(MathAbs(mLine[i]), MathMax(MathAbs(mSig[i]), MathAbs(h)));
      if(v > peak) peak = v;
     }
   
   // SEÑAL BUY
   bool rsiOS = false;
   double minH = 999999;
   for(int i = 0; i < InpRSI_Lookbk; i++)
     {
      if(rsi[i] <= InpBuyRSI_Lvl) rsiOS = true;
      if((mLine[i] - mSig[i]) < minH) minH = (mLine[i] - mSig[i]);
     }
   
   bool buyHist = (mLine[0] - mSig[0]) > (mLine[1] - mSig[1]) && (mLine[1] - mSig[1]) > (mLine[2] - mSig[2]);
   bool buyFinal = rsiOS && buyHist && (minH <= -peak * (InpMACD_Depth / 100.0)) && (diPlus[0] < diMinus[0]) && (adx[0] > adx[InpADX_Slope]);
   
   if(buyFinal && bSinceBuy >= InpCooldown)
     {
      buySignal = true;
      buySL = bid - (300 * point);  // SL 300 pips
      buyTP = bid + (600 * point);  // TP 600 pips (1:2)
      DrawSignal(0, bid, true);
      bSinceBuy = 0;
      return true;
     }
   
   // SEÑAL SELL
   bool rsiOB = false;
   double maxH = -999999;
   for(int i = 0; i < InpRSI_Lookbk; i++)
     {
      if(rsi[i] >= InpSellRSI_Lvl) rsiOB = true;
      if((mLine[i] - mSig[i]) > maxH) maxH = (mLine[i] - mSig[i]);
     }
   
   bool sellHist = (mLine[0] - mSig[0]) < (mLine[1] - mSig[1]) && (mLine[1] - mSig[1]) < (mLine[2] - mSig[2]);
   bool sellFinal = rsiOB && sellHist && (maxH >= peak * (InpMACD_Depth / 100.0)) && (diMinus[0] < diPlus[0]) && (adx[0] > adx[InpADX_Slope]);
   
   if(sellFinal && bSinceSell >= InpCooldown)
     {
      sellSignal = true;
      sellSL = ask + (300 * point);
      sellTP = ask - (600 * point);
      DrawSignal(0, ask, false);
      bSinceSell = 0;
      return true;
     }
   
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
      Print("Error: No se pudo calcular lot size");
      return;
     }
   
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   // Validar SL/TP dirección
   if(isBuy && sl >= price) { Print("ERROR: SL debe ser menor al precio para BUY"); return; }
   if(!isBuy && sl <= price) { Print("ERROR: SL debe ser mayor al precio para SELL"); return; }
   
   bool result = false;
   
   if(isBuy)
      result = trade.Buy(lot, baseSymbolUsed, 0, sl, tp, "Momentum_BUY");
   else
      result = trade.Sell(lot, baseSymbolUsed, 0, sl, tp, "Momentum_SELL");
   
   if(result)
     {
      Print("=== ORDEN EJECUTADA ===");
      Print("Tipo: ", isBuy ? "BUY" : "SELL");
      Print("Lot: ", lot);
      Print("SL: ", sl, " TP: ", tp);
     }
   else
     {
      Print("ERROR: ", trade.ResultRetcodeDescription());
     }
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
// MANAGE POSITIONS
//==================================================================
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      
      if(sym != baseSymbolUsed || magic != MagicNumber) continue;
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Trailing Stop
      if(UseTrailingStop)
        {
         double point = SymbolInfoDouble(baseSymbolUsed, SYMBOL_POINT);
         double trailDistance = TrailStopPips * point;
         
         if(posType == POSITION_TYPE_BUY && profit > trailDistance * 10)
           {
            double newSL = openPrice + trailDistance;
            if(newSL > sl)
               trade.PositionModify(ticket, newSL, tp);
           }
         else if(posType == POSITION_TYPE_SELL && profit > trailDistance * 10)
           {
            double newSL = openPrice - trailDistance;
            if(newSL < sl || sl == 0)
               trade.PositionModify(ticket, newSL, tp);
           }
        }
      
      // Partial Exit
      if(UsePartialExit && profit > 0)
        {
         double volume = PositionGetDouble(POSITION_VOLUME);
         double minLot = SymbolInfoDouble(baseSymbolUsed, SYMBOL_VOLUME_MIN);
         
         if(volume > minLot * 2)
           {
            trade.PositionClosePartial(ticket, volume * PartialExitRatio);
           }
        }
     }
}

//==================================================================
// DAILY DRAWDDOWN
//==================================================================
void ResetDailyLossIfNewDay()
{
   datetime dayStart = iTime(baseSymbolUsed, PERIOD_D1, 0);
   if(dayStart > LastTradeDay)
     {
      CurrentDailyLoss = 0.0;
      LastTradeDay = dayStart;
      Print("=== NUEVO DÍA DE TRADING ===");
     }
}

bool CheckDailyDrawdown(double limit, double currentLoss)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(balance <= 0) return false;
   
   double ddPercent = ((balance - equity) / balance) * 100.0;
   
   return (ddPercent < limit);
}

void UpdateCurrentDailyLoss()
{
   // Calcular pérdida diaria basada en equity vs balance
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   CurrentDailyLoss = balance - equity;
}

//==================================================================
// MARKET HOURS
//==================================================================
bool IsMarketOpen()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   datetime serverTime = currentTime + GMTOffset * 3600;
   TimeToStruct(serverTime, dt);
   
   // Weekend
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   
   // Hours: 22-24 and 0-21 GMT ( Forex market)
   if((dt.hour >= 22 || dt.hour < 21)) return true;
   
   return false;
}

//==================================================================
// DRAW SIGNAL
//==================================================================
void DrawSignal(datetime time, double price, bool isBuy)
{
   string name = "M3_Signal_" + TimeToString(TimeCurrent(), TIME_MINUTES);
   
   ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
   
   if(isBuy)
     {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
     }
   else
     {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
     }
   
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
}

//==================================================================
// ON DEINIT
//==================================================================
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "M3_");
   Print("Bot detenido");
}

//==================================================================
// READ ML SIGNAL (LSTM)
//==================================================================
double ReadMLSignal(string filename)
{
   string commonPath = "MQL5\\Files\\";
   string fullPath = commonPath + filename;
   
   int handle = FileOpen(fullPath, FILE_READ | FILE_CSV);
   if(handle == INVALID_HANDLE)
     {
      Print("Failed to open ML signal file: ", filename);
      return 0.0;
     }
   
   double prob = 0.0;
   while(!FileIsEnding(handle))
     {
      string line = FileReadString(handle);
      if(line != "")
        {
         prob = StringToDouble(line);
        }
     }
   
   FileClose(handle);
   return prob;
}
