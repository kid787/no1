import db from '../database/db';

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

export class TradeModel {
  static create(trade: Trade) {
    const stmt = db.prepare(`
      INSERT INTO trades (date, symbol, side, entry_price, exit_price, quantity, profit_loss, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const result = stmt.run(
      trade.date,
      trade.symbol,
      trade.side,
      trade.entry_price,
      trade.exit_price || null,
      trade.quantity,
      trade.profit_loss || null,
      trade.status || 'open'
    );

    return result.lastInsertRowid;
  }

  static findAll() {
    const stmt = db.prepare('SELECT * FROM trades ORDER BY date DESC, created_at DESC');
    return stmt.all();
  }

  static findById(id: number) {
    const stmt = db.prepare('SELECT * FROM trades WHERE id = ?');
    return stmt.get(id);
  }

  static update(id: number, trade: Partial<Trade>) {
    const fields = [];
    const values = [];

    if (trade.date !== undefined) {
      fields.push('date = ?');
      values.push(trade.date);
    }
    if (trade.symbol !== undefined) {
      fields.push('symbol = ?');
      values.push(trade.symbol);
    }
    if (trade.side !== undefined) {
      fields.push('side = ?');
      values.push(trade.side);
    }
    if (trade.entry_price !== undefined) {
      fields.push('entry_price = ?');
      values.push(trade.entry_price);
    }
    if (trade.exit_price !== undefined) {
      fields.push('exit_price = ?');
      values.push(trade.exit_price);
    }
    if (trade.quantity !== undefined) {
      fields.push('quantity = ?');
      values.push(trade.quantity);
    }
    if (trade.profit_loss !== undefined) {
      fields.push('profit_loss = ?');
      values.push(trade.profit_loss);
    }
    if (trade.status !== undefined) {
      fields.push('status = ?');
      values.push(trade.status);
    }

    values.push(id);

    const stmt = db.prepare(`UPDATE trades SET ${fields.join(', ')} WHERE id = ?`);
    return stmt.run(...values);
  }

  static delete(id: number) {
    const stmt = db.prepare('DELETE FROM trades WHERE id = ?');
    return stmt.run(id);
  }

  static getStats() {
    const totalTrades = db.prepare('SELECT COUNT(*) as count FROM trades').get() as { count: number };
    const totalProfit = db.prepare('SELECT SUM(profit_loss) as total FROM trades WHERE profit_loss IS NOT NULL').get() as { total: number | null };
    const winRate = db.prepare(`
      SELECT
        COUNT(CASE WHEN profit_loss > 0 THEN 1 END) * 100.0 / COUNT(*) as rate
      FROM trades
      WHERE profit_loss IS NOT NULL
    `).get() as { rate: number | null };

    return {
      totalTrades: totalTrades.count,
      totalProfit: totalProfit.total || 0,
      winRate: winRate.rate || 0
    };
  }
}
