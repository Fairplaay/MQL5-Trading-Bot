#!/usr/bin/env python3
"""
Momentum_X3_V2 - Signal Generator
==============================
Genera signals en tiempo real para el EA en MQL5.
"""

import pandas as pd
import numpy as np
import joblib
import json
from datetime import datetime
from datetime import timezone

def load_model(version='v2'):
    """Carga modelo y scaler"""
    model_path = f"/root/.openclaw/workspace/MQL5-Trading-Bot/python/xgb_model_{version}.joblib"
    scaler_path = f"/root/.openclaw/workspace/MQL5-Trading-Bot/python/scaler_{version}.pkl"
    
    model = joblib.load(model_path)
    scaler = joblib.load(scaler_path)
    
    return model, scaler

def calculate_realtime_indicators(df):
    """Calcula indicadores para ultima vela"""
    df = df.copy()
    
    # RSI
    delta = df['close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))
    df['RSI_slope'] = df['RSI'].diff(3) / 3
    
    # MACD
    ema12 = df['close'].ewm(span=12, adjust=False).mean()
    ema26 = df['close'].ewm(span=26, adjust=False).mean()
    df['MACD'] = ema12 - ema26
    df['MACD_signal'] = df['MACD'].ewm(span=9, adjust=False).mean()
    df['MACD_hist'] = df['MACD'] - df['MACD_signal']
    
    # ADX
    high_low = df['high'] - df['low']
    high_close = abs(df['high'] - df['close'].shift())
    low_close = abs(df['low'] - df['close'].shift())
    ranges = pd.concat([high_low, high_close, low_close], axis=1)
    true_range = ranges.max(axis=1)
    
    plus_dm = df['high'].diff()
    minus_dm = -df['low'].diff()
    plus_dm[plus_dm < 0] = 0
    minus_dm[minus_dm < 0] = 0
    
    ATR = true_range.rolling(14).mean()
    plus_di = 100 * (plus_dm.ewm(span=14).mean() / ATR)
    minus_di = 100 * (minus_dm.ewm(span=14).mean() / ATR)
    dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di)
    df['ADX'] = dx.rolling(14).mean()
    df['ATR'] = ATR
    
    # EMAs
    df['EMA50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['EMA200'] = df['close'].ewm(span=200, adjust=False).mean()
    df['EMA_slope'] = (df['EMA200'] - df['EMA200'].shift(10)) / 10
    
    # Bollinger
    df['BB_upper'] = df['close'].rolling(20).mean() + 2 * df['close'].rolling(20).std()
    df['BB_lower'] = df['close'].rolling(20).mean() - 2 * df['close'].rolling(20).std()
    df['BB_width'] = df['BB_upper'] - df['BB_lower']
    
    # Returns
    df['Returns_lag1'] = df['close'].pct_change(1)
    df['Returns_lag2'] = df['close'].pct_change(2)
    df['volume'] = df.get('volume', 1)
    
    return df

FEATURES = [
    'RSI', 'RSI_slope', 'MACD', 'MACD_signal', 'MACD_hist',
    'ADX', 'ATR', 'EMA50', 'EMA200', 'EMA_slope',
    'BB_upper', 'BB_lower', 'BB_width', 'Returns_lag1', 'Returns_lag2', 'volume'
]

def generate_signal(df, version='v2'):
    """Genera signal para ultima vela"""
    
    model, scaler = load_model(version)
    
    # Calcular indicadores
    df = calculate_realtime_indicators(df)
    
    # Obtener ultima fila
    last_row = df[FEATURES].iloc[-1:].fillna(0)
    
    # Scale
    X = scaler.transform(last_row)
    
    # Predict
    prob = model.predict_proba(X)[0][1]
    
    return prob

def main():
    # Ejemplo de uso
    print("Momentum_X3_V2 Signal Generator")
    print("Usage: python predict_signal.py --input xauusd.csv")
    print("\nPara generar signal.csv para MT5:")
    print("  python predict_signal.py --input xauusd.csv --output signal.csv")

if __name__ == '__main__':
    main()