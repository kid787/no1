import express from 'express';
import cors from 'cors';
import tradesRouter from './routes/trades';
import journalRouter from './routes/journal';
import './database/db'; // データベース初期化

const app = express();
const PORT = process.env.PORT || 3001;

// ミドルウェア
app.use(cors());
app.use(express.json());

// ルート
app.use('/api/trades', tradesRouter);
app.use('/api/journal', journalRouter);

// ヘルスチェック
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});
