#!/usr/bin/env python3
"""
GoldScalp Backtest - Multiple Strategies (pandas-based)
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from collections import defaultdict

# ===== DATA =====
def load_csv(path):
    """Load CSV manually"""
    with open(path, 'rb') as f:
        content = f.read().decode('utf-16-le').replace('\x00', '')
    
    lines = content.strip().split('\n')
    headers = [h.strip().lower() for h in lines[0].split('\t')]
    
    data = []
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.strip().split('\t')
        row = {}
        for i, h in enumerate(headers):
            if h == 'time':
                row[h] = parts[i]
            elif h in ['open', 'high', 'low', 'close', 'volume']:
                row[h] = float(parts[i])
        data.append(row)
    
    return pd.DataFrame(data)

# ===== INDICATORS =====
def ema_calc(series, period):
    return series.ewm(span=period, adjust=False).mean()

def rsi_calc(series, period=7):
    delta = series.diff()
    gain = delta.where(delta > 0, 0).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    return 100 - (100 / (1 + rs))

def bb_calc(series, period=20, devs=2):
    middle = series.rolling(period).mean()
    std = series.rolling(period).std()
    upper = middle + devs * std
    lower = middle - devs * std
    return upper, middle, lower

def run_strategy(data, strat_func, name):
    """Generic backtest runner"""
    df = data.copy()
    strat_func(df)
    
    closes = df['close'].values
    closes_next = df['close'].shift(-1).values
    
    trades = []
    position = None
    
    for i in range(50, len(df) - 1):
        signal = df.iloc[i].get('signal', None)
        direction = df.iloc[i].get('direction', None)
        
        if signal == 'buy' and not position:
            position = {'type': 'buy', 'entry': closes[i], 'sl': closes[i] - 30*0.01, 'tp': closes[i] + 60*0.01}
        elif signal == 'sell' and not position:
            position = {'type': 'sell', 'entry': closes[i], 'sl': closes[i] + 30*0.01, 'tp': closes[i] - 60*0.01}
        
        if position:
            if position['type'] == 'buy':
                if closes_next[i] <= position['sl']:
                    trades.append({'profit': -3.0}); position = None
                elif closes_next[i] >= position['tp']:
                    trades.append({'profit': 6.0}); position = None
            else:
                if closes_next[i] >= position['sl']:
                    trades.append({'profit': -3.0}); position = None
                elif closes_next[i] <= position['tp']:
                    trades.append({'profit': 6.0}); position = None
    
    wins = sum(1 for t in trades if t['profit'] > 0)
    return {'name': name, 'trades': len(trades), 'wins': wins, 'losses': len(trades)-wins, 
            'win_rate': wins/len(trades)*100 if trades else 0, 'profit': sum(t['profit'] for t in trades)}

def ema_bb_prep(df):
    """EMA cross + BB preparation"""
    df['ema9'] = ema_calc(df['close'], 9)
    df['ema21'] = ema_calc(df['close'], 21)
    df['bb_upper'], df['bb_mid'], df['bb_lower'] = bb_calc(df['close'])
    
    df['signal'] = None
    
    for i in range(1, len(df)):
        ema9 = df.iloc[i]['ema9']
        ema9_prev = df.iloc[i-1]['ema9']
        ema21 = df.iloc[i]['ema21']
        ema21_prev = df.iloc[i-1]['ema21']
        close = df.iloc[i]['close']
        bb_lower = df.iloc[i]['bb_lower']
        bb_upper = df.iloc[i]['bb_upper']
        
        # BUY
        if ema9 > ema21 and ema9_prev <= ema21_prev:
            if close <= bb_lower * 1.002:
                df.iloc[i, df.columns.get_loc('signal')] = 'buy'
        
        # SELL
        elif ema9 < ema21 and ema9_prev >= ema21_prev:
            if close >= bb_upper * 0.998:
                df.iloc[i, df.columns.get_loc('signal')] = 'sell'

def rsi_extreme_prep(df):
    """RSI Extreme - RSI < 25 BUY, RSI > 75 SELL"""
    df['rsi'] = rsi_calc(df['close'], 7)
    df['bb_upper'], df['bb_mid'], df['bb_lower'] = bb_calc(df['close'])
    
    df['signal'] = None
    
    for i in range(1, len(df)):
        rsi = df.iloc[i]['rsi']
        close = df.iloc[i]['close']
        
        if rsi < 25:
            df.iloc[i, df.columns.get_loc('signal')] = 'buy'
        elif rsi > 75:
            df.iloc[i, df.columns.get_loc('signal')] = 'sell'

def bb_bounce_prep(df):
    """BB Bounce - touches BB lower for BUY, BB upper for SELL"""
    df['bb_upper'], df['bb_mid'], df['bb_lower'] = bb_calc(df['close'])
    
    df['signal'] = None
    
    for i in range(1, len(df)):
        close = df.iloc[i]['close']
        bb_lower = df.iloc[i]['bb_lower']
        bb_upper = df.iloc[i]['bb_upper']
        
        if close <= bb_lower * 1.002:
            df.iloc[i, df.columns.get_loc('signal')] = 'buy'
        elif close >= bb_upper * 0.998:
            df.iloc[i, df.columns.get_loc('signal')] = 'sell'

def trend_only_prep(df):
    """Trend Only - EMA9 > EMA21 > EMA50 for BUY, opposite for SELL"""
    df['ema9'] = ema_calc(df['close'], 9)
    df['ema21'] = ema_calc(df['close'], 21)
    df['ema50'] = ema_calc(df['close'], 50)
    
    df['signal'] = None
    
    for i in range(1, len(df)):
        ema9 = df.iloc[i]['ema9']
        ema21 = df.iloc[i]['ema21']
        ema50 = df.iloc[i]['ema50']
        
        # Strong uptrend
        if ema9 > ema21 > ema50:
            df.iloc[i, df.columns.get_loc('signal')] = 'buy'
        # Strong downtrend
        elif ema9 < ema21 < ema50:
            df.iloc[i, df.columns.get_loc('signal')] = 'sell'

# Main
print("=" * 60)
print("GoldScalp Backtest - Multiple Strategies")
print("=" * 60)

data = load_csv('xauusd.csv' if len(sys.argv) < 2 else sys.argv[1])
print(f"Loaded: {len(data)} candles\n")

results = [
    run_strategy(data.copy(), ema_bb_prep, 'EMA+BB (Original)'),
    run_strategy(data.copy(), rsi_extreme_prep, 'RSI Extreme'),
    run_strategy(data.copy(), bb_bounce_prep, 'BB Bounce'),
    run_strategy(data.copy(), trend_only_prep, 'Trend Only'),
]

print("RESULTS BY STRATEGY")
print("-" * 60)
for r in results:
    print(f"\n{r['name']}")
    print(f"  Trades: {r['trades']} | Wins: {r['wins']} | Losses: {r['losses']}")
    print(f"  Win Rate: {r['win_rate']:.1f}% | Profit: ${r['profit']:.2f}")

# Best strategy
best = max(results, key=lambda x: x['win_rate'] if x['trades'] > 0 else -1)
print(f"\n{'=' * 60}")
print(f"BEST STRATEGY: {best['name']}")
print(f"Win Rate: {best['win_rate']:.1f}% | Profit: ${best['profit']:.2f}")
print(f"{'=' * 60}")