"""
train_rf.py - Entrena RandomForest con data M1
Uso: python train_rf.py --input xauusd_m1.csv --version 3
Más rápido que LSTM, funciona con Python 3.14
"""

import argparse
import os
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import joblib
from dotenv import load_dotenv

# Cargar .env desde la raíz del repo
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

def prepare_features(df):
    """Prepara features para el modelo."""
    df = calculate_indicators(df)
    
    # Features
    features = [
        'Open', 'High', 'Low', 'Close', 'Volume',
        'RSI', 'EMA_9', 'EMA_21', 'ATR',
        'MACD', 'MACD_Signal', 'BB_Upper', 'BB_Lower'
    ]
    
    # Eliminar NaN
    df = df.dropna(subset=features)
    
    X = df[features].values
    
    # Target: 1 si la siguiente vela sube, 0 si baja
    df['Target'] = (df['CLOSE'].shift(-1) > df['CLOSE']).astype(int)
    y = df['Target'].values
    
    # Eliminar última fila (sin target)
    X = X[:-1]
    y = y[:-1]
    
    return X, y

def train_rf(input_csv: str, version: int = 1, n_estimators: int = 100):
    """Entrena RandomForest para M1."""
    
    # Si es ruta relativa, agregar prefijo desde .env
    if not os.path.isabs(input_csv):
        mt5_path = os.environ.get("MT5_FILES_PATH", "")
        if mt5_path and os.path.exists(mt5_path):
            input_csv = os.path.join(mt5_path, os.path.basename(input_csv))
            print(f"Usando ruta MT5: {input_csv}")
        else:
            input_csv = os.path.join(os.path.dirname(__file__), "..", "..", input_csv)
    
    print(f"Cargando data desde: {input_csv}")
    df = load_m1_data(input_csv)
    print(f"Data cargada: {len(df)} velas")
    
    X, y = prepare_features(df)
    print(f"Features: {X.shape}, Target: {y.shape}")
    
    # Train/Test split (80/20)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, shuffle=False
    )
    
    print(f"Train: {len(X_train)}, Test: {len(X_test)}")
    
    # Normalizar
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    
    # RandomForest
    model = RandomForestClassifier(
        n_estimators=n_estimators,
        max_depth=10,
        min_samples_split=20,
        min_samples_leaf=10,
        random_state=42,
        n_jobs=-1
    )
    
    # Entrenar
    print("Entrenando RandomForest...")
    model.fit(X_train_scaled, y_train)
    
    # Predecir
    y_pred = model.predict(X_test_scaled)
    acc = accuracy_score(y_test, y_pred)
    print(f"\nTest accuracy: {acc:.4f}")
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred))
    
    # Feature importance
    feature_names = ['OPEN', 'HIGH', 'LOW', 'CLOSE', 'VOL', 'RSI', 'EMA9', 'EMA21', 'ATR', 'MACD', 'MACD_Sig', 'BB_U', 'BB_L']
    importances = model.feature_importances_
    print("\nFeature Importances:")
    for name, imp in sorted(zip(feature_names, importances), key=lambda x: x[1], reverse=True):
        print(f"  {name}: {imp:.4f}")
    
    # Guardar modelo y scaler
    output_dir = os.path.join(os.path.dirname(__file__))
    os.makedirs(output_dir, exist_ok=True)
    
    joblib.dump(model, f"{output_dir}/rf_model_v{version}.joblib")
    joblib.dump(scaler, f"{output_dir}/scaler_v{version}.pkl")
    
    print(f"\nModelo guardado: rf_model_v{version}.joblib")
    print(f"Scaler guardado: scaler_v{version}.pkl")

def load_m1_data(csv_file: str) -> pd.DataFrame:
    """Carga data M1 del CSV exportado."""
    df = pd.read_csv(csv_file, sep="	", encoding="utf-16")
    
    print("Columnas disponibles:", df.columns.tolist()); print("Columnas:", df.columns.tolist()); required = ["Time", "Open", "High", "Low", "Close", "Volume"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"Falta columna: {col}")
    
    # Crear Time
    df["Time"] = pd.to_datetime(df["Time"], format="%Y.%m.%d %H:%M:%S")
    df.sort_values("Time", inplace=True)
    df.reset_index(drop=True, inplace=True)
    
    return df

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Entrena RandomForest para M1")
    parser.add_argument("--input", type=str, default="xauusd.csv", help="CSV input")
    parser.add_argument("--version", type=int, default=3, help="Version del modelo")
    parser.add_argument("--trees", type=int, default=100, help="Número de árboles")
    
    args = parser.parse_args()
    train_rf(args.input, args.version, args.trees)
