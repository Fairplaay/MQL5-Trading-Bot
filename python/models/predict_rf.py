"""
predict_rf.py - Predice con RandomForest en tiempo real
Uso: python predict_rf.py
Lee data actual, predice probabilidad, escribe signal.csv
"""

import os
import pandas as pd
import numpy as np
import joblib
from dotenv import load_dotenv
import time

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

def calculate_indicators(df):
    """Calcula indicadores técnicos como features."""
    # RSI
    delta = df['CLOSE'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))
    
    # EMA
    df['EMA_9'] = df['CLOSE'].ewm(span=9, adjust=False).mean()
    df['EMA_21'] = df['CLOSE'].ewm(span=21, adjust=False).mean()
    
    # ATR
    high_low = df['HIGH'] - df['LOW']
    high_close = np.abs(df['HIGH'] - df['CLOSE'].shift())
    low_close = np.abs(df['LOW'] - df['CLOSE'].shift())
    ranges = pd.concat([high_low, high_close, low_close], axis=1)
    true_range = ranges.max(axis=1)
    df['ATR'] = true_range.rolling(14).mean()
    
    # MACD
    exp1 = df['CLOSE'].ewm(span=12, adjust=False).mean()
    exp2 = df['CLOSE'].ewm(span=26, adjust=False).mean()
    df['MACD'] = exp1 - exp2
    df['MACD_Signal'] = df['MACD'].ewm(span=9, adjust=False).mean()
    
    # BB
    df['BB_Mid'] = df['CLOSE'].rolling(20).mean()
    bb_std = df['CLOSE'].rolling(20).std()
    df['BB_Upper'] = df['BB_Mid'] + (bb_std * 2)
    df['BB_Lower'] = df['BB_Mid'] - (bb_std * 2)
    
    return df

def predict(model_file: str, scaler_file: str, version: int = 3):
    """Hace predicción con el modelo."""
    
    # Cargar modelo y scaler
    model = joblib.load(model_file)
    scaler = joblib.load(scaler_file)
    
    # Features
    features = ['OPEN', 'HIGH', 'LOW', 'CLOSE', 'TICKVOL',
                'RSI', 'EMA_9', 'EMA_21', 'ATR',
                'MACD', 'MACD_Signal', 'BB_Upper', 'BB_Lower']
    
    # Buscar data reciente del MT5
    mt5_path = os.environ.get("MT5_FILES_PATH", "")
    csv_file = os.path.join(mt5_path, "xauusd_m1.csv")
    
    if not os.path.exists(csv_file):
        print(f"Archivo no encontrado: {csv_file}")
        return 0.0
    
    # Cargar data
    df = pd.read_csv(csv_file)
    df["Time"] = pd.to_datetime(df["DATE"] + " " + df["TIME"], format="%Y.%m.%d %H:%M:%S")
    df.sort_values("Time", inplace=True)
    df.reset_index(drop=True, inplace=True)
    
    # Calcular features
    df = calculate_indicators(df)
    df = df.dropna()
    
    if len(df) < 1:
        print("No hay data suficiente")
        return 0.0
    
    # Tomar última vela
    X = df[features].tail(1).values
    X_scaled = scaler.transform(X)
    
    # Predecir
    prob = model.predict_proba(X_scaled)[0][1]  # Probabilidad de clase 1 (sube)
    
    return prob

def main():
    model_dir = os.path.join(os.path.dirname(__file__))
    version = 3
    
    model_file = os.path.join(model_dir, f"rf_model_v{version}.joblib")
    scaler_file = os.path.join(model_dir, f"scaler_v{version}.pkl")
    
    # Verificar que existan
    if not os.path.exists(model_file):
        print(f"Modelo no encontrado: {model_file}")
        print("Primero entrena con: python train_rf.py --version 3")
        return
    
    print("=== RandomForest Prediction ===")
    
    prob = predict(model_file, scaler_file, version)
    print(f"Probabilidad de SUBIDA: {prob:.4f}")
    
    # Escribir a signal.csv (formato que espera el EA)
    signal_file = os.path.join(mt5_path := os.environ.get("MT5_FILES_PATH", ""), "signal.csv")
    if mt5_path:
        with open(signal_file, 'w') as f:
            f.write(f"{prob:.4f}")
        print(f"Señal escrita en: {signal_file}")

if __name__ == "__main__":
    main()
