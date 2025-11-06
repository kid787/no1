import db from '../database/db';

export interface JournalEntry {
  id?: number;
  trade_id?: number;
  entry_type: 'before' | 'during' | 'after' | 'general';
  emotion?: string;
  content: string;
  created_at?: string;
}

export class JournalEntryModel {
  static create(entry: JournalEntry) {
    const stmt = db.prepare(`
      INSERT INTO journal_entries (trade_id, entry_type, emotion, content)
      VALUES (?, ?, ?, ?)
    `);

    const result = stmt.run(
      entry.trade_id || null,
      entry.entry_type,
      entry.emotion || null,
      entry.content
    );

    return result.lastInsertRowid;
  }

  static findAll() {
    const stmt = db.prepare('SELECT * FROM journal_entries ORDER BY created_at DESC');
    return stmt.all();
  }

  static findById(id: number) {
    const stmt = db.prepare('SELECT * FROM journal_entries WHERE id = ?');
    return stmt.get(id);
  }

  static findByTradeId(tradeId: number) {
    const stmt = db.prepare('SELECT * FROM journal_entries WHERE trade_id = ? ORDER BY created_at ASC');
    return stmt.all(tradeId);
  }

  static update(id: number, entry: Partial<JournalEntry>) {
    const fields = [];
    const values = [];

    if (entry.trade_id !== undefined) {
      fields.push('trade_id = ?');
      values.push(entry.trade_id);
    }
    if (entry.entry_type !== undefined) {
      fields.push('entry_type = ?');
      values.push(entry.entry_type);
    }
    if (entry.emotion !== undefined) {
      fields.push('emotion = ?');
      values.push(entry.emotion);
    }
    if (entry.content !== undefined) {
      fields.push('content = ?');
      values.push(entry.content);
    }

    values.push(id);

    const stmt = db.prepare(`UPDATE journal_entries SET ${fields.join(', ')} WHERE id = ?`);
    return stmt.run(...values);
  }

  static delete(id: number) {
    const stmt = db.prepare('DELETE FROM journal_entries WHERE id = ?');
    return stmt.run(id);
  }
}
