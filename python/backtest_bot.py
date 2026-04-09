#!/usr/bin/env python3
"""
GoldScalp Backtest Engine
=========================
Automatiza testing de estrategias para XAUUSD M1
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from collections import defaultdict

# ===== DATA =====
def load_data(csv_path):
    """Carga datos OHLCV"""
    df = pd.read_csv(csv_path)
    df.columns = [c.lower() for c in df.columns]
    df['time'] = pd.to_datetime(df['time'])
    df = df.sort_values('time').reset_index(drop=True)
    return df

# ===== INDICATORS =====
def ema(series, period):
    return series.ewm(span=period, adjust=False).mean()

def rsi(series, period=14):
    delta = series.diff()
    gain = delta.where(delta > 0, 0).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    return 100 - (100 / (1 + rs))

def macd(series, fast=12, slow=26, sig=9):
    ema_fast = ema(series, fast)
    ema_slow = ema(series, slow)
    macd_line = ema_fast - ema_slow
    signal = ema(macd_line, sig)
    hist = macd_line - signal
    return macd_line, signal, hist

def bollinger(series, period=20, devs=2):
    middle = series.rolling(period).mean()
    std = series.rolling(period).std()
    upper = middle + devs * std
    lower = middle - devs * std
    return upper, middle, lower

defatr(high, low, period=14):
    return (high - low).rolling(period).mean()

# ===== STRATEGIES =====
class Strategy:
    def __init__(self, name, params):
        self.name = name
        self.params = params
        self.trades = []
        
    def check(self, df, i):
        raise NotImplementedError
        
    def run(self, df):
        """Ejecuta backtest"""
        self.trades = []
        self.equity = 100.0
        self.balance = 100.0
        self.position = None
        
        for i in range(50, len(df) - 1):
            if self.check(df, i):
                pass  # Override in subclass
        return self.get_results()
        
    def get_results(self):
        wins = sum(1 for t in self.trades if t['profit'] > 0)
        losses = sum(1 for t in self.trades if t['profit'] <= 0)
        total = len(self.trades)
        
        if total == 0:
            return {'trades': 0, 'win_rate': 0, 'profit': 0}
            
        win_rate = (wins / total) * 100 if total > 0 else 0
        profit = sum(t['profit'] for t in self.trades)
        
        return {
            'trades': total,
            'wins': wins,
            'losses': losses,
            'win_rate': win_rate,
            'profit': profit,
            'avg_win': sum(t['profit'] for t in self.trades if t['profit'] > 0) / wins if wins > 0 else 0,
            'avg_loss': sum(t['profit'] for t in self.trades if t['profit'] < 0) / losses if losses > 0 else 0,
        }

# ===== STRATEGY 1: RSI + MACD Crossover =====
class RSIMACD_Strategy(Strategy):
    def __init__(self):
        super().__init__('RSI_MACD', {'rsi_buy': 25, 'rsi_sell': 75})
        
    def check(self, df, i):
        rsi_val = df.iloc[i]['rsi']
        macd = df.iloc[i]['macd']
        macd_prev = df.iloc[i-1]['macd']
        macd_sig = df.iloc[i]['macd_sig']
        macd_sig_prev = df.iloc[i-1]['macd_sig']
        
        # BUY
        if rsi_val <= self.params['rsi_buy']:
            if macd > macd_sig and macd_prev <= macd_sig_prev:
                self.enter('buy', df.iloc[i])
                
        # SELL
        elif rsi_val >= self.params['rsi_sell']:
            if macd < macd_sig and macd_prev >= macd_sig_prev:
                self.enter('sell', df.iloc[i])
                
    def enter(self, direction, bar):
        if self.position:
            return
            
        sl_pips = 50
        tp_pips = 100
        point = 0.01  # XAUUSD pip value
        
        if direction == 'buy':
            sl = bar['close'] - sl_pips * point
            tp = bar['close'] + tp_pips * point
        else:
            sl = bar['close'] + sl_pips * point
            tp = bar['close'] - tp_pips * point
            
        self.position = {
            'direction': direction,
            'entry': bar['close'],
            'sl': sl,
            'tp': tp,
            'entry_time': bar['time']
        }
        
    def run(self, df):
        # Calculate indicators
        df['rsi'] = rsi(df['close'], 7)
        df['macd'], df['macd_sig'], df['macd_hist'] = macd(df['close'])
        
        return super().run(df)

# ===== STRATEGY 2: EMA Cross + BB =====
class EMABB_Strategy(Strategy):
    def __init__(self):
        super().__init__('EMA_BB', {'ema_fast': 9, 'ema_slow': 21})
        
    def check(self, df, i):
        ema_fast = df.iloc[i]['ema_fast']
        ema_fast_prev = df.iloc[i-1]['ema_fast']
        ema_slow = df.iloc[i]['ema_slow']
        ema_slow_prev = df.iloc[i-1]['ema_slow']
        bb_lower = df.iloc[i]['bb_lower']
        bb_upper = df.iloc[i]['bb_upper']
        close = df.iloc[i]['close']
        
        # BUY: EMA cross up + at BB lower
        if ema_fast > ema_slow and ema_fast_prev <= ema_slow_prev:
            if close <= bb_lower * 1.002:
                self.enter('buy', df.iloc[i])
                
        # SELL: EMA cross down + at BB upper
        elif ema_fast < ema_slow and ema_fast_prev >= ema_slow_prev:
            if close >= bb_upper * 0.998:
                self.enter('sell', df.iloc[i])
                
    def enter(self, direction, bar):
        if self.position:
            return
            
        sl_pips = 30
        tp_pips = 60
        point = 0.01
        
        if direction == 'buy':
            sl = bar['close'] - sl_pips * point
            tp = bar['close'] + tp_pips * point
        else:
            sl = bar['close'] + sl_pips * point
            tp = bar['close'] - tp_pips * point
            
        self.position = {
            'direction': direction,
            'entry': bar['close'],
            'sl': sl,
            'tp': tp,
            'entry_time': bar['time']
        }
        
    def run(self, df):
        df['ema_fast'] = ema(df['close'], 9)
        df['ema_slow'] = ema(df['close'], 21)
        df['bb_upper'], df['bb_middle'], df['bb_lower'] = bollinger(df['close'])
        
        return super().run(df)

# ===== STRATEGY 3: Bollinger Bounce =====
class BBBounce_Strategy(Strategy):
    def __init__(self):
        super().__init__('BB_Bounce', {})
        
    def check(self, df, i):
        close = df.iloc[i]['close']
        bb_upper = df.iloc[i]['bb_upper']
        bb_lower = df.iloc[i]['bb_lower']
        bb_lower_prev = df.iloc[i-1]['bb_lower']
        
        # BUY at lower band
        if close <= bb_lower:
            if bb_lower > bb_lower_prev:  # Lower band rising
                self.enter('buy', df.iloc[i])
                
        # SELL at upper band
        elif close >= bb_upper:
            bb_upper_prev = df.iloc[i-1]['bb_upper']
            if bb_upper < bb_upper_prev:  # Upper band falling
                self.enter('sell', df.iloc[i])
                
    def enter(self, direction, bar):
        if self.position:
            return
            
        sl_pips = 25
        tp_pips = 50
        point = 0.01
        
        if direction == 'buy':
            sl = bar['close'] - sl_pips * point
            tp = bar['close'] + tp_pips * point
        else:
            sl = bar['close'] + sl_pips * point
            tp = bar['close'] - tp_pips * point
            
        self.position = {
            'direction': direction,
            'entry': bar['close'],
            'sl': sl,
            'tp': tp,
            'entry_time': bar['time']
        }
        
    def run(self, df):
        df['bb_upper'], df['bb_middle'], df['bb_lower'] = bollinger(df['close'])
        
        return super().run(df)

# ===== MAIN =====
def main():
    import sys
    
    csv_path = sys.argv[1] if len(sys.argv) > 1 else 'xauusd.csv'
    
    print("=" * 60)
    print("  GOLDSCALP BACKTEST ENGINE")
    print("=" * 60)
    
    # Load data
    print(f"\n[1] Cargando datos: {csv_path}")
    df = load_data(csv_path)
    print(f"    rows: {len(df)}")
    print(f"    {df['time'].iloc[0]} a {df['time'].iloc[-1]}")
    
    # Run strategies
    strategies = [
        RSIMACD_Strategy(),
        EMABB_Strategy(),
        BBBounce_Strategy(),
    ]
    
    print(f"\n[2] Ejecutando {len(strategies)} estrategias...")
    
    results = []
    for strat in strategies:
        res = strat.run(df)
        res['name'] = strat.name
        results.append(res)
        
        print(f"\n{strat.name}:")
        print(f"  Trades: {res['trades']} | WR: {res['win_rate']:.1f}% | Profit: ${res['profit']:.2f}")
    
    # Best strategy
    print(f"\n{'=' * 60}")
    print("  MEJOR ESTRATEGIA")
    print(f"{'=' * 60}")
    
    best = max(results, key=lambda x: (x['win_rate'], x['profit']))
    print(f"\n  {best['name']}")
    print(f"  WR: {best['win_rate']:.1f}%")
    print(f"  Profit: ${best['profit']:.2f}")
    print(f"  Trades: {best['trades']}")

if __name__ == '__main__':
    main()