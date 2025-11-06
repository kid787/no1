import { Router, Request, Response } from 'express';
import { TradeModel } from '../models/Trade';

const router = Router();

// 全トレード取得
router.get('/', (req: Request, res: Response) => {
  try {
    const trades = TradeModel.findAll();
    res.json(trades);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch trades' });
  }
});

// トレード統計取得
router.get('/stats', (req: Request, res: Response) => {
  try {
    const stats = TradeModel.getStats();
    res.json(stats);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// 特定のトレード取得
router.get('/:id', (req: Request, res: Response) => {
  try {
    const trade = TradeModel.findById(parseInt(req.params.id));
    if (!trade) {
      return res.status(404).json({ error: 'Trade not found' });
    }
    res.json(trade);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch trade' });
  }
});

// トレード作成
router.post('/', (req: Request, res: Response) => {
  try {
    const id = TradeModel.create(req.body);
    res.status(201).json({ id, message: 'Trade created successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create trade' });
  }
});

// トレード更新
router.put('/:id', (req: Request, res: Response) => {
  try {
    TradeModel.update(parseInt(req.params.id), req.body);
    res.json({ message: 'Trade updated successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update trade' });
  }
});

// トレード削除
router.delete('/:id', (req: Request, res: Response) => {
  try {
    TradeModel.delete(parseInt(req.params.id));
    res.json({ message: 'Trade deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete trade' });
  }
});

export default router;
