# MOMENTUM_X3_V2 - CAMBIOS IMPLEMENTADOS

## 📁 Archivos Creados/Modificados

### MQL5
- `MQL5/Experts/Momentum_X3_V2_Trading_Bot.mq5` - Nuevo EA con las 3 fases

### Python
- `python/train_xgb.py` - Training script con XGBoost
- `python/predict_signal.py` - Signal generator

---

## 🔄 CAMBIOS POR FASE

### FASE 1: Risk Management + Trend Filter ✅
| Parametro | Antes | Ahora |
|----------|-------|-------|
| SL | 300 pips fijo | 1.5 × ATR |
| TP | 600 pips fijo | 3.0 × ATR |
| RR teórico | 2:1 | 2:1 (dinamico) |
| ADX filter | No | Si (>20) |
| EMA200 filter | No | Si |

### FASE 2: Señales Mejoradas ✅
| Parametro | Antes | Ahora |
|----------|-------|-------|
| RSI Buy | 35 | 30 |
| RSI Sell | 65 | 70 |
| Cooldown | 8 bars | 15 bars |

### FASE 3: ML (XGBoost) ⏳
| Antes | Ahora |
|------|-------|
| RandomForest | XGBoost |
| Accuracy 48% | Target 60%+ |
| Features 13 | Features 16 |

---

## 📋 USO

### Compilar EA
1. Abrir `Momentum_x3_v2_trading_bot.mq5` en MetaEditor
2. Compilar (F7)

### Entrenar Modelo XGBoost
```bash
cd /root/.openclaw/workspace/MQL5-Trading-Bot/python
pip install -r ../requirements.txt

python train_xgb.py \
  --input /home/jesus/.wine-drive_c/Program\ Files/Vantage\ International\ MT5/MQL5/Files/xauusd.csv \
  --version v2
```

### Generar Signal
```bash
python predict_signal.py --input xauusd.csv --output signal.csv
```

---

## 🎯 PARAMETROS DEL EA

### Inputs Principales
| Parametro | Default | Descripcion |
|-----------|---------|-------------|
| InpATR_Mult_SL | 1.5 | Multiplicador SL |
| InpATR_Mult_TP | 3.0 | Multiplicador TP |
| InpMinADX | 20 | ADX minimo |
| InpBuyRSI_Lvl | 30 | RSI buy |
| InpSellRSI_Lvl | 70 | RSI sell |
| InpCooldown | 15 | Cooldown bars |
| UseTrendFilter | true | EMA200 filter |
| UseADXFilter | true | ADX filter |

---

## ⚠️ IMPORTANTE

1. **Backtestear** antes de usar en demo
2. **Entrenar XGBoost** con datos recentos
3. **Ajustar parametros** segun resultados

## 📊 Expected Results
- Win rate: 55-60% (was 51.3%)
- RR: 2:1 dinamico
- Trades: ~50% menos (cooldown mayor)
- Expectancy: $0.05+/trade