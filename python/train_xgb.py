#!/usr/bin/env python3
"""
Momentum_X3_V2 - XGBoost ML Model Training
==========================================
Reemplaza RandomForest con XGBoost para mejor accuracy.

FASE 3: Implementacion del nuevo modelo ML
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split, TimeSeriesSplit
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, accuracy_score
import xgboost as xgb
import joblib
from datetime import datetime
import argparse
import os

# Features para XGBoost (mejoradas)
FEATURES = [
    'RSI',              # Indice de fuerza relativa
    'RSI_slope',         # Pendiente RSI
    'MACD',             # Linea MACD
    'MACD_signal',      # Linea de señal
    'MACD_hist',       # Histograma MACD
    'ADX',             # Indice de movimiento direccional
    'ATR',             # Rango verdadero promedio
    'EMA50',           # EMA rapida
    'EMA200',          # EMA lenta (tendencia)
    'EMA_slope',       # Pendiente EMA200
    'BB_upper',       # Banda superior Bollinger
    'BB_lower',       # Banda inferior Bollinger
    'BB_width',       # Ancho de bandas
    'Returns_lag1',   # Retornos lag1
    'Returns_lag2',   # Retornos lag2
    'volume',        # Volumen
]

def calculate_indicators(df):
    """Calcula indicadores tecnicos"""
    df = df.copy()
    
    # RSI
    delta = df['close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))
    
    # RSI Slope
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
    
    # Bollinger Bands
    df['BB_upper'] = df['close'].rolling(20).mean() + 2 * df['close'].rolling(20).std()
    df['BB_lower'] = df['close'].rolling(20).mean() - 2 * df['close'].rolling(20).std()
    df['BB_width'] = df['BB_upper'] - df['BB_lower']
    
    # Returns
    df['Returns_lag1'] = df['close'].pct_change(1)
    df['Returns_lag2'] = df['close'].pct_change(2)
    
    # Volume
    df['volume'] = df['volume'] if 'volume' in df.columns else 1
    
    return df

def create_target(df, look_ahead=3):
    """
    Crea target: 1 = BUY (sube), 0 = SELL (baja)
    Target: direccion en proximas look_ahead velas
    """
    # lookahead: precio futuro > precio actual
    future_price = df['close'].shift(-look_ahead)
    df['target'] = (future_price > df['close']).astype(int)
    
    return df

def train_xgboost_model(csv_path, version='v2'):
    """Entrena modelo XGBoost"""
    
    print("=" * 60)
    print("  MOMENTUM X3 - XGBOOST MODEL TRAINING")
    print("=" * 60)
    
    # Cargar datos
    print(f"\n[1] Cargando datos: {csv_path}")
    df = pd.read_csv(csv_path)
    
    # Columnas standard
    df.columns = [c.lower() for c in df.columns]
    print(f"    Columnas: {list(df.columns)}")
    
    # Calcular indicadores
    print("\n[2] Calculando indicadores...")
    df = calculate_indicators(df)
    
    # Crear target
    print("\n[3] Creando target (lookahead 3 velas)...")
    df = create_target(df, look_ahead=3)
    
    # Features disponibles
    available_features = [f for f in FEATURES if f in df.columns]
    print(f"    Features disponibles: {len(available_features)}")
    
    # Limpiar NaNs
    df = df.dropna(subset=available_features + ['target'])
    print(f"    Records最后的: {len(df)}")
    
    # Split temporal (no random para time series)
    train_size = int(len(df) * 0.8)
    train_df = df.iloc[:train_size]
    test_df = df.iloc[train_size:]
    
    X_train = train_df[available_features]
    y_train = train_df['target']
    X_test = test_df[available_features]
    y_test = test_df['target']
    
    print(f"\n[4] Train: {len(X_train)} | Test: {len(X_test)}")
    
    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    
    # XGBoost con hyperparametros optimizados
    print("\n[5] Entrenando XGBoost...")
    
    model = xgb.XGBClassifier(
        n_estimators=200,
        max_depth=4,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_weight=3,
        gamma=0.1,
        reg_alpha=0.1,
        reg_lambda=1.0,
        objective='binary:logistic',
        eval_metric='logloss',
        use_label_encoder=False,
        random_state=42,
        n_jobs=-1
    )
    
    model.fit(
        X_train_scaled, y_train,
        eval_set=[(X_test_scaled, y_test)],
        verbose=False
    )
    
    # Predictions
    y_pred = model.predict(X_test_scaled)
    y_pred_proba = model.predict_proba(X_test_scaled)[:, 1]
    
    # Metrics
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"\n{'=' * 60}")
    print(f"  RESULTADOS")
    print(f"{'=' * 60}")
    print(f"\nTest Accuracy: {accuracy:.4f} ({accuracy*100:.2f}%)")
    print(f"\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=['SELL', 'BUY']))
    
    # Feature importance
    importance = pd.DataFrame({
        'feature': available_features,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)
    
    print(f"\nTop 10 Features:")
    for i, row in importance.head(10).iterrows():
        print(f"  {row['feature']}: {row['importance']:.4f}")
    
    # Guardar modelo
    model_path = f"/root/.openclaw/workspace/MQL5-Trading-Bot/python/xgb_model_{version}.joblib"
    scaler_path = f"/root/.openclaw/workspace/MQL5-Trading-Bot/python/scaler_{version}.pkl"
    
    joblib.dump(model, model_path)
    joblib.dump(scaler, scaler_path)
    
    print(f"\n[OK] Modelo guardado: {model_path}")
    print(f"[OK] Scaler guardado: {scaler_path}")
    
    return model, scaler, accuracy

def main():
    parser = argparse.ArgumentParser(description='Train XGBoost model for Momentum X3')
    parser.add_argument('--input', type=str, required=True, help='Input CSV file')
    parser.add_argument('--version', type=str, default='v2', help='Version name')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input):
        print(f"Error: File not found: {args.input}")
        return
    
    train_xgboost_model(args.input, args.version)

if __name__ == '__main__':
    main()