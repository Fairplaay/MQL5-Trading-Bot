"""
train_m1.py - Entrena LSTM con data de un solo timeframe (M1)
Uso: python train_m1.py --symbol XAUUSD --bars 2000
"""

import argparse
import os
import pandas as pd
import numpy as np
import tensorflow as tf
from tensorflow.keras import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from sklearn.preprocessing import StandardScaler
import joblib
import sys

def load_m1_data(csv_file: str) -> pd.DataFrame:
    """Carga data M1 del CSV exportado."""
    df = pd.read_csv(csv_file)
    
    required = ["DATE", "TIME", "OPEN", "HIGH", "LOW", "CLOSE", "TICKVOL"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"Falta columna: {col}")
    
    # Crear Time
    df["Time"] = pd.to_datetime(df["DATE"] + " " + df["TIME"], format="%Y.%m.%d %H:%M:%S")
    df.sort_values("Time", inplace=True)
    df.reset_index(drop=True, inplace=True)
    
    return df

def prepare_features(df: pd.DataFrame) -> tuple:
    """Prepara features para el modelo."""
    # Features: Close, Open, High, Low, Volume
    features = ["OPEN", "HIGH", "LOW", "CLOSE", "TICKVOL"]
    X = df[features].values
    
    # Target: 1 si la siguiente vela sube, 0 si baja
    df["Target"] = (df["CLOSE"].shift(-1) > df["CLOSE"]).astype(int)
    y = df["Target"].values
    
    # Eliminar última fila (sin target)
    X = X[:-1]
    y = y[:-1]
    
    return X, y

def train_m1(input_csv: str, version: int = 1, epochs: int = 30, batch_size: int = 32):
    """Entrena modelo LSTM para M1."""
    print(f"Cargando data desde: {input_csv}")
    df = load_m1_data(input_csv)
    print(f"Data cargada: {len(df)} velas")
    
    X, y = prepare_features(df)
    print(f"Features: {X.shape}, Target: {y.shape}")
    
    # Train/Val/Test split (70/15/15)
    n = len(X)
    train_end = int(n * 0.7)
    val_end = int(n * 0.85)
    
    X_train, y_train = X[:train_end], y[:train_end]
    X_val, y_val = X[train_end:val_end], y[train_end:val_end]
    X_test, y_test = X[val_end:], y[val_end:]
    
    print(f"Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")
    
    # Normalizar
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_val_scaled = scaler.transform(X_val)
    X_test_scaled = scaler.transform(X_test)
    
    # Reshape para LSTM (samples, timesteps, features)
    X_train_scaled = X_train_scaled.reshape((X_train_scaled.shape[0], 1, X_train_scaled.shape[1]))
    X_val_scaled = X_val_scaled.reshape((X_val_scaled.shape[0], 1, X_val_scaled.shape[1]))
    X_test_scaled = X_test_scaled.reshape((X_test_scaled.shape[0], 1, X_test_scaled.shape[1]))
    
    # Modelo LSTM
    model = Sequential([
        LSTM(32, return_sequences=True, input_shape=(1, 5), activation='relu'),
        Dropout(0.2),
        LSTM(16, activation='relu'),
        Dropout(0.2),
        Dense(1, activation='sigmoid')
    ])
    
    model.compile(
        optimizer=Adam(learning_rate=0.001),
        loss='binary_crossentropy',
        metrics=['accuracy']
    )
    
    # Callbacks
    early_stop = EarlyStopping(monitor='val_loss', patience=5, restore_best_weights=True)
    
    # Entrenar
    print("Entrenando...")
    history = model.fit(
        X_train_scaled, y_train,
        epochs=epochs,
        batch_size=batch_size,
        validation_data=(X_val_scaled, y_val),
        callbacks=[early_stop],
        verbose=1
    )
    
    # Evaluar
    loss, acc = model.evaluate(X_test_scaled, y_test, verbose=0)
    print(f"\nTest accuracy: {acc:.4f}")
    
    # Guardar modelo y scaler
    output_dir = "python/models"
    os.makedirs(output_dir, exist_ok=True)
    
    model.save(f"{output_dir}/lstm_model_v{version}.h5")
    joblib.dump(scaler, f"{output_dir}/scaler_v{version}.pkl")
    
    print(f"Modelo guardado: lstm_model_v{version}.h5")
    print(f"Scaler guardado: scaler_v{version}.pkl")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Entrena LSTM para M1")
    parser.add_argument("--input", type=str, default="mt5_export.csv", help="CSV input")
    parser.add_argument("--version", type=int, default=3, help="Version del modelo")
    parser.add_argument("--epochs", type=int, default=30, help="Épocas")
    parser.add_argument("--batch", type=int, default=32, help="Batch size")
    
    args = parser.parse_args()
    train_m1(args.input, args.version, args.epochs, args.batch)
