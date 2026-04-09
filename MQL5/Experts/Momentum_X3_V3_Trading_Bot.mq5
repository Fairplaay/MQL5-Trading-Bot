//+------------------------------------------------------------------+
//|                              Momentum_X3_V3_Trading_Bot.mq5      |
//|                     Bot de trading XAU/USD - V3 (V1 + mejoras)     |
//|                     Basado en V1 que funcionaba                  |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "3.00"
#property strict
#property indicator_plots 0

#include <Trade\Trade.mqh>
CTrade  trade;

//==================================================================
// INPUTS - IGUAL AL V1 (QUE FUNCIONABA)
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

input int      InpCooldown     = 8;  // V1 era 8

//==================================================================
// INPUTS - SL/TP (FIJO COMO V1)
//==================================================================
input int     InpSL_Pips    = 300;   // SL fijo en pips
input int     InpTP_Pips   = 600;   // TP fijo en pips (RR 2:1)

//==================================================================
// INPUTS - OPCIONALES (para mejorar si quieres)
//==================================================================
input bool    UseATR_SL_TP   = false;  // Si true, usa ATR dinamico
input double  InpATR_SL_Mult = 2.0;
input double  InpATR_TP_Mult = 4.0;

//==================================================================
// INPUTS - TRADING
//==================================================================
input double   RiskPerTrade       = 1.0;
input double   DailyDrawdownLimit = 5.0;
input int      MagicNumber        = 2026;
input string   BaseSymbolParam    = "";
input ENUM_TIMEFRAMES MainTF      = PERIOD_M1;

input bool     UseSpreadFilter    = true;
input int      MaxSpreadPoints    = 50;

input bool     UseTrailingStop    = true;
input double   TrailStopPips      = 15.0;
input bool     UsePartialExit     = true;
input double   PartialExitRatio   = 0.5;

//==================================================================
// INPUTS - ML
//==================================================================
input bool     UseMLSignal        = false;
input double   ML_Threshold       = 0.55;

//==================================================================
// GLOBALES
//==================================================================
int hRSI, hADX, hMACD, hATR;
datetime lastBarTime;
string  baseSymbolUsed;

double  CurrentDailyLoss = 0.0;
datetime LastTradeDay;

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   if(BaseSymbolParam == "")
      baseSymbolUsed = _Symbol;
   else
      baseSymbolUsed = BaseSymbolParam;
   
   LastTradeDay = TimeCurrent();
   CurrentDailyLoss = 0.0;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Indicadores
   hRSI  = iRSI(baseSymbolUsed, MainTF, InpRSI_Len, PRICE_CLOSE);
   hADX  = iADX(baseSymbolUsed, MainTF, InpADX_Len);
   hMACD = iMACD(baseSymbolUsed, MainTF, InpMACD_Fast, InpMACD_Slow, InpMACD_Sig, PRICE_CLOSE);
   hATR  = iATR(baseSymbolUsed, MainTF, 14);
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hMACD == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("Error: No se pudieron cargar los indicadores");
      return(INIT_FAILED);
     }
   
   Print("=== MOMENTUM X3 V3 INIT ===");
   Print("Symbol: ", baseSymbolUsed);
   Print("SL: ", UseATR_SL_TP ? "ATR dinamico" : InpSL_Pips, " pips");
   Print("TP: ", UseATR_SL_TP ? "ATR dinamico" : InpTP_Pips, " pips");
   Print("Cooldown: ", InpCooldown, " bars");
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
   
   ResetDailyLossIfNewDay();
   
   if(!CheckDailyDrawdown(DailyDrawdownLimit, CurrentDailyLoss))
     {
      Print("Daily drawdown limit reached");
      return;
     }
   
   if(UseSpreadFilter)
     {
      int currentSpread = (int)SymbolInfoInteger(baseSymbolUsed, SYMBOL_SPREAD);
      if(currentSpread > MaxSpreadPoints)
        {
         Print("Spread too high: ", currentSpread);
         return;
        }
     }
   
   bool buySignal, sellSignal;
   double buySL, buyTP, sellSL, sellTP;
   
   if(CheckMomentumSignal(buySignal, sellSignal, buySL, buyTP, sellSL, sellTP))
     {
      if(UseMLSignal)
        {
         double mlProb = ReadMLSignal("signal.csv");
         if(mlProb < ML_Threshold)
           {
            Print("ML Signal below threshold - trade skipped");
            return;
           }
        }
      
      if(buySignal)
         PlaceOrder(true, SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK), buySL, buyTP);
      else if(sellSignal)
         PlaceOrder(false, SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID), sellSL, sellTP);
     }
   
   ManageOpenPositions();
}

//==================================================================
// CHECK MOMENTUM SIGNAL (EXACTO COMO V1)
//==================================================================
bool CheckMomentumSignal(bool &buySignal, bool &sellSignal, double &buySL, double &buyTP, double &sellSL, double &sellTP)
{
   static int bSinceBuy = 10;
   static int bSinceSell = 10;
   
   bSinceBuy++;
   bSinceSell++;
   
   double rsi[], adx[], diPlus[], diMinus[], mLine[], mSig[], atr[];
   
   if(CopyBuffer(hRSI, 0, 0, InpNorm_Len, rsi) < InpNorm_Len) return false;
   if(CopyBuffer(hADX, 0, 0, InpNorm_Len, adx) < InpNorm_Len) return false;
   if(CopyBuffer(hADX, 1, 0, InpNorm_Len, diPlus) < InpNorm_Len) return false;
   if(CopyBuffer(hADX, 2, 0, InpNorm_Len, diMinus) < InpNorm_Len) return false;
   if(CopyBuffer(hMACD, 0, 0, InpNorm_Len, mLine) < InpNorm_Len) return false;
   if(CopyBuffer(hMACD, 1, 0, InpNorm_Len, mSig) < InpNorm_Len) return false;
   if(CopyBuffer(hATR, 0, 0, 1, atr) < 1) return false;

   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(diPlus, true);
   ArraySetAsSeries(diMinus, true);
   ArraySetAsSeries(mLine, true);
   ArraySetAsSeries(mSig, true);

   double point = SymbolInfoDouble(baseSymbolUsed, SYMBOL_POINT);
   double ask = SymbolInfoDouble(baseSymbolUsed, SYMBOL_ASK);
   double bid = SymbolInfoDouble(baseSymbolUsed, SYMBOL_BID);
   double currentATR = atr[0];
   
   // SL/TP: fixed o dinamico
   double slPips = UseATR_SL_TP ? (currentATR / point) * InpATR_SL_Mult : InpSL_Pips;
   double tpPips = UseATR_SL_TP ? (currentATR / point) * InpATR_TP_Mult : InpTP_Pips;
   
   // Normalizacion MACD
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
      buySL = bid - (slPips * point);
      buyTP = bid + (tpPips * point);
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
      sellSL = ask + (slPips * point);
      sellTP = ask - (tpPips * point);
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
   
   if(isBuy && sl >= price) { Print("ERROR: SL debe ser menor al precio para BUY"); return; }
   if(!isBuy && sl <= price) { Print("ERROR: SL debe ser mayor al precio para SELL"); return; }
   
   bool result = false;
   
   if(isBuy)
      result = trade.Buy(lot, baseSymbolUsed, 0, sl, tp, "MomentumV3_BUY");
   else
      result = trade.Sell(lot, baseSymbolUsed, 0, sl, tp, "MomentumV3_SELL");
   
   if(result)
     {
      Print("=== ORDEN EJECUTADA V3 ===");
      Print("Tipo: ", isBuy ? "BUY" : "SELL");
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
// DAILY DRAWDOWN
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

//==================================================================
// DRAW SIGNAL
//==================================================================
void DrawSignal(datetime time, double price, bool isBuy)
{
   string name = "M3V3_Signal_" + TimeToString(TimeCurrent(), TIME_MINUTES);
   
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
   ObjectsDeleteAll(0, "M3V3_");
   Print("Bot V3 detenido");
}

//==================================================================
// READ ML SIGNAL
//==================================================================
double ReadMLSignal(string filename)
{
   string commonPath = "MQL5\\Files\\";
   string fullPath = commonPath + filename;
   
   int handle = FileOpen(fullPath, FILE_READ | FILE_CSV);
   if(handle == INVALID_HANDLE)
     {
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