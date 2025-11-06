import { Router, Request, Response } from 'express';
import { JournalEntryModel } from '../models/JournalEntry';

const router = Router();

// 全ジャーナルエントリー取得
router.get('/', (req: Request, res: Response) => {
  try {
    const entries = JournalEntryModel.findAll();
    res.json(entries);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch journal entries' });
  }
});

// 特定のジャーナルエントリー取得
router.get('/:id', (req: Request, res: Response) => {
  try {
    const entry = JournalEntryModel.findById(parseInt(req.params.id));
    if (!entry) {
      return res.status(404).json({ error: 'Journal entry not found' });
    }
    res.json(entry);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch journal entry' });
  }
});

// トレードIDでジャーナルエントリー取得
router.get('/trade/:tradeId', (req: Request, res: Response) => {
  try {
    const entries = JournalEntryModel.findByTradeId(parseInt(req.params.tradeId));
    res.json(entries);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch journal entries' });
  }
});

// ジャーナルエントリー作成
router.post('/', (req: Request, res: Response) => {
  try {
    const id = JournalEntryModel.create(req.body);
    res.status(201).json({ id, message: 'Journal entry created successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create journal entry' });
  }
});

// ジャーナルエントリー更新
router.put('/:id', (req: Request, res: Response) => {
  try {
    JournalEntryModel.update(parseInt(req.params.id), req.body);
    res.json({ message: 'Journal entry updated successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update journal entry' });
  }
});

// ジャーナルエントリー削除
router.delete('/:id', (req: Request, res: Response) => {
  try {
    JournalEntryModel.delete(parseInt(req.params.id));
    res.json({ message: 'Journal entry deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete journal entry' });
  }
});

export default router;
