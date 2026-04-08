# Momentum_X3_Trading_Bot

**EA de trading para XAU/USD basado en señales momentum (RSI + ADX + MACD)**

---

## 📋 Parámetros del EA

### Indicadores - RSI
| Parámetro | Default | Descripción |
|----------|---------|-------------|
| `InpRSI_Len` | 14 | Período del RSI |
| `InpBuyRSI_Lvl` | 35 | Nivel de sobreventa (señal buy cuando RSI ≤ 35) |
| `InpSellRSI_Lvl` | 65 | Nivel de sobrecompra (señal sell cuando RSI ≥ 65) |
| `InpRSI_Lookbk` | 6 | Velas hacia atrás para confirmar RSI en sobreventa/sobrecompra |

### Indicadores - ADX
| Parámetro | Default | Descripción |
|----------|---------|-------------|
| `InpADX_Len` | 14 | Período del ADX |
| `InpADX_Slope` | 3 | Comparación de ADX (actual vs hace N velas para confirmar tendencia) |

### Indicadores - MACD
| Parámetro | Default | Descripción |
|----------|---------|-------------|
| `InpMACD_Fast` | 12 | EMA rápido del MACD |
| `InpMACD_Slow` | 26 | EMA lento del MACD |
| `InpMACD_Sig` | 9 | Señal del MACD (EMA de la diferencia) |
| `InpNorm_Len` | 100 | Período para normalización del MACD |
| `InpMACD_Depth` | 20.0 | Profundidad mínima del histograma MACD (0-100%) |

### Configuración - Trading
| Parámetro | Default | Descripción |
|----------|---------|-------------|
| `RiskPerTrade` | 1.0 | % del balance arriesgado por trade (para $300 recomienda 5-10%) |
| `DailyDrawdownLimit` | 5.0 | % máximo de pérdida diaria permitida |
| `MagicNumber` | 2026 | Identificador único del EA (para distinguir trades) |
| `BaseSymbolParam` | "" | Símbolo a tradear (vacío = usa el del chart) |
| `MainTF` | PERIOD_M1 | Timeframe principal para entradas |
| `HigherTF` | PERIOD_M5 | Timeframe superior para contexto |

### Filtros
| Parámetro | Default | Descripción |
|----------|---------|-------------|
| `UseSpreadFilter` | true | Activar filtro de spread |
| `MaxSpreadPoints` | 50 | Spread máximo permitido en puntos (para XAUUSD usar 50+) |
| `CheckMarketHours` | false | Verificar si el mercado está abierto |
| `GMTOffset` | 0 | Ajuste de GMT del broker |

### Gestión de Posiciones
| Parámetro | Default | Descripción |
|----------|---------|-------------|
| `UseTrailingStop` | true | Activar trailing stop |
| `TrailStopPips` | 15.0 | Distancia del trailing stop en pips |
| `UsePartialExit` | true | Cerrar parcialmente la posición |
| `PartialExitRatio` | 0.5 | % de la posición a cerrar (0.5 = 50%) |

---

## 🧠 Lógica de Señales

### Señal BUY
- RSI en sobreventa (≤ 35) en las últimas 6 velas
- MACD histograma en ascenso (3 velas consecutivas)
- ADX en subida (tendencia fortaleciéndose)
- DI- > DI+ (momento bearish弱まり)

### Señal SELL
- RSI en sobrecompra (≥ 65) en las últimas 6 velas
- MACD histograma en descenso (3 velas consecutivas)
- ADX en subida
- DI+ > DI- (momento bullish弱まり)

---

## ⚙️ Configuración Recomendada

### Para XAUUSD Scalping ($300 cuenta demo)
```
RiskPerTrade = 5-10%
DailyDrawdownLimit = 5%
MaxSpreadPoints = 50
MainTF = M1
HigherTF = M5
InpCooldown = 8
```

### Para XAUUSD Intraday ($1000+ cuenta)
```
RiskPerTrade = 1-2%
DailyDrawdownLimit = 5%
MaxSpreadPoints = 50
MainTF = M15
HigherTF = M30
InpCooldown = 4
```

---

## 📊 SL/TP

- **Stop Loss**: 300 pips fijos
- **Take Profit**: 600 pips (ratio 1:2)

---

## ⚠️ Disclaimer

Este código es con fines educativos. Opera bajo tu propio riesgo. Respaldá siempre tu cuenta.
- **Arquitectura del Modelo**: LSTM Secuencial (64→32 unidades, dropout 0.2, salida sigmoid)

### Protocolo de Intercambio de Datos
- **Mecanismo**: IPC basado en archivos via directorio `MQL5/Files/`
- **Archivo de Señal**: `signal.csv` contiene valor único de probabilidad (0.0-1.0)
- **Latencia**: ~50-100ms overhead de E/S de archivos (aceptable para timeframe M15)
- **Flujo**: MQL5 → Export CSV → Preprocesamiento Python → Predicción LSTM → signal.csv → Filtro MQL5

## 🏗 Arquitectura

### Diseño de Alto Nivel

**Arquitectura Orientada a Eventos** construida sobre el modelo de eventos de MetaTrader 5:

1. **OnInit()**: Evento de inicialización - config de símbolo, limpieza de dibujos, setup de CTrade
2. **OnTick()**: Loop principal de ejecución - disparado en cada actualización de precio
3. **OnDeinit()**: Evento de limpieza - remove objetos del chart, log de terminación

**Flujo de Ejecución**:
```
OnTick() (cada tick de precio)
  ↓
Detección de nueva vela (comparación datetime estática)
  ↓ Sí (ejecutar una vez por vela M15)
Reset de P&L diario (si es nuevo día de trading)
  ↓
Check de drawdown diario → Excedido? → Salir
  ↓ OK
Lectura de señal ML (si está habilitada) → Por debajo del threshold? → Salir
  ↓ OK
Calcular zonas Fibonacci H4 (premium/descuento)
  ↓
Detección de Order Blocks (si está habilitado)
  ↓
Cascada de evaluación de estrategias (SFT → FT → NFT → CT)
  ↓ Setup encontrado
Validación de riesgo/recompensa
  ↓
Check de spread + horas de mercado
  ↓
Cálculo de tamaño de posición
  ↓
Colocación de orden límite (con 3 intentos de reintento)
  ↓
Gestión de posiciones abiertas (trailing stop, salida parcial)
  ↓
Actualizar P&L diario del historial
```

### Componentes Clave

El EA está diseñado para operar de manera autónoma sin necesidad de scripts externos, pero puede integrarse con un pipeline de ML de Python para mejorar la calidad de las señales.

## 🚀 Empezando

### Requisitos
- MetaTrader 5 Terminal (build 3320+)
- Python 3.8+ (si usas ML)
- Cuenta de trading (demo o real)

### Instalación
1. Copia `MQL5/Experts/MyTradingBot.mq5` a la carpeta `MQL5/Experts` de tu MT5
2. Compila el EA en MetaEditor
3. Attach el EA al chart del símbolo deseado
4. Configura los parámetros de entrada

### Parámetros de Entrada
- `RiskPerTrade`: % de riesgo por operación
- `DailyDrawdownLimit`: Límite de pérdida diaria (%)
- `MainTF`: Timeframe principal para entradas (default: M15)
- `HigherTF`: Timeframe superior para contexto (default: H4)
- `UseMLSignal`: Habilitar filtro LSTM (default: false)
- `UseOrderBlocks`: Detectar Order Blocks (default: true)
- `MaxSpreadPoints`: Spread máximo permitido en puntos

## 📊 Estrategias SMC Incluidas

### SFT (Strong Follow-Through)
- Concepto: Expansión de alto momentum con liquidez sweep
- Criteria: Dos velas consecutivas bullish/bearish, ambas >1.5x rango promedio
- Kill zones: London 8-10 GMT, New York 13-15 GMT
- R/R: 1:2

### FT (Follow-Through)
- Concepto: Momentum moderado
- Criteria similares a SFT pero con menor.requirements
- R/R: 1:3

### NFT (No Follow-Through)
- Para mercados sin tendencia clara
- Busca rebotes en zonas de soporte/resistencia

### CT (Counter-Trend)
- Reversión contra tendencia
- Requiere confirmación fuerte

## ⚠️ Disclaimer

Este código es con fines educativos. No garantiza ganancias. Opera bajo tu propio riesgo.
