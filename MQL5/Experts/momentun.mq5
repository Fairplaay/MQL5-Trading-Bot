//+------------------------------------------------------------------+
//|                                     Momentum_X3_Visual_BT.mq5    |
//|                                  Copyright 2026, AI Collaborator |
//+------------------------------------------------------------------+
#property strict

// --- INPUTS RSI ---
input int      InpRSI_Len    = 14;
input double   InpBuyRSI_Lvl = 35.0;
input double   InpSellRSI_Lvl= 65.0;
input int      InpRSI_Lookbk = 6;

// --- INPUTS ADX ---
input int      InpADX_Len    = 14;
input int      InpADX_Slope  = 3;

// --- INPUTS MACD ---
input int      InpMACD_Fast  = 12;
input int      InpMACD_Slow  = 26;
input int      InpMACD_Sig   = 9;
input int      InpNorm_Len   = 100;
input double   InpMACD_Depth = 20.0;

// --- CONFIG VISUAL ---
input int      InpBacktestBars = 500; // Velas a escanear al inicio
input int      InpCooldown     = 8;   // Velas de espera entre señales

// --- GLOBALES ---
int hRSI, hADX, hMACD;
datetime lastBarTime;

//+------------------------------------------------------------------+
//| Init: Carga indicadores y escanea el historial                   |
//+------------------------------------------------------------------+
int OnInit()
{
   hRSI  = iRSI(_Symbol, _Period, InpRSI_Len, PRICE_CLOSE);
   hADX  = iADX(_Symbol, _Period, InpADX_Len);
   hMACD = iMACD(_Symbol, _Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Sig, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hMACD == INVALID_HANDLE) return(INIT_FAILED);

   // Esperar un momento a que los indicadores calculen
   Sleep(1000);
   
   // Ejecutar backtest visual inicial
   Print("Iniciando backtest visual...");
   ScanHistory();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick: Dibuja señales en la vela que acaba de cerrar            |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentTime = iTime(_Symbol, _Period, 0);
   if(currentTime == lastBarTime) return;
   lastBarTime = currentTime;

   // Evaluar la vela que acaba de cerrar (índice 1)
   CheckSignalForBar(1);
}

//+------------------------------------------------------------------+
//| Escanea el historial para pintar señales pasadas                 |
//+------------------------------------------------------------------+
void ScanHistory()
{
   int barsToScan = MathMin(InpBacktestBars, iBars(_Symbol, _Period) - InpNorm_Len - 5);
   
   for(int i = barsToScan; i >= 1; i--)
   {
      CheckSignalForBar(i);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Lógica Core: Evalúa una vela específica y dibuja si cumple       |
//+------------------------------------------------------------------+
void CheckSignalForBar(int index)
{
   // Variables estáticas para manejar el cooldown durante el escaneo
   static int bSinceBuy = 10;
   static int bSinceSell = 10;
   
   bSinceBuy++;
   bSinceSell++;

   double rsi[], adx[], diPlus[], diMinus[], mLine[], mSig[];
   
   // Copiar datos necesarios para la normalización (100 velas desde el índice evaluado)
   if(CopyBuffer(hRSI, 0, index, InpNorm_Len, rsi) < InpNorm_Len) return;
   if(CopyBuffer(hADX, 0, index, InpNorm_Len, adx) < InpNorm_Len) return;
   if(CopyBuffer(hADX, 1, index, InpNorm_Len, diPlus) < InpNorm_Len) return;
   if(CopyBuffer(hADX, 2, index, InpNorm_Len, diMinus) < InpNorm_Len) return;
   if(CopyBuffer(hMACD, 0, index, InpNorm_Len, mLine) < InpNorm_Len) return;
   if(CopyBuffer(hMACD, 1, index, InpNorm_Len, mSig) < InpNorm_Len) return;

   ArraySetAsSeries(rsi, true); ArraySetAsSeries(adx, true);
   ArraySetAsSeries(diPlus, true); ArraySetAsSeries(diMinus, true);
   ArraySetAsSeries(mLine, true); ArraySetAsSeries(mSig, true);

   // 1. Normalización Dinámica del MACD Peak
   double peak = 0.0000001;
   for(int i=0; i<InpNorm_Len; i++) {
      double h = mLine[i] - mSig[i];
      double v = MathMax(MathAbs(mLine[i]), MathMax(MathAbs(mSig[i]), MathAbs(h)));
      if(v > peak) peak = v;
   }

   // 2. Condición Compra
   bool rsiOS = false;
   double minH = 999999;
   for(int i=0; i<InpRSI_Lookbk; i++) {
      if(rsi[i] <= InpBuyRSI_Lvl) rsiOS = true;
      if((mLine[i]-mSig[i]) < minH) minH = (mLine[i]-mSig[i]);
   }
   bool buyHist = (mLine[0]-mSig[0]) > (mLine[1]-mSig[1]) && (mLine[1]-mSig[1]) > (mLine[2]-mSig[2]);
   bool buyFinal = rsiOS && buyHist && (minH <= -peak*(InpMACD_Depth/100.0)) && (diPlus[0] < diMinus[0]) && (adx[0] > adx[InpADX_Slope]);

   if(buyFinal && bSinceBuy >= InpCooldown) {
      DrawArrow(index, true);
      bSinceBuy = 0;
   }

   // 3. Condición Venta
   bool rsiOB = false;
   double maxH = -999999;
   for(int i=0; i<InpRSI_Lookbk; i++) {
      if(rsi[i] >= InpSellRSI_Lvl) rsiOB = true;
      if((mLine[i]-mSig[i]) > maxH) maxH = (mLine[i]-mSig[i]);
   }
   bool sellHist = (mLine[0]-mSig[0]) < (mLine[1]-mSig[1]) && (mLine[1]-mSig[1]) < (mLine[2]-mSig[2]);
   bool sellFinal = rsiOB && sellHist && (maxH >= peak*(InpMACD_Depth/100.0)) && (diMinus[0] < diPlus[0]) && (adx[0] > adx[InpADX_Slope]);

   if(sellFinal && bSinceSell >= InpCooldown) {
      DrawArrow(index, false);
      bSinceSell = 0;
   }
}

//+------------------------------------------------------------------+
//| Dibuja el objeto en el gráfico                                   |
//+------------------------------------------------------------------+
void DrawArrow(int index, bool isBuy)
{
   string name = "M3_" + (isBuy ? "Buy_" : "Sell_") + IntegerToString(iTime(_Symbol, _Period, index));
   double price = isBuy ? iLow(_Symbol, _Period, index) : iHigh(_Symbol, _Period, index);
   ENUM_OBJECT objType = OBJ_ARROW;
   
   ObjectCreate(0, name, OBJ_ARROW, 0, iTime(_Symbol, _Period, index), price);
   
   if(isBuy) {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233); // Flecha arriba
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_TOP); // Anclada abajo de la vela
   } else {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234); // Flecha abajo
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_BOTTOM); // Anclada arriba de la vela
   }
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, "M3_"); // Limpia las flechas al quitar el EA
}