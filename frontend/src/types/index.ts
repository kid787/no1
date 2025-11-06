export interface Trade {
  id?: number;
  date: string;
  symbol: string;
  side: 'buy' | 'sell';
  entry_price: number;
  exit_price?: number;
  quantity: number;
  profit_loss?: number;
  status?: 'open' | 'closed';
  created_at?: string;
}

export interface JournalEntry {
  id?: number;
  trade_id?: number;
  entry_type: 'before' | 'during' | 'after' | 'general';
  emotion?: string;
  content: string;
  created_at?: string;
}

export interface TradeStats {
  totalTrades: number;
  totalProfit: number;
  winRate: number;
}
